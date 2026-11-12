local ADDON, ns = ...

ns.name = ADDON
ns.title = "Forever QoL Panel"
ns.VERSION = "0.2.0"   -- the setup wizard shows the pages of features newer than the last version seen
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"

function ns.Tex(name)
    return ns.MEDIA .. name .. ".tga"
end

-- Secret values: Forever hides some values from addons (aura tooltips, combat data). They can be passed on, but
-- comparing or reading them throws, so every value read from a tooltip is checked first.
function ns.Secret(v)
    return issecretvalue ~= nil and v ~= nil and issecretvalue(v) or false
end

-- API across client generations: Forever has the modern C_Item / C_Spell namespaces, the old globals are gone.
function ns.ItemInfo(item)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    if GetItemInfo then return GetItemInfo(item) end
end

function ns.ItemCount(item, bank)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(item, bank) or 0 end
    return GetItemCount and GetItemCount(item, bank) or 0
end

function ns.ItemIcon(item)
    if C_Item and C_Item.GetItemIconByID then
        local icon = C_Item.GetItemIconByID(item)
        if icon then return icon end
    end
    if GetItemIcon then return GetItemIcon(item) end
    return select(10, ns.ItemInfo(item))
end

function ns.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

function ns.SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellInfo and select(3, GetSpellInfo(id))
end

ns.defaults = {
    panel = {
        enabled = true,
        xpbar = true,            -- our XP bar replaces Blizzard's
        skin = "classic",        -- classic (Forever's bronze frame), modern (flat, thin border)
        corners = "square",      -- modern skin: square, round
        border = 2,              -- border width: 1 thin, 2 normal, 3 thick
        position = "top",        -- top, bottom (mirrored)
        style = "edge",          -- "edge": XP bar hangs from the panel's line, "rail": own bar below
        gap = 12,                -- "rail": space between the panel's line and the bar
        rim = "bronze",          -- bronze, silver, dark
        separator = "line",      -- line, dot, none
        iconBorder = "round",    -- round, square, none
        animations = true,
        logPreview = false,      -- XP of every quest in the log (pale blue)
        questPreview = true,     -- XP of finished quests (gold)
        questStyle = "veil",     -- veil, frame, line, glow, shimmer, stripes
        readyPulse = false,      -- the preview pulses when it is enough for the next level
        pad = 9,                 -- left/right padding of every element
        barWidth = 760,          -- XP bar width, never wider than the panel's straight line
        ticks = 10,              -- XP bar tick marks every 5, 10, 20 or 25 %, 0 = none
        delay = 3,               -- seconds until the panel folds up
        pinned = false,
        hideBlizzardXP = true,
        collectButtons = true,   -- minimap buttons of other addons go into the panel's addon menu
        order = { "hearth", "gold", "session", "bags", "materials", "ammo", "durability", "honor", "pvp", "favor", "zone",
            "coords", "xph", "clock", "stopwatch", "latency", "fps", "addons" },
        items = {
            hearth = true, gold = true, session = true, bags = true, materials = false, ammo = false, durability = true,
            honor = false, pvp = false, favor = false, zone = true, coords = false, xph = true, clock = true, stopwatch = false,
            latency = true, fps = false, addons = true,
        },
        opt = {
            xphTime = false,     -- XP/h also shows the time to the next level
            zoneCoords = false,  -- zone also shows the coordinates
            minimapClock = true, -- Blizzard's clock at the minimap stays
            serverTime = false,  -- the clock shows the realm time
        },
    },
    minimap = { show = true, angle = 205, keep = {}, floating = true },   -- floating: collector button without panel
    actionbar = { enabled = true, placeNew = true, replaceRanks = true, general = false, messages = true, seen = {} },
    gameplay = { enabled = true, questAccept = true, questTurnIn = true, gossip = true, rewardValue = true, sellGrey = true,
        repair = true, guildRepair = true, fastLoot = true, lootText = true,
        lootShape = "panel", lootScale = 1 },   -- lootPos: own place of the loot text
    nameplates = { enabled = true, position = "left", progress = true, size = 20, x = 0, y = 0 },
    warnings = { enabled = true, classBuffs = true, food = true, weapon = true, expiring = true, sound = false,
        combat = false, scale = 1, foodWhere = "instance", flask = true, flaskWhere = "raid",
        iconShape = "panel", anim = "pulse", animRepeat = "once",
        hideWithWindows = true },   -- pos / link: placement of the two groups
    tooltip = { enabled = true, sellValue = true, counts = true, gather = true },
    items = {},     -- [realm]["Faction:Name"] = { class, bags = { [itemID] = count }, bank = { ... } }
    session = {},   -- [name-realm] = gold and XP of the running session, kept over /reload
    language = "auto",
    motion = "full",    -- animations: full, reduced (warnings animate once) or off
    gold = {},   -- [realm][faction][name] = { money, class }
}

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            -- lists (like the order) are only copied when missing
            if #v == 0 then copyDefaults(v, dst[k]) elseif #dst[k] == 0 then for i, x in ipairs(v) do dst[k][i] = x end end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Small event bus: modules register with ns.On(event, fn); ns.OnLogin(fn) runs once the DB exists.
local handlers, loginHooks = {}, {}
local bus = CreateFrame("Frame")
bus:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- events differ between client generations; an unknown one is simply never fired
        pcall(bus.RegisterEvent, bus, event)
    end
    table.insert(handlers[event], fn)
end

function ns.OnLogin(fn)
    table.insert(loginHooks, fn)
end

-- Atlases: the first name the client knows wins (Forever renames its "-c60" art now and then). What was
-- picked is noted in the debug data.
ns.atlasUsed = {}
function ns.ResolveAtlas(key, names)
    for _, name in ipairs(names) do
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
        if info and (info.file or info.filename) then
            ns.atlasUsed[key] = name
            return name, info
        end
    end
    ns.atlasUsed[key] = "missing: " .. table.concat(names, ", ")
end

function ns.SetAtlas(tex, key, names)
    local name = ns.ResolveAtlas(key, names)
    if name then tex:SetAtlas(name) end
    return name
end

-- The running session of this character (gold, XP). It survives /reload and starts anew on a real login.
function ns.ResetSession(s)
    s.startMoney, s.income, s.spent = GetMoney(), 0, 0
    s.xp, s.levelXP, s.levelStart = 0, 0, time()
end

function ns.Session()
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    local s = ns.db.session[key]
    if not s or not s.startMoney then
        s = {}
        ns.db.session[key] = s
        ns.ResetSession(s)
    end
    return s
end

ns.On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
    if isInitialLogin and ns.db then
        ns.ResetSession(ns.Session())
        if ns.Elements and ns.Elements.UpdateTexts and ns.Elements.band then ns.Elements:UpdateTexts() end
    end
end)

-- Tooltips open away from the screen edge the panel sits on.
function ns.TipPoint()
    if ns.db and ns.db.panel.position == "bottom" then return "ANCHOR_TOP", 0, 6 end
    return "ANCHOR_BOTTOM", 0, -6
end

-- Re-applies everything that depends on settings.
function ns.Motion() return ns.db.motion or "full" end

-- Icon look shared by panel-like displays (warnings, loot text): r needs r.icon and r.ring (textures on frame r).
-- shape: "panel" (follow the panel's icon border), "round", "square" or "none".
function ns.StyleIcon(r, tex, shape, size)
    if shape == nil or shape == "panel" then shape = ns.db.panel.iconBorder end
    r.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if r.masked then r.icon:RemoveMaskTexture(r.mask); r.masked = false end
    r.ring:Hide()
    local ring
    if shape == "round" then
        if not r.mask then
            r.mask = r:CreateMaskTexture()
            r.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            r.mask:SetAllPoints(r.icon)
        end
        r.icon:AddMaskTexture(r.mask)
        r.masked = true
        if ns.SetAtlas(r.ring, "ring", { "voicechat-portrait-ring", "worldquest-tracker-ring" }) then ring = size * 1.25 end
    elseif shape == "square" then
        if ns.SetAtlas(r.ring, "frame", { "ui-hud-actionbar-iconframe", "ui-hud-actionbar-iconframe-c60" }) then ring = size * 1.2 end
    end
    if ring then
        r.ring:ClearAllPoints()
        r.ring:SetPoint("CENTER", r.icon, "CENTER")
        r.ring:SetSize(ring, ring)
        r.ring:Show()
    end
end

function ns.Refresh()
    ns.db.panel.animations = ns.Motion() ~= "off"
    if ns.Dock then ns.Dock:Refresh() end
    if ns.Elements and ns.Elements.pin then ns.Elements:UpdatePin() end
    if ns.Minimap then ns.Minimap:Update() end
    if ns.Elements and ns.Elements.ApplyMinimapClock then ns.Elements:ApplyMinimapClock() end
    if ns.Warnings and ns.Warnings.ApplyLook then ns.Warnings:ApplyLook() end
    if ns.Gameplay and ns.Gameplay.ApplyLootLook then ns.Gameplay:ApplyLootLook() end
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    ForeverQoLPanelDB = ForeverQoLPanelDB or {}
    local db = ForeverQoLPanelDB
    -- 0.1: the quest preview had a single colour
    if db.panel and db.panel.questColor then db.panel.questColor = nil end
    -- 0.2: the animation switch became a level
    if db.motion == nil and db.panel and db.panel.animations == false then db.motion = "off" end
    -- 0.2: food and flask got their own switches and places
    if db.warnings and db.warnings.foodAnywhere ~= nil then
        if db.warnings.foodAnywhere then db.warnings.foodWhere = "world" end
        db.warnings.foodAnywhere = nil
    end
    copyDefaults(ns.defaults, db)
    ns.db = db
    -- 2: Forever's colour scheme, the preview of all quests is off by default
    db.version = db.version or 1
    if db.version < 2 then db.panel.logPreview = false end
    -- 3: calm, static look for finished quests
    if db.version < 3 and db.panel.questStyle == "shimmer" then db.panel.questStyle = "veil" end
    db.version = 3
    -- elements added in a later version join the saved order next to their default neighbour
    local order, defaults = db.panel.order, ns.defaults.panel.order
    for i, key in ipairs(defaults) do
        if not tContains(order, key) then
            local at = #order + 1
            for j, k in ipairs(order) do if k == defaults[i - 1] then at = j + 1 break end end
            table.insert(order, at, key)
        end
    end
    ns.SetLanguage(db.language)
end)

ns.On("PLAYER_LOGIN", function()
    for _, fn in ipairs(loginHooks) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end)

-- /fqp ---------------------------------------------------------------------------

local function setting(key, value, list)
    if list and not tContains(list, value) then
        print("|cffffd100" .. ns.title .. ":|r " .. key .. " = " .. table.concat(list, " | "))
        return
    end
    ns.db.panel[key] = value
    ns.Refresh()
end

SLASH_FOREVERQOLPANEL1 = "/fqp"
SlashCmdList.FOREVERQOLPANEL = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""), 2)
    cmd = (cmd or ""):lower()
    local num = tonumber(arg)
    if cmd == "pin" then setting("pinned", not ns.db.panel.pinned)
    elseif cmd == "setup" then ns.Wizard:Open(true)
    elseif cmd == "ranks" then ns.ActionBar:UpdateRanks()
    elseif cmd == "place" then ns.ActionBar:PlaceMissing()
    elseif cmd == "position" then setting("position", arg, { "top", "bottom" })
    elseif cmd == "style" then setting("style", arg, { "edge", "rail" })
    elseif cmd == "rim" then setting("rim", arg, { "bronze", "silver", "dark" })
    elseif cmd == "sep" then setting("separator", arg, { "line", "dot", "none" })
    elseif cmd == "border" then setting("iconBorder", arg, { "round", "square", "none" })
    elseif cmd == "ticks" and (num == 0 or num == 5 or num == 10 or num == 20 or num == 25) then setting("ticks", num)
    elseif cmd == "pad" and num then setting("pad", math.max(2, math.min(20, num)))
    elseif cmd == "gap" and num then setting("gap", math.max(4, math.min(40, num)))
    elseif cmd == "width" and num then setting("barWidth", math.max(200, math.min(2000, num)))
    elseif cmd == "delay" and num then setting("delay", math.max(0.5, math.min(30, num)))
    elseif cmd == "toggle" and arg and ns.db.panel.items[arg] ~= nil then
        ns.db.panel.items[arg] = not ns.db.panel.items[arg]
        ns.Refresh()
    elseif cmd == "" or cmd == "options" then
        if ns.Options then ns.Options:Open() end
    elseif cmd == "reset" then
        ns.db.panel = nil
        copyDefaults(ns.defaults, ns.db)
        ns.Refresh()
    else
        print("|cffffd100" .. ns.title .. "|r: " .. ns.L.SLASH_HELP)
        print("  /fqp setup | ranks | place | pin | position top|bottom | style edge|rail | gap <px> | rim bronze|silver|dark | sep line|dot|none |"
            .. " border round|square|none | ticks 0|5|10|20|25 | pad <px> | width <px> | delay <s> | toggle <element> | reset")
    end
end

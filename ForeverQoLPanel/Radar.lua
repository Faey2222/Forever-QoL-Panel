local _, ns = ...

-- Enemy radar: enemy players nearby, the way Spy does it on Forever. The combat log is closed to addons there, so
-- enemies are seen through unit tokens: nameplates, target, focus, mouseover (looked at when they appear and every
-- second while they stay) and the spells they cast (stealth). Values the client keeps secret are skipped.
-- A new enemy plays a sound; one going into stealth plays another and shows a warning in the middle of the screen.
-- The panel element (Elements.lua) shows the count and opens a list below it: class icon, name in class colour, level.
local R = {}
ns.Radar = R

local STEALTH = {   -- spells that make a player stealthed
    [1784] = true, [1785] = true, [1786] = true, [1787] = true,   -- Stealth
    [5215] = true, [6783] = true, [9913] = true,                  -- Prowl
    [1856] = true, [1857] = true,                                  -- Vanish
    [20580] = true,                                                -- Shadowmeld
}
local SCAN = 1
local ROW_H = 18

local function db() return ns.db.radar end
local function readable(v) if v == nil or ns.Secret(v) then return nil end return v end

R.list = {}     -- name -> { name, class, level, first, last, stealth, test }

-- in a battleground or arena: "off", "stealth" (only enemies going into stealth) or "all"; nil outside
function R:PvPMode()
    local ok, inside, kind = pcall(IsInInstance)
    if not ok or not readable(inside) then return nil end
    kind = readable(kind)
    if kind ~= "pvp" and kind ~= "arena" then return nil end
    return db().bgMode or "stealth"
end

function R:On()
    local d = db()
    if not d.enabled then return false end
    if d.quietResting and IsResting and readable(IsResting()) then return false end
    if self:PvPMode() == "off" then return false end
    return true
end

-- the enemy behind a unit token, or nil
local function enemyOf(unit)
    if not (UnitExists and readable(UnitExists(unit))) then return nil end
    -- a target or focus stays set when the player is long gone: only one in sight counts
    if UnitIsVisible and readable(UnitIsVisible(unit)) == false then return nil end
    if not readable(UnitIsPlayer(unit)) then return nil end
    local enemy = readable(UnitIsEnemy and UnitIsEnemy("player", unit))
    if enemy == nil then enemy = readable(UnitCanAttack and UnitCanAttack("player", unit)) end
    if not enemy then return nil end
    local name, suffix = UnitName(unit)
    name, suffix = readable(name), readable(suffix)
    if type(name) ~= "string" or name == "" then return nil end
    local _, class = UnitClass(unit)
    -- the full name as Spy writes it ("First-Last" on Forever, where the second name sits in the realm's place)
    local full = type(suffix) == "string" and suffix ~= "" and (name .. "-" .. suffix) or name
    return name, readable(class), readable(UnitLevel(unit)), full
end

-- a name from another addon ("First-Last", "Name-Realm"): the first part, as our list keys it
local function baseName(n) return type(n) == "string" and n:match("^([^%-]+)") or n end

-- an enemy seen: kept fresh, new ones announced
-- quiet: no "new enemy" sound (a more important warning for the same enemy comes with it: stealth, targets you)
function R:Seen(name, class, level, stealth, test, quiet)
    local now = GetTime()
    local e = self.list[name]
    local new = not e
    if new then
        e = { name = name, first = now }
        self.list[name] = e
    end
    e.last = now
    e.class = class or e.class
    -- the level: read from the unit (and kept for this name), else the one known from an earlier meeting; a "skull"
    -- (-1: 10 or more above you, the game does not tell) means at least your level + 10
    if level and level > 0 then
        e.level, e.levelMin = level, nil
        if not test then db().levels = db().levels or {}; db().levels[name] = level end
    elseif not e.level then
        local known = db().levels and db().levels[name]
        if known then e.level = known
        elseif level == -1 or level == 0 then
            local me = UnitLevel("player") or 1
            e.levelMin = math.min(me + 10, MAX_PLAYER_LEVEL or 60)
        end
    end
    e.test = test
    if stealth then
        local fresh = not e.stealth or now - (e.stealthAt or 0) > 10
        e.stealth, e.stealthAt = true, now
        if fresh then self:StealthAlert(e) end
    elseif new and not quiet then
        self:NewAlert(e)
    end
    -- a new enemy opens the list again after it was closed by a click
    if new then self.dismissed = false end
    self:Changed()
end

function R:NewAlert(e)
    local d = db()
    -- not more than one sound every few seconds, however many come at once
    local now = GetTime()
    if d.sound and d.sound ~= "none" and now - (self.lastSound or 0) > 3 then
        self.lastSound = now
        ns.Warnings.PlaySound(d.sound)
    end
end

function R:StealthAlert(e)
    local d = db()
    if d.stealthSound and d.stealthSound ~= "none" then ns.Warnings.PlaySound(d.stealthSound) end
    if d.stealthWarning then self:ShowStealth(e) end
end

-- the level as shown: "27", "36+" (at least, a skull), "??"; and the colour for it
function R.LevelText(e)
    if e.level and e.level > 0 then return tostring(e.level), e.level end
    if e.levelMin then return e.levelMin .. "+", e.levelMin end
    return "??", nil
end

function R.LevelColor(lvl)
    local c = lvl and GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
    if c then return c.r, c.g, c.b end
    return 1, 0.13, 0.13
end

-- the list sorted: stealthed first, then the most recently seen
function R:Sorted()
    local out = {}
    for _, e in pairs(self.list) do out[#out + 1] = e end
    table.sort(out, function(a, b)
        if (a.stealth and 1 or 0) ~= (b.stealth and 1 or 0) then return a.stealth end
        if (a.targetsMe and 1 or 0) ~= (b.targetsMe and 1 or 0) then return a.targetsMe end
        if a.first ~= b.first then return a.first > b.first end
        return a.name < b.name
    end)
    return out
end

function R:Count()
    local n = 0
    for _ in pairs(self.list) do n = n + 1 end
    return n
end

-- enemies not seen for a while leave the list
function R:Expire()
    local now, gone = GetTime(), false
    -- what keeps each enemy in the list, for the debug data
    local why = {}
    for name, e in pairs(self.list) do why[name] = { src = tostring(e.src), ago = math.floor(now - (e.last or 0)) } end
    ns.Debug.Set("radarList", why)
    local keep = db().timeout or 60
    for name, e in pairs(self.list) do
        if now - (e.last or 0) > (e.test and 15 or keep) then self.list[name] = nil; gone = true
        elseif e.targetsMe and now - (e.tmSeen or 0) > 10 then e.targetsMe = nil; gone = true end
    end
    if gone then self:Changed() end
end

function R:Scan(unit)
    if not self:On() then return end
    -- battlegrounds full of enemies: only the stealthed ones (seen by their spells) count there
    if self:PvPMode() == "stealth" then return end
    local name, class, level, full = enemyOf(unit)
    if not name then return end
    local known = self.list[name]
    -- an enemy that has you as its target: only that warning's sound, not the "new enemy" one as well
    local aims = db().targetMe and UnitIsUnit and readable(UnitIsUnit(unit .. "target", "player"))
    self:Seen(name, class, level, nil, nil, aims)
    local e = self.list[name]
    e.full = full
    e.src = unit   -- what saw it last (debug data)
    -- a new sighting goes to the group and guild, if sharing is on
    if not known then self:Share(e) end
    if aims then self:TargetsMe(e) end
end

-- an enemy targeting you: its own sound and warning (again after 15 seconds at the earliest), marked in the list
function R:TargetsMe(e)
    local d = db()
    if not (e and d.targetMe) then return end
    local now = GetTime()
    local fresh = now - (e.tmAt or 0) > 15
    e.targetsMe, e.tmSeen = true, now
    if not e.tmAt or fresh then
        e.tmAt = now
        if d.targetSound and d.targetSound ~= "none" then ns.Warnings.PlaySound(d.targetSound) end
        if d.targetWarning then self:ShowAlert(e, "target") end
        self:Share(e, "t")
    end
    self:Changed()
end

function R:ScanAll()
    self:Expire()
    if not self:On() then return end
    for _, u in ipairs({ "target", "focus", "mouseover" }) do self:Scan(u) end
    for u in pairs(self.plates) do self:Scan(u) end
end
R.plates = {}

function R:Cast(unit, spellID)
    if not self:On() then return end
    spellID = readable(spellID)
    if not (spellID and STEALTH[spellID]) then return end
    local name, class, level, full = enemyOf(unit)
    if name then
        self:Seen(name, class, level, true)
        local e = self.list[name]
        e.full = full
        self:Share(e, "s")
    end
end

-- something changed: the panel element and the list follow
function R:Changed()
    if ns.Elements and ns.Elements.UpdateTexts then ns.Elements:UpdateTexts() end
    self:UpdateList()
end

-- The list below the element ------------------------------------------------------------

local function classIcon(tex, class)
    local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if c then
        tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

function R:ListFrame()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "ForeverQoLPanelRadarList", UIParent, "BackdropTemplate")
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(60)
    f:SetSize(200, 40)
    f:SetScript("OnSizeChanged", function(s) ns.UI.Skin(s) end)
    f.rows = {}
    f.more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f:Hide()
    self.frame = f
    return f
end

-- each row is a secure button that targets its enemy (/targetexact): the game lets addons target only that way, and
-- only outside combat can the rows be set; in combat the list stays as it is until the fight is over
local function row(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
    r:SetHeight(ROW_H)
    r:RegisterForClicks("AnyUp", "AnyDown")
    r:SetAttribute("type", "macro")
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.82, 0, 0.12)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetJustifyH("LEFT")
    r.level = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.level:SetPoint("RIGHT", -2, 0)
    r.stealth = r:CreateTexture(nil, "OVERLAY")
    r.stealth:SetSize(14, 14)
    r.stealth:SetPoint("RIGHT", r.level, "LEFT", -4, 0)
    r.stealth:SetTexture("Interface\\Icons\\Ability_Stealth")
    r.stealth:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.aim = r:CreateTexture(nil, "OVERLAY")
    r.aim:SetSize(14, 14)
    r.aim:SetPoint("RIGHT", r.stealth, "LEFT", -2, 0)
    r.aim:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot")
    r.aim:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.rows[i] = r
    return r
end

-- shown below the element (above it with the panel at the bottom) while there are enemies and it opens by itself,
-- or while the mouse holds it open; at most listRows rows, the rest as "+n more"
function R:UpdateList()
    -- rows (secure buttons) cannot change in combat: after the fight
    if InCombatLockdown and InCombatLockdown() then self.listPending = true return end
    self.listPending = false
    local f = self:ListFrame()
    local d = db()
    local cell = ns.Elements and ns.Elements.cells and ns.Elements.cells.radar
    local list = self:Sorted()
    local open = self.pinned or (d.autoList and not self.dismissed)
    local onPanel = cell and cell:IsVisible() and ns.Elements:Shown("radar")
    -- the test shows the list even without the element on the panel (below the stealth warning's place then)
    local wanted = #list > 0 and open and (onPanel or self.testing)
    if not wanted then f:Hide() return end
    local maxRows = d.listRows or 6
    local n = math.min(#list, maxRows)
    local w = 210
    for i = 1, n do
        local e, r = list[i], row(f, i)
        classIcon(r.icon, e.class)
        local col = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
        r.name:SetText(e.name)
        if col then r.name:SetTextColor(col.r, col.g, col.b) else r.name:SetTextColor(1, 1, 1) end
        local text, lvl = R.LevelText(e)
        r.level:SetText(text)
        r.level:SetTextColor(R.LevelColor(lvl))
        r.stealth:SetShown(e.stealth and true or false)
        r.aim:SetShown(e.targetsMe and true or false)
        r:SetAttribute("macrotext", "/targetexact " .. e.name)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 12, -10 - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", -12, 0)
        r:Show()
        w = math.max(w, (r.name:GetStringWidth() or 0) + 80)
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
    local extra = #list - n
    f.more:ClearAllPoints()
    f.more:SetPoint("TOPLEFT", 14, -10 - n * ROW_H)
    f.more:SetText(extra > 0 and ns.L.RADAR_MORE:format(extra) or "")
    f.more:SetShown(extra > 0)
    f:SetSize(w, 20 + n * ROW_H + (extra > 0 and 14 or 0))
    ns.UI.Skin(f)
    f:ClearAllPoints()
    if not onPanel then f:SetPoint("TOP", self:StealthFrame(), "BOTTOM", 0, -8)
    elseif ns.db.panel.position == "bottom" then f:SetPoint("BOTTOM", cell, "TOP", 0, 6)
    else f:SetPoint("TOP", cell, "BOTTOM", 0, -6) end
    f:Show()
end

-- Sharing with Spy users ---------------------------------------------------------------------------------------
-- Spy tells the group, raid and guild about every enemy it sees, as an addon message "[Spy]": version|player|class|
-- level|race|zone|subZone|mapX|mapY|guild|mapID. Read here, it gives the real level of enemies far above you that a
-- higher group or guild member has seen. Sending in the same format (setting shareSend, off by default) helps Spy
-- users and other users of this addon in return. The version sent is a low one, so Spy never asks anyone to update.
local PREFIX, SEND_VERSION = "[Spy]", "0.0.1"

function R:Received(prefix, message, channel, sender)
    if prefix ~= PREFIX or not db().shareListen or type(message) ~= "string" or ns.Secret(message) then return end
    local _, player, class, level = strsplit("|", message)
    level = tonumber(level)
    local name = baseName(player)
    if not name or name == "" or not level or level < 1 or level > (MAX_PLAYER_LEVEL or 60) or level % 1 ~= 0 then return end
    if baseName(sender) == UnitName("player") then return end
    db().levels = db().levels or {}
    db().levels[name] = level
    local e = self.list[name]
    if e and not (e.level and e.level > 0) then
        e.level, e.levelMin = level, nil
        if class and class ~= "" and not e.class then e.class = class end
        self:Changed()
    end
end

-- Our own sightings to the people you play with (setting shareSend): over our channel (Comm.lua) with everything
-- (stealth "s", targeting the sender "t", the zone), and in Spy's format for Spy users (plain sightings with a level).
-- The same enemy and kind at most once a minute (plain sightings every five minutes).
local sent = {}
function R:Share(e, flags)
    local d = db()
    flags = flags or ""
    if not (d.shareSend or d.shareSpy) or e.test then return end
    local now, key = GetTime(), e.name .. flags
    if sent[key] and now - sent[key] < (flags == "" and 300 or 60) then return end
    sent[key] = now
    local level = e.level and e.level > 0 and e.level or ""
    local zone = GetZoneText and GetZoneText() or ""
    if ns.Comm and d.shareSend then ns.Comm:Send("S", e.name, e.full or e.name, e.class or "", level, zone, flags) end
    if not d.shareSpy or flags ~= "" or level == "" or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local msg = table.concat({ SEND_VERSION, e.full or e.name, e.class or "", level, "", zone,
        GetSubZoneText and GetSubZoneText() or "", "", "", "", "" }, "|")
    if #msg >= 240 then return end
    for _, ch in ipairs(ns.Comm and ns.Comm.Targets() or {}) do pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch) end
end

-- a sighting from another user of this addon: the level is kept; in your zone the enemy joins the list (quietly, but
-- a stealthed one with its sound and warning), marked as reported by that player
function R:Reported(f, channel, sender)
    if not db().shareListen then return end
    local name, class, level, zone, flags = f[1], f[3], tonumber(f[4]), f[5], f[6] or ""
    if not name or name == "" or name:find("[%s|]") then return end
    if class == "" or (RAID_CLASS_COLORS and not RAID_CLASS_COLORS[class]) then class = nil end
    if level and (level < 1 or level > (MAX_PLAYER_LEVEL or 60) or level % 1 ~= 0) then level = nil end
    if level then db().levels = db().levels or {}; db().levels[name] = level end
    if zone ~= (GetZoneText and GetZoneText() or "") or not self:On() then return end
    local stealth = flags:find("s", 1, true) ~= nil
    if self:PvPMode() == "stealth" and not stealth then return end
    self:Seen(name, class, level, stealth, nil, not stealth)
    local e = self.list[name]
    if e then e.reported = sender end
end

-- Spy still installed: its stored levels taken over once, so nothing is lost when it goes
function R:ImportSpy()
    local d = db()
    local data = rawget(_G, "SpyPerCharDB")
    if d.spyImported or type(data) ~= "table" or type(data.PlayerData) ~= "table" then return end
    d.levels = d.levels or {}
    local n = 0
    for key, p in pairs(data.PlayerData) do
        local name = baseName(key)
        if type(p) == "table" and p.isGuess == false and type(p.level) == "number" and name and not d.levels[name] then
            d.levels[name] = p.level
            n = n + 1
        end
    end
    d.spyImported = true
    ns.Debug.Set("radarSpyImport", n)
end

-- Two warnings in the middle of the screen, each on its own: stealth (red, stealth icon) and targets you (orange,
-- crosshair), one below the other, each placed in the move mode on its own and shown for a few seconds. Each has a
-- secure button of the game lying over it (/targetexact, the only way addons may target): a click targets that enemy,
-- and each has its own key (set in the radar options), which works as long as the enemy is in sight. Outside combat
-- the buttons are set to the latest enemy of their kind; in combat the game lets nothing change, so they keep the one
-- from before and catch up after the fight.
local KINDS = {
    stealth = { frame = "ForeverQoLPanelStealthWarning", button = "ForeverQoLPanelStealthTarget", pos = "stealthPos", y = -230,
        icon = "Interface\\Icons\\Ability_Stealth", bg = { 0.25, 0.02, 0.02, 0.88 }, edge = { 1, 0.15, 0.1, 1 },
        glow = { 1, 0.1, 0.05 }, text = "RADAR_STEALTH", title = "RADAR_STEALTH_TITLE", bind = "BIND_STEALTH" },
    target = { frame = "ForeverQoLPanelTargetWarning", button = "ForeverQoLPanelAttackerTarget", pos = "targetPos", y = -282,
        icon = "Interface\\Icons\\Ability_Hunter_SniperShot", bg = { 0.28, 0.13, 0.0, 0.88 }, edge = { 1, 0.6, 0.1, 1 },
        glow = { 1, 0.55, 0.05 }, text = "RADAR_TARGETME", title = "RADAR_TARGET_TITLE", bind = "BIND_TARGETME" },
}
R.KINDS = KINDS
R.alerts, R.buttons, R.until_, R.pending = {}, {}, {}, {}

function R:AlertFrame(kind)
    if self.alerts[kind] then return self.alerts[kind] end
    local k = KINDS[kind]
    local f = CreateFrame("Frame", k.frame, UIParent, "BackdropTemplate")
    f:SetSize(360, 44)
    -- above the buff and consumable warnings (those use the dialog strata)
    f:SetFrameStrata("FULLSCREEN")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(unpack(k.bg))
        f:SetBackdropBorderColor(unpack(k.edge))
    end
    f.glow = f:CreateTexture(nil, "ARTWORK")
    f.glow:SetPoint("TOPLEFT", -10, 10)
    f.glow:SetPoint("BOTTOMRIGHT", 10, -10)
    f.glow:SetTexture("Interface\\Buttons\\UI-Panel-Button-Glow")
    f.glow:SetTexCoord(0, 0.75, 0, 0.609375)
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(unpack(k.glow))
    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetSize(30, 30)
    f.icon:SetPoint("LEFT", 8, 0)
    f.icon:SetTexture(k.icon)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 10, 0)
    f.text:SetPoint("RIGHT", -10, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetTextColor(1, 0.85, 0.8)
    f.text:SetWordWrap(false)
    local ag = f.glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.2)
    a:SetToAlpha(1)
    a:SetDuration(0.45)
    f.pulse = ag
    f:Hide()
    if ns.Mover then
        ns.Mover:Register(f, {
            label = function() return ns.L[k.title] end,
            save = function(x, y) db()[k.pos] = { x, y }; R:PlaceAlert(kind) end,
            reset = function() db()[k.pos] = nil end,
        })
    end
    self.alerts[kind] = f
    self:PlaceAlert(kind)
    return f
end

-- one line, never wrapped: the warning grows with its text (at least 300 wide)
local function fit(f)
    local fs = f.text
    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    f:SetWidth(math.max(300, math.ceil(w) + 8 + 30 + 10 + 16))
end

-- the stealth warning (the list of the test hangs below it)
function R:StealthFrame() return self:AlertFrame("stealth") end

function R:PlaceAlert(kind)
    local f = self.alerts[kind]
    if not f then return end
    local k = KINDS[kind]
    local pos = db()[k.pos]
    f:ClearAllPoints()
    if pos then f:SetPoint("CENTER", UIParent, "CENTER", pos[1], pos[2])
    else f:SetPoint("TOP", UIParent, "TOP", 0, k.y) end
end

function R:PlaceStealth() self:PlaceAlert("stealth"); self:PlaceAlert("target") end

function R:TargetButton(kind)
    kind = kind or "stealth"
    if self.buttons[kind] then return self.buttons[kind] end
    local k = KINDS[kind]
    local b = CreateFrame("Button", k.button, UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("FULLSCREEN")
    b:SetFrameLevel(120)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(ns.L[k.title], 1, 0.82, 0)
        GameTooltip:AddLine(ns.L.RADAR_CLICK_TARGET, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    self.buttons[kind] = b
    return b
end

function R:SetTarget(kind, name, show)
    local b = self:TargetButton(kind)
    if InCombatLockdown and InCombatLockdown() then self.pending[kind] = { name, show } return end
    self.pending[kind] = nil
    if name then b:SetAttribute("macrotext", "/targetexact " .. name) end
    local f = self.alerts[kind]
    if show and f then
        b:ClearAllPoints()
        b:SetAllPoints(f)
        b:Show()
    else
        b:Hide()
    end
end

function R:ShowStealth(e) return self:ShowAlert(e, "stealth") end

function R:ShowAlert(e, kind)
    local f = self:AlertFrame(kind)
    local k = KINDS[kind]
    self:SetTarget(kind, e.name, true)
    local col = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
    local name = col and col.colorStr and ("|c" .. col.colorStr .. e.name .. "|r") or e.name
    -- the level after the name, in its difficulty colour ("36+" when at least, "??" when unknown)
    local text, lvl = R.LevelText(e)
    local cr, cg, cb = R.LevelColor(lvl)
    name = name .. " " .. string.format("|cff%02x%02x%02x", cr * 255, cg * 255, cb * 255) .. "(" .. text .. ")|r"
    f.text:SetText(ns.L[k.text]:format(name))
    fit(f)
    f:Show()
    if ns.db.panel.animations ~= false then f.pulse:Play() end
    local secs = db().stealthTime or 6
    self.until_[kind] = GetTime() + secs
    C_Timer.After(secs + 0.05, function()
        if GetTime() >= (R.until_[kind] or 0) and not R.moving then f.pulse:Stop(); f:Hide(); R:SetTarget(kind, nil, false) end
    end)
end

-- move mode: both warnings show with an example, so they can be placed
function R:SetMoving(on)
    self.moving = on
    for kind, k in pairs(KINDS) do
        local f = self:AlertFrame(kind)
        if on then
            self:SetTarget(kind, nil, false)
            f.text:SetText(ns.L[k.text]:format(ns.L[k.title]))
            fit(f)
            f.pulse:Stop()
            f:Show()
        elseif GetTime() >= (self.until_[kind] or 0) then
            f:Hide()
        end
    end
end

-- The keys that target the enemy of each warning, set from our options: the next key pressed (with Shift / Ctrl /
-- Alt) is bound to that warning's button and saved with the character's key bindings.
local function bindName(kind) return "CLICK " .. KINDS[kind].button .. ":LeftButton" end
function R.BindingText(kind)
    local key = GetBindingKey and GetBindingKey(bindName(kind or "stealth"))
    return key and (GetBindingText and GetBindingText(key) or key) or ns.L.KEY_NONE
end

local function saveBindings()
    if SaveBindings and GetCurrentBindingSet then pcall(SaveBindings, GetCurrentBindingSet()) end
end

function R:ClearBinding(kind)
    if InCombatLockdown() then return end
    for _, key in ipairs({ GetBindingKey and GetBindingKey(bindName(kind or "stealth")) }) do if key then SetBinding(key, nil) end end
    saveBindings()
end

function R:CaptureBinding(kind, done)
    if InCombatLockdown() then return end
    kind = kind or "stealth"
    local c = self.capture
    if not c then
        c = CreateFrame("Frame", "ForeverQoLPanelKeyCapture", UIParent, "BackdropTemplate")
        c:SetSize(340, 80)
        c:SetPoint("CENTER")
        c:SetFrameStrata("FULLSCREEN_DIALOG")
        c:EnableMouse(true)
        c:EnableKeyboard(true)
        c:SetScript("OnSizeChanged", function(s) ns.UI.Skin(s) end)
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        c.text:SetPoint("CENTER")
        c.text:SetWidth(310)
        self.capture = c
    end
    c.text:SetText(ns.L.KEY_PRESS)
    ns.UI.Skin(c)
    c:SetScript("OnKeyDown", function(frame, key)
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then return end
        frame:Hide()
        if key == "ESCAPE" then return end
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        R:ClearBinding(kind)
        if SetBindingClick then SetBindingClick(combo, KINDS[kind].button, "LeftButton") end
        saveBindings()
        if done then done() end
    end)
    c:Show()
end

-- a click on the element: the list closes (until the next new enemy) or opens
function R:Toggle()
    local f = self.frame
    if f and f:IsShown() then self.pinned, self.dismissed = false, true
    else self.pinned, self.dismissed = true, false end
    self:UpdateList()
end

-- Test: made-up enemies, gone again after 15 seconds. mode: "seen" (enemies spotted), "stealth" (one going into
-- stealth), "target" (one targeting you) or "mixed" (all of it, enough to overflow the list). Each run starts clean
-- (an earlier test's enemies would count as known and stay quiet), with the list open and every sound heard.
local FAKE = {
    { "Grimbash", "WARRIOR", 27 }, { "Sylvaria", "MAGE", 25 }, { "Shadevex", "ROGUE", 26, true },
    { "Thornbeard", "HUNTER", 28 }, { "Lumielle", "PRIEST", 24 }, { "Vexmoor", "WARLOCK", 26 },
    { "Brakka", "SHAMAN", 29 }, { "Eldawin", "DRUID", 27, true }, { "Korgath", "PALADIN", 30 },
    { "Ninevel", "MAGE", 23 }, { "Durgash", "WARRIOR", 31 }, { "Selvane", "ROGUE", 0 },
    { "Mirabel", "PRIEST", 26 }, { "Ottokar", "HUNTER", 25 }, { "Zyreth", "WARLOCK", 28 },
}
function R:Test(mode)
    mode = mode or "mixed"
    for name, e in pairs(self.list) do if e.test then self.list[name] = nil end end
    self.testRun = (self.testRun or 0) + 1
    local run = self.testRun
    self.testing, self.pinned, self.dismissed = true, true, false
    local function later(t, fn) C_Timer.After(t, function() if R.testRun == run then fn() end end) end
    local function seen(e, stealth) R:Seen(e[1], e[2], e[3], stealth, true) end
    if mode == "seen" then
        -- a few enemies, one after the other: the sound for the first, the list fills
        for i = 1, 5 do later((i - 1) * 0.6, function() if i == 1 then R.lastSound = 0 end; seen(FAKE[i], false) end) end
    elseif mode == "stealth" then
        later(0, function() seen(FAKE[3], true) end)
    elseif mode == "target" then
        -- spotted and targeting you at once: only the targets-you sound and warning
        later(0, function()
            R:Seen(FAKE[4][1], FAKE[4][2], FAKE[4][3], false, true, true)
            R:TargetsMe(R.list.Thornbeard)
        end)
    else
        for i, e in ipairs(FAKE) do
            later((i - 1) * 0.35, function() if i == 1 then R.lastSound = 0 end; seen(e, e[4]) end)
        end
        -- and after the stealthed one, another one takes you as its target
        later(3.2, function() R:TargetsMe(R.list.Thornbeard) end)
    end
    later(16, function()
        R.testing, R.pinned = false, false
        for name, e in pairs(R.list) do if e.test then R.list[name] = nil end end
        R:Changed()
    end)
end

ns.OnLogin(function()
    local d = db()
    -- the sounds of the test builds before the freesound ones: once to the new defaults
    -- sharing over our own channel became the default (before, one switch covered both and was off)
    if not d.shareV then d.shareV = 1; d.shareSend = true end
    if (d.soundsV or 0) < 2 then d.sound, d.stealthSound = "fsEnemy", "fsAlarm" end
    if (d.soundsV or 0) < 3 then d.targetSound = "fsTarget" end
    d.soundsV = 3
    if not ns.Warnings.SOUNDS[d.sound or ""] and d.sound ~= "none" then d.sound = "fsEnemy" end
    if not ns.Warnings.SOUNDS[d.stealthSound or ""] and d.stealthSound ~= "none" then d.stealthSound = "fsAlarm" end
    pcall(ns.On, "NAME_PLATE_UNIT_ADDED", function(_, unit)
        if type(unit) == "string" then R.plates[unit] = true; ns.Debug.Call("Radar", R.Scan, R, unit) end
    end)
    pcall(ns.On, "NAME_PLATE_UNIT_REMOVED", function(_, unit) if type(unit) == "string" then R.plates[unit] = nil end end)
    pcall(ns.On, "PLAYER_TARGET_CHANGED", function() ns.Debug.Call("Radar", R.Scan, R, "target") end)
    pcall(ns.On, "UPDATE_MOUSEOVER_UNIT", function() ns.Debug.Call("Radar", R.Scan, R, "mouseover") end)
    -- a unit takes a new target (maybe you)
    pcall(ns.On, "UNIT_TARGET", function(_, unit) if type(unit) == "string" then ns.Debug.Call("Radar", R.Scan, R, unit) end end)
    pcall(ns.On, "UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
        if type(unit) == "string" then ns.Debug.Call("Radar", R.Cast, R, unit, spellID) end
    end)
    C_Timer.NewTicker(SCAN, function() ns.Debug.Call("Radar", R.ScanAll, R) end)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    pcall(ns.On, "CHAT_MSG_ADDON", function(_, prefix, message, channel, sender)
        ns.Debug.Call("Radar", R.Received, R, prefix, message, channel, sender)
    end)
    C_Timer.After(5, function() ns.Debug.Call("Radar", R.ImportSpy, R) end)
    if ns.Comm then ns.Comm:On("S", function(f, channel, sender) R:Reported(f, channel, sender) end) end
    pcall(ns.On, "PLAYER_REGEN_ENABLED", function()
        if R.listPending then ns.Debug.Call("Radar", R.UpdateList, R) end
        -- the target button catches up: the latest enemy, shown only while the warning still is
        for kind, pend in pairs(R.pending) do
            local f = R.alerts[kind]
            R:SetTarget(kind, pend[1], f and f:IsShown() and not R.moving)
        end
    end)
    -- the key binding's names in the game's key binding window
    BINDING_HEADER_FOREVERQOLPANEL = ns.title
    for kind, k in pairs(KINDS) do
        _G["BINDING_NAME_CLICK " .. k.button .. ":LeftButton"] = ns.L[k.bind]
        R:TargetButton(kind)
    end
end)

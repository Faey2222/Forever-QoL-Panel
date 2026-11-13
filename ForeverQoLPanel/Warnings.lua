local _, ns = ...

-- Buff and consumable warnings, out of combat: own class buffs missing, food / flask in instances, weapon buffs
-- missing, own buffs about to run out. Shown as a quiet row of icons with text below the screen centre's top.
local W = {}
ns.Warnings = W

local function db() return ns.db.warnings end
local L = setmetatable({}, { __index = function(_, k) return ns.L[k] end })

-- class buffs: each group is satisfied by any of its spells (all ranks share the name)
local CLASS = {
    MAGE = { { 1459, 23028 }, { 168, 7302, 6117 } },              -- Arcane Intellect / Brilliance; an armor
    PRIEST = { { 1243, 21562 }, { 588 } },                        -- Fortitude; Inner Fire
    DRUID = { { 1126, 21849 } },                                  -- Mark / Gift of the Wild
    PALADIN = { { 19740, 19742, 20217, 1038, 19977, 20911, 25782, 25894, 25898, 25899, 25890, 25895 },
        { 465, 7294, 19746, 19876, 19888, 19891, 20218 } },       -- a blessing; an aura
    WARLOCK = { { 687, 706 } },                                   -- Demon Skin / Armor
    HUNTER = { { 13165, 13163, 5118, 13159, 20043 } },            -- an aspect
    SHAMAN = { { 324 } },                                         -- Lightning Shield
}
local WELL_FED = 19705
local FLASKS = { 17626, 17627, 17628, 17629 }
local ELIXIRS = { 17538, 11405, 11334, 3593, 17539, 11474, 26276, 21920, 11348, 17535, 11390, 11406, 3164, 2367, 7844, 11328 }
local IMBUES = { 8017, 8024, 8033, 8232, 2842 }                    -- shaman weapon imbues, rogue poisons

local name, icon = ns.SpellName, ns.SpellIcon
local FOOD_ICON = "Interface\\Icons\\Spell_Misc_Food"      -- the "Well Fed" buff
local FLASK_ICON = "Interface\\Icons\\INV_Potion_97"       -- Flask of the Titans

local function knows(id) return IsPlayerSpell and IsPlayerSpell(id) end

local CHARGED   -- charge buffs by name, below

-- my buffs: [name] = { expires, duration, mine, icon, id (aura instance), charges }; nil while the game locks them
local function auras()
    local list = {}
    for i = 1, 40 do
        local n, dur, exp, src, ic, inst, stacks, _
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            -- Forever locks auras as "secret" in combat and some encounters; reading them then throws
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok then return nil end
            if not a then break end
            n, dur, exp, src = a.name, a.duration, a.expirationTime, a.sourceUnit
            if ns.Secret(n) or ns.Secret(dur) or ns.Secret(exp) or ns.Secret(src) then n = nil end
            ic = not ns.Secret(a.icon) and a.icon or nil
            inst = not ns.Secret(a.auraInstanceID) and a.auraInstanceID or nil
            stacks = not ns.Secret(a.applications) and a.applications or nil
        else
            n, ic, stacks, _, dur, exp, src = UnitBuff("player", i)
            if not n then break end
        end
        if n then
            -- a buff with one charge shows no stack and reads 0
            local charges = stacks and math.max(stacks, 1) or nil
            list[n] = { expires = exp or 0, duration = dur or 0, mine = src == "player", icon = ic, id = inst, charges = charges }
            local rule = CHARGED[n]
            if rule and charges then rule.full = math.max(rule.full or 0, charges) end
        end
    end
    return list
end

-- Charge buffs, counted down in a fight from the hits taken (UNIT_COMBAT stays readable there):
-- the shaman's Lightning Shield loses a charge per hit, at most one every 3.5 s; on Forever Inner Fire has charges
-- too and loses one per physical hit that did damage. Filled with the localized names on first use.
local CHARGE_RULES = {
    { ids = { 324, 325, 905, 945, 8134, 10431, 10432 }, cooldown = 3.5, full = 3 },          -- Lightning Shield
    { ids = { 588, 7128, 602, 1006, 10951, 10952 }, cooldown = 0, full = 20, physical = true, damage = true }, -- Inner Fire
}
CHARGED = setmetatable({}, { __index = function(t, n)
    if rawget(t, "_built") then return nil end
    rawset(t, "_built", true)
    for _, rule in ipairs(CHARGE_RULES) do
        local rn = name(rule.ids[1])
        if rn then rawset(t, rn, rule) end
    end
    return rawget(t, n)
end })

local function anyOf(list, ids)
    for _, id in ipairs(ids) do
        local n = name(id)
        if n and list[n] then return true end
    end
    return false
end

-- While the auras are locked, the last readable list is carried on: buffs drop out when their time runs out, when
-- the game reports their aura instance removed, and come back when I cast them (UNIT_SPELLCAST_SUCCEEDED).
function W:Known()
    -- locked outside combat (encounters): readable again ends it
    if self.locked and not InCombatLockdown() then
        local list = auras()
        if list then self.locked = nil; self.last = list; return list end
    end
    if self.locked then
        local now = GetTime()
        for n, a in pairs(self.locked) do
            if a.expires > 0 and a.expires <= now then self.locked[n] = nil end
        end
        return self.locked
    end
    local list = not InCombatLockdown() and auras()
    if list then
        self.last = list
        return list
    end
    -- just became unreadable: continue from the last list
    self.locked = {}
    for n, a in pairs(self.last or {}) do
        local c = {}
        for k, v in pairs(a) do c[k] = v end
        self.locked[n] = c
    end
    return self:Known()
end

function W:Unlock() self.locked = nil end

local function safe(v) return v ~= nil and not ns.Secret(v) end

-- UNIT_AURA while locked: removed instance IDs, and added auras whose data is readable
function W:AuraChanged(info)
    if not self.locked or type(info) ~= "table" or ns.Secret(info) then return false end
    local changed = false
    local removed = info.removedAuraInstanceIDs
    if safe(removed) then
        for _, inst in ipairs(removed) do
            if safe(inst) then
                for n, a in pairs(self.locked) do
                    if a.id == inst then self.locked[n] = nil; changed = true end
                end
            end
        end
    end
    local added = info.addedAuras
    if safe(added) then
        for _, a in ipairs(added) do
            if safe(a) and safe(a.name) and a.isHelpful ~= false then
                self.locked[a.name] = { expires = safe(a.expirationTime) and a.expirationTime or 0,
                    duration = safe(a.duration) and a.duration or 0, mine = true,
                    icon = safe(a.icon) and a.icon or nil, id = safe(a.auraInstanceID) and a.auraInstanceID or nil }
                changed = true
            end
        end
    end
    ns.Debug.Set("auraLocked", { removedReadable = safe(removed), addedReadable = safe(added) })
    return changed
end

-- a hit taken while locked: spends charges by the rules above; true when a buff ran out of charges
function W:Hit(action, flag, amount, school)
    if not self.locked or ns.Secret(action) or action ~= "WOUND" then return false end
    local physical = not ns.Secret(school) and school == 1
    local noDamage = (not ns.Secret(flag) and flag == "ABSORB") or (not ns.Secret(amount) and amount == 0)
    local now, gone = GetTime(), false
    for n, a in pairs(self.locked) do
        local rule = CHARGED[n]
        if rule and a.charges and a.charges > 0 and (physical or not rule.physical) and not (rule.damage and noDamage)
            and now - (a.spentAt or 0) >= rule.cooldown then
            a.charges = a.charges - 1
            a.spentAt = now
            if a.charges == 0 then self.locked[n] = nil; gone = true end
        end
    end
    return gone
end

-- my own cast while locked: a class buff counts as there again
function W:Cast(spellID)
    if not self.locked or not safe(spellID) then return false end
    local n = name(spellID)
    if not n then return false end
    local mine = CHARGED[n] ~= nil
    local _, class = UnitClass("player")
    for _, group in ipairs(CLASS[class] or {}) do
        for _, id in ipairs(group) do
            if name(id) == n then mine = true end
        end
    end
    if not mine then return false end
    -- a recast fills the charges but keeps the wait since the last one spent
    local old, rule = self.locked[n], CHARGED[n]
    self.locked[n] = { expires = 0, duration = 0, mine = true, icon = icon(spellID),
        charges = rule and rule.full or nil, spentAt = old and old.spentAt }
    return true
end

-- what is missing now: { { icon, text, group ("buffs" / "cons"), key (stable, for the appear animation) } }
function W:Check()
    local out = {}
    local list = self:Known()
    local _, class = UnitClass("player")
    if db().classBuffs then
        for _, group in ipairs(CLASS[class] or {}) do
            local known
            for _, id in ipairs(group) do if knows(id) then known = known or id end end
            if known and not anyOf(list, group) then out[#out + 1] = { icon(known), L.WARN_MISSING:format(name(known) or "?"), "buffs", "class" .. known } end
        end
    end
    local inInstance, kind = IsInInstance()
    local group = inInstance and (kind == "party" or kind == "raid")
    -- where: "world" everywhere, "instance" dungeons and raids, "raid" raids only
    local function here(where)
        if where == "world" then return true end
        if where == "raid" then return inInstance and kind == "raid" end
        return group
    end
    if db().food and here(db().foodWhere) then
        local fed = name(WELL_FED)
        if fed and not list[fed] then out[#out + 1] = { icon(WELL_FED) or FOOD_ICON, L.WARN_FOOD, "cons", "food" } end
    end
    if db().flask and here(db().flaskWhere) and not anyOf(list, FLASKS) and not anyOf(list, ELIXIRS) then
        out[#out + 1] = { icon(FLASKS[1]) or FLASK_ICON, L.WARN_FLASK, "cons", "flask" }
    end
    if db().weapon and GetWeaponEnchantInfo then
        local ok, hasMain = pcall(GetWeaponEnchantInfo)
        if not ok or ns.Secret(hasMain) then hasMain = self.lastWeapon else self.lastWeapon = hasMain end
        local imbuer = false
        for _, id in ipairs(IMBUES) do if knows(id) then imbuer = true end end
        if hasMain then self.hadWeaponBuff = true end
        -- rogues and shamans always; everyone else only after a weapon buff ran out this session
        if not hasMain and (imbuer or self.hadWeaponBuff) and GetInventoryItemLink("player", 16) then
            out[#out + 1] = { GetInventoryItemTexture("player", 16), L.WARN_WEAPON, "cons", "weapon" }
        end
    end
    -- ammo: hunters only (the only class that shoots it)
    local _, myClass = UnitClass("player")
    if db().ammo and myClass == "HUNTER" and ns.Elements and ns.Elements.AmmoCount then
        local n, link = ns.Elements.AmmoCount()
        if (n or 0) < (db().ammoMin or 200) and (n ~= nil or not link) then
            local tex = link and ns.ItemIcon(link) or "Interface\\Icons\\INV_Ammo_Arrow_02"
            local text = (n or 0) == 0 and L.WARN_AMMO_NONE or L.WARN_AMMO:format(n)
            out[#out + 1] = { tex, text, "cons", "ammo" }
        end
    end
    if db().expiring then
        local now = GetTime()
        for n, a in pairs(list) do
            if a.mine and a.duration >= 120 and a.expires > 0 and a.expires - now < 60 then
                out[#out + 1] = { a.icon, L.WARN_EXPIRING:format(n, math.max(0, math.floor(a.expires - now))), "buffs", "exp" .. n }
            end
        end
    end
    return out
end

-- Frames -------------------------------------------------------------------------
-- Two groups, each its own frame: buffs (class buffs, expiring) and consumables (food, flask, weapon buff).
-- Move mode (from the options) works like Edit Mode: blue boxes, drag them; dropped next to the other one they snap
-- together and move as a group; Shift-drag takes one out of the group; right-click finishes.
-- New warnings get a short animation (pulse, bounce, flash or wave), as often as the global animation setting allows.

local ICON, ROW_W, GAP, SNAP = 28, 340, 6, 24
local GROUPS = { "buffs", "cons" }
local OTHER = { buffs = "cons", cons = "buffs" }
local DEFAULT_POS = { "TOP", "TOP", 0, -150 }
local SIDES = {   -- follower point, leader point, x, y
    BOTTOM = { "TOP", "BOTTOM", 0, -GAP }, TOP = { "BOTTOM", "TOP", 0, GAP },
    RIGHT = { "LEFT", "RIGHT", GAP, 0 }, LEFT = { "RIGHT", "LEFT", -GAP, 0 },
}
W.frames = {}

local function link() return db().link end   -- { follower, leader, side } or nil (default: consumables below buffs)

-- snapped: dropped in move mode, onto the grid (Mover.lua)
local function savePosition(f, snapped)
    local x, y = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (x and ux) then return end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local cx, cy = math.floor(x * s - ux + 0.5), math.floor(y * s - uy + 0.5)
    if snapped then cx, cy = ns.Mover.SnapCenter(f) end
    db().pos = db().pos or {}
    db().pos[f.group] = { "CENTER", "CENTER", cx, cy }
end

local function anchor(f)
    f:ClearAllPoints()
    f:SetScale(db().scale or 1)
    local l = link()
    if l and l.follower == f.group then
        local side = SIDES[l.side] or SIDES.BOTTOM
        f:SetPoint(side[1], W.frames[l.leader], side[2], side[3], side[4])
        return
    end
    local p = db().pos and db().pos[f.group] or DEFAULT_POS
    if f.group == "cons" and not (db().pos and db().pos.cons) then p = { "TOP", "TOP", 0, -150 - 3 * (ICON + 8) } end
    -- scaled frames: offsets were saved in UIParent units
    local s = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
    f:SetPoint(p[1], UIParent, p[2], p[3] * s, p[4] * s)
end

local function placeAll()
    -- the leader first, so the follower can anchor to it
    local l = link()
    if l then anchor(W.frames[l.leader]); anchor(W.frames[l.follower])
    else for _, g in ipairs(GROUPS) do anchor(W.frames[g]) end end
end

-- dropped close to the other frame: which side to snap to (nil = too far)
local function snapSide(f, o)
    local l1, b1, w1, h1 = f:GetRect()
    local l2, b2, w2, h2 = o:GetRect()
    if not (l1 and l2) then return nil end
    local s1, s2 = f:GetEffectiveScale(), o:GetEffectiveScale()
    l1, b1, w1, h1 = l1 * s1, b1 * s1, w1 * s1, h1 * s1
    l2, b2, w2, h2 = l2 * s2, b2 * s2, w2 * s2, h2 * s2
    local overlapX = l1 < l2 + w2 + SNAP and l2 < l1 + w1 + SNAP
    local overlapY = b1 < b2 + h2 + SNAP and b2 < b1 + h1 + SNAP
    if not (overlapX and overlapY) then return nil end
    local dx, dy = (l1 + w1 / 2) - (l2 + w2 / 2), (b1 + h1 / 2) - (b2 + h2 / 2)
    if math.abs(dy) * w2 >= math.abs(dx) * h2 then return dy < 0 and "BOTTOM" or "TOP" end
    return dx > 0 and "RIGHT" or "LEFT"
end

local function startDrag(f)
    if not W.moving then return end
    local l = link()
    if IsShiftKeyDown() and l then
        -- out of the group: both keep their current place
        for _, g in ipairs(GROUPS) do savePosition(W.frames[g]) end
        db().link = false
        placeAll()
    end
    l = link()
    local mover = (l and l.follower == f.group) and W.frames[l.leader] or f
    W.dragging = mover
    ns.Mover:StartDrag(mover)   -- follows the cursor, on the grid
end

local function stopDrag()
    local f = W.dragging
    if not f then return end
    W.dragging = nil
    ns.Mover:StopDrag()
    savePosition(f, true)
    if not link() then
        local o = W.frames[OTHER[f.group]]
        local side = snapSide(f, o)
        if side then
            savePosition(o)
            db().link = { follower = f.group, leader = o.group, side = side }
        end
    end
    placeAll()
end

local function createFrame(group)
    local f = CreateFrame("Frame", "ForeverQoLPanelWarnings" .. (group == "buffs" and "" or "Cons"), UIParent)
    f.group = group
    f:SetSize(ROW_W, ICON + 4)
    -- above game texts like errors and raid warnings (DIALOG), still below menus and tooltips
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(500)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f.rows = {}
    f.shown = {}
    f.box = f:CreateTexture(nil, "BACKGROUND")
    f.box:SetPoint("TOPLEFT", -4, 4)
    f.box:SetPoint("BOTTOMRIGHT", 4, -4)
    if not ns.SetAtlas(f.box, "editSel", { "editmode-actionbar-selected-nineslice-center" }) then
        f.box:SetColorTexture(0.25, 0.55, 1, 0.3)
    end
    f.box:SetVertexColor(0.45, 0.7, 1, 0.55)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.label:SetPoint("BOTTOM", f, "TOP", 0, 8)
    f.box:Hide(); f.label:Hide()
    f:RegisterForDrag("LeftButton")
    -- drag and mouse scripts switch the mouse on: off again, so the warnings never catch clicks outside move mode
    f:SetScript("OnDragStart", startDrag)
    f:SetScript("OnDragStop", stopDrag)
    f:SetScript("OnMouseUp", function(_, button) if W.moving and button == "RightButton" then ns.Mover:Toggle(false) end end)
    f:EnableMouse(false)
    W.frames[group] = f
    return f
end

local function frames()
    if not W.frames.buffs then
        createFrame("buffs"); createFrame("cons")
        -- consumables sit below the buffs as a group until moved apart
        if db().link == nil then db().link = { follower = "cons", leader = "buffs", side = "BOTTOM" } end
        placeAll()
        W.frame = W.frames.buffs
    end
    return W.frames
end

local function styleIcon(r, tex)
    ns.StyleIcon(r, tex, db().iconShape, ICON)
end

-- Animations ---------------------------------------------------------------------
-- Driven frame by frame (OnUpdate) rather than with animation groups: the rows are re-anchored on every update,
-- which cut Blizzard's animations short. Pulse fades the row, bounce lifts it, flash brightens the icon in its own
-- shape, wave sends rings outwards from the icon.

local PERIOD = { pulse = 1.0, bounce = 0.5, flash = 0.8, wave = 1.1 }

-- how often a new warning animates: 0 = never
local function repeats()
    local m = ns.Motion and ns.Motion() or "full"
    if m == "off" or (db().anim or "pulse") == "none" then return 0 end
    return m == "reduced" and 1 or 3
end

local function anchorRow(r)
    r:ClearAllPoints()
    r:SetPoint("TOP", r:GetParent(), "TOP", 0, (r.baseY or 0) + (r.dy or 0))
end

local function stopAnims(r)
    r:SetScript("OnUpdate", nil)
    r:SetAlpha(1)
    r.flash:Hide()
    r.wave:Hide()
    if (r.dy or 0) ~= 0 then r.dy = 0; anchorRow(r) end
end

-- the flash is a brighter copy of the icon (additive), masked like the icon: round stays round
local function prepareFlash(r)
    r.flash:SetTexture(r.icon:GetTexture())
    r.flash:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if r.masked and r.mask and not r.flashMasked then r.flash:AddMaskTexture(r.mask); r.flashMasked = true end
    if not r.masked and r.flashMasked then r.flash:RemoveMaskTexture(r.mask); r.flashMasked = false end
end

-- the wave is the icon's frame shape (ring or square frame), growing and fading
local function prepareWave(r)
    local shape = db().iconShape
    if shape == nil or shape == "panel" then shape = ns.db.panel.iconBorder end
    if shape == "square" then
        ns.SetAtlas(r.wave, "frame", { "ui-hud-actionbar-iconframe", "ui-hud-actionbar-iconframe-c60" })
    else
        ns.SetAtlas(r.wave, "ring", { "voicechat-portrait-ring", "worldquest-tracker-ring" })
    end
    r.wave:SetVertexColor(1, 0.82, 0.3)
end

local function playAnim(r)
    stopAnims(r)
    local n = repeats()
    if n == 0 then return end
    local kind = db().anim or "pulse"
    local period = PERIOD[kind] or 1
    local t, total = 0, n * period
    if kind == "flash" then prepareFlash(r); r.flash:SetAlpha(0); r.flash:Show() end
    if kind == "wave" then prepareWave(r); r.wave:SetAlpha(0); r.wave:Show() end
    r:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        if t >= total then stopAnims(self) return end
        local phase = (t % period) / period                    -- 0 -> 1 in each period
        local wave = 0.5 - 0.5 * math.cos(2 * math.pi * phase)  -- 0 -> 1 -> 0
        if kind == "bounce" then
            self.dy = 8 * math.abs(math.sin(math.pi * phase))
            anchorRow(self)
        elseif kind == "flash" then
            self.flash:SetAlpha(0.8 * wave)
        elseif kind == "wave" then
            local size = ICON * (1.15 + 1.1 * phase)
            self.wave:SetSize(size, size)
            self.wave:SetAlpha(0.9 * (1 - phase) * (1 - phase))
        else
            self:SetAlpha(1 - 0.65 * wave)
        end
    end)
end

-- Showing ------------------------------------------------------------------------

local function row(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f)
    r:SetSize(ROW_W, ICON + 4)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.ring = r:CreateTexture(nil, "OVERLAY")
    r.ring:SetPoint("CENTER", r.icon, "CENTER")
    r.flash = r:CreateTexture(nil, "ARTWORK", nil, 2)
    r.flash:SetBlendMode("ADD")
    r.flash:SetAllPoints(r.icon)
    r.flash:Hide()
    r.wave = r:CreateTexture(nil, "OVERLAY", nil, 3)
    r.wave:SetPoint("CENTER", r.icon, "CENTER")
    r.wave:SetBlendMode("ADD")
    r.wave:Hide()
    r.text = r:CreateFontString(nil, "OVERLAY")
    r.text:SetFont(ns.FontFile(), 15, "OUTLINE")
    r.text:SetTextColor(1, 0.82, 0)
    -- icon anchored to the row (a mask on a texture that hangs on a font string stays empty), text on the icon
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    f.rows[i] = r
    return r
end

local function showGroup(f, list)
    local seen = {}
    for i, w in ipairs(list) do
        local r = row(f, i)
        r.baseY = -(i - 1) * (ICON + 8)
        anchorRow(r)
        r.text:SetText(w[2])
        local width = ICON + 8 + (r.text:GetStringWidth() or 0)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", r, "CENTER", -width / 2, 0)
        styleIcon(r, w[1])
        r:Show()
        if i == 1 then
            -- diagnosis of the icon look (read from the SavedVariables after /reload)
            ns.Debug.Set("warnIcon", { tex = tostring(w[1]), shape = tostring(db().iconShape), panel = ns.db.panel.iconBorder,
                got = tostring((r.icon:GetTexture())), w = r.icon:GetWidth(), masked = r.masked or false })
        end
        local key = w[4] or w[2]
        -- right after a loading screen nothing animates yet (it would run unseen behind the screen); such a warning
        -- counts as new until then and animates once the world is visible
        local ready = GetTime() >= (W.readyAt or 0)
        if ready then seen[key] = true end
        if not W.moving and ready then
            -- new warnings animate; a warning that stays again every 30 s, or without pause, as set
            local again = db().animRepeat
            local idle = not r:GetScript("OnUpdate")
            if not f.shown[key] or r.key ~= key then
                playAnim(r); r.lastPlay = GetTime()
            elseif idle and (again == "always" or (again == "30" and GetTime() - (r.lastPlay or 0) >= 30)) then
                playAnim(r); r.lastPlay = GetTime()
            end
            r.key = key
        end
    end
    for i = #list + 1, #f.rows do stopAnims(f.rows[i]); f.rows[i]:Hide() end
    f.shown = seen
    -- an empty frame collapses, so a group closes up; in move mode both stay visible
    f:SetHeight(#list > 0 and #list * (ICON + 8) - 4 or 1)
    f:SetShown(#list > 0)
end

function W:Show(list)
    local fr = frames()
    local split = { buffs = {}, cons = {} }
    for _, w in ipairs(list) do
        local g = split[w[3] or "buffs"] or split.buffs
        g[#g + 1] = w
    end
    showGroup(fr.buffs, split.buffs)
    showGroup(fr.cons, split.cons)
    if not self.moving and #list > (self.count or 0) and db().sound and PlaySound then
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    end
    self.count = #list
end

-- examples while moving
local function samples()
    local _, class = UnitClass("player")
    local group = CLASS[class] and CLASS[class][1]
    local id = group and group[1] or 1459
    return {
        { icon(id), L.WARN_MISSING:format(name(id) or "?"), "buffs", "s1" },
        { icon(WELL_FED) or FOOD_ICON, L.WARN_FOOD, "cons", "s2" },
    }
end

function W:SetMoving(on)
    if on and InCombatLockdown() then return end
    self.moving = on and true or false
    for _, f in pairs(frames()) do
        f:EnableMouse(self.moving)
        f.box:SetShown(self.moving)
        f.label:SetShown(self.moving)
        f.label:SetText((f.group == "buffs" and L.WARN_GROUP_BUFFS or L.WARN_GROUP_CONS) .. "\n|cffffffff" .. L.WARN_MOVE_HINT .. "|r")
    end
    if self.moving then self:Show(samples()) else self:Update() end
end

function W:ResetPosition()
    db().pos = nil
    db().link = nil
    frames()
    db().link = { follower = "cons", leader = "buffs", side = "BOTTOM" }
    placeAll()
end

-- preview of the chosen animation on the shown warnings (options)
function W:PreviewAnim()
    for _, f in pairs(frames()) do
        for _, r in ipairs(f.rows) do if r:IsShown() then playAnim(r) end end
    end
end

function W:ApplyLook()
    if not self.frames.buffs then return end
    placeAll()
    if self.moving then self:Show(samples()) else self:Update() end
end

-- a game window that the warnings would cover: a UI panel (character, talents, professions, ...) or the map
local function windowOpen()
    if GetUIPanel then
        for _, side in ipairs({ "left", "center", "right", "doublewide", "fullscreen" }) do
            local ok, panel = pcall(GetUIPanel, side)
            if ok and panel then return true end
        end
    end
    for _, name in ipairs({ "WorldMapFrame", "PlayerSpellsFrame", "ProfessionsFrame", "ClassTalentFrame", "SpellBookFrame" }) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown and f:IsShown() then return true end
    end
    return false
end

function W:Update()
    if self.moving then return end
    local d = db()
    local quiet = not d.enabled or (InCombatLockdown() and not d.combat) or UnitIsDeadOrGhost("player")
        or UnitOnTaxi("player") or (IsMounted and IsMounted() and not InCombatLockdown())
        or (d.hideWithWindows and windowOpen())
        or (d.hideResting and IsResting and IsResting())
    self:Show(quiet and {} or self:Check())
end

ns.OnLogin(function()
    C_Timer.NewTicker(2, function() ns.Debug.Call("Warnings", W.Update, W) end)
    local function afterLoading()
        W.readyAt = GetTime() + 3
        C_Timer.After(3.2, function() ns.Debug.Call("Warnings", W.Update, W) end)
    end
    afterLoading()
    ns.On("PLAYER_ENTERING_WORLD", afterLoading)
    ns.On("LOADING_SCREEN_DISABLED", afterLoading)
    -- windows opening or closing: right away, not with the next tick
    local function soon() C_Timer.After(0, function() ns.Debug.Call("Warnings", W.Update, W) end) end
    if ShowUIPanel then hooksecurefunc("ShowUIPanel", soon) end
    if HideUIPanel then hooksecurefunc("HideUIPanel", soon) end
    if WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", soon)
        WorldMapFrame:HookScript("OnHide", soon)
    end
    ns.On("PLAYER_REGEN_DISABLED", function()
        if W.moving then W:SetMoving(false) end
        ns.Debug.Call("Warnings", W.Update, W)
    end)
    ns.On("PLAYER_REGEN_ENABLED", function() W:Unlock(); ns.Debug.Call("Warnings", W.Update, W) end)
    ns.On("PLAYER_UPDATE_RESTING", function() ns.Debug.Call("Warnings", W.Update, W) end)
    ns.On("BAG_UPDATE_DELAYED", function() ns.Debug.Call("Warnings", W.Update, W) end)
    ns.On("UNIT_AURA", function(_, unit, info)
        if unit ~= "player" then return end
        if W.locked then
            if not W:AuraChanged(info) then return end
        end
        ns.Debug.Call("Warnings", W.Update, W)
    end)
    ns.On("UNIT_COMBAT", function(_, unit, action, flag, amount, school)
        if unit == "player" and W.locked and W:Hit(action, flag, amount, school) then ns.Debug.Call("Warnings", W.Update, W) end
    end)
    ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
        if unit == "player" and W:Cast(spellID) then ns.Debug.Call("Warnings", W.Update, W) end
    end)
end)

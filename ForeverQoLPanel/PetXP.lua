local _, ns = ...

-- The hunter pet's XP bar: the pet's level, XP and share of the level, in the reputation bar's art and size. Where it
-- goes is the panel's business (Dock.lua: beside the XP bar, hanging from it, free, under the pet's portrait; XPRing.lua:
-- around the minimap). Only there while a pet with experience is out (hunters).
local Pet = {}
ns.PetXP = Pet

local fmt, floor, max, min = string.format, math.floor, math.max, math.min
local TWEEN = 0.6

-- the fill in a colour of Forever's reputation art (rounded ends built in), flat colours in the modern skin
local ATLAS = {
    bg = { "ui-hud-experiencebar-background", "ui-hud-experiencebar-background-c60" },
    orange = { "ui-hud-experiencebar-fill-reputation-faction-orange", "ui-hud-experiencebar-fill-reputation-faction-orange-c60" },
    yellow = { "ui-hud-experiencebar-fill-reputation-faction-yellow", "ui-hud-experiencebar-fill-reputation-faction-yellow-c60" },
    green = { "ui-hud-experiencebar-fill-reputation-faction-green", "ui-hud-experiencebar-fill-reputation-faction-green-c60" },
    blue = { "ui-hud-experiencebar-fill-reputation-faction-blue", "ui-hud-experiencebar-fill-reputation-faction-blue-c60" },
    red = { "ui-hud-experiencebar-fill-reputation-faction-red", "ui-hud-experiencebar-fill-reputation-faction-red-c60" },
}
Pet.COLORS = {   -- the choices, with the flat colour for the modern skin and the minimap ring
    orange = { 0.95, 0.55, 0.15 }, yellow = { 0.95, 0.8, 0.2 }, green = { 0.2, 0.75, 0.25 },
    blue = { 0.25, 0.5, 0.95 }, red = { 0.85, 0.2, 0.15 },
}
Pet.COLOR_ORDER = { "orange", "yellow", "green", "blue", "red" }
local resolved = {}

local function db() return ns.db.panel end
local function plain(v) return type(v) == "number" and not ns.Secret(v) and v or nil end

-- name, level, XP within the level, XP the level needs; nil without a pet that gains experience
function Pet:Data()
    if not (UnitExists and UnitExists("pet")) or not GetPetExperience then return nil end
    local ok, cur, nxt = pcall(GetPetExperience)
    cur, nxt = ok and plain(cur), ok and plain(nxt)
    if not cur or not nxt or nxt <= 0 then return nil end
    return UnitName("pet") or "?", plain(UnitLevel("pet")) or 0, cur, nxt
end

function Pet:Active()
    local p = db()
    return p.enabled and p.petBar and self:Data() ~= nil or false
end

function Pet.Color()
    local c = Pet.COLORS[db().petColor or "orange"] or Pet.COLORS.orange
    return c[1], c[2], c[3]
end

local function num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(floor(n + 0.5)) or tostring(floor(n + 0.5)) end
local function decimal(v)
    local s = fmt("%.1f", v)
    if ns.language ~= "enUS" and ns.language ~= "zhCN" then s = s:gsub("%.", ",") end
    return s
end

local function crop(tex, key, a, b)
    local info = not Pet.modern and resolved[key]
    if info then
        tex:SetTexture(info.file or info.filename)
        local l, r = info.leftTexCoord, info.rightTexCoord
        tex:SetTexCoord(l + (r - l) * a, l + (r - l) * b, info.topTexCoord, info.bottomTexCoord)
        tex:SetVertexColor(1, 1, 1, 1)
    elseif key == "bg" then
        tex:SetColorTexture(0, 0, 0, Pet.modern and 0.55 or 0.75)
    else
        local r, g, bl = Pet.Color()
        tex:SetColorTexture(r * 0.8, g * 0.8, bl * 0.8, 1)
    end
end

function Pet:Create(parent)
    for key, names in pairs(ATLAS) do
        local _, info = ns.ResolveAtlas("pet-" .. key, names)
        resolved[key] = info
    end
    local f = CreateFrame("Frame", "ForeverQoLPanelPetBar", parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 3)
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.bg:SetAllPoints()
    f.bg2 = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.bg2:SetAllPoints()
    f.fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.shadow = f:CreateTexture(nil, "ARTWORK", nil, 6)
    f.shadow:SetColorTexture(1, 1, 1, 1)
    f.shadow:Hide()
    f.flash = f:CreateTexture(nil, "ARTWORK", nil, 4)
    f.flash:SetColorTexture(1, 0.95, 0.75, 1)
    f.flash:SetBlendMode("ADD")
    f.flash:SetAlpha(0)
    f.flashAnim = f.flash:CreateAnimationGroup()
    local fa = f.flashAnim:CreateAnimation("Alpha")
    fa:SetFromAlpha(0.55)
    fa:SetToAlpha(0)
    fa:SetDuration(0.9)
    fa:SetSmoothing("OUT")
    f.ticks = {}
    for i = 1, 19 do
        local t = f:CreateTexture(nil, "ARTWORK", nil, 5)
        t.light = f:CreateTexture(nil, "ARTWORK", nil, 5)
        t.light:SetColorTexture(1, 0.88, 0.62, 0.4)
        t.light:SetPoint("TOPLEFT", t, "TOPRIGHT")
        t.light:SetPoint("BOTTOMLEFT", t, "BOTTOMRIGHT")
        t.light:SetWidth(1)
        f.ticks[i] = t
    end
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(s) Pet:ShowTooltip(s) end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    self.frame = f
    self:ApplySkin(false)
    return f
end

function Pet:ApplySkin(modern)
    local f = self.frame
    if not f then return end
    self.modern = modern
    crop(f.bg, "bg", 0, 1)
    crop(f.bg2, "bg", 0, 1)
    f.bg2:SetShown(not modern and resolved.bg ~= nil)
    self.shown = nil
end

-- ctx: the frame the bar sits in (a holder), nil = the panel; no size hides the bar
function Pet:SetGeometry(x, y, w, h, ctx)
    local f = self.frame
    if not f then return end
    if not w then f:Hide() return end
    local parent = ctx or ns.Dock
    if f:GetParent() ~= parent then
        f:SetParent(parent)
        f:SetFrameLevel(parent:GetFrameLevel() + 3)
    end
    f:ClearAllPoints()
    if ctx then f:SetPoint("TOPLEFT", ctx, "TOPLEFT", x, -y) else ns.Dock:Anchor(f, x, y) end
    self:SetShadow(false)
    f:SetSize(w, h)
    self.w, self.h = w, h
    f:Show()
    local step = db().petTicks or 0
    local n = step > 0 and floor(100 / step - 0.5) or 0
    for i, t in ipairs(f.ticks) do
        if i <= n then
            t:ClearAllPoints()
            t:SetPoint("RIGHT", f, "LEFT", floor(w * i * step / 100 + 0.5), 0)
            if self.modern then
                t:SetColorTexture(0, 0, 0, 0.3)
                t:SetSize(1, max(2, h - 3))
                t.light:Hide()
            else
                t:SetColorTexture(0, 0, 0, 0.85)
                t:SetSize(1, h - 2)
                t.light:Show()
            end
            t:Show()
        else
            t:Hide()
            t.light:Hide()
        end
    end
    self:Update()
end

-- the XP bar's shadow while the bar hangs from it; flip: the XP bar lies below it
function Pet:SetShadow(on, flip)
    local t = self.frame and self.frame.shadow
    if not t then return end
    if not on then t:Hide() return end
    local h = math.max(3, math.floor((self.h or 10) * 0.6 + 0.5))
    t:ClearAllPoints()
    t:SetPoint(flip and "BOTTOMLEFT" or "TOPLEFT")
    t:SetPoint(flip and "BOTTOMRIGHT" or "TOPRIGHT")
    t:SetHeight(h)
    if t.SetGradient and CreateColor then
        local dark, clear = CreateColor(0, 0, 0, 0.7), CreateColor(0, 0, 0, 0)
        if flip then t:SetGradient("VERTICAL", dark, clear) else t:SetGradient("VERTICAL", clear, dark) end
    else
        t:SetVertexColor(0, 0, 0, 0.35)
    end
    t:Show()
end

function Pet:Draw(k)
    local f = self.frame
    if not self.w then return end
    k = max(0, min(1, k))
    if k <= 0.0005 then f.fill:Hide() return end
    f.fill:ClearAllPoints()
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetSize(self.w * k, self.h)
    crop(f.fill, db().petColor or "orange", 0, k)
    f.fill:Show()
end

function Pet:Update()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    local name, level, cur, nxt = self:Data()
    if not name then return end
    local k = cur / nxt
    -- a new level starts over; within a level the fill glides and the gain flashes
    local same = self.lastLevel == level and self.shown
    if same and k > self.shown + 0.0005 and ns.db.panel.animations then
        local from = self.shown
        f.flash:ClearAllPoints()
        f.flash:SetPoint("TOPLEFT", f, "TOPLEFT", from * self.w, 0)
        f.flash:SetSize(max(1, (k - from) * self.w), self.h)
        f.flashAnim:Stop(); f.flashAnim:Play()
        local t = 0
        f:SetScript("OnUpdate", function(_, elapsed)
            t = min(1, t + elapsed / TWEEN)
            local e = t * t * (3 - 2 * t)
            self.shown = from + (k - from) * e
            self:Draw(self.shown)
            if t >= 1 then f:SetScript("OnUpdate", nil) end
        end)
    else
        f:SetScript("OnUpdate", nil)
        self.shown = k
        self:Draw(k)
    end
    self.lastLevel = level
end

function Pet:ShowTooltip(owner)
    local name, level, cur, nxt = self:Data()
    if not name then return end
    local L = ns.L
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(name, 1, 0.82, 0)
    GameTooltip:AddLine(L.LEVEL_N:format(level), 1, 1, 1)
    GameTooltip:AddDoubleLine(L.EXPERIENCE, fmt("%s / %s (%s %%)", num(cur), num(nxt), decimal(cur / nxt * 100)), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddLine(L.PET_LEFT:format(num(nxt - cur), level + 1), 0.82, 0.82, 0.82)
    GameTooltip:Show()
end

-- a pet called or dismissed changes the panel's layout
local wasActive
local function changed()
    local active = Pet:Active()
    if active ~= wasActive and ns.Dock.band then
        wasActive = active
        ns.Dock.width = nil
        ns.Dock:Relayout()
        if ns.Ring then ns.Ring.RefreshAll() end
    end
    Pet:Update()
end
Pet.Changed = changed

ns.OnLogin(function()
    wasActive = Pet:Active()
    for _, ev in ipairs({ "UNIT_PET_EXPERIENCE", "PET_UI_UPDATE", "PET_BAR_UPDATE" }) do
        pcall(ns.On, ev, function() ns.Debug.Call("PetXP", changed) end)
    end
    pcall(ns.On, "UNIT_PET", function(_, unit) if unit == "player" then C_Timer.After(0.2, function() ns.Debug.Call("PetXP", changed) end) end end)
    pcall(ns.On, "UNIT_LEVEL", function(_, unit) if unit == "pet" then ns.Debug.Call("PetXP", changed) end end)
end)

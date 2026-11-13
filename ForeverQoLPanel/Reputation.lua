local _, ns = ...

-- Reputation bar: the XP bar's little sibling below it, for the faction you watch (character window, "Show as
-- experience bar"). Same looks as the XP bar: Forever's bar art in the classic skin (the fill coloured by standing,
-- tick grooves, the bar border drawn by the panel), flat colours in the modern one; it glides and flashes on gains
-- and has its own status text.
local Rep = {}
ns.Rep = Rep

local fmt, floor, max, min = string.format, math.floor, math.max, math.min
local TWEEN = 0.6

-- Forever's reputation fills (rounded ends built in), by standing: hated..unfriendly red, neutral yellow, friendly
-- and up green
local ATLAS = {
    bg = { "ui-hud-experiencebar-background", "ui-hud-experiencebar-background-c60" },
    red = { "ui-hud-experiencebar-fill-reputation-faction-red", "ui-hud-experiencebar-fill-reputation-faction-red-c60" },
    orange = { "ui-hud-experiencebar-fill-reputation-faction-orange", "ui-hud-experiencebar-fill-reputation-faction-orange-c60" },
    yellow = { "ui-hud-experiencebar-fill-reputation-faction-yellow", "ui-hud-experiencebar-fill-reputation-faction-yellow-c60" },
    green = { "ui-hud-experiencebar-fill-reputation-faction-green", "ui-hud-experiencebar-fill-reputation-faction-green-c60" },
    blue = { "ui-hud-experiencebar-fill-reputation-faction-blue", "ui-hud-experiencebar-fill-reputation-faction-blue-c60" },
}
local ART = { "red", "red", "orange", "yellow", "green", "green", "green", "blue" }
local resolved = {}

local function db() return ns.db.panel end

-- name, reaction (1-8), value within the standing, size of the standing; nil without a watched faction
function Rep:Data()
    local R = C_Reputation
    if R and R.GetWatchedFactionData then
        local d = R.GetWatchedFactionData()
        if d and d.name and d.name ~= "" then
            local lo, hi = d.currentReactionThreshold or 0, d.nextReactionThreshold or 0
            local cur = d.currentStanding or 0
            if hi <= lo then return d.name, d.reaction or 4, 1, 1 end   -- top of the scale (Exalted)
            return d.name, d.reaction or 4, cur - lo, hi - lo
        end
    end
    if GetWatchedFactionInfo then
        local name, reaction, lo, hi, value = GetWatchedFactionInfo()
        if name and name ~= "" then
            if (hi or 0) <= (lo or 0) then return name, reaction or 4, 1, 1 end
            return name, reaction or 4, (value or 0) - lo, hi - lo
        end
    end
end

function Rep:Active()
    local p = db()
    return p.enabled and p.repBar and self:Data() ~= nil or false
end

local function color(reaction)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then return c.r, c.g, c.b end
    return 0.2, 0.6, 0.2
end

local function standing(reaction) return _G["FACTION_STANDING_LABEL" .. (reaction or 4)] or "?" end

local function num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(floor(n + 0.5)) or tostring(floor(n + 0.5)) end

local function decimal(v)
    local s = fmt("%.1f", v)
    if ns.language ~= "enUS" and ns.language ~= "zhCN" then s = s:gsub("%.", ",") end
    return s
end

-- part a..b (0..1) of an atlas, like the XP bar cuts its art; flat colour in the modern skin or without the art
local function crop(tex, key, a, b, reaction)
    local info = not Rep.modern and resolved[key]
    if info then
        tex:SetTexture(info.file or info.filename)
        local l, r = info.leftTexCoord, info.rightTexCoord
        tex:SetTexCoord(l + (r - l) * a, l + (r - l) * b, info.topTexCoord, info.bottomTexCoord)
        tex:SetVertexColor(1, 1, 1, 1)
    elseif key == "bg" then
        tex:SetColorTexture(0, 0, 0, Rep.modern and 0.55 or 0.75)
    else
        local r, g, bl = color(reaction or 4)
        tex:SetColorTexture(r * 0.8, g * 0.8, bl * 0.8, 1)
    end
end

function Rep:Create(parent)
    for key, names in pairs(ATLAS) do
        local _, info = ns.ResolveAtlas("rep-" .. key, names)
        resolved[key] = info
    end
    local f = CreateFrame("Frame", "ForeverQoLPanelRepBar", parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 3)
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.bg:SetAllPoints()
    f.bg2 = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.bg2:SetAllPoints()
    f.fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    -- the XP bar's shadow while the bar hangs from it: dark at the XP bar's side, fading out
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
    -- tick grooves like the XP bar's
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
    f:SetScript("OnEnter", function(s) Rep:ShowTooltip(s) end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- status text, on the bar or below it on a soft dark plate (like the XP bar's)
    local st = CreateFrame("Frame", nil, f)
    st:SetFrameLevel(f:GetFrameLevel() + 8)
    st:SetSize(10, 14)
    st.text = st:CreateFontString(nil, "OVERLAY")
    st.text:SetPoint("CENTER")
    st.text:SetShadowOffset(1, -1)
    st.text:SetShadowColor(0, 0, 0, 1)
    st.plate = {}
    for i = 1, 3 do
        local t = st:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(1, 1, 1, 1)
        st.plate[i] = t
    end
    st.plate[2]:SetPoint("TOPLEFT", st.text, "TOPLEFT", -4, 3)
    st.plate[2]:SetPoint("BOTTOMRIGHT", st.text, "BOTTOMRIGHT", 4, -3)
    st.plate[2]:SetVertexColor(0, 0, 0, 0.6)
    st.plate[1]:SetPoint("TOPRIGHT", st.plate[2], "TOPLEFT")
    st.plate[1]:SetPoint("BOTTOMRIGHT", st.plate[2], "BOTTOMLEFT")
    st.plate[1]:SetWidth(24)
    st.plate[3]:SetPoint("TOPLEFT", st.plate[2], "TOPRIGHT")
    st.plate[3]:SetPoint("BOTTOMLEFT", st.plate[2], "BOTTOMRIGHT")
    st.plate[3]:SetWidth(24)
    if st.plate[1].SetGradient and CreateColor then
        st.plate[1]:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6))
        st.plate[3]:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0))
    else
        st.plate[1]:SetVertexColor(0, 0, 0, 0.3)
        st.plate[3]:SetVertexColor(0, 0, 0, 0.3)
    end
    st:Hide()
    f.status = st
    f:Hide()
    self.frame = f
    self:ApplySkin(false)
    return f
end

function Rep:ApplySkin(modern)
    local f = self.frame
    if not f then return end
    self.modern = modern
    crop(f.bg, "bg", 0, 1)
    crop(f.bg2, "bg", 0, 1)
    f.bg2:SetShown(not modern and resolved.bg ~= nil)
    self.shown = nil
end

-- ctx: the holder of a bar set free (its own space), nil = the panel; no size hides the bar
function Rep:SetGeometry(x, y, w, h, ctx)
    local f = self.frame
    if not f then return end
    if not w then f:Hide(); f.status:Hide() return end
    local parent = ctx or ns.Dock
    if f:GetParent() ~= parent then
        f:SetParent(parent)
        f:SetFrameLevel(parent:GetFrameLevel() + 3)
    end
    self.free = ctx ~= nil
    f:ClearAllPoints()
    if ctx then f:SetPoint("TOPLEFT", ctx, "TOPLEFT", x, -y) else ns.Dock:Anchor(f, x, y) end
    self:SetShadow(false)
    f:SetSize(w, h)
    self.w, self.h = w, h
    f:Show()
    local step = db().repTicks or 0
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

-- The XP bar's shadow on the attached bar; flip: the XP bar lies below it (panel at the bottom of the screen).
function Rep:SetShadow(on, flip)
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
        -- vertical gradients run from the bottom colour to the top colour (no SetVertexColor after it: that would
        -- replace the gradient with plain white)
        if flip then t:SetGradient("VERTICAL", dark, clear) else t:SetGradient("VERTICAL", clear, dark) end
    else
        t:SetVertexColor(0, 0, 0, 0.35)
    end
    t:Show()
end

-- fill to k (0..1)
function Rep:Draw(k)
    local f = self.frame
    local _, reaction = self:Data()
    if not reaction or not self.w then return end
    k = max(0, min(1, k))
    if k <= 0.0005 then f.fill:Hide() return end
    f.fill:ClearAllPoints()
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetSize(self.w * k, self.h)
    crop(f.fill, ART[reaction] or "green", 0, k, reaction)
    f.fill:Show()
end

function Rep:Update()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    local name, reaction, value, size = self:Data()
    if not reaction then return end
    local k = size > 0 and value / size or 0
    -- a new faction or standing starts over; within a standing the fill glides and the gain flashes
    local same = self.lastName == name and self.lastReaction == reaction and self.shown
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
    self.lastName, self.lastReaction = name, reaction
    self:UpdateStatus()
end

function Rep:UpdateStatus()
    local f = self.frame
    local st = f and f.status
    if not st then return end
    local p = db()
    local name, reaction, value, size = self:Data()
    if not p.repText or not f:IsShown() or not name then st:Hide() return end
    local parts = {}
    if p.repTextName then parts[#parts + 1] = name end
    if p.repTextStanding then
        local r, g, b = color(reaction)
        parts[#parts + 1] = fmt("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, standing(reaction))
    end
    if size > 1 then
        if p.repTextValues then parts[#parts + 1] = num(value) .. " / " .. num(size) end
        if p.repTextPercent then parts[#parts + 1] = decimal(value / size * 100) .. " %" end
    end
    if #parts == 0 then st:Hide() return end
    local below = p.repTextPos == "below"
    st.text:SetFont(ns.FontFile(), p.repTextSize or 9, "OUTLINE")
    local gap = string.rep(" ", p.xpTextGap or 2)
    st.text:SetText(table.concat(parts, gap .. "|cffa0a0a0·|r" .. gap))
    st:ClearAllPoints()
    if below then
        if p.position == "bottom" and not self.free then st:SetPoint("BOTTOM", f, "TOP", 0, 6)
        else st:SetPoint("TOP", f, "BOTTOM", 0, -6) end
    else
        st:SetPoint("CENTER", f, "CENTER", 0, 0)
    end
    for _, t in ipairs(st.plate) do t:SetShown(below) end
    st:Show()
end

function Rep:ShowTooltip(owner)
    local name, reaction, value, size = self:Data()
    if not name then return end
    local L = ns.L
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(name, 1, 0.82, 0)
    local r, g, b = color(reaction)
    GameTooltip:AddLine(standing(reaction), r, g, b)
    if size > 1 then
        GameTooltip:AddLine(fmt("%s / %s (%s %%)", num(value), num(size), decimal(value / size * 100)), 1, 1, 1)
        local nextName = _G["FACTION_STANDING_LABEL" .. (reaction + 1)]
        if nextName then GameTooltip:AddLine(L.REP_LEFT:format(size - value, nextName), 0.62, 0.62, 0.62) end
    end
    GameTooltip:Show()
end

-- a faction watched or unwatched changes the panel's height
local wasActive
local function changed()
    local active = Rep:Active()
    if active ~= wasActive and ns.Dock.band then
        wasActive = active
        ns.Dock.width = nil
        ns.Dock:Relayout()
        ns.XP:UpdateStatus()
    end
    Rep:Update()
end
Rep.Changed = changed

ns.OnLogin(function()
    wasActive = Rep:Active()
    ns.On("UPDATE_FACTION", function() ns.Debug.Call("Rep", changed) end)
    ns.On("CHAT_MSG_COMBAT_FACTION_CHANGE", function() ns.Debug.Call("Rep", changed) end)
    -- reaching the highest level may move the bar into the XP bar's place
    ns.On("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, function()
        if ns.Dock.band then ns.Dock.width = nil; ns.Dock:Relayout() end
    end) end)
end)

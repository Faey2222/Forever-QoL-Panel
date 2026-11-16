local _, ns = ...

-- Action buttons that show their state:
--  * colours: the icon tinted when the target is out of range, you lack the mana (rage, energy) or it cannot be used
--    right now; each colour can be picked
--  * cooldown numbers on the buttons: font size, outline, shadow, a colour each for long, medium and short
--    cooldowns, and a minimum duration (the global cooldown gets none)
-- Only the look of Blizzard's buttons changes (their icon colour and a number on top): nothing secure is touched.
local BS = {}
ns.ButtonState = BS

local PREFIX = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

local function db() return ns.db.buttons end
local buttons = {}

local function iconOf(b) return rawget(b, "icon") or rawget(b, "Icon") or _G[(b:GetName() or "") .. "Icon"] end
local function cooldownOf(b) return rawget(b, "cooldown") or rawget(b, "Cooldown") or _G[(b:GetName() or "") .. "Cooldown"] end
local function actionOf(b)
    local a = rawget(b, "action")
    if type(a) ~= "number" and b.GetAttribute then a = b:GetAttribute("action") end
    if type(a) ~= "number" and ActionButton_GetPagedID then
        local ok, id = pcall(ActionButton_GetPagedID, b)
        if ok then a = id end
    end
    return type(a) == "number" and a or nil
end

-- State colours ------------------------------------------------------------------------

local WHITE = { 1, 1, 1 }
function BS:Tint(b)
    local icon = iconOf(b)
    if not icon then return end
    local d = db()
    if not d.range then
        if b.fqpTinted then icon:SetVertexColor(1, 1, 1); b.fqpTinted = nil end
        return
    end
    local a = actionOf(b)
    if not a or not (HasAction and HasAction(a)) then return end
    local usable, noMana = IsUsableAction(a)
    local inRange = IsActionInRange and IsActionInRange(a)
    local c = WHITE
    if inRange == false or inRange == 0 then c = d.colors.range
    elseif noMana then c = d.colors.mana
    elseif not usable then c = d.colors.unusable end
    icon:SetVertexColor(c[1], c[2], c[3])
    b.fqpTinted = c ~= WHITE or nil
end

-- Cooldown numbers ---------------------------------------------------------------------

local function textOf(b)
    if b.fqpCD then return b.fqpCD end
    local holder = CreateFrame("Frame", nil, b)
    holder:SetAllPoints(b)
    local cd = cooldownOf(b)
    holder:SetFrameLevel(((cd and cd:GetFrameLevel()) or b:GetFrameLevel()) + 3)
    -- a font from the start (setting text needs one), then the chosen look
    holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    holder.text:SetPoint("CENTER", 0, 0)
    b.fqpCD = holder
    BS:StyleText(b)
    return holder
end

function BS:StyleText(b)
    local d = db()
    local t = textOf(b).text
    t:SetFont(ns.FontFile(), d.cdSize or 16, d.cdOutline == "none" and "" or (d.cdOutline or "OUTLINE"))
    if d.cdShadow then t:SetShadowOffset(1, -1); t:SetShadowColor(0, 0, 0, 1)
    else t:SetShadowOffset(0, 0) end
end

local function format(remain, d)
    if remain >= 3600 then return math.ceil(remain / 3600) .. "h", d.cdColors.long end
    if remain >= 60 then return math.ceil(remain / 60) .. "m", d.cdColors.long end
    if remain >= (d.cdShort or 5) then return tostring(math.floor(remain + 0.5)), d.cdColors.mid end
    if d.cdDecimals then return string.format("%.1f", remain), d.cdColors.short end
    return tostring(math.ceil(remain)), d.cdColors.short
end
BS.Format = format

function BS:Count(b, now)
    local d = db()
    local holder = b.fqpCD
    local cd = cooldownOf(b)
    if not d.cd or not b.fqpStart then
        if holder then holder.text:SetText("") end
        return
    end
    local remain = b.fqpStart + b.fqpDur - now
    if remain <= 0 or b.fqpDur < (d.cdMin or 2) or not b:IsVisible() then
        if holder then holder.text:SetText("") end
        if remain <= 0 then b.fqpStart = nil end
        return
    end
    holder = textOf(b)
    local text, c = format(remain, d)
    holder.text:SetText(text)
    holder.text:SetTextColor(c[1], c[2], c[3])
    -- the game's own numbers would sit on top of ours
    if cd and cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
end

-- the button's cooldown as it is set (start and duration), for the numbers
local function watch(b)
    local cd = cooldownOf(b)
    if not cd or b.fqpWatched then return end
    b.fqpWatched = true
    hooksecurefunc(cd, "SetCooldown", function(_, start, duration)
        if start and duration and duration > 0 then b.fqpStart, b.fqpDur = start, duration
        else b.fqpStart = nil end
    end)
    if cd.Clear then hooksecurefunc(cd, "Clear", function() b.fqpStart = nil end) end
end

-- Preview (options) ---------------------------------------------------------------------

-- example buttons drawn with the current settings; kept so a setting change redraws them at once
function BS:Preview(w)
    self.preview = w
    local d = db()
    for _, b in ipairs(w.slots) do
        local def = b.def
        b.label:SetText(ns.L[def.label])
        local c = WHITE
        if d.range and def.state and def.state ~= "normal" then c = d.colors[def.state] end
        b.icon:SetVertexColor(c[1], c[2], c[3])
        if def.cd then
            b.shade:SetShown(true)
            local show = d.cd and def.cd >= 0 and (def.cd >= (d.cdMin or 2) or def.cd < 60)
            b.text:SetFont(ns.FontFile(), d.cdSize or 16, d.cdOutline == "none" and "" or (d.cdOutline or "OUTLINE"))
            if d.cdShadow then b.text:SetShadowOffset(1, -1); b.text:SetShadowColor(0, 0, 0, 1) else b.text:SetShadowOffset(0, 0) end
            local text, col = format(def.cd, d)
            b.text:SetText(d.cd and text or "")
            b.text:SetTextColor(col[1], col[2], col[3])
        else
            b.shade:SetShown(false)
            b.text:SetText("")
        end
    end
end

-- Setup --------------------------------------------------------------------------------

function BS:Collect()
    for _, prefix in ipairs(PREFIX) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b and not b.fqpKnown then
                b.fqpKnown = true
                buttons[#buttons + 1] = b
                watch(b)
                -- Blizzard colours the icon on its own updates: ours goes on top right after
                if b.UpdateUsable then hooksecurefunc(b, "UpdateUsable", function(self) BS:Tint(self) end) end
            end
        end
    end
end

-- after a setting changed: every button's look again
function BS:Refresh()
    if self.preview and self.preview:IsVisible() then self:Preview(self.preview) end
    for _, b in ipairs(buttons) do
        self:Tint(b)
        if b.fqpCD or db().cd then self:StyleText(b) end
        local cd = cooldownOf(b)
        if cd and cd.SetHideCountdownNumbers and not db().cd then cd:SetHideCountdownNumbers(false) end
    end
end

ns.OnLogin(function()
    BS:Collect()
    BS:Refresh()
    if ActionButton_UpdateUsable then hooksecurefunc("ActionButton_UpdateUsable", function(b) BS:Tint(b) end) end
    -- range changes without an event: looked at a few times a second, the numbers ten times
    local acc = 0
    C_Timer.NewTicker(0.1, function()
        local now = GetTime()
        acc = acc + 0.1
        local tint = acc >= 0.2
        if tint then acc = 0 end
        for _, b in ipairs(buttons) do
            if b:IsVisible() then
                if tint then BS:Tint(b) end
                BS:Count(b, now)
            end
        end
    end)
    -- bars that appear later (more bars switched on)
    ns.On("ACTIONBAR_SLOT_CHANGED", function() BS:Collect() end)
    ns.On("PLAYER_ENTERING_WORLD", function() BS:Collect(); BS:Refresh() end)
end)

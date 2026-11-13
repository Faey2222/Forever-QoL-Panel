local _, ns = ...

-- The XP bar in Forever's colours: blue = earned, dark blue = rested, black = nothing yet, gold = finished quests not
-- turned in yet, as a shimmer, glow, line or stripes (they pulse when that is enough for the next level). Optional: a preview of every quest
-- in the log.
local XP = {}
ns.XP = XP

-- Forever maps the plain names to its own "-c60" art through an atlas set; the "-c60" names themselves cannot be
-- looked up. Plain names first, the rest are fallbacks.
-- Forever's own bar is blue with a dark blue rested part (and no purple): its "rested" art (blue) is our earned
-- XP, its "prediction" art (dark blue) our rested XP. Both have the bar's rounded ends built in.
local ATLAS = {
    bg = { "ui-hud-experiencebar-background", "ui-hud-experiencebar-background-c60" },
    fill = { "ui-hud-experiencebar-fill-rested", "ui-hud-experiencebar-fill-rested-c60" },
    rested = { "ui-hud-experiencebar-fill-prediction", "ui-hud-experiencebar-fill-prediction-c60" },
    log = { "ui-hud-experiencebar-fill-reputation-faction-blue", "ui-hud-experiencebar-fill-reputation-faction-blue-c60" },
    gold = { "ui-hud-experiencebar-fill-artifactpower", "ui-hud-experiencebar-fill-artifactpower-c60" },
    pip = { "ui-hud-experiencebar-frame-pip", "ui-hud-experiencebar-frame-pip-c60" },
    tick = { "ui-hud-experiencebar-divider", "ui-hud-experiencebar-divider-c60" },
}
-- plain colours if the client knows none of the names
local FALLBACK = {
    bg = { 0, 0, 0, 0.75 }, fill = { 0.2, 0.45, 0.95, 1 }, rested = { 0.1, 0.2, 0.55, 1 }, log = { 0.3, 0.5, 0.75, 0.6 }, gold = { 1, 0.78, 0.2, 1 },
}
local GOLD = { 1, 0.78, 0.2 }
local TWEEN = 0.6
local BLIZZARD_FILL = 137012          -- Forever's own bar: Interface\TargetingFrame\UI-StatusBar, tinted (debug only)

local fmt, floor, max, min = string.format, math.floor, math.max, math.min
local resolved = {}   -- key -> atlas info

local function L() return ns.L end

local function num(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(floor(n + 0.5)) or tostring(floor(n + 0.5))
end

function XP.Duration(sec, short)
    if not sec or sec <= 0 or sec > 360000 then return "-" end
    local h, m = floor(sec / 3600), floor(sec % 3600 / 60)
    if short then
        if h > 0 then return fmt("%d:%02d h", h, m) end
        return fmt("%d min", max(1, m))
    end
    if h > 0 then return fmt(L().DURATION_HM, h, m) end
    return fmt(L().DURATION_M, max(1, m))
end

-- Shows the part a..b (0..1) of an atlas horizontally, like the client cuts its own status bars.
local MODERN = {
    -- the blue of Blizzard's own XP bar (its fill averages to this), rested the same blue translucent
    bg = { 0, 0, 0, 0.55 }, fill = { 0.1, 0.27, 0.76, 1 }, rested = { 0.1, 0.27, 0.76, 0.42 },
    log = { 0.6, 0.7, 0.85, 0.25 }, gold = { 0.9, 0.72, 0.25, 1 },
}

local function crop(tex, key, a, b)
    if XP.modern then
        local c = MODERN[key]
        if c then tex:SetColorTexture(c[1], c[2], c[3], c[4]) end
        return
    end
    local info = resolved[key]
    if not info then
        local c = FALLBACK[key]
        if c then tex:SetColorTexture(c[1], c[2], c[3], c[4]) end
        return
    end
    tex:SetTexture(info.file or info.filename)
    local l, r = info.leftTexCoord, info.rightTexCoord
    tex:SetTexCoord(l + (r - l) * a, l + (r - l) * b, info.topTexCoord, info.bottomTexCoord)
end

local function animated() return ns.db.panel.animations end

-- Session and level statistics -----------------------------------------------------

-- session numbers live in ns.Session() (kept over /reload); lastXP / lastMax only track changes
local stats = { lastXP = nil, lastMax = nil }

local function trackXP()
    local cur, mx = UnitXP("player") or 0, UnitXPMax("player") or 0
    local gained = 0
    if stats.lastXP then
        gained = cur - stats.lastXP
        if gained < 0 then gained = (stats.lastMax or 0) - stats.lastXP + cur end   -- level up in between
        if gained > 0 then
            local s = ns.Session()
            s.xp = s.xp + gained
            s.levelXP = s.levelXP + gained
        end
    end
    stats.lastXP, stats.lastMax = cur, mx
    return gained
end

-- XP per hour since the last level up (or since login): the base for the time to the next level.
function XP.PerHour()
    local s = ns.Session()
    local elapsed = time() - s.levelStart
    if elapsed < 60 or s.levelXP <= 0 then return nil end
    return s.levelXP / elapsed * 3600
end

function XP.TimeToLevel()
    local v = XP.PerHour()
    if not v then return nil end
    return ((UnitXPMax("player") or 0) - (UnitXP("player") or 0)) / v * 3600
end

function XP.SessionXP() return ns.Session().xp end

local function atMaxLevel()
    local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    return (UnitLevel("player") or 1) >= maxLevel
end
XP.AtMaxLevel = atMaxLevel

-- Quests ---------------------------------------------------------------------------

local busy
local function rewardXP(questID, index)
    if GetQuestLogRewardXP then
        if questID then
            local ok, xp = pcall(GetQuestLogRewardXP, questID)
            if ok and tonumber(xp) and xp > 0 then return xp end
        end
        -- older form: the reward of the selected quest
        if SelectQuestLogEntry and index then
            SelectQuestLogEntry(index)
            local ok, xp = pcall(GetQuestLogRewardXP)
            if ok and tonumber(xp) and xp > 0 then return xp end
        end
    end
    return 0
end

-- XP of the finished quests and of all quests in the log; the list { title, xp, done } is kept for the tooltip.
function XP.ScanQuests()
    if busy then return end
    busy = true
    local done, all, n, list = 0, 0, 0, {}
    local selected = GetQuestLogSelection and GetQuestLogSelection()
    local count = (GetNumQuestLogEntries and GetNumQuestLogEntries())
        or (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0
    for i = 1, count do
        local title, isHeader, isComplete, questID
        if GetQuestLogTitle then
            local t, _, _, h, _, c, _, id = GetQuestLogTitle(i)
            title, isHeader, isComplete, questID = t, h, c, id
        elseif C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then
                title, isHeader, questID = info.title, info.isHeader, info.questID
                isComplete = questID and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
            end
        end
        if title and not isHeader then
            local xp = rewardXP(questID, i)
            local finished = isComplete == 1 or isComplete == true
            all = all + xp
            if finished then done, n = done + xp, n + 1 end
            list[#list + 1] = { title, xp, finished }
        end
    end
    if selected and SelectQuestLogEntry then SelectQuestLogEntry(selected) end
    busy = false
    table.sort(list, function(a, b)
        if a[3] ~= b[3] then return a[3] end
        return a[2] > b[2]
    end)
    XP.computedAt = GetTime()   -- selecting log entries may fire QUEST_LOG_UPDATE; those echoes are ignored
    XP.cachedQuestXP, XP.cachedQuestCount, XP.cachedLogXP, XP.cachedQuestList = done, n, all, list
end

-- kept for the smoke test and older callers
function XP.CompletedQuests()
    XP.ScanQuests()
    return XP.cachedQuestXP or 0, XP.cachedQuestCount or 0
end

-- The bar ------------------------------------------------------------------------

function XP:Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 3)
    f:EnableMouse(true)
    self.frame = f

    for key, names in pairs(ATLAS) do
        local _, info = ns.ResolveAtlas("xp-" .. key, names)
        resolved[key] = info
    end

    -- Blizzard's bar background (black, 60 %) twice: dark with just a little transparency
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.bg:SetAllPoints()
    crop(f.bg, "bg", 0, 1)
    f.bg2 = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.bg2:SetAllPoints()
    crop(f.bg2, "bg", 0, 1)
    if not resolved.bg then f.bg2:Hide() end

    f.rested = f:CreateTexture(nil, "BORDER")
    f.rested:SetAlpha(1)
    f.log = f:CreateTexture(nil, "ARTWORK", nil, 0)
    f.log:SetAlpha(0.45)
    f.fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    -- finished quests, in one of several looks (setting questStyle)
    -- "veil": gold that fades downwards from a fine bright edge on top
    f.veil = f:CreateTexture(nil, "ARTWORK", nil, 2)
    f.veil:SetColorTexture(1, 1, 1, 1)
    f.veilTop = f:CreateTexture(nil, "ARTWORK", nil, 3)
    f.veilTop:SetColorTexture(1, 0.88, 0.5, 0.95)
    -- the part inside the bar's rounded right end: the gold fill atlas, whose round end is built in
    f.veilCap = f:CreateTexture(nil, "ARTWORK", nil, 2)
    f.veilParts = { f.veil, f.veilTop, f.veilCap }
    -- "frame": a fine gold outline around the part, barely filled
    f.frameParts = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "ARTWORK", nil, i == 4 and 2 or 3)
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        f.frameParts[i] = t
    end
    f.frameFill = f.frameParts[4]
    f.glow = f:CreateTexture(nil, "ARTWORK", nil, 2)           -- "glow": translucent gold bar
    f.qline = f:CreateTexture(nil, "ARTWORK", nil, 3)          -- "line": gold line along the bottom
    f.qline:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
    f.qlineHi = f:CreateTexture(nil, "ARTWORK", nil, 3)
    f.qlineHi:SetColorTexture(1, 0.95, 0.7, 0.6)
    f.stripes = f:CreateTexture(nil, "ARTWORK", nil, 2)        -- "stripes"
    f.stripes:SetTexture(ns.Tex("stripes"), "REPEAT", "REPEAT")
    f.stripes:SetHorizTile(true)
    f.stripes:SetVertTile(true)
    f.stripes:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.75)
    -- "shimmer": a faint gold bar with a soft light sweeping through it
    f.clip = CreateFrame("Frame", nil, f)
    f.clip:SetClipsChildren(true)
    f.sheen = CreateFrame("Frame", nil, f.clip)
    f.sheen:SetSize(70, 30)
    local s1 = f.sheen:CreateTexture(nil, "ARTWORK")
    local s2 = f.sheen:CreateTexture(nil, "ARTWORK")
    s1:SetPoint("TOPLEFT"); s1:SetPoint("BOTTOMRIGHT", f.sheen, "BOTTOM")
    s2:SetPoint("TOPRIGHT"); s2:SetPoint("BOTTOMLEFT", f.sheen, "BOTTOM")
    for _, t in ipairs({ s1, s2 }) do t:SetColorTexture(1, 1, 1, 1); t:SetBlendMode("ADD") end
    s1:SetGradient("HORIZONTAL", CreateColor(1, 0.85, 0.4, 0), CreateColor(1, 0.85, 0.4, 0.55))
    s2:SetGradient("HORIZONTAL", CreateColor(1, 0.85, 0.4, 0.55), CreateColor(1, 0.85, 0.4, 0))
    f.sweep = f.sheen:CreateAnimationGroup()
    f.sweep:SetLooping("REPEAT")
    f.sweepMove = f.sweep:CreateAnimation("Translation")
    f.sweepMove:SetDuration(2.2)
    f.sweepMove:SetSmoothing("IN_OUT")

    -- a short glow over newly gained XP
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

    -- tick marks every 5, 10, 20 or 25 %: an engraved groove (dark line + light edge), readable on blue and black
    f.ticks = {}
    for i = 1, 19 do
        local t = f:CreateTexture(nil, "ARTWORK", nil, 5)
        t:SetColorTexture(0, 0, 0, 0.85)
        t.light = f:CreateTexture(nil, "ARTWORK", nil, 5)
        t.light:SetColorTexture(1, 0.88, 0.62, 0.4)
        t.light:SetPoint("TOPLEFT", t, "TOPRIGHT")
        t.light:SetPoint("BOTTOMLEFT", t, "BOTTOMRIGHT")
        t.light:SetWidth(1)
        f.ticks[i] = t
    end

    f.pipR = f:CreateTexture(nil, "OVERLAY")
    f.pipQ = f:CreateTexture(nil, "OVERLAY")
    for _, t in ipairs({ f.pipR, f.pipQ }) do
        if resolved.pip then
            t:SetTexture(resolved.pip.file or resolved.pip.filename)
            t:SetTexCoord(resolved.pip.leftTexCoord, resolved.pip.rightTexCoord, resolved.pip.topTexCoord, resolved.pip.bottomTexCoord)
        else
            t:SetColorTexture(1, 1, 1, 0.8)
        end
        t:SetSize(resolved.pip and 10 or 2, 14)
    end
    f.pipQ:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], modern and 0.9 or 1)
    f.pipR:SetVertexColor(modern and 0.6 or 1, modern and 0.78 or 1, 1, modern and 0.7 or 1)

    -- enough XP for the level: the preview pulses (each look has its own animation)
    f.pulses = {}
    for _, t in ipairs({ f.glow, f.qline, f.stripes, f.clip, f.veil, f.frameFill }) do
        local g = t:CreateAnimationGroup()
        g:SetLooping("BOUNCE")
        local a = g:CreateAnimation("Alpha")
        a:SetFromAlpha(0.4)
        a:SetToAlpha(1)
        a:SetDuration(0.8)
        a:SetSmoothing("IN_OUT")
        f.pulses[t] = g
    end

    f:SetScript("OnEnter", function() XP:ShowTooltip() end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- status text ("12.428 / 23.100 · 53,8 % · 1:24 h to level"), on the bar or below it. Below, it sits on a soft
    -- dark plate that fades out at both ends, so it stays readable over any background.
    local st = CreateFrame("Frame", nil, f)
    st:SetFrameLevel(f:GetFrameLevel() + 8)
    st:SetSize(10, 16)
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
    -- the time to the next level changes without XP gains
    C_Timer.NewTicker(15, function() if ns.db.panel.xpText then ns.Debug.Call("XP:Status", XP.UpdateStatus, XP) end end)

    trackXP()
    ns.On("PLAYER_XP_UPDATE", function()
        local before = XP.shown
        if trackXP() > 0 then XP.gainFrom = before end
        XP:Update()
    end)
    ns.On("PLAYER_LEVEL_UP", function()
        local s = ns.Session()
        s.levelStart, s.levelXP = time(), 0
        XP.shown = 0
        XP:Update()
    end)
    ns.On("UPDATE_EXHAUSTION", function() XP:Update() end)
    ns.On("PLAYER_UPDATE_RESTING", function() XP:Update() end)
    ns.On("QUEST_LOG_UPDATE", function()
        if busy or XP.pending or GetTime() - (XP.computedAt or 0) < 0.5 then return end
        XP.pending = true
        C_Timer.After(0.3, function() XP.pending = false; XP.questsDirty = true; XP:Update() end)
    end)
    XP.questsDirty = true

    -- what the client knows about the atlases (debug data)
    local atlases = {}
    for key in pairs(ATLAS) do
        local info = resolved[key]
        atlases[key] = info and { name = ns.atlasUsed["xp-" .. key], file = info.file, filename = info.filename,
            l = info.leftTexCoord, r = info.rightTexCoord, t = info.topTexCoord, b = info.bottomTexCoord }
            or ns.atlasUsed["xp-" .. key]
    end
    ns.Debug.Set("atlases", atlases)
    return f
end

-- classic: Forever's bar art; modern: flat colours and thin pips
function XP:ApplySkin(modern)
    local f = self.frame
    if not f then return end
    self.modern = modern
    crop(f.bg, "bg", 0, 1)
    f.bg2:SetShown(not modern and resolved.bg ~= nil)
    for _, t in ipairs({ f.pipR, f.pipQ }) do
        if resolved.pip and not modern then
            t:SetTexture(resolved.pip.file or resolved.pip.filename)
            t:SetTexCoord(resolved.pip.leftTexCoord, resolved.pip.rightTexCoord, resolved.pip.topTexCoord, resolved.pip.bottomTexCoord)
            t:SetSize(10, 14)
        else
            t:SetColorTexture(1, 1, 1, 1)
            t:SetTexCoord(0, 1, 0, 1)
            t:SetSize(modern and 2 or 1, modern and math.max(2, (self.h or 10) - 2) or 14)
        end
    end
    f.pipQ:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
end

-- ctx: the holder of a bar set free (its own space), nil = the panel
function XP:SetGeometry(x, y, w, h, ctx)
    local f = self.frame
    local parent = ctx or ns.Dock
    if f:GetParent() ~= parent then f:SetParent(parent) end
    -- above the reputation bar and its border (+3, +4), below the bar borders on the rim (+6)
    f:SetFrameLevel(parent:GetFrameLevel() + 5)
    self.free = ctx ~= nil
    f:ClearAllPoints()
    if ctx then f:SetPoint("TOPLEFT", ctx, "TOPLEFT", x, -y) else ns.Dock:Anchor(f, x, y) end
    f:SetSize(w, h)
    self.w, self.h = w, h
    local step = ns.db.panel.ticks or 0
    local n = step > 0 and math.floor(100 / step - 0.5) or 0
    for i, t in ipairs(f.ticks) do
        if i <= n then
            t:ClearAllPoints()
            t:SetPoint("RIGHT", f, "LEFT", math.floor(w * i * step / 100 + 0.5), 0)
            if self.modern then
                -- inside the bar, clear of its border
                t:SetColorTexture(0, 0, 0, 0.3)
                t:SetSize(1, math.max(2, h - 4))
                t.light:Hide()
            else
                t:SetColorTexture(0, 0, 0, 0.85)
                t:SetSize(1, h - 3)
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

local function place(f, tex, a, b)
    local w = XP.w or 0
    if b - a <= 0.0005 or w <= 0 then tex:Hide() return false end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", f, "TOPLEFT", a * w, 0)
    tex:SetSize((b - a) * w, XP.h)
    tex:Show()
    return true
end

local function segment(f, tex, key, a, b)
    if place(f, tex, a, b) then crop(tex, key, a, b) end
end

local function pip(f, tex, at, show)
    if not show or at >= 0.995 then tex:Hide() return end
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", f, "LEFT", at * (XP.w or 0), 0)
    tex:Show()
end

-- The colour of Blizzard's own XP bar (it may change with the rested state), blue if it cannot be found.
function XP.FillColor()
    if XP.blizzardBar == nil then
        XP.blizzardBar = false
        local function walk(frame, depth)
            if not frame or depth > 6 or XP.blizzardBar then return end
            local t = frame.GetStatusBarTexture and frame:GetStatusBarTexture()
            if t and t.GetTexture and t:GetTexture() == BLIZZARD_FILL then XP.blizzardBar = frame return end
            for _, c in ipairs({ frame:GetChildren() }) do walk(c, depth + 1) end
        end
        walk(_G.MainStatusTrackingBarContainer or _G.StatusTrackingBarManager, 0)
    end
    local bar = XP.blizzardBar
    if bar and bar.GetStatusBarColor then
        local r, g, b = bar:GetStatusBarColor()
        if r then return r, g, b end
    end
    return nil
end

function XP:Update()
    ns.Debug.Call("XP:Update", self.UpdateBar, self)
    ns.Debug.Call("XP:Status", self.UpdateStatus, self)
end

-- "1.234,5" in languages that write a decimal comma
local function decimal(v)
    local s = fmt("%.1f", v)
    if ns.language ~= "enUS" and ns.language ~= "zhCN" then s = s:gsub("%.", ",") end
    return s
end

function XP:UpdateStatus()
    local f = self.frame
    local st = f and f.status
    if not st then return end
    local p = ns.db.panel
    local _, cur, mx, maxed = self:Targets()
    if not p.xpText or not p.xpbar or maxed or not f:IsShown() then st:Hide() return end
    local parts = {}
    if p.xpTextValues then parts[#parts + 1] = num(cur) .. " / " .. num(mx) end
    if p.xpTextPercent then parts[#parts + 1] = decimal(cur / mx * 100) .. " %" end
    if p.xpTextRested then
        local rest = GetXPExhaustion and GetXPExhaustion() or 0
        if rest and rest > 0 then parts[#parts + 1] = "|cff7fb2ff" .. L().XPTEXT_RESTED:format(num(rest)) .. "|r" end
    end
    if p.xpTextTime then
        local t = XP.TimeToLevel()
        if t then parts[#parts + 1] = L().XPTEXT_TIME:format(XP.Duration(t, true)) end
    end
    if #parts == 0 then st:Hide() return end
    local below = p.xpTextPos == "below"
    st.text:SetFont(ns.FontFile(), p.xpTextSize or (below and 11 or 10), "OUTLINE")
    local gap = string.rep(" ", p.xpTextGap or 2)
    st.text:SetText(table.concat(parts, gap .. "|cffa0a0a0·|r" .. gap))
    st:ClearAllPoints()
    if below then
        -- away from the screen edge: below the bar at the top, above it at the bottom; past the reputation strip
        local rep = ns.Rep and ns.Rep.frame
        local ref = rep and rep:IsShown() and (rep.status:IsShown() and ns.db.panel.repTextPos == "below" and rep.status or rep) or f
        if p.position == "bottom" and not self.free then st:SetPoint("BOTTOM", ref, "TOP", 0, 6)
        else st:SetPoint("TOP", ref, "BOTTOM", 0, -6) end
    else
        -- the classic fill has an empty row at its bottom edge, so its visible middle sits half a unit higher than the
        -- frame's; the flat modern bar fills the frame exactly
        st:SetPoint("CENTER", f, "CENTER", 0, XP.modern and 0 or -1)
    end
    for _, t in ipairs(st.plate) do t:SetShown(below) end
    st:Show()
end

-- Target values of the bar; the fill glides there (XP.shown) when animations are on.
function XP:Targets()
    local maxed = atMaxLevel()
    local cur, mx = UnitXP("player") or 0, max(1, UnitXPMax("player") or 1)
    local p = maxed and 1 or min(1, cur / mx)
    return p, cur, mx, maxed
end

function XP:UpdateBar()
    local f = self.frame
    if not f or not self.w then return end
    if self.questsDirty then
        self.questsDirty = false
        XP.ScanQuests()
    end
    local p = self:Targets()
    if self.shown == nil or not animated() or p < (self.shown or 0) then self.shown = p end
    if self.shown < p then
        -- glide to the new value
        local from, t = self.shown, 0
        local gainFrom = self.gainFrom
        self.gainFrom = nil
        if gainFrom and animated() then
            place(f, f.flash, gainFrom, p)
            f.flashAnim:Stop()
            f.flashAnim:Play()
        end
        f:SetScript("OnUpdate", function(_, elapsed)
            t = min(1, t + elapsed / TWEEN)
            local e = 1 - (1 - t) * (1 - t)
            XP.shown = from + (p - from) * e
            XP:Draw()
            if t >= 1 then f:SetScript("OnUpdate", nil) end
        end)
    end
    self:Draw()
    if GameTooltip:IsOwned(f) then self:ShowTooltip() end
end

function XP:Draw()
    local f = self.frame
    local panel = ns.db.panel
    local _, cur, mx, maxed = self:Targets()
    local p = self.shown or 0
    local rest = (not maxed and GetXPExhaustion and GetXPExhaustion()) or 0
    local q = (maxed or not panel.questPreview) and 0 or (XP.cachedQuestXP or 0)
    local all = (maxed or not panel.logPreview) and 0 or (XP.cachedLogXP or 0)
    local pr, pq, pl = min(1, p + rest / mx), min(1, p + q / mx), min(1, p + all / mx)

    segment(f, f.fill, "fill", 0, p)
    -- flat look: translucent blue and gold would mix to olive, so the rested part starts where the quest preview ends
    local q0 = (maxed or not panel.questPreview) and 0 or (XP.cachedQuestXP or 0)
    local restFrom = XP.modern and math.max(p, math.min(1, p + q0 / mx)) or p
    segment(f, f.rested, "rested", restFrom, math.max(restFrom, pr))
    segment(f, f.log, "log", p, pl)
    -- finished quests in the chosen look
    local style = panel.questStyle
    local active
    local ready = q > 0 and cur + q >= mx
    f.glow:Hide(); f.qline:Hide(); f.qlineHi:Hide(); f.stripes:Hide(); f.clip:Hide()
    for _, t in ipairs(f.veilParts) do t:Hide() end
    for _, t in ipairs(f.frameParts) do t:Hide() end
    if q > 0 and pq - p > 0.0005 then
        local w, h = XP.w or 0, XP.h or 15
        local x0, qw = p * w, (pq - p) * w
        -- straight-edged looks stop where the bar's rounded right end begins; a cap with the round end built in
        -- covers the rest, so a preview up to the level-up reaches the very end (the modern bar is square)
        local round = not XP.modern
        local qws = round and math.max(1, math.min(qw, w - h / 2 - x0)) or qw
        local capFrom = (x0 + qws) / w
        local function cap(alphaTop, alphaBottom)
            if not round or pq <= capFrom + 0.0005 then return false end
            segment(f, f.veilCap, "gold", capFrom, pq)
            f.veilCap:SetGradient("VERTICAL", CreateColor(1, 1, 1, alphaBottom), CreateColor(1, 1, 1, alphaTop))
            return true
        end
        -- static looks: when the quests are enough for the level they simply shine brighter
        local k = ready and 1 or 0.7
        if style == "veil" or style == nil then
            active = f.veil
            f.veil:ClearAllPoints(); f.veil:SetPoint("TOPLEFT", f, "TOPLEFT", x0, 0); f.veil:SetSize(qws, h); f.veil:Show()
            if XP.modern then
                f.veil:SetGradient("VERTICAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.4 * k),
                    CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.4 * k))
            else
                f.veil:SetGradient("VERTICAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.05 * k),
                    CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.55 * k))
            end
            f.veilTop:ClearAllPoints()
            f.veilTop:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -1)
            f.veilTop:SetSize(qws, 1)
            f.veilTop:SetAlpha(k)
            f.veilTop:SetShown(not XP.modern)
            cap(0.55 * k, 0.05 * k)
        elseif style == "frame" then
            active = f.frameFill
            local fT, fB, fR, fill = unpack(f.frameParts)
            fT:ClearAllPoints(); fT:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -1); fT:SetSize(qws, 1)
            fB:ClearAllPoints(); fB:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x0, 1); fB:SetSize(qws, 1)
            fR:ClearAllPoints(); fR:SetPoint("TOPRIGHT", f, "TOPLEFT", x0 + qws, -1); fR:SetSize(1, h - 2)
            fill:ClearAllPoints(); fill:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -1); fill:SetSize(qws, h - 2)
            fill:SetAlpha(ready and 0.22 or 0.1)
            for _, t in ipairs({ fT, fB, fR }) do t:SetAlpha(k) end
            for _, t in ipairs(f.frameParts) do t:Show() end
            -- reaching the round end: no straight right edge, the fill runs on into the end
            if cap(ready and 0.22 or 0.1, ready and 0.22 or 0.1) then fR:Hide() end
        elseif style == "line" then
            active = f.qline
            f.qline:ClearAllPoints()
            f.qline:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x0, 2)
            f.qline:SetSize(qws, 2)
            f.qlineHi:ClearAllPoints()
            f.qlineHi:SetPoint("BOTTOMLEFT", f.qline, "TOPLEFT")
            f.qlineHi:SetSize(qws, 1)
            f.qline:Show(); f.qlineHi:Show()
        elseif style == "stripes" then
            active = f.stripes
            place(f, f.stripes, p, pq)
            f.stripes:SetTexCoord(0, qw / 12, 0, h / 12)
        else
            segment(f, f.glow, "gold", p, pq)
            f.glow:SetAlpha(style == "shimmer" and 0.22 or 0.42)
            active = f.glow
            if style == "shimmer" then
                active = f.clip
                f.clip:ClearAllPoints()
                f.clip:SetPoint("TOPLEFT", f, "TOPLEFT", x0, 0)
                f.clip:SetSize(qw, h)
                f.clip:Show()
                f.sheen:ClearAllPoints()
                f.sheen:SetPoint("RIGHT", f.clip, "LEFT", 0, 0)
                f.sheen:SetHeight(h)
                if f.sweepWidth ~= qw then
                    f.sweepWidth = qw
                    f.sweep:Stop()
                    f.sweepMove:SetOffset(qw + 70, 0)
                end
                if animated() then
                    if not f.sweep:IsPlaying() then f.sweep:Play() end
                else
                    f.sweep:Stop()
                    f.sheen:ClearAllPoints()
                    f.sheen:SetPoint("CENTER", f.clip, "CENTER")
                end
            end
        end
    end
    if active ~= f.clip then f.sweep:Stop() end
    pip(f, f.pipR, pr, rest > 0)
    pip(f, f.pipQ, pq, q > 0)

    for t, g in pairs(f.pulses) do
        if t == active and ready and animated() and panel.readyPulse then
            if not g:IsPlaying() then g:Play() end
        else
            g:Stop()
            if t == f.glow then
                t:SetAlpha((style == "shimmer" and 0.22 or 0.42) * (ready and 1.4 or 1))
            elseif t ~= f.veil and t ~= f.frameFill then
                t:SetAlpha(1)
            end
        end
    end
end

function XP:ShowTooltip()
    local L = ns.L
    local f = self.frame
    local tt = GameTooltip
    tt:SetOwner(f, ns.TipPoint())
    local level = UnitLevel("player") or 1
    tt:AddLine(fmt(L.LEVEL_N, level), 1, 1, 1)
    if atMaxLevel() then
        tt:AddLine(L.MAX_LEVEL, 0.62, 0.62, 0.62)
        tt:Show()
        return
    end
    local cur, mx = UnitXP("player") or 0, max(1, UnitXPMax("player") or 1)
    tt:AddDoubleLine(L.EXPERIENCE, fmt("%s / %s (%.1f %%)", num(cur), num(mx), cur / mx * 100), 1, 0.82, 0, 1, 1, 1)
    local rest = GetXPExhaustion and GetXPExhaustion() or 0
    if rest > 0 then tt:AddDoubleLine(L.RESTED, "+" .. num(rest), 0.35, 0.5, 1, 0.35, 0.5, 1) end
    tt:AddLine(" ")
    local perHour = XP.PerHour()
    tt:AddDoubleLine(L.XP_SESSION, num(ns.Session().xp), 1, 0.82, 0, 1, 1, 1)
    tt:AddDoubleLine(L.XP_PER_HOUR, perHour and num(perHour) or "-", 1, 0.82, 0, 1, 1, 1)
    tt:AddDoubleLine(fmt(L.TIME_TO_LEVEL, level + 1), XP.Duration(XP.TimeToLevel()), 1, 0.82, 0, 1, 1, 1)
    tt:AddLine(" ")
    local q, n, all, list = XP.cachedQuestXP or 0, XP.cachedQuestCount or 0, XP.cachedLogXP or 0, XP.cachedQuestList or {}
    if n > 0 then
        tt:AddDoubleLine(fmt(L.QUESTS_DONE, n), "+" .. num(q), GOLD[1], GOLD[2], GOLD[3], GOLD[1], GOLD[2], GOLD[3])
        for _, e in ipairs(list) do
            if e[3] then tt:AddDoubleLine("   " .. e[1], "+" .. num(e[2]), 0.62, 0.62, 0.62, 0.62, 0.62, 0.62) end
        end
        if cur + q >= mx then
            tt:AddLine(fmt(L.QUESTS_ENOUGH, level + 1, num(cur + q - mx)), 0.12, 1, 0)
        else
            tt:AddLine(fmt(L.QUESTS_MISSING, num(mx - cur - q)), 1, 0.13, 0.13)
        end
    else
        tt:AddLine(L.QUESTS_NONE, 0.62, 0.62, 0.62)
    end
    if #list > n then
        tt:AddDoubleLine(fmt(L.QUESTS_LOG, #list), "+" .. num(all), 0.45, 0.6, 1, 0.45, 0.6, 1)
    end
    tt:Show()
end

-- Where the bar ended up and what it shows (debug data, a few seconds after login).
function XP:Describe()
    local f = self.frame
    if not f then return end
    local function tex(t)
        return { shown = t:IsShown(), w = t:GetWidth(), h = t:GetHeight(), file = t:GetTexture(),
            alpha = t:GetAlpha(), coords = { t:GetTexCoord() } }
    end
    ns.Debug.Set("bar", {
        left = f:GetLeft(), top = f:GetTop(), w = f:GetWidth(), h = f:GetHeight(), visible = f:IsVisible(),
        alpha = f:GetEffectiveAlpha(), level = f:GetFrameLevel(), strata = f:GetFrameStrata(),
        bg = tex(f.bg), fill = tex(f.fill), rested = tex(f.rested), log = tex(f.log), stripes = tex(f.stripes),
        xp = { UnitXP("player"), UnitXPMax("player"), GetXPExhaustion and GetXPExhaustion(), XP.cachedQuestXP, XP.cachedLogXP },
    })
    -- the atlases Blizzard's own bar uses, to compare
    local seen, found = {}, {}
    local function walk(frame, depth)
        if not frame or seen[frame] or depth > 6 then return end
        seen[frame] = true
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetAtlas and r:GetAtlas() then found[#found + 1] = r:GetAtlas() end
        end
        if frame.GetStatusBarTexture and frame:GetStatusBarTexture() then
            local t = frame:GetStatusBarTexture()
            found[#found + 1] = "statusbar: " .. tostring(t.GetAtlas and t:GetAtlas() or t:GetTexture())
        end
        for _, c in ipairs({ frame:GetChildren() }) do walk(c, depth + 1) end
    end
    walk(_G.MainStatusTrackingBarContainer or _G.StatusTrackingBarManager, 0)
    ns.Debug.Set("blizzardBar", found)
    ns.Debug.Set("fillColor", { XP.FillColor() })
    ns.Debug.Set("atlasUsed", ns.atlasUsed)
end

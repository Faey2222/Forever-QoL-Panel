local _, ns = ...

-- Quest markers on nameplates: units your quests still need get Blizzard's crosshair icon (sword = kill, hand = loot),
-- optionally with the progress ("3/8"). Which unit belongs to which objective comes from the unit's tooltip data;
-- kind and progress come from the quest log (current even when the tooltip is stale). Where the game hides tooltip
-- lines (instances, combat), C_QuestLog.UnitIsRelatedToActiveQuest still says yes or no.
local N = { shown = {}, marks = {} }
ns.Nameplates = N

local function db() return ns.db.nameplates end
local function secret(v) return ns.Secret(v) end

local KILL, LOOT = "Crosshair_Attack_32", "Crosshair_pickup_32"
local FALLBACK = "Interface\\GossipFrame\\AvailableQuestIcon"

-- All "n/m" counts of a line; the one at the start or end is the objective's (a digit inside a name is not).
local function countOf(text)
    local pairs_ = {}
    for have, need in text:gmatch("(%d+)%s*/%s*(%d+)") do pairs_[#pairs_ + 1] = { tonumber(have), tonumber(need) } end
    if #pairs_ == 0 then return nil end
    local pick = text:find("^%s*%d") and pairs_[1] or pairs_[#pairs_]
    return pick[1], pick[2]
end

-- Comparable form of an objective: the words without count, blanks and punctuation, so "Sanglier tués : 3/8" and
-- "Sanglier tués 3/8" are equal (letters of any script stay).
local function key(text)
    local words = {}
    for chunk in text:lower():gsub("%d+%s*/%s*%d+", " "):gmatch("[^%p%s]+") do words[#words + 1] = chunk end
    return table.concat(words)
end

local function logObjective(text)
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return nil end
    local wanted, loose = key(text), nil
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                if o.text == text then return o end
                if not loose and o.text and wanted ~= "" and key(o.text) == wanted then loose = o end
            end
        end
    end
    return loose
end

-- In a group the tooltip lists each member's objectives under their name. A Forever character has a first and a last
-- name, which UnitName returns apart; the header may show them joined by a space or a dash.
local function isMe(header)
    local name = header:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^[%s%-]*(.-)[%s:]*$")
    local first, last = UnitName("player")
    if name == first then return true end
    if not last or last == "" then return false end
    return name == first .. " " .. last or name == first .. "-" .. last
end

-- The words of the client's kill objective format ("%s slain: %d/%d" -> "slain"): a line with one of them is a kill.
local killWords
local function isKill(text)
    if not killWords then
        killWords = {}
        local fmt = (QUEST_MONSTERS_KILLED or ""):gsub("|4[^;]*;", " "):gsub("%%%d*%$?[sd]", " ")
        for word in fmt:lower():gmatch("[^%p%s%d]+") do
            if #word >= 3 then killWords[#killWords + 1] = word end
        end
    end
    local lower = text:lower()
    for _, word in ipairs(killWords) do
        if lower:find(word, 1, true) then return true end
    end
    return false
end

-- kind ("kill"/"loot"), progress text; nil when the unit is not needed; "secret" when the lines are hidden
local function questInfo(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" then return nil end
    -- some clients keep the line fields in args until they are surfaced
    if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, data) end
    local LINE = Enum and Enum.TooltipDataLineType or {}
    local mine, lines = true, 0
    for _, line in ipairs(data.lines or {}) do
        if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
        lines = lines + 1
        if secret(line.leftText) or secret(line.type) then return nil, nil, "secret" end
        if LINE.QuestPlayer and line.type == LINE.QuestPlayer and line.leftText then
            mine = isMe(line.leftText)
        elseif mine and LINE.QuestObjective and line.type == LINE.QuestObjective and line.leftText then
            local text = line.leftText
            local have, need = countOf(text)
            local o = logObjective(text)
            if o and o.numRequired and o.numRequired > 1 and o.numFulfilled then have, need = o.numFulfilled, o.numRequired end
            local done = (o and o.finished) or line.completed or (have and need and have >= need)
            if not done then
                local kind = (o and o.type == "monster") and "kill" or ((o and o.type) and "loot") or nil
                -- no log match: the words of the client's kill format decide
                if not kind then kind = isKill(text) and "kill" or "loot" end
                return kind, have and (have .. "/" .. need) or ""
            end
        end
    end
    N.lastLines = lines
    return nil
end

-- the health bar (Blizzard_NamePlates, retail and Forever); the plate when another nameplate addon replaced it
local function barOf(plate)
    local uf = rawget(plate, "UnitFrame")
    local bar = uf and rawget(uf, "HealthBarsContainer")
    return type(bar) == "table" and bar.GetObjectType and bar or plate
end

-- Forever's level badge right of the bar, when shown: the plate's right end is then the badge
local function edgeOf(plate)
    local uf = rawget(plate, "UnitFrame")
    local lvl = uf and rawget(uf, "PlayerLevelDiffFrame")
    if type(lvl) ~= "table" or not lvl.IsShown then return nil end
    local ok, shown = pcall(lvl.IsShown, lvl)
    return ok and shown == true and lvl or nil
end

local function markFor(plate)
    local m = N.marks[plate]
    if m then return m end
    m = CreateFrame("Frame", nil, plate)
    m:SetSize(20, 20)
    m:SetFrameLevel(plate:GetFrameLevel() + 10)
    m.icon = m:CreateTexture(nil, "OVERLAY")
    m.icon:SetAllPoints()
    m.text = m:CreateFontString(nil, "OVERLAY")
    m.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    m.text:SetTextColor(1, 0.82, 0)
    m:Hide()
    N.marks[plate] = m
    return m
end

-- spots around the health bar: mark point, bar point, base offset, side of the progress text
local SPOTS = {
    left = { "RIGHT", "LEFT", -4, 0, "LEFT" },
    right = { "LEFT", "RIGHT", 4, 0, "RIGHT" },
    top = { "BOTTOM", "TOP", 0, 14, "RIGHT" },
    topleft = { "BOTTOMLEFT", "TOPLEFT", 0, 14, "RIGHT" },
    topright = { "BOTTOMRIGHT", "TOPRIGHT", 0, 14, "LEFT" },
}

local function place(m, plate)
    local d = db()
    local spot = SPOTS[d.position] or SPOTS.left
    local bar = barOf(plate)
    -- on the right, the level badge is the plate's end
    local anchor = (d.position == "right" or d.position == "topright") and edgeOf(plate) or bar
    local size = d.size or 20
    m:SetSize(size, size)
    m:ClearAllPoints()
    m:SetPoint(spot[1], anchor, spot[2], spot[3] + (d.x or 0), spot[4] + (d.y or 0))
    m.text:ClearAllPoints()
    m.text:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(size * 0.5 + 0.5)), "OUTLINE")
    if spot[5] == "LEFT" then m.text:SetPoint("RIGHT", m, "LEFT", -1, 0) else m.text:SetPoint("LEFT", m, "RIGHT", 1, 0) end
end

local function setIcon(m, kind)
    local atlas = kind == "kill" and KILL or LOOT
    if not (m.icon.SetAtlas and pcall(m.icon.SetAtlas, m.icon, atlas)) or not m.icon:GetAtlas() then
        m.icon:SetTexture(FALLBACK)
    end
end

function N:Update(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local m = markFor(plate)
    if not db().enabled or UnitIsPlayer(unit) or UnitIsDead(unit) then m:Hide() return end
    place(m, plate)
    local ok, kind, progress, hidden = pcall(questInfo, unit)
    if ok and not hidden then
        if kind then
            setIcon(m, kind)
            m.text:SetText(db().progress and progress or "")
            m:Show()
        else
            m:Hide()
        end
        ns.Debug.Set("nameplate", { unit = unit, lines = N.lastLines, kind = tostring(kind), hidden = false })
        return
    end
    -- lines hidden: a plain yes/no from the quest log, no kind or progress
    local related = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest and C_QuestLog.UnitIsRelatedToActiveQuest(unit)
    setIcon(m, "loot")
    m.text:SetText("")
    if secret(related) then
        -- a secret boolean can't be branched on, but SetShown may take it
        if not pcall(m.SetShown, m, related) then m:Hide() end
    else
        m:SetShown(related and true or false)
    end
    ns.Debug.Set("nameplate", { unit = unit, hidden = true, error = not ok and tostring(kind) or nil })
end

function N:UpdateAll()
    for unit in pairs(self.shown) do ns.Debug.Call("Nameplates", self.Update, self, unit) end
end

ns.OnLogin(function()
    ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
        N.shown[unit] = true
        ns.Debug.Call("Nameplates", N.Update, N, unit)
        -- the tooltip data of a new plate is sometimes not filled yet
        C_Timer.After(0.4, function() if N.shown[unit] then ns.Debug.Call("Nameplates", N.Update, N, unit) end end)
    end)
    ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        N.shown[unit] = nil
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
        if plate and N.marks[plate] then N.marks[plate]:Hide() end
    end)
    local pending
    local function later()
        if pending then return end
        pending = true
        C_Timer.After(0.3, function() pending = false; N:UpdateAll() end)
    end
    ns.On("QUEST_LOG_UPDATE", later)
    ns.On("UNIT_QUEST_LOG_CHANGED", later)
    ns.On("PLAYER_REGEN_ENABLED", later)
    ns.On("UNIT_HEALTH", function(_, unit) if N.shown[unit] and UnitIsDead(unit) then N:Update(unit) end end)
end)

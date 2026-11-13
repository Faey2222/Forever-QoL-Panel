local _, ns = ...

-- Tooltip additions: sell value, how many of an item each character has (bags and bank, same realm and faction),
-- and the skill an herb, a mineral vein or a skinnable creature needs, coloured by your own skill.
local T = {}
ns.Tooltip = T

local function db() return ns.db.tooltip end
local function on(key) return db().enabled and db()[key] end
local L = setmetatable({}, { __index = function(_, k) return ns.L[k] end })
local LINE = Enum and Enum.TooltipDataLineType or {}

local function money(c) return ns.Money(c) end

-- Item counts per character --------------------------------------------------------

local CC = C_Container
local function slots(bag) return (CC and CC.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function itemAt(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        return info and info.itemID, info and info.stackCount
    end
    local _, count, _, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
    return id, count
end

local function me()
    local realm = GetRealmName() or "?"
    local key = (UnitFactionGroup("player") or "?") .. ":" .. (UnitName("player") or "?")
    ns.db.items[realm] = ns.db.items[realm] or {}
    local c = ns.db.items[realm][key]
    if not c then
        c = { bags = {}, bank = {} }
        ns.db.items[realm][key] = c
    end
    c.class = select(2, UnitClass("player"))
    return c, realm
end

local function count(bags)
    local t = {}
    for _, bag in ipairs(bags) do
        for slot = 1, slots(bag) do
            local id, n = itemAt(bag, slot)
            if id then t[id] = (t[id] or 0) + (n or 1) end
        end
    end
    return t
end

local BI = Enum and Enum.BagIndex or {}
local function bankBags()
    local list = { BI.Bank or -1 }
    local first = BI.BankBag_1 or (BI.ReagentBag and 6 or 5)
    for i = 0, 6 do list[#list + 1] = first + i end
    return list
end

function T:ScanBags()
    me().bags = count({ 0, 1, 2, 3, 4, BI.ReagentBag or 5 })
end

function T:ScanBank()
    me().bank = count(bankBags())
end

local function countLines(tt, id)
    local _, realm = me()
    local faction = UnitFactionGroup("player") or "?"
    local rows, total = {}, 0
    for key, c in pairs(ns.db.items[realm] or {}) do
        local f, name = key:match("^(.-):(.+)$")
        if f == faction then
            local b, k = c.bags[id] or 0, c.bank[id] or 0
            if b + k > 0 then
                rows[#rows + 1] = { name, c.class, b, k }
                total = total + b + k
            end
        end
    end
    if #rows == 0 then return end
    table.sort(rows, function(a, b) return a[3] + a[4] > b[3] + b[4] end)
    tt:AddLine(" ")
    for _, r in ipairs(rows) do
        local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[r[2] or ""]
        local where = {}
        if r[3] > 0 then where[#where + 1] = L.TT_BAGS:format(r[3]) end
        if r[4] > 0 then where[#where + 1] = L.TT_BANK:format(r[4]) end
        tt:AddDoubleLine(r[1], (r[3] + r[4]) .. "  |cffa0a0a0(" .. table.concat(where, ", ") .. ")|r",
            col and col.r or 1, col and col.g or 1, col and col.b or 1, 1, 1, 1)
    end
    if #rows > 1 then tt:AddDoubleLine(L.TOTAL, total, 1, 0.82, 0, 1, 1, 1) end
end

-- Sell value --------------------------------------------------------------------

local function stackOf(tt)
    local owner = tt:GetOwner()
    if not owner then return 1 end
    local n = owner.count
    if n == nil and owner.Count then n = owner.Count:GetText() end
    if ns.Secret(n) then return 1 end
    return tonumber(n) or 1
end

local function hasSellLine(data)
    for _, line in ipairs(data and data.lines or {}) do
        if LINE.SellPrice and line.type == LINE.SellPrice then return true end
    end
end

function T:Item(tt, data)
    if not db().enabled or tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    local id = data and data.id
    if not id then
        local _, link = tt:GetItem()
        id = link and tonumber(link:match("item:(%d+)"))
    end
    if not id or ns.Secret(id) then return end
    if on("sellValue") and not hasSellLine(data) then
        local price = select(11, ns.ItemInfo(id)) or 0
        if price > 0 then
            local n = stackOf(tt)
            local text = money(price)
            if n > 1 then text = money(price * n) .. "  |cffa0a0a0(" .. money(price) .. ")|r" end
            tt:AddDoubleLine(L.TT_SELL, text, 1, 0.82, 0, 1, 1, 1)
        end
    end
    if on("counts") then countLines(tt, id) end
end

-- Gathering skill -------------------------------------------------------------------

-- herbs: the node is named like the herb item, so the item names (any client language) find them
local HERBS = {
    [2447] = 1, [765] = 1, [2449] = 15, [785] = 50, [2450] = 70, [3820] = 85, [2453] = 100, [3355] = 115, [3369] = 120,
    [3356] = 125, [3357] = 150, [3818] = 160, [3821] = 170, [3358] = 185, [3819] = 195, [4625] = 205, [8831] = 210,
    [8836] = 220, [8838] = 230, [8839] = 235, [8845] = 245, [8846] = 250, [13464] = 260, [13463] = 270, [13465] = 280,
    [13466] = 285, [13467] = 290, [13468] = 300,
}
-- mineral veins: node names (English, German)
local VEINS = {
    { 1, "Copper Vein", "Kupferader" }, { 65, "Tin Vein", "Zinnader" }, { 65, "Incendicite Mineral Vein", "Pyrophormineralvene" },
    { 75, "Silver Vein", "Silberader" }, { 75, "Lesser Bloodstone Deposit", "Geringe Blutsteinablagerung" },
    { 125, "Iron Deposit", "Eisenvorkommen" }, { 150, "Indurium Mineral Vein", "Induriummineralvene" },
    { 155, "Gold Vein", "Goldader" }, { 175, "Mithril Deposit", "Mithrilablagerung" },
    { 230, "Truesilver Deposit", "Echtsilberablagerung" }, { 230, "Dark Iron Deposit", "Dunkeleisenablagerung" },
    { 245, "Small Thorium Vein", "Kleine Thoriumader" }, { 275, "Rich Thorium Vein", "Reiche Thoriumader" },
}

local nodeMap, nodeMissing
local function nodes()
    if nodeMap and not nodeMissing then return nodeMap end
    nodeMap, nodeMissing = {}, false
    for id, skill in pairs(HERBS) do
        local n = ns.ItemInfo(id)
        if n then nodeMap[#nodeMap + 1] = { n, skill, "herb" } else nodeMissing = true end
    end
    for _, v in ipairs(VEINS) do
        nodeMap[#nodeMap + 1] = { v[2], v[1], "mine" }
        nodeMap[#nodeMap + 1] = { v[3], v[1], "mine" }
    end
    -- longest names first, so "Rich Thorium Vein" wins over "Thorium Vein" inside "Ooze Covered Rich Thorium Vein"
    table.sort(nodeMap, function(a, b) return #a[1] > #b[1] end)
    return nodeMap
end

-- My rank in a profession. The profession list by skill line ID first (independent of language and of collapsed
-- headers in the skill window), the skill window's lines by name only where the client has no profession list.
-- nil = unknown (shown neutral, never as "too low").
local PROFESSION = { herb = 2372, mine = 2575, skin = 8613 }
local SKILL_LINE = { herb = 182, mine = 186, skin = 393 }
local function rank(kind)
    local wanted = ns.SpellName(PROFESSION[kind])
    if GetProfessions and GetProfessionInfo then
        local found = false
        for _, index in pairs({ GetProfessions() }) do
            if index then
                found = true
                local name, _, r, _, _, _, line = GetProfessionInfo(index)
                if line == SKILL_LINE[kind] or (name and name == wanted) then return r, name or wanted end
            end
        end
        if found then return 0, wanted end
    end
    if not wanted or not GetNumSkillLines then return nil, wanted end
    local headers = 0
    for i = 1, GetNumSkillLines() do
        local n, header, expanded, r = GetSkillLineInfo(i)
        if header and not expanded then headers = headers + 1 end
        if not header and n == wanted then return r, wanted end
    end
    -- a collapsed header may hide it
    if headers > 0 then return nil, wanted end
    return 0, wanted
end

local function skillColor(mine, need)
    if not mine then return 0.8, 0.8, 0.8 end
    if mine < need then return 1, 0.13, 0.13 end
    if mine < need + 25 then return 1, 0.5, 0.25 end
    if mine < need + 50 then return 1, 1, 0 end
    if mine < need + 100 then return 0.25, 0.75, 0.25 end
    return 0.5, 0.5, 0.5
end

local function skillLine(tt, kind, need)
    local mine, prof = rank(kind)
    ns.Debug.Set("gatherSkill", { kind = kind, mine = mine, need = need, prof = prof,
        api = GetProfessions and "professions" or GetNumSkillLines and "skilllines" or "none" })
    local r, g, b = skillColor(mine, need)
    tt:AddLine(L.TT_SKILL:format(prof or "?", need), r, g, b)
    tt:Show()
end

function T:Object(tt)
    if not on("gather") or tt.fqpGather then return end
    local first = _G[tt:GetName() .. "TextLeft1"]
    local text = first and first:GetText()
    if not text or ns.Secret(text) or tt:GetUnit() or tt:GetItem() then return end
    for _, n in ipairs(nodes()) do
        if text == n[1] or text:find(n[1], 1, true) then
            tt.fqpGather = true
            skillLine(tt, n[3], n[2])
            return
        end
    end
end

function T:Unit(tt, data)
    if not on("gather") or tt.fqpGather then return end
    local _, unit = tt:GetUnit()
    if not unit or ns.Secret(unit) or not UnitIsDead(unit) or UnitIsPlayer(unit) then return end
    local skinnable = false
    for _, line in ipairs(data and data.lines or {}) do
        if not ns.Secret(line.leftText) and line.leftText == UNIT_SKINNABLE_LEATHER then skinnable = true end
    end
    if not skinnable then return end
    local level = UnitLevel(unit) or 1
    local need = level <= 10 and 1 or level <= 20 and (level - 10) * 10 or level * 5
    tt.fqpGather = true
    skillLine(tt, "skin", need)
end

ns.OnLogin(function()
    -- herb names come from the item cache
    for id in pairs(HERBS) do
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data) ns.Debug.Call("Tooltip", T.Item, T, tt, data) end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data) ns.Debug.Call("Tooltip", T.Unit, T, tt, data) end)
    elseif GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt) T:Item(tt) end)
    end
    GameTooltip:HookScript("OnShow", function(tt) ns.Debug.Call("Tooltip", T.Object, T, tt) end)
    GameTooltip:HookScript("OnTooltipCleared", function(tt) tt.fqpGather = nil end)
    T:ScanBags()
    ns.On("BAG_UPDATE_DELAYED", function() T:ScanBags() end)
    -- the bank can only be read while it is open
    ns.On("BANKFRAME_OPENED", function() T.bankOpen = true; T:ScanBank() end)
    ns.On("BANKFRAME_CLOSED", function() T.bankOpen = false end)
    ns.On("PLAYERBANKSLOTS_CHANGED", function() if T.bankOpen then T:ScanBank() end end)
    ns.On("BAG_UPDATE_DELAYED", function() if T.bankOpen then T:ScanBank() end end)
end)

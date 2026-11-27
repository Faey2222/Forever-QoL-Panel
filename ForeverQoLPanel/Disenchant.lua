local _, ns = ...

-- What disenchanting an item gives: shown in our small tooltip below the item's (LootOpt.lua draws it), with the
-- materials, their chance and amount, and the enchanting skill it needs. The table follows the public Classic
-- disenchanting tables (by quality, item level, armour or weapon); real results can differ a little.
local DE = {}
ns.Disenchant = DE

local M = {   -- material item IDs
    strangeDust = 10940, soulDust = 11083, visionDust = 11137, dreamDust = 11176, illusionDust = 16204,
    lMagic = 10938, gMagic = 10939, lAstral = 10998, gAstral = 11082, lMystic = 11134, gMystic = 11135,
    lNether = 11174, gNether = 11175, lEternal = 16202, gEternal = 16203,
    sGlimmer = 10978, lGlimmer = 11084, sGlow = 11138, lGlow = 11139, sRadiant = 11177, lRadiant = 11178,
    sBrilliant = 14343, lBrilliant = 14344, nexus = 20725,
}

-- uncommon items: up to item level, then dust, essence, shard as { item, min, max }; armour gives mostly dust,
-- weapons mostly essence
local UNCOMMON = {
    { 15, { M.strangeDust, 1, 2 }, { M.lMagic, 1, 2 } },
    { 20, { M.strangeDust, 2, 3 }, { M.gMagic, 1, 2 }, { M.sGlimmer, 1, 1 } },
    { 25, { M.strangeDust, 4, 6 }, { M.lAstral, 1, 2 }, { M.sGlimmer, 1, 1 } },
    { 30, { M.soulDust, 1, 2 }, { M.gAstral, 1, 2 }, { M.lGlimmer, 1, 1 } },
    { 35, { M.soulDust, 2, 5 }, { M.lMystic, 1, 2 }, { M.sGlow, 1, 1 } },
    { 40, { M.visionDust, 1, 2 }, { M.gMystic, 1, 2 }, { M.lGlow, 1, 1 } },
    { 45, { M.visionDust, 2, 5 }, { M.lNether, 1, 2 }, { M.sRadiant, 1, 1 } },
    { 50, { M.dreamDust, 1, 2 }, { M.gNether, 1, 2 }, { M.lRadiant, 1, 1 } },
    { 55, { M.dreamDust, 2, 5 }, { M.lEternal, 1, 2 }, { M.sBrilliant, 1, 1 } },
    { 60, { M.illusionDust, 1, 2 }, { M.gEternal, 1, 2 }, { M.lBrilliant, 1, 1 } },
    { 99, { M.illusionDust, 2, 5 }, { M.gEternal, 2, 3 }, { M.lBrilliant, 1, 1 } },
}
-- rare items: one shard (from 56 on a small chance of a Nexus Crystal)
local RARE = {
    { 25, M.sGlimmer }, { 30, M.lGlimmer }, { 35, M.sGlow }, { 40, M.lGlow }, { 45, M.sRadiant },
    { 50, M.lRadiant }, { 55, M.sBrilliant }, { 99, M.lBrilliant },
}
-- epic items
local EPIC = {
    { 45, { M.sRadiant, 2, 4 } }, { 50, { M.lRadiant, 2, 4 } }, { 55, { M.sBrilliant, 2, 4 } },
    { 60, { M.nexus, 1, 1 } }, { 99, { M.nexus, 1, 2 } },
}
-- the enchanting skill an item level needs
local SKILL = { { 20, 1 }, { 25, 25 }, { 30, 50 }, { 35, 75 }, { 40, 100 }, { 45, 125 }, { 50, 150 }, { 55, 175 },
    { 60, 200 }, { 99, 225 } }

local function bracket(list, level)
    for _, row in ipairs(list) do if level <= row[1] then return row end end
end

-- { { item, chance (%), min, max }, ... }, skill; nil when the item cannot be disenchanted
function DE.Results(quality, level, classID)
    if not level or level < 5 or (classID ~= 2 and classID ~= 4) then return nil end
    local out = {}
    if quality == 2 then
        local row = bracket(UNCOMMON, level)
        if not row then return nil end
        local weapon = classID == 2
        local dust, ess, shard = row[2], row[3], row[4]
        local pDust = shard and (weapon and 20 or 75) or (weapon and 20 or 80)
        local pEss = shard and (weapon and 75 or 20) or (weapon and 80 or 20)
        out[#out + 1] = { dust[1], pDust, dust[2], dust[3] }
        out[#out + 1] = { ess[1], pEss, ess[2], ess[3] }
        if shard then out[#out + 1] = { shard[1], 5, 1, 1 } end
        table.sort(out, function(a, b) return a[2] > b[2] end)
    elseif quality == 3 then
        local row = bracket(RARE, level)
        if not row then return nil end
        if level > 55 then
            out[1] = { row[2], 99.5, 1, 1 }
            out[2] = { M.nexus, 0.5, 1, 1 }
        else
            out[1] = { row[2], 100, 1, 1 }
        end
    elseif quality == 4 then
        if level < 40 then return nil end
        local row = bracket(EPIC, level)
        out[1] = { row[2][1], 100, row[2][2], row[2][3] }
    else
        return nil
    end
    return out, bracket(SKILL, level)[2]
end

local function db() return ns.db.tooltip end

-- the lines for an item link: { { text, r, g, b }, ... } or nil
function DE.Lines(link)
    local t = db()
    if not (t.enabled and t.disenchant) then return nil end
    local mine = ns.Tooltip and ns.Tooltip.Rank and ns.Tooltip.Rank("ench")
    if t.deOnlyEnchanter and not (mine and mine > 0) then return nil end
    local _, _, quality, level, _, _, _, _, _, _, _, classID = ns.ItemInfo(link)
    if ns.Secret(quality) or ns.Secret(level) then return nil end
    local results, need = DE.Results(quality, level, classID)
    if not results then return nil end
    local L = ns.L
    local lines = { { L.DE_TITLE, 1, 0.82, 0 } }
    for _, r in ipairs(results) do
        local name, _, q, _, _, _, _, _, _, icon = ns.ItemInfo(r[1])
        if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(r[1]) end
        icon = icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r[1])) or "Interface\\Icons\\INV_Misc_QuestionMark"
        local amount = r[3] == r[4] and tostring(r[3]) or (r[3] .. "–" .. r[4])
        local chance = (r[2] % 1 == 0) and string.format("%d %%", r[2]) or string.format("%.1f %%", r[2])
        if ns.language ~= "enUS" and ns.language ~= "zhCN" then chance = chance:gsub("%.", ",") end
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        local col = c and c.hex or "|cffffffff"
        lines[#lines + 1] = { "|T" .. icon .. ":14:14:0:0|t " .. col .. (name or "…") .. "|r  " .. amount .. "x  |cffcccccc" .. chance .. "|r", 1, 1, 1 }
    end
    -- the skill it needs, red while yours is lower
    local low = mine and mine < need
    lines[#lines + 1] = { L.DE_SKILL:format(need), low and 1 or 0.82, low and 0.25 or 0.82, low and 0.25 or 0.82 }
    return lines
end

function DE:Tooltip(tt)
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    local _, link = tt:GetItem()
    if not link or ns.Secret(link) then return end
    tt.fqpDE = DE.Lines(link)
end

ns.OnLogin(function()
    C_Timer.After(3, function()
        local TDP = TooltipDataProcessor
        if not (TDP and TDP.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
        TDP.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt) ns.Debug.Call("Disenchant", DE.Tooltip, DE, tt) end)
    end)
end)

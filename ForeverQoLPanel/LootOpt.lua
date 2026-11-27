local _, ns = ...

-- Loot optimizer:
--  * gear scoring: a weight per stat for your class and talent tree (the tree with the most points, or the profile
--    you pick), hit counted only up to its cap, gear your class cannot wear left out; weights and caps can be changed
--  * tooltip: how a piece of gear compares with what you wear in that slot
--  * a window when you loot something better than what you wear: why it is better, by how much, put it on
--  * a window when your bags are full while looting: the cheapest item in your bags, swap / delete / next / ignore
-- The default weights are Pawn Forever's (WeightData.lua): one set for levelling, one for the highest level.
local LO = {}
ns.LootOpt = LO

local floor, max, min, abs, fmt = math.floor, math.max, math.min, math.abs, string.format
local function L() return ns.L end
local function db() return ns.db.lootopt end
local function on(key) local d = db(); return d.enabled and (key == nil or d[key]) end

-- Stats ------------------------------------------------------------------------------
-- Pawn's stat names, and the item stat names the client may use for them. Weapon damage per second is ranged or
-- melee by the weapon's slot.
local STAT_KEYS = {
    Strength = { "ITEM_MOD_STRENGTH_SHORT" }, Agility = { "ITEM_MOD_AGILITY_SHORT" },
    Stamina = { "ITEM_MOD_STAMINA_SHORT" }, Intellect = { "ITEM_MOD_INTELLECT_SHORT" }, Spirit = { "ITEM_MOD_SPIRIT_SHORT" },
    Ap = { "ITEM_MOD_ATTACK_POWER_SHORT" }, Rap = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
    FeralAp = { "ITEM_MOD_FERAL_ATTACK_POWER_SHORT" },
    SpellDamage = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
    Healing = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
    Mp5 = { "ITEM_MOD_POWER_REGEN0_SHORT", "ITEM_MOD_MANA_REGENERATION_SHORT" },
    Hp5 = { "ITEM_MOD_HEALTH_REGEN_SHORT", "ITEM_MOD_HEALTH_REGENERATION_SHORT" },
    CritRating = { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT", "ITEM_MOD_CRIT_RANGED_RATING_SHORT",
        "ITEM_MOD_CRIT_SPELL_RATING_SHORT" },
    HitRating = { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT", "ITEM_MOD_HIT_RANGED_RATING_SHORT",
        "ITEM_MOD_HIT_SPELL_RATING_SHORT" },
    HasteRating = { "ITEM_MOD_HASTE_RATING_SHORT" }, ExpertiseRating = { "ITEM_MOD_EXPERTISE_RATING_SHORT" },
    DefenseRating = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" }, DodgeRating = { "ITEM_MOD_DODGE_RATING_SHORT" },
    ParryRating = { "ITEM_MOD_PARRY_RATING_SHORT" }, BlockRating = { "ITEM_MOD_BLOCK_RATING_SHORT" },
    BlockValue = { "ITEM_MOD_BLOCK_VALUE_SHORT" }, Armor = { "RESISTANCE0_NAME" },
    MeleeDps = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" }, RangedDps = {},
    Health = { "ITEM_MOD_HEALTH_SHORT" }, Mana = { "ITEM_MOD_MANA_SHORT" },
    FireResist = { "RESISTANCE2_NAME", "ITEM_MOD_FIRE_RESISTANCE_SHORT" },
    NatureResist = { "RESISTANCE3_NAME", "ITEM_MOD_NATURE_RESISTANCE_SHORT" },
    FrostResist = { "RESISTANCE4_NAME", "ITEM_MOD_FROST_RESISTANCE_SHORT" },
    ShadowResist = { "RESISTANCE5_NAME", "ITEM_MOD_SHADOW_RESISTANCE_SHORT" },
    ArcaneResist = { "RESISTANCE6_NAME", "ITEM_MOD_ARCANE_RESISTANCE_SHORT" },
    -- damage of one spell school (Forever names these as item stats)
    FireSpellDamage = { "ITEM_MOD_FIRE_DAMAGE_DONE_SHORT" }, FrostSpellDamage = { "ITEM_MOD_FROST_DAMAGE_DONE_SHORT" },
    NatureSpellDamage = { "ITEM_MOD_NATURE_DAMAGE_DONE_SHORT" }, ShadowSpellDamage = { "ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT" },
    ArcaneSpellDamage = { "ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT" }, HolySpellDamage = { "ITEM_MOD_HOLY_DAMAGE_DONE_SHORT" },
}
local ORDER = { "Strength", "Agility", "Stamina", "Intellect", "Spirit", "Ap", "Rap", "FeralAp", "SpellDamage", "Healing",
    "FireSpellDamage", "FrostSpellDamage", "NatureSpellDamage", "ShadowSpellDamage", "ArcaneSpellDamage", "HolySpellDamage",
    "Mp5", "Hp5", "CritRating", "HitRating", "HasteRating", "ExpertiseRating", "DefenseRating", "DodgeRating",
    "ParryRating", "BlockRating", "BlockValue", "Armor", "MeleeDps", "RangedDps", "Health", "Mana", "FireResist",
    "FrostResist", "NatureResist", "ShadowResist", "ArcaneResist" }
LO.ORDER = ORDER
local FROM = {}
for key, list in pairs(STAT_KEYS) do for _, k in ipairs(list) do FROM[k] = key end end
-- chances in percent; a client that gives ratings instead gets them roughly turned into percent
local PERCENT = { CritRating = true, HitRating = true, HasteRating = true, ExpertiseRating = true, DodgeRating = true,
    ParryRating = true, BlockRating = true }
-- names where the client has none of its own
local OWN_NAME = { RangedDps = "STAT_RANGEDDPS", FeralAp = "STAT_FERALAP", Hp5 = "STAT_HPFIVE", HasteRating = "STAT_HASTE",
    ExpertiseRating = "STAT_EXPERTISE", MeleeDps = "STAT_MELEEDPS" }

function LO.StatName(key)
    if OWN_NAME[key] and L()[OWN_NAME[key]] then return L()[OWN_NAME[key]] end
    for _, k in ipairs(STAT_KEYS[key] or {}) do
        local g = _G[k]
        if type(g) == "string" and g ~= "" and not g:find("%%") then return g end
    end
    return key
end

local function class() return select(2, UnitClass("player")) end

-- Profiles -----------------------------------------------------------------------------

-- The talent trees (Forever: three per class): name and points spent
-- Forever: one trait tree per class, split into three groups (the talent trees) with their own points; read for the
-- active spec group (primary / secondary) through the client's specialization and traits functions
local function traitSpecs()
    local SI, T = C_SpecializationInfo, C_Traits
    if not (SI and T and SI.GetActiveSpecGroup and SI.GetCombatConfigIDForSpecGroup and T.GetConfigInfo
        and T.GetGroupDisplayInfoByTreeID and T.GetGroupCurrencyInfo) then return nil end
    local ok, group = pcall(SI.GetActiveSpecGroup)
    local config = ok and group and select(2, pcall(SI.GetCombatConfigIDForSpecGroup, group))
    if type(config) ~= "number" then return nil end
    local okI, info = pcall(T.GetConfigInfo, config)
    local tree = okI and info and info.treeIDs and info.treeIDs[1]
    if not tree then return nil end
    local okD, groups = pcall(T.GetGroupDisplayInfoByTreeID, tree)
    if not okD or type(groups) ~= "table" or #groups == 0 then return nil end
    local ids = {}
    for _, g in ipairs(groups) do ids[#ids + 1] = g.groupID end
    local spent = {}
    local okC, currency = pcall(T.GetGroupCurrencyInfo, config, ids)
    for _, c in ipairs(okC and currency or {}) do
        local ci = c.currencyInfos and c.currencyInfos[1]
        if ci and c.traitNodeGroupID then spent[c.traitNodeGroupID] = ci.spent or 0 end
    end
    table.sort(groups, function(x, y) return (x.orderIndex or 0) < (y.orderIndex or 0) end)
    local list = {}
    for i, g in ipairs(groups) do
        if i > 3 then break end
        list[i] = { name = g.displayName or ("#" .. i), points = spent[g.groupID] or 0 }
    end
    return list
end

function LO.Specs()
    local traits = traitSpecs()
    if traits then
        local pts = {}
        for i, sp in ipairs(traits) do pts[i] = sp.points end
        ns.Debug.Set("lootSpecs", { via = "traits", points = pts })
        return traits
    end
    local list = {}
    local n = GetNumTalentTabs and GetNumTalentTabs() or 0
    -- clients with specializations instead of talent tabs: the active one counts as the one with the points
    if n == 0 and GetSpecialization and GetSpecializationInfo then
        local active = GetSpecialization()
        for i = 1, 3 do
            local ok, _, name = pcall(GetSpecializationInfo, i)
            if ok and type(name) == "string" then list[i] = { name = name, points = (i == active) and 1 or 0 } end
        end
        ns.Debug.Set("lootSpecs", { via = "specialization", active = active, count = #list })
        return list
    end
    for i = 1, min(n, 3) do
        local r = { GetTalentTabInfo(i) }
        local name = type(r[2]) == "string" and r[2] or (type(r[1]) == "string" and r[1]) or ("#" .. i)
        local points = type(r[5]) == "number" and r[5] or (type(r[3]) == "number" and r[3]) or 0
        list[i] = { name = name, points = points }
    end
    return list
end

local function data(cls) return ns.WeightData[cls or class()] end

-- a profile's name in the client's language: ours (Locale), else Pawn's
local function profileName(key, d)
    local own = L()["PROFILE_" .. key:upper()]
    if own and own ~= "PROFILE_" .. key:upper() then return own end
    return d.profiles[key].label
end

-- the profiles of a class: its talent trees first (named as the game names them), then the extra ones
function LO.Profiles(cls)
    local d = data(cls)
    if not d then return {} end
    local specs = (not cls or cls == class()) and LO.Specs() or {}
    ns.Debug.Set("lootTalentTabs", { count = #specs, first = specs[1] and specs[1].name })
    local list, seen = {}, {}
    for i, key in ipairs(d.tabs) do
        local game = specs[i] and specs[i].name
        if game and game:find("^#") then game = nil end
        -- the druid's feral tree rates for the cat; the game's tree name would hide that
        if key == "feral" then game = nil end
        list[#list + 1] = { key = key, label = game or profileName(key, d) }
        seen[key] = true
    end
    for _, key in ipairs(d.order) do
        if not seen[key] then list[#list + 1] = { key = key, label = profileName(key, d) } end
    end
    return list
end

-- the profile rated for: the one picked, or the talent tree with the most points (below level 10 the first)
function LO.Profile(cls)
    local d = data(cls)
    if not d then return nil end
    local pick = db().spec
    if type(pick) == "string" and d.profiles[pick] then return pick end
    if type(pick) == "number" and d.tabs[pick] then return d.tabs[pick] end   -- picked before profiles existed
    local best, bestPts = 1, -1
    for i, sp in ipairs(LO.Specs()) do if sp.points > bestPts then best, bestPts = i, sp.points end end
    return d.tabs[best] or d.tabs[1]
end
LO.Spec = LO.Profile

function LO.ProfileLabel(key, cls)
    for _, p in ipairs(LO.Profiles(cls)) do if p.key == key then return p.label end end
    return key or "?"
end

local function maxLevel() return (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60 end

-- weights: Pawn Forever's (levelling below the highest level), your own on top
function LO.Weights(cls, profile)
    cls = cls or class()
    profile = profile or LO.Profile(cls)
    local d = data(cls)
    local prof = d and d.profiles[profile]
    local base = {}
    if prof then
        local set = (UnitLevel("player") or 1) >= maxLevel() and prof.max or prof.leveling
        for k, v in pairs(set) do if STAT_KEYS[k] then base[k] = v end end
    end
    local own = db().weights[cls] and db().weights[cls][profile]
    local w = {}
    for k, v in pairs(base) do w[k] = v end
    for k, v in pairs(type(own) == "table" and own or {}) do w[k] = v end
    return w, base
end

-- hit cap in percent: spells for casters and healers, white melee for everyone else
function LO.Caps(cls, profile)
    cls = cls or class()
    profile = profile or LO.Profile(cls)
    local own = db().caps[cls] and db().caps[cls][profile]
    if type(own) == "number" then return { HitRating = own } end
    local _, w = LO.Weights(cls, profile)
    local caster = max(w.SpellDamage or 0, w.Healing or 0) >= 0.5 and (w.Strength or 0) < 0.5 and (w.Agility or 0) < 0.5
    return { HitRating = caster and 16 or 9 }
end

-- Export / import of one profile's weights and cap: one line to copy and paste,
-- "FQPW2;MAGE;fire;SpellDamage=1;Intellect=0.9;...;cap=16"
function LO.Export(cls, profile)
    cls = cls or class()
    profile = profile or LO.Profile(cls)
    local w = LO.Weights(cls, profile)
    local parts = { "FQPW2", cls, tostring(profile) }
    for _, key in ipairs(ORDER) do
        if (w[key] or 0) ~= 0 then parts[#parts + 1] = key .. "=" .. tostring(floor(w[key] * 1000 + 0.5) / 1000) end
    end
    parts[#parts + 1] = "cap=" .. LO.Caps(cls, profile).HitRating
    return table.concat(parts, ";")
end

-- applies a line from Export to your class and current profile; returns the number of values or nil, error
function LO.Import(text)
    if type(text) ~= "string" then return nil, "empty" end
    local parts = {}
    for part in text:gmatch("[^;%s]+") do parts[#parts + 1] = part end
    if parts[1] ~= "FQPW2" then return nil, "format" end
    local cls, profile = class(), LO.Profile()
    local d = db()
    local weights, cap, n = {}, nil, 0
    for i = 4, #parts do
        local k, v = parts[i]:match("^(%w+)=([%d%.]+)$")
        v = tonumber(v)
        if k and v then
            if k == "cap" then cap = v; n = n + 1
            elseif STAT_KEYS[k] then weights[k] = v; n = n + 1 end
        end
    end
    if n == 0 then return nil, "empty" end
    -- every stat not named counts nothing
    for _, key in ipairs(ORDER) do if weights[key] == nil then weights[key] = 0 end end
    d.weights[cls] = d.weights[cls] or {}
    d.weights[cls][profile] = weights
    if cap then
        d.caps[cls] = type(d.caps[cls]) == "table" and d.caps[cls] or {}
        d.caps[cls][profile] = cap
    end
    return n
end

-- Proficiency ------------------------------------------------------------------------

-- armor subclasses (class 4): 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem; the number
-- is the level from which the class may wear it
local ARMOR = {
    WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 }, PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
    HUNTER = { [1] = 1, [2] = 1, [3] = 40 }, ROGUE = { [1] = 1, [2] = 1 }, PRIEST = { [1] = 1 },
    SHAMAN = { [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 }, MAGE = { [1] = 1 }, WARLOCK = { [1] = 1 },
    DRUID = { [1] = 1, [2] = 1, [8] = 1 },
}
-- weapon subclasses (class 2) a class can learn
local WEAPON = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 10, 13, 15 },
}
local DUAL = { WARRIOR = true, ROGUE = true, HUNTER = true }

local function canWear(classID, subID, cls)
    cls = cls or class()
    if classID == 4 then
        if subID == 0 then return true end
        local lvl = ARMOR[cls] and ARMOR[cls][subID]
        return lvl ~= nil and (UnitLevel("player") or 1) >= lvl
    elseif classID == 2 then
        for _, s in ipairs(WEAPON[cls] or {}) do if s == subID then return true end end
        return false
    end
    return false
end

-- Class-bound items ("Classes: Rogue" in the tooltip): only for the classes named there. Read from the item's tooltip
-- data, the class compared in its male and female name; the answer is kept per item.
local classOk = {}
local function classAllowed(link)
    local id = link and tonumber(tostring(link):match("item:(%d+)"))
    if not id then return true end
    if classOk[id] ~= nil then return classOk[id] end
    local TI = C_TooltipInfo
    local data = TI and TI.GetHyperlink and select(2, pcall(TI.GetHyperlink, link))
    if type(data) ~= "table" or type(data.lines) ~= "table" or not ITEM_CLASSES_ALLOWED then return true end
    local pattern = "^" .. ITEM_CLASSES_ALLOWED:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
    local _, cls = UnitClass("player")
    local names = {}
    for _, t in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
        if t and t[cls] then names[#names + 1] = t[cls] end
    end
    local mine = UnitClass("player")
    if mine then names[#names + 1] = mine end
    local ok = true
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not ns.Secret(text) then
            local list = text:match(pattern)
            if list then
                ok = false
                for part in list:gmatch("[^,]+") do
                    part = part:gsub("^%s+", ""):gsub("%s+$", "")
                    for _, n in ipairs(names) do if part == n then ok = true end end
                end
                break
            end
        end
    end
    classOk[id] = ok
    return ok
end
LO.ClassAllowed = classAllowed

-- equip location -> inventory slots
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Scoring -----------------------------------------------------------------------------

local seenKeys = {}
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
function LO.Stats(link)
    if not link then return nil end
    local get = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not get then return nil end
    local ok, raw = pcall(get, link)
    if not ok or type(raw) ~= "table" then return nil end
    local s = {}
    for k, v in pairs(raw) do
        local key = FROM[k]
        seenKeys[k] = true
        if key and type(v) == "number" then
            if PERCENT[key] and v > 6 then v = v / 14 end
            s[key] = (s[key] or 0) + v
        end
    end
    -- a ranged weapon's damage per second is ranged damage
    if s.MeleeDps then
        local loc = select(9, ns.ItemInfo(link))
        if RANGED[loc] then s.RangedDps, s.MeleeDps = s.MeleeDps, nil end
    end
    return s
end

-- score of a stat table; room: how much hit (percent) still counts
local function score(stats, w, room)
    if not stats then return 0 end
    local total = 0
    for key, v in pairs(stats) do
        if key == "HitRating" and room then v = min(v, max(0, room.HitRating)) end
        total = total + (w[key] or 0) * v
    end
    return total
end

local function equipped(slot)
    return GetInventoryItemLink and GetInventoryItemLink("player", slot)
end

-- hit already on your gear, without one slot
local function hitWithout(skip)
    local hit = 0
    for slot = 1, 18 do
        if slot ~= skip then
            local st = LO.Stats(equipped(slot))
            if st then hit = hit + (st.HitRating or 0) end
        end
    end
    return hit
end

local function roomFor(slot, caps)
    return { HitRating = caps.HitRating - hitWithout(slot) }
end

local function info(link)
    local name, _, quality, _, minLevel, _, _, _, equipLoc, icon, sellPrice, classID, subID, bind = ns.ItemInfo(link)
    if not name then return nil end
    return { name = name, quality = quality, minLevel = minLevel or 0, equipLoc = equipLoc, icon = icon,
        sellPrice = sellPrice or 0, classID = classID, subID = subID, bind = bind }
end

-- Compares an item with what you wear. Returns nil (not gear, cannot wear it, no data) or
-- { pct, new, old, slot, oldLink, empty, level, newStats, oldStats }
function LO:Compare(link)
    local i = info(link)
    if not i or not i.equipLoc or i.equipLoc == "" then return nil end
    local slots = SLOTS[i.equipLoc]
    if not slots then return nil end
    if not canWear(i.classID, i.subID) then return nil end
    -- an item only some classes may wear (a rogues' mask, say)
    if not classAllowed(link) then return nil end
    local newStats = LO.Stats(link)
    if not newStats then return nil end
    local w, caps = LO.Weights(), LO.Caps()
    local cls = class()
    local mainLink = equipped(16)
    local mainInfo = mainLink and info(mainLink)
    local twoHanded = mainInfo and mainInfo.equipLoc == "INVTYPE_2HWEAPON"
    local best
    local function consider(slot, oldScore, oldLink, oldStats)
        local newScore = score(newStats, w, roomFor(slot, caps))
        local r = { new = newScore, old = oldScore, slot = slot, oldLink = oldLink, newStats = newStats, oldStats = oldStats }
        r.empty = not oldLink
        -- against a worn piece worth nothing for you, anything that counts is far better
        if oldScore > 0 then r.pct = (newScore - oldScore) / oldScore * 100
        elseif newScore > 0 then r.pct = math.huge end
        if not best or (newScore - oldScore) > (best.new - best.old) then best = r end
    end
    if i.equipLoc == "INVTYPE_2HWEAPON" then
        -- against main and off hand together
        local off = equipped(17)
        local ms, os = LO.Stats(mainLink), LO.Stats(off)
        local old = score(ms, w, roomFor(16, caps)) + score(os, w, roomFor(17, caps))
        local both = {}
        for _, t in ipairs({ ms or {}, os or {} }) do for k, v in pairs(t) do both[k] = (both[k] or 0) + v end end
        consider(16, old, mainLink or off, both)
    else
        for _, slot in ipairs(slots) do
            local ok = true
            if slot == 17 and i.equipLoc == "INVTYPE_WEAPON" and not DUAL[cls] then ok = false end
            if slot == 17 and twoHanded then ok = false end   -- an off hand next to a two-hander: no verdict
            if ok then
                local old = equipped(slot)
                local os = LO.Stats(old)
                consider(slot, score(os, w, roomFor(slot, caps)), old, os)
            end
        end
    end
    if best then best.level = i.minLevel > (UnitLevel("player") or 1) and i.minLevel or nil end
    ns.Debug.Set("lootStatKeys", seenKeys)
    return best
end

-- Tooltip ------------------------------------------------------------------------------

local function isEquipped(link)
    for slot = 1, 19 do if equipped(slot) == link then return true end end
    return false
end

local function signed(v, key)
    local s = key and PERCENT[key] and fmt("%.1f %%", abs(v)) or tostring(floor(abs(v) + 0.5))
    if ns.language ~= "enUS" and ns.language ~= "zhCN" then s = s:gsub("%.", ",") end
    return (v >= 0 and "+" or "-") .. s
end

-- what changes against the worn piece, the weighted most important first: { text, r, g, b }
function LO.Diffs(r, limit)
    local w = LO.Weights()
    local diff = {}
    for _, key in ipairs(ORDER) do
        local d = ((r.newStats or {})[key] or 0) - ((r.oldStats or {})[key] or 0)
        if abs(d) > 0.001 and (PERCENT[key] or abs(d) >= 0.5) then
            diff[#diff + 1] = { key = key, d = d, weight = abs(d * (w[key] or 0)), counted = (w[key] or 0) > 0 }
        end
    end
    table.sort(diff, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return abs(a.d) > abs(b.d)
    end)
    -- only the number is coloured (green more, red less, neutral when it is not rated); the name stays white
    local out = {}
    for n = 1, min(#diff, limit or 8) do
        local e = diff[n]
        local col = not e.counted and "|cffd8d8d8" or (e.d > 0 and "|cff20ff20" or "|cffff5050")
        out[n] = { col .. signed(e.d, e.key) .. "|r " .. LO.StatName(e.key), 1, 1, 1 }
    end
    return out
end

function LO:Tooltip(tt, data)
    if not on("tooltip") then return end
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end   -- not on the comparison tooltips
    local _, link = tt:GetItem()
    if not link or ns.Secret(link) or isEquipped(link) then return end
    local r = self:Compare(link)
    if not r then return end
    local text, cr, cg, cb
    if r.empty then
        text, cr, cg, cb = L().LO_TT_EMPTY, 0.12, 1, 0
    elseif not r.pct then
        return
    elseif r.pct >= 1 then
        text, cr, cg, cb = r.pct > 300 and L().LO_TT_MUCH or L().LO_TT_BETTER:format(floor(r.pct + 0.5)), 0.12, 1, 0
    elseif r.pct <= -1 then
        text, cr, cg, cb = L().LO_TT_WORSE:format(floor(-r.pct + 0.5)), 1, 0.3, 0.3
    else
        text, cr, cg, cb = L().LO_TT_SAME, 0.7, 0.7, 0.7
    end
    if r.level then text = text .. "  |cffff8040" .. L().LO_FROM_LEVEL:format(r.level) .. "|r" end
    -- shown in our own small tooltip right below the item's (see below): nothing mixes with other addons' lines
    tt.fqpLoot = { text = text, r = cr, g = cg, b = cb, diffs = LO.Diffs(r, 8) }
end

-- a tiny font for the gap below the heading of our tooltip
local gapFont
function LO.GapFont()
    if not gapFont then
        gapFont = CreateFont("ForeverQoLPanelGapFont")
        local file = GameTooltipText and GameTooltipText:GetFont()
        gapFont:SetFont(file or ns.FontFile(), 4, "")
    end
    return gapFont
end

-- Our tooltip below the item tooltip, as wide as it; above it when there is no room below
local tip
local function ourTip()
    if not tip then
        tip = CreateFrame("GameTooltip", "ForeverQoLPanelLootTip", UIParent, "GameTooltipTemplate")
        tip:SetFrameStrata("TOOLTIP")
    end
    return tip
end

-- the comparison (fqpLoot) and what disenchanting gives (fqpDE, Disenchant.lua), each when there is one
local function place(tt)
    local line, de = tt.fqpLoot, tt.fqpDE
    local t = ourTip()
    if not (line or de) or not tt:IsShown() then
        if t.owner == tt then t:Hide() end
        return
    end
    t.owner = tt
    t:SetOwner(tt, "ANCHOR_NONE")
    t:ClearLines()
    t:SetScale(tt:GetScale() or 1)
    t:AddDoubleLine("|T" .. ns.Tex("icon") .. ":12:12:0:0|t " .. ns.title, " ", 0.8, 0.8, 0.8, 1, 1, 1)
    t:AddLine(" ")
    if line then
        t:AddLine(line.text, line.r, line.g, line.b, true)
        for _, d in ipairs(line.diffs or {}) do t:AddLine("   " .. d[1], d[2], d[3], d[4]) end
    end
    if de then
        if line then t:AddLine(" ") end
        for _, d in ipairs(de) do t:AddLine(d[1], d[2], d[3], d[4]) end
    end
    -- fonts per line: the first would get the big heading font (here the normal one, grey, like a source note),
    -- the second is a small gap below it, the rest the normal tooltip font
    for n = 1, (t:NumLines() or 0) do
        local fs = _G["ForeverQoLPanelLootTipTextLeft" .. n]
        if fs then fs:SetFontObject(n == 2 and LO.GapFont() or GameTooltipText) end
    end
    if t.SetMinimumWidth then t:SetMinimumWidth(0) end
    t:Show()
    -- a nearly solid dark ground: what lies behind must not shine through the text
    if type(t.NineSlice) == "table" and t.NineSlice.SetCenterColor then
        t.NineSlice:SetCenterColor(0.03, 0.03, 0.04, 0.94)
    elseif t.SetBackdropColor then
        t:SetBackdropColor(0.03, 0.03, 0.04, 0.94)
    end
    -- as wide as the item tooltip, but never narrower than its own text (a short item name above a long line of what
    -- disenchanting gives)
    local own = t:GetWidth() or 0
    local w = tt:GetWidth()
    if w and w > 0 then t:SetWidth(math.max(w, own)) end
    t:ClearAllPoints()
    local bottom = tt:GetBottom() or 0
    if bottom * (tt:GetEffectiveScale() or 1) < (t:GetHeight() or 40) * (t:GetEffectiveScale() or 1) + 8 then
        t:SetPoint("BOTTOMLEFT", tt, "TOPLEFT", 0, 2)
    else
        t:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", 0, -2)
    end
end
LO.Place = place

-- Windows in the panel's look ----------------------------------------------------------

local function dialog(name, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -16)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -4, -4)
    -- the panel's look (UI.Skin), laid out again when the size changes
    function f:Skin() ns.UI.Skin(self) end
    f:SetScript("OnSizeChanged", function(self) ns.UI.Skin(self) end)
    f:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, name) end
    return f
end

local function button(parent, width, text)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text or "")
    return b
end

-- an item row: icon with quality border, name in quality colour, a second line
local function itemRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(200, 40)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(36, 36)
    r.icon:SetPoint("LEFT")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -2)
    r.name:SetPoint("RIGHT")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 2)
    r.sub:SetPoint("RIGHT")
    r.sub:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- fallback { icon, name, quality }: what the loot window knows about an item whose data is not loaded yet
    function r:Set(link, sub, fallback)
        self.link = link
        local i = link and info(link)
        fallback = fallback or {}
        -- each part from the item data, else from what the loot window knows, else from the link itself
        local id = link and tonumber(link:match("item:(%d+)"))
        local icon = (i and i.icon) or fallback.icon or (id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
        local name = (i and i.name) or fallback.name or (link and link:match("%[(.-)%]"))
        local quality = (i and i.quality) or fallback.quality
        if link and not i and id and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        self.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        self.name:SetText(name or L().LO_NOTHING)
        if c then self.name:SetTextColor(c.r, c.g, c.b) else self.name:SetTextColor(0.7, 0.7, 0.7) end
        self.sub:SetText(sub or "")
    end
    return r
end

-- Upgrade window -------------------------------------------------------------------------

-- Offered again later unless ignored: "Later", closing the window or a reload only put a piece aside until the
-- next good moment: a loading screen (login, reload, zone change), a level up, the piece coming into the bags anew
-- (from the bank, say). In combat the window waits until the fight is over.
local queue, queued, snoozed = {}, {}, {}
local function itemKey(link) return link and (link:match("item:([%-%d:]+)") or link) end

local function inBags(link)
    local key = itemKey(link)
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, ((C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0) do
            local it = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
            if it and it.hyperlink and itemKey(it.hyperlink) == key then return true end
        end
    end
    return false
end


function LO:UpgradeFrame()
    if self.up then return self.up end
    local f = dialog("ForeverQoLPanelUpgrade", 420, 300)
    f.newRow = itemRow(f)
    f.newRow:SetPoint("TOPLEFT", 20, -48)
    f.newRow:SetWidth(380)
    f.oldRow = itemRow(f)
    f.oldRow:SetPoint("TOPLEFT", f.newRow, "BOTTOMLEFT", 0, -6)
    f.oldRow:SetWidth(380)
    f.pct = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.pct:SetPoint("TOPRIGHT", -22, -52)
    f.lines = {}
    for n = 1, 8 do
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        l:SetPoint("TOPLEFT", f.oldRow, "BOTTOMLEFT", 44, -10 - (n - 1) * 16)
        l:SetJustifyH("LEFT")
        f.lines[n] = l
    end
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.note:SetPoint("BOTTOM", 0, 46)
    f.note:SetWidth(380)
    -- three buttons of one width with even gaps
    local bw = floor((420 - 2 * 24 - 2 * 10) / 3)
    f.equip = button(f, bw, L().LO_EQUIP)
    f.equip:SetPoint("BOTTOMLEFT", 24, 18)
    f.ignore = button(f, bw, L().LO_IGNORE)
    f.ignore:SetPoint("BOTTOM", 0, 18)
    f.later = button(f, bw, L().LO_LATER)
    f.later:SetPoint("BOTTOMRIGHT", -24, 18)
    f.later:SetScript("OnClick", function() f:Hide() end)
    f.ignore:SetScript("OnClick", function()
        local id = f.link and tonumber(f.link:match("item:(%d+)"))
        if id then db().ignoreUpgrade[id] = true end
        f.result = "ignore"
        f:Hide()
    end)
    f.equip:SetScript("OnClick", function()
        if InCombatLockdown() or not f.link then return end
        LO:Equip(f.link, f.slot)
        f.result = "equip"
        f:Hide()
    end)
    -- "Later", the close button or Esc: put aside until the next good moment
    f:SetScript("OnHide", function()
        if f.link then
            queued[itemKey(f.link)] = nil
            if not f.result then snoozed[itemKey(f.link)] = true end
        end
        C_Timer.After(0.2, function() LO:NextUpgrade() end)
    end)
    self.up = f
    return f
end

-- Puts a piece from the bags on, into that slot: the client's own function where it has one (moved to C_Item in
-- newer clients), else picked up from the bag and put into the slot. Binding on equip asks first, as usual. A moment
-- later it checks and says so in the chat if the piece is not on.
-- picked up from the bag and put into the slot
local function equipFromBag(link, slot)
    local key = itemKey(link)
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for s = 1, ((C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0) do
            local it = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, s)
            if it and it.hyperlink and itemKey(it.hyperlink) == key then
                C_Container.PickupContainerItem(bag, s)
                if CursorHasItem and CursorHasItem() then
                    if EquipCursorItem then EquipCursorItem(slot) else PickupInventoryItem(slot) end
                end
                return true
            end
        end
    end
    return false
end

local function isOn(link, slot)
    return itemKey(GetInventoryItemLink and GetInventoryItemLink("player", slot)) == itemKey(link)
end
-- binding on equip: the game's confirmation may be open
local function asking()
    return StaticPopup_Visible and (StaticPopup_Visible("EQUIP_BIND") or StaticPopup_Visible("AUTOEQUIP_BIND")) and true or false
end

-- Puts a piece from the bags on, into that slot: the client's own function (moved to C_Item in newer clients); if
-- the piece is not on a moment later, picked up from the bag and put into the slot. Binding on equip asks first, as
-- usual. If it is still not on, the chat says so.
function LO:Equip(link, slot)
    local how = "bag"
    if C_Item and C_Item.EquipItemByName then how = "C_Item"; pcall(C_Item.EquipItemByName, link, slot)
    elseif EquipItemByName then how = "global"; pcall(EquipItemByName, link, slot)
    else equipFromBag(link, slot) end
    C_Timer.After(0.4, function()
        if how ~= "bag" and not isOn(link, slot) and not asking() then how = how .. "+bag"; equipFromBag(link, slot) end
        C_Timer.After(0.8, function()
            ns.Debug.Set("lootEquip", { how = how, slot = slot, on = isOn(link, slot) })
            if not isOn(link, slot) and not asking() then
                print("|cffffd100" .. ns.title .. "|r: " .. L().LO_EQUIP_FAILED:format(link))
            end
        end)
    end)
end

function LO:ShowUpgrade(link, r)
    local f = self:UpgradeFrame()
    f:Skin()
    f.link, f.slot, f.result = link, r.slot, nil
    f.title:SetText(L().LO_UP_TITLE)
    f.newRow:Set(link, L().LO_NEW)
    f.oldRow:Set(r.oldLink, r.oldLink and L().LO_WORN or L().LO_EMPTY_SLOT)
    if r.pct then
        -- against a piece worth almost nothing the percentage means little
        f.pct:SetText("|cff20ff20" .. (r.pct > 300 and "> 300 %" or ("+" .. floor(r.pct + 0.5) .. " %")) .. "|r")
    else
        f.pct:SetText("|cff20ff20" .. L().LO_NEW_SLOT .. "|r")
    end
    -- what changes, the weighted most important first
    local diff = LO.Diffs(r, #f.lines)
    for n, l in ipairs(f.lines) do
        local e = diff[n]
        if e then
            l:SetText(e[1])
            l:SetTextColor(e[2], e[3], e[4])
            l:Show()
        else
            l:Hide()
        end
    end
    local i = info(link)
    local notes = {}
    if i and i.bind == 2 then notes[#notes + 1] = L().LO_BOE end
    if InCombatLockdown() then notes[#notes + 1] = L().LO_AFTER_COMBAT end
    notes[#notes + 1] = L().LO_RATED_FOR:format(UnitClass("player") or "?", LO.ProfileLabel(LO.Profile()))
    f.note:SetText(table.concat(notes, "\n"))
    f.equip:SetEnabled(not InCombatLockdown())
    f:SetHeight(150 + max(1, min(#diff, 8)) * 16 + #notes * 12 + 40)
    f:Show()
end

-- worth a window: at least the threshold better, or an empty slot filled with something that counts
function LO.Worth(r)
    if r.empty then return (r.new or 0) > 0 end
    return r.pct ~= nil and r.pct >= (db().threshold or 3)
end

function LO:NextUpgrade()
    if self.up and self.up:IsShown() then return end
    if InCombatLockdown() then self.afterCombat = true return end
    local nxt = table.remove(queue, 1)
    if not nxt then return end
    local key = itemKey(nxt)
    local r = inBags(nxt) and not snoozed[key] and self:Compare(nxt)
    if r and LO.Worth(r) and not r.level then self:ShowUpgrade(nxt, r)
    else queued[key] = nil; self:NextUpgrade() end
end

-- offers a piece in your bags if it is better, not ignored, not put aside and not offered already
function LO:Offer(link)
    if not on("upgrade") or not link then return end
    local key = itemKey(link)
    local id = tonumber(link:match("item:(%d+)"))
    if (id and db().ignoreUpgrade[id]) or snoozed[key] or queued[key] then return end
    if self.up and self.up:IsShown() and self.up.link and itemKey(self.up.link) == key then return end
    local r = self:Compare(link)
    if not r or r.level or not LO.Worth(r) then return end
    queued[key] = true
    queue[#queue + 1] = link
    self:NextUpgrade()
end

function LO:Looted(link)
    if not link then return end
    -- item data may still be on its way
    C_Timer.After(0.6, function() LO:Offer(link) end)
end

-- the gear in your bags: all of it, or only what came in since the last look
local lastBags = {}
function LO:ScanBags(onlyNew)
    if not on("upgrade") then return end
    local now = {}
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, ((C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0) do
            local it = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
            if it and it.hyperlink then
                local key = itemKey(it.hyperlink)
                now[key] = it.hyperlink
            end
        end
    end
    for key, link in pairs(now) do
        if not onlyNew or not lastBags[key] then
            -- something that comes in again counts as new: offered even if put aside before
            if onlyNew then snoozed[key] = nil end
            self:Offer(link)
        end
    end
    lastBags = now
end

-- the ignore lists emptied (options): said in the chat, and the bags looked at again right away
-- which: "upgrade" (never offered to put on) or "full" (never offered to delete)
function LO:ResetIgnored(which)
    local d, n = db(), 0
    local key = which == "full" and "ignore" or "ignoreUpgrade"
    for _ in pairs(d[key]) do n = n + 1 end
    d[key] = {}
    print("|cffffd100" .. ns.title .. "|r: " .. L().LO_IGNORE_RESET:format(n))
    self:Revisit(0.3)
end

-- a good moment: everything put aside is offered again
function LO:Revisit(delay)
    for k in pairs(snoozed) do snoozed[k] = nil end
    C_Timer.After(delay or 3, function() ns.Debug.Call("LootOpt", LO.ScanBags, LO, false) end)
end

-- your own loot from a chat message ("You receive loot: [x]")
local selfPatterns
local function selfLoot(msg)
    if not selfPatterns then
        selfPatterns = {}
        for _, f in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE,
            LOOT_ITEM_CREATED_SELF }) do
            if f then
                local p = f:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "%%d+")
                selfPatterns[#selfPatterns + 1] = "^" .. p .. "$"
            end
        end
    end
    for _, p in ipairs(selfPatterns) do
        local link = msg:match(p)
        if link then return link:match("|c%x+|Hitem:.-|h.-|h|r") or link:match("|Hitem:.-|h.-|h") end
    end
end

-- Bags full ----------------------------------------------------------------------------

local CC = C_Container
local function bagItem(bag, slot)
    if CC and CC.GetContainerItemInfo then return CC.GetContainerItemInfo(bag, slot) end
end

-- items in the bags that could go, cheapest first (vendor value x stack); quest items, items without value and
-- the ones you ignore stay
function LO:Candidates()
    local list, missing = {}, 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, ((CC and CC.GetContainerNumSlots and CC.GetContainerNumSlots(bag)) or 0) do
            local it = bagItem(bag, slot)
            if it and it.itemID and not db().ignore[it.itemID] and not it.isLocked then
                local i = info(it.hyperlink or it.itemID)
                -- item data not loaded yet: asked for, the window looks again in a moment
                if not i then
                    missing = missing + 1
                    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(it.itemID) end
                end
                local quest = i and i.classID == 12
                if i and not quest and i.sellPrice > 0 then
                    list[#list + 1] = { bag = bag, slot = slot, link = it.hyperlink, id = it.itemID,
                        count = it.stackCount or 1, value = i.sellPrice * (it.stackCount or 1), quality = i.quality or 1 }
                end
            end
        end
    end
    table.sort(list, function(a, b) if a.value ~= b.value then return a.value < b.value end return a.quality < b.quality end)
    return list, missing
end

-- the first loot item still lying there, with its value. Only real items count (no coins, no currencies, nothing the
-- game keeps secret); what each slot held is kept in the debug data.
local LOOT_ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or LOOT_SLOT_ITEM or 1
local function plainStr(v) return type(v) == "string" and not ns.Secret(v) and v or nil end
local function plainNum(v) return type(v) == "number" and not ns.Secret(v) and v or nil end
local function describe(v) if ns.Secret(v) then return "secret" end return tostring(v) end
local function pendingLoot()
    local seen = {}
    local found
    for i = 1, (plainNum(GetNumLootItems and GetNumLootItems()) or 0) do
        local kind = GetLootSlotType and GetLootSlotType(i)
        local rawLink = GetLootSlotLink and GetLootSlotLink(i)
        local tex, name, count, quality, _
        if GetLootSlotInfo then tex, name, count, _, quality = GetLootSlotInfo(i) end
        seen[#seen + 1] = { slot = i, kind = describe(kind), link = describe(rawLink), name = describe(name), count = describe(count) }
        local link = plainStr(rawLink)
        local isItem = plainNum(kind) == nil or kind == LOOT_ITEM
        if not found and link and isItem and link:find("item:") then
            local inf = info(link)
            local n = plainNum(count) or 1
            local value = inf and plainNum(inf.sellPrice) and inf.sellPrice * n or nil
            found = { link, value, i, { icon = plainStr(tex) or plainNum(tex), name = plainStr(name), quality = plainNum(quality) } }
        end
    end
    ns.Debug.Set("lootSlots", seen)
    if found then return found[1], found[2], found[3], found[4] end
end

function LO:FullFrame()
    if self.full then return self.full end
    local f = dialog("ForeverQoLPanelBagsFull", 440, 236)
    f.lootLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.lootLabel:SetPoint("TOPLEFT", 22, -46)
    f.lootRow = itemRow(f)
    f.lootRow:SetPoint("TOPLEFT", 22, -60)
    f.lootRow:SetWidth(396)
    f.bagLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.bagLabel:SetPoint("TOPLEFT", f.lootRow, "BOTTOMLEFT", 0, -10)
    f.bagRow = itemRow(f)
    f.bagRow:SetPoint("TOPLEFT", f.bagLabel, "BOTTOMLEFT", 0, -4)
    f.bagRow:SetWidth(396)
    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.count:SetPoint("TOPRIGHT", -24, -46)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.hint:SetPoint("BOTTOM", 0, 48)
    f.hint:SetTextColor(1, 0.55, 0.2)
    f.prev = button(f, 30, "<")
    f.prev:SetPoint("BOTTOMLEFT", 20, 16)
    f.nxt = button(f, 30, ">")
    f.nxt:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
    f.swap = button(f, 110, L().LO_SWAP)
    f.swap:SetPoint("LEFT", f.nxt, "RIGHT", 10, 0)
    f.delete = button(f, 90, L().LO_DELETE)
    f.delete:SetPoint("LEFT", f.swap, "RIGHT", 4, 0)
    f.ign = button(f, 100, L().LO_IGNORE)
    f.ign:SetPoint("LEFT", f.delete, "RIGHT", 4, 0)
    f.prev:SetScript("OnClick", function() LO:Step(-1) end)
    f.nxt:SetScript("OnClick", function() LO:Step(1) end)
    f.ign:SetScript("OnClick", function()
        local c = f.list and f.list[f.index]
        if c then db().ignore[c.id] = true end
        LO:RefreshFull()
    end)
    f.delete:SetScript("OnClick", function() LO:Delete(false) end)
    f.swap:SetScript("OnClick", function() LO:Delete(true) end)
    self.full = f
    return f
end

function LO:RefreshFull(keepIndex)
    local f = self:FullFrame()
    local missing
    f.list, missing = self:Candidates()
    f.index = keepIndex and min(f.index or 1, #f.list) or 1
    if f.index < 1 then f.index = 1 end
    self:DrawFull()
end

function LO:Step(d)
    local f = self.full
    if not (f and f.list and #f.list > 0) then return end
    f.index = (f.index - 1 + d) % #f.list + 1
    self:DrawFull()
end

function LO:DrawFull()
    local f = self.full
    local link0 = pendingLoot()
    ns.Debug.Set("lootBagsFull", { candidates = f.list and #f.list or 0, loot = link0 ~= nil, open = self.lootOpen })
    -- nothing to swap and no loot left: no empty window
    if (not f.list or #f.list == 0) and not link0 then f:Hide() return end
    f:Skin()
    f.title:SetText(L().LO_FULL_TITLE)
    local link, lootValue, _, fallback = pendingLoot()
    f.lootLabel:SetText(L().LO_LOOT)
    f.lootRow:Set(link, link and (lootValue and ns.Money(lootValue) or "…") or nil, fallback)
    f.bagLabel:SetText(L().LO_CHEAPEST)
    local c = f.list[f.index]
    f.bagRow:Set(c and c.link, c and ((c.count > 1 and (c.count .. "x  ") or "") .. ns.Money(c.value)) or nil)
    f.count:SetText(c and (f.index .. " / " .. #f.list) or "")
    f.hint:SetText(c and link and lootValue and lootValue < c.value and L().LO_LOOT_CHEAPER or "")
    for _, b in ipairs({ f.prev, f.nxt, f.swap, f.delete, f.ign }) do b:SetEnabled(c ~= nil) end
    f.swap:SetEnabled(c ~= nil and link ~= nil)
end

-- delete the chosen bag item (green and better asks first); swap: then pick up the loot
function LO:Delete(swap)
    local f = self.full
    local c = f and f.list and f.list[f.index]
    if not c or InCombatLockdown() then return end
    local function go()
        if CC and CC.PickupContainerItem then CC.PickupContainerItem(c.bag, c.slot) end
        if CursorHasItem and CursorHasItem() then DeleteCursorItem() end
        if swap then LO:LootWhenFree(8) end
        C_Timer.After(0.4, function() if f:IsShown() then LO:RefreshFull(true) end end)
    end
    if (c.quality or 0) >= 2 and StaticPopupDialogs then
        StaticPopupDialogs.FQP_LO_DELETE = {
            text = L().LO_DELETE_ASK, button1 = YES or "Yes", button2 = NO or "No", OnAccept = go,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("FQP_LO_DELETE", c.link)
    else
        go()
    end
end

-- free slots in the normal bags
local function freeSlots()
    local n = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        if CC and CC.GetContainerNumFreeSlots then
            local free, family = CC.GetContainerNumFreeSlots(bag)
            if (family or 0) == 0 then n = n + (free or 0) end
        end
    end
    return n
end

-- after deleting: the loot is picked up as soon as the bags have room (the game takes a moment), up to `tries` times
function LO:LootWhenFree(tries)
    C_Timer.After(0.25, function()
        if not self.lootOpen then return end
        local link, _, slot = pendingLoot()
        if not slot then return end
        if freeSlots() > 0 then
            LootSlot(slot)
        elseif tries > 1 then
            self:LootWhenFree(tries - 1)
        end
    end)
end

function LO:BagsFull()
    if not on("bagsFull") or not self.lootOpen then return end
    self:RefreshFull()
    self.full:Show()
    -- the loot list and item data may not be ready at the moment of the error: drawn again shortly after
    for _, delay in ipairs({ 0.2, 0.6, 1.2 }) do
        C_Timer.After(delay, function()
            if self.full:IsShown() then ns.Debug.Call("LootOpt", LO.RefreshFull, LO, true) end
        end)
    end
end

-- Events --------------------------------------------------------------------------------

ns.OnLogin(function()
    -- registered a few seconds after login: item tooltips run their calls in the order they were registered, so the
    -- comparison line comes after what other addons add (the calls for all types run before those, not after)
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt then
            -- placed when the item tooltip shows (its size is known then), gone with it
            hooksecurefunc(tt, "Show", function(t) ns.Debug.Call("LootOpt", place, t) end)
            tt:HookScript("OnTooltipCleared", function(t) t.fqpLoot = nil; t.fqpDE = nil; place(t) end)
            tt:HookScript("OnHide", function(t) if tip and tip.owner == t then tip:Hide() end end)
        end
    end
    C_Timer.After(3, function()
        local TDP = TooltipDataProcessor
        if not (TDP and TDP.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
        TDP.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data) ns.Debug.Call("LootOpt", LO.Tooltip, LO, tt, data) end)
    end)
    ns.On("CHAT_MSG_LOOT", function(_, msg)
        if type(msg) ~= "string" or ns.Secret(msg) then return end
        local link = selfLoot(msg)
        if link then ns.Debug.Call("LootOpt", LO.Looted, LO, link) end
    end)
    ns.On("LOOT_OPENED", function() LO.lootOpen = true end)
    ns.On("LOOT_READY", function() LO.lootOpen = true end)
    -- the loot or the bags changed while the window is open: drawn again
    local function redraw()
        if LO.full and LO.full:IsShown() then ns.Debug.Call("LootOpt", LO.RefreshFull, LO, true) end
    end
    ns.On("LOOT_SLOT_CLEARED", redraw)
    ns.On("LOOT_SLOT_CHANGED", redraw)
    ns.On("GET_ITEM_INFO_RECEIVED", redraw)
    ns.On("BAG_UPDATE_DELAYED", redraw)
    ns.On("LOOT_CLOSED", function()
        LO.lootOpen = false
        if LO.full and LO.full:IsShown() then LO.full:Hide() end
    end)
    ns.On("UI_ERROR_MESSAGE", function(_, a, b)
        local msg = type(b) == "string" and b or a
        if msg == ERR_INV_FULL or msg == ERR_BAG_FULL then ns.Debug.Call("LootOpt", LO.BagsFull, LO) end
    end)
    ns.On("PLAYER_REGEN_ENABLED", function()
        if LO.up and LO.up:IsShown() then LO.up.equip:SetEnabled(true) end
        if LO.afterCombat then LO.afterCombat = false; LO:NextUpgrade() end
    end)
    ns.On("PLAYER_ENTERING_WORLD", function() LO:Revisit(4) end)
    ns.On("PLAYER_LEVEL_UP", function() LO:Revisit(2) end)
    ns.On("BAG_UPDATE_DELAYED", function()
        if LO.bagTimer then return end
        LO.bagTimer = true
        C_Timer.After(0.5, function() LO.bagTimer = false; ns.Debug.Call("LootOpt", LO.ScanBags, LO, true) end)
    end)
end)

local _, ns = ...

-- Beast tooltip for hunters: on a tameable beast, the pet abilities it teaches (green: new for you, grey: known
-- already) and its attack speed (read live from the game; tamed pets keep it in Forever). Which beast teaches what
-- comes from Petopia (BeastData.lua); the options name the source. What you know is read from the Beast Training
-- window whenever it is open, per character.
-- Names in the client's language: a spell id per ability gives the game's own name.
-- Abilities in that window are matched by name and by icon (Forever's icon and Petopia's).
local B = {}
ns.Beasts = B

-- Rank 1 spell ids of all 22 abilities, found in Forever's data on Wowhead (pet abilities, Petopia's names): with
-- them the game gives each name in the client's language. Forever's Bite and Demoralizing Screech have other icons
-- than Petopia lists; the icons come from the game too.
local SPELL = {
    bite = 17253, charge = 7371, claw = 16827, cower = 1742, dash = 23099, demoralizingscreech = 24423,
    dismember = 1264758, dive = 23145, dustcloud = 1265899, furioushowl = 24604, lightningbreath = 24844,
    ["mine!"] = 1265054, pinch = 1264735, prowl = 24450, savagerend = 1265065, scorpidpoison = 24640,
    shellshield = 26064, swipe = 1264494, tendonrip = 1265038, thunderstomp = 26090, trickstersdance = 1310612,
    web = 1265843,
}

local function L() return ns.L end
local function on()
    local t = ns.db.tooltip
    return t.enabled and t.beasts and select(2, UnitClass("player")) == "HUNTER"
end
local function charKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end

local function norm(s) return s and tostring(s):lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "") end

-- icon (file id or lower-case path / name) -> key, name (English and the client's language) -> key
local iconMap, nameMap
local function maps()
    if iconMap then return iconMap, nameMap end
    iconMap, nameMap = {}, {}
    local probe = UIParent:CreateTexture(nil, "BACKGROUND")
    local function addIcon(icon, key)
        if not icon then return end
        if type(icon) == "number" then iconMap[icon] = key return end
        local path = icon:find("[\\/]") and icon or ("Interface\\Icons\\" .. icon)
        iconMap[path:lower()] = key
        iconMap[(path:match("([^\\/]+)$") or ""):lower()] = key
        probe:SetTexture(path)
        local id = probe.GetTextureFileID and probe:GetTextureFileID()
        if type(id) == "number" then iconMap[id] = key end
    end
    for key, a in pairs(ns.BeastData.abilities) do
        addIcon(a[2], key)
        nameMap[norm(a[1])] = key
        if SPELL[key] then
            addIcon(ns.SpellIcon(SPELL[key]), key)
            local n = ns.SpellName(SPELL[key])
            if n and not ns.Secret(n) then nameMap[norm(n)] = key end
        end
    end
    probe:Hide()
    return iconMap, nameMap
end

local function keyOf(name, icon)
    local im, nm = maps()
    local key = name and not ns.Secret(name) and nm[norm(name)]
    if key then return key end
    if type(icon) == "string" then
        return im[icon:lower()] or im[(icon:match("([^\\/]+)$") or ""):lower()]
    end
    return icon and im[icon]
end

-- Beast Training window: highest known rank per ability, and the names in the client's language
function B:ReadTraining(event)
    local info = { event = event, api = (GetNumCrafts and GetCraftInfo) and "craft" or "none" }
    ns.Debug.Set("beastTraining", info)
    if not (GetNumCrafts and GetCraftInfo) then return end
    local known, names, found, sample = {}, {}, 0, {}
    local n = GetNumCrafts() or 0
    for i = 1, n do
        local name, rankText, kind = GetCraftInfo(i)
        local icon = GetCraftIcon and GetCraftIcon(i)
        if #sample < 6 then sample[#sample + 1] = { name = name, rank = rankText, kind = kind, icon = icon } end
        if kind ~= "header" then
            local key = keyOf(name, icon)
            if key then
                found = found + 1
                local rank = tonumber(rankText and tostring(rankText):match("%d+")) or 1
                known[key] = math.max(known[key] or 0, rank)
                if name and not ns.Secret(name) then names[key] = name end
            end
        end
    end
    info.crafts, info.matched, info.sample = n, found, sample
    info.window = GetCraftName and GetCraftName() or nil
    -- another craft window (enchanting) matches nothing and changes nothing
    if found == 0 then return end
    ns.db.beasts = ns.db.beasts or { known = {}, names = {} }
    ns.db.beasts.known[charKey()] = known
    for k, v in pairs(names) do ns.db.beasts.names[k] = v end
end

-- Forever shows Beast Training in the trainer window (TRAINER_SHOW), its list being the abilities you know (used:
-- your pet has it too, available: you can teach it, unavailable: not this pet). A real trainer (an NPC) is skipped.
function B:ReadTrainer(event)
    local info = { event = event, api = (GetNumTrainerServices and GetTrainerServiceInfo) and "trainer" or "none" }
    ns.Debug.Set("beastTraining", info)
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
    info.npc = UnitExists("npc") and true or false
    if info.npc or self.reading then return end
    -- the window's filters may hide entries: all on while reading, then back as they were
    self.reading = true
    local saved = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, t in ipairs({ "available", "unavailable", "used" }) do
            saved[t] = GetTrainerServiceTypeFilter(t)
            if not saved[t] then pcall(SetTrainerServiceTypeFilter, t, 1) end
        end
    end
    local known, names, found, sample = {}, {}, 0, {}
    local n = GetNumTrainerServices() or 0
    -- protected: the filters must come back and the flag be cleared even if reading fails
    -- Forever returns name, status, icon (no rank); the rank is looked for in every value and the description
    local ok, err = pcall(function()
        for i = 1, n do
            local values = { GetTrainerServiceInfo(i) }
            local name, status = values[1], values[2]
            local icon = GetTrainerServiceIcon and GetTrainerServiceIcon(i)
            if type(values[3]) == "number" and not icon then icon = values[3] end
            local rank
            for j = 2, #values do
                local v = values[j]
                if type(v) == "string" and not ns.Secret(v) then rank = rank or tonumber(v:match("(%d+)")) end
            end
            -- "Biss (Rang 2)": only a number in brackets at the end counts as the rank
            if not rank and type(name) == "string" and not ns.Secret(name) then
                local inner = name:match("%(([^)]*)%)%s*$")
                rank = inner and tonumber(inner:match("%d+"))
            end
            local desc = GetTrainerServiceDescription and GetTrainerServiceDescription(i)
            if #sample < 12 then
                local copy = {}
                for j = 1, math.min(#values, 8) do copy[j] = values[j] end
                sample[#sample + 1] = { values = copy, icon = icon, desc = desc }
            end
            if status ~= "header" then
                local key = keyOf(name and tostring(name):gsub("%s*%(.-%)$", "") or nil, icon)
                if key then
                    found = found + 1
                    known[key] = math.max(known[key] or 0, rank or 1)
                    if name and not ns.Secret(name) then names[key] = tostring(name):gsub("%s*%(.-%)$", "") end
                end
            end
        end
    end)
    for t, v in pairs(saved) do if not v then pcall(SetTrainerServiceTypeFilter, t, 0) end end
    self.reading = false
    if not ok then info.error = tostring(err) return end
    info.services, info.matched, info.sample = n, found, sample
    -- without an NPC this is Beast Training: also when none of its abilities is one a beast teaches (you know
    -- none of those yet, so all of them are new)
    if n == 0 then return end
    ns.db.beasts = ns.db.beasts or { known = {}, names = {} }
    ns.db.beasts.known[charKey()] = known
    for k, v in pairs(names) do ns.db.beasts.names[k] = v end
end

-- The pet's spell book: its abilities with the names the game uses ("Biss"), matched by icon
function B:ReadPetBook()
    local book = BOOKTYPE_PET or "pet"
    local count = HasPetSpells and HasPetSpells()
    if not count or count == 0 then return end
    local names = {}
    for i = 1, count do
        local name, icon
        if C_SpellBook and C_SpellBook.GetSpellBookItemName and Enum and Enum.SpellBookSpellBank then
            name = C_SpellBook.GetSpellBookItemName(i, Enum.SpellBookSpellBank.Pet)
            icon = C_SpellBook.GetSpellBookItemTexture and C_SpellBook.GetSpellBookItemTexture(i, Enum.SpellBookSpellBank.Pet)
        elseif GetSpellBookItemName then
            name = GetSpellBookItemName(i, book)
            icon = GetSpellBookItemTexture and GetSpellBookItemTexture(i, book)
        end
        if name and not ns.Secret(name) then
            local key = keyOf(nil, icon) or keyOf(name, nil)
            if key then names[key] = name end
        end
    end
    ns.Debug.Set("beastPetBook", { count = count, matched = names })
    if next(names) then
        ns.db.beasts = ns.db.beasts or { known = {}, names = {} }
        for k, v in pairs(names) do ns.db.beasts.names[k] = v end
    end
end

local function known(key)
    local b = ns.db.beasts
    local mine = b and b.known[charKey()]
    if not mine then return nil end   -- never opened the window: unknown
    return mine[key] or 0
end

-- the window's name, else the game's name for the spell, else Petopia's (English)
local function abilityName(key)
    local b = ns.db.beasts
    if b and b.names[key] then return b.names[key] end
    local n = SPELL[key] and ns.SpellName(SPELL[key])
    if n and not ns.Secret(n) then return n end
    return ns.BeastData.abilities[key][1]
end

-- npc id from the unit's GUID ("Creature-0-...-<id>-...")
local function npcID(unit)
    local guid = UnitGUID(unit)
    if not guid or ns.Secret(guid) then return nil end
    local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
    if kind ~= "Creature" then return nil end
    return tonumber(id)
end

function B:Unit(tt)
    if not on() or tt.fqpBeast then return end
    local _, unit = tt:GetUnit()
    if not unit or ns.Secret(unit) or UnitIsPlayer(unit) then return end
    -- only tameable families have a family
    local family = UnitCreatureFamily and UnitCreatureFamily(unit)
    if not family or ns.Secret(family) then return end
    tt.fqpBeast = true
    local id = npcID(unit)
    local teaches = id and ns.BeastData.npcs[id]
    -- our lines, collected first: a small gap separates them from the game's own lines
    local lines = {}
    if teaches then
        for i = 1, #teaches, 2 do
            local key, rank = teaches[i], teaches[i + 1]
            if ns.BeastData.abilities[key] then
                local have = known(key)
                local text = L().BEAST_TEACHES:format(abilityName(key), rank)
                if have == nil then
                    lines[#lines + 1] = { text, 1, 0.82, 0 }
                elseif have >= rank then
                    lines[#lines + 1] = { text .. "  |cff9d9d9d(" .. L().BEAST_KNOWN .. ")|r", 0.62, 0.62, 0.62 }
                else
                    lines[#lines + 1] = { text .. "  |cff20ff20(" .. L().BEAST_NEW .. ")|r", 0.12, 1, 0 }
                end
            end
        end
    end
    local ok, speed = pcall(UnitAttackSpeed, unit)
    if ok and speed and not ns.Secret(speed) and speed > 0 then
        local sp = string.format("%.1f", speed)
        if ns.language ~= "enUS" and ns.language ~= "zhCN" then sp = sp:gsub("%.", ",") end
        lines[#lines + 1] = { L().BEAST_SPEED:format(sp), 1, 1, 1 }
    end
    if #lines == 0 then return end
    tt:AddLine(" ")
    for _, l in ipairs(lines) do tt:AddLine(l[1], l[2], l[3], l[4]) end
    local added = true
    if added then tt:Show() end
end

ns.OnLogin(function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
            ns.Debug.Call("Beasts", B.Unit, B, tt)
        end)
    end
    -- the flag lives as long as one tooltip content
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipCleared", function(tt) tt.fqpBeast = nil end)
    end
    local function read(event) ns.Debug.Call("Beasts", B.ReadTraining, B, event) end
    ns.On("CRAFT_SHOW", read)
    ns.On("CRAFT_UPDATE", read)
    -- Forever: Beast Training is a trainer window; its list may fill in a moment after it opens
    local function trainer(event)
        ns.Debug.Call("Beasts", B.ReadTrainer, B, event)
        C_Timer.After(0.3, function() ns.Debug.Call("Beasts", B.ReadTrainer, B, event) end)
    end
    ns.On("TRAINER_SHOW", trainer)
    local function petBook() ns.Debug.Call("Beasts", B.ReadPetBook, B) end
    ns.On("PET_BAR_UPDATE", petBook)
    ns.On("UNIT_PET", function(_, unit) if unit == "player" then C_Timer.After(1, petBook) end end)
    C_Timer.After(5, petBook)
    ns.On("TRAINER_UPDATE", function(event) ns.Debug.Call("Beasts", B.ReadTrainer, B, event) end)
end)

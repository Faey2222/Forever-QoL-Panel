local _, ns = ...

-- Action bars: newly learned spells go to free slots (main bar first, then the other shown bars), a new rank takes
-- the place of the lower rank on every bar. Works out of combat; in combat the work waits for its end.
local AB = { queue = {} }
ns.ActionBar = AB

-- action bars in Edit Mode order: number, slots, frame that must be shown (main bar: always)
local BARS = {
    { 1, 1, nil }, { 2, 61, "MultiBarBottomLeft" }, { 3, 49, "MultiBarBottomRight" }, { 4, 25, "MultiBarRight" },
    { 5, 37, "MultiBarLeft" }, { 6, 145, "MultiBar5" }, { 7, 157, "MultiBar6" }, { 8, 169, "MultiBar7" },
}

local function db() return ns.db.actionbar end

local function say(fmtKey, ...)
    if db().messages then print("|cffffd100" .. ns.title .. "|r: " .. string.format(ns.L[fmtKey], ...)) end
end

-- Spell facts across client generations -------------------------------------------

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

local function spellRank(id)
    local text = (C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id))
        or (GetSpellSubtext and GetSpellSubtext(id))
    return text and tonumber(text:match("%d+")) or nil
end

local function isPassive(id)
    if C_Spell and C_Spell.IsSpellPassive then return C_Spell.IsSpellPassive(id) end
    return IsPassiveSpell and IsPassiveSpell(id)
end

local BOOK = BOOKTYPE_SPELL or "spell"

-- Every spell in the player's spellbook: [spellID] = { index, tab }
local function scanBook()
    local found = {}
    local SB = C_SpellBook
    if SB and SB.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for tab = 1, SB.GetNumSpellBookSkillLines() do
            local line = SB.GetSpellBookSkillLineInfo(tab)
            if line and not line.shouldHide then
                for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local info = SB.GetSpellBookItemInfo(i, bank)
                    local isSpell = info and (info.itemType == (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1))
                    if isSpell and info.spellID and not info.isPassive and not info.isOffSpec then
                        found[info.spellID] = { index = i, tab = tab, bank = bank }
                    end
                end
            end
        end
    elseif GetNumSpellTabs then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, count = GetSpellTabInfo(tab)
            for i = offset + 1, offset + count do
                local kind, id = GetSpellBookItemInfo(i, BOOK)
                if kind == "SPELL" and id and not isPassive(id) then found[id] = { index = i, tab = tab, bank = BOOK } end
            end
        end
    end
    return found
end

local function pickup(id, entry)
    if C_SpellBook and C_SpellBook.PickupSpellBookItem and entry then
        C_SpellBook.PickupSpellBookItem(entry.index, entry.bank)
    elseif PickupSpellBookItem and entry then
        PickupSpellBookItem(entry.index, entry.bank)
    elseif C_Spell and C_Spell.PickupSpell then
        C_Spell.PickupSpell(id)
    else
        PickupSpell(id)
    end
end

-- Bars ----------------------------------------------------------------------------

local function barShown(frameName)
    if not frameName then return true end
    local f = _G[frameName]
    return f and f:IsShown()
end

local function eachSlot(fn)
    for _, bar in ipairs(BARS) do
        if barShown(bar[3]) then
            for i = 0, 11 do
                if fn(bar[2] + i, bar[1], i + 1) then return end
            end
        end
    end
end

local function spellIn(slot)
    local kind, id = GetActionInfo(slot)
    if kind == "spell" and id then return id end
end

local function place(slot, id, entry)
    ClearCursor()
    pickup(id, entry)
    PlaceAction(slot)
    ClearCursor()
end

-- Handling one new spell ------------------------------------------------------------

function AB:Handle(id, entry)
    local name = spellName(id)
    if not name then return end
    local rank = spellRank(id)

    -- a new rank: every slot with a lower rank of the same spell gets the new one
    local onBar, replaced = false, false
    eachSlot(function(slot)
        local old = spellIn(slot)
        if old and spellName(old) == name then
            onBar = true
            if old ~= id and db().replaceRanks then
                local oldRank = spellRank(old)
                if not (rank and oldRank) or oldRank < rank then
                    place(slot, id, entry)
                    replaced = true
                    say("AB_RANK", name, oldRank or "?", rank or "?")
                end
            end
        end
    end)
    if onBar or replaced or not db().placeNew then return end
    if entry.tab == 1 and not db().general then return end

    -- a new spell: the first free slot
    local done = false
    eachSlot(function(slot, bar, n)
        if not HasAction(slot) then
            place(slot, id, entry)
            say("AB_PLACED", name, n, bar)
            done = true
            return true
        end
    end)
    if not done then say("AB_FULL", name) end
end

function AB:Work()
    if InCombatLockdown() or (GetCursorInfo and GetCursorInfo()) then return end
    local list = self.queue
    self.queue = {}
    for _, job in ipairs(list) do ns.Debug.Call("ActionBar", self.Handle, self, job[1], job[2]) end
end

-- By hand (options, /fqp ranks, /fqp place) ------------------------------------------

-- the highest rank of every spell in the book: [name] = { id, entry, rank }
local function highestRanks(book)
    local best = {}
    for id, entry in pairs(book) do
        local name = spellName(id)
        if name then
            local rank = spellRank(id) or 0
            local b = best[name]
            if not b or rank > b.rank or (rank == b.rank and entry.index > b.entry.index) then
                best[name] = { id = id, entry = entry, rank = rank }
            end
        end
    end
    return best
end

local function busy()
    if InCombatLockdown() then
        print("|cffffd100" .. ns.title .. "|r: " .. ns.L.AB_COMBAT)
        return true
    end
end

-- Every spell on the bars gets its highest known rank.
function AB:UpdateRanks()
    if busy() then return end
    local best, n = highestRanks(scanBook()), 0
    eachSlot(function(slot)
        local old = spellIn(slot)
        local b = old and best[spellName(old) or ""]
        if b and b.id ~= old and b.rank > (spellRank(old) or 0) then
            place(slot, b.id, b.entry)
            n = n + 1
        end
    end)
    print("|cffffd100" .. ns.title .. "|r: " .. string.format(ns.L.AB_RANKS_DONE, n))
end

-- Every spell that is on no bar yet goes to a free slot (spellbook order, General tab only if switched on).
function AB:PlaceMissing()
    if busy() then return end
    local onBar = {}
    eachSlot(function(slot)
        local id = spellIn(slot)
        if id then onBar[spellName(id) or ""] = true end
    end)
    local list = {}
    for name, b in pairs(highestRanks(scanBook())) do
        if not onBar[name] and (b.entry.tab ~= 1 or db().general) then list[#list + 1] = b end
    end
    table.sort(list, function(a, b) return a.entry.index < b.entry.index end)
    local n, i = 0, 1
    eachSlot(function(slot)
        if not list[i] then return true end
        if not HasAction(slot) then
            place(slot, list[i].id, list[i].entry)
            n, i = n + 1, i + 1
        end
    end)
    print("|cffffd100" .. ns.title .. "|r: " .. string.format(ns.L.AB_PLACE_DONE, n, #list - n))
end

-- New spells: the spellbook compared with what this character has seen before (on the very first run everything
-- counts as seen, so nothing is moved around).
function AB:Scan()
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    local seen = db().seen[key]
    local book = scanBook()
    if not seen then
        seen = {}
        for id in pairs(book) do seen[id] = true end
        db().seen[key] = seen
        return
    end
    for id, entry in pairs(book) do
        if not seen[id] then
            seen[id] = true
            if db().enabled then self.queue[#self.queue + 1] = { id, entry } end
        end
    end
    if #self.queue > 0 then self:Work() end
end

ns.OnLogin(function()
    local pending
    local function later()
        if pending then return end
        pending = true
        C_Timer.After(0.5, function() pending = false; AB:Scan() end)
    end
    C_Timer.After(2, function()
        AB:Scan()
        ns.On("SPELLS_CHANGED", later)
    end)
    ns.On("PLAYER_REGEN_ENABLED", function() if #AB.queue > 0 then AB:Work() end end)
    ns.On("CURSOR_CHANGED", function() if #AB.queue > 0 then C_Timer.After(0.2, function() AB:Work() end) end end)
end)

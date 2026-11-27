local _, ns = ...

-- Questing together: in a group, the members using this addon tell each other their quests and progress over our
-- channel (Comm.lua, group only). From that:
--  1. quests you have and another member lacks: the panel element shows them, its menu shares them (the ones the
--     game lets you share; the others are listed greyed);
--  2. the quests the group is working on: a quest becomes active when, while grouped, someone holding it makes
--     progress on it and at least two members hold it. It stays until everyone holding it has finished it (so half
--     done quests are not forgotten), then folds away. Quests nobody moved on never show. The group leader can hide
--     a quest for everyone. A movable window (lock to fix it) lists them with every member's progress.
-- Messages: Q|id|done|progress (progress "3/8,0/1"), R|id (gone from the log), Y (send me your quests), H|id (hidden
-- by the leader), P|id (picked by the leader: shown for everyone), A|ids (the leader's active quests, to new members),
-- U|id|title (I am sharing this quest with you: accept it), N|id (the game refused me the quest you shared),
-- D|id (I turned in this quest you reported already), T|id (I just turned this quest in), K|id (the leader confirmed
-- that not all turned it in), B|id:done:progress;... (several quests at once).
local T = {}
ns.Together = T

local function db() return ns.db.together end
local function readable(v) if v == nil or ns.Secret(v) then return nil end return v end
-- your first name only (on Forever UnitName also gives the last name, as a second value)
local function me() return (UnitName("player")) end

T.members = {}   -- name -> { quests = { [id] = { done, prog } }, at }
T.mine = {}      -- [id] = { done, prog, title }

local function state()
    local d = db()
    d.state = d.state or { active = {}, hidden = {}, finished = {} }
    return d.state
end

function T.InGroup() return T.testing or (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or false end

-- you lead the group (in the test you do)
function T.Leader() return T.testing or (UnitIsGroupLeader and readable(UnitIsGroupLeader("player"))) and true or false end

-- the members of the group by name: { name = unit }
function T.Roster()
    local out = {}
    if T.testing then out[T.TEST_NAME] = "test" end
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            local u = "raid" .. i
            local n = readable(UnitName(u))
            if n and n ~= me() and not (UnitIsUnit and readable(UnitIsUnit(u, "player"))) then out[n] = u end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            local n = readable(UnitName(u))
            -- never yourself (Forever may answer for a token with your own first or last name)
            local self = UnitIsUnit and readable(UnitIsUnit(u, "player"))
            if n and n ~= me() and not self then out[n] = u end
        end
    end
    return out
end

-- a message from the group leader (only the leader may hide or pick quests for everyone)
local function fromLeader(sender)
    local unit = T.Roster()[sender]
    return unit and UnitIsGroupLeader and readable(UnitIsGroupLeader(unit)) and true or false
end

-- your quest log: [id] = { done, prog, title }
local function progressOf(id)
    local parts = {}
    local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
    for _, o in ipairs(type(objs) == "table" and objs or {}) do
        local have, need = readable(o.numFulfilled), readable(o.numRequired)
        if type(have) ~= "number" or type(need) ~= "number" or need <= 0 then
            have, need = o.finished and 1 or 0, 1
        end
        parts[#parts + 1] = have .. "/" .. need
    end
    return table.concat(parts, ",")
end

function T.Scan()
    local out = {}
    local QL = C_QuestLog
    if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return out end
    local zone   -- the header above a quest: its zone (or kind, e.g. "Class")
    for i = 1, (QL.GetNumQuestLogEntries() or 0) do
        local info = QL.GetInfo(i)
        local id = info and readable(info.questID)
        if info and info.isHeader then
            zone = readable(info.title)
        elseif id and id > 0 then
            local done = QL.IsComplete and readable(QL.IsComplete(id)) and true or false
            out[id] = { done = done, prog = progressOf(id), title = readable(info.title), zone = zone,
                level = readable(info.level) }
        end
    end
    -- quests under a folded zone header are missing from that list: the ones the others report are asked for
    -- directly, so you are not offered a quest you already have
    if QL.IsOnQuest then
        for _, m in pairs(T.members) do
            for id in pairs(m.quests) do
                if not out[id] and id < 900000 then
                    local ok, on = pcall(QL.IsOnQuest, id)
                    if ok and readable(on) then
                        local done = QL.IsComplete and readable(QL.IsComplete(id)) and true or false
                        local title = QL.GetTitleForQuestID and readable(QL.GetTitleForQuestID(id))
                        out[id] = { done = done, prog = progressOf(id), title = title }
                    end
                end
            end
        end
    end
    return out
end

-- A quest's colour by how hard it is for you, as the game's quest log shows it (grey: no XP any more, green, yellow,
-- orange, red: too hard). Only for quests in your log (their level is known); else the usual gold.
function T.TitleColor(id)
    local q = T.mine[id]
    local level = q and tonumber(q.level)
    if not level or level <= 0 then return 1, 0.82, 0 end
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
    end
    local diff = level - (UnitLevel("player") or level)
    if diff >= 5 then return 1, 0.1, 0.1
    elseif diff >= 3 then return 1, 0.5, 0.25
    elseif diff >= -2 then return 1, 1, 0
    elseif -diff <= (GetQuestGreenRange and GetQuestGreenRange() or 8) then return 0.25, 0.75, 0.25 end
    return 0.5, 0.5, 0.5
end

-- A quest's title: from your log, else remembered from when it was in it (after turning it in), else from the game.
T.titles = {}
function T.TitleOf(id)
    local q = T.mine[id]
    if q and q.title then return q.title end
    if T.titles[id] then return T.titles[id] end
    for _, m in pairs(T.members) do if m.quests[id] and m.quests[id].title then return m.quests[id].title end end
    local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and readable(C_QuestLog.GetTitleForQuestID(id))
    return t or ("#" .. id)
end

-- the title with its colour, for menus
function T.ColoredTitle(id, title)
    local r, g, b = T.TitleColor(id)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, title or ("#" .. id))
end

-- the sum of what is done, to tell progress
local function amount(prog, done)
    local n = done and 1000 or 0
    for have in tostring(prog or ""):gmatch("(%d+)/%d+") do n = n + tonumber(have) end
    return n
end

-- everyone holding a quest: you and the members who reported it
function T:Holders(id)
    local out = {}
    if self.mine[id] then out[#out + 1] = { name = me(), q = self.mine[id], self = true } end
    for name, m in pairs(self.members) do
        if m.quests[id] then out[#out + 1] = { name = name, q = m.quests[id] } end
    end
    return out
end

-- progress on a quest while grouped: active, if at least two hold it
function T:Progressed(id)
    if not self.InGroup() then return end
    local st = state()
    if st.finished[id] or st.hidden[id] then return end
    if #self:Holders(id) >= 2 then
        if not st.active[id] then st.active[id] = true end
    end
end

-- A shown quest done by everyone holding it: a sound (option soundAllDone) and a golden glow, "turn it in!"; it
-- stays until it is gone from every log (turned in or given up), then folds away and does not come back.
function T:CheckDone(id)
    local st = state()
    if not st.active[id] then return end
    local holders = self:Holders(id)
    if #holders == 0 then
        st.active[id] = nil
        st.finished[id] = true
        if st.allDone then st.allDone[id] = nil end
        self:StopAlarm(id, true)
        self:Fold(id, true)
        return
    end
    local all = true
    for _, h in ipairs(holders) do if not h.q.done then all = false end end
    st.allDone = st.allDone or {}
    if all and not st.allDone[id] then
        st.allDone[id] = true
        self:AllDone(id)
    elseif not all then
        st.allDone[id] = nil
    end
end

local function play(file)
    if PlaySoundFile then pcall(PlaySoundFile, ns.MEDIA .. "sounds\\" .. file .. ".ogg", "Master") end
end

function T:AllDone(id)
    if db().soundAllDone then play("questdone") end
    local b = self.frame and self.frame.blocks[id]
    if b and self.Glow then self.Glow(b, 0.5, 2) end
end

-- Turned in by some, not by all --------------------------------------------------------------------------------
-- Someone turns in a shown quest that others still hold: a timer starts (not everyone turns in at the very same
-- moment). Still held after it: a sound, the quest pulses red and a note next to the window says who turned it in
-- and who did not. It goes on until the group leader confirms it ("Got it", for everyone) or nobody holds the quest
-- any more. Option turnInWatch. Messages: T|id (I turned it in), K|id (the leader confirmed).

T.watch = {}   -- [id] = { alarm, acked }
T.TURNIN_SECS = 60

function T:StartWatch(id)
    if not db().turnInWatch or not state().active[id] then return end
    local w = self.watch[id]
    if w then return end
    w = {}
    self.watch[id] = w
    C_Timer.After(self.testing and 5 or T.TURNIN_SECS, function()
        if self.watch[id] ~= w or w.acked then return end
        if #self:Holders(id) > 0 then ns.Debug.Call("Together", self.Alarm, self, id) else self.watch[id] = nil end
    end)
end

-- who turned the quest in and who still holds it
function T:TurnInState(id)
    local gave, holding = {}, {}
    local mineDone = self.turnedIn[me()] and self.turnedIn[me()][id]
    if mineDone then gave[#gave + 1] = me() end
    for name, ids in pairs(self.turnedIn) do if name ~= me() and ids[id] then gave[#gave + 1] = name end end
    for _, h in ipairs(self:Holders(id)) do holding[#holding + 1] = h.name end
    table.sort(gave); table.sort(holding)
    return gave, holding
end

function T:Alarm(id)
    local w = self.watch[id]
    if not w or w.acked then return end
    w.alarm = true
    if db().soundTurnIn ~= false then play("turnin") end
    self:UpdateWindow()
    self:ShowTurnInNote(id)
end

-- the leader confirmed (or nobody holds it any more): the pulse and the note end
function T:StopAlarm(id, gone)
    local w = self.watch[id]
    if not w then return end
    if gone then self.watch[id] = nil else w.alarm, w.acked = false, true end
    if self.notes and self.notes[id] then self.notes[id]:Hide(); self:LayoutNotes() end
    self:UpdateWindow()
end

function T:Acknowledge(id)
    if not self.Leader() then return end
    if not self.testing then ns.Comm:SendGroup("K", id) end
    self:StopAlarm(id)
end

-- I turned a quest in (the game says so): the others are told
function T:MyTurnIn(id)
    if not id or not state().active[id] then return end
    self.turnedIn[me()] = self.turnedIn[me()] or {}
    self.turnedIn[me()][id] = true
    if not self.testing then ns.Comm:SendGroup("T", id) end
    self:StartWatch(id)
end

function T:OthersTurnIn(sender, id)
    self:OnTurnedIn(sender, id)
    self:StartWatch(id)
end

-- your log changed: what changed goes to the group; your own progress makes a quest active
function T:ApplyMine(snap)
    local old = self.mine
    self.mine = snap
    local grouped = self.InGroup()
    -- titles kept for when the quest has left the log (turned in, the others still on it)
    for id, q in pairs(snap) do if q.title then self.titles[id] = q.title end end
    for id, q in pairs(snap) do
        local o = old[id]
        local changed = not o or o.done ~= q.done or o.prog ~= q.prog
        if changed and grouped then ns.Comm:SendGroup("Q", id, q.done and 1 or 0, q.prog) end
        if o and amount(q.prog, q.done) > amount(o.prog, o.done) then self:Progressed(id) end
        if changed then self:CheckDone(id) end
    end
    for id in pairs(old) do
        if not snap[id] then
            if grouped then ns.Comm:SendGroup("R", id) end
            self:CheckDone(id)
        end
    end
    self:Changed()
end

-- everything of yours to the group (joining, asked for it); not more than every ten seconds
function T:SendAll(force)
    if not self.InGroup() then return end
    local now = GetTime()
    if not force and now - (self.lastAll or 0) < 10 then return end
    self.lastAll = now
    -- bundled: several quests per message (B|id:done:progress;id:done:progress...), so a full log arrives in a
    -- few messages instead of one per quest
    local chunk = {}
    local size = 0
    for id, q in pairs(self.mine) do
        local part = id .. ":" .. (q.done and 1 or 0) .. ":" .. tostring(q.prog or ""):gsub("[|:;]", "")
        if size + #part + 1 > 230 and #chunk > 0 then
            ns.Comm:SendGroup("B", table.concat(chunk, ";"))
            chunk, size = {}, 0
        end
        chunk[#chunk + 1] = part
        size = size + #part + 1
    end
    if #chunk > 0 then ns.Comm:SendGroup("B", table.concat(chunk, ";")) end
end

-- a bundle of quests (see SendAll)
function T:OnBundle(sender, text)
    for part in tostring(text or ""):gmatch("[^;]+") do
        local id, done, prog = part:match("^(%d+):(%d):(.*)$")
        id = tonumber(id)
        if id and id < ns.Comm.TEST_IDS then
            self:OnQuest(sender, id, done == "1", prog)
            self:CheckHeld(id)
        end
    end
end

-- Messages from the others --------------------------------------------------------------------------------

function T:OnQuest(sender, id, done, prog)
    local m = self.members[sender] or { quests = {} }
    self.members[sender] = m
    m.at = GetTime()
    local o = m.quests[id]
    local q = { done = done, prog = prog }
    m.quests[id] = q
    if o and amount(prog, done) > amount(o.prog, o.done) then self:Progressed(id) end
    self:CheckDone(id)
    self:Changed()
end

function T:OnRemoved(sender, id)
    local m = self.members[sender]
    if m then m.quests[id] = nil end
    self:CheckDone(id)
    self:Changed()
end

function T:OnHidden(sender, id)
    -- only the group leader may hide a quest for everyone
    if not fromLeader(sender) then return end
    local st = state()
    st.hidden[id], st.active[id] = true, nil
    self:Fold(id)
end

-- the leader picks a quest: shown for everyone, even without progress yet
function T:Pick(id)
    if not self.Leader() then return end
    local st = state()
    st.active[id], st.hidden[id], st.finished[id] = true, nil, nil
    ns.Comm:SendGroup("P", id)
    self:Changed()
end

function T:OnPicked(sender, id)
    if not fromLeader(sender) then return end
    local st = state()
    st.active[id], st.hidden[id], st.finished[id] = true, nil, nil
    self:Changed()
end

-- the leader tells new members which quests the group works on (and which are hidden)
function T:SendActive()
    if not self.Leader() or self.testing then return end
    local st, ids = state(), {}
    for id in pairs(st.active) do ids[#ids + 1] = id end
    for id in pairs(st.hidden) do ids[#ids + 1] = -id end
    if #ids > 0 then ns.Comm:SendGroup("A", table.concat(ids, ",")) end
end

function T:OnActive(sender, list)
    if not fromLeader(sender) then return end
    local st = state()
    for v in tostring(list or ""):gmatch("%-?%d+") do
        local id = tonumber(v)
        if math.abs(id) >= ns.Comm.TEST_IDS then
            -- a test quest of a development copy: left out
        elseif id > 0 then if not st.finished[id] then st.active[id] = true end
        else st.hidden[-id], st.active[-id] = true, nil end
    end
    self:Changed()
end

-- A list of quests ({ id, title, zone }) by zone: { { zone, items }, ... }; the zone you are in first, the others by
-- name, quests without one ("Other") last.
function T.ByZone(list)
    local here = readable(GetRealZoneText and GetRealZoneText()) or ""
    local other = ns.L.TOG_OTHER_ZONE
    local groups, byName = {}, {}
    for _, q in ipairs(list) do
        local z = q.zone or other
        local g = byName[z]
        if not g then
            g = { zone = z, items = {} }
            byName[z] = g
            groups[#groups + 1] = g
        end
        g.items[#g.items + 1] = q
    end
    local function rank(g) if g.zone == here then return 0 elseif g.zone == other then return 2 end return 1 end
    table.sort(groups, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return a.zone < b.zone
    end)
    return groups
end

-- quests the leader may pick: everything you hold that is not shown yet
function T:Pickable()
    local st, out = state(), {}
    for id, q in pairs(self.mine) do
        if not st.active[id] and not q.done then out[#out + 1] = { id = id, title = q.title or ("#" .. id), zone = q.zone } end
    end
    table.sort(out, function(a, b) return a.title < b.title end)
    return out
end

function T:Hide(id)
    if not self.Leader() then return end
    local st = state()
    st.hidden[id], st.active[id] = true, nil
    ns.Comm:SendGroup("H", id)
    self:Fold(id)
end

-- Sharing (the panel element's menu) ---------------------------------------------------------------------

-- your quests that a member using the addon lacks: { { id, title, missing = { names }, pushable } }
-- What the game said when sharing went wrong: name -> { [id] = "has" (already holds or did it) or "no" (cannot take
-- it, e.g. a quest before it is missing) }. A quest someone already has is not offered again; one they cannot take is
-- listed greyed as not shareable.
T.blocked = {}

function T:Missing()
    local out = {}
    local roster = self.Roster()
    for id, q in pairs(self.mine) do
        local missing, unable = {}, {}
        for name, m in pairs(self.members) do
            if roster[name] and not m.quests[id] and not q.done then
                local b = self.blocked[name] and self.blocked[name][id]
                if self.turnedIn[name] and self.turnedIn[name][id] then b = "has" end
                if b == "no" then unable[#unable + 1] = name
                elseif b ~= "has" then missing[#missing + 1] = name end
            end
        end
        if #missing > 0 then
            table.sort(missing)
            out[#out + 1] = { id = id, title = q.title or ("#" .. id), missing = missing, pushable = self.Pushable(id), zone = q.zone }
        elseif #unable > 0 then
            table.sort(unable)
            out[#out + 1] = { id = id, title = q.title or ("#" .. id), missing = unable, pushable = false, zone = q.zone }
        end
    end
    table.sort(out, function(a, b) if a.pushable ~= b.pushable then return a.pushable end return a.title < b.title end)
    return out
end

function T.Pushable(id)
    if T.testing and id > 900000 then return true end
    local QL = C_QuestLog
    if QL and QL.IsPushableQuest then
        local ok, yes = pcall(QL.IsPushableQuest, id)
        if ok then return readable(yes) and true or false end
    end
    if QL and QL.SetSelectedQuest and GetQuestLogPushable then
        pcall(QL.SetSelectedQuest, id)
        local ok, yes = pcall(GetQuestLogPushable)
        return ok and readable(yes) and true or false
    end
    return false
end

function T.Share(id)
    if T.testing and id > 900000 then
        -- in the test every second shared quest is refused by the partner, as the game does when a quest before it
        -- is missing
        T.testShares = (T.testShares or 0) + 1
        if T.testShares % 2 == 0 then T:Refused(T.TEST_NAME, id, "no") else T:OnQuest(T.TEST_NAME, id, false, "0/10") end
        return
    end
    -- the others' addon accepts it for them (U|id|title) and tells us if the game refused it (N|id)
    local q = T.mine[id]
    T.lastShare = { id = id, at = GetTime() }
    ns.Comm:SendGroup("U", id, q and q.title or "")
    ns.Comm:Flush()
    local QL = C_QuestLog
    if QL and QL.SetSelectedQuest then pcall(QL.SetSelectedQuest, id) end
    if QuestLogPushQuest then pcall(QuestLogPushQuest) end
end

-- sharing went wrong for someone: noted until the group changes
function T:Refused(name, id, why)
    if not (name and id) then return end
    if why == "done" then return self:OnTurnedIn(name, id) end
    self.blocked[name] = self.blocked[name] or {}
    self.blocked[name][id] = why
    self:Changed()
end

-- a member turned the quest in already: "turned in" instead of "lacks it", never offered to share
T.turnedIn = {}   -- name -> { [id] = true }
function T:OnTurnedIn(name, id)
    self.turnedIn[name] = self.turnedIn[name] or {}
    self.turnedIn[name][id] = true
    self:Changed()
end

-- The game's answers to the one sharing ("%s is already on that quest" and so on), as patterns; the name is the
-- first word of what the game puts in (Forever gives first and last name).
local PUSH = {
    ERR_QUEST_PUSH_ONQUEST_S = "has", ERR_QUEST_PUSH_ALREADY_DONE_S = "done",
    ERR_QUEST_PUSH_INVALID_S = "no", ERR_QUEST_PUSH_INVALID2_S = "no", ERR_QUEST_PUSH_NOT_ALLOWED_S = "no",
    ERR_QUEST_PUSH_LOW_LEVEL_S = "no", ERR_QUEST_PUSH_HIGH_LEVEL_S = "no", ERR_QUEST_PUSH_CLASS_S = "no",
    ERR_QUEST_PUSH_RACE_S = "no", ERR_QUEST_PUSH_WRONG_FACTION_S = "no", ERR_QUEST_PUSH_EXPANSION_S = "no",
    ERR_QUEST_PUSH_NOT_DAILY_S = "no", ERR_QUEST_PUSH_DIFFERENT_SERVER_DAILY_S = "no",
}
local pushPatterns
local function patterns()
    if pushPatterns then return pushPatterns end
    pushPatterns = {}
    for key, why in pairs(PUSH) do
        local s = _G[key]
        if type(s) == "string" and s:find("%s", 1, true) then
            local p = "^" .. s:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
            pushPatterns[#pushPatterns + 1] = { p, why }
        end
    end
    return pushPatterns
end

-- A system message. For the one sharing: the game's answer about a member. For the one receiving: the game refused
-- the shared quest (the message names its title, e.g. "... you must first complete the quests before it") -> the
-- sharer is told (N|id), as the game tells only us.
function T:SystemMessage(msg)
    msg = readable(msg)
    if type(msg) ~= "string" then return end
    local ls = self.lastShare
    if ls and GetTime() - ls.at < 15 then
        for _, p in ipairs(patterns()) do
            local who = msg:match(p[1])
            if who then
                self:Refused(who:match("^([^%s%-]+)") or who, ls.id, p[2])
                return
            end
        end
    end
    local ex = self.expect
    if ex and GetTime() - ex.at < 20 and ex.title ~= "" and msg:find(ex.title, 1, true) then
        self.expect = nil
        ns.Comm:SendGroup("N", ex.id)
    end
end

-- someone shares a quest with us through the addon: when its window comes, it is accepted (option autoAccept)
function T:OnShare(sender, id, title)
    if not db().enabled then return end
    self.expect = { id = id, title = title or "", from = sender, at = GetTime() }
    self:CheckHeld(id)   -- already ours after all: the sharer learns it from our list
end

local function expected(id, title)
    local ex = T.expect
    if not ex or GetTime() - ex.at > 20 then return nil end
    if (id and id == ex.id) or (title and title ~= "" and title == ex.title) then return ex end
end

function T:QuestDetail()
    local id = GetQuestID and readable(GetQuestID())
    local title = GetTitleText and readable(GetTitleText())
    if not expected(id, title) then return end
    self.expect = nil
    if db().autoAccept and AcceptQuest then AcceptQuest() end
end

-- quests some must confirm (escorts started by someone): the same
function T:AcceptConfirm(_, title)
    if not expected(nil, readable(title)) then return end
    self.expect = nil
    if db().autoAccept and ConfirmAcceptQuest then
        ConfirmAcceptQuest()
        if StaticPopup_Hide then StaticPopup_Hide("QUEST_ACCEPT") end
    end
end

-- members without the addon: nothing known about their quests
function T:WithoutAddon()
    local out = {}
    for name in pairs(self.Roster()) do
        if not (self.members[name] or ns.Comm.seen[name] or (ns.GroupXP and ns.GroupXP.members[name])) then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

-- The window ---------------------------------------------------------------------------------------------
-- A title bar (a soft golden band), the active quests one below the other with a fading line between them (like
-- the panel's), each with every member's progress; below them the quests a member lacks, with a button to share.
-- The leader picks more quests with the "+" in the title bar and hides one with its cross. Everything moves: a new
-- quest unfolds and glows, a member's progress flashes, a finished or hidden quest folds away.

local ROW, HEAD, PAD, W, TOP = 16, 22, 14, 300, 34
local GOLD = { 0.77, 0.63, 0.43 }

-- a member's class: yours, from the group's unit, the test partner's made up
function T.ClassOf(name)
    if T.testing and name == T.TEST_NAME then return "HUNTER" end
    local unit = name == me() and "player" or T.Roster()[name]
    if not unit or unit == "test" then return nil end
    local _, class = UnitClass(unit)
    class = readable(class)
    -- the client may keep it from the unit: the character behind its GUID tells it as well
    if not class and UnitGUID and GetPlayerInfoByGUID then
        local guid = readable(UnitGUID(unit))
        if guid then
            local ok, _, cls = pcall(GetPlayerInfoByGUID, guid)
            class = ok and readable(cls) or nil
        end
    end
    return class
end

-- a member's name as shown: "First Last" when the window is wide enough, else "First L." (Forever names have a
-- last name in the realm's place; a name without one stays as it is)
local function firstChar(s) return s:match("^[%z\1-\127\194-\244][\128-\191]*") or s:sub(1, 1) end
function T.ShowName(name, width)
    local last
    if name == me() then
        local _, l = UnitName("player")
        last = readable(l)
    else
        local unit = T.Roster()[name]
        if unit and unit ~= "test" then
            local _, l = UnitName(unit)
            last = readable(l)
        end
    end
    if type(last) ~= "string" or last == "" then return name end
    if (width or 0) >= 340 then return name .. " " .. last end
    return name .. " " .. firstChar(last) .. "."
end

local function classColor(name)
    local class = T.ClassOf(name)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function classIcon(tex, name)
    local class = T.ClassOf(name)
    local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if c then
        tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
        tex:Show()
    else
        tex:Hide()
    end
end
T.ClassIcon = classIcon

-- a line fading out to both sides
local function fadeLine(parent)
    local l, r = parent:CreateTexture(nil, "ARTWORK"), parent:CreateTexture(nil, "ARTWORK")
    for _, t in ipairs({ l, r }) do t:SetColorTexture(1, 1, 1, 1); t:SetHeight(1) end
    l:SetPoint("TOPLEFT"); l:SetPoint("TOPRIGHT", parent, "TOP")
    r:SetPoint("TOPLEFT", parent, "TOP"); r:SetPoint("TOPRIGHT")
    if l.SetGradient and CreateColor then
        l:SetGradient("HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.6))
        r:SetGradient("HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.6), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0))
    else
        l:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.35); r:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
    end
    return { l, r }
end

T.FadeLine = function(parent) return fadeLine(parent) end

-- A button drawn with the client's own icon art (like the panel's pin), without a square frame; it lights up on
-- hover. atlases: tried in turn, else the plain texture fallback. b:SetOn(false) shows it greyed (e.g. unlocked).
local PIN_ATLAS = "friendslist-recentallies-pin-yellow"
local PIN_ORANGE = { 1, 0.68, 0.12 }
local GAP = 14   -- between the title bar's icons
local function iconButton(parent, key, atlases, fallback, tip, onClick, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 16, size or 16)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    local atlas = ns.SetAtlas(b.tex, key, atlases)
    if atlas then
        b.hl:SetAtlas(atlas)
    else
        b.tex:SetTexture(fallback)
        b.hl:SetTexture(fallback)
    end
    -- every icon in the pin's orange: the art made grey, then coloured (the pin itself is orange already)
    b.tint = atlas ~= PIN_ATLAS
    if b.tint then
        b.tex:SetDesaturated(true)
        b.tex:SetVertexColor(PIN_ORANGE[1], PIN_ORANGE[2], PIN_ORANGE[3])
        b.hl:SetDesaturated(true)
        b.hl:SetVertexColor(PIN_ORANGE[1], PIN_ORANGE[2], PIN_ORANGE[3])
    end
    b.hl:SetBlendMode("ADD")
    b.hl:SetAlpha(0.45)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(tip) == "function" and tip() or tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function b:SetOn(on)
        if self.tint then
            if on then self.tex:SetVertexColor(PIN_ORANGE[1], PIN_ORANGE[2], PIN_ORANGE[3]) else self.tex:SetVertexColor(0.6, 0.6, 0.6) end
        else
            self.tex:SetDesaturated(not on)
        end
        self.tex:SetAlpha(on and 1 or 0.55)
    end
    return b
end
T.IconButton = function(...) return iconButton(...) end

-- the window's icons
T.ICON_LOCK = { "lock", { "friendslist-recentallies-pin-yellow" }, "Interface\\Buttons\\LockButton-Locked-Up" }
local ICON_ADD = { "pickAdd", { "communities-icon-addchannelplus", "Garr_Building-AddFollowerPlus" }, "Interface\\Buttons\\UI-PlusButton-Up" }
local ICON_MISS = { "missing", { "socialqueuing-icon-group", "groupfinder-icon-friend" }, "Interface\\GossipFrame\\AvailableQuestIcon" }
local ICON_HIDE = { "hideQuest", { "common-icon-redx", "communities-icon-redx" }, "Interface\\Buttons\\UI-StopButton" }

-- a small round number on a button (the quests missing in the group)
local function badge(b)
    local g = CreateFrame("Frame", nil, b)
    g:SetSize(14, 14)
    g:SetPoint("CENTER", b, "BOTTOMRIGHT", -1, 2)
    g:SetFrameLevel(b:GetFrameLevel() + 2)
    g.bg = g:CreateTexture(nil, "ARTWORK")
    g.bg:SetAllPoints()
    g.bg:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    g.text = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g.text:SetPoint("CENTER", 0, 0)
    local font, _, flags = g.text:GetFont()
    if font then g.text:SetFont(font, 9, flags) end
    g:EnableMouse(false)
    return g
end

function T:Frame()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "ForeverQoLPanelTogether", UIParent, "BackdropTemplate")
    f:SetSize(W, 60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if not db().locked then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local l, t = s:GetLeft(), s:GetTop()
        if l and t then db().pos = { l, t - UIParent:GetHeight() } end
    end)
    f:SetScript("OnSizeChanged", function(s)
        ns.UI.Skin(s)
        if s.content then s.content:SetWidth(math.max(10, s:GetWidth() - 2 * PAD)) end
    end)
    -- the title bar: a golden band fading downwards, the title in it, the buttons on the right
    f.band = f:CreateTexture(nil, "ARTWORK")
    f.band:SetPoint("TOPLEFT", 8, -8)
    f.band:SetPoint("TOPRIGHT", -8, -8)
    f.band:SetHeight(24)
    f.band:SetColorTexture(1, 1, 1, 1)
    if f.band.SetGradient and CreateColor then
        f.band:SetGradient("VERTICAL", CreateColor(0.55, 0.42, 0.18, 0.05), CreateColor(0.55, 0.42, 0.18, 0.4))
    else
        f.band:SetVertexColor(0.55, 0.42, 0.18, 0.25)
    end
    f.bandLine = fadeLine(CreateFrame("Frame", nil, f))
    f.bandLine[1]:GetParent():SetPoint("TOPLEFT", f.band, "BOTTOMLEFT")
    f.bandLine[1]:GetParent():SetPoint("TOPRIGHT", f.band, "BOTTOMRIGHT")
    f.bandLine[1]:GetParent():SetHeight(1)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f.band, "LEFT", 8, 0)
    local L = T.ICON_LOCK
    f.lock = iconButton(f, L[1], L[2], L[3],
        function() return db().locked and ns.L.TOG_UNLOCK or ns.L.TOG_LOCK end,
        function() db().locked = not db().locked; T:UpdateLock() end)
    f.lock:SetPoint("RIGHT", f.band, "RIGHT", -6, 0)
    f.add = iconButton(f, ICON_ADD[1], ICON_ADD[2], ICON_ADD[3], ns.L.TOG_PICK_TIP, function(b) T:PickMenu(b) end)
    f.add:SetPoint("RIGHT", f.lock, "LEFT", -GAP, 0)
    -- the quests a member lacks: a button with their number, its menu shares them (by zone)
    f.missBtn = iconButton(f, ICON_MISS[1], ICON_MISS[2], ICON_MISS[3], ns.L.TOG_MISSING_HEAD, function(b) T:MissingMenu(b) end)
    f.missBtn.badge = badge(f.missBtn)
    -- the content scrolls when it is taller than the window may be (maxHeight, set with the grip in the corner)
    f.scroll = CreateFrame("ScrollFrame", nil, f)
    f.scroll:SetPoint("TOPLEFT", PAD, -TOP)
    f.scroll:SetPoint("BOTTOMRIGHT", -PAD, 22)   -- room below for the grip
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(W - 2 * PAD, 10)
    f.scroll:SetScrollChild(f.content)
    f.scroll:EnableMouseWheel(true)
    f.scroll:SetScript("OnMouseWheel", function(sf, delta)
        local maxY = math.max(0, (f.content:GetHeight() or 0) - (sf:GetHeight() or 0))
        sf:SetVerticalScroll(math.max(0, math.min(maxY, (sf:GetVerticalScroll() or 0) - delta * 30)))
    end)
    -- the grip: width and the highest the window may get
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(240, 120, 700, 1000) elseif f.SetMinResize then f:SetMinResize(240, 120) end
    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(16, 16)
    f.grip:SetPoint("BOTTOMRIGHT", -9, 9)   -- inside the border
    f.grip:SetFrameLevel(f:GetFrameLevel() + 10)
    f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    f.grip:SetScript("OnMouseDown", function() f.sizing = true; f:StartSizing("BOTTOMRIGHT") end)
    f.grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f.sizing = false
        db().width = math.floor(f:GetWidth() + 0.5)
        db().maxHeight = math.floor(f:GetHeight() + 0.5)
        T:UpdateWindow()
    end)
    f.grip:SetScript("OnEnter", function(gb)
        GameTooltip:SetOwner(gb, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L.TOG_GRIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- the group's XP at the top (GroupXP.lua), unless it has a window of its own
    f.xp = CreateFrame("Frame", nil, f.content)
    f.xp.head = f.xp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.xp.head:SetPoint("TOPLEFT", 0, -4)
    f.xp.host = CreateFrame("Frame", nil, f.xp)
    f.xp.host:SetPoint("TOPLEFT", 0, -20)
    f.xp.host:SetPoint("RIGHT")
    f.xp.line = CreateFrame("Frame", nil, f.xp)
    f.xp.line:SetPoint("BOTTOMLEFT"); f.xp.line:SetPoint("BOTTOMRIGHT"); f.xp.line:SetHeight(1)
    fadeLine(f.xp.line)
    f.empty = f.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetJustifyH("LEFT")
    f.empty:SetJustifyV("TOP")
    f.empty:SetWordWrap(true)
    f.foot = f.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.foot:SetJustifyH("LEFT")
    f.blocks, f.order = {}, {}
    f:Hide()
    self.frame = f
    self:UpdateLock()
    return f
end

function T:UpdateLock()
    local f = self.frame
    if not f then return end
    f.lock:SetOn(db().locked)
end

-- the missing quests' button: a menu by zone to share them
function T:MissingMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.L.TOG_MISSING_HEAD)
        local missing = T:Missing()
        if #missing == 0 then root:CreateTitle("|cff9d9d9d" .. ns.L.TOG_SAME .. "|r") end
        T.ShareEntries(root, missing)
    end)
end

-- the missing quests into a menu: one submenu per zone; a quest the game does not let you share is greyed
function T.ShareEntries(root, missing)
    local L = ns.L
    for _, g in ipairs(T.ByZone(missing)) do
        local share = 0
        for _, m in ipairs(g.items) do if m.pushable then share = share + 1 end end
        local sub = root:CreateButton(g.zone .. "  |cff9d9d9d(" .. #g.items .. ")|r")
        for _, m in ipairs(g.items) do
            local label = T.ColoredTitle(m.id, m.title) .. "  |cff9d9d9d(" .. table.concat(m.missing, ", ") .. ")|r"
            if m.pushable then
                -- the menu stays open, so several quests can be shared one after another
                sub:CreateButton(L.TOG_SHARE:format(label), function() T.Share(m.id); return T.KeepOpen() end)
            else
                sub:CreateTitle("|cff7f7f7f" .. m.title .. "  " .. L.TOG_NOTSHAREABLE .. "|r")
            end
        end
    end
end

-- the button's number: how many quests someone lacks; red while some can be shared, grey if none can
function T:UpdateMissingButton(f, missing, x)
    local b = f.missBtn
    if #missing == 0 then b:Hide() return x end
    local share = 0
    for _, m in ipairs(missing) do if m.pushable then share = share + 1 end end
    b.badge.text:SetText(#missing)
    -- red like the game's own notification numbers (it stands out against the orange icons); grey if none can be shared
    if share > 0 then b.badge.bg:SetVertexColor(0.78, 0.08, 0.06) else b.badge.bg:SetVertexColor(0.35, 0.35, 0.35) end
    b:SetOn(share > 0)
    b:ClearAllPoints()
    b:SetPoint("RIGHT", x, "LEFT", -GAP, 0)
    b:Show()
    return b
end

-- the leader's "+": every quest you hold that is not shown yet
function T:PickMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.L.TOG_PICK)
        local list = T:Pickable()
        if #list == 0 then root:CreateTitle("|cff9d9d9d" .. ns.L.TOG_PICK_NONE .. "|r") end
        T.PickEntries(root, list)
    end)
end

-- A quest of yours in the game's quest window, with its text. Newer clients: the map's quest details; the classic
-- quest log: shown and the quest selected; else the quest log just opens. The way taken is noted for the debug data.
function T.OpenQuest(id)
    if T.testing and id > 900000 then return end
    if not T.mine[id] then
        print("|cffffd100" .. ns.title .. "|r: " .. ns.L.TOG_NOT_IN_LOG)
        return
    end
    local QL = C_QuestLog
    local function note(way) ns.Debug.Set("openQuest", way) end
    if QuestMapFrame_OpenToQuestDetails then
        if pcall(QuestMapFrame_OpenToQuestDetails, id) then note("map") return end
    end
    local index = QL and QL.GetLogIndexForQuestID and readable(QL.GetLogIndexForQuestID(id))
    if not index and GetQuestLogIndexByID then index = readable(GetQuestLogIndexByID(id)) end
    local frame = rawget(_G, "QuestLogFrame")
    if index and frame and QuestLog_SetSelection then
        if not frame:IsShown() then
            if ShowUIPanel then ShowUIPanel(frame) else frame:Show() end
        end
        pcall(QuestLog_SetSelection, index)
        if QuestLog_Update then pcall(QuestLog_Update) end
        note("questlog " .. index)
        return
    end
    if QL and QL.SetSelectedQuest then pcall(QL.SetSelectedQuest, id) end
    if ToggleQuestLog then pcall(ToggleQuestLog) note("toggle") return end
    note("none")
end

-- what a menu entry answers so the menu does not close after the click
function T.KeepOpen() return MenuResponse and MenuResponse.Open or nil end

-- the pickable quests into a menu: one submenu per zone, with the number of quests
function T.PickEntries(root, list)
    for _, g in ipairs(T.ByZone(list)) do
        local sub = root:CreateButton(g.zone .. "  |cff9d9d9d(" .. #g.items .. ")|r")
        for _, q in ipairs(g.items) do sub:CreateButton(T.ColoredTitle(q.id, q.title), function() T:Pick(q.id); return T.KeepOpen() end) end
    end
end

local function block(f, id)
    local b = f.blocks[id]
    if b then return b end
    b = CreateFrame("Frame", nil, f.content)
    b:SetHeight(0.1)
    b:SetClipsChildren(true)
    b.sep = CreateFrame("Frame", nil, b)
    b.sep:SetPoint("TOPLEFT"); b.sep:SetPoint("TOPRIGHT"); b.sep:SetHeight(1)
    fadeLine(b.sep)
    -- the glow of a new quest
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetAllPoints()
    b.glow:SetColorTexture(1, 0.82, 0.3, 1)
    b.glow:SetAlpha(0)
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.title:SetPoint("TOPLEFT", 0, -7)
    b.title:SetPoint("RIGHT", -22, 0)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)
    -- a click on the title opens the quest in the quest log (its text, where to go); dragging still moves the window
    b.titleBtn = CreateFrame("Button", nil, b)
    b.titleBtn:SetPoint("TOPLEFT", 0, -3)
    b.titleBtn:SetPoint("RIGHT", -22, 0)
    b.titleBtn:SetHeight(20)
    b.titleBtn:RegisterForDrag("LeftButton")
    b.titleBtn:SetScript("OnDragStart", function() local s = f:GetScript("OnDragStart"); if s then s(f) end end)
    b.titleBtn:SetScript("OnDragStop", function() local s = f:GetScript("OnDragStop"); if s then s(f) end end)
    b.titleBtn:SetScript("OnClick", function() T.OpenQuest(id) end)
    b.titleBtn:SetScript("OnEnter", function(s)
        b.title:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(s, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(b.title:GetText() or "", 1, 0.82, 0)
        if T.mine[id] then
            GameTooltip:AddLine(ns.L.TOG_OPEN_QUEST, 0.82, 0.82, 0.82)
        else
            GameTooltip:AddLine(ns.L.TOG_NOT_IN_LOG, 0.82, 0.82, 0.82)
        end
        GameTooltip:Show()
    end)
    b.titleBtn:SetScript("OnLeave", function()
        b.title:SetTextColor(T.TitleColor(id))
        GameTooltip:Hide()
    end)
    b.hide = iconButton(b, ICON_HIDE[1], ICON_HIDE[2], ICON_HIDE[3], ns.L.TOG_HIDE, function() T:Hide(id) end, 14)
    b.hide:SetPoint("TOPRIGHT", 0, -6)
    b.rows = {}
    b.new = true
    f.blocks[id] = b
    return b
end

local function row(b, i)
    local r = b.rows[i]
    if r then return r end
    r = {}
    r.flash = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.flash:SetColorTexture(1, 0.82, 0.3, 1)
    r.flash:SetAlpha(0)
    r.icon = b:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(12, 12)
    r.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.prog = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.prog:SetJustifyH("RIGHT")
    r.far = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.far:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.far:SetText(ns.L.TOG_TOO_FAR)
    r.far:Hide()
    b.rows[i] = r
    return r
end

-- Too far away to get the kill or the loot: about 100 yards, as far as the game shares kill credit. Measured where
-- the client allows it; else: the game no longer draws them (that is about as far), or another zone, or offline.
T.RANGE = 100
function T.FarAway(name)
    if T.testing and name == T.TEST_NAME then return T.testFar or false end
    local unit = T.Roster()[name]
    if not unit or unit == "test" then return false end
    if UnitIsConnected and readable(UnitIsConnected(unit)) == false then return true end
    if UnitDistanceSquared then
        local ok, d2, checked = pcall(UnitDistanceSquared, unit)
        d2, checked = readable(d2), readable(checked)
        if ok and checked and type(d2) == "number" then return d2 > T.RANGE * T.RANGE end
    end
    if UnitIsVisible then
        local v = readable(UnitIsVisible(unit))
        if v ~= nil then return not v end
    end
    return false
end

-- the rows of members too far away: dimmed, "too far away" behind the name (looked at every two seconds)
function T:UpdateRange()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    for _, b in pairs(f.blocks) do
        for _, r in ipairs(b.rows) do
            if r.member and r.name:IsShown() then
                local far = r.member ~= me() and T.FarAway(r.member)
                local a = far and 0.45 or 1
                r.name:SetAlpha(a); r.icon:SetAlpha(a); r.prog:SetAlpha(a)
                r.far:SetShown(far and true or false)
            else
                r.far:Hide()
            end
        end
    end
end

-- a short fading light on a texture (new quest, new progress)
local function flash(tex, peak, secs)
    if ns.db.panel.animations == false then return end
    tex.fT = 0
    tex.peak, tex.secs = peak, secs
    tex.ticker = tex.ticker or CreateFrame("Frame")
    tex.ticker:SetScript("OnUpdate", function(s, elapsed)
        tex.fT = tex.fT + elapsed
        local k = math.min(1, tex.fT / tex.secs)
        tex:SetAlpha(tex.peak * (1 - k))
        if k >= 1 then s:SetScript("OnUpdate", nil) end
    end)
end

-- a block's glow lit once (all done: golden)
T.Glow = function(b, peak, secs)
    b.glow:SetColorTexture(1, 0.82, 0.3, 1)
    flash(b.glow, peak, secs)
end

-- a block pulsing red while a quest waits for the others to turn it in (until the leader confirms)
local function alarmPulse(b, on)
    b.alarmer = b.alarmer or CreateFrame("Frame", nil, b)
    if not on then
        if b.alarming then
            b.alarmer:SetScript("OnUpdate", nil)
            b.glow:SetAlpha(0)
            b.glow:SetColorTexture(1, 0.82, 0.3, 1)
            b.alarming = false
        end
        return
    end
    if b.alarming then return end
    b.alarming = true
    if b.glow.ticker then b.glow.ticker:SetScript("OnUpdate", nil) end
    b.glow:SetColorTexture(0.9, 0.1, 0.05, 1)
    local t = 0
    b.alarmer:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        b.glow:SetAlpha(0.08 + 0.32 * (0.5 + 0.5 * math.sin(t * 5)))
    end)
end

-- The note next to the window (to the right of the quest): who turned it in, who has not yet. The leader confirms it
-- ("Got it": ends it for everyone); the others can only close their note (the pulse goes on until the leader's word).
function T:ShowTurnInNote(id)
    local f = self.frame
    local b = f and f.blocks[id]
    if not b then return end
    self.notes = self.notes or {}
    local n = self.notes[id]
    if not n then
        n = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        n:SetSize(250, 108)
        n:SetFrameStrata("DIALOG")
        n:SetClampedToScreen(true)
        n.title = n:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        n.title:SetPoint("TOPLEFT", 14, -14)
        n.title:SetPoint("RIGHT", -14, 0)
        n.title:SetJustifyH("LEFT")
        n.title:SetWordWrap(false)
        n.gave = n:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        n.gave:SetPoint("TOPLEFT", n.title, "BOTTOMLEFT", 0, -8)
        n.gave:SetPoint("RIGHT", -14, 0)
        n.gave:SetJustifyH("LEFT")
        n.open = n:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        n.open:SetPoint("TOPLEFT", n.gave, "BOTTOMLEFT", 0, -4)
        n.open:SetPoint("RIGHT", -14, 0)
        n.open:SetJustifyH("LEFT")
        n.btn = CreateFrame("Button", nil, n, "UIPanelButtonTemplate")
        n.btn:SetSize(110, 22)
        -- some room between the button and the frame
        n.btn:SetPoint("BOTTOMRIGHT", -16, 16)
        n.hint = n:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        n.hint:SetPoint("BOTTOMLEFT", 14, 21)
        n.hint:SetPoint("RIGHT", n.btn, "LEFT", -6, 0)
        n.hint:SetJustifyH("LEFT")
        ns.UI.Skin(n)
        self.notes[id] = n
    end
    n.id = id
    n.title:SetText(T.TitleOf(id))
    local gave, holding = self:TurnInState(id)
    n.gave:SetText("|cff20ff20" .. ns.L.TOG_GAVE_IN .. "|r " .. (#gave > 0 and table.concat(gave, ", ") or "–"))
    n.open:SetText("|cffff5040" .. ns.L.TOG_NOT_YET .. "|r " .. (#holding > 0 and table.concat(holding, ", ") or "–"))
    if self.Leader() then
        n.btn:SetText(ns.L.TOG_GOT_IT)
        n.btn:SetScript("OnClick", function() T:Acknowledge(id) end)
        n.hint:SetText("")
    else
        n.btn:SetText(CLOSE or "Close")
        n.btn:SetScript("OnClick", function() n:Hide(); T:LayoutNotes() end)
        n.hint:SetText(ns.L.TOG_LEADER_CONFIRMS)
    end
    n:Show()
    self:LayoutNotes()
end

-- The notes beside the window, on the side with room (left of it when the window stands in the right half of the
-- screen). Each next to its quest, but never over the one above it: then right below that one.
function T:LayoutNotes()
    local f = self.frame
    if not (f and self.notes) then return end
    local cx, sw = f:GetCenter(), UIParent:GetWidth()
    local left = cx and sw and cx > sw / 2
    local order = {}
    for i, id in ipairs(f.order or {}) do order[id] = i end
    local list = {}
    for id, n in pairs(self.notes) do
        if n:IsShown() and f.blocks[id] then list[#list + 1] = n else n:Hide() end
    end
    table.sort(list, function(a, b) return (order[a.id] or 999) < (order[b.id] or 999) end)
    local prev
    for _, n in ipairs(list) do
        local b = f.blocks[n.id]
        n:ClearAllPoints()
        local top, below = b:GetTop(), prev and prev:GetBottom()
        if prev and not (top and below and top + 6 <= below - 6) then
            -- it would cover the note above: right below it
            n:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
        elseif left then
            n:SetPoint("TOPRIGHT", b, "TOPLEFT", -(PAD + 10), 6)
        else
            n:SetPoint("TOPLEFT", b, "TOPRIGHT", PAD + 10, 6)
        end
        prev = n
    end
end

-- the blocks one below the other at their current heights, then the footer
function T:Layout()
    local f = self.frame
    if not f then return end
    local c = f.content
    local y = 0
    if f.xp:IsShown() then
        f.xp:ClearAllPoints()
        f.xp:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        f.xp:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        y = f.xp:GetHeight() + 6
    end
    for _, id in ipairs(f.order) do
        local b = f.blocks[id]
        if b and b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y)
            b:SetPoint("RIGHT", c, "RIGHT", 0, 0)
            y = y + b:GetHeight()
        end
    end
    if f.empty:IsShown() then
        f.empty:ClearAllPoints()
        f.empty:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y - 6)
        f.empty:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        -- as many lines as the text needs at this width
        y = y + 6 + math.ceil(f.empty:GetStringHeight() or 14) + 8
    end
    if (f.foot:GetText() or "") ~= "" then
        f.foot:ClearAllPoints()
        f.foot:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y - 4)
        f.foot:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        y = y + 18
    end
    c:SetHeight(math.max(1, y))
    -- as tall as the content, at most maxHeight (then it scrolls); while the grip is held the user decides
    if f.sizing then return end
    -- the scroll area ends 22 above the window's bottom (the grip's strip): the window is that much taller
    local maxH = db().maxHeight or 600
    f:SetHeight(math.min(TOP + y + 24, math.max(120, maxH)))
    local maxY = math.max(0, y - (f.scroll:GetHeight() or 0))
    if (f.scroll:GetVerticalScroll() or 0) > maxY then f.scroll:SetVerticalScroll(maxY) end
end

-- a block's height glides to its target (unfolding a new quest, folding a finished one)
local function glide(b, to, done)
    if ns.db.panel.animations == false then b:SetHeight(math.max(0.1, to)); b:SetAlpha(to > 0 and 1 or 0); if done then done() end return end
    local from, t = b:GetHeight(), 0
    b:SetScript("OnUpdate", function(s, elapsed)
        t = math.min(1, t + elapsed / 0.4)
        local e = t * t * (3 - 2 * t)
        local h = from + (to - from) * e
        s:SetHeight(math.max(0.1, h))
        if to > from then s:SetAlpha(math.min(1, 0.2 + e)) else s:SetAlpha(1 - e) end
        T:Layout()
        if t >= 1 then s:SetScript("OnUpdate", nil); if done then done() end end
    end)
end

function T:UpdateWindow()
    local d = db()
    local f = self:Frame()
    if not (d.enabled and d.window and self.InGroup()) then f:Hide() return end
    local st = state()
    local ids = {}
    for id in pairs(st.active) do if not st.hidden[id] then ids[#ids + 1] = id end end
    for id, b in pairs(f.blocks) do if b.folding then ids[#ids + 1] = id end end
    local missing = self:Missing()
    local xpList = ns.GroupXP and not d.xpSeparate and ns.GroupXP:List()
    -- in a group the window stays, also without a quest: the leader picks one here, missing ones are shared here
    table.sort(ids)
    f.order = ids
    f.title:SetText(ns.L.SEC_TOGETHER)
    local leader = self.Leader()
    f.add:SetShown(leader and #self:Pickable() > 0)
    -- the buttons from the right: lock, "+" (if shown), the missing quests (if any)
    self:UpdateMissingButton(f, missing, f.add:IsShown() and f.add or f.lock)
    local names = { me() }
    for name in pairs(self.Roster()) do names[#names + 1] = name end
    table.sort(names, function(a, b) if a == me() then return true elseif b == me() then return false end return a < b end)
    local shown = {}
    for n, id in ipairs(ids) do
        local b = block(f, id)
        shown[b] = true
        b.sep:SetShown(n > 1)
        b.title:SetText(T.TitleOf(id))
        b.title:SetTextColor(T.TitleColor(id))
        b.hide:SetShown(leader and not b.folding and true or false)
        -- waiting for the others to turn it in: red pulse, the note kept up to date
        local w = self.watch[id]
        alarmPulse(b, w and w.alarm and not b.folding)
        if w and w.alarm and self.notes and self.notes[id] and self.notes[id]:IsShown() then self:ShowTurnInNote(id) end
        local k = 0
        b.lastProg = b.lastProg or {}
        for _, name in ipairs(names) do
            local q = name == me() and self.mine[id] or (self.members[name] and self.members[name].quests[id])
            local known = name == me() or self.members[name] or ns.Comm.seen[name]
            local gaveIn = self.turnedIn[name] and self.turnedIn[name][id]
            k = k + 1
            local r = row(b, k)
            local yy = -HEAD - 6 - (k - 1) * ROW
            r.icon:ClearAllPoints(); r.icon:SetPoint("TOPLEFT", 6, yy)
            classIcon(r.icon, name)
            r.prog:ClearAllPoints(); r.prog:SetPoint("TOPRIGHT", 0, yy)
            r.flash:ClearAllPoints(); r.flash:SetPoint("TOPLEFT", 0, yy + 2); r.flash:SetPoint("RIGHT"); r.flash:SetHeight(ROW)
            r.name:SetText(T.ShowName(name, f.content:GetWidth())); r.name:SetTextColor(classColor(name))
            r.member = name
            local text
            if not q and gaveIn then text = "|cff20ff20" .. ns.L.TOG_TURNEDIN .. "|r"
            elseif not known then text = "|cff9d9d9d" .. ns.L.TOG_NOADDON .. "|r"
            elseif not q then text = "|cff9d9d9d" .. ns.L.TOG_LACKS .. "|r"
            elseif q.done then text = "|cff20ff20" .. ns.L.TOG_DONE .. "|r"
            else text = (q.prog or ""):gsub(",", "  ·  ") end
            -- new progress: the row lights up
            if b.lastProg[name] and b.lastProg[name] ~= text and not b.new then flash(r.flash, 0.35, 1.2) end
            b.lastProg[name] = text
            r.prog:SetText(text)
            -- the name never runs into the progress (nor "too far away" behind it): shorter, else cut
            local room = f.content:GetWidth() - 22 - (r.prog:GetStringWidth() or 0) - 12
                - (r.member ~= me() and ((r.far:GetStringWidth() or 0) + 6) or 0)
            if (r.name:GetStringWidth() or 0) > room then r.name:SetText(T.ShowName(name, 0)) end
            r.name:SetWidth(math.max(30, math.min((r.name:GetStringWidth() or 0) + 2, room)))
            r.name:Show(); r.prog:Show()
        end
        for x = k + 1, #b.rows do b.rows[x].name:Hide(); b.rows[x].prog:Hide(); b.rows[x].icon:Hide(); b.rows[x].far:Hide() end
        b.full = HEAD + 10 + k * ROW
        b:Show()
        if b.new then
            -- a new quest unfolds and glows
            b.new = false
            b:SetHeight(0.1)
            b:SetAlpha(0)
            glide(b, b.full)
            flash(b.glow, 0.28, 1.6)
        elseif not b.folding and not b:GetScript("OnUpdate") then
            b:SetHeight(b.full)
        end
    end
    for id, b in pairs(f.blocks) do if not shown[b] then b:Hide(); f.blocks[id] = nil end end
    -- no quest followed yet
    -- the hint to the "+" only when there is something to pick
    f.empty:SetText(leader and #self:Pickable() > 0 and ns.L.TOG_NONE_LEADER or ns.L.TOG_NONE)
    f.empty:SetShown(#ids == 0)
    -- the group's XP section
    if xpList then
        f.content:SetWidth(math.max(10, (f.sizing and f:GetWidth() or (d.width or W)) - 2 * PAD))
        f.xp.head:SetText(ns.L.SEC_GROUPXP)
        local h = ns.GroupXP:Render(f.xp.host, xpList, f.content:GetWidth())
        f.xp.host:SetHeight(h)
        f.xp:SetHeight(20 + h + 6)
        f.xp:Show()
    else
        f.xp:Hide()
        if ns.GroupXP then ns.GroupXP.HideRows(f.xp.host) end
    end
    local without = self:WithoutAddon()
    f.foot:SetText(#without > 0 and ns.L.TOG_WITHOUT:format(table.concat(without, ", ")) or "")
    local pos = d.pos
    f:ClearAllPoints()
    if pos then f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos[1], pos[2]) else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -260) end
    if not f.sizing then f:SetWidth(d.width or W) end
    f.content:SetWidth(math.max(10, f:GetWidth() - 2 * PAD))
    self:Layout()
    ns.UI.Skin(f)
    f:Show()
    self:UpdateRange()
    -- the distance is looked at again every two seconds while the window is up
    if not self.rangeTicker and C_Timer.NewTicker then
        self.rangeTicker = C_Timer.NewTicker(2, function() ns.Debug.Call("Together", T.UpdateRange, T) end)
    end
end

-- a hidden quest folds away at once; one finished by everyone first pulses golden three times, so it is seen
function T:Fold(id, finished)
    local f = self.frame
    local b = f and f.blocks[id]
    if not (b and b:IsShown()) then self:Changed() return end
    b.folding = true
    b.hide:Hide()
    local function away()
        glide(b, 0, function()
            b:Hide()
            f.blocks[id] = nil
            T:Changed()
        end)
    end
    if not finished or ns.db.panel.animations == false then away() return end
    -- the rows show "done" while it pulses
    self:UpdateWindow()
    local t, secs = 0, 1.8
    -- stop the glow of a fresh quest (it runs on its own frame; textures have no scripts)
    if b.glow.ticker then b.glow.ticker:SetScript("OnUpdate", nil) end
    local ticker = b.pulser or CreateFrame("Frame")
    b.pulser = ticker
    ticker:SetScript("OnUpdate", function(s, elapsed)
        t = t + elapsed
        local k = math.min(1, t / secs)
        b.glow:SetAlpha(0.32 * (0.5 - 0.5 * math.cos(k * 3 * 2 * math.pi)))   -- three pulses
        if k >= 1 then s:SetScript("OnUpdate", nil); b.glow:SetAlpha(0); away() end
    end)
end

function T:Changed()
    if ns.Elements and ns.Elements.UpdateTexts then ns.Elements:UpdateTexts() end
    ns.Debug.Call("Together", T.UpdateWindow, T)
    ns.Debug.Call("Together", T.CheckTracker, T)
end

-- Blizzard's quest tracker ---------------------------------------------------------------------------------------
-- In a group where most members use this addon (you included), the game's own quest tracker folds up (setting
-- minimizeTracker): our window shows the group's quests. It unfolds again when that is no longer so, but only if we
-- folded it (not if you did). Not in combat (the game may not allow it then): after the fight.

-- how many in the group use the addon (you included), and how big the group is
function T:AddonShare()
    local roster, n, users = self.Roster(), 1, 1
    for name in pairs(roster) do
        n = n + 1
        if self.members[name] or ns.Comm.seen[name] or (ns.GroupXP and ns.GroupXP.members[name]) then users = users + 1 end
    end
    return users, n
end

local function tracker() return rawget(_G, "ObjectiveTrackerFrame") end

local function collapsed(t)
    if t.IsCollapsed then local ok, v = pcall(t.IsCollapsed, t); if ok then return v and true or false end end
    return t.collapsed and true or false
end

local function setCollapsed(t, on)
    if t.SetCollapsed then return pcall(t.SetCollapsed, t, on) end
    local btn = t.Header and t.Header.MinimizeButton or (t.HeaderMenu and t.HeaderMenu.MinimizeButton)
    if btn and btn.Click and collapsed(t) ~= on then return pcall(btn.Click, btn) end
    if on and ObjectiveTracker_Collapse then return pcall(ObjectiveTracker_Collapse) end
    if not on and ObjectiveTracker_Expand then return pcall(ObjectiveTracker_Expand) end
end

function T:CheckTracker()
    local d = db()
    local users, n = self:AddonShare()
    local want = d.enabled and d.minimizeTracker and self.InGroup() and not self.testing and n > 1 and users * 2 > n
    if InCombatLockdown and InCombatLockdown() then self.trackerPending = true return end
    self.trackerPending = false
    local t = tracker()
    local qw = rawget(_G, "QuestWatchFrame")
    if want and not self.folded then
        if t then
            if not collapsed(t) then setCollapsed(t, true); self.folded = "tracker" end
        elseif qw and qw:IsShown() then
            qw:Hide(); self.folded = "watch"
        end
    elseif not want and self.folded then
        if self.folded == "tracker" and t and collapsed(t) then setCollapsed(t, false) end
        if self.folded == "watch" and qw then qw:Show() end
        self.folded = nil
    end
end

-- Test -----------------------------------------------------------------------------------------------------
-- Step by step, at your own pace (development copy only): start the test (a made-up partner, no real quests shown,
-- nothing sent), add a quest (it unfolds), update one (a row flashes), finish one (it pulses, then folds away).
-- Every third added quest is missing for the partner (the "missing" section and the element show it).
T.TEST_NAME = "Testpartner"
local TEST_BASE = 900000

function T:Test()
    if self.testing then return self:EndTest() end
    self.saved = { mine = self.mine, members = self.members, state = db().state, turnedIn = self.turnedIn }
    self.turnedIn = {}
    self.testing = true
    -- a clean window: no quest of the real group left in it (not even one still folding away)
    local f = self.frame
    if f then for id, b in pairs(f.blocks) do b:SetScript("OnUpdate", nil); b:Hide(); f.blocks[id] = nil end end
    self.testN = 0
    db().state = nil
    self.mine = {}
    self.members = { [T.TEST_NAME] = { quests = {} } }
    -- the partner's XP for the XP window
    -- (low on arrows, to see the warning)
    if ns.GroupXP then ns.GroupXP.members[T.TEST_NAME] = { level = 26, xp = 4500, max = 12000, rested = 2000, quest = 2600, new = true,
        free = 3, slots = 64, ammo = 150 } end
    self:Changed()
end

local function copyMine()
    local m = {}
    for id, q in pairs(T.mine) do m[id] = { done = q.done, prog = q.prog, title = q.title, zone = q.zone } end
    return m
end

function T:TestAdd()
    if not self.testing then return end
    self.testN = self.testN + 1
    local id = TEST_BASE + self.testN
    local m = copyMine()
    -- test quests in two zones (the one you are in and a made-up one), to see the zone grouping
    local zone = self.testN % 2 == 1 and readable(GetRealZoneText and GetRealZoneText()) or ns.L.TOG_TEST_ZONE
    m[id] = { done = false, prog = "0/10", title = ns.L.TOG_TEST_QUEST:format(self.testN), zone = zone }
    self:ApplyMine(m)
    if self.testN % 3 ~= 0 then
        self:OnQuest(T.TEST_NAME, id, false, "0/10")
        self:Pick(id)
    end
    self:Changed()
end

-- the shown quests not done yet, oldest first
local function openTests()
    local out, st = {}, state()
    for id in pairs(st.active) do if T.mine[id] and not T.mine[id].done then out[#out + 1] = id end end
    table.sort(out)
    return out
end

function T:TestUpdate()
    if not self.testing then return end
    local open = openTests()
    if #open == 0 then return end
    -- the partner gains some XP as well
    local gx = ns.GroupXP and ns.GroupXP.members[T.TEST_NAME]
    if gx then gx.xp = math.min(gx.max - 1, gx.xp + math.random(300, 900)); ns.GroupXP:Update() end
    local id = open[math.random(#open)]
    self.testFlip = not self.testFlip
    local function step(prog) local have = tonumber(prog:match("^(%d+)")) or 0; return math.min(9, have + math.random(1, 3)) .. "/10" end
    local partner = self.members[T.TEST_NAME].quests[id]
    if self.testFlip and partner then
        self:OnQuest(T.TEST_NAME, id, false, step(partner.prog))
    else
        local m = copyMine()
        m[id].prog = step(m[id].prog)
        self:ApplyMine(m)
    end
end

function T:TestFinish()
    if not self.testing then return end
    local id = openTests()[1]
    if not id then return end
    if self.members[T.TEST_NAME].quests[id] then self:OnQuest(T.TEST_NAME, id, true, "10/10") end
    local m = copyMine()
    m[id].done, m[id].prog = true, "10/10"
    self:ApplyMine(m)
end

-- the shown quests both hold, oldest first (to turn in)
local function sharedTests()
    local out, st = {}, state()
    local partner = T.members[T.TEST_NAME] and T.members[T.TEST_NAME].quests or {}
    for id in pairs(st.active) do if T.mine[id] and partner[id] then out[#out + 1] = id end end
    table.sort(out)
    return out
end

-- the partner turns in a quest you still hold: after a few seconds (60 for real) the reminder comes
-- the partner walks away or comes back (to see "too far away")
function T:TestFar()
    if not self.testing then return end
    self.testFar = not self.testFar
    self:UpdateRange()
end

function T:TestPartnerTurnIn()
    if not self.testing then return end
    local id = sharedTests()[1]
    if not id then return end
    self.members[T.TEST_NAME].quests[id] = nil
    self:OthersTurnIn(T.TEST_NAME, id)
    self:CheckDone(id)
    self:Changed()
end

-- you turn in a shown quest: if the partner still holds it, the reminder comes; if not, it folds away
function T:TestMyTurnIn()
    if not self.testing then return end
    local st, id = state(), nil
    for qid in pairs(st.active) do if self.mine[qid] and (not id or qid < id) then id = qid end end
    if not id then return end
    self:MyTurnIn(id)
    local m = copyMine()
    m[id] = nil
    self:ApplyMine(m)
end

function T:EndTest()
    if not self.testing then return end
    for id in pairs(self.watch) do self:StopAlarm(id, true) end
    self.testing = false
    local f = self.frame
    if f then for id, b in pairs(f.blocks) do b:Hide(); f.blocks[id] = nil end end
    self.mine, self.members, db().state = self.saved.mine, self.saved.members, self.saved.state
    self.turnedIn = self.saved.turnedIn or {}
    if ns.GroupXP then ns.GroupXP.members[T.TEST_NAME] = nil; ns.GroupXP:Update() end
    self.saved = nil
    self:Changed()
end

-- Events --------------------------------------------------------------------------------------------------

local pending
local function scanSoon()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        if T.testing then return end   -- the test's made-up log stays until it ends
        ns.Debug.Call("Together", function() T:ApplyMine(T.Scan()) end)
    end)
end

-- a quest you turned in already (the game remembers it)
local function turnedIn(id)
    local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if not f then return false end
    local ok, yes = pcall(f, id)
    return ok and readable(yes) and true or false
end

-- A quest someone reports that is not in your list: you hold it after all (under a folded header) -> looked at
-- again; you turned it in already -> the group is told (D|id), so it shows "turned in" instead of "lacks it".
local toldDone = {}
function T:CheckHeld(id)
    local QL = C_QuestLog
    if self.mine[id] or self.testing then return end
    if QL and QL.IsOnQuest then
        local ok, on = pcall(QL.IsOnQuest, id)
        if ok and readable(on) then scanSoon() return end
    end
    if turnedIn(id) and GetTime() - (toldDone[id] or -60) > 30 then
        toldDone[id] = GetTime()
        ns.Comm:SendGroup("D", id)
    end
end

-- what the group looks like, for the debug data (who counts as a member)
function T:Describe()
    local r = {}
    for name, unit in pairs(self.Roster()) do r[#r + 1] = name .. "=" .. tostring(unit) .. ":" .. tostring(T.ClassOf(name)) end
    ns.Debug.Set("togetherRoster", { me = me(), group = IsInGroup and IsInGroup() or false, raid = IsInRaid and IsInRaid() or false,
        members = r })
end

function T:RosterChanged()
    self:Describe()
    if not self.InGroup() then
        -- the group is over: everything of it forgotten
        self.members, self.blocked, self.turnedIn, self.watch = {}, {}, {}, {}
        for _, n in pairs(self.notes or {}) do n:Hide() end
        db().state = nil
        self:Changed()
        return
    end
    -- members who left
    local roster = self.Roster()
    for name in pairs(self.members) do if not roster[name] then self.members[name] = nil end end
    for name in pairs(self.blocked) do if not roster[name] then self.blocked[name] = nil end end
    for name in pairs(self.turnedIn) do if not roster[name] then self.turnedIn[name] = nil end end
    ns.Comm:SendGroup("Y")
    self:SendAll()
    self:Changed()
end

ns.OnLogin(function()
    if not ns.Comm then return end
    ns.Comm:On("Q", function(f, _, sender)
        local id = tonumber(f[1])
        if id and db().enabled then T:OnQuest(sender, id, f[2] == "1", f[3] or ""); T:CheckHeld(id) end
    end)
    ns.Comm:On("R", function(f, _, sender) local id = tonumber(f[1]); if id then T:OnRemoved(sender, id) end end)
    ns.Comm:On("H", function(f, _, sender) local id = tonumber(f[1]); if id then T:OnHidden(sender, id) end end)
    -- asked for everything (someone joined or logged in): answered always, even right after our own SendAll
    ns.Comm:On("Y", function() if db().enabled then T:SendAll(true); T:SendActive() end end)
    ns.Comm:On("P", function(f, _, sender) local id = tonumber(f[1]); if id then T:OnPicked(sender, id) end end)
    ns.Comm:On("A", function(f, _, sender) T:OnActive(sender, f[1]) end)
    ns.Comm:On("U", function(f, _, sender) local id = tonumber(f[1]); if id then T:OnShare(sender, id, f[2]) end end)
    ns.Comm:On("N", function(f, _, sender) local id = tonumber(f[1]); if id then T:Refused(sender, id, "no") end end)
    ns.Comm:On("B", function(f, _, sender) if db().enabled then T:OnBundle(sender, f[1]) end end)
    ns.Comm:On("T", function(f, _, sender) local id = tonumber(f[1]); if id then T:OthersTurnIn(sender, id) end end)
    ns.Comm:On("K", function(f, _, sender)
        local id = tonumber(f[1])
        if id and fromLeader(sender) then T:StopAlarm(id) end
    end)
    pcall(ns.On, "QUEST_TURNED_IN", function(_, id) ns.Debug.Call("Together", T.MyTurnIn, T, readable(id)) end)
    ns.Comm:On("D", function(f, _, sender) local id = tonumber(f[1]); if id then T:OnTurnedIn(sender, id) end end)
    pcall(ns.On, "QUEST_DETAIL", function() ns.Debug.Call("Together", T.QuestDetail, T) end)
    pcall(ns.On, "QUEST_ACCEPT_CONFIRM", function(_, ...) ns.Debug.Call("Together", T.AcceptConfirm, T, ...) end)
    pcall(ns.On, "CHAT_MSG_SYSTEM", function(_, msg) ns.Debug.Call("Together", T.SystemMessage, T, msg) end)
    T.mine = T.Scan()
    -- test quests a development copy sent before it kept them to itself: out of the saved group state
    local st0 = db().state
    if type(st0) == "table" then
        for _, set in pairs(st0) do
            if type(set) == "table" then
                for id in pairs(set) do if type(id) == "number" and id >= ns.Comm.TEST_IDS then set[id] = nil end end
            end
        end
    end
    -- What was known of the others before a /reload (kept for 15 minutes): the window is complete at once and only
    -- refreshed by their answers. Members no longer in the group drop out at the roster check below.
    local c = db().cache
    db().cache = nil
    if type(c) == "table" and type(c.at) == "number" and time() - c.at < 900 then
        T.members = type(c.members) == "table" and c.members or {}
        T.turnedIn = type(c.turnedIn) == "table" and c.turnedIn or {}
        if ns.GroupXP and type(c.xp) == "table" then
            for _, m in pairs(c.xp) do m.new = false end
            ns.GroupXP.members = c.xp
        end
        for name, m in pairs(T.members) do
            ns.Comm.seen[name] = GetTime()
            for id in pairs(type(m.quests) == "table" and m.quests or {}) do
                if id >= ns.Comm.TEST_IDS then m.quests[id] = nil end
            end
        end
    end
    pcall(ns.On, "PLAYER_LOGOUT", function()
        if T.testing or not T.InGroup() then return end
        db().cache = { at = time(), members = T.members, turnedIn = T.turnedIn, xp = ns.GroupXP and ns.GroupXP.members }
    end)
    pcall(ns.On, "QUEST_LOG_UPDATE", function() if db().enabled then scanSoon() end end)
    pcall(ns.On, "PLAYER_REGEN_ENABLED", function() if T.trackerPending then ns.Debug.Call("Together", T.CheckTracker, T) end end)
    pcall(ns.On, "GROUP_ROSTER_UPDATE", function() C_Timer.After(1, function() ns.Debug.Call("Together", T.RosterChanged, T) end) end)
    -- soon after logging in: your log read again (it may not have been there at once) and the group asked
    C_Timer.After(2, function()
        if not T.InGroup() then return end
        if not T.testing then T.mine = T.Scan() end
        ns.Debug.Call("Together", T.RosterChanged, T)
    end)
end)

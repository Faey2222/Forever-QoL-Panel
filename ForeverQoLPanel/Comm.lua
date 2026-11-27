local _, ns = ...

-- Our own channel to other users of this addon: invisible addon messages under the prefix "FQP" to the group, the
-- raid and the guild (the guild only outside instances), like Spy does it. A message is "kind|field|field...";
-- modules register a handler per kind. Nothing goes to strangers: only people you play with anyway get it.
--   V|version                              the sender's version (a newer one is pointed out once)
--   S|name|full|class|level|zone|flags     an enemy sighting (Radar.lua); flags: s = stealthed, t = targeting the sender
local C = {}
ns.Comm = C

C.PREFIX = "FQP"
C.handlers = {}
C.seen = {}      -- name -> when the last message of theirs came
C.recvLog = {}
C.sentLog = {}

-- one message out; what the game answered is noted for the debug data (the last 15)
local function deliver(msg, ch)
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, C.PREFIX, msg, ch)
    local log = C.sentLog
    log[#log + 1] = date("%H:%M:%S") .. " " .. ch .. " " .. msg:sub(1, 1) .. " ok=" .. tostring(ok) .. " res=" .. tostring(res)
    if #log > 15 then table.remove(log, 1) end
    ns.Debug.Set("commSent", log)
end

local function readable(v) if v == nil or ns.Secret(v) then return nil end return v end
-- your first name only (on Forever UnitName also gives the last name, as a second value)
local function me() return (UnitName("player")) end
-- the first name alone: without "-Realm" and without a last name after a space (Forever has both)
local function baseName(n) return type(n) == "string" and n:match("^([^%-%s]+)") or n end
C.BaseName = baseName

function C:On(kind, fn) self.handlers[kind] = fn end

-- where a message goes now: the raid or the group, and the guild outside instances
function C.Targets()
    local out = {}
    if IsInRaid and IsInRaid() then out[#out + 1] = "RAID"
    elseif IsInGroup and IsInGroup() then out[#out + 1] = "PARTY" end
    local inside = readable(select(1, IsInInstance()))
    if not inside and IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
    return out
end

-- only the group or raid (not the guild): for things that concern the group alone (quests)
function C.GroupTargets()
    if IsInRaid and IsInRaid() then return { "RAID" } end
    if IsInGroup and IsInGroup() then return { "PARTY" } end
    return {}
end

-- kind and fields joined with "|" (the fields must not contain it); at most a few messages a second
local queue, ticking = {}, false
function C:Send(kind, ...) return self:SendTo(C.Targets(), kind, ...) end
function C:SendGroup(kind, ...) return self:SendTo(C.GroupTargets(), kind, ...) end
-- what questing together sends: nothing of it while its test runs (made-up quests must not reach the real group)
C.TOGETHER = { Q = true, R = true, H = true, P = true, A = true, Y = true, U = true, N = true, D = true, T = true,
    K = true, B = true, X = true }

function C:SendTo(targets, kind, ...)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if C.TOGETHER[kind] and ns.Together and ns.Together.testing then return end
    local parts = { kind }
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        parts[#parts + 1] = tostring(v == nil and "" or v):gsub("|", "/")
    end
    local msg = table.concat(parts, "|")
    if #msg > 250 then return end
    for _, ch in ipairs(targets) do queue[#queue + 1] = { msg, ch } end
    if ticking then return end
    ticking = true
    local function step()
        local item = table.remove(queue, 1)
        if not item then ticking = false return end
        deliver(item[1], item[2])
        C_Timer.After(0.25, step)
    end
    step()
end

-- everything still waiting, at once (the waiting queue's timer is not needed then)
function C:Flush()
    while #queue > 0 do
        local item = table.remove(queue, 1)
        deliver(item[1], item[2])
    end
    ticking = false
end

function C:Received(prefix, message, channel, sender)
    if prefix ~= C.PREFIX or type(message) ~= "string" or ns.Secret(message) then return end
    if baseName(sender) == me() then return end   -- our own message coming back
    local kind, rest = message:match("^(%a)|?(.*)$")
    -- anyone who sends us anything uses the addon (even without quests or XP news); noted for the debug data
    local first = not C.seen[baseName(sender)]
    C.seen[baseName(sender)] = GetTime()
    if first and ns.Together and ns.Together.Changed then ns.Debug.Call("Comm", ns.Together.Changed, ns.Together) end
    local log = C.recvLog
    log[#log + 1] = date("%H:%M:%S") .. " " .. tostring(sender) .. " " .. tostring(channel) .. " " .. tostring(kind)
    if #log > 15 then table.remove(log, 1) end
    ns.Debug.Set("commReceived", log)
    if kind == "Y" and GetTime() - (C.lastHello or 0) > 5 then
        C.lastHello = GetTime()
        C:SendGroup("I")   -- "here I am": the asker learns of us even if we have nothing else to say
    end
    local h = kind and self.handlers[kind]
    if not h then return end
    local fields, start = {}, 1
    while true do
        local i = rest:find("|", start, true)
        if not i then fields[#fields + 1] = rest:sub(start); break end
        fields[#fields + 1] = rest:sub(start, i - 1)
        start = i + 1
    end
    -- a test quest of someone's development copy (ids from 900000): never taken for a real one
    local id = tonumber(fields[1])
    if C.TOGETHER[kind] and id and id >= C.TEST_IDS then return end
    h(fields, channel, baseName(sender))
end
C.TEST_IDS = 900000

-- Versions -------------------------------------------------------------------------------------------------------
-- a newer version among the people you play with: said once in the chat

local function parts(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end
function C.Newer(a, b)   -- is a newer than b?
    local a1, a2, a3 = parts(a)
    local b1, b2, b3 = parts(b)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

C:On("V", function(f)
    local v = f[1]
    if not ns.db.versionCheck or C.told or not v or not v:match("^%d+%.%d+%.%d+$") then return end
    if C.Newer(v, ns.VERSION) then
        C.told = true
        print("|cffffd100" .. ns.title .. "|r: " .. ns.L.NEW_VERSION:format(v, ns.VERSION))
    end
end)

local lastVersion = 0
function C:SendVersion()
    if not ns.db.versionCheck then return end
    local now = GetTime()
    if now - lastVersion < 60 then return end
    lastVersion = now
    self:Send("V", ns.VERSION)
end

ns.OnLogin(function()
    local reg = "missing"
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, C.PREFIX)
        reg = tostring(ok) .. "/" .. tostring(res)
    end
    ns.Debug.Set("commPrefix", { registered = reg, me = me(),
        send = C_ChatInfo and C_ChatInfo.SendAddonMessage and true or false })
    pcall(ns.On, "CHAT_MSG_ADDON", function(_, prefix, message, channel, sender)
        ns.Debug.Call("Comm", C.Received, C, prefix, message, channel, sender)
    end)
    C_Timer.After(15, function() ns.Debug.Call("Comm", C.SendVersion, C) end)
    pcall(ns.On, "GROUP_JOINED", function() C_Timer.After(5, function() ns.Debug.Call("Comm", C.SendVersion, C) end) end)
end)

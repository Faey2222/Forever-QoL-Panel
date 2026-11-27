local _, ns = ...

-- The group's XP: members using this addon tell each other their level and XP (our channel, group only). Shown at
-- the top of the quest window (or, setting xpSeparate, in a window of its own in the same look): class icon, name in
-- class colour, level and share of the level, and below them a bar in the art of our XP bar (rested part included).
-- Fills glide to new values, new members fade in.
-- Message: X|level|xp|max|rested|questXP|free|slots|ammo (questXP: the XP of the finished quests not turned in yet;
-- free/slots: free and all bag slots, special bags left out; ammo: hunters' ammunition, -1 for other classes; older
-- versions leave the last ones out). The bars show the quest XP as the panel's XP bar does (gold), the mouse over a
-- bar the details. Bag slots and ammunition stand behind the name, without animation; only low ammunition glows.
local G = {}
ns.GroupXP = G

local function db() return ns.db.together end
-- your first name only (on Forever UnitName also gives the last name, as a second value)
local function me() return (UnitName("player")) end

G.members = {}   -- name -> { level, xp, max, rested }

local ROW, BAR, BARY, SIDE, PAD, TOP, W = 40, 10, 22, 8, 14, 34, 260   -- BARY: the bar's top; SIDE: room for the caps

local function mine()
    local maxed = ns.XP.AtMaxLevel and ns.XP.AtMaxLevel()
    return UnitLevel("player") or 1, UnitXP("player") or 0, math.max(1, UnitXPMax("player") or 1),
        (GetXPExhaustion and GetXPExhaustion()) or 0, maxed and 0 or (ns.XP.cachedQuestXP or 0)
end

local function readable(v) if v == nil or ns.Secret(v) then return nil end return v end

-- your free and all bag slots (backpack and bags; quivers, ammo pouches and other special bags left out)
function G.Bags()
    local C = C_Container
    local numFree = (C and C.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    local numSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
    if not (numFree and numSlots) then return nil, nil end
    local free, all = 0, 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local f, kind = numFree(bag)
        f, kind = readable(f), readable(kind)
        if (kind == nil or kind == 0) and type(f) == "number" then
            free = free + f
            all = all + (readable(numSlots(bag)) or 0)
        end
    end
    return free, all
end

-- a hunter's ammunition (what is in the ammo slot, counted over the bags); -1 for other classes
G.LOW_AMMO = 200
function G.Ammo()
    local _, class = UnitClass("player")
    if readable(class) ~= "HUNTER" then return -1 end
    local slot = 0
    if GetInventorySlotInfo then
        local ok, s = pcall(GetInventorySlotInfo, "AmmoSlot")
        if ok and type(s) == "number" then slot = s end
    end
    local n = GetInventoryItemCount and readable(GetInventoryItemCount("player", slot))
    return type(n) == "number" and n or 0
end

local last = 0
function G:Send(force)
    local T = ns.Together
    if not (db().enabled and T.InGroup()) or T.testing then return end
    local now = GetTime()
    if not force and now - last < 3 then
        if not self.queued then
            self.queued = true
            C_Timer.After(3, function() G.queued = false; G:Send(true) end)
        end
        return
    end
    last = now
    local level, xp, mx, rested, q = mine()
    local free, all = G.Bags()
    self.sentInv = tostring(free) .. "/" .. tostring(all) .. "/" .. G.Ammo()
    ns.Comm:SendGroup("X", level, xp, mx, rested, q, free or "", all or "", G.Ammo())
end

-- bags or ammunition changed: told only if the numbers did (bag events come often)
function G:InventoryChanged()
    local free, all = G.Bags()
    local now = tostring(free) .. "/" .. tostring(all) .. "/" .. G.Ammo()
    if now ~= self.sentInv then self:Send() end
    self:Update()
end

function G:OnXP(sender, f)
    local level, xp, mx, rested, q = tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    if not (level and xp and mx and mx > 0) then return end
    local new = not self.members[sender]
    self.members[sender] = { level = level, xp = xp, max = mx, rested = rested or 0, quest = q or 0, new = new,
        free = tonumber(f[6]), slots = tonumber(f[7]), ammo = tonumber(f[8]) }
    self:Update()
end

-- you first, then the members with the addon (and the test partner), by name; nil when nobody else is known
function G:List()
    local T = ns.Together
    if not (db().enabled and db().xpWindow and T.InGroup()) then return nil end
    local level, xp, mx, rested, q = mine()
    local free, all = G.Bags()
    local list = { { name = me(), level = level, xp = xp, max = mx, rested = rested, quest = q, self = true,
        free = free, slots = all, ammo = G.Ammo() } }
    local names = {}
    for name in pairs(self.members) do if T.Roster()[name] then names[#names + 1] = name end end
    table.sort(names)
    for _, name in ipairs(names) do
        local m = self.members[name]
        list[#list + 1] = { name = name, level = m.level, xp = m.xp, max = m.max, rested = m.rested, quest = m.quest or 0, new = m.new,
            free = m.free, slots = m.slots, ammo = m.ammo }
        m.new = false
    end
    return #list >= 2 and list or nil
end

-- Rows (in any frame) ------------------------------------------------------------------------------------------

local function row(host, i)
    host.xpRows = host.xpRows or {}
    local r = host.xpRows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, host)
    r:SetHeight(ROW)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("TOPLEFT", 0, -2)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.info:SetPoint("TOPRIGHT", 0, -3)
    -- free bag slots and (hunters) ammunition, left of the level
    r.ammo = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.ammo:SetPoint("RIGHT", r.info, "LEFT", -10, 0)
    r.bags = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.bags:SetPoint("RIGHT", r.ammo, "LEFT", -8, 0)
    r.name:SetPoint("RIGHT", r.bags, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    -- the bar, in the XP bar's art (ground, rested part, fill, ticks) with the panel's bar border around it
    r.bar = CreateFrame("Frame", nil, r)
    r.bar:SetPoint("TOPLEFT", SIDE, -BARY)
    r.bar:SetPoint("RIGHT", -SIDE, 0)
    r.bar:SetHeight(BAR)
    r.rim = CreateFrame("Frame", nil, r)
    r.rim:SetAllPoints()
    r.rim:SetFrameLevel(r:GetFrameLevel() + 5)
    r.S = ns.Dock:NewSet(r.rim, r)
    r.ticks = {}
    for k = 1, 19 do
        local tk = r.bar:CreateTexture(nil, "ARTWORK", nil, 3)
        r.ticks[k] = tk
    end
    r.bg = r.bar:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.rest = r.bar:CreateTexture(nil, "ARTWORK", nil, 1)
    r.rest:SetPoint("TOPLEFT"); r.rest:SetPoint("BOTTOMLEFT")
    r.fill = r.bar:CreateTexture(nil, "ARTWORK", nil, 2)
    r.fill:SetPoint("TOPLEFT"); r.fill:SetPoint("BOTTOMLEFT")
    r.gold = r.bar:CreateTexture(nil, "ARTWORK", nil, 2)
    -- the details under the mouse (only the bar takes the mouse, so the window can still be dragged by the rest)
    r.bar:EnableMouse(true)
    r.bar:SetScript("OnEnter", function(bar) G:Tooltip(bar, r.entry) end)
    r.bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    host.xpRows[i] = r
    return r
end

-- a share of the bar in the art (cut like the XP bar cuts its own), the fill gliding to it
local function setBar(r, share, rest, width)
    local XP = ns.XP
    XP.Crop(r.bg, "bg", 0, 1)
    local rs = math.min(1, rest)
    if rs > share + 0.001 then
        r.rest:SetWidth(math.max(0.1, rs * width)); XP.Crop(r.rest, "rested", 0, rs); r.rest:Show()
    else
        r.rest:Hide()
    end
    local from = r.shown or share
    if from > share or ns.db.panel.animations == false then from = share end
    r.shown = share
    local function draw(v)
        if v <= 0.002 then r.fill:Hide() return end
        r.fill:SetWidth(math.max(0.1, v * width)); XP.Crop(r.fill, "fill", 0, v); r.fill:Show()
    end
    if from == share then draw(share) return end
    local t = 0
    local ticker = r.glider or CreateFrame("Frame")
    r.glider = ticker
    ticker:SetScript("OnUpdate", function(s, elapsed)
        t = math.min(1, t + elapsed / 0.6)
        local e = 1 - (1 - t) * (1 - t)
        draw(from + (share - from) * e)
        if t >= 1 then s:SetScript("OnUpdate", nil) end
    end)
end

local BAG_ICON = "|TInterface\\Icons\\INV_Misc_Bag_08:12:12:0:0:64:64:5:59:5:59|t"
local AMMO_ICON = "|TInterface\\Icons\\INV_Ammo_Arrow_02:12:12:0:0:64:64:5:59:5:59|t"

-- low ammunition glows red up and down (nothing else on these numbers moves)
local function ammoGlow(r, on)
    r.ammoPulse = r.ammoPulse or CreateFrame("Frame", nil, r)
    if not on or ns.db.panel.animations == false then
        r.ammoPulse:SetScript("OnUpdate", nil)
        r.ammo:SetAlpha(1)
        return
    end
    if r.ammoPulse:GetScript("OnUpdate") then return end
    local t = 0
    r.ammoPulse:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        r.ammo:SetAlpha(0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 4)))
    end)
end

-- bag slots and ammunition of a row; unknown (an older version) -> nothing
local function inventory(r, e)
    if e.free and e.slots and e.slots > 0 then
        local c = e.free == 0 and "|cffff3020" or (e.free <= 3 and "|cffffa040" or "|cffffffff")
        r.bags:SetText(BAG_ICON .. " " .. c .. e.free .. "|r")
    else
        r.bags:SetText("")
    end
    local low = e.ammo and e.ammo >= 0 and e.ammo < G.LOW_AMMO
    if e.ammo and e.ammo >= 0 then
        r.ammo:SetText(AMMO_ICON .. " " .. (low and "|cffff3020" or "|cffffffff") .. e.ammo .. "|r")
    else
        r.ammo:SetText("")
    end
    ammoGlow(r, low)
end

-- The name in the room the row leaves it: the full name if it fits, else "First L.", else cut with "…" (no line
-- break). When even that gets too tight, the ammunition and then the bag slots leave the row (the tooltip keeps them).
local MIN_NAME = 48
local function fitName(r, e, width)
    local T = ns.Together
    local function used()
        local w = 14 + 5 + (r.info:GetStringWidth() or 0) + 10
        if (r.ammo:GetText() or "") ~= "" then w = w + (r.ammo:GetStringWidth() or 0) + 8 end
        if (r.bags:GetText() or "") ~= "" then w = w + (r.bags:GetStringWidth() or 0) + 6 end
        return w
    end
    if width - used() < MIN_NAME and (r.ammo:GetText() or "") ~= "" then
        r.ammo:SetText(""); r.ammoPulse:SetScript("OnUpdate", nil); r.ammo:SetAlpha(1)
    end
    if width - used() < MIN_NAME then r.bags:SetText("") end
    local room = width - used()
    r.name:SetText(T.ShowName(e.name, 9999))
    if (r.name:GetStringWidth() or 0) > room then r.name:SetText(T.ShowName(e.name, 0)) end
end

-- the rows into a frame from its top, as wide as width; returns their height
function G:Render(host, list, width)
    local T = ns.Together
    local bw = width - 2 * SIDE
    local every = ns.db.panel.ticks or 10
    for i, e in ipairs(list) do
        local r = row(host, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -(i - 1) * ROW)
        r:SetWidth(width)
        T.ClassIcon(r.icon, e.name)
        local class = T.ClassOf(e.name)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then r.name:SetTextColor(c.r, c.g, c.b) else r.name:SetTextColor(1, 1, 1) end
        local share = math.min(1, e.xp / e.max)
        r.info:SetText(ns.L.LEVEL_N:format(e.level) .. "  |cffffffff" .. string.format("%d %%", math.floor(share * 100 + 0.5)) .. "|r")
        inventory(r, e)
        fitName(r, e, width)
        -- the border like the panel's XP bar, the ticks like its dividers
        ns.Dock:DrawBarBorder(r.S, r, SIDE, BARY, bw, BAR)
        for k, tk in ipairs(r.ticks) do
            local pct = k * 5
            if every > 0 and pct % every == 0 and pct < 100 then
                ns.XP.Crop(tk, "tick", 0, 1)
                tk:ClearAllPoints()
                tk:SetPoint("TOP", r.bar, "TOPLEFT", bw * pct / 100, 0)
                tk:SetSize(2, BAR)
                tk:Show()
            else
                tk:Hide()
            end
        end
        setBar(r, share, share + (e.rested or 0) / e.max, bw)
        -- finished quests not turned in yet, in gold like on the panel's XP bar
        r.entry = e
        local q = ns.db.panel.questPreview ~= false and (e.quest or 0) or 0
        local pq = math.min(1, share + q / e.max)
        if pq > share + 0.002 then
            r.gold:ClearAllPoints()
            r.gold:SetPoint("TOPLEFT", r.bar, "TOPLEFT", share * bw, 0)
            r.gold:SetSize(math.max(0.1, (pq - share) * bw), BAR)
            ns.XP.Crop(r.gold, "gold", share, pq)
            r.gold:SetAlpha(0.85)
            r.gold:Show()
        else
            r.gold:Hide()
        end
        if e.new and ns.db.panel.animations ~= false then
            r:SetAlpha(0)
            local t = 0
            local fader = r.fader or CreateFrame("Frame")
            r.fader = fader
            fader:SetScript("OnUpdate", function(s, elapsed)
                t = math.min(1, t + elapsed / 0.5)
                r:SetAlpha(t)
                if t >= 1 then s:SetScript("OnUpdate", nil) end
            end)
        end
        r:Show()
    end
    for i = #list + 1, #(host.xpRows or {}) do host.xpRows[i]:Hide() end
    return #list * ROW
end

-- the mouse over a bar: yours is the panel XP bar's tooltip, a member's the same numbers as far as they are known
local function num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(n + 0.5)) or tostring(math.floor(n + 0.5)) end
function G:Tooltip(owner, e)
    if not e then return end
    if e.self then ns.XP:ShowTooltip(owner) return end
    local L = ns.L
    local tt = GameTooltip
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:AddLine(e.name, 1, 1, 1)
    tt:AddLine(L.LEVEL_N:format(e.level), 1, 0.82, 0)
    tt:AddDoubleLine(L.EXPERIENCE, string.format("%s / %s (%.1f %%)", num(e.xp), num(e.max), e.xp / e.max * 100), 1, 0.82, 0, 1, 1, 1)
    if (e.rested or 0) > 0 then tt:AddDoubleLine(L.RESTED, "+" .. num(e.rested), 0.35, 0.5, 1, 0.35, 0.5, 1) end
    if e.free and e.slots then tt:AddDoubleLine(L.GXP_BAGS, L.GXP_BAGS_N:format(e.free, e.slots), 1, 0.82, 0, 1, 1, 1) end
    if e.ammo and e.ammo >= 0 then
        local low = e.ammo < G.LOW_AMMO
        tt:AddDoubleLine(L.GXP_AMMO, num(e.ammo), 1, 0.82, 0, 1, low and 0.2 or 1, low and 0.13 or 1)
    end
    local q = e.quest or 0
    if q > 0 then
        tt:AddLine(" ")
        tt:AddDoubleLine(L.GXP_QUESTS, string.format("+%s  (%.1f %%)", num(q), q / e.max * 100), 1, 0.78, 0.2, 1, 0.78, 0.2)
        if e.xp + q >= e.max then
            tt:AddLine(L.QUESTS_ENOUGH:format(e.level + 1, num(e.xp + q - e.max)), 0.12, 1, 0)
        else
            tt:AddLine(L.QUESTS_MISSING:format(num(e.max - e.xp - q)), 1, 0.13, 0.13)
        end
    end
    tt:Show()
end

function G.HideRows(host) for _, r in ipairs(host and host.xpRows or {}) do r:Hide() end end

-- The window of its own (setting xpSeparate) -------------------------------------------------------------------

function G:Frame()
    if self.frame then return self.frame end
    local T = ns.Together
    local f = CreateFrame("Frame", "ForeverQoLPanelGroupXP", UIParent, "BackdropTemplate")
    f:SetSize(W, 60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if not db().xpLocked then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local l, t = s:GetLeft(), s:GetTop()
        if l and t then db().xpPos = { l, t - UIParent:GetHeight() } end
    end)
    f:SetScript("OnSizeChanged", function(s) ns.UI.Skin(s) end)
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
    local line = CreateFrame("Frame", nil, f)
    line:SetPoint("TOPLEFT", f.band, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", f.band, "BOTTOMRIGHT")
    line:SetHeight(1)
    T.FadeLine(line)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f.band, "LEFT", 8, 0)
    f.lock = T.IconButton(f, T.ICON_LOCK[1], T.ICON_LOCK[2], T.ICON_LOCK[3],
        function() return db().xpLocked and ns.L.TOG_UNLOCK or ns.L.TOG_LOCK end,
        function() db().xpLocked = not db().xpLocked; G:Update() end)
    f.lock:SetPoint("RIGHT", f.band, "RIGHT", -6, 0)
    f.host = CreateFrame("Frame", nil, f)
    f.host:SetPoint("TOPLEFT", PAD, -TOP - 4)
    f.host:SetSize(W - 2 * PAD, 10)
    f:Hide()
    self.frame = f
    return f
end

-- in the quest window (Together.lua draws the section) or in the window of its own
function G:Update()
    local T = ns.Together
    local d = db()
    -- the quest window draws (or drops) its XP section itself
    if T.frame and not self.inQuest then self.inQuest = true; T:Changed(); self.inQuest = false end
    if not d.xpSeparate then
        if self.frame then self.frame:Hide() end
        return
    end
    local f = self:Frame()
    f.lock:SetOn(d.xpLocked)
    local list = self:List()
    if not list then f:Hide() return end
    f.title:SetText(ns.L.SEC_GROUPXP)
    local h = self:Render(f.host, list, W - 2 * PAD)
    f.host:SetHeight(h)
    f:SetHeight(TOP + 4 + h + 10)
    f:ClearAllPoints()
    local q = T.frame
    if d.xpPos then f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", d.xpPos[1], d.xpPos[2])
    elseif q and q:IsShown() then f:SetPoint("TOPLEFT", q, "BOTTOMLEFT", 0, -4)
    else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -260) end
    ns.UI.Skin(f)
    f:Show()
end

ns.OnLogin(function()
    if not ns.Comm then return end
    ns.Comm:On("X", function(f, _, sender) if db().enabled then G:OnXP(sender, f) end end)
    -- asked for everything (a new member): our XP too
    local prevY = ns.Comm.handlers.Y
    ns.Comm:On("Y", function(...) if prevY then prevY(...) end; G:Send(true) end)
    for _, ev in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION" }) do
        pcall(ns.On, ev, function() G:Send(); G:Update() end)
    end
    -- bags and ammunition (shooting uses up arrows): told when the numbers change, at most every three seconds
    for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do
        pcall(ns.On, ev, function(_, unit)
            if ev == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
            ns.Debug.Call("GroupXP", G.InventoryChanged, G)
        end)
    end
    -- the finished quests' XP changed (the panel's XP bar counted them again): the group hears it
    if ns.XP and ns.XP.ScanQuests then hooksecurefunc(ns.XP, "ScanQuests", function() G:Send(); G:Update() end) end
    pcall(ns.On, "GROUP_ROSTER_UPDATE", function()
        C_Timer.After(1.5, function()
            local roster = ns.Together.Roster()
            for name in pairs(G.members) do if not roster[name] then G.members[name] = nil end end
            G:Send(true)
            G:Update()
        end)
    end)
    -- the quest window changes: the separate XP window hanging below it follows
    hooksecurefunc(ns.Together, "Changed", function() if db().xpSeparate and not db().xpPos then G:Update() end end)
end)

local _, ns = ...

-- The elements in the panel: icon + text, a tooltip, an optional click. Order and visibility come from the
-- settings; the elements can be dragged to a new place, a right-click opens the panel menu.
local E = { defs = {}, cells = {} }
ns.Elements = E

local BH, ICON, GAP, PIN = 26, 16, 5, 22
local function side() return ns.Dock and ns.Dock.Side and ns.Dock:Side() or 46 end
local fmt, floor, ceil, abs = string.format, math.floor, math.ceil, math.abs
local HEARTHSTONE = 6948
local HONOR, FAVOR = 1792, 3402
local REAGENT_BAG = 5

local L = setmetatable({}, { __index = function(_, k) return ns.L[k] end })

local font = CreateFont("ForeverQoLPanelFont")
font:SetFontObject(GameFontHighlight)
font:SetFont(STANDARD_TEXT_FONT, 12, "")
font:SetShadowOffset(1, -1)
font:SetShadowColor(0, 0, 0, 1)

function E.ApplyFont()
    font:SetFont(ns.FontFile(), 12, "")
end

local function money(c, plain)
    c = floor(c or 0)
    if GetCoinTextureString and not plain then return GetCoinTextureString(c, 11) end
    return GetMoneyString and GetMoneyString(c, true) or tostring(c)
end

local function num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(floor(n + 0.5)) or tostring(floor(n + 0.5)) end

local function opt(key) return ns.db.panel.opt[key] end

local function def(key, d)
    d.key = key
    E.defs[key] = d
end

local function header(tt, text) tt:AddLine(text, 1, 1, 1) end
local function hint(tt, text) tt:AddLine(text, 0.12, 1, 0) end
local function line(tt, left, right) tt:AddDoubleLine(left, right, 1, 0.82, 0, 1, 1, 1) end

-- Small tweens (hover, flashes, pin): one per id, each runs from `from` to `to`.
local tweens = {}
local driver = CreateFrame("Frame")
local function step(_, elapsed)
    local any
    for id, tw in pairs(tweens) do
        tw.t = math.min(1, tw.t + elapsed / tw.dur)
        local e = tw.t * tw.t * (3 - 2 * tw.t)
        tw.set(tw.from + (tw.to - tw.from) * e)
        if tw.t >= 1 then tweens[id] = nil else any = true end
    end
    if not any then driver:SetScript("OnUpdate", nil) end
end
local function tween(id, from, to, dur, set)
    if not ns.db.panel.animations or dur <= 0 then tweens[id] = nil; set(to); return end
    tweens[id] = { from = from, to = to, t = 0, dur = dur, set = set }
    driver:SetScript("OnUpdate", step)
end
E.Tween = tween

-- Hearthstone -----------------------------------------------------------------------

def("hearth", {
    icon = "Interface\\Icons\\INV_Misc_Rune_01",
    flash = true,
    text = function() return GetBindLocation and GetBindLocation() or "?" end,
    tip = function(tt)
        header(tt, L.ITEM_hearth)
        tt:AddLine(GetBindLocation and GetBindLocation() or "?", 1, 0.82, 0)
        local count = ns.ItemCount(HEARTHSTONE)
        local getCD = C_Container and C_Container.GetItemCooldown or GetItemCooldown
        local start, dur = 0, 0
        if getCD then start, dur = getCD(HEARTHSTONE) end
        local left = (start or 0) > 0 and (start + dur - GetTime()) or 0
        if left > 0 then
            line(tt, L.COOLDOWN, SecondsToTime and SecondsToTime(left) or fmt("%d s", left))
        else
            tt:AddDoubleLine(L.COOLDOWN, L.READY, 1, 0.82, 0, 0.12, 1, 0)
        end
        if count > 0 then hint(tt, L.CLICK_HEARTH) else tt:AddLine(L.NO_HEARTH, 0.62, 0.62, 0.62) end
    end,
})

-- Gold ----------------------------------------------------------------------------

local realm, faction, me
local lastMoney
local function S() return ns.Session() end

local function store()
    local m = GetMoney()
    ns.db.gold[realm] = ns.db.gold[realm] or {}
    ns.db.gold[realm][faction] = ns.db.gold[realm][faction] or {}
    ns.db.gold[realm][faction][me] = { money = m, class = select(2, UnitClass("player")) }
    if lastMoney then
        local d = m - lastMoney
        local s = S()
        if d > 0 then s.income = s.income + d elseif d < 0 then s.spent = s.spent - d end
    end
    lastMoney = m
end

def("gold", {
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    flash = true,
    text = function() return money(GetMoney()) end,
    tip = function(tt)
        header(tt, L.GOLD_REALM)
        tt:AddLine(fmt("%s, %s", realm or "?", faction or "?"), 0.62, 0.62, 0.62)
        local chars, total = {}, 0
        for name, e in pairs(ns.db.gold[realm] and ns.db.gold[realm][faction] or {}) do
            chars[#chars + 1] = { name, e }
            total = total + (e.money or 0)
        end
        table.sort(chars, function(a, b) return (a[2].money or 0) > (b[2].money or 0) end)
        tt:AddLine(" ")
        for _, c in ipairs(chars) do
            local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c[2].class or ""]
            local r, g, b = 1, 1, 1
            if col then r, g, b = col.r, col.g, col.b end
            tt:AddDoubleLine(c[1], money(c[2].money), r, g, b, 1, 1, 1)
        end
        tt:AddLine(" ")
        line(tt, L.TOTAL, money(total))
    end,
})

-- the whole amount in green or red
local function signed(d)
    if d == 0 then return "|cffa0a0a0" .. money(0) .. "|r" end
    return (d > 0 and "|cff1eff00+" or "|cffff3030-") .. money(abs(d)) .. "|r"
end

def("session", {
    icon = "Interface\\Icons\\Achievement_GuildPerk_CashFlow",
    flash = true,
    text = function() return signed(GetMoney() - S().startMoney) end,
    tip = function(tt)
        header(tt, L.ITEM_session)
        tt:AddDoubleLine(L.EARNED, money(S().income), 1, 0.82, 0, 0.12, 1, 0)
        tt:AddDoubleLine(L.SPENT, money(S().spent), 1, 0.82, 0, 1, 0.19, 0.19)
        tt:AddLine(" ")
        line(tt, L.BALANCE, signed(GetMoney() - S().startMoney))
    end,
})

-- Bags ----------------------------------------------------------------------------

local band = bit and bit.band or function(a, b) return a % (b * 2) >= b and b or 0 end

local function bagInfo(bag)
    local CC = C_Container
    local free, kind
    if CC and CC.GetContainerNumFreeSlots then free, kind = CC.GetContainerNumFreeSlots(bag)
    elseif GetContainerNumFreeSlots then free, kind = GetContainerNumFreeSlots(bag) end
    local total = (CC and CC.GetContainerNumSlots and CC.GetContainerNumSlots(bag))
        or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
    return free or 0, total, kind or 0
end

-- "bags" (normal), "ammo" (quivers, ammo pouches) or "materials" (profession bags, reagent bag)
local function bagGroup(bag, kind)
    if bag == REAGENT_BAG then return "materials" end
    if kind == 0 then return "bags" end
    if band(kind, 1) > 0 or band(kind, 2) > 0 then return "ammo" end
    return "materials"
end

local function bagName(bag)
    if bag == 0 then return BACKPACK_TOOLTIP or "Backpack" end
    return (C_Container and C_Container.GetBagName and C_Container.GetBagName(bag)) or (GetBagName and GetBagName(bag))
        or ("Bag " .. bag)
end

local function slots(group)
    local free, total, list = 0, 0, {}
    for bag = 0, REAGENT_BAG do
        local f, t, kind = bagInfo(bag)
        if t > 0 and bagGroup(bag, kind) == group then
            free, total = free + f, total + t
            list[#list + 1] = { bagName(bag), f, t }
        end
    end
    return free, total, list
end

local function slotText(group)
    local free, total = slots(group)
    if total == 0 then return "|cffa0a0a0-|r" end
    local col = free == 0 and "|cffff3030" or free <= 2 and "|cffffd100" or ""
    return fmt("%s%d/%d%s", col, free, total, col ~= "" and "|r" or "")
end

local function slotTip(tt, group, title, empty)
    header(tt, title)
    local _, total, list = slots(group)
    if total == 0 and empty then tt:AddLine(empty, 0.62, 0.62, 0.62) end
    for _, b in ipairs(list) do tt:AddDoubleLine(b[1], fmt(L.FREE_OF, b[2], b[3]), 1, 1, 1, 1, 1, 1) end
end

local function openBags() if ToggleAllBags then ToggleAllBags() end end

def("bags", {
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    flash = true,
    text = function() return slotText("bags") end,
    tip = function(tt)
        slotTip(tt, "bags", L.ITEM_bags)
        hint(tt, L.CLICK_BAGS)
    end,
    click = openBags,
})

def("materials", {
    icon = "Interface\\Icons\\INV_Misc_Bag_10_Green",
    flash = true,
    text = function() return slotText("materials") end,
    tip = function(tt)
        slotTip(tt, "materials", L.ITEM_materials, L.NO_MATERIAL_BAG)
        hint(tt, L.CLICK_BAGS)
    end,
    click = openBags,
})

local function ammoSlot()
    if GetInventorySlotInfo then
        local ok, slot = pcall(GetInventorySlotInfo, "AmmoSlot")
        if ok and slot then return slot end
    end
    return 0
end

-- Ammo in the bags, the kind the ranged weapon shoots: arrows for bows and crossbows, bullets for guns (both
-- without a known weapon). Counted from the bags, because the client may have no readable ammo slot at all.
local PROJECTILE, ARROW, BULLET = 6, 2, 3
local BOW, GUN, CROSSBOW = 2, 3, 18
local function itemClass(id)
    if not id then return nil end
    local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not get then return nil end
    local ok, _, _, _, _, _, classID, subID = pcall(get, id)
    if ok then return classID, subID end
end

local function wantedAmmo()
    local id = GetInventoryItemID and GetInventoryItemID("player", 18)
    local classID, subID = itemClass(id)
    if classID == 2 and subID == GUN then return BULLET end
    if classID == 2 and (subID == BOW or subID == CROSSBOW) then return ARROW end
    return nil
end

local CC = C_Container
-- counted once per bag change, not on every panel update
local ammoCache
ns.On("BAG_UPDATE_DELAYED", function() ammoCache = nil end)
ns.On("UNIT_INVENTORY_CHANGED", function(_, unit) if unit == "player" then ammoCache = nil end end)
local function bagAmmo()
    if ammoCache then return ammoCache[1], ammoCache[2] end
    local want, total, link = wantedAmmo(), 0, nil
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local n = (CC and CC.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0
        for slot = 1, n do
            local id, count, l
            if CC and CC.GetContainerItemInfo then
                local info = CC.GetContainerItemInfo(bag, slot)
                if info then id, count, l = info.itemID, info.stackCount, info.hyperlink end
            end
            local classID, subID = itemClass(id)
            if classID == PROJECTILE and (not want or subID == want) then
                total = total + (count or 1)
                link = link or l
            end
        end
    end
    ammoCache = { total, link }
    return total, link
end

-- the ammo you carry and a link to show; the equipped ammo slot first where the client has one
local function ammoCount()
    local slot = ammoSlot()
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if link then
        local ok, n = pcall(GetInventoryItemCount, "player", slot)
        if ok and n and not ns.Secret(n) and n > 0 then return n, link end
    end
    local n, bagLink = bagAmmo()
    return n, link or bagLink
end
E.AmmoCount = ammoCount

def("ammo", {
    class = "HUNTER",
    icon = "Interface\\Icons\\INV_Ammo_Arrow_02",
    flash = true,
    text = function()
        -- the ammo you carry first, the free slots of the ammo pouch after it in grey
        local n = ammoCount()
        local _, total = slots("ammo")
        local count = n and num(n) or "|cffa0a0a0-|r"
        if n and n < (ns.db.warnings.ammoMin or 200) then count = "|cffff3030" .. count .. "|r" end
        if total == 0 then return count end
        return count .. "  |cffa0a0a0" .. slotText("ammo"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r"
    end,
    tip = function(tt)
        slotTip(tt, "ammo", L.ITEM_ammo, L.NO_AMMO_BAG)
        local n, link = ammoCount()
        tt:AddLine(" ")
        line(tt, link or L.ITEM_ammo, num(n or 0))
        hint(tt, L.CLICK_BAGS)
    end,
    click = openBags,
})

-- Soul shards (warlocks) ----------------------------------------------------------------

local SOUL_SHARD = 6265

def("shards", {
    class = "WARLOCK",
    icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
    flash = true,
    text = function()
        local n = ns.ItemCount(SOUL_SHARD)
        if n == 0 then return "|cffff3030" .. n .. "|r" end
        return tostring(n)
    end,
    tip = function(tt)
        header(tt, L.ITEM_shards)
        line(tt, L.SHARDS_CARRIED, num(ns.ItemCount(SOUL_SHARD)))
        hint(tt, L.CLICK_BAGS)
    end,
    click = openBags,
})

-- Mail -------------------------------------------------------------------------------
-- New mail glows in the panel until it is read: a gentle pulse, or a steady glow with fewer animations.

local function mailSenders()
    local list = {}
    if GetLatestThreeSenders then
        for _, name in ipairs({ GetLatestThreeSenders() }) do
            if name and not ns.Secret(name) and name ~= "" then list[#list + 1] = name end
        end
    end
    return list
end

def("mail", {
    icon = "Interface\\Icons\\INV_Letter_15",
    minWidth = 40,
    text = function()
        if not (HasNewMail and HasNewMail()) then return "|cffa0a0a0" .. L.MAIL_NONE .. "|r" end
        local s = mailSenders()
        if #s == 1 then return "|cffffd100" .. s[1] .. "|r" end
        if #s > 1 then return "|cffffd100" .. L.MAIL_FROM_N:format(#s) .. "|r" end
        return "|cffffd100" .. L.MAIL_NEW .. "|r"
    end,
    pulse = function() return HasNewMail and HasNewMail() and true or false end,
    tip = function(tt)
        header(tt, L.ITEM_mail)
        if HasNewMail and HasNewMail() then
            local s = mailSenders()
            if #s > 0 then
                tt:AddLine(L.MAIL_FROM, 1, 0.82, 0)
                for _, name in ipairs(s) do tt:AddLine("  " .. name, 1, 1, 1) end
            else
                tt:AddLine(L.MAIL_NEW, 1, 0.82, 0)
            end
        else
            tt:AddLine(L.MAIL_NONE, 0.62, 0.62, 0.62)
        end
    end,
})

-- Durability ----------------------------------------------------------------------

local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
local function durability()
    local lowest, items = 1, {}
    for _, s in ipairs(SLOTS) do
        local cur, mx = GetInventoryItemDurability(s)
        if cur and mx and mx > 0 then
            local p = cur / mx
            lowest = math.min(lowest, p)
            if p < 1 then items[#items + 1] = { GetInventoryItemLink("player", s), p } end
        end
    end
    return lowest, items
end

def("durability", {
    icon = "Interface\\Icons\\Trade_BlackSmithing",
    flash = true,
    minWidth = 30,
    text = function()
        local p = durability()
        local col = p < 0.25 and "|cffff2020" or p < 0.5 and "|cffffd100" or ""
        return fmt("%s%d %%%s", col, floor(p * 100 + 0.5), col ~= "" and "|r" or "")
    end,
    tip = function(tt)
        header(tt, L.ITEM_durability)
        local _, items = durability()
        table.sort(items, function(a, b) return a[2] < b[2] end)
        if #items == 0 then tt:AddLine(L.PERFECT_SHAPE, 0.62, 0.62, 0.62) end
        for _, e in ipairs(items) do tt:AddDoubleLine(e[1] or "?", fmt("%d %%", floor(e[2] * 100 + 0.5)), 1, 1, 1, 1, 1, 1) end
        hint(tt, L.CLICK_CHARACTER)
    end,
    click = function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end,
})

-- Currencies ------------------------------------------------------------------------

local function currency(id)
    local CI = C_CurrencyInfo
    local info = CI and CI.GetCurrencyInfo and CI.GetCurrencyInfo(id)
    if info then return info.quantity or 0, info end
end

local function currencyTip(tt, id, title)
    local q, info = currency(id)
    header(tt, info and info.name or title)
    if info and info.description and info.description ~= "" then
        tt:AddLine(info.description, 1, 0.82, 0, true)
        tt:AddLine(" ")
    end
    line(tt, L.AMOUNT, q and num(q) or "-")
    if info and (info.maxQuantity or 0) > 0 then line(tt, L.MAXIMUM, num(info.maxQuantity)) end
    hint(tt, L.CLICK_CURRENCY)
end

local function openCurrency() if ToggleCharacter then pcall(ToggleCharacter, "TokenFrame") end end

def("honor", {
    icon = function()
        return UnitFactionGroup("player") == "Horde" and "Interface\\Icons\\INV_BannerPVP_01" or "Interface\\Icons\\INV_BannerPVP_02"
    end,
    flash = true,
    text = function()
        local q = currency(HONOR)
        if not q and GetHonorCurrency then q = GetHonorCurrency() end
        return q and num(q) or "-"
    end,
    tip = function(tt) currencyTip(tt, HONOR, L.ITEM_honor) end,
    click = openCurrency,
})

def("favor", {
    icon = function()
        local _, info = currency(FAVOR)
        return info and info.iconFileID or 135725
    end,
    flash = true,
    text = function()
        local q = currency(FAVOR)
        return q and num(q) or "-"
    end,
    tip = function(tt) currencyTip(tt, FAVOR, L.ITEM_favor) end,
    click = openCurrency,
})

-- PvP flag: on / off, and the time until it runs out ------------------------------

local function pvpState()
    if UnitIsPVPFreeForAll and UnitIsPVPFreeForAll("player") then return "ffa" end
    if not UnitIsPVP("player") then return "off" end
    local ms = GetPVPTimer and GetPVPTimer()
    local running = IsPVPTimerRunning and IsPVPTimerRunning()
    if running and ms and ms > 0 and ms < 301000 then return "timer", ms / 1000 end
    return "on"
end

local function mmss(sec)
    sec = math.max(0, floor(sec))
    return fmt("%d:%02d", floor(sec / 60), sec % 60)
end

def("pvp", {
    icon = "Interface\\Icons\\Ability_DualWield",
    minWidth = 40,
    text = function()
        local state, left = pvpState()
        if state == "off" then return "|cff1eff00" .. L.PVP_OFF .. "|r" end
        if state == "ffa" then return "|cffff3030" .. L.PVP_FFA .. "|r" end
        if state == "timer" then return "|cffff3030PvP|r " .. mmss(left) end
        return "|cffff3030PvP|r"
    end,
    tip = function(tt)
        header(tt, L.ITEM_pvp)
        local state, left = pvpState()
        if state == "off" then
            tt:AddLine(L.PVP_NOT_FLAGGED, 0.12, 1, 0)
        elseif state == "ffa" then
            tt:AddLine(L.PVP_FFA_LONG, 1, 0.19, 0.19)
        else
            tt:AddLine(L.PVP_FLAGGED, 1, 0.19, 0.19)
            if state == "timer" then line(tt, L.PVP_ENDS_IN, mmss(left)) else tt:AddLine(L.PVP_PERMANENT, 0.62, 0.62, 0.62, true) end
        end
        hint(tt, L.CLICK_PVP)
    end,
    click = function()
        if TogglePVP then TogglePVP()
        elseif SetPVP and GetPVPDesired then SetPVP(not GetPVPDesired()) end
        C_Timer.After(0.3, function() E:UpdateTexts(); ns.Dock:Relayout() end)
    end,
})

-- Location ------------------------------------------------------------------------

local function position()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if pos then
        local x, y = pos:GetXY()
        if x and (x > 0 or y > 0) then return x * 100, y * 100 end
    end
end

local function coordText()
    local x, y = position()
    return x and fmt("%.1f, %.1f", x, y) or "-"
end

local function openMap() if ToggleWorldMap then ToggleWorldMap() end end

def("zone", {
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    minWidth = 70,
    center = true,
    text = function()
        local sub = GetSubZoneText()
        local zone = (sub and sub ~= "") and sub or GetZoneText() or ""
        if opt("zoneCoords") then zone = zone .. "  |cffa0a0a0" .. coordText() .. "|r" end
        return zone
    end,
    tip = function(tt)
        header(tt, GetZoneText() or "")
        local sub = GetSubZoneText()
        if sub and sub ~= "" then tt:AddLine(sub, 1, 0.82, 0) end
        line(tt, L.ITEM_coords, coordText())
        hint(tt, L.CLICK_MAP)
    end,
    click = openMap,
})

def("coords", {
    icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
    minWidth = 62,
    text = coordText,
    tip = function(tt)
        header(tt, L.ITEM_coords)
        line(tt, GetZoneText() or "", coordText())
        hint(tt, L.CLICK_MAP)
    end,
    click = openMap,
})

-- XP per hour ---------------------------------------------------------------------

def("xph", {
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    text = function()
        local v = ns.XP.PerHour()
        local s = v and (num(v) .. " XP/h") or "- XP/h"
        if opt("xphTime") then s = s .. "  |cffa0a0a0" .. ns.XP.Duration(ns.XP.TimeToLevel(), true) .. "|r" end
        return s
    end,
    tip = function(tt)
        header(tt, L.ITEM_xph)
        line(tt, L.MEASURED_SINCE, L.SINCE_LEVEL)
        line(tt, L.XP_SESSION, num(ns.XP.SessionXP()))
        line(tt, L.TIME_TO_NEXT, ns.XP.Duration(ns.XP.TimeToLevel()))
    end,
})

-- Clock, latency, frame rate ------------------------------------------------------

def("clock", {
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    minWidth = 32,
    text = function()
        if opt("serverTime") then
            local h, m = GetGameTime()
            return fmt("%02d:%02d", h, m)
        end
        return date("%H:%M")
    end,
    tip = function(tt)
        header(tt, L.ITEM_clock)
        line(tt, L.LOCAL_TIME, date("%H:%M"))
        local h, m = GetGameTime()
        line(tt, L.SERVER_TIME, fmt("%02d:%02d", h, m))
        hint(tt, L.CLICK_CALENDAR)
    end,
    click = function() if ToggleCalendar then ToggleCalendar() end end,
})

-- Stopwatch: click starts / pauses, shift-click resets. Runs for this session only.
local watch = { running = false, started = 0, total = 0 }

local function watchTime()
    return watch.total + (watch.running and GetTime() - watch.started or 0)
end

local function clockString(sec)
    sec = floor(sec)
    local h, m, s = floor(sec / 3600), floor(sec % 3600 / 60), sec % 60
    if h > 0 then return fmt("%d:%02d:%02d", h, m, s) end
    return fmt("%d:%02d", m, s)
end

def("stopwatch", {
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_02",
    minWidth = 30,
    text = function()
        local s = clockString(watchTime())
        if watch.running then return s end
        return "|cffa0a0a0" .. s .. "|r"
    end,
    tip = function(tt)
        header(tt, L.ITEM_stopwatch)
        line(tt, watch.running and L.RUNNING or L.STOPPED, clockString(watchTime()))
        hint(tt, watch.running and L.CLICK_PAUSE or L.CLICK_START)
        hint(tt, L.SHIFT_RESET)
    end,
    click = function(cell)
        if IsShiftKeyDown() then
            watch.running, watch.total = false, 0
        elseif watch.running then
            watch.total, watch.running = watchTime(), false
        else
            watch.started, watch.running = GetTime(), true
        end
        E:UpdateTexts()
        if cell and cell:IsMouseOver() then GameTooltip:Hide(); E.ShowTip(cell) end
    end,
})

local function latencyColor(ms)
    if ms < 150 then return "|cff1eff00" elseif ms < 300 then return "|cffffd100" end
    return "|cffff2020"
end

def("latency", {
    icon = "Interface\\Icons\\INV_Gizmo_02",
    minWidth = 40,
    text = function()
        local _, _, home = GetNetStats()
        return latencyColor(home or 0) .. (home or 0) .. "|r ms"
    end,
    tip = function(tt)
        header(tt, L.ITEM_latency)
        local _, _, home, world = GetNetStats()
        line(tt, L.HOME, (home or 0) .. " ms")
        line(tt, L.WORLD, (world or 0) .. " ms")
    end,
})

def("fps", {
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    minWidth = 44,
    text = function() return fmt("%d fps", floor(GetFramerate() + 0.5)) end,
    tip = function(tt)
        header(tt, L.ITEM_fps)
        line(tt, L.CURRENT, fmt("%d fps", floor(GetFramerate() + 0.5)))
    end,
})

-- Addons: the collected minimap buttons --------------------------------------------

def("addons", {
    icon = "Interface\\Icons\\Trade_Engineering",
    -- the gold chevron of Blizzard's dropdowns
    text = function() return L.ADDONS .. " |A:dropdown-hover-arrow:8:12:0:-1|a" end,
    tip = function(tt)
        header(tt, L.ADDONS)
        tt:AddLine(fmt(L.BUTTONS_COLLECTED, ns.Minimap:CollectedCount()), 0.62, 0.62, 0.62)
        hint(tt, L.CLICK_ADDONS)
    end,
    click = function(cell) ns.Minimap:ShowMenu(cell) end,
})

-- Blizzard's clock at the minimap ---------------------------------------------------

function E:ApplyMinimapClock()
    local clock = _G.TimeManagerClockButton
    if not clock or not ns.db then return end
    if not self.clockHooked then
        self.clockHooked = true
        hooksecurefunc(clock, "Show", function(b) if not opt("minimapClock") then b:Hide() end end)
    end
    -- only shown again if we hid it (Blizzard's own setting may hide it too)
    if not opt("minimapClock") then
        clock:Hide()
        self.clockHidden = true
    elseif self.clockHidden then
        self.clockHidden = false
        clock:Show()
    end
end

-- Cells ---------------------------------------------------------------------------

local function showTip(cell)
    local d = E.defs[cell.key]
    if E.dragging or not d.tip then return end
    GameTooltip:SetOwner(cell, ns.TipPoint())
    d.tip(GameTooltip)
    GameTooltip:AddLine(L.DRAG_HINT, 0.5, 0.5, 0.5)
    GameTooltip:AddLine(L.RIGHT_CLICK_MENU, 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function hover(c, on)
    tween(c.hl, c.hlAlpha or 0, on and 0.12 or 0, 0.15, function(v) c.hlAlpha = v; c.hl:SetAlpha(v) end)
    tween(c.icon, c.iconScale or 1, on and 1.15 or 1, 0.15, function(v)
        c.iconScale = v
        c.icon:SetSize(ICON * v, ICON * v)
        if c.ringSize then c.ring:SetSize(c.ringSize * v, c.ringSize * v) end
    end)
end

E.ShowTip = showTip

-- a cell that asks for attention (new mail): pulsing glow, steady glow with fewer animations
local function pulse(c, on)
    if not c.pulseGlow then
        c.pulseGlow = c:CreateTexture(nil, "BACKGROUND", nil, 2)
        c.pulseGlow:SetPoint("TOPLEFT", 0, -3)
        c.pulseGlow:SetPoint("BOTTOMRIGHT", 0, 3)
        c.pulseGlow:SetColorTexture(1, 0.82, 0.3, 1)
        c.pulseGlow:SetBlendMode("ADD")
        c.pulseGlow:SetAlpha(0)
    end
    if not on then
        c:SetScript("OnUpdate", nil)
        c.pulseGlow:SetAlpha(0)
        c.pulsing = false
        return
    end
    if c.pulsing then return end
    c.pulsing = true
    if ns.Motion() ~= "full" then
        c.pulseGlow:SetAlpha(0.35)
        return
    end
    local t = 0
    c:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        local wave = 0.5 - 0.5 * math.cos(2 * math.pi * t / 1.6)
        self.pulseGlow:SetAlpha(0.1 + 0.5 * wave)
    end)
end

local function flash(c)
    tween(c.glow, 0.35, 0, 0.9, function(v) c.glow:SetAlpha(v) end)
end

-- Hearthstone: using an item needs a secure button. It is not a child of the panel (that would lock the panel's
-- movement in combat); it lies on top of the cell, follows it out of combat and is hidden in combat.
function E:CreateHearthButton()
    local ok, b = pcall(CreateFrame, "Button", "ForeverQoLPanelHearthButton", UIParent, "SecureActionButtonTemplate")
    if not ok or not b then return end
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(40)
    -- modern clients cast on key down by default (CVar ActionButtonUseKeyDown): secure buttons need down and up
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:RegisterForDrag("LeftButton")
    b:SetAttribute("type1", "macro")
    b:SetAttribute("macrotext1", "/use item:" .. HEARTHSTONE)
    local cell = self.cells.hearth
    b:SetScript("OnEnter", function() showTip(cell); hover(cell, true) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide(); hover(cell, false) end)
    b:SetScript("PostClick", function(_, button, down)
        if down then return end
        GameTooltip:Hide()
        if button == "RightButton" then E:ShowMenu(cell) end
    end)
    b:SetScript("OnDragStart", function() E:StartDrag(cell) end)
    b:SetScript("OnDragStop", function() E:StopDrag() end)
    b:Hide()
    self.hearthButton = b
    ns.On("PLAYER_REGEN_DISABLED", function() b:Hide() end)
    ns.On("PLAYER_REGEN_ENABLED", function() E:PlaceHearthButton() end)
end

-- debug data: where the secure button is and what it does
function E:DescribeHearth()
    local b = self.hearthButton
    if not b then ns.Debug.Set("hearth", "no secure button") return end
    ns.Debug.Set("hearth", { shown = b:IsShown(), left = b:GetLeft(), top = b:GetTop(), w = b:GetWidth(), h = b:GetHeight(),
        type = b:GetAttribute("type1"), macro = b:GetAttribute("macrotext1"), level = b:GetFrameLevel(),
        count = ns.ItemCount(6948) })
end

function E:PlaceHearthButton()
    local b, cell = self.hearthButton, self.cells.hearth
    if not b or InCombatLockdown() then return end
    local l, t = cell:GetLeft(), cell:GetTop()
    if not cell:IsVisible() or not l or not ns.db.panel.items.hearth or (ns.Dock.band and ns.Dock.band:GetAlpha() < 0.5) then
        b:Hide()
        return
    end
    local s = cell:GetEffectiveScale() / UIParent:GetEffectiveScale()
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * s, t * s)
    b:SetSize(cell:GetWidth() * s, cell:GetHeight() * s)
    b:Show()
end

function E:Build(parent)
    self.band = parent
    realm, faction, me = GetRealmName(), UnitFactionGroup("player") or "Neutral", UnitName("player")
    store()
    E.ApplyFont()
    ns.On("PLAYER_MONEY", function() store(); E:UpdateTexts(); ns.Dock:Relayout() end)

    -- right-click on the empty parts of the panel
    parent:EnableMouse(true)
    parent:SetScript("OnMouseUp", function(f, button) if button == "RightButton" then E:ShowMenu(f) end end)

    for key, d in pairs(self.defs) do
        local c = CreateFrame("Button", nil, parent)
        c.key = key
        c:SetHeight(BH)
        c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        c:RegisterForDrag("LeftButton")
        c.hl = c:CreateTexture(nil, "BACKGROUND")
        c.hl:SetAllPoints()
        c.hl:SetColorTexture(1, 0.82, 0.47, 1)
        c.hl:SetAlpha(0)
        c.glow = c:CreateTexture(nil, "BACKGROUND", nil, 1)
        c.glow:SetPoint("TOPLEFT", 0, -3)
        c.glow:SetPoint("BOTTOMRIGHT", 0, 3)
        c.glow:SetColorTexture(1, 0.85, 0.4, 1)
        c.glow:SetBlendMode("ADD")
        c.glow:SetAlpha(0)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(ICON, ICON)
        c.ring = c:CreateTexture(nil, "OVERLAY")
        -- the text sits in a clipping frame: a text longer than its room is cut off and fades out, never wraps
        c.clip = CreateFrame("Frame", nil, c)
        c.clip:SetClipsChildren(true)
        -- clipping applies to child frames, so the text lives on a frame inside the clipping one
        local holder = CreateFrame("Frame", nil, c.clip)
        holder:SetAllPoints(c.clip)
        c.text = holder:CreateFontString(nil, "ARTWORK")
        c.text:SetFontObject(font)
        c.text:SetJustifyH("LEFT")
        c.text:SetWordWrap(false)
        if c.text.SetNonSpaceWrap then c.text:SetNonSpaceWrap(false) end
        -- separator to the left of the cell
        c.sepTop = parent:CreateTexture(nil, "ARTWORK")
        c.sepBot = parent:CreateTexture(nil, "ARTWORK")
        c.dot = parent:CreateTexture(nil, "ARTWORK")
        for _, t in ipairs({ c.sepTop, c.sepBot, c.dot }) do t:SetColorTexture(1, 1, 1, 1) end
        c.sepTop:SetGradient("VERTICAL", CreateColor(0.77, 0.63, 0.43, 0.6), CreateColor(0.77, 0.63, 0.43, 0))
        c.sepBot:SetGradient("VERTICAL", CreateColor(0.77, 0.63, 0.43, 0), CreateColor(0.77, 0.63, 0.43, 0.6))
        c.dot:SetVertexColor(0.64, 0.51, 0.35, 1)
        c.dot:SetSize(4, 4)
        c.dot:SetRotation(math.rad(45))

        c:SetScript("OnEnter", function(self) showTip(self); hover(self, true) end)
        c:SetScript("OnLeave", function(self) GameTooltip:Hide(); hover(self, false) end)
        c:SetScript("OnClick", function(self, button)
            GameTooltip:Hide()
            if button == "RightButton" then E:ShowMenu(self)
            elseif d.click then d.click(self) end
        end)
        c:SetScript("OnDragStart", function() E:StartDrag(c) end)
        c:SetScript("OnDragStop", function() E:StopDrag() end)
        self.cells[key] = c
    end
    self:ApplyIcons()
    self:CreateHearthButton()

    -- the pin keeps the panel open
    local pin = CreateFrame("Button", nil, parent)
    pin:SetSize(PIN, BH)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin.tex = pin:CreateTexture(nil, "ARTWORK")
    pin.tex:SetSize(16, 16)
    pin.tex:SetPoint("CENTER")
    pin.tex:SetAtlas("friendslist-recentallies-pin-yellow")
    pin:SetScript("OnClick", function(b, button)
        if button == "RightButton" then E:ShowMenu(b) return end
        ns.db.panel.pinned = not ns.db.panel.pinned
        E:UpdatePin(true)
    end)
    pin:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, ns.TipPoint())
        GameTooltip:AddLine(ns.db.panel.pinned and L.PINNED or L.PIN_PANEL, 1, 1, 1)
        GameTooltip:AddLine(L.PIN_HINT, 0.62, 0.62, 0.62)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.pin = pin
    self:UpdatePin()

    self.marker = parent:CreateTexture(nil, "OVERLAY")
    self.marker:SetColorTexture(1, 0.82, 0, 1)
    self.marker:SetSize(2, BH - 8)
    self.marker:Hide()

    for _, ev in ipairs({ "UPDATE_PENDING_MAIL", "MAIL_INBOX_UPDATE", "MAIL_CLOSED" }) do
        ns.On(ev, function() E:UpdateTexts(); ns.Dock:Relayout() end)
    end
    for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
        "PLAYER_XP_UPDATE", "CURRENCY_DISPLAY_UPDATE", "UNIT_INVENTORY_CHANGED", "PLAYER_FLAGS_CHANGED", "UNIT_FACTION" }) do
        ns.On(ev, function() E:UpdateTexts(); ns.Dock:Relayout() end)
    end
    ns.On("ZONE_CHANGED_NEW_AREA", function() E:ResetWidths(); E:UpdateTexts(); ns.Dock:Relayout() end)
    self:ApplyMinimapClock()
end

-- Icon borders: round (masked icon + thin ring), square (Blizzard's action button frame) or none.
function E:ApplyIcons()
    local style = ns.db.panel.iconBorder
    for key, c in pairs(self.cells) do
        local d = self.defs[key]
        local ok, icon = pcall(function() return type(d.icon) == "function" and d.icon() or d.icon end)
        c.icon:SetTexture(ok and icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        if c.masked then c.icon:RemoveMaskTexture(c.mask); c.masked = false end
        c.ring:Hide()
        c.ringSize = nil
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if style == "round" then
            if not c.mask then
                c.mask = c:CreateMaskTexture()
                c.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                c.mask:SetAllPoints(c.icon)
            end
            c.icon:AddMaskTexture(c.mask)
            c.masked = true
            if ns.SetAtlas(c.ring, "ring", { "voicechat-portrait-ring", "worldquest-tracker-ring" }) then c.ringSize = ICON + 5 end
        elseif style == "square" then
            if ns.SetAtlas(c.ring, "frame", { "ui-hud-actionbar-iconframe", "ui-hud-actionbar-iconframe-c60" }) then
                c.ringSize = ICON + 4
            end
        end
        if c.ringSize then
            c.ring:ClearAllPoints()
            c.ring:SetPoint("CENTER", c.icon, "CENTER")
            c.ring:SetSize(c.ringSize * (c.iconScale or 1), c.ringSize * (c.iconScale or 1))
            c.ring:Show()
        end
    end
end

function E:UpdatePin(animate)
    local pinned = ns.db.panel.pinned
    local tex = self.pin.tex
    tex:SetDesaturated(not pinned)
    tex:SetAlpha(pinned and 1 or 0.5)
    -- loose pin tilted, pinned upright
    local to = pinned and 0 or math.rad(-30)
    if animate then
        tween(tex, self.pinAngle or to, to, 0.25, function(v) self.pinAngle = v; tex:SetRotation(v) end)
    else
        self.pinAngle = to
        tex:SetRotation(to)
    end
end

-- Text width without the jitter of changing digits: digits are measured as "0" (outside texture escapes).
local measure
local function steadyWidth(text)
    if not measure then
        measure = E.band:CreateFontString(nil, "ARTWORK")
        measure:SetFontObject(font)
        measure:Hide()
    end
    local kept = {}
    local s = text:gsub("|T.-|t", function(t) kept[#kept + 1] = t; return "\1" .. string.char(64 + #kept) .. "\2" end)
    s = s:gsub("%d", "0"):gsub("\1(.)\2", function(ch) return kept[ch:byte() - 64] end)
    measure:SetText(s)
    return measure:GetStringWidth() or 0
end

function E:ResetWidths()
    for _, c in pairs(self.cells) do c.steady = nil end
end

-- A cell's width follows its text both ways, gliding to the new width (the panel follows along); a growing text
-- fades in as its room opens. Digits count as "0", so ticking numbers never change a width.
local WIDTH_STEP, WIDTH_TIME = 4, 0.35
local function glideWidth(c, text)
    local target = math.ceil(steadyWidth(text) / WIDTH_STEP) * WIDTH_STEP
    if c.steady == nil then c.steady, c.target = target, target return end
    if target == c.target then return end
    c.target = target
    local from = c.steady
    c.widthId = c.widthId or {}
    tween(c.widthId, from, target, WIDTH_TIME, function(v)
        c.steady = v
        if ns.Dock then ns.Dock:Relayout() end
    end)
end

-- Test from the options: the zone element (or the first shown one) switches between a long and a short text.
function E:TestWidths()
    local key = self:Shown("zone") and "zone" or nil
    if not key then
        for _, k in ipairs(ns.db.panel.order) do if self:Shown(k) then key = k break end end
    end
    if not key then return end
    self.testText = self.testText or {}
    local steps = { L.TEST_WIDTH_LONG, L.TEST_WIDTH_SHORT, L.TEST_WIDTH_LONG, false }
    for i, text in ipairs(steps) do
        C_Timer.After((i - 1) * 1.4, function()
            self.testText[key] = text or nil
            self:UpdateTexts()
            ns.Dock:Relayout()
        end)
    end
end

-- shown: switched on, and for class-bound elements (ammo, soul shards) the right class
function E:Available(key)
    local d = self.defs[key]
    if not d then return false end
    if d.class then
        local _, class = UnitClass("player")
        if class ~= d.class then return false end
    end
    return true
end

function E:Shown(key)
    return ns.db.panel.items[key] and self:Available(key) or false
end

function E:UpdateTexts()
    for key, c in pairs(self.cells) do
        local d = self.defs[key]
        if self:Shown(key) then
            local ok, text = pcall(d.text)
            text = ok and text or "?"
            if self.testText and self.testText[key] then text = self.testText[key] end
            if c.last and c.last ~= text and d.flash then flash(c) end
            c.last = text
            c.text:SetText(text)
            if d.pulse then
                local okP, on = pcall(d.pulse)
                pulse(c, okP and on)
            end
            glideWidth(c, text)
        end
        if GameTooltip:IsOwned(c) then showTip(c) end
    end
end

-- A text in its clipping frame: centred or left-aligned when it fits; otherwise left-aligned, cut off by the frame
-- and fading out over its last visible letters.
local function visibleLength(text)
    local plain = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "#"):gsub("|A.-|a", "#")
    return #plain:gsub("[\128-\191]", "")
end

function E.FitText(fs, room, center)
    fs:ClearAllPoints()
    local full = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    local fits = full <= room + 1
    if fits and center then
        fs:SetPoint("CENTER", fs:GetParent(), "CENTER", 0, 0)
    else
        fs:SetPoint("LEFT", fs:GetParent(), "LEFT", 0, 0)
    end
    if not fs.SetAlphaGradient then return end
    local n = visibleLength(fs:GetText())
    if fits or full <= 0 then
        fs:SetAlphaGradient(n + 10, 1)   -- past the end: no fade
    else
        local shown = math.floor(n * room / full)
        fs:SetAlphaGradient(math.max(0, shown - 3), 3)
    end
end

-- Places the visible cells left to right and returns the panel width (whole units, so the border stays seamless).
function E:Layout()
    local p = ns.db.panel
    local pad, x, first = p.pad, side(), true
    for _, key in ipairs(p.order) do
        local c, d = self.cells[key], self.defs[key]
        if c and self:Shown(key) then
            local tw = ceil(math.max(c.steady or c.text:GetStringWidth(), d.minWidth or 0))
            local w = pad * 2 + ICON + GAP + tw
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", self.band, "TOPLEFT", x, 0)
            c:SetWidth(w)
            c.icon:ClearAllPoints()
            c.icon:SetPoint("CENTER", c, "LEFT", pad + ICON / 2, 0)
            c.clip:ClearAllPoints()
            c.clip:SetPoint("LEFT", c, "LEFT", pad + ICON + GAP, 0)
            c.clip:SetSize(tw + 1, BH)
            E.FitText(c.text, tw, d.center)
            c:Show()
            c.x = x
            self:PlaceSeparator(c, x, first)
            first = false
            x = x + w
        elseif c then
            c:Hide()
            c.sepTop:Hide(); c.sepBot:Hide(); c.dot:Hide()
        end
    end
    self.pin:ClearAllPoints()
    self.pin:SetPoint("TOPLEFT", self.band, "TOPLEFT", x + 4, 0)
    return x + 4 + PIN + side()
end

function E:PlaceSeparator(c, x, first)
    local style = ns.db.panel.separator
    c.sepTop:Hide(); c.sepBot:Hide(); c.dot:Hide()
    if first or style == "none" then return end
    if style == "dot" then
        c.dot:ClearAllPoints()
        c.dot:SetPoint("CENTER", self.band, "TOPLEFT", x, -BH / 2)
        c.dot:Show()
    else
        local h = (BH - 12) / 2
        c.sepTop:ClearAllPoints(); c.sepTop:SetPoint("TOPLEFT", self.band, "TOPLEFT", x, -6); c.sepTop:SetSize(1, h)
        c.sepBot:ClearAllPoints(); c.sepBot:SetPoint("TOPLEFT", self.band, "TOPLEFT", x, -6 - h); c.sepBot:SetSize(1, h)
        c.sepTop:Show(); c.sepBot:Show()
    end
end

-- Elements by theme, for the options and the right-click menu. Elements not listed land in the last group.
E.GROUPS = {
    { "EL_GROUP_MONEY", { "gold", "session", "bags", "materials", "ammo", "shards" } },
    { "EL_GROUP_PROGRESS", { "xph", "durability", "honor", "pvp", "favor" } },
    { "EL_GROUP_WORLD", { "hearth", "zone", "coords", "clock", "stopwatch" } },
    { "EL_GROUP_SYSTEM", { "mail", "latency", "fps", "addons" } },
}

-- { { title, { keys available to this character } }, ... }
function E:Grouped()
    local placed, out = {}, {}
    for _, g in ipairs(self.GROUPS) do
        local keys = {}
        for _, key in ipairs(g[2]) do
            placed[key] = true
            if self:Available(key) then keys[#keys + 1] = key end
        end
        out[#out + 1] = { L[g[1]], keys }
    end
    local last = out[#out][2]
    for _, key in ipairs(ns.defaults.panel.order) do
        if not placed[key] and self:Available(key) then last[#last + 1] = key end
    end
    return out
end

-- Right-click menu: which elements are shown, pin, options ---------------------------

function E:ShowMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local p = ns.db.panel
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.title)
        -- elements by theme, each theme a submenu
        for _, g in ipairs(self:Grouped()) do
            if #g[2] > 0 then
                local sub = root:CreateButton(g[1])
                for _, key in ipairs(g[2]) do
                    sub:CreateCheckbox(L["ITEM_" .. key], function() return p.items[key] end, function()
                        p.items[key] = not p.items[key]
                        E:UpdateTexts()
                        ns.Refresh()
                    end)
                end
            end
        end
        root:CreateDivider()
        if p.xpbar then
            local sub = root:CreateButton(L.OPT_QSTYLE)
            for _, st in ipairs({ { "veil", L.QSTYLE_VEIL }, { "frame", L.QSTYLE_FRAME }, { "line", L.QSTYLE_LINE },
                { "glow", L.QSTYLE_GLOW }, { "shimmer", L.QSTYLE_SHIMMER }, { "stripes", L.QSTYLE_STRIPES } }) do
                sub:CreateRadio(st[2], function() return p.questStyle == st[1] end, function()
                    p.questStyle = st[1]
                    ns.XP:Update()
                end)
            end
        end
        root:CreateCheckbox(L.PIN_PANEL, function() return p.pinned end, function()
            p.pinned = not p.pinned
            ns.Refresh()
        end)
        root:CreateButton(L.OPTIONS .. "...", function() ns.Options:Open() end)
    end)
end

-- Drag & drop ---------------------------------------------------------------------

local function cursorX(frame)
    local x = GetCursorPosition()
    return x / frame:GetEffectiveScale()
end

function E:StartDrag(c)
    self.dragging = c.key
    GameTooltip:Hide()
    c:SetAlpha(0.35)
    self.marker:Show()
    self.band:SetScript("OnUpdate", function() E:DragUpdate() end)
end

function E:DragUpdate()
    local x = cursorX(self.band)
    local before
    for _, key in ipairs(ns.db.panel.order) do
        local c = self.cells[key]
        if key ~= self.dragging and c and c:IsShown() then
            local l, w = c:GetLeft(), c:GetWidth()
            if l and x < l + w / 2 then before = key break end
        end
    end
    self.dropBefore = before
    local mx
    if before then mx = self.cells[before].x
    else
        mx = side()
        for _, key in ipairs(ns.db.panel.order) do
            local c = self.cells[key]
            if key ~= self.dragging and c and c:IsShown() then mx = c.x + c:GetWidth() end
        end
    end
    self.marker:ClearAllPoints()
    self.marker:SetPoint("CENTER", self.band, "TOPLEFT", mx, -BH / 2)
end

function E:StopDrag()
    local key = self.dragging
    if not key then return end
    self.band:SetScript("OnUpdate", nil)
    self.marker:Hide()
    self.cells[key]:SetAlpha(1)
    local order = ns.db.panel.order
    for i, k in ipairs(order) do if k == key then table.remove(order, i) break end end
    local at = #order + 1
    if self.dropBefore then
        for i, k in ipairs(order) do if k == self.dropBefore then at = i break end end
    end
    table.insert(order, at, key)
    self.dragging, self.dropBefore = nil, nil
    ns.Dock.width = nil
    ns.Dock:Relayout()
end

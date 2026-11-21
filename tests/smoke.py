"""Loads the addon against a mocked WoW API (tests/smoke.lua), logs in, runs timers and slash commands.

    python tests/smoke.py
"""
import pathlib
import re
import sys

from lupa import luajit21 as lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "ForeverQoLPanel"


def check_locale() -> bool:
    """Every text has all six languages, every key the code uses exists."""
    src = (ADDON / "Locale.lua").read_text(encoding="utf-8")
    keys, ok = set(), True
    for m in re.finditer(r"^\s+([A-Za-z_]+) = \{ (.*) \},\s*$", src, re.M):
        keys.add(m.group(1))
        n = len(re.findall(r'"(?:[^"\\]|\\.)*"', m.group(2)))
        if n != 6:
            print(f"Locale.lua: {m.group(1)} has {n} languages")
            ok = False
    used = set()
    for f in ADDON.glob("*.lua"):
        code = f.read_text(encoding="utf-8")
        used |= set(re.findall(r"\bL(?:\(\))?\.([A-Z][A-Za-z_]+)", code))
    for key in sorted(used - keys):
        print(f"Locale.lua: missing {key}")
        ok = False
    return ok


def main() -> int:
    if not check_locale():
        return 1
    toc =(ADDON / "ForeverQoLPanel.toc").read_text(encoding="utf-8")
    files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
    for f in files:
        code = (ADDON / f).read_text(encoding="utf-8")
        if re.search(r"\bgoto\b|::\w+::", code):
            print(f"{f}: goto/labels are not Lua 5.1")
            return 1
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / "tests" / "smoke.lua").read_text(encoding="utf-8"))
    ns = lua.table()
    for f in files:
        chunk = lua.eval("function(s, n) local f, e = loadstring(s, n); if not f then error(e) end; return f end")(
            (ADDON / f).read_text(encoding="utf-8"), "@" + f)
        chunk("ForeverQoLPanel", ns)
    lua.globals().ns = ns
    lua.execute("""
        MOCK_fire("ADDON_LOADED", "ForeverQoLPanel")
        MOCK_fire("PLAYER_LOGIN")
        MOCK_runTimers()
        MOCK_fire("PLAYER_XP_UPDATE"); MOCK_fire("PLAYER_MONEY"); MOCK_fire("QUEST_LOG_UPDATE")
        MOCK_runTimers()
        for _, cmd in ipairs({ "pin", "style rail", "gap 20", "rim silver", "sep dot", "border square", "pad 14", "width 400",
                               "ticks 25", "ticks 5", "ticks 0", "toggle fps", "toggle addons", "toggle honor", "toggle favor",
                               "toggle ammo", "toggle materials", "border none", "style edge", "help", "rim dark", "sep none" }) do
            SlashCmdList.FOREVERQOLPANEL(cmd)
        end
        -- menus, options, language, features off and on
        for _, st in ipairs({ "glow", "line", "stripes", "shimmer", "frame", "veil" }) do ForeverQoLPanelDB.panel.questStyle = st; ns.XP:Update() end
        ForeverQoLPanelDB.panel.readyPulse = true; ns.XP:Update()
        ns.Elements:ShowMenu(UIParent)
        ns.Minimap:ShowMenu(UIParent)
        ns.Options:Open()
        -- characters filed under an empty realm (realm not known yet right after loading) go to their real realm
do
    local real = GetRealmName()
    local g = ForeverQoLPanelDB.gold
    g[real] = g[real] or {}; g[real].Alliance = g[real].Alliance or {}
    g[real].Alliance.Alt = { money = 5, level = 11 }
    g[""] = { Alliance = { Alt = { money = 9, level = 12 }, NewOne = { money = 1, level = 3 } } }
    ForeverQoLPanelDB.items[""] = { ["Alliance:Alt"] = { bags = { [1] = 2 }, bank = {} } }
    ns.FixEmptyRealm()
    -- the known one goes to its realm, the one known nowhere else waits under the empty realm
    assert(g[real].Alliance.Alt.money == 9 and g[""].Alliance.NewOne and not g[""].Alliance.Alt, "empty realm not merged")
    assert(ForeverQoLPanelDB.items[""] == nil and ForeverQoLPanelDB.items[real]["Alliance:Alt"], "empty realm items not merged")
    g[real].Alliance.Alt, g[""] = nil, nil
    ForeverQoLPanelDB.items[real]["Alliance:Alt"] = nil
    -- Forever answering "" all the time: the realm where this character is known
    local realGRN, realNorm = GetRealmName, GetNormalizedRealmName
    GetRealmName = function() return "" end
    GetNormalizedRealmName = nil
    ns.lastRealm = nil
    local me = UnitName("player")
    g["Some Realm 6 PvP"] = { [UnitFactionGroup("player")] = { [me] = { money = 1 } } }
    local saved = g[real]; g[real] = nil
    assert(ns.Realm() == "Some Realm 6 PvP", "realm from the known character: " .. tostring(ns.Realm()))
    g[real] = saved; g["Some Realm 6 PvP"] = nil
    GetRealmName, GetNormalizedRealmName = realGRN, realNorm
    ns.lastRealm = nil
end
-- panel elements: tracking (the client's tracking list) and WIM (only with WIM 3, through its data broker object)
do
    local E = ns.Elements
    local tracked = { false, true }
    C_Minimap = C_Minimap or {}
    local realCM = { C_Minimap.GetNumTrackingTypes, C_Minimap.GetTrackingInfo, C_Minimap.SetTracking }
    C_Minimap.GetNumTrackingTypes = function() return 2 end
    C_Minimap.GetTrackingInfo = function(i) return ({ "Kräutersuche", "Mineraliensuche" })[i], 136025, tracked[i] end
    C_Minimap.SetTracking = function(i, on) tracked[i] = on end
    assert(E:Available("tracking"), "tracking element not available")
    assert(E.defs.tracking.text() == "Mineralien", "tracking text: " .. E.defs.tracking.text())
    ForeverQoLPanelDB.panel.opt.trackingIconOnly = true
    assert(E.defs.tracking.text() == "" and E.defs.tracking.minWidth() == 0, "tracking icon only")
    ForeverQoLPanelDB.panel.opt.trackingIconOnly = false
    C_Minimap.GetNumTrackingTypes, C_Minimap.GetTrackingInfo, C_Minimap.SetTracking = realCM[1], realCM[2], realCM[3]
    assert(not E:Available("wim"), "WIM element without WIM")
    local clicked
    local obj = { OnClick = function(_, button) clicked = button end, OnTooltipShow = function(tt) tt:AddLine("WIM") end }
    local realLS = LibStub
    LibStub = function() return { GetDataObjectByName = function(_, name) return name == "WIM" and obj or nil end } end
    WIM = { Notifications = { { tag = "Mario", text = "2", color = "ffffff" } } }
    assert(E:Available("wim") and E.defs.wim.text():find("1"), "WIM element: " .. tostring(E.defs.wim.text()))
    assert(E.defs.wim.pulse(), "WIM element does not ask for attention")
    WIM.Notifications = {}
    ForeverQoLPanelDB.panel.opt.wimHideEmpty = true
    assert(E.defs.wim.text() == "" and E.defs.wim.minWidth() == 0, "WIM text without news")
    ForeverQoLPanelDB.panel.opt.wimHideEmpty = false
    WIM.Notifications = { { tag = "Mario", text = "2", color = "ffffff" } }
    E.defs.wim.click(UIParent, "LeftButton")
    assert(clicked == "LeftButton", "WIM menu not opened")
    -- WIM's own minimap button goes while the element is shown
    WIM3MinimapButton = CreateFrame("Button", "WIM3MinimapButton", Minimap)
    ForeverQoLPanelDB.panel.items.wim = true; ns.Refresh()
    assert(not WIM3MinimapButton:IsShown(), "WIM minimap button still shown")
    WIM3MinimapButton:Show(); assert(not WIM3MinimapButton:IsShown(), "WIM shows its button again")
    ForeverQoLPanelDB.panel.items.wim = false; ns.Refresh()
    assert(WIM3MinimapButton:IsShown(), "WIM minimap button not back")
    WIM, LibStub = nil, realLS
end
-- XP and reputation bar share a page with a tab each; the second tab shows the reputation settings
do
    local idx
    for i, p in ipairs(ns.Options.PAGES) do if p.title == "SEC_BARS" then idx = i end end
    assert(idx and #ns.Options.PAGES[idx].tabs == 2, "bars page with tabs")
    ns.Options.tabOf = { [idx] = 2 }
    ns.Options:Show(idx)
    local tabs = ns.Options.frame.body.tabs
    assert(tabs[2]:IsShown() and tabs[2].glow:IsShown() and not tabs[1].glow:IsShown(), "reputation tab not chosen")
    -- long pages are split into tabs at their section headers
    for _, title in ipairs({ "SEC_ELEMENTS", "SEC_WARNINGS", "SEC_LOOTOPT" }) do
        local i2
        for i, p in ipairs(ns.Options.PAGES) do if p.title == title then i2 = i end end
        ns.Options.tabOf = { [i2] = 2 }
        ns.Options:Show(i2)
        assert(tabs[2]:IsShown() and tabs[2].glow:IsShown(), "header tabs on " .. title)
    end
    ns.Options.tabOf = nil
end
for i = 1, #ns.Options.PAGES do
            ns.Options:Show(i)
            local pool = ns.Options.frame.pool.check
            if pool and pool[1] then pool[1].box.scripts.OnClick(pool[1].box); pool[1].box.scripts.OnClick(pool[1].box) end
            -- dropdowns: run the menu generator and pick the first value
            local choices = ns.Options.frame.pool.choice
            if choices and choices[1] and choices[1].dropdown and choices[1].dropdown.gen then
                local root = { CreateRadio = function(_, _, isSel, set) isSel(); MOCK_pick = MOCK_pick or set end }
                MOCK_pick = nil
                choices[1].dropdown.gen(choices[1].dropdown, root)
                if MOCK_pick then MOCK_pick() end
            end
        end
        assert(ns.Options.category, "settings stub missing")
        -- language switch while the window is open: footer and wizard buttons follow
        ns.SetLanguage("enUS"); ns.Options:Render(); ns.Wizard:Open(true); ns.Wizard:Finish()
        assert(ns.L.CLOSE_BTN == "Close", "language switch")
        ns.SetLanguage("auto"); ns.Options:Render()
        -- search across all pages
        ns.Options.query = "graue"; ns.Options:Render()
        assert(ns.Options.frame.pool.check and ns.Options.frame.pool.check.n >= 1, "search found nothing")
        ns.Options.query = "zzzz"; ns.Options:Render()
        ns.Options.query = "warnungen"; ns.Options:Render()
        ns.Options.query = ""; ns.Options:Render()
        local of = ns.Options.frame
        of:SetSize(1200, 800); of.scripts.OnSizeChanged(of); MOCK_runTimers()
        assert(of.contentWidth > 800, "options did not follow the size")
        of.grip.scripts.OnMouseUp(); assert(ForeverQoLPanelDB.windows.ForeverQoLPanelOptions.w == 1200, "size not saved")
        ForeverQoLPanelDB.panel.opt.xphTime = true; ForeverQoLPanelDB.panel.opt.zoneCoords = true
        ForeverQoLPanelDB.panel.opt.minimapClock = false; ForeverQoLPanelDB.panel.opt.serverTime = true
        ForeverQoLPanelDB.panel.xpbar = false; ns.Refresh()
        ForeverQoLPanelDB.panel.xpbar = true; ForeverQoLPanelDB.panel.hideBlizzardXP = false; ns.Refresh()
        ForeverQoLPanelDB.panel.collectButtons = false; ns.Refresh()
        ns.SetLanguage("deDE"); ns.Elements:UpdateTexts()
        assert(ns.L.ITEM_favor == "Händlergunst")
        ns.SetLanguage("auto")
        MOCK_fire("PLAYER_XP_UPDATE"); MOCK_fire("ZONE_CHANGED_NEW_AREA"); MOCK_fire("CURRENCY_DISPLAY_UPDATE")
        -- action bars: a new rank replaces the old one, a new spell takes the first free slot
        MOCK_book = { 101, 102, 201 }
        MOCK_fire("SPELLS_CHANGED"); MOCK_runTimers()
        assert(MOCK_actions[1] == 102, "rank not replaced")
        assert(MOCK_actions[2] == 201, "new spell not placed")
        SlashCmdList.FOREVERQOLPANEL("position bottom"); SlashCmdList.FOREVERQOLPANEL("pin"); SlashCmdList.FOREVERQOLPANEL("position top")
        ns.Elements.defs.stopwatch.click(); ns.Elements.defs.stopwatch.text(); ns.Elements.defs.stopwatch.click()
        ForeverQoLPanelDB.panel.enabled = false; ns.Minimap:Update(); assert(ForeverQoLPanelCollector:IsShown())
        ForeverQoLPanelDB.panel.enabled = true; ns.Minimap:Update()
        -- modern skin, square and round, top and bottom; manual action bar runs
        ForeverQoLPanelDB.panel.skin = "modern"; ns.Refresh()
        ForeverQoLPanelDB.panel.corners = "round"; ns.Refresh()
        SlashCmdList.FOREVERQOLPANEL("position bottom"); SlashCmdList.FOREVERQOLPANEL("style rail")
        ForeverQoLPanelDB.panel.xpbar = false; ns.Refresh(); ForeverQoLPanelDB.panel.xpbar = true
        ForeverQoLPanelDB.panel.skin = "classic"; SlashCmdList.FOREVERQOLPANEL("position top")
        SlashCmdList.FOREVERQOLPANEL("ranks"); SlashCmdList.FOREVERQOLPANEL("place")
        MOCK_fire("PLAYER_ENTERING_WORLD", true, false)
        -- gameplay, nameplates, warnings, tooltips, wizard
        MerchantFrame._shown = false   -- Blizzard shows its frame after the event
        MOCK_fire("MERCHANT_SHOW"); MOCK_runTimers()
        assert(MOCK_used == 1, "grey item not sold"); assert(MOCK_repaired, "not repaired")
        GetNumQuestChoices = function() return 2 end; GetQuestItemLink = function() return "item:1" end
        GetQuestItemInfo = function() return "x", 1, 1 end; QuestInfoRewardsFrameQuestInfoItem1 = obj("Button")
        MOCK_fire("QUEST_COMPLETE"); MOCK_fire("LOOT_READY")
        ns.Gameplay:MarkRewards()
        local mk = ns.Gameplay.marks and ns.Gameplay.marks[QuestInfoRewardsFrameQuestInfoItem1]
        assert(mk and mk.coin:IsShown(), "no coin on the most valuable reward")
        MOCK_fire("CHAT_MSG_LOOT", "You receive loot: |Hitem:2589|h[Linen]|hx2.")
        MOCK_fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        assert(ns.Nameplates.marks[MOCK_plate]:IsShown(), "no quest marker")
        -- group tooltip: my objectives under "First Last" (Forever names), someone else's done
        local realGet, realName = C_TooltipInfo.GetUnit, UnitName
        UnitName = function() return "Aerilyn", "Sturmwind" end
        C_TooltipInfo.GetUnit = function() return { lines = { { type = 17, leftText = "A quest" },
            { type = 18, leftText = "Bob" }, { type = 8, leftText = "Kobold slain: 8/8" },
            { type = 18, leftText = "Aerilyn Sturmwind" }, { type = 8, leftText = "Kobold slain: 2/8" } } } end
        ns.Nameplates:Update("nameplate1"); assert(ns.Nameplates.marks[MOCK_plate]:IsShown(), "group: my objective missed")
        -- hidden lines: yes/no from the quest log
        local hidden = setmetatable({}, { __index = function() error("secret touched") end })
        MOCK_secret[hidden] = true
        C_TooltipInfo.GetUnit = function() return { lines = { { type = 8, leftText = hidden } } } end
        C_QuestLog.UnitIsRelatedToActiveQuest = function() return true end
        ns.Nameplates:Update("nameplate1"); assert(ns.Nameplates.marks[MOCK_plate]:IsShown(), "secret: no fallback")
        C_TooltipInfo.GetUnit, UnitName = realGet, realName
        local w = ns.Warnings:Check()
        assert(#w >= 2, "warnings missing: " .. #w)
        ns.Warnings:Update()
        -- XP status text, every part, on and below the bar, panel top and bottom
        local P = ForeverQoLPanelDB.panel
        P.xpText, P.xpTextTime, P.xpTextRested = true, true, true
        for _, pos in ipairs({ "on", "below" }) do
            P.xpTextPos = pos; ns.XP:UpdateStatus(); assert(ns.XP.frame.status:IsShown(), "no XP status text")
        end
        P.position = "bottom"; ns.XP:UpdateStatus(); P.position = "top"
        P.xpTextValues, P.xpTextPercent, P.xpTextTime, P.xpTextRested = false, false, false, false
        ns.XP:UpdateStatus(); assert(not ns.XP.frame.status:IsShown(), "empty status text shown")
        P.xpText, P.xpTextValues, P.xpTextPercent = false, true, true; ns.XP:UpdateStatus()
        -- released copy steps aside while the dev copy is on
        C_AddOns = C_AddOns or {}
        C_AddOns.GetAddOnEnableState = function(name) return name == "ForeverQoLPanel_Dev" and 2 or 0 end
        assert(ns.name == "ForeverQoLPanel_Dev" or ns.DevCopyActive(), "released copy does not step aside")
        C_AddOns.GetAddOnEnableState = nil
        -- width test: zone switches long/short and back, widths glide
        ns.Elements:TestWidths(); MOCK_runTimers()
        assert(ns.Elements.testText == nil or next(ns.Elements.testText) == nil, "test text left behind")
        -- hunter: low ammo warns; warlock: shard element; new mail glows
        local realClass = UnitClass
        UnitClass = function() return "Hunter", "HUNTER" end
        -- beast tooltip: Ragged Scavenger (1509) teaches Bite 1; the Beast Training window says Bite 2 is known
        do
            local tt = { lines = {}, scripts = {} }
            function tt:GetUnit() return "Ragged Scavenger", "mouseover" end
            function tt:AddLine(t) table.insert(self.lines, t) end
            function tt:Show() end
            UnitCreatureFamily = function() return "Wolf" end
            UnitGUID = function() return "Creature-0-1-2-3-1509-0000" end
            UnitAttackSpeed = function() return 1.5 end
            local realExists = UnitExists
            UnitExists = function(u) return u == "pet" end
            ns.Beasts:Unit(tt)
            local text = table.concat(tt.lines, " | ")
            assert(text:find("Begleiter %(Wolf%) kann es lernen"), "pet line: " .. text)
            UnitExists = realExists
            assert(text:find("Spell17253 %(Rang 1%)") and not text:find("Petopia") and text:find("1,5"), "beast tooltip: " .. text)
            GetNumCrafts = function() return 1 end
            GetCraftInfo = function() return "Biss", "Rang 2", "used" end
            GetCraftIcon = function() return "Interface\\\\Icons\\\\Ability_Druid_FerociousBite" end
            ns.Beasts:ReadTraining()
            tt.lines, tt.fqpBeast = {}, nil
            ns.Beasts:Unit(tt)
            text = table.concat(tt.lines, " | ")
            assert(text:find("Biss") and text:find("bekannt"), "beast tooltip after training: " .. text)
            -- Forever: Beast Training as a trainer window; Claw 3 known there, the "used" filter switched off
            GetNumCrafts, GetCraftInfo, GetCraftIcon = nil, nil, nil
            ForeverQoLPanelDB.beasts.known = {}
            local filters = { available = true, unavailable = true, used = false }
            GetTrainerServiceTypeFilter = function(t) return filters[t] end
            SetTrainerServiceTypeFilter = function(t, v) filters[t] = v == 1 end
            GetNumTrainerServices = function() return filters.used and 2 or 1 end
            GetTrainerServiceInfo = function(i) if i == 1 then return "Spell16827", "available", 132140, "Rang 3" end return "Spell17253", "used", 132278 end
            GetTrainerServiceIcon = function() return nil end
            UnitExists = function() return false end
            ns.Beasts:ReadTrainer("TRAINER_SHOW")
            assert(filters.used == false, "trainer filter not restored")
            local k = ForeverQoLPanelDB.beasts.known
            local mine; for _, v in pairs(k) do mine = v end
            assert(mine and mine.claw == 3 and mine.bite == 1, "trainer window not read")
            UnitCreatureFamily, UnitGUID, UnitAttackSpeed = nil, nil, nil
            GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceIcon, GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter = nil, nil, nil, nil, nil
        end
        -- ammo counted from the bags: 2 stacks of arrows (class 6/2) with a bow equipped, a gun's bullets ignored
        local realInfo, realInstant, realID = C_Container.GetContainerItemInfo, C_Item.GetItemInfoInstant, GetInventoryItemID
        C_Container.GetContainerItemInfo = function(bag, slot)
            if bag == 1 and slot <= 2 then return { itemID = 2512, stackCount = 200, hyperlink = "|Hitem:2512|h[Rough Arrow]|h" } end
            if bag == 1 and slot == 3 then return { itemID = 2516, stackCount = 200 } end
        end
        C_Item.GetItemInfoInstant = function(id)
            if id == 2512 then return id, "", "", "", 0, 6, 2 end
            if id == 2516 then return id, "", "", "", 0, 6, 3 end
            if id == 100 then return id, "", "", "", 0, 2, 2 end
        end
        GetInventoryItemID = function(_, slot) return slot == 18 and 100 or nil end
        -- like Forever: the ammo slot cannot be read
        local realLink = GetInventoryItemLink
        GetInventoryItemLink = function(_, slot) if slot ~= 0 then return realLink() end end
        MOCK_fire("BAG_UPDATE_DELAYED")
        local ammoN = ns.Elements.AmmoCount()
        assert(ammoN == 400, "ammo from bags: " .. tostring(ammoN))
        local found2 = false
        ForeverQoLPanelDB.warnings.ammoMin = 900
        for _, w in ipairs(ns.Warnings:Check()) do if w[4] == "ammo" then found2 = w[2] end end
        assert(found2 and not found2:find("Keine"), "warning should give the count, got " .. tostring(found2))
        C_Container.GetContainerItemInfo, C_Item.GetItemInfoInstant, GetInventoryItemID = realInfo, realInstant, realID
        GetInventoryItemLink = realLink
        MOCK_fire("BAG_UPDATE_DELAYED")
        ForeverQoLPanelDB.warnings.ammoMin = 900
        local found = false
        for _, w in ipairs(ns.Warnings:Check()) do if w[4] == "ammo" then found = true end end
        assert(found, "no low-ammo warning for a hunter")
        assert(ns.Elements:Available("ammo") and not ns.Elements:Available("shards"), "class-bound elements")
        ns.Elements.defs.ammo.text()
        UnitClass = function() return "Warlock", "WARLOCK" end
        assert(ns.Elements:Available("shards"), "shards for warlocks")
        ns.Elements.defs.shards.text(); ns.Elements.defs.shards.tip(GameTooltip)
        for _, w in ipairs(ns.Warnings:Check()) do assert(w[4] ~= "ammo", "ammo warning for a warlock") end
        -- loot optimizer: a warrior, chest +10 Str +5 Sta against worn +5 Str
        do
            local LO = ns.LootOpt
            local realItemInfo, realInvLink, realStats, realLevel = ns.ItemInfo, GetInventoryItemLink, GetItemStats, UnitLevel
            UnitClass = function() return "Warrior", "WARRIOR" end
            UnitLevel = function() return 20 end
            ns.ItemInfo = function(link)
                if link == "new" then return "New Chest", "new", 2, 20, 15, "", "", 1, "INVTYPE_CHEST", 1, 100, 4, 3, 2 end
                if link == "old" then return "Old Chest", "old", 1, 10, 5, "", "", 1, "INVTYPE_CHEST", 1, 50, 4, 3, 1 end
                if link == "robe" then return "Robe", "robe", 1, 10, 5, "", "", 1, "INVTYPE_CHEST", 1, 50, 4, 1, 1 end
                if link == "plate" then return "Plate", "plate", 2, 40, 40, "", "", 1, "INVTYPE_CHEST", 1, 50, 4, 4, 1 end
                if type(link) == "string" and link:find("99999") then return nil end
                return realItemInfo(link)
            end
            GetInventoryItemLink = function(_, slot) if slot == 5 then return "old" end end
            GetItemStats = function(link)
                if link == "new" then return { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 5 } end
                if link == "old" then return { ITEM_MOD_STRENGTH_SHORT = 5 } end
                if link == "robe" or link == "plate" then return { ITEM_MOD_STRENGTH_SHORT = 1 } end
                return {}
            end
            local r = LO:Compare("new")
            assert(r and r.slot == 5 and r.pct and r.pct > 100, "loot compare: " .. tostring(r and r.pct))
            assert(LO:Compare("plate") == nil, "plate before level 40")
            assert(LO:Compare("robe"), "cloth for a warrior")
            -- Forever talents (traits): a shaman with 0 / 20 / 0 points is rated as enhancement
            do
                local realClass2, realSI, realT = UnitClass, C_SpecializationInfo, C_Traits
                UnitClass = function() return "Shaman", "SHAMAN" end
                C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return 7 end }
                C_Traits = {
                    GetConfigInfo = function() return { treeIDs = { 99 } } end,
                    GetGroupDisplayInfoByTreeID = function() return { { groupID = 3, displayName = "Wiederherstellung", orderIndex = 2 },
                        { groupID = 1, displayName = "Elementarkampf", orderIndex = 0 }, { groupID = 2, displayName = "Verstärkung", orderIndex = 1 } } end,
                    GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 1, currencyInfos = { { spent = 0 } } },
                        { traitNodeGroupID = 2, currencyInfos = { { spent = 20 } } }, { traitNodeGroupID = 3, currencyInfos = { { spent = 0 } } } } end,
                }
                assert(LO.Profile() == "enhancement", "talent groups: " .. tostring(LO.Profile()))
                assert(LO.ProfileLabel("enhancement") == "Verstärkung", "tree name from the game")
                UnitClass, C_SpecializationInfo, C_Traits = realClass2, realSI, realT
            end
            local line = LO.Export()
            assert(line:find("^FQPW2;WARRIOR;arms;") and line:find("Strength=1"), "export: " .. line)
            assert(LO.Import((line:gsub("Strength=1;", "Strength=2;"))) and LO.Weights().Strength == 2 and LO.Weights().SpellDamage == 0, "import")
            assert(LO.Import("hallo") == nil, "bad import accepted")
            ForeverQoLPanelDB.lootopt.weights = {}; ForeverQoLPanelDB.lootopt.caps = {}
            local lines = {}
            local realGet, realAdd = GameTooltip.GetItem, GameTooltip.AddLine
            GameTooltip.GetItem = function() return "New Chest", "new" end
            GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end; GameTooltip.AddDoubleLine = function(_, t) lines[#lines + 1] = t end
            GameTooltip.IsShown = function() return true end
            LO:Tooltip(GameTooltip); LO.Place(GameTooltip)
            GameTooltip.GetItem, GameTooltip.AddLine = realGet, realAdd
            assert(GameTooltip.fqpLoot and GameTooltip.fqpLoot.text:find("besser") and ForeverQoLPanelLootTip:IsShown(), "loot tooltip")
            LO:ShowUpgrade("new", r)
            assert(LO.up:IsShown(), "upgrade window")
            LO.up:Hide()
            LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
            for _, ev in ipairs({ "LOOT_OPENED" }) do MOCK_fire(ev) end
            LO:BagsFull()
            assert(LO.full and LO.full:IsShown(), "bags full window")
            -- loot whose item data the game has not loaded yet: its real name from the loot window, no false hint
            local realNum, realLink, realInfo = GetNumLootItems, GetLootSlotLink, GetLootSlotInfo
            GetNumLootItems = function() return 1 end
            GetLootSlotLink = function() return "|cff1eff00|Hitem:99999::|h[Neuer Kilt]|h|r" end
            GetLootSlotInfo = function() return 134586, "Neuer Kilt", 1, nil, 2 end
            LO:RefreshFull(true)
            assert(LO.full.lootRow.name:GetText() == "Neuer Kilt", "loot row: " .. tostring(LO.full.lootRow.name:GetText()))
            assert(LO.full.hint:GetText() == "", "hint with unknown value: " .. tostring(LO.full.hint:GetText()))
            -- coins first, then a fish whose item data has no name yet: the coins are skipped, the fish shown by name
            GetNumLootItems = function() return 2 end
            GetLootSlotType = function(i) return i == 1 and 2 or 1 end
            GetLootSlotLink = function(i) if i == 2 then return "|cffffffff|Hitem:6362::|h[Fisch]|h|r" end end
            GetLootSlotInfo = function(i) if i == 1 then return 133784, "12 Kupfer", 0 end return 133888, "Fisch", 1, nil, 1 end
            LO:RefreshFull(true)
            assert(LO.full.lootRow.link and LO.full.lootRow.link:find("6362"), "loot row after coins: " .. tostring(LO.full.lootRow.link))
            assert(ForeverQoLPanelDB.debug.lootSlots and #ForeverQoLPanelDB.debug.lootSlots == 2, "loot slots in debug data")
            GetLootSlotType = nil
            GetNumLootItems, GetLootSlotLink, GetLootSlotInfo = realNum, realLink, realInfo
            LO.full:Hide()
            ns.ItemInfo, GetInventoryItemLink, GetItemStats, UnitLevel = realItemInfo, realInvLink, realStats, realLevel
        end
        UnitClass = realClass; ForeverQoLPanelDB.warnings.ammoMin = 200
        HasNewMail = function() return true end
        GetLatestThreeSenders = function() return "Bob", "Alice" end
        ns.Elements:UpdateTexts(); ns.Elements.defs.mail.tip(GameTooltip)
        assert(ns.Elements.cells.mail.pulsing, "new mail does not glow")
        for _, eff in ipairs({ "glow", "blink", "icon", "none", "pulse" }) do
            ForeverQoLPanelDB.panel.noticeEffect = eff; ns.Elements:UpdateTexts()
            local fn = ns.Elements.cells.mail.scripts.OnUpdate; if fn then fn(ns.Elements.cells.mail, 0.3) end
        end
        for _, skin in ipairs({ "classic", "modern" }) do
            ForeverQoLPanelDB.panel.skin = skin; ForeverQoLPanelDB.panel.height = 36; ForeverQoLPanelDB.panel.fontSize = 14; ns.Refresh()
            assert(ns.Elements.cells.gold.h == 36, "panel height not applied (" .. skin .. ")")
        end
        ForeverQoLPanelDB.panel.skin = "classic"; ForeverQoLPanelDB.panel.height = 26; ForeverQoLPanelDB.panel.fontSize = 12; ns.Refresh()
        HasNewMail = function() return false end; ns.Elements:UpdateTexts()
        -- reputation strip: a watched faction adds it in both skins, the tooltip reads it
        GetWatchedFactionInfo = function() return "Darnassus", 5, 3000, 9000, 4500 end
        for _, skin in ipairs({ "classic", "modern" }) do
            ForeverQoLPanelDB.panel.skin = skin; ns.Dock.width = nil; ns.Dock:Relayout()
            assert(ns.Rep:Active() and ns.Rep.frame:IsShown(), "no reputation strip (" .. skin .. ")")
        end
        ns.Rep:ShowTooltip(ns.Rep.frame)
        -- at the highest level (and without the XP bar) it takes the XP bar's place
        local realLevel = UnitLevel
        UnitLevel = function() return 60 end
        for _, skin in ipairs({ "classic", "modern" }) do
            ForeverQoLPanelDB.panel.skin = skin; ns.Dock.width = nil; ns.Dock:Relayout()
            assert(ns.Dock:RepInSlot() and not ns.Dock.bar:IsShown() and ns.Rep.h == (skin == "classic" and 15 or 10), "rep bar not in the XP slot ("
                .. skin .. ") " .. tostring(ns.Dock:RepInSlot()) .. tostring(ns.Dock.bar:IsShown()) .. tostring(ns.Rep.h) .. "/" .. tostring(ns.XP.h)
                .. " max " .. tostring(GetMaxPlayerLevel and GetMaxPlayerLevel()))
        end
        UnitLevel = realLevel; ns.Dock.width = nil; ns.Dock:Relayout()
        -- placements: attached, below, free; the XP bar set free; move mode with the grid
        local P = ForeverQoLPanelDB.panel
        for _, skin in ipairs({ "classic", "modern" }) do
            P.skin = skin
            for _, place in ipairs({ "attach", "below", "free" }) do
                P.repPlace = place; ns.Dock.width = nil; ns.Dock:Relayout()
                assert(ns.Rep.frame:IsShown(), "no reputation bar (" .. skin .. ", " .. place .. ")")
                assert((place == "free") == ns.Dock.repHolder:IsShown(), "reputation holder (" .. place .. ")")
            end
            P.xpPlace = "free"; P.repPlace = "attach"; ns.Dock.width = nil; ns.Dock:Relayout()
            assert(ns.Dock.xpHolder:IsShown() and ns.XP.free and ns.Rep.free, "XP bar not free (" .. skin .. ")")
            P.xpPlace = "panel"; ns.Dock.width = nil; ns.Dock:Relayout()
            assert(not ns.Dock.xpHolder:IsShown() and not ns.XP.free, "XP bar not back on the panel")
        end
        P.skin = "classic"; P.repPlace = "attach"
        -- action buttons: out of range tints the icon, a cooldown gets a number, the global cooldown none
        do
            local BS = ns.ButtonState
            local b = CreateFrame("CheckButton", "ActionButton1", UIParent)
            local tint = {}
            b.icon = { SetVertexColor = function(_, r, g, bl) tint = { r, g, bl } end }
            b.action = 1
            b.IsVisible = function() return true end
            local cdHooks = {}
            b.cooldown = CreateFrame("Cooldown", nil, b)
            local realHook = hooksecurefunc
            HasAction = function() return true end
            IsUsableAction = function() return true, false end
            IsActionInRange = function() return false end
            BS:Collect(); BS:Tint(b)
            assert(tint[1] == 1 and tint[2] < 0.5, "out of range not tinted")
            b.fqpStart, b.fqpDur = 100, 30
            BS:Count(b, 110)
            assert(b.fqpCD and b.fqpCD.text, "no cooldown number")
            assert(BS.Format(12.4, ForeverQoLPanelDB.buttons) == "12" and BS.Format(90, ForeverQoLPanelDB.buttons) == "2m", "cooldown format")
            b.fqpStart, b.fqpDur = 100, 1.5
            BS:Count(b, 100.5)
            -- in combat the game keeps cooldowns and states secret: nothing compared, the game shows its own numbers
            local S1, S2 = {}, {}
            MOCK_secret[S1], MOCK_secret[S2] = true, true
            b.cooldown:SetCooldown(S1, S2)
            assert(b.fqpSecret and not b.fqpStart, "secret cooldown not set aside")
            BS:Count(b, 120)
            IsActionInRange = function() return S1 end
            BS:Tint(b)
            b.cooldown:SetCooldown(100, 30)
            assert(not b.fqpSecret and b.fqpStart == 100, "plain cooldown after a secret one")
            MOCK_secret[S1], MOCK_secret[S2] = nil, nil
            IsActionInRange = function() return false end
            ForeverQoLPanelDB.buttons.range = false; BS:Refresh(); ForeverQoLPanelDB.buttons.range = true
            HasAction, IsUsableAction, IsActionInRange = nil, nil, nil
        end
        -- target cast bar: hidden stays hidden while it fades itself in, free sits on its holder, default comes back
        do
            local bar = CreateFrame("StatusBar", "TargetFrameSpellBar", UIParent)
            local alpha = 1
            bar.SetAlpha = function(_, a) alpha = a end
            -- the interrupt animation the game plays on the bar
            local anim = { stopped = false }
            anim.HookScript = function(self, _, fn) self.onPlay = fn end
            anim.Stop = function(self) self.stopped = true end
            bar.GetAnimationGroups = function() return anim end
            local onShow
            bar.HookScript = function(_, name, fn) if name == "OnShow" then onShow = fn end end
            local CB = ns.CastBar
            ForeverQoLPanelDB.castbar.target = "hide"; CB:Refresh()
            bar:SetAlpha(1)
            assert(alpha == 0, "hidden cast bar visible again")
            alpha = 1; anim.onPlay(anim)
            assert(anim.stopped and alpha == 0, "interrupt animation shows the hidden cast bar")
            assert(not bar:IsShown(), "hidden cast bar still shown")
            bar:Show(); onShow(bar)
            assert(not bar:IsShown(), "game shows the hidden cast bar again")
            -- Forever keeps the bar's layout values secret
            local S = {}; MOCK_secret[S] = true
            bar.GetNumPoints = function() return S end
            bar.GetWidth = function() return S end
            ForeverQoLPanelDB.castbar.target = "free"; CB:Refresh()
            assert(alpha == 1 and ForeverQoLPanelCastBar_target and ForeverQoLPanelCastBar_target:IsShown(), "free cast bar")
            ForeverQoLPanelDB.castbar.target = "default"; CB:Refresh()
            assert(not ForeverQoLPanelCastBar_target:IsShown(), "holder left after default")
            MOCK_secret[S] = nil
        end
        -- XP ring around the minimap: shown with its fills, the panel gives the bar up, a square minimap brings it back
        do
            local P = ForeverQoLPanelDB.panel
            local cds = {}
            local realCF = CreateFrame
            CreateFrame = function(kind, ...)
                local f = realCF(kind, ...)
                if kind == "Cooldown" then
                    cds[#cds + 1] = f
                    f.SetCooldown = function(self, start, dur) self.share = (GetTime() - start) / dur end
                end
                return f
            end
            Minimap.GetWidth = function() return 140 end
            P.xpPlace = "minimap"; ns.Refresh()
            CreateFrame = realCF
            local ring = ForeverQoLPanelXPRing
            assert(ring and ring:IsShown() and ns.Dock:XPPlace() == "minimap", "XP ring not shown")
            assert(#cds == 4 and cds[4].share and cds[4].share > 0, "XP ring fill: " .. tostring(cds[4] and cds[4].share))
            assert(ns.Dock:StackMain() ~= "xp", "XP bar still on the panel with the ring")
            -- folded without a bar in the panel, part of it stays at the screen edge for the mouse
            assert(ns.Dock.folded < ns.Dock:GetHeight(), "panel leaves the screen completely when folded")
            -- the reputation ring outside the XP ring, the reputation bar off the panel
            local realData = ns.Rep.Data
            ns.Rep.Data = function() return "Sturmwind", 5, 300, 1000 end
            P.repBar, P.repPlace = true, "minimap"; ns.Refresh()
            local rr = ForeverQoLPanelRepRing
            assert(rr and rr:IsShown() and ns.Dock:RepMode() == "minimap", "reputation ring not shown")
            assert(ns.RepRing.outer > ns.Ring.outer, "reputation ring not outside the XP ring")
            assert(rr.arcs.fill.share and math.abs(rr.arcs.fill.share - 0.3) < 0.01, "reputation ring fill")
            -- without the XP ring: right at the map
            P.xpPlace = "panel"; ns.Refresh()
            assert(rr:IsShown() and ns.RepRing.base == nil, "reputation ring alone")
            P.xpPlace = "minimap"; P.repPlace = "attach"; ns.Refresh()
            assert(not rr:IsShown(), "reputation ring left")
            ns.Rep.Data = realData
            -- the bar's look of finished quests applies to the ring too
            XP_CACHE_Q = ns.XP.cachedQuestXP
            ns.XP.cachedQuestXP = 500
            P.questStyle = "stripes"; ns.Refresh()
            assert(cds[3].tex and cds[3].tex:find("q%-stripes"), "ring ignores the quest style: " .. tostring(cds[3].tex))
            P.questStyle = "veil"; ns.Refresh()
            assert(cds[3].tex:find("%-gold"), "ring veil style: " .. tostring(cds[3].tex))
            ns.XP.cachedQuestXP = XP_CACHE_Q
            -- the tooltip when the mouse is on the band (centre 500/400 in the mock, outer radius about 80)
            ring.IsVisible = function(self) return self:IsShown() end
            local realCursor = GetCursorPosition
            GetCursorPosition = function() return 500 + 76, 400 end
            ns.Ring:CheckHover(); assert(ns.Ring.hover, "XP ring tooltip")
            -- the minimap cluster under the mouse (it takes the mouse on Forever): still the tooltip; a button: its own
            local cluster = CreateFrame("Frame", "FakeCluster", UIParent)
            cluster.IsObjectType = function(_, t) return t == "Frame" end
            GetMouseFoci = function() return { cluster } end
            ns.Ring.hover = false; ns.Ring:CheckHover(); assert(ns.Ring.hover, "XP ring tooltip over the minimap cluster")
            local btn = CreateFrame("Button", "FakeMMButton", Minimap)
            btn.IsObjectType = function(_, t) return t == "Button" end
            GetMouseFoci = function() return { btn } end
            ns.Ring:CheckHover(); assert(not ns.Ring.hover, "XP ring tooltip over a minimap button")
            GetMouseFoci = nil
            GetCursorPosition = function() return 500 + 76, 400 end
            ns.Ring:CheckHover()
            GetCursorPosition = function() return 500 + 20, 400 end
            ns.Ring:CheckHover(); assert(not ns.Ring.hover, "XP ring tooltip over the map")
            GetCursorPosition = realCursor
            -- our square minimap: a square frame of straight pieces, the minimap answers SQUARE, the border shows
            ForeverQoLPanelDB.minimap.shape, ForeverQoLPanelDB.minimap.look = "square", "modern"; ns.Refresh()
            assert(GetMinimapShape and GetMinimapShape() == "SQUARE", "square minimap shape")
            assert(ForeverQoLPanelMinimapBorder:IsShown(), "square minimap border")
            assert(ring:IsShown() and ns.Ring.shape == "square" and ring.sq.fill[1]:IsShown(), "XP frame around the square minimap")
            GetCursorPosition = function() return 500 + ns.Ring.h, 400 end
            ns.Ring:CheckHover(); assert(ns.Ring.hover, "square XP frame tooltip")
            GetCursorPosition = realCursor
            ForeverQoLPanelDB.minimap.shape = "round"; ns.Refresh()
            assert(GetMinimapShape == nil and not ForeverQoLPanelMinimapBorder:IsShown() and ns.Ring.shape == "round", "back to round")
            -- the classic border needs more room than the modern one
            ForeverQoLPanelDB.minimap.shape, ForeverQoLPanelDB.minimap.look = "square", "classic"; ns.Refresh()
            assert(ns.MinimapShape.BorderPad() == 9 and ns.MinimapShape.RingPad() == 5 and ForeverQoLPanelMinimapBorder:IsShown(), "classic square border")
            ForeverQoLPanelDB.minimap.shape = "round"; ns.Refresh()
            -- the game's elements at the minimap: hidden when unticked, back when ticked again
            GameTimeFrame = CreateFrame("Button", "GameTimeFrame", Minimap)
            local gtfAlpha = 1
            GameTimeFrame.SetAlpha = function(_, a) gtfAlpha = a end
            GameTimeFrame.GetAlpha = function() return gtfAlpha end
            ForeverQoLPanelDB.minimap.calendar = false; ns.Refresh()
            assert(GameTimeFrame:GetAlpha() == 0, "calendar still at the minimap")
            GameTimeFrame:SetAlpha(1); assert(GameTimeFrame:GetAlpha() == 0, "calendar shown again by the game")
            ForeverQoLPanelDB.minimap.calendar = true; ns.Refresh()
            assert(GameTimeFrame:GetAlpha() == 1, "calendar not back")
            -- Forever's day and night icon: an unnamed small frame in the minimap's container
            local cont = CreateFrame("Frame", nil, UIParent)
            MinimapCluster = MinimapCluster or CreateFrame("Frame", "MinimapCluster", UIParent)
            rawset(MinimapCluster, "MinimapContainer", cont)
            local diel = CreateFrame("Frame", nil, cont); diel:SetSize(40, 40)
            local dielAlpha = 1
            diel.SetAlpha = function(_, a) dielAlpha = a end
            diel.GetAlpha = function() return dielAlpha end
            cont.GetChildren = function() return diel end
            ForeverQoLPanelDB.minimap.calendar = false; ns.Refresh()
            assert(dielAlpha == 0, "day and night icon still shown")
            ForeverQoLPanelDB.minimap.calendar = true; ns.Refresh()
            assert(dielAlpha == 1, "day and night icon not back")
            rawset(MinimapCluster, "MinimapContainer", nil)
            -- coordinates under the map: found by their text, faded out and back
            MinimapCluster = MinimapCluster or CreateFrame("Frame", "MinimapCluster", UIParent)
            local coordFrame = CreateFrame("Frame", nil, MinimapCluster)
            local fs = coordFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetText("65.0, 50.3")
            local alpha = 1
            fs.SetAlpha = function(_, a) alpha = a end
            fs.GetAlpha = function() return alpha end
            local realKids, realRegs = MinimapCluster.GetChildren, MinimapCluster.GetRegions
            MinimapCluster.GetChildren = function() return coordFrame end
            coordFrame.GetRegions = function() return fs end
            fs.GetObjectType = function() return "FontString" end
            ForeverQoLPanelDB.minimap.coords = false; ns.Refresh()
            assert(alpha == 0, "coordinates still shown")
            ForeverQoLPanelDB.minimap.coords = true; ns.Refresh()
            assert(alpha == 1, "coordinates not back")
            MinimapCluster.GetChildren, MinimapCluster.GetRegions = realKids, realRegs
            -- a shape the ring cannot follow: the XP bar goes back to the panel
            GetMinimapShape = function() return "CORNER-TOPLEFT" end
            ns.Refresh()
            assert(not ring:IsShown() and ns.Dock:XPPlace() == "panel", "XP ring with an odd minimap shape")
            GetMinimapShape = nil
            P.xpPlace = "panel"; ns.Refresh()
        end
        -- warning sounds: each category its own, only when its warning is new, the old switch migrated
        do
            local W, played = ns.Warnings, {}
            local oldPS = PlaySound
            PlaySound = function(id) played[#played + 1] = id end
            assert(ForeverQoLPanelDB.warnings.soundFood == "none", "sound migration: " .. tostring(ForeverQoLPanelDB.warnings.soundFood))
            ForeverQoLPanelDB.warnings.soundFood, ForeverQoLPanelDB.warnings.soundAmmo = "ready", "alarm"
            W.seen = {}
            local list = { { "x", "food", "cons", "food" }, { "x", "class", "buffs", "class123" } }
            W:Show(list)
            assert(#played == 1, "food sound: " .. #played)
            W:Show(list)
            assert(#played == 1, "sound repeated for a known warning")
            list[#list + 1] = { "x", "ammo", "cons", "ammo" }
            W:Show(list)
            assert(#played == 2, "ammo sound: " .. #played)
            W:Show({}); PlaySound = oldPS
            -- every sound has its name
            for _, k in ipairs(W.SOUND_ORDER) do assert(W.SOUNDS[k] and ns.L["SND_" .. k:upper()], "sound name " .. k) end
            ForeverQoLPanelDB.warnings.soundFood, ForeverQoLPanelDB.warnings.soundAmmo = "none", "none"
        end
        ns.Mover:Toggle(true); assert(ns.Mover.active and ns.Warnings.moving and ForeverQoLPanelGrid:IsShown(), "move mode not on")
        local sx, sy = ns.Mover.SnapCenter(ns.Dock.xpHolder)
        ns.Mover:Toggle(false); assert(not ns.Mover.active and not ns.Warnings.moving, "move mode stuck")
        ns.Options:Open(); ns.Mover:Toggle(true); assert(not ns.Options.frame:IsShown(), "options not hidden for moving")
        ns.Mover:Toggle(false); assert(ns.Options.frame:IsShown(), "options not back after moving"); ns.Options.frame:Hide()
        ns.Mail:Alts(); ns.FullName()
        -- removing a character that no longer exists
        local before = #ns.Characters()
        local c = ns.Characters()[1]
        if c then ns.RemoveCharacter(c[1], c[2], c[3]); assert(#ns.Characters() == before - 1, "character not removed") end
        assert(not ns.Dock:RepInSlot() and ns.Dock.bar:IsShown(), "XP bar not back below max level")
        GetWatchedFactionInfo = function() return nil end; ns.Dock.width = nil; ns.Dock:Relayout()
        assert(not ns.Rep.frame:IsShown(), "reputation strip without a faction")
        ForeverQoLPanelDB.panel.skin = "classic"; ns.Dock.width = nil; ns.Dock:Relayout()
        -- mail recipient picker lists the other characters
        ns.Mail:Alts()
        IsResting = function() return true end; ForeverQoLPanelDB.warnings.hideResting = true; ns.Warnings:Update()
        ForeverQoLPanelDB.warnings.hideResting = false
        -- quests enough for the level: the preview runs into the bar's round end
        local q0 = ns.XP.cachedQuestXP; ns.XP.cachedQuestXP = 20000
        for _, st in ipairs({ "veil", "frame", "line", "stripes", "glow" }) do ForeverQoLPanelDB.panel.questStyle = st; ns.XP:Draw() end
        ForeverQoLPanelDB.panel.questStyle = "veil"; ns.XP:Draw()
        assert(ns.XP.frame.veilCap:IsShown(), "no cap at the round end")
        ns.XP.cachedQuestXP = q0; ns.XP:Draw()
        -- locked auras: reading throws, the last result stays
        -- locked auras (combat): carried on from the last readable list
        C_UnitAuras = { GetAuraDataByIndex = function(_, i)
            if MOCK_auraLock then error("Auras cannot be accessed when secret") end
            if i == 1 then return { name = "Spell324", duration = 600, expirationTime = 700, sourceUnit = "player", icon = 1, auraInstanceID = 77 } end
        end }
        ns.Warnings:Check()
        MOCK_auraLock = true
        local kept = ns.Warnings:Check(); assert(type(kept) == "table" and ns.Warnings.locked, "locked auras broke the check")
        assert(ns.Warnings.locked.Spell324, "buff not carried into the lock")
        assert(ns.Warnings:AuraChanged({ removedAuraInstanceIDs = { 77 } }) and not ns.Warnings.locked.Spell324, "removed aura stayed")
        -- Lightning Shield (324) with 3 charges: three hits 3.5 s apart empty it
        ns.Warnings.locked = { Spell324 = { expires = 0, duration = 0, mine = true, charges = 3 } }
        local t = 100; GetTime = function() return t end
        assert(not ns.Warnings:Hit("WOUND", nil, 50, 1)); t = 101
        assert(not ns.Warnings:Hit("WOUND", nil, 50, 1), "cooldown ignored")
        assert(ns.Warnings.locked.Spell324.charges == 2, "charges: " .. ns.Warnings.locked.Spell324.charges)
        t = 105; ns.Warnings:Hit("MISS", nil, 0, 1); assert(ns.Warnings.locked.Spell324.charges == 2, "miss spent a charge")
        ns.Warnings:Hit("WOUND", nil, 50, 1); t = 109
        assert(ns.Warnings:Hit("WOUND", nil, 50, 1) and not ns.Warnings.locked.Spell324, "empty shield stayed")
        ns.Warnings:Cast(324); assert(ns.Warnings.locked.Spell324 and ns.Warnings.locked.Spell324.charges == 3, "recast")
        GetTime = function() return 100 end
        MOCK_auraLock = nil
        ns.Warnings:Check(); assert(not ns.Warnings.locked, "readable again did not unlock")
        C_UnitAuras = nil
        GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silber", "%d Kupfer"
        ns.Gameplay:MoneyMessage("Ihr erbeutet 1 Gold, 23 Silber, 5 Kupfer.")
        ns.Gameplay:MoneyMessage("Ihr erbeutet 7 Kupfer.")
        ns.Gameplay:SetLootMoving(true); ns.Gameplay.anchor.scripts.OnDragStop(ns.Gameplay.anchor)
        assert(ForeverQoLPanelDB.gameplay.lootPos, "loot position not saved")
        ns.Gameplay.anchor.scripts.OnMouseUp(ns.Gameplay.anchor, "RightButton"); assert(not ns.Gameplay.moving, "loot move stuck")
        for _, sh in ipairs({ "round", "square", "none", "panel" }) do ForeverQoLPanelDB.gameplay.lootShape = sh; ns.Gameplay:MoneyMessage("1 Gold") end
        ForeverQoLPanelDB.gameplay.lootScale = 1.3; ns.Refresh(); ns.Gameplay:ResetLootPosition()
        ns.Warnings:SetMoving(true); assert(ns.Warnings.frames.buffs:IsShown(), "move mode shows samples")
        local fb, fc = ns.Warnings.frames.buffs, ns.Warnings.frames.cons
        fc.scripts.OnDragStart(fc); fc.scripts.OnDragStop(fc)          -- grouped: moves the leader
        IsShiftKeyDown = function() return true end
        fc.scripts.OnDragStart(fc)                                       -- shift: out of the group
        assert(ForeverQoLPanelDB.warnings.link == false, "shift-drag did not split")
        fc.scripts.OnDragStop(fc)                                        -- dropped onto the other: grouped again
        assert(ForeverQoLPanelDB.warnings.link and ForeverQoLPanelDB.warnings.link.follower == "cons", "no snap")
        IsShiftKeyDown = function() return false end
        ns.Warnings:PreviewAnim()
        fb.scripts.OnMouseUp(fb, "RightButton"); assert(not ns.Warnings.moving, "move mode stuck")
        ForeverQoLPanelDB.warnings.scale = 1.5; ns.Refresh(); ns.Warnings:ResetPosition()
        for _, a in ipairs({ "pulse", "bounce", "flash", "wave", "none" }) do
            ForeverQoLPanelDB.warnings.anim = a; ns.Warnings.frames.buffs.shown = {}; ns.Warnings:Show(ns.Warnings:Check())
        end
        -- frame-driven animation runs its course and stops
        assert(not ns.Warnings.frames.buffs.rows[1] or not ns.Warnings.frames.buffs.rows[1].scripts.OnUpdate, "animated behind the loading screen")
        ns.Warnings.readyAt = 0
        ForeverQoLPanelDB.warnings.anim = "pulse"; ForeverQoLPanelDB.warnings.animRepeat = "always"
        ns.Warnings.frames.buffs.shown = {}; ns.Warnings.frames.cons.shown = {}
        local current = ns.Warnings:Check()
        assert(#current > 0, "test needs a warning")
        ns.Warnings:Show(current)
        local r1
        for _, fr in pairs(ns.Warnings.frames) do
            for _, r in ipairs(fr.rows) do if r:IsShown() and r.scripts.OnUpdate then r1 = r end end
        end
        assert(r1, "no animation after the loading screen")
        for _ = 1, 40 do if r1.scripts.OnUpdate then r1.scripts.OnUpdate(r1, 0.1) end end
        assert(not r1.scripts.OnUpdate, "animation did not stop")
        ns.Warnings:Show(ns.Warnings:Check())
        ForeverQoLPanelDB.warnings.animRepeat = "once"
        ForeverQoLPanelDB.motion = "off"; ns.Refresh(); assert(ForeverQoLPanelDB.panel.animations == false, "motion off")
        ForeverQoLPanelDB.motion = "full"; ns.Refresh()
        ForeverQoLPanelDB.warnings.iconShape = "square"; ns.Warnings:Show(ns.Warnings:Check())
        ForeverQoLPanelDB.warnings.iconShape = "panel"
        for _, b in ipairs({ "round", "square", "none" }) do ForeverQoLPanelDB.panel.iconBorder = b; ns.Warnings:Show(ns.Warnings:Check()) end
        MOCK_tooltipPost[0](GameTooltip, { id = 2589, lines = {} })
        -- aura tooltips carry secret text: reading it must not throw
        local secret = setmetatable({}, { __index = function() error("secret value touched") end })
        local first = obj("FontString"); first.GetText = function() return secret end
        MOCK_secret[secret] = true; GameTooltipTextLeft1 = first; GameTooltip.name = "GameTooltip"
        ns.Tooltip:Object(GameTooltip)
        GameTooltipTextLeft1 = nil
        ns.Elements.defs.pvp.text(); ns.Elements.defs.pvp.tip(GameTooltip); ns.Elements.defs.pvp.click()
        ForeverQoLPanelDB.panel.border = 1; ns.Refresh(); ForeverQoLPanelDB.panel.border = 3; ns.Refresh()
        ns.Wizard:Open(true)
        for _ = 1, 30 do ns.Wizard:Go(1) end
        assert(ForeverQoLPanelDB.wizard == ns.VERSION, "wizard not finished")
        ForeverQoLPanelDB.wizard = "0.1.0"; ns.Wizard:Open(false)
        assert(#ns.Wizard.pages == 22, "update pages: " .. #ns.Wizard.pages)
        for i = 1, 8 do ns.Wizard:Jump(i) end
        ns.Wizard:OpenNews(); assert(#ns.Wizard.pages == 4 and ns.Wizard.pages[2].id == "minimapring" and ns.Wizard.pages[4].id == "newelements", "news pages: " .. #ns.Wizard.pages)
        ns.Wizard.frame.tiles[1]:GetScript("OnClick")(ns.Wizard.frame.tiles[1])
        ns.Wizard:Finish()
        SlashCmdList.FOREVERQOLPANEL("reset")
        SlashCmdList.FOREVERQOLPANEL("")
    """)
    dock = lua.globals().ForeverQoLPanelDock
    assert dock.width and dock.width > 300, dock.width
    assert ns.XP.cachedQuestXP == 3700, ns.XP.cachedQuestXP
    # every element renders its text and tooltip
    for key in lua.eval("function(ns) local t = {} for k in pairs(ns.Elements.defs) do t[#t+1] = k end return t end")(ns).values():
        lua.eval("function(ns, k) local d = ns.Elements.defs[k]; d.text(); if d.tip then d.tip(GameTooltip) end end")(ns, key)
    ns.XP.ShowTooltip(ns.XP)
    ns.XP.Describe(ns.XP)
    errors = lua.eval("function() return #ForeverQoLPanelDB.debug.errors end")()
    assert errors == 0, lua.eval("function() return ForeverQoLPanelDB.debug.errors[1] end")()
    assert ns.Minimap.List(ns.Minimap)[1].name == "Forever QoL Panel"
    names = lua.eval("function(ns) local t = {} for _, e in ipairs(ns.Minimap.entries) do t[#t+1] = e.name end return table.concat(t, '|') end")(ns)
    assert names == "Baganator|Darkmoon Arcade|Good Range|LFG Forever", names
    print(f"smoke ok: panel width {dock.width}, quest XP {ns.XP.cachedQuestXP}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

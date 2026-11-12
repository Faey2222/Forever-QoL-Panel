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
        MerchantFrame.shown = false   -- Blizzard shows its frame after the event
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
        for _ = 1, 12 do ns.Wizard:Go(1) end
        assert(ForeverQoLPanelDB.wizard == ns.VERSION, "wizard not finished")
        ForeverQoLPanelDB.wizard = "0.1.0"; ns.Wizard:Open(false)
        assert(#ns.Wizard.pages == 7, "update pages: " .. #ns.Wizard.pages)
        for i = 1, 8 do ns.Wizard:Jump(i) end
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

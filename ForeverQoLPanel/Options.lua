local _, ns = ...

-- Options in an own window, same look as the setup wizard (UI.lua): categories on the left, the settings of the
-- chosen one on the right. Blizzard's settings (Esc > Options > AddOns) only get a page with a button to open it.
local O = {}
ns.Options = O

local LANGUAGES = {
    { "auto" }, { "enUS", "English" }, { "deDE", "Deutsch" }, { "frFR", "Français" },
    { "esES", "Español" }, { "ruRU", "Русский" }, { "zhCN", "简体中文" },
}

local L = setmetatable({}, { __index = function(_, k) return ns.L[k] end })

local function db(name) return function() return name and ns.db[name] or ns.db end end
local panel, opts = db("panel"), function() return ns.db.panel.opt end
local minimap, actionbar, gameplay = db("minimap"), db("actionbar"), db("gameplay")
local nameplates, warnings, tooltip, root = db("nameplates"), db("warnings"), db("tooltip"), db(nil)
local layout = db("layout")
local lootopt = db("lootopt")
local btns = db("buttons")
local castbar = db("castbar")
local radar = db("radar")
local together = db("together")
-- a colour setting: tbl()[key] = { r, g, b }
local function color(label, tip, tbl, key, needs)
    return { type = "color", label = label, tip = tip, needs = needs,
        get = function() return tbl()[key] end, set = function(v) tbl()[key] = v end }
end

-- the loot optimizer's weights for your class and the profile it rates for: one slider per stat that counts
local RANGE = { CritRating = 30, HitRating = 30, HasteRating = 30, ExpertiseRating = 30, DodgeRating = 30, ParryRating = 30,
    BlockRating = 15, MeleeDps = 25, RangedDps = 25, Mp5 = 6 }
local function weightSpecs()
    local LO = ns.LootOpt
    local cls = select(2, UnitClass("player"))
    local profile = LO.Profile(cls)
    local w, base = LO.Weights(cls, profile)
    local list = {}
    for _, key in ipairs(LO.ORDER) do
        if (base[key] or 0) > 0 or (w[key] or 0) > 0 then
            local top = math.max(RANGE[key] or 2, math.ceil((base[key] or 0) * 2 * 10) / 10)
            list[#list + 1] = { type = "slider", label = LO.StatName(key), min = 0, max = top,
                step = top <= 0.2 and 0.005 or (top <= 3 and 0.01 or 0.1), needs = { "lootopt" },
                get = function() return LO.Weights(cls, profile)[key] or 0 end,
                set = function(v)
                    local d = ns.db.lootopt
                    d.weights[cls] = d.weights[cls] or {}
                    d.weights[cls][profile] = type(d.weights[cls][profile]) == "table" and d.weights[cls][profile] or {}
                    d.weights[cls][profile][key] = v
                end }
        end
    end
    if (w.HitRating or 0) > 0 then
        list[#list + 1] = { type = "slider", label = L.LO_CAP:format(LO.StatName("HitRating")), tip = L.LO_CAP_TIP,
            min = 0, max = 20, step = 0.5, suffix = " %", needs = { "lootopt" },
            get = function() return LO.Caps(cls, profile).HitRating end,
            set = function(v)
                local d = ns.db.lootopt
                d.caps[cls] = type(d.caps[cls]) == "table" and d.caps[cls] or {}
                d.caps[cls][profile] = v
            end }
    end
    return list
end

-- value accessors for a spec
local function bind(s, tbl, key, onChange)
    s.tbl, s.key = tbl, key   -- to tell a setting the newest version brought (marked as new)
    s.get = function() return tbl()[key] end
    s.set = function(v) tbl()[key] = v; if onChange then onChange(v) end end
    return s
end
local function check(label, tip, tbl, key, needs, extra)
    local s = bind({ type = "check", label = label, tip = tip, needs = needs }, tbl, key)
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end
local function choice(label, tip, tbl, key, values, needs, onChange, indent)
    return bind({ type = "choice", label = label, tip = tip, values = values, needs = needs, indent = indent }, tbl, key, onChange)
end
local function slider(label, tip, key, min, max, step, suffix, needs, tbl, indent)
    return bind({ type = "slider", label = label, tip = tip, min = min, max = max, step = step, suffix = suffix,
        needs = needs, indent = indent }, tbl or panel, key)
end
local function header(label) return { type = "header", label = label } end

-- a page's entries without the gaps (entries only in the development copy are nil elsewhere, and ipairs would stop
-- at the first one)
function O.Compact(t)
    local out = {}
    for i = 1, table.maxn(t) do if t[i] then out[#out + 1] = t[i] end end
    return out
end

-- Settings the newest version brought get the game's "new" mark (the news pages tell which); a page holding any
-- is marked in the navigation too.
local function markNew(specs, fresh)
    local any = false
    for _, s in ipairs(specs) do
        local t = s.tbl and select(2, pcall(s.tbl))
        s.isNew = type(t) == "table" and fresh[t] and fresh[t][s.key] or nil
        if s.isNew then any = true end
    end
    return any
end
function O.FreshSettings() return ns.Wizard and ns.Wizard.NewSettings and ns.Wizard.NewSettings() or {} end

-- a whole feature the newest version brought (its page's main switch is new): marked in the navigation only, not on
-- every one of its settings
function O.FeatureIsNew(p, fresh)
    local m = p.master
    if not m then return false end
    local ok, t = pcall(m[1])
    return ok and type(t) == "table" and fresh[t] and fresh[t][m[2]] and true or false
end

function O.PageIsNew(p, fresh)
    if O.FeatureIsNew(p, fresh) then return true end
    -- a page of tab pages: new if any of them is
    if p.tabs then
        for _, tab in ipairs(p.tabs) do if O.PageIsNew(tab, fresh) then return true end end
        return false
    end
    if not p.build then return false end
    local ok, specs = pcall(p.build)
    return ok and type(specs) == "table" and markNew(O.Compact(specs), fresh)
end

-- the marks on one page's settings (none on a page that is new as a whole)
function O.MarkPage(p, specs, fresh)
    if O.FeatureIsNew(p, fresh) then
        for _, s in ipairs(specs) do s.isNew = nil end
        return
    end
    markNew(specs, fresh)
end
O.MarkNew = markNew

local function buttons(label, tip, list, needs)
    return { type = "button", label = label, tip = tip, buttons = list, needs = needs }
end
local WHERE_FOOD = function() return { { "instance", L.WHERE_INSTANCE }, { "world", L.WHERE_WORLD } } end
local WHERE_FLASK = function() return { { "raid", L.WHERE_RAID }, { "instance", L.WHERE_INSTANCE }, { "world", L.WHERE_WORLD } } end
local SHAPES = function() return { { "panel", L.SHAPE_PANEL }, { "round", L.BORDER_ROUND }, { "square", L.BORDER_SQUARE },
    { "none", L.NONE } } end

-- "More addons from us": our other addons, with a hint where to get them (shown only here, never in the game)
local MORE = {
    { folder = "DarkmoonArcade", name = "Darkmoon Arcade", logo = "more-darkmoonarcade", text = "MORE_DARKMOON",
      url = "https://www.curseforge.com/wow/addons/darkmoon-arcade" },
}
local function loaded(folder)
    local A = C_AddOns
    if A and A.IsAddOnLoaded then return A.IsAddOnLoaded(folder) or A.IsAddOnLoaded(folder .. "_Dev") end
    return IsAddOnLoaded and (IsAddOnLoaded(folder) or IsAddOnLoaded(folder .. "_Dev"))
end
-- one tile per addon: its logo (shipped with this addon, so it shows without the other one), name, what it is,
-- installed or where to get it
function O.MoreAddons()
    local tiles = {}
    for _, a in ipairs(MORE) do
        -- the development copy can show the page as if none were installed: /fqp more
        local have = loaded(a.folder) and not (ns.name == "ForeverQoLPanel_Dev" and ns.db.devMoreMissing)
        tiles[#tiles + 1] = { logo = ns.Tex(a.logo), name = a.name, text = L[a.text],
            status = have and ("|cff20ff20" .. L.MORE_INSTALLED .. "|r") or ("|cffffd100" .. L.MORE_GET:format(a.name) .. "|r"),
            -- not installed: a button with the CurseForge link to copy
            button = not have and a.url and { L.MORE_LINK, function() ns.UI.CopyLink(L.MORE_LINK_TITLE:format(a.name), a.url) end } or nil }
    end
    return { { type = "text", label = L.MORE_TIP }, { type = "tiles", tiles = tiles } }
end

-- Pages in groups (shown as titles in the list). A page with `master` gets the feature's on/off switch in its header,
-- the list greys out switched-off features. build() -> specs (UI.lua).
local PAGES = {
    -- General ----------------------------------------------------------------------------------------------------
    { group = "NAV_GENERAL", icon = "Interface\\Icons\\INV_Misc_Gear_01", title = "SEC_GENERAL", build = function()
        local langs = {}
        for _, l in ipairs(LANGUAGES) do langs[#langs + 1] = { l[1], l[2] or L.LANG_AUTO } end
        return {
            header(L.SEC_GENERAL),
            choice(L.OPT_LANGUAGE, L.OPT_LANGUAGE_TIP, root, "language", langs, nil, function(v)
                ns.SetLanguage(v)
                -- panel cells keep their widest width; texts in another language start over
                if ns.Elements and ns.Elements.ResetWidths then ns.Elements:ResetWidths() end
            end),
            choice(L.OPT_MOTION, L.OPT_MOTION_TIP, root, "motion", { { "full", L.MOTION_FULL },
                { "reduced", L.MOTION_REDUCED }, { "off", L.MOTION_OFF } }),
            check(L.OPT_VERSIONCHECK, L.OPT_VERSIONCHECK_TIP, root, "versionCheck"),
            header(L.SEC_MOVE),
            buttons(L.OPT_MOVE, L.OPT_MOVE_TIP, { { L.OPT_WARN_MOVE_BTN, function() ns.Mover:Toggle(true) end } }),
            check(L.MOVE_GRID, nil, layout, "grid"),
            check(L.MOVE_SNAP, L.OPT_SNAP_TIP, layout, "snap"),
            slider(L.OPT_GRID_SIZE, nil, "gridSize", 8, 64, 4, " px", nil, layout),
            header(L.WZ_OPEN),
            buttons(L.WZ_OPEN, L.WZ_OPEN_TIP, { { L.WZ_OPEN_BTN, function() ns.Wizard:Open(true) end } }),
            buttons(L.WZ_NEWS, L.WZ_NEWS_TIP, { { L.WZ_NEWS_BTN, function() ns.Wizard:OpenNews() end } }),
        }
    end },

    -- the characters the addon knows; ones that no longer exist can be removed (gold overview, mail list ...)
    { group = "NAV_GENERAL", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", title = "SEC_CHARS", build = function()
        local list = { { type = "text", label = L.CHARS_TIP } }
        local me, myRealm = UnitName("player"), ns.Realm()
        local lastRealm
        for _, c in ipairs(ns.Characters()) do
            local realm, faction, name, e = c[1], c[2], c[3], c[4]
            if realm ~= lastRealm then list[#list + 1] = header(ns.ShortRealm(realm)); lastRealm = realm end
            local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class or ""]
            local full = ns.CharName(name, e)
            local label = (col and col.colorStr and ("|c" .. col.colorStr .. full .. "|r") or full)
                .. (e.level and ("  |cff9d9d9d" .. L.LVL_N:format(e.level) .. "|r") or "")
            local tip = (FACTION_ALLIANCE and faction == "Alliance" and FACTION_ALLIANCE)
                or (FACTION_HORDE and faction == "Horde" and FACTION_HORDE) or faction
            if name == me and realm == myRealm then
                -- a row without a button, so it stays in its realm's card
                list[#list + 1] = buttons(label .. "  |cff9d9d9d(" .. L.CHARS_YOU .. ")|r", tip, {})
            else
                list[#list + 1] = buttons(label, tip, { { L.CHARS_REMOVE, function()
                    ns.RemoveCharacter(realm, faction, name)
                    O:Render(true)
                end } })
            end
        end
        return list
    end },

    -- Interface --------------------------------------------------------------------------------------------------
    { group = "NAV_INTERFACE", icon = "Interface\\Icons\\INV_Misc_Note_06", title = "SEC_PANEL",
        master = { panel, "enabled", tip = "OPT_PANEL_TIP", reload = true }, build = function()
        local P = { "panel" }
        return {
            header(L.SEC_BEHAVIOUR),
            choice(L.OPT_POSITION, L.OPT_POSITION_TIP, panel, "position", { { "top", L.POS_TOP }, { "bottom", L.POS_BOTTOM } }, P),
            check(L.PIN_PANEL, L.PIN_HINT, panel, "pinned", P),
            slider(L.OPT_DELAY, L.OPT_DELAY_TIP, "delay", 1, 15, 0.5, " s", P),
            header(L.SEC_LOOK),
            choice(L.OPT_SKIN, L.OPT_SKIN_TIP, panel, "skin", { { "classic", L.SKIN_CLASSIC }, { "modern", L.SKIN_MODERN } }, P),
            choice(L.OPT_CORNERS, nil, panel, "corners", { { "square", L.CORNERS_SQUARE }, { "round", L.CORNERS_ROUND } },
                { "panel", "modern" }, nil, true),
            choice(L.OPT_RIM, L.OPT_RIM_TIP, panel, "rim", { { "bronze", L.RIM_BRONZE }, { "silver", L.RIM_SILVER },
                { "dark", L.RIM_DARK } }, P),
            choice(L.OPT_BORDER, L.OPT_BORDER_TIP, panel, "border", { { 1, L.BORDER_THIN }, { 2, L.BORDER_NORMAL },
                { 3, L.BORDER_THICK } }, P),
            choice(L.OPT_ICONBORDER, nil, panel, "iconBorder", { { "round", L.BORDER_ROUND }, { "square", L.BORDER_SQUARE },
                { "none", L.NONE } }, P),
            choice(L.OPT_SEP, L.OPT_SEP_TIP, panel, "separator", { { "line", L.SEP_LINE }, { "dot", L.SEP_DOT },
                { "none", L.NONE } }, P),
            slider(L.OPT_PAD, L.OPT_PAD_TIP, "pad", 2, 20, 1, " px", P),
            slider(L.OPT_HEIGHT, L.OPT_HEIGHT_TIP, "height", 20, 40, 1, " px", P),
            slider(L.OPT_FONTSIZE, nil, "fontSize", 9, 16, 1, " pt", P),
            choice(L.OPT_NOTICE, L.OPT_NOTICE_TIP, panel, "noticeEffect", { { "pulse", L.NOTICE_PULSE }, { "glow", L.NOTICE_GLOW },
                { "blink", L.NOTICE_BLINK }, { "icon", L.NOTICE_ICON }, { "none", L.NONE } }, P),
            -- a test for the width animation, only in the development copy
            ns.name == "ForeverQoLPanel_Dev" and buttons(L.OPT_TEST_WIDTH, L.OPT_TEST_WIDTH_TIP,
                { { L.OPT_TEST_WIDTH_BTN, function() ns.Elements:TestWidths() end } }, P) or nil,
        }
    end },
    { group = "NAV_INTERFACE", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", title = "SEC_ELEMENTS", tabsByHeader = true,
        off = function() return not ns.db.panel.enabled end, build = function()
        -- every element with its own settings right below it (indented, greyed while the element is off)
        local SUB = {
            zone = { { "zoneCoords", L.OPT_ZONE_COORDS } },
            xph = { { "xphTime", L.OPT_XPH_TIME, L.OPT_XPH_TIME_TIP } },
            clock = { { "serverTime", L.OPT_SERVER_TIME }, { "minimapClock", L.OPT_MM_CLOCK, nil, true } },
            addons = { { "addonsIconOnly", L.OPT_ADDONS_ICON } },
            tracking = { { "trackingIconOnly", L.OPT_TRACKING_ICON } },
            wim = { { "wimHideButton", L.OPT_WIM_HIDE_BTN, L.OPT_WIM_HIDE_BTN_TIP }, { "wimHideEmpty", L.OPT_HIDE_EMPTY_WIM } },
            mail = { { "mailHideEmpty", L.OPT_HIDE_EMPTY_MAIL } },
        }
        local items = function() return ns.db.panel.items end
        -- one card per theme; elements of other classes (ammo, soul shards) are left out
        local list = { { type = "text", label = L.ITEMS_TIP } }
        for _, g in ipairs(ns.Elements:Grouped()) do
            if #g[2] > 0 then
                list[#list + 1] = header(g[1])
                for _, key in ipairs(g[2]) do
                    list[#list + 1] = check(L["ITEM_" .. key], nil, items, key, { "panel" })
                    for _, s in ipairs(SUB[key] or {}) do
                        list[#list + 1] = check(s[2], s[3], opts, s[1], not s[4] and { "panel", key } or nil, { indent = true })
                    end
                end
            end
        end
        return list
    end },
    -- XP and reputation bar: one page, a tab each
    { group = "NAV_INTERFACE", icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", title = "SEC_BARS", tabs = {
    { title = "SEC_XPBAR",
        master = { panel, "xpbar", tip = "OPT_XPBAR_TIP", needs = { "panel" } }, build = function()
        local X = { "xpbar" }
        local ticks = { { 0, L.NONE } }
        for _, n in ipairs({ 5, 10, 20, 25 }) do ticks[#ticks + 1] = { n, L.TICKS_N:format(n) } end
        return {
            header(L.SEC_LAYOUT),
            choice(L.OPT_XP_PLACE, L.OPT_XP_PLACE_TIP, panel, "xpPlace", { { "panel", L.PLACE_PANEL }, { "free", L.PLACE_FREE },
                { "minimap", L.PLACE_MINIMAP } }, X),
            choice(L.OPT_RING_WIDTH, nil, panel, "ringWidth", { { "thin", L.RING_THIN }, { "medium", L.RING_MEDIUM },
                { "wide", L.RING_WIDE } }, { "xpbar", "xpring" }, nil, true),
            slider(L.OPT_RING_GAP, L.OPT_RING_GAP_TIP, "ringGap", 0, 20, 1, " px", { "xpbar", "xpring" }, nil, true),
            buttons(L.OPT_POS_RESET, nil, { { L.OPT_WARN_MOVE_BTN, function() ns.Mover:Toggle(true) end },
                { L.OPT_WARN_RESET_BTN, function() ns.db.panel.xpPos = nil; ns.Refresh() end } }, { "xpbar", "xpfree" }),
            choice(L.OPT_STYLE, L.OPT_STYLE_TIP, panel, "style", { { "edge", L.STYLE_EDGE }, { "rail", L.STYLE_RAIL } }, X),
            slider(L.OPT_GAP, L.OPT_GAP_TIP, "gap", 4, 40, 1, " px", { "xpbar", "rail" }),
            slider(L.OPT_WIDTH, L.OPT_WIDTH_TIP, "barWidth", 200, 2000, 10, " px", X),
            choice(L.OPT_TICKS, nil, panel, "ticks", ticks, X),
            header(L.SEC_XPTEXT),
            check(L.OPT_XPTEXT, L.OPT_XPTEXT_TIP, panel, "xpText", { "xpbar", "xpnotring" }),
            check(L.OPT_XPTEXT_VALUES, nil, panel, "xpTextValues", { "xpbar", "xptext", "xpnotring" }, { indent = true }),
            check(L.OPT_XPTEXT_PERCENT, nil, panel, "xpTextPercent", { "xpbar", "xptext", "xpnotring" }, { indent = true }),
            check(L.OPT_XPTEXT_TIME, L.OPT_XPTEXT_TIME_TIP, panel, "xpTextTime", { "xpbar", "xptext", "xpnotring" }, { indent = true }),
            check(L.OPT_XPTEXT_RESTED, nil, panel, "xpTextRested", { "xpbar", "xptext", "xpnotring" }, { indent = true }),
            choice(L.OPT_XPTEXT_POS, L.OPT_XPTEXT_POS_TIP, panel, "xpTextPos", { { "on", L.XPTEXT_ON }, { "below", L.XPTEXT_BELOW } },
                { "xpbar", "xptext", "xpnotring" }, nil, true),
            slider(L.OPT_XPTEXT_SIZE, nil, "xpTextSize", 8, 16, 1, " pt", { "xpbar", "xptext", "xpnotring" }, panel, true),
            slider(L.OPT_XPTEXT_GAP, L.OPT_XPTEXT_GAP_TIP, "xpTextGap", 1, 6, 1, "", { "xpbar", "xptext", "xpnotring" }, panel, true),
            header(L.SEC_PREVIEW),
            check(L.OPT_DONE, L.OPT_DONE_TIP, panel, "questPreview", X),
            choice(L.OPT_QSTYLE, L.OPT_QSTYLE_TIP, panel, "questStyle", { { "veil", L.QSTYLE_VEIL }, { "frame", L.QSTYLE_FRAME },
                { "line", L.QSTYLE_LINE }, { "glow", L.QSTYLE_GLOW }, { "shimmer", L.QSTYLE_SHIMMER },
                { "stripes", L.QSTYLE_STRIPES } }, { "xpbar", "preview" }, nil, true),
            check(L.OPT_PULSE, L.OPT_PULSE_TIP, panel, "readyPulse", { "xpbar", "preview" }, { indent = true }),
            check(L.OPT_LOG, L.OPT_LOG_TIP, panel, "logPreview", X),
            header(L.SEC_BLIZZARD),
            check(L.OPT_HIDE_BLIZZ, L.OPT_HIDE_BLIZZ_TIP, panel, "hideBlizzardXP", X),
        }
    end },
    { title = "SEC_REP",
        master = { panel, "repBar", tip = "OPT_REPBAR_TIP", needs = { "panel" } }, build = function()
        local R, T = { "repbar" }, { "repbar", "reptext" }
        local ticks = { { 0, L.NONE } }
        for _, n in ipairs({ 5, 10, 20, 25 }) do ticks[#ticks + 1] = { n, L.TICKS_N:format(n) } end
        return {
            header(L.SEC_LAYOUT),
            choice(L.OPT_REP_PLACE, L.OPT_REP_PLACE_TIP, panel, "repPlace", { { "attach", L.REP_ATTACH },
                { "below", L.REP_BELOW }, { "free", L.PLACE_FREE }, { "minimap", L.PLACE_MINIMAP } }, R),
            choice(L.OPT_RING_WIDTH, nil, panel, "repRingWidth", { { "thin", L.RING_THIN }, { "medium", L.RING_MEDIUM },
                { "wide", L.RING_WIDE } }, { "repbar", "repring" }, nil, true),
            slider(L.OPT_RING_GAP, L.OPT_REP_RING_GAP_TIP, "repRingGap", 0, 20, 1, " px", { "repbar", "repring" }, nil, true),
            buttons(L.OPT_POS_RESET, nil, { { L.OPT_WARN_MOVE_BTN, function() ns.Mover:Toggle(true) end },
                { L.OPT_WARN_RESET_BTN, function() ns.db.panel.repPos = nil; ns.Refresh() end } }, { "repbar", "repfree" }),
            slider(L.OPT_REP_WIDTH, L.OPT_REP_WIDTH_TIP, "repWidth", 50, 100, 5, " %", R),
            choice(L.OPT_TICKS, nil, panel, "repTicks", ticks, R),
            header(L.SEC_XPTEXT),
            check(L.OPT_XPTEXT, nil, panel, "repText", R),
            check(L.OPT_REPTEXT_NAME, nil, panel, "repTextName", T, { indent = true }),
            check(L.OPT_REPTEXT_STANDING, nil, panel, "repTextStanding", T, { indent = true }),
            check(L.OPT_REPTEXT_VALUES, nil, panel, "repTextValues", T, { indent = true }),
            check(L.OPT_XPTEXT_PERCENT, nil, panel, "repTextPercent", T, { indent = true }),
            choice(L.OPT_XPTEXT_POS, L.OPT_XPTEXT_POS_TIP, panel, "repTextPos", { { "on", L.XPTEXT_ON }, { "below", L.XPTEXT_BELOW } },
                T, nil, true),
            slider(L.OPT_XPTEXT_SIZE, nil, "repTextSize", 7, 14, 1, " pt", T, panel, true),
        }
    end },
    -- the hunter pet's XP bar
    { title = "SEC_PET", icon = "Interface\\Icons\\Ability_Hunter_BeastTaming",
        master = { panel, "petBar", tip = "OPT_PETBAR_TIP", needs = { "panel", "hunter" } }, build = function()
        local P = { "petbar" }
        local ticks = { { 0, L.NONE } }
        for _, n in ipairs({ 5, 10, 20, 25 }) do ticks[#ticks + 1] = { n, L.TICKS_N:format(n) } end
        local colors = {}
        for _, c in ipairs(ns.PetXP.COLOR_ORDER) do colors[#colors + 1] = { c, L["COLOR_" .. c:upper()] } end
        return {
            header(L.SEC_LAYOUT),
            choice(L.OPT_PET_PLACE, L.OPT_PET_PLACE_TIP, panel, "petPlace", { { "side", L.PET_SIDE }, { "attach", L.PET_ATTACH },
                { "minimap", L.PLACE_MINIMAP }, { "free", L.PLACE_FREE }, { "portrait", L.PET_PORTRAIT } }, P),
            choice(L.OPT_PET_SIDE, nil, panel, "petSide", { { "left", L.SIDE_LEFT }, { "right", L.SIDE_RIGHT } }, { "petbar", "petside" }, nil, true),
            slider(L.OPT_PET_SIDEWIDTH, L.OPT_PET_SIDEWIDTH_TIP, "petSideWidth", 15, 50, 1, " %", { "petbar", "petside" }, nil, true),
            slider(L.OPT_PET_WIDTH, nil, "petWidth", 40, 100, 5, " %", { "petbar", "petattach" }, nil, true),
            slider(L.OPT_PET_FREEW, nil, "petFreeWidth", 60, 400, 10, " px", { "petbar", "petfree" }, nil, true),
            slider(L.OPT_PET_FREEH, nil, "petFreeHeight", 6, 20, 1, " px", { "petbar", "petfree" }, nil, true),
            buttons(L.OPT_POS_RESET, nil, { { L.OPT_WARN_MOVE_BTN, function() ns.Mover:Toggle(true) end },
                { L.OPT_WARN_RESET_BTN, function() ns.db.panel.petPos = nil; ns.Refresh() end } }, { "petbar", "petfree" }),
            slider(L.OPT_PET_PORTW, L.OPT_PET_PORTW_TIP, "petPortraitWidth", 0, 300, 5, " px", { "petbar", "petportrait" }, nil, true),
            slider(L.OPT_PET_FREEH, nil, "petPortraitHeight", 6, 20, 1, " px", { "petbar", "petportrait" }, nil, true),
            slider(L.OPT_PET_PORTX, nil, "petPortraitX", -150, 150, 1, " px", { "petbar", "petportrait" }, nil, true),
            slider(L.OPT_PET_PORTY, nil, "petPortraitY", -60, 60, 1, " px", { "petbar", "petportrait" }, nil, true),
            header(L.SEC_LOOK),
            choice(L.OPT_PET_COLOR, nil, panel, "petColor", colors, P),
            choice(L.OPT_TICKS, nil, panel, "petTicks", ticks, P),
        }
    end },
    } },
    -- action buttons: state colours and cooldown numbers
    { group = "NAV_INTERFACE", icon = "Interface\\Icons\\Ability_Marksmanship", title = "SEC_BUTTONS", build = function()
        local colors = function() return ns.db.buttons.colors end
        local cdColors = function() return ns.db.buttons.cdColors end
        local R, C = { "btnrange" }, { "btncd" }
        return {
            { type = "text", label = L.BTN_TIP },
            { type = "buttonpreview" },
            header(L.SEC_BTN_COLORS),
            check(L.OPT_BTN_RANGE, L.OPT_BTN_RANGE_TIP, btns, "range"),
            color(L.BTN_COL_RANGE, nil, colors, "range", R),
            color(L.BTN_COL_MANA, nil, colors, "mana", R),
            color(L.BTN_COL_UNUSABLE, nil, colors, "unusable", R),
            header(L.SEC_BTN_CD),
            check(L.OPT_BTN_CD, L.OPT_BTN_CD_TIP, btns, "cd"),
            slider(L.OPT_XPTEXT_SIZE, nil, "cdSize", 8, 32, 1, " pt", C, btns),
            choice(L.OPT_BTN_OUTLINE, nil, btns, "cdOutline", { { "none", L.NONE }, { "OUTLINE", L.OUTLINE_NORMAL },
                { "THICKOUTLINE", L.OUTLINE_THICK } }, C),
            check(L.OPT_BTN_SHADOW, nil, btns, "cdShadow", C),
            slider(L.OPT_BTN_MIN, L.OPT_BTN_MIN_TIP, "cdMin", 0, 10, 0.5, " s", C, btns),
            slider(L.OPT_BTN_SHORT, L.OPT_BTN_SHORT_TIP, "cdShort", 1, 15, 1, " s", C, btns),
            check(L.OPT_BTN_DECIMALS, nil, btns, "cdDecimals", C),
            color(L.BTN_COL_LONG, nil, cdColors, "long", C),
            color(L.BTN_COL_MID, nil, cdColors, "mid", C),
            color(L.BTN_COL_SHORT, nil, cdColors, "short", C),
        }
    end },
    -- cast bars of target and focus
    { group = "NAV_INTERFACE", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", title = "SEC_CASTBAR", build = function()
        local list = { { type = "text", label = L.CB_TIP } }
        local modes = { { "default", L.CB_DEFAULT }, { "hide", L.CB_HIDE }, { "free", L.PLACE_FREE } }
        for _, def in ipairs(ns.CastBar.BARS) do
            if def.key == "target" or ns.CastBar.Has(def.key) then
                local key = def.key
                list[#list + 1] = header(L[def.label])
                list[#list + 1] = choice(L.OPT_CB_MODE, nil, castbar, key, modes)
                list[#list + 1] = slider(L.OPT_CB_SCALE, nil, key .. "Scale", 0.5, 2, 0.05, "x", { "cb" .. key }, castbar, true)
                list[#list + 1] = buttons(L.OPT_POS_RESET, nil, { { L.OPT_WARN_MOVE_BTN, function() ns.Mover:Toggle(true) end },
                    { L.OPT_WARN_RESET_BTN, function() ns.db.castbar[key .. "Pos"] = nil; ns.Refresh() end } }, { "cb" .. key })
            end
        end
        return list
    end },
    { group = "NAV_INTERFACE", icon = "Interface\\Icons\\INV_Misc_Map_01", title = "WZ_MINIMAP", build = function()
        return {
            header(L.SEC_MM_SHAPE),
            choice(L.OPT_MM_SHAPE, L.OPT_MM_SHAPE_TIP, minimap, "shape", { { "round", L.MM_ROUND }, { "square", L.MM_SQUARE } }),
            choice(L.OPT_MM_LOOK, L.OPT_MM_LOOK_TIP, minimap, "look", { { "classic", L.SKIN_CLASSIC }, { "modern", L.SKIN_MODERN } },
                { "mmsquare" }, nil, true),
            header(L.SEC_MM_SHOW),
            check(L.OPT_MM_ZONE, L.OPT_MM_SHOW_TIP, minimap, "zone"),
            check(L.OPT_MM_CLOCK, L.OPT_MM_SHOW_TIP, opts, "minimapClock"),
            check(L.OPT_MM_CALENDAR, L.OPT_MM_SHOW_TIP, minimap, "calendar"),
            check(L.OPT_MM_TRACKING, L.OPT_MM_SHOW_TIP, minimap, "tracking"),
            check(L.OPT_MM_ADDONS, L.OPT_MM_SHOW_TIP, minimap, "addons"),
            check(L.OPT_MM_COORDS, L.OPT_MM_SHOW_TIP, minimap, "coords"),
            header(L.SEC_MM_BUTTONS),
            { type = "text", label = L.WZ_MINIMAP_TEXT },
            check(L.OPT_COLLECT, L.OPT_COLLECT_TIP, panel, "collectButtons", { "panel" }),
            check(L.OPT_FLOATING, L.OPT_FLOATING_TIP, minimap, "floating", { "noPanel" }),
            check(L.OPT_MM_BUTTON, L.OPT_MM_BUTTON_TIP, minimap, "show", { "noCollect" }),
        }
    end },

    -- Automation -------------------------------------------------------------------------------------------------
    { group = "NAV_AUTOMATION", icon = "Interface\\Icons\\Spell_Arcane_StudentOfMagic", title = "SEC_ACTIONBAR",
        master = { actionbar, "enabled", tip = "OPT_AB_TIP" }, build = function()
        local A = { "actionbar" }
        return {
            header(L.SEC_AUTOMATIC),
            check(L.OPT_AB_PLACE, L.OPT_AB_PLACE_TIP, actionbar, "placeNew", A),
            check(L.OPT_AB_RANKS, L.OPT_AB_RANKS_TIP, actionbar, "replaceRanks", A),
            check(L.OPT_AB_GENERAL, L.OPT_AB_GENERAL_TIP, actionbar, "general", A),
            check(L.OPT_AB_MSG, nil, actionbar, "messages", A),
            header(L.SEC_BY_HAND),
            buttons(L.AB_BTN_RANKS, L.AB_BTN_RANKS_TIP, { { L.AB_BTN_RUN, function() ns.ActionBar:UpdateRanks() end } }),
            buttons(L.AB_BTN_PLACE, L.AB_BTN_PLACE_TIP, { { L.AB_BTN_RUN, function() ns.ActionBar:PlaceMissing() end } }),
        }
    end },
    { group = "NAV_AUTOMATION", icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue", title = "SEC_LOOTOPT", tabsByHeader = true,
        master = { lootopt, "enabled", tip = "OPT_LOOTOPT_TIP" }, build = function()
        local O2 = { "lootopt" }
        local specs = { { "auto", L.LO_SPEC_AUTO } }
        for _, p in ipairs(ns.LootOpt.Profiles()) do specs[#specs + 1] = { p.key, p.label } end
        local list = {
            header(L.LO_SEC_SHOW),
            check(L.OPT_LO_TOOLTIP, L.OPT_LO_TOOLTIP_TIP, lootopt, "tooltip", O2),
            check(L.OPT_LO_UPGRADE, L.OPT_LO_UPGRADE_TIP, lootopt, "upgrade", O2),
            slider(L.OPT_LO_THRESHOLD, L.OPT_LO_THRESHOLD_TIP, "threshold", 1, 25, 1, " %", O2, lootopt, true),
            buttons(L.LO_IGNORED_UP, L.LO_IGNORED_UP_TIP, { { L.LO_RESET, function() ns.LootOpt:ResetIgnored("upgrade") end } }, O2),
            check(L.OPT_LO_FULL, L.OPT_LO_FULL_TIP, lootopt, "bagsFull", O2),
            buttons(L.LO_IGNORED_FULL, L.LO_IGNORED_FULL_TIP, { { L.LO_RESET, function() ns.LootOpt:ResetIgnored("full") end } }, O2),
            header(L.LO_SEC_RATING),
            choice(L.OPT_LO_SPEC, L.OPT_LO_SPEC_TIP, lootopt, "spec", specs, O2),
            { type = "text", label = L.LO_WEIGHTS_TIP },
        }
        for _, s in ipairs(weightSpecs()) do list[#list + 1] = s end
        list[#list + 1] = buttons(L.LO_SHARE, L.LO_SHARE_TIP, {
            { L.LO_EXPORT, function()
                local LO = ns.LootOpt
                ns.UI.CopyLink(L.LO_EXPORT_TITLE:format(UnitClass("player") or "?", LO.ProfileLabel(LO.Profile())), LO.Export())
            end },
            { L.LO_IMPORT, function()
                local LO = ns.LootOpt
                ns.UI.AskText(L.LO_IMPORT_TITLE:format(UnitClass("player") or "?", LO.ProfileLabel(LO.Profile())), function(text)
                    local n = ns.LootOpt.Import(text)
                    print("|cffffd100" .. ns.title .. "|r: " .. (n and L.LO_IMPORT_OK:format(n) or L.LO_IMPORT_BAD))
                    if n and O.frame and O.frame:IsShown() then O:Render(true) end
                end)
            end },
        }, O2)
        list[#list + 1] = buttons(L.LO_RESET_WEIGHTS, L.LO_RESET_TIP, {
            { L.LO_RESET, function()
                local cls = select(2, UnitClass("player"))
                local d = ns.db.lootopt
                local profile = ns.LootOpt.Profile()
                if d.weights[cls] then d.weights[cls][profile] = nil end
                if type(d.caps[cls]) == "table" then d.caps[cls][profile] = nil end
            end },
        }, O2)
        return list
    end },
    { group = "NAV_AUTOMATION", icon = "Interface\\Icons\\INV_Scroll_03", title = "SEC_GAMEPLAY",
        master = { gameplay, "enabled", tip = "OPT_GAMEPLAY_TIP" }, build = function()
        local G = { "gameplay" }
        return {
            header(L.WZ_QUESTS),
            check(L.OPT_GP_ACCEPT, L.OPT_GP_SHIFT, gameplay, "questAccept", G),
            check(L.OPT_GP_TURNIN, L.OPT_GP_TURNIN_TIP, gameplay, "questTurnIn", G),
            check(L.OPT_GP_REWARD, L.OPT_GP_REWARD_TIP, gameplay, "rewardValue", G),
            check(L.OPT_GP_GOSSIP, L.OPT_GP_GOSSIP_TIP, gameplay, "gossip", G),
            header(L.WZ_MERCHANT),
            check(L.OPT_GP_SELL, L.OPT_GP_SHIFT, gameplay, "sellGrey", G),
            check(L.OPT_GP_REPAIR, nil, gameplay, "repair", G),
            check(L.OPT_GP_GUILD, nil, gameplay, "guildRepair", G, { indent = true }),
            header(L.SEC_LOOT),
            check(L.OPT_GP_FASTLOOT, L.OPT_GP_FASTLOOT_TIP, gameplay, "fastLoot", G),
            bind({ type = "check", label = L.OPT_GP_SPARKLE, tip = L.OPT_GP_SPARKLE_TIP, needs = G, restart = true }, gameplay, "lootSparkle",
                function() ns.Gameplay:SparkleChanged() end),
            header(L.SEC_MAIL),
            check(L.OPT_GP_MAILALTS, L.MAIL_ALTS_TIP, gameplay, "mailAlts", G),
        }
    end },

    -- Notices ----------------------------------------------------------------------------------------------------
    { group = "NAV_NOTICES", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", title = "SEC_WARNINGS", tabsByHeader = true,
        master = { warnings, "enabled", tip = "OPT_WARNINGS_TIP" }, build = function()
        local Wd = { "warnings" }
        local sounds = { { "none", L.NONE } }
        for _, k in ipairs(ns.Warnings.SOUND_ORDER) do sounds[#sounds + 1] = { k, L["SND_" .. k:upper()] } end
        local function sound(cat, need)
            return choice(L.OPT_WARN_SOUND_CAT, L.OPT_WARN_SOUND_TIP, warnings, "sound" .. cat, sounds, need,
                function() ns.Warnings.PlaySound(ns.db.warnings["sound" .. cat]) end, true)
        end
        return {
            header(L.WARN_GROUP_BUFFS),
            check(L.OPT_WARN_CLASS, nil, warnings, "classBuffs", Wd),
            sound("Class", { "warnings", "wclass" }),
            check(L.OPT_WARN_EXPIRING, nil, warnings, "expiring", Wd),
            sound("Expiring", { "warnings", "wexpiring" }),
            header(L.WARN_GROUP_CONS),
            check(L.OPT_WARN_FOOD, L.OPT_WARN_FOOD_TIP, warnings, "food", Wd),
            choice(L.OPT_WARN_WHERE, nil, warnings, "foodWhere", WHERE_FOOD(), { "warnings", "food" }, nil, true),
            sound("Food", { "warnings", "food" }),
            check(L.OPT_WARN_FLASK, L.OPT_WARN_FLASK_TIP, warnings, "flask", Wd),
            choice(L.OPT_WARN_WHERE, nil, warnings, "flaskWhere", WHERE_FLASK(), { "warnings", "flask" }, nil, true),
            sound("Flask", { "warnings", "flask" }),
            check(L.OPT_WARN_WEAPON, L.OPT_WARN_WEAPON_TIP, warnings, "weapon", Wd),
            sound("Weapon", { "warnings", "wweapon" }),
            check(L.OPT_WARN_AMMO, L.OPT_WARN_AMMO_TIP, warnings, "ammo", { "warnings", "hunter" }),
            slider(L.OPT_WARN_AMMO_MIN, L.OPT_WARN_AMMO_MIN_TIP, "ammoMin", 100, 800, 50, "", { "warnings", "ammo", "hunter" }, warnings, true),
            sound("Ammo", { "warnings", "ammo", "hunter" }),
            header(L.SEC_BEHAVIOUR),
            check(L.OPT_WARN_COMBAT, L.OPT_WARN_COMBAT_TIP, warnings, "combat", Wd),
            check(L.OPT_WARN_WINDOWS, L.OPT_WARN_WINDOWS_TIP, warnings, "hideWithWindows", Wd),
            check(L.OPT_WARN_RESTING, L.OPT_WARN_RESTING_TIP, warnings, "hideResting", Wd),
            choice(L.OPT_WARN_ANIM, L.OPT_WARN_ANIM_TIP, warnings, "anim", { { "pulse", L.ANIM_PULSE }, { "bounce", L.ANIM_BOUNCE },
                { "flash", L.ANIM_FLASH }, { "wave", L.ANIM_WAVE }, { "none", L.NONE } }, Wd, function() ns.Warnings:PreviewAnim() end),
            choice(L.OPT_WARN_REPEAT, L.OPT_WARN_REPEAT_TIP, warnings, "animRepeat", { { "once", L.REPEAT_ONCE },
                { "30", L.REPEAT_HALFMIN }, { "always", L.REPEAT_ALWAYS } }, Wd, nil, true),
            header(L.SEC_LOOK),
            choice(L.OPT_WARN_SHAPE, nil, warnings, "iconShape", SHAPES(), Wd),
            slider(L.OPT_WARN_SCALE, nil, "scale", 0.5, 2, 0.05, "x", Wd, warnings),
            buttons(L.OPT_WARN_MOVE, L.OPT_WARN_MOVE_TIP, {
                { L.OPT_WARN_MOVE_BTN, function() ns.Mover:Toggle(true) end },
                { L.OPT_WARN_PREVIEW_BTN, function()
                    if not ns.Warnings.moving then ns.Warnings:SetMoving(true) end
                    ns.Warnings:PreviewAnim()
                end },
                { L.OPT_WARN_RESET_BTN, function() ns.Warnings:ResetPosition() end },
            }, Wd),
        }
    end },
    -- questing together
    { group = "NAV_NOTICES", icon = "Interface\\Icons\\INV_Misc_Book_08", title = "SEC_TOGETHER", tabsByHeader = true,
        master = { together, "enabled", tip = "OPT_TOG_TIP" }, build = function()
        local Tg = { "together" }
        local dev = ns.name == "ForeverQoLPanel_Dev"
        return {
            { type = "text", label = L.TOG_TEXT },
            -- the window
            header(L.TOG_SEC_WINDOW),
            check(L.OPT_TOG_WINDOW, L.OPT_TOG_WINDOW_TIP, together, "window", Tg),
            check(L.OPT_TOG_LOCKED, nil, together, "locked", Tg, { indent = true }),
            check(L.OPT_TOG_TRACKER, L.OPT_TOG_TRACKER_TIP, together, "minimizeTracker", Tg),
            buttons(L.OPT_POS_RESET, nil, { { L.OPT_WARN_RESET_BTN, function()
                ns.db.together.pos, ns.db.together.xpPos, ns.db.together.width, ns.db.together.maxHeight = nil, nil, nil, nil
                ns.Together:Changed()
            end } }, Tg),
            -- the group's XP (with bag slots and ammunition)
            header(L.SEC_GROUPXP),
            check(L.OPT_TOG_XPWIN, L.OPT_TOG_XPWIN_TIP, together, "xpWindow", Tg),
            check(L.OPT_TOG_XPSEP, L.OPT_TOG_XPSEP_TIP, together, "xpSeparate", Tg, { indent = true }),
            check(L.OPT_TOG_XPLOCKED, nil, together, "xpLocked", Tg, { indent = true }),
            -- sharing quests
            header(L.TOG_SEC_SHARE),
            check(L.OPT_TOG_ACCEPT, L.OPT_TOG_ACCEPT_TIP, together, "autoAccept", Tg),
            -- done and turned in
            header(L.TOG_SEC_TURNIN),
            check(L.OPT_TOG_SOUNDDONE, L.OPT_TOG_SOUNDDONE_TIP, together, "soundAllDone", Tg),
            check(L.OPT_TOG_TURNIN, L.OPT_TOG_TURNIN_TIP, together, "turnInWatch", Tg),
            check(L.OPT_TOG_SOUNDTURNIN, L.OPT_TOG_SOUNDTURNIN_TIP, together, "soundTurnIn", { "together", "togturnin" }, { indent = true }),
            -- the test with a made-up partner: only in the development copy
            dev and header(L.SEC_RADAR_TEST) or nil,
            dev and buttons(L.OPT_RADAR_TEST, L.OPT_TOG_TEST_TIP, {
                { ns.Together.testing and L.TOG_TEST_STOP or L.TOG_TEST_START, function() ns.Together:Test(); O:Render(true) end },
                { L.TOG_TEST_ADD, function() ns.Together:TestAdd() end },
                { L.TOG_TEST_UPDATE, function() ns.Together:TestUpdate() end },
                { L.TOG_TEST_FINISH, function() ns.Together:TestFinish() end } }, Tg) or nil,
            dev and buttons(L.OPT_TOG_TEST_TURNIN, L.OPT_TOG_TEST_TURNIN_TIP, {
                { L.TOG_TEST_PARTNER_TURNIN, function() ns.Together:TestPartnerTurnIn() end },
                { L.TOG_TEST_MY_TURNIN, function() ns.Together:TestMyTurnIn() end },
                { L.TOG_TEST_FAR, function() ns.Together:TestFar() end } }, Tg) or nil,
        }
    end },
    -- enemy radar
    { group = "NAV_NOTICES", icon = "Interface\\Icons\\Ability_Hunter_EagleEye", title = "SEC_RADAR", tabsByHeader = true,
        master = { radar, "enabled", tip = "OPT_RADAR_TIP" }, build = function()
        local Rd = { "radar" }
        local sounds = { { "none", L.NONE } }
        for _, k in ipairs(ns.Warnings.SOUND_ORDER) do sounds[#sounds + 1] = { k, L["SND_" .. k:upper()] } end
        return {
            { type = "text", label = L.RADAR_TEXT },
            header(L.SEC_RADAR_TEST),
            buttons(L.OPT_RADAR_TEST, L.OPT_RADAR_TEST_TIP, {
                { L.TEST_SEEN, function() ns.Radar:Test("seen") end },
                { L.TEST_STEALTH, function() ns.Radar:Test("stealth") end },
                { L.TEST_TARGET, function() ns.Radar:Test("target") end },
                { L.TEST_MIXED, function() ns.Radar:Test("mixed") end } }, Rd),
            header(L.SEC_RADAR_DETECT),
            slider(L.OPT_RADAR_TIMEOUT, L.OPT_RADAR_TIMEOUT_TIP, "timeout", 15, 300, 15, " s", Rd, radar),
            check(L.OPT_RADAR_RESTING, nil, radar, "quietResting", Rd),
            choice(L.OPT_RADAR_BG, L.OPT_RADAR_BG_TIP, radar, "bgMode", { { "off", L.RADAR_BG_OFF },
                { "stealth", L.RADAR_BG_STEALTH }, { "all", L.RADAR_BG_ALL } }, Rd),
            header(L.SEC_RADAR_ALERTS),
            choice(L.OPT_RADAR_SOUND, nil, radar, "sound", sounds, Rd, function() ns.Warnings.PlaySound(ns.db.radar.sound) end),
            choice(L.OPT_RADAR_STEALTH_SOUND, nil, radar, "stealthSound", sounds, Rd, function() ns.Warnings.PlaySound(ns.db.radar.stealthSound) end),
            check(L.OPT_RADAR_STEALTH_WARN, L.OPT_RADAR_STEALTH_WARN_TIP, radar, "stealthWarning", Rd),
            check(L.OPT_RADAR_TARGETME, L.OPT_RADAR_TARGETME_TIP, radar, "targetMe", Rd),
            choice(L.OPT_RADAR_TARGET_SOUND, nil, radar, "targetSound", sounds, { "radar", "radartm" },
                function() ns.Warnings.PlaySound(ns.db.radar.targetSound) end, true),
            check(L.OPT_RADAR_TARGET_WARN, nil, radar, "targetWarning", { "radar", "radartm" }, { indent = true }),
            buttons(L.OPT_RADAR_KEY:format(ns.Radar.BindingText("stealth")), L.OPT_RADAR_KEY_TIP, {
                { L.KEY_SET, function() ns.Radar:CaptureBinding("stealth", function() O:Render(true) end) end },
                { L.KEY_CLEAR, function() ns.Radar:ClearBinding("stealth"); O:Render(true) end } }, Rd),
            buttons(L.OPT_RADAR_KEY_TM:format(ns.Radar.BindingText("target")), L.OPT_RADAR_KEY_TIP, {
                { L.KEY_SET, function() ns.Radar:CaptureBinding("target", function() O:Render(true) end) end },
                { L.KEY_CLEAR, function() ns.Radar:ClearBinding("target"); O:Render(true) end } }, { "radar", "radartm" }),
            buttons(L.OPT_WARN_MOVE, nil, { { L.OPT_WARN_MOVE_BTN, function() ns.Radar:StealthFrame(); ns.Mover:Toggle(true) end },
                { L.OPT_WARN_RESET_BTN, function() ns.db.radar.stealthPos, ns.db.radar.targetPos = nil, nil; ns.Radar:PlaceStealth() end } }, Rd),
            header(L.SEC_RADAR_SHARE),
            check(L.OPT_RADAR_LISTEN, L.OPT_RADAR_LISTEN_TIP, radar, "shareListen", Rd),
            check(L.OPT_RADAR_SEND, L.OPT_RADAR_SEND_TIP, radar, "shareSend", Rd),
            check(L.OPT_RADAR_SENDSPY, L.OPT_RADAR_SENDSPY_TIP, radar, "shareSpy", Rd, { indent = true }),
            header(L.SEC_RADAR_LIST),
            check(L.OPT_RADAR_AUTOLIST, L.OPT_RADAR_AUTOLIST_TIP, radar, "autoList", Rd),
            slider(L.OPT_RADAR_ROWS, nil, "listRows", 3, 20, 1, "", Rd, radar),
            check(L.OPT_RADAR_HIDEEMPTY, nil, radar, "hideEmpty", Rd),
        }
    end },
    { group = "NAV_NOTICES", icon = "Interface\\Icons\\INV_Misc_Coin_02", title = "SEC_LOOTTEXT",
        master = { gameplay, "lootText", tip = "OPT_GP_LOOTTEXT", needs = { "gameplay" } }, build = function()
        local T = { "gameplay", "lootText" }
        return {
            header(L.SEC_LOOK),
            choice(L.OPT_WARN_SHAPE, nil, gameplay, "lootShape", SHAPES(), T),
            slider(L.OPT_WARN_SCALE, nil, "lootScale", 0.5, 2, 0.05, "x", T, gameplay),
            buttons(L.OPT_WARN_MOVE, L.OPT_LOOT_MOVE_TIP, {
                { L.OPT_WARN_MOVE_BTN, function() ns.Mover:Toggle(true) end },
                { L.OPT_WARN_RESET_BTN, function() ns.Gameplay:ResetLootPosition() end },
            }, T),
        }
    end },
    { group = "NAV_NOTICES", icon = "Interface\\Icons\\Ability_Hunter_SniperShot", title = "SEC_NAMEPLATES",
        master = { nameplates, "enabled", tip = "OPT_NP_TIP" }, build = function()
        local N = { "nameplates" }
        return {
            { type = "text", label = L.WZ_NP_TEXT },
            check(L.OPT_NP_PROGRESS, nil, nameplates, "progress", N),
            header(L.SEC_LOOK),
            choice(L.OPT_NP_POS, nil, nameplates, "position", { { "left", L.NP_LEFT }, { "right", L.NP_RIGHT },
                { "top", L.NP_TOP }, { "topleft", L.NP_TOPLEFT }, { "topright", L.NP_TOPRIGHT } }, N),
            slider(L.OPT_NP_SIZE, nil, "size", 12, 36, 1, " px", N, nameplates),
            slider(L.OPT_NP_X, L.OPT_NP_OFFSET_TIP, "x", -40, 40, 1, " px", N, nameplates),
            slider(L.OPT_NP_Y, L.OPT_NP_OFFSET_TIP, "y", -40, 40, 1, " px", N, nameplates),
        }
    end },
    { group = "NAV_NOTICES", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", title = "SEC_TOOLTIP",
        master = { tooltip, "enabled", tip = "OPT_TOOLTIP_TIP" }, build = function()
        local Td = { "tooltip" }
        return {
            { type = "text", label = L.WZ_TT_TEXT },
            check(L.OPT_TT_SELL, nil, tooltip, "sellValue", Td),
            check(L.OPT_TT_COUNTS, L.OPT_TT_COUNTS_TIP, tooltip, "counts", Td),
            check(L.OPT_TT_GATHER, L.OPT_TT_GATHER_TIP, tooltip, "gather", Td),
            check(L.OPT_TT_BEASTS, L.OPT_TT_BEASTS_TIP, tooltip, "beasts", { "tooltip", "hunter" }),
            check(L.OPT_TT_DE, L.OPT_TT_DE_TIP, tooltip, "disenchant", Td),
            check(L.OPT_TT_DE_ONLY, nil, tooltip, "deOnlyEnchanter", { "tooltip", "disenchant" }, { indent = true }),
        }
    end },

    -- More addons from us: last in the list, its own page
    { group = "NAV_MORE", icon = "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", title = "SEC_MORE_ADDONS",
        build = function() return O.MoreAddons() end },
}
O.PAGES = PAGES

local isOff
function isOff(p)
    -- a page of tabs is off when every tab is
    if p.tabs then
        for _, t in ipairs(p.tabs) do if not isOff(t) then return false end end
        return true
    end
    if p.master then
        local missing = p.master.needs and ns.UI.Missing(p.master.needs)
        return missing ~= nil or not p.master[1]()[p.master[2]]
    end
    return p.off and p.off() or false
end

function O:Render(keepScroll)
    local f = self.frame
    -- texts that are set here, not at creation: the language may change while the window is open
    if f.closeButton then f.closeButton:SetText(L.CLOSE_BTN) end
    if f.wizardButton then f.wizardButton:SetText(L.OPT_MOVE) end
    if f.SetSearchHint then f:SetSearchHint(L.SEARCH_HINT) end
    local page = PAGES[self.index]
    -- list with group titles; navIndex -> page index
    local nav, map, group = {}, {}, nil
    local fresh = O.FreshSettings()
    self.fresh = fresh
    for i, p in ipairs(PAGES) do
        if p.group ~= group then
            group = p.group
            nav[#nav + 1] = { header = L[p.group] }
        end
        nav[#nav + 1] = { icon = p.icon, title = L[p.title], off = isOff(p), fresh = O.PageIsNew(p, fresh) }
        map[#nav] = i
        if i == self.index then self.navActive = #nav end
    end
    local searching = self.query and self.query ~= ""
    f:SetNav(nav, not searching and self.navActive or nil, function(n)
        if not map[n] then return end
        -- picking a page leaves the search
        if f.search and f.search:GetText() ~= "" then O.query = ""; f.search:SetText(""); f.search:ClearFocus() end
        O:Show(map[n])
    end)
    if searching then return self:RenderSearch(keepScroll) end
    -- a page of tabs: the chosen tab (kept per page) brings its switch and settings
    local tabs
    if page.tabs then
        self.tabOf = self.tabOf or {}
        local t = math.min(self.tabOf[self.index] or 1, #page.tabs)
        local labels = {}
        local fresh = self.fresh or O.FreshSettings()
        for n, tab in ipairs(page.tabs) do labels[n] = { title = L[tab.title], off = isOff(tab), fresh = O.PageIsNew(tab, fresh) } end
        tabs = { items = labels, active = t, onClick = function(n)
            O.tabOf[O.index] = n
            O:Render()
            f:FadeContent()
        end }
        local group = page.group
        page = page.tabs[t]
        page = setmetatable({ group = group, icon = page.icon or PAGES[self.index].icon, title = PAGES[self.index].title }, { __index = page })
    end
    local toggle
    if page.master then
        local m = page.master
        local missing = m.needs and ns.UI.Missing(m.needs)
        toggle = { get = function() return m[1]()[m[2]] end,
            set = function(v) m[1]()[m[2]] = v; if m.reload then O.pendingReload = true end end,
            tip = (m.tip and L[m.tip] or "") .. (m.reload and ("\n|cffa0a0a0" .. L.NEEDS_RELOAD .. "|r") or "")
                .. (missing and ("\n|cffff8a6a" .. missing .. "|r") or ""),
            onChange = function() O:Render(true) end }
    end
    f:SetHead(page.icon, L[page.title], L[page.group], nil, toggle, tabs)
    local scroll = keepScroll and f.scroll.GetVerticalScroll and f.scroll:GetVerticalScroll()
    local specs = O.Compact(page.build())
    O.MarkPage(page, specs, self.fresh or O.FreshSettings())
    -- a long page split into tabs at its section headers (text before the first header shows on every tab)
    if page.tabsByHeader then
        local lead, parts = {}, {}
        for _, s in ipairs(specs) do
            if s.type == "header" then parts[#parts + 1] = { title = s.label, items = { s } }
            elseif #parts == 0 then lead[#lead + 1] = s
            else table.insert(parts[#parts].items, s) end
        end
        if #parts > 1 then
            self.tabOf = self.tabOf or {}
            local t = math.min(self.tabOf[self.index] or 1, #parts)
            local labels = {}
            for n, part in ipairs(parts) do
                -- a tab holding a new setting carries the mark too (on a page new as a whole none is marked)
                local fresh = false
                for _, s in ipairs(part.items) do if s.isNew then fresh = true end end
                labels[n] = { title = part.title, fresh = fresh }
            end
            f:SetTabs({ items = labels, active = t, onClick = function(n)
                O.tabOf[O.index] = n
                O:Render()
                f:FadeContent()
            end })
            specs = lead
            for _, s in ipairs(parts[t].items) do specs[#specs + 1] = s end
        end
    end
    f:Render(O.Track(specs), function() O:Render(true) end)
    if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(scroll or 0) end
end

-- Search: every setting whose name or description contains the words, from all pages, under the page's title.
-- A page whose title matches brings its on/off switch and all its settings.
local function matches(text, words)
    if not text then return false end
    text = text:lower()
    for _, w in ipairs(words) do
        if not text:find(w, 1, true) then return false end
    end
    return true
end

function O:RenderSearch(keepScroll)
    local f = self.frame
    local words = {}
    for w in self.query:lower():gmatch("%S+") do words[#words + 1] = w end
    local list, count = {}, 0
    -- tabs count as pages of their own, titled with page and tab
    local all = {}
    for _, p in ipairs(PAGES) do
        if p.tabs then
            for _, t in ipairs(p.tabs) do
                all[#all + 1] = setmetatable({ searchTitle = L[p.title] .. " – " .. L[t.title] }, { __index = t })
            end
        else
            all[#all + 1] = p
        end
    end
    for _, p in ipairs(all) do
        local title = p.searchTitle or L[p.title]
        local whole = matches(title, words)
        local found = {}
        if whole and p.master then
            local m = p.master
            local s = { type = "check", label = L.OPT_ENABLED, tip = m.tip and L[m.tip], needs = m.needs, reload = m.reload,
                get = function() return m[1]()[m[2]] end, set = function(v) m[1]()[m[2]] = v end }
            O.Track({ s })
            found[#found + 1] = s
        end
        local specs = O.Compact(p.build())
        O.MarkPage(p, specs, self.fresh or O.FreshSettings())
        for _, s in ipairs(specs) do
            if s.type ~= "header" and s.type ~= "text" and (whole or matches(s.label, words) or matches(s.tip, words)) then
                found[#found + 1] = s
            end
        end
        if #found > 0 then
            list[#list + 1] = { type = "header", label = title }
            for _, s in ipairs(found) do
                -- a sub-setting found alone loses its indent
                if not whole and s.indent then
                    local c = {}
                    for k, v in pairs(s) do c[k] = v end
                    c.indent = nil
                    s = c
                end
                list[#list + 1] = s
                count = count + 1
            end
        end
    end
    if count == 0 then list[1] = { type = "text", label = L.SEARCH_NONE } end
    f:SetHead("Interface\\Icons\\INV_Misc_Spyglass_02", L.SEARCH_TITLE, L.SEARCH_RESULTS:format(count))
    local scroll = keepScroll and f.scroll.GetVerticalScroll and f.scroll:GetVerticalScroll()
    f:Render(O.Track(list), function() O:Render(true) end)
    if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(scroll or 0) end
end

-- Settings that only take effect after reloading the interface (reload = true) note it when changed; closing the
-- window then asks whether to reload now. A game restart (the loot sparkle) is said there too.
function O.Track(specs)
    for _, s in ipairs(specs) do
        if s.reload and s.set and not s.tracked then
            local set = s.set
            s.set = function(v) set(v); O.pendingReload = true end
            s.tracked = true
        end
    end
    return specs
end

function O:AskReload()
    if ns.Mover and ns.Mover.active then return end   -- hidden for the move mode: asked on the real close
    local reload, restart = self.pendingReload, self.pendingRestart
    if not (reload or restart) or not StaticPopupDialogs then return end
    self.pendingReload, self.pendingRestart = nil, nil
    local text = reload and L.ASK_RELOAD or L.NOTE_RESTART
    if reload and restart then text = text .. "\n\n" .. L.NOTE_RESTART end
    StaticPopupDialogs.FQP_RELOAD = {
        text = ns.title .. "\n\n" .. text,
        button1 = reload and L.RELOAD_NOW or (OKAY or "OK"),
        button2 = reload and L.RELOAD_LATER or nil,
        OnAccept = function() if reload then ReloadUI() end end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("FQP_RELOAD")
end

function O:Show(i)
    self.index = i or self.index or 1
    self:Render()
    self.frame:FadeContent()
end

function O:Open(i)
    if not self.frame then
        local f = ns.UI.Window("ForeverQoLPanelOptions", { width = 800, height = 600 })
        local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        close:SetSize(120, 24)
        f.closeButton = close
        close:SetPoint("BOTTOMRIGHT", -12, 12)
        close:SetScript("OnClick", function() f:Hide() end)
        local wizard = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        wizard:SetSize(180, 24)
        f.wizardButton = wizard
        f.version = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.version:SetPoint("BOTTOM", 0, 18)
        f.version:SetText(ns.title .. " " .. ns.VERSION .. (ns.name == "ForeverQoLPanel_Dev" and "  (dev)" or ""))
        -- bottom left: the move mode (the setup wizard is on the General page)
        wizard:SetPoint("BOTTOMLEFT", 12, 12)
        wizard:SetScript("OnClick", function() ns.Mover:Toggle(true) end)
        f.onLayout = function() O:Render(true) end
        f:HookScript("OnHide", function() O:AskReload() end)
        f:EnableSearch(function(text)
            if text == (O.query or "") then return end
            O.query = text
            O:Render()
        end)
        self.frame = f
    end
    if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
    if ns.Wizard and ns.Wizard.frame then ns.Wizard.frame:Hide() end
    self:Show(i)
    self.frame:Show()
end

function O:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

-- Blizzard's settings: a page that points to the own window
local function registerStub()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local f = CreateFrame("Frame")
    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetSize(128, 128)
    f.logo:SetPoint("TOP", 0, -40)
    f.logo:SetTexture(ns.Tex("logo"))
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOP", f.logo, "BOTTOM", 0, -16)
    f.text:SetWidth(420)
    f:SetScript("OnShow", function(self)
        self.text:SetText(L.OPT_WINDOW_TEXT)
        self.button:SetText(L.OPT_OPEN_BTN)
    end)
    f.button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.button:SetSize(220, 28)
    f.button:SetPoint("TOP", f.text, "BOTTOM", 0, -16)
    f.button:SetScript("OnClick", function() O:Open() end)
    local category = Settings.RegisterCanvasLayoutCategory(f, ns.title)
    Settings.RegisterAddOnCategory(category)
    O.category = category
end

ns.OnLogin(function()
    ns.Debug.Call("Options:Stub", registerStub)
end)

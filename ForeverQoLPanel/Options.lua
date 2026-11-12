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

-- value accessors for a spec
local function bind(s, tbl, key, onChange)
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
local function slider(label, tip, key, min, max, step, suffix, needs, tbl)
    return bind({ type = "slider", label = label, tip = tip, min = min, max = max, step = step, suffix = suffix,
        needs = needs }, tbl or panel, key)
end
local function header(label) return { type = "header", label = label } end

local function buttons(label, tip, list, needs)
    return { type = "button", label = label, tip = tip, buttons = list, needs = needs }
end
local WHERE_FOOD = function() return { { "instance", L.WHERE_INSTANCE }, { "world", L.WHERE_WORLD } } end
local WHERE_FLASK = function() return { { "raid", L.WHERE_RAID }, { "instance", L.WHERE_INSTANCE }, { "world", L.WHERE_WORLD } } end
local SHAPES = function() return { { "panel", L.SHAPE_PANEL }, { "round", L.BORDER_ROUND }, { "square", L.BORDER_SQUARE },
    { "none", L.NONE } } end

-- Pages in groups (shown as titles in the list). A page with `master` gets the feature's on/off switch in its header,
-- the list greys out switched-off features. build() -> specs (UI.lua).
local PAGES = {
    -- General ----------------------------------------------------------------------------------------------------
    { group = "NAV_GENERAL", icon = "Interface\\Icons\\INV_Misc_Gear_01", title = "SEC_GENERAL", build = function()
        local langs = {}
        for _, l in ipairs(LANGUAGES) do langs[#langs + 1] = { l[1], l[2] or L.LANG_AUTO } end
        return {
            header(L.SEC_GENERAL),
            choice(L.OPT_LANGUAGE, L.OPT_LANGUAGE_TIP, root, "language", langs, nil, function(v) ns.SetLanguage(v) end),
            choice(L.OPT_MOTION, L.OPT_MOTION_TIP, root, "motion", { { "full", L.MOTION_FULL },
                { "reduced", L.MOTION_REDUCED }, { "off", L.MOTION_OFF } }),
            header(L.WZ_OPEN),
            buttons(L.WZ_OPEN, L.WZ_OPEN_TIP, { { L.WZ_OPEN_BTN, function() ns.Wizard:Open(true) end } }),
        }
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
        }
    end },
    { group = "NAV_INTERFACE", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", title = "SEC_ELEMENTS",
        off = function() return not ns.db.panel.enabled end, build = function()
        -- every element with its own settings right below it (indented, greyed while the element is off)
        local SUB = {
            zone = { { "zoneCoords", L.OPT_ZONE_COORDS } },
            xph = { { "xphTime", L.OPT_XPH_TIME, L.OPT_XPH_TIME_TIP } },
            clock = { { "serverTime", L.OPT_SERVER_TIME }, { "minimapClock", L.OPT_MM_CLOCK, nil, true } },
        }
        local items = function() return ns.db.panel.items end
        local list = { { type = "text", label = L.ITEMS_TIP }, header(L.SEC_SHOWN) }
        for _, key in ipairs(ns.defaults.panel.order) do
            list[#list + 1] = check(L["ITEM_" .. key], nil, items, key, { "panel" })
            for _, s in ipairs(SUB[key] or {}) do
                list[#list + 1] = check(s[2], s[3], opts, s[1], not s[4] and { "panel", key } or nil, { indent = true })
            end
        end
        return list
    end },
    { group = "NAV_INTERFACE", icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", title = "SEC_XPBAR",
        master = { panel, "xpbar", tip = "OPT_XPBAR_TIP", needs = { "panel" } }, build = function()
        local X = { "xpbar" }
        local ticks = { { 0, L.NONE } }
        for _, n in ipairs({ 5, 10, 20, 25 }) do ticks[#ticks + 1] = { n, L.TICKS_N:format(n) } end
        return {
            header(L.SEC_LAYOUT),
            choice(L.OPT_STYLE, L.OPT_STYLE_TIP, panel, "style", { { "edge", L.STYLE_EDGE }, { "rail", L.STYLE_RAIL } }, X),
            slider(L.OPT_GAP, L.OPT_GAP_TIP, "gap", 4, 40, 1, " px", { "xpbar", "rail" }),
            slider(L.OPT_WIDTH, L.OPT_WIDTH_TIP, "barWidth", 200, 2000, 10, " px", X),
            choice(L.OPT_TICKS, nil, panel, "ticks", ticks, X),
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
    { group = "NAV_INTERFACE", icon = "Interface\\Icons\\INV_Misc_Map_01", title = "WZ_MINIMAP", build = function()
        return {
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
        }
    end },

    -- Notices ----------------------------------------------------------------------------------------------------
    { group = "NAV_NOTICES", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", title = "SEC_WARNINGS",
        master = { warnings, "enabled", tip = "OPT_WARNINGS_TIP" }, build = function()
        local Wd = { "warnings" }
        return {
            header(L.WARN_GROUP_BUFFS),
            check(L.OPT_WARN_CLASS, nil, warnings, "classBuffs", Wd),
            check(L.OPT_WARN_EXPIRING, nil, warnings, "expiring", Wd),
            header(L.WARN_GROUP_CONS),
            check(L.OPT_WARN_FOOD, L.OPT_WARN_FOOD_TIP, warnings, "food", Wd),
            choice(L.OPT_WARN_WHERE, nil, warnings, "foodWhere", WHERE_FOOD(), { "warnings", "food" }, nil, true),
            check(L.OPT_WARN_FLASK, L.OPT_WARN_FLASK_TIP, warnings, "flask", Wd),
            choice(L.OPT_WARN_WHERE, nil, warnings, "flaskWhere", WHERE_FLASK(), { "warnings", "flask" }, nil, true),
            check(L.OPT_WARN_WEAPON, L.OPT_WARN_WEAPON_TIP, warnings, "weapon", Wd),
            header(L.SEC_BEHAVIOUR),
            check(L.OPT_WARN_COMBAT, L.OPT_WARN_COMBAT_TIP, warnings, "combat", Wd),
            check(L.OPT_WARN_SOUND, nil, warnings, "sound", Wd),
            check(L.OPT_WARN_WINDOWS, L.OPT_WARN_WINDOWS_TIP, warnings, "hideWithWindows", Wd),
            choice(L.OPT_WARN_ANIM, L.OPT_WARN_ANIM_TIP, warnings, "anim", { { "pulse", L.ANIM_PULSE }, { "bounce", L.ANIM_BOUNCE },
                { "flash", L.ANIM_FLASH }, { "wave", L.ANIM_WAVE }, { "none", L.NONE } }, Wd, function() ns.Warnings:PreviewAnim() end),
            choice(L.OPT_WARN_REPEAT, L.OPT_WARN_REPEAT_TIP, warnings, "animRepeat", { { "once", L.REPEAT_ONCE },
                { "30", L.REPEAT_HALFMIN }, { "always", L.REPEAT_ALWAYS } }, Wd, nil, true),
            header(L.SEC_LOOK),
            choice(L.OPT_WARN_SHAPE, nil, warnings, "iconShape", SHAPES(), Wd),
            slider(L.OPT_WARN_SCALE, nil, "scale", 0.5, 2, 0.05, "x", Wd, warnings),
            buttons(L.OPT_WARN_MOVE, L.OPT_WARN_MOVE_TIP, {
                { L.OPT_WARN_MOVE_BTN, function() ns.Warnings:SetMoving(not ns.Warnings.moving) end },
                { L.OPT_WARN_PREVIEW_BTN, function()
                    if not ns.Warnings.moving then ns.Warnings:SetMoving(true) end
                    ns.Warnings:PreviewAnim()
                end },
                { L.OPT_WARN_RESET_BTN, function() ns.Warnings:ResetPosition() end },
            }, Wd),
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
                { L.OPT_WARN_MOVE_BTN, function() ns.Gameplay:SetLootMoving(not ns.Gameplay.moving) end },
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
        }
    end },
}
O.PAGES = PAGES

local function isOff(p)
    if p.master then
        local missing = p.master.needs and ns.UI.Missing(p.master.needs)
        return missing ~= nil or not p.master[1]()[p.master[2]]
    end
    return p.off and p.off() or false
end

function O:Render(keepScroll)
    local f = self.frame
    local page = PAGES[self.index]
    -- list with group titles; navIndex -> page index
    local nav, map, group = {}, {}, nil
    for i, p in ipairs(PAGES) do
        if p.group ~= group then
            group = p.group
            nav[#nav + 1] = { header = L[p.group] }
        end
        nav[#nav + 1] = { icon = p.icon, title = L[p.title], off = isOff(p) }
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
    local toggle
    if page.master then
        local m = page.master
        local missing = m.needs and ns.UI.Missing(m.needs)
        toggle = { get = function() return m[1]()[m[2]] end, set = function(v) m[1]()[m[2]] = v end,
            tip = (m.tip and L[m.tip] or "") .. (m.reload and ("\n|cffa0a0a0" .. L.NEEDS_RELOAD .. "|r") or "")
                .. (missing and ("\n|cffff8a6a" .. missing .. "|r") or ""),
            onChange = function() O:Render(true) end }
    end
    f:SetHead(page.icon, L[page.title], L[page.group], nil, toggle)
    local scroll = keepScroll and f.scroll.GetVerticalScroll and f.scroll:GetVerticalScroll()
    f:Render(page.build(), function() O:Render(true) end)
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
    for _, p in ipairs(PAGES) do
        local title = L[p.title]
        local whole = matches(title, words)
        local found = {}
        if whole and p.master then
            local m = p.master
            local s = { type = "check", label = L.OPT_ENABLED, tip = m.tip and L[m.tip], needs = m.needs, reload = m.reload,
                get = function() return m[1]()[m[2]] end, set = function(v) m[1]()[m[2]] = v end }
            found[#found + 1] = s
        end
        for _, s in ipairs(p.build()) do
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
    f:Render(list, function() O:Render(true) end)
    if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(scroll or 0) end
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
        close:SetText(CLOSE or "Close")
        close:SetPoint("BOTTOMRIGHT", -12, 12)
        close:SetScript("OnClick", function() f:Hide() end)
        local wizard = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        wizard:SetSize(180, 24)
        wizard:SetText(L.WZ_OPEN)
        wizard:SetPoint("BOTTOMLEFT", 12, 12)
        wizard:SetScript("OnClick", function() ns.Wizard:Open(true) end)
        f.onLayout = function() O:Render(true) end
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
    f.text:SetText(L.OPT_WINDOW_TEXT)
    f.button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.button:SetSize(220, 28)
    f.button:SetPoint("TOP", f.text, "BOTTOM", 0, -16)
    f.button:SetText(L.OPT_OPEN_BTN)
    f.button:SetScript("OnClick", function() O:Open() end)
    local category = Settings.RegisterCanvasLayoutCategory(f, ns.title)
    Settings.RegisterAddOnCategory(category)
    O.category = category
end

ns.OnLogin(function()
    ns.Debug.Call("Options:Stub", registerStub)
end)

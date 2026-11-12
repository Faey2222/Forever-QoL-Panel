local _, ns = ...

-- Setup wizard: on the first login with the addon every page, after an update only the pages of what is new.
-- Every page bundles a few switches; changes apply at once. /fqp setup opens it again with all pages.
local Wz = {}
ns.Wizard = Wz

local L = setmetatable({}, { __index = function(_, k) return ns.L[k] end })

local function panel() return ns.db.panel end
local function ab() return ns.db.actionbar end
local function gp() return ns.db.gameplay end
local function wn() return ns.db.warnings end
local function tt() return ns.db.tooltip end
local function np() return ns.db.nameplates end
local function mm() return ns.db.minimap end

-- page: id, since (version that brought it), title, text, controls
-- control: { "check", label, tbl, key } or { "choice", label, tbl, key, { { value, label }, ... } }
local PAGES = {
    { id = "panel", icon = "Interface\\Icons\\INV_Misc_Note_06", since = "0.1.0", title = "WZ_PANEL", text = "WZ_PANEL_TEXT", controls = {
        { "check", "OPT_PANEL", panel, "enabled", reload = true },
        { "choice", "OPT_SKIN", panel, "skin", { { "classic", "SKIN_CLASSIC" }, { "modern", "SKIN_MODERN" } } },
        { "choice", "OPT_POSITION", panel, "position", { { "top", "POS_TOP" }, { "bottom", "POS_BOTTOM" } } },
        { "choice", "OPT_BORDER", panel, "border", { { 1, "BORDER_THIN" }, { 2, "BORDER_NORMAL" }, { 3, "BORDER_THICK" } } },
    } },
    { id = "xpbar", icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", since = "0.1.0", title = "WZ_XPBAR", text = "WZ_XPBAR_TEXT", controls = {
        { "check", "OPT_XPBAR", panel, "xpbar" },
        { "check", "OPT_DONE", panel, "questPreview" },
        { "choice", "OPT_STYLE", panel, "style", { { "edge", "STYLE_EDGE" }, { "rail", "STYLE_RAIL" } } },
    } },
    { id = "minimap", icon = "Interface\\Icons\\INV_Misc_Map_01", since = "0.1.0", title = "WZ_MINIMAP", text = "WZ_MINIMAP_TEXT", controls = {
        { "check", "OPT_COLLECT", panel, "collectButtons" },
        { "check", "OPT_FLOATING", mm, "floating" },
    } },
    { id = "actionbar", icon = "Interface\\Icons\\Spell_Arcane_StudentOfMagic", since = "0.2.0", title = "SEC_ACTIONBAR", text = "WZ_AB_TEXT", controls = {
        { "check", "OPT_AB", ab, "enabled" },
        { "check", "OPT_AB_PLACE", ab, "placeNew" },
        { "check", "OPT_AB_RANKS", ab, "replaceRanks" },
    } },
    { id = "quests", icon = "Interface\\Icons\\INV_Scroll_03", since = "0.2.0", title = "WZ_QUESTS", text = "WZ_QUESTS_TEXT", controls = {
        { "check", "OPT_GP_ACCEPT", gp, "questAccept" },
        { "check", "OPT_GP_TURNIN", gp, "questTurnIn" },
        { "check", "OPT_GP_GOSSIP", gp, "gossip" },
        { "check", "OPT_GP_REWARD", gp, "rewardValue" },
    } },
    { id = "merchant", icon = "Interface\\Icons\\INV_Misc_Coin_02", since = "0.2.0", title = "WZ_MERCHANT", text = "WZ_MERCHANT_TEXT", controls = {
        { "check", "OPT_GP_SELL", gp, "sellGrey" },
        { "check", "OPT_GP_REPAIR", gp, "repair" },
        { "check", "OPT_GP_FASTLOOT", gp, "fastLoot" },
        { "check", "OPT_GP_LOOTTEXT", gp, "lootText" },
    } },
    { id = "nameplates", icon = "Interface\\Icons\\Ability_Hunter_SniperShot", since = "0.2.0", title = "SEC_NAMEPLATES", text = "WZ_NP_TEXT", controls = {
        { "check", "OPT_NP", np, "enabled" },
        { "check", "OPT_NP_PROGRESS", np, "progress" },
    } },
    { id = "warnings", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", since = "0.2.0", title = "SEC_WARNINGS", text = "WZ_WARN_TEXT", controls = {
        { "check", "OPT_WARN_CLASS", wn, "classBuffs" },
        { "check", "OPT_WARN_FOOD", wn, "food" },
        { "choice", "OPT_WARN_WHERE", wn, "foodWhere", { { "instance", "WHERE_INSTANCE" }, { "world", "WHERE_WORLD" } } },
        { "check", "OPT_WARN_FLASK", wn, "flask" },
        { "check", "OPT_WARN_WEAPON", wn, "weapon" },
        { "check", "OPT_WARN_EXPIRING", wn, "expiring" },
        { "check", "OPT_WARN_COMBAT", wn, "combat" },
        { "choice", "OPT_WARN_ANIM", wn, "anim", { { "pulse", "ANIM_PULSE" }, { "bounce", "ANIM_BOUNCE" },
            { "flash", "ANIM_FLASH" }, { "wave", "ANIM_WAVE" }, { "none", "NONE" } } },
    } },
    { id = "tooltip", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", since = "0.2.0", title = "SEC_TOOLTIP", text = "WZ_TT_TEXT", controls = {
        { "check", "OPT_TT_SELL", tt, "sellValue" },
        { "check", "OPT_TT_COUNTS", tt, "counts" },
        { "check", "OPT_TT_GATHER", tt, "gather" },
    } },
}

local function newer(a, b)
    local x, y = {}, {}
    for n in tostring(a):gmatch("%d+") do x[#x + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do y[#y + 1] = tonumber(n) end
    for i = 1, math.max(#x, #y) do
        if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) > (y[i] or 0) end
    end
    return false
end

-- Window -------------------------------------------------------------------------
-- Look and controls come from UI.lua (shared with the options window). The first page is an overview
-- ("Welcome" / "What's new") with a tile per following page.

local OVERVIEW = { id = "overview", icon = "Interface\\Icons\\INV_Misc_Book_07", title = "WZ_OVERVIEW", controls = {} }

-- description of a control: the option's tooltip text, if there is one
local function tipOf(key)
    local t = ns.L[key .. "_TIP"]
    if t ~= key .. "_TIP" then return t end
end

local function createWindow()
    local f = ns.UI.Window("ForeverQoLPanelWizard", { width = 780, height = 540 })
    f.tiles, f.pips = {}, {}
    f.onLayout = function() Wz:Render() end
    local function navButton(label, fn)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(120, 24)
        btn:SetText(label)
        btn:SetScript("OnClick", fn)
        return btn
    end
    f.next = navButton(L.WZ_NEXT, function() Wz:Go(1) end)
    f.next:SetPoint("BOTTOMRIGHT", -12, 12)
    f.back = navButton(L.WZ_BACK, function() Wz:Go(-1) end)
    f.back:SetPoint("RIGHT", f.next, "LEFT", -6, 0)
    f.skip = navButton(L.WZ_SKIP, function() Wz:Finish() end)
    f.skip:SetPoint("BOTTOMLEFT", 12, 12)
    return f
end

-- overview tile: icon and name of a following page, click jumps there
local function tile(f, i)
    local t = f.tiles[i]
    if t then return t end
    t = CreateFrame("Button", nil, f.content)
    t.hl = t:CreateTexture(nil, "HIGHLIGHT")
    t.hl:SetAllPoints()
    if not ns.SetAtlas(t.hl, "listHover", { "options_list_hover", "options_list_hover-c60" }) then
        t.hl:SetColorTexture(1, 1, 1, 0.08)
    end
    t.icon = ns.UI.Icon(t, 34)
    t.icon:SetPoint("LEFT", 2, 0)
    t.label = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.label:SetPoint("LEFT", t.icon, "RIGHT", 10, 0)
    t.label:SetPoint("RIGHT", -6, 0)
    t.label:SetJustifyH("LEFT")
    t:SetScript("OnClick", function(b) Wz:Jump(b.index) end)
    f.tiles[i] = t
    return t
end

local function pip(f, i)
    local p = f.pips[i]
    if p then return p end
    p = f:CreateTexture(nil, "OVERLAY")
    p:SetSize(9, 9)
    f.pips[i] = p
    return p
end

function Wz:IsNew(page)
    return self.update and page.since and newer(page.since, self.from)
end

-- the page's controls as UI specs
local function specs(page)
    local list = { { type = "text", label = L[page.text] } }
    for _, c in ipairs(page.controls) do
        local kind, key, tbl, field = c[1], c[2], c[3], c[4]
        local s = {
            label = L[key], tip = tipOf(key), reload = c.reload,
            get = function() return tbl()[field] end,
            set = function(v) tbl()[field] = v end,
        }
        if kind == "check" then
            s.type = "check"
        else
            s.type = "choice"
            s.values = {}
            for _, opt in ipairs(c[5]) do s.values[#s.values + 1] = { opt[1], L[opt[2]] } end
        end
        list[#list + 1] = s
    end
    return list
end

function Wz:Render()
    local f, page = self.frame, self.pages[self.index]
    self.seen[self.index] = true
    for _, t in ipairs(f.tiles) do t:Hide() end

    local nav = {}
    for i, p in ipairs(self.pages) do
        nav[i] = { icon = p.icon, title = L[p.title],
            mark = self.seen[i] and i ~= self.index and p ~= OVERVIEW,
            new = self:IsNew(p) and not self.seen[i] and L.WZ_NEW or nil }
    end
    f:SetNav(nav, self.index, function(i) Wz:Jump(i) end)

    if page == OVERVIEW then
        f:SetHead(page.icon, self.update and L.WZ_WHATSNEW_TITLE or L.WZ_WELCOME_TITLE,
            self.update and L.WZ_UPDATE:format(ns.VERSION) or ns.title)
        -- the global animation level right on the first page
        local list = {}
        if not self.update then list[1] = { type = "text", label = L.WZ_WELCOME } end
        list[#list + 1] = { type = "choice", label = L.OPT_MOTION, tip = L.OPT_MOTION_TIP,
            get = function() return ns.db.motion end, set = function(v) ns.db.motion = v end,
            values = { { "full", L.MOTION_FULL }, { "reduced", L.MOTION_REDUCED }, { "off", L.MOTION_OFF } } }
        list[#list + 1] = { type = "header", label = L.WZ_INCLUDED }
        local y = f:Render(list, function() Wz:Render() end)
        -- two columns, three when the window is wide enough
        local cols = f.contentWidth >= 640 and 3 or 2
        local tw = (f.contentWidth - (cols - 1) * 12) / cols
        for i = 2, #self.pages do
            local p, t = self.pages[i], tile(f, i - 1)
            t.index = i
            t:SetSize(tw, 38)
            t.icon.icon:SetTexture(p.icon)
            t.label:SetText(L[p.title])
            local col, row = (i - 2) % cols, math.floor((i - 2) / cols)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", col * (tw + 12), -(y + row * 42))
            t:Show()
        end
        f.content:SetHeight(y + math.ceil((#self.pages - 1) / cols) * 42 + 8)
    else
        f:SetHead(page.icon, L[page.title], L.WZ_STEP:format(self.index - 1, #self.pages - 1),
            self:IsNew(page) and L.WZ_NEW or nil)
        f:Render(specs(page), function() Wz:Render() end)
    end

    local n = #self.pages
    for i = 1, n do
        local p = pip(f, i)
        p:ClearAllPoints()
        p:SetPoint("BOTTOM", f, "BOTTOM", (i - (n + 1) / 2) * 15, 20)
        p:SetTexture(i == self.index and "Interface\\COMMON\\Indicator-Yellow" or "Interface\\COMMON\\Indicator-Gray")
        p:Show()
    end
    for i = n + 1, #f.pips do f.pips[i]:Hide() end
    f.back:SetEnabled(self.index > 1)
    f.next:SetText(self.index == 1 and L.WZ_START or self.index == n and L.WZ_DONE or L.WZ_NEXT)
end

function Wz:Jump(i)
    self.index = math.max(1, math.min(#self.pages, i))
    self:Render()
    self.frame:FadeContent()
end

function Wz:Go(delta)
    local i = self.index + delta
    if i > #self.pages then return self:Finish() end
    self:Jump(i)
end

function Wz:Finish()
    ns.db.wizard = ns.VERSION
    if self.frame then self.frame:Hide() end
end

-- all = every page (first run or /fqp setup); otherwise only what came after `from`
function Wz:Open(all)
    local from = ns.db.wizard
    self.update = not all and from ~= nil
    self.from = from
    self.pages = { OVERVIEW }
    for _, p in ipairs(PAGES) do
        if all or not from or newer(p.since, from) then self.pages[#self.pages + 1] = p end
    end
    if #self.pages == 1 then return self:Finish() end
    self.frame = self.frame or createWindow()
    if ns.Options and ns.Options.frame then ns.Options.frame:Hide() end
    self.index, self.seen = 1, {}
    self:Render()
    self.frame:Show()
end

ns.OnLogin(function()
    if ns.db.wizard and not newer(ns.VERSION, ns.db.wizard) then return end
    C_Timer.After(3, function()
        if InCombatLockdown() then return end
        ns.Debug.Call("Wizard", Wz.Open, Wz, ns.db.wizard == nil)
    end)
end)

local _, ns = ...

-- Shared window look for the setup wizard and the options: Blizzard settings style with a step/category list on the
-- left and the page on the right (icon, title, divider, scrollable content). Controls are described by specs:
--   { type = "header", label }                  section title with a divider
--   { type = "text", label }                    paragraph
--   { type = "check", label, tip, get, set, needs, indent, reload }
--   { type = "choice", label, tip, get, set, values = { { value, label }, ... }, needs, indent }
--   { type = "slider", label, tip, get, set, min, max, step, suffix, needs }
--   { type = "button", label, text, tip, func, needs }
-- needs = keys of UI.NEED; while one of them is not met, the control is greyed out and says what it needs.
local UI = {}
ns.UI = UI

local L = setmetatable({}, { __index = function(_, k) return ns.L[k] end })

-- conditions controls depend on: { test, label of what is needed }
UI.NEED = {
    panel = { function() return ns.db.panel.enabled end, "OPT_PANEL" },
    xpbar = { function() return ns.db.panel.enabled and ns.db.panel.xpbar end, "OPT_XPBAR" },
    rail = { function() return ns.db.panel.style == "rail" end, "STYLE_RAIL" },
    modern = { function() return ns.db.panel.skin == "modern" end, "SKIN_MODERN" },
    preview = { function() return ns.db.panel.questPreview end, "OPT_DONE" },
    noCollect = { function() return not (ns.db.panel.enabled and ns.db.panel.collectButtons) end, "OPT_COLLECT_OFF" },
    noPanel = { function() return not ns.db.panel.enabled end, "OPT_PANEL_OFF" },
    actionbar = { function() return ns.db.actionbar.enabled end, "OPT_AB" },
    gameplay = { function() return ns.db.gameplay.enabled end, "OPT_GAMEPLAY" },
    nameplates = { function() return ns.db.nameplates.enabled end, "OPT_NP" },
    warnings = { function() return ns.db.warnings.enabled end, "OPT_WARNINGS" },
    tooltip = { function() return ns.db.tooltip.enabled end, "OPT_TOOLTIP" },
    zone = { function() return ns.db.panel.items.zone end, "ITEM_zone" },
    xph = { function() return ns.db.panel.items.xph end, "ITEM_xph" },
    clock = { function() return ns.db.panel.items.clock end, "ITEM_clock" },
    addons = { function() return ns.db.panel.items.addons end, "ITEM_addons" },
    food = { function() return ns.db.warnings.food end, "OPT_WARN_FOOD" },
    xptext = { function() return ns.db.panel.xpText end, "OPT_XPTEXT" },
    lootopt = { function() return ns.db.lootopt.enabled end, "SEC_LOOTOPT" },
    btnrange = { function() return ns.db.buttons.range end, "OPT_BTN_RANGE" },
    cbtarget = { function() return ns.db.castbar.target == "free" end, "PLACE_FREE" },
    cbfocus = { function() return ns.db.castbar.focus == "free" end, "PLACE_FREE" },
    btncd = { function() return ns.db.buttons.cd end, "OPT_BTN_CD" },
    repbar = { function() return ns.db.panel.enabled and ns.db.panel.repBar end, "OPT_REPBAR" },
    repfree = { function() return ns.db.panel.repPlace == "free" end, "PLACE_FREE" },
    xpfree = { function() return ns.db.panel.xpPlace == "free" end, "PLACE_FREE" },
    reptext = { function() return ns.db.panel.repText end, "OPT_XPTEXT" },
    hunter = { function() return select(2, UnitClass("player")) == "HUNTER" end, "NEED_HUNTER" },
    warlock = { function() return select(2, UnitClass("player")) == "WARLOCK" end, "NEED_WARLOCK" },
    flask = { function() return ns.db.warnings.flask end, "OPT_WARN_FLASK" },
    wclass = { function() return ns.db.warnings.classBuffs end, "OPT_WARN_CLASS" },
    wexpiring = { function() return ns.db.warnings.expiring end, "OPT_WARN_EXPIRING" },
    wweapon = { function() return ns.db.warnings.weapon end, "OPT_WARN_WEAPON" },
    ammo = { function() return ns.db.warnings.ammo end, "OPT_WARN_AMMO" },
    lootText = { function() return ns.db.gameplay.lootText end, "OPT_GP_LOOTTEXT" },
}

-- nil when everything needed is there, otherwise the "Requires: ..." text
function UI.Missing(needs)
    if not needs then return nil end
    local names = {}
    for _, n in ipairs(needs) do
        local need = UI.NEED[n]
        if need and not need[1]() then names[#names + 1] = L[need[2]] end
    end
    if #names == 0 then return nil end
    return L.REQUIRES:format(table.concat(names, ", "))
end

local function click()
    if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) end
end

local function inset(parent)
    local ok, f = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if not ok or not f then f = CreateFrame("Frame", nil, parent) end
    return f
end

-- square icon in the action button frame
function UI.Icon(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetPoint("CENTER")
    holder.icon:SetSize(size * 0.86, size * 0.86)
    holder.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    holder.ring = holder:CreateTexture(nil, "OVERLAY")
    holder.ring:SetAllPoints()
    if not ns.SetAtlas(holder.ring, "frame", { "ui-hud-actionbar-iconframe", "ui-hud-actionbar-iconframe-c60" }) then
        holder.ring:Hide()
        holder.icon:SetAllPoints()
    end
    return holder
end

local function listTextures(b)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    if not ns.SetAtlas(b.sel, "listActive", { "options_list_active", "options_list_active-c60" }) then
        b.sel:SetColorTexture(1, 0.82, 0, 0.15)
    end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    if not ns.SetAtlas(b.hl, "listHover", { "options_list_hover", "options_list_hover-c60" }) then
        b.hl:SetColorTexture(1, 1, 1, 0.08)
    end
end
UI.ListTextures = listTextures

-- Window ---------------------------------------------------------------------------

local Window = {}

-- opts: width, height, navWidth
function UI.Window(name, opts)
    local W, H, NAV = opts.width or 780, opts.height or 540, opts.navWidth or 210
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "PortraitFrameTemplate")
    if not ok or not f then f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset") end
    for k, v in pairs(Window) do f[k] = v end
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetTitle then f:SetTitle(ns.title) end
    local pc = rawget(f, "PortraitContainer")
    local portrait = type(pc) == "table" and rawget(pc, "portrait") or rawget(f, "portrait")
    if portrait then portrait:SetTexture(ns.Tex("icon")) end
    tinsert(UISpecialFrames, name)

    f.nav = inset(f)
    f.nav:SetPoint("TOPLEFT", 10, -62)
    f.nav:SetPoint("BOTTOMLEFT", 10, 44)
    f.nav:SetWidth(NAV)
    f.navWidth = NAV
    f.navRows = {}
    -- the list scrolls when the window is lower than it: mouse wheel, a thin gold bar shows where you are
    f.navScroll = CreateFrame("ScrollFrame", nil, f.nav)
    f.navScroll:SetPoint("TOPLEFT", 0, -4)
    f.navScroll:SetPoint("BOTTOMRIGHT", 0, 4)
    f.navList = CreateFrame("Frame", nil, f.navScroll)
    f.navList:SetSize(NAV, 10)
    f.navScroll:SetScrollChild(f.navList)
    f.navScroll:EnableMouseWheel(true)
    f.navScroll:SetScript("OnMouseWheel", function(_, delta) f:ScrollNav(f.navScroll:GetVerticalScroll() - delta * 62) end)
    f.navScroll:SetScript("OnSizeChanged", function() f:ScrollNav(f.navScroll:GetVerticalScroll()) end)
    f.navThumb = f.nav:CreateTexture(nil, "OVERLAY")
    f.navThumb:SetColorTexture(1, 0.82, 0.25, 0.45)
    f.navThumb:SetWidth(3)
    f.navThumb:Hide()

    local b = inset(f)
    f.body = b
    b:SetPoint("TOPLEFT", f.nav, "TOPRIGHT", 6, 0)
    b:SetPoint("BOTTOMRIGHT", -10, 44)
    f.bodyWidth = W - NAV - 26

    -- warm light from the top behind the header
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    b.glow:SetPoint("TOPLEFT", 3, -3)
    b.glow:SetPoint("TOPRIGHT", -3, -3)
    b.glow:SetHeight(110)
    b.glow:SetColorTexture(1, 1, 1, 1)
    if b.glow.SetGradient and CreateColor then
        b.glow:SetGradient("VERTICAL", CreateColor(0.55, 0.42, 0.18, 0), CreateColor(0.55, 0.42, 0.18, 0.28))
    else
        b.glow:SetAlpha(0.06)
    end

    b.icon = UI.Icon(b, 58)
    b.icon:SetPoint("TOPLEFT", 22, -20)
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    b.title:SetPoint("TOPLEFT", 96, -26)
    b.title:SetJustifyH("LEFT")
    b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.badge:SetPoint("LEFT", b.title, "RIGHT", 10, 0)
    b.badge:SetTextColor(0.12, 1, 0)
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    b.sub:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -6)
    b.divider = b:CreateTexture(nil, "ARTWORK")
    b.divider:SetPoint("TOPLEFT", 16, -96)
    b.divider:SetPoint("TOPRIGHT", -16, -96)
    if ns.SetAtlas(b.divider, "divider", { "options_horizontaldivider", "options_horizontaldivider-c60" }) then
        b.divider:SetHeight(4)
    else
        b.divider:SetHeight(2)
        b.divider:SetColorTexture(1, 0.82, 0, 0.25)
    end

    -- scrollable content below the header
    local sok, scroll = pcall(CreateFrame, "ScrollFrame", nil, b, "ScrollFrameTemplate")
    if not sok or not scroll then
        sok, scroll = pcall(CreateFrame, "ScrollFrame", nil, b, "UIPanelScrollFrameTemplate")
    end
    if not sok or not scroll then scroll = CreateFrame("ScrollFrame", nil, b) end
    scroll:SetPoint("TOPLEFT", 8, -104)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    f.scroll = scroll
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(f.bodyWidth - 34, 10)
    scroll:SetScrollChild(f.content)
    f.contentWidth = f.bodyWidth - 34 - 32
    f.pool = {}

    -- resizable: grip in the corner, size kept per window; the page is laid out again for the new width
    f.minW, f.minH = opts.minWidth or 640, opts.minHeight or 440
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(f.minW, f.minH, 1600, 1200)
    elseif f.SetMinResize then
        f:SetMinResize(f.minW, f.minH)
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f:SaveSize()
    end)
    f.grip = grip
    f:SetScript("OnSizeChanged", function() f:Layout() end)
    local saved = ns.db.windows and ns.db.windows[name]
    if saved and saved.w and saved.h then
        f:SetSize(math.max(f.minW, saved.w), math.max(f.minH, saved.h))
    end
    f.windowName = name
    f:Layout()
    return f
end

-- search field on top of the list; onSearch(text) on every change
function Window:EnableSearch(onSearch)
    local ok, box = pcall(CreateFrame, "EditBox", nil, self.nav, "SearchBoxTemplate")
    if not ok or not box then box = CreateFrame("EditBox", nil, self.nav, "InputBoxTemplate") end
    box:SetHeight(22)
    box:SetPoint("TOPLEFT", 14, -8)
    box:SetPoint("TOPRIGHT", -10, -8)
    box:SetAutoFocus(false)
    box:HookScript("OnTextChanged", function(b) onSearch(strtrim(b:GetText() or "")) end)
    box:SetScript("OnEscapePressed", function(b) b:SetText(""); b:ClearFocus() end)
    self.search = box
    self.navTop = 38
    self.navScroll:SetPoint("TOPLEFT", 0, -36)
end

-- scrolls the list to y (clamped) and places the position bar
function Window:ScrollNav(y)
    local view, total = self.navScroll:GetHeight() or 0, self.navList:GetHeight() or 0
    local maxY = math.max(0, total - view)
    y = math.max(0, math.min(maxY, y or 0))
    self.navScroll:SetVerticalScroll(y)
    local t = self.navThumb
    if maxY <= 0 or view <= 0 then t:Hide() return end
    local h = math.max(24, view * view / total)
    t:ClearAllPoints()
    t:SetPoint("TOPRIGHT", self.navScroll, "TOPRIGHT", -3, -(y / maxY) * (view - h))
    t:SetHeight(h)
    t:Show()
end

function Window:SetSearchHint(text)
    local box = self.search
    local hint = box and (rawget(box, "Instructions") or rawget(box, "instructions"))
    if hint and hint.SetText then hint:SetText(text) end
end

function Window:SaveSize()
    ns.db.windows = ns.db.windows or {}
    ns.db.windows[self.windowName] = { w = math.floor(self:GetWidth() + 0.5), h = math.floor(self:GetHeight() + 0.5) }
end

-- widths follow the window; the owner re-renders its page (throttled to one layout per frame while dragging)
function Window:Layout()
    local w = self:GetWidth() or 0
    self.bodyWidth = w - self.navWidth - 26
    self.contentWidth = self.bodyWidth - 34 - 32
    self.content:SetWidth(self.bodyWidth - 34)
    if not self.onLayout or self.layoutPending then return end
    self.layoutPending = true
    C_Timer.After(0, function()
        self.layoutPending = false
        if self:IsShown() then self.onLayout() end
    end)
end

-- items: { { icon, title, mark = bool, new = text, off = bool } } or { header = text } for a group title;
-- onClick(index) gets the index into items
function Window:SetNav(items, active, onClick)
    local y = 2
    local activeTop, activeBottom
    for i, item in ipairs(items) do
        local r = self.navRows[i]
        if not r then
            r = CreateFrame("Button", nil, self.navList)
            listTextures(r)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(22, 22)
            r.icon:SetPoint("LEFT", 8, 0)
            r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.label:SetJustifyH("LEFT")
            r.label:SetWordWrap(false)
            r.mark = r:CreateTexture(nil, "OVERLAY")
            r.mark:SetSize(14, 14)
            r.mark:SetPoint("RIGHT", -8, 0)
            r.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            r.new = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.new:SetPoint("RIGHT", -8, 0)
            self.navRows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 6, -y)
        r.label:ClearAllPoints()
        if item.header then
            -- group title: small gold caps, not clickable
            r:SetSize(self.navWidth - 12, 24)
            r:EnableMouse(false)
            r.icon:Hide(); r.mark:Hide(); r.sel:Hide(); r.hl:Hide()
            r.label:SetPoint("BOTTOMLEFT", 8, 3)
            r.label:SetPoint("RIGHT", -8, 0)
            r.label:SetFontObject(GameFontNormalSmall)
            r.label:SetText(item.header)
            r.new:SetText("")
            y = y + (i > 1 and 28 or 24)
        else
            r:SetSize(self.navWidth - 12, 30)
            r:EnableMouse(true)
            r.hl:Show()
            r.icon:Show()
            r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
            r.label:SetPoint("RIGHT", -34, 0)
            r:SetScript("OnClick", function() click(); onClick(i) end)
            r.icon:SetTexture(item.icon)
            r.icon:SetDesaturated(item.off and true or false)
            r.icon:SetAlpha(item.off and 0.6 or 1)
            r.label:SetText(item.title)
            r.label:SetFontObject(i == active and GameFontNormal or (item.off and GameFontDisable or GameFontHighlight))
            r.sel:SetShown(i == active)
            r.mark:SetShown(item.mark and true or false)
            -- "NEW" in green, a switched-off feature says "Off" in grey
            r.new:SetText(item.new or (item.off and L.NAV_OFF) or "")
            if item.new then r.new:SetTextColor(0.12, 1, 0) else r.new:SetTextColor(0.5, 0.5, 0.5) end
            if i == active then activeTop, activeBottom = y, y + 30 end
            y = y + 31
        end
        r:Show()
    end
    for i = #items + 1, #self.navRows do self.navRows[i]:Hide() end
    self.navList:SetSize(self.navWidth, y + 4)
    -- the chosen page stays in view
    local cur, view = self.navScroll:GetVerticalScroll() or 0, self.navScroll:GetHeight() or 0
    if activeTop and view > 0 then
        if activeTop < cur then cur = activeTop - 4
        elseif activeBottom > cur + view then cur = activeBottom - view + 4 end
    end
    self:ScrollNav(cur)
end

-- toggle: nil, or { get, set, label, tip } = the page's master switch, top right in the header
function Window:SetHead(icon, title, sub, badge, toggle)
    local b = self.body
    b.icon.icon:SetTexture(icon)
    b.title:SetText(title)
    b.sub:SetText(sub or "")
    b.badge:SetText(badge or "")
    if not b.master then
        local m = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
        m:SetSize(30, 30)
        m:SetPoint("TOPRIGHT", -20, -30)
        local own = rawget(m, "Text") or rawget(m, "text")
        if own then own:SetText("") end
        m.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        m.label:SetPoint("RIGHT", m, "LEFT", -4, 1)
        m:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        m:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b.master = m
    end
    local m = b.master
    if toggle then
        m.label:SetText(toggle.label or L.OPT_ENABLED)
        m.tip = toggle.tip
        local on = toggle.get() and true or false
        m:SetChecked(on)
        m.label:SetTextColor(on and 0.12 or 0.6, on and 1 or 0.6, on and 0 or 0.6)
        m:SetScript("OnClick", function(btn)
            click()
            toggle.set(btn:GetChecked() and true or false)
            ns.Refresh()
            if toggle.onChange then toggle.onChange() end
        end)
        m:Show(); m.label:Show()
    else
        m:Hide(); m.label:Hide()
    end
end

-- Controls ---------------------------------------------------------------------------
-- Settings sit in cards (one per section, a dark rounded box), one row each: the name on the left, the control
-- right-aligned. Choices are dropdowns. Descriptions and "Requires: ..." go to the row's tooltip; a row that is not
-- available is greyed out. Sub-settings are indented in a smaller font.

local PAD, ROW_H, SUB_H, GAP = 16, 38, 32, 22

local function take(f, kind, make)
    local pool = f.pool[kind]
    if not pool then pool = { n = 0 }; f.pool[kind] = pool end
    pool.n = pool.n + 1
    local w = pool[pool.n]
    if not w then w = make(); pool[pool.n] = w end
    w:ClearAllPoints()
    w:Show()
    return w
end

local function textHeight(fs)
    local t = fs:GetText()
    if not t or t == "" then return 0 end
    return fs:GetStringHeight() or 12
end

-- tooltip of a row: name, description, what it needs
local function showTip(owner, row)
    local s = row.spec
    if not s or (not s.tip and not row.missing) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(s.label, 1, 1, 1)
    if s.tip then GameTooltip:AddLine(s.tip, 1, 0.82, 0, true) end
    if s.reload then GameTooltip:AddLine(L.NEEDS_RELOAD, 0.62, 0.62, 0.62, true) end
    -- needs a game restart (not just a reload): its own line in orange
    if s.restart then GameTooltip:AddLine(L.NEEDS_RESTART, 1, 0.55, 0.2, true) end
    if row.missing then GameTooltip:AddLine(row.missing, 1, 0.54, 0.42, true) end
    GameTooltip:Show()
end

local function hookTip(region, row)
    if region.fqpTip then return end
    region.fqpTip = true
    region:HookScript("OnEnter", function(self) row.hover:Show(); showTip(self, row) end)
    region:HookScript("OnLeave", function() row.hover:Hide(); GameTooltip:Hide() end)
end

local function newCard(f)
    local ok, c = pcall(CreateFrame, "Frame", nil, f.content, "BackdropTemplate")
    if not ok or not c then c = CreateFrame("Frame", nil, f.content) end
    if c.SetBackdrop then
        c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        c:SetBackdropColor(0.06, 0.06, 0.07, 0.72)
        c:SetBackdropBorderColor(0.45, 0.45, 0.48, 0.9)
    end
    c:SetFrameLevel(f.content:GetFrameLevel() + 1)
    return c
end

local function newRow(f)
    local w = CreateFrame("Frame", nil, f.content)
    w:SetFrameLevel(f.content:GetFrameLevel() + 3)
    w.hover = w:CreateTexture(nil, "BACKGROUND")
    w.hover:SetPoint("TOPLEFT", -PAD + 4, 0)
    w.hover:SetPoint("BOTTOMRIGHT", PAD - 4, 0)
    w.hover:SetColorTexture(1, 1, 1, 0.04)
    w.hover:Hide()
    w.label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.label:SetPoint("LEFT", 0, 0)
    w.label:SetJustifyH("LEFT")
    w.label:SetWordWrap(false)
    w:EnableMouse(true)
    hookTip(w, w)
    return w
end

local MAKE = {}

function MAKE.header(f)
    local w = CreateFrame("Frame", nil, f.content)
    w.label = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    w.label:SetPoint("BOTTOMLEFT", 4, 4)
    return w
end

function MAKE.text(f)
    local w = CreateFrame("Frame", nil, f.content)
    w.label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.label:SetPoint("TOPLEFT", 4, 0)
    w.label:SetJustifyH("LEFT")
    w.label:SetSpacing(3)
    w.label:SetTextColor(0.78, 0.78, 0.78)
    return w
end

-- a tile (the "More addons" page), upright: the logo on top, name, a few lines about it, a status line at the bottom
local TILE_H, TILE_COLS = 236, 3
function MAKE.tile(f)
    local w = newCard(f)
    w.glow = w:CreateTexture(nil, "BACKGROUND", nil, 2)
    w.glow:SetPoint("TOPLEFT", 4, -4)
    w.glow:SetPoint("TOPRIGHT", -4, -4)
    w.glow:SetHeight(110)
    w.glow:SetColorTexture(1, 1, 1, 1)
    if w.glow.SetGradient and CreateColor then
        w.glow:SetGradient("VERTICAL", CreateColor(1, 0.82, 0.3, 0), CreateColor(1, 0.82, 0.3, 0.1))
    else
        w.glow:SetVertexColor(1, 0.82, 0.3, 0.05)
    end
    w.logo = w:CreateTexture(nil, "ARTWORK")
    w.logo:SetSize(88, 88)
    w.logo:SetPoint("TOP", 0, -18)
    w.name = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    w.name:SetPoint("TOP", w.logo, "BOTTOM", 0, -12)
    w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.text:SetPoint("TOP", w.name, "BOTTOM", 0, -8)
    w.text:SetJustifyH("CENTER")
    w.text:SetJustifyV("TOP")
    w.text:SetSpacing(2)
    w.text:SetTextColor(0.82, 0.82, 0.82)
    w.status = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.status:SetPoint("BOTTOM", 0, 14)
    -- a button in place of the status line (e.g. the download link to copy)
    w.button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.button:SetSize(160, 24)
    w.button:SetPoint("BOTTOM", 0, 12)
    w.button:Hide()
    return w
end

-- Windows in the panel's look ---------------------------------------------------------------------------
-- Classic: the panel's bar border made into a frame: the corners are the quarters of the bar's rounded cap, the
-- sides a slice from the middle of the cap (where its arc runs straight down), top and bottom the bar's straight
-- edges; inside the panel's dark fill. Modern: the flat box with the rim colour, square or round corners. Both follow
-- the panel's rim (bronze / silver / dark) and border width.
local FILL_C, FILL_M = { 0.03, 0.025, 0.02, 0.92 }, { 0.05, 0.05, 0.06, 0.94 }
local RIM_M = { bronze = { 0.52, 0.4, 0.24, 1 }, silver = { 0.56, 0.56, 0.6, 1 }, dark = { 0, 0, 0, 1 } }
local RIM_C = { bronze = { 1, 1, 1 }, silver = { 1, 1, 1 }, dark = { 0.42, 0.42, 0.42 } }
local SUFFIX = { "-thin", "", "-thick" }
local K = 1                                   -- the classic border as wide as the panel's bar border (its width setting picks the texture)
local CW, CH = 20 * K, 16 * K                 -- corner piece: 20 x 16 units of the cap's 33 x 32 canvas
local CAP_U = 20 / 33 * 66 / 128              -- its width in texture coordinates
local LINE = 6 * K                            -- where the line runs, from the outer edge
local QUARTERS = { { 0, 1, 0, 1 }, { 1, 0, 0, 1 }, { 0, 1, 1, 0 }, { 1, 0, 1, 0 } }   -- TL, TR, BL, BR

local function skinParts(f)
    if f.skin then return f.skin end
    local s = { c = {}, m = {} }
    local function tex(layer, sub) return f:CreateTexture(nil, layer, nil, sub or 0) end
    -- classic: fill (centre, top and bottom bands, round corners), border (corners, sides, top, bottom)
    s.c.fill = { tex("BACKGROUND"), tex("BACKGROUND"), tex("BACKGROUND") }
    s.c.fillCorner = { tex("BACKGROUND"), tex("BACKGROUND"), tex("BACKGROUND"), tex("BACKGROUND") }
    s.c.corner = { tex("BORDER", 2), tex("BORDER", 2), tex("BORDER", 2), tex("BORDER", 2) }
    s.c.left, s.c.right, s.c.top, s.c.bottom = tex("BORDER", 1), tex("BORDER", 1), tex("BORDER", 1), tex("BORDER", 1)
    -- modern: fill, four lines, corner arcs and corner fills
    s.m.fill = { tex("BACKGROUND"), tex("BACKGROUND"), tex("BACKGROUND") }
    s.m.fillCorner = { tex("BACKGROUND"), tex("BACKGROUND"), tex("BACKGROUND"), tex("BACKGROUND") }
    s.m.line = { tex("BORDER"), tex("BORDER"), tex("BORDER"), tex("BORDER") }
    s.m.ring = { tex("BORDER", 1), tex("BORDER", 1), tex("BORDER", 1), tex("BORDER", 1) }
    f.skin = s
    return s
end

local function put(t, f, x, y, w, h)
    t:ClearAllPoints()
    if w <= 0 or h <= 0 then t:Hide() return end
    t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
    t:SetSize(w, h)
    t:Show()
end

local function hideAll(list) for _, t in pairs(list) do if type(t) == "table" and t.Hide then t:Hide() elseif type(t) == "table" then hideAll(t) end end end

-- lays the look out for the frame's current size; call again after resizing
function UI.Skin(f)
    if f.SetBackdrop then f:SetBackdrop(nil) end
    local s = skinParts(f)
    local p = ns.db.panel
    local W, H = f:GetWidth() or 0, f:GetHeight() or 0
    if p.skin == "modern" then
        hideAll(s.c)
        local th = p.border or 2
        local r = p.corners == "round" and 6 or 0
        local tint = RIM_M[p.rim] or RIM_M.bronze
        for i = 1, 3 do s.m.fill[i]:SetColorTexture(unpack(FILL_M)) end
        put(s.m.fill[1], f, r, 0, W - 2 * r, r)
        put(s.m.fill[2], f, 0, r, W, H - 2 * r)
        put(s.m.fill[3], f, r, H - r, W - 2 * r, r)
        for i = 1, 4 do s.m.line[i]:SetColorTexture(unpack(tint)) end
        put(s.m.line[1], f, r, 0, W - 2 * r, th)
        put(s.m.line[2], f, r, H - th, W - 2 * r, th)
        put(s.m.line[3], f, 0, r, th, H - 2 * r)
        put(s.m.line[4], f, W - th, r, th, H - 2 * r)
        local pos = { { 0, 0 }, { W - r, 0 }, { 0, H - r }, { W - r, H - r } }
        for i = 1, 4 do
            local q = QUARTERS[i]
            if r > 0 then
                s.m.fillCorner[i]:SetTexture(ns.Tex("corner"))
                s.m.fillCorner[i]:SetVertexColor(unpack(FILL_M))
                s.m.fillCorner[i]:SetTexCoord(q[1], q[2], q[3], q[4])
                put(s.m.fillCorner[i], f, pos[i][1], pos[i][2], r, r)
                s.m.ring[i]:SetTexture(ns.Tex("corner-ring-6-" .. math.min(3, th)))
                s.m.ring[i]:SetVertexColor(unpack(tint))
                s.m.ring[i]:SetTexCoord(q[1], q[2], q[3], q[4])
                put(s.m.ring[i], f, pos[i][1], pos[i][2], r, r)
            else
                s.m.fillCorner[i]:Hide(); s.m.ring[i]:Hide()
            end
        end
        return
    end
    hideAll(s.m)
    local suffix = (SUFFIX[p.border or 2] or "") .. (p.rim == "bronze" and "" or "-silver")
    local tint = RIM_C[p.rim] or RIM_C.bronze
    local cap = ns.Tex("cap-bar" .. suffix)
    -- fill inside the line, its corners round like the border's
    local rr = CW - LINE
    for i = 1, 3 do s.c.fill[i]:SetColorTexture(unpack(FILL_C)) end
    put(s.c.fill[1], f, CW, LINE, W - 2 * CW, rr)
    put(s.c.fill[2], f, LINE, LINE + rr, W - 2 * LINE, H - 2 * (LINE + rr))
    put(s.c.fill[3], f, CW, H - LINE - rr, W - 2 * CW, rr)
    local fpos = { { LINE, LINE }, { W - CW, LINE }, { LINE, H - CW }, { W - CW, H - CW } }
    for i = 1, 4 do
        local q, t = QUARTERS[i], s.c.fillCorner[i]
        t:SetTexture(ns.Tex("corner"))
        t:SetVertexColor(unpack(FILL_C))
        t:SetTexCoord(q[1], q[2], q[3], q[4])
        put(t, f, fpos[i][1], fpos[i][2], rr, rr)
    end
    -- corners: quarters of the cap (the right ones mirrored)
    local cpos = { { 0, 0, 0, CAP_U, 0, 0.5 }, { W - CW, 0, CAP_U, 0, 0, 0.5 }, { 0, H - CH, 0, CAP_U, 0.5, 1 },
        { W - CW, H - CH, CAP_U, 0, 0.5, 1 } }
    for i = 1, 4 do
        local c, t = cpos[i], s.c.corner[i]
        t:SetTexture(cap)
        t:SetVertexColor(unpack(tint))
        t:SetTexCoord(c[3], c[4], c[5], c[6])
        put(t, f, c[1], c[2], CW, CH)
    end
    -- sides: a thin slice from the middle of the cap, stretched
    for i, t in ipairs({ s.c.left, s.c.right }) do
        t:SetTexture(cap)
        t:SetVertexColor(unpack(tint))
        if i == 1 then t:SetTexCoord(0, CAP_U, 0.49, 0.51) else t:SetTexCoord(CAP_U, 0, 0.49, 0.51) end
        put(t, f, i == 1 and 0 or W - CW, CH, CW, H - 2 * CH)
    end
    -- top and bottom: the bar's straight edges (top line from the upper half, bottom line from the lower)
    local len = W - 2 * CW
    local u = len * 2 / (256 * K)
    s.c.top:SetTexture(ns.Tex("edge-bar-top" .. suffix), "REPEAT", "CLAMP")
    s.c.top:SetTexCoord(0, u, 0, 0.5)
    s.c.bottom:SetTexture(ns.Tex("edge-bar" .. suffix), "REPEAT", "CLAMP")
    s.c.bottom:SetTexCoord(0, u, 0.5, 1)
    for _, t in ipairs({ s.c.top, s.c.bottom }) do t:SetVertexColor(unpack(tint)) end
    put(s.c.top, f, CW, 0, len, CH)
    put(s.c.bottom, f, CW, H - CH, len, CH)
end

-- A small window with an empty text field; onAccept(text) when confirmed
function UI.AskText(title, onAccept)
    if not StaticPopupDialogs then return end
    StaticPopupDialogs.FQP_ASK_TEXT = {
        text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, editBoxWidth = 360,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnShow = function(self)
            local box = (self.GetEditBox and self:GetEditBox()) or rawget(self, "editBox") or rawget(self, "EditBox")
            if box then box:SetText(""); box:SetFocus() end
        end,
        OnAccept = function(self)
            local box = (self.GetEditBox and self:GetEditBox()) or rawget(self, "editBox") or rawget(self, "EditBox")
            onAccept(box and box:GetText() or "")
        end,
        EditBoxOnEnterPressed = function(box)
            local parent = box:GetParent()
            onAccept(box:GetText() or "")
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    }
    StaticPopup_Show("FQP_ASK_TEXT", title)
end

-- A small window with a link in a text field, selected, to copy with Ctrl+C (the game cannot open web pages).
function UI.CopyLink(title, url)
    if not StaticPopupDialogs then return end
    StaticPopupDialogs.FQP_COPY_LINK = StaticPopupDialogs.FQP_COPY_LINK or {
        text = "%s", button1 = CLOSE or OKAY, hasEditBox = true, editBoxWidth = 360, timeout = 0,
        whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnShow = function(self, data)
            local box = (self.GetEditBox and self:GetEditBox()) or rawget(self, "editBox") or rawget(self, "EditBox")
            if not box then return end
            box:SetText(data or "")
            box:HighlightText()
            box:SetFocus()
            -- the text stays the link, whatever is typed
            box:SetScript("OnTextChanged", function(b) if b:GetText() ~= data then b:SetText(data or ""); b:HighlightText() end end)
        end,
        OnHide = function(self)
            local box = (self.GetEditBox and self:GetEditBox()) or rawget(self, "editBox") or rawget(self, "EditBox")
            if box then box:SetScript("OnTextChanged", nil) end
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
    }
    StaticPopup_Show("FQP_COPY_LINK", title, nil, url)
end

function MAKE.check(f)
    local w = newRow(f)
    w.box = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
    w.box:SetSize(30, 30)
    w.box:SetPoint("RIGHT", 4, 0)
    local own = rawget(w.box, "Text") or rawget(w.box, "text")
    if own then own:SetText("") end
    hookTip(w.box, w)
    return w
end

function MAKE.choice(f)
    local w = newRow(f)
    local ok, d = pcall(CreateFrame, "DropdownButton", nil, w, "WowStyle1DropdownTemplate")
    if ok and d and d.SetupMenu then
        w.dropdown = d
        d:SetPoint("RIGHT", 0, 0)
        hookTip(d, w)
    else
        -- no dropdown template: a button that steps through the values
        w.stepper = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        w.stepper:SetSize(200, 24)
        w.stepper:SetPoint("RIGHT", 0, 0)
        hookTip(w.stepper, w)
    end
    return w
end

function MAKE.slider(f)
    local w = newRow(f)
    local ok, s = pcall(CreateFrame, "Frame", nil, w, "MinimalSliderWithSteppersTemplate")
    if ok and s then
        w.slider = s
        s:SetSize(200, 20)
        s:SetPoint("RIGHT", -52, 0)
        hookTip(s, w)
        if s.RegisterCallback and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Event then
            s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
                if w.busy or not w.spec then return end
                local st = w.spec.step or 1
                value = math.floor(value / st + 0.5) * st
                if value ~= w.spec.get() then w.spec.set(value); ns.Refresh() end
            end, w)
        end
    end
    return w
end

-- a preview of action buttons (the Action buttons page): example buttons drawn with the current settings
local PREVIEW = { { state = "normal", label = "BTN_PREV_NORMAL" }, { state = "range", label = "BTN_COL_RANGE" },
    { state = "mana", label = "BTN_PREV_MANA" }, { state = "unusable", label = "BTN_COL_UNUSABLE" },
    { cd = 95, label = "BTN_PREV_LONG" }, { cd = 14, label = "BTN_PREV_MID" }, { cd = 3.4, label = "BTN_PREV_SHORT" } }
UI.PREVIEW = PREVIEW
function MAKE.buttonpreview(f)
    local w = newCard(f)
    w.slots = {}
    for i, def in ipairs(PREVIEW) do
        local b = CreateFrame("Frame", nil, w)
        b:SetSize(40, 40)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexture("Interface\\Icons\\Spell_Nature_Lightning")
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.border = b:CreateTexture(nil, "OVERLAY")
        b.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        b.border:SetPoint("CENTER")
        b.border:SetSize(66, 66)
        b.shade = b:CreateTexture(nil, "ARTWORK", nil, 2)
        b.shade:SetAllPoints()
        b.shade:SetColorTexture(0, 0, 0, 0.6)
        -- a font from the start: the slots without a cooldown only ever clear this text
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("CENTER")
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.label:SetPoint("TOP", b, "BOTTOM", 0, -6)
        b.label:SetWidth(90)
        b.def = def
        w.slots[i] = b
    end
    return w
end

-- a colour: a swatch on the right, a click opens the game's colour picker
function MAKE.color(f)
    local w = newRow(f)
    w.swatch = CreateFrame("Button", nil, w, "BackdropTemplate")
    w.swatch:SetSize(34, 20)
    w.swatch:SetPoint("RIGHT", -6, 0)
    if w.swatch.SetBackdrop then
        w.swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        w.swatch:SetBackdropBorderColor(0.7, 0.6, 0.4, 1)
    end
    w.swatch.fill = w.swatch:CreateTexture(nil, "ARTWORK")
    w.swatch.fill:SetPoint("TOPLEFT", 2, -2)
    w.swatch.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    hookTip(w.swatch, w)
    return w
end

-- the game's colour picker for a colour { r, g, b }; onChange(r, g, b) while picking and on cancel
function UI.PickColor(c, onChange)
    local CPF = ColorPickerFrame
    if not CPF then return end
    local r, g, b = c[1], c[2], c[3]
    if CPF.SetupColorPickerAndShow then
        CPF:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = function() onChange(CPF:GetColorRGB()) end,
            cancelFunc = function() onChange(r, g, b) end })
    else
        CPF.hasOpacity = false
        CPF.func = function() onChange(CPF:GetColorRGB()) end
        CPF.cancelFunc = function() onChange(r, g, b) end
        CPF:SetColorRGB(r, g, b)
        CPF.previousValues = { r, g, b }
        if ShowUIPanel then ShowUIPanel(CPF) else CPF:Show() end
    end
end

function MAKE.button(f)
    local w = newRow(f)
    w.buttons = {}
    return w
end

local function rowButton(w, j)
    local b = w.buttons[j]
    if b then return b end
    b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    b:SetSize(120, 24)
    hookTip(b, w)
    w.buttons[j] = b
    return b
end

local function valueLabel(s)
    for _, v in ipairs(s.values) do if s.get() == v[1] then return v[2] end end
    return s.values[1] and s.values[1][2] or ""
end

-- lays out the specs in the content frame; onChange() runs after a value changed (re-render the page there)
function Window:Render(specs, onChange)
    local f, width = self, self.contentWidth
    for _, pool in pairs(f.pool) do
        for i = 1, #pool do pool[i]:Hide() end
        pool.n = 0
    end
    local function changed() ns.Refresh(); if onChange then onChange() end end
    local y = 2
    local cardTop      -- y where the open card started
    local function closeCard()
        if not cardTop then return end
        local c = take(f, "card", function() return newCard(f) end)
        c:SetPoint("TOPLEFT", 0, -cardTop)
        c:SetSize(width, y - cardTop + 6)
        y = y + 6 + GAP
        cardTop = nil
    end
    for idx, s in ipairs(specs) do
        if s.type == "header" then
            closeCard()
            local w = take(f, "header", function() return MAKE.header(f) end)
            w.label:SetText(s.label)
            w:SetSize(width, 26)
            w:SetPoint("TOPLEFT", 0, -y)
            y = y + 30
        elseif s.type == "tiles" then
            -- upright tiles, three per row
            closeCard()
            local n = #s.tiles
            local cols = TILE_COLS
            local tw = math.floor((width - 12 * (cols - 1)) / cols)
            for i, t in ipairs(s.tiles) do
                local w = take(f, "tile", function() return MAKE.tile(f) end)
                local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
                w:SetSize(tw, TILE_H)
                w:SetPoint("TOPLEFT", col * (tw + 12), -(y + row * (TILE_H + 12)))
                w.logo:SetTexture(t.logo)
                w.name:SetText(t.name)
                w.text:SetWidth(tw - 28)
                w.text:SetText(t.text)
                w.status:SetWidth(tw - 28)
                w.status:SetText(t.button and "" or (t.status or ""))
                w.button:SetShown(t.button ~= nil)
                if t.button then
                    w.button:SetText(t.button[1])
                    w.button:SetWidth(math.min(tw - 28, (w.button:GetFontString() and w.button:GetFontString():GetStringWidth() or 120) + 32))
                    w.button:SetScript("OnClick", function() click(); t.button[2]() end)
                end
            end
            y = y + math.ceil(n / cols) * (TILE_H + 12) + 4
        elseif s.type == "buttonpreview" then
            closeCard()
            local w = take(f, "buttonpreview", function() return MAKE.buttonpreview(f) end)
            w:SetSize(width, 96)
            w:SetPoint("TOPLEFT", 0, -y)
            local stepX = width / #w.slots
            for i, b in ipairs(w.slots) do
                b:ClearAllPoints()
                b:SetPoint("TOP", w, "TOPLEFT", stepX * (i - 0.5), -14)
            end
            if ns.ButtonState then ns.ButtonState:Preview(w) end
            y = y + 96 + GAP
        elseif s.type == "text" then
            closeCard()
            local w = take(f, "text", function() return MAKE.text(f) end)
            w.label:SetWidth(width - 8)
            w.label:SetText(s.label)
            local h = textHeight(w.label)
            w:SetSize(width, h)
            w:SetPoint("TOPLEFT", 0, -y)
            y = y + h + 16
        else
            if not cardTop then cardTop = y; y = y + 6 end
            local sub = s.indent and true or false
            local x = PAD + (sub and 18 or 0)
            local h = sub and SUB_H or ROW_H
            local w = take(f, s.type, function() return MAKE[s.type](f) end)
            local missing = UI.Missing(s.needs)
            local on = not missing
            w.spec, w.missing = s, missing
            w.label:SetFontObject(sub and GameFontHighlightSmall or GameFontHighlight)
            w.label:SetText(s.label .. (s.reload and "  |cff808080*|r" or ""))
            w.label:SetTextColor(on and (sub and 0.85 or 1) or 0.45, on and (sub and 0.85 or 1) or 0.45, on and (sub and 0.85 or 1) or 0.45)
            w:SetSize(width - x - PAD, h)
            w:SetPoint("TOPLEFT", x, -y)
            local controlW = 0
            if s.type == "check" then
                w.box:SetChecked(s.get() and true or false)
                w.box:SetEnabled(on)
                w.box:SetScript("OnClick", function(btn)
                    click()
                    s.set(btn:GetChecked() and true or false)
                    changed()
                end)
                controlW = 30
            elseif s.type == "choice" then
                if w.dropdown then
                    local d = w.dropdown
                    d:SetWidth(sub and 180 or 210)
                    d:SetupMenu(function(_, root)
                        for _, v in ipairs(s.values) do
                            root:CreateRadio(v[2], function() return s.get() == v[1] end, function() s.set(v[1]); changed() end)
                        end
                    end)
                    if d.GenerateMenu then d:GenerateMenu() end
                    d:SetEnabled(on)
                    controlW = sub and 180 or 210
                else
                    w.stepper:SetText(valueLabel(s))
                    w.stepper:SetEnabled(on)
                    w.stepper:SetScript("OnClick", function()
                        click()
                        local i = 1
                        for j, v in ipairs(s.values) do if s.get() == v[1] then i = j end end
                        s.set(s.values[i % #s.values + 1][1])
                        changed()
                    end)
                    controlW = 200
                end
            elseif s.type == "slider" then
                if w.slider then
                    local sl = w.slider
                    w.busy = true
                    local fmt = {}
                    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
                        local st = s.step or 1
                        local decimals = st >= 1 and 0 or st >= 0.1 and 1 or 2
                        fmt[MinimalSliderWithSteppersMixin.Label.Right] = function(v)
                            return string.format("%." .. decimals .. "f", math.floor(v / st + 0.5) * st) .. (s.suffix or "")
                        end
                    end
                    if sl.Init then sl:Init(s.get(), s.min, s.max, (s.max - s.min) / (s.step or 1), fmt) end
                    if sl.SetEnabled then sl:SetEnabled(on) end
                    w.busy = false
                    controlW = 252
                end
            elseif s.type == "color" then
                local c = s.get() or { 1, 1, 1 }
                w.swatch.fill:SetColorTexture(c[1], c[2], c[3], 1)
                w.swatch:SetEnabled(on)
                w.swatch:SetAlpha(on and 1 or 0.4)
                w.swatch:SetScript("OnClick", function()
                    click()
                    UI.PickColor(s.get() or { 1, 1, 1 }, function(r, g, b)
                        s.set({ r, g, b })
                        w.swatch.fill:SetColorTexture(r, g, b, 1)
                        ns.Refresh()
                    end)
                end)
                controlW = 46
            elseif s.type == "button" then
                local list = s.buttons or { { s.text, s.func } }
                for _, b in ipairs(w.buttons) do b:Hide() end
                local bx = 0
                for j = #list, 1, -1 do
                    local def = list[j]
                    local b = rowButton(w, j)
                    b:SetText(def[1])
                    local fs = b.GetFontString and b:GetFontString()
                    local bw = math.max(100, (fs and fs:GetStringWidth() or 80) + 28)
                    b:SetWidth(bw)
                    b:ClearAllPoints()
                    b:SetPoint("RIGHT", -bx, 0)
                    b:SetEnabled(on)
                    b:SetScript("OnClick", function() click(); def[2](); if onChange then onChange() end end)
                    b:Show()
                    bx = bx + bw + 6
                end
                controlW = bx
            end
            w.label:SetWidth(math.max(60, width - x - PAD - controlW - 16))
            y = y + h
        end
    end
    closeCard()
    f.content:SetHeight(y + 8)
    return y
end

function Window:FadeContent()
    if ns.db.panel.animations and UIFrameFadeIn then
        self.content:SetAlpha(0)
        UIFrameFadeIn(self.content, 0.2, 0, 1)
    end
end

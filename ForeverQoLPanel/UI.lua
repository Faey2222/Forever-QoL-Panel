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
    food = { function() return ns.db.warnings.food end, "OPT_WARN_FOOD" },
    flask = { function() return ns.db.warnings.flask end, "OPT_WARN_FLASK" },
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
    local y = self.navTop or 6
    for i, item in ipairs(items) do
        local r = self.navRows[i]
        if not r then
            r = CreateFrame("Button", nil, self.nav)
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
            y = y + 31
        end
        r:Show()
    end
    for i = #items + 1, #self.navRows do self.navRows[i]:Hide() end
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

local _, ns = ...

-- Our own minimap button (LibDBIcon style) and the collector: minimap buttons of other addons are taken off the
-- minimap and listed in the panel's addon menu instead. Without the panel they stay where they are.
local M = { entries = {}, seen = {} }
ns.Minimap = M

local ICON = ns.Tex("icon")
local RADIUS_PADDING, CORNER_INSET = 5, 10

-- Blizzard's own minimap buttons are never collected.
local BLIZZARD = { "^MiniMap", "^Minimap", "^GameTime", "^TimeManager", "^QueueStatus", "^ExpansionLandingPage",
    "^AddonCompartment", "^GarrisonLandingPage", "^LFGMinimapFrame", "^LFGFrame", "^Calendar", "^MinimapZoom", "^HelpOpenTicket",
    "^ForeverQoLPanel" }

-- With the panel, its addon menu collects; without it, the free-standing collector button does (if switched on).
local function floating()
    return not ns.db.panel.enabled and ns.db.minimap.floating
end

local function collecting()
    if floating() then return true end
    return ns.db.panel.enabled and ns.db.panel.collectButtons and ns.db.panel.items.addons
end

-- a button the player wants to keep on the minimap is listed, but not taken off
local function collected(entry)
    return collecting() and not ns.db.minimap.keep[entry.key or entry.name]
end

-- Own button ----------------------------------------------------------------------

local function place(button, angle)
    local r = math.rad(angle)
    local x, y = math.cos(r), math.sin(r)
    local hw, hh = Minimap:GetWidth() / 2 + RADIUS_PADDING, Minimap:GetHeight() / 2 + RADIUS_PADDING
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        local rx, ry = math.sqrt(2 * hw * hw) - CORNER_INSET, math.sqrt(2 * hh * hh) - CORNER_INSET
        x, y = math.max(-hw, math.min(x * rx, hw)), math.max(-hh, math.min(y * ry, hh))
    else
        x, y = x * hw, y * hh
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function followCursor(button)
    local cx, cy = Minimap:GetCenter()
    if not cx then return end
    local scale = Minimap:GetEffectiveScale()
    local x, y = GetCursorPosition()
    ns.db.minimap.angle = math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
    place(button, ns.db.minimap.angle)
end

function M.Click(mouseButton)
    if mouseButton == "RightButton" then
        ns.db.panel.pinned = not ns.db.panel.pinned
        if ns.Dock then ns.Dock:Refresh() end
        if ns.Elements.pin then ns.Elements:UpdatePin() end
    elseif ns.Options then
        ns.Options:Open()
    end
end

function M.Tooltip(owner, canDrag)
    local L = ns.L
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText(ns.title, 1, 0.82, 0)
    GameTooltip:AddLine(L.MM_CLICK, 1, 1, 1)
    GameTooltip:AddLine(L.MM_RIGHT, 1, 1, 1)
    if canDrag then GameTooltip:AddLine(L.MM_DRAG, 0.62, 0.62, 0.62) end
    GameTooltip:Show()
end

function M:CreateButton()
    local b = CreateFrame("Button", "ForeverQoLPanelMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    b:SetScript("OnClick", function(_, mouseButton) M.Click(mouseButton) end)
    b:SetScript("OnEnter", function(self) if not self.dragging then M.Tooltip(self, true) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        self.dragging = true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", followCursor)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.dragging = false
    end)
    self.button = b
    self:Update()
end

-- Our button is shown on the minimap only when the panel does not collect it; the other buttons follow the
-- collect / keep settings.
-- Free-standing collector button (when the panel is off): drag to move, click for the addon menu.
function M:CreateFloating()
    local b = CreateFrame("Button", "ForeverQoLPanelCollector", UIParent)
    b:SetSize(33, 33)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(10)
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(25, 25)
    bg:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    b:SetScript("OnClick", function(self, button)
        GameTooltip:Hide()
        if button == "RightButton" then ns.Options:Open() else M:ShowMenu(self) end
    end)
    b:SetScript("OnEnter", function(self)
        local L = ns.L
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ns.title, 1, 0.82, 0)
        GameTooltip:AddLine(string.format(L.BUTTONS_COLLECTED, M:CollectedCount()), 0.62, 0.62, 0.62)
        GameTooltip:AddLine(L.CLICK_ADDONS, 1, 1, 1)
        GameTooltip:AddLine(L.MM_CLICK_RIGHT_OPTIONS, 1, 1, 1)
        GameTooltip:AddLine(L.MM_DRAG, 0.62, 0.62, 0.62)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self) GameTooltip:Hide(); self:StartMoving() end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.db.minimap.floatPos = { point, rel, x, y }
    end)
    local pos = ns.db.minimap.floatPos
    b:ClearAllPoints()
    if pos then b:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else b:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -24) end
    self.floatButton = b
end

-- Some addons make their minimap button a secure frame: hiding or showing it in combat is blocked. Those wait for
-- the end of combat.
local pendingShow = {}
local function setShown(button, shown)
    if InCombatLockdown() and button.IsProtected and button:IsProtected() then
        pendingShow[button] = shown
        return
    end
    pendingShow[button] = nil
    if shown then button:Show() else button:Hide() end
end
M.SetButtonShown = setShown

function M:FlushPending()
    for button, shown in pairs(pendingShow) do setShown(button, shown) end
end

function M:Update()
    if self.floatButton then self.floatButton:SetShown(floating()) end
    local b = self.button
    if b then
        place(b, ns.db.minimap.angle)
        -- the collector button carries our entry, so ours leaves the minimap then
        b:SetShown(ns.db.minimap.show and not collecting())
    end
    for _, e in ipairs(self.entries) do
        if e.button then
            if collected(e) then setShown(e.button, false) elseif e.wasShown then setShown(e.button, true) end
        end
    end
    if collecting() then self:Scan() end
end
M.UpdateButton = M.Update

function M:CollectedCount()
    local n = 0
    for _, e in ipairs(self.entries) do if collected(e) then n = n + 1 end end
    return n
end

-- Collector -----------------------------------------------------------------------

local function iconOf(button)
    if button.dataObject and button.dataObject.icon then return button.dataObject.icon end
    if button.icon and button.icon.GetTexture then return button.icon:GetTexture() end
    for _, region in ipairs({ button:GetRegions() }) do
        if region:IsObjectType("Texture") and region:GetDrawLayer() == "ARTWORK" and region:GetTexture() then
            return region:GetTexture()
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function isBlizzard(name)
    for _, pattern in ipairs(BLIZZARD) do
        if name:find(pattern) then return true end
    end
    return false
end

local function candidate(f)
    if M.seen[f] or not f.IsObjectType or not (f:IsObjectType("Button") or f:IsObjectType("Frame")) then return false end
    local name = f.GetName and f:GetName()
    if not name or isBlizzard(name) then return false end
    if name:find("^LibDBIcon10_") then return true end
    local w, h = f:GetSize()
    return f:IsObjectType("Button") and w and w > 15 and w <= 40 and h <= 40 and f:GetScript("OnClick") ~= nil
end

-- One addon often shows up twice: as a minimap button ("FooMinimapButton") and in Blizzard's addon compartment
-- ("Foo"). Names are compared without case, spaces, punctuation and "minimap button" suffixes.
local function norm(name)
    local s = name:lower():gsub("[^%w]", ""):gsub("^libdbicon10", "")
    s = s:gsub("minimapbutton$", ""):gsub("minimapicon$", ""):gsub("minimap$", ""):gsub("button$", "")
    return s
end

local function sameAddon(a, b)
    if a == "" or b == "" then return false end
    if a == b then return true end
    if #a < 5 or #b < 5 then return false end
    return a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

local function findEntry(name)
    local n = norm(name)
    for _, e in ipairs(M.entries) do
        if sameAddon(norm(e.name), n) or (e.key and sameAddon(norm(e.key), n)) then return e end
    end
end

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- A button without a compartment entry is named after its frame ("PetSkillScoutMinimapButton"): the installed addon
-- with the same name gives the readable title instead.
local titles
local function addonTitle(buttonName)
    if not titles then
        titles = {}
        local num = C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns
        local info = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
        if num and info then
            for i = 1, num() do
                local name, title = info(i)
                if name then
                    title = strtrim(((title or name):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")))
                    titles[#titles + 1] = { norm(name), title ~= "" and title or name }
                end
            end
        end
    end
    local n = norm(buttonName)
    for _, t in ipairs(titles) do if t[1] == n then return t[2] end end
    for _, t in ipairs(titles) do if sameAddon(t[1], n) then return t[2] end end
    return nil
end

local function take(f)
    M.seen[f] = true
    local name = f:GetName():gsub("^LibDBIcon10_", "")
    local click = function(mouseButton)
        local onClick = f:GetScript("OnClick")
        if onClick then onClick(f, mouseButton or "LeftButton")
        elseif f.dataObject and f.dataObject.OnClick then f.dataObject.OnClick(f, mouseButton or "LeftButton") end
    end
    -- already listed through the addon compartment: that entry gets the button (and keeps its nicer name)
    local entry = findEntry(name)
    if entry and not entry.button then
        entry.key, entry.button, entry.click, entry.wasShown = name, f, click, f:IsShown()
        if entry.icon == QUESTION then entry.icon = iconOf(f) end
    else
        entry = { name = addonTitle(name) or name, key = name, icon = iconOf(f), click = click, button = f,
            wasShown = f:IsShown() }
        table.insert(M.entries, entry)
    end
    if collected(entry) then setShown(f, false) end
    -- addons show their buttons with Show or SetShown
    hooksecurefunc(f, "Show", function(self) if collected(entry) then setShown(self, false) end end)
    hooksecurefunc(f, "SetShown", function(self, shown) if shown and collected(entry) then setShown(self, false) end end)
end

function M:Scan()
    if not collecting() then return end
    for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
        if parent and parent.GetChildren then
            for _, child in ipairs({ parent:GetChildren() }) do
                if candidate(child) then take(child) end
            end
        end
    end
    -- addons registered in Blizzard's addon compartment
    local reg = AddonCompartmentFrame and AddonCompartmentFrame.registeredAddons
    if type(reg) == "table" then
        for _, a in ipairs(reg) do
            if not M.seen[a] and a.text and a.text ~= ns.title and (a.func or a.funcOnClick) then
                M.seen[a] = true
                local entry = findEntry(a.text)
                if entry then
                    -- the button is already listed: only its name gets nicer
                    entry.name = a.text
                    if entry.icon == QUESTION and a.icon then entry.icon = a.icon end
                else
                    table.insert(M.entries, { name = a.text, icon = a.icon or QUESTION,
                        click = function(mouseButton)
                            local fn = a.func or a.funcOnClick
                            if type(fn) == "function" then fn(a.text, mouseButton) end
                        end })
                end
            end
        end
    end
    table.sort(M.entries, function(a, b) return a.name:lower() < b.name:lower() end)
end

-- Our own entry comes first in the panel's menu.
function M:List()
    local list = { { name = ns.title, icon = ICON, click = M.Click } }
    for _, e in ipairs(self.entries) do list[#list + 1] = e end
    return list
end

local function label(e)
    local icon = e.icon
    if type(icon) == "number" or type(icon) == "string" then return "|T" .. icon .. ":16:16:0:0|t  " .. e.name end
    return e.name
end

-- The menu (Blizzard's context menu) with every collected addon, and a sub-menu to keep buttons on the minimap.
function M:ShowMenu(owner)
    local L = ns.L
    local list = self:List()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        print("|cffffd100" .. ns.title .. "|r: " .. L.NO_MENUS)
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L.ADDONS)
        for _, e in ipairs(list) do
            root:CreateButton(label(e), function(_, input) e.click(input and input.buttonName or "LeftButton") end)
        end
        local buttons = {}
        for _, e in ipairs(self.entries) do if e.button then buttons[#buttons + 1] = e end end
        if #buttons > 0 then
            root:CreateDivider()
            local sub = root:CreateButton(L.KEEP_ON_MINIMAP)
            sub:CreateTitle(L.KEEP_ON_MINIMAP_HINT)
            for _, e in ipairs(buttons) do
                sub:CreateCheckbox(label(e), function() return ns.db.minimap.keep[e.key or e.name] == true end, function()
                    ns.db.minimap.keep[e.key or e.name] = not ns.db.minimap.keep[e.key or e.name] or nil
                    setShown(e.button, not collected(e))
                end)
            end
        end
    end)
end

ns.OnLogin(function()
    M:CreateFloating()
    M:CreateButton()
    M:Scan()
    -- addons create their buttons at different times
    C_Timer.After(3, function() M:Scan() end)
    C_Timer.After(10, function() M:Scan() end)
    ns.On("PLAYER_REGEN_ENABLED", function() M:FlushPending() end)
end)

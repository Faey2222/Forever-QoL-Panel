local _, ns = ...

-- Move mode for everything that can be placed: the bars set free, the warning groups and the loot text. Like Edit
-- Mode: blue boxes to drag, an optional grid on the screen that dropped frames snap to (their edges or centre,
-- whichever is closest to a line), a small bar at the top with the grid settings; right-click, Esc or "Done" ends it.
local M = {}
ns.Mover = M
M.items = {}

local function db() return ns.db.layout end
local function L() return ns.L end

-- Grid ------------------------------------------------------------------------------

local grid
local function lines()
    if not grid then
        grid = CreateFrame("Frame", "ForeverQoLPanelGrid", UIParent)
        grid:SetAllPoints()
        grid:SetFrameStrata("BACKGROUND")
        grid:EnableMouse(false)
        grid.pool = {}
        grid:Hide()
    end
    return grid
end

function M:DrawGrid()
    local g = lines()
    for _, t in ipairs(g.pool) do t:Hide() end
    if not (self.active and db().grid) then g:Hide() return end
    local size = math.max(8, db().gridSize or 32)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local n = 0
    local function line(vertical, offset)
        n = n + 1
        local t = g.pool[n]
        if not t then t = g:CreateTexture(nil, "BACKGROUND"); g.pool[n] = t end
        t:ClearAllPoints()
        local centre = offset == 0
        t:SetColorTexture(centre and 1 or 1, centre and 0.35 or 1, centre and 0.35 or 1, centre and 0.5 or 0.12)
        if vertical then
            t:SetPoint("TOP", g, "TOP", offset, 0); t:SetPoint("BOTTOM", g, "BOTTOM", offset, 0); t:SetWidth(1)
        else
            t:SetPoint("LEFT", g, "LEFT", 0, offset); t:SetPoint("RIGHT", g, "RIGHT", 0, offset); t:SetHeight(1)
        end
        t:Show()
    end
    -- lines run out from the screen's centre, so centred things land on a line
    for x = 0, w / 2, size do line(true, x); if x > 0 then line(true, -x) end end
    for y = 0, h / 2, size do line(false, y); if y > 0 then line(false, -y) end end
    g:Show()
end

-- Snapping: a centre offset (UIParent units, from the screen centre) moved so that the frame's nearest edge or its
-- centre lies on a grid line. Without snapping just the offset.
local function snapOffsets(cx, cy, w, h)
    if db().snap then
        local size = math.max(8, db().gridSize or 32)
        local function snap(c, half)
            local bestD
            for _, edge in ipairs({ -half, 0, half }) do
                local v = c + edge
                local d = math.floor(v / size + 0.5) * size - v
                if not bestD or math.abs(d) < math.abs(bestD) then bestD = d end
            end
            return c + bestD
        end
        cx, cy = snap(cx, w / 2), snap(cy, h / 2)
    end
    return math.floor(cx + 0.5), math.floor(cy + 0.5)
end

-- size and scale ratio of a frame in UIParent units
local function measure(f)
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (f:GetWidth() or 0) * s, (f:GetHeight() or 0) * s, s
end

function M.SnapCenter(f)
    local x, y = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (x and ux) then return 0, 0 end
    local w, h, s = measure(f)
    return snapOffsets(x * s - ux, y * s - uy, w, h)
end

-- Dragging with the grid: the frame follows the cursor and jumps from line to line while it is dragged, so you see
-- where it lands. Used instead of StartMoving by everything the move mode places.
local driver = CreateFrame("Frame")
local function cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    local ux, uy = UIParent:GetCenter()
    return x / s - ux, y / s - uy
end

function M:StartDrag(f)
    local x, y = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (x and ux) then return end
    local w, h, s = measure(f)
    local mx, my = cursor()
    local dx, dy = x * s - ux - mx, y * s - uy - my
    self.dragged = f
    driver:SetScript("OnUpdate", function()
        local cx, cy = cursor()
        cx, cy = snapOffsets(cx + dx, cy + dy, w, h)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", cx / s, cy / s)
    end)
end

function M:StopDrag()
    driver:SetScript("OnUpdate", nil)
    self.dragged = nil
end

-- Registered frames (the bars set free) --------------------------------------------

-- opts: label() text, save(x, y) after a drop
function M:Register(frame, opts)
    local ov = CreateFrame("Frame", nil, frame)
    ov:SetAllPoints()
    ov:SetFrameLevel(frame:GetFrameLevel() + 20)
    ov.box = ov:CreateTexture(nil, "BACKGROUND")
    ov.box:SetPoint("TOPLEFT", -2, 2)
    ov.box:SetPoint("BOTTOMRIGHT", 2, -2)
    if not ns.SetAtlas(ov.box, "editSel", { "editmode-actionbar-selected-nineslice-center" }) then
        ov.box:SetColorTexture(0.25, 0.55, 1, 0.3)
    end
    ov.box:SetVertexColor(0.45, 0.7, 1, 0.55)
    ov.label = ov:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ov.label:SetPoint("BOTTOM", ov, "TOP", 0, 4)
    ov:RegisterForDrag("LeftButton")
    ov:SetScript("OnDragStart", function() if M.active then M:StartDrag(frame) end end)
    ov:SetScript("OnDragStop", function()
        M:StopDrag()
        opts.save(M.SnapCenter(frame))
    end)
    ov:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then M:Toggle(false) end end)
    ov:EnableMouse(false)
    ov:Hide()
    self.items[#self.items + 1] = { frame = frame, ov = ov, opts = opts }
end

function M:ShowItems()
    for _, it in ipairs(self.items) do
        local on = self.active and it.frame:IsShown()
        it.ov:SetShown(on)
        it.ov:EnableMouse(on and true or false)
        if on then it.ov.label:SetText(it.opts.label()) end
    end
end

-- The bar at the top ----------------------------------------------------------------

local bar
local function toolbar()
    if bar then return bar end
    bar = CreateFrame("Frame", "ForeverQoLPanelMoveBar", UIParent, "BackdropTemplate")
    bar:SetSize(460, 106)
    bar:SetPoint("TOP", UIParent, "TOP", 0, -90)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:EnableMouse(true)
    if bar.SetBackdrop then
        bar:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    end
    bar.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.title:SetPoint("TOPLEFT", 16, -12)
    bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.hint:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -4)
    local function check(key, x)
        local c = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
        c:SetSize(24, 24)
        c:SetPoint("BOTTOMLEFT", x, 8)
        local t = rawget(c, "text") or rawget(c, "Text")
        if type(t) ~= "table" then t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end
        c.text = t
        c.text:ClearAllPoints()
        c.text:SetPoint("LEFT", c, "RIGHT", 2, 0)
        c:SetScript("OnClick", function(self) db()[key] = self:GetChecked() and true or false; M:DrawGrid() end)
        c.key = key
        return c
    end
    bar.grid = check("grid", 14)
    bar.snap = check("snap", 130)
    bar.size = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    bar.size:SetSize(90, 22)
    bar.size:SetPoint("BOTTOMLEFT", 250, 9)
    bar.size:SetScript("OnClick", function()
        -- 16 -> 24 -> 32 -> 48 -> 64 -> 16
        local steps, cur = { 16, 24, 32, 48, 64 }, db().gridSize or 32
        local nxt = steps[1]
        for i, v in ipairs(steps) do if v == cur then nxt = steps[i % #steps + 1] end end
        db().gridSize = nxt
        M:UpdateBar()
        M:DrawGrid()
    end)
    -- where the bars are, switchable right here: a click goes to the next place
    local function cycle(key, places, x)
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetSize(210, 22)
        b:SetPoint("BOTTOMLEFT", x, 36)
        b:SetScript("OnClick", function()
            local p, cur, nxt = ns.db.panel, ns.db.panel[key], places[1]
            for i, v in ipairs(places) do if v == cur then nxt = places[i % #places + 1] end end
            p[key] = nxt
            ns.Refresh()
            M:UpdateBar()
            M:ShowItems()
        end)
        return b
    end
    bar.xp = cycle("xpPlace", { "panel", "free" }, 14)
    bar.rep = cycle("repPlace", { "attach", "below", "free" }, 236)
    bar.done = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    bar.done:SetSize(90, 22)
    bar.done:SetPoint("BOTTOMRIGHT", -14, 9)
    bar.done:SetScript("OnClick", function() M:Toggle(false) end)
    -- hidden first, the script after: hiding the new bar must not end the move mode it is being built for
    bar:Hide()
    -- Esc closes it like a window
    bar:SetScript("OnHide", function() if M.active then M:Toggle(false) end end)
    if UISpecialFrames then table.insert(UISpecialFrames, "ForeverQoLPanelMoveBar") end
    return bar
end

function M:UpdateBar()
    local b = toolbar()
    b.title:SetText(ns.title .. ": " .. L().MOVE_TITLE)
    b.hint:SetText(L().MOVE_HINT)
    b.grid.text:SetText(L().MOVE_GRID)
    b.snap.text:SetText(L().MOVE_SNAP)
    b.grid:SetChecked(db().grid)
    b.snap:SetChecked(db().snap)
    b.size:SetText(L().MOVE_SIZE:format(db().gridSize or 32))
    b.done:SetText(L().MOVE_DONE)
    local p = ns.db.panel
    local XP = { panel = L().PLACE_PANEL, free = L().PLACE_FREE_SHORT }
    local REP = { attach = L().REP_ATTACH, below = L().REP_BELOW, free = L().PLACE_FREE_SHORT }
    b.xp:SetText(L().MOVE_XPBAR .. ": " .. (XP[p.xpPlace or "panel"] or "?"))
    b.rep:SetText(L().MOVE_REPBAR .. ": " .. (REP[p.repPlace or "attach"] or "?"))
    b.xp:SetEnabled(p.enabled and p.xpbar and true or false)
    b.rep:SetEnabled(p.enabled and p.repBar and true or false)
end

-- Switching -------------------------------------------------------------------------

function M:Toggle(on)
    if on == nil then on = not self.active end
    if on and InCombatLockdown() then
        print("|cffffd100" .. ns.title .. "|r: " .. L().MOVE_COMBAT)
        return
    end
    -- switching off always ends every part (one may have been started on its own)
    if on and self.active then return end
    self.active = on and true or false
    if self.active then
        if ns.Options and ns.Options.frame and ns.Options.frame:IsShown() then ns.Options.frame:Hide() end
        self:UpdateBar()
        toolbar():Show()
    elseif bar then
        bar:Hide()
    end
    local w, g = ns.db.warnings, ns.db.gameplay
    if ns.Warnings and ns.Warnings.SetMoving and (not self.active or w.enabled) then ns.Warnings:SetMoving(self.active) end
    if ns.Gameplay and ns.Gameplay.SetLootMoving and (not self.active or (g.enabled and g.lootText)) then
        ns.Gameplay:SetLootMoving(self.active)
    end
    self:ShowItems()
    self:DrawGrid()
end

ns.OnLogin(function()
    ns.On("PLAYER_REGEN_DISABLED", function() if M.active then M:Toggle(false) end end)
    ns.On("DISPLAY_SIZE_CHANGED", function() if M.active then M:DrawGrid() end end)
end)

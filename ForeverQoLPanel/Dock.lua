local _, ns = ...

-- The panel: hangs from the top of the screen (or stands mirrored on the bottom), its border leaves the screen in an S-curve on each side and runs
-- into a straight line that is also the top border of the XP bar. Folded, only the XP bar stays visible.
local Dock = CreateFrame("Frame", "ForeverQoLPanelDock", UIParent)
ns.Dock = Dock
Dock:Hide()
Dock:SetFrameStrata("MEDIUM")
Dock:SetFrameLevel(20)
Dock:SetClampedToScreen(false)

-- Geometry in UI units; the textures are 2x (tools/gen_caps.py writes them with the same numbers).
local F, BH, BAR = 76, 26, 15            -- curve width, content height, XP bar height
local YP = BH + 5                         -- the straight line (panel bottom = XP bar top in "edge" style)
local CAP_X, CAP_Y, CAP_W, CAP_H = -16, -14, 112, 60   -- panel caps, reaching above the screen edge
local CAP_U, CAP_V = 224 / 256, 120 / 128
local BCAP_W, BCAP_H, BCAP_U, BCAP_V = 33, 32, 66 / 128, 1
-- border widths (setting "border" 1-3): texture suffix, straight edge: line offset, height, texture rows used
local WIDTH = {
    { suffix = "-thin", c = 4, h = 10.5, v = 21 / 32 },
    { suffix = "", c = 6, h = 16, v = 1 },
    { suffix = "-thick", c = 8, h = 21.5, v = 43 / 64 },
}
local SLIDE = 0.38

local FILL = { 0.03, 0.025, 0.02, 0.9 }

-- modern skin: flat, a thin border, square or round corners
local MPH, MBAR, MSIDE = BH + 2, 10, 12        -- panel height, bar height, side room
local MFILL = { 0.05, 0.05, 0.06, 0.88 }
local MBORDER = { bronze = { 0.52, 0.4, 0.24, 1 }, silver = { 0.56, 0.56, 0.6, 1 }, dark = { 0, 0, 0, 1 } }
local RIM_TINT = { bronze = { 1, 1, 1 }, silver = { 1, 1, 1 }, dark = { 0.42, 0.42, 0.42 } }

-- At the bottom of the screen the whole panel is mirrored: y counts from the screen edge either way.
local function bottom() return ns.db.panel.position == "bottom" end

function Dock:Anchor(f, x, y)
    if bottom() then f:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, y)
    else f:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y) end
end

local function put(t, x, y, w, h)
    t:ClearAllPoints()
    if w <= 0 or h <= 0 then t:Hide() return end
    Dock:Anchor(t, x, y)
    t:SetSize(w, h)
    t:Show()
end

local function tc(t, l, r, top, btm)
    if bottom() then t:SetTexCoord(l, r, btm, top) else t:SetTexCoord(l, r, top, btm) end
end

function Dock:Modern() return ns.db.panel.skin == "modern" end

-- room left and right of the elements: the classic curves need more
function Dock:Side() return self:Modern() and MSIDE or 46 end

-- A rectangle with an optional radius: fill (centre bands + quarter discs) and a 1-unit border (lines + arcs).
local CORNERS = { { 0, 1, 0, 1 }, { 1, 0, 0, 1 }, { 0, 1, 1, 0 }, { 1, 0, 1, 0 } }   -- TL, TR, BL, BR
local function newBox(fillParent, borderParent)
    local b = { fill = {}, border = {} }
    for i = 1, 7 do
        b.fill[i] = fillParent:CreateTexture(nil, "BACKGROUND", nil, 1)
        b.border[i] = borderParent:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    b.border[8] = borderParent:CreateTexture(nil, "OVERLAY", nil, 6)
    return b
end

local function boxHide(b)
    for _, t in ipairs(b.fill) do t:Hide() end
    for _, t in ipairs(b.border) do t:Hide() end
end

-- radii: one radius for all corners, or { TL, TR, BL, BR }; t: border thickness
local function boxSet(b, x, y, w, h, radii, fill, border, t)
    local f, e = b.fill, b.border
    t = t or 1
    local rr = type(radii) == "table" and radii or { radii, radii, radii, radii }
    local rTop, rBot = math.max(rr[1], rr[2]), math.max(rr[3], rr[4])
    -- fill: top band, middle, bottom band, round corners
    if fill then
        for i = 1, 3 do f[i]:SetColorTexture(fill[1], fill[2], fill[3], fill[4]) end
        put(f[1], x + rr[1], y, w - rr[1] - rr[2], rTop)
        put(f[2], x, y + rTop, w, h - rTop - rBot)
        put(f[3], x + rr[3], y + h - rBot, w - rr[3] - rr[4], rBot)
    else
        for i = 1, 3 do f[i]:Hide() end
    end
    -- border: top, bottom, left, right, then the arcs
    for i = 1, 4 do e[i]:SetColorTexture(border[1], border[2], border[3], border[4]) end
    put(e[1], x + rr[1], y, w - rr[1] - rr[2], t)
    put(e[2], x + rr[3], y + h - t, w - rr[3] - rr[4], t)
    put(e[3], x, y + rr[1], t, h - rr[1] - rr[3])
    put(e[4], x + w - t, y + rr[2], t, h - rr[2] - rr[4])
    for i = 1, 4 do
        local r = rr[i]
        local pos = ({ { x, y }, { x + w - r, y }, { x, y + h - r }, { x + w - r, y + h - r } })[i]
        local cf, ce = f[3 + i], e[4 + i]
        if r > 0 then
            local c = CORNERS[i]
            if fill then
                cf:SetTexture(ns.Tex("corner"))
                cf:SetVertexColor(fill[1], fill[2], fill[3], fill[4])
                put(cf, pos[1], pos[2], r, r)
                tc(cf, c[1], c[2], c[3], c[4])
            else
                cf:Hide()
            end
            ce:SetTexture(ns.Tex((r >= 5 and "corner-ring-6-" or "corner-ring-3-") .. math.min(3, t)))
            ce:SetVertexColor(border[1], border[2], border[3], border[4])
            put(ce, pos[1], pos[2], r, r)
            tc(ce, c[1], c[2], c[3], c[4])
        else
            cf:Hide()
            ce:Hide()
        end
    end
end

function Dock:Init()
    local p = ns.db.panel
    if not p.enabled then return end

    -- background (white textures tinted with FILL, so the caps and the colour texture in between match)
    self.fillL = self:CreateTexture(nil, "BACKGROUND")
    self.fillR = self:CreateTexture(nil, "BACKGROUND")
    for _, t in ipairs({ self.fillL, self.fillR }) do
        t:SetTexture(ns.Tex("cap-panel-fill"))
        t:SetVertexColor(unpack(FILL))
    end
    self.fillM = self:CreateTexture(nil, "BACKGROUND")
    self.fillM:SetColorTexture(unpack(FILL))

    self.band = CreateFrame("Frame", nil, self)
    self.band:SetFrameLevel(self:GetFrameLevel() + 2)
    self.band:SetHeight(BH)

    self.bar = ns.XP:Create(self)

    -- border on top of everything
    self.rim = CreateFrame("Frame", nil, self)
    self.rim:SetFrameLevel(self:GetFrameLevel() + 6)
    self.rim:SetAllPoints()
    -- the panel's line lies above the bar's own border: the bar's round ends start under it and disappear there
    local function rimTex(sub) return self.rim:CreateTexture(nil, "OVERLAY", nil, sub) end
    self.capL, self.capR, self.edge = rimTex(4), rimTex(4), rimTex(4)
    self.bcapL, self.bcapR, self.thinB, self.thinT = rimTex(0), rimTex(0), rimTex(0), rimTex(0)

    -- modern skin: the panel's box (fill below everything, border on the rim frame) and the bar's border
    self.mPanel = newBox(self, self.rim)
    self.mBar = newBox(self, self.rim)

    ns.Elements:Build(self.band)

    self.open, self.offset = true, 0
    self:Show()
    self:Refresh()

    C_Timer.After(5, function()
        ns.Debug.Call("XP:Describe", ns.XP.Describe, ns.XP)
        ns.Debug.Call("Hearth", ns.Elements.DescribeHearth, ns.Elements)
    end)
    self.lastHover = GetTime()
    C_Timer.NewTicker(0.1, function() self:CheckHover() end)
    C_Timer.NewTicker(1, function()
        ns.Elements:UpdateTexts()
        self:Relayout()
    end)
end

-- Rebuilds everything that depends on settings.
function Dock:Refresh()
    if not self.band then return end
    local p = ns.db.panel
    local width = WIDTH[p.border or 2] or WIDTH[2]
    local suffix = width.suffix .. (p.rim == "bronze" and "" or "-silver")
    local tint = RIM_TINT[p.rim] or RIM_TINT.bronze
    self.capL:SetTexture(ns.Tex("cap-panel" .. suffix))
    self.capR:SetTexture(ns.Tex("cap-panel" .. suffix))
    self.edge:SetTexture(ns.Tex("edge" .. suffix), "REPEAT", "CLAMP")
    local bcap = (p.style == "rail" and "cap-bar" or "cap-bar-open") .. suffix
    self.bcapL:SetTexture(ns.Tex(bcap))
    self.bcapR:SetTexture(ns.Tex(bcap))
    self.thinB:SetTexture(ns.Tex("edge-bar" .. suffix), "REPEAT", "CLAMP")
    self.thinT:SetTexture(ns.Tex("edge-bar-top" .. suffix), "REPEAT", "CLAMP")
    for _, t in ipairs({ self.capL, self.capR, self.edge, self.bcapL, self.bcapR, self.thinB, self.thinT }) do
        t:SetVertexColor(unpack(tint))
    end
    ns.XP:ApplySkin(self:Modern())
    ns.Elements.ApplyFont()
    ns.Elements:ApplyIcons()
    ns.Elements:ResetWidths()
    ns.Elements:UpdateTexts()
    self.bar:SetShown(p.xpbar)
    self.width = nil
    self:Relayout()
    ns.XP:Update()
    self:HideBlizzardXP()
    if p.pinned then self:SetOpen(true) end
end

-- Lays the panel out again when the content width changed (texts change every second).
function Dock:Relayout()
    local W = ns.Elements:Layout()
    ns.Elements:PlaceHearthButton()
    if W == self.width then return end
    self.width = W
    self:Layout(W)
end

function Dock:Layout(W)
    if self:Modern() then return self:LayoutModern(W) end
    boxHide(self.mPanel)
    boxHide(self.mBar)
    local p = ns.db.panel
    local rail = p.style == "rail"
    local r = BAR / 2
    W = math.max(W, 2 * 96 + 40)

    -- the XP bar has its own width; it never gets wider than the panel's straight line allows
    local minCx = rail and F + 12 or F
    local bw = math.min(p.barWidth, W - 2 * minCx + BAR)
    local cx = math.floor((W - bw) / 2 + r + 0.5)          -- centre of the bar's round ends
    local top = rail and YP + p.gap or YP                   -- bar top
    local x0, x1 = cx - r, W - cx + r
    local H = p.xpbar and top + BAR + 8 or YP + 12
    self:SetSize(W, H)
    self.band:SetWidth(W)
    self.band:ClearAllPoints()
    self.band:SetPoint(bottom() and "BOTTOMLEFT" or "TOPLEFT")

    put(self.fillL, CAP_X, CAP_Y, CAP_W, CAP_H); tc(self.fillL, 0, CAP_U, 0, CAP_V)
    put(self.fillR, W - 96, CAP_Y, CAP_W, CAP_H); tc(self.fillR, CAP_U, 0, 0, CAP_V)
    put(self.fillM, 96, CAP_Y, W - 192, YP - CAP_Y)

    put(self.capL, CAP_X, CAP_Y, CAP_W, CAP_H); tc(self.capL, 0, CAP_U, 0, CAP_V)
    put(self.capR, W - 96, CAP_Y, CAP_W, CAP_H); tc(self.capR, CAP_U, 0, 0, CAP_V)
    local width = WIDTH[p.border or 2] or WIDTH[2]
    put(self.edge, 96, YP - width.c, W - 192, width.h); tc(self.edge, 0, (W - 192) * 2 / 256, 0, width.v)

    -- the bar's own border: the straight pieces are drawn on the caps' canvas (same height, same rows) and sit at
    -- the caps' position, so the seams line up exactly
    local e0, e1 = cx + 20, W - cx - 20
    local u = (e1 - e0) * 2 / 256
    put(self.bcapL, cx - 13, top - 8, BCAP_W, BCAP_H); tc(self.bcapL, 0, BCAP_U, 0, BCAP_V)
    put(self.bcapR, W - cx - 20, top - 8, BCAP_W, BCAP_H); tc(self.bcapR, BCAP_U, 0, 0, BCAP_V)
    put(self.thinB, e0, top - 8, e1 - e0, BCAP_H); tc(self.thinB, 0, u, 0, BCAP_V)
    if rail then
        put(self.thinT, e0, top - 8, e1 - e0, BCAP_H); tc(self.thinT, 0, u, 0, BCAP_V)
    else
        self.thinT:Hide()
    end
    if not p.xpbar then
        for _, t in ipairs({ self.bcapL, self.bcapR, self.thinB, self.thinT }) do t:Hide() end
    end

    ns.XP:SetGeometry(x0, top, x1 - x0, BAR)
    -- folded: in "edge" style the line (the bar's top border) leaves the screen; "rail" keeps the bar's border;
    -- without the XP bar the whole panel leaves
    self.folded = not p.xpbar and YP + 16 or rail and top - 4 or YP + 5
    self:SetOffset(self.open and (self.offset or 0) or self.folded)
end

-- Modern skin: a flat rectangle hanging from the screen edge (its far corners off screen), the XP bar sharing its
-- bottom border ("edge") or with its own border below ("rail").
function Dock:LayoutModern(W)
    local p = ns.db.panel
    local rail = p.style == "rail"
    W = math.max(W, 200)
    local r = p.corners == "round" and 6 or 0
    -- the bar's corners as round as the panel's: with the border on top, the bar's square ends disappear under the arcs
    local br = p.corners == "round" and 6 or 0
    local tint = MBORDER[p.rim] or MBORDER.bronze
    local th = p.border or 2                                -- border thickness: 1, 2 or 3 units
    for _, t in ipairs({ self.fillL, self.fillR, self.fillM, self.capL, self.capR, self.edge,
        self.bcapL, self.bcapR, self.thinB, self.thinT }) do t:Hide() end

    local bw = math.min(p.barWidth, W - 2 * MSIDE)
    local x0 = math.floor((W - bw) / 2 + 0.5)
    local top = rail and MPH + p.gap or MPH
    local H = p.xpbar and top + MBAR + th or MPH + th
    self:SetSize(W, H)
    self.band:SetWidth(W)
    self.band:ClearAllPoints()
    self.band:SetPoint(bottom() and "BOTTOMLEFT" or "TOPLEFT")

    boxSet(self.mPanel, 0, -8, W, MPH + 8, r, MFILL, tint, th)
    if p.xpbar then
        -- hanging from the panel, the bar's upper corners stay square (they meet the panel's line)
        local radii = rail and br or { 0, 0, br, br }
        boxSet(self.mBar, x0 - th, top - th, bw + 2 * th, MBAR + 2 * th, radii, nil, tint, th)
    else
        boxHide(self.mBar)
    end
    ns.XP:SetGeometry(x0, top, bw, MBAR)
    self.folded = not p.xpbar and MPH + 8 or rail and top - th or MPH
    self:SetOffset(self.open and (self.offset or 0) or self.folded)
end

-- Slide in and out --------------------------------------------------------------

function Dock:SetOffset(y)
    self.offset = y
    self:ClearAllPoints()
    if bottom() then self:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, -math.floor(y + 0.5))
    else self:SetPoint("TOP", UIParent, "TOP", 0, math.floor(y + 0.5)) end
    -- the elements fade while the panel slides
    local k = self.folded and self.folded > 0 and math.min(1, math.max(0, y / self.folded)) or 0
    self.band:SetAlpha(ns.db.panel.animations and 1 - k * k or (k < 1 and 1 or 0))
    ns.Elements:PlaceHearthButton()
end

function Dock:SetOpen(open)
    if self.open == open then return end
    self.open = open
    local from, to = self.offset, open and 0 or self.folded
    local t = 0
    self:SetScript("OnUpdate", function(_, elapsed)
        t = math.min(1, t + elapsed / SLIDE)
        local e = t * t * (3 - 2 * t)
        self:SetOffset(from + (to - from) * e)
        if t >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

function Dock:CheckHover()
    local p = ns.db.panel
    local now = GetTime()
    if p.pinned or (bottom() and self:IsMouseOver(2, 0, 0, 0) or not bottom() and self:IsMouseOver(0, -2, 0, 0)) or ns.Elements.dragging then
        self.lastHover = now
        self:SetOpen(true)
    elseif self.open and now - self.lastHover > p.delay then
        self:SetOpen(false)
    end
end

-- Blizzard's own XP bar is replaced by ours (only faded out, the Edit Mode keeps its place). Turning the option
-- off brings it back with its mouse handling as it was.
local mouseState = {}
function Dock:HideBlizzardXP()
    local p = ns.db.panel
    local hide = p.enabled and p.xpbar and p.hideBlizzardXP
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "StatusTrackingBarManager" }) do
        local f = _G[name]
        if f then
            local frames = { f, f:GetChildren() }
            if hide then
                f:SetAlpha(0)
                for _, fr in ipairs(frames) do
                    if mouseState[fr] == nil and fr.IsMouseEnabled then mouseState[fr] = fr:IsMouseEnabled() end
                    pcall(fr.EnableMouse, fr, false)
                end
            elseif self.blizzardHidden then
                f:SetAlpha(1)
                for _, fr in ipairs(frames) do
                    if mouseState[fr] ~= nil then pcall(fr.EnableMouse, fr, mouseState[fr]) end
                end
            end
        end
    end
    self.blizzardHidden = hide
end

ns.OnLogin(function() Dock:Init() end)

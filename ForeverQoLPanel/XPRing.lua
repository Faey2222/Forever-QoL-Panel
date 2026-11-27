local _, ns = ...

-- The XP bar around the minimap (XP place "minimap"): the same layers as the bar (earned, rested, finished quests, the
-- whole quest log) clockwise from the top, the bar's tick marks, the panel's rim colour, and the bar's tooltip when
-- the mouse is on it. Round minimap: a ring, each fill a cooldown swipe with a ring texture frozen at its share (the
-- one way the client draws a part of a circle). Square minimap (ours or another addon's): a square frame of straight
-- pieces. It lies below the minimap (background strata) and takes no clicks, so the map and its buttons work as before.
-- One class, two rings: the XP ring (ns.Ring) and the reputation ring (ns.RepRing, place "minimap" of the reputation
-- bar), the latter outside the XP ring when that is shown, else right at the map.
local Ring = {}

-- Round: the panel's XP bar revolved (tools/gen_ring.py): media/ring-<k>-frame-<metal>.tga is the empty bar with both
-- borders, ring-<k>-<layer>.tga the fills in the bar's colours; k = the band in % of the outer radius.
local WIDTHS = { thin = 11, medium = 15, wide = 19 }
local UNITS = { thin = 9, medium = 12, wide = 15 }      -- square: band in UI units
-- the reputation ring is finer at every width (its larger radius would make the same share wider)
local REP_WIDTHS = { thin = 8, medium = 11, wide = 15 }
local REP_UNITS = { thin = 6, medium = 9, wide = 12 }
local RIM = { bronze = { 0.59, 0.45, 0.3, 1 }, silver = { 0.66, 0.66, 0.72, 1 }, dark = { 0.08, 0.08, 0.08, 1 } }
-- square: the bar's colours, flat
local COLORS = {
    bg = { 0.012, 0.016, 0.02, 0.95 }, fill = { 0.03, 0.14, 0.64, 1 }, rested = { 0.03, 0.08, 0.3, 1 },
    log = { 0.15, 0.2, 0.36, 1 }, gold = { 0.2, 0.16, 0.05, 1 },
}
local WHITE = { 1, 1, 1, 1 }
-- the looks of finished quests (the bar's questStyle): round texture (ring-<k>-<tex>, white shapes tinted) and colour,
-- square colour; shimmer and the ready pulse move the layer's alpha
local GOLD = { 1, 0.78, 0.2 }
local QSTYLE = {
    veil = {},
    glow = { tex = "q-solid", color = { GOLD[1], GOLD[2], GOLD[3], 0.55 }, square = { GOLD[1], GOLD[2], GOLD[3], 0.55 } },
    shimmer = { tex = "q-solid", color = { GOLD[1], GOLD[2], GOLD[3], 0.45 }, square = { GOLD[1], GOLD[2], GOLD[3], 0.45 }, shimmer = true },
    line = { tex = "q-line", color = { GOLD[1], GOLD[2], GOLD[3], 1 }, square = { GOLD[1], GOLD[2], GOLD[3], 1 }, thin = true },
    frame = { tex = "q-frame", color = { GOLD[1], GOLD[2], GOLD[3], 1 }, square = { GOLD[1], GOLD[2], GOLD[3], 0.35 } },
    stripes = { tex = "q-stripes", color = { GOLD[1], GOLD[2], GOLD[3], 0.75 }, square = { GOLD[1], GOLD[2], GOLD[3], 0.4 } },
}
local LAYERS = { "log", "rested", "gold", "fill" }     -- bottom to top; each starts at the top, the next covers it
local STEP = 5                                          -- tick marks are possible every 5 %
local RIM_OUT_PX = 2.3 * 1.6                           -- the outer border's width in texture pixels (tools/gen_ring.py)
local EDGE = 127 / 128                                  -- where the ring textures' outer edge lies (tools/gen_ring.py: R = N / 2 - 1)
local min, max, sqrt, sin, cos, pi, abs = math.min, math.max, math.sqrt, math.sin, math.cos, math.pi, math.abs

local function p() return ns.db.panel end
local function plain(v) return type(v) == "number" and not ns.Secret(v) and v or nil end

-- "round", "square" or nil (a shape the ring cannot follow)
function Ring.Shape()
    if not Minimap then return nil end
    local shape = "ROUND"
    if GetMinimapShape then
        local ok, s = pcall(GetMinimapShape)
        if ok and type(s) == "string" then shape = s end
    end
    if shape == "ROUND" then return "round" end
    if shape == "SQUARE" then return "square" end
    return nil
end

function Ring.Supported() return Ring.Shape() ~= nil end

local XPRING, REPRING, PETRING   -- the instances, made at the end

-- what the player wants and can have: XP place "minimap", the XP bar on, not at the highest level
function Ring.Wanted()
    local panel = p()
    return panel.xpPlace == "minimap" and panel.xpbar and not (ns.XP.AtMaxLevel and ns.XP.AtMaxLevel())
        and Ring.Supported() or false
end

-- reputation ring: place "minimap", a watched faction, the bar on
function Ring.RepWanted()
    local panel = p()
    return panel.repPlace == "minimap" and ns.Rep and ns.Rep:Active() and Ring.Supported() or false
end

-- the hunter pet's ring: place "minimap" of the pet bar; it takes the XP ring's place, so not with the XP ring
function Ring.PetWanted()
    local panel = p()
    return panel.petPlace == "minimap" and ns.PetXP and ns.PetXP:Active() and not Ring.Wanted() and Ring.Supported() or false
end

function Ring:IsWanted()
    if self.kind == "rep" then return Ring.RepWanted() end
    if self.kind == "pet" then return Ring.PetWanted() end
    return Ring.Wanted()
end

-- Round: frozen cooldown swipes -----------------------------------------------------------

local function newArc(f, color)
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(f)
    cd.noCooldownCount = true                       -- OmniCC and the like: no numbers on the ring
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
    if cd.SetReverse then cd:SetReverse(true) end   -- the swipe covers the part that has run: filled clockwise from the top
    cd.color = color
    cd:EnableMouse(false)
    return cd
end

-- shows a share (0..1) of the ring. The start must not lie before the client's clock began (GetTime counts from the
-- computer's start): a long cooldown ending in the past would not draw at all.
local function setArc(cd, share, tex, color)
    if color then cd.color = color end
    share = plain(share) or 0
    if share <= 0.001 then cd:Hide(); cd.share = nil return end
    share = min(share, 0.9995)
    if cd.tex ~= tex then
        cd.tex = tex
        if cd.SetSwipeTexture then cd:SetSwipeTexture(tex) end
    end
    if cd.SetSwipeColor then cd:SetSwipeColor(unpack(cd.color)) end
    cd:Show()
    local now = GetTime()
    local dur = max(10, min(3600, now * 0.9))
    if cd.Resume then pcall(cd.Resume, cd) end
    cd:SetCooldown(now - share * dur, dur)
    cd.paused = cd.Pause and pcall(cd.Pause, cd) or false
    cd.share, cd.setAt = share, now
end

-- Square: straight pieces along the frame ------------------------------------------------
-- The path runs on the band's middle line, clockwise from the top centre: half the top, right, bottom, left, half the
-- top. A share covers the first share * length of it; pieces meeting a corner reach half a band further to fill it.

local function pieces(h, share)
    local out, len, left = {}, 8 * h, share * 8 * h
    local sides = {   -- from (x1, y1) to (x2, y2), corner at start / end
        { 0, h, h, h, false, true }, { h, h, h, -h, true, true }, { h, -h, -h, -h, true, true },
        { -h, -h, -h, h, true, true }, { -h, h, 0, h, true, false },
    }
    for _, s in ipairs(sides) do
        if left <= 0 then break end
        local x1, y1, x2, y2 = s[1], s[2], s[3], s[4]
        local sl = abs(x2 - x1) + abs(y2 - y1)
        local part = min(1, left / sl)
        left = left - sl
        out[#out + 1] = { x1, y1, x1 + (x2 - x1) * part, y1 + (y2 - y1) * part, s[5], s[6] and part >= 1 }
    end
    return out, len
end

local function drawStrips(f, list, set, h, t, color)
    local ps = pieces(h, set)
    for i = 1, 5 do
        local tex, pc = list[i], ps[i]
        if pc then
            local x1, y1, x2, y2 = pc[1], pc[2], pc[3], pc[4]
            local ext1, ext2 = pc[5] and t / 2 or 0, pc[6] and t / 2 or 0
            local w, hgt, cx, cy
            if y1 == y2 then                            -- horizontal
                local dir = x2 >= x1 and 1 or -1
                local a, b = x1 - dir * ext1, x2 + dir * ext2
                w, hgt, cx, cy = abs(b - a), t, (a + b) / 2, y1
            else
                local dir = y2 >= y1 and 1 or -1
                local a, b = y1 - dir * ext1, y2 + dir * ext2
                w, hgt, cx, cy = t, abs(b - a), x1, (a + b) / 2
            end
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", f, "CENTER", cx, cy)
            tex:SetSize(max(0.1, w), max(0.1, hgt))
            tex:SetColorTexture(unpack(color))
            tex:SetShown(w > 0.05 and hgt > 0.05)
        else
            tex:Hide()
        end
    end
end

-- The frame -------------------------------------------------------------------------------

function Ring:Create()
    if self.frame then return self.frame end
    local me = self
    local NAMES = { xp = "ForeverQoLPanelXPRing", rep = "ForeverQoLPanelRepRing", pet = "ForeverQoLPanelPetRing" }
    local f = CreateFrame("Frame", NAMES[self.kind], UIParent)
    f:SetFrameStrata("BACKGROUND")
    if self.kind == "rep" then f:SetFrameLevel(20) end   -- above the XP ring (its layers use levels up to +8)
    f:EnableMouse(false)
    -- round
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.arcs = {}
    for i, key in ipairs(LAYERS) do
        f.arcs[key] = newArc(f, WHITE)
        f.arcs[key]:SetFrameLevel(f:GetFrameLevel() + i)
    end
    -- square: background, the four layers and the rim lines (outer and inner, four each)
    f.sq = { bg = {} }
    for i = 1, 5 do f.sq.bg[i] = f:CreateTexture(nil, "BACKGROUND") end
    for i, key in ipairs(LAYERS) do
        f.sq[key] = {}
        for j = 1, 5 do f.sq[key][j] = f:CreateTexture(nil, "ARTWORK", nil, i) end
    end
    -- ticks and rim above the fills
    f.top = CreateFrame("Frame", nil, f)
    f.top:SetAllPoints()
    f.top:SetFrameLevel(f:GetFrameLevel() + 8)
    f.ticks = {}
    for i = 1, 100 / STEP - 1 do
        local t = f.top:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(0, 0, 0, 0.6)
        f.ticks[i] = t
    end
    f.rim = f.top:CreateTexture(nil, "OVERLAY")
    f.rim:SetAllPoints()
    f.lines = {}
    for i = 1, 8 do f.lines[i] = f.top:CreateTexture(nil, "OVERLAY") end
    -- the tooltip: the mouse position is checked a few times a second, as the ring takes no mouse itself; the frozen
    -- fills are set again now and then in case the client cannot pause a cooldown
    local acc, re = 0, 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc, re = acc + elapsed, re + elapsed
        me:Animate()
        if re > 5 then re = 0; me:Reapply() end
        if acc < 0.1 then return end
        acc = 0
        me:CheckHover()
    end)
    f:Hide()
    -- shown and hidden with the minimap
    if Minimap.HookScript then
        Minimap:HookScript("OnShow", function() me:Refresh() end)
        Minimap:HookScript("OnHide", function() if me.frame then me.frame:Hide() end end)
    end
    self.frame = f
    if self.kind == "rep" then
        hooksecurefunc(ns.Rep, "Update", function() ns.Debug.Call("RepRing", me.Update, me) end)
    elseif self.kind == "pet" then
        hooksecurefunc(ns.PetXP, "Update", function() ns.Debug.Call("PetRing", me.Update, me) end)
    else
        hooksecurefunc(ns.XP, "Update", function() ns.Debug.Call("XPRing", me.Update, me) end)
    end
    return f
end

-- size and look from the minimap and the settings
function Ring:Layout()
    local f = self.frame
    local panel = p()
    local rep = self.kind == "rep"
    local width = rep and (panel.repRingWidth or "thin") or (panel.ringWidth or "medium")
    local mw = plain(Minimap:GetWidth()) or 140
    local gap = rep and (panel.repRingGap or 2) or (panel.ringGap or 2)
    -- the reputation ring: outside the inner ring (XP, or the pet's in its place) when that is shown, else at the map
    local inner = (XPRING.frame and XPRING.frame:IsShown() and XPRING) or (PETRING.frame and PETRING.frame:IsShown() and PETRING)
    local xpOn = rep and inner and inner.shape
    self.base = nil
    if xpOn then
        -- round: from the XP ring's visible outer edge. At 0 the reputation ring's inner border lies right on the XP
        -- ring's outer one (drawn above it): one border between the two. The border is 2.3 texture units of 256 wide.
        if inner.shape == "round" then
            local vis = inner.outer * EDGE
            local rimW = RIM_OUT_PX * (inner.outer * 2 / 256)
            self.base = gap > 0 and (vis + gap) or (vis - rimW)
        else
            -- square: at 0 the reputation frame's inner line on the XP frame's outer line
            self.base = inner.h + inner.t / 2 + (gap > 0 and gap or -1)
        end
    end
    local rim = RIM[panel.rim or "bronze"] or RIM.bronze
    self.shape = Ring.Shape()
    f:ClearAllPoints()
    f:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    -- the bar's setting: every 5, 10, 20 or 25 %, 0 = none
    local every = rep and (panel.repTicks or 10) or (self.kind == "pet" and (panel.petTicks or 10)) or (panel.ticks or 10)
    if self.shape == "round" then
        local k = (rep and REP_WIDTHS or WIDTHS)[width] or WIDTHS.medium
        -- the band's inner edge `gap` outside the map (or at base); the textures' ring ends a pixel before their edge
        local outer = (self.base or (mw / 2 + gap)) / ((1 - k / 100) * EDGE) + 0.5
        self.outer, self.inner = outer, outer * (1 - k / 100)
        f:SetSize(outer * 2, outer * 2)
        self.k = k
        -- the empty bar with its borders; the dark rim is the silver one darkened
        local metal = panel.rim == "bronze" and "bronze" or "silver"
        f.bg:SetTexture(ns.Tex("ring-" .. k .. "-frame-" .. metal))
        if panel.rim == "dark" then f.bg:SetVertexColor(0.3, 0.3, 0.3, 1) else f.bg:SetVertexColor(1, 1, 1, 1) end
        f.bg:Show()
        f.rim:Hide()
        for _, t in ipairs(f.sq.bg) do t:Hide() end
        for _, key in ipairs(LAYERS) do for _, t in ipairs(f.sq[key]) do t:Hide() end end
        for _, t in ipairs(f.lines) do t:Hide() end
        -- ticks across the fill zone only (the borders are about 2.3 and 2 units wide)
        local mid, len = (self.outer - 2.3 + self.inner + 2) / 2, self.outer - self.inner - 4.3
        for i, t in ipairs(f.ticks) do
            local pct = i * STEP
            local a = pct / 100 * 2 * pi                -- clockwise from the top
            t:ClearAllPoints()
            t:SetSize(1, len)
            t:SetPoint("CENTER", f, "CENTER", sin(a) * mid, cos(a) * mid)
            if t.SetRotation then pcall(t.SetRotation, t, -a) end
            t:SetShown(every > 0 and pct % every == 0)
        end
    else
        -- square: outside our own border when it is there
        local pad = ns.MinimapShape and ns.MinimapShape.RingPad() or 0
        local t = (rep and REP_UNITS or UNITS)[width] or UNITS.medium
        local half = self.base or (mw / 2 + pad + gap)
        self.h, self.t = half + t / 2, t                  -- h: the band's middle line
        f:SetSize((half + t) * 2, (half + t) * 2)
        f.bg:Hide(); f.rim:Hide()
        for _, cd in pairs(f.arcs) do cd:Hide() end
        drawStrips(f, f.sq.bg, 1, self.h, t, COLORS.bg)
        -- rim: outer and inner lines
        local o, i = half + t, half
        local L = f.lines
        local function line(tex, x, y, w, hh) tex:ClearAllPoints(); tex:SetPoint("CENTER", f, "CENTER", x, y); tex:SetSize(w, hh); tex:SetColorTexture(unpack(rim)); tex:Show() end
        line(L[1], 0, o - 0.5, 2 * o, 1); line(L[2], 0, -o + 0.5, 2 * o, 1); line(L[3], -o + 0.5, 0, 1, 2 * o); line(L[4], o - 0.5, 0, 1, 2 * o)
        line(L[5], 0, i + 0.5, 2 * i + 2, 1); line(L[6], 0, -i - 0.5, 2 * i + 2, 1); line(L[7], -i - 0.5, 0, 1, 2 * i + 2); line(L[8], i + 0.5, 0, 1, 2 * i + 2)
        -- ticks across the band, at their place on the path
        for n, tex in ipairs(f.ticks) do
            local pct = n * STEP
            local ps = pieces(self.h, pct / 100)
            local last = ps[#ps]
            tex:ClearAllPoints()
            if last[2] == last[4] then tex:SetSize(1, t - 2) else tex:SetSize(t - 2, 1) end
            tex:SetPoint("CENTER", f, "CENTER", last[3], last[4])
            if tex.SetRotation then pcall(tex.SetRotation, tex, 0) end
            -- not on a corner (the frame's corners are on 12.5, 37.5, ... %)
            tex:SetShown(every > 0 and pct % every == 0)
        end
    end
end

function Ring:Refresh()
    if not self:IsWanted() or not Minimap:IsShown() then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Create()
    self:Layout()
    self.frame:Show()
    self:Update()
end

function Ring:UpdateRep()
    local f = self.frame
    local share, r, g, b
    if self.kind == "pet" then
        local name, _, cur, nxt = ns.PetXP:Data()
        if not name then return end
        share = cur / nxt
        r, g, b = ns.PetXP.Color()
    else
        local _, reaction, value, size = ns.Rep:Data()
        if not reaction then return end
        share = size > 0 and value / size or 0
        r, g, b = ns.Rep.Color(reaction)
    end
    for _, key in ipairs(LAYERS) do
        if key ~= "fill" then
            f.arcs[key]:Hide()
            for _, t in ipairs(f.sq[key]) do t:Hide() end
        end
    end
    self.shares = { fill = share }
    if self.shape == "round" then
        setArc(f.arcs.fill, share, ns.Tex("ring-" .. self.k .. "-shade"), { r, g, b, 1 })
    else
        drawStrips(f, f.sq.fill, share, self.h, self.t - 2, { r * 0.8, g * 0.8, b * 0.8, 1 })
    end
    if self.hover then if self.kind == "pet" then ns.PetXP:ShowTooltip(f) else ns.Rep:ShowTooltip(f) end end
end

function Ring:Update()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    if self.kind ~= "xp" then return self:UpdateRep() end
    local XP = ns.XP
    if XP.questsDirty then XP.questsDirty = false; XP.ScanQuests() end
    local panel = p()
    local share, cur, mx = XP:Targets()
    local rest = (GetXPExhaustion and GetXPExhaustion()) or 0
    local q = panel.questPreview and (XP.cachedQuestXP or 0) or 0
    local all = panel.logPreview and (XP.cachedLogXP or 0) or 0
    local shares = {
        fill = share, rested = min(1, share + rest / mx),
        gold = q > 0 and min(1, share + q / mx) or 0, log = all > 0 and min(1, share + all / mx) or 0,
    }
    self.shares = shares
    -- finished quests in the look chosen for the bar (questStyle), pulsing when they are enough for the level
    local style = panel.questStyle or "veil"
    local qs = QSTYLE[style] or QSTYLE.veil
    self.ready = q > 0 and cur + q >= mx
    self.qstyle = style
    for _, key in ipairs(LAYERS) do
        if self.shape == "round" then
            if key == "gold" then
                local tex = qs.tex and ns.Tex("ring-" .. self.k .. "-" .. qs.tex) or ns.Tex("ring-" .. self.k .. "-gold")
                setArc(f.arcs.gold, shares.gold, tex, qs.color or WHITE)
            else
                setArc(f.arcs[key], shares[key], ns.Tex("ring-" .. self.k .. "-" .. key))
            end
        elseif key == "gold" then
            drawStrips(f, f.sq.gold, shares.gold, self.h, qs.thin and 2 or (self.t - 2), qs.square or COLORS.gold)
        else
            drawStrips(f, f.sq[key], shares[key], self.h, self.t - 2, COLORS[key])
        end
    end
    local fill = f.arcs.fill
    ns.Debug.Set("xpRing", { shape = self.shape, share = share, gold = shares.gold, paused = fill.paused,
        shown = fill:IsShown(), swipe = fill.SetSwipeTexture ~= nil, now = GetTime() })
    if self.hover then XP:ShowTooltip(f) end
end

-- shimmer: the quest layer breathes slowly; ready (enough for the level, readyPulse on): it pulses faster
function Ring:Animate()
    if self.kind ~= "xp" then return end
    local f = self.frame
    local panel = p()
    local moving = panel.animations ~= false
    local pulse = moving and self.ready and panel.readyPulse
    local shimmer = moving and self.qstyle == "shimmer"
    local a = 1
    if pulse then a = 0.55 + 0.45 * (0.5 + 0.5 * sin(GetTime() * 5))
    elseif shimmer then a = 0.6 + 0.4 * (0.5 + 0.5 * sin(GetTime() * 2)) end
    if a ~= self.goldAlpha then
        self.goldAlpha = a
        f.arcs.gold:SetAlpha(a)
        for _, t in ipairs(f.sq.gold) do t:SetAlpha(a) end
    end
end

-- cooldowns the client could not pause: set again before they move noticeably
function Ring:Reapply()
    if self.shape ~= "round" or not self.shares then return end
    for _, key in ipairs(LAYERS) do
        local cd = self.frame.arcs[key]
        if cd.share and not cd.paused then setArc(cd, cd.share, cd.tex) end
    end
end

-- the mouse on the band (and not on a button lying on it): the XP tooltip
function Ring:CheckHover()
    local f = self.frame
    local on = false
    if f:IsVisible() and GetCursorPosition then
        local cx, cy = f:GetCenter()
        local s = f:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        if cx and s and s > 0 then
            local dx, dy = mx / s - cx, my / s - cy
            if self.shape == "round" and self.outer then
                local d = sqrt(dx * dx + dy * dy)
                on = d >= self.inner - 2 and d <= self.outer + 2
            elseif self.h then
                local d = max(abs(dx), abs(dy))
                on = d >= self.h - self.t / 2 - 2 and d <= self.h + self.t / 2 + 2
            end
        end
        if on then
            -- the frames around the map (the minimap cluster takes the mouse on Forever) do not count, only a button
            -- lying on the band (minimap buttons, WIM, the calendar) keeps its own tooltip
            local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
            local isButton = focus and focus.IsObjectType and (focus:IsObjectType("Button") or focus:IsObjectType("CheckButton"))
            on = not isButton
            ns.Debug.Set("xpRingFocus", focus and focus.GetName and tostring(focus:GetName()) or "none")
        end
    end
    if on and not self.hover then
        self.hover = true
        if self.kind == "rep" then ns.Rep:ShowTooltip(f) elseif self.kind == "pet" then ns.PetXP:ShowTooltip(f) else ns.XP:ShowTooltip(f) end
    elseif not on and self.hover then
        self.hover = false
        if GameTooltip:IsOwned(f) then GameTooltip:Hide() end
    end
end

XPRING = setmetatable({ kind = "xp" }, { __index = Ring })
REPRING = setmetatable({ kind = "rep" }, { __index = Ring })
PETRING = setmetatable({ kind = "pet" }, { __index = Ring })
ns.Ring, ns.RepRing, ns.PetRing = XPRING, REPRING, PETRING

-- both, the XP ring first (the reputation ring measures from it)
function Ring.RefreshAll()
    XPRING:Refresh()
    PETRING:Refresh()
    REPRING:Refresh()
end

ns.OnLogin(function()
    Ring.RefreshAll()
    -- the minimap's size and shape may be set by other addons a moment later
    C_Timer.After(2, function() Ring.RefreshAll() end)
end)

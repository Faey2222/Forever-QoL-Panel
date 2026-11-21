local _, ns = ...

-- The minimap's shape: round as in the game, or square with a border in the panel's look (classic or modern). Square
-- means a square mask, the game's round border pieces made invisible, our border behind the map, and
-- GetMinimapShape() answering "SQUARE" so that minimap buttons (ours and other addons') line up along the square.
-- Which round pieces the client has is written to the debug data (minimapRegions).
local MS = {}
ns.MinimapShape = MS

-- our border's width around the map: the classic border's line runs 6 units in from its edge, so it needs more room
local PADS = { classic = 9, modern = 5 }
local LINE = 6                                   -- the classic border's line, from its outer edge
local function look() return ns.db.minimap.look == "modern" and "modern" or "classic" end
-- the round mask every client has (the one Forever's map starts with cannot be read back)
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
-- the round border's pieces by name in the clients this runs on
local NAMES = { "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture", "MinimapNorthTag" }

local function db() return ns.db.minimap end

function MS.Square() return db().shape == "square" end

-- room our square border takes around the map (the XP frame goes outside it)
function MS.BorderPad() return MS.Square() and PADS[look()] or 0 end

-- where the XP frame starts: right outside the border's line (the classic border's dark rim outside the line is
-- covered by the frame, so there is no gap)
function MS.RingPad()
    if not MS.Square() then return 0 end
    return look() == "classic" and PADS.classic - LINE + 2 or PADS.modern
end

-- the map is drawn again after its mask changed (otherwise it may stay empty until a reload)
local function redraw()
    if not (Minimap.GetZoom and Minimap.SetZoom) then return end
    local z = Minimap:GetZoom()
    local other = (z or 0) > 0 and z - 1 or (z or 0) + 1
    pcall(Minimap.SetZoom, Minimap, other)
    pcall(Minimap.SetZoom, Minimap, z)
end

-- a texture that looks like part of the round border: by name, or by an atlas naming the minimap's frame
local function roundPiece(region)
    local name = region.GetName and region:GetName()
    for _, n in ipairs(NAMES) do if name == n then return true end end
    local atlas = region.GetAtlas and region:GetAtlas()
    if type(atlas) == "string" and not ns.Secret(atlas) then
        local a = atlas:lower()
        if a:find("minimap") and (a:find("border") or a:find("frame") or a:find("compass") or a:find("ring")) then return true end
    end
    return false
end

-- the round pieces, and a note of every texture around the map for the debug data
local function findPieces()
    local found, seen = {}, {}
    local function scan(frame)
        if not (frame and frame.GetRegions) then return end
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" then
                local atlas = r.GetAtlas and r:GetAtlas()
                local file = r.GetTexture and r:GetTexture()
                seen[#seen + 1] = { name = tostring(r:GetName()), atlas = not ns.Secret(atlas) and tostring(atlas) or "secret",
                    file = not ns.Secret(file) and tostring(file) or "secret", parent = tostring(frame:GetName()) }
                if roundPiece(r) then found[#found + 1] = r end
            end
        end
    end
    for _, fr in ipairs({ Minimap, _G.MinimapBackdrop, _G.MinimapCluster, _G.MinimapCluster and rawget(_G.MinimapCluster, "BorderTop") }) do scan(fr) end
    for _, n in ipairs(NAMES) do
        local r = _G[n]
        if r and r.SetAlpha then
            local dup = false
            for _, x in ipairs(found) do if x == r then dup = true end end
            if not dup then found[#found + 1] = r end
        end
    end
    ns.Debug.Set("minimapRegions", seen)
    return found
end

local function border()
    if MS.border then return MS.border end
    local f = CreateFrame("Frame", "ForeverQoLPanelMinimapBorder", UIParent, "BackdropTemplate")
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    f:Hide()
    MS.border = f
    if Minimap.HookScript then
        Minimap:HookScript("OnShow", function() MS:Apply() end)
        Minimap:HookScript("OnHide", function() f:Hide() end)
    end
    return f
end

-- The game's elements at the minimap that can be hidden: candidates by name for the clients this runs on (the clock
-- has its own handling in Elements.lua). Hidden ones stay hidden when the game shows them again.
local ELEMENTS = {
    zone = { "MinimapZoneTextButton", "MinimapZoneText", "MinimapBorderTop", "MinimapCluster.ZoneTextButton", "MinimapCluster.BorderTop" },
    calendar = { "GameTimeFrame", "GameTimeCalendarInvitesTexture", "GameTimeCalendarInvitesGlow" },
    tracking = { "MiniMapTracking", "MiniMapTrackingFrame", "MiniMapTrackingButton", "MinimapCluster.Tracking", "MinimapCluster.TrackingFrame" },
    addons = { "AddonCompartmentFrame" },
}

-- Coordinates under the map: no name to find them by, so any text at the minimap that reads like "65.0, 50.3"
local function coordText(fs)
    local ok, text = pcall(fs.GetText, fs)
    return ok and type(text) == "string" and not ns.Secret(text) and text:match("^%s*%d+[%.,]%d+%s*[,/]%s*%d+[%.,]%d+%s*$") ~= nil
end

local function findCoords()
    local out = {}
    local function scan(frame, depth)
        if not frame or depth > 3 then return end
        if frame.GetRegions then
            for _, r in ipairs({ frame:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "FontString" and coordText(r) then out[#out + 1] = r end
            end
        end
        if frame.GetChildren then
            for _, c in ipairs({ frame:GetChildren() }) do scan(c, depth + 1) end
        end
    end
    scan(_G.MinimapCluster, 0)
    if not _G.MinimapCluster then scan(Minimap, 0) end
    return out
end

function MS:ApplyCoords()
    local show = db().coords ~= false
    if not show then
        for _, fs in ipairs(findCoords()) do
            if fs:GetAlpha() > 0 then self.coordsHidden = self.coordsHidden or {}; self.coordsHidden[fs] = true; fs:SetAlpha(0) end
        end
    elseif self.coordsHidden then
        for fs in pairs(self.coordsHidden) do fs:SetAlpha(1) end
        self.coordsHidden = nil
    end
end

local function lookup(path)
    local obj = _G
    for part in path:gmatch("[^%.]+") do
        if type(obj) ~= "table" then return nil end
        obj = rawget(obj, part)
    end
    return type(obj) == "table" and obj.Hide and obj or nil
end

-- Forever's day and night icon (Blizzard_Minimap/Camelot/Diel.lua) has no name: a small frame of its own in the
-- minimap's container, next to the map. Found once, kept (it moves to the hidden frame when hidden).
local function plainNum(v) return type(v) == "number" and not ns.Secret(v) and v or nil end
local function dielFrames()
    MS.diel = MS.diel or {}
    local cont = _G.MinimapCluster and rawget(_G.MinimapCluster, "MinimapContainer")
    local seen = {}
    if cont and cont.GetChildren then
        for _, c in ipairs({ cont:GetChildren() }) do
            local w, h = plainNum(c.GetWidth and c:GetWidth()), plainNum(c.GetHeight and c:GetHeight())
            seen[#seen + 1] = { name = tostring(c.GetName and c:GetName()), w = w, h = h }
            if c ~= Minimap and not (c.GetName and c:GetName()) and w and h and w <= 80 and h <= 80 then
                local known = false
                for _, x in ipairs(MS.diel) do if x == c then known = true end end
                if not known then MS.diel[#MS.diel + 1] = c end
            end
        end
    end
    ns.Debug.Set("minimapContainer", seen)
    return MS.diel
end
local EXTRA = { calendar = dielFrames }

function MS:ApplyElements()
    self.hiddenEls = self.hiddenEls or {}
    local found = {}
    for key, names in pairs(ELEMENTS) do
        local show = db()[key] ~= false
        local frames = {}
        for _, n in ipairs(names) do
            local f = lookup(n)
            if f then frames[#frames + 1] = f; found[#found + 1] = n end
        end
        if EXTRA[key] then
            for _, f in ipairs(EXTRA[key]()) do frames[#frames + 1] = f; found[#found + 1] = key .. ":unnamed" end
        end
        for _, f in ipairs(frames) do
            do
                -- hidden = invisible and without mouse: the game's own layout code shows these again (Show,
                -- SetShown), but leaves their alpha alone
                if not show then
                    if not self.hiddenEls[f] then
                        self.hiddenEls[f] = { mouse = f.IsMouseEnabled and f:IsMouseEnabled(), parent = f.GetParent and f:GetParent() }
                        -- in a hidden frame nothing the game does (Show, SetShown, animations) makes it visible
                        if f.SetParent and f.GetObjectType and f:GetObjectType() ~= "Texture" and f:GetObjectType() ~= "FontString" then
                            MS.vault = MS.vault or CreateFrame("Frame")
                            MS.vault:Hide()
                            pcall(f.SetParent, f, MS.vault)
                        end
                        if not f.fqpHooked then
                            f.fqpHooked = true
                            hooksecurefunc(f, "SetAlpha", function(fr, a)
                                if MS.hiddenEls[fr] and not MS.settingAlpha and a ~= 0 then
                                    MS.settingAlpha = true; fr:SetAlpha(0); MS.settingAlpha = false
                                end
                            end)
                        end
                    end
                    self.settingAlpha = true
                    f:SetAlpha(0)
                    self.settingAlpha = false
                    if f.EnableMouse then f:EnableMouse(false) end
                elseif self.hiddenEls[f] then
                    local was = self.hiddenEls[f]
                    self.hiddenEls[f] = nil
                    if was.parent and f.SetParent and f:GetObjectType() ~= "Texture" and f:GetObjectType() ~= "FontString" then
                        pcall(f.SetParent, f, was.parent)
                    end
                    f:SetAlpha(1)
                    if f.EnableMouse and was.mouse ~= false then f:EnableMouse(true) end
                end
            end
        end
    end
    ns.Debug.Set("minimapElements", found)
    -- every frame at the minimap by name, to find the ones still missing here
    local kids = {}
    for _, parent in ipairs({ Minimap, _G.MinimapCluster, _G.MinimapBackdrop }) do
        if parent and parent.GetChildren then
            for _, c in ipairs({ parent:GetChildren() }) do
                local n = c.GetName and c:GetName()
                if n then kids[#kids + 1] = n end
            end
        end
    end
    ns.Debug.Set("minimapChildren", kids)
    self:ApplyCoords()
end

function MS:Apply()
    if not Minimap then return end
    ns.Debug.Call("MinimapElements", self.ApplyElements, self)
    local square = MS.Square()
    if square then
        if not self.pieces then self.pieces = findPieces() end
        for _, r in ipairs(self.pieces) do r:SetAlpha(0) end
        if Minimap.SetMaskTexture and not self.applied then pcall(Minimap.SetMaskTexture, Minimap, SQUARE_MASK); redraw() end
        -- other addons ask this to place their buttons; the one that was there comes back when round again
        if not self.ownShape then
            self.oldShape = rawget(_G, "GetMinimapShape")
            self.ownShape = function() return "SQUARE" end
        end
        _G.GetMinimapShape = self.ownShape
        local f = border()
        local plain = function(v) return type(v) == "number" and not ns.Secret(v) and v or nil end
        f:ClearAllPoints()
        f:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
        local pad = PADS[look()]
        f:SetSize((plain(Minimap:GetWidth()) or 140) + 2 * pad, (plain(Minimap:GetHeight()) or 140) + 2 * pad)
        f:SetShown(Minimap:IsShown())
        ns.UI.Skin(f, look())
        self.applied = true
    elseif self.applied then
        -- back to round: only what we changed is put back
        for _, r in ipairs(self.pieces or {}) do r:SetAlpha(1) end
        if Minimap.SetMaskTexture then pcall(Minimap.SetMaskTexture, Minimap, ROUND_MASK); redraw() end
        if rawget(_G, "GetMinimapShape") == self.ownShape then _G.GetMinimapShape = self.oldShape end
        if self.border then self.border:Hide() end
        self.applied = false
    end
end

ns.OnLogin(function()
    MS:Apply()
    C_Timer.After(2, function() MS:Apply() end)
    -- the coordinates may be made (and filled) a little later
    C_Timer.After(6, function() ns.Debug.Call("MinimapCoords", MS.ApplyCoords, MS) end)
end)

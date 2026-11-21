local _, ns = ...

-- The cast bars of your target and focus (the ones below their unit frames, not on nameplates): as the game shows
-- them, hidden, or free, placed in the move mode with the grid and scaled. The standard interface can do neither.
-- Cast bars are not protected frames, so this works in combat too. Hidden means the bar is hidden again whenever the
-- game shows it (a cast, the interrupt display): only invisible would still let the game's own animations through.
local CB = {}
ns.CastBar = CB

local function db() return ns.db.castbar end

CB.BARS = {
    { key = "target", label = "CB_TARGET", frame = function() return _G.TargetFrameSpellBar or (TargetFrame and rawget(TargetFrame, "spellbar")) end },
    { key = "focus", label = "CB_FOCUS", frame = function() return _G.FocusFrameSpellBar or (FocusFrame and rawget(FocusFrame, "spellbar")) end },
}

local state = {}   -- key -> { bar, holder, original points }

-- a layout value the game may keep secret (Forever does for these bars): only a plain number counts
local function plain(v) return type(v) == "number" and not ns.Secret(v) and v or nil end

-- the bar's points as the game set them, to give them back; nil when the game keeps them secret
local function savePoints(bar)
    local n = plain(bar:GetNumPoints())
    if not n then return nil end
    local pts = {}
    for i = 1, n do
        local p = { bar:GetPoint(i) }
        for _, v in pairs(p) do if ns.Secret(v) then return nil end end
        pts[i] = p
    end
    return pts
end

-- the game puts the bar back in its place itself (the function differs between client generations)
local function gameLayout(bar)
    if bar.AdjustPosition then pcall(bar.AdjustPosition, bar) end
    if Target_Spellbar_AdjustPosition then pcall(Target_Spellbar_AdjustPosition, bar) end
    local parent = bar:GetParent()
    if parent and parent.UpdateAuras then pcall(parent.UpdateAuras, parent) end
    if parent and TargetFrame_UpdateAuras then pcall(TargetFrame_UpdateAuras, parent) end
end

local function holderFor(def)
    local st = state[def.key]
    if st.holder then return st.holder end
    local h = CreateFrame("Frame", "ForeverQoLPanelCastBar_" .. def.key, UIParent)
    h:SetSize(195, 13)
    h:SetFrameStrata("MEDIUM")
    h:SetMovable(true)
    h:SetClampedToScreen(true)
    h:Hide()
    ns.Mover:Register(h, {
        label = function() return ns.L[def.label] end,
        save = function(x, y) db()[def.key .. "Pos"] = { x, y }; CB:Apply(def) end,
    })
    st.holder = h
    return h
end

-- lays the bar where its mode wants it
function CB:Apply(def)
    local bar = def.frame()
    if not bar then return end
    local st = state[def.key] or {}
    state[def.key] = st
    st.bar = bar
    local mode = db()[def.key] or "default"
    if mode ~= "default" and not st.saved then st.points, st.saved = savePoints(bar), true end
    st.busy = true
    if mode == "hide" then
        bar:SetAlpha(0)
        bar:Hide()
        if st.holder then st.holder:Hide() end
    elseif mode == "free" then
        bar:SetAlpha(1)
        local h = holderFor(def)
        local pos = db()[def.key .. "Pos"] or (def.key == "target" and { 0, -120 } or { 0, -160 })
        -- the holder (the box in move mode) as large as the scaled bar, at the saved centre
        local s = db()[def.key .. "Scale"] or 1
        h:SetSize(math.max(60, (plain(bar:GetWidth()) or 195) * s), math.max(8, (plain(bar:GetHeight()) or 13) * s))
        h:ClearAllPoints()
        h:SetPoint("CENTER", UIParent, "CENTER", pos[1], pos[2])
        h:Show()
        bar:SetScale(db()[def.key .. "Scale"] or 1)
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", h, "CENTER", 0, 0)
    else
        bar:SetAlpha(1)
        bar:SetScale(1)
        if st.holder then st.holder:Hide() end
        if st.saved then
            if st.points then
                bar:ClearAllPoints()
                for _, p in ipairs(st.points) do bar:SetPoint(unpack(p)) end
            else
                gameLayout(bar)
            end
            st.points, st.saved = nil, nil
        end
    end
    st.busy = false
    -- the game moves the bar again (target change, auras): ours goes back on top
    if not st.hooked then
        st.hooked = true
        hooksecurefunc(bar, "SetPoint", function()
            if st.busy or (db()[def.key] or "default") ~= "free" then return end
            CB:Apply(def)
        end)
        bar:HookScript("OnShow", function()
            if (db()[def.key] or "default") == "hide" then bar:SetAlpha(0); bar:Hide() end
        end)
        -- the game's own animations (the interrupt flash and shake, the fade-out) set the bar's alpha themselves and
        -- would show it again: hidden, they are stopped as soon as they start
        if bar.GetAnimationGroups then
            for _, g in ipairs({ bar:GetAnimationGroups() }) do
                if g and g.HookScript then
                    g:HookScript("OnPlay", function(self)
                        if (db()[def.key] or "default") ~= "hide" then return end
                        self:Stop()
                        st.busy = true
                        bar:SetAlpha(0)
                        st.busy = false
                    end)
                end
            end
        end
        -- the bar fades itself in and out while casting: hidden stays hidden
        hooksecurefunc(bar, "SetAlpha", function(_, a)
            if st.busy or (db()[def.key] or "default") ~= "hide" or not a or ns.Secret(a) or a == 0 then return end
            st.busy = true
            bar:SetAlpha(0)
            st.busy = false
        end)
    end
end

function CB:Refresh()
    for _, def in ipairs(self.BARS) do ns.Debug.Call("CastBar", CB.Apply, CB, def) end
end

-- a bar the client has (this client may have no focus frame)
function CB.Has(key)
    for _, def in ipairs(CB.BARS) do if def.key == key then return def.frame() ~= nil end end
    return false
end

ns.OnLogin(function()
    CB:Refresh()
    -- the focus frame's bar may come later
    C_Timer.After(2, function() CB:Refresh() end)
end)

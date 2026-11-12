local ADDON, ns = ...

ns.name = ADDON
ns.defaults = {}

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    ForeverQoLPanelDB = ForeverQoLPanelDB or {}
    copyDefaults(ns.defaults, ForeverQoLPanelDB)
    ns.db = ForeverQoLPanelDB
end)

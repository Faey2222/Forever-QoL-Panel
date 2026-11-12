local _, ns = ...

-- Facts about the client and caught errors, written to the SavedVariables (ForeverQoLPanelDB.debug) on
-- /reload or logout, so a test run can be read without screenshots. Reset on every login.
local D = {}
ns.Debug = D

function D.Set(key, value)
    if ns.db and ns.db.debug then ns.db.debug[key] = value end
end

function D.Error(where, err)
    if not (ns.db and ns.db.debug) then return end
    local list = ns.db.debug.errors
    if #list < 30 then list[#list + 1] = where .. ": " .. tostring(err) end
end

-- Runs fn; an error is noted and also passed on to the normal error display.
function D.Call(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        D.Error(where, err)
        geterrorhandler()(err)
    end
    return ok
end

ns.OnLogin(function()
    local version, build, _, interface = GetBuildInfo()
    ns.db.debug = { errors = {}, client = { version = version, build = build, interface = interface }, at = date("%Y-%m-%d %H:%M") }
end)

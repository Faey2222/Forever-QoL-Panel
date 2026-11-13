local _, ns = ...

-- Mail: a small arrow next to the recipient field lists your other characters on this realm and faction (class
-- colours, level), a click fills in the name. The list is the one the gold overview keeps (db.gold), so a character
-- shows up once it has logged in with the addon.
local Mail = {}
ns.Mail = Mail

local function on() local g = ns.db.gameplay; return g.enabled and g.mailAlts end

function Mail:Alts()
    local realm, faction, me = GetRealmName(), UnitFactionGroup("player") or "Neutral", UnitName("player")
    local list = {}
    for name, e in pairs(ns.db.gold[realm] and ns.db.gold[realm][faction] or {}) do
        -- full: first and last name, which mail needs (stored at each login since 1.2.0)
        -- (names stored with a hyphen by the first version get the space mail needs)
        if name ~= me then list[#list + 1] = { name = ns.CharName(name, e), class = e.class, level = e.level, short = not e.full } end
    end
    table.sort(list, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return a.name < b.name
    end)
    return list
end

local function label(c)
    local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class or ""]
    local name = col and col.colorStr and ("|c" .. col.colorStr .. c.name .. "|r") or c.name
    -- only the first name known yet: greyed hint to log in once
    if c.short then name = name .. "  |cff9d9d9d(" .. ns.L.MAIL_RELOG .. ")|r" end
    return c.level and (name .. "  |cff9d9d9d" .. ns.L.LVL_N:format(c.level) .. "|r") or name
end

function Mail:Pick(name)
    local box = SendMailNameEditBox
    if not box then return end
    box:SetText(name)
    box:SetCursorPosition(#name)
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetFocus() end
end

function Mail:ShowMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local L = ns.L
    local list = self:Alts()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L.MAIL_ALTS)
        if #list == 0 then
            root:CreateTitle("|cff9d9d9d" .. L.MAIL_NO_ALTS .. "|r")
        end
        for _, c in ipairs(list) do
            root:CreateButton(label(c), function() Mail:Pick(c.name) end)
        end
    end)
end

function Mail:Create()
    if self.button or not SendMailNameEditBox then return end
    local b = CreateFrame("Button", "ForeverQoLPanelMailAlts", SendMailNameEditBox)
    b:SetSize(24, 24)
    b:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 0, 0)
    b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function(self) Mail:ShowMenu(self) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L.MAIL_ALTS)
        GameTooltip:AddLine(ns.L.MAIL_ALTS_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.button = b
end

function Mail:Refresh()
    if on() then self:Create() end
    if self.button then self.button:SetShown(on() and true or false) end
end

ns.OnLogin(function()
    ns.On("MAIL_SHOW", function() ns.Debug.Call("Mail", Mail.Refresh, Mail) end)
end)

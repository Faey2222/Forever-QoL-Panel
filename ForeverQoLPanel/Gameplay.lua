local _, ns = ...

-- Gameplay helpers: auto quests (Shift pauses), reward values, skipping single-choice dialogues, selling grey items,
-- repairing, fast auto loot and loot as floating text. Each one can be switched off.
local G = {}
ns.Gameplay = G

local function db() return ns.db.gameplay end
local function on(key) return db().enabled and db()[key] end
local function paused() return IsShiftKeyDown() end
local function say(text) print("|cffffd100" .. ns.title .. "|r: " .. text) end
local function money(c) return ns.Money(c) end

local CC = C_Container
local function bagSlots(bag) return (CC and CC.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function itemInfo(bag, slot)
    if CC and CC.GetContainerItemInfo then return CC.GetContainerItemInfo(bag, slot) end
    local _, count, _, quality, _, _, link, _, noValue, id = GetContainerItemInfo(bag, slot)
    if id then return { stackCount = count, quality = quality, hyperlink = link, hasNoValue = noValue, itemID = id } end
end
local function useItem(bag, slot) (CC and CC.UseContainerItem or UseContainerItem)(bag, slot) end

local function sellPrice(link)
    if not link then return 0 end
    local price = select(11, ns.ItemInfo(link))
    return price or 0
end

-- Quests -------------------------------------------------------------------------

local function gossipQuests()
    local GI = C_GossipInfo
    if GI and GI.GetActiveQuests then
        for _, q in ipairs(GI.GetActiveQuests() or {}) do
            if q.isComplete and on("questTurnIn") then GI.SelectActiveQuest(q.questID) return true end
        end
        for _, q in ipairs(GI.GetAvailableQuests() or {}) do
            if on("questAccept") then GI.SelectAvailableQuest(q.questID) return true end
        end
    end
    return false
end

local function skipDialogue()
    local GI = C_GossipInfo
    if not (on("gossip") and GI and GI.GetOptions) then return end
    if (GI.GetNumActiveQuests and GI.GetNumActiveQuests() or 0) > 0 then return end
    if (GI.GetNumAvailableQuests and GI.GetNumAvailableQuests() or 0) > 0 then return end
    local options = GI.GetOptions() or {}
    -- only a single plain dialogue option (no vendor, trainer, banker ... and nothing that costs money)
    if #options ~= 1 then return end
    local o = options[1]
    if (o.cost or 0) > 0 or o.selectOptionWhenOnlyOption == false then return end
    if o.icon and o.icon ~= 132053 then return end   -- 132053: the plain chat bubble of a dialogue line
    GI.SelectOption(o.gossipOptionID)
end

function G:Quests(event)
    if not db().enabled or paused() then return end
    if event == "GOSSIP_SHOW" then
        if not gossipQuests() then skipDialogue() end
    elseif event == "QUEST_GREETING" then
        for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
            local _, complete = GetActiveTitle(i)
            if complete and on("questTurnIn") then SelectActiveQuest(i) return end
        end
        for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
            if on("questAccept") then SelectAvailableQuest(i) return end
        end
    elseif event == "QUEST_DETAIL" then
        if on("questAccept") then
            if QuestGetAutoAccept and QuestGetAutoAccept() then AcknowledgeAutoAcceptQuest() else AcceptQuest() end
        end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        if on("questAccept") then ConfirmAcceptQuest() end
    elseif event == "QUEST_PROGRESS" then
        if on("questTurnIn") and IsQuestCompletable() then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        -- Blizzard lays the reward buttons out after this event
        C_Timer.After(0.05, function() ns.Debug.Call("Rewards", G.MarkRewards, G) end)
        -- with a choice of rewards the window stays open; the most valuable one is marked
        if on("questTurnIn") and (GetNumQuestChoices() or 0) <= 1 then GetQuestReward(GetNumQuestChoices() == 1 and 1 or nil) end
    end
end

-- Reward values: the sell value on every reward to choose from, a gold coin on the most valuable one. Runs once
-- Blizzard has laid out the reward buttons (after QUEST_COMPLETE), and again when item prices arrive from the server.
local function choiceButtons()
    local list = {}
    local frame = QuestInfoRewardsFrame
    local buttons = frame and rawget(frame, "RewardButtons")
    if type(buttons) == "table" then
        for _, b in ipairs(buttons) do
            if b.IsShown and b:IsShown() and rawget(b, "type") == "choice" and b.GetID then list[b:GetID()] = b end
        end
    end
    for i = 1, (GetNumQuestChoices() or 0) do
        if not list[i] then
            local b = _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
            if b and (not rawget(b, "type") or rawget(b, "type") == "choice") then list[i] = b end
        end
    end
    return list
end

local function marker(self, b)
    self.marks = self.marks or {}
    local m = self.marks[b]
    if m then return m end
    m = {}
    -- an own layer above the button: Blizzard's icon border and highlight lie over the button's own textures and
    -- left the coin half see-through
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints()
    top:SetFrameLevel(b:GetFrameLevel() + 10)
    m.coin = top:CreateTexture(nil, "OVERLAY", nil, 7)
    m.coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    m.coin:SetSize(18, 18)
    m.coin:SetAlpha(1)
    m.coin:SetVertexColor(1, 1, 1, 1)
    local icon = rawget(b, "Icon") or rawget(b, "icon")
    m.coin:SetPoint("TOPLEFT", icon or b, "TOPLEFT", -5, 5)
    m.value = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.value:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 4)
    self.marks[b] = m
    return m
end

function G:MarkRewards()
    for _, m in pairs(self.marks or {}) do m.coin:Hide(); m.value:Hide() end
    if not on("rewardValue") then return end
    local best, bestValue, missing = nil, 0, false
    for i, b in pairs(choiceButtons()) do
        local link = GetQuestItemLink("choice", i)
        local _, _, count = GetQuestItemInfo("choice", i)
        local id = link and tonumber(link:match("item:(%d+)"))
        local price = sellPrice(id or link)
        if price == 0 and id and not ns.ItemInfo(id) then
            missing = true
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        end
        local value = price * math.max(1, count or 1)
        local m = marker(self, b)
        if value > 0 then
            m.value:SetText(money(value))
            m.value:Show()
        end
        if value > bestValue then best, bestValue = b, value end
    end
    if best then self.marks[best].coin:Show() end
    -- prices still loading: once more when they are there
    if missing and not self.retry then
        self.retry = true
        C_Timer.After(0.5, function() self.retry = false; if QuestFrame and QuestFrame:IsShown() then self:MarkRewards() end end)
    end
end

-- Merchant: sell grey, repair -----------------------------------------------------

function G:Merchant()
    if not db().enabled then return end
    if on("repair") and CanMerchantRepair and CanMerchantRepair() then
        local cost, canRepair = GetRepairAllCost()
        if canRepair and cost > 0 then
            local guild = on("guildRepair") and CanGuildBankRepair and CanGuildBankRepair()
                and (GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0) ~= 0
            if guild then
                RepairAllItems(true)
                say(ns.L.GP_REPAIRED_GUILD:format(money(cost)))
            elseif GetMoney() >= cost then
                RepairAllItems()
                say(ns.L.GP_REPAIRED:format(money(cost)))
            else
                say(ns.L.GP_NO_MONEY:format(money(cost)))
            end
        end
    end
    if on("sellGrey") and not paused() then self:SellGrey() end
end

-- The grey items in the bags: { bag, slot, id, value } each.
local function greyItems()
    local list = {}
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, bagSlots(bag) do
            local info = itemInfo(bag, slot)
            if info and info.quality == 0 and not info.hasNoValue then
                -- the price may not be cached yet; the item is sold all the same
                local value = sellPrice(info.itemID or info.hyperlink) * (info.stackCount or 1)
                list[#list + 1] = { bag, slot, info.itemID, value, locked = info.isLocked }
            end
        end
    end
    return list
end

-- The game may refuse an addon selling item by item (the sale then needs a click). So the merchant's own "sell all
-- junk" is used where the client has it, the old way only as a fallback, and the message counts what really left the
-- bags: nothing is reported as sold that wasn't. The merchant counts as open from MERCHANT_SHOW to MERCHANT_CLOSED.
function G:SellGrey()
    local list = {}
    for _, s in ipairs(greyItems()) do if not s.locked then list[#list + 1] = s end end
    if #list == 0 then return end
    local MF = C_MerchantFrame
    local how
    if MF and MF.SellAllJunkItems and pcall(MF.SellAllJunkItems) then
        how = "junk"
    else
        how = "items"
        self.sellBlocked = false
        local i = 1
        local function step()
            if not self.merchantOpen or self.sellBlocked then return end
            for _ = 1, 8 do
                local s = list[i]
                if not s then return end
                useItem(s[1], s[2])
                i = i + 1
            end
            C_Timer.After(0.25, step)
        end
        step()
    end
    -- count after the server has answered: an item counts as sold when its slot no longer holds it
    C_Timer.After(1.5 + 0.25 * math.floor(#list / 8), function()
        local left = {}
        for _, s in ipairs(greyItems()) do left[s[1] * 1000 + s[2]] = s[3] end
        local sold, total = 0, 0
        for _, s in ipairs(list) do
            if left[s[1] * 1000 + s[2]] ~= s[3] then sold, total = sold + 1, total + s[4] end
        end
        ns.Debug.Set("sellGrey", { how = how, found = #list, sold = sold, total = total, blocked = self.sellBlocked })
        if sold > 0 then
            say(ns.L.GP_SOLD:format(sold, money(total)))
        else
            say(ns.L.GP_SELL_BLOCKED)
        end
    end)
end

-- the game refused one of our calls: stop selling item by item at once
function G:ActionBlocked(addon)
    if addon == ns.name then self.sellBlocked = true end
end

-- Loot -------------------------------------------------------------------------

function G:FastLoot()
    if not on("fastLoot") then return end
    local auto = GetCVarBool and GetCVarBool("autoLootDefault")
    if auto == (IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE")) then return end
    if (self.lastLoot or 0) > GetTime() - 0.3 then return end
    self.lastLoot = GetTime()
    for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
end

-- Loot as floating text: rises from the anchor (default right of and below the screen centre) and fades. The anchor
-- can be moved (blue box like Edit Mode, right-click finishes) and scaled; icons look like the panel's or own shape.
local LOOT_ICON = 20
local MONEY_ICON = { gold = "Interface\\Icons\\INV_Misc_Coin_01", silver = "Interface\\Icons\\INV_Misc_Coin_03",
    copper = "Interface\\Icons\\INV_Misc_Coin_05" }
local pool = {}

local function lootAnchor()
    if G.anchor then return G.anchor end
    local a = CreateFrame("Frame", "ForeverQoLPanelLootAnchor", UIParent)
    a:SetSize(280, 3 * (LOOT_ICON + 6))
    a:SetFrameStrata("DIALOG")
    a:SetFrameLevel(500)
    a:SetMovable(true)
    a:SetClampedToScreen(true)
    a.box = a:CreateTexture(nil, "BACKGROUND")
    a.box:SetAllPoints()
    if not ns.SetAtlas(a.box, "editSel", { "editmode-actionbar-selected-nineslice-center" }) then
        a.box:SetColorTexture(0.25, 0.55, 1, 0.3)
    end
    a.box:SetVertexColor(0.45, 0.7, 1, 0.55)
    a.label = a:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    a.label:SetPoint("BOTTOM", a, "TOP", 0, 6)
    a.box:Hide(); a.label:Hide()
    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", function(self) if G.moving then ns.Mover:StartDrag(self) end end)
    a:SetScript("OnDragStop", function(self)
        ns.Mover:StopDrag()
        -- onto the grid of the move mode (Mover.lua)
        db().lootPos = { ns.Mover.SnapCenter(self) }
        G:PlaceLoot()
    end)
    a:SetScript("OnMouseUp", function(_, button) if G.moving and button == "RightButton" then ns.Mover:Toggle(false) end end)
    a:EnableMouse(false)   -- only move mode takes the mouse
    G.anchor = a
    G:PlaceLoot()
    return a
end

function G:PlaceLoot()
    local a = lootAnchor()
    a:SetScale(db().lootScale or 1)
    local p = db().lootPos or { 220, -40 }
    local s = UIParent:GetEffectiveScale() / a:GetEffectiveScale()
    a:ClearAllPoints()
    a:SetPoint("CENTER", UIParent, "CENTER", p[1] * s, p[2] * s)
end

local function lootLine(i)
    local f = pool[i]
    if f then return f end
    f = CreateFrame("Frame", nil, lootAnchor())
    f:SetSize(280, LOOT_ICON + 4)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(LOOT_ICON, LOOT_ICON)
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(ns.FontFile(), 15, "OUTLINE")
    -- icon anchored to the line (masks need it), text on the icon
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
    pool[i] = f
    return f
end

local function setLine(f, text, icon)
    f.text:SetText(text)
    local width = (icon and LOOT_ICON + 6 or 0) + (f.text:GetStringWidth() or 0)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("LEFT", f, "CENTER", -width / 2 - (icon and 0 or LOOT_ICON + 6), 0)
    ns.StyleIcon(f, icon, db().lootShape, LOOT_ICON)
    f.icon:SetShown(icon ~= nil)
    if not icon then f.ring:Hide() end
end

local function floatText(text, icon)
    if not on("lootText") or G.moving then return end
    local f, busy
    for i = 1, #pool + 1 do
        local p = pool[i]
        if not p or not p:IsShown() then f = lootLine(i) break end
    end
    busy = 0
    for _, p in ipairs(pool) do if p:IsShown() then busy = busy + 1 end end
    setLine(f, text, icon)
    local step = LOOT_ICON + 6
    local y0 = (1 - busy) * step
    local t = 0
    local still = ns.Motion and ns.Motion() == "off"
    f:SetAlpha(0)
    f:Show()
    f:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        local k = t / 2.6
        self:ClearAllPoints()
        self:SetPoint("CENTER", G.anchor, "CENTER", 0, y0 + (still and 0 or 60 * k))
        self:SetAlpha(t < 0.2 and t / 0.2 or (k > 0.7 and math.max(0, (1 - k) / 0.3) or 1))
        if k >= 1 then self:Hide(); self:SetScript("OnUpdate", nil) end
    end)
end

-- move mode: blue box with example lines, drag it, right-click finishes
function G:SetLootMoving(on)
    if on and InCombatLockdown() then return end
    self.moving = on and true or false
    local a = lootAnchor()
    a:EnableMouse(self.moving)
    a.box:SetShown(self.moving)
    a.label:SetShown(self.moving)
    a.label:SetText(ns.L.LOOT_MOVE_HINT)
    for _, f in ipairs(pool) do f:SetScript("OnUpdate", nil); f:Hide() end
    if self.moving then
        local samples = {
            { "+" .. ns.Money(12345), MONEY_ICON.gold },
            { "+2 " .. ns.L.LOOT_SAMPLE_ITEM, "Interface\\Icons\\INV_Misc_Herb_10" },
        }
        for i, s in ipairs(samples) do
            local f = lootLine(i)
            setLine(f, s[1], s[2])
            f:SetAlpha(1)
            f:ClearAllPoints()
            f:SetPoint("CENTER", a, "CENTER", 0, (1 - i) * (LOOT_ICON + 6) + (LOOT_ICON + 6) / 2)
            f:Show()
        end
    end
end

function G:ResetLootPosition()
    db().lootPos = nil
    self:PlaceLoot()
end

function G:ApplyLootLook()
    if not self.anchor then return end
    self:PlaceLoot()
    if self.moving then self:SetLootMoving(true) end
end

-- "You loot 1 Gold, 23 Silver" -> copper, read with the client's own coin words
local function moneyOf(msg)
    local total, found = 0, false
    for _, c in ipairs({ { GOLD_AMOUNT, 10000 }, { SILVER_AMOUNT, 100 }, { COPPER_AMOUNT, 1 } }) do
        if c[1] then
            local n = msg:match((c[1]:gsub("%%d", "(%%d+)")))
            if n then total = total + tonumber(n) * c[2]; found = true end
        end
    end
    return found and total or nil
end

function G:MoneyMessage(msg)
    if not on("lootText") then return end
    local copper = moneyOf(msg)
    local icon = MONEY_ICON.copper
    if copper and copper >= 10000 then icon = MONEY_ICON.gold elseif copper and copper >= 100 then icon = MONEY_ICON.silver end
    local text = copper and ns.Money(copper) or (msg:gsub("^[^%d]*", ""))
    floatText("+" .. text, icon)
end

local function pattern(fmt)
    return "^" .. fmt:gsub("%%", "%%%%"):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)") .. "$"
end

function G:LootMessage(msg)
    local P = self.patterns
    if not P then
        P = {}
        for _, f in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_CREATED_SELF_MULTIPLE }) do
            if f then P[#P + 1] = { pattern(f), true } end
        end
        for _, f in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_CREATED_SELF }) do
            if f then P[#P + 1] = { pattern(f), false } end
        end
        self.patterns = P
    end
    for _, p in ipairs(P) do
        local link, count = msg:match(p[1])
        if link then
            count = p[2] and tonumber(count) or 1
            local icon = ns.ItemIcon(link)
            floatText("+" .. (count > 1 and (count .. " ") or "") .. link, icon)
            return
        end
    end
end

ns.OnLogin(function()
    for _, ev in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS",
        "QUEST_COMPLETE" }) do
        ns.On(ev, function(event) ns.Debug.Call("Quests", G.Quests, G, event) end)
    end
    if QuestInfo_Display then
        hooksecurefunc("QuestInfo_Display", function()
            if QuestFrame and QuestFrame:IsShown() and (GetNumQuestChoices() or 0) > 1 then
                ns.Debug.Call("Rewards", G.MarkRewards, G)
            end
        end)
    end
    ns.On("MERCHANT_SHOW", function() G.merchantOpen = true; ns.Debug.Call("Merchant", G.Merchant, G) end)
    ns.On("MERCHANT_CLOSED", function() G.merchantOpen = false end)
    ns.On("ADDON_ACTION_BLOCKED", function(_, addon) G:ActionBlocked(addon) end)
    ns.On("ADDON_ACTION_FORBIDDEN", function(_, addon) G:ActionBlocked(addon) end)
    ns.On("LOOT_READY", function() G:FastLoot() end)
    ns.On("CHAT_MSG_LOOT", function(_, msg) ns.Debug.Call("Loot", G.LootMessage, G, msg) end)
    ns.On("CHAT_MSG_MONEY", function(_, msg) ns.Debug.Call("Loot", G.MoneyMessage, G, msg) end)
    ns.On("PLAYER_REGEN_DISABLED", function() if G.moving then G:SetLootMoving(false) end end)
end)

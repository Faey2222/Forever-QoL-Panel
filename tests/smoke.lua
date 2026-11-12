-- Minimal mocked WoW API: enough to load the addon, log in and run the timers once.
local timers, handlers = {}, {}

function obj(kind)
    local o = { kind = kind, shown = true, scripts = {}, w = 10, h = 10 }
    return setmetatable(o, { __index = function(t, k)
        local f = rawget(_G, "MOCK_" .. k)
        if f then return f end
        if type(k) ~= "string" or not k:match("^%u") then return nil end   -- own fields, like in the game
        return function() end
    end })
end
MOCK_GetFrameLevel = function() return 1 end
MOCK_CreateTexture = function() return obj("Texture") end
MOCK_CreateFontString = function() return obj("FontString") end
MOCK_CreateMaskTexture = function() return obj("Mask") end
MOCK_CreateAnimationGroup = function() return obj("AnimGroup") end
MOCK_CreateAnimation = function() return obj("Anim") end
MOCK_GetStringWidth = function() return 40 end
MOCK_GetLeft = function() return 0 end
MOCK_SetupMenu = function(self, gen) self.gen = gen end
MOCK_GetCenter = function() return 500, 400 end
MOCK_GetRect = function(self) return 400, 380, self.w, self.h end
MOCK_GetWidth = function(self) return self.w end
MOCK_GetHeight = function(self) return self.h end
MOCK_SetWidth = function(self, w) self.w = w end
MOCK_SetSize = function(self, w, h) self.w, self.h = w, h end
MOCK_IsOwned = function() return false end
MOCK_IsPlaying = function() return false end
MOCK_IsMouseOver = function() return false end
MOCK_IsShown = function(self) return self.shown end
MOCK_Show = function(self) self.shown = true end
MOCK_Hide = function(self) self.shown = false end
MOCK_GetEffectiveScale = function() return 1 end
MOCK_GetChildren = function() end
MOCK_GetParent = function(self) return self.parent or UIParent end
MOCK_SetScript = function(self, name, fn) self.scripts[name] = fn end
MOCK_RegisterEvent = function(self, ev) handlers[ev] = self end

UIParent = obj("Frame")
Minimap = obj("Minimap")
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70245", "", 16001 end
GameTooltip = obj("GameTooltip")
GameFontHighlight = obj("Font")
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
function CreateFrame(kind, name, parent) local f = obj(kind); f.parent = parent; if name then _G[name] = f end; return f end
function CreateFont(name) local f = obj("Font"); _G[name] = f; return f end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
C_Timer = { NewTicker = function(_, fn) table.insert(timers, fn) end, After = function(_, fn) table.insert(timers, fn) end }
C_Texture = { GetAtlasInfo = function() return { file = 1, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end }
C_Container = { GetContainerNumFreeSlots = function() return 4, 0 end, GetContainerNumSlots = function() return 16 end,
    GetItemCooldown = function() return 0, 0 end, GetBagName = function() return "Bag" end }
C_Map = { GetBestMapForUnit = function() return 1 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.432, 0.668 end } end }
C_QuestLog = {}
SlashCmdList = {}
RAID_CLASS_COLORS = {}
function GetTime() return 100 end
function GetMoney() return 482790 end
function GetCoinTextureString(c) return tostring(c) .. "c" end
function BreakUpLargeNumbers(n) return tostring(n) end
function UnitXP() return 12428 end
function UnitXPMax() return 23100 end
function UnitLevel() return 23 end
function GetMaxPlayerLevel() return 60 end
function GetXPExhaustion() return 4620 end
function UnitClass() return "Paladin", "PALADIN" end
function UnitName() return "Aerilyn" end
function UnitFactionGroup() return "Alliance" end
function GetRealmName() return "Realm" end
function GetBindLocation() return "Goldshire" end
function GetInventoryItemDurability() return 61, 100 end
function GetInventoryItemLink() return "[Item]" end
function GetSubZoneText() return "Lakeshire" end
function GetZoneText() return "Redridge Mountains" end
function GetNetStats() return 0, 0, 38, 44 end
function GetFramerate() return 143.6 end
function GetGameTime() return 13, 5 end
function GetNumQuestLogEntries() return 3 end
function GetQuestLogTitle(i) return "Quest " .. i, 1, nil, i == 1, nil, i > 1 and 1 or nil, nil, 100 + i end
function GetQuestLogRewardXP() return 1850 end
function GetQuestLogSelection() return 0 end
function SelectQuestLogEntry() end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function strsplit(sep, s, n) local a, b = s:match("^(%S*)%s*(.*)$"); return a, b ~= "" and b or nil end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function geterrorhandler() return function(e) error(e, 0) end end
date = os.date
time = os.time
function GetLocale() return "deDE" end
C_CurrencyInfo = { GetCurrencyInfo = function(id) return { name = "Currency " .. id, quantity = 1234, iconFileID = 135725,
    description = "Text", maxQuantity = id == 1792 and 25000 or 0 } end }
function GetInventorySlotInfo() return 0 end
function GetInventoryItemCount() return 800 end
bit = { band = function(a, b) return a % (b * 2) >= b and b or 0 end }
TimeManagerClockButton = obj("Button")
MainStatusTrackingBarContainer = obj("Frame")
MOCK_IsMouseEnabled = function() return true end

-- context menus: the generator runs against a recording root
local function menuNode()
    local n = obj("Menu")
    n.CreateButton = function() return menuNode() end
    n.CreateCheckbox = function(_, _, isSet, set) isSet(); return menuNode() end
    return n
end
MenuUtil = { CreateContextMenu = function(owner, gen) gen(owner, menuNode()) end }

-- Blizzard settings: enough to build the pages
local function setting() return obj("Setting") end
Settings = {
    VarType = { Boolean = "boolean", Number = "number", String = "string" },
    RegisterVerticalLayoutCategory = function() local c = obj("Category"); c.GetID = function() return 1 end; return c, obj("Layout") end,
    RegisterVerticalLayoutSubcategory = function() return obj("Category"), obj("Layout") end,
    RegisterProxySetting = function(_, _, _, _, _, get, set) set(get()); return setting() end,
    CreateCheckbox = function() return obj("Init") end, CreateSlider = function() return obj("Init") end,
    CreateDropdown = function(_, _, options) options(); return obj("Init") end,
    CreateSliderOptions = function() return obj("SliderOptions") end,
    CreateControlTextContainer = function() local c = obj("Container"); c.GetData = function() return {} end; return c end,
    RegisterCanvasLayoutCategory = function() return obj("Category") end,
    RegisterAddOnCategory = function() end, OpenToCategory = function() end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
function CreateSettingsListSectionHeaderInitializer() return {} end
function CreateSettingsButtonInitializer(_, _, fn) return obj("Init") end

function MOCK_fire(ev, ...)
    local seen = {}
    for _, f in pairs(handlers) do
        if not seen[f] and f.scripts.OnEvent then seen[f] = true; f.scripts.OnEvent(f, ev, ...) end
    end
end
function MOCK_runTimers()
    local list = timers; timers = {}
    for _, fn in ipairs(list) do fn() end
end

-- combat, keys, items
function InCombatLockdown() return false end
MOCK_secret = {}
function issecretvalue(v) return MOCK_secret[v] == true end
function IsShiftKeyDown() return false end
function GetItemCount() return 1 end

-- spellbook (classic API) and action bars
MOCK_book = { 101 }
MOCK_spells = { [101] = { "Frostbolt", "Rank 1" }, [102] = { "Frostbolt", "Rank 2" }, [201] = { "Blink", "" } }
MOCK_actions = { [1] = 101 }
local cursor
function GetNumSpellTabs() return 2 end
function GetSpellTabInfo(tab) if tab == 1 then return "General", nil, 0, 0 end return "Frost", nil, 0, #MOCK_book end
function GetSpellBookItemInfo(i) return "SPELL", MOCK_book[i] end
function GetSpellInfo(id) return MOCK_spells[id] and MOCK_spells[id][1] or ("Spell" .. tostring(id)) end
function GetSpellSubtext(id) return MOCK_spells[id] and MOCK_spells[id][2] end
function IsPassiveSpell() return false end
function PickupSpellBookItem(i) cursor = MOCK_book[i] end
function PlaceAction(slot) MOCK_actions[slot] = cursor; cursor = nil end
function ClearCursor() cursor = nil end
function GetCursorInfo() return nil end
function GetActionInfo(slot) if MOCK_actions[slot] then return "spell", MOCK_actions[slot] end end
function HasAction(slot) return MOCK_actions[slot] ~= nil end

-- minimap buttons and the addon compartment: one addon in both places becomes one entry
MOCK_GetName = function(self) return self.name end
MOCK_IsObjectType = function(self, t) return self.kind == t end
MOCK_GetSize = function(self) return self.w, self.h end
MOCK_GetScript = function(self, n) return self.scripts[n] end
local function mmButton(name)
    local b = obj("Button"); b.name = name; b.w, b.h = 31, 31; b.scripts.OnClick = function() end
    return b
end
MOCK_mmChildren = { mmButton("DarkmoonArcadeMinimapButton"), mmButton("GoodRange"), mmButton("LFGForeverMinimapButton") }
Minimap.GetChildren = function() return unpack(MOCK_mmChildren) end
AddonCompartmentFrame = { registeredAddons = {
    { text = "Darkmoon Arcade", func = function() end }, { text = "Good Range", func = function() end },
    { text = "LFG Forever", func = function() end }, { text = "Baganator", func = function() end } } }

-- bags with a grey item, merchant, loot, tooltips, nameplates, PvP, wizard frames
C_Container.GetContainerItemInfo = function(bag, slot)
    if bag == 0 and slot == 1 then return { itemID = 2589, stackCount = 3, quality = 0, hyperlink = "|Hitem:2589|h[Linen]|h" } end
end
C_Container.UseContainerItem = function() MOCK_used = (MOCK_used or 0) + 1 end
function GetItemInfo(id) return "Item" .. tostring(id), nil, nil, nil, nil, nil, nil, nil, nil, 134400, 12 end
-- Forever only has the C_Item variant
C_Item = C_Item or {}
C_Item.GetItemInfo = GetItemInfo
GetItemInfo = nil
function GetItemIcon() return 134400 end
MerchantFrame = obj("Frame")
function CanMerchantRepair() return true end
function GetRepairAllCost() return 250, true end
function RepairAllItems() MOCK_repaired = true end
function CanGuildBankRepair() return false end
function GetCVarBool() return true end
function IsModifiedClick() return false end
function GetNumLootItems() return 2 end
function LootSlot() end
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
UNIT_SKINNABLE_LEATHER = "Skinnable"
Enum = { TooltipDataType = { Item = 0, Unit = 2 }, TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 } }
MOCK_tooltipPost = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) MOCK_tooltipPost[kind] = fn end }
C_TooltipInfo = { GetUnit = function() return { lines = { { type = 17, leftText = "A quest" }, { type = 8, leftText = "Kobold slain: 3/8" } } } end }
C_NamePlate = { GetNamePlateForUnit = function() MOCK_plate = MOCK_plate or obj("Frame"); return MOCK_plate end }
function UnitIsPlayer() return false end
function UnitIsDead() return false end
function UnitIsDeadOrGhost() return false end
function UnitOnTaxi() return false end
function UnitIsPVP() return true end
function UnitIsPVPFreeForAll() return false end
function GetPVPTimer() return 120000 end
function IsPVPTimerRunning() return true end
function TogglePVP() end
function IsInInstance() return true, "raid" end
function IsPlayerSpell(id) return id == 1459 end
function GetWeaponEnchantInfo() return false end
function GetInventoryItemTexture() return 1 end
function UnitBuff() return nil end
function GetNumSkillLines() return 0 end
UISpecialFrames = {}
tinsert = table.insert
GameFontHighlightMedium = obj("Font")
MOCK_GetChecked = function() return true end

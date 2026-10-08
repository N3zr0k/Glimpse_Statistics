local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Gemeinsame Helfer der Sammler (Kills.lua, Fishing.lua, Gathering.lua).

-- Blizzard-API gebündelt, damit Tests sie ersetzen können
S.api = {
    GetTime = GetTime,
    UnitGUID = UnitGUID,
    UnitName = UnitName,
    UnitIsDead = UnitIsDead,
    UnitExists = UnitExists,
    UnitIsUnit = UnitIsUnit,
    UnitHealth = UnitHealth,
    UnitCanAttack = UnitCanAttack,
    After = C_Timer and C_Timer.After or nil,
    UnitIsTapDenied = UnitIsTapDenied,
    GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant,
    GetItemNameByID = C_Item and C_Item.GetItemNameByID or nil,
    GetNumLootItems = (C_Loot and C_Loot.GetNumLootItems) or GetNumLootItems,
    GetLootSlotType = (C_Loot and C_Loot.GetLootSlotType) or GetLootSlotType,
    GetLootSlotLink = (C_Loot and C_Loot.GetLootSlotLink) or GetLootSlotLink,
    GetLootSourceInfo = (C_Loot and C_Loot.GetLootSourceInfo) or GetLootSourceInfo,
    IsFishingLoot = IsFishingLoot,
    GetSpellName = C_Spell and C_Spell.GetSpellName or nil,
    GetSpellInfo = GetSpellInfo,
    GetSpellSubtext = C_Spell and C_Spell.GetSpellSubtext or nil,
    GetProfessions = GetProfessions,
    GetProfessionInfo = GetProfessionInfo,
}

local api = S.api

local LOOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1

-- Fallback-Zahlen für Clients ohne Enum
local ItemClass = Enum and Enum.ItemClass or {}
local TRADEGOODS = ItemClass.Tradegoods or 7
local MATERIAL_CLASSES = { [TRADEGOODS] = true, [ItemClass.Gem or 3] = true }

local SUBCLASS = Enum and Enum.ItemTradeGoodsSubclass or {}
local HERB = SUBCLASS.Herb or 9
local METAL_STONE = SUBCLASS.MetalStone or 7
local MEAT = SUBCLASS.Meat or 8 -- Fisch hat keine eigene Unterklasse

--- nil für Secret Values.
function S.Clean(value)
    if value ~= nil and Glimpse:IsSecret(value) then return nil end
    return value
end
local Clean = S.Clean

--- "Creature-0-3131-2552-14367-179891-0000A5C2B1" -> "Creature", 179891
function S.ParseGUID(guid)
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind, tonumber(id)
end

function S:IsCollecting()
    return self.account.collect ~= false
end

--- Schlüssel (uiMapID oder "i<InstanzID>") und Name, nil wenn unbekannt.
function S:CurrentZone()
    local Locations = Glimpse.GetModule and Glimpse:GetModule("Locations", true)
    if not Locations or not Locations.GetPlayerArea then return nil end

    local ok, area = pcall(Locations.GetPlayerArea, Locations)
    if not ok or type(area) ~= "table" then return nil end

    if type(area.instance) == "number" then return "i" .. area.instance, area.name end
    if type(area.map) == "number" then
        local named, name = pcall(Locations.GetMapName, Locations, area.map)
        return area.map, named and name or nil
    end
end

--- Nur für uiMapIDs; Instanznamen stehen in den Daten.
function S.ZoneName(key)
    local Locations = Glimpse.GetModule and Glimpse:GetModule("Locations", true)
    local map = tonumber(key)
    if not (Locations and map and Locations.GetMapName) then return nil end
    local ok, name = pcall(Locations.GetMapName, Locations, map)
    return ok and name or nil
end

--- Gibt seen(guid, now) zurück: true, wenn innerhalb von window Sekunden schon gesehen, sonst vermerken.
-- Über max Einträgen wird geleert.
function S.NewSeen(window, max)
    local seen, size = {}, 0
    return function(guid, now)
        local at = seen[guid]
        if at and (now - at) <= window then return true end
        if not at then
            if size >= max then
                wipe(seen)
                size = 0
            end
            size = size + 1
        end
        seen[guid] = now
        return false
    end
end

local NAME_UNITS = { "target", "mouseover", "focus", "pettarget" }

--- Sucht über target, mouseover, focus, pettarget.
function S.UnitNameOf(guid)
    for _, unit in ipairs(NAME_UNITS) do
        if Clean(api.UnitGUID(unit)) == guid then return Clean(api.UnitName(unit)) end
    end
end

--- nil, solange nicht im Cache.
function S.ItemName(itemID)
    local get = api.GetItemNameByID
    if not get then return nil end
    local ok, name = pcall(get, itemID)
    return ok and type(name) == "string" and name or nil
end

local function ItemID(link)
    link = Clean(link)
    return type(link) == "string" and tonumber(strmatch(link, "item:(%d+)")) or nil
end

--- Handwerkswaren oder Edelstein; GetItemInfoInstant braucht keinen Cache.
function S.IsMaterial(itemID)
    local _, _, _, _, _, classID = api.GetItemInfoInstant(itemID)
    return MATERIAL_CLASSES[classID] == true
end

function S.IsFish(itemID)
    local _, _, _, _, _, classID, subClassID = api.GetItemInfoInstant(itemID)
    return classID == TRADEGOODS and subClassID == MEAT
end

--- "herb", "ore" oder "other"
function S.CategoryOf(items)
    local category = "other"
    for itemID in pairs(items) do
        local _, _, _, _, _, classID, subClassID = api.GetItemInfoInstant(itemID)
        if classID == TRADEGOODS then
            if subClassID == HERB then return "herb" end
            if subClassID == METAL_STONE then category = "ore" end
        end
    end
    return category
end

--- guid -> { [itemID] = Menge }, nur Materialien. Quellen ohne Material mit leerer Tabelle.
function S:ReadLoot()
    local bySource = {}
    for slot = 1, api.GetNumLootItems() do
        -- guid1, menge1, guid2, menge2 ... (AoE-Loot)
        local info = { api.GetLootSourceInfo(slot) }
        local itemID = api.GetLootSlotType(slot) == LOOT_ITEM and ItemID(api.GetLootSlotLink(slot)) or nil
        if itemID and not S.IsMaterial(itemID) then itemID = nil end

        for i = 1, #info, 2 do
            local guid, amount = Clean(info[i]), tonumber(Clean(info[i + 1])) or 1
            if type(guid) == "string" then
                bySource[guid] = bySource[guid] or {}
                if itemID then bySource[guid][itemID] = (bySource[guid][itemID] or 0) + amount end
            end
        end
    end
    return bySource
end

--- { [itemID] = Menge }, nur Fische, Quelle egal.
function S:ReadFishingLoot()
    local items = {}
    for slot = 1, api.GetNumLootItems() do
        local itemID = api.GetLootSlotType(slot) == LOOT_ITEM and ItemID(api.GetLootSlotLink(slot)) or nil
        if itemID then
            if S.IsFish(itemID) then
                items[itemID] = (items[itemID] or 0) + 1
            elseif self:IsDebugging() then
                local _, _, _, _, _, classID, subClassID = api.GetItemInfoInstant(itemID)
                self:DebugLog("Fishing loot item %s is not a fish (class %s, subclass %s)", tostring(itemID), tostring(classID), tostring(subClassID))
            end
        end
    end
    return items
end

function S:RegisterCollectorStats()
    local function Zone(key) return S.ZoneName(key) end
    local function Item(key) return S.ItemName(tonumber(key) or 0) end

    self:RegisterStat("kills", L["Creatures killed"], { group = L["Combat"], breakdown = true })
    self:RegisterStat("kills.area", L["Kills per zone"], { group = L["Combat"], breakdown = true, name = Zone })
    self:RegisterStat("kills.zone", L["Creatures killed by zone"], { group = L["Combat"], breakdown = true })
    self:RegisterStat("deaths", L["Deaths"], { group = L["Combat"], breakdown = true })
    self:RegisterStat("deaths.area", L["Deaths per zone"], { group = L["Combat"], breakdown = true, name = Zone })
    self:RegisterStat("fishing.casts", L["Fishing casts"], { group = L["Fishing"], breakdown = true, name = Zone })
    self:RegisterStat("fishing.catches", L["Fishing catches"], { group = L["Fishing"], breakdown = true, name = Zone })
    self:RegisterStat("fishing.items", L["Fish caught"], { group = L["Fishing"], breakdown = true, name = Item })
    self:RegisterStat("fishing.items.zone", L["Fish caught by zone"], { group = L["Fishing"], breakdown = true })
    self:RegisterStat("skinning", L["Creatures skinned"], { group = L["Gathering"], breakdown = true })
    self:RegisterStat("gathering.herb", L["Herbs gathered"], { group = L["Gathering"], breakdown = true })
    self:RegisterStat("gathering.ore", L["Ore gathered"], { group = L["Gathering"], breakdown = true })
    self:RegisterStat("gathering.other", L["Other nodes gathered"], { group = L["Gathering"], breakdown = true })
end

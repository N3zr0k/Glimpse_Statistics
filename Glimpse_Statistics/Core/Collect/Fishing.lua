local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- fishing.casts je Wurf, fishing.catches je Fang-Lootfenster (IsFishingLoot), beide je Zone.
-- Nur Fische: fishing.items (je Item), fishing.items.zone ("<Item>@<Zone>").
-- Würfe ohne Fang werden berechnet (Core/Api.lua), nicht gespeichert.

local api = S.api
local Clean = S.Clean

local FISHING_SPELL = 7620 -- weitere Ränge über den Namen
local knownSpell = {}

local function SpellName(spellID)
    if api.GetSpellName then
        local ok, name = pcall(api.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if api.GetSpellInfo then
        local ok, name = pcall(api.GetSpellInfo, spellID)
        if ok and type(name) == "table" then name = name.name end
        if ok and type(name) == "string" and name ~= "" then return name end
    end
end

S.SpellName = SpellName -- auch Gathering.lua

function S.IsFishingSpell(spellID)
    spellID = tonumber(Clean(spellID))
    if not spellID then return false end
    if spellID == FISHING_SPELL then return true end
    if knownSpell[spellID] ~= nil then return knownSpell[spellID] end

    local name, reference = SpellName(spellID), SpellName(FISHING_SPELL)
    if not (name and reference) then return false end -- noch nicht im Cache, nicht merken
    knownSpell[spellID] = name == reference
    return knownSpell[spellID]
end

--- true, wenn es ein Wurf war.
function S:CountCast(spellID)
    if not self:IsCollecting() or not S.IsFishingSpell(spellID) then return false end

    local zone, zoneName = self:CurrentZone()
    self:DebugLog("Fishing cast detected (spell %s) in %s", tostring(Clean(spellID)), tostring(zoneName or zone))
    self:Add("fishing.casts", 1, zone, zoneName)
    self:AddTier("fishing.casts", 1)
    return true
end

function S:CountCatch()
    if not self:IsCollecting() then return end

    local zone, zoneName = self:CurrentZone()
    self:DebugLog("Fishing catch detected in %s", tostring(zoneName or zone))
    self:Add("fishing.catches", 1, zone, zoneName)
    self:AddTier("fishing.catches", 1)

    for itemID, amount in pairs(self:ReadFishingLoot()) do
        local name = S.ItemName(itemID)
        self:Add("fishing.items", amount, itemID, name)
        self:AddTier("fishing.items", amount)
        if zone then
            self:Add("fishing.items.zone", amount, itemID .. "@" .. zone,
                name and (name .. " - " .. tostring(zoneName or zone)) or nil)
        end
    end
end

function S.IsFishingLootOpen()
    if not api.IsFishingLoot then return false end
    local ok, result = pcall(api.IsFishingLoot)
    return ok and Clean(result) == true
end

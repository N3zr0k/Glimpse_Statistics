local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Beutefenster zählt nur mit vorherigem Zauber (Truhen also nicht).
--   GameObject  nach UNIT_SPELLCAST_SENT, mind. ein Material: gathering.herb/.ore/.other. Einmal je Abbau,
--               erneutes Öffnen desselben Abbaus nicht.
--   Creature    nur direkt nach erfolgreichem Kürschnern: skinning. Sonst Leichenbeute (Kills.lua); ein
--               Sofortzauber mit Auto-Loot ist kein Kürschnern.

local api = S.api
local Clean, ParseGUID = S.Clean, S.ParseGUID

local CAST_WINDOW = 1.0   -- Zauber muss so kurz vor LOOT_OPENED erfolgreich sein
local SENT_WINDOW = 10    -- Sammelzauber haben Zauberzeit
local TARGET_WINDOW = 15  -- Zielname des Zaubers = Knotenname
local SKIN_REPEAT = 600
local MAX_REMEMBERED = 2000

-- Bekannte Ränge; unbekannte IDs werden über den Zaubernamen erkannt
local SKINNING_SPELLS = { 8613, 8617, 8618, 10768, 32678, 50305, 74522 }
local skinningID = {}
for _, id in ipairs(SKINNING_SPELLS) do skinningID[id] = true end
local skinningName = {}

function S.IsSkinningSpell(spellID)
    spellID = tonumber(Clean(spellID))
    if not spellID then return false end
    if skinningID[spellID] then return true end
    if skinningName[spellID] ~= nil then return skinningName[spellID] end

    local name = S.SpellName and S.SpellName(spellID)
    local reference = S.SpellName and S.SpellName(SKINNING_SPELLS[1])
    if not (name and reference) then return false end -- noch nicht im Cache, nicht merken
    skinningName[spellID] = name == reference
    return skinningName[spellID]
end

local lastSent, lastSuccess, lastSkinning, lastTarget, lastTargetTime = -1000, -1000, -1000, nil, -1000
local nodeMark, nodeMarkSize = {}, 0
local SkinSeen = S.NewSeen(SKIN_REPEAT, MAX_REMEMBERED)

--- target kann leer sein.
function S:OnSpellSent(spellID, target)
    if S.IsFishingSpell(spellID) then return end

    lastSent = api.GetTime()
    target = Clean(target)
    if type(target) == "string" and target ~= "" then lastTarget, lastTargetTime = target, lastSent end
end

function S:OnSpellSucceeded(spellID)
    if S.IsFishingSpell(spellID) then return end
    lastSuccess = api.GetTime()
    if S.IsSkinningSpell(spellID) then lastSkinning = lastSuccess end
end

local function NewNodeCast(guid)
    if (nodeMark[guid] or -1) >= lastSent then return false end
    if nodeMarkSize >= MAX_REMEMBERED then
        wipe(nodeMark)
        nodeMarkSize = 0
    end
    if not nodeMark[guid] then nodeMarkSize = nodeMarkSize + 1 end
    nodeMark[guid] = lastSent
    return true
end

local UnitNameOf = S.UnitNameOf

--- Kein Fang: Knoten, Kürschnern, Kills nicht anvisierter Leichen.
function S:OnLoot()
    if not self:IsCollecting() then return end

    local opened = api.GetTime()
    local afterCast = lastSuccess >= (opened - CAST_WINDOW)
    local afterSkinning = lastSkinning >= (opened - CAST_WINDOW)
    local afterNodeCast = afterCast or lastSent >= (opened - SENT_WINDOW)

    for guid, items in pairs(self:ReadLoot()) do
        local kind, id = ParseGUID(guid)

        if kind == "GameObject" and id then
            if afterNodeCast and next(items) and NewNodeCast(guid) then
                local name = UnitNameOf(guid)
                if not name and lastTarget and (opened - lastTargetTime) <= TARGET_WINDOW then name = lastTarget end
                local category = S.CategoryOf(items)
                self:DebugLog("Gathering detected: %s [%s] as %s", tostring(name), tostring(id), category)
                self:Add("gathering." .. category, 1, id, name)
                self:AddTier("gathering." .. category, 1)
            elseif self:IsDebugging() then
                self:DebugLog("Node loot ignored: %s [%s] (%s)", tostring((UnitNameOf(guid))), tostring(id),
                    not afterNodeCast and "no gathering spell before" or (not next(items) and "no materials" or "already counted"))
            end

        elseif kind == "Creature" and id then
            local name = UnitNameOf(guid)
            if afterSkinning then
                if not SkinSeen(guid, opened) then
                    self:DebugLog("Skinning detected: %s [%s]", tostring(name), tostring(id))
                    self:Add("skinning", 1, id, name)
                    self:AddTier("skinning", 1)
                else
                    self:DebugLog("Skinning ignored (corpse already counted): %s [%s]", tostring(name), tostring(id))
                end
            else
                self:CountKill(guid, name, "loot")
            end
        end
    end
end

function S:OnLootOpened()
    if not self:IsCollecting() then return end
    if S.IsFishingLootOpen() then
        self:CountCatch()
    else
        self:OnLoot()
    end
end

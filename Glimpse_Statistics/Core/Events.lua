local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Einziger Event-Frame; die Sammler bleiben ohne Events und damit testbar.

local frame = CreateFrame("Frame")
S.eventFrame = frame

local function Dispatch(event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        -- unit, target, castGUID, spellID
        local _, target, _, spellID = ...
        if not S:CountCast(S.Clean(spellID)) then S:OnSpellSent(S.Clean(spellID), target) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- unit, castGUID, spellID
        local _, _, spellID = ...
        S:OnSpellSucceeded(S.Clean(spellID))
    elseif event == "PARTY_KILL" then
        S:OnPartyKill(...)
    elseif event == "LOOT_OPENED" then
        S:OnLootOpened()
    else
        S:OnTargetEvent(event)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local diag = S.diag
    diag.events = diag.events or {}
    diag.events[event] = (diag.events[event] or 0) + 1
    S.Protected(event, Dispatch, event, ...)
end)

function S:StartCollecting()
    frame:RegisterEvent("LOOT_OPENED")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:RegisterUnitEvent("UNIT_HEALTH", "target")
    -- Tod ändert die Ziel-Flags; nicht in jedem Client
    pcall(frame.RegisterUnitEvent, frame, "UNIT_DYNAMIC_FLAGS", "target")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- Ohne PARTY_KILL bleibt der Tod des Ziels als Ersatz (sichtbar in /gli stats status)
    S.diag.partyKill = pcall(frame.RegisterEvent, frame, "PARTY_KILL")
    S:StartDeathTracking()
end

function S:StopCollecting()
    frame:UnregisterAllEvents()
    S:StopDeathTracking()
end

function S:OnEnable()
    self:RegisterCollectorStats()
    self:StartCollecting()
    self:RegisterTooltips()
    self:RegisterWindow()
    self:RestoreWindow()
    self:StartBaseline()
end

function S:OnDisable()
    self:StopCollecting()
end

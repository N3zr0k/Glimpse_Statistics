local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Kill-Quellen: PARTY_KILL, Tod des eigenen (nicht fremd getappten) Ziels, gelootete Leichen ohne Ziel (AoE, Pet).
-- Einmal je GUID. Kampflog ist für Addons gesperrt.
-- Zähler: kills (je Kreatur), kills.area (je Zone), kills.zone ("<ID>@<Zone>").

local api = S.api
local Clean, ParseGUID = S.Clean, S.ParseGUID

-- GUIDs werden wiederverwendet, daher zählt dieselbe GUID nach 600 s erneut
local CREATURE_REPEAT = 600
local MAX_REMEMBERED = 2000
local Seen = S.NewSeen(CREATURE_REPEAT, MAX_REMEMBERED)

--- Einmal je Leiche, name optional.
function S:CountKill(guid, name, source)
    if not self:IsCollecting() then return end
    if type(guid) ~= "string" then return end

    local kind, id = ParseGUID(guid)
    if kind ~= "Creature" or not id then
        self:DebugLog("Kill ignored (%s is not a creature)", tostring(kind))
        return
    end
    if Seen(guid, api.GetTime()) then
        -- totes Ziel löst bei jedem UNIT_HEALTH erneut aus, kein Debug-Spam
        if source == "loot" then
            self:DebugLog("Kill ignored (corpse already counted): %s [%s]", tostring(name), tostring(id))
        end
        return
    end
    self:DebugLog("Kill detected: %s [%s] via %s", tostring(name), tostring(id), source or "?")

    self:Add("kills", 1, id, name)

    local zone, zoneName = self:CurrentZone()
    if zone then
        self:Add("kills.area", 1, zone, zoneName)
        self:Add("kills.zone", 1, id .. "@" .. zone, name and (name .. " - " .. tostring(zoneName or zone)) or nil)
    end
end

-- GUID -> Name, da PARTY_KILL nur die GUID liefert
local MAX_NAMES = 300
local names, nameCount = {}, 0

local function Remember(guid, name)
    if type(name) ~= "string" or name == "" or names[guid] == name then return end
    if not names[guid] then
        if nameCount >= MAX_NAMES then wipe(names) nameCount = 0 end
        nameCount = nameCount + 1
    end
    names[guid] = name
end

local function NameOf(guid)
    return names[guid] or S.UnitNameOf(guid)
end

local targetGUID -- letzte lesbare GUID des Ziels

local function RefreshTargetGUID(reset)
    local guid = Clean(api.UnitGUID("target"))
    if type(guid) == "string" then
        targetGUID = guid
        Remember(guid, Clean(api.UnitName("target")))
    elseif reset then
        targetGUID = nil -- neues Ziel mit gesperrter GUID
    end
end

-- Diagnose für /gli stats status
S.diag = S.diag or { checks = 0, dead = 0, secret = 0, noGUID = 0, tapped = 0 }
local diag = S.diag

-- nil bei Secret. Health 0 zählt mit, da UnitIsDead beim Event teils noch false ist.
local function TargetDead()
    local ok, dead = pcall(api.UnitIsDead, "target")
    if ok then
        dead = Clean(dead)
        if dead == true then return true end
    else
        dead = nil
    end
    if api.UnitHealth then
        local hOK, health = pcall(api.UnitHealth, "target")
        health = hOK and Clean(health) or nil
        if type(health) == "number" then return health <= 0 end
    end
    return dead
end

--- Im Kampf ist die Ziel-GUID evtl. gesperrt, dann gilt targetGUID.
function S:CheckTargetKill()
    if not self:IsCollecting() then return end
    if diag.partyKill then return end -- PARTY_KILL kennt den Killer und hat Vorrang
    diag.checks = diag.checks + 1

    local dead = TargetDead()
    if dead == nil then diag.secret = diag.secret + 1 self:DebugLog("Target check: value is secret, nothing counted") return end
    if dead ~= true then return end
    diag.dead = diag.dead + 1

    local guid = Clean(api.UnitGUID("target"))
    if type(guid) ~= "string" then guid = targetGUID end
    if type(guid) ~= "string" then
        diag.noGUID = diag.noGUID + 1
        self:DebugLog("Target died but its GUID is not readable")
        return
    end

    if api.UnitIsTapDenied then
        local tapOK, denied = pcall(api.UnitIsTapDenied, "target")
        if tapOK and Clean(denied) == true then
            diag.tapped = diag.tapped + 1
            self:DebugLog("Target died but belongs to another player (tap denied)")
            return
        end -- fremd getappt
    end

    self:CountKill(guid, Clean(api.UnitName("target")), "target death")
end

-- Tod/Kampfende ist beim Event teils noch nicht sichtbar; doppelt zählen verhindert Seen.
local function Recheck(...)
    if not api.After then return end
    for _, delay in ipairs({ ... }) do
        api.After(delay, function() S.Protected("Recheck", S.CheckTargetKill, S) end)
    end
end

function S:OnTargetEvent(event)
    if event == "PLAYER_TARGET_CHANGED" then
        RefreshTargetGUID(true)
    elseif event == "UNIT_HEALTH" or event == "UNIT_DYNAMIC_FLAGS" then
        RefreshTargetGUID(false)
    end
    self:CheckTargetKill()

    if event == "PLAYER_REGEN_ENABLED" then Recheck(0.5, 2) end
end

--- Kommt auch für Gruppenmitglieder, gezählt wird nur Spieler oder eigenes Pet.
function S:OnPartyKill(killer, victim)
    if not self:IsCollecting() then return end
    killer, victim = Clean(killer), Clean(victim)
    if type(killer) ~= "string" or type(victim) ~= "string" then return end

    local mine = killer == Clean(api.UnitGUID("player")) or killer == Clean(api.UnitGUID("pet"))
    if not mine then
        self:DebugLog("Party kill by someone else, not counted")
        return
    end
    self:CountKill(victim, NameOf(victim), "party kill")
end

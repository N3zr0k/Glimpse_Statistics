local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Tode per PLAYER_DEAD: deaths (je NPC-ID des Verursachers), deaths.area (je Zone).
-- Kampflog ist gesperrt, daher Schätzung: bei jedem Schaden werden Einheiten gesampelt, die den Spieler im Ziel haben
-- (target, focus, boss, nameplate). Verursacher = zuletzt gesehen, bei Gleichstand nach dieser Reihenfolge.
-- Ohne lesbaren Angreifer (Umwelt, Secret, außer Sicht) zählt nur der Tod.

local api = S.api
local Clean, ParseGUID = S.Clean, S.ParseGUID

local SAMPLE_INTERVAL = 0.3
local ATTACKER_MAX_AGE = 20 -- Sekunden
local DEATH_REPEAT = 5 -- Sekunden, gegen doppeltes PLAYER_DEAD
local MAX_ATTACKERS = 40

local units = { "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
for index = 1, 40 do units[#units + 1] = "nameplate" .. index end
-- "target" -> "targettarget", vorberechnet da bei jedem Treffer gebraucht
local targetOf = {}
for _, unit in ipairs(units) do targetOf[unit] = unit .. "target" end

local attackers, attackerCount = {}, 0 -- guid -> { id, name, at, rank }
local lastSample, lastDeath = -1e9, -1e9

local function Forget()
    wipe(attackers)
    attackerCount = 0
end

-- Lesbare, angreifbare Kreatur mit dem Spieler als Ziel, sonst nil
local function Attacker(unit)
    if not (api.UnitExists and api.UnitIsUnit) then return nil end
    local ok, exists = pcall(api.UnitExists, unit)
    if not ok or Clean(exists) ~= true then return nil end

    local guid = Clean(api.UnitGUID(unit))
    if type(guid) ~= "string" then return nil end
    local kind, id = ParseGUID(guid)
    if kind ~= "Creature" or not id then return nil end

    local canOK, can = pcall(api.UnitCanAttack, "player", unit)
    if not canOK or Clean(can) ~= true then return nil end
    local deadOK, dead = pcall(api.UnitIsDead, unit)
    if deadOK and Clean(dead) == true then return nil end

    local hitOK, hits = pcall(api.UnitIsUnit, targetOf[unit], "player")
    if not hitOK or Clean(hits) ~= true then return nil end
    return guid, id, Clean(api.UnitName(unit))
end

function S:SampleAttackers()
    local now = api.GetTime()
    lastSample = now
    for rank, unit in ipairs(units) do
        local guid, id, name = Attacker(unit)
        if guid then
            local entry = attackers[guid]
            if not entry then
                if attackerCount >= MAX_ATTACKERS then Forget() end
                attackerCount = attackerCount + 1
                entry = {}
                attackers[guid] = entry
            end
            -- mehrfach im selben Durchgang: kleinster Rang gewinnt
            entry.rank = (entry.at == now and entry.rank) and math.min(entry.rank, rank) or rank
            entry.id, entry.name, entry.at = id, name or entry.name, now
        end
    end
end

-- zuletzt gesehen, bei Gleichstand kleinster Rang
local function Killer(now)
    local best
    for _, entry in pairs(attackers) do
        if now - entry.at <= ATTACKER_MAX_AGE then
            if not best or entry.at > best.at or (entry.at == best.at and entry.rank < best.rank) then best = entry end
        end
    end
    return best
end

function S:OnPlayerDead()
    if not self:IsCollecting() then return end
    local now = api.GetTime()
    if now - lastDeath < DEATH_REPEAT then return end
    lastDeath = now

    -- Beim Tod haben Gegner schon das Ziel gewechselt, daher die Samples aus dem Kampf nehmen
    -- und nur ohne sie jetzt prüfen.
    local killer = Killer(now)
    if not killer then
        self:SampleAttackers()
        killer = Killer(now)
    end
    Forget()

    if killer then
        self:DebugLog("Death: killed by %s [%s]", tostring(killer.name), tostring(killer.id))
        self:Add("deaths", 1, killer.id, killer.name)
    else
        self:DebugLog("Death: killer unknown")
        self:Add("deaths", 1)
    end

    local zone, zoneName = self:CurrentZone()
    if zone then self:Add("deaths.area", 1, zone, zoneName) end
end

local frame = CreateFrame("Frame")
S.deathFrame = frame

local function Handle(event)
    if event == "PLAYER_DEAD" then
        S:OnPlayerDead()
    elseif api.GetTime() - lastSample >= SAMPLE_INTERVAL then
        S:SampleAttackers()
    end
end

frame:SetScript("OnEvent", function(_, event) S.Protected(event, Handle, event) end)

function S:StartDeathTracking()
    frame:RegisterEvent("PLAYER_DEAD")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterUnitEvent("UNIT_HEALTH", "player")
    pcall(frame.RegisterUnitEvent, frame, "UNIT_COMBAT", "player") -- WOUND
end

function S:StopDeathTracking()
    frame:UnregisterAllEvents()
    Forget()
end

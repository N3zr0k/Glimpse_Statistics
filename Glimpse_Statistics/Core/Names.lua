local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Namen für die Aufschlüsselung. Database speichert nur IDs, Namen kommen vom Client:
--   item          Item-Cache des Clients
--   zone          uiMapID über das Modul Locations; Instanzen (-instanceID) haben dort keinen Namen
--   npc, object   der Client nennt Namen nur für sichtbare Einheiten und Objekte
--   mode          Fortbewegungsart aus dem Modul Reisen (1 bis 8)
--   flightpoint   nodeID; Karte aus den Orten in travel, Name vom Client (C_TaxiMap)
--   tramstop      Ziel der Tiefenbahn: 1 Sturmwind, 2 Eisenschmiede, 0 = Einstiegsstadt unbekannt
--   route         Flugstrecke von * 10000 + nach, aus zwei Flugpunkten
-- Was der Client nicht liefert, kommt aus den alten Daten von Statistics (GlimpseStatisticsDB, nur gelesen), sonst
-- steht die ID da. ID 0 heißt bei Kills und Toden: keiner Kreatur zugeordnet.

-- Alte Zählerschlüssel und welche Namen in ihrer Aufschlüsselung stehen
local OLD_KEYS = {
    kills = "npc", deaths = "npc", skinning = "npc",
    ["gathering.herb"] = "object", ["gathering.ore"] = "object", ["gathering.other"] = "object",
    ["fishing.items"] = "item",
    -- Zonen-Zähler: nur die Instanzen ("i<ID>") sind interessant
    ["kills.area"] = "instance", ["deaths.area"] = "instance", ["fishing.casts"] = "instance", ["fishing.catches"] = "instance",
}

local oldNames

local function AddOld(by)
    if type(by) ~= "table" then return end
    for key, kind in pairs(OLD_KEYS) do
        for subKey, entry in pairs(type(by[key]) == "table" and by[key] or {}) do
            local name = type(entry) == "table" and entry.name
            local id = kind == "instance" and type(subKey) == "string" and tonumber(subKey:match("^i(%d+)$"))
                or (kind ~= "instance" and tonumber(subKey))
            if id and type(name) == "string" and name ~= "" and not oldNames[kind][id] then oldNames[kind][id] = name end
        end
    end
end

-- Einmal aufgebaut, die alten Daten ändern sich nicht mehr
local function OldNames()
    if oldNames then return oldNames end
    oldNames = { npc = {}, object = {}, item = {}, instance = {} }
    local old = _G.GlimpseStatisticsDB
    if type(old) ~= "table" then return oldNames end
    AddOld(type(old.global) == "table" and old.global.by)
    for _, data in pairs(type(old.char) == "table" and old.char or {}) do
        AddOld(type(data) == "table" and data.by)
    end
    return oldNames
end

--- Für Tests: alte Namen neu lesen.
function S:ResetNames()
    oldNames = nil
end

local function ItemName(id)
    local get = S.api.GetItemNameByID
    if not get then return nil end
    local ok, name = pcall(get, id)
    name = ok and S.Clean(name) or nil
    if type(name) == "string" and name ~= "" then return name end
end

--- Zonenname zu uiMapID oder -instanceID.
function S:ZoneName(zone)
    zone = tonumber(zone)
    if not zone then return tostring(zone) end
    if zone < 0 then return OldNames().instance[-zone] or format(L["Instance %d"], -zone) end

    local Locations = Glimpse:GetModule("Locations", true)
    if Locations and Locations.GetMapName then
        local ok, name = pcall(Locations.GetMapName, Locations, zone)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return format(L["Zone %d"], zone)
end

-- Reihenfolge wie Travel.MODES im Core
local MODES = { L["Walking"], L["Riding"], L["Swimming"], L["Flight path"], L["Ghost"], L["Ship or zeppelin"],
    L["Under water"], L["Deeprun Tram"] }

local TRAM_STOPS = { L["Stormwind"], L["Ironforge"] }

local flightPoints = {} -- nodeID -> Name, einmal gefunden reicht

local function FlightPointName(id)
    if flightPoints[id] then return flightPoints[id] end
    local reader, get = S:Reader("travel"), S.api.GetTaxiNodesForMap
    if not (reader and get) then return nil end
    for _, place in ipairs(reader:GetLocations(nil, id, "all") or {}) do
        local ok, nodes = pcall(get, place.mapID)
        for _, node in ipairs(ok and type(nodes) == "table" and nodes or {}) do
            local name = S.Clean(node.name)
            if node.nodeID == id and type(name) == "string" and name ~= "" then
                flightPoints[id] = name
                return name
            end
        end
    end
end

--- Für Tests: gefundene Flugpunkt-Namen vergessen.
function S:ResetFlightPoints()
    wipe(flightPoints)
end

local FALLBACK = { npc = "Creature %d", object = "Object %d", item = "Item %d", mode = "Mode %d",
    flightpoint = "Flight point %d", tramstop = "Stop %d" }

--- Name einer ID der Aufschlüsselung, names wie in Counters.lua ("npc", "object", "item", "mode", "zone" ...).
function S:NameOf(names, id)
    if names == "npc" and id == 0 then return L["Unknown"] end
    if names == "zone" then return self:ZoneName(id) end
    if names == "route" then
        local from, to = math.floor(id / 10000), id % 10000
        return format("%s - %s", self:NameOf("flightpoint", from), self:NameOf("flightpoint", to))
    end
    if names == "mode" and MODES[id] then return MODES[id] end
    if names == "tramstop" then
        if id == 0 then return L["Unknown"] end
        if TRAM_STOPS[id] then return TRAM_STOPS[id] end
    end
    if names == "flightpoint" then
        local name = FlightPointName(id)
        if name then return name end
    end
    local name = names == "item" and ItemName(id) or nil
    name = name or (OldNames()[names] or {})[id]
    return name or format(L[FALLBACK[names] or "ID %d"], id)
end

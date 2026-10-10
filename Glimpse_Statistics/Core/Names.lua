local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Namen für die Aufschlüsselung. Database speichert nur IDs, Namen kommen vom Client:
--   item          Item-Cache des Clients
--   zone          uiMapID über das Modul Locations; Instanzen (-instanceID) haben dort keinen Namen
--   npc, object   Namensdienst des Cores (Glimpse.IDs:NPCName und :ObjectName), er lernt sie beim Spielen
--   mode          Fortbewegungsart aus dem Modul Reisen (1 bis 8)
--   flightpoint   nodeID; Karte aus den Orten in travel, Name vom Client (C_TaxiMap)
--   tramstop      Ziel der Tiefenbahn: 1 Sturmwind, 2 Eisenschmiede, 0 = Einstiegsstadt unbekannt
--   route         Flugstrecke von * 10000 + nach, aus zwei Flugpunkten
-- Was niemand liefert, steht als ID da. ID 0 heißt bei Kills und Toden: keiner Kreatur zugeordnet.

--- Name aus dem Namensdienst des Cores (npc, object), nil wenn er fehlt oder die ID nicht kennt.
local function CoreName(names, id)
    local IDs = Glimpse.IDs
    local get = IDs and (names == "npc" and IDs.NPCName or IDs.ObjectName)
    if not get then return nil end
    local ok, name = pcall(get, IDs, id)
    name = ok and S.Clean(name) or nil
    if type(name) == "string" and name ~= "" then return name end
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
    if zone < 0 then return format(L["Instance %d"], -zone) end

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
    if names == "npc" or names == "object" then name = CoreName(names, id) end
    return name or format(L[FALLBACK[names] or "ID %d"], id)
end

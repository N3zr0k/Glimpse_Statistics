local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Öffentliche API für andere Addons (API_VERSION 5). Liefert Daten statt Text, gegliedert nach Themen
-- (Berufe: fishing, herbalism, mining, skinning; Kampf: kills, deaths, combat; Reisen: travel, tram; Charakter: character). Die Zahlen kommen aus Glimpse: Database;
-- wer nur einzelne Zähler braucht, liest besser selbst mit GlimpseDB:Get(namespace). Jedes Feld ist immer vorhanden
-- (0, leere Liste oder, wo angegeben, nil). Neue Felder sind möglich, bestehende bleiben.
--
--   S:GetInfo()                  { api, apiMin, name, version, available, collecting } (available: Database lesbar)
--   S:GetTopicList(kind)         Liste { key, kind, label, metrics = { Name ... } }; kind "profession", "combat", nil = alle
--   S:Query(request)             request (alles optional, Unbekanntes wird ignoriert):
--                                  topics     z. B. { "fishing", "kills" }; nil oder "all" = alle
--                                  kind       nur Themen dieser Art (mit topics: beides muss passen)
--                                  scope      "char" (Standard), "account", Charakter-Index oder "Name - Realm"
--                                  periods    Zeiträume in Tagen, Standard { 1, 7 }
--                                  tiers      Werte je Berufsstufe (Standard true)
--                                  breakdown  Anzahl Einträge der Aufschlüsselung je Kennzahl (Standard 0)
--
-- Antwort (immer eine Tabelle, nie ein Fehler):
--   { api, schema = 1, ok, scope, since (Zeitpunkt oder nil), sinceText (oder nil),
--     labels = { since, periods = { [Tage] = Text } },
--     order = { Themen in fester Reihenfolge }, unknown = { angefragte, unbekannte Themen },
--     topics = { [key] = {
--         key, kind, label, hasData,
--         metrics = { [name] = { label, unit ("count", "seconds", "yards"), total, periods = { [Tage] = Zahl },
--                                tiers = { { max, name, count } },            -- leer ohne Stufen
--                                breakdown = { { id, name, count } } } },     -- größte Einträge, leer ohne breakdown
--         derived = { [name] = { label, unit ("count", "ratio" oder "seconds"), value (nil wenn nicht berechenbar),
--                                tiers = { { max, name, value, numerator, denominator } } } } } } }
--
-- Eingebaut: fishing (casts, catches, fish, fishByZone; derived missed, rate), herbalism/mining (gathered),
-- skinning (skinned), kills (total, byZone), deaths (total, byZone), combat (time, looted), travel (distance und time
-- je Fortbewegungsart 1 Laufen, 2 Reiten, 3 Schwimmen, 4 Flugroute, 5 Geist, 6 Schiff/Zeppelin, 7 unter Wasser,
-- 8 Tiefenbahn; zones und zoneTime je Zone; flightPoints; teleports; flights, flightTime und flightDistance je
-- Strecke von * 10000 + nach; derived averageFlight), tram (Tiefenbahn: rides je Ziel
-- 1 Sturmwind, 2 Eisenschmiede, 0 unbekannt; distance; time = Fahrzeit, fest 58 s je Fahrt; stay = Sekunden in der Instanz),
-- character (jumps, walked, ridden, swum, dived, ghost: Strecken in Yards). total enthält den Blizzard-Startwert,
-- Zeiträume, Quoten und Aufschlüsselungen nicht. Kennzahlen "...ByZone" sind nach Zone (uiMapID, Instanz -ID)
-- aufgeschlüsselt. zones und flightPoints zählen verschiedene IDs (beim Account ohne Doppelte), Zeiträume sind dort 0.
-- Nachricht GLIMPSE_STATISTICS_UPDATED (key, topic, metric) bei jeder Änderung in Database; ohne Argumente, wenn
-- vieles auf einmal geändert wurde (Import, Zurücksetzen).
--
-- Seit API 5 (Umstieg auf Database) entfallen RegisterStat, Add, RegisterTopic und die anderen Funktionen eigener
-- Zähler; Zeiträume zählen ab Mitternacht Ortszeit, fishByZone ist nach Zone statt nach Fisch und Zone aufgeteilt.

S.API_MIN_COMPATIBLE = 5
S.API_SCHEMA = 1

-- Eingebaute Themen: Kennzahl -> Zählerschlüssel, in Anzeigereihenfolge. breakdown = "id" oder "zone".
local topics, order = {}, {}

local function Define(key, kind, metrics, derive, label)
    topics[key] = { key = key, kind = kind, metrics = metrics, derive = derive, label = label }
    order[#order + 1] = key
end

local function Percent(part, whole)
    if not whole or whole <= 0 then return nil end
    return part / whole
end

-- Fänge ohne Blizzard-Startwert, da es zu ihm keine Würfe gibt
local function FishingDerived(metrics, self, scope)
    local casts, catches = metrics.casts, metrics.catches
    local missed = { label = L["Casts without catch"], unit = "count", value = nil, tiers = {} }
    local rate = { label = L["Catch rate"], unit = "ratio", value = nil, tiers = {} }

    local counted = self:GetCounted("fishing.catches", scope)
    missed.value = math.max(casts.total - counted, 0)
    rate.value = Percent(counted, casts.total)

    local byMax, list = {}, {}
    local function Entry(tier)
        local entry = byMax[tier.max]
        if not entry then
            entry = { max = tier.max, name = tier.name, casts = 0, catches = 0 }
            byMax[tier.max] = entry
            list[#list + 1] = entry
        end
        return entry
    end
    for _, tier in ipairs(casts.tiers) do Entry(tier).casts = tier.count end
    for _, tier in ipairs(catches.tiers) do Entry(tier).catches = tier.count end
    table.sort(list, function(a, b) return a.max < b.max end)
    for _, entry in ipairs(list) do
        local missing = math.max(entry.casts - entry.catches, 0)
        missed.tiers[#missed.tiers + 1] = { max = entry.max, name = entry.name, value = missing, numerator = missing,
            denominator = entry.casts }
        rate.tiers[#rate.tiers + 1] = { max = entry.max, name = entry.name, value = Percent(entry.catches, entry.casts),
            numerator = entry.catches, denominator = entry.casts }
    end
    return { missed = missed, rate = rate }
end

Define("fishing", "profession", { { "casts", "fishing.casts" }, { "catches", "fishing.catches" },
    { "fish", "fishing.items", breakdown = "id" }, { "fishByZone", "fishing.items", breakdown = "zone" } }, FishingDerived)
Define("herbalism", "profession", { { "gathered", "gathering.herb", breakdown = "id" } })
Define("mining", "profession", { { "gathered", "gathering.ore", breakdown = "id" } })
Define("skinning", "profession", { { "skinned", "skinning", breakdown = "id" } })
Define("kills", "combat", { { "total", "kills", breakdown = "id" }, { "byZone", "kills", breakdown = "zone" } }, nil,
    L["Creatures killed"])
Define("deaths", "combat", { { "total", "deaths", breakdown = "id" }, { "byZone", "deaths", breakdown = "zone" } }, nil,
    L["Deaths"])

local function TravelDerived(metrics)
    local flights, seconds = metrics.flights.total, metrics.flightTime.total
    return { averageFlight = { label = L["Average flight"], unit = "seconds", value = flights > 0 and seconds / flights or nil,
        tiers = {} } }
end

Define("combat", "combat", { { "time", "combat.time" }, { "looted", "combat.looted", breakdown = "id" } }, nil, L["Combat"])
Define("travel", "travel", { { "distance", "travel.distance", breakdown = "id" }, { "time", "travel.time", breakdown = "id" },
    { "zones", "travel.zones", breakdown = "id" }, { "zoneTime", "travel.zonetime", breakdown = "id" },
    { "flightPoints", "travel.flightpoints" }, { "teleports", "travel.teleports" },
    { "flights", "travel.flights", breakdown = "id" }, { "flightTime", "travel.flighttime", breakdown = "id" },
    { "flightDistance", "travel.flightdistance", breakdown = "id" }, { "shipDistance", "travel.ship" } }, TravelDerived, L["Travel"])
Define("tram", "travel", { { "rides", "tram.rides", breakdown = "id" }, { "distance", "tram.distance" }, { "time", "tram.time" },
    { "stay", "tram.stay" } }, nil, L["Deeprun Tram"])
Define("character", "character", { { "jumps", "jumps" }, { "walked", "char.walked" }, { "ridden", "char.ridden" },
    { "swum", "char.swum" }, { "dived", "char.dived" }, { "ghost", "char.ghost" } }, nil, L["Character"])

-- Zählerschlüssel -> { Thema, Kennzahl } (erste Kennzahl des Zählers)
local owner = {}
for _, key in ipairs(order) do
    for _, metric in ipairs(topics[key].metrics) do
        owner[metric[2]] = owner[metric[2]] or { key, metric[1] }
    end
end

--- Thema und Kennzahl eines Zählers, nichts wenn unbekannt.
function S:TopicOfKey(key)
    local entry = owner[key]
    if entry then return entry[1], entry[2] end
end

local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return nil end
    local ok, value = pcall(get, "Glimpse_Statistics", "Version")
    return ok and type(value) == "string" and value or nil
end

function S:GetInfo()
    local available = self:Database() ~= nil
    -- collecting: erfasst wird von Glimpse und seinen Erweiterungen, sobald Database da ist
    return { api = self.API_VERSION, apiMin = self.API_MIN_COMPATIBLE, name = "Glimpse_Statistics", version = Version(),
        available = available, collecting = available }
end

--- Berufe lokalisiert vom Client, Kampf aus L.
function S:TopicLabel(key)
    local topic = topics[key]
    if not topic then return key end
    if topic.label then return topic.label end
    if topic.kind == "profession" then return self:ProfessionClientName(key) or key end
    return key
end

function S:GetTopicList(kind)
    local list = {}
    for _, key in ipairs(order) do
        local topic = topics[key]
        if kind == nil or topic.kind == kind then
            local metrics = {}
            for _, metric in ipairs(topic.metrics) do metrics[#metrics + 1] = metric[1] end
            list[#list + 1] = { key = key, kind = topic.kind, label = self:TopicLabel(key), metrics = metrics }
        end
    end
    return list
end

local function Periods(self, key, scope, periods)
    local result = {}
    for _, days in ipairs(periods) do
        local ok, value = pcall(self.GetSum, self, key, scope, days)
        result[days] = ok and tonumber(value) or 0
    end
    return result
end

local function Tiers(self, key, scope)
    local result = {}
    local ok, list = pcall(self.GetTierCounts, self, key, scope)
    for _, tier in ipairs(ok and list or {}) do result[#result + 1] = { max = tier.max, name = tier.name, count = tier.count } end
    return result
end

local function Breakdown(self, key, scope, kind, limit)
    local result = {}
    if not kind or limit < 1 then return result end
    local get = kind == "zone" and self.GetZoneBreakdown or self.GetBreakdown
    local ok, list = pcall(get, self, key, scope, limit)
    for _, entry in ipairs(ok and list or {}) do result[#result + 1] = { id = entry.key, name = entry.name, count = entry.count } end
    return result
end

local UNITS = { time = "seconds", distance = "yards" }

local function Metric(self, metric, scope, periods, withTiers, limit)
    local key, kind = metric[2], metric.breakdown
    local counter = self.counterByKey[key]
    -- nach Zone ohne Startwert, er gehört zu keiner Zone
    local total = kind == "zone" and self:GetCounted(key, scope) or self:Get(key, scope)
    return {
        label = counter.label, unit = UNITS[counter.unit] or "count", total = tonumber(total) or 0,
        periods = Periods(self, key, scope, periods),
        tiers = withTiers and Tiers(self, key, scope) or {},
        breakdown = Breakdown(self, key, scope, kind, limit),
    }
end

local function Topic(self, topic, scope, periods, withTiers, limit)
    local metrics, hasData = {}, false
    for _, metric in ipairs(topic.metrics) do
        local entry = Metric(self, metric, scope, periods, withTiers, limit)
        metrics[metric[1]] = entry
        if entry.total > 0 then hasData = true end
    end
    return { key = topic.key, kind = topic.kind, label = self:TopicLabel(topic.key), hasData = hasData, metrics = metrics,
        derived = topic.derive and topic.derive(metrics, self, scope) or {} }
end

local function Wanted(list)
    if list == nil or list == "all" then return nil end
    local wanted = {}
    for _, key in ipairs(type(list) == "table" and list or { list }) do wanted[tostring(key)] = true end
    return wanted
end

-- Unbekannter Charakter: Index, den es nicht gibt, damit alle Werte 0 sind
local NOBODY = -1

function S:Query(request)
    request = type(request) == "table" and request or {}
    local scope = request.scope
    if scope ~= "account" and type(scope) ~= "string" and type(scope) ~= "number" then scope = "char" end

    local periods = {}
    for _, days in ipairs(type(request.periods) == "table" and request.periods or { 1, 7 }) do
        days = tonumber(days)
        if days and days >= 1 then periods[#periods + 1] = math.floor(days) end
    end
    local limit = math.max(math.min(math.floor(tonumber(request.breakdown) or 0), 100), 0)

    local response = { api = self.API_VERSION, schema = self.API_SCHEMA, ok = false, scope = scope, topics = {}, order = {}, unknown = {},
        labels = { since = L["Counting since"], periods = { [1] = L["today"], [7] = L["7 days"], [30] = L["30 days"] } } }
    if not self:Database() then return response end

    response.ok = pcall(function()
        local resolved = self:ResolveScope(scope) or NOBODY
        response.since = self:GetSince(resolved)
        response.sinceText = response.since and self:FormatDate(response.since) or nil

        local wanted = Wanted(request.topics)
        for _, key in ipairs(order) do
            local topic = topics[key]
            if (not wanted or wanted[key]) and (request.kind == nil or topic.kind == request.kind) then
                response.topics[key] = Topic(self, topic, resolved, periods, request.tiers ~= false, limit)
                response.order[#response.order + 1] = key
            end
        end
        for key in pairs(wanted or {}) do
            if not topics[key] then response.unknown[#response.unknown + 1] = key end
        end
        table.sort(response.unknown)
    end)
    return response
end

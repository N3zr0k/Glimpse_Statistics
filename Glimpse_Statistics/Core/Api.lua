local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Öffentliche API für andere Addons (API_VERSION 4). Liefert Daten statt Text, gegliedert nach Themen
-- (Berufe: fishing, herbalism, mining, skinning; Kampf: kills, deaths; weitere per RegisterTopic).
-- DB-Schlüssel stehen nur in der Zuordnung unten. Jedes Feld ist immer vorhanden (0, leere Liste oder,
-- wo angegeben, nil). Neue Felder sind möglich, bestehende bleiben.
--
--   S:GetInfo()                  { api, apiMin, name, version, available, collecting } (available: Daten lesbar)
--   S:GetTopicList(kind)         Liste { key, kind, label, metrics = { Name ... } }; kind "profession", "combat" ..., nil = alle
--   S:RegisterTopic(key, def)    def = { kind, label, metrics = { { name, key, label, breakdown } ... } }, key = Zähler aus :Add.
--                                false bei ungültigen Angaben oder vergebenem Namen.
--   S:Query(request)             request (alles optional, Unbekanntes wird ignoriert):
--                                  topics     z. B. { "fishing", "kills" }; nil oder "all" = alle
--                                  kind       nur Themen dieser Art (mit topics: beides muss passen)
--                                  scope      "char" (Standard), "account" oder "Name - Realm"
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
--         metrics = { [name] = { label, total, periods = { [Tage] = Zahl },
--                                tiers = { { max, name, count } },            -- leer ohne Stufen
--                                breakdown = { { id, name, count } } } },     -- größte Einträge, leer ohne breakdown
--         derived = { [name] = { label, unit ("count" oder "ratio"), value (nil wenn nicht berechenbar),
--                                tiers = { { max, name, value, numerator, denominator } } } } } } }
--
-- Eingebaut: fishing (casts, catches, fish, fishByZone; derived missed, rate), herbalism/mining (gathered),
-- skinning (skinned), kills (total, byZone), deaths (total, byZone).
-- Nachricht GLIMPSE_STATISTICS_UPDATED (key, topic, metric): topic/metric nil, wenn der Zähler zu keinem Thema gehört.

S.API_MIN_COMPATIBLE = 1
S.API_SCHEMA = 1

-- Eingebaute Themen: Kennzahl -> Zählerschlüssel, in Anzeigereihenfolge. breakdown = true: Aufschlüsselung abfragbar.
local topics, order = {}, {}

local function Define(key, kind, metrics, derive, label)
    topics[key] = { key = key, kind = kind, metrics = metrics, derive = derive, label = label, builtin = true }
    order[#order + 1] = key
end

local function Percent(part, whole)
    if not whole or whole <= 0 then return nil end
    return part / whole
end

-- Fänge ohne Blizzard-Startwert (Core/Baseline/Baseline.lua), da es zu ihm keine Würfe gibt.
local function FishingDerived(metrics, self, scope)
    local casts, catches = metrics.casts, metrics.catches
    local missed = { label = L["Casts without catch"], unit = "count", value = nil, tiers = {} }
    local rate = { label = L["Catch rate"], unit = "ratio", value = nil, tiers = {} }
    if not (casts and catches) then return { missed = missed, rate = rate } end

    local counted = math.max(catches.total - (self and self:GetBaseline("fishing.catches", scope) or 0), 0)
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
        missed.tiers[#missed.tiers + 1] = { max = entry.max, name = entry.name, value = math.max(entry.casts - entry.catches, 0),
            numerator = math.max(entry.casts - entry.catches, 0), denominator = entry.casts }
        rate.tiers[#rate.tiers + 1] = { max = entry.max, name = entry.name, value = Percent(entry.catches, entry.casts),
            numerator = entry.catches, denominator = entry.casts }
    end
    return { missed = missed, rate = rate }
end

Define("fishing", "profession", { { "casts", "fishing.casts" }, { "catches", "fishing.catches" }, { "fish", "fishing.items" },
    { "fishByZone", "fishing.items.zone", breakdown = true } }, FishingDerived)
Define("herbalism", "profession", { { "gathered", "gathering.herb", breakdown = true } })
Define("mining", "profession", { { "gathered", "gathering.ore", breakdown = true } })
Define("skinning", "profession", { { "skinned", "skinning", breakdown = true } })
Define("kills", "combat", { { "total", "kills", breakdown = true }, { "byZone", "kills.area", breakdown = true } }, nil, L["Creatures killed"])
Define("deaths", "combat", { { "total", "deaths", breakdown = true }, { "byZone", "deaths.area", breakdown = true } }, nil, L["Deaths"])

-- Zählerschlüssel (inkl. "<key>.tier") -> { Thema, Kennzahl }
local owner = {}
local function Own(topic)
    for _, metric in ipairs(topic.metrics) do
        owner[metric[2]] = { topic.key, metric[1] }
        owner[metric[2] .. ".tier"] = { topic.key, metric[1] }
    end
end
for _, key in ipairs(order) do Own(topics[key]) end

--- Thema und Kennzahl eines Zählers, nichts wenn unbekannt.
function S:TopicOfKey(key)
    local entry = owner[key]
    if entry then return entry[1], entry[2] end
end

--- Siehe Dateikopf.
function S:RegisterTopic(key, def)
    if type(key) ~= "string" or not key:match("^[%a][%w_]*$") or type(def) ~= "table" or type(def.metrics) ~= "table" then return false end
    if topics[key] and topics[key].builtin then return false end

    local metrics, seen = {}, {}
    for _, metric in ipairs(def.metrics) do
        local name, counter = type(metric) == "table" and metric.name or nil, type(metric) == "table" and metric.key or nil
        if type(name) ~= "string" or not name:match("^[%a][%w_]*$") or type(counter) ~= "string" or counter == "" or seen[name] then return false end
        seen[name] = true
        metrics[#metrics + 1] = { name, counter, label = type(metric.label) == "string" and metric.label or nil, breakdown = metric.breakdown == true }
    end
    if #metrics == 0 then return false end

    if not topics[key] then order[#order + 1] = key end
    topics[key] = { key = key, kind = type(def.kind) == "string" and def.kind or "other", label = type(def.label) == "string" and def.label or key,
        metrics = metrics }
    Own(topics[key])
    return true
end

local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return nil end
    local ok, value = pcall(get, "Glimpse_Statistics", "Version")
    return ok and type(value) == "string" and value or nil
end

function S:GetInfo()
    local available = self.char ~= nil and self.account ~= nil
    return { api = self.API_VERSION, apiMin = self.API_MIN_COMPATIBLE, name = "Glimpse_Statistics", version = Version(),
        available = available, collecting = available and self:IsCollecting() == true }
end

--- Berufe lokalisiert vom Client, Kampf aus L, eigene Themen wie gemeldet.
function S:TopicLabel(key)
    local topic = topics[key]
    if not topic then return key end
    if topic.label then return topic.label end
    if topic.kind == "profession" and self.ProfessionClientName then return self:ProfessionClientName(key) or key end
    if topic.kind == "combat" then return L["Combat"] end
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

local function Breakdown(self, key, scope, limit)
    local result = {}
    if limit < 1 then return result end
    local ok, list = pcall(self.GetBreakdown, self, key, scope, limit)
    for _, entry in ipairs(ok and list or {}) do result[#result + 1] = { id = entry.key, name = entry.name, count = entry.count } end
    return result
end

local function Metric(self, metric, scope, periods, withTiers, limit)
    local name, key = metric[1], metric[2]
    local info = self.registry and self.registry[key]
    return {
        label = metric.label or (info and info.label) or name, total = tonumber(self:Get(key, scope)) or 0,
        periods = Periods(self, key, scope, periods),
        tiers = (withTiers and S.TIERED[key]) and Tiers(self, key, scope) or {},
        breakdown = metric.breakdown and Breakdown(self, key, scope, limit) or {},
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

function S:Query(request)
    request = type(request) == "table" and request or {}
    local scope = request.scope
    if scope ~= "account" and type(scope) ~= "string" then scope = "char" end

    local periods = {}
    for _, days in ipairs(type(request.periods) == "table" and request.periods or { 1, 7 }) do
        days = tonumber(days)
        if days and days >= 1 then periods[#periods + 1] = math.floor(days) end
    end
    local limit = math.max(math.min(math.floor(tonumber(request.breakdown) or 0), 100), 0)

    local response = { api = self.API_VERSION, schema = self.API_SCHEMA, ok = false, scope = scope, topics = {}, order = {}, unknown = {},
        labels = { since = L["Counting since"], periods = { [1] = L["today"], [7] = L["7 days"], [30] = L["30 days"] } } }
    if not (self.char and self.account) then return response end

    response.ok = pcall(function()
        response.since = self:GetSince(scope)
        response.sinceText = response.since and self:FormatDate(response.since) or nil

        local wanted = Wanted(request.topics)
        for _, key in ipairs(order) do
            local topic = topics[key]
            if (not wanted or wanted[key]) and (request.kind == nil or topic.kind == request.kind) then
                response.topics[key] = Topic(self, topic, scope, periods, request.tiers ~= false, limit)
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

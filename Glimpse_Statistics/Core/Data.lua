local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Lesen aus Glimpse: Database. Alle Funktionen nehmen einen Zählerschlüssel aus Counters.lua und einen scope:
--   "char" (Standard)  eingeloggter Charakter
--   "account"          alle eigenen Charaktere
--   Zahl               ein Charakter-Index aus S:GetCharacters()
-- Fehlen Database, der Namespace oder der Zähler, ist das Ergebnis 0, nil oder eine leere Liste.
-- Herkünfte: own und imported zählen immer, baseline (Blizzard-Startwert) nur in Get.
-- Zähler mit unit "distinct" liefern die Zahl verschiedener IDs; Zeiträume und Verlauf gibt es für sie nicht.

local WITH_BASELINE = { "own", "imported", "baseline" }

--- GlimpseDB oder nil
function S:Database()
    local DB = GlimpseDB
    if type(DB) == "table" and type(DB.Get) == "function" then return DB end
end

--- Leser eines Namespace, nil ohne Database oder ohne den Namespace (Addon nicht installiert, noch nichts erfasst)
function S:Reader(name)
    local DB = self:Database()
    if not DB then return nil end
    local ok, reader = pcall(DB.Get, DB, name)
    if ok and type(reader) == "table" then return reader end
end

local function Chars(scope)
    if scope == nil or scope == "char" then return "char" end
    if scope == "account" or type(scope) == "number" then return scope end
end

-- Zähler, Leser und Abfrage für Database; nil, wenn etwas fehlt. extra ergänzt die Abfrage (sources, from).
local function Open(key, scope, extra)
    local counter, chars = S.counterByKey[key], Chars(scope)
    if not (counter and chars) then return nil end
    local reader = S:Reader(counter.ns)
    if not reader then return nil end

    local query = { chars = chars }
    for field, value in pairs(extra or {}) do query[field] = value end
    return counter, reader, query
end

-- IDs mit Wert, ohne names nur 0
local function Ids(counter, reader, query)
    if not counter.names then return { [counter.id or 0] = reader:GetCount(counter.kind, counter.id or 0, query) } end
    return reader:GetCounts(counter.kind, query)
end

-- Anzahl der IDs mit Wert, beim Account ohne Doppelte
local function Distinct(counter, reader, query)
    local n = 0
    for _, count in pairs(reader:GetCounts(counter.kind, query)) do
        if count > 0 then n = n + 1 end
    end
    return n
end

--- Gesamtsumme, mit Blizzard-Startwert, wo es einen gibt.
function S:Get(key, scope)
    local counter, reader, query = Open(key, scope)
    if not counter then return 0 end
    if counter.unit == "distinct" then return Distinct(counter, reader, query) end
    if counter.baseline then query.sources = WITH_BASELINE end
    return reader:GetCount(counter.kind, counter.id, query)
end

--- Nur der Blizzard-Startwert, 0 ohne.
function S:GetBaseline(key, scope)
    local counter, reader, query = Open(key, scope, { sources = "baseline" })
    if not (counter and counter.baseline) then return 0 end
    return reader:GetCount(counter.kind, counter.id, query)
end

--- Ohne Startwert, für Quoten (Blizzard zählt keine Würfe).
function S:GetCounted(key, scope)
    local counter, reader, query = Open(key, scope)
    if not counter then return 0 end
    if counter.unit == "distinct" then return Distinct(counter, reader, query) end
    return reader:GetCount(counter.kind, counter.id, query)
end

--- Summe der letzten days Tage, 1 = heute (ab Mitternacht Ortszeit). Aus den Stunden von Database.
function S:GetSum(key, scope, days)
    local DB = self:Database()
    local counter, reader, query = Open(key, scope)
    if not (counter and DB) or counter.unit == "distinct" then return 0 end
    query.from = DB:LocalDayStart(1 - math.max(math.floor(days or 1), 1))
    return reader:GetCount(counter.kind, counter.id, query)
end

local function Sorted(list, limit)
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.key < b.key
    end)
    while limit and #list > limit do list[#list] = nil end
    return list
end

--- Liste { key = ID, name, count, first, last }, größte zuerst. Leer, wenn der Zähler keine IDs hat.
function S:GetBreakdown(key, scope, limit)
    local counter, reader, query = Open(key, scope)
    local list = {}
    if not (counter and counter.names) then return list end

    for id, count in pairs(reader:GetCounts(counter.kind, query)) do
        if count > 0 then list[#list + 1] = { key = id, count = count } end
    end
    Sorted(list, limit)
    -- Namen und Zeiten nur für das, was gezeigt wird
    for _, entry in ipairs(list) do
        entry.name = self:NameOf(counter.names, entry.key)
        entry.first, entry.last = reader:GetSeen(counter.kind, entry.key, query)
    end
    return list
end

--- Liste { key = Zone, name, count }, größte zuerst. Leer ohne Zonen.
function S:GetZoneBreakdown(key, scope, limit)
    local counter, reader, query = Open(key, scope)
    local list = {}
    if not (counter and counter.zones) then return list end

    local sums = {}
    for id in pairs(Ids(counter, reader, query)) do
        for zone, count in pairs(reader:GetZones(counter.kind, id, query)) do sums[zone] = (sums[zone] or 0) + count end
    end
    for zone, count in pairs(sums) do
        if count > 0 then list[#list + 1] = { key = zone, count = count } end
    end
    Sorted(list, limit)
    for _, entry in ipairs(list) do entry.name = self:ZoneName(entry.key) end
    return list
end

--- Erste und letzte Erfassung eines Zählers, nil ohne Daten.
function S:GetFirst(key, scope)
    local counter, reader, query = Open(key, scope)
    if not counter then return nil end
    local first, last
    for id in pairs(Ids(counter, reader, query)) do
        local from, to = reader:GetSeen(counter.kind, id, query)
        if from and (not first or from < first) then first = from end
        if to and (not last or to > last) then last = to end
    end
    return first, last
end

-- Seit-Zeitpunkt je scope. Neue Zählungen machen ihn nie früher, nur Importe und Zurücksetzen (S:ForgetSince).
local sinceCache = {}

--- Früheste Erfassung über alle Zähler, nil ohne Daten.
function S:GetSince(scope)
    scope = scope or "char"
    if sinceCache[scope] then return sinceCache[scope] end
    local since
    for _, counter in ipairs(self.COUNTERS) do
        local first = self:GetFirst(counter.key, scope)
        if first and (not since or first < since) then since = first end
    end
    sinceCache[scope] = since
    return since
end

function S:ForgetSince()
    wipe(sinceCache)
end

--- Tagesverlauf der letzten days Tage (Standard 30): Liste { day = JJJJMMTT, time, n } aufsteigend, Ortszeit.
-- Tage ohne Wert fehlen.
function S:GetSeries(key, scope, days)
    local DB = self:Database()
    local counter, reader, query = Open(key, scope)
    local list = {}
    if not (counter and DB) or counter.unit == "distinct" then return list end

    query.from = DB:LocalDayStart(1 - (days or 30))
    local byDay = {}
    for hour, n in pairs(reader:GetSeries(counter.kind, counter.id, query)) do
        local stamp = DB:HourStart(hour)
        local day = tonumber(date("%Y%m%d", stamp))
        local entry = byDay[day]
        if not entry then
            entry = { day = day, time = stamp, n = 0 }
            byDay[day] = entry
            list[#list + 1] = entry
        end
        entry.n = entry.n + n
        entry.time = math.min(entry.time, stamp)
    end
    table.sort(list, function(a, b) return a.day < b.day end)
    return list
end

--- Werte je Berufsstufe: Liste { max, name, count } aufsteigend, leer ohne Stufen. Werte aus der Zeit vor den
-- Stufen (Übernahme) fehlen hier, sie stehen nur in der Gesamtsumme.
function S:GetTierCounts(key, scope)
    local counter, reader, query = Open(key, scope)
    local list = {}
    if not (counter and counter.tier) then return list end

    for maximum, count in pairs(reader:GetCounts(counter.tier, query)) do
        if count > 0 then
            list[#list + 1] = { max = maximum, name = self:TierName(counter.profession, maximum), count = count }
        end
    end
    table.sort(list, function(a, b) return a.max < b.max end)
    return list
end

--- Charakter-Indizes aus Database, aktueller zuerst.
function S:GetCharacters()
    local DB = self:Database()
    if not DB then return {} end
    local ok, list = pcall(DB.GetCharacters, DB)
    return ok and list or {}
end

--- "Name - Realm" eines Charakter-Index
function S:CharacterName(index)
    local DB = self:Database()
    local name, realm
    if DB then name, realm = DB:GetCharacterInfo(index) end
    if not name then return "#" .. tostring(index) end
    return realm and (name .. " - " .. realm) or name
end

--- scope für Data.lua aus "char", "account", Index oder "Name - Realm"; nil bei unbekanntem Charakter.
function S:ResolveScope(scope)
    if scope == nil or scope == "char" or scope == "account" or type(scope) == "number" then return scope or "char" end
    if type(scope) ~= "string" then return nil end
    for _, index in ipairs(self:GetCharacters()) do
        if self:CharacterName(index) == scope then return index end
    end
end

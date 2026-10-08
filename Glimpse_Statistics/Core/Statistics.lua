local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Zähler pro Charakter und Account mit Zeitstempeln. Sammler: Core/Collect/Kills.lua, Fishing.lua, Gathering.lua.
-- Andere Addons melden eigene Zähler an.
--
-- Öffentliche API über Glimpse.Statistics (API_VERSION 4; Daten-API in Core/Api.lua). Aufrufer prüfen auf nil.
--   :RegisterStat(key, label, options)  label schon übersetzt. options: group = Überschrift,
--                                       breakdown = true (nach subKey), name = function(subKey) -> Name
--   :Add(key, amount, subKey, subName)  amount Standard 1, auch negativ; schreibt Charakter und Account.
--                                       subKey (Zahl oder Text) + subName für die Aufschlüsselung, z. B. Kreatur
--   :Get(key, scope)                    scope = "char" (Standard), "account" oder "Name - Realm"
--   :GetBreakdown(key, scope, limit)    Liste { key, name, count }, absteigend
--   :GetSub(key, subKey, scope)         einzelner Eintrag der Aufschlüsselung, 0 wenn nicht vorhanden
--   :GetCharacters()                    "Name - Realm" aller Charaktere mit Daten, aktueller zuerst
--   :GetRegistered()                    Liste { key, label, group, breakdown } in Anmeldereihenfolge
--   :GetSince(scope)                    Beginn der Zählung; :GetFirst(key, scope) erste und letzte Zählung
--   :OverviewLines(detail, charOnly, keyPrefix)  Zeilen der Übersicht (heute, 7 Tage). keyPrefix filtert, z. B.
--                                       "fishing."; charOnly stellt "Erfasst seit ..." voran
--   :GetTierCounts(key, scope)          Liste { max, name, count } je Berufsstufe, aufsteigend. Werte ohne Stufe
--                                       zählen zur niedrigsten; leer ohne Stufenwerte
--   :GetSeries(key, scope, von, bis)    Tagesverlauf: Liste { day = JJJJMMTT, time, n }
-- Nachricht GLIMPSE_STATISTICS_UPDATED (key, topic, metric) bei jeder Änderung, siehe Core/Api.lua.
local S = Glimpse:NewModule("Statistics", nil, "AceEvent-3.0")
S.L = L
S.API_VERSION = 4
S.MESSAGE_UPDATED = "GLIMPSE_STATISTICS_UPDATED"

-- Zugriff ohne GetModule
Glimpse.Statistics = S

-- Gesamtzähler werden nie beschnitten, nur Aufschlüsselungen (MAX_BREAKDOWN, kleinste Einträge zuerst).
local COUNT_MAX = 1e12
S.COUNT_MAX = COUNT_MAX -- auch Transfer.lua, Baseline.lua
S.MAX_BREAKDOWN = 1000
S.clock = time -- in Tests ersetzbar

-- Gleiches Format für char und global: totals[key] = Zahl, by[key][subKey] = { n, name }, since,
-- first[key]/last[key], days[key][JJJJMMTT] = Tagessumme (Ortszeit), baseline (Core/Baseline/Baseline.lua), baselineDone.
-- Account zählt separat, damit gelöschte oder umbenannte Charaktere erhalten bleiben.
local defaults = {
    char = {
        totals = {}, by = {}, first = {}, last = {}, days = {},
        baseline = {}, baselineDone = false,
        windowStatus = {}, windowOpen = false, -- Fensterposition/-größe je Charakter
    },
    global = {
        totals = {}, by = {}, first = {}, last = {}, days = {},
        baseline = {},
        imports = {}, -- IDs importierter Exporte
        collect = true,
        tooltipKills = true, tooltipDeaths = true, tooltipAccount = false,
        tooltipKillsMode = "name", tooltipLineFrame = "blizzard", tooltipSide = "right",
        windowScope = "all", windowFrame = false, windowFontSize = 12,
    },
}

function S:OnInitialize()
    self.store = LibStub("AceDB-3.0"):New("GlimpseStatisticsDB", defaults, true)
    self.char = self.store.char
    self.account = self.store.global
    self.registry, self.order = {}, {}

    -- Icon-Nachweis für den Credits-Tab, gleich wie in der README
    local credits = { images = { "Analytics - Pixel perfect (Flaticon) |cff66ccff(https://www.flaticon.com/free-icon/analytics_731794)|r" } }
    Glimpse:RegisterAddonOptions(ADDON_NAME, self:BuildOptions(), true, credits)
end

local function ScopeData(self, scope)
    if scope == nil or scope == "char" then return self.char end
    if scope == "account" then return self.account end

    local chars = self.store and self.store.sv and self.store.sv.char
    local data = chars and chars[scope]
    if type(data) == "table" and type(data.totals) == "table" then return data end
end

--- pcall-Wrapper für Sammler; Fehler landen in errorCount/lastError für /gli stats. true bei Erfolg.
function S.Protected(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        S.errorCount = (S.errorCount or 0) + 1
        S.lastError = label .. ": " .. tostring(err)
    end
    return ok
end

function S:DebugLog(text, ...)
    if not self:IsDebugging() then return end
    self:DebugLogAlways(text, ...)
end

--- Vor teuren Debug-Zeilen prüfen.
function S:IsDebugging()
    return Glimpse.IsDebug ~= nil and Glimpse:IsDebug() == true
end

--- Wie DebugLog, auch ohne Debug-Modus (für /gli stats trace)
function S:DebugLogAlways(text, ...)
    if select("#", ...) > 0 then text = format(text, ...) end
    Glimpse:Print("|cff66ccff[Statistics]|r |cff999999" .. text:gsub("|", "||") .. "|r")
end

--- Rohdaten für die Debug-Ausgabe, nur lesen.
function S:GetRawData(scope)
    return ScopeData(self, scope)
end

-- Kürzt auf 90 % von limit, kleinste Einträge zuerst
local function PruneBreakdown(list, limit)
    local keys = {}
    for subKey in pairs(list) do keys[#keys + 1] = subKey end
    if #keys <= limit then return end

    table.sort(keys, function(a, b)
        if list[a].n ~= list[b].n then return list[a].n > list[b].n end
        return tostring(a) < tostring(b)
    end)
    for index = math.floor(limit * 0.9) + 1, #keys do list[keys[index]] = nil end
end

S.PruneBreakdown = PruneBreakdown

local sinceCheck = setmetatable({}, { __mode = "k" })

-- ca. zehn Jahre Tageswerte je Zähler
local MAX_DAYS = 3660
S.MAX_DAYS = MAX_DAYS

function S.PruneDays(days, limit)
    local keys = {}
    for day in pairs(days) do keys[#keys + 1] = day end
    if #keys <= limit then return end
    table.sort(keys)
    for index = 1, #keys - limit do days[keys[index]] = nil end
end

-- JJJJMMTT (Ortszeit), gecacht: ein Kill schreibt mehrere Zähler im selben Moment.
local lastStamp, lastDay
local function DayKey(timestamp)
    if timestamp ~= lastStamp then
        lastStamp, lastDay = timestamp, tonumber(date("%Y%m%d", timestamp))
    end
    return lastDay
end
S.DayKey = DayKey

local function Stamp(data, key, amount, now)
    data.first, data.last, data.days = data.first or {}, data.last or {}, data.days or {}
    data.since = data.since or now
    data.first[key] = data.first[key] or now
    data.last[key] = now

    local days = data.days[key]
    if not days then
        if amount < 0 then return end
        days = {}
        data.days[key] = days
    end

    local day = DayKey(now)
    if days[day] == nil then
        if amount < 0 then return end
        local count = 0
        for _ in pairs(days) do count = count + 1 end
        if count >= MAX_DAYS then S.PruneDays(days, MAX_DAYS - 1) end
    end
    local value = math.min(math.max((days[day] or 0) + amount, 0), COUNT_MAX)
    days[day] = value > 0 and value or nil
end

local function Bump(data, key, amount, subKey, subName, limit, now)
    data.totals[key] = math.min(math.max((data.totals[key] or 0) + amount, 0), COUNT_MAX)
    if data.totals[key] == 0 then data.totals[key] = nil end
    Stamp(data, key, amount, now)

    if subKey == nil then return end
    data.by[key] = data.by[key] or {}
    local list = data.by[key]

    local entry = list[subKey]
    if not entry then
        if amount < 0 then return end
        entry = { n = 0 }
        list[subKey] = entry
    end
    entry.n = math.min(math.max(entry.n + amount, 0), COUNT_MAX)
    entry.first = entry.first or now
    entry.last = now
    if type(subName) == "string" and subName ~= "" and not entry.name then entry.name = subName:sub(1, 100) end
    if entry.n == 0 then list[subKey] = nil end

    -- Prune durchläuft alle Einträge, daher nur alle 50 Änderungen
    sinceCheck[list] = (sinceCheck[list] or 0) + 1
    if sinceCheck[list] >= 50 then
        sinceCheck[list] = 0
        PruneBreakdown(list, limit)
    end
end

--- Negative amount nimmt zurück, nie unter 0.
function S:Add(key, amount, subKey, subName)
    if type(key) ~= "string" or key == "" then return end
    amount = tonumber(amount) or 1
    if amount ~= amount or amount == 0 then return end
    if subKey ~= nil and type(subKey) ~= "number" and type(subKey) ~= "string" then subKey = nil end

    local now = self.clock()
    Bump(self.char, key, amount, subKey, subName, self.MAX_BREAKDOWN, now)
    Bump(self.account, key, amount, subKey, subName, self.MAX_BREAKDOWN, now)
    if self:IsDebugging() then
        local entry = subKey ~= nil and self.char.by[key] and self.char.by[key][subKey]
        self:DebugLog("DB write: %s %+d%s -> character %s, account %s", key, amount,
            subKey ~= nil and (" [" .. tostring(subKey) .. (subName and (" " .. tostring(subName)) or "") ..
                (entry and (" = " .. tostring(entry.n)) or "") .. "]") or "",
            tostring(self.char.totals[key]), tostring(self.account.totals[key]))
    end
    local profession, metric
    if self.TopicOfKey then profession, metric = self:TopicOfKey(key) end
    self:SendMessage(self.MESSAGE_UPDATED, key, profession, metric)
end

--- scope "char" oder "account".
function S:Reset(scope)
    local data = (scope == "char" or scope == "account") and ScopeData(self, scope)
    if not data then return false end
    wipe(data.totals)
    wipe(data.by)
    for _, field in ipairs({ "first", "last", "days" }) do
        if data[field] then wipe(data[field]) end
    end
    data.since = nil
    -- Baseline wird beim nächsten Login neu gelesen
    if data.baseline then wipe(data.baseline) end
    if scope == "char" then data.baselineDone = false end
    self:SendMessage(self.MESSAGE_UPDATED)
    return true
end

function S:Get(key, scope)
    local data = ScopeData(self, scope)
    return data and data.totals[key] or 0
end

--- Im Zähler enthaltener Blizzard-Startwert (Core/Baseline/Baseline.lua), sonst 0.
function S:GetBaseline(key, scope)
    local data = ScopeData(self, scope)
    return data and data.baseline and data.baseline[key] or 0
end

--- Zähler ohne Startwert, für Quoten gegen Zähler ohne Baseline (Blizzard zählt keine Würfe).
function S:GetCounted(key, scope)
    return math.max(self:Get(key, scope) - self:GetBaseline(key, scope), 0)
end

--- Gibt n, first, last eines Eintrags zurück, 0 wenn nicht vorhanden.
function S:GetSub(key, subKey, scope)
    local data = ScopeData(self, scope)
    local entry = data and data.by and data.by[key] and data.by[key][subKey]
    if not entry then return 0 end
    return entry.n, entry.first, entry.last
end

--- nil, solange noch nichts gezählt wurde.
function S:GetSince(scope)
    local data = ScopeData(self, scope)
    return data and data.since or nil
end

function S:GetFirst(key, scope)
    local data = ScopeData(self, scope)
    if not data or not data.first then return nil end
    return data.first[key], data.last and data.last[key]
end

--- Liste { day, time (Mittag), n } aufsteigend; fromDay/toDay optional. Tage ohne Zählung fehlen.
function S:GetSeries(key, scope, fromDay, toDay)
    local data = ScopeData(self, scope)
    local list = {}
    local days = data and data.days and data.days[key]
    if not days then return list end

    for day, n in pairs(days) do
        if (not fromDay or day >= fromDay) and (not toDay or day <= toDay) then
            local year, month, dom = math.floor(day / 10000), math.floor(day / 100) % 100, day % 100
            local ok, stamp = pcall(time, { year = year, month = month, day = dom, hour = 12 })
            list[#list + 1] = { day = day, time = ok and stamp or nil, n = n }
        end
    end
    table.sort(list, function(a, b) return a.day < b.day end)
    return list
end

--- days = 1: nur heute.
function S:GetSum(key, scope, days)
    local data = ScopeData(self, scope)
    local list = data and data.days and data.days[key]
    if not list then return 0 end

    local from = DayKey(self.clock() - ((days or 1) - 1) * 86400)
    local sum = 0
    for day, n in pairs(list) do
        if day >= from then sum = sum + n end
    end
    return sum
end

--- Liste { key, name, count, first, last, storedName }, absteigend.
-- Name: gespeichert, sonst options.name aus RegisterStat, sonst der Schlüssel.
function S:GetBreakdown(key, scope, limit)
    local data = ScopeData(self, scope)
    local list = {}
    if not data then return list end

    local info = self.registry[key]
    for subKey, entry in pairs(data.by[key] or {}) do
        local name = entry.name
        if not name and info and info.name then
            local ok, resolved = pcall(info.name, subKey)
            if ok and type(resolved) == "string" then name = resolved end
        end
        list[#list + 1] = { key = subKey, name = name or tostring(subKey), count = entry.n, first = entry.first, last = entry.last,
            storedName = entry.name, time = entry.last }
    end

    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return tostring(a.key) < tostring(b.key)
    end)
    while limit and #list > limit do list[#list] = nil end
    return list
end

function S:GetCharacters()
    local result = {}
    local current = self.store.keys and self.store.keys.char
    for name, data in pairs(self.store.sv and self.store.sv.char or {}) do
        if type(data) == "table" and name ~= current then result[#result + 1] = name end
    end
    table.sort(result)
    if current then tinsert(result, 1, current) end
    return result
end

--- Angemeldete Zähler in Anmeldereihenfolge, danach nicht angemeldete alphabetisch.
function S:GetCounterKeys(scope)
    local data = ScopeData(self, scope)
    local keys, seen = {}, {}
    if not data then return keys end

    for _, key in ipairs(self.order) do
        if (data.totals[key] or 0) > 0 then
            keys[#keys + 1] = key
            seen[key] = true
        end
    end
    local rest = {}
    for key, value in pairs(data.totals) do
        if value > 0 and not seen[key] then rest[#rest + 1] = key end
    end
    table.sort(rest)
    for _, key in ipairs(rest) do keys[#keys + 1] = key end
    return keys
end

--- Erneutes Anmelden aktualisiert nur.
function S:RegisterStat(key, label, options)
    if type(key) ~= "string" or type(label) ~= "string" then return end
    options = options or {}

    local info = self.registry[key]
    if not info then
        info = { key = key }
        self.registry[key] = info
        self.order[#self.order + 1] = key
    end
    info.label = label
    info.group = options.group
    info.breakdown = options.breakdown == true
    info.name = options.name
end

function S:GetRegistered()
    local result = {}
    for _, key in ipairs(self.order) do
        local info = self.registry[key]
        result[#result + 1] = { key = key, label = info.label, group = info.group, breakdown = info.breakdown }
    end
    return result
end

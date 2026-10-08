local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Export/Import der Zähler (Sicherung, Rechnerwechsel, Zusammenführen).
--
-- Exporttext: GSTAT<Format>:<Methode>:<Daten>
--   Format   FORMAT
--   Methode  "D" = LibDeflate + druckbar kodiert, "R" = unkomprimiert
--   Daten    { format, created, id, account = Abschnitt, chars = { ["Name - Realm"] = Abschnitt } } in eigener
--            Textform (Serialize.lua), wird nur geparst, nie als Code ausgeführt.
-- Abschnitt = { totals, by, since, first, last, days } wie in der DB; Zeitpunkte und days optional.
--
-- Import validiert komplett, bevor gemergt (addieren) oder ersetzt (Account und alle Charaktere) wird.

local FORMAT = 1
local MAGIC = "GSTAT"

-- Limits gegen kaputte oder manipulierte Texte
local MAX_TEXT = 20000000   -- Zeichen im Eingabetext
local MAX_NAME = 100        -- Schlüssel/Namen werden darauf gekürzt
local MAX_CHARS = 200       -- Charaktere je Export
local MAX_IMPORTS = 50      -- gemerkte Export-IDs
local COUNT_MAX = S.COUNT_MAX

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------

local function Compressor()
    return LibStub("LibDeflate", true)
end

local function NewExportID()
    return format("%x-%x", time(), math.random(0, 0xFFFFFF))
end

local function Count(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

-- Verhindert doppeltes Mergen desselben Exports
local function RememberImport(account, id)
    if type(id) ~= "string" then return end

    account.imports = account.imports or {}
    account.imports[id] = time()

    local ids = {}
    for key in pairs(account.imports) do ids[#ids + 1] = key end
    if #ids <= MAX_IMPORTS then return end

    table.sort(ids, function(a, b)
        local ta, tb = account.imports[a], account.imports[b]
        if ta ~= tb then return ta > tb end
        return a < b
    end)
    for index = MAX_IMPORTS + 1, #ids do account.imports[ids[index]] = nil end
end

-- Name -> { totals, by }
local function AllChars(self)
    local chars = {}
    for name, data in pairs(self.store.sv and self.store.sv.char or {}) do
        if type(data) == "table" and type(data.totals) == "table" then chars[name] = data end
    end
    -- aktueller Charakter fehlt evtl. noch in der DB-Liste
    local current = self.store.keys and self.store.keys.char
    if current and not chars[current] then chars[current] = self.char end
    return chars
end

-- Nur Zähler, keine Einstellungen
local function Section(data)
    return { totals = data.totals, by = data.by, since = data.since, first = data.first, last = data.last, days = data.days }
end

--- Gibt Text und { chars, counters, length } zurück.
function S:ExportData()
    local chars = {}
    for name, data in pairs(AllChars(self)) do chars[name] = Section(data) end

    local payload = {
        format = FORMAT,
        created = time(),
        id = NewExportID(),
        account = Section(self.account),
        chars = chars,
    }
    local text = self.Serialize(payload)

    local method, body = "R", text
    local lib = Compressor()
    if lib then
        local packed = lib:CompressDeflate(text, { level = 9 })
        if packed then method, body = "D", lib:EncodeForPrint(packed) end
    end

    -- Eigenen Export nicht zurückmergen (verdoppelt alles); Wiederherstellen geht über "replace"
    RememberImport(self.account, payload.id)

    local result = MAGIC .. FORMAT .. ":" .. method .. ":" .. body
    return result, { chars = Count(chars), counters = Count(self.account.totals), length = #result }
end

-- ---------------------------------------------------------------------------
-- Import
-- ---------------------------------------------------------------------------

-- Fehlerschlüssel (übersetzt in der UI):
--   empty        leere Eingabe
--   tooLarge     länger als MAX_TEXT
--   notExport    kein Statistics-Export
--   formatNewer  Format einer neueren Addon-Version
--   unsupported  Kompression nicht verfügbar
--   damaged      beschädigt oder unvollständig
--   duplicate    schon gemergt oder eigener Export

--- Gibt Nutzdaten zurück oder nil, Fehlerschlüssel.
function S:DecodeExport(text)
    if type(text) ~= "string" then return nil, "empty" end
    if #text > MAX_TEXT then return nil, "tooLarge" end

    local version, method, body = text:match("^%s*" .. MAGIC .. "(%d+):(%a):(.*)$")
    if not version then
        if text:match("^%s*$") then return nil, "empty" end
        return nil, "notExport"
    end
    if tonumber(version) > FORMAT then return nil, "formatNewer" end

    local serialized
    if method == "D" then
        local lib = Compressor()
        if not lib then return nil, "unsupported" end

        -- Copy & Paste fügt teils Zeilenumbrüche ein
        body = body:gsub("%s+", "")
        local packed = lib:DecodeForPrint(body)
        serialized = packed and lib:DecompressDeflate(packed)
        if not serialized then return nil, "damaged" end
    elseif method == "R" then
        serialized = body:gsub("%s+$", "")
    else
        return nil, "notExport"
    end

    local payload = self.Deserialize(serialized)
    if not payload or type(payload.account) ~= "table" then return nil, "damaged" end
    return payload
end

local function CleanString(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value:sub(1, MAX_NAME)
end

local function CleanCount(value)
    if type(value) ~= "number" or value ~= value then return nil end
    value = math.floor(value)
    if value < 1 then return nil end
    return math.min(value, COUNT_MAX)
end

-- Unix-Zeit zwischen 2000 und 2100
local function CleanTime(value)
    if type(value) ~= "number" or value ~= value then return nil end
    value = math.floor(value)
    if value < 946684800 or value > 4102444800 then return nil end
    return value
end

-- JJJJMMTT
local function CleanDay(value)
    if type(value) ~= "number" or value ~= value or value ~= math.floor(value) then return nil end
    local year, month, day = math.floor(value / 10000), math.floor(value / 100) % 100, value % 100
    if year < 2000 or year > 2100 or month < 1 or month > 12 or day < 1 or day > 31 then return nil end
    return value
end

-- Gibt bereinigte Kopie und Zahl verworfener Einträge zurück
local function CleanSection(self, section)
    local clean, removed = { totals = {}, by = {}, first = {}, last = {}, days = {} }, 0
    if type(section) ~= "table" then return clean, 1 end

    clean.since = CleanTime(section.since)
    for key, value in pairs(type(section.first) == "table" and section.first or {}) do
        local name, stamp = CleanString(key), CleanTime(value)
        if name and stamp then clean.first[name] = stamp else removed = removed + 1 end
    end
    for key, value in pairs(type(section.last) == "table" and section.last or {}) do
        local name, stamp = CleanString(key), CleanTime(value)
        if name and stamp then clean.last[name] = stamp else removed = removed + 1 end
    end
    for key, list in pairs(type(section.days) == "table" and section.days or {}) do
        local name = CleanString(key)
        if name and type(list) == "table" then
            local target, size = {}, 0
            for day, value in pairs(list) do
                local cleanDay, count = CleanDay(day), CleanCount(value)
                if cleanDay and count and size < self.MAX_DAYS then
                    target[cleanDay], size = count, size + 1
                else
                    removed = removed + 1
                end
            end
            if next(target) then clean.days[name] = target end
        else
            removed = removed + 1
        end
    end

    for key, value in pairs(type(section.totals) == "table" and section.totals or {}) do
        local name, count = CleanString(key), CleanCount(value)
        if name and count then clean.totals[name] = count else removed = removed + 1 end
    end

    for key, list in pairs(type(section.by) == "table" and section.by or {}) do
        local name = CleanString(key)
        if name and type(list) == "table" then
            local target = {}
            for subKey, entry in pairs(list) do
                local keyType = type(subKey)
                local count = type(entry) == "table" and CleanCount(entry.n)
                if (keyType == "number" and subKey == subKey) or (keyType == "string" and subKey ~= "") then
                    if keyType == "string" then subKey = subKey:sub(1, MAX_NAME) end
                    if count then
                        target[subKey] = { n = count, name = CleanString(entry.name), first = CleanTime(entry.first), last = CleanTime(entry.last) }
                    else
                        removed = removed + 1
                    end
                else
                    removed = removed + 1
                end
            end
            if next(target) then
                self.PruneBreakdown(target, self.MAX_BREAKDOWN)
                clean.by[name] = target
            end
        else
            removed = removed + 1
        end
    end
    return clean, removed
end

local function MergeSection(self, target, source)
    target.first, target.last, target.days = target.first or {}, target.last or {}, target.days or {}
    if source.since and (not target.since or source.since < target.since) then target.since = source.since end
    for key, stamp in pairs(source.first) do
        if not target.first[key] or stamp < target.first[key] then target.first[key] = stamp end
    end
    for key, stamp in pairs(source.last) do
        if not target.last[key] or stamp > target.last[key] then target.last[key] = stamp end
    end
    for key, days in pairs(source.days) do
        target.days[key] = target.days[key] or {}
        for day, n in pairs(days) do
            target.days[key][day] = math.min((target.days[key][day] or 0) + n, COUNT_MAX)
        end
        self.PruneDays(target.days[key], self.MAX_DAYS)
    end

    for key, count in pairs(source.totals) do
        target.totals[key] = math.min((target.totals[key] or 0) + count, COUNT_MAX)
    end
    for key, list in pairs(source.by) do
        target.by[key] = target.by[key] or {}
        local into = target.by[key]
        for subKey, entry in pairs(list) do
            local sum = into[subKey]
            if sum then
                sum.n = math.min(sum.n + entry.n, COUNT_MAX)
                sum.name = sum.name or entry.name
                if entry.first and (not sum.first or entry.first < sum.first) then sum.first = entry.first end
                if entry.last and (not sum.last or entry.last > sum.last) then sum.last = entry.last end
            else
                into[subKey] = { n = entry.n, name = entry.name, first = entry.first, last = entry.last }
            end
        end
        self.PruneBreakdown(into, self.MAX_BREAKDOWN)
    end
end

-- In place, da andere Stellen die Tabelle referenzieren
local function ReplaceSection(target, source)
    wipe(target.totals)
    wipe(target.by)
    target.first, target.last, target.days = target.first or {}, target.last or {}, target.days or {}
    wipe(target.first); wipe(target.last); wipe(target.days)
    target.since = source.since

    for key, count in pairs(source.totals) do target.totals[key] = count end
    for key, list in pairs(source.by) do target.by[key] = list end
    for key, stamp in pairs(source.first or {}) do target.first[key] = stamp end
    for key, stamp in pairs(source.last or {}) do target.last[key] = stamp end
    for key, days in pairs(source.days or {}) do target.days[key] = days end
end

--- mode = "merge" (Standard) oder "replace". Gibt true, { chars, counters, removed, mode } zurück,
-- sonst false, Fehlerschlüssel.
function S:ImportData(text, mode)
    mode = mode == "replace" and "replace" or "merge"

    local payload, err = self:DecodeExport(text)
    if not payload then return false, err end

    if mode == "merge" and type(payload.id) == "string" and self.account.imports and self.account.imports[payload.id] then
        return false, "duplicate"
    end

    -- erst alles prüfen, dann schreiben
    local removed = 0
    local account, count = CleanSection(self, payload.account)
    removed = removed + count

    local chars, charCount = {}, 0
    for name, section in pairs(type(payload.chars) == "table" and payload.chars or {}) do
        local clean = CleanString(name)
        if clean and charCount < MAX_CHARS then
            chars[clean], count = CleanSection(self, section)
            removed = removed + count
            charCount = charCount + 1
        else
            removed = removed + 1
        end
    end

    local existing = AllChars(self)
    local function Target(name)
        if existing[name] then return existing[name] end
        local data = { totals = {}, by = {} }
        self.store.sv.char = self.store.sv.char or {}
        self.store.sv.char[name] = data
        existing[name] = data
        return data
    end

    if mode == "replace" then
        ReplaceSection(self.account, account)
        for _, data in pairs(existing) do ReplaceSection(data, { totals = {}, by = {} }) end
        for name, section in pairs(chars) do ReplaceSection(Target(name), section) end
    else
        MergeSection(self, self.account, account)
        for name, section in pairs(chars) do MergeSection(self, Target(name), section) end
    end

    RememberImport(self.account, payload.id)
    self:SendMessage(self.MESSAGE_UPDATED)

    return true, { chars = charCount, counters = Count(account.totals), removed = removed, mode = mode }
end

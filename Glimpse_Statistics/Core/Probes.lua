local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")

-- Prüfungen für Tester über den Core (/gli probe stats ...), Ausgabe englisch wie die übrigen Debug-Zeilen:
--   status           Database, Übernahme der alten Daten, Namespaces und Summen je Zähler
--   raw [Zähler]     Werte je Herkunft, größte IDs und Zeiträume, wie sie in Database stehen

local function Number(value)
    return tostring(value or 0)
end

--- Zeilen für /gli probe stats status und /gli stats status.
function S:StatusLines()
    local lines = {}
    local DB = self:Database()
    if not DB then
        lines[1] = "Glimpse: Database: missing, nothing to show"
        return lines
    end
    lines[#lines + 1] = format("Glimpse: Database: API %s", tostring(DB.API_VERSION))

    local seen = {}
    for _, counter in ipairs(self.COUNTERS) do
        if not seen[counter.ns] then
            seen[counter.ns] = true
            lines[#lines + 1] = format("namespace %s: %s", counter.ns,
                self:Reader(counter.ns) and "readable" or "missing (addon not installed or nothing recorded yet)")
        end
        lines[#lines + 1] = format("  %s = %s:%s  char %s (baseline %s), account %s", counter.key, counter.ns, counter.kind,
            Number(self:Get(counter.key, "char")), Number(self:GetBaseline(counter.key, "char")),
            Number(self:Get(counter.key, "account")))
    end
    return lines
end

local SOURCES = { "own", "imported", "baseline" }

local function RawLines(counter)
    local lines = {}
    local reader = S:Reader(counter.ns)
    if not reader then return { counter.key .. ": namespace " .. counter.ns .. " missing" } end

    for _, scope in ipairs({ "char", "account" }) do
        local parts = {}
        for _, source in ipairs(SOURCES) do
            parts[#parts + 1] = source .. "=" .. Number(reader:GetCount(counter.kind, counter.id, { chars = scope, sources = source }))
        end
        lines[#lines + 1] = format("%s (%s:%s) %s: %s", counter.key, counter.ns, counter.kind, scope, table.concat(parts, " "))
    end

    local entries = S:GetBreakdown(counter.key, "char", 5)
    for _, entry in ipairs(entries) do
        lines[#lines + 1] = format("  id %s n=%d first=%s last=%s %s", tostring(entry.key), entry.count, tostring(entry.first),
            tostring(entry.last), entry.name)
    end
    if counter.tier then
        local parts = {}
        for _, tier in ipairs(S:GetTierCounts(counter.key, "char")) do parts[#parts + 1] = tier.max .. "=" .. tier.count end
        lines[#lines + 1] = format("  %s: %s", counter.tier, #parts > 0 and table.concat(parts, " ") or "-")
    end
    lines[#lines + 1] = format("  today=%d week=%d month=%d zones=%d", S:GetSum(counter.key, "char", 1),
        S:GetSum(counter.key, "char", 7), S:GetSum(counter.key, "char", 30), #S:GetZoneBreakdown(counter.key, "char"))
    return lines
end

--- Zeilen für /gli probe stats raw [Zähler]; ohne Zähler alle.
function S:RawLines(key)
    local lines = {}
    key = key and strtrim(key) or ""
    for _, counter in ipairs(self.COUNTERS) do
        if key == "" or counter.key == key then
            for _, line in ipairs(RawLines(counter)) do lines[#lines + 1] = line end
        end
    end
    if #lines == 0 then lines[1] = "unknown counter: " .. key end
    return lines
end

--- Woher die Zahlen kommen, für /gli probe db sources (Core)
function S:SourceLines()
    local lines = {}
    local seen = {}
    for _, counter in ipairs(self.COUNTERS) do
        if not seen[counter.ns] then
            seen[counter.ns] = true
            lines[#lines + 1] = format("reads namespace %s: %s", counter.ns,
                self:Reader(counter.ns) and "available" or "missing")
        end
    end
    lines[#lines + 1] = "names of creatures and objects: Glimpse core (Glimpse.IDs), "
        .. ((Glimpse.IDs and Glimpse.IDs.NPCName) and "available" or "missing")
    lines[#lines + 1] = "settings: Glimpse profile, namespace Statistics"
    return lines
end

function S:RegisterProbes()
    if Glimpse.RegisterDataSource then
        Glimpse:RegisterDataSource("Glimpse_Statistics", function() return S:SourceLines() end)
    end
    if not Glimpse.RegisterProbe then return end
    Glimpse:RegisterProbe("stats", "status", function() return S:StatusLines() end,
        "Glimpse: Statistics: Database, namespaces, totals")
    Glimpse:RegisterProbe("stats", "raw", function(args) return S:RawLines(args) end,
        "Glimpse: Statistics: values per source, biggest IDs, periods ([counter])")
end

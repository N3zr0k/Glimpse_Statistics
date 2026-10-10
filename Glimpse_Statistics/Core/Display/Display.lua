local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Textausgabe für Befehle, Optionsseite und Fenster

local Format = S.FormatNumber

-- Zählerwert in seiner Einheit (DisplayFormat.lua)
local function Value(key, value)
    return S:FormatValue(key, value)
end

--- L["DATE_FORMAT"], "-" ohne Zeitpunkt.
function S:FormatDate(timestamp)
    if not timestamp then return "-" end
    local ok, text = pcall(date, L["DATE_FORMAT"], timestamp)
    return ok and text or "-"
end

--- "Erfasst seit ...", nil ohne Daten.
function S:SinceLine(scope)
    local since = self:GetSince(scope)
    if not since then return nil end
    return format("|cff999999%s %s|r", L["Counting since"], self:FormatDate(since))
end

-- "-" bei whole = 0
local function Percent(part, whole)
    if not whole or whole <= 0 then return "-" end
    return format("%d %%", math.floor(part / whole * 100 + 0.5))
end

function S:HasData(charOnly)
    for _, counter in ipairs(self:GetCounters()) do
        if self:Get(counter.key, "char") > 0 then return true end
        if not charOnly and self:Get(counter.key, "account") > 0 then return true end
    end
    return false
end

--- "Fangquote Lehrling: 79 % (57/72)" je Stufe; leer bei nur einer Stufe (Gesamtquote reicht).
function S:TierRateLines(scope)
    local byMax, order = {}, {}
    local function Entry(item)
        local entry = byMax[item.max]
        if not entry then
            entry = { max = item.max, name = item.name, casts = 0, catches = 0 }
            byMax[item.max] = entry
            order[#order + 1] = entry
        end
        return entry
    end
    for _, item in ipairs(self:GetTierCounts("fishing.casts", scope)) do Entry(item).casts = item.count end
    for _, item in ipairs(self:GetTierCounts("fishing.catches", scope)) do Entry(item).catches = item.count end
    if #order < 2 then return {} end

    table.sort(order, function(a, b) return a.max < b.max end)
    local lines = {}
    for _, entry in ipairs(order) do
        lines[#lines + 1] = format("  %s %s: %s  |cff999999(%s/%s)|r", L["Catch rate"], entry.name, Percent(entry.catches, entry.casts),
            Format(entry.catches), Format(entry.casts))
    end
    return lines
end

-- Würfe ohne Fang und Fangquote; Fänge ohne Blizzard-Startwert, da es zu ihm keine Würfe gibt
local function RateLines(self, lines, charOnly)
    local casts, casts2 = self:Get("fishing.casts", "char"), self:Get("fishing.casts", "account")
    local mine, all = self:GetCounted("fishing.catches", "char"), self:GetCounted("fishing.catches", "account")
    if charOnly then
        lines[#lines + 1] = format("  %s: %s", L["Casts without catch"], Format(math.max(casts - mine, 0)))
        lines[#lines + 1] = format("  %s: %s", L["Catch rate"], Percent(mine, casts))
    else
        lines[#lines + 1] = format("  %s: %s  |cff999999(%s: %s)|r", L["Casts without catch"],
            Format(math.max(casts - mine, 0)), L["Account"], Format(math.max(casts2 - all, 0)))
        lines[#lines + 1] = format("  %s: %s  |cff999999(%s: %s)|r", L["Catch rate"],
            Percent(mine, casts), L["Account"], Percent(all, casts2))
    end
    for _, line in ipairs(self:TierRateLines("char")) do lines[#lines + 1] = line end
end

--- Flugzeit im Schnitt, nil ohne Flüge.
function S:AverageFlight(scope)
    local flights = self:Get("travel.flights", scope)
    if flights <= 0 then return nil end
    return self:Get("travel.flighttime", scope) / flights
end

-- Schnitt als eigene Zeile unter dem Zeitzähler, Charakter und Account
local function AverageLine(lines, label, mine, all, charOnly)
    if not (mine or all) then return end
    local text = format("  %s: %s", label, mine and S.FormatDuration(mine) or "-")
    if not charOnly then text = text .. format("  |cff999999(%s: %s)|r", L["Account"], all and S.FormatDuration(all) or "-") end
    lines[#lines + 1] = text
end

local function FlightLines(self, lines, charOnly)
    AverageLine(lines, L["Average flight"], self:AverageFlight("char"), not charOnly and self:AverageFlight("account") or nil, charOnly)
end

--- Übersicht als Abschnitte je Gruppe: since = "Erfasst seit"-Zeile (oder nil), sections = { { group, lines } }.
-- Zeilen "Name: Charakter (Account: Zahl)" plus heute/7 Tage. detail: Top 3 der Aufschlüsselung und Stufen.
-- charOnly: ohne Account. keyPrefix: nur passende Zähler.
function S:OverviewSections(detail, charOnly, keyPrefix)
    local sections, lines = {}, nil
    local group
    local since = self:SinceLine("char")
    if not charOnly then
        local sinceAll = self:SinceLine("account")
        since = since and sinceAll and format("%s (%s)  %s (%s)", since, L["Character"], sinceAll, L["Account"]) or nil
    end
    for _, counter in ipairs(self:GetCounters()) do
        local key = counter.key
        local mine, all = self:Get(key, "char"), charOnly and 0 or self:Get(key, "account")
        if (not keyPrefix or key:sub(1, #keyPrefix) == keyPrefix) and (mine > 0 or all > 0) then
            if counter.group ~= group then
                group = counter.group
                lines = {}
                sections[#sections + 1] = { group = group, lines = lines }
            end

            local text = charOnly and format("  %s: %s", counter.label, Value(key, mine))
                or format("  %s: %s  |cff999999(%s: %s)|r", counter.label, Value(key, mine), L["Account"], Value(key, all))
            local week = self:GetSum(key, "char", 7)
            if week > 0 then
                text = text .. format("  |cff66ccff%s %s · %s %s|r", L["today"], Value(key, self:GetSum(key, "char", 1)),
                    L["7 days"], Value(key, week))
            end
            lines[#lines + 1] = text

            if key == "fishing.catches" then RateLines(self, lines, charOnly) end
            if key == "travel.flighttime" then FlightLines(self, lines, charOnly) end
            if detail and key ~= "fishing.catches" then
                local tiers = self:GetTierCounts(key, "char")
                if #tiers >= 2 then
                    for _, tier in ipairs(tiers) do
                        lines[#lines + 1] = format("      |cff999999%s: %s|r", tier.name, Format(tier.count))
                    end
                end
            end
            if detail then
                for index, entry in ipairs(self:GetBreakdown(key, "char", 3)) do
                    lines[#lines + 1] = format("      |cff999999%d. %s: %s|r", index, entry.name, Value(key, entry.count))
                end
            end
        end
    end
    return since, sections
end

--- Zeilen der Übersicht, Gruppen mit Überschrift. "Erfasst seit" bleibt erste Zeile.
function S:OverviewLines(detail, charOnly, keyPrefix)
    local since, sections = self:OverviewSections(detail, charOnly, keyPrefix)
    local lines = { since }
    for _, section in ipairs(sections) do
        lines[#lines + 1] = "|cffffd100" .. section.group .. "|r"
        for _, line in ipairs(section.lines) do lines[#lines + 1] = line end
    end
    return lines
end

--- /gli stats verbose. scope "char" oder "account".
function S:VerboseLines(scope)
    local lines = {}
    lines[#lines + 1] = format("%s (%s)  %s (%s)", self:SinceLine("char") or "-", L["Character"], self:SinceLine("account") or "-", L["Account"])

    local group
    for _, counter in ipairs(self:GetCounters()) do
        local key = counter.key
        local value = self:Get(key, scope)
        if value > 0 then
            if counter.group ~= group then
                group = counter.group
                lines[#lines + 1] = "|cffffd100" .. group .. "|r"
            end
            lines[#lines + 1] = format("  |cffffffff%s: %s|r  |cff999999(%s)|r", counter.label, Value(key, value), key)
            local baseline = self:GetBaseline(key, scope)
            if baseline > 0 then
                lines[#lines + 1] = format("    |cff999999%s: %s|r", L["From Blizzard's statistics"], Format(baseline))
            end
            local span = self:SpanLine(key, scope)
            if span then lines[#lines + 1] = "    " .. span end
            if counter.unit ~= "distinct" then
                lines[#lines + 1] = format("    |cff66ccff%s %s · %s %s · %s %s|r", L["today"], Value(key, self:GetSum(key, scope, 1)),
                    L["7 days"], Value(key, self:GetSum(key, scope, 7)), L["30 days"], Value(key, self:GetSum(key, scope, 30)))
            end
            local average = key == "travel.flighttime" and self:AverageFlight(scope)
            if average then lines[#lines + 1] = format("    %s: %s", L["Average flight"], S.FormatDuration(average)) end

            if key == "fishing.catches" then
                local casts, counted = self:Get("fishing.casts", scope), self:GetCounted(key, scope)
                lines[#lines + 1] = format("    %s: %s · %s: %s", L["Casts without catch"], Format(math.max(casts - counted, 0)),
                    L["Catch rate"], Percent(counted, casts))
                for _, line in ipairs(self:TierRateLines(scope)) do lines[#lines + 1] = "  " .. line end
            end

            for _, line in ipairs(self:BreakdownLines(key, scope, 10)) do lines[#lines + 1] = "  " .. line end
            for _, line in ipairs(self:ZoneLines(key, scope, 5)) do lines[#lines + 1] = "  " .. line end
            local series = self:SeriesLines(key, scope, 7)
            if #series > 0 then
                lines[#lines + 1] = "    |cff999999" .. L["Last days"] .. ":|r"
                for _, line in ipairs(series) do lines[#lines + 1] = "  " .. line end
            end
        end
    end
    return lines
end

--- Je Charakter aus Database: Seit-Zeile und die Hauptzähler (ohne Punkt im Schlüssel).
function S:CharacterLines()
    local lines = {}
    for _, index in ipairs(self:GetCharacters()) do
        local parts = {}
        for _, counter in ipairs(self:GetCounters()) do
            local value = self:Get(counter.key, index)
            if value > 0 and not counter.key:find(".", 1, true) then
                parts[#parts + 1] = format("%s %s", counter.label, Value(counter.key, value))
            end
        end
        lines[#lines + 1] = format("|cffffd100%s|r |cff999999(%s %s)|r", self:CharacterName(index), L["Counting since"],
            self:FormatDate(self:GetSince(index)))
        if #parts > 0 then lines[#lines + 1] = "  " .. table.concat(parts, " · ") end
    end
    return lines
end

--- nil ohne Daten.
function S:SpanLine(key, scope)
    local first, last = self:GetFirst(key, scope)
    if not first then return nil end
    return format("|cff999999%s %s, %s %s|r", L["first"], self:FormatDate(first), L["last"], self:FormatDate(last))
end

--- Neueste zuerst, die letzten days Tage (Standard 14), für /gli stats <Zähler> days.
function S:SeriesLines(key, scope, days)
    local lines = {}
    local series = self:GetSeries(key, scope, days or 14)
    for index = #series, 1, -1 do
        local entry = series[index]
        lines[#lines + 1] = format("  %s: %s", self:FormatDate(entry.time), Value(key, entry.n))
    end
    return lines
end

function S:BreakdownLines(key, scope, limit)
    local lines = {}
    for index, entry in ipairs(self:GetBreakdown(key, scope, limit or 10)) do
        lines[#lines + 1] = format("  %d. %s: %s", index, entry.name, Value(key, entry.count))
    end
    return lines
end

--- Aufschlüsselung nach Zone mit Überschrift, leer ohne Zonen.
function S:ZoneLines(key, scope, limit)
    local lines = {}
    for index, entry in ipairs(self:GetZoneBreakdown(key, scope, limit or 10)) do
        if index == 1 then lines[1] = "  |cff999999" .. L["By zone"] .. ":|r" end
        lines[#lines + 1] = format("  %d. %s: %s", index, entry.name, Value(key, entry.count))
    end
    return lines
end

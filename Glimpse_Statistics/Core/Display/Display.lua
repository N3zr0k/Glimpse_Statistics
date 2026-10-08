local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Textausgabe für Befehle, Optionsseite und Fenster

local function Format(value)
    -- Tausendertrennung: 12345 -> 12 345
    local text = tostring(math.floor(value))
    while true do
        local replaced, count = text:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
        text = replaced
        if count == 0 then break end
    end
    return text
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
    for _, info in ipairs(self:GetRegistered()) do
        if self:Get(info.key, "char") > 0 then return true end
        if not charOnly and self:Get(info.key, "account") > 0 then return true end
    end
    return false
end

--- "Fangquote Lehrling: 79 % (57/72)" je Stufe; leer bei nur einer Stufe (Gesamtquote reicht).
function S:TierRateLines()
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
    for _, item in ipairs(self:GetTierCounts("fishing.casts", "char")) do Entry(item).casts = item.count end
    for _, item in ipairs(self:GetTierCounts("fishing.catches", "char")) do Entry(item).catches = item.count end
    if #order < 2 then return {} end

    table.sort(order, function(a, b) return a.max < b.max end)
    local lines = {}
    for _, entry in ipairs(order) do
        lines[#lines + 1] = format("  %s %s: %s  |cff999999(%s/%s)|r", L["Catch rate"], entry.name, Percent(entry.catches, entry.casts),
            Format(entry.catches), Format(entry.casts))
    end
    return lines
end

--- Zeilen "Name: Charakter (Account: Zahl)" plus heute/7 Tage, gruppiert. detail: Top 3 der Aufschlüsselung
-- und Stufen. charOnly: ohne Account. keyPrefix: nur passende Zähler, "Erfasst seit" bleibt erste Zeile.
function S:OverviewLines(detail, charOnly, keyPrefix)
    local lines = {}
    local group
    local since, sinceAll = self:SinceLine("char"), self:SinceLine("account")
    if charOnly then
        if since then lines[1] = since end
    elseif since and sinceAll then
        lines[1] = format("%s (%s)  %s (%s)", since, L["Character"], sinceAll, L["Account"])
    end
    for _, info in ipairs(self:GetRegistered()) do
        local mine, all = self:Get(info.key, "char"), self:Get(info.key, "account")
        if (not keyPrefix or info.key:sub(1, #keyPrefix) == keyPrefix) and (mine > 0 or (all > 0 and not charOnly)) then
            if info.group and info.group ~= group then
                group = info.group
                lines[#lines + 1] = "|cffffd100" .. group .. "|r"
            end

            local text = charOnly and format("  %s: %s", info.label, Format(mine))
                or format("  %s: %s  |cff999999(%s: %s)|r", info.label, Format(mine), L["Account"], Format(all))
            local today, week = self:GetSum(info.key, "char", 1), self:GetSum(info.key, "char", 7)
            if week > 0 then
                text = text .. format("  |cff66ccff%s %s · %s %s|r", L["today"], Format(today), L["7 days"], Format(week))
            end
            lines[#lines + 1] = text

            -- Quote ohne Blizzard-Startwert, da es zu ihm keine Würfe gibt
            if info.key == "fishing.catches" then
                local casts, casts2 = self:Get("fishing.casts", "char"), self:Get("fishing.casts", "account")
                mine, all = self:GetCounted(info.key, "char"), self:GetCounted(info.key, "account")
                if charOnly then
                    lines[#lines + 1] = format("  %s: %s", L["Casts without catch"], Format(math.max(casts - mine, 0)))
                    lines[#lines + 1] = format("  %s: %s", L["Catch rate"], Percent(mine, casts))
                else
                    lines[#lines + 1] = format("  %s: %s  |cff999999(%s: %s)|r", L["Casts without catch"],
                        Format(math.max(casts - mine, 0)), L["Account"], Format(math.max(casts2 - all, 0)))
                    lines[#lines + 1] = format("  %s: %s  |cff999999(%s: %s)|r", L["Catch rate"],
                        Percent(mine, casts), L["Account"], Percent(all, casts2))
                end
            end

            if info.key == "fishing.catches" then
                for _, line in ipairs(self:TierRateLines()) do lines[#lines + 1] = line end
            end
            if detail and S.TIERED[info.key] then
                local tiers = self:GetTierCounts(info.key, "char")
                if #tiers >= 2 then
                    for _, tier in ipairs(tiers) do
                        lines[#lines + 1] = format("      |cff999999%s: %s|r", tier.name, Format(tier.count))
                    end
                end
            end

            if detail and info.breakdown then
                for index, entry in ipairs(self:GetBreakdown(info.key, "char", 3)) do
                    lines[#lines + 1] = format("      |cff999999%d. %s: %s|r", index, entry.name, Format(entry.count))
                end
            end
        end
    end
    return lines
end

--- /gli stats verbose. scope "char" oder "account".
function S:VerboseLines(scope)
    local lines = {}
    lines[#lines + 1] = format("%s %s", L["Counting"] .. ":", self:IsCollecting() and L["on"] or L["off"])
    lines[#lines + 1] = format("%s (%s)  %s (%s)", self:SinceLine("char") or "-", L["Character"], self:SinceLine("account") or "-", L["Account"])
    if self.errorCount then
        lines[#lines + 1] = format("%s: %d", L["Errors"], self.errorCount) .. (self.lastError and (" (" .. self.lastError .. ")") or "")
    end

    local group
    for _, info in ipairs(self:GetRegistered()) do
        local value = self:Get(info.key, scope)
        if value > 0 then
            if info.group and info.group ~= group then
                group = info.group
                lines[#lines + 1] = "|cffffd100" .. group .. "|r"
            end
            lines[#lines + 1] = format("  |cffffffff%s: %s|r  |cff999999(%s)|r", info.label, Format(value), info.key)
            local span = self:SpanLine(info.key, scope)
            if span then lines[#lines + 1] = "    " .. span end
            lines[#lines + 1] = format("    |cff66ccff%s %s · %s %s · %s %s|r", L["today"], Format(self:GetSum(info.key, scope, 1)),
                L["7 days"], Format(self:GetSum(info.key, scope, 7)), L["30 days"], Format(self:GetSum(info.key, scope, 30)))

            if info.key == "fishing.catches" then
                local casts = self:Get("fishing.casts", scope)
                value = self:GetCounted(info.key, scope) -- ohne Startwert, siehe OverviewLines
                lines[#lines + 1] = format("    %s: %s · %s: %s", L["Casts without catch"], Format(math.max(casts - value, 0)),
                    L["Catch rate"], Percent(value, casts))
            end

            if info.breakdown then
                for _, line in ipairs(self:BreakdownLines(info.key, scope, 10)) do lines[#lines + 1] = "  " .. line end
            end
            local series = self:SeriesLines(info.key, scope, 7)
            if #series > 0 then
                lines[#lines + 1] = "    |cff999999" .. L["Last days"] .. ":|r"
                for _, line in ipairs(series) do lines[#lines + 1] = "  " .. line end
            end
        end
    end
    return lines
end

-- Zahlen vor Strings
local function SortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    return keys
end

--- DB-Rohdaten für den Debug-Modus, eine Zeile je Wert: "since|Zeit", "totals|Zähler|Summe", "first|Zähler|Zeit",
-- "last|Zähler|Zeit", "by|Zähler|ID|n=..|name=..|first=..|last=..", "days|Zähler|JJJJMMTT|Summe".
-- Ohne full je Abschnitt/Zähler nur 5 (by: größte, days: neueste). onlyKey filtert auf einen Zähler.
function S:RawLines(scope, full, onlyKey)
    local lines = {}
    local limit = (not full) and 5 or nil
    -- "|" ist im Chat Escape-Zeichen, daher "||" (auch in Namen)
    local function Line(...)
        local fields = { ... }
        for index, value in ipairs(fields) do fields[index] = (tostring(value):gsub("|", "||")) end
        lines[#lines + 1] = "|cff999999" .. table.concat(fields, "||") .. "|r"
    end
    local function Wanted(key) return not onlyKey or onlyKey == key end

    local data = self:GetRawData(scope)
    if not data then return lines end

    if data.since and not onlyKey then Line("since", data.since) end

    local keys = {}
    local seen = {}
    local function Add(key) if not seen[key] then seen[key] = true keys[#keys + 1] = key end end
    for _, key in ipairs(self:GetCounterKeys(scope)) do Add(key) end
    for _, section in ipairs({ "totals", "first", "last", "by", "days" }) do
        for _, key in ipairs(SortedKeys(data[section] or {})) do Add(key) end
    end

    for _, key in ipairs(keys) do
        if Wanted(key) then
            for _, section in ipairs({ "totals", "first", "last" }) do
                if data[section] and data[section][key] ~= nil then Line(section, key, data[section][key]) end
            end

            local by = data.by and data.by[key]
            if by then
                local ids = SortedKeys(by)
                table.sort(ids, function(a, b)
                    local na, nb = by[a].n or 0, by[b].n or 0
                    if na ~= nb then return na > nb end
                    return tostring(a) < tostring(b)
                end)
                for index, id in ipairs(ids) do
                    if limit and index > limit then break end
                    local fields = {}
                    for _, field in ipairs(SortedKeys(by[id])) do fields[#fields + 1] = field .. "=" .. tostring(by[id][field]) end
                    Line("by", key, id, unpack(fields))
                end
            end

            local days = data.days and data.days[key]
            if days then
                local list = SortedKeys(days)
                for index = #list, 1, -1 do
                    if limit and #list - index >= limit then break end
                    Line("days", key, list[index], days[list[index]])
                end
            end
        end
    end
    return lines
end

function S:CharacterLines()
    local lines = {}
    for _, name in ipairs(self:GetCharacters()) do
        local parts = {}
        for _, info in ipairs(self:GetRegistered()) do
            local value = self:Get(info.key, name)
            if value > 0 and not info.key:find(".", 1, true) then
                parts[#parts + 1] = format("%s %s", info.label, Format(value))
            end
        end
        lines[#lines + 1] = format("|cffffd100%s|r |cff999999(%s %s)|r", name, L["Counting since"], self:FormatDate(self:GetSince(name)))
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

--- Neueste zuerst, für /gli stats <Zähler> days.
function S:SeriesLines(key, scope, limit)
    local lines = {}
    local series = self:GetSeries(key, scope)
    for index = #series, math.max(#series - (limit or 14) + 1, 1), -1 do
        local entry = series[index]
        lines[#lines + 1] = format("  %s: %s", self:FormatDate(entry.time), Format(entry.n))
    end
    return lines
end

function S:BreakdownLines(key, scope, limit)
    local lines = {}
    for index, entry in ipairs(self:GetBreakdown(key, scope, limit or 10)) do
        lines[#lines + 1] = format("  %d. %s: %s", index, entry.name, Format(entry.count))
    end
    return lines
end

local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- /gli stats [account] [<Zähler> [days]] [verbose]
--   ohne Zähler  Übersicht
--   mit Zähler   Aufschlüsselung nach ID und Zone, mit days Tagesverlauf
--   verbose      alles; mit Zähler bis 100 Einträge und 30 Tage
--   details      Top 3 je Zähler; chars: alle Charaktere; status: wie /gli probe stats status
--   window, blizzard, trace
local function PrintLines(lines)
    for _, line in ipairs(lines) do Glimpse:Print(line) end
end

local function Next(text)
    local first, rest = strmatch(text, "^(%S*)%s*(.-)$")
    return strlower(first), rest
end

local function FindCounter(first, rest)
    local label = strlower(first .. (rest ~= "" and (" " .. rest) or ""))
    for _, counter in ipairs(S:GetCounters()) do
        if strlower(counter.key) == first or strlower(counter.label) == label then return counter end
    end
end

local function ShowCounter(counter, scope, days, verbose)
    local key = counter.key
    Glimpse:Print(format("%s: %s", counter.label, S:FormatValue(key, S:Get(key, scope))))
    local span = S:SpanLine(key, scope)
    if span then Glimpse:Print(span) end
    if verbose then
        PrintLines(S:BreakdownLines(key, scope, 100))
        PrintLines(S:ZoneLines(key, scope, 100))
        Glimpse:Print(L["Last days"] .. ":")
        PrintLines(S:SeriesLines(key, scope, 30))
    elseif days then
        PrintLines(S:SeriesLines(key, scope, 14))
    else
        PrintLines(S:BreakdownLines(key, scope, 10))
        PrintLines(S:ZoneLines(key, scope, 10))
    end
end

local function OnCommand(_, args)
    local text = strtrim(args or "")
    local plain = strtrim((text:gsub("[Vv][Ee][Rr][Bb][Oo][Ss][Ee]$", "")))
    local verbose = plain ~= text

    local first, rest = Next(plain)
    -- Charaktername enthält Leerzeichen, daher hier nur "account"
    local scope = "char"
    if first == "account" then
        scope = "account"
        first, rest = Next(rest)
    end

    if scope == "char" then
        if first == "status" then PrintLines(S:StatusLines()) return end
        if first == "window" then S:ToggleWindow() return end
        if first == "trace" then S:Trace(rest) return end
        if first == "blizzard" then
            if strlower(rest) == "all" then
                Glimpse:ShowTextWindow("Blizzard statistics", S:BlizzardDumpText())
            else
                PrintLines(S:BlizzardLines(rest))
            end
            return
        end
        if first == "chars" then PrintLines(S:CharacterLines()) return end
    end

    if first == "" and verbose then
        Glimpse:Print(L["Statistics"] .. " (" .. (scope == "account" and L["Account"] or L["Character"]) .. ", verbose)")
        PrintLines(S:VerboseLines(scope))
        return
    end
    if first == "details" or first == "" then
        local lines = S:OverviewLines(first == "details")
        if #lines == 0 then
            Glimpse:Print(L["Nothing counted yet."])
            return
        end
        Glimpse:Print(L["Statistics"] .. " (" .. (first == "details" and L["Details"] or
            (scope == "account" and L["Account"] or L["Character"])) .. ")")
        PrintLines(lines)
        return
    end

    -- Schlüssel oder Anzeigename, optional "days"
    local days = false
    if strlower(rest):find("^days$") or strlower(rest):find("%sdays$") then
        days, rest = true, strtrim(rest:sub(1, -5))
    end
    local counter = FindCounter(first, rest)
    if counter then
        ShowCounter(counter, scope, days, verbose)
        return
    end

    local keys = {}
    for _, info in ipairs(S:GetCounters()) do keys[#keys + 1] = info.key end
    Glimpse:Print(format(L["Unknown counter. Known: %s"], table.concat(keys, ", ")))
end

Glimpse:RegisterCommand("stats", L["Shows your statistics: /gli stats [account] [counter], details, chars, verbose, window (opens or closes the statistics window), status, blizzard, trace"], OnCommand)

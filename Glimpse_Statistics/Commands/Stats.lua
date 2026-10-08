local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- /gli stats [account | <Charakter>] [<Zähler> [days]] [verbose]
--   ohne Zähler  Übersicht
--   mit Zähler   Aufschlüsselung, mit days Tagesverlauf
--   verbose      alles; mit Zähler bis 100 Einträge und 30 Tage
--   details      Top 3 je Zähler; chars: alle Charaktere
local function PrintLines(lines)
    for _, line in ipairs(lines) do Glimpse:Print(line) end
end

local function OnCommand(_, args)
    local text = strtrim(args or "")
    local plain = strtrim((text:gsub("[Vv][Ee][Rr][Bb][Oo][Ss][Ee]$", "")))
    local verbose = plain ~= text

    local first, rest = strmatch(plain, "^(%S*)%s*(.-)$")
    first = strlower(first)

    -- Rohdaten im Debug-Modus oder mit "debug": 5 je Zähler, mit verbose alle
    local raw = Glimpse.IsDebug ~= nil and Glimpse:IsDebug() == true
    if first == "debug" then
        raw, first, rest = true, strmatch(rest, "^(%S*)%s*(.-)$")
        first = strlower(first)
    end

    -- Charaktername enthält Leerzeichen, daher hier nur "account"
    local scope = "char"
    if first == "account" then
        scope = "account"
        first, rest = strmatch(rest, "^(%S*)%s*(.-)$")
        first = strlower(first)
        if first == "debug" then
            raw, first, rest = true, strmatch(rest, "^(%S*)%s*(.-)$")
            first = strlower(first)
        end
    end

    if first == "status" and scope == "char" then
        Glimpse:Print(format(L["Counting is %s. Counting since: %s (character), %s (account). Errors: %d."],
            S:IsCollecting() and L["on"] or L["off"], S:FormatDate(S:GetSince("char")), S:FormatDate(S:GetSince("account")),
            S.errorCount or 0))
        if S.lastError then Glimpse:Print(format(L["Last error: %s"], S.lastError)) end
        Glimpse:Print("|cff999999" .. S:BaselineStatusLine() .. "|r")
        -- Kill-Diagnose
        local d = S.diag
        if d and d.checks then
            local events = {}
            for name, n in pairs(d.events or {}) do events[#events + 1] = name .. "=" .. n end
            table.sort(events)
            Glimpse:Print("|cff999999PARTY_KILL: " .. (d.partyKill and "active" or "unknown to this client, target death is used") .. "|r")
            Glimpse:Print(format("|cff999999kills: checks=%d dead=%d secret=%d noGUID=%d tapped=%d  %s|r", d.checks, d.dead,
                d.secret, d.noGUID, d.tapped, table.concat(events, " ")))
        end
        return
    end
    if first == "window" and scope == "char" then S:ToggleWindow() return end
    if first == "trace" and scope == "char" then S:Trace(rest) return end
    if first == "blizzard" and scope == "char" then
        if strlower(rest) == "all" then
            S:ShowText("Blizzard statistics", S:BlizzardDumpText())
        else
            PrintLines(S:BlizzardLines(rest))
        end
        return
    end
    if first == "chars" and scope == "char" then
        PrintLines(S:CharacterLines())
        return
    end
    if first == "details" then
        local lines = S:OverviewLines(true)
        if #lines == 0 then
            Glimpse:Print(L["Nothing counted yet. Kills, fishing and gathering are counted automatically from now on."])
            return
        end
        Glimpse:Print(L["Statistics"] .. " (" .. L["Details"] .. ")")
        PrintLines(lines)
        return
    end
    if first == "export" and scope == "char" then S:ShowExport() return end
    if first == "import" and scope == "char" then S:ShowImport() return end

    if first == "" and verbose then
        Glimpse:Print(L["Statistics"] .. " (" .. (scope == "account" and L["Account"] or L["Character"]) .. ", verbose)")
        PrintLines(S:VerboseLines(scope))
        if raw then PrintLines(S:RawLines(scope, true)) end
        return
    end

    if first == "" then
        local lines = S:OverviewLines()
        if #lines == 0 then
            Glimpse:Print(L["Nothing counted yet. Kills, fishing and gathering are counted automatically from now on."])
            return
        end
        Glimpse:Print(L["Statistics"] .. " (" .. (scope == "account" and L["Account"] or L["Character"]) .. ")")
        PrintLines(lines)
        if raw then PrintLines(S:RawLines(scope, false)) end
        return
    end

    -- Schlüssel oder Anzeigename, optional "days"
    local days = false
    if strlower(rest) == "days" then days, rest = true, "" end

    for _, info in ipairs(S:GetRegistered()) do
        if strlower(info.key) == first or strlower(info.label) == strlower(first .. (rest ~= "" and (" " .. rest) or "")) then
            Glimpse:Print(format("%s: %d", info.label, S:Get(info.key, scope)))
            local span = S:SpanLine(info.key, scope)
            if span then Glimpse:Print(span) end
            if verbose then
                if info.breakdown then PrintLines(S:BreakdownLines(info.key, scope, 100)) end
                Glimpse:Print(L["Last days"] .. ":")
                PrintLines(S:SeriesLines(info.key, scope, 30))
            elseif days then
                PrintLines(S:SeriesLines(info.key, scope, 14))
            elseif info.breakdown then
                PrintLines(S:BreakdownLines(info.key, scope, 10))
            end
            if raw then PrintLines(S:RawLines(scope, verbose, info.key)) end
            return
        end
    end

    local keys = {}
    for _, info in ipairs(S:GetRegistered()) do keys[#keys + 1] = info.key end
    Glimpse:Print(format(L["Unknown counter. Known: %s"], table.concat(keys, ", ")))
end

Glimpse:RegisterCommand("stats", L["Shows your statistics: /gli stats [account] [counter], details, chars, verbose, window (opens or closes the statistics window), status with /gli stats status, backup with /gli stats export | import"], OnCommand)

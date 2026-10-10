-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Anzeige (Core/Display/Display.lua), Befehl (Commands/Stats.lua), Probes, Optionen und Nachrichten

local function writers(DB)
    return DB:Register("combat", { area = "Core", zones = true }),
        DB:Register("fishing", { area = "Professions", zones = true }),
        DB:Register("gathering", { area = "Gathering", zones = true })
end

local function text(lines) return table.concat(lines, "\n") end

test("Anzeige: Übersicht mit Gruppen, Account, Zeiträumen und Tausendertrennung", function()
    local S, _, DB = stub.setup()
    local combat, _, gathering = writers(DB)
    combat:Count("kill", 299, 12, 12345)
    gathering:Count("herb", 1617, 12, 2)

    local lines = S:OverviewLines()
    assert(lines[1]:find("Counting since 2026", 1, true), lines[1])
    eq(lines[2], "|cffffd100Combat|r", "Gruppe")
    assert(lines[3]:find("Creatures killed: 12 345", 1, true) and lines[3]:find("Account: 12 345", 1, true), lines[3])
    assert(lines[3]:find("today 12 345 · 7 days 12 345", 1, true), "Zeiträume")
    assert(text(lines):find("Herbs gathered: 2", 1, true), "Sammeln")
    assert(not text(lines):find("Fishing", 1, true), "Zähler ohne Wert fehlen")

    local mine = text(S:OverviewLines(false, true, "gathering."))
    assert(mine:find("Herbs gathered: 2", 1, true) and not mine:find("Account", 1, true), mine)
    assert(not mine:find("Creatures killed", 1, true), "Filter nach Schlüssel")

    local details = text(S:OverviewLines(true))
    assert(details:find("1. Creature 299: 12 345", 1, true), details)
end)

test("Anzeige: Fangquote ohne Blizzard-Startwert, Quote je Stufe erst ab zwei Stufen", function()
    local S, _, DB = stub.setup()
    local _, fishing = writers(DB)
    fishing:SetBaseline("catch", 0, 1000)
    for _ = 1, 10 do fishing:Count("cast", 0, 12); fishing:Count("casttier", 75) end
    for _ = 1, 5 do fishing:Count("catch", 0, 12); fishing:Count("catchtier", 75) end
    S.api.GetSpellSubtext = function(id) return ({ [7620] = "Lehrling", [7731] = "Geselle" })[id] end

    local lines = text(S:OverviewLines(false, true))
    assert(lines:find("Fishing catches: 1 005", 1, true), "Fänge mit Startwert\n" .. lines)
    assert(lines:find("Casts without catch: 5", 1, true) and lines:find("Catch rate: 50 %", 1, true), "Quote ohne Startwert\n" .. lines)
    eq(#S:TierRateLines(), 0, "nur eine Stufe: Gesamtquote reicht")

    for _ = 1, 4 do fishing:Count("cast", 0, 12); fishing:Count("casttier", 150) end
    for _ = 1, 3 do fishing:Count("catch", 0, 12); fishing:Count("catchtier", 150) end
    local tiers = S:TierRateLines()
    eq(#tiers, 2, "zwei Stufen")
    assert(tiers[1]:find("Catch rate Lehrling: 50 %", 1, true) and tiers[2]:find("Catch rate Geselle: 75 %", 1, true), text(tiers))
    assert(text(S:OverviewLines()):find("Catch rate Geselle", 1, true), "in der Übersicht")
end)

test("Anzeige: verbose zeigt Startwert, Zeiträume, Aufschlüsselung, Zonen und Tage", function()
    local S, _, DB = stub.setup()
    local combat = writers(DB)
    combat:SetBaseline("kill", 0, 50)
    combat:Count("kill", 299, 12, 3); combat:Count("kill", 40, 14)
    local all = text(S:VerboseLines("char"))
    for _, part in ipairs({ "Creatures killed: 54", "(kills)", "From Blizzard's statistics: 50", "first 2026", "30 days 4",
        "1. Creature 299: 3", "By zone", "Zone 12: 3", "Last days" }) do
        assert(all:find(part, 1, true), part .. "\n" .. all)
    end
end)

test("Befehl: Übersicht, Account, Zähler mit Aufschlüsselung und Tagen, unbekannt", function()
    local S, Glimpse, DB = stub.setup()
    local run = Glimpse.commands.stats.func
    run(nil, "")
    eq(Glimpse.printed[1], "Nothing counted yet.", "noch nichts")

    local combat = writers(DB)
    combat:Count("kill", 299, 12, 3)
    Glimpse.printed = {}
    run(nil, "")
    eq(Glimpse.printed[1], "Statistics (Character)", "Überschrift")
    assert(Glimpse.printed[4]:find("Creatures killed: 3", 1, true), text(Glimpse.printed))

    Glimpse.printed = {}
    run(nil, "account kills")
    local out = text(Glimpse.printed)
    assert(Glimpse.printed[1] == "Creatures killed: 3" and out:find("1. Creature 299: 3", 1, true) and out:find("Zone 12: 3", 1, true), out)

    Glimpse.printed = {}
    run(nil, "creatures killed days")
    eq(Glimpse.printed[1], "Creatures killed: 3", "Anzeigename"); eq(#Glimpse.printed, 3, "Summe, Zeitspanne, ein Tag")

    Glimpse.printed = {}
    run(nil, "kills verbose")
    assert(text(Glimpse.printed):find("Last days", 1, true), "verbose mit Zähler")

    Glimpse.printed = {}
    run(nil, "verbose")
    assert(Glimpse.printed[1]:find("verbose", 1, true), "verbose")

    Glimpse.printed = {}
    run(nil, "gibtsnicht")
    assert(Glimpse.printed[1]:find("Unknown counter. Known: kills, deaths", 1, true), Glimpse.printed[1])
    eq(S:IsWindowOpen(), false, "kein Fenster")
end)

test("Befehl: status und Probes, chars, blizzard all", function()
    local S, Glimpse, DB = stub.setup()
    local combat = writers(DB)
    combat:Count("kill", 1, 12)
    local run = Glimpse.commands.stats.func

    run(nil, "status")
    local out = text(Glimpse.printed)
    assert(out:find("Glimpse: Database: API", 1, true) and out:find("namespace combat: readable", 1, true), out)
    assert(out:find("kills = combat:kill  char 1", 1, true), out)
    eq(text(Glimpse.probes["stats status"]("")), text(S:StatusLines()), "Probe wie Befehl")

    local raw = text(Glimpse.probes["stats raw"]("kills"))
    assert(raw:find("kills (combat:kill) char: own=1 imported=0 baseline=0", 1, true) and raw:find("id 1 n=1", 1, true), raw)
    assert(raw:find("today=1 week=1 month=1 zones=1", 1, true), raw)
    eq(Glimpse.probes["stats raw"]("x")[1], "unknown counter: x", "unbekannter Zähler")

    Glimpse.printed = {}
    run(nil, "chars")
    assert(Glimpse.printed[1]:find("Flovy - Forever", 1, true) and Glimpse.printed[2]:find("Creatures killed 1", 1, true), text(Glimpse.printed))

    run(nil, "blizzard all")
    eq(Glimpse.textWindow.title, "Blizzard statistics", "Kopierfenster des Core")

    _G.GlimpseDB = nil
    eq(S:StatusLines()[1], "Glimpse: Database: missing, nothing to show", "ohne Database")
end)

test("Übernahme: alte Daten von Statistics kommen über Database und werden angezeigt", function()
    local old = {
        char = { ["Flovy - Forever"] = {
            totals = { kills = 120, ["fishing.casts"] = 10, ["fishing.catches"] = 1006, ["gathering.herb"] = 2 },
            baseline = { kills = 100, ["fishing.catches"] = 1000 },
            by = { kills = { [299] = { n = 15, name = "Wolf", first = 1760000000, last = 1760003600 } },
                ["gathering.herb"] = { [1617] = { n = 2, name = "Silberblatt" } },
                ["fishing.casts"] = { [12] = { n = 10 } } },
            first = { kills = 1760000000, ["fishing.casts"] = 1760000000 }, last = { kills = 1760003600 },
        } },
        global = { totals = { kills = 999 } },
    }
    local S = stub.setup({ GlimpseStatisticsDB = old })
    S:ResetNames()
    eq(S:Get("kills"), 120, "Kills mit Startwert"); eq(S:GetCounted("kills"), 20, "ohne Startwert")
    eq(S:GetBreakdown("kills")[1].name, "Wolf", "Name aus den alten Daten")
    eq(S:Get("gathering.herb"), 2, "Sammeln")
    local lines = text(S:OverviewLines(false, true))
    assert(lines:find("Catch rate: 60 %", 1, true), "Quote ohne Startwert\n" .. lines)
    eq(old.char["Flovy - Forever"].totals.kills, 120, "alte Daten unverändert"); eq(old.global.totals.kills, 999, "Account unverändert")
end)

test("Nachrichten: Änderung in Database meldet Zähler und Thema, fremde Arten nicht", function()
    local S, _, DB = stub.setup()
    local combat, fishing = writers(DB)
    S.messages = {}
    combat:Count("kill", 1, 12)
    eq(S.messages[1][1], "GLIMPSE_STATISTICS_UPDATED", "Nachricht"); eq(S.messages[1][2], "kills", "Zähler")
    eq(S.messages[1][3], "kills", "Thema"); eq(S.messages[1][4], "total", "Kennzahl")
    combat:Count("loot:1", 2589)
    eq(#S.messages, 1, "Beute gehört zu keinem Zähler")
    fishing:Count("casttier", 75)
    eq(S.messages[2][2], "fishing.casts", "Stufe gehört zu den Würfen")
    eq(S:GetSince(), stub.NOON, "seit")
    DB:ResetArea("Core")
    eq(S.messages[3][2], nil, "vieles auf einmal: ohne Zähler")
    eq(S:GetSince(), nil, "seit neu berechnet")
end)

test("Optionen: Übersicht, Hinweis auf die Herkunft, ohne Erfassung, Sicherung und Zurücksetzen", function()
    local S, _, DB = stub.setup()
    local options = S:BuildOptions()
    local main = options.options.args
    eq(main.overview.args.text.name(), "Nothing counted yet.", "ohne Daten")
    assert(main.source.args.text.name:find("Glimpse: Database", 1, true), "Herkunft")
    eq(main.collect, nil, "kein Schalter fürs Zählen"); eq(main.backup, nil, "keine Sicherung"); eq(main.reset, nil, "kein Zurücksetzen")

    local combat = writers(DB)
    combat:Count("kill", 1, 12)
    assert(main.overview.args.text.name():find("Creatures killed: 1", 1, true), "Zahlen aktuell")
end)

test("Datenquellen für /gli probe db sources", function()
    local _, Glimpse, DB = stub.setup()
    writers(DB)
    local lines = text(Glimpse.dataSources.Glimpse_Statistics())
    assert(lines:find("reads namespace combat: available", 1, true), lines)
    assert(lines:find("names of creatures and objects: GlimpseStatisticsDB (read only), not loaded", 1, true), lines)
    assert(lines:find("settings: Glimpse profile, namespace Statistics", 1, true), lines)
end)

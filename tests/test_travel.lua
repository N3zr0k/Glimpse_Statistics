-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Werte aus dem Core: Reisen (travel) und Kampfzeit, geplünderte Leichen (combat). Geschrieben wie im Core.

local function text(lines) return table.concat(lines, "\n") end

local function writers(DB)
    return DB:Register("travel", { area = "Core", days = true }),
        DB:Register("combat", { area = "Core", zones = true, world = { looted = true, loot = true } })
end

test("Format: Zeit, Strecke je Sprache, Zahl", function()
    local S = stub.setup()
    eq(S.FormatDuration(45), "45 s", "Sekunden"); eq(S.FormatDuration(720), "12 min", "Minuten")
    eq(S.FormatDuration(3 * 3600 + 12 * 60 + 5), "3 h 12 min", "Stunden")
    eq(S.FormatDistance(10936), "10.0 km", "ohne Locale km mit Punkt")
    S.L.DISTANCE_UNIT, S.L.DECIMAL_SEPARATOR = "km", ","
    eq(S.FormatDistance(13452), "12,3 km", "deutsch")
    eq(S.FormatDistance(1093613), "1 000,0 km", "Tausendertrennung")
    S.L.DISTANCE_UNIT, S.L.DECIMAL_SEPARATOR = "mi", "."
    eq(S.FormatDistance(17600), "10.0 mi", "englisch in Meilen")
    eq(S:FormatValue("travel.flighttime", 90), "1 min", "Zähler mit Zeit"); eq(S:FormatValue("kills", 1234), "1 234", "Anzahl")
end)

test("Reisen: Summen, verschiedene Zonen und Flugpunkte, beim Account ohne Doppelte", function()
    local S, _, DB, P = stub.setup()
    local travel = writers(DB)
    travel:Count("distance", 1, nil, 500); travel:Count("distance", 2, nil, 1500)
    travel:Count("zone", 12); travel:Count("zone", 12); travel:Count("zone", 1429)
    travel:Count("flightpoint", 2); travel:Count("flightpoint", 6)

    eq(S:Get("travel.distance"), 2000, "Strecke gesamt"); eq(S:Get("travel.zones"), 2, "zwei verschiedene Zonen")
    eq(S:Get("travel.flightpoints"), 2, "zwei Flugpunkte"); eq(S:GetSum("travel.zones", "char", 7), 0, "keine Zeiträume")
    eq(#S:GetSeries("travel.flightpoints", "char", 7), 0, "kein Verlauf"); eq(S:GetSum("travel.distance", "char", 1), 2000, "heute")

    P.char, P.charKey = nil, nil
    stub.player.guid, stub.player.name = "Player-1-00000002", "Zweit"
    travel:Count("flightpoint", 2); travel:Count("flightpoint", 7)
    eq(S:Get("travel.flightpoints"), 2, "Zweit kennt zwei"); eq(S:Get("travel.flightpoints", "account"), 3, "Account ohne Doppelte")

    local modes = S:GetBreakdown("travel.distance", "char")
    eq(#modes, 0, "Zweit ist noch nicht gereist")
    modes = S:GetBreakdown("travel.distance", "account")
    eq(modes[1].name, "Riding", "Art 2"); eq(modes[2].name, "Walking", "Art 1")
end)

test("Reisen: Namen von Flugpunkten vom Client, Strecken, Rückfall auf die ID", function()
    local S, _, DB = stub.setup()
    local travel = writers(DB)
    travel:AddLocation(2, 1415, 0.4, 0.5); travel:AddLocation(6, 1415, 0.5, 0.6)
    travel:Count("flight", 20006, nil, 2); travel:Count("flighttime", 20006, nil, 300)
    travel:Count("flight", 20009); travel:Count("flighttime", 20009, nil, 120)
    S.api.GetTaxiNodesForMap = function(mapID)
        if mapID ~= 1415 then return {} end
        return { { nodeID = 2, name = "Sturmwind" }, { nodeID = 6, name = "Eisenschmiede" } }
    end
    S:ResetFlightPoints()

    local routes = S:GetBreakdown("travel.flights")
    eq(routes[1].name, "Sturmwind - Eisenschmiede", "Strecke mit Namen"); eq(routes[2].name, "Sturmwind - Flight point 9", "ohne Ort die ID")
    eq(S:NameOf("mode", 9), "Mode 9", "unbekannte Art"); eq(S:NameOf("zone", 12), "Zone 12", "Zone über ZoneName")
    eq(S:AverageFlight("char"), 140, "Schnitt 420 s / 3 Flüge"); eq(S:AverageFlight("account"), 140, "Account")
end)

test("Anzeige: Gruppe Reisen, Einheiten, Schnitt der Flüge, Kampfzeit", function()
    local S, _, DB = stub.setup()
    local travel, combat = writers(DB)
    travel:Count("distance", 1, nil, 10936); travel:Count("traveltime", 1, nil, 3725)
    travel:Count("flight", 20006); travel:Count("flighttime", 20006, nil, 150)
    combat:Count("time", 0, nil, 600); combat:Count("looted", 299, 12, 3)

    local lines = text(S:OverviewLines())
    assert(lines:find("|cffffd100Travel|r", 1, true), lines)
    assert(lines:find("Distance travelled: 10.0 km", 1, true), "Strecke in km\n" .. lines)
    assert(lines:find("Time on the move: 1 h 2 min", 1, true), "Zeit")
    assert(lines:find("Average flight: 2 min", 1, true), "Schnitt")
    assert(lines:find("Time in combat: 10 min", 1, true) and lines:find("Corpses looted: 3", 1, true), "Kampf")

    local details = text(S:OverviewLines(true))
    assert(details:find("1. Walking: 10.0 km", 1, true), details)

    local verbose = text(S:VerboseLines("char"))
    assert(verbose:find("today 10.0 km · 7 days 10.0 km", 1, true), verbose)
    assert(verbose:find("Average flight: 2 min", 1, true), "Schnitt in verbose")
end)

test("API: Kampf und Reisen mit Einheiten und Flugschnitt", function()
    local S, _, DB = stub.setup()
    local travel, combat = writers(DB)
    travel:Count("distance", 2, nil, 2000); travel:Count("flightpoint", 2)
    travel:Count("flight", 20006, nil, 2); travel:Count("flighttime", 20006, nil, 200)
    combat:Count("time", 0, nil, 60)

    local r = S:Query({ topics = { "travel", "combat" }, breakdown = 3 })
    local t = r.topics.travel
    eq(t.hasData, true, "Daten"); eq(t.metrics.distance.unit, "yards", "Yards"); eq(t.metrics.distance.total, 2000, "Strecke")
    eq(t.metrics.distance.breakdown[1].id, 2, "nach Art"); eq(t.metrics.flightPoints.total, 1, "Flugpunkte")
    eq(t.metrics.flightTime.unit, "seconds", "Sekunden"); eq(t.derived.averageFlight.value, 100, "Schnitt")
    eq(r.topics.combat.metrics.time.total, 60, "Kampfzeit"); eq(r.topics.combat.metrics.looted.unit, "count", "Anzahl")
end)

test("Reisen ab Core 0.3.13: Teleports, Sprünge, Flugstrecke, Arten 6 bis 8", function()
    local S, _, DB = stub.setup()
    local travel = writers(DB)
    travel:Count("teleport", 0, nil, 3); travel:Count("jump", 0, nil, 250)
    travel:Count("flight", 20006); travel:Count("flightdistance", 20006, nil, 21872)
    travel:Count("distance", 8, nil, 900); travel:Count("distance", 6, nil, 100)

    eq(S:Get("travel.teleports"), 3, "Teleports"); eq(S:Get("jumps"), 250, "Sprünge")
    assert(table.concat(S:OverviewLines(), "\n"):find("|cffffd100Character|r\n  Jumps: 250", 1, true), "Sprünge in der Gruppe Charakter")
    eq(S:FormatValue("travel.flightdistance", S:Get("travel.flightdistance")), "20.0 km", "Flugstrecke als Strecke")
    local modes = S:GetBreakdown("travel.distance")
    eq(modes[1].name, "Deeprun Tram", "Art 8"); eq(modes[2].name, "Ship or zeppelin", "Art 6")
    eq(S:NameOf("mode", 7), "Under water", "Art 7")

    local t = S:Query({ topics = { "travel" } }).topics.travel
    eq(t.metrics.jumps, nil, "Sprünge nicht unter Reisen"); eq(t.metrics.flightDistance.unit, "yards", "API Flugstrecke")
    eq(S:Query({ topics = { "character" } }).topics.character.metrics.jumps.total, 250, "API Sprünge beim Charakter")
end)

test("Tiefenbahn: Strecke und Fahrzeit der Art 8, Aufenthalt in Instanz 369", function()
    local S, _, DB = stub.setup()
    local travel = writers(DB)
    travel:Count("distance", 8, nil, 1094); travel:Count("distance", 1, nil, 500)
    travel:Count("traveltime", 8, nil, 60); travel:Count("zonetime", -369, nil, 150); travel:Count("zonetime", 12, nil, 999)

    eq(S:Get("tram.distance"), 1094, "nur Art 8"); eq(S:Get("travel.distance"), 1594, "Reisen gesamt unverändert")
    eq(S:Get("tram.stay"), 150, "nur Instanz 369"); eq(S:GetSum("tram.time", "char", 7), 60, "Zeitraum")
    eq(#S:GetBreakdown("tram.distance"), 0, "keine Aufschlüsselung")
    local lines = table.concat(S:OverviewLines(), "\n")
    assert(lines:find("|cffffd100Deeprun Tram|r\n  Distance: 1.0 km", 1, true), lines)
    assert(lines:find("Riding time: 1 min", 1, true) and lines:find("Time spent: 2 min", 1, true), "Zeiten")

    S.messages = {}
    travel:Count("distance", 8, nil, 10)
    eq(S.messages[1][2], "travel.distance", "Änderung meldet den Reisezähler")
    eq(S:Query({ topics = { "tram" } }).topics.tram.metrics.stay.total, 150, "API")
end)

test("Tiefenbahn ab Core 0.3.21: Fahrten je Ziel, Fahrzeit fest 58 s je Fahrt in traveltime Art 8", function()
    local S, _, DB = stub.setup()
    local travel = writers(DB)
    travel:Count("tram", 1, nil, 2); travel:Count("tram", 2, nil, 2); travel:Count("tram", 0)
    travel:Count("traveltime", 8, nil, 5 * 58); travel:Count("distance", 8, nil, 900)

    eq(S:Get("tram.rides"), 5, "alle Fahrten sind die Summe von tram")
    local stops = S:GetBreakdown("tram.rides")
    eq(stops[1].name, "Stormwind", "Ziel 1"); eq(stops[2].name, "Ironforge", "Ziel 2"); eq(stops[3].name, "Unknown", "Ziel 0")
    eq(S:NameOf("tramstop", 3), "Stop 3", "unbekanntes Ziel")
    eq(S:Get("tram.time"), 290, "Fahrzeit aus traveltime Art 8")
    eq(S.counterByKey["tram.ridetime"], nil, "tramtime wird nicht mehr gelesen")

    local lines = table.concat(S:OverviewLines(), "\n")
    assert(lines:find("|cffffd100Deeprun Tram|r\n  Rides: 5", 1, true), lines)
    assert(lines:find("Riding time: 4 min", 1, true), "Fahrzeit")
    assert(not lines:find("Average ride", 1, true) and not lines:find("Ride time", 1, true), "keine Doppelung")
    local t = S:Query({ topics = { "tram" }, breakdown = 3 }).topics.tram
    eq(t.metrics.rides.total, 5, "API Fahrten"); eq(t.metrics.rides.breakdown[1].id, 1, "API je Ziel")
    eq(t.metrics.time.total, 290, "API Fahrzeit"); eq(t.metrics.rideTime, nil, "keine Fahrzeit je Ziel mehr"); eq(next(t.derived), nil, "kein Schnitt")
end)

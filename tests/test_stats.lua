-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Zähler pro Charakter und Account (Core/Statistics.lua), Anzeige (Core/Display/Display.lua) und Befehl (Commands/Stats.lua)
local function setup()
    local Glimpse = stub.newGlimpse()
    stub.load("Core/Statistics.lua", "Glimpse_Statistics")
    local S = Glimpse:GetModule("Statistics")
    -- Ersatz für AceDB: aktueller Charakter, Account und die rohe Tabelle aller Charaktere
    local me = { totals = {}, by = {} }
    local other = { totals = { kills = 7 }, by = {} }
    S.store = { char = me, global = { totals = {}, by = {} }, keys = { char = "Ich - Realm" },
        sv = { char = { ["Ich - Realm"] = me, ["Zweit - Realm"] = other } } }
    S.char, S.account = S.store.char, S.store.global
    S.registry, S.order = {}, {}
    stub.load("Core/Display/Display.lua", "Glimpse_Statistics")
    stub.load("Core/Display/Tooltip.lua", "Glimpse_Statistics")
    stub.load("Core/Options.lua", "Glimpse_Statistics")
    stub.load("Core/Collect/Collect.lua", "Glimpse_Statistics")
    stub.load("Core/Tiers.lua", "Glimpse_Statistics")
    stub.load("Core/Api.lua", "Glimpse_Statistics")
    stub.load("Core/Collect/Deaths.lua", "Glimpse_Statistics")
    stub.load("Core/Baseline/Blizzard.lua", "Glimpse_Statistics")
    stub.load("Core/Baseline/Baseline.lua", "Glimpse_Statistics")
    stub.load("Commands/Stats.lua", "Glimpse_Statistics")
    return S, Glimpse
end

test("Statistics: Zähler gelten für Charakter und Account", function()
    local S = setup()
    S:Add("fishing.casts")
    S:Add("fishing.casts", 4)
    eq(S:Get("fishing.casts"), 5, "Charakter")
    eq(S:Get("fishing.casts", "account"), 5, "Account")
    eq(S:Get("unbekannt"), 0, "unbekannter Zähler")
    eq(S:Get("kills", "Zweit - Realm"), 7, "anderer Charakter")
    eq(S:Get("kills", "Niemand - Realm"), 0, "unbekannter Charakter")
    eq(S.messages[1][1], "GLIMPSE_STATISTICS_UPDATED", "Nachricht")
end)

test("Statistics: ungültige Werte werden ignoriert, Negatives nimmt zurück, nie unter 0", function()
    local S = setup()
    S:Add(nil); S:Add(""); S:Add("x", 0); S:Add("x", 0 / 0)
    eq(S:Get("x"), 0, "nichts gezählt")
    S:Add("x", 3)
    S:Add("x", -1)
    eq(S:Get("x"), 2, "zurückgenommen")
    S:Add("x", -10)
    eq(S:Get("x"), 0, "nicht unter null")
    eq(S.account.totals.x, nil, "leere Zähler fallen weg")
end)

test("Statistics: Aufschlüsselung nach Schlüssel, größte zuerst", function()
    local S = setup()
    S:RegisterStat("kills", "Kills", { breakdown = true })
    S:Add("kills", 1, 100, "Wolf")
    S:Add("kills", 1, 200, "Bär")
    S:Add("kills", 1, 200, "Bär")
    S:Add("kills", 1) -- ohne Aufschlüsselung

    local list = S:GetBreakdown("kills")
    eq(#list, 2, "zwei Einträge")
    eq(list[1].name, "Bär", "größter zuerst"); eq(list[1].count, 2, "Zahl")
    eq(S:Get("kills"), 4, "Summe enthält alles")
    eq(#S:GetBreakdown("kills", "char", 1), 1, "limit")

    S:Add("kills", -1, 100)
    eq(#S:GetBreakdown("kills"), 1, "Eintrag bei 0 entfernt")
end)

test("Statistics: Name der Aufschlüsselung aus der Anmeldung", function()
    local S = setup()
    S:RegisterStat("fishing.casts", "Casts", { breakdown = true, name = function(map) return "Zone " .. map end })
    S:Add("fishing.casts", 1, 37)
    eq(S:GetBreakdown("fishing.casts")[1].name, "Zone 37", "aufgelöster Name")
    eq(setup():GetBreakdown("gibts.nicht")[1], nil, "leer")
end)

test("Statistics: die Aufschlüsselung bleibt unter der Obergrenze, die Summe nie", function()
    local S = setup()
    S.MAX_BREAKDOWN = 100
    local total = 0
    for id = 1, 400 do
        local n = id % 7 + 1
        total = total + n
        S:Add("kills", n, id)
    end
    local count = 0
    for _ in pairs(S.char.by.kills) do count = count + 1 end
    assert(count <= 150, "begrenzt, bekommen " .. count)
    eq(S:Get("kills"), total, "Summe bleibt vollständig")
end)

test("Statistics: Reset leert nur den gewählten Bereich", function()
    local S = setup()
    S:Add("kills", 2, 5, "Wolf")
    eq(S:Reset("char"), true, "Reset ok")
    eq(S:Get("kills"), 0, "Charakter leer"); eq(#S:GetBreakdown("kills"), 0, "Aufschlüsselung leer")
    eq(S:Get("kills", "account"), 2, "Account bleibt")
    S:Reset("account")
    eq(S:Get("kills", "account"), 0, "Account leer")
    eq(S:Reset("Zweit - Realm"), false, "andere Charaktere nicht")
end)

test("Statistics: Charaktere, aktueller zuerst", function()
    local S = setup()
    local list = S:GetCharacters()
    eq(list[1], "Ich - Realm", "aktueller zuerst")
    eq(list[2], "Zweit - Realm", "danach die anderen")
end)

test("Statistics: Anmeldung in der Reihenfolge, nochmal anmelden aktualisiert", function()
    local S = setup()
    S:RegisterStat("a", "Eins", { group = "G" })
    S:RegisterStat("b", "Zwei")
    S:RegisterStat("a", "Eins neu", { group = "G", breakdown = true })
    local list = S:GetRegistered()
    eq(#list, 2, "zwei Einträge"); eq(list[1].label, "Eins neu", "aktualisiert"); eq(list[1].breakdown, true, "Aufschlüsselung")
    eq(list[2].key, "b", "Reihenfolge")
end)

test("Statistics: Übersicht zeigt nur Zähler mit Wert, mit Gruppen und Tausendertrennung", function()
    local S = setup()
    S:RegisterStat("a", "Würfe", { group = "Angeln" })
    S:RegisterStat("b", "Ohne Wert", { group = "Angeln" })
    S:RegisterStat("c", "Kills", { group = "Kampf" })
    S:Add("a", 12345)
    S:Add("c", 2)
    local lines = S:OverviewLines()
    eq(#lines, 5, "Seit-Zeile und zwei Gruppen mit je einer Zeile")
    assert(lines[1]:find("Counting since", 1, true), "Seit-Zeile")
    assert(lines[3]:find("12 345", 1, true), "Tausendertrennung")
    assert(lines[3]:find("Account", 1, true), "Account in Klammern")
    assert(not table.concat(lines):find("Ohne Wert", 1, true), "Zähler ohne Wert fehlt")
end)

test("Statistics: Übersicht mit Schlüssel-Anfang (API 2) zeigt nur diese Zähler, mit der Seit-Zeile des Charakters", function()
    local S = setup()
    S:RegisterStat("fishing.casts", "Würfe", { group = "Angeln" })
    S:RegisterStat("kills", "Kills", { group = "Kampf" })
    S:Add("fishing.casts", 3)
    S:Add("kills", 2)
    eq(S.API_VERSION >= 2, true, "API 2")
    local lines = S:OverviewLines(false, true, "fishing.")
    eq(#lines, 3, "Seit-Zeile, Gruppe und ein Zähler")
    assert(lines[1]:find("Counting since", 1, true), "Seit-Zeile")
    assert(lines[3]:find("Würfe: 3", 1, true), "Zähler")
    assert(not table.concat(lines):find("Kills", 1, true), "fremder Zähler fehlt")
end)

test("Statistics: Zähler nach Berufsstufe, alte Werte zur niedrigsten Stufe, Fangquote je Stufe", function()
    local S = setup()
    local max = 75
    S.api.GetProfessions = function() return nil, nil, nil, 3 end
    S.api.GetProfessionInfo = function() return "Angeln", "icon", 10, max, 1, 0, 356 end
    S.api.GetSpellSubtext = function(id) return ({ [7620] = "Lehrling", [7731] = "Geselle" })[id] end
    S:RegisterStat("fishing.casts", "Würfe", { group = "Angeln" })
    S:RegisterStat("fishing.catches", "Fänge", { group = "Angeln" })

    -- von vor der Einführung: ohne Stufe
    S:Add("fishing.casts", 10); S:Add("fishing.catches", 6)
    eq(#S:GetTierCounts("fishing.casts", "char"), 0, "ohne Werte mit Stufe nichts")
    eq(#S:TierRateLines(), 0, "keine Stufenzeilen")

    -- Lehrling: 10 Würfe, 5 Fänge
    for _ = 1, 10 do S:Add("fishing.casts"); S:AddTier("fishing.casts", 1) end
    for _ = 1, 5 do S:Add("fishing.catches"); S:AddTier("fishing.catches", 1) end
    eq(#S:TierRateLines(), 0, "nur eine Stufe: keine Stufenzeilen")
    -- Geselle: 4 Würfe, 3 Fänge
    max = 150
    for _ = 1, 4 do S:Add("fishing.casts"); S:AddTier("fishing.casts", 1) end
    for _ = 1, 3 do S:Add("fishing.catches"); S:AddTier("fishing.catches", 1) end

    local tiers = S:GetTierCounts("fishing.casts", "char")
    eq(#tiers, 2, "zwei Stufen"); eq(tiers[1].name, "Lehrling", "Name aus dem Spiel"); eq(tiers[1].count, 20, "Lehrling: 10 alte + 10 neue")
    eq(tiers[2].name, "Geselle", "zweite Stufe"); eq(tiers[2].count, 4, "Geselle")
    eq(S:Get("fishing.casts"), 24, "Gesamtzahl bleibt")

    local lines = S:TierRateLines()
    eq(#lines, 2, "eine Zeile je Stufe")
    assert(lines[1]:find("Catch rate Lehrling: 55 %", 1, true), "Lehrling: 11 von 20")
    assert(lines[2]:find("Catch rate Geselle: 75 %", 1, true), "Geselle: 3 von 4")
    assert(table.concat(S:OverviewLines(false, true), "\n"):find("Catch rate Geselle", 1, true), "in der Übersicht")

    max = 225
    S.api.GetSpellSubtext = nil
    S:AddTier("fishing.casts", 1)
    eq(S:GetTierCounts("fishing.casts", "char")[3].name, "Skill up to 225", "ohne Zusatztext neutraler Name")
    S:AddTier("kills", 1)
    eq(S:Get("kills.tier"), 0, "nicht getrennte Zähler bleiben")
    S.api.GetProfessions = nil
    S:AddTier("fishing.casts", 1)
    eq(S:GetTierCounts("fishing.casts", "char")[3].count, 1, "ohne Stufe vom Client wird nichts getrennt")
end)

test("Statistics: Datenschnittstelle: feste Antwort für alle Themen, Auswahl, Stufen, Fangquote, nie ein Fehler", function()
    local S = setup()
    local max = 75
    S.api.GetProfessions = function() return nil, nil, nil, 3 end
    S.api.GetProfessionInfo = function() return "Angeln", "icon", 10, max, 1, 0, 356 end
    S.api.GetSpellSubtext = function(id) return ({ [7620] = "Lehrling", [7731] = "Geselle" })[id] end
    S:RegisterStat("fishing.casts", "Angelwürfe", {})

    local info = S:GetInfo()
    eq(info.api, S.API_VERSION, "API-Version"); eq(info.available, true, "lesbar"); eq(info.apiMin, 1, "ältester kompatibler Stand")
    local list = S:GetTopicList()
    eq(list[1].key, "fishing", "Angeln zuerst"); eq(list[1].label, "Angeln", "Name vom Client"); eq(list[1].kind, "profession", "Art"); eq(list[1].metrics[1], "casts", "Kennzahlen")
    eq(#S:GetTopicList("combat"), 2, "nach Art: kills und deaths"); eq(#S:GetTopicList("gibtsnicht"), 0, "unbekannte Art")

    local messages = {}
    S.SendMessage = function(_, message, ...) messages[#messages + 1] = { message, ... } end
    for _ = 1, 10 do S:Add("fishing.casts"); S:AddTier("fishing.casts", 1) end
    for _ = 1, 5 do S:Add("fishing.catches"); S:AddTier("fishing.catches", 1) end
    max = 150
    for _ = 1, 4 do S:Add("fishing.casts"); S:AddTier("fishing.casts", 1) end
    for _ = 1, 3 do S:Add("fishing.catches"); S:AddTier("fishing.catches", 1) end
    S:Add("kills", 2, 113, "Wolf"); S:Add("kills.area", 2, 1429, "Wald")
    eq(messages[1][2], "fishing.casts", "Nachricht: Zähler"); eq(messages[1][3], "fishing", "Nachricht: Thema"); eq(messages[1][4], "casts", "Nachricht: Kennzahl")
    eq(messages[#messages][3], "kills", "Kills sind ein Thema"); S:Add("irgendwas"); eq(messages[#messages][3], nil, "kein Thema bei fremden Zählern")

    local r = S:Query({ topics = { "fishing", "gibtsnicht" } })
    eq(r.ok, true, "ok"); eq(r.schema, 1, "Schema"); eq(r.scope, "char", "Standard: dieser Charakter"); eq(r.topics.herbalism, nil, "nur das gewünschte Thema")
    eq(r.unknown[1], "gibtsnicht", "unbekanntes Thema gemeldet"); eq(r.order[1], "fishing", "Reihenfolge")
    local fishing = r.topics.fishing
    eq(fishing.hasData, true, "Daten da"); eq(fishing.kind, "profession", "Art"); eq(fishing.metrics.casts.total, 14, "Würfe"); eq(fishing.metrics.casts.label, "Angelwürfe", "Name von Statistics")
    eq(fishing.metrics.casts.periods[1], 14, "heute"); eq(fishing.metrics.casts.periods[7], 14, "7 Tage")
    eq(fishing.derived.missed.value, 6, "ohne Fang"); eq(fishing.derived.missed.unit, "count", "Einheit"); eq(math.floor(fishing.derived.rate.value * 100 + 0.5), 57, "Quote gesamt (8 von 14)")
    eq(fishing.derived.rate.unit, "ratio", "Einheit der Quote"); eq(fishing.derived.rate.label, "Catch rate", "Beschriftung von Statistics")
    local rate = fishing.derived.rate.tiers
    eq(#rate, 2, "zwei Stufen"); eq(rate[1].name, "Lehrling", "Stufe"); eq(rate[1].denominator, 10, "Würfe der Stufe"); eq(rate[2].numerator, 3, "Fänge der Stufe")
    assert(r.labels.periods[1] == "today" and r.sinceText, "Beschriftung und Datum")

    -- gleiches Schema bei jedem Thema, auch ohne Werte und ohne Ableitungen
    local all = S:Query({ breakdown = 3 })
    for _, key in ipairs({ "fishing", "herbalism", "mining", "skinning", "kills", "deaths" }) do
        local topic = all.topics[key]
        assert(topic and topic.key == key and topic.kind and topic.label and type(topic.hasData) == "boolean" and type(topic.metrics) == "table" and type(topic.derived) == "table", key)
        for name, metric in pairs(topic.metrics) do
            assert(metric.label and type(metric.total) == "number" and type(metric.periods) == "table" and type(metric.tiers) == "table" and type(metric.breakdown) == "table", key .. "." .. name)
        end
    end
    eq(all.topics.herbalism.hasData, false, "ohne Werte"); eq(all.topics.kills.metrics.total.total, 2, "Kills")
    eq(all.topics.kills.metrics.total.breakdown[1].name, "Wolf", "Aufschlüsselung: Name"); eq(all.topics.kills.metrics.total.breakdown[1].count, 2, "Anzahl")
    eq(#S:Query().topics.kills.metrics.total.breakdown, 0, "ohne breakdown keine Einträge")
    eq(#S:Query({ kind = "combat" }).order, 2, "nur Kampf")
    eq(S:Query({ topics = "all", periods = { 30, "x", 0 }, tiers = false }).topics.fishing.metrics.casts.periods[30], 14, "Zeiträume, Unsinn wird übergangen")
    eq(#S:Query({ tiers = false }).topics.fishing.metrics.casts.tiers, 0, "ohne Stufen")
    eq(S:Query({ scope = "Niemand - Realm" }).topics.fishing.metrics.casts.total, 0, "unbekannter Charakter: 0 statt Fehler")
    eq(S:Query("Unsinn").ok, true, "falscher Typ der Abfrage")

    -- eigene Themen anderer Addons: dasselbe Schema
    eq(S:RegisterTopic("fishing", { metrics = { { name = "x", key = "x" } } }), false, "eingebaute Themen bleiben")
    eq(S:RegisterTopic("bad key", { metrics = {} }), false, "ungültiger Name")
    eq(S:RegisterTopic("pets", { kind = "collection", label = "Haustiere", metrics = { { name = "caught", key = "pets.caught", label = "Gefangen", breakdown = true } } }), true, "gemeldet")
    S:Add("pets.caught", 3, 7, "Hase")
    local pets = S:Query({ topics = { "pets" }, breakdown = 5 }).topics.pets
    eq(pets.label, "Haustiere", "Name"); eq(pets.kind, "collection", "Art"); eq(pets.metrics.caught.total, 3, "Wert"); eq(pets.metrics.caught.label, "Gefangen", "Beschriftung")
    eq(pets.metrics.caught.breakdown[1].name, "Hase", "Aufschlüsselung"); eq(next(pets.derived), nil, "keine abgeleiteten Zahlen"); eq(pets.hasData, true, "Daten")

    S.char = nil
    eq(S:Query().ok, false, "Datenbank nicht bereit: Antwort statt Fehler"); eq(S:GetInfo().available, false, "nicht lesbar")
end)

test("Statistics: Befehl zeigt Übersicht, Account und Aufschlüsselung", function()
    local S, Glimpse = setup()
    local run = Glimpse.commands.stats.func
    run(nil, "")
    eq(Glimpse.printed[1]:find("Nothing counted", 1, true) ~= nil, true, "noch nichts gezählt")

    S:RegisterStat("kills", "Kills", { breakdown = true })
    S:Add("kills", 3, 5, "Wolf")
    Glimpse.printed = {}
    run(nil, "")
    assert(Glimpse.printed[3]:find("Kills: 3", 1, true), "Übersicht")
    Glimpse.printed = {}
    run(nil, "account kills")
    assert(Glimpse.printed[1]:find("Kills: 3", 1, true), "Account-Summe")
    assert(Glimpse.printed[3]:find("Wolf", 1, true), "Aufschlüsselung")
    Glimpse.printed = {}
    run(nil, "gibtsnicht")
    assert(Glimpse.printed[1]:find("Unknown counter", 1, true), "unbekannter Zähler")
end)

test("Statistics: Zeitstempel: seit, erste und letzte Erfassung, Verlauf je Tag", function()
    local S, Glimpse = setup()
    local day1, day2 = 1760000000, 1760000000 + 86400 * 2
    local now = day1
    S.clock = function() return now end

    eq(S:GetSince(), nil, "vorher nichts")
    S:Add("kills", 2)
    S:Add("kills", 1)
    now = day2
    S:Add("kills", 4)
    S:Add("fishing.casts", 1)

    eq(S:GetSince(), day1, "seit dem ersten Zählen"); eq(S:GetSince("account"), day1, "Account auch")
    local first, last = S:GetFirst("kills")
    eq(first, day1, "erste Erfassung des Zählers"); eq(last, day2, "letzte Erfassung")
    eq(select(1, S:GetFirst("fishing.casts")), day2, "anderer Zähler beginnt später")

    local series = S:GetSeries("kills")
    eq(#series, 2, "zwei Tage"); eq(series[1].n, 3, "Tag 1 summiert"); eq(series[2].n, 4, "Tag 2")
    eq(series[1].day, S.DayKey(day1), "Tagesschlüssel"); eq(series[1].day < series[2].day, true, "aufsteigend")
    eq(#S:GetSeries("kills", "char", series[2].day), 1, "ab einem Tag")
    eq(#S:GetSeries("gibts.nicht"), 0, "leer")

    S:Add("kills", -1)
    eq(S:GetSeries("kills")[2].n, 3, "Rücknahme am heutigen Tag")

    -- Befehl
    local run = Glimpse.commands.stats.func
    S:RegisterStat("kills", "Kills")
    Glimpse.printed = {}
    run(nil, "kills days")
    assert(Glimpse.printed[1]:find("Kills: 6", 1, true), "Summe")
    assert(Glimpse.printed[2]:find("first", 1, true), "erste und letzte Erfassung")
    eq(#Glimpse.printed, 4, "Summe, Zeitspanne, zwei Tage")

    S:Reset("char")
    eq(S:GetSince(), nil, "Reset löscht auch den Zeitpunkt"); eq(#S:GetSeries("kills"), 0, "und den Verlauf")
    eq(S:GetSince("account"), day1, "Account bleibt")
end)

test("Statistics: der Verlauf behält höchstens 3660 Tage", function()
    local S = setup()
    local now = 1700000000
    S.clock = function() return now end
    for index = 1, 3700 do
        now = 1700000000 + index * 86400
        S:Add("x")
    end
    local series = S:GetSeries("x")
    eq(#series, 3660, "begrenzt"); eq(S:Get("x"), 3700, "Summe bleibt vollständig")
end)

test("Statistics: /gli stats status zeigt Zustand und Fehler", function()
    local S, Glimpse = setup()
    local run = Glimpse.commands.stats.func
    S.errorCount, S.lastError = 2, "LOOT_OPENED: kaputt"
    run(nil, "status")
    assert(Glimpse.printed[1]:find("Errors: 2", 1, true), "Fehlerzahl")
    assert(Glimpse.printed[2]:find("kaputt", 1, true), "letzter Fehler")
end)

test("Statistics: verbose gibt alle Informationen aus", function()
    local S, Glimpse = setup()
    local run = Glimpse.commands.stats.func
    S:RegisterStat("kills", "Kills", { group = "Kampf", breakdown = true })
    S:RegisterStat("fishing.casts", "Würfe", { group = "Angeln" })
    S:Add("kills", 3, 5, "Wolf")
    S:Add("kills", 1, 6, "Bär")
    S:Add("fishing.casts", 2)

    Glimpse.printed = {}
    run(nil, "verbose")
    local text = table.concat(Glimpse.printed, "\n")
    for _, part in ipairs({ "verbose", "Kills: 4", "Würfe: 2", "Wolf", "Bär", "first", "30 days", "Last days" }) do
        assert(text:find(part, 1, true), "enthält " .. part .. "\n" .. text)
    end

    -- mit Zähler: alle Einträge und 30 Tage
    Glimpse.printed = {}
    run(nil, "kills verbose")
    text = table.concat(Glimpse.printed, "\n")
    assert(text:find("Wolf", 1, true) and text:find("Bär", 1, true), "Aufschlüsselung")
    assert(text:find("Last days", 1, true), "Tage")

    Glimpse.printed = {}
    run(nil, "account verbose")
    assert(table.concat(Glimpse.printed, "\n"):find("Account", 1, true), "Account verbose")
end)

test("Statistics: Zeitstempel je Eintrag, im Debug-Modus mit grauen Rohdaten", function()
    local S, Glimpse = setup()
    local t1, t2 = 1760000000, 1760003600
    local now = t1
    S.clock = function() return now end
    S:RegisterStat("kills", "Kills", { group = "Kampf", breakdown = true })
    S:Add("kills", 2, 5, "Alter Schwarzbär")
    now = t2
    S:Add("kills", 1, 5)

    local entry = S:GetBreakdown("kills")[1]
    eq(entry.first, t1, "erste Zählung des Eintrags"); eq(entry.last, t2, "letzte Zählung"); eq(entry.storedName, "Alter Schwarzbär", "gespeicherter Name")

    -- ohne Debug: normale Übersicht ohne Rohdaten
    local run = Glimpse.commands.stats.func
    Glimpse.printed = {}
    run(nil, "")
    assert(not table.concat(Glimpse.printed, "\n"):find("Alter Schwarzbär", 1, true), "Übersicht ohne Einzelheiten")

    -- Debug: die normale Übersicht, dazu kompakte graue Rohdaten (Zeilen wie in der Datenbank)
    Glimpse.IsDebug = function() return true end
    Glimpse.printed = {}
    run(nil, "")
    local text = table.concat(Glimpse.printed, "\n")
    assert(not text:find("verbose", 1, true), "Debug erzwingt kein verbose")
    assert(text:find("|cff999999", 1, true), "graue Rohdaten")
    assert(text:find("by||kills||5||first=", 1, true) and text:find("||n=3||name=Alter Schwarzbär", 1, true), "Eintrag wie gespeichert\n" .. text)
    assert(text:find("||last=" .. t2 .. "||n=3", 1, true), "Zeit als Unix-Zeit, unverändert")

    Glimpse.printed = {}
    run(nil, "kills")
    text = table.concat(Glimpse.printed, "\n")
    assert(text:find("||n=3||name=Alter Schwarzbär", 1, true), "auch mit Zähler")
end)

test("Statistics: debug gibt die Datenbank kompakt und grau aus", function()
    local S, Glimpse = setup()
    local run = Glimpse.commands.stats.func
    S.clock = function() return 1760000000 end
    S:RegisterStat("kills", "Kills", { breakdown = true })
    for id = 1, 8 do S:Add("kills", id, id, "Tier" .. id) end
    S:Add("ohne.anmeldung", 2)

    Glimpse.printed = {}
    run(nil, "debug")
    local text = table.concat(Glimpse.printed, "\n")
    assert(text:find("|cff999999", 1, true), "grau")
    assert(text:find("totals||kills||36", 1, true), "Summe")
    assert(text:find("since||1760000000", 1, true), "since")
    assert(text:find("first||kills||1760000000", 1, true) and text:find("last||kills||1760000000", 1, true), "erste und letzte Zeit")
    assert(text:find("by||kills||8||first=1760000000||last=1760000000||n=8||name=Tier8", 1, true), "größter Eintrag mit allen Feldern")
    assert(not text:find("name=Tier1", 1, true), "nur die ersten fünf")
    assert(text:find("totals||ohne.anmeldung||2", 1, true), "auch Zähler ohne Anmeldung")
    assert(text:find("days||kills||", 1, true) and text:find("||36", 1, true), "Tag")
    eq(S:GetBreakdown("kills")[1].time, 1760000000, "Eintrag trägt seinen Zeitpunkt")
end)

test("Statistics: debug mit verbose zeigt alle Einträge, ohne Debug-Modus nur mit dem Wort debug", function()
    local S, Glimpse = setup()
    local run = Glimpse.commands.stats.func
    S.clock = function() return 1760000000 end
    S:RegisterStat("kills", "Kills", { breakdown = true })
    for id = 1, 8 do S:Add("kills", id, id, "Tier" .. id) end

    -- ohne Debug-Modus und ohne das Wort: keine Rohdaten
    Glimpse.printed = {}
    run(nil, "")
    assert(not table.concat(Glimpse.printed, "\n"):find("by||kills", 1, true), "keine Rohdaten ohne Debug")

    -- Debug + verbose: alle acht Einträge
    Glimpse.IsDebug = function() return true end
    Glimpse.printed = {}
    run(nil, "verbose")
    local text = table.concat(Glimpse.printed, "\n")
    assert(text:find("name=Tier1", 1, true), "auch der kleinste Eintrag")
    assert(text:find("name=Tier8", 1, true), "und der größte")

    -- nur ein Zähler, Account
    Glimpse.printed = {}
    run(nil, "account debug kills")
    text = table.concat(Glimpse.printed, "\n")
    assert(text:find("name=Tier8", 1, true), "account debug <Zähler>")
    assert(not text:find("name=Tier1", 1, true), "nur die ersten fünf")
end)

test("Statistics: GetSub liefert den Eintrag der Aufschlüsselung", function()
    local S = setup()
    S:Add("kills", 2, 113, "Wildschwein")
    local n, first, last = S:GetSub("kills", 113)
    eq(n, 2, "Zahl")
    eq(first ~= nil and last ~= nil, true, "Zeiten")
    eq(S:GetSub("kills", 1), 0, "unbekannt")
    eq(S:GetSub("nichts", 113, "account"), 0, "unbekannter Zähler")
end)

test("Statistics: Tooltip-Handler wird für Einheiten angemeldet", function()
    local S = setup()
    eq(S:RegisterTooltips(), false, "ohne Tooltip-Schnittstelle")

    _G.Enum = { TooltipDataType = { Unit = 2 } }
    local got
    S.RegisterTooltip = function(self, dataType, provider) got = { self, dataType, provider } end
    eq(S:RegisterTooltips(), true, "angemeldet")
    _G.Enum = nil
    eq(got[2], 2, "Typ Einheit")
    eq(got[3], "UnitTooltipHandler", "Handler")
end)

test("Statistics: Übersicht nur für den Charakter, ohne Account", function()
    local S = setup()
    S:RegisterStat("kills", "Kills", { group = "Kampf" })
    S:Add("kills", 3)
    S.account.totals.kills = 10 -- Account-Zähler (andere Charaktere)
    S:RegisterStat("fishing.casts", "Würfe", { group = "Angeln" })
    S.account.totals["fishing.casts"] = 4 -- nur im Account
    S.account.since = nil

    local all = table.concat(S:OverviewLines(), "\n")
    assert(all:find("Kills: 3", 1, true) and all:find("Account: 10", 1, true), all)
    assert(all:find("Würfe", 1, true), "Zähler nur im Account steht in der Gesamtübersicht")

    local mine = table.concat(S:OverviewLines(false, true), "\n")
    assert(mine:find("Kills: 3", 1, true), mine)
    eq(mine:find("Account", 1, true), nil, "kein Account")
    eq(mine:find("Würfe", 1, true), nil, "Zähler nur im Account fehlt")
end)

-- Ein Rahmen, der Aufrufe nur festhält (unbekannte Methoden tun nichts)
local function fakeFrame(kind, name)
    local f = { kind = kind, name = name, scripts = {}, shown = false, points = {}, alpha = 1, state = {}, width = 200, height = 100 }
    setmetatable(f, { __index = function() return function() end end })
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetScript(event, func) self.scripts[event] = func end
    function f:HookScript(event, func) self.state.hooks = self.state.hooks or {} self.state.hooks[event] = func end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:SetAlpha(alpha) self.alpha = alpha end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:GetPoint() local p = self.points[1] return p and p[1], nil, p and p[3], p and p[4], p and p[5] end
    function f:StartMoving() self.state.moving = true end
    function f:StartSizing(corner) self.state.sizing = corner end
    function f:StopMovingOrSizing() self.state.moving, self.state.sizing = false, nil end
    function f:SetScrollChild() end
    function f:SetVerticalScroll(value) self.state.scroll = value end
    function f:GetVerticalScroll() return self.state.scroll or 0 end
    function f:CreateFontString()
        local fs = { state = {} }
        _G.fakeTexts[#_G.fakeTexts + 1] = fs
        setmetatable(fs, { __index = function() return function() end end })
        function fs:SetText(text) self.state.text = text end
        function fs:SetFont(path, size, flags) self.state.font = { path, size, flags } end
        function fs:GetStringWidth() return self.state.text and #self.state.text or 0 end
        function fs:GetStringHeight() return self.state.height or 12 end
        return fs
    end
    if name then _G[name] = f end
    return f
end

-- Ein AceGUI, das seine Widgets nur festhält
local function fakeAceGUI()
    local gui = { created = {} }
    function gui:Create(kind)
        local w = { kind = kind, state = {}, layouts = 0 }
        setmetatable(w, { __index = function() return function() end end })
        function w:SetTitle(text) self.state.title = text end
        function w:SetStatusTable(status) self.state.status = status end
        function w:SetText(text) self.state.text = text end
        function w:SetFont(path, size) self.state.font = { path, size } end
        function w:DoLayout() self.layouts = self.layouts + 1 end
        w.frame = fakeFrame("AceFrame")
        w.closebutton = fakeFrame("Button")
        gui.created[#gui.created + 1] = w
        return w
    end
    return gui
end

local function setupWindow()
    local S, Glimpse = setup()
    local frames, gui = {}, fakeAceGUI()
    _G.CreateFrame = function(kind, name)
        local f = fakeFrame(kind, name)
        frames[#frames + 1] = f
        return f
    end
    local libStub = _G.LibStub
    _G.LibStub = function(name, ...) if name == "AceGUI-3.0" then return gui end return libStub(name, ...) end
    _G.fakeTexts = {}
    _G.UIParent = {}
    _G.UISpecialFrames = {}
    _G.GameFontHighlight = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
    _G.C_Timer = { After = function(_, func) func() end }
    stub.load("Core/Display/Window.lua", "Glimpse_Statistics")
    S:RegisterStat("kills", "Kills", {})
    return S, Glimpse, frames, gui
end

local function cleanWindow()
    _G.UISpecialFrames, _G.GlimpseStatisticsWindow, _G.C_Timer, _G.UIParent, _G.GameFontHighlight, _G.fakeTexts = nil, nil, nil, nil, nil, nil
end

test("Statistics: Fenster ohne Rahmen öffnen, schließen, Text wie die Übersicht, nie bei Escape", function()
    local S, _, frames, gui = setupWindow()
    S:Add("kills", 3)
    S.account.totals.kills = 10

    eq(S:ToggleWindow(), true, "öffnet")
    local frame = frames[1]
    eq(frame.name, "GlimpseStatisticsWindow", "Name")
    eq(#gui.created, 0, "ohne Rahmen kein AceGUI-Fenster")
    eq(#_G.UISpecialFrames, 0, "nicht bei Escape (sonst schließt es mit dem Optionenmenü)")
    eq(frame.points[1][1], "TOPLEFT", "Standardposition")
    assert(frame.width >= 100 and frame.height >= 25, "Größe nach dem Text")
    eq(S.char.windowSize, nil, "eine eigene Größe gibt es erst nach dem Ändern")
    eq(S:IsWindowOpen(), true, "offen")

    eq(S:ToggleWindow(), false, "schließt")
    eq(frame.shown, false, "versteckt")
    eq(S:ToggleWindow(true), true, "öffnet wieder")
    eq(#frames, 5, "dasselbe Fenster, nicht neu gebaut (Rahmen, Scrollbereich, Inhalt, x und Griff)")
    eq(S:ToggleWindow(false), false, "false schließt")
    cleanWindow()
end)

test("Statistics: Schriftgröße einstellbar und begrenzt", function()
    local S = setupWindow()
    eq(S:WindowFontSize(), 12, "Standard")
    S.account.windowFontSize = 16; eq(S:WindowFontSize(), 16, "16")
    S.account.windowFontSize = 3; eq(S:WindowFontSize(), 8, "nicht kleiner als 8")
    S.account.windowFontSize = 99; eq(S:WindowFontSize(), 24, "nicht größer als 24")
    S.account.windowFontSize = "x"; eq(S:WindowFontSize(), 12, "Unsinn: Standard")
    cleanWindow()
end)

test("Statistics: Schrift im Fenster ohne Rahmen und mit Rahmen", function()
    local S, _, frames, gui = setupWindow()
    S.account.windowFontSize = 18
    S:ToggleWindow(true)
    -- die Textfelder des Fensters ohne Rahmen
    for _, f in ipairs(frames) do
        local fs = f:CreateFontString()
        assert(fs, "Textfeld")
    end
    S.account.windowFrame = true
    S:ApplyWindowStyle()
    local label = gui.created[3]
    eq(label.state.font[2], 18, "Schriftgröße im Fenster mit Rahmen")
    eq(label.state.font[1], "Fonts\\FRIZQT__.TTF", "Schriftart der Spielschrift")
    S.account.windowFontSize = 10
    S:RefreshWindow()
    eq(label.state.font[2], 10, "neue Größe sofort")
    cleanWindow()
end)

test("Statistics: ohne Rahmen verschieben, Größe ändern, Position und Größe merken, x und rechte Maustaste schließen", function()
    local S, _, frames = setupWindow()
    S:ToggleWindow(true)
    local frame, close, grip = frames[1], nil, nil
    -- Knöpfe in der Reihenfolge ihrer Erstellung: x, dann Griff
    for _, f in ipairs(frames) do
        if f.kind == "Button" then if not close then close = f else grip = f end end
    end
    assert(close and grip, "x und Griff")

    frame.scripts.OnDragStart(frame)
    eq(frame.state.moving, true, "wird verschoben")
    frame.points = { { "TOPLEFT", frame, "TOPLEFT", 120, -300 } }
    frame.scripts.OnDragStop(frame)
    eq(frame.state.moving, false, "Verschieben beendet")
    eq(S.char.windowPos.x, 120, "Position gemerkt")

    grip.scripts.OnMouseDown(grip)
    eq(frame.state.sizing, "BOTTOMRIGHT", "Größe ändern")
    frame.width, frame.height = 333, 222
    grip.scripts.OnMouseUp(grip)
    eq(frame.state.sizing, nil, "beendet")
    eq(S.char.windowSize.width, 333, "Breite gemerkt"); eq(S.char.windowSize.height, 222, "Höhe gemerkt")

    frame.scripts.OnMouseUp(frame, "LeftButton")
    eq(frame.shown, true, "linke Maustaste schließt nicht")
    frame.scripts.OnMouseUp(frame, "RightButton")
    eq(frame.shown, false, "rechte Maustaste schließt")

    S:ToggleWindow(true)
    close.scripts.OnEnter(close); eq(close.alpha, 1, "x wird sichtbar")
    close.scripts.OnLeave(close); assert(close.alpha < 1, "x wieder blass")
    close.scripts.OnClick(close)
    eq(frame.shown, false, "x schließt")

    -- nach dem Neuladen: gemerkte Position und Größe
    local S2, _, frames2 = setupWindow()
    S2.char.windowPos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 120, y = -300 }
    S2.char.windowSize = { width = 333, height = 222 }
    S2:ToggleWindow(true)
    eq(frames2[1].points[1][4], 120, "Position wiederhergestellt")
    eq(frames2[1].width, 333, "Breite wiederhergestellt"); eq(frames2[1].height, 222, "Höhe wiederhergestellt")
    cleanWindow()
end)

test("Statistics: Rahmen zeigen nutzt das normale Fenster (AceGUI), Wechsel im laufenden Betrieb", function()
    local S, _, frames, gui = setupWindow()
    S:ToggleWindow(true)
    local plainFrame = frames[1]
    eq(plainFrame.shown, true, "ohne Rahmen offen")
    eq(#gui.created, 0, "noch kein AceGUI-Fenster")

    S.account.windowFrame = true
    S:ApplyWindowStyle()
    eq(plainFrame.shown, false, "der Text-Rahmen verschwindet")
    local frame, scroll, label = gui.created[1], gui.created[2], gui.created[3]
    eq(frame.kind, "Frame", "Fenster mit Titelleiste"); eq(scroll.kind, "ScrollFrame", "Scrollbereich"); eq(label.kind, "Label", "Text")
    eq(frame.frame.shown, true, "sofort sichtbar")
    eq(frame.state.status, S.char.windowStatus, "Position und Größe im Account")
    eq(label.state.text, S:WindowText(), "dieselbe Übersicht wie die Optionen")
    eq(#_G.UISpecialFrames, 0, "nicht bei Escape")

    eq(S:ToggleWindow(), false, "schließt")
    eq(frame.frame.shown, false, "versteckt")
    eq(S:ToggleWindow(true), true, "öffnet im Rahmen")
    eq(#gui.created, 3, "nicht neu gebaut")

    S.account.windowFrame = false
    S:ApplyWindowStyle()
    eq(frame.frame.shown, false, "Rahmenfenster verschwindet")
    eq(plainFrame.shown, true, "Text-Rahmen wieder da")

    -- geschlossen: Umschalten öffnet nichts
    S:ToggleWindow(false)
    S.account.windowFrame = true
    S:ApplyWindowStyle()
    eq(S:IsWindowOpen(), false, "bleibt geschlossen")
    cleanWindow()
end)

test("Statistics: Fenster zeigt nur den Charakter, wenn eingestellt, und aktualisiert sich", function()
    local S = setupWindow()
    S:Add("kills", 3)
    S.account.totals.kills = 10
    eq(S:WindowScope(), "all", "Standard: alles")
    assert(S:WindowText():find("Account: 10", 1, true), S:WindowText())

    S.account.windowScope = "char"
    eq(S:WindowScope(), "char", "nur Charakter")
    assert(not S:WindowText():find("Account", 1, true), S:WindowText())

    -- Änderung der Zähler aktualisiert das offene Fenster (ohne Fehler), geschlossen passiert nichts
    S:ToggleWindow(true)
    S:Add("kills", 2)
    S:OnCountersChanged()
    assert(S:WindowText():find("Kills: 5", 1, true), S:WindowText())
    S:ToggleWindow(false)
    S:OnCountersChanged()

    -- nichts gezählt: Hinweistext
    S.char.totals, S.char.by, S.account.totals, S.account.by = {}, {}, {}, {}
    S.char.since, S.account.since = nil, nil -- wie nach dem Zurücksetzen
    eq(S:WindowText(), "No data has been collected for this character yet.", "Hinweis: Charakter ohne Daten")
    S.account.windowScope = "all"
    eq(S:WindowText(), "No data has been collected yet.", "Hinweis: gar keine Daten")
    S.account.windowScope = "char"

    -- nur Charakter, der Charakter hat nichts, der Account schon
    S.account.totals.kills = 4
    S.account.since = 1
    eq(S:WindowScope(), "char", "nur Charakter")
    eq(S:WindowText(), "No data has been collected for this character yet.", "Hinweis: Charakter ohne Daten")
    S.account.windowScope = "all"
    assert(S:WindowText():find("Account: 4", 1, true), S:WindowText())
    cleanWindow()
end)

test("Statistics: Optionen haben die Tabs Optionen und Fenster, die Einstellungen gelten für das Fenster", function()
    local S, _, frames, gui = setupWindow()
    local options = S:BuildOptions()
    eq(options.options.type, "group", "Tab Optionen")
    assert(options.options.args.overview and options.options.args.tooltip and options.options.args.reset, "bisheriger Inhalt")
    eq(options.window.type, "group", "Tab Fenster")

    local scope = options.window.args.scope
    eq(scope.get(), "all", "Standard")
    scope.set(nil, "char")
    eq(S.account.windowScope, "char", "gespeichert")
    scope.set(nil, "unsinn")
    eq(S.account.windowScope, "all", "Unbekanntes wird zu alles")

    local size = options.window.args.fontSize
    eq(size.type, "range", "Regler"); eq(size.min, 8, "Minimum"); eq(size.max, 24, "Maximum")
    eq(size.get(), 12, "Standard")
    size.set(nil, 15)
    eq(S.account.windowFontSize, 15, "Schriftgröße gespeichert")

    local border = options.window.args.frame
    eq(border.get(), false, "Rahmen standardmäßig aus")
    options.window.args.open.func()
    eq(frames[1].shown, true, "Knopf öffnet das Fenster")
    border.set(nil, true)
    eq(S.account.windowFrame, true, "Rahmen gespeichert")
    eq(frames[1].shown, false, "Text-Rahmen weg"); eq(gui.created[1].frame.shown, true, "Fenster mit Rahmen sofort sichtbar")
    border.set(nil, false)
    eq(gui.created[1].frame.shown, false, "Fenster mit Rahmen weg"); eq(frames[1].shown, true, "Text wieder da")
    cleanWindow()
end)

test("Statistics: Position und Größe zurücksetzen (beide Aussehen)", function()
    local S, _, frames = setupWindow()
    S.char.windowStatus = {} -- (im Spiel der Standardwert aus AceDB)
    S.char.windowPos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 500, y = -50 }
    S.char.windowSize = { width = 700, height = 600 }
    S:ToggleWindow(true)
    local frame = frames[1]
    eq(frame.width, 700, "gemerkte Größe")

    S:ResetWindowLayout()
    eq(S.char.windowPos, nil, "Position vergessen"); eq(S.char.windowSize, nil, "Größe vergessen")
    eq(S:IsWindowOpen(), true, "bleibt offen")
    eq(frame.points[1][4], 40, "Standardposition"); assert(frame.width < 700, "Größe nach dem Text")

    -- mit Rahmen: der Status des Fensters wird geleert
    S.account.windowFrame = true
    S:ApplyWindowStyle()
    S.char.windowStatus.width, S.char.windowStatus.top = 800, 100
    S:ResetWindowLayout()
    eq(next(S.char.windowStatus), nil, "Status geleert")
    eq(S:IsWindowOpen(), true, "bleibt offen")
    cleanWindow()
end)

test("Statistics: das Fenster schließt sich nicht von selbst", function()
    local S, _, frames, gui = setupWindow()
    S:ToggleWindow(true)
    -- Escape (CloseSpecialWindows) wirkt nur auf UISpecialFrames, dort steht das Fenster nicht
    for _, name in ipairs(_G.UISpecialFrames) do _G[name]:Hide() end
    eq(frames[1].shown, true, "Escape schließt es nicht")
    S.account.windowFrame = true
    S:ApplyWindowStyle()
    for _, name in ipairs(_G.UISpecialFrames) do _G[name]:Hide() end
    eq(gui.created[1].frame.shown, true, "auch mit Rahmen nicht")
    cleanWindow()
end)

test("Statistics: ist der Text länger als das Fenster, scrollt das Mausrad", function()
    local S, _, frames = setupWindow()
    S:Add("kills", 3)
    S:ToggleWindow(true)
    local frame, scroll = frames[1], frames[2]
    eq(scroll.kind, "ScrollFrame", "Scrollbereich")
    assert(frame.scripts.OnMouseWheel, "Mausrad im Fenster")

    -- den Text des Fensters finden (er steht im Inhalt des Scrollbereichs)
    local text
    for _, fs in ipairs(_G.fakeTexts) do if fs.state.text == S:WindowText() then text = fs end end
    assert(text, "Textfeld")

    -- Text passt: nichts zu scrollen
    text.state.height = 40; scroll.height = 100
    frame.scripts.OnMouseWheel(frame, -1)
    eq(scroll:GetVerticalScroll(), 0, "passt ins Fenster")

    -- Text höher als das Fenster: nach unten (delta < 0) scrollen, begrenzt auf das Ende
    text.state.height = 300; scroll.height = 100
    frame.scripts.OnMouseWheel(frame, -1)
    eq(scroll:GetVerticalScroll(), S:WindowFontSize() * 3, "ein Schritt nach unten")
    for _ = 1, 50 do frame.scripts.OnMouseWheel(frame, -1) end
    eq(scroll:GetVerticalScroll(), 200, "höchstens bis zum Ende des Textes")
    frame.scripts.OnMouseWheel(frame, 1)
    eq(scroll:GetVerticalScroll(), 200 - S:WindowFontSize() * 3, "nach oben")
    for _ = 1, 50 do frame.scripts.OnMouseWheel(frame, 1) end
    eq(scroll:GetVerticalScroll(), 0, "nicht über den Anfang")

    -- geschlossen: das Mausrad tut nichts
    S:ToggleWindow(false)
    S:ScrollWindow(-1)
    eq(scroll:GetVerticalScroll(), 0, "geschlossen")
    cleanWindow()
end)

test("Statistics: das Fenster merkt sich je Charakter, ob es offen war, und kommt wieder", function()
    local S = setupWindow()
    eq(S.char.windowOpen, nil, "Standard: nichts gemerkt")
    S:RestoreWindow()
    eq(S:IsWindowOpen(), false, "bleibt zu")

    S:ToggleWindow(true)
    eq(S.char.windowOpen, true, "offen gemerkt")

    -- /reload: neues Fenster, dieselben Charakterdaten
    local char = S.char
    cleanWindow()
    local S2, _, frames2, gui2 = setupWindow()
    S2.char = char
    S2:RestoreWindow()
    eq(S2:IsWindowOpen(), true, "nach dem Neuladen wieder offen")

    -- das Spiel versteckt das Fenster (Alt+Z): gemerkt bleibt offen
    frames2[1].shown = false
    eq(S2.char.windowOpen, true, "Verstecken durch das Spiel ändert nichts")

    -- rechte Maustaste schließt für immer
    S2:ToggleWindow(true)
    frames2[1].scripts.OnMouseUp(frames2[1], "RightButton")
    eq(S2.char.windowOpen, false, "rechte Maustaste: gemerkt")

    -- Schließen über den Befehl
    S2:ToggleWindow(true)
    S2:ToggleWindow(false)
    eq(S2.char.windowOpen, false, "Befehl: gemerkt")

    -- mit Rahmen: der Schließen-Knopf
    S2.account.windowFrame = true
    S2:ToggleWindow(true)
    eq(S2.char.windowOpen, true, "mit Rahmen offen")
    gui2.created[1].closebutton.state.hooks.OnClick()
    eq(S2.char.windowOpen, false, "Schließen-Knopf gemerkt")
    cleanWindow()
end)

test("Statistics: Position und Größe der alten Account-Daten übernimmt der Charakter einmal", function()
    local S = setupWindow()
    S.account.windowPos = { point = "CENTER", relPoint = "CENTER", x = 5, y = 6 }
    S.account.windowSize = { width = 300, height = 200 }
    S:RestoreWindow()
    eq(S.char.windowPos.x, 5, "Position übernommen")
    eq(S.char.windowSize.width, 300, "Größe übernommen")
    eq(S.account.windowPos, nil, "Account-Wert entfernt")
    cleanWindow()
end)

-- Gegner, die den Spieler angreifen: unit -> { guid, name } (Ziel zeigt auf "player")
local function setupDeaths(enemies)
    local S = setup()
    local now = 100
    local api = S.api
    api.GetTime = function() return now end
    api.UnitExists = function(unit) return enemies[unit] ~= nil end
    api.UnitGUID = function(unit) return enemies[unit] and enemies[unit].guid end
    api.UnitName = function(unit) return enemies[unit] and enemies[unit].name end
    api.UnitCanAttack = function() return true end
    api.UnitIsDead = function() return false end
    api.UnitIsUnit = function(unit) return unit:sub(-6) == "target" and enemies[unit:sub(1, -7)] ~= nil end
    return S, function(t) now = t end
end

test("Statistics: ein Tod wird gezählt, der Angreifer zuletzt gilt als Verursacher", function()
    local enemies = { nameplate1 = { guid = "Creature-0-1-2-3-500-0000A", name = "Wolf" } }
    local S, setNow = setupDeaths(enemies)

    S.deathFrame.scripts.OnEvent(nil, "UNIT_HEALTH") -- im Kampf gesehen
    setNow(104)
    enemies.nameplate1 = nil
    enemies.nameplate2 = { guid = "Creature-0-1-2-3-600-0000B", name = "Bär" }
    S.deathFrame.scripts.OnEvent(nil, "UNIT_HEALTH")
    setNow(105)
    S.deathFrame.scripts.OnEvent(nil, "PLAYER_DEAD")

    eq(S:Get("deaths"), 1, "ein Tod")
    eq(S:GetSub("deaths", 600), 1, "der Bär (zuletzt gesehen)")
    eq(S:GetSub("deaths", 500), 0, "nicht der Wolf")
    eq(S:GetBreakdown("deaths")[1].name, "Bär", "Name")

    -- ein zweites Ereignis kurz danach zählt nicht doppelt
    S.deathFrame.scripts.OnEvent(nil, "PLAYER_DEAD")
    eq(S:Get("deaths"), 1, "nicht doppelt")
end)

test("Statistics: Tod ohne lesbaren Angreifer zählt nur gesamt; Spieler und Freunde sind keine Verursacher", function()
    local enemies = { target = { guid = "Player-1-0000ABCD", name = "Spieler" } }
    local S, setNow = setupDeaths(enemies)
    S.deathFrame.scripts.OnEvent(nil, "PLAYER_DEAD")
    eq(S:Get("deaths"), 1, "gezählt")
    eq(#S:GetBreakdown("deaths"), 0, "kein Verursacher")

    -- der Angreifer war zu lange nicht zu sehen
    setNow(200)
    enemies.target = { guid = "Creature-0-1-2-3-700-0000C", name = "Alt" }
    S.deathFrame.scripts.OnEvent(nil, "UNIT_HEALTH")
    setNow(300)
    enemies.target = nil
    S.deathFrame.scripts.OnEvent(nil, "PLAYER_DEAD")
    eq(S:Get("deaths"), 2, "zweiter Tod")
    eq(S:GetSub("deaths", 700), 0, "veraltet")

    -- ausgeschaltet: nichts zählen
    S.account.collect = false
    setNow(400)
    S.deathFrame.scripts.OnEvent(nil, "PLAYER_DEAD")
    eq(S:Get("deaths"), 2, "Sammlung aus")
end)

test("Statistics: im Moment des Todes zählt die Prüfung aus dem Kampf, nicht wer dann noch zu sehen ist", function()
    local enemies = {
        target = { guid = "Creature-0-1-2-3-800-0000D", name = "Schneeleopard" },
        nameplate1 = { guid = "Creature-0-1-2-3-1126-0000E", name = "Eber" },
    }
    local S, setNow = setupDeaths(enemies)
    S.deathFrame.scripts.OnEvent(nil, "UNIT_COMBAT") -- beide greifen an, das Ziel kommt zuerst
    setNow(103)
    enemies.target = nil -- Tod: das Ziel ist weg, der Eber steht noch da
    S.deathFrame.scripts.OnEvent(nil, "PLAYER_DEAD")
    eq(S:GetSub("deaths", 800), 1, "Schneeleopard")
    eq(S:GetSub("deaths", 1126), 0, "nicht der Eber")
end)

local KILL = "|TInterface\\CURSOR\\Attack:12|t"
local DEATH = "|A:poi-graveyard-neutral:14:14|a"
local GUID113 = "Creature-0-6782-0-21-113-000045F296"

test("Statistics: Text der Kreatur: Kills hellgrau, Tode rot, Account dunkler in Klammern", function()
    local S = setup()
    S:Add("kills", 3, 113, "Wildschwein")
    S.account.totals.kills = S.account.totals.kills + 4
    S.account.by.kills[113].n = 7
    S:Add("deaths", 1, 113, "Wildschwein")
    S.account.totals.deaths = S.account.totals.deaths + 2
    S.account.by.deaths[113].n = 3

    eq(S:CreatureCounterText(113), KILL .. " |cffd0d0d03|r|cffffffff · |r" .. DEATH .. " |cffff55551|r", "ohne Account")
    S.account.tooltipAccount = true
    eq(S:CreatureCounterText(113),
        KILL .. " |cffd0d0d03|r|cff808080(7)|r|cffffffff · |r" .. DEATH .. " |cffff55551|r|cff994040(3)|r", "mit Account")

    S.account.tooltipDeaths = false
    eq(S:CreatureCounterText(113), KILL .. " |cffd0d0d03|r|cff808080(7)|r", "nur Kills")
    S.account.tooltipDeaths, S.account.tooltipKills = true, false
    eq(S:CreatureCounterText(113), DEATH .. " |cffff55551|r|cff994040(3)|r", "nur Tode")
    S.account.tooltipKills = true
    eq(S:CreatureCounterText(999), nil, "unbekannte Kreatur: nichts")
end)

test("Statistics: Tooltip: Option Account", function()
    local S = setup()
    S:Add("deaths", 1, 113, "Wildschwein")
    S.account.by.deaths[113].n = 4
    eq(S:CreatureCounterText(113), DEATH .. " |cffff55551|r", "Standard: ohne Account")
    S.account.tooltipAccount = true
    eq(S:ShowsTooltipAccount(), true, "an")
    eq(S:CreatureCounterText(113), DEATH .. " |cffff55551|r|cff994040(4)|r", "mit Account")
end)

test("Statistics: Beispiel für die Optionen und Standardwerte", function()
    local S = setup()
    eq(S:ShowsTooltipAccount(), false, "Account standardmäßig aus")
    eq(S:TooltipKillsMode(), "name", "Standard: neben dem Namen")
    eq(S:ExampleCounterText(), KILL .. " |cffd0d0d03|r|cffffffff · |r" .. DEATH .. " |cffff55551|r", "Beispiel ohne Account")
    S.account.tooltipAccount = true
    eq(S:ExampleCounterText(), KILL .. " |cffd0d0d03|r|cff808080(7)|r|cffffffff · |r" .. DEATH .. " |cffff55551|r|cff994040(3)|r", "mit Account")

    local text = S:BuildOptions().options.args.tooltip.args.example.name()
    assert(text:find("Example:", 1, true) and text:find(KILL, 1, true) and text:find(DEATH, 1, true), "Beschreibung")
end)

test("Statistics: ohne eigenen Kill oder Tod steht nichts da, außer bei Account-Werten (dann 0(5))", function()
    local S = setup()
    S:Add("kills", 5, 113, "Wildschwein")
    S.char.by.kills[113] = nil -- nur ein anderer Charakter hat sie getötet
    eq(S:CreatureCounterText(113), nil, "ohne Account: nichts")
    S.account.tooltipAccount = true
    eq(S:CreatureCounterText(113), KILL .. " |cffd0d0d00|r|cff808080(5)|r", "mit Account: 0(5)")
end)

-- Tooltip mit linken und rechten Textfeldern (wie GameTooltip): rows = { { links, rechts }, ... }. Mit options.hideRight
-- zeigt der Tooltip rechte Texte nicht an (das Addon muss sie zurücknehmen).
local function rightTooltip(rows, options)
    options = options or {}
    local tip = { rows = {}, shown = 0 }
    local function field(text)
        local f = { text = text or "", visible = (text or "") ~= "" }
        function f:GetText() return self.text end
        function f:SetText(value) self.text = value end
        function f:SetFontObject(font) self.font = font end
        function f:Show() self.visible = true end
        function f:IsShown() return self.visible and not options.hideRight end
        return f
    end
    local function add(left, right)
        tip.rows[#tip.rows + 1] = true
        _G["RightTipTextLeft" .. #tip.rows] = field(left)
        _G["RightTipTextRight" .. #tip.rows] = field(right)
    end
    for _, row in ipairs(rows) do add(row[1], row[2]) end
    function tip:GetName() return "RightTip" end
    function tip:NumLines() return #self.rows end
    function tip:AddLine(text) add(text) end
    function tip:Show() self.shown = self.shown + 1 end
    function tip:Left(index) return _G["RightTipTextLeft" .. index] end
    function tip:Right(index) return _G["RightTipTextRight" .. index] end
    return tip
end

test("Statistics: Tooltip: rechts neben dem Namen (Zeile 1), Name unverändert, nie doppelt", function()
    local S = setup()
    S:Add("kills", 3, 113, "Wildschwein")
    local text = S:CreatureCounterText(113)
    local tip = rightTooltip({ { "Wildschwein" }, { "Stufe 8" }, { "Wildtier" } })
    local data = { guid = GUID113 }

    eq(S:UnitTooltipLines(data, tip), nil, "nichts übrig")
    eq(tip:Left(1).text, "Wildschwein", "Name unverändert")
    eq(tip:Right(1).text, text, "rechts daneben")
    eq(tip.shown, 1, "Größe neu berechnet")
    S:UnitTooltipLines(data, tip)
    eq(tip:Right(1).text, text, "zweiter Durchlauf ändert nichts")
    eq(#tip.rows, 3, "keine neue Zeile")

    eq(S:UnitTooltipLines({ guid = "Player-1-0000ABCD" }, tip), nil, "Spieler")
    eq(S:UnitTooltipLines({ guid = "GameObject-0-1-2-3-113-0000" }, tip), nil, "Objekt")
    eq(S:UnitTooltipLines({}, tip), nil, "ohne GUID")
    eq(S:UnitTooltipLines(nil, tip), nil, "ohne Daten")
    S.account.tooltipKills, S.account.tooltipDeaths = false, false
    eq(S:UnitTooltipLines(data, tip), nil, "beides aus")
end)

test("Statistics: Tooltip: rechts neben der Stufe ist immer Zeile 2", function()
    local S = setup()
    S.account.tooltipKillsMode = "level"
    S:Add("kills", 3, 113, "Wildschwein")
    local text = S:CreatureCounterText(113)
    local tip = rightTooltip({ { "Händler" }, { "<Gilde>" }, { "Stufe 8" } })
    eq(S:UnitTooltipLines({ guid = GUID113 }, tip), nil, "nichts übrig")
    eq(tip:Right(2).text, text, "Zeile 2, ohne Suche nach dem Wort Stufe")
    eq(tip:Right(1).text, "", "Zeile 1 unberührt")
    eq(tip:Left(2).text, "<Gilde>", "Text unverändert")
end)

test("Statistics: Tooltip: Name oder Stufe nicht möglich ergibt die eigene Zeile", function()
    local S, Glimpse = setup()
    S:Add("kills", 3, 113, "Wildschwein")
    local text = S:CreatureCounterText(113)
    local data = { guid = GUID113 }

    -- rechtes Feld schon belegt: nichts überschreiben, eigene Zeile am Ende
    local busy = rightTooltip({ { "Wildschwein", "Elite" }, { "Stufe 8" } })
    eq(S:UnitTooltipLines(data, busy), nil, "Blizzard-Zeile selbst angehängt")
    eq(busy:Right(1).text, "Elite", "fremder Text unberührt")
    eq(busy:Left(3).text, text, "eigene Zeile am Ende")

    -- der Tooltip zeigt den rechten Text nicht an: zurücknehmen, eigene Zeile
    local hidden = rightTooltip({ { "Wildschwein" }, { "Stufe 8" } }, { hideRight = true })
    S:UnitTooltipLines(data, hidden)
    eq(hidden:Right(1).text, "", "zurückgenommen")
    eq(hidden:Left(3).text, text, "eigene Zeile")

    -- Stufe gewählt, aber nur eine Zeile
    S.account.tooltipKillsMode = "level"
    local short = rightTooltip({ { "Ding" } })
    S:UnitTooltipLines(data, short)
    eq(short:Left(2).text, text, "eigene Zeile")

    -- rechtes Feld geschützt (Secret): nichts ändern, eigene Zeile
    S.account.tooltipKillsMode = "name"
    local tip = rightTooltip({ { "Wildschwein", "geheim" }, { "Stufe 8" } })
    Glimpse.IsSecret = function(_, value) return value == "geheim" end
    S:UnitTooltipLines(data, tip)
    Glimpse.IsSecret = function() return false end
    eq(tip:Right(1).text, "geheim", "unberührt")
    eq(tip:Left(3).text, text, "eigene Zeile")
end)

test("Statistics: Tooltip: eigene Zeile im Blizzard-Frame (klein, am Ende, nie doppelt)", function()
    local S = setup()
    S.account.tooltipKillsMode = "line"
    S:Add("kills", 3, 113, "Wildschwein")
    local text = S:CreatureCounterText(113)
    local data = { guid = GUID113 }
    eq(S:TooltipLineFrame(), "blizzard", "Standard: Blizzard")

    local tip = rightTooltip({ { "Wildschwein" }, { "Stufe 8" } })
    eq(S:UnitTooltipLines(data, tip), nil, "Zeile selbst angehängt")
    eq(#tip.rows, 3, "eine Zeile mehr")
    eq(tip:Left(3).text, text, "Text am Ende")
    eq(tip:Left(3).font, nil, "normale Schriftgröße (nicht verkleinert)")
    S:UnitTooltipLines(data, tip)
    eq(#tip.rows, 3, "zweiter Durchlauf fügt nichts hinzu")

    -- ohne Tooltip-Objekt: Zeilen für Glimpse
    eq(S:UnitTooltipLines(data, nil)[1][1], text, "ohne Tooltip")
end)

test("Statistics: Tooltip: Glimpse-Frame: Zeile und danach eine Leerzeile, nie doppelt", function()
    local S = setup()
    S.account.tooltipKillsMode = "line"
    S.account.tooltipLineFrame = "glimpse"
    S:Add("kills", 3, 113, "Wildschwein")
    local text = S:CreatureCounterText(113)
    eq(S:TooltipLineFrame(), "glimpse", "gewählt")

    local tip = rightTooltip({ { "Wildschwein" }, { "Stufe 8" } })
    local back = S:UnitTooltipLines({ guid = GUID113 }, tip)
    eq(back[1][1], text, "erst die Zeile")
    eq(back[2][1], " ", "dann eine Leerzeile")
    eq(#tip.rows, 2, "Tooltip selbst unberührt")

    -- schon im Tooltip (erneut verarbeitet): nichts mehr zurückgeben
    tip:AddLine(text)
    eq(S:UnitTooltipLines({ guid = GUID113 }, tip), nil, "nicht doppelt")
end)

test("Statistics: Tooltip-Handler hängt die Zeilen für Glimpse gleich an", function()
    local S, Glimpse = setup()
    S.account.tooltipKillsMode = "line"
    S.account.tooltipLineFrame = "glimpse"
    S:Add("kills", 3, 113, "Wildschwein")
    local added = {}
    Glimpse.AddTooltipLine = function(_, _, left) added[#added + 1] = left end
    local tip = rightTooltip({ { "Wildschwein" } })

    S:UnitTooltipHandler(tip, { guid = GUID113 })
    eq(added[1], S:CreatureCounterText(113), "Zeile")
    eq(added[2], " ", "Leerzeile")

    added = {}
    S:UnitTooltipHandler(tip, { })
    S:UnitTooltipHandler(tip, nil)
    eq(#added, 0, "ohne GUID oder Daten nichts")
end)

test("Statistics: Optionen: Position und Frame der eigenen Zeile", function()
    local S = setup()
    local args = S:BuildOptions().options.args.tooltip.args
    eq(S:TooltipKillsMode(), "name", "Standard: neben dem Namen")
    args.mode.set(nil, "level")
    eq(S:TooltipKillsMode(), "level", "Stufe")
    eq(args.position2.values().left ~= nil and args.position2.values().glimpse == nil, true, "Name/Stufe: links oder rechts")
    eq(args.position2.get(), "right", "Standard: rechts")
    args.position2.set(nil, "left")
    eq(S:TooltipSide(), "left", "links")
    args.mode.set(nil, "line")
    eq(args.position2.values().glimpse ~= nil and args.position2.values().left == nil, true, "eigene Zeile: Blizzard oder Glimpse")
    eq(args.position2.get(), "blizzard", "Standard: Blizzard")
    eq(S:TooltipSide(), "left", "die Seite bleibt gemerkt")
    args.position2.set(nil, "glimpse")
    eq(S:TooltipLineFrame(), "glimpse", "Glimpse-Frame")
    args.mode.set(nil, "unsinn")
    eq(S:TooltipKillsMode(), "name", "unbekannt: Standard")
end)

test("Statistics: Tooltip: links hinter dem Text von Name und Stufe, nie doppelt, sonst eigene Zeile", function()
    local S, Glimpse = setup()
    S.account.tooltipSide = "left"
    S:Add("kills", 3, 113, "Wildschwein")
    local text = S:CreatureCounterText(113)
    local data = { guid = GUID113 }

    local tip = rightTooltip({ { "Wildschwein" }, { "Stufe 8" } })
    eq(S:UnitTooltipLines(data, tip), nil, "nichts übrig")
    eq(tip:Left(1).text, "Wildschwein " .. text, "hinter dem Namen")
    eq(tip:Right(1).text, "", "rechts leer")
    S:UnitTooltipLines(data, tip)
    eq(tip:Left(1).text, "Wildschwein " .. text, "nie doppelt")

    S.account.tooltipKillsMode = "level"
    local tip2 = rightTooltip({ { "Wildschwein" }, { "Stufe 8" } })
    S:UnitTooltipLines(data, tip2)
    eq(tip2:Left(2).text, "Stufe 8 " .. text, "hinter der Stufe (Zeile 2)")

    -- Text geschützt: nichts ändern, eigene Zeile
    local tip3 = rightTooltip({ { "geheim" }, { "Stufe 8" } })
    S.account.tooltipKillsMode = "name"
    Glimpse.IsSecret = function(_, value) return value == "geheim" end
    S:UnitTooltipLines(data, tip3)
    Glimpse.IsSecret = function() return false end
    eq(tip3:Left(1).text, "geheim", "unverändert")
    eq(tip3:Left(3).text, text, "eigene Zeile")
end)

test("Statistics: Blizzard-Statistiken lesen (Schnittstelle fehlt / vorhanden)", function()
    local S = setup()
    local saved = {}
    local names = { "GetStatisticsCategoryList", "GetCategoryInfo", "GetCategoryNumAchievements", "GetAchievementInfo", "GetStatistic" }
    for _, name in ipairs(names) do saved[name] = _G[name]; _G[name] = nil end

    local _, complete = S:BlizzardApi()
    eq(complete, false, "ohne Schnittstelle")
    eq(S:ReadBlizzardStats(), nil, "nichts lesbar")
    eq(S:BlizzardLines()[#S:BlizzardLines()], "The classic statistics API is not complete in this client.", "Hinweis")

    local data = { [1] = { "Combat", nil, { { 10, "Total kills", "1,234" }, { 11, "Total deaths", "7" } } },
        [2] = { "Deaths", nil, { { 20, "Total deaths", "--" } } } }
    _G.GetStatisticsCategoryList = function() return { 1, 2 } end
    _G.GetCategoryInfo = function(id) return data[id][1], data[id][2] end
    _G.GetCategoryNumAchievements = function(id) return #data[id][3] end
    _G.GetAchievementInfo = function(id, index) local row = data[id][3][index] return row[1], row[2] end
    _G.GetStatistic = function(statID)
        for _, category in pairs(data) do for _, row in ipairs(category[3]) do if row[1] == statID then return row[3] end end end
    end

    local categories = S:ReadBlizzardStats()
    eq(#categories, 2, "zwei Kategorien")
    eq(categories[1].name, "Combat", "Name")
    eq(categories[1].stats[1].value, "1,234", "Wert")
    eq(categories[2].stats[1].id, 20, "ID")

    local lines = S:BlizzardLines("deaths")
    eq(lines[#lines], "2 matches for \"deaths\"", "Suche")
    local joined = table.concat(lines, "\n")
    assert(joined:find("[Combat] Total deaths (11) = 7", 1, true), joined)
    assert(joined:find("2 categories, 3 statistics", 1, true), joined)

    local dump = S:BlizzardDumpText()
    assert(dump:find("== Combat (category 1", 1, true) and dump:find("10 | Total kills | 1,234", 1, true), dump)

    -- ein Fehler in der Schnittstelle ruft keinen Fehler hervor
    _G.GetStatistic = function() error("kaputt") end
    eq(S:ReadBlizzardStats()[1].stats[1].value, nil, "kaputt: kein Wert, kein Fehler")

    for _, name in ipairs(names) do _G[name] = saved[name] end
end)

-- Blizzard-Statistik nachgebaut: stats[statID] = Text
local function fakeBlizzardStats(stats)
    local saved = _G.GetStatistic
    _G.GetStatistic = function(statID) return stats[statID] or "--" end
    return function() _G.GetStatistic = saved end
end

test("Statistics: Startwerte von Blizzard: Wert minus schon Gezähltes, einmal je Charakter", function()
    local S = setup()
    S.char.baseline, S.account.baseline = {}, {}
    local restore = fakeBlizzardStats({ [1197] = "389", [60] = "6", [1456] = "1,019" })

    S:Add("kills", 9) -- das Addon hat schon 9 Kills gezählt: sie stecken in den 389 von Blizzard
    eq(S:ImportBaseline(), true, "geändert")
    eq(S:Get("kills"), 389, "Kills = Wert von Blizzard (nichts doppelt)")
    eq(S.char.baseline.kills, 380, "Startwert = 389 - 9")
    eq(S:Get("deaths"), 6, "Tode")
    eq(S:Get("fishing.catches"), 1019, "Tausendertrenner")
    eq(S:Get("kills", "account"), 389, "Account")
    eq(S.account.baseline.kills, 380, "Account-Startwert")
    eq(S.char.baselineDone, true, "Charakter gelesen")

    eq(S:ImportBaseline(), false, "zweiter Aufruf tut nichts")
    eq(S:Get("kills"), 389, "unverändert")
    -- danach zählt das Addon normal weiter
    S:Add("kills", 1)
    eq(S:Get("kills"), 390, "weitergezählt")

    -- der Verlauf je Tag enthält den Startwert nicht
    eq(#S:GetSeries("kills"), 1, "nur der Tag mit echten Kills")
    restore()
end)

test("Statistics: Startwerte: zweiter Charakter summiert im Account, Reset des Charakters liest neu", function()
    local S = setup()
    S.char.baseline, S.account.baseline = {}, {}
    local restore = fakeBlizzardStats({ [1197] = "100" })
    S:ImportBaseline()

    -- zweiter Charakter (anderes Blizzard-Ergebnis)
    local first = S.char
    S.char = { totals = {}, by = {}, first = {}, last = {}, days = {}, baseline = {}, baselineDone = false }
    restore()
    restore = fakeBlizzardStats({ [1197] = "50" })
    S:ImportBaseline()
    eq(S:Get("kills"), 50, "zweiter Charakter")
    eq(S:Get("kills", "account"), 150, "Account: Summe beider")
    eq(S.account.baseline.kills, 150, "Account-Startwert")

    -- Reset des Charakters: Merker und Startwert weg, nächster Login liest wieder
    S:Reset("char")
    eq(S.char.baselineDone, false, "Merker zurück")
    eq(S:Get("kills"), 0, "Zähler leer")
    S:ImportBaseline()
    eq(S:Get("kills"), 50, "wieder gelesen")
    eq(S:Get("kills", "account"), 200, "Account zählt den Startwert erneut dazu")
    S.char = first
    restore()
end)

test("Statistics: Startwerte: Account zurückgesetzt, gelesener Charakter bringt seinen Startwert wieder ein", function()
    local S = setup()
    S.char.baseline, S.account.baseline = {}, {}
    local restore = fakeBlizzardStats({ [1197] = "100" })
    S:ImportBaseline()
    eq(S.char.baselineDone, true, "gelesen")

    S:Reset("account")
    eq(S:Get("kills", "account"), 0, "Account leer")
    eq(S.account.baseline.kills, nil, "Account-Startwert weg")
    eq(S:ImportBaseline(), true, "trotz Merker geladen")
    eq(S:Get("kills", "account"), 100, "Startwert wieder im Account")
    eq(S:Get("kills"), 100, "Charakter unverändert (nicht doppelt)")

    eq(S:ImportBaseline(), false, "danach nichts mehr")
    restore()
end)

test("Statistics: Startwerte: nicht lesbare Werte setzen den Merker nicht, nichts Negatives", function()
    local S = setup()
    S.char.baseline, S.account.baseline = {}, {}
    local restore = fakeBlizzardStats({ [1197] = "--", [60] = "--", [1456] = "55 67" })
    eq(S:ImportBaseline(), false, "nichts gelesen")
    eq(S.char.baselineDone == true, false, "später nochmal")
    restore()

    -- Blizzard kleiner als das Addon gezählt hat: nichts abziehen
    restore = fakeBlizzardStats({ [1197] = "3" })
    S:Add("kills", 10)
    S:ImportBaseline()
    eq(S:Get("kills"), 10, "nicht gekürzt")
    eq(S.char.baselineDone, true, "gelesen")
    restore()

    eq(S.ParseStatistic("210 (Humanoid)"), nil, "Text mit Zusatz")
    eq(S.ParseStatistic("1.234"), 1234, "Punkt als Tausendertrenner")
    eq(S.ParseStatistic(nil), nil, "nil")
    eq(S:BaselineStatusLine():find("character read", 1, true) ~= nil, true, "Statuszeile")
end)

test("Statistics: Protected fängt Fehler und vermerkt sie, NewSeen merkt GUIDs nur für das Zeitfenster", function()
    local S = setup()
    S.errorCount, S.lastError = nil, nil
    eq(S.Protected("Test", function(a, b) return a + b end, 1, 2), true, "ohne Fehler")
    eq(S.errorCount, nil, "nichts vermerkt")
    eq(S.Protected("Test", function() error("kaputt") end), false, "mit Fehler")
    eq(S.errorCount, 1, "gezählt")
    assert(S.lastError:find("Test: ", 1, true) and S.lastError:find("kaputt", 1, true), "Meldung mit Namen")

    local seen = S.NewSeen(10, 3)
    eq(seen("a", 100), false, "neu")
    eq(seen("a", 105), true, "im Zeitfenster")
    eq(seen("a", 111), false, "Zeitfenster vorbei, zählt wieder")
    seen("b", 111); seen("c", 111)
    eq(seen("d", 112), false, "über der Obergrenze: neu angefangen")
    eq(seen("a", 113), false, "alte Einträge sind weg")
    eq(seen("d", 113), true, "der neueste bleibt")
end)

test("Statistics: Fangquote ohne den Startwert von Blizzard (keine Würfe dazu), der Startwert gehört zu keiner Stufe", function()
    local S = setup()
    S.api.GetProfessions = function() return nil, nil, nil, 3 end
    S.api.GetProfessionInfo = function() return "Angeln", "icon", 5, 75, 1, 0, 356 end
    S.api.GetSpellSubtext = function(id) return ({ [7620] = "Lehrling" })[id] end
    S:RegisterStat("fishing.casts", "Würfe", { group = "Angeln" })
    S:RegisterStat("fishing.catches", "Fänge", { group = "Angeln" })
    local saved = _G.GetStatistic
    _G.GetStatistic = function(id) return id == 1456 and "3572" or "--" end
    S:ImportBaseline()
    _G.GetStatistic = saved
    eq(S:Get("fishing.catches"), 3572, "Startwert im Zähler")

    for _ = 1, 6 do S:Add("fishing.casts"); S:AddTier("fishing.casts", 1) end
    for _ = 1, 3 do S:Add("fishing.catches"); S:AddTier("fishing.catches", 1) end
    eq(S:Get("fishing.catches"), 3575, "Anzeige mit Startwert"); eq(S:GetCounted("fishing.catches"), 3, "selbst gezählt")

    local tiers = S:GetTierCounts("fishing.catches", "char")
    eq(#tiers, 1, "eine Stufe"); eq(tiers[1].name, "Lehrling", "Name"); eq(tiers[1].count, 3, "ohne Startwert")

    local fishing = S:Query({ topics = { "fishing" } }).topics.fishing
    eq(fishing.derived.missed.value, 3, "Würfe ohne Fang"); eq(fishing.derived.rate.value, 0.5, "Fangquote")
    local text = table.concat(S:OverviewLines(false, true), "\n")
    assert(text:find("Catch rate: 50", 1, true), "Übersicht: Quote 50 %: " .. text)
    assert(text:find("Casts without catch: 3", 1, true), "Übersicht: 3 ohne Fang")
end)

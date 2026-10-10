-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Öffentliche API (Core/Api.lua) über Daten aus Glimpse: Database

test("API: feste Antwort für alle Themen, Auswahl, Stufen, Fangquote, nie ein Fehler", function()
    local S, _, DB = stub.setup()
    S.api.GetProfessions = function() return nil, nil, nil, 3 end
    S.api.GetProfessionInfo = function() return "Angeln", "icon", 10, 150, 1, 0, 356 end
    S.api.GetSpellSubtext = function(id) return ({ [7620] = "Lehrling", [7731] = "Geselle" })[id] end

    local info = S:GetInfo()
    eq(info.api, 5, "API-Version"); eq(info.apiMin, 5, "ältester kompatibler Stand"); eq(info.available, true, "Database da")
    eq(S.RegisterTopic, nil, "eigene Themen gibt es nicht mehr"); eq(S.Add, nil, "eigene Zähler auch nicht")
    local list = S:GetTopicList()
    eq(list[1].key, "fishing", "Angeln zuerst"); eq(list[1].label, "Angeln", "Name vom Client"); eq(list[1].metrics[1], "casts", "Kennzahlen")
    eq(#S:GetTopicList("combat"), 3, "kills, deaths, combat"); eq(#S:GetTopicList("travel"), 2, "Reisen und Tiefenbahn"); eq(#S:GetTopicList("gibtsnicht"), 0, "unbekannte Art")

    local combat = DB:Register("combat", { area = "Core", zones = true })
    local fishing = DB:Register("fishing", { area = "Professions", zones = true })
    for _ = 1, 10 do fishing:Count("cast", 0, 12); fishing:Count("casttier", 75) end
    for _ = 1, 5 do fishing:Count("catch", 0, 12); fishing:Count("catchtier", 75) end
    for _ = 1, 4 do fishing:Count("cast", 0, 12); fishing:Count("casttier", 150) end
    for _ = 1, 3 do fishing:Count("catch", 0, 12); fishing:Count("catchtier", 150) end
    fishing:SetBaseline("catch", 0, 100)
    fishing:Count("fish", 6291, 12, 2)
    combat:Count("kill", 113, 12, 2)
    combat:SetBaseline("kill", 0, 40)

    local r = S:Query({ topics = { "fishing", "gibtsnicht" } })
    eq(r.ok, true, "ok"); eq(r.schema, 1, "Schema"); eq(r.scope, "char", "Standard"); eq(r.topics.herbalism, nil, "nur das gewünschte Thema")
    eq(r.unknown[1], "gibtsnicht", "unbekanntes Thema"); eq(r.order[1], "fishing", "Reihenfolge"); eq(r.since, stub.NOON, "seit")
    local fishingTopic = r.topics.fishing
    eq(fishingTopic.hasData, true, "Daten"); eq(fishingTopic.metrics.casts.total, 14, "Würfe"); eq(fishingTopic.metrics.casts.label, "Fishing casts", "Beschriftung")
    eq(fishingTopic.metrics.catches.total, 108, "Fänge mit Startwert")
    eq(fishingTopic.metrics.casts.periods[1], 14, "heute"); eq(fishingTopic.metrics.catches.periods[7], 8, "Zeitraum ohne Startwert")
    eq(fishingTopic.derived.missed.value, 6, "ohne Fang"); eq(math.floor(fishingTopic.derived.rate.value * 100 + 0.5), 57, "Quote ohne Startwert")
    local rate = fishingTopic.derived.rate.tiers
    eq(#rate, 2, "zwei Stufen"); eq(rate[1].name, "Lehrling", "Stufe"); eq(rate[1].denominator, 10, "Würfe der Stufe"); eq(rate[2].numerator, 3, "Fänge")
    eq(#fishingTopic.metrics.fish.tiers, 0, "Fische ohne Stufen")

    local all = S:Query({ breakdown = 3, periods = { 30, "x", 0 } })
    for _, key in ipairs({ "fishing", "herbalism", "mining", "skinning", "kills", "deaths" }) do
        local topic = all.topics[key]
        assert(topic and topic.key == key and topic.kind and topic.label and type(topic.hasData) == "boolean" and type(topic.derived) == "table", key)
        for name, metric in pairs(topic.metrics) do
            assert(metric.label and type(metric.total) == "number" and type(metric.periods) == "table" and type(metric.tiers) == "table"
                and type(metric.breakdown) == "table", key .. "." .. name)
        end
    end
    eq(all.topics.herbalism.hasData, false, "ohne Namespace keine Daten"); eq(all.topics.kills.metrics.total.total, 42, "Kills mit Startwert")
    eq(all.topics.kills.metrics.byZone.total, 2, "nach Zone ohne Startwert")
    eq(all.topics.kills.metrics.total.breakdown[1].id, 113, "Aufschlüsselung"); eq(all.topics.kills.metrics.byZone.breakdown[1].id, 12, "Zone")
    eq(all.topics.fishing.metrics.fishByZone.breakdown[1].count, 2, "Fische nach Zone")
    eq(all.topics.fishing.metrics.casts.periods[30], 14, "30 Tage, Unsinn übergangen")
    eq(#S:Query().topics.kills.metrics.total.breakdown, 0, "ohne breakdown keine Einträge")
    eq(#S:Query({ kind = "combat" }).order, 3, "nur Kampf"); eq(#S:Query({ tiers = false }).topics.fishing.metrics.casts.tiers, 0, "ohne Stufen")
    eq(S:Query({ scope = "Flovy - Forever" }).topics.kills.metrics.total.total, 42, "Name - Realm")
    eq(S:Query({ scope = "account" }).topics.kills.metrics.total.total, 42, "Account")
    eq(S:Query({ scope = "Niemand - Realm" }).topics.kills.metrics.total.total, 0, "unbekannter Charakter: 0 statt Fehler")
    eq(S:Query("Unsinn").ok, true, "falscher Typ der Abfrage")

    _G.GlimpseDB = nil
    eq(S:Query().ok, false, "ohne Database: Antwort statt Fehler"); eq(S:GetInfo().available, false, "nicht lesbar")
end)

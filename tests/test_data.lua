-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Lesen aus Glimpse: Database (Core/Data.lua, Names.lua). Testdaten schreiben die echten Schreiber-APIs von Database,
-- so wie Glimpse (combat), Professions (fishing) und Gathering (gathering) es tun.

local function writers(DB)
    return DB:Register("combat", { area = "Core", zones = true, world = { looted = true, loot = true } }),
        DB:Register("fishing", { area = "Professions", zones = true, world = { looted = true, loot = true, drop = true } }),
        DB:Register("gathering", { area = "Gathering", zones = true })
end

test("Daten: Summen je Charakter und Account, Startwert nur in der Gesamtsumme", function()
    local S, _, DB = stub.setup()
    local combat, fishing = writers(DB)
    combat:Count("kill", 299, 12); combat:Count("kill", 299, 12); combat:Count("kill", 40, 14)
    combat:SetBaseline("kill", 0, 100)
    fishing:Count("cast", 0, 12, 10); fishing:Count("catch", 0, 12, 6)
    fishing:SetBaseline("catch", 0, 50)

    eq(S:Get("kills"), 103, "Kills mit Startwert"); eq(S:GetCounted("kills"), 3, "ohne Startwert")
    eq(S:GetBaseline("kills"), 100, "Startwert"); eq(S:Get("kills", "account"), 103, "Account")
    eq(S:Get("fishing.catches"), 56, "Fänge mit Startwert"); eq(S:GetCounted("fishing.catches"), 6, "Fänge gezählt")
    eq(S:Get("fishing.casts"), 10, "Würfe ohne Startwert"); eq(S:GetBaseline("fishing.casts"), 0, "Würfe haben keinen")
    eq(S:Get("unbekannt"), 0, "unbekannter Zähler"); eq(S:Get("kills", "irgendwas"), 0, "unbekannter scope")
end)

test("Daten: Zeiträume aus den Stunden, ohne Startwert", function()
    local S, _, DB = stub.setup()
    local combat = writers(DB)
    combat:SetBaseline("kill", 0, 100)
    stub.serverTime = stub.NOON - 86400 * 20
    combat:Count("kill", 1, 12, 4)
    stub.serverTime = stub.NOON - 86400 * 3
    combat:Count("kill", 1, 12, 2)
    stub.serverTime = stub.NOON
    combat:Count("kill", 1, 12)

    eq(S:GetSum("kills", "char", 1), 1, "heute"); eq(S:GetSum("kills", "char", 7), 3, "7 Tage")
    eq(S:GetSum("kills", "char", 30), 7, "30 Tage"); eq(S:Get("kills"), 107, "gesamt")

    local series = S:GetSeries("kills", "char", 30)
    eq(#series, 3, "drei Tage"); eq(series[1].n, 4, "ältester zuerst"); eq(series[3].n, 1, "heute zuletzt")
    eq(series[3].day, tonumber(os.date("%Y%m%d", stub.NOON)), "Tag in Ortszeit")
    eq(#S:GetSeries("kills", "char", 7), 2, "nur die letzten 7 Tage")
end)

test("Daten: Aufschlüsselung nach ID und Zone, größte zuerst, mit Namen", function()
    local S, _, DB = stub.setup()
    local combat, fishing, gathering = writers(DB)
    combat:Count("kill", 299, 12, 3); combat:Count("kill", 40, 14); combat:Count("kill", 0, nil, 2)
    combat:SetBaseline("kill", 0, 100)
    fishing:Count("fish", 6291, 12, 4)
    gathering:Count("herb", 1617, 12)
    S.api.GetItemNameByID = function(id) return id == 6291 and "Rohe Lederflosse" or nil end

    local list = S:GetBreakdown("kills")
    eq(#list, 3, "drei IDs, Startwert nicht dabei"); eq(list[1].key, 299, "größte zuerst"); eq(list[1].count, 3, "Anzahl")
    eq(list[1].name, "Creature 299", "ohne Namen die ID"); eq(list[2].name, "Unknown", "ID 0: keiner Kreatur zugeordnet")
    eq(list[1].first, stub.NOON, "erste Erfassung")
    eq(#S:GetBreakdown("kills", "char", 1), 1, "limit")
    eq(S:GetBreakdown("fishing.items")[1].name, "Rohe Lederflosse", "Item-Name vom Client")
    eq(S:GetBreakdown("gathering.herb")[1].name, "Object 1617", "Objekt ohne Namen")
    eq(#S:GetBreakdown("fishing.casts"), 0, "Würfe haben keine IDs")

    local zones = S:GetZoneBreakdown("kills")
    eq(#zones, 2, "zwei Zonen, Kills ohne Zone fehlen"); eq(zones[1].key, 12, "Zone"); eq(zones[1].count, 3, "Summe der Zone")
    eq(zones[1].name, "Zone 12", "ohne Modul Locations die ID")
end)

test("Daten: Namen vom Namensdienst des Cores, Zonen und Instanzen", function()
    local S, Glimpse = stub.setup()
    eq(S:NameOf("npc", 299), "Creature 299", "ohne Namensdienst die ID"); eq(S:NameOf("object", 1617), "Object 1617", "Objekt ohne Namen")
    Glimpse.IDs = {
        NPCName = function(_, id) return id == 299 and "Wolf" or nil end,
        ObjectName = function(_, id) return id == 1617 and "Silberblatt" or nil end,
    }
    eq(S:NameOf("npc", 299), "Wolf", "Kreatur"); eq(S:NameOf("object", 1617), "Silberblatt", "Objekt")
    eq(S:NameOf("npc", 300), "Creature 300", "unbekannte Kreatur")
    Glimpse.IDs.NPCName = function() error("kaputt") end
    eq(S:NameOf("npc", 299), "Creature 299", "ein Fehler im Namensdienst stört nicht")
    eq(S:ZoneName(-36), "Instance 36", "Instanz")

    Glimpse.modules.Locations = { GetMapName = function(_, map) return map == 12 and "Wald von Elwynn" or nil end }
    eq(S:ZoneName(12), "Wald von Elwynn", "Zone vom Modul Locations"); eq(S:ZoneName(13), "Zone 13", "unbekannte Zone")
end)

test("Daten: erste Erfassung, seit wann, Stufen", function()
    local S, _, DB = stub.setup()
    local _, fishing = writers(DB)
    eq(S:GetSince(), nil, "ohne Daten")
    stub.serverTime = stub.NOON - 3600
    fishing:Count("cast", 0, 12); fishing:Count("casttier", 75)
    stub.serverTime = stub.NOON
    fishing:Count("cast", 0, 12); fishing:Count("casttier", 150)
    fishing:Count("catch", 0, 12); fishing:Count("catchtier", 150)

    local first, last = S:GetFirst("fishing.casts")
    eq(first, stub.NOON - 3600, "erste"); eq(last, stub.NOON, "letzte")
    eq(S:GetSince(), stub.NOON - 3600, "seit"); eq(S:GetSince("account"), stub.NOON - 3600, "Account")

    S.api.GetSpellSubtext = function(id) return ({ [7620] = "Lehrling", [7731] = "Geselle" })[id] end
    local tiers = S:GetTierCounts("fishing.casts")
    eq(#tiers, 2, "zwei Stufen"); eq(tiers[1].max, 75, "aufsteigend"); eq(tiers[1].name, "Lehrling", "Name vom Client")
    eq(tiers[2].count, 1, "Anzahl"); eq(#S:GetTierCounts("fishing.items"), 0, "Fische ohne Stufen")
    S.api.GetSpellSubtext = nil
    eq(S:GetTierCounts("fishing.catches")[1].name, "Skill up to 150", "neutraler Name")
end)

test("Daten: fehlt ein Namespace, gibt es nur Nullen; fehlt Database, auch", function()
    local S, _, DB = stub.setup()
    local combat = DB:Register("combat", { area = "Core", zones = true })
    combat:Count("kill", 1, 12)
    eq(S:Reader("gathering"), nil, "kein Namespace gathering")
    eq(S:Get("gathering.herb"), 0, "nichts"); eq(#S:GetBreakdown("skinning"), 0, "leer"); eq(S:GetFirst("skinning"), nil, "keine Zeit")
    eq(S:GetSince(), stub.NOON, "andere Zähler zählen weiter")

    _G.GlimpseDB = nil
    eq(S:Get("kills"), 0, "ohne Database"); eq(S:GetSum("kills", "char", 7), 0, "Zeitraum"); eq(#S:GetSeries("kills"), 0, "Verlauf")
    eq(#S:GetCharacters(), 0, "keine Charaktere")
    _G.GlimpseDB = DB
end)

test("Daten: Charaktere über Database, scope je Index und Name", function()
    local S, _, DB, P = stub.setup()
    local combat = writers(DB)
    combat:Count("kill", 1, 12, 5)

    -- zweiter Charakter loggt sich ein
    P.char, P.charKey = nil, nil
    stub.player.guid, stub.player.name = "Player-1-00000002", "Zweit"
    combat:Count("kill", 1, 12, 2)

    local list = S:GetCharacters()
    eq(#list, 2, "zwei Charaktere"); eq(S:CharacterName(list[1]), "Zweit - Forever", "aktueller zuerst")
    eq(S:Get("kills"), 2, "dieser Charakter"); eq(S:Get("kills", "account"), 7, "Account")
    eq(S:Get("kills", list[2]), 5, "anderer Charakter über den Index")
    eq(S:ResolveScope("Flovy - Forever"), list[2], "Name - Realm"); eq(S:ResolveScope("Niemand - Realm"), nil, "unbekannt")
end)

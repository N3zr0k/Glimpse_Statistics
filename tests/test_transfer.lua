-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Export und Import (Core/Transfer/Serialize.lua, Transfer.lua)
local function setup()
    _G.time = os.time
    local Glimpse = stub.newGlimpse()
    stub.load("Core/Statistics.lua", "Glimpse_Statistics")
    local S = Glimpse:GetModule("Statistics")
    local me = { totals = {}, by = {} }
    local other = { totals = { kills = 7 }, by = { kills = { [5] = { n = 7, name = "Wolf" } } } }
    S.store = { char = me, global = { totals = {}, by = {}, imports = {} }, keys = { char = "Ich - Realm" },
        sv = { char = { ["Ich - Realm"] = me, ["Zweit - Realm"] = other } } }
    S.char, S.account = S.store.char, S.store.global
    S.registry, S.order = {}, {}
    stub.load("Core/Transfer/Serialize.lua", "Glimpse_Statistics")
    stub.load("Core/Transfer/Transfer.lua", "Glimpse_Statistics")
    return S, Glimpse
end

local function fill(S)
    S:Add("kills", 3, 100, "Bär")
    S:Add("fishing.casts", 12, 37)
    S:Add("skinning", 2)
end

test("Transfer: Serialisieren und Lesen ergibt dasselbe", function()
    local S = setup()
    local value = { a = 1, b = { 1, 2, x = "text" }, c = true, d = 1.5 }
    local back = S.Deserialize(S.Serialize(value))
    eq(back.a, 1, "Zahl"); eq(back.b[2], 2, "Liste"); eq(back.b.x, "text", "Text"); eq(back.c, true, "bool"); eq(back.d, 1.5, "Kommazahl")
    eq(S.Deserialize("{n1;"), nil, "unvollständig")
end)

test("Transfer: Export und Ersetzen stellt alles wieder her", function()
    local S = setup()
    fill(S)
    local text, info = S:ExportData()
    eq(text:sub(1, 6), "GSTAT1", "Kennung"); eq(info.chars, 2, "zwei Charaktere")

    S:Reset("char"); S:Reset("account")
    eq(S:Get("kills"), 0, "geleert")
    local ok, result = S:ImportData(text, "replace")
    eq(ok, true, "Import ok"); eq(result.chars, 2, "Charaktere")
    eq(S:Get("kills"), 3, "Charakter"); eq(S:Get("kills", "account"), 3, "Account")
    eq(S:GetBreakdown("kills")[1].name, "Bär", "Aufschlüsselung")
    eq(S:Get("kills", "Zweit - Realm"), 7, "anderer Charakter")
end)

test("Transfer: Zusammenführen addiert, der eigene Export wird abgelehnt", function()
    local S = setup()
    fill(S)
    local text = S:ExportData()
    local ok, err = S:ImportData(text, "merge")
    eq(ok, false, "eigener Export"); eq(err, "duplicate", "Grund")

    -- anderer Export (andere ID) wird addiert
    local other = setup()
    fill(other)
    other:Add("kills", 1, 100, "Bär")
    local fremd = other:ExportData()
    ok = S:ImportData(fremd, "merge")
    eq(ok, true, "Fremder Export")
    eq(S:Get("kills"), 3 + 4, "Charakter addiert"); eq(S:Get("kills", "account"), 3 + 4, "Account addiert")
    eq(S:Get("kills", "Zweit - Realm"), 14, "anderer Charakter addiert")
    eq(S:GetBreakdown("kills")[1].count, 7, "Aufschlüsselung addiert")
    eq(select(2, S:ImportData(fremd, "merge")), "duplicate", "zweites Mal")
end)

test("Transfer: ungültige Texte", function()
    local S = setup()
    eq(select(2, S:ImportData("")), "empty", "leer")
    eq(select(2, S:ImportData("hallo")), "notExport", "kein Export")
    eq(select(2, S:ImportData("GSTAT9:R:{}")), "formatNewer", "neuer")
    eq(select(2, S:ImportData("GSTAT1:R:{n1;")), "damaged", "kaputt")
    eq(select(2, S:ImportData("GSTAT1:R:{}")), "damaged", "ohne Account")
    eq(select(2, S:ImportData("GSTAT1:D:xyz")), "unsupported", "ohne Kompression")
end)

test("Transfer: Import prüft die Zahlen", function()
    local S = setup()
    local payload = S.Serialize({
        format = 1, id = "x-1",
        account = { totals = { ok = 5, bad = -3, ["1"] = 0, huge = 1e14 }, by = { ok = { [1] = { n = 5, name = "A" }, [2] = { n = -1 } } } },
        chars = {},
    })
    local ok, info = S:ImportData("GSTAT1:R:" .. payload, "merge")
    eq(ok, true, "Import ok")
    eq(S:Get("ok", "account"), 5, "gültig"); eq(S:Get("bad", "account"), 0, "negativ verworfen")
    eq(S:Get("huge", "account"), 1e12, "Obergrenze")
    eq(#S:GetBreakdown("ok", "account"), 1, "ungültiger Eintrag verworfen")
    assert(info.removed >= 3, "verworfene Einträge gezählt: " .. info.removed)
end)

test("Transfer: Ersetzen leert auch andere Charaktere und legt neue an", function()
    local S = setup()
    local payload = S.Serialize({
        format = 1, id = "x-2", account = { totals = {}, by = {} },
        chars = { ["Neu - Realm"] = { totals = { kills = 2 }, by = {} } },
    })
    S:ImportData("GSTAT1:R:" .. payload, "replace")
    eq(S:Get("kills", "Zweit - Realm"), 0, "alter Charakter geleert")
    eq(S:Get("kills", "Neu - Realm"), 2, "neuer Charakter")
end)

test("Transfer: Zeitpunkte und Tagesreihen reisen mit (Ersetzen und Zusammenführen)", function()
    local S = setup()
    local t1, t2 = 1760000000, 1760000000 + 86400
    S.clock = function() return t1 end
    S:Add("kills", 2, 5, "Wolf")
    S.clock = function() return t2 end
    S:Add("kills", 3, 5, "Wolf")
    local text = S:ExportData()

    S:Reset("char"); S:Reset("account")
    eq(S:GetSince(), nil, "geleert")
    eq(S:ImportData(text, "replace"), true, "Import")
    eq(S:GetSince(), t1, "seit"); eq(S:GetSince("account"), t1, "Account seit")
    local first, last = S:GetFirst("kills")
    eq(first, t1, "erste"); eq(last, t2, "letzte")
    local series = S:GetSeries("kills")
    eq(#series, 2, "zwei Tage"); eq(series[1].n, 2, "Tag 1"); eq(series[2].n, 3, "Tag 2")

    -- Zusammenführen: früheste Zeit, Tage addiert
    local other = setup()
    other.clock = function() return t1 - 86400 * 5 end
    other:Add("kills", 4, 5, "Wolf")
    local fremd = other:ExportData()
    eq(S:ImportData(fremd, "merge"), true, "zusammengeführt")
    eq(S:GetSince("account"), t1 - 86400 * 5, "früheste Zeit")
    eq(select(1, S:GetFirst("kills", "account")), t1 - 86400 * 5, "früheste Erfassung")
    eq(#S:GetSeries("kills", "account"), 3, "drei Tage")
    eq(S:Get("kills", "account"), 9, "Summe")
end)

test("Transfer: ungültige Zeitpunkte und Tage werden verworfen", function()
    local S = setup()
    local payload = S.Serialize({
        format = 1, id = "x-9",
        account = { totals = { a = 3 }, by = {}, since = 5, first = { a = 1760000000 }, last = { a = -1 },
            days = { a = { [20251001] = 3, [99999999] = 2, [20250230] = 0 } } },
        chars = {},
    })
    eq(S:ImportData("GSTAT1:R:" .. payload, "merge"), true, "Import")
    eq(S:GetSince("account"), nil, "ungültiger Zeitpunkt verworfen")
    eq(select(1, S:GetFirst("a", "account")), 1760000000, "gültig")
    eq(#S:GetSeries("a", "account"), 1, "nur der gültige Tag")
end)

test("Transfer: Zeitstempel der Einträge reisen mit und werden beim Zusammenführen vereint", function()
    local S = setup()
    local t1, t2 = 1760000000, 1760086400
    S.clock = function() return t1 end
    S:Add("kills", 1, 5, "Wolf")
    local text = S:ExportData()
    local other = setup()
    other.clock = function() return t2 end
    other:Add("kills", 2, 5, "Wolf")
    local fremd = other:ExportData()

    eq(S:ImportData(fremd, "merge"), true, "zusammengeführt")
    local entry = S.account.by.kills[5]
    eq(entry.n, 3, "Summe"); eq(entry.first, t1, "früheste"); eq(entry.last, t2, "späteste")

    S:Reset("char"); S:Reset("account")
    eq(S:ImportData(text, "replace"), true, "Ersetzen")
    eq(S.account.by.kills[5].first, t1, "Eintrag-Zeitpunkt aus dem Export")
end)

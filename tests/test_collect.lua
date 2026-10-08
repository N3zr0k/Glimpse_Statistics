-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Sammler: Kills (Kills.lua), Angeln (Fishing.lua), Sammeln und Kürschnern (Gathering.lua), Ereignisse (Events.lua)
local ITEMS = { -- itemID -> { classID, subClassID }
    [101] = { 7, 8 },   -- Fisch (Handwerkswaren)
    [102] = { 15, 0 },  -- Müll
    [201] = { 7, 9 },   -- Kraut
    [301] = { 7, 7 },   -- Erz
}

local function setup()
    local Glimpse = stub.newGlimpse()
    stub.load("Core/Statistics.lua", "Glimpse_Statistics")
    local S = Glimpse:GetModule("Statistics")
    local me = { totals = {}, by = {}, first = {}, last = {}, days = {} }
    S.store = { char = me, global = { totals = {}, by = {}, first = {}, last = {}, days = {}, imports = {}, collect = true },
        keys = { char = "Ich - Realm" }, sv = { char = { ["Ich - Realm"] = me } } }
    S.char, S.account = S.store.char, S.store.global
    S.registry, S.order = {}, {}

    -- Ort des Spielers
    local area = { map = 37, x = 0.5, y = 0.5 }
    Glimpse.modules.Locations = {
        GetPlayerArea = function() return area end,
        GetMapName = function(_, map) return map == 37 and "Elwynn" or "Karte " .. tostring(map) end,
    }

    stub.load("Core/Display/Display.lua", "Glimpse_Statistics")
    stub.load("Core/Collect/Collect.lua", "Glimpse_Statistics")
    stub.load("Core/Tiers.lua", "Glimpse_Statistics")
    stub.load("Core/Api.lua", "Glimpse_Statistics")
    stub.load("Core/Collect/Kills.lua", "Glimpse_Statistics")
    stub.load("Core/Collect/Deaths.lua", "Glimpse_Statistics")
    stub.load("Core/Collect/Fishing.lua", "Glimpse_Statistics")
    stub.load("Core/Collect/Gathering.lua", "Glimpse_Statistics")

    local env = { S = S, Glimpse = Glimpse, now = 100, area = function(value) area = value end,
        units = {}, loot = {}, fishingLoot = false }
    local api = S.api
    api.GetTime = function() return env.now end
    api.UnitGUID = function(unit) local u = env.units[unit]; return u and u.guid end
    api.UnitName = function(unit) local u = env.units[unit]; return u and u.name end
    api.UnitIsDead = function(unit) local u = env.units[unit]; return u and u.dead or false end
    api.UnitIsTapDenied = function(unit) local u = env.units[unit]; return u and u.tapped or false end
    api.GetItemInfoInstant = function(id) local c = ITEMS[id]; return id, "", "", "", "", c[1], c[2] end
    api.GetItemNameByID = function(id) return "Item" .. id end
    api.GetNumLootItems = function() return #env.loot end
    api.GetLootSlotType = function() return 1 end
    api.GetLootSlotLink = function(slot) return "|Hitem:" .. env.loot[slot][1] .. ":0|h[x]|h" end
    api.GetLootSourceInfo = function(slot) return env.loot[slot][2], 1 end
    api.IsFishingLoot = function() return env.fishingLoot end
    api.GetSpellName = function(id)
        if id == 7620 or id == 7731 then return "Fischen" end
        if id == 8613 then return "Kürschnern" end
        return "Anderes"
    end
    return env
end

local function row(S, key, scope) return S:Get(key, scope or "account") end

test("Kills: totes Ziel zählt einmal, mit Zone und Name", function()
    local e = setup()
    local S = e.S
    e.units.target = { guid = "Creature-0-1-2-3-77-0000", name = "Wolf", dead = true }
    S:OnTargetEvent("UNIT_HEALTH")
    S:OnTargetEvent("PLAYER_REGEN_ENABLED")
    eq(row(S, "kills"), 1, "ein Kill")
    eq(S.account.by.kills[77].name, "Wolf", "Name")
    eq(row(S, "kills.area"), 1, "je Zone"); eq(S.account.by["kills.area"][37].name, "Elwynn", "Zonenname")
    eq(S.account.by["kills.zone"]["77@37"].name, "Wolf - Elwynn", "Kreatur je Zone")
    eq(S:GetSince("account") ~= nil, true, "Zeitstempel gesetzt")

    -- dieselbe Leiche später noch einmal: nichts. Nach langer Zeit (neue Leiche gleicher GUID): zählt
    e.now = 200; S:OnTargetEvent("UNIT_HEALTH")
    eq(row(S, "kills"), 1, "nicht doppelt")
    e.now = 900; S:OnTargetEvent("UNIT_HEALTH")
    eq(row(S, "kills"), 2, "neue Leiche")
end)

test("Kills: fremdes Tap, lebendes Ziel, Instanz und ausgeschaltete Sammlung", function()
    local e = setup()
    local S = e.S
    e.units.target = { guid = "Creature-0-1-2-3-77-0000", name = "Wolf", dead = false }
    S:OnTargetEvent("UNIT_HEALTH")
    eq(row(S, "kills"), 0, "lebt")
    e.units.target.dead, e.units.target.tapped = true, true
    S:OnTargetEvent("UNIT_HEALTH")
    eq(row(S, "kills"), 0, "gehört einem anderen")
    e.units.target.tapped = false
    S.account.collect = false
    S:OnTargetEvent("UNIT_HEALTH")
    eq(row(S, "kills"), 0, "Sammlung aus")
    S.account.collect = true

    e.area({ instance = 36, name = "Die Todesminen" })
    S:OnTargetEvent("UNIT_HEALTH")
    eq(S.account.by["kills.area"]["i36"].name, "Die Todesminen", "Instanz als Zone")
end)

test("Kills: Spieler und Gegenstände zählen nicht, Leichen ohne Ziel über das Beutefenster", function()
    local e = setup()
    local S = e.S
    e.units.target = { guid = "Player-0-1-2-3", name = "Spieler", dead = true }
    S:OnTargetEvent("UNIT_HEALTH")
    eq(row(S, "kills"), 0, "Spieler")

    e.loot = { { 102, "Creature-0-1-2-3-88-0000" } }
    S:OnLootOpened()
    eq(row(S, "kills"), 1, "Leiche per Beute"); eq(S.account.by.kills[88].n, 1, "je Kreatur")
    S:OnLootOpened()
    eq(row(S, "kills"), 1, "Fenster erneut geöffnet")
end)

test("Angeln: Würfe, Fänge, nur Fische (kein Material, kein Müll)", function()
    local e = setup()
    local S = e.S
    S:OnSpellSent(7620) -- nur Sammelzauber
    eq(S:CountCast(7620), true, "Wurf erkannt")
    eq(S:CountCast(7731), true, "anderer Rang über den Namen")
    eq(S:CountCast(1234), false, "anderer Zauber")
    eq(row(S, "fishing.casts"), 2, "zwei Würfe"); eq(S.account.by["fishing.casts"][37].name, "Elwynn", "je Zone")

    e.fishingLoot = true
    e.loot = { { 101, "GameObject-0-1-2-3-9-0" }, { 102, "GameObject-0-1-2-3-9-0" }, { 101, "GameObject-0-1-2-3-9-0" },
        { 201, "GameObject-0-1-2-3-9-0" }, { 301, "GameObject-0-1-2-3-9-0" } }
    S:OnLootOpened()
    eq(row(S, "fishing.catches"), 1, "ein Fang")
    eq(row(S, "fishing.items"), 2, "zwei Fische, weder Müll noch Kraut noch Erz")
    eq(S.account.by["fishing.items"][101].name, "Item101", "Name")
    eq(S.account.by["fishing.items.zone"]["101@37"].n, 2, "je Zone")
    eq(row(S, "kills"), 0, "Fang ist kein Kill"); eq(row(S, "gathering.other"), 0, "und kein Knoten")
end)

test("Sammeln: Knoten nach einem Zauber, Kategorie, nicht doppelt", function()
    local e = setup()
    local S = e.S
    e.loot = { { 201, "GameObject-0-1-2-3-1618-0" } }
    S:OnLootOpened()
    eq(row(S, "gathering.herb"), 0, "ohne Zauber zählt eine Truhe nicht")

    e.now = 200
    S:OnSpellSent(2366, "Silberblatt")
    e.now = 203
    S:OnLootOpened(); S:OnLootOpened()
    eq(row(S, "gathering.herb"), 1, "ein Abbau"); eq(S.account.by["gathering.herb"][1618].name, "Silberblatt", "Name aus dem Zauberziel")

    e.now = 220
    S:OnSpellSent(2366, "Silberblatt")
    e.now = 223
    S:OnLootOpened()
    eq(row(S, "gathering.herb"), 2, "zweiter Abbau am selben Knoten")

    e.loot = { { 301, "GameObject-0-1-2-3-1731-0" } }
    e.now = 300; S:OnSpellSent(2575, "Kupfervorkommen"); e.now = 302
    S:OnLootOpened()
    eq(row(S, "gathering.ore"), 1, "Erz")
    e.loot = { { 102, "GameObject-0-1-2-3-55-0" } }
    e.now = 400; S:OnSpellSent(2575); e.now = 402
    S:OnLootOpened()
    eq(row(S, "gathering.other") + row(S, "gathering.ore") + row(S, "gathering.herb"), 3, "ohne Material kein Knoten")
end)

test("Kürschnern: direkt nach einem erfolgreichen Zauber, sonst Beute", function()
    local e = setup()
    local S = e.S
    e.loot = { { 102, "Creature-0-1-2-3-77-0000" } }
    S:OnLootOpened()
    eq(row(S, "kills"), 1, "erst Beute: Kill"); eq(row(S, "skinning"), 0, "noch kein Kürschnern")

    e.now = 105
    S:OnSpellSucceeded(8613)
    S:OnLootOpened()
    eq(row(S, "skinning"), 1, "Kürschnern"); eq(row(S, "kills"), 1, "der Kill zählt nicht noch einmal")
end)

test("Kürschnern: nur nach dem Zauber Kürschnern, nicht nach anderen Zaubern", function()
    local e = setup()
    local S = e.S
    e.loot = { { 102, "Creature-0-1-2-3-77-0000" } }

    -- Kill mit einem Sofortzauber, automatisches Looten kurz danach: Beute, kein Kürschnern
    e.now = 105
    S:OnSpellSucceeded(133)
    S:OnLootOpened()
    eq(row(S, "skinning"), 0, "anderer Zauber ist kein Kürschnern")
    eq(row(S, "kills"), 1, "zählt als Kill der Beute")

    -- ein Rang aus einem echten Ablauf (8617) und ein Zauber mit demselben Namen
    e.loot = { { 102, "Creature-0-1-2-3-78-0000" } }
    e.now = 200
    S:OnSpellSucceeded(8617)
    S:OnLootOpened()
    eq(row(S, "skinning"), 1, "Rang 8617")

    S.api.GetSpellName = function(id) return (id == 8613 or id == 99999) and "Kürschnern" or "Anderes" end
    e.loot = { { 102, "Creature-0-1-2-3-79-0000" } }
    e.now = 300
    S:OnSpellSucceeded(99999)
    S:OnLootOpened()
    eq(row(S, "skinning"), 2, "gleicher Name wie Kürschnern")
end)

test("Ereignisse: Events.lua verbindet Spiel und Sammler, Fehler stören nicht", function()
    local e = setup()
    local S = e.S
    stub.load("Core/Events.lua", "Glimpse_Statistics")
    local handler = S.eventFrame.scripts.OnEvent
    S:StartCollecting()
    assert(S.eventFrame.events.LOOT_OPENED and S.eventFrame.events.UNIT_SPELLCAST_SENT, "Ereignisse angemeldet")

    handler(nil, "UNIT_SPELLCAST_SENT", "player", "", "guid", 7620)
    eq(row(S, "fishing.casts"), 1, "Wurf über das Ereignis")
    assert(S.diag.partyKill and S.eventFrame.events.PARTY_KILL, "PARTY_KILL angemeldet")
    e.units.player = { guid = "Player-1-A", name = "Ich" }
    handler(nil, "PARTY_KILL", "Player-1-A", "Creature-0-1-2-3-77-0000")
    eq(row(S, "kills"), 1, "Kill über PARTY_KILL")

    -- ohne PARTY_KILL (Client kennt es nicht): Tod des Ziels als Ersatz
    S.diag.partyKill = false
    e.units.target = { guid = "Creature-0-1-2-3-78-0000", name = "Wolf", dead = true }
    handler(nil, "PLAYER_REGEN_ENABLED")
    eq(row(S, "kills"), 2, "Kill über den Tod des Ziels")

    S.api.GetNumLootItems = function() error("kaputt") end
    handler(nil, "LOOT_OPENED")
    eq(S.errorCount, 1, "Fehler vermerkt"); assert(S.lastError:find("LOOT_OPENED", 1, true), "mit Ereignis")
    S:StopCollecting()
    eq(next(S.eventFrame.events), nil, "abgemeldet")
end)

test("Kills ohne Beute: Gesundheit 0, Nachprüfung nach Kampfende, gesperrte Werte", function()
    local e = setup()
    local S = e.S
    local api = S.api

    -- UnitIsDead noch false, aber Gesundheit 0: zählt als tot
    e.units.target = { guid = "Creature-0-1-2-3-55-0000", name = "Eber", dead = false }
    api.UnitHealth = function() return 0 end
    S:OnTargetEvent("UNIT_HEALTH")
    eq(row(S, "kills"), 1, "Gesundheit 0 zählt")

    -- Nachprüfung nach Kampfende: erst später als tot gemeldet
    local timers = {}
    api.After = function(_delay, fn) timers[#timers + 1] = fn end
    api.UnitHealth = nil
    e.units.target = { guid = "Creature-0-1-2-3-56-0000", name = "Wolf", dead = false }
    S:OnTargetEvent("PLAYER_REGEN_ENABLED")
    eq(row(S, "kills"), 1, "noch nicht tot")
    eq(#timers, 2, "zwei Nachprüfungen geplant")
    e.units.target.dead = true
    for _, fn in ipairs(timers) do fn() end
    eq(row(S, "kills"), 2, "nach dem Kampf gezählt, nur einmal")

    -- gesperrter Wert: nichts gezählt, aber vermerkt
    S.Clean = S.Clean
    local before = S.diag.secret
    e.Glimpse.IsSecret = function(_, value) return value == "geheim" end
    api.UnitIsDead = function() return "geheim" end
    S:CheckTargetKill()
    eq(S.diag.secret, before + 1, "gesperrt vermerkt")
    eq(row(S, "kills"), 2, "nichts gezählt")
end)

test("Debug-Modus: Chatausgabe mit Präfix für Erkennung und Datenbank, sonst still", function()
    local e = setup()
    local S, Glimpse = e.S, e.Glimpse
    Glimpse.printed = {}
    e.units.target = { guid = "Creature-0-1-2-3-77-0000", name = "Wolf", dead = true }
    S:OnTargetEvent("UNIT_HEALTH")
    eq(#Glimpse.printed, 0, "ohne Debug-Modus keine Ausgabe")

    Glimpse.IsDebug = function() return true end
    e.units.target = { guid = "Creature-0-1-2-3-78-0000", name = "Eber", dead = true }
    S:OnTargetEvent("UNIT_HEALTH")
    local text = table.concat(Glimpse.printed, "\n")
    assert(text:find("[Statistics]", 1, true), "Präfix")
    assert(text:find("Kill detected: Eber [78] via target death", 1, true), "Erkennung\n" .. text)
    assert(text:find("DB write: kills +1 [78 Eber = 1]", 1, true), "Datenbank\n" .. text)
    assert(text:find("DB write: kills.zone +1", 1, true), "alle Zähler")

    -- Fischen
    Glimpse.printed = {}
    S:CountCast(7620)
    text = table.concat(Glimpse.printed, "\n")
    assert(text:find("Fishing cast detected", 1, true) and text:find("DB write: fishing.casts +1", 1, true), text)
end)

test("Debug-Modus: wiederholte Prüfung desselben toten Ziels bleibt still", function()
    local e = setup()
    local S, Glimpse = e.S, e.Glimpse
    Glimpse.IsDebug = function() return true end
    e.units.target = { guid = "Creature-0-1-2-3-78-0000", name = "Eber", dead = true }
    S:OnTargetEvent("UNIT_HEALTH")
    Glimpse.printed = {}
    S:OnTargetEvent("UNIT_HEALTH"); S:OnTargetEvent("PLAYER_REGEN_ENABLED")
    eq(#Glimpse.printed, 0, "keine Meldung für dieselbe Leiche")
    eq(row(S, "kills"), 1, "nur einmal gezählt")

    -- ein zweiter Eber (andere GUID) zählt
    e.units.target = { guid = "Creature-0-1-2-3-78-0000A", name = "Eber", dead = true }
    S:OnTargetEvent("PLAYER_TARGET_CHANGED")
    eq(row(S, "kills"), 2, "gleicher Typ, andere Leiche zählt")
end)

test("Kills: PARTY_KILL zählt Kills von uns und dem Haustier, auch ohne Ziel, einmal", function()
    local e = setup()
    local S = e.S
    e.units.player = { guid = "Player-1-A", name = "Ich" }
    e.units.pet = { guid = "Creature-0-1-2-3-999-PET", name = "Bär" }

    -- Hase war Ziel (Name gemerkt), dann Ziel gewechselt, dann stirbt er
    e.units.target = { guid = "Creature-0-1-2-3-721-0000A", name = "Hase", dead = false }
    S:OnTargetEvent("PLAYER_TARGET_CHANGED")
    e.units.target = { guid = "Creature-0-1-2-3-113-0000B", name = "Eber", dead = false }
    S:OnTargetEvent("PLAYER_TARGET_CHANGED")
    S:OnPartyKill("Player-1-A", "Creature-0-1-2-3-721-0000A")
    eq(S.account.by.kills[721].n, 1, "Hase gezählt")
    eq(S.account.by.kills[721].name, "Hase", "mit gemerktem Namen")

    -- dieselbe Leiche nochmal und Kill eines Fremden
    S:OnPartyKill("Player-1-A", "Creature-0-1-2-3-721-0000A")
    S:OnPartyKill("Player-9-Z", "Creature-0-1-2-3-50-0000C")
    eq(row(S, "kills"), 1, "nicht doppelt, Fremde nicht")

    -- Haustier, Opfer unbekannt (kein Name)
    S:OnPartyKill("Creature-0-1-2-3-999-PET", "Creature-0-1-2-3-30-0000D")
    eq(S.account.by.kills[30].n, 1, "Kill des Haustiers")
    eq(S.account.by.kills[30].name, nil, "ohne Namen")

    -- Spieler als Opfer zählt nicht
    S:OnPartyKill("Player-1-A", "Player-2-B")
    eq(row(S, "kills"), 2, "Spieler zählen nicht")

    -- mit PARTY_KILL ist der Tod des Ziels nur Ersatz
    S.diag.partyKill = true
    e.units.target = { guid = "Creature-0-1-2-3-77-0000E", name = "Wolf", dead = true }
    S:OnTargetEvent("UNIT_HEALTH")
    eq(row(S, "kills"), 2, "Tod des Ziels zählt nicht, wenn PARTY_KILL aktiv ist")
    S.diag.partyKill = nil
end)

test("Trace: feste Liste anmelden, Lärm und fremde Einheiten filtern, mute, Zusammenfassung", function()
    local e = setup()
    local S, Glimpse = e.S, e.Glimpse
    stub.load("Modules/Trace/Trace.lua", "Glimpse_Statistics")
    local registeredAll = false
    S.traceFrame.RegisterAllEvents = function() registeredAll = true end
    Glimpse.printed = {}
    eq(S:Trace(""), true, "an")
    eq(registeredAll, false, "nie alle Ereignisse auf einmal (das löst Sperrmeldungen aus)")
    assert(S.traceFrame.events.PARTY_KILL and S.traceFrame.events.UNIT_SPELLCAST_SENT and S.traceFrame.events.LOOT_OPENED, "Liste angemeldet")
    eq(S.traceFrame.events.COMBAT_LOG_EVENT_UNFILTERED, nil, "Kampflog nie angemeldet")

    e.units.target = { guid = "Creature-0-1-2-3-77-0000", name = "Wolf", dead = true }
    local handler = S.traceFrame.scripts.OnEvent
    Glimpse.printed = {}
    handler(nil, "PARTY_KILL", "Player-1-A", "Creature-0-1-2-3-77-0000")
    assert(Glimpse.printed[1]:find("PARTY_KILL(Player-1-A, Creature-0-1-2-3-77-0000) target=Wolf dead=true", 1, true), Glimpse.printed[1])
    assert(Glimpse.printed[1]:find("%[%d+%.%d%d%]"), "mit Zeit")

    handler(nil, "COMBAT_LOG_EVENT_UNFILTERED")
    handler(nil, "CHAT_MSG_COMBAT_XP_GAIN", "Wolf stirbt.")
    handler(nil, "CHAT_MSG_SPELL_SELF_DAMAGE", "x")
    eq(#Glimpse.printed, 1, "gesperrte Ereignisse nie ausgegeben")
    handler(nil, "UNIT_AURA", "target")
    handler(nil, "ACTIONBAR_UPDATE_STATE")
    handler(nil, "UNIT_HEALTH", "party1")
    eq(#Glimpse.printed, 1, "Lärm und fremde Einheiten gefiltert")
    handler(nil, "UNIT_DIED", "Creature-0-1-2-3-77-0000")
    eq(#Glimpse.printed, 2, "UNIT_DIED mit GUID erscheint")
    Glimpse.printed[2] = nil
    handler(nil, "UNIT_HEALTH", "nameplate3")
    eq(#Glimpse.printed, 2, "Namensplakette erscheint")

    S:Trace("mute UNIT_HEALTH"); handler(nil, "UNIT_HEALTH", "target")
    eq(#Glimpse.printed, 3, "nur die mute-Meldung, Ereignis stumm")
    S:Trace("unmute unit_aura"); handler(nil, "UNIT_AURA", "target")
    eq(#Glimpse.printed, 5, "unmute zeigt wieder")

    -- ohne Filter
    eq(S:Trace(""), false, "aus")
    assert(Glimpse.printed[#Glimpse.printed]:find("trace off. Most frequent events:", 1, true), "Zusammenfassung")
    eq(S:Trace("all"), true, "an ohne Filter")
    local before = #Glimpse.printed
    handler(nil, "ACTIONBAR_UPDATE_STATE")
    handler(nil, "CHAT_MSG_COMBAT_XP_GAIN", "Wolf stirbt.")
    eq(#Glimpse.printed, before + 1, "alles sichtbar, nur nicht die gesperrten")
    eq(row(S, "kills"), 0, "der Ablauf zählt nichts")
    S:Trace("")

    -- full: alles auf einmal, die gesperrten wieder abgemeldet
    registeredAll = false
    S.traceFrame.RegisterAllEvents = function(self) registeredAll = true; self.events.COMBAT_LOG_EVENT_UNFILTERED = true end
    S.traceFrame.UnregisterEvent = function(self, event) self.events[event] = nil end
    S:Trace("full")
    eq(registeredAll, true, "full meldet alle an")
    eq(S.traceFrame.events.COMBAT_LOG_EVENT_UNFILTERED, nil, "Kampflog wieder abgemeldet")
    S:Trace("")

    -- Ersatz ohne RegisterAllEvents: bekannte einzeln, Unbekanntes genannt
    S.traceFrame.RegisterEvent = function(self, event)
        if event == "PARTY_KILL" then error("unknown event") end
        self.events[event] = true
    end
    Glimpse.printed = {}
    S:Trace("")
    local text = table.concat(Glimpse.printed, "\n")
    assert(text:find("unknown to this client: PARTY_KILL", 1, true), text)
    assert(S.traceFrame.events.PLAYER_XP_UPDATE, "bekanntes angemeldet")
    eq(S.traceFrame.events.CHAT_MSG_COMBAT_XP_GAIN, nil, "gesperrtes nie angemeldet")
    eq(S.traceFrame.events.COMBAT_LOG_EVENT_UNFILTERED, nil, "Kampflog nie angemeldet")
    S:Trace("")
    eq(next(S.traceFrame.events), nil, "abgemeldet")
end)

-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Werkzeuge zur Fehlersuche, die (noch) in Statistics liegen: Event-Trace (Modules/Trace) und die Anzeige der
-- Blizzard-Statistik (Core/Blizzard.lua)

test("Trace: feste Liste anmelden, Lärm und fremde Einheiten filtern, mute, Zusammenfassung", function()
    local S, Glimpse = stub.setup()
    local units = {}
    S.api.GetTime = function() return 100 end
    S.api.UnitName = function(unit) return units[unit] and units[unit].name end
    S.api.UnitIsDead = function(unit) return units[unit] and units[unit].dead or false end
    local registeredAll = false
    S.traceFrame.RegisterAllEvents = function() registeredAll = true end
    Glimpse.printed = {}
    eq(S:Trace(""), true, "an")
    eq(registeredAll, false, "nie alle Ereignisse auf einmal (das löst Sperrmeldungen aus)")
    assert(S.traceFrame.events.PARTY_KILL and S.traceFrame.events.UNIT_SPELLCAST_SENT and S.traceFrame.events.LOOT_OPENED, "Liste angemeldet")
    eq(S.traceFrame.events.COMBAT_LOG_EVENT_UNFILTERED, nil, "Kampflog nie angemeldet")

    units.target = { guid = "Creature-0-1-2-3-77-0000", name = "Wolf", dead = true }
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
    eq(S:Get("kills"), 0, "der Ablauf zählt nichts")
    assert(Glimpse.logged[1]:find("[Glimpse:Statistics/trace]", 1, true), "Zeilen auch im Log des Core")
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

test("Blizzard-Statistiken lesen (Schnittstelle fehlt / vorhanden)", function()
    local S = stub.setup()
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

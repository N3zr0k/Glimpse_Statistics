local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local S = Glimpse:GetModule("Statistics")
local L = S.L

-- Die Zähler, die Statistics zeigt. Der Schlüssel ist der Name in /gli stats und in der API, dahinter stehen
-- Namespace und Art in Glimpse: Database (Arten siehe DEVELOPER.md des Core, "Übernahme alter Daten"):
--   names     wie die IDs der Aufschlüsselung heißen (Names.lua); ohne names gibt es nur ID 0
--   zones     Aufschlüsselung nach Zone
--   baseline  Startwert aus der Blizzard-Statistik (Herkunft baseline) zählt in der Gesamtsumme mit,
--             nie in Zeiträumen, Quoten und Aufschlüsselungen
--   tier      Art mit denselben Werten je Berufsstufe (ID = höchste Fertigkeit der Stufe), profession dazu
--   id        nur diese ID der Art (z. B. Tiefenbahn = Fortbewegungsart 8), ohne Aufschlüsselung
--   unit      "time" (Sekunden), "distance" (Yards), "distinct" (Anzahl verschiedener IDs, ohne Zeiträume);
--             ohne unit eine Anzahl
S.COUNTERS = {
    { key = "kills", ns = "combat", kind = "kill", label = L["Creatures killed"], group = L["Combat"],
        names = "npc", zones = true, baseline = true },
    { key = "deaths", ns = "combat", kind = "death", label = L["Deaths"], group = L["Combat"],
        names = "npc", zones = true, baseline = true },
    { key = "combat.time", ns = "combat", kind = "time", label = L["Time in combat"], group = L["Combat"], unit = "time" },
    { key = "combat.looted", ns = "combat", kind = "looted", label = L["Corpses looted"], group = L["Combat"],
        names = "npc", zones = true },
    { key = "fishing.casts", ns = "fishing", kind = "cast", label = L["Fishing casts"], group = L["Fishing"],
        zones = true, tier = "casttier", profession = "fishing" },
    { key = "fishing.catches", ns = "fishing", kind = "catch", label = L["Fishing catches"], group = L["Fishing"],
        zones = true, baseline = true, tier = "catchtier", profession = "fishing" },
    { key = "fishing.items", ns = "fishing", kind = "fish", label = L["Fish caught"], group = L["Fishing"],
        names = "item", zones = true },
    { key = "skinning", ns = "gathering", kind = "skin", label = L["Creatures skinned"], group = L["Gathering"],
        names = "npc", zones = true },
    { key = "gathering.herb", ns = "gathering", kind = "herb", label = L["Herbs gathered"], group = L["Gathering"],
        names = "object", zones = true },
    { key = "gathering.ore", ns = "gathering", kind = "ore", label = L["Ore gathered"], group = L["Gathering"],
        names = "object", zones = true },
    { key = "gathering.other", ns = "gathering", kind = "other", label = L["Other nodes gathered"], group = L["Gathering"],
        names = "object", zones = true },
    { key = "travel.distance", ns = "travel", kind = "distance", label = L["Distance travelled"], group = L["Travel"],
        names = "mode", unit = "distance" },
    { key = "travel.time", ns = "travel", kind = "traveltime", label = L["Time on the move"], group = L["Travel"],
        names = "mode", unit = "time" },
    { key = "travel.zones", ns = "travel", kind = "zone", label = L["Zones visited"], group = L["Travel"],
        names = "zone", unit = "distinct" },
    { key = "travel.zonetime", ns = "travel", kind = "zonetime", label = L["Time in zones"], group = L["Travel"],
        names = "zone", unit = "time" },
    { key = "travel.flightpoints", ns = "travel", kind = "flightpoint", label = L["Flight points known"],
        group = L["Travel"], names = "flightpoint", unit = "distinct" },
    { key = "travel.teleports", ns = "travel", kind = "teleport", label = L["Teleports"], group = L["Travel"] },
    { key = "travel.flights", ns = "travel", kind = "flight", label = L["Flights"], group = L["Travel"], names = "route" },
    { key = "travel.flighttime", ns = "travel", kind = "flighttime", label = L["Flight time"], group = L["Travel"],
        names = "route", unit = "time" },
    { key = "travel.flightdistance", ns = "travel", kind = "flightdistance", label = L["Flight distance"],
        group = L["Travel"], names = "route", unit = "distance" },
    { key = "tram.rides", ns = "travel", kind = "tram", label = L["Rides"], group = L["Deeprun Tram"], names = "tramstop" },
    { key = "tram.distance", ns = "travel", kind = "distance", id = 8, label = L["Distance"], group = L["Deeprun Tram"],
        unit = "distance" },
    { key = "tram.time", ns = "travel", kind = "traveltime", id = 8, label = L["Riding time"], group = L["Deeprun Tram"],
        unit = "time" },
    { key = "tram.stay", ns = "travel", kind = "zonetime", id = -369, label = L["Time spent"], group = L["Deeprun Tram"],
        unit = "time" },
    -- Sprünge mit der Leertaste zählt das Modul Reisen mit, sie gehören aber zum Charakter
    { key = "jumps", ns = "travel", kind = "jump", label = L["Jumps"], group = L["Character"] },
}

S.counterByKey = {}
local byKind = {} -- "Namespace/Art" -> Zähler, auch für die Stufen-Art

for _, counter in ipairs(S.COUNTERS) do
    S.counterByKey[counter.key] = counter
    -- erster Zähler einer Art meldet Änderungen (Tiefenbahn teilt sich die Arten mit Reisen)
    byKind[counter.ns .. "/" .. counter.kind] = byKind[counter.ns .. "/" .. counter.kind] or counter
    if counter.tier then byKind[counter.ns .. "/" .. counter.tier] = counter end
end

--- Zähler zu Namespace und Art aus Database, nil wenn Statistics die Art nicht zeigt.
function S:CounterOf(nsName, kind)
    return byKind[tostring(nsName) .. "/" .. tostring(kind)]
end

--- Alle Zähler in Anzeigereihenfolge.
function S:GetCounters()
    return self.COUNTERS
end

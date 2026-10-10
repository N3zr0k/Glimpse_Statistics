local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Auswertung und Anzeige der Zähler aus Glimpse: Database. Statistics erfasst selbst nichts:
--   combat     Glimpse (Modul Kampf): Kills, Tode, Zeit im Kampf, geplünderte Leichen
--   fishing    Glimpse: Professions: Würfe, Fänge, Fische, je Berufsstufe
--   gathering  Glimpse: Gathering: Kräuter, Erz, sonstige Knoten, Kürschnern
--   travel     Glimpse (Modul Reisen): Strecke, Zeit, Zonen, Flugpunkte, Flüge
-- Fehlt ein Namespace, fehlen nur seine Zähler. Zähler: Counters.lua, Lesen: Data.lua, Namen: Names.lua,
-- öffentliche API: Api.lua (API_VERSION 5).
--
-- GlimpseStatisticsDB bleibt in der TOC, damit Database die Daten bis 0.1.56 übernehmen kann (AlphaMigration).
-- Statistics liest daraus nur noch Namen (Names.lua) und schreibt nichts hinein.
local S = Glimpse:NewModule("Statistics", nil, "AceEvent-3.0")
S.L = L
S.API_VERSION = 5
S.MESSAGE_UPDATED = "GLIMPSE_STATISTICS_UPDATED"

-- Zugriff ohne GetModule
Glimpse.Statistics = S

-- Blizzard-API gebündelt, damit Tests sie ersetzen können
S.api = {
    GetTime = GetTime,
    UnitName = UnitName,
    UnitIsDead = UnitIsDead,
    GetItemNameByID = C_Item and C_Item.GetItemNameByID or nil,
    GetSpellInfo = GetSpellInfo,
    GetSpellSubtext = C_Spell and C_Spell.GetSpellSubtext or nil,
    GetProfessions = GetProfessions,
    GetProfessionInfo = GetProfessionInfo,
    GetTaxiNodesForMap = C_TaxiMap and (C_TaxiMap.GetTaxiNodesForMap or C_TaxiMap.GetAllTaxiNodes) or nil,
}

-- Einstellungen im Namespace "Statistics" von Glimpse.db: Aussehen des Fensters je Profil, Position und ob es offen
-- war je Charakter (Display/Window.lua)
S.defaults = {
    profile = { windowScope = "all", windowFrame = false, windowFontSize = 12 },
    char = { windowStatus = {}, windowOpen = false, windowCollapsed = {} },
}

function S:OnInitialize()
    self.debug = Glimpse:NewDebugger("Statistics", { "data", "trace" })
    self.settings = Glimpse.db:RegisterNamespace("Statistics", self.defaults)

    Glimpse:RegisterAddonOptions(ADDON_NAME, self:BuildOptions(), true)
end

function S:OnEnable()
    self:RegisterProbes()
    local DB = self:Database()
    if DB then
        DB.RegisterCallback(self, DB.EVENT_CHANGED, "OnDataChanged")
    else
        self.debug:Error("data", "Glimpse: Database is missing, nothing to show")
    end
    self:RestoreWindow()
end

--- Änderung in Database: Nachricht für andere Addons und Fenster neu zeichnen. Fremde Arten (z. B. Beute) zählen nicht.
function S:OnDataChanged(_, nsName, kind)
    local key, topic, metric
    if nsName then
        local counter = self:CounterOf(nsName, kind)
        if not counter then return end
        key = counter.key
        topic, metric = self:TopicOfKey(key)
    else
        self:ForgetSince()
    end
    self:SendMessage(self.MESSAGE_UPDATED, key, topic, metric)
    self:OnCountersChanged()
end

--- nil für Secret Values.
function S.Clean(value)
    if value ~= nil and Glimpse:IsSecret(value) then return nil end
    return value
end

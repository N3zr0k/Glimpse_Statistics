# Glimpse: Statistics – Dateien

Alle Dateien im Addon-Ordner `Glimpse_Statistics/`, in Ladereihenfolge. Statistics schreibt nichts in Glimpse: Database,
es liest nur. Namespaces in Database: `combat` (Schreiber Glimpse, Modul Kampf), `travel` (Glimpse, Modul Reisen),
`fishing` (Glimpse: Professions), `gathering` (Glimpse: GatheringDB).

| Datei | Beschreibung | Database | Weitere Abhängigkeiten |
|---|---|---|---|
| `Glimpse_Statistics.toc` | Metadaten, lädt nur `Glimpse_Statistics.xml` | – | Benötigt Glimpse und Glimpse_Database (min. Core 0.3.21). SavedVariables `GlimpseStatisticsDB` nur noch für die AlphaMigration von Database |
| `Glimpse_Statistics.xml` | Lädt Locales, Core, Modules, Commands in dieser Reihenfolge | – | – |
| `Locales/Locales.xml` | Lädt die Sprachdateien, `enUS` zuerst | – | – |
| `Locales/enUS.lua` | Englische Texte (Standard) | – | AceLocale-3.0 |
| `Locales/deDE.lua` | Deutsche Texte | – | AceLocale-3.0 |
| `Core/Core.xml` | Lädt die Core-Dateien, `Statistics.lua` zuerst | – | – |
| `Core/Statistics.lua` | Legt das Modul an, Blizzard-API-Tabelle (auch `C_TaxiMap`), Einstellungen, reagiert auf Änderungen in Database und sendet `GLIMPSE_STATISTICS_UPDATED` | liest: Callback `EVENT_CHANGED` | Glimpse (`NewModule`, `NewDebugger`, `RegisterAddonOptions`), Einstellungen im Namespace `Statistics` von `Glimpse.db`, AceEvent-3.0 |
| `Core/Counters.lua` | Liste der angezeigten Zähler, welcher Namespace, welche Art und ggf. welche ID dahinter steht (Tiefenbahn), Einheit (Zeit, Strecke, verschiedene IDs) | – (nur Zuordnung) | – |
| `Core/Names.lua` | Namen für IDs der Aufschlüsselung (Item, Zone, NPC, Objekt, Fortbewegungsart, Flugpunkt, Flugstrecke, Ziel der Tiefenbahn) | liest: Orte der Flugpunkte in `travel` | Modul Locations (Zonennamen), Item-Cache des Clients, `C_TaxiMap` (Flugpunkt-Namen), liest alte Namen aus `GlimpseStatisticsDB` |
| `Core/Data.lua` | Alle Lesezugriffe: Summen, Zeiträume, Aufschlüsselung, Tagesverlauf, Stufen, Charaktere | liest: `combat`, `travel`, `fishing`, `gathering`; Charakterliste | `GlimpseDB` |
| `Core/Tiers.lua` | Berufsstufen und ihre Namen (Lehrling ...) für Angeln | – (Werte über `Data.lua`) | Blizzard: `GetProfessions`, `GetProfessionInfo`, Zauber-Subtext |
| `Core/Api.lua` | Öffentliche API für andere Addons (`API_VERSION` 5): `GetInfo`, `GetTopicList`, `Query` | liest über `Data.lua` | – |
| `Core/Blizzard.lua` | Liest die Blizzard-Statistiken für `/gli stats blizzard`, speichert nichts. Soll in den Core | – | Blizzard-Statistik-API (`GetStatistic` ...) |
| `Core/Probes.lua` | Prüfungen `/gli probe stats status\|raw` und Zeilen für `/gli probe db sources` | liest: `combat`, `travel`, `fishing`, `gathering`, Migrationsstand | Glimpse (`RegisterProbe`, `RegisterDataSource`) |
| `Core/Display/DisplayFormat.lua` | Zahlen je Einheit: Tausendertrennung, Zeit ("3 h 12 min"), Strecke in km oder Meilen | – | – |
| `Core/Display/Display.lua` | Textausgabe für Befehle, Optionen und Fenster (Übersicht, Quoten, Schnitt der Flüge, Zeiträume) | liest über `Data.lua` | – |
| `Core/Display/Window.lua` | Statistikfenster mit und ohne Rahmen | – | AceGUI-3.0, Einstellungen im Namespace `Statistics` |
| `Core/Options.lua` | Optionsseite (Übersicht, Fenster-Einstellungen) | liest über `Display.lua` | Einstellungen im Namespace `Statistics` |
| `Modules/Trace/Trace.xml` | Lädt `Trace.lua` | – | – |
| `Modules/Trace/Trace.lua` | Event-Trace zur Fehlersuche (`/gli stats trace`), zählt nichts. Soll in den Core | – | Glimpse (`AddLogLine`) |
| `Commands/Commands.xml` | Lädt die Slash-Befehle | – | – |
| `Commands/Stats.lua` | `/gli stats` mit allen Unterbefehlen | liest über `Data.lua` | Glimpse (`RegisterCommand`, `ShowTextWindow`) |
| `Media/Icon.tga` | Addon-Icon | – | – |
| `LICENSE` | MIT-Lizenz | – | – |

# Glimpse: Statistics – Funktionen

Stand 0.3.10-alpha.1. Benötigt Glimpse (Core) 0.3.21 oder neuer mit Glimpse: Database.

## Funktionen

| Funktion | Beschreibung | Option (Standard) |
| --- | --- | --- |
| Übersicht | `/gli stats` zeigt alle Zähler je Charakter, Account in Klammern. `account`, `details` und `verbose` erweitern sie. | – |
| Kampf | Getötete Kreaturen und eigene Tode (je Kreatur bzw. Killer und Zone), Zeit im Kampf, geplünderte Leichen. | – |
| Angeln | Würfe und Fänge je Zone, gefangene Fische je Fisch, Fangquote gesamt und je Berufsstufe. | – |
| Sammeln | Gehäutete Kreaturen, gesammelte Kräuter, Erze und andere Objekte je Objekt. | – |
| Reisen | Strecke und Zeit je Fortbewegungsart, besuchte Zonen und Zeit je Zone, bekannte Flugpunkte, Teleports, Flüge, Flugzeit und Flugstrecke je Route, Schnitt der Flüge. | – |
| Tiefenbahn | Fahrten gesamt und je Ziel, Strecke, Fahrzeit (fest 58 s je Fahrt) und Aufenthalt in der Bahn. | – |
| Charakter | Sprünge. | – |
| Zeiträume | Heute, letzte 7 und 30 Tage, ab Mitternacht Ortszeit. Verschiedene Zonen und Flugpunkte haben keine Zeiträume. | – |
| Einheiten | Strecke in km (Deutsch) oder Meilen (Englisch), Zeiten als „3 h 12 min“. | – |
| Aufschlüsselung | `/gli stats <Zähler> [Tage]` zeigt die zehn größten Einträge oder die letzten 14 Tage. | – |
| Startwerte | Kills, Tode und gefangene Fische beginnen mit Blizzards eigener Statistik, ohne Zeiträume und Aufschlüsselung. | – |
| Statistikfenster | Verschiebbar und in der Größe änderbar, mit oder ohne Rahmen, alles oder nur dieser Charakter. | Rahmen, Schriftgröße (8 bis 24) |
| Daten-API | `Query`, `GetInfo`, `GetTopicList` (API_VERSION 5) und die Nachricht `GLIMPSE_STATISTICS_UPDATED` für andere Addons. | – |
| Alte Daten | Zähler von Statistics bis 0.1.56 übernimmt Glimpse: Database beim ersten Login jedes Charakters. | – |
| `/gli stats` Hilfsbefehle | `chars`, `status`, `window`, `blizzard`, `trace`, dazu `/gli probe stats status\|raw`. | – |

## Datenbank

Statistics schreibt nichts in die Datenbank. Alle Werte erfassen der Core und die Berufs-Addons, Statistics liest sie nur.

| Namespace | Daten | Lesen | Schreiben |
| --- | --- | --- | --- |
| `combat` | `kill`, `death`, `time`, `looted` | ja | nein |
| `travel` | `distance`, `traveltime`, `zone`, `zonetime`, `flightpoint`, `teleport`, `jump`, `flight`, `flighttime`, `flightdistance`, `tram`, Orte der Flugpunkte | ja | nein |
| `fishing` | `cast`, `catch`, `casttier`, `catchtier`, `fish` | ja | nein |
| `gathering` | `skin`, `herb`, `ore`, `other` | ja | nein |

Einstellungen (Fenster) liegen nicht in der Datenbank, sondern im Namespace `Statistics` von `Glimpse.db` (Profil).
Außerdem liest Statistics die alte SavedVariables `GlimpseStatisticsDB` (nur Namen und AlphaMigration) und Blizzards Statistik-API.

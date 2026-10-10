# Glimpse: Statistics – Funktionen

Stand 0.3.14-alpha.1. Benötigt Glimpse (Core) 0.3.40 oder neuer mit Glimpse: Database.

## Funktionen

| Funktion | Beschreibung | Option (Standard) |
| --- | --- | --- |
| Übersicht | `/gli stats` zeigt alle Zähler je Charakter, Account in Klammern. `account`, `details` und `verbose` erweitern sie. | – |
| Kampf | Getötete Kreaturen und eigene Tode (je Kreatur bzw. Killer und Zone), Zeit im Kampf, geplünderte Leichen. | – |
| Angeln | Würfe und Fänge je Zone, gefangene Fische je Fisch, Fangquote gesamt und je Berufsstufe. | – |
| Sammeln | Gehäutete Kreaturen, gesammelte Kräuter, Erze und andere Objekte je Objekt. | – |
| Reisen | Strecke mit Schiff oder Zeppelin, besuchte Zonen und Zeit je Zone, bekannte Flugpunkte, Teleports, Flüge, Flugzeit und Flugstrecke je Route, Schnitt der Flüge. Gesamtstrecke und Gesamtzeit nur per Befehl und API. | – |
| Tiefenbahn | Fahrten gesamt und je Ziel, Strecke, Fahrzeit (fest 58 s je Fahrt) und Aufenthalt in der Bahn. | – |
| Charakter | Strecke gelaufen, geritten, geschwommen, getaucht und als Geist, dazu Sprünge. | – |
| Zeiträume | Heute, letzte 7 und 30 Tage, ab Mitternacht Ortszeit. Verschiedene Zonen und Flugpunkte haben keine Zeiträume. | – |
| Einheiten | Strecke in km (Deutsch) oder Meilen (Englisch), unter 1 km in Metern bzw. unter 1 Meile in Yards, Zeiten als „3 h 12 min“. | – |
| Aufschlüsselung | `/gli stats <Zähler> [Tage]` zeigt die zehn größten Einträge oder die letzten 14 Tage. | – |
| Startwerte | Kills, Tode und gefangene Fische beginnen mit Blizzards eigener Statistik, ohne Zeiträume und Aufschlüsselung. | – |
| Statistikfenster | Verschiebbar und in der Größe änderbar, mit oder ohne Rahmen, alles oder nur dieser Charakter. Ein Klick auf die Überschrift einer Gruppe klappt sie ein oder aus, je Charakter gemerkt. | Rahmen, Schriftgröße (8 bis 24) |
| Daten-API | `Query`, `GetInfo`, `GetTopicList` (API_VERSION 5) und die Nachricht `GLIMPSE_STATISTICS_UPDATED` für andere Addons. | – |
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
Außerdem liest Statistics Namen vom Namensdienst des Cores (`Glimpse.IDs:NPCName`, `:ObjectName`) und Blizzards Statistik-API. Statistics hat keine eigenen Saved Variables.

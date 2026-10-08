# Glimpse: Statistics

<p align="center"><img src="docs/icon.png" alt="Statistics icon" width="160"></p>

Counts what you do, per character and for the whole account, with a time stamp for every count, and offers the numbers
to other addons. It collects by itself and needs no other extension.

Requires [Glimpse](https://github.com/N3zr0k/Glimpse) 0.2.2 or newer. For WoW Forever (interface 16001).

## Contents

* [Features](#features)
* [Options](#options)
* [Commands](#commands)
* [Installation](#installation)
* [For developers](#for-developers)
* [Credits](#credits)
* [License](#license)

## Features

| Group | Counters |
| --- | --- |
| Combat | Creatures killed (per creature and per zone), your deaths (per killer and per zone) |
| Fishing | Casts and catches (per zone), fish caught (per fish and per fish and zone), catch rate in total and per profession tier |
| Gathering | Creatures skinned (per creature), herbs, ore and other nodes gathered (per node) |

* **Kills:** every creature the client reports as killed by you or your pet (`PARTY_KILL`), also without target or loot;
  a corpse counts once. Clients without that event fall back to the death of your target and to looted corpses.
* **Deaths:** the client does not say who killed you, so the enemy seen attacking you last is taken as the killer (an estimate).
* **Fishing and gathering:** only fish are counted when fishing, only crafting materials when gathering; chests do not count.
* **Profession tiers:** profession counters are also kept per tier (Apprentice, Journeyman ...), read from the client.
* **Counts from before the installation:** at the first login of each character the addon reads Blizzard's own
  statistics and adds total kills, deaths and fish caught as a starting value (nothing is counted twice). Breakdowns are
  not affected, and the catch rate ignores the starting value.
* **Time stamps:** since when each scope counts, first and last count per counter, and a total per calendar day.
* **Creature tooltips:** how often you killed the creature and how often it killed you, e.g. `[sword] 3(7) · [graveyard] 1(3)`
  (account values in brackets, optional). Position selectable: next to the name, next to the level or in an own line.
* **Statistics window:** the overview in a movable, resizable window, with or without frame.
* **Backup:** export and import of all counters. **Merge** adds the numbers, **Replace** restores a backup; an export
  of this account is not merged back into it.

Everything is stored in `GlimpseStatisticsDB` (per character and account-wide, so deleted characters still count).
Totals are never pruned; a breakdown keeps at most 1000 entries per counter.

## Options

Open them with `/gli config`, then Glimpse > Statistics.

* **Options:** overview, counting on/off, tooltip position, kills and deaths in tooltips, account values, backup, reset
  of the character or the account (with confirmation).
* **Window:** frame, font size (8 to 24), everything or this character only, reset position and size.

## Commands

| Command | Does |
| --- | --- |
| `/gli stats` | Overview of all counters (character, account in brackets) |
| `/gli stats account` | The same with the account numbers |
| `/gli stats <counter> [days]` | Breakdown of a counter (the ten biggest) or its last 14 days, e.g. `/gli stats kills` |
| `/gli stats account <counter> [days]` | The same for the account |
| `/gli stats [<counter>] verbose` | Everything about all counters or one counter |
| `/gli stats debug` | Adds the database as stored (also with `/gli debug on`) |
| `/gli stats status` | Whether counting is on, since when, starting values, last error |
| `/gli stats window` | Opens or closes the statistics window |
| `/gli stats blizzard [text \| all]` | What the client offers of Blizzard's own statistics; a text searches the names |
| `/gli stats trace` | Writes the client events to the chat (troubleshooting), see [docs/EVENTS.md](docs/EVENTS.md) |
| `/gli stats export` / `import` | Backup |

## Installation

Install [Glimpse](https://github.com/N3zr0k/Glimpse/releases) first, then unpack this addon next to it into the AddOns
folder of the Forever client, during the beta for example `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns`.
The folder must be called `Glimpse_Statistics`.

## For developers

Check that the addon is there (`Glimpse.Statistics ~= nil`) and keep working without it.

**Data API** (`Core/Api.lua`, API_VERSION 4): `GetInfo()`, `GetTopicList(kind)`, `RegisterTopic(key, def)` and
`Query({ topics, kind, scope, periods, tiers, breakdown })` return data in a fixed schema, organized in topics
(`fishing`, `herbalism`, `mining`, `skinning`, `kills`, `deaths` and topics of other addons). The full schema is at the top
of `Core/Api.lua`. Message `GLIMPSE_STATISTICS_UPDATED (key, topic, metric)` after every change.

**Own counters:**

```lua
local stats = Glimpse.Statistics
if stats then
    stats:RegisterStat("fishing.casts", "Fishing casts", { group = "Fishing", breakdown = true })
    stats:Add("fishing.casts", 1, mapID)           -- +1 for the character and the account, per zone
    stats:Add("kills", 1, npcID, "Forest Wolf")    -- subKey and name break the counter down
end
```

| Function | Does |
| --- | --- |
| `:RegisterStat(key, label, options)` | Makes a counter known: `options.group`, `options.breakdown`, `options.name(subKey)` |
| `:Add(key, amount, subKey, subName)` | Adds (default 1, negative takes back, never below 0) for the character and the account |
| `:Get(key, scope)` | Value; scope `"char"` (default), `"account"` or `"Name - Realm"` |
| `:GetBreakdown(key, scope, limit)` | List of `{ key, name, count }`, biggest first |
| `:GetSub(key, subKey, scope)` | One breakdown entry (count, first and last time) |
| `:GetCharacters()` | Characters with data, the current one first |
| `:GetRegistered()` | Registered counters |
| `:GetSince(scope)` / `:GetFirst(key, scope)` | Since when the scope counts / first and last change of a counter |
| `:GetSeries(key, scope, fromDay, toDay)` | Totals per day for graphs |
| `:ExportData()` / `:ImportData(text, mode)` | Backup in code, mode `"merge"` or `"replace"` |

The addon lives in the folder `Glimpse_Statistics/` of the repository; link that folder into the AddOns folder
(junction) and `/reload` after each change. The tests need the Glimpse repository next to this one (or `GLIMPSE_DIR`).
Checks:

```
lua tests/run.lua
luacheck .
python3 tools/check.py
```

## Credits

Author: N3zr0k. Special thanks to Flovy and sMash for testing.

The pie chart in the addon icon is based on the icon "Analytics" by Pixel perfect from
[Flaticon](https://www.flaticon.com/free-icon/analytics_731794), pixelated and combined with the database symbol of the
other Glimpse data addons.

## License

MIT, see [LICENSE](LICENSE). LibDeflate in `Glimpse_Statistics/Libs/` has its own license.

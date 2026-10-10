# CurseForge texts: Glimpse: Statistics

Copy the fields into the CurseForge Author Console. Texts are in English. Relations (Required: Glimpse) come from
`.pkgmeta`, do not enter them by hand.

## Project name

Glimpse: Statistics

## Slug

glimpse-statistics

## Summary

Shows what Glimpse records: kills, deaths, fishing, gathering, travel and Deeprun Tram rides, per character and account.

## Categories

Primary: Miscellaneous. Additional: Combat, Professions, Tooltip, Plugins.

## License

MIT License

## Logo

`docs/icon.png`

## Links

- Source: https://github.com/N3zr0k/Glimpse_Statistics
- Issues: https://github.com/N3zr0k/Glimpse_Statistics/issues

## Description

[![latest](https://img.shields.io/github/v/release/N3zr0k/Glimpse_Statistics?include_prereleases&amp;sort=date&amp;label=latest)](https://github.com/N3zr0k/Glimpse_Statistics/releases) [![last push](https://img.shields.io/github/last-commit/N3zr0k/Glimpse_Statistics/main?label=last%20push)](https://github.com/N3zr0k/Glimpse_Statistics/commits/main) [![CI](https://img.shields.io/github/actions/workflow/status/N3zr0k/Glimpse_Statistics/ci.yml?branch=main&amp;label=CI)](https://github.com/N3zr0k/Glimpse_Statistics/actions/workflows/ci.yml)

> ## ⚠ Requires the Glimpse core addon
> **Glimpse: Statistics only works together with [Glimpse](https://www.curseforge.com/wow/addons/glimpse).** Install Glimpse first (version 0.3.21 or newer), otherwise this addon does not load.
> 👉 https://www.curseforge.com/wow/addons/glimpse

**Glimpse: Statistics** shows what Glimpse records, per character and for the whole account. It counts nothing itself: all numbers come from Glimpse: Database.

## What you see

- **Combat:** creatures killed and your deaths (per creature or killer and zone), time in combat, corpses looted
- **Fishing:** casts and catches per zone, fish caught per fish, catch rate in total and per profession tier
- **Gathering:** creatures skinned, herbs, ore and other nodes gathered
- **Travel:** zones visited, flight points, teleports, flights with average flight time, distance by ship or zeppelin
- **Deeprun Tram:** rides per destination, distance, riding time and time spent in the tram
- **Character:** distance walked, ridden, swum, dived and as ghost, jumps

## Good to know

- Today, the last 7 and the last 30 days, and totals; breakdowns by creature, node, fish, zone and route
- Statistics window: movable and resizable, with or without frame, groups can be folded
- Starting values from Blizzard's own statistics (kills, deaths, fish caught); nothing is counted twice
- A group is shown when the addon that records it is installed
- Data API for other addons
- German and English

## Commands

`/gli stats` shows the overview, `/gli stats window` opens the window, `/gli stats kills` breaks down a counter. Options: `/gli config` > Glimpse > Statistics.

## Links

- Core addon: [Glimpse on CurseForge](https://www.curseforge.com/wow/addons/glimpse) · [GitHub](https://github.com/N3zr0k/Glimpse)
- Source, API documentation and issues: [GitHub](https://github.com/N3zr0k/Glimpse_Statistics)
- MIT license

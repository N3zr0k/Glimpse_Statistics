# Changelog

## [Unreleased]

### Changed
- Reads all data from Glimpse: Database; old data is taken over on first start
- No own counting, export, import and reset any more (done by Glimpse and Glimpse: Database)
- Kills and deaths in creature tooltips moved to Glimpse (tab Combat)

### Added
- Character: distance walked, ridden, swum, dived and as ghost
- Statistics window: groups can be folded
- Travel: distance, time on the move, zones, flight points, teleports and flights
- Jumps per character
- Deeprun Tram: rides per destination, ride times, distance and time spent
- Time in combat and corpses looted
- Data sources shown in `/gli probe db sources`
- Data API for other addons (`Query`, topics, catch rate per tier)
- Counters per profession tier
- Starting values from Blizzard's statistics (kills, deaths, fish caught)
- `/gli stats blizzard`: shows Blizzard's own statistics
- Deaths per killer and zone
- Statistics window (`/gli stats window`)
- First version: counters for kills, fishing, gathering and skinning per character and account
- Export, import and reset of all counters

### Changed
- WoW Forever only (interface 16001)
- Fishing counts only fish, no other materials

### Fixed
- Catch rate no longer includes the starting value from Blizzard's statistics (showed e.g. 59583 %)
- Skinning is only counted after the skinning spell
- Kills are recognized via `PARTY_KILL`, also without target or loot

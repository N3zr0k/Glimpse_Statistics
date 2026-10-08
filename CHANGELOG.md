# Changelog

## [Unreleased]

### Added
- Data API for other addons (`Query`, topics, catch rate per tier)
- Counters per profession tier
- Starting values from Blizzard's statistics (kills, deaths, fish caught)
- `/gli stats blizzard`: shows Blizzard's own statistics
- Deaths per killer and zone, shown in creature tooltips
- Statistics window (`/gli stats window`)
- Kills in creature tooltips
- First version: counters for kills, fishing, gathering and skinning per character and account
- Export, import and reset of all counters

### Changed
- WoW Forever only (interface 16001)
- Fishing counts only fish, no other materials

### Fixed
- Catch rate no longer includes the starting value from Blizzard's statistics (showed e.g. 59583 %)
- Skinning is only counted after the skinning spell
- Kills are recognized via `PARTY_KILL`, also without target or loot

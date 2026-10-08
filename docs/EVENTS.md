# Client events seen with `/gli stats trace`

What the game client really delivers, collected from traces on a live client (Dun Morogh, Elwynn Forest; character
with a pet). Meant as a reference for later counters: look here before building something on an event. Everything
below was **observed**; ideas are marked as ideas. Times are `GetTime()` seconds.

Start a trace with `/gli stats trace` (fixed list of events, noise muted, units limited to player, target, pet,
mouseover, focus and nameplates), `trace all` (no filter), `trace full` (every client event, may make the client
report a blocked action). Nothing is counted while tracing.

## Not available to addons

| Event | State |
|---|---|
| `COMBAT_LOG_EVENT_UNFILTERED` and the other combat log events | blocked for addons (never registered by the trace) |
| `CHAT_MSG_COMBAT_*`, `CHAT_MSG_SPELL_*`, `COMBAT_TEXT_*` | combat chat is blocked as well (never registered) |
| `CHAT_MSG_COMBAT_HOSTILE_DEATH`, `CHAT_MSG_COMBAT_FRIENDLY_DEATH`, `UNIT_DESTROYED`, `UNIT_DYNAMIC_FLAGS`, `TRADE_SKILL_UPDATE` | unknown to this client (registering throws, so register with `pcall`) |

Chat escape: `|` must be written `||` in chat output.

## Kills

| Event | Arguments / notes |
|---|---|
| `PARTY_KILL` | `(killerGUID, victimGUID)`, both readable. Fires for your kills, your pet's (killer is then the player GUID in all traces so far) and for group members. Arrives **before** `UNIT_DIED`, also when the victim was never your target and without loot. This is the primary kill source |
| `UNIT_DIED` | `(guid)`: a GUID, not a unit token (a unit filter must let GUIDs pass) |
| `PLAYER_TARGET_DIED` | no arguments, the target died (fallback for clients without `PARTY_KILL`) |
| `PLAYER_XP_UPDATE` | `(player)`, fires together with the kill when it gives experience |
| `UNIT_FLAGS`, `UNIT_HEALTH`, `UNIT_THREAT_*` | follow a kill in a burst for target, nameplates and pet (`UNIT_HEALTH` is nil or secret in combat) |

GUID layout: `Creature-0-<server>-<map>-<instance>-<npcID>-<spawnUID>`; the npcID is the sixth field.

## Combat flow

| Event | Arguments / notes |
|---|---|
| `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` | combat start / end |
| `PLAYER_IN_COMBAT_CHANGED` | `(bool)` |
| `PLAYER_ENTER_COMBAT` / `PLAYER_LEAVE_COMBAT` | melee auto attack on / off |
| `PLAYER_SWING` | `(swingTime, 1)`, e.g. `(1.4, 1)`: one per melee swing |
| `UNIT_COMBAT` | `(unit, "WOUND", flagText, amount, schoolMask)` with readable numbers, e.g. `(target, WOUND, , 5, 1)` (physical) and `(target, WOUND, , 27, 32)` (32 = shadow). Idea: damage dealt, but it also reports damage from others |
| `PET_ATTACK_START` / `PET_ATTACK_STOP` | pet attack |
| `DAMAGE_METER_COMBAT_SESSION_UPDATED`, `DAMAGE_METER_CURRENT_SESSION_UPDATED` | the built-in damage meter changed (idea: source for damage and healing statistics, untested) |

## Spells (fishing, gathering, skinning)

| Event | Arguments / notes |
|---|---|
| `UNIT_SPELLCAST_SENT` | `(unit, targetName, castGUID, spellID)`. For gathering the target name is the node name (`Friedensblume`), for skinning the corpse name |
| `UNIT_SPELLCAST_START` / `_STOP` / `_SUCCEEDED` | `(unit, castGUID, spellID, castBarGUID)`. The same cast also arrives for other unit tokens (`targettarget`, `pet`): always check `unit == "player"` |
| `UNIT_SPELLCAST_FAILED`, `UNIT_SPELLCAST_FAILED_QUIET` | `(unit, castGUID, spellID)` |
| `UNIT_SPELLCAST_CHANNEL_STOP` | `(unit, castGUID, spellID)`: end of a fishing cast |
| `CURRENT_SPELL_CAST_CHANGED` | `(bool)`, noise |

Spell IDs seen: `7620` fishing, `2366` herb gathering, `8617` skinning (rank 2), `695` a damage spell, `7799` a pet spell.
Sequence of a gathering action: `SENT` -> `START` -> `SUCCEEDED` (about 5 s later) -> `LOOT_READY` -> `LOOT_OPENED`.
Fishing messages ("Euer Fisch ist entkommen!", "Es hat kein Fisch angebissen.") arrive as `UI_ERROR_MESSAGE` or
`UI_INFO_MESSAGE` (used by GatheringDB). The skill-up text ("Eure Fertigkeit 'Angeln' hat sich auf 6 erhöht.") appears in
the chat (idea: count skill-ups).

## Loot

| Event | Arguments / notes |
|---|---|
| `LOOT_READY` | `(autoLoot)`, fires twice (before and with `LOOT_OPENED`) |
| `LOOT_OPENED` | `(autoLoot, isFromItem)`; the loot source GUID is `Creature-...` (corpse, skinning) or `GameObject-...` (node) |
| `LOOT_SLOT_CLEARED` | `(slot)`; `LOOT_CLOSED` fires twice |
| `ITEM_PUSH` | `(bagSlot, iconFileID)` |
| `CHAT_MSG_LOOT` | `(text, player, ...)`: item link in `text`, a stack ends in `x3` (`Ihr erhaltet Beute: [Friedensblume]x3`). The amount is **not** in `LOOT_OPENED` counting: Statistics counts a gathering action once per node (idea: also count the amount per item as fishing does) |
| `ITEM_COUNT_CHANGED` | `(itemID)` |

Fishing loot is recognized with `IsFishingLoot()`; corpse loot after the skinning spell is skinning, other corpse loot is
only an extra source for a kill (`PARTY_KILL` comes first).

## Mouse and cursor (what was clicked)

| Event | Arguments / notes |
|---|---|
| `GLOBAL_REGION_MOUSE_DOWN` / `_UP` | `(region or nil, button)`, `nil` for clicks in the world |
| `WORLD_CURSOR_TOOLTIP_UPDATE` | `(1 or 0)`: the cursor is over (1) or left (0) a world object |
| `UPDATE_MOUSEOVER_UNIT` | the mouseover unit changed |
| `PLAYER_STARTED_LOOKING` / `PLAYER_STOPPED_LOOKING` | camera drag |

## Noise (muted by default in the trace)

`ACTION_RANGE_CHECK_UPDATE`, `SPELL_RANGE_CHECK_UPDATE`, `ACTION_USABLE_CHANGED`, `PLAYER_EQUIPED_SPELLS_CHANGED`,
`UNIT_FLAGS`/`UNIT_HEALTH` bursts, `DAMAGE_METER_*` (100 per fight), `GLOBAL_REGION_MOUSE_*`. Use `trace mute <EVENT>` and
`trace unmute <EVENT>` to change that.

## Ideas for later counters (not built)

- Amount per item for gathering (`CHAT_MSG_LOOT` or the loot slots, as for fishing).
- Experience (`PLAYER_XP_UPDATE`), skill-ups, deaths (`PLAYER_DEAD`), time in combat (`PLAYER_REGEN_*`).
- Melee swings (`PLAYER_SWING`), damage dealt (`UNIT_COMBAT` for the target, or the damage meter events).
- Kills by a pet or in a group: `PARTY_KILL` already reports them, but they are untested.

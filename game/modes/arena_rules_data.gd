class_name ArenaRulesData
extends Resource
## The arena's numbers a non-coder may tune (cards T12, T15). Owner: Adam (game/modes).
## The respawn delay stays in combat.tres (respawn_sec) until a mode needs its own.

## Seconds after each respawn with no damage and no knockback (healing still works).
## The first spawn of a match gets none, and firing does not end it.
@export_range(0.0, 10.0, 0.1, "suffix:s") var spawn_protection_sec: float = 2.0
## The score limit is this many points for each player on a team (8 players: 64).
@export_range(1, 50, 1) var score_per_player: int = 8
## The longest a match runs; then the higher score wins, and equal scores draw.
@export_range(60.0, 3600.0, 1.0, "suffix:s") var match_length_sec: float = 1200.0
## Seconds from a match's end to the next match (the winner shows meanwhile).
@export_range(3.0, 60.0, 0.5, "suffix:s") var next_match_delay_sec: float = 10.0


## This file's problems in plain words. Empty when the file is fine.
func validate() -> PackedStringArray:
	return DataCheck.ranges(self)

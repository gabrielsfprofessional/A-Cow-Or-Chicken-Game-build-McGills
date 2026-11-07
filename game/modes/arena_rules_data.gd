class_name ArenaRulesData
extends Resource
## The arena's numbers a non-coder may tune (card T12). Owner: Adam (game/modes).
## The respawn delay stays in combat.tres (respawn_sec) until a mode needs its own.

## Seconds after each respawn with no damage and no knockback (healing still works).
## The first spawn of a match gets none, and firing does not end it.
@export_range(0.0, 10.0, 0.1, "suffix:s") var spawn_protection_sec: float = 2.0


## This file's problems in plain words. Empty when the file is fine.
func validate() -> PackedStringArray:
	return DataCheck.ranges(self)

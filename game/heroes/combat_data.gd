class_name CombatData
extends Resource
## Respawn numbers a non-coder may tune. Owner: Gabe (game/heroes). Cards T08, T13.
## Lives here until T15's mode rules take it. Max health is in each HeroData (T13).
## Seconds an eliminated hero waits before it comes back.
@export_range(0.5, 30.0, 0.1, "suffix:s") var respawn_sec: float = 4.0


## This file's problems in plain words. Empty when the file is fine.
func validate() -> PackedStringArray:
	return DataCheck.ranges(self)

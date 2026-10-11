class_name CombatData
extends Resource
## Health and respawn numbers a non-coder may tune. Owner: Gabe (game/heroes). Card T08.
## Lives here until T13's HeroData and T15's mode rules take them.

## Health a hero starts and respawns with.
@export_range(1, 1000, 1) var max_health: int = 100
## Seconds an eliminated hero waits before it comes back.
@export_range(0.5, 30.0, 0.1, "suffix:s") var respawn_sec: float = 4.0

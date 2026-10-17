class_name HealDroneData
extends AbilityData
## A drone over the hero that heals every alive hero near it (card T18): the
## Medic's Heal Drone (data/heal_drone.tres). Owner: Gabe (game/heroes).
## Until T15 adds teams, everyone counts as an ally.

## Health each tick gives each hero in range, in HP.
@export_range(1, 50, 1, "suffix:HP") var heal_per_tick_hp: int = 5
## Seconds between heal ticks. The first falls one tick after the use.
@export_range(0.1, 2.0, 0.05, "suffix:s") var tick_sec: float = 0.5
## How long the drone heals, in seconds. Must be a whole number of ticks.
@export_range(0.5, 10.0, 0.1, "suffix:s") var duration_sec: float = 4.0
## Heroes this close to the healer's centre are healed, in pixels (48 px is one tile).
@export_range(48.0, 480.0, 1.0, "suffix:px") var radius_px: float = 144.0


## Heal ticks per use, from tick_sec through duration_sec.
func tick_count() -> int:
	return roundi(duration_sec / tick_sec) if tick_sec > 0.0 else 0


## The most one use heals one hero, in HP (before the max-health cap).
func total_heal_hp() -> int:
	return tick_count() * heal_per_tick_hp


func node_script_path() -> String:
	return "res://game/heroes/heal_drone.gd"


func validate() -> PackedStringArray:
	var problems := super()
	if tick_sec > 0.0 and is_finite(tick_sec) and is_finite(duration_sec):
		var ticks := duration_sec / tick_sec
		if absf(ticks - roundf(ticks)) > 0.001:
			problems.append("duration_sec is %s s, not a whole number of tick_sec (%s s) ticks; make it a multiple of tick_sec" % [
				String.num(duration_sec), String.num(tick_sec),
			])
	return problems

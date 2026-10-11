class_name WeaponData
extends Resource
## One weapon's numbers, tuned in the Inspector. Owner: Gabe (logic); the .tres
## files in data/ are Adam's. Cards T08, T13. T19 adds the other five weapons.

## Name shown in menus and the HUD.
@export var display_name: String = ""
## Health taken by each hit.
@export_range(1, 200, 1) var damage: int = 20
## Seconds between shots while the fire button is held.
@export_range(0.05, 5.0, 0.01, "suffix:s") var fire_interval_sec: float = 0.3
## True: holding the fire button keeps shooting. False: one shot per click.
@export var automatic: bool = true
## How fast a shot flies, in pixels per second.
@export_range(100.0, 5000.0, 10.0, "suffix:px/s") var projectile_speed: float = 900.0
## Size of a shot, in pixels from its center.
@export_range(1.0, 50.0, 0.5, "suffix:px") var projectile_radius: float = 6.0
## How far a shot flies before it disappears, in pixels.
@export_range(50.0, 5000.0, 10.0, "suffix:px") var range_px: float = 900.0
## Random spread, in degrees either side of the aim. Not used until T19.
@export_range(0.0, 45.0, 0.5, "suffix:deg") var spread_deg: float = 0.0
## Shots per trigger pull. Not used until T19.
@export_range(1, 20, 1) var pellets: int = 1


## This weapon's problems in plain words. Empty when the file is fine.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	DataCheck.require_text(problems, "display_name", display_name)
	problems.append_array(DataCheck.ranges(self))
	return problems

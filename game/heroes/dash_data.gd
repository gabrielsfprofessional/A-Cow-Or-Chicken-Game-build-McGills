class_name DashData
extends AbilityData
## A dash toward the mouse (cards T14, T18): the Bruiser's Shield Charge
## (data/shield_charge.tres) and the Scout's Jet Dash. With knockback_px > 0 it
## knocks back every hero it passes through. Owner: Gabe (game/heroes).

## Fastest a dash or a knockback may go, in px/s. Faster is more than
## RemoteTimeline.SNAP_DISTANCE per 50 ms update, and everyone else would see the
## hero jump instead of slide. tests/data_test.gd keeps the two in step.
const MAX_SPEED_PX_PER_SEC: float = 4000.0

## How far the dash goes, in pixels (48 px is one tile). Walls stop it early.
@export_range(48.0, 960.0, 1.0, "suffix:px") var dash_distance_px: float = 240.0
## How long the dash takes, in seconds.
@export_range(0.05, 1.0, 0.01, "suffix:s") var dash_duration_sec: float = 0.2
## How far each hero the dash passes through is pushed, in pixels. 0 pushes nobody.
@export_range(0.0, 480.0, 1.0, "suffix:px") var knockback_px: float = 96.0
## How long the push takes, in seconds.
@export_range(0.05, 1.0, 0.01, "suffix:s") var knockback_duration_sec: float = 0.2


func _node_script_path() -> String:
	return "res://game/heroes/dash.gd"


func validate() -> PackedStringArray:
	var problems := super()
	_check_speed(problems, "dash", "dash_distance_px", dash_distance_px, "dash_duration_sec", dash_duration_sec)
	_check_speed(problems, "knockback", "knockback_px", knockback_px, "knockback_duration_sec", knockback_duration_sec)
	return problems


## Adds a problem when distance / duration is faster than MAX_SPEED_PX_PER_SEC.
## Skipped when either number is already out of range (that has its own problem).
func _check_speed(problems: PackedStringArray, what: String, distance_field: String, distance: float,
		duration_field: String, duration: float) -> void:
	if not (duration > 0.0) or not is_finite(distance):
		return
	var speed := distance / duration
	if speed > MAX_SPEED_PX_PER_SEC:
		problems.append("%s speed is %d px/s (%s / %s); it must be at most %d px/s, so shorten the distance or lengthen the time" % [
			what, roundi(speed), distance_field, duration_field, roundi(MAX_SPEED_PX_PER_SEC),
		])

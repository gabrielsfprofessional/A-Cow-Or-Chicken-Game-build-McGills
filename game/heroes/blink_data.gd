class_name BlinkData
extends AbilityData
## A jump toward the mouse in one physics tick (card T18): the Mage's Blink
## (data/blink.tres). Walls stop it short; it never goes through one. Owner:
## Gabe (game/heroes).
##
## No speed cap, unlike DashData: everyone else sees the hero snap on purpose
## (RemoteTimeline snaps any jump over SNAP_DISTANCE).

## How far the blink goes, in pixels (48 px is one tile). Walls stop it early.
@export_range(48.0, 480.0, 1.0, "suffix:px") var distance_px: float = 240.0


func node_script_path() -> String:
	return "res://game/heroes/blink.gd"

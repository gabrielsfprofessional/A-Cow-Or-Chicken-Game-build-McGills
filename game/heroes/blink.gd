class_name Blink
extends Ability
## A jump toward the aim in one physics tick (card T18): the Mage's Blink.
## Owner: Gabe (game/heroes). Numbers: a BlinkData file.
##
## - The server grants the distance to the hero's MoveCheck before it tells
##   anyone; the owner runs it as one tick of forced motion when the yes
##   arrives, so move_and_collide casts the whole jump and a wall stops it short.
## - Everyone else's copy snaps (RemoteTimeline.SNAP_DISTANCE).


func _blink() -> BlinkData:
	return data as BlinkData


func _use_on_server(_now: float) -> void:
	# Grant first, so the jump is never judged before it.
	_hero.grant_motion(_blink().distance_px, _one_tick_sec())


func _use_on_owner(direction: Vector2) -> void:
	_hero.start_forced_motion(direction * _blink().distance_px, _one_tick_sec())


func _one_tick_sec() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)

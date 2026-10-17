class_name SpawnProtection
extends RefCounted
## Server only: a hero's spawn protection after a respawn (week-3 seams, for
## T12). Owner: Gabe (game/heroes). Protected while now < the end; from the end
## on, damage and knockback work again. Healing is never blocked.

var _end_sec: float = 0.0


## Starts protection for `duration_sec` from `now_sec`; 0 or less ends it.
func start(now_sec: float, duration_sec: float) -> void:
	_end_sec = now_sec + maxf(0.0, duration_sec)


func stop() -> void:
	_end_sec = 0.0


func is_protected(now_sec: float) -> bool:
	return now_sec < _end_sec

class_name Health
extends Node
## Health for anything that can be shot: a child node named "Health". Owner: Gabe
## (game/heroes). Card T08. The rules live in HealthState.
##
## Knows nothing about heroes or the network: it changes its numbers and emits
## local signals; its parent decides what that looks like (hide, respawn, send).
## Anything on physics layer 2 with a live Health child can be hit (T20's dummies too).
##
## The server calls take_damage(). Clients mirror the server's messages with
## show_damage() and show_elimination(), which emit the same signals.

signal damaged(amount: int, attacker_id: int, shot_id: int, health_after: int, hit_position: Vector2)
signal eliminated(attacker_id: int)
signal restored()

@export var combat: CombatData = preload("res://game/heroes/data/combat.tres")

var _state: HealthState = null


func health() -> int:
	return _rules().health


func max_health() -> int:
	return _rules().max_health


func is_alive() -> bool:
	return not _rules().eliminated


## Server only. Returns the health taken; emits damaged, then eliminated on the hit that reaches 0.
func take_damage(amount: int, attacker_id: int, shot_id: int, hit_position: Vector2) -> int:
	var was_alive := is_alive()
	var taken := _rules().damage(amount)
	if taken > 0:
		damaged.emit(taken, attacker_id, shot_id, _rules().health, hit_position)
	if was_alive and not is_alive():
		eliminated.emit(attacker_id)
	return taken


## Client mirror of a server hit.
func show_damage(amount: int, attacker_id: int, shot_id: int, health_after: int, hit_position: Vector2) -> void:
	if not is_alive():
		return
	_rules().mirror(health_after)
	damaged.emit(amount, attacker_id, shot_id, _rules().health, hit_position)


## Client mirror of a server elimination. Emits once.
func show_elimination(attacker_id: int) -> void:
	if not is_alive():
		return
	_rules().eliminate()
	eliminated.emit(attacker_id)


## Full health and alive again (respawn).
func restore() -> void:
	_rules().restore()
	restored.emit()


## Late join: take the server's state without emitting anything.
func sync(new_health: int, is_eliminated: bool) -> void:
	_rules().sync(new_health, is_eliminated)


## Built on first use, so Health works before _ready and with any `combat` set.
func _rules() -> HealthState:
	if _state == null:
		_state = HealthState.new(combat.max_health)
	return _state

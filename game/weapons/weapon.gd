class_name Weapon
extends Node2D
## A hero's gun: a child named "Weapon" of a NetHero. Owner: Gabe (game/weapons).
## Cards T08, T09. Messages: see game/net/README.md.
##
## - The owner aims and fires from its hero's `input` (T09: the mouse, or a test
##   bot) and, while fire is held, fires every fire_interval_sec, counted on
##   physics ticks. Its own shot is drawn at once; the server's copy decides hits.
## - The server checks each fire message with ShotCheck, starts the shot at its
##   own copy of the hero's center and tells everyone else.
## - Everyone else draws the shot and turns this barrel to its direction.

## The owner fired its shot `shot_id`. Own shots only; T09's bots count them.
signal fired(shot_id: int)

## [Shot] (server refusals) lines per hero at most this often.
const LOG_INTERVAL_MSEC: int = 1000
## Float slack when the cooldown lands exactly on a physics tick.
const COOLDOWN_SLACK_SEC: float = 0.0001

@export var data: WeaponData = preload("res://game/weapons/data/sidearm.tres")

var _hero: NetHero
var _interval_sec: float = 0.3
var _cooldown_sec: float = 0.0
var _shot_id: int = 0
var _check: ShotCheck
## Debug --sim-lag/--sim-jitter: the owner's outgoing fire messages.
var _out_queue: DelayQueue
var _last_log_msec: int = -LOG_INTERVAL_MSEC
var _unlogged_refusals: int = 0
var _last_reason: String = ""


## Own fire-rate multiplier from "--fire-cheat=<x>" (debug builds). 1.0 when not passed.
static func fire_cheat() -> float:
	var value := Net.debug_flag(OS.is_debug_build(), OS.get_cmdline_user_args(), "--fire-cheat=")
	if value.is_valid_float() and value.to_float() > 0.0:
		return value.to_float()
	return 1.0


func _ready() -> void:
	_hero = get_parent() as NetHero
	_interval_sec = data.fire_interval_sec
	if multiplayer.is_server():
		_check = ShotCheck.new(_hero.owner_peer, data.fire_interval_sec)
	elif _hero.is_owned():
		_interval_sec /= fire_cheat()
		_out_queue = DelayQueue.new(Net.sim_lag_msec(), Net.sim_jitter_msec())
	set_physics_process(_out_queue != null)


func _physics_process(delta: float) -> void:
	_drain_outgoing()
	var input := _hero.input
	if input == null:
		return
	var wants := input.fire_held() if data.automatic else input.fire_pressed()
	_cooldown_sec -= delta
	if not _hero.is_alive():
		_cooldown_sec = maxf(_cooldown_sec, 0.0)
		return
	var aim := input.aim()
	if not aim.is_zero_approx():
		rotation = aim.angle()
	if wants and _cooldown_sec <= COOLDOWN_SLACK_SEC:
		_cooldown_sec += _interval_sec
		_fire_own(Vector2.from_angle(rotation))
	elif _cooldown_sec < 0.0:
		_cooldown_sec = 0.0


func _fire_own(direction: Vector2) -> void:
	_shot_id += 1
	var shots := _hero.shots()
	if shots != null:
		shots.add_visual(_hero.owner_peer, _shot_id, _hero.global_position, direction, data)
	if _out_queue.is_active():
		if _out_queue.is_full():
			_send_oldest()
		_out_queue.push(_shot_id, direction, _now_sec(), _hero.life)
	else:
		fire.rpc_id(1, _hero.life, _shot_id, direction)
	fired.emit(_shot_id)


# --- messages (table in game/net/README.md) ------------------------------------

## Owner -> server: I fired shot `shot_id` in life `life`.
@rpc("authority", "call_remote", "reliable", 0)
func fire(life: int, shot_id: int, direction: Vector2) -> void:
	if not multiplayer.is_server() or _check == null:
		return
	var result := _check.check(multiplayer.get_remote_sender_id(), shot_id, life, _hero.life,
		_hero.is_alive(), direction, _now_sec())
	match result:
		ShotCheck.Result.ACCEPTED:
			_start_shot(shot_id, _check.direction)
		ShotCheck.Result.BAD_DIRECTION, ShotCheck.Result.TOO_SOON:
			_refuse(result)
		_:
			return  # Wrong owner, old id, another life or eliminated: dropped silently.


## Server -> every ready peer except the shooter: an accepted shot.
@rpc("any_peer", "call_remote", "reliable", 0)
func receive_shot(shot_id: int, origin: Vector2, direction: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1 or _hero.is_owned():
		return
	if not direction.is_finite() or direction.is_zero_approx():
		return
	rotation = direction.angle()
	var shots := _hero.shots()
	if shots != null:
		shots.add_visual(_hero.owner_peer, shot_id, origin, direction, data)


func _start_shot(shot_id: int, direction: Vector2) -> void:
	rotation = direction.angle()
	var shots := _hero.shots()
	var origin := _hero.global_position
	if shots == null or not shots.start_server_shot(_hero, _hero.owner_peer, shot_id, origin, direction, data):
		return
	for peer: int in multiplayer.get_peers():
		if peer != _hero.owner_peer and _hero.can_receive(peer):
			receive_shot.rpc_id(peer, shot_id, origin, direction)


func _refuse(result: ShotCheck.Result) -> void:
	_unlogged_refusals += 1
	_last_reason = ShotCheck.result_name(result)
	var now := Time.get_ticks_msec()
	if now - _last_log_msec < LOG_INTERVAL_MSEC:
		return
	_last_log_msec = now
	print("[Shot] peer %d: refused %d shot(s), last: %s (%d since spawn)" % [
		_hero.owner_peer, _unlogged_refusals, _last_reason, _check.refused,
	])
	_unlogged_refusals = 0


func _drain_outgoing() -> void:
	var now := _now_sec()
	while _out_queue.is_due(now):
		_send_oldest()


func _send_oldest() -> void:
	fire.rpc_id(1, _out_queue.peek_life(), _out_queue.peek_sequence(), _out_queue.peek_position())
	_out_queue.pop()


## Real time, for the server's check and the sim-lag queue.
func _now_sec() -> float:
	return Time.get_ticks_usec() / 1000000.0

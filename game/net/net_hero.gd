class_name NetHero
extends CharacterBody2D
## A test-world hero that moves online. Owner: Gabe (game/net). Card T07.
## T13/T14 move it into game/heroes. Messages: see game/net/README.md.
##
## - The owner moves it every physics tick from the keyboard and sends
##   (sequence, position) to the server 20 times a second. It never waits.
## - The server checks each update with MoveCheck, keeps the result as its copy
##   and relays accepted ones to everyone else.
## - Everyone else plays it back 100 ms behind with RemoteTimeline.

## Sends per second. physics_ticks_per_second must be a multiple of it.
const SEND_RATE: int = 20
## The server snaps an owner back at most this often while their moves keep failing.
const SNAP_INTERVAL_MSEC: int = 500
## [Move] (server rejects) and [Remote] (underruns) lines per hero at most this often.
const LOG_INTERVAL_MSEC: int = 1000
const MOVEMENT: MovementData = preload("res://game/net/data/movement.tres")

var owner_peer: int = 0
var color: Color = Color.WHITE

var _ticks_per_send: int = 3
var _tick: int = 0
var _sequence: int = 0
var _speed: float = 0.0
var _check: MoveCheck
var _timeline: RemoteTimeline
## Debug --sim-lag/--sim-jitter: owner's outgoing moves, and incoming updates
## (snap-backs on the owner, relays everywhere else).
var _out_queue: DelayQueue
var _in_queue: DelayQueue
var _last_snap_msec: int = -SNAP_INTERVAL_MSEC
var _last_log_msec: int = -LOG_INTERVAL_MSEC
var _unlogged_rejects: int = 0
var _last_reason: String = ""
var _underruns_logged: int = 0


## Called by the spawn function before the hero enters the tree.
func setup(peer_id: int, spawn_position: Vector2, hero_color: Color) -> void:
	owner_peer = peer_id
	name = str(peer_id)
	position = spawn_position
	color = hero_color
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	($Body as ColorRect).color = color
	($PlayerName as Label).text = "Player %d" % owner_peer
	var ticks := Engine.physics_ticks_per_second
	assert(ticks % SEND_RATE == 0, "physics_ticks_per_second must be a multiple of %d" % SEND_RATE)
	if ticks % SEND_RATE != 0:
		push_error("[Move] physics_ticks_per_second (%d) is not a multiple of %d" % [ticks, SEND_RATE])
	@warning_ignore("integer_division")
	_ticks_per_send = maxi(1, ticks / SEND_RATE)
	_speed = MOVEMENT.move_speed
	if multiplayer.is_server():
		_check = MoveCheck.new(owner_peer, position, _speed, _now_sec())
	elif is_owned():
		_speed *= Net.speed_cheat()
	else:
		_timeline = RemoteTimeline.new(position)
	if not multiplayer.is_server():
		_out_queue = DelayQueue.new(Net.sim_lag_msec(), Net.sim_jitter_msec())
		_in_queue = DelayQueue.new(Net.sim_lag_msec(), Net.sim_jitter_msec())
	reset_physics_interpolation()


## True on the client that drives this hero.
func is_owned() -> bool:
	return not multiplayer.is_server() and multiplayer.get_unique_id() == owner_peer


## Remote heroes only: how far ahead the buffer reaches, in milliseconds.
func buffer_depth_msec() -> int:
	return roundi(_timeline.buffer_depth_sec() * 1000.0) if _timeline != null else 0


## Remote heroes only: times the buffer ran dry.
func underruns() -> int:
	return _timeline.underruns if _timeline != null else 0


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		return
	_drain_incoming()
	if is_owned():
		_move_own(delta)
		_drain_outgoing()
	elif _timeline != null:
		global_position = _timeline.sample(_clock_sec())
		if _timeline.take_snap():
			reset_physics_interpolation()
		_log_underruns()


func _move_own(_delta: float) -> void:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = input * _speed
	move_and_slide()
	_tick += 1
	if _tick % _ticks_per_send != 0:
		return
	_sequence += 1
	if _out_queue.is_active():
		if _out_queue.is_full():
			_send_oldest()
		_out_queue.push(_sequence, global_position, _now_sec())
	else:
		submit_move.rpc_id(1, _sequence, global_position)


# --- messages (table in game/net/README.md) ------------------------------------

## Owner -> server: where my hero is after `sequence` sends.
@rpc("authority", "call_remote", "unreliable_ordered", Net.MOVE_CHANNEL)
func submit_move(sequence: int, new_position: Vector2) -> void:
	if not multiplayer.is_server() or _check == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	var result := _check.check(sender, sequence, new_position, _now_sec())
	match result:
		MoveCheck.Result.ACCEPTED:
			global_position = _check.position
			_relay(sequence, _check.position)
		MoveCheck.Result.WRONG_OWNER, MoveCheck.Result.OLD_SEQUENCE:
			return
		_:
			_reject(result)


## Server -> everyone but the owner: an accepted update.
@rpc("any_peer", "call_remote", "unreliable_ordered", Net.MOVE_CHANNEL)
func relay_move(sequence: int, new_position: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1 or _timeline == null:
		return
	_receive(sequence, new_position)


## Server -> owner: that move was refused, go back to the server's position.
@rpc("any_peer", "call_remote", "reliable")
func snap_back(sequence: int, new_position: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_owned():
		return
	_receive(sequence, new_position)


func _relay(sequence: int, new_position: Vector2) -> void:
	var world := get_parent().get_parent()
	for peer: int in multiplayer.get_peers():
		if peer != owner_peer and world.has_method(&"is_peer_ready") and world.is_peer_ready(peer):
			relay_move.rpc_id(peer, sequence, new_position)


func _reject(result: MoveCheck.Result) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_snap_msec >= SNAP_INTERVAL_MSEC:
		_last_snap_msec = now
		snap_back.rpc_id(owner_peer, _check.last_sequence, _check.position)
	_unlogged_rejects += 1
	_last_reason = MoveCheck.result_name(result)
	if now - _last_log_msec >= LOG_INTERVAL_MSEC:
		_last_log_msec = now
		print("[Move] peer %d: rejected %d update(s), last: %s (%d since spawn), snapped back" % [
			owner_peer, _unlogged_rejects, _last_reason, _check.rejected,
		])
		_unlogged_rejects = 0


func _receive(sequence: int, new_position: Vector2) -> void:
	if _in_queue.is_active():
		if _in_queue.is_full():
			_apply(_in_queue.peek_sequence(), _in_queue.peek_position())
			_in_queue.pop()
		_in_queue.push(sequence, new_position, _now_sec())
	else:
		_apply(sequence, new_position)


func _apply(sequence: int, new_position: Vector2) -> void:
	if is_owned():
		global_position = new_position
		velocity = Vector2.ZERO
		reset_physics_interpolation()
	elif _timeline != null:
		_timeline.push(sequence, new_position, _clock_sec())


func _drain_incoming() -> void:
	var now := _now_sec()
	while _in_queue.is_due(now):
		_apply(_in_queue.peek_sequence(), _in_queue.peek_position())
		_in_queue.pop()


func _drain_outgoing() -> void:
	var now := _now_sec()
	while _out_queue.is_due(now):
		_send_oldest()


func _send_oldest() -> void:
	submit_move.rpc_id(1, _out_queue.peek_sequence(), _out_queue.peek_position())
	_out_queue.pop()


func _log_underruns() -> void:
	if _timeline.underruns == _underruns_logged:
		return
	var now := Time.get_ticks_msec()
	if now - _last_log_msec < LOG_INTERVAL_MSEC:
		return
	_last_log_msec = now
	print("[Remote] peer %d: remote buffer ran dry %d time(s) (%d total)" % [
		owner_peer, _timeline.underruns - _underruns_logged, _timeline.underruns,
	])
	_underruns_logged = _timeline.underruns


## Real time, for the server's checks and the sim-lag queues.
func _now_sec() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Steps exactly once per physics tick, so remote playback is even on any screen.
func _clock_sec() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)

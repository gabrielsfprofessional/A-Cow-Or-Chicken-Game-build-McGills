class_name NetHero
extends CharacterBody2D
## A test-world hero that moves and fights online. Owner: Gabe (game/net).
## Cards T07, T08. T13/T14 move it into game/heroes. Messages: see game/net/README.md.
##
## - The owner moves it every physics tick from the keyboard and sends
##   (life, sequence, position) to the server 20 times a second. It never waits.
## - The server checks each update with MoveCheck, keeps the result as its copy
##   and relays accepted ones to everyone else.
## - Everyone else plays it back 100 ms behind with RemoteTimeline.
## - Children: Weapon (aim and fire) and Health (the numbers). Health only
##   emits signals; this script hides the hero, turns its collider off, stops
##   its input and brings it back.
## - Every respawn raises `life`. Moves and fire carry the life they were sent
##   in, and another life's are dropped silently.

## Sends per second. physics_ticks_per_second must be a multiple of it.
const SEND_RATE: int = 20
## The server snaps an owner back at most this often while their moves keep failing.
const SNAP_INTERVAL_MSEC: int = 500
## [Move] (server rejects) and [Remote] (underruns) lines per hero at most this often.
const LOG_INTERVAL_MSEC: int = 1000
const MOVEMENT: MovementData = preload("res://game/net/data/movement.tres")
const COMBAT: CombatData = preload("res://game/heroes/data/combat.tres")

var owner_peer: int = 0
var color: Color = Color.WHITE
## Raised by every respawn; 0 when the hero spawns.
var life: int = 0

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
## While eliminated: when the hero comes back (_now_sec() clock). The server
## respawns it then; clients count down to it for the status line.
var _respawn_at_sec: float = 0.0

@onready var _health: Health = $Health
@onready var _collider: CollisionShape2D = $Collider
@onready var _name_label: Label = $PlayerName


## Called by the spawn function before the hero enters the tree.
func setup(peer_id: int, spawn_position: Vector2, hero_color: Color) -> void:
	owner_peer = peer_id
	name = str(peer_id)
	position = spawn_position
	color = hero_color
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	($Body as ColorRect).color = color
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
	_health.damaged.connect(_on_damaged)
	_health.eliminated.connect(_on_eliminated)
	_update_label()
	reset_physics_interpolation()


## True on the client that drives this hero.
func is_owned() -> bool:
	return not multiplayer.is_server() and multiplayer.get_unique_id() == owner_peer


func is_alive() -> bool:
	return _health.is_alive()


## Seconds until an eliminated hero comes back; 0 while alive.
func respawn_in_sec() -> float:
	return 0.0 if is_alive() else maxf(0.0, _respawn_at_sec - _now_sec())


## Remote heroes only: how far ahead the buffer reaches, in milliseconds.
func buffer_depth_msec() -> int:
	return roundi(_timeline.buffer_depth_sec() * 1000.0) if _timeline != null else 0


## Remote heroes only: times the buffer ran dry.
func underruns() -> int:
	return _timeline.underruns if _timeline != null else 0


## The world's Shots node, or null outside a world that has one.
func shots() -> Shots:
	var world := _world()
	if world == null or not world.has_method(&"shots"):
		return null
	return world.call(&"shots") as Shots


## Server only: true when `peer` may get messages (its world is loaded).
func can_receive(peer: int) -> bool:
	var world := _world()
	return world != null and world.has_method(&"is_peer_ready") and world.call(&"is_peer_ready", peer)


## Server only: tells a peer that just joined this hero's life, health and
## respawn time. The spawner rebuilt the hero from its spawn data, so without
## this the newcomer would see full health and life 0.
func send_combat_state(peer: int) -> void:
	receive_combat_state.rpc_id(peer, life, _health.health(), not is_alive(), respawn_in_sec())


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		if not is_alive() and _now_sec() >= _respawn_at_sec:
			_respawn_on_server()
		return
	_drain_incoming()
	if is_owned():
		# Eliminated: no input, no sends, and the sequence stands still.
		if is_alive():
			_move_own(delta)
		_drain_outgoing()
	elif _timeline != null and is_alive():
		# Never sampled while eliminated, so a death is not an underrun.
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
		_out_queue.push(_sequence, global_position, _now_sec(), life)
	else:
		submit_move.rpc_id(1, life, _sequence, global_position)


# --- messages (table in game/net/README.md) ------------------------------------

## Owner -> server: where my hero is after `sequence` sends, in life `life_number`.
@rpc("authority", "call_remote", "unreliable_ordered", Net.MOVE_CHANNEL)
func submit_move(life_number: int, sequence: int, new_position: Vector2) -> void:
	if not multiplayer.is_server() or _check == null:
		return
	if life_number != life or not is_alive():
		return  # From before a death, or sent while eliminated: dropped silently.
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
func relay_move(life_number: int, sequence: int, new_position: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1 or _timeline == null:
		return
	_receive(life_number, sequence, new_position)


## Server -> owner: that move was refused, go back to the server's position.
@rpc("any_peer", "call_remote", "reliable")
func snap_back(life_number: int, sequence: int, new_position: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_owned():
		return
	_receive(life_number, sequence, new_position)


## Server -> every ready peer: this hero was hit.
@rpc("any_peer", "call_remote", "reliable", 0)
func receive_damage(attacker: int, shot_id: int, amount: int, health_after: int, hit_position: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_health.show_damage(amount, attacker, shot_id, health_after, hit_position)


## Server -> every ready peer: this hero was eliminated.
@rpc("any_peer", "call_remote", "reliable", 0)
func receive_elimination(attacker: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_health.show_elimination(attacker)


## Server -> every ready peer: this hero is back at `spawn_position` in life `life_number`.
@rpc("any_peer", "call_remote", "reliable", 0)
func receive_respawn(spawn_position: Vector2, life_number: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or life_number <= life:
		return
	_respawn(spawn_position, life_number)


## Server -> a peer that just joined: this hero's combat state (see send_combat_state).
@rpc("any_peer", "call_remote", "reliable", 0)
func receive_combat_state(life_number: int, health: int, eliminated: bool, respawn_in: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	life = life_number
	_health.sync(health, eliminated)
	_respawn_at_sec = _now_sec() + clampf(respawn_in, 0.0, COMBAT.respawn_sec)
	_show_eliminated(eliminated)
	_update_label()


func _relay(sequence: int, new_position: Vector2) -> void:
	for peer: int in multiplayer.get_peers():
		if peer != owner_peer and can_receive(peer):
			relay_move.rpc_id(peer, life, sequence, new_position)


func _reject(result: MoveCheck.Result) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_snap_msec >= SNAP_INTERVAL_MSEC:
		_last_snap_msec = now
		snap_back.rpc_id(owner_peer, life, _check.last_sequence, _check.position)
	_unlogged_rejects += 1
	_last_reason = MoveCheck.result_name(result)
	if now - _last_log_msec >= LOG_INTERVAL_MSEC:
		_last_log_msec = now
		print("[Move] peer %d: rejected %d update(s), last: %s (%d since spawn), snapped back" % [
			owner_peer, _unlogged_rejects, _last_reason, _check.rejected,
		])
		_unlogged_rejects = 0


func _receive(life_number: int, sequence: int, new_position: Vector2) -> void:
	if life_number != life:
		return
	if _in_queue.is_active():
		if _in_queue.is_full():
			_apply(_in_queue.peek_life(), _in_queue.peek_sequence(), _in_queue.peek_position())
			_in_queue.pop()
		_in_queue.push(sequence, new_position, _now_sec(), life_number)
	else:
		_apply(life_number, sequence, new_position)


func _apply(life_number: int, sequence: int, new_position: Vector2) -> void:
	# Checked again here: a fake-lag queue can hold an update across a death.
	if life_number != life or not is_alive():
		return
	if is_owned():
		global_position = new_position
		velocity = Vector2.ZERO
		reset_physics_interpolation()
	elif _timeline != null:
		_timeline.push(sequence, new_position, _clock_sec())


func _drain_incoming() -> void:
	var now := _now_sec()
	while _in_queue.is_due(now):
		_apply(_in_queue.peek_life(), _in_queue.peek_sequence(), _in_queue.peek_position())
		_in_queue.pop()


func _drain_outgoing() -> void:
	var now := _now_sec()
	while _out_queue.is_due(now):
		_send_oldest()


func _send_oldest() -> void:
	submit_move.rpc_id(1, _out_queue.peek_life(), _out_queue.peek_sequence(), _out_queue.peek_position())
	_out_queue.pop()


# --- combat ----------------------------------------------------------------------

## Health was hit: on the server it just decided so; on a client the message arrived.
func _on_damaged(amount: int, attacker: int, shot_id: int, health_after: int, hit_position: Vector2) -> void:
	_update_label()
	if multiplayer.is_server():
		for peer: int in multiplayer.get_peers():
			if can_receive(peer):
				receive_damage.rpc_id(peer, attacker, shot_id, amount, health_after, hit_position)
	else:
		var world_shots := shots()
		if world_shots != null:
			world_shots.end_visual(attacker, shot_id, hit_position)
	Events.hero_damaged.emit(owner_peer, attacker, amount, hit_position)


func _on_eliminated(attacker: int) -> void:
	_respawn_at_sec = _now_sec() + COMBAT.respawn_sec
	_show_eliminated(true)
	_update_label()
	if multiplayer.is_server():
		for peer: int in multiplayer.get_peers():
			if can_receive(peer):
				receive_elimination.rpc_id(peer, attacker)
	Events.hero_eliminated.emit(owner_peer, attacker)


func _respawn_on_server() -> void:
	var world := _world()
	var spot := position
	if world != null and world.has_method(&"respawn_point"):
		spot = world.call(&"respawn_point", owner_peer)
	_respawn(spot, life + 1)
	_check.reset(spot, _now_sec())
	for peer: int in multiplayer.get_peers():
		if can_receive(peer):
			receive_respawn.rpc_id(peer, spot, life)


func _respawn(spot: Vector2, life_number: int) -> void:
	life = life_number
	_health.restore()
	global_position = spot
	velocity = Vector2.ZERO
	if _timeline != null:
		_timeline.reset(spot)
	_show_eliminated(false)
	reset_physics_interpolation()
	_update_label()
	Events.hero_respawned.emit(owner_peer, spot)


## Hidden with its collider off while eliminated. Disabling takes effect at once,
## so shots later in the same tick already pass through.
func _show_eliminated(eliminated: bool) -> void:
	visible = not eliminated
	_collider.disabled = eliminated
	if eliminated:
		velocity = Vector2.ZERO


func _update_label() -> void:
	_name_label.text = "Player %d  %d" % [owner_peer, _health.health()]


func _world() -> Node:
	var heroes := get_parent()
	return heroes.get_parent() if heroes != null else null


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


## Real time, for the server's checks, respawns and the sim-lag queues.
func _now_sec() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Steps exactly once per physics tick, so remote playback is even on any screen.
func _clock_sec() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)

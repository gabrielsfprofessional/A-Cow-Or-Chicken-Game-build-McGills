class_name Ability
extends Node
## What every Q ability shares (cards T14, T18). Owner: Gabe (game/heroes).
## Messages: see game/net/README.md.
##
## NetHero.setup() adds the node its HeroData.ability makes (AbilityData.make())
## as the child "Ability", on every peer, so the node path matches everywhere.
## - Server-confirmed, not predicted: the owner sends request_ability on Q and
##   its effect starts only when the server's receive_ability_used arrives. Its
##   countdown starts then, so an honest owner never asks early.
## - The server checks each request with AbilityCheck. On a yes it runs
##   _use_on_server() (grants first), then tells every ready peer. A refusal
##   answers the owner, and BAD_DIRECTION / COOLING_DOWN also print a
##   rate-limited [Ability] line.
## - T18: charges. The answers carry each charge's ready time, so the owner
##   knows how many are left and when the next comes back.
## - T18: a press while a request is out or forced motion runs is held (at most
##   one) and sent when both are over, if a charge is ready then.
## - Each ability's script extends this one and adds only its effect, through
##   _use_on_server(), _use_on_owner() and on_server_moved().

## [Ability] (server refusals) lines per hero at most this often.
const LOG_INTERVAL_MSEC: int = 1000

var data: AbilityData = null

var _hero: NetHero
var _check: AbilityCheck
## When each charge is ready again, on this peer's _now_sec() clock (T18).
var _ready_at: PackedFloat64Array = []
## Owner: a request is out and no answer has come back yet.
var _pending: bool = false
## Owner: Q was pressed while a request was out or forced motion ran (T18). It
## is sent once both are over if a charge is ready then, else dropped.
var _held: bool = false
## Owner: the last non-zero aim, so a request never carries a zero direction.
var _aim: Vector2 = Vector2.RIGHT
## Debug --sim-lag/--sim-jitter: the owner's outgoing requests (direction in the position slot).
var _out_queue: DelayQueue
var _last_log_msec: int = -LOG_INTERVAL_MSEC
var _unlogged_refusals: int = 0
var _last_reason: String = ""


func _ready() -> void:
	assert(data != null, "%s needs its AbilityData before it enters the tree" % get_script().get_global_name())
	_hero = get_parent() as NetHero
	_ready_at.resize(data.charges)
	_ready_at.fill(0.0)
	if multiplayer.is_server():
		_check = AbilityCheck.new(_hero.owner_peer, data.cooldown_sec, data.charges)
	elif _hero.is_owned():
		_out_queue = DelayQueue.new(Net.sim_lag_msec(), Net.sim_jitter_msec())
	set_physics_process(_out_queue != null)


## Seconds until Q works again; 0 while any charge is ready. Exact on the owner
## and the server; everyone else's copy is only as fresh as the last
## receive_ability_used.
func ready_in_sec() -> float:
	if _check != null:
		return _check.ready_in_sec(_now_sec())
	var now := _now_sec()
	var soonest := INF
	for at: float in _ready_at:
		soonest = minf(soonest, at)
	return maxf(0.0, soonest - now)


## Charges ready now (T18). Same freshness as ready_in_sec().
func charges_left() -> int:
	var now := _now_sec()
	if _check != null:
		return _check.charges_left(now)
	var left := 0
	for at: float in _ready_at:
		if at <= now:
			left += 1
	return left


## Server only: the hero's accepted move from `from` to `to` drew on its grant.
## Abilities that act along the hero's path (Dash) override it.
func on_server_moved(_from: Vector2, _to: Vector2) -> void:
	pass


## Server only: the request was accepted at `now` (seconds, _now_sec() clock);
## the normalized aim is in _check.direction. Runs before anyone is told, so
## grants go here.
func _use_on_server(_now: float) -> void:
	pass


## Owner only: the server's yes arrived for this life while alive, toward
## `direction` (normalized).
func _use_on_owner(_direction: Vector2) -> void:
	pass


func _physics_process(_delta: float) -> void:
	_drain_outgoing()
	var input := _hero.input
	if input == null:
		return
	var aim := input.aim()
	if aim.is_finite() and not aim.is_zero_approx():
		_aim = aim
	if input.ability_pressed():
		_held = true
	if not _hero.is_alive():
		_held = false
		return
	# Held through a request and through forced motion, so a dash never cuts
	# another short and a quick second press still counts.
	if not _held or _pending or _hero.in_forced_motion():
		return
	_held = false
	if ready_in_sec() > 0.0:
		return  # No charge ready: the press is dropped.
	_pending = true
	var direction := _aim.normalized()
	if _out_queue.is_active():
		if _out_queue.is_full():
			_send_oldest()
		_out_queue.push(0, direction, _now_sec(), _hero.life)
	else:
		request_ability.rpc_id(1, _hero.life, direction)


# --- messages (table in game/net/README.md) ------------------------------------

## Owner -> server: I pressed Q in life `life`, aiming `direction`.
@rpc("authority", "call_remote", "reliable", 0)
func request_ability(life: int, direction: Vector2) -> void:
	if not multiplayer.is_server() or _check == null:
		return
	var now := _now_sec()
	var result := _check.check(multiplayer.get_remote_sender_id(), life, _hero.life, _hero.is_alive(), direction, now)
	match result:
		AbilityCheck.Result.ACCEPTED:
			_start_on_server(life, now)
		AbilityCheck.Result.WRONG_OWNER:
			return  # Not the owner: dropped silently, nobody to answer.
		_:
			if AbilityCheck.is_refusal(result):
				_log_refusal(result)
			receive_ability_refused.rpc_id(_hero.owner_peer, _check.charge_ready_in(now))


## Server -> every ready peer: the hero used its ability in life `life`, toward
## `direction`; each charge is ready in `charge_ready_in` seconds (soonest first,
## 0 = ready). The owner's effect starts.
@rpc("any_peer", "call_remote", "reliable", 0)
func receive_ability_used(life: int, direction: Vector2, charge_ready_in: PackedFloat64Array) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_resync(charge_ready_in)
	if _hero.is_owned():
		_pending = false
		# Another life's grant, or one that lands while eliminated, moves nothing.
		if life == _hero.life and _hero.is_alive() and direction.is_finite() and not direction.is_zero_approx():
			_use_on_owner(direction.normalized())
	Events.ability_used.emit(_hero.owner_peer, ready_in_sec())


## Server -> owner: that request was refused or dropped; each charge is ready in
## `charge_ready_in` seconds.
@rpc("any_peer", "call_remote", "reliable", 0)
func receive_ability_refused(charge_ready_in: PackedFloat64Array) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not _hero.is_owned():
		return
	_pending = false
	_resync(charge_ready_in)


func _start_on_server(life: int, now: float) -> void:
	_use_on_server(now)
	var charge_ready_in := _check.charge_ready_in(now)
	for peer: int in multiplayer.get_peers():
		if _hero.can_receive(peer):
			receive_ability_used.rpc_id(peer, life, _check.direction, charge_ready_in)
	Events.ability_used.emit(_hero.owner_peer, _check.ready_in_sec(now))


## Each charge's ready time from an answer. A missing entry counts as ready and
## an extra one is ignored; each is clamped to 0..cooldown_sec.
func _resync(charge_ready_in: PackedFloat64Array) -> void:
	var now := _now_sec()
	for i: int in _ready_at.size():
		var ready_in := charge_ready_in[i] if i < charge_ready_in.size() else 0.0
		_ready_at[i] = now + clampf(ready_in, 0.0, data.cooldown_sec)


func _log_refusal(result: AbilityCheck.Result) -> void:
	_unlogged_refusals += 1
	_last_reason = AbilityCheck.result_name(result)
	var now := Time.get_ticks_msec()
	if now - _last_log_msec < LOG_INTERVAL_MSEC:
		return
	_last_log_msec = now
	print("[Ability] peer %d: refused %d request(s), last: %s (%d since joining)" % [
		_hero.owner_peer, _unlogged_refusals, _last_reason, _check.refused,
	])
	_unlogged_refusals = 0


func _drain_outgoing() -> void:
	var now := _now_sec()
	while _out_queue.is_due(now):
		_send_oldest()


func _send_oldest() -> void:
	request_ability.rpc_id(1, _out_queue.peek_life(), _out_queue.peek_position())
	_out_queue.pop()


## Real time, for the cooldown, the server's check and the sim-lag queue.
func _now_sec() -> float:
	return Time.get_ticks_usec() / 1000000.0

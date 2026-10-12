class_name ShieldCharge
extends Node
## The Fantasy Bruiser's Q (card T14): a dash toward the aim that knocks back every
## other hero it passes through. Owner: Gabe (game/heroes). Messages: see game/net/README.md.
##
## NetHero.setup() adds one as the child "Ability" when its HeroData.ability is a
## ShieldChargeData, on every peer, so the node path matches everywhere.
## - Server-confirmed, not predicted: the owner sends request_ability on Q and
##   dashes only when the server's receive_ability_used arrives. Its countdown
##   starts then, so an honest owner never asks early.
## - The server checks each request with AbilityCheck. On a yes it grants the
##   dash distance to the hero's MoveCheck first, then tells every ready peer.
##   A refusal answers the owner, and BAD_DIRECTION / COOLING_DOWN also print a
##   rate-limited [Ability] line.
## - While the dash lasts, the server sweeps each accepted move that drew on the
##   grant (ChargeSweep) and knocks back each hero it finds, once per dash.

## [Ability] (server refusals) lines per hero at most this often.
const LOG_INTERVAL_MSEC: int = 1000
## Sweeping stops once this much more than the dash distance has been swept,
## so a knockback that hits the dasher right after doesn't carry the charge.
const SWEEP_SLACK_PX: float = 24.0

var data: ShieldChargeData = null

var _hero: NetHero
var _check: AbilityCheck
## When the ability is ready again, on this peer's _now_sec() clock.
var _ready_at_sec: float = 0.0
## Owner: a request is out and no answer has come back yet.
var _pending: bool = false
## Owner: the last non-zero aim, so a request never carries a zero direction.
var _aim: Vector2 = Vector2.RIGHT
## Debug --sim-lag/--sim-jitter: the owner's outgoing requests (direction in the position slot).
var _out_queue: DelayQueue
## Server: what is left of the current dash's sweep, when it ends, and who it already hit.
var _sweep_left_px: float = 0.0
var _sweep_until_sec: float = -INF
var _hit_peers: Dictionary[int, bool] = {}
var _last_log_msec: int = -LOG_INTERVAL_MSEC
var _unlogged_refusals: int = 0
var _last_reason: String = ""


func _ready() -> void:
	assert(data != null, "ShieldCharge needs its ShieldChargeData before it enters the tree")
	_hero = get_parent() as NetHero
	if multiplayer.is_server():
		_check = AbilityCheck.new(_hero.owner_peer, data.cooldown_sec)
	elif _hero.is_owned():
		_out_queue = DelayQueue.new(Net.sim_lag_msec(), Net.sim_jitter_msec())
	set_physics_process(_out_queue != null)


## Seconds until Q works again; 0 when ready. Exact on the owner and the server;
## everyone else's copy is only as fresh as the last receive_ability_used.
func ready_in_sec() -> float:
	if _check != null:
		return _check.ready_in_sec(_now_sec())
	return maxf(0.0, _ready_at_sec - _now_sec())


func _physics_process(_delta: float) -> void:
	_drain_outgoing()
	var input := _hero.input
	if input == null:
		return
	var aim := input.aim()
	if aim.is_finite() and not aim.is_zero_approx():
		_aim = aim
	if not input.ability_pressed() or _pending or not _hero.is_alive() or ready_in_sec() > 0.0:
		return
	_pending = true
	var direction := _aim.normalized()
	if _out_queue.is_active():
		if _out_queue.is_full():
			_send_oldest()
		_out_queue.push(0, direction, _now_sec(), _hero.life)
	else:
		request_ability.rpc_id(1, _hero.life, direction)


## Server only: the hero's accepted move from `from` to `to` drew on its grant.
## While a dash lasts, knocks back each hero on that stretch, once per dash.
func on_server_moved(from: Vector2, to: Vector2) -> void:
	if _sweep_left_px <= 0.0 or _now_sec() > _sweep_until_sec:
		return
	_sweep_left_px -= from.distance_to(to)
	if data.knockback_px <= 0.0:
		return
	var collider := _hero.get_node(^"Collider") as CollisionShape2D
	var found := ChargeSweep.find(_hero.get_world_2d().direct_space_state, collider.shape, from, to, [_hero.get_rid()])
	for body: Node in found:
		var victim := body as NetHero
		if victim == null or not victim.is_alive() or _hit_peers.has(victim.owner_peer):
			continue
		_hit_peers[victim.owner_peer] = true
		victim.knock_back(_hero.owner_peer, _check.direction * data.knockback_px, data.knockback_duration_sec)


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
			receive_ability_refused.rpc_id(_hero.owner_peer, _check.ready_in_sec(now))


## Server -> every ready peer: the hero used its ability in life `life`, toward
## `direction`; it is ready again in `ready_in` seconds. The owner dashes.
@rpc("any_peer", "call_remote", "reliable", 0)
func receive_ability_used(life: int, direction: Vector2, ready_in: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_resync(ready_in)
	if _hero.is_owned():
		_pending = false
		# Another life's grant, or one that lands while eliminated, moves nothing.
		if life == _hero.life and _hero.is_alive() and direction.is_finite() and not direction.is_zero_approx():
			_hero.start_forced_motion(direction.normalized() * data.dash_distance_px, data.dash_duration_sec)
	Events.ability_used.emit(_hero.owner_peer, ready_in)


## Server -> owner: that request was refused or dropped; it is ready in `ready_in` seconds.
@rpc("any_peer", "call_remote", "reliable", 0)
func receive_ability_refused(ready_in: float) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not _hero.is_owned():
		return
	_pending = false
	_resync(ready_in)


func _start_on_server(life: int, now: float) -> void:
	# Grant first, so the dash's moves are never judged before it.
	_hero.grant_motion(data.dash_distance_px, data.dash_duration_sec)
	_sweep_left_px = data.dash_distance_px + SWEEP_SLACK_PX
	_sweep_until_sec = now + data.dash_duration_sec + NetHero.FORCED_MOTION_GRACE_SEC
	_hit_peers.clear()
	var ready_in := _check.ready_in_sec(now)
	for peer: int in multiplayer.get_peers():
		if _hero.can_receive(peer):
			receive_ability_used.rpc_id(peer, life, _check.direction, ready_in)
	Events.ability_used.emit(_hero.owner_peer, ready_in)


func _resync(ready_in: float) -> void:
	_ready_at_sec = _now_sec() + clampf(ready_in, 0.0, data.cooldown_sec)


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

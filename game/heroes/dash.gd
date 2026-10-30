class_name Dash
extends Ability
## A dash toward the aim (cards T14, T18): the Bruiser's Shield Charge and the
## Scout's Jet Dash. Owner: Gabe (game/heroes). Numbers: a DashData file.
##
## - The server grants the dash distance to the hero's MoveCheck before it tells
##   anyone; the owner runs it as forced motion when the yes arrives.
## - While the dash lasts and knockback_px > 0, the server sweeps each accepted
##   move that drew on the grant (ChargeSweep) and knocks back each enemy it
##   finds that is not spawn-protected, once per dash. A respawn of the dasher
##   ends the sweep (world.respawn_all() respawns heroes that are alive).

## Sweeping stops once this much more than the dash distance has been swept,
## so a knockback that hits the dasher right after doesn't carry the charge.
const SWEEP_SLACK_PX: float = 24.0

## Server: what is left of the current dash's sweep, when it ends, who it already
## hit, and the dasher's life it belongs to (a respawn ends it).
var _sweep_left_px: float = 0.0
var _sweep_until_sec: float = -INF
var _hit_peers: Dictionary[int, bool] = {}
var _sweep_life: int = -1


func _dash() -> DashData:
	return data as DashData


func on_server_moved(from: Vector2, to: Vector2) -> void:
	if _sweep_left_px <= 0.0 or _now_sec() > _sweep_until_sec or _hero.life != _sweep_life:
		return
	_sweep_left_px -= from.distance_to(to)
	var dash := _dash()
	if dash.knockback_px <= 0.0:
		return
	var collider := _hero.get_node(^"Collider") as CollisionShape2D
	var found := ChargeSweep.find(_hero.get_world_2d().direct_space_state, collider.shape, from, to, [_hero.get_rid()])
	for body: Node in found:
		var victim := body as NetHero
		if victim == null or not victim.is_alive() or _hit_peers.has(victim.owner_peer):
			continue
		if not _hero.match_rules().is_enemy(_hero.owner_peer, victim.owner_peer):
			continue  # Allies are passed, not pushed.
		if victim.is_protected():
			continue  # Not marked, so this dash can still push it once protection ends.
		_hit_peers[victim.owner_peer] = true
		victim.knock_back(_hero.owner_peer, _check.direction * dash.knockback_px, dash.knockback_duration_sec)


func _use_on_server(now: float) -> void:
	var dash := _dash()
	# Grant first, so the dash's moves are never judged before it.
	_hero.grant_motion(dash.dash_distance_px, dash.dash_duration_sec)
	_sweep_left_px = dash.dash_distance_px + SWEEP_SLACK_PX
	_sweep_until_sec = now + dash.dash_duration_sec + NetHero.FORCED_MOTION_GRACE_SEC
	_hit_peers.clear()
	_sweep_life = _hero.life


func _use_on_owner(direction: Vector2) -> void:
	var dash := _dash()
	_hero.start_forced_motion(direction * dash.dash_distance_px, dash.dash_duration_sec)

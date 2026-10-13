class_name HealDrone
extends Ability
## A drone over the hero that heals every alive hero near it (card T18): the
## Medic's Heal Drone. Owner: Gabe (game/heroes). Numbers: a HealDroneData file.
##
## - The server heals: one tick every tick_sec from tick_sec through
##   duration_sec, real time, each giving heal_per_tick_hp to every alive hero
##   within radius_px of the healer (the healer included). It stops at once if
##   the healer is eliminated. A new use starts the ticks over.
## - Every client draws the drone, with a ring at radius_px, from the moment
##   the yes arrives until duration_sec later or the healer's elimination. A
##   peer that joins mid-heal doesn't see it (not in T18).

## How it looks; not gameplay numbers.
const DRONE_OFFSET: Vector2 = Vector2(0.0, -72.0)
const DRONE_RADIUS_PX: float = 8.0
const DRONE_COLOR: Color = Color(0.45, 1.0, 0.55)
const RING_COLOR: Color = Color(0.45, 1.0, 0.55, 0.35)
const RING_WIDTH_PX: float = 2.0
const RING_POINTS: int = 64

## Server: heal ticks still to come and when the next falls (_now_sec() clock).
var _ticks_left: int = 0
var _next_tick_sec: float = INF
## Clients: the drone's drawing, a child of the hero, and when it hides.
var _view: Node2D = null
var _show_until_sec: float = -INF


func _drone() -> HealDroneData:
	return data as HealDroneData


func _ready() -> void:
	super()
	if multiplayer.is_server():
		return
	_view = Node2D.new()
	_view.name = "HealDroneView"
	_view.visible = false
	_view.draw.connect(_draw_view)
	# The hero is still adding its children, so the view joins it next frame.
	_hero.add_child.call_deferred(_view)


func _use_on_server(now: float) -> void:
	_ticks_left = _drone().tick_count()
	_next_tick_sec = now + _drone().tick_sec


func _use_on_client(_direction: Vector2) -> void:
	_show_until_sec = _now_sec() + _drone().duration_sec


func _effect_physics(_delta: float) -> void:
	if _view != null:
		_view.visible = _hero.is_alive() and _now_sec() < _show_until_sec
	if _ticks_left <= 0:
		return
	if not _hero.is_alive():
		_ticks_left = 0  # The healer was eliminated: the drone stops.
		return
	var now := _now_sec()
	while _ticks_left > 0 and now >= _next_tick_sec:
		_ticks_left -= 1
		_next_tick_sec += _drone().tick_sec
		_heal_tick()


## Server: one tick's healing for every alive hero in range.
func _heal_tick() -> void:
	var drone := _drone()
	for node: Node in _hero.get_parent().get_children():
		var other := node as NetHero
		if other == null or not other.is_alive():
			continue
		if other.global_position.distance_to(_hero.global_position) <= drone.radius_px:
			other.heal(_hero.owner_peer, drone.heal_per_tick_hp)


func _draw_view() -> void:
	_view.draw_arc(Vector2.ZERO, _drone().radius_px, 0.0, TAU, RING_POINTS, RING_COLOR, RING_WIDTH_PX)
	_view.draw_circle(DRONE_OFFSET, DRONE_RADIUS_PX, DRONE_COLOR)

class_name TeamMarks
extends Node2D
## The ring in the hero's team color under it, and your own hero's outline (T42).
## Owner: Gabe (game/heroes). NetHero adds it on screens only (TeamMarkData.builds_marks()).
##
## - The team comes from the world's teams_seen() when the hero spawns (a late
##   joiner's replay may come first), then from every Events.team_assigned for
##   this peer, so a balance switch recolors it at once. No RPC of its own.
## - No team (-1: the Practice Range, the test world): no ring. The outline shows anyway.
## - Drawn behind its hero (show_behind_parent) at the hero's own z, so it stays
##   above a map's floor; a negative z_index would sort it under the floor.
## - One line per change, so a log shows what each window drew:
##   [Team] peer <id>: ring Blue|Orange|none[, own outline]

const DATA: TeamMarkData = preload("res://game/heroes/data/team_marks.tres")
## Points on the ring's circle: drawing detail, not a tuning number.
const RING_POINTS: int = 64

var _peer_id: int = 0
var _own: bool = false
## The hero's body, in the hero's coordinates: the outline goes around it.
var _body: Rect2 = Rect2()
var _team: int = -1


## Before it enters the tree. `team` is the world's team for this peer, or -1.
func setup(peer_id: int, own: bool, body: Rect2, team: int) -> void:
	name = "TeamMarks"
	_peer_id = peer_id
	_own = own
	_body = body
	_team = team if TeamMarkData.has_ring(team) else -1
	show_behind_parent = true  # Under the hero's body: it stands on the ring.


func _ready() -> void:
	Events.team_assigned.connect(_on_team_assigned)
	_log_marks()


## The team this ring shows: 0, 1, or -1 for none.
func team() -> int:
	return _team


## True when this is the window's own hero.
func is_own() -> bool:
	return _own


func _on_team_assigned(peer_id: int, new_team: int) -> void:
	if peer_id != _peer_id:
		return
	var shown: int = new_team if TeamMarkData.has_ring(new_team) else -1
	if shown == _team:
		return
	_team = shown
	_log_marks()
	queue_redraw()


func _draw() -> void:
	if TeamMarkData.has_ring(_team):
		draw_arc(Vector2.ZERO, DATA.ring_radius_px, 0.0, TAU, RING_POINTS, DATA.ring_color(_team), DATA.ring_width_px, true)
	if _own:
		var around: Rect2 = _body.grow(DATA.outline_gap_px + DATA.outline_width_px * 0.5)
		draw_rect(around, DATA.outline, false, DATA.outline_width_px)


func _log_marks() -> void:
	var ring := "none"
	if _team == 0:
		ring = "Blue"
	elif _team == 1:
		ring = "Orange"
	print("[Team] peer %d: ring %s%s" % [_peer_id, ring, ", own outline" if _own else ""])

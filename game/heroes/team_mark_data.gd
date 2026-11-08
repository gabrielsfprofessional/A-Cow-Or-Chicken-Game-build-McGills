class_name TeamMarkData
extends Resource
## The team ring and own-hero outline's colors and sizes (T42). Owner: Gabe (game/heroes).
## TeamMarks draws them; game/heroes/data/team_marks.tres holds the numbers.
## Teams: 0 = Blue #3B82F6, 1 = Orange #F97316 (PROJECT_PLAN, the same two as T17's HUD).

## Team 0's ring.
@export var blue: Color = Color("#3B82F6")
## Team 1's ring.
@export var orange: Color = Color("#F97316")
## Your own hero's outline.
@export var outline: Color = Color.WHITE
## From the hero's middle to the middle of the ring's line. The hero's body is 48 px across.
@export_range(20.0, 80.0, 1.0, "suffix:px") var ring_radius_px: float = 36.0
@export_range(1.0, 16.0, 0.5, "suffix:px") var ring_width_px: float = 5.0
## Space between the hero's body and its outline.
@export_range(0.0, 16.0, 0.5, "suffix:px") var outline_gap_px: float = 3.0
@export_range(1.0, 8.0, 0.5, "suffix:px") var outline_width_px: float = 3.0


## True for a team that has a ring: 0 or 1. -1 (no team: the Practice Range,
## the test world) and anything else draw none.
static func has_ring(team: int) -> bool:
	return team == 0 or team == 1


## The ring's color for `team`: blue for 0, orange for 1, see-through for any other.
func ring_color(team: int) -> Color:
	match team:
		0:
			return blue
		1:
			return orange
		_:
			return Color.TRANSPARENT


## The team `peer_id` plays for in `seen` (the world's teams_seen()), or -1 when
## it has none or `seen` isn't a peer id -> team Dictionary.
static func team_in(seen: Variant, peer_id: int) -> int:
	if not seen is Dictionary:
		return -1
	var team: Variant = (seen as Dictionary).get(peer_id, -1)
	return team if team is int and has_ring(team) else -1


## The team `peer_id` plays for in `world`'s teams_seen() (team_in()), or -1 when
## there is no world or it keeps no teams. NetHero reads its start team with it.
static func world_team(world: Node, peer_id: int) -> int:
	if world == null or not world.has_method(&"teams_seen"):
		return -1
	return team_in(world.call(&"teams_seen"), peer_id)


## True where heroes get a ring and an outline: never on a headless run (the
## dedicated server, test bots), where nobody sees them.
static func builds_marks(display_server_name: String) -> bool:
	return display_server_name != "headless"


## This file's problems in plain words. Empty when the file is fine.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = DataCheck.ranges(self)
	var colors: Dictionary[String, Color] = {"blue": blue, "orange": orange, "outline": outline}
	for field: String in colors:
		if colors[field].a < 1.0:
			problems.append("%s is see-through (alpha %.2f); it must be 1" % [field, colors[field].a])
	if blue.is_equal_approx(orange):
		problems.append("blue and orange are the same color; the teams must differ")
	return problems

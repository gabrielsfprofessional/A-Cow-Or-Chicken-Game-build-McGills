class_name ArenaLookData
extends Resource
## How the arena is dressed (T34): the numbers and colors behind its team sides, spawn pads,
## walls and cover. Owner: Adam (game/maps). game/maps/data/arena_look.tres holds the values;
## ArenaDressing draws with them. Looks only: nothing here moves a wall, a spawn or a shot.
## The two team colors are not here: ArenaDressing reads them from the hero rings' file.

## Hero names are drawn in white (the hero scene's PlayerName label).
const NAME_COLOR: Color = Color.WHITE

## How far each team's floor reaches in from its side wall. The middle stays plain.
@export_range(0.0, 1824.0, 48.0, "suffix:px") var side_width_px: float = 1296.0
## How much darker than the team's color its floor shade is. 1 is black.
@export_range(0.0, 1.0, 0.01) var side_darken: float = 0.72
## How much of that shade is mixed into the floor on the team's side. 0 leaves the floor plain.
@export_range(0.0, 1.0, 0.01) var side_mix: float = 0.6
## The square frame on the floor around each spawn point.
@export_range(48.0, 384.0, 48.0, "suffix:px") var pad_size_px: float = 144.0
@export_range(1.0, 24.0, 1.0, "suffix:px") var pad_line_px: float = 6.0
## How much darker than the team's color its spawn pads are. 1 is black.
@export_range(0.0, 1.0, 0.01) var pad_darken: float = 0.62
## How much of that shade is mixed into the floor for a spawn pad.
@export_range(0.0, 1.0, 0.01) var pad_mix: float = 0.6
## How much darker than the team's color its side wall is. 0 is the team's own color.
@export_range(0.0, 1.0, 0.01) var side_wall_darken: float = 0.15
## The top and bottom walls.
@export var wall_fill: Color = Color(0.26, 0.27, 0.3, 1)
## Cover blocks, and the bright line just inside their edge.
@export var cover_fill: Color = Color(0.47, 0.5, 0.55, 1)
@export var cover_edge: Color = Color(0.88, 0.9, 0.94, 1)
@export_range(0.0, 16.0, 1.0, "suffix:px") var cover_edge_px: float = 4.0
## The least contrast (1 = none, 21 = black on white) kept between cover and the floor, and
## between a team ring or a hero's name and whatever is under it. 3 is the usual floor for shapes.
@export_range(1.0, 21.0, 0.1) var min_contrast: float = 3.0


## The floor on `team_color`'s side: the plain `floor_color` with the team's dark shade mixed in.
func side_floor(floor_color: Color, team_color: Color) -> Color:
	return _opaque(floor_color.lerp(team_color.darkened(side_darken), side_mix))


## The color of the frame around `team_color`'s spawn points.
func pad_color(floor_color: Color, team_color: Color) -> Color:
	return _opaque(floor_color.lerp(team_color.darkened(pad_darken), pad_mix))


## The color of `team_color`'s side wall.
func side_wall(team_color: Color) -> Color:
	return _opaque(team_color.darkened(side_wall_darken))


## Every color a hero can stand on, by its plain name. `teams` is [Blue, Orange].
func floor_shades(floor_color: Color, teams: Array[Color]) -> Dictionary[String, Color]:
	var shades: Dictionary[String, Color] = {"the plain floor": _opaque(floor_color)}
	for team: int in teams.size():
		shades["%s's side of the floor" % team_name(team)] = side_floor(floor_color, teams[team])
		shades["%s's spawn pads" % team_name(team)] = pad_color(floor_color, teams[team])
	return shades


## What would be hard to see with these values, in plain words. Empty when cover stands out
## from every floor shade, both team rings and hero names stand out from every floor shade,
## and a name still reads over cover. `teams` is [Blue, Orange].
func sight_problems(floor_color: Color, teams: Array[Color]) -> PackedStringArray:
	var problems: PackedStringArray = []
	if teams.size() != 2:
		problems.append("the look needs the 2 team colors and got %d" % teams.size())
		return problems
	var shades: Dictionary[String, Color] = floor_shades(floor_color, teams)
	for shade_name: String in shades:
		var shade: Color = shades[shade_name]
		_need(problems, "cover", cover_fill, shade_name, shade)
		_need(problems, "a hero's name", NAME_COLOR, shade_name, shade)
		for team: int in teams.size():
			_need(problems, "%s's ring" % team_name(team), teams[team], shade_name, shade)
	_need(problems, "a hero's name", NAME_COLOR, "cover", cover_fill)
	return problems


## This file's problems in plain words. Empty when the file is fine.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = DataCheck.ranges(self)
	var colors: Dictionary[String, Color] = {"wall_fill": wall_fill, "cover_fill": cover_fill, "cover_edge": cover_edge}
	for field: String in colors:
		if colors[field].a < 1.0:
			problems.append("%s is see-through (alpha %.2f); it must be 1" % [field, colors[field].a])
	return problems


## "Blue" for team 0 and "Orange" for team 1 (PROJECT_PLAN); "team <n>" for any other.
static func team_name(team: int) -> String:
	match team:
		0:
			return "Blue"
		1:
			return "Orange"
		_:
			return "team %d" % team


## How far apart two colors are in brightness, from 1 (the same) to 21 (black on white).
## The usual screen-contrast measure (WCAG relative luminance).
static func contrast(a: Color, b: Color) -> float:
	var light: float = maxf(luminance(a), luminance(b))
	var dark: float = minf(luminance(a), luminance(b))
	return (light + 0.05) / (dark + 0.05)


## A color's brightness as the eye sees it, 0 (black) to 1 (white).
static func luminance(color: Color) -> float:
	var linear: Color = color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


## Adds a problem when `thing` doesn't stand out from `under` by min_contrast.
func _need(problems: PackedStringArray, thing_name: String, thing: Color, under_name: String, under: Color) -> void:
	var found: float = contrast(thing, under)
	if found < min_contrast:
		problems.append("%s is hard to see on %s (contrast %.2f, needs %.1f)" % [thing_name, under_name, found, min_contrast])


func _opaque(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 1.0)

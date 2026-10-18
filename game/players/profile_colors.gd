class_name ProfileColors
extends Resource
## The profile swatches and the rules they must pass (card T11). Owner: John (game/players).
## Data lives in data/profile_colors.tres. validate() is how a bad swatch gets caught.
## The profile color is for menus only. It never colors a hero or a name in a match.

const FILE_NAME: String = "profile_colors.tres"
## D65 white point for CIE L*a*b*.
const WHITE: Vector3 = Vector3(0.95047, 1.0, 1.08883)

@export var swatch_count: int = 8
@export var swatches: Array[Color] = []
@export var team_names: PackedStringArray = []
@export var team_colors: Array[Color] = []
@export var ui_background: Color = Color("#1C1F29")
## Each swatch must be at least this far (CIE76 delta E) from both team colors.
@export var min_team_distance: float = 30.0
## Each swatch must have at least this WCAG contrast ratio against ui_background.
@export var min_contrast: float = 4.5


## One message per broken rule, each naming this file and the swatch. Empty means all good.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if swatches.size() != swatch_count:
		problems.append("%s: has %d swatches, needs exactly %d" % [FILE_NAME, swatches.size(), swatch_count])
	if team_colors.size() != team_names.size():
		problems.append("%s: team_names and team_colors are not the same length" % FILE_NAME)
	var seen: Dictionary[String, int] = {}
	for i: int in swatches.size():
		var swatch: Color = swatches[i]
		var label := "%s: swatch %d (#%s)" % [FILE_NAME, i + 1, swatch.to_html(false).to_upper()]
		var hex := swatch.to_html(false).to_upper()
		if seen.has(hex):
			problems.append("%s is the same as swatch %d" % [label, seen[hex] + 1])
		else:
			seen[hex] = i
		for t: int in team_colors.size():
			var distance := delta_e(swatch, team_colors[t])
			if distance < min_team_distance:
				var team: String = team_names[t] if t < team_names.size() else "team %d" % (t + 1)
				problems.append("%s is too close to %s (delta E %.1f, needs at least %.0f)" % [
					label, team, distance, min_team_distance])
		var ratio := contrast_ratio(swatch, ui_background)
		if ratio < min_contrast:
			problems.append("%s is hard to read on the menu background (contrast %.2f, needs at least %.1f)" % [
				label, ratio, min_contrast])
	return problems


## CIE76: the straight-line distance in CIE L*a*b* (D65), from sRGB.
static func delta_e(a: Color, b: Color) -> float:
	return to_lab(a).distance_to(to_lab(b))


static func to_lab(color: Color) -> Vector3:
	var r := _linear(color.r)
	var g := _linear(color.g)
	var b := _linear(color.b)
	var x := (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / WHITE.x
	var y := (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / WHITE.y
	var z := (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / WHITE.z
	var fx := _lab_f(x)
	var fy := _lab_f(y)
	var fz := _lab_f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


## The WCAG contrast ratio, 1 to 21.
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(color: Color) -> float:
	return 0.2126 * _linear(color.r) + 0.7152 * _linear(color.g) + 0.0722 * _linear(color.b)


static func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


static func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 216.0 / 24389.0 else (24389.0 / 27.0 * t + 16.0) / 116.0

class_name DataCheck
extends RefCounted
## Shared helpers for the validate() of every data Resource (HeroData,
## HeroRoster, WeaponData, CombatData). Owner: Gabe (game/core). Card T13.
##
## ranges() reads each field's limits from its own @export_range, so the
## limits are written once and validate() always matches the Inspector. A text
## edit of a .tres can't sneak past it. tests/data_test.gd runs every validate().


## One problem per number outside its @export_range, in plain words, for
## example "move_speed is 0 px/s; it must be 50 to 1000 px/s". NaN fails too.
static func ranges(resource: Resource) -> PackedStringArray:
	var problems := PackedStringArray()
	for property: Dictionary in resource.get_property_list():
		if property.hint != PROPERTY_HINT_RANGE:
			continue
		if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var limits := _limits(property.hint_string)
		if limits.is_empty():
			continue
		var field: String = property.name
		var value := float(resource.get(field))
		var unit: String = limits.unit
		if not (value >= limits.low and value <= limits.high):
			problems.append("%s is %s%s; it must be %s" % [field, _number(value), unit, _span(limits)])
	return problems


## Adds a problem when `value` is empty or only spaces.
static func require_text(problems: PackedStringArray, field: String, value: String) -> void:
	if value.strip_edges().is_empty():
		problems.append("%s is empty; type one in" % field)


## The file a resource came from ("sidearm.tres"), for problem messages.
static func file_name(resource: Resource) -> String:
	var path := resource.resource_path
	if path.is_empty() or path.contains("::"):
		return "built-in"
	return path.get_file()


## {low, high, unit} from a range hint such as "50,1000,10,suffix:px/s"; empty
## when the hint has no low and high. "or_greater" and "or_less" open that end
## (INF); the other flags (exp, degrees, hide_slider...) don't change the limits.
static func _limits(hint_string: String) -> Dictionary:
	var parts := hint_string.split(",")
	if parts.size() < 2 or not parts[0].strip_edges().is_valid_float() or not parts[1].strip_edges().is_valid_float():
		return {}
	var limits := {"low": parts[0].to_float(), "high": parts[1].to_float(), "unit": ""}
	for raw: String in parts:
		var part := raw.strip_edges()
		if part == "or_greater":
			limits.high = INF
		elif part == "or_less":
			limits.low = -INF
		elif part.begins_with("suffix:"):
			limits.unit = " " + part.trim_prefix("suffix:")
	return limits


## "50 to 1000 px/s", "at least 1 HP", "at most 5 s" or "a number" (NaN).
static func _span(limits: Dictionary) -> String:
	var unit: String = limits.unit
	var low: float = limits.low
	var high: float = limits.high
	if is_finite(low) and is_finite(high):
		return "%s to %s%s" % [_number(low), _number(high), unit]
	if is_finite(low):
		return "at least %s%s" % [_number(low), unit]
	if is_finite(high):
		return "at most %s%s" % [_number(high), unit]
	return "a number"


## "0", "1000", "0.05", "nan": whole numbers without ".0".
static func _number(value: float) -> String:
	if is_finite(value) and value == floorf(value) and absf(value) < 1e15:
		return str(int(value))
	return String.num(value)

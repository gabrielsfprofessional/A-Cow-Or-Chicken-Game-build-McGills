extends SceneTree
## Tests for the hero and weapon data files (card T13). Owner: Gabe.
## Run: godot --headless --path . --script res://tests/data_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it, so every
## pull request checks all the data files, Adam's weapon edits included.
##
## 1. Every .tres in DATA_FOLDERS must load, be a known type and pass validate().
##    A failure names the file and the problem in plain words.
## 2. validate() itself, on resources built here: each kind of problem is caught,
##    and range flags (or_greater, or_less, suffix, exp, degrees) read right.
## 3. A .tres with a wrong script path fails, naming the file.

const DATA_FOLDERS: PackedStringArray = ["res://game/heroes/data", "res://game/weapons/data"]
const ROSTER_PATH: String = "res://game/heroes/data/roster.tres"
const SIDEARM_PATH: String = "res://game/weapons/data/sidearm.tres"
const UNKNOWN_TYPE: String = "is not a HeroData, HeroRoster, CombatData or WeaponData file; check its script path"
const SCRATCH_FOLDER: String = "user://data_test"
const WRONG_SCRIPT_TRES: String = """[gd_resource type="Resource" script_class="HeroData" format=3]

[ext_resource type="Script" path="res://game/heroes/health.gd" id="1_hero"]

[resource]
script = ExtResource("1_hero")
display_name = "Moved Hero"
"""
## A Resource script with every kind of range hint DataCheck reads.
const RANGES_SCRIPT: String = """extends Resource
@export_range(1, 10, 1, "or_greater") var at_least: int = 5
@export_range(-5.0, 5.0, 0.5, "or_less", "suffix:s") var at_most: float = 0.0
@export_range(0.0, 360.0, 1.0, "degrees", "exp", "hide_slider", "suffix:deg") var angle: float = 90.0
"""

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_every_data_file()
	_roster_has_a_first_hero()
	_good_hero_passes()
	_speed_out_of_range()
	_not_a_number()
	_empty_texts()
	_missing_weapon()
	_weapon_problems_passed_on()
	_roster_empty_slot()
	_range_flags()
	_combat_out_of_range()
	_wrong_script_path()
	print("DATA TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


# --- the real files --------------------------------------------------------------

func _every_data_file() -> void:
	for folder: String in DATA_FOLDERS:
		var files := DirAccess.get_files_at(folder)
		var found := 0
		for file: String in files:
			if file.get_extension() != "tres":
				continue
			found += 1
			_check_file(folder.path_join(file))
		_expect(found > 0, "%s has .tres files" % folder, "none found")


func _check_file(path: String) -> void:
	var problem := _file_problem(path)
	_expect(problem.is_empty(), path.get_file(), problem)


## Empty when the file loads, is a known type and passes validate(); else the
## problem in plain words. _check_file() puts the file name in front.
func _file_problem(path: String) -> String:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		return "won't load; open it in Godot to see why"
	var problems := PackedStringArray()
	if resource is HeroData:
		problems = (resource as HeroData).validate()
	elif resource is HeroRoster:
		problems = (resource as HeroRoster).validate()
	elif resource is CombatData:
		problems = (resource as CombatData).validate()
	elif resource is WeaponData:
		problems = (resource as WeaponData).validate()
	else:
		return UNKNOWN_TYPE
	return "; ".join(problems)


## A hero file whose script path points at the wrong script fails, naming the file.
## It points at health.gd, a Node script: a missing script would make the engine
## print "Parse Error", which smoke counts as a script error.
func _wrong_script_path() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_FOLDER)
	var path := SCRATCH_FOLDER.path_join("wrong_script.tres")
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(WRONG_SCRIPT_TRES)
	out.close()
	print("  (an engine error about health.gd on a Resource is expected next)")
	var problem := _file_problem(path)
	DirAccess.remove_absolute(path)
	# _check_file() would print "FAIL  wrong_script.tres: " and this problem.
	_expect(problem == UNKNOWN_TYPE, "a .tres with a wrong script path fails (%s)" % UNKNOWN_TYPE,
		"got \"%s\"" % problem)


func _roster_has_a_first_hero() -> void:
	var roster := load(ROSTER_PATH) as HeroRoster
	_expect(roster != null and roster.first() != null, "roster.tres has a first hero (everyone plays it until T16)",
		"roster.tres is missing, not a HeroRoster or empty")


# --- validate() on resources built here --------------------------------------------

func _good_hero() -> HeroData:
	var hero := HeroData.new()
	hero.display_name = "Test Hero"
	hero.role = "Tests things"
	hero.default_weapon = _good_weapon()
	return hero


func _good_weapon() -> WeaponData:
	var weapon := WeaponData.new()
	weapon.display_name = "Test Gun"
	return weapon


func _good_hero_passes() -> void:
	var problems := _good_hero().validate()
	_expect(problems.is_empty(), "a hero at the defaults passes", "; ".join(problems))


func _speed_out_of_range() -> void:
	var hero := _good_hero()
	hero.move_speed = 0.0
	_expect_problems(hero.validate(), ["move_speed is 0 px/s; it must be 50 to 1000 px/s"], "move_speed 0")
	hero.move_speed = 1000.0
	_expect_problems(hero.validate(), [], "move_speed 1000 (the top) passes")
	hero.move_speed = 1001.0
	_expect_problems(hero.validate(), ["move_speed is 1001 px/s; it must be 50 to 1000 px/s"], "move_speed 1001")
	hero.move_speed = 300.0
	hero.max_health = 0
	_expect_problems(hero.validate(), ["max_health is 0 HP; it must be 1 to 1000 HP"], "max_health 0")


func _not_a_number() -> void:
	var hero := _good_hero()
	hero.move_speed = NAN
	_expect_problems(hero.validate(), ["move_speed is nan px/s; it must be 50 to 1000 px/s"], "move_speed NaN")
	hero.move_speed = INF
	_expect_problems(hero.validate(), ["move_speed is inf px/s; it must be 50 to 1000 px/s"], "move_speed INF")


func _empty_texts() -> void:
	var hero := _good_hero()
	hero.display_name = "  "
	hero.role = ""
	_expect_problems(hero.validate(), ["display_name is empty; type one in", "role is empty; type one in"],
		"empty display_name and role")


func _missing_weapon() -> void:
	var hero := _good_hero()
	hero.default_weapon = null
	_expect_problems(hero.validate(),
		["default_weapon is empty; pick a WeaponData file such as sidearm.tres"], "no default_weapon")


func _weapon_problems_passed_on() -> void:
	var hero := _good_hero()
	hero.default_weapon.damage = 0
	_expect_problems(hero.validate(),
		["default_weapon (built-in): damage is 0; it must be 1 to 200"], "a bad weapon fails its hero")
	var weapon := _good_weapon()
	weapon.fire_interval_sec = 0.0
	weapon.display_name = ""
	_expect_problems(weapon.validate(), [
		"display_name is empty; type one in",
		"fire_interval_sec is 0 s; it must be 0.05 to 5 s",
	], "a bad weapon on its own")
	var sidearm := load(SIDEARM_PATH) as WeaponData
	hero.default_weapon = sidearm
	_expect(sidearm != null and hero.validate().is_empty(), "a hero with sidearm.tres passes", "it did not")


func _roster_empty_slot() -> void:
	var roster := HeroRoster.new()
	_expect_problems(roster.validate(), ["heroes is empty; add at least one HeroData file"], "an empty roster")
	var bad := _good_hero()
	bad.move_speed = 0.0
	roster.heroes = [_good_hero(), null, bad]
	_expect_problems(roster.validate(), [
		"heroes[1] is empty; pick a HeroData file such as bruiser.tres",
		"heroes[2] (built-in): move_speed is 0 px/s; it must be 50 to 1000 px/s",
	], "an empty slot and a bad hero")


## or_greater / or_less open that end; suffix, exp, degrees and hide_slider don't change the limits.
func _range_flags() -> void:
	var script := GDScript.new()
	script.source_code = RANGES_SCRIPT
	script.reload()
	var data := Resource.new()
	data.set_script(script)
	_expect_problems(DataCheck.ranges(data), [], "range flags: defaults pass")
	data.set("at_least", 1000)
	data.set("at_most", -1000.0)
	_expect_problems(DataCheck.ranges(data), [], "or_greater and or_less are open-ended")
	data.set("at_least", 0)
	data.set("at_most", 6.0)
	data.set("angle", 361.0)
	_expect_problems(DataCheck.ranges(data), [
		"at_least is 0; it must be at least 1",
		"at_most is 6 s; it must be at most 5 s",
		"angle is 361 deg; it must be 0 to 360 deg",
	], "the closed end of each range still holds")


func _combat_out_of_range() -> void:
	var combat := CombatData.new()
	_expect_problems(combat.validate(), [], "combat at the defaults passes")
	combat.respawn_sec = 0.0
	_expect_problems(combat.validate(), ["respawn_sec is 0 s; it must be 0.5 to 30 s"], "respawn_sec 0")


# --- helpers -----------------------------------------------------------------------

func _expect_problems(got: PackedStringArray, want: Array[String], what: String) -> void:
	var same := got.size() == want.size()
	for i: int in mini(got.size(), want.size()):
		same = same and got[i] == want[i]
	_expect(same, what, "got [%s], want [%s]" % ["; ".join(got), "; ".join(PackedStringArray(want))])


func _expect(ok: bool, what: String, problem: String) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s: %s" % [what, problem])

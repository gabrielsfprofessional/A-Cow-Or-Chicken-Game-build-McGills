extends SceneTree
## Tests for the hero and weapon data files (card T13). Owner: Gabe.
## Run: godot --headless --path . --script res://tests/data_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it, so every
## pull request checks Adam's and John's data edits.
##
## 1. Every .tres in DATA_FOLDERS must load, be a known type and pass validate().
##    A failure names the file and the problem in plain words.
## 2. validate() itself, on resources built here: each kind of problem is caught.

const DATA_FOLDERS: PackedStringArray = ["res://game/heroes/data", "res://game/weapons/data"]
const ROSTER_PATH: String = "res://game/heroes/data/roster.tres"
const SIDEARM_PATH: String = "res://game/weapons/data/sidearm.tres"

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
	_combat_out_of_range()
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
	var file := path.get_file()
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		_expect(false, file, "won't load; open it in Godot to see why")
		return
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
		_expect(false, file, "is not a HeroData, HeroRoster, CombatData or WeaponData file")
		return
	_expect(problems.is_empty(), file, "; ".join(problems))


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

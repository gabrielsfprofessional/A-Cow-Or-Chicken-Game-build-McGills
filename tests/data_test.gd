extends SceneTree
## Tests for the hero, ability and weapon data files (cards T13, T14, T18). Owner: Gabe.
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
const BRUISER_PATH: String = "res://game/heroes/data/bruiser.tres"
const CHARGE_PATH: String = "res://game/heroes/data/shield_charge.tres"
const SCOUT_PATH: String = "res://game/heroes/data/scout.tres"
const JET_DASH_PATH: String = "res://game/heroes/data/jet_dash.tres"
const MAGE_PATH: String = "res://game/heroes/data/mage.tres"
const BLINK_PATH: String = "res://game/heroes/data/blink.tres"
const MEDIC_PATH: String = "res://game/heroes/data/medic.tres"
const HEAL_DRONE_PATH: String = "res://game/heroes/data/heal_drone.tres"
const UNKNOWN_TYPE: String = "is not a HeroData, HeroRoster, CombatData, AbilityData or WeaponData file; check its script path"
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
	_roster_finds_heroes()
	_good_hero_passes()
	_speed_out_of_range()
	_not_a_number()
	_empty_texts()
	_missing_weapon()
	_weapon_problems_passed_on()
	_roster_empty_slot()
	_range_flags()
	_combat_out_of_range()
	_bruiser_has_shield_charge()
	_abilities_name_their_node()
	_good_charge_passes()
	_charge_out_of_range()
	_charge_too_fast()
	_charge_cap_fits_the_snap()
	_blink_passes_and_ranges()
	_heal_drone_passes_and_ranges()
	_heal_drone_whole_ticks()
	_ability_problems_passed_on()
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
	elif resource is AbilityData:
		problems = (resource as AbilityData).validate()
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
	_expect(roster != null and roster.first() != null, "roster.tres has a first hero (the default until T16)",
		"roster.tres is missing, not a HeroRoster or empty")


## --hero=<file name> and client_ready's hero_index (T18) go through these.
func _roster_finds_heroes() -> void:
	var roster := load(ROSTER_PATH) as HeroRoster
	var names: PackedStringArray = ["bruiser", "mage", "scout", "medic"]
	var all_found := true
	for i: int in names.size():
		all_found = all_found and roster.index_of(names[i]) == i and roster.at(i) == load("res://game/heroes/data/%s.tres" % names[i])
	_expect(all_found, "the roster is bruiser, mage, scout, medic (tools/run_bots.ps1 and smoke use that order)",
		"index_of() or at() disagrees with roster.tres; update the tools too")
	_expect(roster.index_of("dragon") == -1 and roster.index_of("") == -1, "an unknown hero name is -1", "it is not")
	_expect(roster.at(-1) == null and roster.at(names.size()) == null, "a slot out of range is null", "it is not")


# --- validate() on resources built here --------------------------------------------

func _good_hero() -> HeroData:
	var hero := HeroData.new()
	hero.display_name = "Test Hero"
	hero.role = "Tests things"
	hero.default_weapon = _good_weapon()
	hero.ability = _good_charge()
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


# --- abilities (T14) ----------------------------------------------------------------

func _good_charge() -> DashData:
	var charge := DashData.new()
	charge.display_name = "Test Charge"
	return charge


func _bruiser_has_shield_charge() -> void:
	var bruiser := load(BRUISER_PATH) as HeroData
	_expect(bruiser != null and bruiser.ability is DashData
			and bruiser.ability.resource_path == CHARGE_PATH,
		"bruiser.tres has shield_charge.tres as its ability", "it does not")
	var scout := load(SCOUT_PATH) as HeroData
	var jet := scout.ability as DashData if scout != null else null
	_expect(jet != null and jet.resource_path == JET_DASH_PATH and jet.charges == 2 and jet.knockback_px == 0.0,
		"scout.tres has jet_dash.tres as its ability: 2 charges, no knockback (T18)", "it does not")
	var mage := load(MAGE_PATH) as HeroData
	_expect(mage != null and mage.ability is BlinkData and mage.ability.resource_path == BLINK_PATH,
		"mage.tres has blink.tres as its ability (T18)", "it does not")
	var medic := load(MEDIC_PATH) as HeroData
	_expect(medic != null and medic.ability is HealDroneData and medic.ability.resource_path == HEAL_DRONE_PATH,
		"medic.tres has heal_drone.tres as its ability (T18)", "it does not")


## make() loads its node script by path at run time (T18), so a wrong path would
## only show in the game. Checked here without loading it: it needs Net.
func _abilities_name_their_node() -> void:
	var folder := "res://game/heroes/data"
	for file: String in DirAccess.get_files_at(folder):
		var ability := load(folder.path_join(file)) as AbilityData if file.get_extension() == "tres" else null
		if ability == null:
			continue
		var path := ability._node_script_path()
		_expect(path != "" and ResourceLoader.exists(path), "%s names its node script (%s)" % [file, path],
			"no script at that path")


func _good_charge_passes() -> void:
	var problems := _good_charge().validate()
	_expect(problems.is_empty(), "a shield charge at the defaults passes", "; ".join(problems))
	var hero := _good_hero()
	hero.ability = null
	_expect_problems(hero.validate(), ["ability is empty; pick an AbilityData file such as shield_charge.tres"],
		"a hero with no ability fails (T18)")


func _charge_out_of_range() -> void:
	var charge := _good_charge()
	charge.display_name = ""
	charge.cooldown_sec = 0.0
	_expect_problems(charge.validate(), [
		"display_name is empty; type one in",
		"cooldown_sec is 0 s; it must be 1 to 60 s",
	], "empty display_name and cooldown_sec 0")
	charge = _good_charge()
	charge.dash_distance_px = 47.0
	charge.dash_duration_sec = 1.5
	charge.knockback_px = -1.0
	charge.knockback_duration_sec = 0.0
	_expect_problems(charge.validate(), [
		"dash_distance_px is 47 px; it must be 48 to 960 px",
		"dash_duration_sec is 1.5 s; it must be 0.05 to 1 s",
		"knockback_px is -1 px; it must be 0 to 480 px",
		"knockback_duration_sec is 0 s; it must be 0.05 to 1 s",
	], "each charge number out of range, once each")
	charge = _good_charge()
	charge.knockback_px = 0.0
	_expect_problems(charge.validate(), [], "knockback_px 0 (pushes nobody) passes")
	charge = _good_charge()
	charge.charges = 0
	_expect_problems(charge.validate(), ["charges is 0; it must be 1 to 5"], "charges 0 (T18)")
	charge.charges = 6
	_expect_problems(charge.validate(), ["charges is 6; it must be 1 to 5"], "charges 6")
	charge.charges = 1
	var one_ok := charge.validate().is_empty()
	charge.charges = 5
	_expect(one_ok and charge.validate().is_empty(), "charges 1 and 5 pass", "; ".join(charge.validate()))


func _charge_too_fast() -> void:
	var charge := _good_charge()
	charge.dash_distance_px = 960.0
	charge.dash_duration_sec = 0.24
	_expect_problems(charge.validate(), [], "a dash at exactly 4000 px/s passes")
	charge.dash_duration_sec = 0.05
	charge.knockback_px = 480.0
	charge.knockback_duration_sec = 0.1
	_expect_problems(charge.validate(), [
		"dash speed is 19200 px/s (dash_distance_px / dash_duration_sec); it must be at most 4000 px/s, so shorten the distance or lengthen the time",
		"knockback speed is 4800 px/s (knockback_px / knockback_duration_sec); it must be at most 4000 px/s, so shorten the distance or lengthen the time",
	], "a dash and a knockback faster than 4000 px/s")


## The speed cap must stay within what one 50 ms update may jump before
## RemoteTimeline snaps instead of sliding.
func _charge_cap_fits_the_snap() -> void:
	var per_update := DashData.MAX_SPEED_PX_PER_SEC * MoveCheck.STEP_SEC
	_expect(per_update <= RemoteTimeline.SNAP_DISTANCE,
		"the charge speed cap (%d px per update) is within RemoteTimeline.SNAP_DISTANCE (%d px)" % [
			roundi(per_update), roundi(RemoteTimeline.SNAP_DISTANCE)],
		"lower DashData.MAX_SPEED_PX_PER_SEC or raise SNAP_DISTANCE")


# --- Blink (T18) --------------------------------------------------------------------

func _blink_passes_and_ranges() -> void:
	var blink := BlinkData.new()
	blink.display_name = "Test Blink"
	_expect(blink.validate().is_empty(), "a blink at the defaults passes", "; ".join(blink.validate()))
	blink.distance_px = 47.0
	_expect_problems(blink.validate(), ["distance_px is 47 px; it must be 48 to 480 px"], "blink distance_px 47")
	blink.distance_px = 481.0
	_expect_problems(blink.validate(), ["distance_px is 481 px; it must be 48 to 480 px"], "blink distance_px 481")
	blink.distance_px = 48.0
	var low_ok := blink.validate().is_empty()
	blink.distance_px = 480.0
	_expect(low_ok and blink.validate().is_empty(), "blink distance_px 48 and 480 pass", "; ".join(blink.validate()))


# --- Heal Drone (T18) ---------------------------------------------------------------

func _good_drone() -> HealDroneData:
	var drone := HealDroneData.new()
	drone.display_name = "Test Drone"
	return drone


func _heal_drone_passes_and_ranges() -> void:
	var drone := _good_drone()
	_expect(drone.validate().is_empty(), "a heal drone at the defaults passes", "; ".join(drone.validate()))
	_expect(drone.tick_count() == 8 and drone.total_heal_hp() == 40, "the defaults heal 8 ticks, 40 HP",
		"got %d ticks, %d HP" % [drone.tick_count(), drone.total_heal_hp()])
	drone.heal_per_tick_hp = 0
	drone.tick_sec = 0.05
	drone.duration_sec = 0.4
	drone.radius_px = 47.0
	_expect_problems(drone.validate(), [
		"heal_per_tick_hp is 0 HP; it must be 1 to 50 HP",
		"tick_sec is 0.05 s; it must be 0.1 to 2 s",
		"duration_sec is 0.4 s; it must be 0.5 to 10 s",
		"radius_px is 47 px; it must be 48 to 480 px",
	], "each heal drone number out of range, once each")
	drone = _good_drone()
	drone.heal_per_tick_hp = 51
	drone.radius_px = 481.0
	_expect_problems(drone.validate(), [
		"heal_per_tick_hp is 51 HP; it must be 1 to 50 HP",
		"radius_px is 481 px; it must be 48 to 480 px",
	], "heal_per_tick_hp 51 and radius_px 481")


func _heal_drone_whole_ticks() -> void:
	var drone := _good_drone()
	drone.duration_sec = 4.2
	_expect_problems(drone.validate(), [
		"duration_sec is 4.2 s, not a whole number of tick_sec (0.5 s) ticks; make it a multiple of tick_sec",
	], "duration_sec 4.2 with 0.5 s ticks fails")
	drone.duration_sec = 4.5
	_expect(drone.validate().is_empty() and drone.tick_count() == 9, "duration_sec 4.5 passes: 9 ticks",
		"; ".join(drone.validate()))
	drone.tick_sec = 0.3
	drone.duration_sec = 0.9
	_expect(drone.validate().is_empty() and drone.tick_count() == 3, "0.9 s of 0.3 s ticks passes despite float rounding",
		"; ".join(drone.validate()))


func _ability_problems_passed_on() -> void:
	var hero := _good_hero()
	hero.ability = _good_charge()
	hero.ability.cooldown_sec = 0.0
	_expect_problems(hero.validate(),
		["ability (built-in): cooldown_sec is 0 s; it must be 1 to 60 s"], "a bad ability fails its hero")


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

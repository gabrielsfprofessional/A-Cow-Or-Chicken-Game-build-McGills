extends SceneTree
## Tests for the profile (card T11): name rules, token, safe save, recovery, colors, theme.
## Owner: John.
## Run: godot --headless --path . --script res://tests/profile_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
## Writes only user://profile_test.json and its siblings, never the real profile.json.

const ProfileScript: GDScript = preload("res://game/players/profile.gd")
const COLORS_PATH: String = "res://game/players/data/profile_colors.tres"
const THEME_PATH: String = "res://game/ui/main_theme.tres"
const TEST_PATH: String = "user://profile_test.json"
const TEST_FILE: String = "profile_test.json"
const SCENE_FOLDERS: Array[String] = ["res://game/ui", "res://game/players"]
const TITLE_SIZE: int = 96
const MIN_FONT: int = 18
const MIN_BUTTON_HEIGHT: float = 72.0

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_names()
	_token()
	_corrupt_files()
	_crash_before_rename()
	_crash_between_renames()
	_corrupt_with_good_backup()
	_newer_version()
	_colors()
	_theme()
	_clean()
	print("PROFILE TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _names() -> void:
	var bad: Dictionary[String, String] = {
		"blank": "",
		"all spaces": "      ",
		"13 characters": "1234567890123",
		"13 after trimming": "  1234567890123  ",
		"control character": "a\u0001b",
		"C1 control character": "a\u0085b",
		"zero-width space": "a\u200Bb",
		"right-to-left override": "a\u202Eb",
		"two spaces in a row": "a  b",
		"private-use character": "a\ue000",
	}
	for label: String in bad:
		_expect_true("name fails: %s" % label, ProfileScript.name_problem(bad[label]) != "")
	var good: Dictionary[String, String] = {
		"Zoë": "Zoë",
		"12 characters": "123456789012",
		"12 after trimming": "  123456789012  ",
		"one space inside": "Ann Lee",
	}
	for label: String in good:
		_expect_true("name passes: %s" % label, ProfileScript.name_problem(good[label]) == "")


func _token() -> void:
	_clean()
	_expect_true("first save works", ProfileScript.save(_data("Ann", "#F2555A"), TEST_PATH))
	var first: Dictionary = ProfileScript.load_or_default(TEST_PATH)
	var token: String = first["device_token"]
	_expect_true("token is 32 lowercase hex characters", _is_token(token))
	_expect_true("name and color come back", first["name"] == "Ann" and first["color"] == "#F2555A")
	_expect_true("a rename saves", ProfileScript.save(_data("Bob", "#46A758"), TEST_PATH))
	var second: Dictionary = ProfileScript.load_or_default(TEST_PATH)
	_expect_true("a rename keeps the token", second["device_token"] == token and second["name"] == "Bob")
	ProfileScript.save({"name": "Cy", "color": "#F2555A", "device_token": "0".repeat(32)}, TEST_PATH)
	_expect_true("a token passed in does not replace it", ProfileScript.load_or_default(TEST_PATH)["device_token"] == token)
	_expect_true("an invalid name is refused", not ProfileScript.save(_data("a  b", "#F2555A"), TEST_PATH))
	_expect_true("an invalid color is refused", not ProfileScript.save(_data("Ann", "red"), TEST_PATH))
	_expect_true("the previous file is kept as .bak", FileAccess.file_exists(TEST_PATH + ".bak"))
	_expect_true("no .tmp is left behind", not FileAccess.file_exists(TEST_PATH + ".tmp"))


func _corrupt_files() -> void:
	var cases: Dictionary[String, String] = {
		"bad JSON": "{not json",
		"wrong type": JSON.stringify({"version": 1, "name": 5, "color": "#F2555A", "device_token": "x"}),
		"version 0": JSON.stringify({"version": 0, "name": "Ann", "color": "#F2555A", "device_token": "x"}),
		"version 1.5": JSON.stringify({"version": 1.5, "name": "Ann", "color": "#F2555A", "device_token": "x"}),
		"missing field": JSON.stringify({"version": 1, "name": "Ann"}),
	}
	for label: String in cases:
		_clean()
		_write(TEST_PATH, cases[label])
		_expect_true("%s: no profile" % label, not ProfileScript.exists(TEST_PATH))
		_expect_true("%s: the default comes back" % label, ProfileScript.load_or_default(TEST_PATH)["name"] == "")
		var aside: Array[String] = _files_starting(TEST_FILE + ".bad-")
		_expect_true("%s: moved to .bad-<unix time>" % label, aside.size() == 1 and not FileAccess.file_exists(TEST_PATH))
		_expect_true("%s: bytes unchanged" % label, aside.size() == 1 and _text("user://" + aside[0]) == cases[label])
		_expect_true("%s: a new save works and keeps the old file" % label,
			ProfileScript.save(_data("New", "#F2555A"), TEST_PATH) and _files_starting(TEST_FILE + ".bad-").size() == 1)


func _crash_before_rename() -> void:
	_clean()
	ProfileScript.save(_data("Old", "#F2555A"), TEST_PATH)
	var token: String = ProfileScript.load_or_default(TEST_PATH)["device_token"]
	_write(TEST_PATH + ".tmp", JSON.stringify({"version": 1, "name": "New", "color": "#46A758", "device_token": token}))
	var loaded: Dictionary = ProfileScript.load_or_default(TEST_PATH)
	_expect_true("crash after the temp write: the old profile loads", loaded["name"] == "Old" and loaded["device_token"] == token)
	_expect_true("a leftover .tmp is ignored", _files_starting(TEST_FILE + ".bad-").is_empty())
	_expect_true("the next save replaces it", ProfileScript.save(_data("New", "#46A758"), TEST_PATH)
		and ProfileScript.load_or_default(TEST_PATH)["name"] == "New" and not FileAccess.file_exists(TEST_PATH + ".tmp"))


func _crash_between_renames() -> void:
	_clean()
	ProfileScript.save(_data("Old", "#F2555A"), TEST_PATH)
	var token: String = ProfileScript.load_or_default(TEST_PATH)["device_token"]
	# Only .bak and .tmp exist: profile.json went to .bak, the .tmp never became profile.json.
	DirAccess.rename_absolute(ProjectSettings.globalize_path(TEST_PATH), ProjectSettings.globalize_path(TEST_PATH + ".bak"))
	_write(TEST_PATH + ".tmp", JSON.stringify({"version": 1, "name": "New", "color": "#46A758", "device_token": token}))
	var loaded: Dictionary = ProfileScript.load_or_default(TEST_PATH)
	_expect_true("crash between the renames: the old profile loads from .bak",
		ProfileScript.exists(TEST_PATH) and loaded["name"] == "Old" and loaded["device_token"] == token)


func _corrupt_with_good_backup() -> void:
	_clean()
	ProfileScript.save(_data("Old", "#F2555A"), TEST_PATH)
	var token: String = ProfileScript.load_or_default(TEST_PATH)["device_token"]
	ProfileScript.save(_data("New", "#46A758"), TEST_PATH)
	_write(TEST_PATH, "garbage {")
	var loaded: Dictionary = ProfileScript.load_or_default(TEST_PATH)
	_expect_true("corrupt main, good .bak: the .bak's name, color and token",
		loaded["name"] == "Old" and loaded["color"] == "#F2555A" and loaded["device_token"] == token)
	var aside: Array[String] = _files_starting(TEST_FILE + ".bad-")
	_expect_true("the corrupt file is moved aside, not deleted", aside.size() == 1 and _text("user://" + aside[0]) == "garbage {")


func _newer_version() -> void:
	_clean()
	var text: String = JSON.stringify({"version": 2, "name": "Zed", "color": "#F2555A", "device_token": "x"})
	_write(TEST_PATH, text)
	_expect_true("version 2: newer_version_found", ProfileScript.newer_version_found(TEST_PATH))
	_expect_true("version 2: not a usable profile", not ProfileScript.exists(TEST_PATH))
	_expect_true("version 2: save refuses", not ProfileScript.save(_data("Ann", "#F2555A"), TEST_PATH))
	_expect_true("version 2: file and bytes unchanged", _text(TEST_PATH) == text)
	_expect_true("version 2: nothing renamed", _files_starting(TEST_FILE).size() == 1)


func _colors() -> void:
	var colors: ProfileColors = load(COLORS_PATH)
	_expect_true("profile_colors.tres passes validate()", colors.validate().is_empty())
	_expect_true("it holds 8 swatches", colors.swatches.size() == 8)
	var distance: float = ProfileColors.delta_e(Color("#C084FC"), Color("#3B82F6"))
	_expect_true("delta E violet to blue is 32.4 (got %.2f)" % distance, absf(distance - 32.4) <= 0.1)
	var orange: float = ProfileColors.delta_e(Color("#F2555A"), Color("#F97316"))
	_expect_true("delta E red to orange is 39.7 (got %.2f)" % orange, absf(orange - 39.7) <= 0.1)
	_expect_true("brown has contrast 4.66", absf(ProfileColors.contrast_ratio(Color("#AD7F58"), colors.ui_background) - 4.66) <= 0.02)
	for bad: String in ["#3B82F6", "#F97316", "#202020"]:
		var copy: ProfileColors = colors.duplicate(true)
		var swatches: Array[Color] = copy.swatches.duplicate()
		swatches[0] = Color(bad)
		copy.swatches = swatches
		var problems: PackedStringArray = copy.validate()
		_expect_true("swatch set to %s fails and is named" % bad,
			not problems.is_empty() and "\n".join(problems).contains(bad.to_upper()))
	var dup: ProfileColors = colors.duplicate(true)
	var same: Array[Color] = dup.swatches.duplicate()
	same[1] = same[0]
	dup.swatches = same
	_expect_true("a duplicate swatch is flagged", "\n".join(dup.validate()).contains("same as swatch 1"))
	var short: ProfileColors = colors.duplicate(true)
	var seven: Array[Color] = short.swatches.duplicate()
	seven.remove_at(7)
	short.swatches = seven
	_expect_true("7 swatches is flagged", not short.validate().is_empty())


func _theme() -> void:
	var theme: Theme = load(THEME_PATH)
	_expect_true("the theme loads", theme != null)
	if theme == null:
		return
	_expect_true("default font size is at least %d" % MIN_FONT, theme.default_font_size >= MIN_FONT)
	var smallest: int = 1000
	for type_name: String in theme.get_font_size_type_list():
		for item: String in theme.get_font_size_list(type_name):
			smallest = mini(smallest, theme.get_font_size(item, type_name))
	_expect_true("no font size in the theme is under %d (smallest %d)" % [MIN_FONT, smallest], smallest >= MIN_FONT)
	var box: StyleBox = theme.get_stylebox("normal", "Button")
	var height: float = box.get_minimum_size().y + ThemeDB.fallback_font.get_height(theme.default_font_size)
	_expect_true("buttons are at least %d px tall (%.0f)" % [int(MIN_BUTTON_HEIGHT), height], height >= MIN_BUTTON_HEIGHT)
	var overrides: Array[String] = []
	for folder: String in SCENE_FOLDERS:
		for file: String in DirAccess.get_files_at(folder):
			if not file.ends_with(".tscn"):
				continue
			for line: String in _text(folder + "/" + file).split("\n"):
				if line.begins_with("theme_override_font_sizes/") and not line.strip_edges().ends_with("= %d" % TITLE_SIZE):
					overrides.append("%s: %s" % [file, line.strip_edges()])
	_expect_true("only the %d px title overrides a font size %s" % [TITLE_SIZE, overrides], overrides.is_empty())


func _data(player_name: String, color: String) -> Dictionary:
	return {"name": player_name, "color": color}


func _is_token(text: String) -> bool:
	return text.length() == 32 and text == text.to_lower() and text.is_valid_hex_number(false)


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _files_starting(prefix: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at("user://"):
		if file.begins_with(prefix):
			found.append(file)
	return found


## Removes every test file. Only names starting with profile_test.json.
func _clean() -> void:
	for file: String in _files_starting(TEST_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + file))


func _expect_true(label: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok: %s" % label)
		return
	_failed += 1
	print("  FAIL: %s" % label)

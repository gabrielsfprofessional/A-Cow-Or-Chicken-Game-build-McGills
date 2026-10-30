extends SceneTree
## Tests for the server's player saves (card T21, part 1): folder choice, ids, round
## trip, validation, safe writes after a crash, a cut-short file or a pulled plug, saves
## from another version, locked files, listing.
## Owner: Gabe.
## Run: godot --headless --path . --script res://tests/profile_store_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
## Writes only inside user://profile_store_test/ and removes it at the end.

const TEST_FOLDER: String = "user://profile_store_test/"
## The SHA-256 of "abc", from the standard's own test vectors.
const ABC_SHA256: String = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
const NOW: int = 1793000000

var _store: ProfileStore = ProfileStore.new(TEST_FOLDER)
var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	# Real file ages are seconds old here; _settle() covers the .old path with ages it picks.
	_store.settle_sec = 0
	_remove_folder()
	_store.ensure_folder()
	_folders()
	_ids()
	_round_trip()
	_validation()
	_crash_before_rename()
	_crash_between_renames()
	_cut_short()
	_both_unreadable()
	_newer_version()
	_wrong_id_inside()
	_newer_bak()
	_round_trip_checks()
	_settle()
	_locked()
	_listing()
	_remove_folder()
	_expect_true("the test folder is gone afterwards", not DirAccess.dir_exists_absolute(_global(TEST_FOLDER)))
	print("PROFILE STORE TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _folders() -> void:
	_expect_true("debug build: user://saves_test/", ProfileStore.folder_for(true, PackedStringArray()) == "user://saves_test/")
	_expect_true("release build: user://saves/", ProfileStore.folder_for(false, PackedStringArray()) == "user://saves/")
	_expect_true("--saves wins in a debug build",
		ProfileStore.folder_for(true, PackedStringArray(["--server", "--saves=user://elsewhere"])) == "user://elsewhere/")
	_expect_true("--saves wins in a release build",
		ProfileStore.folder_for(false, PackedStringArray(["--saves=/srv/acoc/"])) == "/srv/acoc/")
	_expect_true("a Windows path gets a slash at the end",
		ProfileStore.folder_for(false, PackedStringArray(["--saves=C:\\acoc\\saves"])) == "C:\\acoc\\saves/")
	_expect_true("a blank --saves is ignored", ProfileStore.folder_for(true, PackedStringArray(["--saves=  "])) == "user://saves_test/")
	_expect_true("the folder always ends in a slash", ProfileStore.new("user://abc").folder == "user://abc/")
	var deep: ProfileStore = ProfileStore.new(TEST_FOLDER + "deep/er")
	_expect_true("ensure_folder makes nested folders, twice is fine",
		deep.ensure_folder() == OK and deep.ensure_folder() == OK and DirAccess.dir_exists_absolute(_global(deep.folder)))
	var missing: ProfileStore = ProfileStore.new(TEST_FOLDER + "not_made_yet")
	_expect_true("a missing folder lists no ids", missing.list_ids().is_empty())


func _ids() -> void:
	_expect_true("id is the SHA-256 of the token", ProfileStore.id_for_token("abc") == ABC_SHA256)
	_expect_true("an empty token has no id", ProfileStore.id_for_token("") == "")
	var id: String = ProfileStore.id_for_token("test-token-1")
	_expect_true("the same token gives the same id", ProfileStore.id_for_token("test-token-1") == id)
	_expect_true("another token gives another id", ProfileStore.id_for_token("test-token-2") != id)
	_expect_true("an id is 64 lowercase hex characters", ProfileStore.is_id(id))
	var bad: Dictionary[String, String] = {
		"uppercase": id.to_upper(),
		"a sign in front": "-" + id.substr(1),
		"63 characters": id.substr(1),
		"65 characters": id + "0",
		"not hex": "g".repeat(64),
		"empty": "",
	}
	for label: String in bad:
		_expect_true("not an id: %s" % label, not ProfileStore.is_id(bad[label]))


func _round_trip() -> void:
	_clean()
	var token: String = "test-token-round-trip"
	var id: String = ProfileStore.id_for_token(token)
	_expect_true("a new player saves", _store.save_player(ProfileStore.new_player(id, "Ann", "#f2555a", NOW)))
	var loaded: Dictionary = _store.load_player(id)
	_expect_true("it loads", loaded["read"] == ProfileStore.Read.OK)
	var data: Dictionary = loaded.get("data", {})
	_expect_true("name and id come back", data.get("name") == "Ann" and data.get("id") == id)
	_expect_true("the color comes back in capitals", data.get("color") == "#F2555A")
	_expect_true("numbers come back as ints, not floats",
		typeof(data.get("created_unix")) == TYPE_INT and typeof(data["stats"]["matches"]) == TYPE_INT)
	_expect_true("every counter starts at 0",
		data["stats"]["matches"] == 0 and data["stats"]["wins"] == 0 and data["stats"]["eliminations"] == 0
		and data["stats"]["damage"] == 0 and (data["stats"]["heroes"] as Dictionary).is_empty())
	var all_text: String = ""
	for file: String in _files():
		all_text += _text(TEST_FOLDER + file)
	_expect_true("the token is in no file", not all_text.contains(token))
	data["stats"]["matches"] = 1
	data["stats"]["heroes"]["scout"] = 1
	_expect_true("a second save works", _store.save_player(data))
	var second: Dictionary = _store.load_player(id)["data"]
	_expect_true("the second save loads", second["stats"]["matches"] == 1 and second["stats"]["heroes"]["scout"] == 1)
	var bak: Dictionary = _parse(TEST_FOLDER + id + ".json.bak")
	_expect_true("the first save is kept as .bak", int(bak.get("stats", {}).get("matches", -1)) == 0)
	_expect_true("no .tmp is left behind", not FileAccess.file_exists(_store.path_for(id) + ".tmp"))
	_expect_true("only the save and its .bak are on disk", _files().size() == 2)


func _validation() -> void:
	var id: String = ProfileStore.id_for_token("test-token-validation")
	_expect_true("a new player passes", ProfileStore.problem_in(ProfileStore.new_player(id, "Ann", "#F2555A", NOW)) == "")
	var cases: Dictionary[String, Callable] = {
		"version 2": func(d: Dictionary) -> void: d["version"] = 2,
		"version 1.5": func(d: Dictionary) -> void: d["version"] = 1.5,
		"uppercase id": func(d: Dictionary) -> void: d["id"] = id.to_upper(),
		"id that is a number": func(d: Dictionary) -> void: d["id"] = 5,
		"empty name": func(d: Dictionary) -> void: d["name"] = "",
		"name of spaces": func(d: Dictionary) -> void: d["name"] = "   ",
		"name over 64 characters": func(d: Dictionary) -> void: d["name"] = "a".repeat(65),
		"color word": func(d: Dictionary) -> void: d["color"] = "red",
		"color too short": func(d: Dictionary) -> void: d["color"] = "#12345",
		"color not hex": func(d: Dictionary) -> void: d["color"] = "#GGGGGG",
		"created below 0": func(d: Dictionary) -> void: d["created_unix"] = -1,
		"created not whole": func(d: Dictionary) -> void: d["created_unix"] = 1.5,
		"last seen as text": func(d: Dictionary) -> void: d["last_seen_unix"] = "5",
		"no stats": func(d: Dictionary) -> void: d.erase("stats"),
		"matches below 0": func(d: Dictionary) -> void: d["stats"]["matches"] = -1,
		"wins not whole": func(d: Dictionary) -> void: d["stats"]["wins"] = 2.5,
		"damage infinite": func(d: Dictionary) -> void: d["stats"]["damage"] = INF,
		"eliminations NaN": func(d: Dictionary) -> void: d["stats"]["eliminations"] = NAN,
		"heroes not a dictionary": func(d: Dictionary) -> void: d["stats"]["heroes"] = [],
		"empty hero name": func(d: Dictionary) -> void: d["stats"]["heroes"][""] = 1,
		"hero name over 32 characters": func(d: Dictionary) -> void: d["stats"]["heroes"]["a".repeat(33)] = 1,
		"hero count below 0": func(d: Dictionary) -> void: d["stats"]["heroes"]["mage"] = -1,
	}
	for label: String in cases:
		_clean()
		var data: Dictionary = ProfileStore.new_player(id, "Ann", "#F2555A", NOW)
		(cases[label] as Callable).call(data)
		_expect_true("%s: refused" % label, ProfileStore.problem_in(data) != "")
		_expect_true("%s: nothing written" % label, not _store.save_player(data) and _files().is_empty())


func _crash_before_rename() -> void:
	_clean()
	var id: String = _save_matches("test-token-crash-1", [0])
	_write(_store.path_for(id) + ".tmp", "{\"version\": 1, \"id\": \"" + id.substr(0, 20))
	var loaded: Dictionary = _store.load_player(id)
	_expect_true("crash while writing the temp file: the last save loads",
		loaded["read"] == ProfileStore.Read.OK and loaded["data"]["stats"]["matches"] == 0)
	_expect_true("a half-written .tmp is ignored, not moved aside", _bad_files().is_empty())
	var data: Dictionary = loaded["data"]
	data["stats"]["matches"] = 1
	_expect_true("the next save replaces the .tmp",
		_store.save_player(data) and not FileAccess.file_exists(_store.path_for(id) + ".tmp")
		and _store.load_player(id)["data"]["stats"]["matches"] == 1)


func _crash_between_renames() -> void:
	_clean()
	var id: String = _save_matches("test-token-crash-2", [0, 1])
	var path: String = _store.path_for(id)
	# The moment after <id>.json became the .bak and before the .tmp became <id>.json.
	DirAccess.remove_absolute(_global(path + ".bak"))
	DirAccess.rename_absolute(_global(path), _global(path + ".bak"))
	var newer: Dictionary = ProfileStore.new_player(id, "Ann", "#F2555A", NOW)
	newer["stats"]["matches"] = 2
	_write(path + ".tmp", JSON.stringify(newer))
	var loaded: Dictionary = _store.load_player(id)
	_expect_true("crash between the renames: the .bak loads",
		loaded["read"] == ProfileStore.Read.OK and loaded["data"]["stats"]["matches"] == 1)
	_expect_true("a player with only a .bak is still listed", _store.list_ids() == PackedStringArray([id]))
	var data: Dictionary = loaded["data"]
	data["stats"]["matches"] = 2
	_expect_true("the next save makes <id>.json again", _store.save_player(data) and FileAccess.file_exists(path)
		and _store.load_player(id)["data"]["stats"]["matches"] == 2 and _bad_files().is_empty())


func _cut_short() -> void:
	_clean()
	var id: String = _save_matches("test-token-power", [0, 1])
	var path: String = _store.path_for(id)
	var whole: String = _text(path)
	var half: String = whole.substr(0, floori(whole.length() / 2.0))
	# A pulled plug can leave the newest file cut short even after the rename.
	_write(path, half)
	var loaded: Dictionary = _store.load_player(id)
	_expect_true("a cut-short save: the .bak loads",
		loaded["read"] == ProfileStore.Read.OK and loaded["data"]["stats"]["matches"] == 0)
	var aside: PackedStringArray = _bad_files()
	_expect_true("the cut-short file moved to .bad-<unix time>", aside.size() == 1 and not FileAccess.file_exists(path))
	_expect_true("its bytes are unchanged", aside.size() == 1 and _text(TEST_FOLDER + aside[0]) == half)
	var data: Dictionary = loaded["data"]
	data["stats"]["matches"] = 2
	_expect_true("the next save works and keeps the .bad file",
		_store.save_player(data) and _store.load_player(id)["data"]["stats"]["matches"] == 2 and _bad_files().size() == 1)


func _both_unreadable() -> void:
	_clean()
	var id: String = ProfileStore.id_for_token("test-token-both")
	var path: String = _store.path_for(id)
	_write(path, "{not json")
	_write(path + ".bak", "[1, 2]")
	_expect_true("both files unreadable: no save", _store.load_player(id)["read"] == ProfileStore.Read.MISSING)
	var aside: PackedStringArray = _bad_files()
	_expect_true("both moved aside, nothing deleted", aside.size() == 2
		and not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"))
	var texts: Array[String] = []
	for file: String in aside:
		texts.append(_text(TEST_FOLDER + file))
	_expect_true("their bytes are unchanged", texts.has("{not json") and texts.has("[1, 2]"))
	_expect_true("a new save starts fresh and keeps both", _store.save_player(ProfileStore.new_player(id, "Ann", "#F2555A", NOW))
		and _bad_files().size() == 2)


func _newer_version() -> void:
	_clean()
	var id: String = ProfileStore.id_for_token("test-token-newer")
	var path: String = _store.path_for(id)
	var future: Dictionary = ProfileStore.new_player(id, "Ann", "#F2555A", NOW)
	future["version"] = 2
	future["level"] = 7
	var text: String = JSON.stringify(future)
	_write(path, text)
	_expect_true("a newer save reads as NEWER", _store.load_player(id)["read"] == ProfileStore.Read.NEWER)
	_expect_true("saving over it is refused", not _store.save_player(ProfileStore.new_player(id, "Bob", "#F2555A", NOW)))
	_expect_true("its bytes are unchanged and nothing moved", _text(path) == text and _bad_files().is_empty()
		and not FileAccess.file_exists(path + ".bak"))


func _wrong_id_inside() -> void:
	_clean()
	var id: String = ProfileStore.id_for_token("test-token-a")
	var other: Dictionary = ProfileStore.new_player(ProfileStore.id_for_token("test-token-b"), "Ann", "#F2555A", NOW)
	_write(_store.path_for(id), JSON.stringify(other))
	_expect_true("a file holding another player's id is not that player",
		_store.load_player(id)["read"] == ProfileStore.Read.MISSING and _bad_files().size() == 1)


func _newer_bak() -> void:
	_clean()
	var id: String = _save_matches("test-token-newer-bak", [3])
	var bak: String = _store.path_for(id) + ".bak"
	var future: Dictionary = ProfileStore.new_player(id, "Ann", "#F2555A", NOW)
	future["version"] = 2
	var text: String = JSON.stringify(future)
	_write(bak, text)
	var data: Dictionary = _store.load_player(id)["data"]
	data["stats"]["matches"] = 4
	_expect_true("a .bak from a newer game: saving is refused", not _store.save_player(data))
	_expect_true("the newer .bak is untouched and nothing moved aside", _text(bak) == text and _bad_files().is_empty()
		and _store.load_player(id)["data"]["stats"]["matches"] == 3)


## What the store writes must load back exactly; anything else is refused before it is saved.
func _round_trip_checks() -> void:
	_clean()
	var id: String = ProfileStore.id_for_token("test-token-round-trip-checks")
	var data: Dictionary = ProfileStore.new_player(id, "Ann", "#F2555A", NOW)
	data["junk"] = "not a field"
	data["stats"]["junk"] = 1
	_expect_true("unknown fields: the save works", _store.save_player(data))
	var text: String = _text(_store.path_for(id))
	_expect_true("unknown fields are not written", not text.contains("junk"))
	var big: Dictionary = ProfileStore.new_player(id, "Ann", "#F2555A", NOW)
	big["stats"]["damage"] = 9007199254740993
	_expect_true("a number past 2^53 is refused (JSON would change it)", ProfileStore.problem_in(big) != ""
		and not _store.save_player(big))
	big["stats"]["damage"] = 9007199254740991
	_expect_true("2^53 - 1 is fine", ProfileStore.problem_in(big) == "")
	var odd: Dictionary = ProfileStore.new_player(id, "An\vn", "#F2555A", NOW)
	_expect_true("a name that wouldn't load back is refused", not _store.save_player(odd))
	_expect_true("its temp file is removed and the last save is kept",
		not FileAccess.file_exists(_store.path_for(id) + ".tmp") and _store.load_player(id)["data"]["name"] == "Ann")


## A pulled plug can lose files the OS hadn't written yet. While <id>.json is younger than
## settle_sec, the older .bak is kept as .old, so one copy that surely reached the disk stays.
func _settle() -> void:
	_clean()
	var real_age: int = _store._file_age_sec(TEST_FOLDER + "missing.json")
	_write(TEST_FOLDER + "age.txt", "x")
	var fresh_age: int = _store._file_age_sec(TEST_FOLDER + "age.txt")
	_expect_true("a file just written is 0-5 s old", fresh_age >= 0 and fresh_age <= 5 and real_age > 1000)
	DirAccess.remove_absolute(_global(TEST_FOLDER + "age.txt"))
	var settled_store: ProfileStore = ProfileStore.new(TEST_FOLDER)
	settled_store.settle_sec = 30
	settled_store.age_of = func(path: String) -> int: return 600
	_save_matches_in(settled_store, "test-token-settled", [0, 1, 2])
	_expect_true("saves far apart: no .old", _files().size() == 2)
	_clean()
	var quick: ProfileStore = ProfileStore.new(TEST_FOLDER)
	quick.settle_sec = 30
	# <id>.json was just written; the .bak (and an .old) have had time to reach the disk.
	quick.age_of = func(path: String) -> int: return 5 if path.ends_with(".json") else 600
	var id: String = _save_matches_in(quick, "test-token-quick", [0, 1, 2])
	var path: String = quick.path_for(id)
	_expect_true("quick saves: the settled .bak became .old",
		int(_parse(path + ".old").get("stats", {}).get("matches", -1)) == 0
		and int(_parse(path + ".bak").get("stats", {}).get("matches", -1)) == 1
		and int(_parse(path).get("stats", {}).get("matches", -1)) == 2)
	_save_matches_in(quick, "test-token-quick", [3])
	_expect_true("the next quick save replaces the .old",
		int(_parse(path + ".old").get("stats", {}).get("matches", -1)) == 1 and _bad_files().is_empty())
	# The plug: neither recent file reached the disk.
	_write(path, "")
	_write(path + ".bak", "\u0000".repeat(40))
	var loaded: Dictionary = quick.load_player(id)
	_expect_true("after the plug, the .old loads", loaded["read"] == ProfileStore.Read.OK
		and loaded["data"]["stats"]["matches"] == 1 and _bad_files().size() == 2)
	_expect_true("and the next save works", quick.save_player(loaded["data"]) and quick.load_player(id)["read"] == ProfileStore.Read.OK)


## A save that exists but can't be opened is LOCKED, never a new player. Linux and macOS only
## (file permissions stand in for a lock); skipped where the user can open it anyway (root).
func _locked() -> void:
	if OS.get_name() == "Windows":
		print("  skipped: locked files (Windows)")
		return
	_clean()
	var id: String = _save_matches("test-token-locked", [5])
	var path: String = _store.path_for(id)
	DirAccess.rename_absolute(_global(path), _global(path + ".bak"))
	FileAccess.set_unix_permissions(path + ".bak", 0)
	if FileAccess.open(path + ".bak", FileAccess.READ) != null:
		FileAccess.set_unix_permissions(path + ".bak", FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
		print("  skipped: locked files (this user can open any file)")
		return
	_expect_true("a locked save is LOCKED, not a new player", _store.load_player(id)["read"] == ProfileStore.Read.LOCKED)
	_expect_true("saving over a locked save is refused",
		not _store.save_player(ProfileStore.new_player(id, "Ann", "#F2555A", NOW)))
	FileAccess.set_unix_permissions(path + ".bak", FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
	_expect_true("unlocked, the old save loads", _store.load_player(id)["data"]["stats"]["matches"] == 5)


func _listing() -> void:
	_clean()
	var a: String = _save_matches("test-token-list-a", [0])
	var b: String = ProfileStore.id_for_token("test-token-list-b")
	var c: String = ProfileStore.id_for_token("test-token-list-c")
	var d: String = ProfileStore.id_for_token("test-token-list-d")
	var e: String = ProfileStore.id_for_token("test-token-list-e")
	_write(TEST_FOLDER + b + ".json.bak", "{}")
	_write(TEST_FOLDER + e + ".json.old", "{}")
	_write(TEST_FOLDER + c + ".json.tmp", "{}")
	_write(TEST_FOLDER + d + ".json.bad-1793000000", "{}")
	_write(TEST_FOLDER + "notes.txt", "hi")
	var expected: PackedStringArray = PackedStringArray([a, b, e])
	expected.sort()
	_expect_true("ids come from .json, .json.bak and .json.old only, sorted", _store.list_ids() == expected)
	_expect_true("an id that isn't one loads nothing", _store.load_player("../../etc/passwd")["read"] == ProfileStore.Read.MISSING)


## Saves one player with each matches value in turn. Returns its id.
func _save_matches(token: String, values: Array) -> String:
	return _save_matches_in(_store, token, values)


func _save_matches_in(store: ProfileStore, token: String, values: Array) -> String:
	var id: String = ProfileStore.id_for_token(token)
	for value: int in values:
		var data: Dictionary = ProfileStore.new_player(id, "Ann", "#F2555A", NOW)
		data["stats"]["matches"] = value
		if not store.save_player(data):
			_expect_true("setup save of %s" % token, false)
	return id


func _files() -> PackedStringArray:
	var global: String = _global(TEST_FOLDER)
	return DirAccess.get_files_at(global) if DirAccess.dir_exists_absolute(global) else PackedStringArray()


func _bad_files() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for file: String in _files():
		if file.contains(".bad-"):
			found.append(file)
	return found


## Removes every file in the test folder, nothing else.
func _clean() -> void:
	for file: String in _files():
		DirAccess.remove_absolute(_global(TEST_FOLDER + file))


## Removes the test folder, including the nested one _folders() makes.
func _remove_folder() -> void:
	_clean()
	for folder: String in [TEST_FOLDER + "deep/er/", TEST_FOLDER + "deep/", TEST_FOLDER]:
		if DirAccess.dir_exists_absolute(_global(folder)):
			DirAccess.remove_absolute(_global(folder))


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _parse(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_text(path))
	return parsed if parsed is Dictionary else {}


func _global(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _expect_true(label: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok: %s" % label)
		return
	_failed += 1
	print("  FAIL: %s" % label)

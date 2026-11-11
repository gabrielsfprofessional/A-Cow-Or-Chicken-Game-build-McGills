extends SceneTree
## Tests for the server's players (card T21, part 2): PlayerRegistry saves a player when
## they join and when they leave, and makes guests of bots, a second window with the same
## profile and saves it must leave alone. Owner: Gabe.
## Run: godot --headless --path . --script res://tests/player_registry_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
## Writes only inside user://player_registry_test/ and removes it at the end.

const TEST_FOLDER: String = "user://player_registry_test/"
const TOKEN_A: String = "0123456789abcdef0123456789abcdef"
const TOKEN_B: String = "fedcba9876543210fedcba9876543210"
const NOW: int = 1793000000

var _store: ProfileStore = ProfileStore.new(TEST_FOLDER)
var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_remove_folder()
	var registry := PlayerRegistry.new(_store)
	_expect_true("open() makes the folder and names it",
		registry.open() == "player saves in %s" % TEST_FOLDER and DirAccess.dir_exists_absolute(_global(TEST_FOLDER)))
	_new_player(registry)
	_second_window(registry)
	_leave_saves(registry)
	_returning_player(registry)
	_guests(registry)
	_other_version()
	_leave_all()
	_add_stats()
	_add_stats_refused()
	_add_stats_disk_refuses()
	_token_nowhere()
	_remove_folder()
	_expect_true("the test folder is gone afterwards", not DirAccess.dir_exists_absolute(_global(TEST_FOLDER)))
	print("PLAYER REGISTRY TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _new_player(registry: PlayerRegistry) -> void:
	var id := ProfileStore.id_for_token(TOKEN_A)
	var line := registry.join(2, _player("Gabe", "#3b82f6", TOKEN_A), NOW)
	_expect_true("a new player is saved at once (%s)" % line, line == "peer 2: player %s \"Gabe\" (new)" % id.substr(0, 8))
	var save := _parse(TEST_FOLDER + id + ".json")
	_expect_true("their save holds the name, the color in capitals and the time",
		save.get("name") == "Gabe" and save.get("color") == "#3B82F6"
		and int(save.get("created_unix", -1)) == NOW and int(save.get("last_seen_unix", -1)) == NOW)
	_expect_true("player_id() names them", registry.player_id(2) == id and registry.player_count() == 1)
	_expect_true("player_name() is the name they joined with", registry.player_name(2) == "Gabe")


## Two windows on one PC share one profile: the second plays as a guest.
func _second_window(registry: PlayerRegistry) -> void:
	var id := ProfileStore.id_for_token(TOKEN_A)
	var line := registry.join(3, _player("Gabe", "#3B82F6", TOKEN_A), NOW + 5)
	_expect_true("the same token again while connected: a guest (%s)" % line,
		line == "peer 3: guest (player %s is already connected as peer 2)" % id.substr(0, 8))
	_expect_true("the guest has no player id and changed no save",
		registry.player_id(3) == "" and int(_parse(TEST_FOLDER + id + ".json").get("last_seen_unix", -1)) == NOW)
	_expect_true("the guest has no name, so its hero shows \"Player 3\"", registry.player_name(3) == "")
	_expect_true("a guest leaving says nothing", registry.leave(3, NOW + 6) == "")


func _leave_saves(registry: PlayerRegistry) -> void:
	var id := ProfileStore.id_for_token(TOKEN_A)
	var line := registry.leave(2, NOW + 60)
	_expect_true("leaving saves when they were last seen (%s)" % line, line == "peer 2: player %s left, saved" % id.substr(0, 8)
		and int(_parse(TEST_FOLDER + id + ".json").get("last_seen_unix", -1)) == NOW + 60)
	_expect_true("after leaving they are no one", registry.player_id(2) == "" and registry.player_count() == 0)
	_expect_true("after leaving they have no name", registry.player_name(2) == "")


## They come back with a new name and color: same save, created time kept.
func _returning_player(registry: PlayerRegistry) -> void:
	var id := ProfileStore.id_for_token(TOKEN_A)
	var line := registry.join(4, _player("Gabriel", "#F25559", TOKEN_A), NOW + 120)
	var save := _parse(TEST_FOLDER + id + ".json")
	_expect_true("a returning player (%s)" % line, line == "peer 4: player %s \"Gabriel\" (returning)" % id.substr(0, 8))
	_expect_true("their save takes the new name and color, keeps the created time",
		save.get("name") == "Gabriel" and save.get("color") == "#F25559"
		and int(save.get("created_unix", -1)) == NOW and int(save.get("last_seen_unix", -1)) == NOW + 120)
	_expect_true("their name is the new one", registry.player_name(4) == "Gabriel")
	registry.leave(4, NOW + 130)


func _guests(registry: PlayerRegistry) -> void:
	var before := _files().size()
	_expect_true("a bot is a guest", registry.join(5, PlayerAuth.guest("bot"), NOW) == "peer 5: guest (bot)")
	_expect_true("a broken message is a guest with its reason",
		registry.join(6, PlayerAuth.read_message("nope".to_utf8_buffer()), NOW) == "peer 6: guest (player message unreadable)")
	_expect_true("guests write nothing", _files().size() == before and registry.player_count() == 0)
	_expect_true("a bot has no name, and nor has a peer that never joined",
		registry.player_name(5) == "" and registry.player_name(999) == "")


## A save from a newer game is left alone, and that player plays as a guest.
func _other_version() -> void:
	var registry := PlayerRegistry.new(_store)
	var id := ProfileStore.id_for_token(TOKEN_B)
	var newer := ProfileStore.new_player(id, "Adam", "#46A758", NOW)
	newer["version"] = ProfileStore.VERSION + 1
	var text := JSON.stringify(newer, "\t")
	_write(TEST_FOLDER + id + ".json", text)
	var line := registry.join(7, _player("Adam", "#46A758", TOKEN_B), NOW + 1)
	_expect_true("a save from a newer game: a guest (%s)" % line,
		line == "peer 7: guest (the save of player %s is from another version of the game; left alone)" % id.substr(0, 8))
	_expect_true("and the newer save is untouched", _text(TEST_FOLDER + id + ".json") == text and registry.player_count() == 0)
	DirAccess.remove_absolute(_global(TEST_FOLDER + id + ".json"))


## The server closing saves every player still connected.
func _leave_all() -> void:
	var registry := PlayerRegistry.new(_store)
	registry.join(8, _player("Gabe", "#3B82F6", TOKEN_A), NOW + 200)
	registry.join(9, _player("Adam", "#46A758", TOKEN_B), NOW + 200)
	var lines := registry.leave_all(NOW + 300)
	var a := _parse(TEST_FOLDER + ProfileStore.id_for_token(TOKEN_A) + ".json")
	var b := _parse(TEST_FOLDER + ProfileStore.id_for_token(TOKEN_B) + ".json")
	_expect_true("leave_all() saves both players (%s)" % ", ".join(lines),
		lines.size() == 2 and int(a.get("last_seen_unix", -1)) == NOW + 300 and int(b.get("last_seen_unix", -1)) == NOW + 300
		and registry.player_count() == 0)


## A match's counts are added and saved at once, add up, and outlive leaving (T22).
func _add_stats() -> void:
	var registry := PlayerRegistry.new(_store)
	var id: String = ProfileStore.id_for_token(TOKEN_A)
	var path: String = TEST_FOLDER + id + ".json"
	registry.join(20, _player("Gabe", "#3B82F6", TOKEN_A), NOW + 400)
	registry.join(21, PlayerAuth.guest("bot"), NOW + 400)
	var before := _parse(path).get("stats", {}) as Dictionary
	var line: String = registry.add_stats(20, _delta(1, 1, 3, 240, {"scout": 1}))
	_expect_true("add_stats() answers one line with the short id and each count (%s)" % line,
		line == "Player %s: matches +1, wins +1, eliminations +3, damage +240, scout +1" % id.substr(0, 8))
	_expect_true("the save on disk has the counts at once", _stats_are(path, int(before["matches"]) + 1,
		int(before["wins"]) + 1, int(before["eliminations"]) + 3, int(before["damage"]) + 240, {"scout": 1}))
	registry.add_stats(20, _delta(1, 0, 2, 100, {"scout": 1}))
	registry.add_stats(20, _delta(1, 0, 0, 0, {"mage": 1}))
	_expect_true("later matches add up, per hero too", _stats_are(path, int(before["matches"]) + 3,
		int(before["wins"]) + 1, int(before["eliminations"]) + 5, int(before["damage"]) + 340, {"scout": 2, "mage": 1}))
	line = registry.add_stats(20, _delta(0, 0, 1, 60, {}))
	_expect_true("a leaver's counts have no hero in the line (%s)" % line,
		line == "Player %s: matches +0, wins +0, eliminations +1, damage +60" % id.substr(0, 8))
	var files: int = _files().size()
	_expect_true("a guest gets nothing: no line, no file", registry.add_stats(21, _delta(1, 1, 3, 240, {"scout": 1})) == ""
		and registry.add_stats(999, _delta(1, 0, 0, 0, {})) == "" and _files().size() == files)
	registry.leave(20, NOW + 500)
	_expect_true("add_stats() then leave: the stats are still there, with the new last-seen time",
		_stats_are(path, int(before["matches"]) + 3, int(before["wins"]) + 1, int(before["eliminations"]) + 6,
			int(before["damage"]) + 400, {"scout": 2, "mage": 1})
		and int(_parse(path).get("last_seen_unix", -1)) == NOW + 500)
	registry.join(22, _player("Gabe", "#3B82F6", TOKEN_A), NOW + 600)
	registry.add_stats(22, _delta(1, 1, 0, 0, {"scout": 1}))
	_expect_true("coming back keeps them and adds to them", _stats_are(path, int(before["matches"]) + 4,
		int(before["wins"]) + 2, int(before["eliminations"]) + 6, int(before["damage"]) + 400, {"scout": 3, "mage": 1}))
	registry.leave(22, NOW + 700)


## A delta that breaks the rules changes nothing, on disk or in the copy leave() saves.
func _add_stats_refused() -> void:
	var registry := PlayerRegistry.new(_store)
	var id: String = ProfileStore.id_for_token(TOKEN_B)
	var path: String = TEST_FOLDER + id + ".json"
	registry.join(30, _player("Adam", "#46A758", TOKEN_B), NOW + 400)
	# Counts above 0 first, so a count below 0 would still leave a save that loads.
	registry.add_stats(30, _delta(1, 0, 2, 50, {"scout": 1}))
	var text: String = _text(path)
	var bad: Dictionary[String, Dictionary] = {
		"a count below 0": _delta(1, 0, -1, 0, {}),
		"a count that isn't whole": {"matches": 1, "wins": 0, "eliminations": 1.5, "damage": 0, "heroes": {}},
		"a count that is text": {"matches": "1", "wins": 0, "eliminations": 0, "damage": 0, "heroes": {}},
		"heroes that isn't a list": {"matches": 1, "wins": 0, "eliminations": 0, "damage": 0, "heroes": "scout"},
		"a hero name with a new line": _delta(1, 0, 0, 0, {"scout\n[Server] fake": 1}),
		"a hero name in capitals": _delta(1, 0, 0, 0, {"Scout": 1}),
		"an empty hero name": _delta(1, 0, 0, 0, {"": 1}),
		"a hero name of 33 characters": _delta(1, 0, 0, 0, {"a".repeat(33): 1}),
		"a hero count below 0": _delta(1, 0, 0, 0, {"scout": -1}),
		"a count past what a save can hold": _delta(0, 0, 0, ProfileStore.WHOLE_MAX + 1, {}),
	}
	for what: String in bad:
		var line: String = registry.add_stats(30, bad[what])
		_expect_true("%s is not recorded (%s)" % [what, line.c_escape()],
			line.begins_with("Player %s: not recorded (" % id.substr(0, 8)) and not line.contains("\n") and _text(path) == text)
	_expect_true("a count that reaches what a save can hold is recorded",
		registry.add_stats(30, _delta(0, 0, 0, ProfileStore.WHOLE_MAX - 50, {})).ends_with("damage +%d" % (ProfileStore.WHOLE_MAX - 50))
		and _text(path) != text)
	text = _text(path)
	var line: String = registry.add_stats(30, _delta(0, 0, 0, 1, {}))
	_expect_true("a count that would pass what a save can hold is not recorded (%s)" % line,
		line.begins_with("Player %s: not recorded (stats.damage" % id.substr(0, 8)) and _text(path) == text)
	_expect_true("a hero name of 32 small letters, digits and _ is recorded",
		registry.add_stats(30, _delta(1, 0, 0, 0, {"hero_2".repeat(5) + "ab": 1})).ends_with("ab +1"))
	registry.leave(30, NOW + 500)
	_expect_true("after the refusals, leaving still saves", int(_parse(path).get("last_seen_unix", -1)) == NOW + 500
		and int((_parse(path).get("stats", {}) as Dictionary).get("matches", -1)) == 2)
	DirAccess.remove_absolute(_global(path))
	DirAccess.remove_absolute(_global(path + ".bak"))
	DirAccess.remove_absolute(_global(path + ".old"))


## The disk refuses a save (here: a save from a newer game appeared): the counts stay
## in the registry's copy, and the save on leaving writes them.
func _add_stats_disk_refuses() -> void:
	var registry := PlayerRegistry.new(_store)
	var id: String = ProfileStore.id_for_token(TOKEN_B)
	var path: String = TEST_FOLDER + id + ".json"
	registry.join(40, _player("Adam", "#46A758", TOKEN_B), NOW + 400)
	var good: String = _text(path)
	var newer: Dictionary = ProfileStore.new_player(id, "Adam", "#46A758", NOW)
	newer["version"] = ProfileStore.VERSION + 1
	_write(path, JSON.stringify(newer, "\t"))
	print("  (1 WARNING line follows on purpose: the store refuses to save over a newer save)")
	var line: String = registry.add_stats(40, _delta(1, 1, 2, 90, {"medic": 1}))
	_expect_true("the disk refuses: the line says so and keeps the counts (%s)" % line,
		line == "Player %s: matches +1, wins +1, eliminations +2, damage +90, medic +1; could not save now, will try again when they leave" % id.substr(0, 8))
	_write(path, good)
	registry.leave(40, NOW + 500)
	_expect_true("and the save on leaving writes them", _stats_are(path, 1, 1, 2, 90, {"medic": 1}))


## Neither token is in any file name or file.
func _token_nowhere() -> void:
	var found := false
	for file: String in _files():
		if file.contains(TOKEN_A) or file.contains(TOKEN_B):
			found = true
		var text: String = _text(TEST_FOLDER + file)
		if text.contains(TOKEN_A) or text.contains(TOKEN_B):
			found = true
	_expect_true("no token in any file name or save (%d files)" % _files().size(), not found and _files().size() > 0)


func _player(player_name: String, color: String, token: String) -> Dictionary:
	return PlayerAuth.read_message(PlayerAuth.player_message(player_name, color, token))


func _delta(matches: int, wins: int, eliminations: int, damage: int, heroes: Dictionary) -> Dictionary:
	return {"matches": matches, "wins": wins, "eliminations": eliminations, "damage": damage, "heroes": heroes}


## True when the save at `path` has exactly these stats.
func _stats_are(path: String, matches: int, wins: int, eliminations: int, damage: int, heroes: Dictionary) -> bool:
	var stats: Variant = _parse(path).get("stats")
	if not stats is Dictionary:
		return false
	var found: Dictionary = stats
	var found_heroes: Variant = found.get("heroes")
	if not found_heroes is Dictionary or (found_heroes as Dictionary).size() != heroes.size():
		return false
	for hero: String in heroes:
		if int((found_heroes as Dictionary).get(hero, -1)) != int(heroes[hero]):
			return false
	return int(found.get("matches", -1)) == matches and int(found.get("wins", -1)) == wins \
		and int(found.get("eliminations", -1)) == eliminations and int(found.get("damage", -1)) == damage


func _files() -> PackedStringArray:
	var global := _global(TEST_FOLDER)
	return DirAccess.get_files_at(global) if DirAccess.dir_exists_absolute(global) else PackedStringArray()


func _remove_folder() -> void:
	for file: String in _files():
		DirAccess.remove_absolute(_global(TEST_FOLDER + file))
	if DirAccess.dir_exists_absolute(_global(TEST_FOLDER)):
		DirAccess.remove_absolute(_global(TEST_FOLDER))


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


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

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


## Two windows on one PC share one profile: the second plays as a guest.
func _second_window(registry: PlayerRegistry) -> void:
	var id := ProfileStore.id_for_token(TOKEN_A)
	var line := registry.join(3, _player("Gabe", "#3B82F6", TOKEN_A), NOW + 5)
	_expect_true("the same token again while connected: a guest (%s)" % line,
		line == "peer 3: guest (player %s is already connected as peer 2)" % id.substr(0, 8))
	_expect_true("the guest has no player id and changed no save",
		registry.player_id(3) == "" and int(_parse(TEST_FOLDER + id + ".json").get("last_seen_unix", -1)) == NOW)
	_expect_true("a guest leaving says nothing", registry.leave(3, NOW + 6) == "")


func _leave_saves(registry: PlayerRegistry) -> void:
	var id := ProfileStore.id_for_token(TOKEN_A)
	var line := registry.leave(2, NOW + 60)
	_expect_true("leaving saves when they were last seen (%s)" % line, line == "peer 2: player %s left, saved" % id.substr(0, 8)
		and int(_parse(TEST_FOLDER + id + ".json").get("last_seen_unix", -1)) == NOW + 60)
	_expect_true("after leaving they are no one", registry.player_id(2) == "" and registry.player_count() == 0)


## They come back with a new name and color: same save, created time kept.
func _returning_player(registry: PlayerRegistry) -> void:
	var id := ProfileStore.id_for_token(TOKEN_A)
	var line := registry.join(4, _player("Gabriel", "#F25559", TOKEN_A), NOW + 120)
	var save := _parse(TEST_FOLDER + id + ".json")
	_expect_true("a returning player (%s)" % line, line == "peer 4: player %s \"Gabriel\" (returning)" % id.substr(0, 8))
	_expect_true("their save takes the new name and color, keeps the created time",
		save.get("name") == "Gabriel" and save.get("color") == "#F25559"
		and int(save.get("created_unix", -1)) == NOW and int(save.get("last_seen_unix", -1)) == NOW + 120)
	registry.leave(4, NOW + 130)


func _guests(registry: PlayerRegistry) -> void:
	var before := _files().size()
	_expect_true("a bot is a guest", registry.join(5, PlayerAuth.guest("bot"), NOW) == "peer 5: guest (bot)")
	_expect_true("a broken message is a guest with its reason",
		registry.join(6, PlayerAuth.read_message("nope".to_utf8_buffer()), NOW) == "peer 6: guest (player message unreadable)")
	_expect_true("guests write nothing", _files().size() == before and registry.player_count() == 0)


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


## Neither token is in any file name or file.
func _token_nowhere() -> void:
	var found := false
	for file: String in _files():
		if file.contains(TOKEN_A) or file.contains(TOKEN_B):
			found = true
		var text := _text(TEST_FOLDER + file)
		if text.contains(TOKEN_A) or text.contains(TOKEN_B):
			found = true
	_expect_true("no token in any file name or save (%d files)" % _files().size(), not found and _files().size() > 0)


func _player(player_name: String, color: String, token: String) -> Dictionary:
	return PlayerAuth.read_message(PlayerAuth.player_message(player_name, color, token))


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

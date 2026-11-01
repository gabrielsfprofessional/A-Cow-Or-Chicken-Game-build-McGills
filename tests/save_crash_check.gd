extends SceneTree
## Run by tools/save_crash_test.sh and .ps1 after each hard kill (card T21, part 1).
## Owner: Gabe. Fails when a player that loaded at an earlier check is gone, when a
## player's "matches" went backwards, when a save on disk doesn't load, or when a file
## had to be moved aside (a killed process never cuts a file short; only a pulled plug can).
## It remembers each player's last "matches" in <saves folder>.seen.json, beside the folder.
## Args: -- --saves=<a temp folder> [--players=8]. Exits 0 when all is well.

const TOKEN_FORMAT: String = "crash-test-token-%d"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = ProfileStore.folder_for(true, args)
	if folder == ProfileStore.DEBUG_FOLDER:
		print("SAVE CRASH CHECK: needs -- --saves=<a temp folder>; it never runs on %s" % folder)
		quit(2)
		return
	var players: int = 8
	for arg: String in args:
		if arg.begins_with("--players=") and arg.substr(10).is_valid_int():
			players = clampi(arg.substr(10).to_int(), 1, 64)
	var store: ProfileStore = ProfileStore.new(folder)
	var seen_path: String = store.folder.trim_suffix("/").trim_suffix("\\") + ".seen.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(seen_path)) if FileAccess.file_exists(seen_path) else {}
	var seen: Dictionary = parsed if parsed is Dictionary else {}
	var problems: int = 0
	var saved: int = 0
	for i: int in players:
		var id: String = ProfileStore.id_for_token(TOKEN_FORMAT % i)
		var found: Dictionary = store.load_player(id)
		if found["read"] == ProfileStore.Read.OK:
			saved += 1
			var matches: int = int(found["data"]["stats"]["matches"])
			if matches < int(seen.get(id, 0)):
				problems += 1
				print("  player %d (%s): matches went back from %d to %d" % [i, id.substr(0, 8), int(seen[id]), matches])
			seen[id] = matches
		elif seen.has(id):
			problems += 1
			print("  player %d (%s): loaded at the last check, now %s" % [i, id.substr(0, 8), ProfileStore.Read.keys()[found["read"]]])
		elif FileAccess.file_exists(store.path_for(id)) or FileAccess.file_exists(store.path_for(id) + ".bak"):
			problems += 1
			print("  player %d (%s): a save is on disk but doesn't load" % [i, id.substr(0, 8)])
	var global: String = ProjectSettings.globalize_path(store.folder)
	var files: PackedStringArray = DirAccess.get_files_at(global) if DirAccess.dir_exists_absolute(global) else PackedStringArray()
	for file: String in files:
		if file.contains(".bad-"):
			problems += 1
			print("  %s had to be moved aside" % file)
	var out: FileAccess = FileAccess.open(seen_path, FileAccess.WRITE)
	if out == null or not out.store_string(JSON.stringify(seen)):
		problems += 1
		print("  could not write %s" % seen_path)
	if out != null:
		out.close()
	print("SAVE CRASH CHECK: %s (%d of %d players saved so far)" % ["PASS" if problems == 0 else "FAIL, %d problem(s)" % problems, saved, players])
	quit(0 if problems == 0 else 1)

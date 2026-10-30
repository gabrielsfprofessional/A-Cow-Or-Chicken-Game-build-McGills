extends SceneTree
## Not a test by itself (card T21, part 1). Owner: Gabe. tools/save_crash_test.sh and
## .ps1 start it, hard-kill it while it saves, then run save_crash_check.gd.
## Args: -- --saves=<a temp folder> [--players=8] [--writer-limit-sec=60]
## Saves the players round robin until it is killed (or the limit passes), adding 1 to
## each one's "matches" per save, so every save really changes the file.

const TOKEN_FORMAT: String = "crash-test-token-%d"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = ProfileStore.folder_for(true, args)
	if folder == ProfileStore.DEBUG_FOLDER:
		print("[SaveCrash] needs -- --saves=<a temp folder>; it never runs on %s" % folder)
		quit(2)
		return
	var players: int = clampi(_int_arg(args, "--players=", 8), 1, 64)
	var limit_msec: int = clampi(_int_arg(args, "--writer-limit-sec=", 60), 5, 600) * 1000
	var store: ProfileStore = ProfileStore.new(folder)
	if store.ensure_folder() != OK:
		print("[SaveCrash] cannot make %s" % store.folder)
		quit(1)
		return
	var ids: Array[String] = []
	for i: int in players:
		ids.append(ProfileStore.id_for_token(TOKEN_FORMAT % i))
	print("[SaveCrash] writing %d players" % players)
	var saves: int = 0
	while Time.get_ticks_msec() < limit_msec:
		for id: String in ids:
			var found: Dictionary = store.load_player(id)
			var data: Dictionary
			if found["read"] == ProfileStore.Read.OK:
				data = found["data"]
			elif found["read"] == ProfileStore.Read.MISSING:
				data = ProfileStore.new_player(id, "Crash %s" % id.substr(0, 4), "#3B82F6", int(Time.get_unix_time_from_system()))
			else:
				continue
			data["stats"]["matches"] = int(data["stats"]["matches"]) + 1
			data["last_seen_unix"] = int(Time.get_unix_time_from_system())
			if store.save_player(data):
				saves += 1
	print("[SaveCrash] limit reached after %d saves" % saves)
	quit(0)


func _int_arg(args: PackedStringArray, flag: String, fallback: int) -> int:
	for arg: String in args:
		if arg.begins_with(flag) and arg.substr(flag.length()).is_valid_int():
			return arg.substr(flag.length()).to_int()
	return fallback

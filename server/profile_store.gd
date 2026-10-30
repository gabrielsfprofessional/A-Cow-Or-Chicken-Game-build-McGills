class_name ProfileStore
extends RefCounted
## The server's player saves (card T21, part 1). Owner: Gabe (server).
##
## One JSON file per player, all in one folder, named by the player's id: the SHA-256
## of their device token as 64 lowercase hex characters. The token itself is never
## stored, printed or logged. Part 2 (after #71) receives the token in the second auth
## message and calls id_for_token(); until then nothing in the game calls this class.
##
## Safe writes, building on the pattern of game/players/profile.gd (T11):
## - save_player() writes <id>.json.tmp and loads it back, moves <id>.json to
##   <id>.json.bak, then renames the temp file to <id>.json. A crash loses at most the
##   newest save, never the player.
## - Godot can't force a file onto the disk, and Windows may hold a just-written file in
##   memory for a few seconds. So while <id>.json is younger than settle_sec, an older
##   .bak isn't deleted but kept as <id>.json.old. A pulled plug loses at most the saves
##   of the last settle_sec seconds.
## - A file that can't be parsed is renamed to <file>.bad-<unix time>. Nothing here deletes
##   or overwrites a file it can't read. A file that can't be opened at all (locked for a
##   moment, say by antivirus or a backup) makes the player LOCKED: try again later.
## - A file from another version of the game is left alone, and saving over it is refused.
##
## Folder: "-- --saves=<path>" when given, in any build. Otherwise release builds use
## user://saves/ and debug builds (editor, console build, smoke, bots, tests) user://saves_test/,
## so a test never touches the family's saves (decided Oct 2026). The family server must be a
## release export (T29) or run with "-- --saves=user://saves/".

## Schema of one save. Raise it when a field changes, and teach _read() the old one.
const VERSION: int = 1
const RELEASE_FOLDER: String = "user://saves/"
const DEBUG_FOLDER: String = "user://saves_test/"
const SAVES_FLAG: String = "--saves="
const EXTENSION: String = ".json"
const TMP_SUFFIX: String = ".tmp"
const BAK_SUFFIX: String = ".bak"
const OLD_SUFFIX: String = ".old"
const BAD_INFIX: String = ".bad-"
const ID_LENGTH: int = 64
## A storage limit only. Part 2 checks names with T11's rules before they get here.
const NAME_MAX: int = 64
const HERO_NAME_MAX: int = 32
## The counters T22 records. Each is a whole number, never below 0.
const STAT_KEYS: Array[String] = ["matches", "wins", "eliminations", "damage"]
## JSON numbers are doubles: whole numbers past this lose precision.
const WHOLE_MAX: int = 9007199254740991

## What load_player() found. LOCKED: a save exists but can't be opened now; never treat
## that player as new. NEWER, OLDER: a save from another version; leave it alone.
## BAD is internal: load_player() moves such a file aside and looks further.
enum Read { MISSING, OK, BAD, NEWER, OLDER, LOCKED }

## Where this store keeps its files. Always ends in a slash.
var folder: String = ""
## A new <id>.json younger than this keeps the older .bak as .old (see the top).
var settle_sec: int = 30
## Seconds since a file was last written. Tests swap this out.
var age_of: Callable


func _init(folder_path: String) -> void:
	folder = _with_slash(folder_path)
	age_of = _file_age_sec


## The folder from "--saves=<path>", else the build's default. Takes its inputs so tests can call it.
static func folder_for(debug_build: bool, user_args: PackedStringArray) -> String:
	for arg: String in user_args:
		if arg.begins_with(SAVES_FLAG):
			var value: String = arg.substr(SAVES_FLAG.length()).strip_edges()
			if value != "":
				return _with_slash(value)
	return DEBUG_FOLDER if debug_build else RELEASE_FOLDER


## The store for this process: this build's folder and its "--saves=" argument.
static func open_default() -> ProfileStore:
	return ProfileStore.new(folder_for(OS.is_debug_build(), OS.get_cmdline_user_args()))


## Makes the folder when it isn't there. OK when it exists afterwards.
func ensure_folder() -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))


## The player id for a device token: its SHA-256 as 64 lowercase hex characters.
## "" for an empty token, which never gets a save.
static func id_for_token(token: String) -> String:
	return token.sha256_text() if token != "" else ""


## True for exactly 64 lowercase hex characters (no sign, no prefix).
static func is_id(text: String) -> bool:
	return text.length() == ID_LENGTH and _only_chars(text, "0123456789abcdef")


## The file a player's save lives in.
func path_for(id: String) -> String:
	return folder + id + EXTENSION


## A new player's save: every counter at 0, created and last seen at now_unix.
static func new_player(id: String, player_name: String, color: String, now_unix: int) -> Dictionary:
	return {
		"version": VERSION,
		"id": id,
		"name": player_name,
		"color": color.to_upper(),
		"created_unix": now_unix,
		"last_seen_unix": now_unix,
		"stats": {"matches": 0, "wins": 0, "eliminations": 0, "damage": 0, "heroes": {}},
	}


## "" when `data` is a whole save of this version, else its first problem in plain words.
static func problem_in(data: Dictionary) -> String:
	if not _is_whole(data.get("version")) or int(data["version"]) != VERSION:
		return "version is not %d" % VERSION
	var id: Variant = data.get("id")
	if not id is String or not is_id(id):
		return "id is not 64 lowercase hex characters"
	var player_name: Variant = data.get("name")
	if not player_name is String or (player_name as String).strip_edges() == "" \
			or (player_name as String).length() > NAME_MAX:
		return "name is empty or longer than %d characters" % NAME_MAX
	var color: Variant = data.get("color")
	if not color is String or not _is_color(color):
		return "color is not #RRGGBB"
	for key: String in ["created_unix", "last_seen_unix"]:
		if not _is_count(data.get(key)):
			return "%s is not a whole number from 0 to %d" % [key, WHOLE_MAX]
	var stats: Variant = data.get("stats")
	if not stats is Dictionary:
		return "stats is missing"
	for key: String in STAT_KEYS:
		if not _is_count((stats as Dictionary).get(key)):
			return "stats.%s is not a whole number from 0 to %d" % [key, WHOLE_MAX]
	var heroes: Variant = (stats as Dictionary).get("heroes")
	if not heroes is Dictionary:
		return "stats.heroes is missing"
	for hero: Variant in heroes:
		if not hero is String or (hero as String) == "" or (hero as String).length() > HERO_NAME_MAX:
			return "stats.heroes has a hero name that is empty or longer than %d characters" % HERO_NAME_MAX
		if not _is_count((heroes as Dictionary)[hero]):
			return "stats.heroes.%s is not a whole number from 0 to %d" % [hero, WHOLE_MAX]
	return ""


## Loads one player. {"read": Read.OK, "data": {...}} or {"read": Read.MISSING} (a new
## player), Read.LOCKED (try again later) or Read.NEWER / Read.OLDER (leave it alone).
## Looks at <id>.json, then .bak, then .old, and moves unparsable files aside on the way.
func load_player(id: String) -> Dictionary:
	if not is_id(id):
		return {"read": Read.MISSING}
	var path: String = path_for(id)
	for suffix: String in ["", BAK_SUFFIX, OLD_SUFFIX]:
		var found: Dictionary = _read(path + suffix, id)
		var read: Read = found["read"]
		if read == Read.MISSING:
			continue
		if read == Read.BAD:
			_move_aside(path + suffix)
			continue
		return found  # OK, LOCKED, NEWER or OLDER.
	return {"read": Read.MISSING}


## Saves one player. Answers false when nothing new was saved: bad data, a save from another
## version or a locked one on disk, a save that wouldn't load back the same, a file that
## couldn't be moved aside, or a disk error. On false the last good save is still on disk.
func save_player(data: Dictionary) -> bool:
	var problem: String = problem_in(data)
	if problem != "":
		push_warning("ProfileStore: not saving: %s" % problem)
		return false
	var clean: Dictionary = _normalized(data)
	var id: String = clean["id"]
	var path: String = path_for(id)
	var found: Read = load_player(id)["read"]
	if found == Read.LOCKED or found == Read.NEWER or found == Read.OLDER:
		push_warning("ProfileStore: the save for %s is locked or from another version, not saving" % _short(id))
		return false
	# load_player() moved unparsable files aside. A <id>.json still here that won't load couldn't be moved.
	if FileAccess.file_exists(path) and _read(path, id)["read"] != Read.OK:
		push_warning("ProfileStore: the save for %s can't be moved aside, not saving" % _short(id))
		return false
	var tmp: String = path + TMP_SUFFIX
	if not _write_checked(tmp, JSON.stringify(clean, "\t")):
		push_warning("ProfileStore: could not write %s" % tmp.get_file())
		return false
	var back: Dictionary = _read(tmp, id)
	if back["read"] != Read.OK or back["data"] != clean:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		push_warning("ProfileStore: the save for %s would not load back the same, not saving" % _short(id))
		return false
	if FileAccess.file_exists(path):
		var bak: String = path + BAK_SUFFIX
		if FileAccess.file_exists(bak) and not _clear_bak(path, bak, id):
			return false
		if not _rename(path, bak):
			push_warning("ProfileStore: could not keep %s as .bak" % path.get_file())
			return false
	if not _rename(tmp, path):
		# The .bak holds the last good save, and load_player() falls back to it.
		push_warning("ProfileStore: could not finish saving %s" % path.get_file())
		return false
	return true


## Every player id with a save in the folder (a main file, or only a .bak or .old), sorted.
func list_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var global: String = ProjectSettings.globalize_path(folder)
	if not DirAccess.dir_exists_absolute(global):
		return ids
	for file: String in DirAccess.get_files_at(global):
		for ending: String in [EXTENSION, EXTENSION + BAK_SUFFIX, EXTENSION + OLD_SUFFIX]:
			if file.ends_with(ending):
				var stem: String = file.trim_suffix(ending)
				if is_id(stem) and not ids.has(stem):
					ids.append(stem)
	ids.sort()
	return ids


## Makes room for <id>.json to become the .bak. A good .bak is deleted, unless <id>.json is
## younger than settle_sec and the .bak older: then the .bak becomes .old, the newest copy
## that has surely reached the disk. False (with a warning) when saving must stop.
func _clear_bak(path: String, bak: String, id: String) -> bool:
	var bak_read: Read = _read(bak, id)["read"]
	if bak_read == Read.BAD:
		return _move_aside(bak)
	if bak_read != Read.OK:
		push_warning("ProfileStore: %s is locked or from another version, not saving" % bak.get_file())
		return false
	if int(age_of.call(path)) < settle_sec and int(age_of.call(bak)) >= settle_sec:
		var old: String = path + OLD_SUFFIX
		if FileAccess.file_exists(old):
			var old_read: Read = _read(old, id)["read"]
			if old_read == Read.BAD:
				if not _move_aside(old):
					return false
			elif old_read != Read.OK:
				push_warning("ProfileStore: %s is locked or from another version, not saving" % old.get_file())
				return false
			elif DirAccess.remove_absolute(ProjectSettings.globalize_path(old)) != OK:
				push_warning("ProfileStore: could not replace %s" % old.get_file())
				return false
		if _rename(bak, old):
			return true
		push_warning("ProfileStore: could not keep %s as .old" % bak.get_file())
		return false
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(bak)) == OK:
		return true
	push_warning("ProfileStore: could not replace %s" % bak.get_file())
	return false


## Reads one file without changing it. A file that exists but can't be opened is LOCKED.
static func _read(path: String, expected_id: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"read": Read.MISSING}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"read": Read.LOCKED}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {"read": Read.BAD}
	var data: Dictionary = json.data
	var version: Variant = data.get("version")
	if not _is_whole(version) or float(version) < 1.0:
		return {"read": Read.BAD}
	if float(version) > VERSION:
		return {"read": Read.NEWER}
	if float(version) < VERSION:
		return {"read": Read.OLDER}  # Not migrated yet: never moved aside, saving refused.
	if problem_in(data) != "" or data["id"] != expected_id:
		return {"read": Read.BAD}
	return {"read": Read.OK, "data": _normalized(data)}


## A clean copy with whole numbers as ints (JSON gives floats) and only the known fields.
static func _normalized(data: Dictionary) -> Dictionary:
	var stats: Dictionary = data["stats"]
	var heroes: Dictionary = {}
	for hero: String in (stats["heroes"] as Dictionary):
		heroes[hero] = int(stats["heroes"][hero])
	var clean_stats: Dictionary = {"heroes": heroes}
	for key: String in STAT_KEYS:
		clean_stats[key] = int(stats[key])
	return {
		"version": VERSION,
		"id": str(data["id"]),
		"name": str(data["name"]),
		"color": str(data["color"]).to_upper(),
		"created_unix": int(data["created_unix"]),
		"last_seen_unix": int(data["last_seen_unix"]),
		"stats": clean_stats,
	}


## Writes text to a file and reads it back. True only when the file holds exactly that text.
static func _write_checked(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	var wrote: bool = file.get_error() == OK
	file.close()
	return wrote and FileAccess.get_file_as_string(path) == text


## Renames an unparsable file to <file>.bad-<unix time>, so no save can overwrite it.
static func _move_aside(path: String) -> bool:
	var stamp: int = int(Time.get_unix_time_from_system())
	var target: String = "%s%s%d" % [path, BAD_INFIX, stamp]
	while FileAccess.file_exists(target):
		stamp += 1
		target = "%s%s%d" % [path, BAD_INFIX, stamp]
	if _rename(path, target):
		return true
	push_warning("ProfileStore: could not move %s aside" % path.get_file())
	return false


static func _rename(from: String, to: String) -> bool:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to)) == OK


func _file_age_sec(path: String) -> int:
	return int(Time.get_unix_time_from_system()) - FileAccess.get_modified_time(path)


static func _with_slash(path: String) -> String:
	return path if path.ends_with("/") or path.ends_with("\\") else path + "/"


static func _is_whole(value: Variant) -> bool:
	if value is int:
		return absi(value) <= WHOLE_MAX
	if not value is float:
		return false
	var number: float = value
	return is_finite(number) and number == floorf(number) and absf(number) <= float(WHOLE_MAX)


static func _is_count(value: Variant) -> bool:
	return _is_whole(value) and float(value) >= 0.0


static func _is_color(text: String) -> bool:
	return text.length() == 7 and text.begins_with("#") and _only_chars(text.substr(1).to_lower(), "0123456789abcdef")


static func _only_chars(text: String, allowed: String) -> bool:
	for i: int in text.length():
		if not allowed.contains(text[i]):
			return false
	return true


## The first 8 characters of an id, for warnings. Never a token.
static func _short(id: String) -> String:
	return id.substr(0, 8)

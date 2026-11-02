class_name Profile
extends RefCounted
## The player's profile: name, color and device token, saved in user://profile.json (card T11).
## Owner: John (game/players). T21 and T17 call exists(), load_or_default() and save().
##
## The device token is the player's identity, so no code path here deletes or overwrites a
## profile file it cannot read. Unreadable files are renamed to <name>.bad-<unix time>.
## A file from a newer game version is never touched. The token is never printed or logged.
## Every function takes an optional path so tests can use a file of their own.

const PATH: String = "user://profile.json"
const VERSION: int = 1
const NAME_MAX: int = 12
const TMP_SUFFIX: String = ".tmp"
const BAK_SUFFIX: String = ".bak"
const BAD_INFIX: String = ".bad-"
const THEME_PATH: String = "res://game/ui/main_theme.tres"
const COLORS: ProfileColors = preload("res://game/players/data/profile_colors.tres")

enum Read { MISSING, OK, BAD, NEWER }


## True when a readable profile is on disk (the .bak counts when profile.json is gone).
static func exists(path: String = PATH) -> bool:
	return _resolve(path)["read"] == Read.OK


## The saved profile as {version, name, color, device_token}, or a default one with an
## empty name and token when there is none.
static func load_or_default(path: String = PATH) -> Dictionary:
	var found: Dictionary = _resolve(path)
	if found["read"] == Read.OK:
		return found["data"]
	var color: String = COLORS.swatches[0].to_html(false).to_upper() if not COLORS.swatches.is_empty() else "FFFFFF"
	return {"version": VERSION, "name": "", "color": "#" + color, "device_token": ""}


## True when the profile file was written by a newer game. It is left alone; save() refuses.
static func newer_version_found(path: String = PATH) -> bool:
	return _resolve(path)["read"] == Read.NEWER


## Saves name and color (data["name"], data["color"]). The token is kept from the profile
## already on disk, or made on the first Save. Answers false when nothing was written.
static func save(data: Dictionary, path: String = PATH) -> bool:
	var existing: Dictionary = _resolve(path)
	if existing["read"] == Read.NEWER:
		push_warning("Profile: the saved profile is from a newer game, not saving")
		return false
	if existing["read"] != Read.OK and FileAccess.file_exists(path):
		push_warning("Profile: could not move an unreadable profile aside, not saving")
		return false
	var player_name: String = str(data.get("name", "")).strip_edges()
	var color: String = str(data.get("color", "")).to_upper()
	if name_problem(player_name) != "" or not _is_color(color):
		return false
	var token: String
	if existing["read"] == Read.OK:
		token = existing["data"]["device_token"]
	else:
		var offered: String = str(data.get("device_token", ""))
		token = offered if _is_token(offered) else _new_token()
	var text: String = JSON.stringify({
		"version": VERSION,
		"name": player_name,
		"color": color,
		"device_token": token,
	}, "\t")
	var tmp: String = path + TMP_SUFFIX
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("Profile: cannot write %s" % tmp)
		return false
	file.store_string(text)
	var wrote: bool = file.get_error() == OK
	file.close()
	if not wrote:
		return false
	if FileAccess.file_exists(path):
		var bak: String = path + BAK_SUFFIX
		if FileAccess.file_exists(bak):
			if _read(bak)["read"] == Read.OK:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
			else:
				_move_aside(bak)
		if not _rename(path, bak):
			return false
	return _rename(tmp, path)


## "" when the name is fine, else the first broken rule in words the player can use.
## Spaces at both ends are trimmed first; save() stores the trimmed name.
static func name_problem(raw: String) -> String:
	var text: String = raw.strip_edges()
	if text == "":
		return "Type a name, 1 to %d characters." % NAME_MAX
	if text.length() > NAME_MAX:
		return "Too long: %d characters, the most is %d." % [text.length(), NAME_MAX]
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if code < 32 or (code >= 127 and code <= 159):
			return "Names can't hold control characters."
		if _is_invisible(code):
			return "Names can't hold invisible or direction marks."
	if text.contains("  "):
		return "Names can't have two spaces in a row."
	var font: Font = _font()
	for i: int in text.length():
		if not font.has_char(text.unicode_at(i)):
			return "The game can't draw \"%s\". Use a different character." % text[i]
	return ""


static func _is_invisible(code: int) -> bool:
	return (code >= 0x200B and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) \
		or (code >= 0x2060 and code <= 0x206F) or code == 0xFEFF


## The font the menus draw with: the theme's default font, else Godot's built-in one.
static func _font() -> Font:
	var theme: Theme = load(THEME_PATH) as Theme
	if theme != null and theme.default_font != null:
		return theme.default_font
	return ThemeDB.fallback_font


static func _is_color(text: String) -> bool:
	return text.length() == 7 and text.begins_with("#") and text.substr(1).is_valid_hex_number(false)


static func _is_token(text: String) -> bool:
	return text.length() == 32 and text == text.to_lower() and text.is_valid_hex_number(false)


static func _new_token() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Finds the profile to use. Moves unreadable files aside on the way. Answers
## {"read": Read.OK, "data": ...}, or {"read": Read.NEWER} or {"read": Read.MISSING}.
static func _resolve(path: String) -> Dictionary:
	var main: Dictionary = _read(path)
	if main["read"] == Read.OK or main["read"] == Read.NEWER:
		return main
	if main["read"] == Read.BAD:
		_move_aside(path)
	var bak_path: String = path + BAK_SUFFIX
	var bak: Dictionary = _read(bak_path)
	if bak["read"] == Read.BAD:
		_move_aside(bak_path)
		return {"read": Read.MISSING}
	return bak


## Looks at one file without changing it.
static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"read": Read.MISSING}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"read": Read.BAD}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {"read": Read.BAD}
	var data: Dictionary = json.data
	var version: Variant = data.get("version")
	if not (version is float or version is int) or float(version) != floorf(float(version)) or float(version) < 1.0:
		return {"read": Read.BAD}
	if float(version) > VERSION:
		return {"read": Read.NEWER}
	for key: String in ["name", "color", "device_token"]:
		if typeof(data.get(key)) != TYPE_STRING:
			return {"read": Read.BAD}
	if not _is_color(str(data["color"]).to_upper()):
		return {"read": Read.BAD}
	return {"read": Read.OK, "data": {
		"version": VERSION,
		"name": str(data["name"]),
		"color": str(data["color"]).to_upper(),
		"device_token": str(data["device_token"]),
	}}


## Renames an unreadable file to <name>.bad-<unix time> so a Save can never overwrite it.
static func _move_aside(path: String) -> void:
	var stamp: int = int(Time.get_unix_time_from_system())
	var target: String = "%s%s%d" % [path, BAD_INFIX, stamp]
	while FileAccess.file_exists(target):
		stamp += 1
		target = "%s%s%d" % [path, BAD_INFIX, stamp]
	if not _rename(path, target):
		push_warning("Profile: could not move %s aside" % path.get_file())


static func _rename(from: String, to: String) -> bool:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to)) == OK

extends SceneTree
## Tests for the second auth message (card T21, part 2): PlayerAuth writes it on the
## client and reads it on the server. Owner: Gabe.
## Run: godot --headless --path . --script res://tests/player_auth_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.

## A token the way T11 makes one: 16 random bytes as lowercase hex.
const TOKEN: String = "0123456789abcdef0123456789abcdef"

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_round_trip()
	_guests()
	_tokens()
	_colors()
	_names()
	_broken_messages()
	_versions_in_logs()
	_names_agree_with_t11()
	_names_from_the_network()
	print("PLAYER AUTH TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _round_trip() -> void:
	var reading := _read({"name": "Gabe", "color": "#3b82f6", "token": TOKEN})
	_expect_true("a player message reads back: name, color in capitals, token (%s)" % _shown(reading),
		reading == {"name": "Gabe", "color": "#3B82F6", "token": TOKEN})
	var from_writer := PlayerAuth.read_message(PlayerAuth.player_message("Gabe", "#3B82F6", TOKEN))
	_expect_true("player_message() makes what read_message() reads", from_writer == {"name": "Gabe", "color": "#3B82F6", "token": TOKEN})
	_expect_true("the name is trimmed, as T11 saves it", _read({"name": "  Gabe  ", "color": "#3B82F6", "token": TOKEN}).get("name") == "Gabe")
	_expect_true("fields it doesn't know are ignored",
		not PlayerAuth.is_guest(_read({"name": "Gabe", "color": "#3B82F6", "token": TOKEN, "score": 9999})))
	_expect_true("a 12-character name passes (T11's most)",
		not PlayerAuth.is_guest(_read({"name": "Abcdefghijkl", "color": "#3B82F6", "token": TOKEN})))


func _guests() -> void:
	_expect_true("guest_message() reads back as a guest with its reason",
		PlayerAuth.read_message(PlayerAuth.guest_message("bot")) == {"guest": "bot"})
	_expect_true("a guest reason is lowercased", _read({"guest": "No Profile"}) == {"guest": "no profile"})
	_expect_true("a reason that could fake a log line becomes \"unknown\"",
		_read({"guest": "bot\n[Combat] hero_damaged: Player 1"}) == {"guest": "unknown"})
	_expect_true("a 41-character reason becomes \"unknown\"", _read({"guest": "a".repeat(41)}) == {"guest": "unknown"})
	_expect_true("a reason that isn't text becomes \"unknown\"", _read({"guest": 12}) == {"guest": "unknown"})
	_expect_true("a guest note wins over a token in the same message",
		PlayerAuth.is_guest(_read({"guest": "bot", "name": "Gabe", "color": "#3B82F6", "token": TOKEN})))


func _tokens() -> void:
	var bad := {
		"31 characters": TOKEN.substr(1),
		"33 characters": TOKEN + "0",
		"capitals": TOKEN.to_upper(),
		"a minus sign in front (T11's _is_token lets it through)": "-" + TOKEN.substr(1),
		"a plus sign in front": "+" + TOKEN.substr(1),
		"0x in front": "0x" + TOKEN.substr(2),
		"a space inside": TOKEN.substr(0, 16) + " " + TOKEN.substr(17),
		"a letter past f": TOKEN.substr(0, 31) + "g",
		"empty": "",
	}
	for case_name: String in bad:
		_expect_true("token with %s: a guest" % case_name,
			_read({"name": "Gabe", "color": "#3B82F6", "token": bad[case_name]}) == {"guest": "bad device token"})
	_expect_true("is_token() takes T11's own format", PlayerAuth.is_token(Crypto.new().generate_random_bytes(16).hex_encode()))


func _colors() -> void:
	for color: String in ["#12345", "123456", "#1234567", "#12345G", "#-12345", "#+12345", "# 12345", ""]:
		_expect_true("color \"%s\": a guest" % color, _read({"name": "Gabe", "color": color, "token": TOKEN}) == {"guest": "bad color"})
	_expect_true("lower and upper case colors pass", PlayerAuth.is_color("#abcdef") and PlayerAuth.is_color("#ABCDEF"))


func _names() -> void:
	var bad := {
		"empty": "",
		"only spaces": "   ",
		"13 characters": "Abcdefghijklm",
		"a tab": "Ga\tbe",
		"a new line": "Ga\nbe",
		"two spaces in a row": "Ga  be",
		"an invisible mark": "Ga" + char(0x200B) + "be",
	}
	for case_name: String in bad:
		_expect_true("name with %s: a guest" % case_name,
			_read({"name": bad[case_name], "color": "#3B82F6", "token": TOKEN}) == {"guest": "name breaks the profile rules"})


func _broken_messages() -> void:
	_expect_true("not JSON: a guest", PlayerAuth.read_message("not json".to_utf8_buffer()) == {"guest": "player message unreadable"})
	_expect_true("a JSON list: a guest", PlayerAuth.read_message("[1, 2]".to_utf8_buffer()) == {"guest": "player message unreadable"})
	_expect_true("an empty message: a guest", PlayerAuth.read_message(PackedByteArray()) == {"guest": "player message unreadable"})
	_expect_true("no token: a guest", _read({"name": "Gabe", "color": "#3B82F6"}) == {"guest": "player message incomplete"})
	_expect_true("a token that is a number: a guest",
		_read({"name": "Gabe", "color": "#3B82F6", "token": 12345}) == {"guest": "player message incomplete"})
	_expect_true("a name that is a list: a guest",
		_read({"name": ["Gabe"], "color": "#3B82F6", "token": TOKEN}) == {"guest": "player message incomplete"})
	var long_message := PackedByteArray()
	long_message.resize(PlayerAuth.MAX_BYTES + 1)
	long_message.fill(32)
	_expect_true("over %d bytes: a guest, not read" % PlayerAuth.MAX_BYTES,
		PlayerAuth.read_message(long_message) == {"guest": "player message too long"})


## The server's name check is T11's without the font: on every name the menus' font can
## draw, the two must agree, so a change to T11's rules shows up here.
func _names_agree_with_t11() -> void:
	var theme := load(Profile.THEME_PATH) as Theme
	var font: Font = theme.default_font if theme != null and theme.default_font != null else ThemeDB.fallback_font
	var names: PackedStringArray = ["Gabe", "Mom", "Zoe", "Zoë", "José", "Abcdefghijkl", "Abcdefghijklm", "  Gabe  ",
		"", "   ", "Ga\tbe", "Ga\nbe", "Ga  be", "G a b e", "Ga" + char(0x200B) + "be", "Ga" + char(0x202E) + "be",
		"Ga" + char(0xFEFF) + "be", "Ga" + char(0x7F) + "be", "Ga" + char(0x85) + "be", "O'Neil", "Anne-Marie", "Gabe 2"]
	var compared := 0
	var disagree: PackedStringArray = []
	for player_name: String in names:
		var drawable := true
		for i: int in player_name.length():
			var code := player_name.unicode_at(i)
			# Only printable characters can be drawn; control and invisible ones are never drawable
			# but both checks refuse them before the font matters.
			if code >= 32 and not (code >= 127 and code <= 159) and not font.has_char(code):
				drawable = false
		if not drawable:
			continue
		compared += 1
		if PlayerAuth.name_ok(player_name) != (Profile.name_problem(player_name) == ""):
			disagree.append(JSON.stringify(player_name))
	_expect_true("the server's name check agrees with T11's on %d names the font can draw (disagree: %s)" % [compared, ", ".join(disagree)],
		disagree.is_empty() and compared >= 18)


## The hero's spawn data carries the player's name (the names seam, for T17). Every peer
## reads it with clean_name(), so a bad one shows as "Player <id>" and never reaches a label.
func _names_from_the_network() -> void:
	_expect_true("clean_name(): a good name comes back as sent", PlayerAuth.clean_name("Gabe") == "Gabe")
	_expect_true("clean_name(): it is trimmed", PlayerAuth.clean_name("  Zoë ") == "Zoë")
	_expect_true("clean_name(): \"\" (a guest) stays \"\"", PlayerAuth.clean_name("") == "")
	var bad := {
		"a number": 42,
		"null": null,
		"a list": ["Gabe"],
		"13 characters": "Abcdefghijklm",
		"a new line": "Ga\nbe",
		"two spaces in a row": "Ga  be",
		"a direction mark": "Ga" + char(0x202E) + "be",
	}
	for case_name: String in bad:
		_expect_true("clean_name() of %s: \"\"" % case_name, PlayerAuth.clean_name(bad[case_name]) == "")


## Net logs the version a peer sends. Only a plain, short one is repeated, so a player
## message sent out of turn never puts its token in a log. Net uses autoloads, so it is
## loaded at run time (see tests/README.md).
func _versions_in_logs() -> void:
	var net: GDScript = load("res://game/core/net.gd")
	_expect_true("a real version is shown as sent", net.call(&"shown_version", "0.0.1+net8") == "0.0.1+net8")
	_expect_true("an empty one is \"?\"", net.call(&"shown_version", "") == "?")
	_expect_true("one over 40 characters is \"?\"", net.call(&"shown_version", "1".repeat(41)) == "?")
	_expect_true("one that could fake a log line is \"?\"", net.call(&"shown_version", "1.0\n[Combat] x") == "?")
	var message := PlayerAuth.player_message("Gabe", "#3B82F6", TOKEN).get_string_from_utf8()
	_expect_true("a player message sent as a version is \"?\", token and all", net.call(&"shown_version", message) == "?")


func _read(message: Dictionary) -> Dictionary:
	return PlayerAuth.read_message(JSON.stringify(message).to_utf8_buffer())


## A reading for a case name, with the token replaced: test output never shows a token.
func _shown(reading: Dictionary) -> String:
	var copy := reading.duplicate()
	if copy.has("token"):
		copy["token"] = "<token>"
	return str(copy)


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

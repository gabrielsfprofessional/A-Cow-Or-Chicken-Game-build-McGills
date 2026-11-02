class_name PlayerAuth
extends RefCounted
## The second auth message: who is joining (card T21, part 2). Owner: Gabe (server).
## Pure functions, so tests/player_auth_test.gd can drive them. Net sends and reads it.
##
## The first auth message is still exactly "<version>+net<N>" both ways. Only after the
## client accepts the server's version does it send this one, a JSON object:
##   {"name": <name>, "color": "#RRGGBB", "token": <device token>}  a player with a profile
##   {"guest": <reason>}                                             a test bot, or no profile
## The server reads it with read_message(): the name by T11's rules (name_ok()), the color
## as #RRGGBB, the token as exactly 32 lowercase hex characters. Anything else makes the
## peer a guest, never a refusal: a family member still plays, just without a save.
## The token never leaves read_message() except to ProfileStore.id_for_token(), and nothing
## here prints it.

## The longest message the server reads. A real one is under 150 bytes.
const MAX_BYTES: int = 1024
## T11's device token: 16 random bytes as lowercase hex (game/players/profile.gd).
const TOKEN_LENGTH: int = 32
## A guest reason is logged, so it's cut to this and to plain characters.
const REASON_MAX: int = 40
const REASON_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789 "
const HEX_LOWER: String = "0123456789abcdef"
const HEX_ANY: String = "0123456789abcdefABCDEF"


## Client: the message for a player with a profile.
static func player_message(player_name: String, color: String, token: String) -> PackedByteArray:
	return JSON.stringify({"name": player_name, "color": color, "token": token}).to_utf8_buffer()


## Client: the message for a guest, with why (it ends up in the server's log).
static func guest_message(reason: String) -> PackedByteArray:
	return JSON.stringify({"guest": reason}).to_utf8_buffer()


## Server: what a peer's message says. Never fails: a player is
## {"name": <trimmed>, "color": "#RRGGBB" in capitals, "token": <32 lowercase hex>},
## anything else is {"guest": <plain reason>}.
static func read_message(data: PackedByteArray) -> Dictionary:
	if data.size() > MAX_BYTES:
		return guest("player message too long")
	var json := JSON.new()
	if json.parse(data.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return guest("player message unreadable")
	var message: Dictionary = json.data
	if message.has("guest"):
		return guest(clean_reason(message["guest"]))
	var player_name: Variant = message.get("name")
	var color: Variant = message.get("color")
	var token: Variant = message.get("token")
	if not player_name is String or not color is String or not token is String:
		return guest("player message incomplete")
	if not is_token(token):
		return guest("bad device token")
	var trimmed: String = (player_name as String).strip_edges()
	if not name_ok(trimmed):
		return guest("name breaks the profile rules")
	if not is_color(color):
		return guest("bad color")
	return {"name": trimmed, "color": (color as String).to_upper(), "token": token}


## A guest reading, with its reason.
static func guest(reason: String) -> Dictionary:
	return {"guest": reason}


## True for a guest reading.
static func is_guest(reading: Dictionary) -> bool:
	return reading.has("guest")


## T11's name rules (Profile.name_problem()) except "the game can't draw it": 1 to
## Profile.NAME_MAX characters after trimming, no control character, no invisible or
## direction mark, no two spaces in a row. A dedicated server export may strip fonts, and
## every client already refuses a name its font can't draw. tests/player_auth_test.gd
## checks that the two agree on every name the font can draw.
static func name_ok(raw: String) -> bool:
	var text: String = raw.strip_edges()
	if text == "" or text.length() > Profile.NAME_MAX or text.contains("  "):
		return false
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if code < 32 or (code >= 127 and code <= 159) or _is_invisible(code):
			return false
	return true


## Exactly 32 lowercase hex characters: no sign, prefix, space or capital.
static func is_token(text: String) -> bool:
	return text.length() == TOKEN_LENGTH and _only_chars(text, HEX_LOWER)


## "#RRGGBB" in either case.
static func is_color(text: String) -> bool:
	return text.length() == 7 and text.begins_with("#") and _only_chars(text.substr(1), HEX_ANY)


## A reason fit for the log: lowercase letters, digits and spaces, at most REASON_MAX
## characters. Anything else from a client becomes "unknown".
static func clean_reason(value: Variant) -> String:
	if not value is String:
		return "unknown"
	var text: String = (value as String).to_lower().strip_edges()
	if text == "" or text.length() > REASON_MAX or not _only_chars(text, REASON_CHARS):
		return "unknown"
	return text


## The same marks as Profile._is_invisible() (T11): zero-width and direction marks.
static func _is_invisible(code: int) -> bool:
	return (code >= 0x200B and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) \
		or (code >= 0x2060 and code <= 0x206F) or code == 0xFEFF


static func _only_chars(text: String, allowed: String) -> bool:
	for i: int in text.length():
		if not allowed.contains(text[i]):
			return false
	return true

class_name PlayerRegistry
extends RefCounted
## Who each connected peer is, on the server (card T21, part 2). Owner: Gabe (server).
## No network code: Net hands it each peer's reading of the second auth message
## (PlayerAuth.read_message()) when the peer connects, and tells it when the peer leaves.
## tests/player_registry_test.gd drives it with a folder of its own.
##
## - A player's save is loaded, or made for a new player, and saved at once with the name
##   and color they joined with and the time. It's saved again when they leave (last seen).
## - Guests get no save: test bots, a client with no profile, a message that breaks the
##   rules, and a token that is already connected (two windows on one PC with one profile).
## - A save that is locked or from another version of the game is left alone, and that
##   player plays as a guest this time.
## - Every answer is one log line for Net to print after "[Server] ". It names a player by
##   the first 8 characters of their id (the SHA-256 of the token), never by the token.
## - add_stats() adds a match's counts to a player's stats and saves them (card T22). The
##   save on leaving writes this same copy, so it keeps them.

var _store: ProfileStore
## Connected players: peer id -> their save, as last saved. Guests are not here.
var _players: Dictionary[int, Dictionary] = {}


func _init(store: ProfileStore) -> void:
	_store = store


## Makes the saves folder. One log line either way.
func open() -> String:
	var err := _store.ensure_folder()
	if err != OK:
		return "could not make the player saves folder %s (error %d): everyone plays as a guest" % [_store.folder, err]
	return "player saves in %s" % _store.folder


## A peer connected; `reading` is PlayerAuth.read_message() of its second auth message.
## Loads or makes its save and saves it. Returns one log line.
func join(peer_id: int, reading: Dictionary, now_unix: int) -> String:
	if PlayerAuth.is_guest(reading):
		return "peer %d: guest (%s)" % [peer_id, reading["guest"]]
	var id: String = ProfileStore.id_for_token(reading["token"])
	for other: int in _players:
		if _players[other]["id"] == id:
			return "peer %d: guest (player %s is already connected as peer %d)" % [peer_id, _short(id), other]
	var found: Dictionary = _store.load_player(id)
	var read: ProfileStore.Read = found["read"]
	var data: Dictionary
	var kind: String
	if read == ProfileStore.Read.OK:
		data = found["data"]
		data["name"] = reading["name"]
		data["color"] = reading["color"]
		data["last_seen_unix"] = now_unix
		kind = "returning"
	elif read == ProfileStore.Read.MISSING:
		data = ProfileStore.new_player(id, reading["name"], reading["color"], now_unix)
		kind = "new"
	elif read == ProfileStore.Read.LOCKED:
		return "peer %d: guest (the save of player %s is locked; try again later)" % [peer_id, _short(id)]
	else:
		return "peer %d: guest (the save of player %s is from another version of the game; left alone)" % [peer_id, _short(id)]
	if not _store.save_player(data):
		return "peer %d: guest (could not save player %s)" % [peer_id, _short(id)]
	_players[peer_id] = data
	return "peer %d: player %s %s (%s)" % [peer_id, _short(id), JSON.stringify(reading["name"]), kind]


## A peer left: saves when it was last seen. "" for a guest.
func leave(peer_id: int, now_unix: int) -> String:
	if not _players.has(peer_id):
		return ""
	var data: Dictionary = _players[peer_id]
	_players.erase(peer_id)
	data["last_seen_unix"] = now_unix
	if not _store.save_player(data):
		return "peer %d: player %s left; could not save when they were last seen" % [peer_id, _short(data["id"])]
	return "peer %d: player %s left, saved" % [peer_id, _short(data["id"])]


## Every connected player leaves (the server is closing). One line per player.
func leave_all(now_unix: int) -> PackedStringArray:
	var lines := PackedStringArray()
	for peer_id: int in _players.keys():
		lines.append(leave(peer_id, now_unix))
	return lines


## The player id of a connected peer, or "" for a guest. For T22's stats.
func player_id(peer_id: int) -> String:
	return _players[peer_id]["id"] if _players.has(peer_id) else ""


## The name a connected player joined with, or "" for a guest. The test world sends it
## to every peer in the hero's spawn data, so names show above heroes (T17).
func player_name(peer_id: int) -> String:
	if not _players.has(peer_id):
		return ""
	var joined_name: Variant = _players[peer_id].get("name")
	return joined_name if joined_name is String else ""


## Adds a match's counts to a connected player's stats and saves them (T22). `delta` has
## the shape of a save's "stats" (MatchStats makes it): every count a whole number, 0 or
## more, and hero file names (small letters, digits and _). Returns one log line for Net
## to print after "[Record] ", or "" for a guest, who gets nothing. A delta that would
## break the save's rules changes nothing. When the disk refuses the save, the counts
## stay in this copy and the save on leaving writes them.
func add_stats(peer_id: int, delta: Dictionary) -> String:
	if not _players.has(peer_id):
		return ""
	var merged: Dictionary = _players[peer_id].duplicate(true)
	var id: String = merged["id"]
	var stats: Dictionary = merged["stats"]
	var parts := PackedStringArray()
	for key: String in ProfileStore.STAT_KEYS:
		var amount: Variant = delta.get(key, 0)
		if not amount is int or (amount as int) < 0:
			return "Player %s: not recorded (%s is not a whole number, 0 or more)" % [_short(id), key]
		stats[key] = int(stats[key]) + (amount as int)
		parts.append("%s +%d" % [key, amount])
	var heroes: Variant = delta.get("heroes", {})
	if not heroes is Dictionary:
		return "Player %s: not recorded (heroes is not a list of heroes)" % _short(id)
	for hero: Variant in (heroes as Dictionary):
		var times: Variant = (heroes as Dictionary)[hero]
		if not hero is String or not is_hero_file(hero) or not times is int or (times as int) < 0:
			return "Player %s: not recorded (a hero's name or count is wrong)" % _short(id)
		stats["heroes"][hero] = int(stats["heroes"].get(hero, 0)) + (times as int)
		parts.append("%s +%d" % [hero, times])
	var problem: String = ProfileStore.problem_in(merged)
	if problem != "":
		return "Player %s: not recorded (%s)" % [_short(id), problem]
	_players[peer_id] = merged
	if not _store.save_player(merged):
		return "Player %s: %s; could not save now, will try again when they leave" % [_short(id), ", ".join(parts)]
	return "Player %s: %s" % [_short(id), ", ".join(parts)]


## How many connected peers are players (not guests).
func player_count() -> int:
	return _players.size()


## True for a hero's file name as a log line can repeat it: small letters, digits and _.
## ProfileStore.problem_in() holds its length. tests/data_test.gd holds the roster to both.
static func is_hero_file(text: String) -> bool:
	const ALLOWED: String = "abcdefghijklmnopqrstuvwxyz0123456789_"
	if text == "":
		return false
	for i: int in text.length():
		if not ALLOWED.contains(text[i]):
			return false
	return true


static func _short(id: String) -> String:
	return id.substr(0, 8)

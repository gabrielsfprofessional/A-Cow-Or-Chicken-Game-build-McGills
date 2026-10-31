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


## How many connected peers are players (not guests).
func player_count() -> int:
	return _players.size()


static func _short(id: String) -> String:
	return id.substr(0, 8)

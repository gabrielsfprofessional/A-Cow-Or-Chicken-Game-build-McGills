class_name ArenaMode
extends Node
## The arena's match (card T15): two teams, auto-balance, score limit, 20-minute cap.
## Owner: Adam (game/modes). ArenaMap adds it as its child "Mode" in online play only,
## so its path is the same on every peer.
##
## The server decides (TeamBook, ArenaMatch) and emits the Events match signals
## (team_assigned, team_score_changed, match_clock_changed, match_ended,
## match_started) on itself, then sends each to every ready peer, whose copy
## emits it there. A late joiner gets the whole state once ready. Tunable numbers:
## data/arena_rules.tres.
## It reaches the Events autoload at run time (EVENTS_PATH), never by name: the
## arena map names this class, and --script tests load the map before autoloads exist.

const EVENTS_PATH: NodePath = ^"/root/Events"
const DATA: ArenaRulesData = preload("res://game/modes/data/arena_rules.tres")
const TEAM_NAMES: Array[String] = ["Blue", "Orange"]
const MODE_NAME: StringName = &"arena"
## The world's node that holds the heroes (game/net/README.md, "Match scene").
const HEROES_NODE: NodePath = ^"Heroes"

## The teams. ArenaMap hands it to ArenaTeamRules, so rules and mode agree.
var book: TeamBook = TeamBook.new()

var _match: ArenaMatch = ArenaMatch.new(DATA.match_length_sec, DATA.score_per_player, DATA.next_match_delay_sec)
var _last_clock: int = -1
## The Events autoload; a plain Node so this script compiles without it.
var _events: Node = null


func _ready() -> void:
	set_process(false)
	_events = get_node_or_null(EVENTS_PATH)
	if _events == null:
		push_error("ArenaMode: no Events autoload, so the arena match can't run.")
		_events = Node.new()  # Emits to no one; freed with this node.
		add_child(_events)
		return
	if not multiplayer.is_server():
		return
	book.score_of = func(team: int) -> int: return _match.scores[team]
	book.team_changed.connect(_on_team_changed)
	_events.connect(&"peer_became_ready", _on_peer_ready)
	_events.connect(&"peer_left", _on_peer_left)
	_events.connect(&"hero_eliminated", _on_hero_eliminated)
	set_process(true)


func _process(delta: float) -> void:
	match _match.tick(delta):
		ArenaMatch.Tick.ENDED:
			_announce_end()
		ArenaMatch.Tick.RESTART:
			_begin(true)
	if _match.phase == ArenaMatch.Phase.PLAYING and _match.clock() != _last_clock:
		_send_clock()


# --- Server ---------------------------------------------------------------

func _on_peer_ready(peer_id: int) -> void:
	book.team_of(peer_id)  # Usually given already, when the server picked its spawn point.
	if _match.phase == ArenaMatch.Phase.WAITING:
		_begin(false)
	_replay_to(peer_id)


func _on_peer_left(peer_id: int) -> void:
	for moved: int in book.peer_left(peer_id):
		_respawn(moved)
	if book.player_count() == 0:
		if _match.phase != ArenaMatch.Phase.WAITING:
			print("[Mode] everyone left, waiting for players")
		_match.stop()
		_last_clock = -1
	elif _match.check_limit(book.player_count()):
		_announce_end()


func _on_team_changed(peer_id: int, team: int) -> void:
	var counts := book.sizes()
	print("[Mode] Player %d plays for %s (Blue %d, Orange %d)" % [peer_id, TEAM_NAMES[team], counts[0], counts[1]])
	_events.emit_signal(&"team_assigned", peer_id, team)
	_send(&"receive_team", [peer_id, team])


## A point for the eliminator's team, when it eliminated an enemy. The eliminator
## may have left already: its last shot still counts for its last team.
func _on_hero_eliminated(victim: int, attacker: int) -> void:
	var team := book.peek(attacker)
	if attacker == victim or team < 0 or team == book.peek(victim):
		return
	if not _match.add_point(team):
		return
	print("[Mode] %s scores (Blue %d, Orange %d; first to %d)" % [TEAM_NAMES[team],
		_match.scores[0], _match.scores[1], _match.score_limit(book.player_count())])
	_events.emit_signal(&"team_score_changed", team, _match.scores[team])
	_send(&"receive_score", [team, _match.scores[team]])
	if _match.check_limit(book.player_count()):
		_announce_end()


## A match starts: the first when the first player is in, the next after the pause
## (forgets the peers that left, then every hero comes back).
func _begin(next: bool) -> void:
	if next:
		book.new_match()
	else:
		_match.start()
	print("[Mode] match started: first to %d, or %d:%02d on the clock" % [
		_match.score_limit(book.player_count()), floori(_match.clock() / 60.0), _match.clock() % 60])
	_events.emit_signal(&"match_started", MODE_NAME)
	_send(&"receive_started", [])
	for team: int in 2:
		_events.emit_signal(&"team_score_changed", team, 0)
		_send(&"receive_score", [team, 0])
	_send_clock()
	if next:
		var world := _world()
		if world != null and world.has_method(&"respawn_all"):
			world.call(&"respawn_all")


func _announce_end() -> void:
	var winner_text := "draw" if _match.winner == ArenaMatch.DRAW else "%s wins" % TEAM_NAMES[_match.winner]
	print("[Mode] match over: %s %d-%d; next match in %s s" % [winner_text, _match.scores[0], _match.scores[1],
		DATA.next_match_delay_sec])
	_events.emit_signal(&"match_ended", _match.winner)
	_send(&"receive_ended", [_match.winner])


func _send_clock() -> void:
	_last_clock = _match.clock()
	_events.emit_signal(&"match_clock_changed", _last_clock)
	_send(&"receive_clock", [_last_clock])


## The current state to a peer that just became ready.
func _replay_to(peer_id: int) -> void:
	receive_started.rpc_id(peer_id)
	var teams := book.playing()
	for other: int in teams:
		receive_team.rpc_id(peer_id, other, teams[other])
	for team: int in 2:
		receive_score.rpc_id(peer_id, team, _match.scores[team])
	receive_clock.rpc_id(peer_id, _match.clock())
	if _match.phase == ArenaMatch.Phase.OVER:
		receive_ended.rpc_id(peer_id, _match.winner)


## A player moved to the other team comes back now on its new side (no elimination).
func _respawn(peer_id: int) -> void:
	var world := _world()
	var heroes := world.get_node_or_null(HEROES_NODE) if world != null else null
	var hero := heroes.get_node_or_null(NodePath(str(peer_id))) if heroes != null else null
	if hero != null and hero.has_method(&"respawn_now"):
		hero.call(&"respawn_now")


## To every ready peer through the world (never a peer whose world isn't loaded).
func _send(method: StringName, args: Array) -> void:
	var world := _world()
	if world != null and world.has_method(&"send_to_ready"):
		world.call(&"send_to_ready", self, method, args)


## The map's parent.
func _world() -> Node:
	var map := get_parent()
	return map.get_parent() if map != null else null


# --- Clients: the server's word, emitted here ------------------------------

@rpc("authority", "call_remote", "reliable")
func receive_started() -> void:
	if not multiplayer.is_server():
		_events.emit_signal(&"match_started", MODE_NAME)


@rpc("authority", "call_remote", "reliable")
func receive_team(peer_id: int, team: int) -> void:
	if multiplayer.is_server() or team < 0 or team > 1:
		return
	_events.emit_signal(&"team_assigned", peer_id, team)


@rpc("authority", "call_remote", "reliable")
func receive_score(team: int, score: int) -> void:
	if multiplayer.is_server() or team < 0 or team > 1:
		return
	_events.emit_signal(&"team_score_changed", team, score)


@rpc("authority", "call_remote", "reliable")
func receive_clock(seconds_left: int) -> void:
	if not multiplayer.is_server():
		_events.emit_signal(&"match_clock_changed", seconds_left)


@rpc("authority", "call_remote", "reliable")
func receive_ended(winning_team: int) -> void:
	if multiplayer.is_server():
		return
	var text := "a draw" if winning_team < 0 else "%s wins" % TEAM_NAMES[clampi(winning_team, 0, 1)]
	print("[Mode] match over: %s" % text)
	_events.emit_signal(&"match_ended", winning_team)

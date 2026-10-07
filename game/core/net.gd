extends Node
## Online play (autoload "Net"). Owner: Gabe. Built in card T06.
## Design (docs/PROJECT_PLAN.md, "Architecture"):
## - A headless dedicated server is peer 1. Clients join over ENet on UDP 7777.
## - Each client moves its own hero; the server decides hits, damage and score.
## - The server address comes from res://server.cfg, which git ignores.
##   T29 adds server.cfg to the export filter so it ships inside the .exe.
##
## Run a server: Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --server
## Join one:     Godot_v4.7.2-stable_win64.exe --path . -- --join=<address>
##
## API and signals for other cards (T10 builds the Join screen on them):
## see game/net/README.md.

## The client finished the handshake and is in the game.
signal joined()
## The client never got in. "reason" is one plain sentence for the player.
signal join_failed(reason: String)
## The client is out of the game. "reason" is "" when the player left on purpose.
signal left(reason: String)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 16
const CONFIG_PATH: String = "res://server.cfg"
## How long a client waits for the server before it gives up.
const JOIN_TIMEOUT: float = 5.0
## How long the server waits before dropping a version-mismatched peer.
const REFUSE_DELAY: float = 1.0
const TEST_WORLD: String = "res://game/net/test_world.tscn"
const MAIN_MENU: String = "res://game/ui/main_menu.tscn"
## Frames the auto-join waits for the world to load before it gives up.
const WORLD_LOAD_FRAMES: int = 600

enum State {
	OFFLINE,     ## No peer. The main menu.
	CONNECTING,  ## A client between join() and the handshake finishing.
	CLIENT,      ## A client in the game.
	SERVER,      ## This process is the dedicated server (peer 1).
}

## Read-only for other cards. T10 uses it to pick what the Join screen shows.
var state: State = State.OFFLINE

var _peer_versions: Dictionary[int, String] = {}
var _server_version: String = ""
var _join_target: String = ""
var _join_started_msec: int = 0
## Bumped on every join and leave so a stale timeout cannot fail a later attempt.
var _join_attempt: int = 0


func _ready() -> void:
	var api := multiplayer as SceneMultiplayer
	if api != null:
		# The version check rides along inside the connect handshake, before the
		# peer counts as connected on either side.
		api.auth_callback = _on_auth
		api.auth_timeout = JOIN_TIMEOUT
		api.peer_authenticating.connect(_on_peer_authenticating)
		api.peer_authentication_failed.connect(_on_peer_authentication_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_autostart()


## Address players join when they click Play. Falls back to this PC.
func server_address() -> String:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		return str(config.get_value("server", "address", "127.0.0.1"))
	return "127.0.0.1"


## The version this build reports in the handshake.
func version() -> String:
	var override := version_override(OS.is_debug_build(), OS.get_cmdline_user_args())
	return override if override != "" else Game.version()


## The version from "-- --version-override=<v>", or "" when it was not passed.
## A release build always gets "": the override is a debug-only testing aid, so
## nobody can talk their way past the version check in a shipped game.
func version_override(debug_build: bool, user_args: PackedStringArray) -> String:
	if not debug_build:
		return ""
	const FLAG: String = "--version-override="
	for arg: String in user_args:
		if arg.begins_with(FLAG):
			return arg.substr(FLAG.length()).strip_edges()
	return ""


## The address from "-- --join=<address>", or "" when the flag was not passed.
## A bare "--join" means: use server_address().
func join_argument() -> String:
	const FLAG: String = "--join="
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--join":
			return server_address()
		if arg.begins_with(FLAG):
			var value := arg.substr(FLAG.length()).strip_edges()
			return value if value != "" else server_address()
	return ""


## Host the game on UDP 7777. The dedicated server calls this itself.
func host() -> Error:
	if state != State.OFFLINE:
		_close_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	if err != OK:
		_log("could not host on UDP %d (error %d). Is a server already running?" % [DEFAULT_PORT, err])
		_alert("Could not host on UDP %d. Is a server already running?" % DEFAULT_PORT)
		return err
	multiplayer.multiplayer_peer = peer
	state = State.SERVER
	_log("server up on UDP %d, version %s, room for %d players" % [DEFAULT_PORT, version(), MAX_PLAYERS])
	_load_world()
	return OK


## Join a server. An empty address means server_address().
## Answers with "joined" or "join_failed(reason)" within JOIN_TIMEOUT seconds.
func join(address: String) -> Error:
	if state != State.OFFLINE:
		_close_peer()
	_join_target = address.strip_edges()
	if _join_target == "":
		_join_target = server_address()
	_server_version = ""
	_join_started_msec = Time.get_ticks_msec()
	_join_attempt += 1
	state = State.CONNECTING
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_join_target, DEFAULT_PORT)
	if err != OK:
		_fail_join("Could not use the address %s (error %d). Check it and try again." % [_join_target, err])
		return err
	multiplayer.multiplayer_peer = peer
	_log("joining %s:%d as version %s" % [_join_target, DEFAULT_PORT, version()])
	_watch_join_timeout(_join_attempt)
	return OK


## Hang up. Quiet on purpose: it emits left("") and leaves the scene alone, so
## whoever called it decides where to go next.
func leave() -> void:
	if state == State.OFFLINE:
		return
	_close_peer()
	_log("left")
	left.emit("")


func _autostart() -> void:
	# Let the main scene finish loading before swapping it out.
	await get_tree().process_frame
	if Game.is_server():
		host()
		return
	var address := join_argument()
	if address == "":
		return  # A normal launch: stay on the main menu.
	# The world has to exist before the handshake, so the server's spawns have
	# somewhere to land and hello only goes out once we can draw heroes.
	if not await _load_world():
		return
	join(address)


func _load_world() -> bool:
	var err := get_tree().change_scene_to_file(TEST_WORLD)
	if err != OK:
		_log("could not load %s (error %d)" % [TEST_WORLD, err])
		_alert("Could not load the test world (error %d)." % err)
		return false
	var waited := 0
	while waited < WORLD_LOAD_FRAMES:
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == TEST_WORLD:
			return true
		await get_tree().process_frame
		waited += 1
	_log("the test world did not load within %d frames" % WORLD_LOAD_FRAMES)
	_alert("The test world did not load. Tell Gabe.")
	return false


func _watch_join_timeout(attempt: int) -> void:
	await get_tree().create_timer(JOIN_TIMEOUT).timeout
	if state != State.CONNECTING or attempt != _join_attempt:
		return
	_fail_join("Could not reach the server at %s on UDP %d within %d seconds. Is the server running?" % [
		_join_target, DEFAULT_PORT, int(JOIN_TIMEOUT),
	])


# --- handshake ---------------------------------------------------------------
#
# House rule for everything below: the auth callback and the multiplayer signals
# all arrive from inside the peer's own poll, so nothing down here closes the
# peer, changes the scene or opens an alert on the spot. It hands that to
# call_deferred and lets the poll finish first. Doing it on the spot frees the
# peer while the engine is still walking it, which crashes Godot (signal 11).

func _on_peer_authenticating(id: int) -> void:
	var api := multiplayer as SceneMultiplayer
	if api == null:
		return
	# Both sides send their version, so either side can name both in a message.
	api.send_auth(id, version().to_utf8_buffer())


func _on_auth(id: int, data: PackedByteArray) -> void:
	var api := multiplayer as SceneMultiplayer
	if api == null:
		return
	var peer_version := data.get_string_from_utf8().strip_edges()
	var mine := version()
	if multiplayer.is_server():
		_peer_versions[id] = peer_version
		if peer_version != mine:
			_log("refused peer %d: version mismatch (server %s, peer %s)" % [id, mine, peer_version])
			_peer_versions.erase(id)
			# Disconnecting now would clear the outgoing queue and drop the
			# version we just sent, so the client could not name it.
			_refuse_later(id)
			return
		api.complete_auth(id)
		return
	# On a client the only peer that authenticates is the server, peer 1.
	if state != State.CONNECTING:
		return
	_server_version = peer_version
	if peer_version != mine:
		_fail_join.call_deferred(_mismatch_reason(peer_version, mine))
		return
	api.complete_auth(id)


## Disconnects a refused peer after REFUSE_DELAY, if it hasn't already left.
func _refuse_later(id: int) -> void:
	await get_tree().create_timer(REFUSE_DELAY).timeout
	var api := multiplayer as SceneMultiplayer
	if api != null and id in api.get_authenticating_peers():
		api.disconnect_peer(id)


func _on_peer_authentication_failed(id: int) -> void:
	if multiplayer.is_server():
		_log("peer %d failed the version handshake" % id)
		_peer_versions.erase(id)
		return
	if state != State.CONNECTING:
		return
	if _server_version != "" and _server_version != version():
		_fail_join.call_deferred(_mismatch_reason(_server_version, version()))
		return
	_fail_join.call_deferred("The server refused the connection. It may be full, or running a different version.")


func _mismatch_reason(server_version: String, my_version: String) -> String:
	return "Update the game from the Drive folder (server v%s, you v%s)" % [server_version, my_version]


# --- connection signals ------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	_log("join: peer %d version %s (%d connected)" % [
		id, _peer_versions.get(id, "unknown"), multiplayer.get_peers().size(),
	])


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# The leaving peer is already out of get_peers() by the time this fires.
	_log("leave: peer %d version %s (%d connected)" % [
		id, _peer_versions.get(id, "unknown"), multiplayer.get_peers().size(),
	])
	_peer_versions.erase(id)


func _on_connected_to_server() -> void:
	if state != State.CONNECTING:
		return  # Already given up on this attempt. Do not resurrect it.
	state = State.CLIENT
	_log("connected as peer %d after %s (server version %s)" % [
		multiplayer.get_unique_id(), _since_join(), _server_version,
	])
	joined.emit()


func _on_connection_failed() -> void:
	_fail_join.call_deferred("Could not reach the server at %s on UDP %d. Is the server running?" % [
		_join_target, DEFAULT_PORT,
	])


func _on_server_disconnected() -> void:
	if state == State.CONNECTING:
		_fail_join.call_deferred("The server closed the connection before the game started.")
		return
	if state != State.CLIENT:
		return
	_lose_server.call_deferred()


func _lose_server() -> void:
	if state != State.CLIENT:
		return
	_close_peer()
	var reason := "Lost connection to the server. It may have been closed."
	_log(reason)
	left.emit(reason)
	_return_to_menu(reason)


# --- plumbing ----------------------------------------------------------------

func _fail_join(reason: String) -> void:
	if state != State.CONNECTING and state != State.CLIENT:
		return
	_close_peer()
	_log("join failed after %s: %s" % [_since_join(), reason])
	join_failed.emit(reason)
	_return_to_menu(reason)


func _close_peer() -> void:
	state = State.OFFLINE
	_join_attempt += 1
	_peer_versions.clear()
	var peer := multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = null


## Say why, then put the player back where they can try again.
## T10 replaces the alert with the Join screen's own message.
func _return_to_menu(reason: String) -> void:
	if Game.is_server():
		return
	_alert(reason)
	var current := get_tree().current_scene
	if current == null or current.scene_file_path != MAIN_MENU:
		get_tree().change_scene_to_file.call_deferred(MAIN_MENU)
		_log_menu_arrival()


## Logs once the menu is really up, not just asked for.
func _log_menu_arrival() -> void:
	var waited := 0
	while waited < WORLD_LOAD_FRAMES:
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == MAIN_MENU:
			_log("back to the main menu")
			return
		await get_tree().process_frame
		waited += 1
	_log("could not get back to the main menu")


func _alert(message: String) -> void:
	# A headless run has no window to put a box in, and the log already says it.
	if DisplayServer.get_name() == "headless":
		return
	OS.alert(message, "A Cow or Chicken")


func _since_join() -> String:
	return "%.1f s" % ((Time.get_ticks_msec() - _join_started_msec) / 1000.0)


func _log(message: String) -> void:
	print("[Net] ", message)

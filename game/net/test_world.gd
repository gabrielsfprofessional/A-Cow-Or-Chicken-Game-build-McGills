extends Node2D
## Proving ground for cards T06-T09, T13, T14, T18: one hero per connected player, walls to
## bump into and shoot at, room for test bots. Owner: Gabe (game/net). T16
## replaces it with the real arena.
##
## The server spawns a hero for a client only after that client says its world
## is loaded, so nobody gets a hero they cannot draw yet. Movement and combat
## live in game/heroes/net_hero.gd; shots in game/weapons.

const HERO_SCENE: PackedScene = preload("res://game/heroes/net_hero.tscn")
## The heroes, in hero-select order. Until T16's hero select, "--hero=<file name>"
## picks one (T18); the default is the first. Net.chosen_hero_index overrides both.
const ROSTER: HeroRoster = preload("res://game/heroes/data/roster.tres")
## How often the status lines refresh, in seconds.
const STATUS_INTERVAL: float = 0.5
## The floor inside the 32 px border walls, kept 32 px clear of them (T09).
const BOT_AREA: Rect2 = Rect2(64.0, 64.0, 1792.0, 952.0)
## The maps a server can run, by name (T39). Adam edits the list.
const MAP_LIST: MapList = preload("res://game/maps/data/maps.tres")
## "-- --map=<name>" on the server. A server setting, not a debug aid: release builds read it too.
const MAP_FLAG: String = "--map="
## A map without bot_area(): its floor inside the outer wall (one 48 px cell), kept 32 px clear.
const MAP_WALL_PX: float = 48.0
const BOT_WALL_CLEARANCE_PX: float = 32.0

## Server only: peers that said client_ready, so relays never reach a peer
## whose world is not loaded yet.
var _ready_peers: ReadyPeers = ReadyPeers.new()
var _status_wait: float = 0.0
## Server: who hits whom, respawns and protection. A mode replaces it (set_rules).
var _rules: MatchRules = MatchRules.new()
## Every peer: teams heard from Events.team_assigned since this world loaded, so a
## bot whose hero spawns after the replay still knows them (teams_seen()).
var _teams_seen: Dictionary[int, int] = {}
## The map this world runs (T39): "test" for none. The server picks it; clients hear it in load_map.
var _map_name: String = MapList.TEST
var _map: Node2D = null

@onready var _heroes: Node2D = $Heroes
@onready var _shots: Shots = $Shots
@onready var _spawner: MultiplayerSpawner = $HeroSpawner
@onready var _status: Label = $Hud/Status
@onready var _remotes: Label = $Hud/Remotes


func _ready() -> void:
	# Every peer builds heroes the same way, so the spawner only has to send
	# the peer id and hero index across.
	_spawner.spawn_function = _make_hero
	_heroes.child_entered_tree.connect(_on_heroes_changed)
	_heroes.child_entered_tree.connect(_on_hero_entered)
	_heroes.child_exiting_tree.connect(_on_heroes_changed)
	Events.hero_damaged.connect(_on_hero_damaged)
	Events.hero_eliminated.connect(_on_hero_eliminated)
	Events.hero_respawned.connect(_on_hero_respawned)
	Events.ability_used.connect(_on_ability_used)
	Events.hero_knocked_back.connect(_on_hero_knocked_back)
	Events.hero_healed.connect(_on_hero_healed)
	Events.team_assigned.connect(_on_team_assigned)
	if Net.state == Net.State.SERVER:
		multiplayer.peer_connected.connect(_send_map)
		multiplayer.peer_disconnected.connect(_remove_hero)
		_build_map(_server_map_name())
		var stats := ServerStats.new()
		stats.name = "ServerStats"
		add_child(stats)
	# A client: Net loads this world before it joins, and hello waits for the
	# server's load_map, so the map is built before this player's own hero spawns
	# (T39). Other players' heroes can arrive a few packets earlier (the spawner
	# replays them on connect), so nothing may assume the map exists when a hero enters.
	_refresh_status()


func _process(delta: float) -> void:
	_status_wait -= delta
	if _status_wait > 0.0:
		return
	_status_wait = STATUS_INTERVAL
	_refresh_status()
	_refresh_remotes()


## Server only: true once the peer has said client_ready.
func is_peer_ready(peer_id: int) -> bool:
	return _ready_peers.has(peer_id)


## Server: node.rpc_id(peer, method, ...args) to every ready peer (T39), so a relay
## never reaches a peer whose world is not loaded. Modes send their events with it.
func send_to_ready(node: Node, method: StringName, args: Array = []) -> void:
	for peer_id: int in _ready_peers.recipients(multiplayer.get_peers()):
		node.callv(&"rpc_id", [peer_id, method] + args)


## The world's shots: the server's simulation and every client's drawing.
func shots() -> Shots:
	return _shots


## Server: the match rules heroes, shots and bots follow (week-3 seams).
func rules() -> MatchRules:
	return _rules


## Every peer: peer id -> team from every team_assigned heard so far. Empty: no teams.
## A copy: teams change through team_assigned, not here. The server drops a peer
## that leaves; clients keep it (harmless: it has no hero to target).
func teams_seen() -> Dictionary[int, int]:
	return _teams_seen.duplicate()


func _on_team_assigned(peer_id: int, team: int) -> void:
	_teams_seen[peer_id] = team


## Server: a mode (T15) installs its rules here, before heroes spawn. Null puts
## the defaults back: MapRules on a map (T39; a mode there extends MapRules), else MatchRules.
func set_rules(new_rules: MatchRules) -> void:
	if new_rules != null:
		_rules = new_rules
	elif _map != null and _map.has_method(&"make_rules"):
		_rules = _map.call(&"make_rules") as MatchRules
	elif _map != null:
		_rules = MapRules.from_map(_map)
	else:
		_rules = MatchRules.new()


## Server: where a hero spawns and respawns (the rules decide; the T06 ring by
## default). Clients get the first spot in the spawn data, later ones with the respawn.
func respawn_point(peer_id: int) -> Vector2:
	return _rules.respawn_point(peer_id)


## Where test bots wander (T09): BotBrain walks to random points in it. Points
## inside the inner walls are fine; a bot that can't reach one picks another.
## On a map (T39): its bot_area() if it has one, else its floor inside the outer wall.
func bot_area() -> Rect2:
	if _map == null:
		return BOT_AREA
	if _map.has_method(&"bot_area"):
		return _map.call(&"bot_area")
	var inset := MAP_WALL_PX + BOT_WALL_CLEARANCE_PX
	var size: Vector2 = _map.get(&"map_size")
	return Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)


## The map this world runs: "test" for none (T39).
func map_name() -> String:
	return _map_name


## Server -> one peer, the moment it connects (late joiners too): the map to build
## before saying hello. Nobody types the map on a client (T39).
@rpc("authority", "call_remote", "reliable")
func load_map(new_map_name: String) -> void:
	if multiplayer.is_server():
		return
	if _map_name != MapList.TEST or _map != null:
		return  # Already built. One map per server run until T16's lobby.
	if new_map_name != MapList.TEST and MAP_LIST.scene_path(new_map_name) == "":
		_map_failed.call_deferred("Could not load the map %s. Update the game from the Drive folder." % new_map_name)
		return
	if not _build_map(new_map_name):
		_map_failed.call_deferred("Could not load the map %s. Tell Gabe." % new_map_name)
		return
	_say_hello()


func _send_map(peer_id: int) -> void:
	load_map.rpc_id(peer_id, _map_name)


## The server's "--map=<name>", or "test". Read in every build: it is a server
## setting, so T29's release server needs it too.
func _server_map_name() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(MAP_FLAG):
			var wanted := arg.substr(MAP_FLAG.length()).strip_edges().to_lower()
			if wanted == "" or wanted == MapList.TEST:
				return MapList.TEST
			if MAP_LIST.scene_path(wanted) == "":
				print("[TestWorld] no map named %s in maps.tres, so using the test world" % wanted)
				return MapList.TEST
			return wanted
	return MapList.TEST


## Builds the map as the world's first child, behind everything, and takes the
## test world's own floor and walls out. "test" builds nothing. False on a failure.
func _build_map(new_map_name: String) -> bool:
	if new_map_name == MapList.TEST:
		return true
	var scene := load(MAP_LIST.scene_path(new_map_name)) as PackedScene
	var map := scene.instantiate() as Node2D if scene != null else null
	if map == null:
		print("[TestWorld] could not build the map %s" % new_map_name)
		return false
	for old: String in ["Background", "Walls"]:
		var node := get_node_or_null(old)
		if node != null:
			remove_child(node)
			node.queue_free()
	# Offline-only cameras (Adam's FlyCamera) go before the map enters the tree:
	# online, the own hero's camera is the only one.
	var cameras := map.find_children("*", "Camera2D", true, false)
	for camera: Node in cameras:
		camera.get_parent().remove_child(camera)
		camera.free()
	map.name = "Map"
	add_child(map)
	move_child(map, 0)
	_map = map
	_map_name = new_map_name
	print("[TestWorld] map %s built (%d offline-only cameras removed)" % [new_map_name, cameras.size()])
	if Net.state == Net.State.SERVER:
		set_rules(null)  # The map's make_rules() if it has one, else MapRules from its spawns.
	return true


## " at SpawnA2 (x, y)" on a map, naming the Spawn marker at that spot (or "a
## spot off the markers"); "" on the test world, so its log lines stay as they were.
func _spot_text(spot: Vector2) -> String:
	if _map == null:
		return ""
	var spot_name := "a spot off the markers"
	var spawns := _map.get_node_or_null(MapList.SPAWNS_NODE)
	if spawns != null:
		for child: Node in spawns.get_children():
			if child is Marker2D and (child as Marker2D).global_position.is_equal_approx(spot):
				spot_name = String(child.name)
				break
	return " at %s (%.0f, %.0f)" % [spot_name, spot.x, spot.y]


## A client on a map: its own hero gets the camera, kept inside the map (T39).
## The test world has none, so its view stays as it was.
func _on_hero_entered(node: Node) -> void:
	var hero := node as NetHero
	if _map == null or hero == null or not hero.is_owned():
		return
	var size: Vector2 = _map.get(&"map_size")
	var camera := Camera2D.new()
	camera.name = "OwnCamera"
	# Physics interpolation is on, so the camera moves with the physics ticks.
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)
	hero.add_child.call_deferred(camera)
	camera.make_current.call_deferred()


## A client that can't build the server's map leaves, saying why. Deferred: an RPC
## arrives inside the peer's poll, where closing the peer crashes Godot (see net.gd).
func _map_failed(reason: String) -> void:
	print("[TestWorld] %s" % reason)
	Net.drop_out(reason)


## A client telling the server its world is ready and which roster hero it
## plays (T18; T16's hero select sends the same index). The server answers with
## a hero, then each hero's combat state (the spawner only knows spawn data).
@rpc("any_peer", "call_remote", "reliable")
func client_ready(hero_index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_ready_peers.add(peer_id)
	if _heroes.has_node(NodePath(str(peer_id))):
		return  # Already has a hero. A repeated hello changes nothing.
	if ROSTER.at(hero_index) == null:
		print("[TestWorld] peer %d asked for hero %d; there is none, so it plays %s" % [
			peer_id, hero_index, ROSTER.first().display_name])
		hero_index = 0
	var spot := respawn_point(peer_id)
	_spawner.spawn([peer_id, hero_index, spot])
	print("[TestWorld] hero spawned for peer %d%s" % [peer_id, _spot_text(spot)])
	for child: Node in _heroes.get_children():
		var hero := child as NetHero
		if hero != null:
			hero.send_combat_state(peer_id)
	Events.peer_became_ready.emit(peer_id)


func _say_hello() -> void:
	print("[TestWorld] world ready, saying hello as peer %d" % multiplayer.get_unique_id())
	client_ready.rpc_id(1, _chosen_hero())


## Net.chosen_hero_index when T16's hero select set it (any build), else the roster
## slot named by "--hero=<file name>" (debug builds), else 0. An unknown name
## plays the first hero and says so.
func _chosen_hero() -> int:
	if Net.chosen_hero_index >= 0:
		return Net.chosen_hero_index
	var wanted := Net.debug_flag(OS.is_debug_build(), OS.get_cmdline_user_args(), "--hero=")
	if wanted == "":
		return 0
	var index := ROSTER.index_of(wanted.to_lower())
	if index < 0:
		print("[TestWorld] no hero named %s in the roster, so playing %s" % [wanted, ROSTER.first().display_name])
		return 0
	return index


func _remove_hero(peer_id: int) -> void:
	_ready_peers.remove(peer_id)
	Events.peer_left.emit(peer_id)
	_teams_seen.erase(peer_id)
	var hero := _heroes.get_node_or_null(NodePath(str(peer_id)))
	if hero == null:
		return
	hero.queue_free()  # The spawner takes the hero off every client too.
	print("[TestWorld] hero removed for peer %d" % peer_id)


## Runs on every peer, server included, through the spawner. The spawn data is
## [peer_id, hero_index, spawn_position] (T18, week-3 seams); every peer picks the
## same HeroData from the same roster, so a late joiner gets each hero right too.
## The server decides the spot (its MatchRules); without one, the T06 ring.
## A late joiner gets the first spot, then the hero's current position with its relays.
func _make_hero(data: Variant) -> Node:
	var spawn: Array = data
	var peer_id := int(spawn[0])
	var hero_data := ROSTER.at(int(spawn[1]))
	if hero_data == null:
		hero_data = ROSTER.first()
	var spot := MatchRules.new().respawn_point(peer_id)
	if spawn.size() > 2 and spawn[2] is Vector2:
		spot = spawn[2]
	var hero := HERO_SCENE.instantiate() as NetHero
	# The owning client drives this hero; setup() makes it the authority.
	hero.setup(peer_id, spot, _hero_color(peer_id), hero_data)
	return hero


func _hero_color(peer_id: int) -> Color:
	return Color.from_hsv(fposmod(float(peer_id) * MatchRules.RING_STEP, 1.0), 0.55, 0.95)


func _on_heroes_changed(_hero: Node) -> void:
	# child_exiting_tree fires before the child is gone, so count next frame.
	_log_hero_count.call_deferred()


func _log_hero_count() -> void:
	_refresh_status()
	print("[TestWorld] heroes in the world: %d" % _heroes.get_child_count())


func _on_hero_damaged(victim: int, attacker: int, amount: int, at: Vector2) -> void:
	print("[Combat] hero_damaged: Player %d hit by Player %d for %d at (%.0f, %.0f)" % [victim, attacker, amount, at.x, at.y])


func _on_hero_eliminated(victim: int, attacker: int) -> void:
	print("[Combat] hero_eliminated: Player %d by Player %d" % [victim, attacker])


func _on_hero_respawned(peer_id: int, at: Vector2) -> void:
	print("[Combat] hero_respawned: Player %d at (%.0f, %.0f)" % [peer_id, at.x, at.y])


func _on_ability_used(peer_id: int, ready_in_sec: float) -> void:
	var hero := _heroes.get_node_or_null(NodePath(str(peer_id))) as NetHero
	var ability := hero.hero_data.ability.display_name if hero != null else "?"
	print("[Combat] ability_used: Player %d used %s, ready again in %.1f s" % [peer_id, ability, ready_in_sec])


func _on_hero_knocked_back(victim: int, attacker: int) -> void:
	print("[Combat] knocked_back: Player %d by Player %d" % [victim, attacker])


func _on_hero_healed(peer_id: int, healer: int, amount: int) -> void:
	if amount > 0:
		print("[Combat] hero_healed: Player %d by Player %d for %d" % [peer_id, healer, amount])


func _refresh_status() -> void:
	var parts: PackedStringArray = [
		"Test world (card T08)", "version %s" % Net.version(), _role_text(),
		"%d in the world" % _heroes.get_child_count(),
	]
	if _map != null:
		parts.insert(1, "map %s" % _map_name)
	var flags := Net.debug_flags_text()
	if Weapon.fire_cheat() != 1.0:
		flags = (flags + " " if flags != "" else "") + "fire-cheat=%s" % Weapon.fire_cheat()
	if flags != "":
		parts.append(flags)
	var own := _own_hero()
	if own != null and not own.is_alive():
		parts.append("Eliminated, back in %d s" % ceili(own.respawn_in_sec()))
	if own != null and own.has_ability():
		var ready_in := own.ability_ready_in_sec()
		if ready_in > 0.0:
			parts.append("Q %.1f s" % ready_in)
		elif own.hero_data.ability.charges > 1:
			parts.append("Q x%d" % own.ability_charges_left())  # T18
		else:
			parts.append("Q ready")
	_status.text = "  |  ".join(parts)


func _own_hero() -> NetHero:
	if Net.state != Net.State.CLIENT:
		return null
	return _heroes.get_node_or_null(NodePath(str(multiplayer.get_unique_id()))) as NetHero


## Each remote hero's buffer depth and underrun count. "Smooth" = ur stays 0.
func _refresh_remotes() -> void:
	var parts: PackedStringArray = []
	for child: Node in _heroes.get_children():
		var hero := child as NetHero
		if hero == null or hero.is_owned() or Net.state != Net.State.CLIENT:
			continue
		parts.append("P%d buf %d ms ur %d" % [hero.owner_peer, hero.buffer_depth_msec(), hero.underruns()])
	_remotes.text = "  |  ".join(parts)


func _role_text() -> String:
	match Net.state:
		Net.State.SERVER:
			return "server"
		Net.State.CLIENT:
			return "peer %d" % multiplayer.get_unique_id()
		Net.State.CONNECTING:
			return "connecting"
		_:
			return "offline"

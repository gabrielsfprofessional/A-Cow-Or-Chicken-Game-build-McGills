extends Node2D
## Proving ground for cards T06-T09, T13, T14: one hero per connected player, walls to
## bump into and shoot at, room for test bots. Owner: Gabe (game/net). T16
## replaces it with the real arena.
##
## The server spawns a hero for a client only after that client says its world
## is loaded, so nobody gets a hero they cannot draw yet. Movement and combat
## live in game/heroes/net_hero.gd; shots in game/weapons.

const HERO_SCENE: PackedScene = preload("res://game/heroes/net_hero.tscn")
## Everyone plays the roster's first hero until T16's hero select (T13).
const ROSTER: HeroRoster = preload("res://game/heroes/data/roster.tres")
const RING_RADIUS: float = 260.0
## Middle of the 1920x1080 viewport. This world has no camera.
const WORLD_CENTER: Vector2 = Vector2(960.0, 540.0)
## Golden-ratio step, so nearby peer ids land far apart on the ring.
const RING_STEP: float = 0.618034
## How often the status lines refresh, in seconds.
const STATUS_INTERVAL: float = 0.5
## The floor inside the 32 px border walls, kept 32 px clear of them (T09).
const BOT_AREA: Rect2 = Rect2(64.0, 64.0, 1792.0, 952.0)

## Server only: peers that said client_ready, so relays never reach a peer
## whose world is not loaded yet.
var _ready_peers: Dictionary[int, bool] = {}
var _status_wait: float = 0.0

@onready var _heroes: Node2D = $Heroes
@onready var _shots: Shots = $Shots
@onready var _spawner: MultiplayerSpawner = $HeroSpawner
@onready var _status: Label = $Hud/Status
@onready var _remotes: Label = $Hud/Remotes


func _ready() -> void:
	# Every peer builds heroes the same way, so the spawner only has to send
	# the peer id across.
	_spawner.spawn_function = _make_hero
	_heroes.child_entered_tree.connect(_on_heroes_changed)
	_heroes.child_exiting_tree.connect(_on_heroes_changed)
	Events.hero_damaged.connect(_on_hero_damaged)
	Events.hero_eliminated.connect(_on_hero_eliminated)
	Events.hero_respawned.connect(_on_hero_respawned)
	Events.ability_used.connect(_on_ability_used)
	Events.hero_knocked_back.connect(_on_hero_knocked_back)
	if Net.state == Net.State.SERVER:
		multiplayer.peer_disconnected.connect(_remove_hero)
		var stats := ServerStats.new()
		stats.name = "ServerStats"
		add_child(stats)
	else:
		# Net loads this world before it joins, so the usual path is: connect,
		# then hello. The state check covers a caller that joins first.
		Net.joined.connect(_say_hello)
		if Net.state == Net.State.CLIENT:
			_say_hello()
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


## The world's shots: the server's simulation and every client's drawing.
func shots() -> Shots:
	return _shots


## Where a hero spawns and respawns. Same spot on every peer: the peer id alone
## decides it (the T06 ring). T12 replaces it with team spawns.
func respawn_point(peer_id: int) -> Vector2:
	var angle := fposmod(float(peer_id) * RING_STEP, 1.0) * TAU
	return WORLD_CENTER + Vector2(cos(angle), sin(angle)) * RING_RADIUS


## Where test bots wander (T09): BotBrain walks to random points in it. Points
## inside the inner walls are fine; a bot that can't reach one picks another.
## T16's arena needs one too.
func bot_area() -> Rect2:
	return BOT_AREA


## A client telling the server its world is ready. The server answers with a
## hero, then each hero's combat state (the spawner only knows spawn data).
@rpc("any_peer", "call_remote", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_ready_peers[peer_id] = true
	if _heroes.has_node(NodePath(str(peer_id))):
		return  # Already has a hero. A repeated hello changes nothing.
	_spawner.spawn(peer_id)
	print("[TestWorld] hero spawned for peer %d" % peer_id)
	for child: Node in _heroes.get_children():
		var hero := child as NetHero
		if hero != null:
			hero.send_combat_state(peer_id)


func _say_hello() -> void:
	print("[TestWorld] world ready, saying hello as peer %d" % multiplayer.get_unique_id())
	client_ready.rpc_id(1)


func _remove_hero(peer_id: int) -> void:
	_ready_peers.erase(peer_id)
	var hero := _heroes.get_node_or_null(NodePath(str(peer_id)))
	if hero == null:
		return
	hero.queue_free()  # The spawner takes the hero off every client too.
	print("[TestWorld] hero removed for peer %d" % peer_id)


## Runs on every peer, server included, through the spawner. The spawn data is
## the peer id alone; every peer picks the same HeroData from the same roster.
func _make_hero(data: Variant) -> Node:
	var peer_id := int(data)
	var hero := HERO_SCENE.instantiate() as NetHero
	# The owning client drives this hero; setup() makes it the authority.
	hero.setup(peer_id, respawn_point(peer_id), _hero_color(peer_id), ROSTER.first())
	return hero


func _hero_color(peer_id: int) -> Color:
	return Color.from_hsv(fposmod(float(peer_id) * RING_STEP, 1.0), 0.55, 0.95)


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
	print("[Combat] ability_used: Player %d, ready again in %.1f s" % [peer_id, ready_in_sec])


func _on_hero_knocked_back(victim: int, attacker: int) -> void:
	print("[Combat] knocked_back: Player %d by Player %d" % [victim, attacker])


func _refresh_status() -> void:
	var parts: PackedStringArray = [
		"Test world (card T08)", "version %s" % Net.version(), _role_text(),
		"%d in the world" % _heroes.get_child_count(),
	]
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
		parts.append("Q ready" if ready_in <= 0.0 else "Q %.1f s" % ready_in)
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

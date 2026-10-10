extends Node2D
## Proving ground for cards T06 and T07: one hero per connected player, walls to
## bump into. Owner: Gabe (game/net). T16 replaces it with the real arena.
##
## The server spawns a hero for a client only after that client says its world
## is loaded, so nobody gets a hero they cannot draw yet. Movement lives in
## net_hero.gd (T07).

const HERO_SCENE: PackedScene = preload("res://game/net/net_hero.tscn")
const RING_RADIUS: float = 260.0
## Middle of the 1920x1080 viewport. This world has no camera.
const WORLD_CENTER: Vector2 = Vector2(960.0, 540.0)
## Golden-ratio step, so nearby peer ids land far apart on the ring.
const RING_STEP: float = 0.618034
## How often the status lines refresh, in seconds.
const STATUS_INTERVAL: float = 0.5

## Server only: peers that said client_ready, so relays never reach a peer
## whose world is not loaded yet.
var _ready_peers: Dictionary[int, bool] = {}
var _status_wait: float = 0.0

@onready var _heroes: Node2D = $Heroes
@onready var _spawner: MultiplayerSpawner = $HeroSpawner
@onready var _status: Label = $Hud/Status
@onready var _remotes: Label = $Hud/Remotes


func _ready() -> void:
	# Every peer builds heroes the same way, so the spawner only has to send
	# the peer id across.
	_spawner.spawn_function = _make_hero
	_heroes.child_entered_tree.connect(_on_heroes_changed)
	_heroes.child_exiting_tree.connect(_on_heroes_changed)
	if Net.state == Net.State.SERVER:
		multiplayer.peer_disconnected.connect(_remove_hero)
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
	_refresh_remotes()


## Server only: true once the peer has said client_ready.
func is_peer_ready(peer_id: int) -> bool:
	return _ready_peers.has(peer_id)


## A client telling the server its world is ready. The server answers with a hero.
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


## Runs on every peer, server included, through the spawner.
func _make_hero(data: Variant) -> Node:
	var peer_id := int(data)
	var hero := HERO_SCENE.instantiate() as NetHero
	# The owning client drives this hero; setup() makes it the authority.
	hero.setup(peer_id, _spawn_point(peer_id), _hero_color(peer_id))
	return hero


## Same spot on every peer: the peer id alone decides it.
func _spawn_point(peer_id: int) -> Vector2:
	var angle := fposmod(float(peer_id) * RING_STEP, 1.0) * TAU
	return WORLD_CENTER + Vector2(cos(angle), sin(angle)) * RING_RADIUS


func _hero_color(peer_id: int) -> Color:
	return Color.from_hsv(fposmod(float(peer_id) * RING_STEP, 1.0), 0.55, 0.95)


func _on_heroes_changed(_hero: Node) -> void:
	# child_exiting_tree fires before the child is gone, so count next frame.
	_refresh_status.call_deferred()


func _refresh_status() -> void:
	var count := _heroes.get_child_count()
	var flags := Net.debug_flags_text()
	_status.text = "Test world (card T07)  |  version %s  |  %s  |  %d in the world%s" % [
		Net.version(), _role_text(), count, "  |  " + flags if flags != "" else "",
	]
	print("[TestWorld] heroes in the world: %d" % count)


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

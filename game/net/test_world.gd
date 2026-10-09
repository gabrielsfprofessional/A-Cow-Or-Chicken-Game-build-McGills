extends Node2D
## Proving ground for card T06: one 48 px square per connected player.
## Owner: Gabe (game/net). T16 replaces it with the real arena.
##
## The server spawns a hero for a client only after that client says its world
## is loaded, so nobody gets a hero they cannot draw yet.
## No movement here: that is T07.

const HERO_SIZE: float = 48.0
const NAME_HEIGHT: float = 28.0
const NAME_WIDTH: float = 160.0
const RING_RADIUS: float = 260.0
## Middle of the 1920x1080 viewport. This world has no camera.
const WORLD_CENTER: Vector2 = Vector2(960.0, 540.0)
## Golden-ratio step, so nearby peer ids land far apart on the ring.
const RING_STEP: float = 0.618034

@onready var _heroes: Node2D = $Heroes
@onready var _spawner: MultiplayerSpawner = $HeroSpawner
@onready var _status: Label = $Hud/Status


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


## A client telling the server its world is ready. The server answers with a hero.
@rpc("any_peer", "call_remote", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if _heroes.has_node(NodePath(str(peer_id))):
		return  # Already has a hero. A repeated hello changes nothing.
	_spawner.spawn(peer_id)
	print("[TestWorld] hero spawned for peer %d" % peer_id)


func _say_hello() -> void:
	print("[TestWorld] world ready, saying hello as peer %d" % multiplayer.get_unique_id())
	client_ready.rpc_id(1)


func _remove_hero(peer_id: int) -> void:
	var hero := _heroes.get_node_or_null(NodePath(str(peer_id)))
	if hero == null:
		return
	hero.queue_free()  # The spawner takes the square off every client too.
	print("[TestWorld] hero removed for peer %d" % peer_id)


## Runs on every peer, server included, through the spawner.
func _make_hero(data: Variant) -> Node:
	var peer_id := int(data)
	var hero := Node2D.new()
	hero.name = str(peer_id)
	hero.position = _spawn_point(peer_id)
	# The owning client drives this hero from T07 on.
	hero.set_multiplayer_authority(peer_id)

	var body := ColorRect.new()
	body.name = "Body"
	body.color = _hero_color(peer_id)
	body.size = Vector2(HERO_SIZE, HERO_SIZE)
	body.position = -body.size * 0.5
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(body)

	var label := Label.new()
	label.name = "PlayerName"
	label.text = "Player %d" % peer_id
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(NAME_WIDTH, NAME_HEIGHT)
	label.position = Vector2(-NAME_WIDTH * 0.5, -HERO_SIZE * 0.5 - NAME_HEIGHT - 6.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(label)

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
	_status.text = "Test world (card T06)  |  version %s  |  %s  |  %d in the world" % [
		Net.version(), _role_text(), count,
	]
	print("[TestWorld] heroes in the world: %d" % count)


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

class_name BotBrain
extends HeroInput
## A test bot's hands on its hero (card T09). Owner: Gabe (game/net).
##
## The owner's NetHero makes one instead of a plain HeroInput when the game was
## started with "-- --bot=<seed>" (debug builds). The hero moves, aims and fires
## through the same calls as a person's, so the server can't tell them apart.
## BotRules decides; this node feeds it the world every physics tick and turns
## its answers into move, aim and fire.
##
## Prints "[Bot] seed <n>: <shots> shots, <hits> hits, <eliminations>
## eliminations, <deaths> deaths" every STATS_INTERVAL_SEC and when it leaves the
## tree. Shots come from its Weapon's `fired` signal, the rest from Events.

const STATS_INTERVAL_SEC: float = 30.0
## Physics layer 1 ("world"): what blocks the bot's view.
const WORLD_MASK: int = 1

## The seed from "--bot=<seed>". Set before the node enters the tree.
var bot_seed: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rules: BotRules
var _range_px: float = 0.0
var _ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.new()
var _move: Vector2 = Vector2.ZERO
var _aim: Vector2 = Vector2.RIGHT
var _fire: bool = false
var _was_alive: bool = true
var _stats_at_sec: float = 0.0
var _shots: int = 0
var _hits: int = 0
var _eliminations: int = 0
var _deaths: int = 0


func _ready() -> void:
	# Decide before the hero moves and its weapon fires in the same tick.
	process_physics_priority = -1
	_rng.seed = bot_seed
	_rules = BotRules.new(_rng, _area())
	_ray.collision_mask = WORLD_MASK
	var weapon := hero.get_node(^"Weapon") as Weapon
	_range_px = weapon.data.range_px
	weapon.fired.connect(_on_fired)
	Events.hero_damaged.connect(_on_hero_damaged)
	Events.hero_eliminated.connect(_on_hero_eliminated)
	var now := _now_sec()
	_rules.restart(now, hero.global_position)
	_stats_at_sec = now + STATS_INTERVAL_SEC
	print("[Bot] seed %d is peer %d" % [bot_seed, hero.owner_peer])


func _exit_tree() -> void:
	_print_stats()


func move() -> Vector2:
	return _move


func aim() -> Vector2:
	return _aim


func fire_held() -> bool:
	return _fire


## A bot clicks on every tick of a burst, so a one-shot-per-click weapon fires
## as fast as it allows.
func fire_pressed() -> bool:
	return _fire


func _physics_process(_delta: float) -> void:
	var now := _now_sec()
	if now >= _stats_at_sec:
		_stats_at_sec = now + STATS_INTERVAL_SEC
		_print_stats()
	if not hero.is_alive():
		_idle()
		return
	var at := hero.global_position
	if not _was_alive:
		_was_alive = true
		_rules.restart(now, at)
	_move = _rules.walk(now, at)
	if _rules.is_look_due(now):
		_rules.pick_target(hero.owner_peer, at, _seen_heroes(at), _range_px)
	var target := _target_hero()
	if target == null:
		# No target: aim where it walks and hold fire.
		_rules.drop_target()
		_fire = false
		if not _move.is_zero_approx():
			_aim = _move
		return
	_aim = _rules.aim_at(at, target.global_position)
	_fire = _rules.trigger(now)


## Eliminated: stand still and hold fire until the hero comes back.
func _idle() -> void:
	_was_alive = false
	_move = Vector2.ZERO
	_fire = false
	_rules.drop_target()


## Every other hero in the world, and whether a wall blocks the view of it.
func _seen_heroes(at: Vector2) -> Array[BotRules.Seen]:
	var seen: Array[BotRules.Seen] = []
	var space := hero.get_world_2d().direct_space_state
	for child: Node in hero.get_parent().get_children():
		var other := child as NetHero
		if other == null or other == hero:
			continue
		_ray.from = at
		_ray.to = other.global_position
		var in_sight := space.intersect_ray(_ray).is_empty()
		seen.append(BotRules.Seen.new(other.owner_peer, other.global_position, other.is_alive(), in_sight))
	return seen


## The hero BotRules picked, while it is still there and alive; else null.
func _target_hero() -> NetHero:
	if _rules.target == 0:
		return null
	var other := hero.get_parent().get_node_or_null(NodePath(str(_rules.target))) as NetHero
	if other == null or not other.is_alive():
		return null
	return other


## Where the world lets bots walk: its bot_area(), or just the spawn spot, so a
## world without one gets bots that stand and shoot.
func _area() -> Rect2:
	var heroes := hero.get_parent()
	var world := heroes.get_parent() if heroes != null else null
	if world != null and world.has_method(&"bot_area"):
		return world.call(&"bot_area")
	return Rect2(hero.global_position, Vector2.ZERO)


func _on_fired(_shot_id: int) -> void:
	_shots += 1


func _on_hero_damaged(_victim: int, attacker: int, _amount: int, _at: Vector2) -> void:
	if attacker == hero.owner_peer:
		_hits += 1


func _on_hero_eliminated(victim: int, attacker: int) -> void:
	if attacker == hero.owner_peer:
		_eliminations += 1
	if victim == hero.owner_peer:
		_deaths += 1


func _print_stats() -> void:
	print("[Bot] seed %d: %d shots, %d hits, %d eliminations, %d deaths" % [
		bot_seed, _shots, _hits, _eliminations, _deaths,
	])


func _now_sec() -> float:
	return Time.get_ticks_usec() / 1000000.0

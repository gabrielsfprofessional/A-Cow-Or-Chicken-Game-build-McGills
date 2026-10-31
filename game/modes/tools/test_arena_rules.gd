extends SceneTree
## Tests for card T12: SpawnPicker (which point a returning hero gets), ArenaRules
## (MapRules plus that pick and spawn protection), data/arena_rules.tres and
## ArenaMap.make_rules(). Owner: Adam (game/modes). No autoloads: fake heroes stand in.
## Run from the repo folder:
##   godot --headless --path . --script res://game/modes/tools/test_arena_rules.gd
## Exits with code 1 when any case is wrong. tools/smoke.ps1 runs it.

const ARENA_SCENE: PackedScene = preload("res://game/maps/arena/arena_graybox.tscn")
const DATA_PATH: String = "res://game/modes/data/arena_rules.tres"
const COMBAT: CombatData = preload("res://game/heroes/data/combat.tres")
const PEERS: Array[int] = [2, 3, 17, 1743561404, 186990725, 475170837, 99, 1000]


## A 2-team mode on the arena, the way T15 would write one: even peers Blue, odd Orange.
class ArenaTeams:
	extends ArenaRules

	func _init(points: Dictionary[String, Vector2], living_heroes: Callable) -> void:
		super(points, living_heroes)

	func team_of(peer_id: int) -> int:
		return peer_id % 2

	func is_enemy(a: int, b: int) -> bool:
		return team_of(a) != team_of(b)


## The same teams on plain MapRules, to compare picks with.
class MapTeams:
	extends MapRules

	func _init(points: Dictionary[String, Vector2]) -> void:
		super(points)

	func team_of(peer_id: int) -> int:
		return peer_id % 2


## Stands in for a NetHero: ArenaMap reads only these three things.
class FakeHero:
	extends Node2D

	var owner_peer: int = 0
	var alive: bool = true

	func is_alive() -> bool:
		return alive


## Has owner_peer but no is_alive(): ArenaMap must not count it.
class NoIsAlive:
	extends Node2D

	var owner_peer: int = 7


var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_picker_farthest_from_nearest_enemy()
	_picker_tie_goes_to_teammates()
	_picker_tie_goes_to_stable_slot()
	_picker_no_points()
	_no_heroes_picks_like_map_rules()
	_ignores_own_hero()
	_teammates_are_not_enemies()
	_name_and_point_agree()
	_no_points_falls_back_to_the_ring()
	_arena_real_points()
	_data_file()
	_make_rules_on_the_arena()
	_make_rules_without_heroes()
	_living_heroes_fails_closed()
	print("ARENA RULES TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _points() -> Dictionary[String, Vector2]:
	var points: Dictionary[String, Vector2] = {}
	for i: int in 4:
		points["SpawnA%d" % (i + 1)] = Vector2(100.0, 100.0 + 200.0 * i)
		points["SpawnB%d" % (i + 1)] = Vector2(1800.0, 100.0 + 200.0 * i)
	return points


func _heroes(living: Dictionary[int, Vector2]) -> Callable:
	return func() -> Dictionary[int, Vector2]: return living


func _picker_farthest_from_nearest_enemy() -> void:
	var points: Array[Vector2] = [Vector2(0, 0), Vector2(100, 0), Vector2(500, 0)]
	var enemies: Array[Vector2] = [Vector2(0, 0)]
	var got := SpawnPicker.pick(points, enemies, [], 0.0)
	_expect(got == 2, "the point farthest from the enemy wins", "got %d" % got)
	# The nearest enemy counts, not the sum: point 0 is 300 from its nearest, point 1 only 100.
	points = [Vector2(0, 0), Vector2(1000, 0)]
	enemies = [Vector2(300, 0), Vector2(1100, 0)]
	got = SpawnPicker.pick(points, enemies, [], 0.99)
	_expect(got == 0, "the nearest enemy decides, not the total", "got %d" % got)


func _picker_tie_goes_to_teammates() -> void:
	var points: Array[Vector2] = [Vector2(0, -100), Vector2(0, 100)]
	var enemies: Array[Vector2] = [Vector2(0, 0)]
	var teammates: Array[Vector2] = [Vector2(0, 90)]
	var got := SpawnPicker.pick(points, enemies, teammates, 0.99)
	_expect(got == 0, "an enemy tie goes to the point farthest from a teammate", "got %d" % got)


func _picker_tie_goes_to_stable_slot() -> void:
	var points: Array[Vector2] = [Vector2(0, -100), Vector2(0, 100), Vector2(500, 500)]
	# Points 0 and 1 are 100 px from their nearest enemy; point 2 only 50.
	var enemies: Array[Vector2] = [Vector2(0, 0), Vector2(500, 450)]
	var low := SpawnPicker.pick(points, enemies, [], 0.0)
	var high := SpawnPicker.pick(points, enemies, [], 0.99)
	_expect(low == 0 and high == 1, "a full tie goes to the stable slot among the tied points only",
		"got %d and %d" % [low, high])
	var none := SpawnPicker.pick(points, [], [], 0.5)
	_expect(none == 1, "with nobody alive, every point ties", "got %d" % none)


func _picker_no_points() -> void:
	var got := SpawnPicker.pick([], [Vector2(1, 1)], [], 0.5)
	_expect(got == -1, "no points gives -1", "got %d" % got)


func _no_heroes_picks_like_map_rules() -> void:
	var nobody := _heroes({})
	var wrong: PackedStringArray = []
	var peers: Array[int] = PEERS.duplicate()
	for peer: int in range(2, 51):
		peers.append(peer)
	for peer: int in peers:
		if ArenaRules.new(_points(), nobody).pick(peer) != MapRules.new(_points()).pick(peer):
			wrong.append("no teams %d" % peer)
		if ArenaTeams.new(_points(), nobody).pick(peer) != MapTeams.new(_points()).pick(peer):
			wrong.append("teams %d" % peer)
	var one_sided: Dictionary[String, Vector2] = {"SpawnA1": Vector2(10, 10), "SpawnA2": Vector2(20, 20), "Bridge": Vector2(30, 30)}
	for peer: int in peers:
		if ArenaTeams.new(one_sided, nobody).pick(peer) != MapTeams.new(one_sided).pick(peer):
			wrong.append("one-sided %d" % peer)
	_expect(wrong.is_empty(), "with nobody alive, ArenaRules picks exactly what MapRules picks (%d peers)" % peers.size(),
		", ".join(wrong))


func _ignores_own_hero() -> void:
	# Peer 5 stands on SpawnB4 (where it died); peer 6 stands on SpawnA1.
	var living: Dictionary[int, Vector2] = {5: Vector2(1800, 700), 6: Vector2(100, 100)}
	var rules := ArenaRules.new(_points(), _heroes(living))
	_expect(rules.point_name(5) == "SpawnB4", "the hero's own body doesn't push it away",
		rules.point_name(5))


func _teammates_are_not_enemies() -> void:
	# Peer 2 (Blue) gets an A point. Teammate 4 stands on SpawnA1; enemy 3 is far below.
	# Counted as an enemy, the teammate would rule SpawnA1 out.
	var living: Dictionary[int, Vector2] = {4: Vector2(100, 100), 3: Vector2(100, 1900)}
	var rules := ArenaTeams.new(_points(), _heroes(living))
	_expect(rules.point_name(2) == "SpawnA1", "a team keeps to its points and keeps away from enemies only",
		rules.point_name(2))
	# Orange peer 3 respawning: it may only use B points, even with Blue standing on all of them.
	living = {2: Vector2(1800, 100), 4: Vector2(1800, 300), 6: Vector2(1800, 500), 8: Vector2(1800, 700)}
	rules = ArenaTeams.new(_points(), _heroes(living))
	_expect(rules.point_name(3).begins_with("SpawnB"), "a team never takes the other side's points",
		rules.point_name(3))


func _name_and_point_agree() -> void:
	var points := _points()
	var living: Dictionary[int, Vector2] = {7: Vector2(150, 250), 9: Vector2(1700, 650)}
	var rules := ArenaRules.new(points, _heroes(living))
	var off: PackedStringArray = []
	for peer: int in PEERS:
		var spot_name := rules.point_name(peer)
		if not points.has(spot_name) or not points[spot_name].is_equal_approx(rules.respawn_point(peer)):
			off.append("%d -> %s" % [peer, spot_name])
	_expect(off.is_empty(), "respawn_point() and point_name() name the same point", ", ".join(off))


func _no_points_falls_back_to_the_ring() -> void:
	var living: Dictionary[int, Vector2] = {3: Vector2(1, 1)}
	var rules := ArenaRules.new({}, _heroes(living))
	var ring := MatchRules.new()
	_expect(rules.pick(17) == -1 and rules.point_name(17) == "" and rules.respawn_point(17) == ring.respawn_point(17),
		"a map with no points falls back to the ring", rules.point_name(17))


func _arena_real_points() -> void:
	var arena := _arena()
	root.add_child(arena)
	var points := MapRules.points_of(arena)
	_expect(points.size() == ArenaMap.SPAWN_NAMES.size(), "the arena has its %d spawn points" % ArenaMap.SPAWN_NAMES.size(),
		"found %d" % points.size())
	# An enemy on SpawnA1: a point farthest from it must win (any of them, if several tie).
	var living: Dictionary[int, Vector2] = {3: points["SpawnA1"]}
	var rules := ArenaRules.new(points, _heroes(living))
	var far := 0.0
	for spawn_name: String in points:
		far = maxf(far, points[spawn_name].distance_to(points["SpawnA1"]))
	var farthest: PackedStringArray = []
	for spawn_name: String in points:
		if is_equal_approx(points[spawn_name].distance_to(points["SpawnA1"]), far):
			farthest.append(spawn_name)
	_expect(farthest.has(rules.point_name(2)), "on the arena, an enemy on SpawnA1 sends you to %s" % " or ".join(farthest),
		rules.point_name(2))
	arena.free()


func _data_file() -> void:
	var data := ResourceLoader.load(DATA_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ArenaRulesData
	if data == null:
		_expect(false, "arena_rules.tres loads as ArenaRulesData", "it didn't load; check its script path")
		return
	_expect(data.validate().is_empty(), "arena_rules.tres passes validate()", "; ".join(data.validate()))
	# On purpose: the card says 2 s. A tuning change updates this line too.
	_expect(is_equal_approx(data.spawn_protection_sec, 2.0), "spawn protection is 2 s", str(data.spawn_protection_sec))
	var rules := ArenaRules.new(_points(), _heroes({}))
	_expect(is_equal_approx(rules.spawn_protection_sec(), data.spawn_protection_sec),
		"ArenaRules reads its protection from the file", str(rules.spawn_protection_sec()))
	_expect(is_equal_approx(rules.respawn_delay_sec(2), COMBAT.respawn_sec),
		"the respawn delay stays combat.tres respawn_sec", str(rules.respawn_delay_sec(2)))
	for bad: float in [-1.0, 99.0]:
		var broken := ArenaRulesData.new()
		broken.spawn_protection_sec = bad
		_expect(not broken.validate().is_empty(), "validate() catches spawn protection %.0f s" % bad, "no problem found")


func _make_rules_on_the_arena() -> void:
	var world := Node2D.new()
	var heroes := Node2D.new()
	heroes.name = "Heroes"
	world.add_child(heroes)
	var arena := _arena()
	world.add_child(arena)
	root.add_child(world)
	var points := MapRules.points_of(arena)
	# Enemy 3 on SpawnA1 is alive; enemy 5, dead, lies on the point that would otherwise win.
	var living: Dictionary[int, Vector2] = {3: points["SpawnA1"]}
	var expected := ArenaRules.new(points, _heroes(living)).point_name(2)
	heroes.add_child(_fake_hero(3, points["SpawnA1"], true))
	heroes.add_child(_fake_hero(5, points[expected], false))
	var rules: MatchRules = arena.make_rules()
	_expect(rules is ArenaRules, "the arena's make_rules() gives ArenaRules", str(rules))
	if rules is ArenaRules:
		var got := (rules as ArenaRules).point_name(2)
		_expect(got == expected, "make_rules() reads the living heroes and skips the dead", "got %s, wanted %s" % [got, expected])
	world.free()


## The two ways the arena can't see the heroes each say why, and the rules still work
## (falling back to MapRules' pick). Both print an engine error on purpose.
func _make_rules_without_heroes() -> void:
	print("  (the next two ERROR lines are on purpose)")
	var arena := _arena()
	var alone := ArenaMap.heroes_problem(arena)
	_expect(alone.contains("not in a world"), "a map with no world says so", alone)
	var world := Node2D.new()
	world.add_child(arena)
	var bare := ArenaMap.heroes_problem(arena)
	_expect(bare.contains("no Heroes node"), "a world with no Heroes node says so", bare)
	var rules := arena.make_rules()
	var plain := MapRules.new(MapRules.points_of(arena))
	_expect(rules.pick(2) == plain.pick(2), "without heroes, the arena picks like MapRules", rules.point_name(2))
	var heroes := Node2D.new()
	heroes.name = "Heroes"
	world.add_child(heroes)
	_expect(ArenaMap.heroes_problem(arena) == "", "a world with Heroes has no problem", ArenaMap.heroes_problem(arena))
	world.free()
	var no_reader := ArenaRules.new(_points(), Callable())
	_expect(no_reader.pick(2) == MapRules.new(_points()).pick(2), "ArenaRules with no hero reader still picks", no_reader.point_name(2))


## A Heroes child that isn't a hero is named in an error and skipped, never counted;
## a dead hero is skipped without one. Prints engine errors on purpose.
func _living_heroes_fails_closed() -> void:
	print("  (the next two ERROR lines, naming NoPeer and NoIsAlive, are on purpose)")
	var heroes := Node2D.new()
	heroes.name = "Heroes"
	heroes.add_child(_fake_hero(3, Vector2(10, 10), true))
	heroes.add_child(_fake_hero(5, Vector2(20, 20), false))
	var no_peer := Node2D.new()
	no_peer.name = "NoPeer"
	heroes.add_child(no_peer)
	var no_is_alive := NoIsAlive.new()
	no_is_alive.name = "NoIsAlive"
	heroes.add_child(no_is_alive)
	root.add_child(heroes)
	var living := ArenaMap._living_heroes(heroes)
	_expect(living.keys() == [3] and living[3].is_equal_approx(Vector2(10, 10)),
		"only real living heroes count: no owner_peer or no is_alive() is skipped, and so is the dead", str(living))
	heroes.free()


func _arena() -> ArenaMap:
	var arena := ARENA_SCENE.instantiate() as ArenaMap
	# The world drops map cameras before a map enters the tree; so does this test.
	for camera: Node in arena.find_children("*", "Camera2D", true, false):
		camera.get_parent().remove_child(camera)
		camera.free()
	return arena


func _fake_hero(peer: int, at: Vector2, alive: bool) -> FakeHero:
	var hero := FakeHero.new()
	hero.name = str(peer)
	hero.owner_peer = peer
	hero.alive = alive
	hero.position = at
	return hero


func _expect(ok: bool, what: String, problem: String) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s: %s" % [what, problem])

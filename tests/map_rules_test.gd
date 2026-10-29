extends SceneTree
## Tests for card T39: MapRules (heroes spawn on the map's points, by team) and
## ReadyPeers.recipients() (send_to_ready reaches ready, connected peers only).
## Owner: Gabe.
## Run: godot --headless --path . --script res://tests/map_rules_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
## Building a real map online is covered by smoke's arena check.

const ARENA_SCENE: PackedScene = preload("res://game/maps/arena/arena_graybox.tscn")
const PRACTICE_SCENE: PackedScene = preload("res://game/maps/practice/practice_range.tscn")
const PEERS: Array[int] = [2, 3, 17, 1743561404, 186990725, 475170837, 99, 1000]


## A 2-team mode on a map, the way T15 would write one: even peers Blue, odd Orange.
class EvenOdd:
	extends MapRules

	func _init(points: Dictionary[String, Vector2] = {}) -> void:
		super(points)

	func team_of(peer_id: int) -> int:
		return peer_id % 2


var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_no_team_uses_every_point()
	_teams_use_their_side()
	_stable_per_peer()
	_no_points_falls_back_to_the_ring()
	_one_sided_map()
	_untagged_points()
	_from_the_arena()
	_from_the_practice_range()
	_send_to_ready_recipients()
	print("MAP RULES TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _points() -> Dictionary[String, Vector2]:
	var points: Dictionary[String, Vector2] = {}
	for i: int in 4:
		points["SpawnA%d" % (i + 1)] = Vector2(100.0, 100.0 + 200.0 * i)
		points["SpawnB%d" % (i + 1)] = Vector2(1800.0, 100.0 + 200.0 * i)
	return points


func _no_team_uses_every_point() -> void:
	var rules := MapRules.new(_points())
	var seen: Dictionary[String, bool] = {}
	for peer: int in range(1, 200):
		var spot_name := rules.point_name(peer)
		seen[spot_name] = true
		_expect_quiet(_points().get(spot_name, Vector2.INF) == rules.respawn_point(peer),
			"peer %d spawns at its named point" % peer)
	_expect(seen.size() == 8, "with no teams, 199 peers land on all 8 points", "%d points used" % seen.size())


func _teams_use_their_side() -> void:
	var rules := EvenOdd.new(_points())
	var wrong: PackedStringArray = []
	for peer: int in range(1, 200):
		var want := "SpawnA" if peer % 2 == 0 else "SpawnB"
		if not rules.point_name(peer).begins_with(want):
			wrong.append("%d -> %s" % [peer, rules.point_name(peer)])
	_expect(wrong.is_empty(), "team 0 spawns on A points, team 1 on B points", ", ".join(wrong))


func _stable_per_peer() -> void:
	var a := MapRules.new(_points())
	var b := MapRules.new(_points())
	var moved: PackedStringArray = []
	for peer: int in PEERS:
		if a.respawn_point(peer) != b.respawn_point(peer) or a.point_name(peer) != b.point_name(peer):
			moved.append(str(peer))
	_expect(moved.is_empty(), "a peer gets the same point every time", ", ".join(moved))


func _no_points_falls_back_to_the_ring() -> void:
	var rules := MapRules.new()
	var ring := MatchRules.new()
	_expect(rules.respawn_point(17) == ring.respawn_point(17) and rules.point_name(17) == "",
		"no points: the T06 ring", "%s vs %s" % [rules.respawn_point(17), ring.respawn_point(17)])


func _one_sided_map() -> void:
	var points: Dictionary[String, Vector2] = {"SpawnA1": Vector2(10.0, 10.0), "SpawnA2": Vector2(20.0, 20.0)}
	var rules := EvenOdd.new(points)
	_expect(rules.point_name(3).begins_with("SpawnA"), "a team with no points of its own uses all of them", rules.point_name(3))


## A point with no team in its name (the practice range's PlayerSpawn) serves every team,
## and a team with points of its own never takes the other team's.
func _untagged_points() -> void:
	var single: Dictionary[String, Vector2] = {"PlayerSpawn": Vector2(50.0, 60.0)}
	var rules := EvenOdd.new(single)
	_expect(rules.point_name(2) == "PlayerSpawn" and rules.point_name(3) == "PlayerSpawn",
		"one untagged point serves both teams", "%s / %s" % [rules.point_name(2), rules.point_name(3)])
	var mixed: Dictionary[String, Vector2] = {"SpawnA1": Vector2(10.0, 10.0), "PlayerSpawn": Vector2(50.0, 60.0)}
	var wrong: PackedStringArray = []
	for peer: int in PEERS:
		if peer % 2 == 1 and EvenOdd.new(mixed).point_name(peer) != "PlayerSpawn":
			wrong.append("%d -> %s" % [peer, EvenOdd.new(mixed).point_name(peer)])
	_expect(wrong.is_empty(), "Orange never takes a SpawnA point; it uses the shared one", ", ".join(wrong))

func _from_the_arena() -> void:
	var arena := ARENA_SCENE.instantiate() as Node2D
	# The world drops map cameras before a map enters the tree; so does this test.
	for camera: Node in arena.find_children("*", "Camera2D", true, false):
		camera.get_parent().remove_child(camera)
		camera.free()
	root.add_child(arena)
	var rules := MapRules.from_map(arena)
	var spawns := arena.get_node("Spawns")
	var off: PackedStringArray = []
	for peer: int in PEERS:
		var marker := spawns.get_node_or_null(rules.point_name(peer)) as Marker2D
		if marker == null or not marker.global_position.is_equal_approx(rules.respawn_point(peer)):
			off.append("%d -> %s" % [peer, rules.point_name(peer)])
	_expect(off.is_empty(), "on the arena every pick is one of its Spawn markers", ", ".join(off))
	arena.free()


func _from_the_practice_range() -> void:
	var practice := PRACTICE_SCENE.instantiate() as Node2D
	for camera: Node in practice.find_children("*", "Camera2D", true, false):
		camera.get_parent().remove_child(camera)
		camera.free()
	root.add_child(practice)
	var rules := MapRules.from_map(practice)
	var spot := (practice.get_node("Spawns/PlayerSpawn") as Marker2D).global_position
	var off: PackedStringArray = []
	for peer: int in PEERS:
		if rules.point_name(peer) != "PlayerSpawn" or not rules.respawn_point(peer).is_equal_approx(spot):
			off.append("%d -> %s" % [peer, rules.point_name(peer)])
	_expect(off.is_empty(), "on the practice range every peer spawns on PlayerSpawn", ", ".join(off))
	practice.free()


func _send_to_ready_recipients() -> void:
	var peers := ReadyPeers.new()
	peers.add(30)
	peers.add(10)
	peers.add(99)  # Ready, then left: not in the connected list any more.
	var got := peers.recipients(PackedInt32Array([10, 20, 30]))
	_expect(got == [10, 30], "send_to_ready skips peers that aren't ready or left", str(got))
	peers.remove(10)
	got = peers.recipients(PackedInt32Array([10, 20, 30]))
	_expect(got == [30] and not peers.has(10), "a removed peer gets nothing", str(got))


## Counts only a failure, so a 199-peer loop doesn't print 199 lines.
func _expect_quiet(ok: bool, what: String) -> void:
	if not ok:
		_expect(false, what, "wrong")


func _expect(ok: bool, what: String, problem: String) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s: %s" % [what, problem])

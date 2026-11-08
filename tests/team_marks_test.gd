extends SceneTree
## Tests for T42's team ring and own-hero outline. Owner: Gabe.
## Run: godot --headless --path . --script res://tests/team_marks_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
##
## 1. The ring's color (TeamMarkData.ring_color() on team_marks.tres): 0 Blue
##    #3B82F6, 1 Orange #F97316, any other team none.
## 2. team_in() reads the world's teams_seen() and turns anything odd into -1;
##    world_team() (NetHero's start team) reads it from a world node.
## 3. builds_marks(): never on a headless run, so the server and bots build none,
##    and a hero built here (headless) has no TeamMarks child.
## 4. TeamMarks follows Events.team_assigned for its own peer only: a balance
##    switch recolors it, a late joiner starts from the world's team.
## 5. TeamMarks draws behind its hero at the hero's own z (show_behind_parent,
##    z_index 0), so a map's floor at z 0 never covers it, and is named TeamMarks.
##
## TeamMarks and NetHero use the Events autoload, so this test never names them
## (see tests/README.md): it loads their files at run time.

const DATA_PATH: String = "res://game/heroes/data/team_marks.tres"
const MARKS_SCRIPT_PATH: String = "res://game/heroes/team_marks.gd"
const HERO_SCENE_PATH: String = "res://game/heroes/net_hero.tscn"
const ROSTER_PATH: String = "res://game/heroes/data/roster.tres"
const BODY: Rect2 = Rect2(-24.0, -24.0, 48.0, 48.0)
## The node cases wait a frame for _ready. An error after an await would hang
## the test, so it fails itself after this long.
const DEADLINE_SEC: float = 10.0


## Stands in for the test world: the parent of "Heroes", with the teams it heard.
class FakeWorld:
	extends Node2D
	var seen: Dictionary[int, int] = {}

	func teams_seen() -> Dictionary[int, int]:
		return seen.duplicate()

	func rules() -> MatchRules:
		return MatchRules.new()

	func is_peer_ready(_peer_id: int) -> bool:
		return false


var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	create_timer(DEADLINE_SEC).timeout.connect(_on_deadline)
	_run()


func _on_deadline() -> void:
	printerr("  FAIL  the test did not finish within %d s (a script error after an await?)" % roundi(DEADLINE_SEC))
	quit(1)


func _run() -> void:
	_ring_colors()
	_has_ring()
	_team_in()
	_builds_marks()
	await _marks_follow_team_assigned()
	await _headless_hero_has_no_marks()
	print("TEAM MARKS TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _ring_colors() -> void:
	var data := load(DATA_PATH) as TeamMarkData
	_expect(data != null, "team_marks.tres loads as TeamMarkData", "it doesn't")
	if data == null:
		return
	_expect(data.ring_color(0).to_html(false) == "3b82f6", "team 0's ring is Blue #3B82F6",
		"it is #%s" % data.ring_color(0).to_html(false))
	_expect(data.ring_color(1).to_html(false) == "f97316", "team 1's ring is Orange #F97316",
		"it is #%s" % data.ring_color(1).to_html(false))
	_expect(data.ring_color(-1).a == 0.0, "no team (-1): the ring is see-through", "alpha %s" % data.ring_color(-1).a)
	_expect(data.ring_color(2).a == 0.0, "an unknown team (2): the ring is see-through", "alpha %s" % data.ring_color(2).a)


func _has_ring() -> void:
	_expect(TeamMarkData.has_ring(0) and TeamMarkData.has_ring(1), "teams 0 and 1 have a ring", "one doesn't")
	_expect(not TeamMarkData.has_ring(-1), "no team (-1) has no ring", "it has one")
	_expect(not TeamMarkData.has_ring(2), "an unknown team (2) has no ring", "it has one")


func _team_in() -> void:
	var seen: Dictionary[int, int] = {5: 1, 6: 0}
	_expect(TeamMarkData.team_in(seen, 5) == 1 and TeamMarkData.team_in(seen, 6) == 0,
		"team_in() finds each peer's team", "got %d and %d" % [TeamMarkData.team_in(seen, 5), TeamMarkData.team_in(seen, 6)])
	_expect(TeamMarkData.team_in(seen, 7) == -1, "a peer not in teams_seen() has no team (-1)",
		"got %d" % TeamMarkData.team_in(seen, 7))
	_expect(TeamMarkData.team_in(null, 5) == -1, "no world (null): no team", "got %d" % TeamMarkData.team_in(null, 5))
	_expect(TeamMarkData.team_in({5: "1"}, 5) == -1, "a team that isn't an int: no team",
		"got %d" % TeamMarkData.team_in({5: "1"}, 5))
	_expect(TeamMarkData.team_in({5: 7}, 5) == -1, "a team that isn't 0 or 1: no team",
		"got %d" % TeamMarkData.team_in({5: 7}, 5))


func _builds_marks() -> void:
	_expect(not TeamMarkData.builds_marks("headless"), "a headless run (server, bots) builds no marks", "it builds them")
	_expect(TeamMarkData.builds_marks("Windows"), "a window builds the marks", "it doesn't")


func _marks_follow_team_assigned() -> void:
	var events: Node = root.get_node(^"Events")
	var script := load(MARKS_SCRIPT_PATH) as GDScript
	var mine := script.new() as Node2D
	mine.call(&"setup", 5, true, BODY, 1)
	root.add_child(mine)
	var other := script.new() as Node2D
	other.call(&"setup", 6, false, BODY, -1)
	root.add_child(other)
	await process_frame
	_expect(mine.call(&"team") == 1, "a late joiner's ring starts at the world's team (1)", "got %s" % mine.call(&"team"))
	_expect(mine.call(&"is_own") == true and other.call(&"is_own") == false,
		"only the own hero has the outline", "own: %s and %s" % [mine.call(&"is_own"), other.call(&"is_own")])
	_expect(mine.show_behind_parent, "the marks draw behind the hero's body", "show_behind_parent is off")
	# A map's Floor sits at z 0: a negative z would sort the marks under it, out of sight.
	_expect(mine.z_index == 0 and mine.z_as_relative, "the marks keep the hero's z, so a map's floor never covers them",
		"z_index %d, z_as_relative %s" % [mine.z_index, mine.z_as_relative])
	_expect(mine.name == &"TeamMarks", "the marks node is named TeamMarks from setup()", "named %s" % mine.name)
	events.emit_signal(&"team_assigned", 6, 0)
	_expect(mine.call(&"team") == 1 and other.call(&"team") == 0,
		"team_assigned for peer 6 changes only peer 6's ring", "got %s and %s" % [mine.call(&"team"), other.call(&"team")])
	events.emit_signal(&"team_assigned", 5, 0)
	_expect(mine.call(&"team") == 0, "a balance switch (1 -> 0) changes the ring at once", "got %s" % mine.call(&"team"))
	events.emit_signal(&"team_assigned", 5, 9)
	_expect(mine.call(&"team") == -1, "an unknown team takes the ring away", "got %s" % mine.call(&"team"))
	mine.free()
	other.free()


func _headless_hero_has_no_marks() -> void:
	var world := FakeWorld.new()
	world.name = "World"
	world.seen = {3: 0}
	root.add_child(world)
	var heroes := Node2D.new()
	heroes.name = "Heroes"
	world.add_child(heroes)
	var hero: Node = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	var roster := load(ROSTER_PATH) as HeroRoster
	hero.call(&"setup", 3, Vector2(100.0, 100.0), Color.WHITE, roster.first())
	heroes.add_child(hero)
	await process_frame
	_expect(hero.get_node_or_null(^"TeamMarks") == null, "a hero on a headless run has no TeamMarks child",
		"it has one")
	# NetHero's start team: TeamMarkData.world_team(its world, its peer).
	_expect(TeamMarkData.world_team(world, 3) == 0, "world_team() reads the world's teams_seen()",
		"got %d" % TeamMarkData.world_team(world, 3))
	_expect(TeamMarkData.world_team(world, 4) == -1, "world_team() for a peer the world hasn't heard: -1",
		"got %d" % TeamMarkData.world_team(world, 4))
	_expect(TeamMarkData.world_team(null, 3) == -1, "world_team() with no world: -1",
		"got %d" % TeamMarkData.world_team(null, 3))
	_expect(TeamMarkData.world_team(heroes, 3) == -1, "world_team() on a node without teams_seen(): -1",
		"got %d" % TeamMarkData.world_team(heroes, 3))
	world.free()


func _expect(ok: bool, what: String, problem: String) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s: %s" % [what, problem])

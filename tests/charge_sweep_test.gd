extends SceneTree
## Physics test for ChargeSweep.find(), the server's dash hit test (card T14). Owner: Gabe.
## Run: godot --headless --path . --script res://tests/charge_sweep_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
##
## Real bodies in a real physics space: a hero-sized circle swept 240 px along
## y = 300 must find a hero in the middle of the path, miss one beside it, skip
## the dasher it was told to exclude and skip one whose collider is off.

const RADIUS: float = 20.0
const FROM: Vector2 = Vector2(100.0, 300.0)
const TO: Vector2 = Vector2(340.0, 300.0)
## Physics layer 2 ("heroes").
const HERO_LAYER: int = 2
## This test awaits physics frames, and smoke has no per-test timeout: an error
## after an await would hang it, so it fails itself after this long.
const DEADLINE_SEC: float = 10.0

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	create_timer(DEADLINE_SEC).timeout.connect(_on_deadline)
	_run()


func _on_deadline() -> void:
	printerr("  FAIL  the test did not finish within %d s (a script error after an await?)" % roundi(DEADLINE_SEC))
	quit(1)


func _run() -> void:
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var dasher := _body("Dasher", FROM, shape)
	var mid_path := _body("MidPath", Vector2(220.0, 300.0), shape)
	var grazed := _body("Grazed", Vector2(220.0, 300.0 + 2.0 * RADIUS - 2.0), shape)
	var beside := _body("Beside", Vector2(220.0, 300.0 + 2.0 * RADIUS + 20.0), shape)
	var past_end := _body("PastEnd", TO + Vector2(2.0 * RADIUS + 20.0, 0.0), shape)
	var eliminated := _body("Eliminated", Vector2(280.0, 300.0), shape)
	(eliminated.get_child(0) as CollisionShape2D).disabled = true
	# Let the bodies reach the physics server's broadphase.
	await physics_frame
	await physics_frame
	var space := root.get_world_2d().direct_space_state
	var found := ChargeSweep.find(space, shape, FROM, TO, [dasher.get_rid()])
	_expect(found.has(mid_path), "finds a hero in the middle of the path")
	_expect(found.has(grazed), "finds a hero whose edge overlaps the path by 2 px")
	_expect(not found.has(beside), "misses a hero 20 px beside the path")
	_expect(not found.has(past_end), "misses a hero 20 px past the end")
	_expect(not found.has(dasher), "skips the dasher (excluded)")
	_expect(not found.has(eliminated), "skips a hero with its collider off (eliminated)")
	_expect(found.size() == 2, "finds exactly those two (got %d)" % found.size())
	var unexcluded := ChargeSweep.find(space, shape, FROM, TO, [])
	_expect(unexcluded.has(dasher), "without the exclude, the dasher is found (the exclude matters)")
	var still := ChargeSweep.find(space, shape, FROM, FROM, [dasher.get_rid()])
	_expect(not still.has(mid_path), "a sweep that doesn't move only checks where it is")
	print("CHARGE SWEEP TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _body(body_name: String, at: Vector2, shape: Shape2D) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = body_name
	body.collision_layer = HERO_LAYER
	body.collision_mask = 0
	body.position = at
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)
	return body


func _expect(ok: bool, case_name: String) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

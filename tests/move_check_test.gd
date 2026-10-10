extends SceneTree
## Tests for MoveCheck, the server's movement check (card T07). Owner: Gabe.
## Run: godot --headless --path . --script res://tests/move_check_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.

const MoveCheckScript: GDScript = preload("res://game/net/move_check.gd")
const OWNER: int = 5
const SPEED: float = 300.0
const START: Vector2 = Vector2(100.0, 100.0)
const STEP: float = 0.05

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_wrong_owner()
	_old_sequence()
	_honest_full_speed()
	_too_far()
	_reject_keeps_position_and_advances_sequence()
	_budget_overspend()
	_huge_sequence_jump()
	_not_finite()
	_out_of_bounds()
	_lags_as_they_join()
	print("MOVE CHECK TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _new_check() -> MoveCheck:
	return MoveCheckScript.new(OWNER, START, SPEED, 0.0)


func _wrong_owner() -> void:
	var check := _new_check()
	_expect("wrong owner is dropped", check.check(9, 1, START, 0.05), MoveCheck.Result.WRONG_OWNER)
	_expect_true("wrong owner changes nothing", check.last_sequence == 0 and check.position == START and check.rejected == 0)


func _old_sequence() -> void:
	var check := _new_check()
	_expect("first update", check.check(OWNER, 3, START + Vector2(10, 0), 0.15), MoveCheck.Result.ACCEPTED)
	_expect("same sequence again", check.check(OWNER, 3, START, 0.2), MoveCheck.Result.OLD_SEQUENCE)
	_expect("older sequence", check.check(OWNER, 2, START, 0.2), MoveCheck.Result.OLD_SEQUENCE)
	_expect_true("old sequence keeps the newer position", check.position == START + Vector2(10, 0) and check.last_sequence == 3)


func _honest_full_speed() -> void:
	# Full speed on a diagonal for 10 s at 20 Hz, sent on time.
	var check := _new_check()
	var position := START
	var step := Vector2(1, 1).normalized() * SPEED * STEP
	var all_ok := true
	for sequence: int in range(1, 201):
		position += step
		all_ok = all_ok and check.check(OWNER, sequence, position, sequence * STEP) == MoveCheck.Result.ACCEPTED
	_expect_true("full speed for 10 s is accepted", all_ok and check.rejected == 0)


func _too_far() -> void:
	var check := _new_check()
	var limit := SPEED * MoveCheck.SPEED_TOLERANCE * STEP
	_expect("just inside 1.25x speed", check.check(OWNER, 1, START + Vector2(limit - 0.1, 0), 0.05), MoveCheck.Result.ACCEPTED)
	var from := check.position
	_expect("2x speed is too far", check.check(OWNER, 2, from + Vector2(SPEED * 2.0 * STEP, 0), 0.1), MoveCheck.Result.TOO_FAR)
	# A gap of 3 allows three steps' worth.
	_expect("a gap of 3 allows 3 steps", check.check(OWNER, 5, from + Vector2(SPEED * 3.0 * STEP, 0), 0.25), MoveCheck.Result.ACCEPTED)


func _reject_keeps_position_and_advances_sequence() -> void:
	var check := _new_check()
	check.check(OWNER, 1, START + Vector2(10, 0), 0.05)
	_expect("teleport is too far", check.check(OWNER, 2, START + Vector2(500, 0), 0.1), MoveCheck.Result.TOO_FAR)
	_expect_true("reject keeps the last good position", check.position == START + Vector2(10, 0))
	_expect_true("reject advances the last sequence", check.last_sequence == 2 and check.rejected == 1)
	_expect("the next honest step is fine", check.check(OWNER, 3, START + Vector2(20, 0), 0.15), MoveCheck.Result.ACCEPTED)


func _budget_overspend() -> void:
	# Sends 2 s of sequence numbers within 0.5 s of real time: the budget (1 s full,
	# refilling at 1.1x) runs out part way through.
	var check := _new_check()
	var results: Array[MoveCheck.Result] = []
	for sequence: int in range(1, 41):
		results.append(check.check(OWNER, sequence, START, sequence * STEP * 0.25))
	_expect("the early burst is accepted", results[0], MoveCheck.Result.ACCEPTED)
	_expect_true("the burst overspends the budget", MoveCheck.Result.OVER_BUDGET in results)
	_expect_true("over budget is counted", check.rejected > 0)


func _huge_sequence_jump() -> void:
	var check := _new_check()
	check.check(OWNER, 1, START, 0.05)
	# Claims 50 000 s of movement: the distance rule alone would allow 18 million px.
	_expect("a huge sequence jump is over budget", check.check(OWNER, 1000001, START + Vector2(5000, 0), 0.1), MoveCheck.Result.OVER_BUDGET)
	_expect_true("the jump does not move the hero", check.position == START)


func _not_finite() -> void:
	var check := _new_check()
	_expect("NaN is rejected", check.check(OWNER, 1, Vector2(NAN, 100), 0.05), MoveCheck.Result.NOT_FINITE)
	_expect("INF is rejected", check.check(OWNER, 2, Vector2(100, INF), 0.1), MoveCheck.Result.NOT_FINITE)
	_expect("-INF is rejected", check.check(OWNER, 3, Vector2(-INF, 100), 0.15), MoveCheck.Result.NOT_FINITE)
	_expect_true("non-finite keeps the position", check.position == START and check.last_sequence == 3)


func _out_of_bounds() -> void:
	var check: MoveCheck = MoveCheckScript.new(OWNER, Vector2(99990, 0), SPEED, 0.0)
	_expect("+100001 px is rejected", check.check(OWNER, 1, Vector2(100001, 0), 0.05), MoveCheck.Result.OUT_OF_BOUNDS)
	var far: MoveCheck = MoveCheckScript.new(OWNER, Vector2(0, -99990), SPEED, 0.0)
	_expect("-100001 px is rejected", far.check(OWNER, 1, Vector2(0, -100001), 0.05), MoveCheck.Result.OUT_OF_BOUNDS)
	_expect("exactly 100000 px is allowed", far.check(OWNER, 2, Vector2(0, -100000), 0.1), MoveCheck.Result.ACCEPTED)


func _lags_as_they_join() -> void:
	# The hero spawns at t = 0 but the first update only arrives at t = 5 s.
	# The old "since the first update" rule rejected this player all match.
	var check := _new_check()
	var position := START
	var all_ok := true
	for sequence: int in range(1, 201):
		position += Vector2(SPEED * STEP, 0) if sequence % 40 < 20 else Vector2(-SPEED * STEP, 0)
		all_ok = all_ok and check.check(OWNER, sequence, position, 5.0 + sequence * STEP) == MoveCheck.Result.ACCEPTED
	_expect_true("a player who lags as they join then moves normally is never rejected", all_ok and check.rejected == 0)


func _expect(case_name: String, got: MoveCheck.Result, wanted: MoveCheck.Result) -> void:
	_count += 1
	if got == wanted:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s: got %s, wanted %s" % [case_name, MoveCheck.result_name(got), MoveCheck.result_name(wanted)])


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

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
	_reset_on_respawn()
	_dash_without_grant()
	_grant_lets_a_dash_through()
	_grant_gets_used_up()
	_grant_expires()
	_grant_survives_a_freeze()
	_grant_survives_a_freeze_on_a_slow_link()
	_grant_hold_has_a_limit()
	_grants_add_up()
	_reset_clears_the_grant()
	_snap_waits_for_the_owner()
	_snap_retries_when_unanswered()
	_snap_after_an_accept()
	_snap_after_a_budget_refusal()
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


func _reset_on_respawn() -> void:
	# A burst drains the budget, then the hero dies and respawns far away (T08).
	var check := _new_check()
	for sequence: int in range(1, 31):
		check.check(OWNER, sequence, START, sequence * STEP * 0.25)
	var spent := check.budget_sec
	var spawn := Vector2(1500.0, 800.0)
	check.reset(spawn, 5.0)
	_expect_true("reset refills the budget (was %.2f s)" % spent, spent < MoveCheck.BUDGET_MAX_SEC and check.budget_sec == MoveCheck.BUDGET_MAX_SEC)
	_expect_true("reset moves the server's copy and keeps the last sequence", check.position == spawn and check.last_sequence == 30)
	_expect("a sequence from before the death is still old", check.check(OWNER, 30, spawn, 5.05), MoveCheck.Result.OLD_SEQUENCE)
	# Moves in flight at the death were dropped, so the first one back has a gap.
	_expect("the first move after respawn passes", check.check(OWNER, 36, spawn + Vector2(30, 0), 5.1), MoveCheck.Result.ACCEPTED)
	_expect("a move from where the hero died is too far", check.check(OWNER, 37, START, 5.15), MoveCheck.Result.TOO_FAR)


# --- grants (T14): a 240 px dash in 0.2 s is 60 px per send ----------------------

const DASH_STEP: Vector2 = Vector2(60.0, 0.0)


## Sends `count` dash steps from the check's position, starting at sequence
## `first` and time first x STEP. True when every one is accepted and drew on the grant.
func _dash(check: MoveCheck, first: int, count: int) -> bool:
	var all_ok := true
	for i: int in count:
		var sequence := first + i
		var result := check.check(OWNER, sequence, check.position + DASH_STEP, sequence * STEP)
		all_ok = all_ok and result == MoveCheck.Result.ACCEPTED and check.drew_grant
	return all_ok


func _dash_without_grant() -> void:
	var check := _new_check()
	_expect("a dash step without a grant is too far", check.check(OWNER, 1, START + DASH_STEP, STEP), MoveCheck.Result.TOO_FAR)


func _grant_lets_a_dash_through() -> void:
	var check := _new_check()
	check.grant(240.0, 1.2, 0.0)
	_expect_true("a 240 px grant lets a 4-send dash through", _dash(check, 1, 4))
	_expect_true("the dash ends 240 px on", check.position.is_equal_approx(START + DASH_STEP * 4.0))
	var walk := SPEED * MoveCheck.SPEED_TOLERANCE * STEP + MoveCheck.DISTANCE_SLACK
	_expect_true("each step drew only its excess over walking (%.2f px left)" % check.grant_px,
		is_equal_approx(check.grant_px, 240.0 - 4.0 * (60.0 - walk)))
	_expect("walking after the dash is fine", check.check(OWNER, 5, check.position + Vector2(10, 0), 0.25), MoveCheck.Result.ACCEPTED)
	_expect_true("walking does not draw on the grant", not check.drew_grant)


func _grant_gets_used_up() -> void:
	var check := _new_check()
	check.grant(50.0, 1.2, 0.0)
	_expect_true("a 50 px grant covers one dash step", _dash(check, 1, 1))
	_expect("the next dash step is too far", check.check(OWNER, 2, check.position + DASH_STEP, 0.1), MoveCheck.Result.TOO_FAR)


func _grant_expires() -> void:
	# Open 0.5 s: 10 sends, plus 20 for the round trip. The owner stands still
	# through all 30, on time.
	var check := _new_check()
	check.grant(240.0, 0.5, 0.0)
	for sequence: int in range(1, 31):
		check.check(OWNER, sequence, START, sequence * STEP)
	_expect("a dash step after the grant's time and its sends is too far",
		check.check(OWNER, 31, START + DASH_STEP, 31 * STEP), MoveCheck.Result.TOO_FAR)
	_expect_true("the expired grant is gone", check.grant_px == 0.0)
	check.grant(30.0, 3.0, 2.0)
	_expect_true("an expired leftover never comes back with a new grant", check.grant_px == 30.0)


func _grant_survives_a_freeze() -> void:
	# #92: the owner's game froze 1.5 s between the server's yes and the dash, so
	# no move came while the 1.2 s grant was open. The dash lands after it.
	var check := _new_check()
	check.grant(240.0, 1.2, 0.0)
	var all_ok := true
	for i: int in 4:
		var result := check.check(OWNER, 1 + i, check.position + DASH_STEP, 1.5 + i * STEP)
		all_ok = all_ok and result == MoveCheck.Result.ACCEPTED and check.drew_grant
	_expect_true("a dash after a 1.5 s freeze still draws on its grant", all_ok and check.rejected == 0)


func _grant_survives_a_freeze_on_a_slow_link() -> void:
	# 500 ms each way: the owner sent 20 more moves while the server's yes
	# traveled, then froze 1.5 s; 3 catch-up sends, then the dash's 4.
	var check := _new_check()
	check.grant(240.0, 1.2, 0.0)
	for sequence: int in range(1, 21):
		check.check(OWNER, sequence, START, sequence * STEP)
	var all_ok := true
	for i: int in 3:
		all_ok = all_ok and check.check(OWNER, 21 + i, START, 2.5 + i * STEP) == MoveCheck.Result.ACCEPTED
	for i: int in 4:
		var result := check.check(OWNER, 24 + i, check.position + DASH_STEP, 2.65 + i * STEP)
		all_ok = all_ok and result == MoveCheck.Result.ACCEPTED and check.drew_grant
	_expect_true("a dash after 20 sends in flight and a 1.5 s freeze still draws on its grant", all_ok and check.rejected == 0)


func _grant_hold_has_a_limit() -> void:
	var check := _new_check()
	check.grant(240.0, 1.2, 0.0)
	_expect("a dash step after the hold limit is too far",
		check.check(OWNER, 1, START + DASH_STEP, MoveCheck.GRANT_HOLD_MAX_SEC + 0.1), MoveCheck.Result.TOO_FAR)
	_expect_true("the held grant is gone", check.grant_px == 0.0)


func _grants_add_up() -> void:
	var check := _new_check()
	check.grant(100.0, 1.0, 0.0)
	check.grant(100.0, 2.0, 0.5)
	_expect_true("two grants add up", check.grant_px == 200.0)
	_expect("the later expiry wins: a dash step at 1.5 s", check.check(OWNER, 1, START + DASH_STEP, 1.5), MoveCheck.Result.ACCEPTED)
	_expect_true("that step drew on the grant", check.drew_grant)


func _reset_clears_the_grant() -> void:
	var check := _new_check()
	check.grant(240.0, 5.0, 0.0)
	check.reset(START, 0.1)
	_expect_true("reset clears the grant", check.grant_px == 0.0)
	_expect("a dash step after reset is too far", check.check(OWNER, 1, START + DASH_STEP, 0.15), MoveCheck.Result.TOO_FAR)


# --- snap-backs (#92) -------------------------------------------------------------

## Rejects one teleport per send from `first` at `start_sec`, 20 a second, for
## `seconds`; returns how many snap-backs snap_due() let through.
func _rejects_snaps(check: MoveCheck, first: int, start_sec: float, seconds: float) -> int:
	var snaps := 0
	var sends := roundi(seconds / STEP)
	for i: int in sends:
		var now := start_sec + i * STEP
		if check.check(OWNER, first + i, START + Vector2(500, 0), now) != MoveCheck.Result.ACCEPTED and check.snap_due(now):
			snaps += 1
	return snaps


func _snap_waits_for_the_owner() -> void:
	# A 600 ms round trip: 12 sends left the owner before the snap landed.
	var check := _new_check()
	var snaps := _rejects_snaps(check, 1, 0.05, 0.6)
	_expect_true("moves in flight get one snap-back, not one per 0.5 s (got %d)" % snaps, snaps == 1)


func _snap_retries_when_unanswered() -> void:
	var check := _new_check()
	# 2.6 s, so the retry at about 2.05 s or the send after it both fall inside.
	var snaps := _rejects_snaps(check, 1, 0.05, 2.6)
	_expect_true("a snap the owner never takes is sent again after 2 s (got %d)" % snaps, snaps == 2)


func _snap_after_an_accept() -> void:
	var check := _new_check()
	_expect_true("the first reject snaps", _rejects_snaps(check, 1, 0.05, 0.05) == 1)
	_expect("the owner took it: a move from the server's spot is fine",
		check.check(OWNER, 2, START + Vector2(10, 0), 0.6), MoveCheck.Result.ACCEPTED)
	_expect_true("a new reject 0.5 s after the last snap snaps again", _rejects_snaps(check, 3, 0.65, 0.05) == 1)


func _snap_after_a_budget_refusal() -> void:
	# #92 after a server stall: the burst drained the budget, so the owner's first
	# move from the snapped spot is refused over budget; it still took the snap.
	# The whole burst lands at t = 0: moves until one is over budget, then a teleport.
	var check := _new_check()
	var sequence := 0
	var drained := false
	while not drained and sequence < 40:
		sequence += 1
		drained = check.check(OWNER, sequence, START, 0.0) == MoveCheck.Result.OVER_BUDGET
	_expect_true("the stall's burst drains the budget", drained)
	_expect_true("the burst's teleport rejects and snaps", _rejects_snaps(check, sequence + 1, 0.0, 0.05) == 1)
	_expect("the owner's move from the snapped spot is over budget",
		check.check(OWNER, sequence + 2, START + Vector2(10, 0), 0.0), MoveCheck.Result.OVER_BUDGET)
	_expect_true("its next miss 0.5 s after the snap snaps again, not 2 s after",
		_rejects_snaps(check, sequence + 3, 0.55, 0.05) == 1)


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

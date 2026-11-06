extends SceneTree
## Tests for ShotCheck, the server's check on fire messages (card T08). Owner: Gabe.
## Run: godot --headless --path . --script res://tests/shot_check_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.

const ShotCheckScript: GDScript = preload("res://game/weapons/shot_check.gd")
const DelayQueueScript: GDScript = preload("res://game/net/delay_queue.gd")
const OWNER: int = 5
const INTERVAL: float = 0.3
const LIFE: int = 2
const AIM: Vector2 = Vector2(3.0, 4.0)
const TICK: float = 1.0 / 60.0
const MSEC: float = 0.001

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_wrong_owner()
	_old_shot_id()
	_dead_shooter()
	_earlier_life()
	_bad_direction()
	_normalizes_direction()
	_sustained_at_the_limit()
	_faster_stream_refused()
	_jitter_boundary()
	_late_shot_does_not_shorten_the_next()
	_double_rate_held_down()
	_honest_stream_through_lag()
	_honest_stream_through_a_server_stall()
	_double_rate_through_server_stalls()
	_stall_credit_is_capped()
	print("SHOT CHECK TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _new_check() -> ShotCheck:
	return ShotCheckScript.new(OWNER, INTERVAL)


## An honest shot from the owner, alive, in LIFE.
func _shoot(check: ShotCheck, shot_id: int, now: float) -> ShotCheck.Result:
	return check.check(OWNER, shot_id, LIFE, LIFE, true, AIM, now)


func _wrong_owner() -> void:
	var check := _new_check()
	_expect("wrong owner is dropped", check.check(9, 1, LIFE, LIFE, true, AIM, 0.0), ShotCheck.Result.WRONG_OWNER)
	_expect_true("wrong owner changes nothing", check.last_shot_id == 0 and check.refused == 0)


func _old_shot_id() -> void:
	var check := _new_check()
	_expect("first shot", _shoot(check, 4, 0.0), ShotCheck.Result.ACCEPTED)
	_expect("same shot id again", _shoot(check, 4, 1.0), ShotCheck.Result.OLD_SHOT)
	_expect("older shot id", _shoot(check, 3, 2.0), ShotCheck.Result.OLD_SHOT)
	_expect("a newer id is fine", _shoot(check, 5, 3.0), ShotCheck.Result.ACCEPTED)


func _dead_shooter() -> void:
	var check := _new_check()
	_expect("an eliminated shooter is dropped", check.check(OWNER, 1, LIFE, LIFE, false, AIM, 0.0), ShotCheck.Result.ELIMINATED)
	_expect_true("and not counted as a refusal", check.refused == 0)


func _earlier_life() -> void:
	var check := _new_check()
	_expect("a shot from an earlier life is dropped", check.check(OWNER, 1, LIFE - 1, LIFE, true, AIM, 0.0), ShotCheck.Result.OTHER_LIFE)
	_expect_true("and not counted as a refusal", check.refused == 0)
	_expect("and does not use up the rate", _shoot(check, 2, 0.0), ShotCheck.Result.ACCEPTED)


func _bad_direction() -> void:
	var check := _new_check()
	_expect("NaN direction is refused", check.check(OWNER, 1, LIFE, LIFE, true, Vector2(NAN, 1), 0.0), ShotCheck.Result.BAD_DIRECTION)
	_expect("INF direction is refused", check.check(OWNER, 2, LIFE, LIFE, true, Vector2(1, INF), 1.0), ShotCheck.Result.BAD_DIRECTION)
	_expect("zero direction is refused", check.check(OWNER, 3, LIFE, LIFE, true, Vector2.ZERO, 2.0), ShotCheck.Result.BAD_DIRECTION)
	_expect_true("bad directions count as refusals", check.refused == 3)


func _normalizes_direction() -> void:
	var check := _new_check()
	_shoot(check, 1, 0.0)
	_expect_true("the server normalizes the direction", check.direction.is_equal_approx(AIM.normalized()))


func _sustained_at_the_limit() -> void:
	var check := _new_check()
	var all_ok := true
	for i: int in range(400):
		all_ok = all_ok and _shoot(check, i + 1, i * INTERVAL * ShotCheck.RATE_SLACK) == ShotCheck.Result.ACCEPTED
	_expect_true("a sustained stream at 0.9 x interval passes", all_ok and check.refused == 0)


func _faster_stream_refused() -> void:
	var check := _new_check()
	for i: int in range(100):
		_shoot(check, i + 1, i * INTERVAL * 0.8)
	_expect_true("a sustained stream at 0.8 x interval is refused (saw %d)" % check.refused, check.refused > 0)


func _jitter_boundary() -> void:
	var slot := 10.0 + INTERVAL * ShotCheck.RATE_SLACK
	var inside := _new_check()
	_shoot(inside, 1, 10.0)
	_expect("1 ms inside the jitter allowance passes", _shoot(inside, 2, slot - ShotCheck.JITTER_SEC + MSEC), ShotCheck.Result.ACCEPTED)
	var beyond := _new_check()
	_shoot(beyond, 1, 10.0)
	_expect("1 ms beyond the jitter allowance is refused", _shoot(beyond, 2, slot - ShotCheck.JITTER_SEC - MSEC), ShotCheck.Result.TOO_SOON)


func _late_shot_does_not_shorten_the_next() -> void:
	# Fired every 0.3 s; the second arrives 200 ms late, the third on time.
	var check := _new_check()
	_expect("on time", _shoot(check, 1, 0.0), ShotCheck.Result.ACCEPTED)
	_expect("200 ms late", _shoot(check, 2, 0.5), ShotCheck.Result.ACCEPTED)
	_expect("the next on-time shot still passes", _shoot(check, 3, 0.6), ShotCheck.Result.ACCEPTED)
	_expect("and the one after", _shoot(check, 4, 0.9), ShotCheck.Result.ACCEPTED)


func _double_rate_held_down() -> void:
	var check := _new_check()
	var accepted := 0
	var seconds := 60.0
	var shots := int(seconds / (INTERVAL * 0.5))
	for i: int in range(shots):
		if _shoot(check, i + 1, i * INTERVAL * 0.5) == ShotCheck.Result.ACCEPTED:
			accepted += 1
	var limit := seconds / (INTERVAL * ShotCheck.RATE_SLACK)
	_expect_true("a x2 stream is held to 1/0.9 of the rate (%d accepted of %d, limit %.1f)" % [accepted, shots, limit],
		accepted <= ceili(limit) + 1 and accepted >= floori(limit) - 1)


func _honest_stream_through_lag() -> void:
	# A 60 Hz client holding fire for 60 s, through 150 ms lag + 50 ms jitter.
	var check := _new_check()
	var queue: DelayQueue = DelayQueueScript.new(150, 50, 11)
	var ticks_per_shot := roundi(INTERVAL / TICK)
	var shot_id := 0
	var received := 0
	for tick: int in range(60 * 61):
		var now := tick * TICK
		if tick % ticks_per_shot == 0 and tick < 60 * 60:
			shot_id += 1
			queue.push(shot_id, AIM, now, LIFE)
		while queue.is_due(now):
			check.check(OWNER, queue.peek_sequence(), queue.peek_life(), LIFE, true, queue.peek_position(), now)
			received += 1
			queue.pop()
	_expect_true("an honest 60 s stream through 150 ms lag and 50 ms jitter refuses nothing (%d shots, %d refused)" % [
		received, check.refused], received == shot_id and check.refused == 0)


# --- server stalls (J18): a frame that took STALL reads every message that came in
# during it at once, and the server passes how long that frame took ---------------

const STALL: float = 0.8


## When a shot sent at `sent` is read, if the server is stuck from `stall_at` for STALL.
func _read_at(sent: float, stall_at: float) -> float:
	return stall_at + STALL if sent >= stall_at and sent < stall_at + STALL else sent


func _honest_stream_through_a_server_stall() -> void:
	# Fired every 0.3 s for 10 s; the server is stuck from 3.0 to 3.8 s, so the
	# shots sent at 3.0, 3.3 and 3.6 s are all read at 3.8 s (John's Nov 3 failure).
	var check := _new_check()
	for i: int in range(34):
		var sent := i * INTERVAL
		var read := _read_at(sent, 3.0)
		_shoot_after(check, i + 1, read, STALL if read != sent else TICK)
	_expect_true("an honest stream through a 0.8 s server stall refuses nothing (%d refused)" % check.refused,
		check.refused == 0)


func _double_rate_through_server_stalls() -> void:
	# A x2 stream for 60 s, the server stuck for 0.8 s every 3 s: a stall buys a
	# cheater nothing, since its next slot is always ahead of the stall's start.
	var check := _new_check()
	var accepted := 0
	var seconds := 60.0
	var shots := int(seconds / (INTERVAL * 0.5))
	for i: int in range(shots):
		var sent := i * INTERVAL * 0.5
		var phase := fmod(sent, 3.0)
		var stalled := phase >= 2.0 and phase < 2.0 + STALL
		var read := sent - phase + 2.0 + STALL if stalled else sent
		if _shoot_after(check, i + 1, read, STALL if stalled else TICK) == ShotCheck.Result.ACCEPTED:
			accepted += 1
	var limit := seconds / (INTERVAL * ShotCheck.RATE_SLACK)
	_expect_true("a x2 stream through server stalls is still held to 1/0.9 of the rate (%d accepted of %d, limit %.1f)" % [
		accepted, shots, limit], accepted <= ceili(limit) + 1 and check.refused > 0)


func _stall_credit_is_capped() -> void:
	# After a pause, a 5 s stall and 30 shots read at once: the stall counts for
	# MAX_STALL_SEC at most.
	var check := _new_check()
	_shoot_after(check, 1, 0.0, TICK)
	var accepted := 0
	for i: int in range(30):
		if _shoot_after(check, i + 2, 20.0, 5.0) == ShotCheck.Result.ACCEPTED:
			accepted += 1
	var most := 1 + floori((ShotCheck.MAX_STALL_SEC + ShotCheck.JITTER_SEC) / (INTERVAL * ShotCheck.RATE_SLACK))
	_expect_true("a 5 s stall buys at most %d shots at once (%d accepted)" % [most, accepted], accepted <= most)


## An honest shot read at `now` in a server frame that took `stall` seconds.
func _shoot_after(check: ShotCheck, shot_id: int, now: float, stall: float) -> ShotCheck.Result:
	return check.check(OWNER, shot_id, LIFE, LIFE, true, AIM, now, stall)


func _expect(case_name: String, got: ShotCheck.Result, wanted: ShotCheck.Result) -> void:
	_count += 1
	if got == wanted:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s: got %s, wanted %s" % [case_name, ShotCheck.result_name(got), ShotCheck.result_name(wanted)])


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

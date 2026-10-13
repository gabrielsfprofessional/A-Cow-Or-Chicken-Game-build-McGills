extends SceneTree
## Tests for AbilityCheck, the server's check on ability requests (card T14). Owner: Gabe.
## Run: godot --headless --path . --script res://tests/ability_check_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.

const AbilityCheckScript: GDScript = preload("res://game/heroes/ability_check.gd")
const OWNER: int = 5
const COOLDOWN: float = 10.0
## Jet Dash's numbers (T18): 2 charges, 6 s each.
const CHARGED_COOLDOWN: float = 6.0
const LIFE: int = 2
const AIM: Vector2 = Vector2(3.0, 4.0)

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_wrong_owner()
	_other_life()
	_eliminated()
	_bad_direction()
	_normalizes_direction()
	_cooldown()
	_cooldown_kept_through_death()
	_honest_owner_never_early()
	_two_charges_back_to_back()
	_each_charge_returns_from_its_own_use()
	_charge_ready_in_sorted()
	_charges_kept_through_death()
	_honest_owner_with_charges()
	print("ABILITY CHECK TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _new_check() -> AbilityCheck:
	return AbilityCheckScript.new(OWNER, COOLDOWN)


## An honest request from the owner, alive, in LIFE.
func _ask(check: AbilityCheck, now: float, direction: Vector2 = AIM) -> AbilityCheck.Result:
	return check.check(OWNER, LIFE, LIFE, true, direction, now)


func _wrong_owner() -> void:
	var check := _new_check()
	_expect("wrong owner is dropped", check.check(9, LIFE, LIFE, true, AIM, 0.0), AbilityCheck.Result.WRONG_OWNER)
	_expect_true("wrong owner books no cooldown", check.ready_in_sec(0.0) == 0.0 and check.refused == 0)


func _other_life() -> void:
	var check := _new_check()
	_expect("a request from an older life", check.check(OWNER, LIFE - 1, LIFE, true, AIM, 0.0), AbilityCheck.Result.OTHER_LIFE)
	_expect_true("another life is not a logged refusal",
		check.refused == 0 and not AbilityCheck.is_refusal(AbilityCheck.Result.OTHER_LIFE))


func _eliminated() -> void:
	var check := _new_check()
	_expect("a request while eliminated", check.check(OWNER, LIFE, LIFE, false, AIM, 0.0), AbilityCheck.Result.ELIMINATED)
	_expect_true("eliminated is not a logged refusal and books nothing",
		check.refused == 0 and check.ready_in_sec(0.0) == 0.0 and not AbilityCheck.is_refusal(AbilityCheck.Result.ELIMINATED))


func _bad_direction() -> void:
	var check := _new_check()
	_expect("zero direction", _ask(check, 0.0, Vector2.ZERO), AbilityCheck.Result.BAD_DIRECTION)
	_expect("NaN direction", _ask(check, 0.0, Vector2(NAN, 1.0)), AbilityCheck.Result.BAD_DIRECTION)
	_expect("INF direction", _ask(check, 0.0, Vector2(INF, 0.0)), AbilityCheck.Result.BAD_DIRECTION)
	_expect_true("bad directions are refusals and book nothing",
		check.refused == 3 and check.ready_in_sec(0.0) == 0.0 and AbilityCheck.is_refusal(AbilityCheck.Result.BAD_DIRECTION))


func _normalizes_direction() -> void:
	var check := _new_check()
	_expect("first request", _ask(check, 0.0), AbilityCheck.Result.ACCEPTED)
	_expect_true("direction is normalized", check.direction.is_equal_approx(AIM.normalized()))


func _cooldown() -> void:
	var check := _new_check()
	_expect("first request", _ask(check, 100.0), AbilityCheck.Result.ACCEPTED)
	_expect_true("ready in 10 s", is_equal_approx(check.ready_in_sec(100.0), COOLDOWN))
	_expect("again at once", _ask(check, 100.0), AbilityCheck.Result.COOLING_DOWN)
	_expect("at 9.99 s", _ask(check, 109.99), AbilityCheck.Result.COOLING_DOWN)
	_expect_true("cooling down is a refusal and leaves the ready time",
		check.refused == 2 and AbilityCheck.is_refusal(AbilityCheck.Result.COOLING_DOWN)
		and is_equal_approx(check.ready_in_sec(105.0), 5.0))
	_expect("at exactly 10 s", _ask(check, 110.0), AbilityCheck.Result.ACCEPTED)
	_expect_true("the next cooldown counts from there", is_equal_approx(check.ready_in_sec(110.0), COOLDOWN))


func _cooldown_kept_through_death() -> void:
	var check := _new_check()
	_ask(check, 0.0)
	# Eliminated at 1 s, back at 5 s in the next life.
	_expect("next life at 5 s still cools down", check.check(OWNER, LIFE + 1, LIFE + 1, true, AIM, 5.0),
		AbilityCheck.Result.COOLING_DOWN)
	_expect("next life at 10 s is ready", check.check(OWNER, LIFE + 1, LIFE + 1, true, AIM, 10.0),
		AbilityCheck.Result.ACCEPTED)


## The owner starts its countdown when the answer arrives (one way later) and
## its request takes another one-way trip, so it lands after the ready time.
func _honest_owner_never_early() -> void:
	var check := _new_check()
	var now := 0.0
	var all_ok := true
	for i: int in 20:
		var one_way := 0.001 + 0.08 * float(i % 4)
		all_ok = all_ok and _ask(check, now) == AbilityCheck.Result.ACCEPTED
		var owner_ready := now + one_way + check.ready_in_sec(now)
		now = owner_ready + one_way
	_expect_true("an honest owner is never refused over 20 uses", all_ok and check.refused == 0)


# --- charges (T18) ------------------------------------------------------------------

func _new_charged_check() -> AbilityCheck:
	return AbilityCheckScript.new(OWNER, CHARGED_COOLDOWN, 2)


func _two_charges_back_to_back() -> void:
	var check := _new_charged_check()
	_expect_true("2 charges ready at the start", check.charges_left(0.0) == 2 and check.ready_in_sec(0.0) == 0.0)
	_expect("first charge", _ask(check, 0.0), AbilityCheck.Result.ACCEPTED)
	_expect_true("one left, so ready in 0 s", check.charges_left(0.0) == 1 and check.ready_in_sec(0.0) == 0.0)
	_expect("second charge at once", _ask(check, 0.0), AbilityCheck.Result.ACCEPTED)
	_expect_true("none left, ready in 6 s", check.charges_left(0.0) == 0
		and is_equal_approx(check.ready_in_sec(0.0), CHARGED_COOLDOWN))
	_expect("a third at once", _ask(check, 0.0), AbilityCheck.Result.COOLING_DOWN)
	_expect_true("the refusal booked nothing", check.refused == 1 and check.charges_left(0.0) == 0)


## Used at 0 s and 2 s: one comes back at 6 s, the other at 8 s.
func _each_charge_returns_from_its_own_use() -> void:
	var check := _new_charged_check()
	_ask(check, 0.0)
	_ask(check, 2.0)
	_expect("at 5.99 s", _ask(check, 5.99), AbilityCheck.Result.COOLING_DOWN)
	_expect_true("one back at exactly 6 s", check.charges_left(6.0) == 1)
	_expect_true("the other still 2 s away at 6 s", check.charges_left(7.99) == 1 and check.charges_left(8.0) == 2)
	_expect("at exactly 6 s", _ask(check, 6.0), AbilityCheck.Result.ACCEPTED)
	_expect_true("that use books 6 s from 6 s, the other still comes back at 8 s",
		check.charges_left(8.0) == 1 and check.charges_left(11.99) == 1 and check.charges_left(12.0) == 2)
	_expect("at 8 s", _ask(check, 8.0), AbilityCheck.Result.ACCEPTED)
	_expect_true("then none until 12 s", check.charges_left(11.99) == 0 and is_equal_approx(check.ready_in_sec(8.0), 4.0))


func _charge_ready_in_sorted() -> void:
	var check := _new_charged_check()
	var fresh := check.charge_ready_in(0.0)
	_expect_true("both ready: [0, 0]", fresh.size() == 2 and fresh[0] == 0.0 and fresh[1] == 0.0)
	_ask(check, 0.0)
	_ask(check, 2.0)
	var times := check.charge_ready_in(3.0)
	_expect_true("soonest first: [3, 5] at 3 s (got %s)" % times, times.size() == 2
		and is_equal_approx(times[0], 3.0) and is_equal_approx(times[1], 5.0))
	var later := check.charge_ready_in(7.0)
	_expect_true("a ready one reads 0: [0, 1] at 7 s (got %s)" % later, later[0] == 0.0 and is_equal_approx(later[1], 1.0))


func _charges_kept_through_death() -> void:
	var check := _new_charged_check()
	_ask(check, 0.0)
	_ask(check, 0.0)
	_expect("next life at 3 s still has none", check.check(OWNER, LIFE + 1, LIFE + 1, true, AIM, 3.0),
		AbilityCheck.Result.COOLING_DOWN)
	_expect("next life at 6 s has one", check.check(OWNER, LIFE + 1, LIFE + 1, true, AIM, 6.0),
		AbilityCheck.Result.ACCEPTED)


## The owner mirrors the charges from each answer (a one-way trip late) and asks
## only while it sees one ready; its request takes another one-way trip.
func _honest_owner_with_charges() -> void:
	var check := _new_charged_check()
	var owner_ready_at: Array[float] = [0.0, 0.0]
	var now := 0.0
	var all_ok := true
	for i: int in 30:
		var one_way := 0.001 + 0.08 * float(i % 4)
		var owner_now := maxf(now, owner_ready_at.min())
		var arrive := owner_now + one_way
		all_ok = all_ok and _ask(check, arrive) == AbilityCheck.Result.ACCEPTED
		var answer_at := arrive + one_way
		var times := check.charge_ready_in(arrive)
		owner_ready_at = [answer_at + times[0], answer_at + times[1]]
		now = answer_at
	_expect_true("an honest owner with 2 charges is never refused over 30 uses", all_ok and check.refused == 0)


func _expect(case_name: String, got: AbilityCheck.Result, wanted: AbilityCheck.Result) -> void:
	_count += 1
	if got == wanted:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s: got %s, wanted %s" % [case_name, AbilityCheck.result_name(got), AbilityCheck.result_name(wanted)])


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

extends SceneTree
## Tests for BotRules, a test bot's decisions (card T09). Owner: Gabe.
## Run: godot --headless --path . --script res://tests/bot_rules_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.

const BotRulesScript: GDScript = preload("res://game/net/bot_rules.gd")
const SELF_ID: int = 7
const AREA: Rect2 = Rect2(100.0, 100.0, 1000.0, 600.0)
const RANGE_PX: float = 900.0
const TICK: float = 1.0 / 60.0
## A hero's walking speed, px/s.
const SPEED: float = 300.0
## Far outside AREA: a bot here never reaches its walk point within these cases.
const FAR: Vector2 = Vector2(-5000.0, -5000.0)
const EPSILON: float = 0.000001

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_nearest_visible_wins()
	_ignores_itself()
	_ignores_eliminated()
	_ignores_blocked()
	_ignores_out_of_range()
	_no_target_holds_fire()
	_aim_error_within_limit()
	_bursts_and_pauses()
	_looks_every_quarter_second()
	_stuck_repicks()
	_progress_keeps_point()
	_arrival_repicks()
	_wander_time_repicks()
	_points_stay_in_area()
	_same_seed_same_choices()
	print("BOT RULES TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _new_rules(seed_value: int = 1) -> BotRules:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return BotRulesScript.new(rng, AREA)


func _seen(peer_id: int, at: Vector2, alive: bool = true, in_sight: bool = true) -> BotRules.Seen:
	return BotRules.Seen.new(peer_id, at, alive, in_sight)


# --- targeting -------------------------------------------------------------------

func _nearest_visible_wins() -> void:
	var rules := _new_rules()
	var from := Vector2(500.0, 400.0)
	var heroes: Array[BotRules.Seen] = [
		_seen(1, from + Vector2(300.0, 0.0)),
		_seen(2, from + Vector2(0.0, 200.0)),
		_seen(3, from + Vector2(-250.0, 0.0)),
	]
	_expect_int("the nearest visible hero wins", rules.pick_target(SELF_ID, from, heroes, RANGE_PX), 2)
	_expect_int("and becomes the target", rules.target, 2)


func _ignores_itself() -> void:
	var rules := _new_rules()
	var from := Vector2(500.0, 400.0)
	var heroes: Array[BotRules.Seen] = [_seen(SELF_ID, from), _seen(1, from + Vector2(400.0, 0.0))]
	_expect_int("itself is ignored, even at 0 px", rules.pick_target(SELF_ID, from, heroes, RANGE_PX), 1)
	var alone: Array[BotRules.Seen] = [_seen(SELF_ID, from)]
	_expect_int("alone, it has no target", rules.pick_target(SELF_ID, from, alone, RANGE_PX), 0)


func _ignores_eliminated() -> void:
	var rules := _new_rules()
	var from := Vector2(500.0, 400.0)
	var heroes: Array[BotRules.Seen] = [
		_seen(2, from + Vector2(100.0, 0.0), false),
		_seen(1, from + Vector2(300.0, 0.0)),
	]
	_expect_int("an eliminated hero is ignored", rules.pick_target(SELF_ID, from, heroes, RANGE_PX), 1)


func _ignores_blocked() -> void:
	var rules := _new_rules()
	var from := Vector2(500.0, 400.0)
	var heroes: Array[BotRules.Seen] = [
		_seen(2, from + Vector2(100.0, 0.0), true, false),
		_seen(1, from + Vector2(300.0, 0.0)),
	]
	_expect_int("a hero behind a wall is ignored", rules.pick_target(SELF_ID, from, heroes, RANGE_PX), 1)
	var blocked: Array[BotRules.Seen] = [
		_seen(2, from + Vector2(100.0, 0.0), true, false),
		_seen(1, from + Vector2(300.0, 0.0), true, false),
	]
	_expect_int("everyone behind walls: no target", rules.pick_target(SELF_ID, from, blocked, RANGE_PX), 0)


func _ignores_out_of_range() -> void:
	var rules := _new_rules()
	var from := Vector2(500.0, 400.0)
	var far: Array[BotRules.Seen] = [_seen(1, from + Vector2(RANGE_PX + 1.0, 0.0))]
	_expect_int("1 px out of range is ignored", rules.pick_target(SELF_ID, from, far, RANGE_PX), 0)
	var near: Array[BotRules.Seen] = [_seen(1, from + Vector2(RANGE_PX - 1.0, 0.0))]
	_expect_int("1 px inside range is picked", rules.pick_target(SELF_ID, from, near, RANGE_PX), 1)


func _no_target_holds_fire() -> void:
	var rules := _new_rules()
	var none: Array[BotRules.Seen] = []
	rules.pick_target(SELF_ID, Vector2.ZERO, none, RANGE_PX)
	var any_fire := false
	for i: int in range(120):
		any_fire = any_fire or rules.trigger(i * TICK)
	_expect_true("no target: holds fire", not any_fire)
	var one: Array[BotRules.Seen] = [_seen(1, Vector2(100.0, 0.0))]
	rules.pick_target(SELF_ID, Vector2.ZERO, one, RANGE_PX)
	_expect_true("a target: fires", rules.trigger(2.0))
	rules.pick_target(SELF_ID, Vector2.ZERO, none, RANGE_PX)
	_expect_true("target gone: holds fire at once", not rules.trigger(2.0 + TICK))


func _aim_error_within_limit() -> void:
	var rules := _new_rules()
	var from := Vector2(500.0, 400.0)
	var at := Vector2(800.0, 500.0)
	var heroes: Array[BotRules.Seen] = [_seen(1, at)]
	var true_angle := (at - from).angle()
	var worst := 0.0
	var left := false
	var right := false
	for i: int in range(400):
		rules.pick_target(SELF_ID, from, heroes, RANGE_PX)
		var error := rad_to_deg(angle_difference(true_angle, rules.aim_at(from, at).angle()))
		worst = maxf(worst, absf(error))
		left = left or error < -1.0
		right = right or error > 1.0
	_expect_true("aim error stays within 6 degrees (worst %.3f)" % worst, worst <= BotRules.AIM_ERROR_DEG + 0.0001)
	_expect_true("aim error varies both ways", left and right)


func _bursts_and_pauses() -> void:
	var rules := _new_rules(5)
	var one: Array[BotRules.Seen] = [_seen(1, Vector2(100.0, 0.0))]
	rules.pick_target(SELF_ID, Vector2.ZERO, one, RANGE_PX)
	var now := 0.0
	var firing := rules.trigger(now)
	_expect_true("a new target starts with a burst", firing)
	var since := now
	var bursts: Array[float] = []
	var pauses: Array[float] = []
	for i: int in range(3600):
		now += TICK
		var fire := rules.trigger(now)
		if fire == firing:
			continue
		if firing:
			bursts.append(now - since)
		else:
			pauses.append(now - since)
		since = now
		firing = fire
	var bursts_ok := bursts.size() >= 10
	for length: float in bursts:
		bursts_ok = bursts_ok and length >= BotRules.BURST_MIN_SEC - EPSILON and length <= BotRules.BURST_MAX_SEC + TICK + EPSILON
	var pauses_ok := pauses.size() >= 10
	for length: float in pauses:
		pauses_ok = pauses_ok and length >= BotRules.PAUSE_MIN_SEC - EPSILON and length <= BotRules.PAUSE_MAX_SEC + TICK + EPSILON
	_expect_true("over 60 s: %d bursts, all 0.5-1.5 s" % bursts.size(), bursts_ok)
	_expect_true("over 60 s: %d pauses, all 0.3-1 s" % pauses.size(), pauses_ok)


func _looks_every_quarter_second() -> void:
	var rules := _new_rules()
	rules.restart(10.0, FAR)
	_expect_true("restart looks at once", rules.is_look_due(10.0))
	_expect_true("not again 0.1 s later", not rules.is_look_due(10.1))
	_expect_true("not at 0.24 s", not rules.is_look_due(10.24))
	_expect_true("again at 0.25 s", rules.is_look_due(10.25))
	_expect_true("then not at 0.3 s", not rules.is_look_due(10.3))


# --- walking ---------------------------------------------------------------------

func _stuck_repicks() -> void:
	var rules := _new_rules()
	rules.restart(0.0, FAR)
	var first := rules.walk_point
	rules.walk(0.5, FAR)
	_expect_true("standing still 0.5 s: same point", rules.walk_point == first)
	var nudged := FAR + FAR.direction_to(first) * 5.0
	rules.walk(0.7, nudged)
	_expect_true("5 px closer is not progress", rules.walk_point == first)
	rules.walk(0.99, nudged)
	_expect_true("0.99 s without progress: same point", rules.walk_point == first)
	rules.walk(1.0, nudged)
	_expect_true("1 s without progress: stuck, a new point", rules.walk_point != first)


func _progress_keeps_point() -> void:
	var rules := _new_rules()
	var at := FAR
	rules.restart(0.0, at)
	var first := rules.walk_point
	var now := 0.0
	for i: int in range(180):
		now += TICK
		at += rules.walk(now, at) * SPEED * TICK
	_expect_true("walking at full speed for 3 s keeps the point", rules.walk_point == first)


func _arrival_repicks() -> void:
	var rules := _new_rules()
	rules.restart(0.0, FAR)
	var first := rules.walk_point
	rules.walk(0.1, first + Vector2(30.0, 0.0))
	_expect_true("30 px away is not there yet", rules.walk_point == first)
	rules.walk(0.2, first + Vector2(10.0, 0.0))
	_expect_true("10 px away is there: a new point", rules.walk_point != first)


func _wander_time_repicks() -> void:
	var times: Array[float] = []
	for seed_value: int in range(1, 21):
		var rules := _new_rules(seed_value)
		var at := FAR
		rules.restart(0.0, at)
		var first := rules.walk_point
		var now := 0.0
		var repicked_at := -1.0
		for i: int in range(int(9.0 / TICK)):
			now += TICK
			var direction := rules.walk(now, at)
			if rules.walk_point != first:
				repicked_at = now
				break
			at += direction * SPEED * TICK
		times.append(repicked_at)
	var in_window := true
	for t: float in times:
		in_window = in_window and t >= BotRules.WANDER_MIN_SEC - EPSILON and t <= BotRules.WANDER_MAX_SEC + TICK + EPSILON
	_expect_true("walking but never arriving, 20 seeds re-pick after 4-8 s (%.2f to %.2f s)" % [times.min(), times.max()], in_window)
	_expect_true("and not all at the same time", times.max() - times.min() > 1.0)


func _points_stay_in_area() -> void:
	var rules := _new_rules()
	var inside := true
	for i: int in range(1000):
		rules.restart(float(i), FAR)
		var p := rules.walk_point
		inside = inside and p.x >= AREA.position.x and p.x <= AREA.end.x and p.y >= AREA.position.y and p.y <= AREA.end.y
	_expect_true("1000 walk points all inside the area", inside)


# --- seeds -----------------------------------------------------------------------

func _same_seed_same_choices() -> void:
	var a := _session(42)
	_expect_true("the same seed makes the same choices (%d decisions)" % a.size(), a == _session(42))
	_expect_true("another seed makes other choices", a != _session(43))


## Ten seconds of a bot walking in AREA with two heroes in view: every walk
## point, target, aim and trigger it chose, in order.
func _session(seed_value: int) -> Array:
	var rules := _new_rules(seed_value)
	var choices: Array = []
	var at := Vector2(600.0, 400.0)
	var heroes: Array[BotRules.Seen] = [_seen(1, Vector2(800.0, 400.0)), _seen(2, Vector2(600.0, 150.0))]
	rules.restart(0.0, at)
	var now := 0.0
	for i: int in range(600):
		now += TICK
		at += rules.walk(now, at) * SPEED * TICK
		if rules.is_look_due(now):
			choices.append(rules.pick_target(SELF_ID, at, heroes, RANGE_PX))
			choices.append(rules.aim_at(at, heroes[0].position))
		choices.append(rules.trigger(now))
		choices.append(rules.walk_point)
	return choices


func _expect_int(case_name: String, got: int, wanted: int) -> void:
	_count += 1
	if got == wanted:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s: got %d, wanted %d" % [case_name, got, wanted])


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

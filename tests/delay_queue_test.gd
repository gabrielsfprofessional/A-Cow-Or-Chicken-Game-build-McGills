extends SceneTree
## Tests for DelayQueue, the --sim-lag/--sim-jitter network faker (card T07). Owner: Gabe.
## Run: godot --headless --path . --script res://tests/delay_queue_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.

const DelayQueueScript: GDScript = preload("res://game/net/delay_queue.gd")
const TICK: float = 1.0 / 60.0

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_never_reorders_and_delays_within_range()
	_inactive_without_flags()
	_full_queue_drops_oldest()
	print("DELAY QUEUE TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _never_reorders_and_delays_within_range() -> void:
	var queue: DelayQueue = DelayQueueScript.new(150, 50, 3)
	var sent_at: Dictionary[int, float] = {}
	var last_out := 0
	var in_order := true
	var min_delay := INF
	var max_delay := -INF
	var sequence := 0
	for tick: int in range(60 * 30):
		var now := tick * TICK
		if tick % 3 == 0:
			sequence += 1
			sent_at[sequence] = now
			queue.push(sequence, Vector2(sequence, 0), now)
		while queue.is_due(now):
			var out := queue.peek_sequence()
			in_order = in_order and out == last_out + 1
			last_out = out
			var delay := queue.peek_release() - sent_at[out]
			min_delay = minf(min_delay, delay)
			max_delay = maxf(max_delay, delay)
			queue.pop()
	_expect_true("messages come out in order, none lost", in_order and last_out > 500)
	_expect_true("every delay is 150 to 200 ms (saw %.1f to %.1f)" % [min_delay * 1000.0, max_delay * 1000.0],
		min_delay >= 0.15 - 0.0001 and max_delay <= 0.2 + 0.0001)
	_expect_true("jitter really varies the delay", max_delay - min_delay > 0.02)


func _inactive_without_flags() -> void:
	var queue: DelayQueue = DelayQueueScript.new(0, 0, 1)
	_expect_true("no lag and no jitter means inactive", not queue.is_active())


func _full_queue_drops_oldest() -> void:
	var queue: DelayQueue = DelayQueueScript.new(10000, 0, 1)
	for sequence: int in range(1, DelayQueue.CAPACITY + 2):
		queue.push(sequence, Vector2.ZERO, 0.0)
	_expect_true("a full queue keeps its size", queue.size() == DelayQueue.CAPACITY)
	_expect_true("and the oldest went first", queue.peek_sequence() == 2)


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

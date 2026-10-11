extends SceneTree
## Tests for RemoteTimeline, how other players' heroes are played back (card T07).
## Owner: Gabe. Run: godot --headless --path . --script res://tests/remote_timeline_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
##
## Simulates a 60 Hz client receiving 20 Hz updates through the same DelayQueue
## the --sim-lag and --sim-jitter flags use.

const TimelineScript: GDScript = preload("res://game/net/remote_timeline.gd")
const DelayQueueScript: GDScript = preload("res://game/net/delay_queue.gd")
const TICK: float = 1.0 / 60.0
const STEP: float = 0.05
## The sender's clock and ours never agree; the timeline must not care.
const CLOCK_SKEW: float = 1234.5
const RATE_SLACK: float = 0.0001

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_smooth_under_lag_and_jitter()
	_extrapolates_then_holds()
	_snaps_on_a_big_jump()
	_offset_settles()
	_reset_on_respawn()
	print("REMOTE TIMELINE TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


## Where the test sender is at its own time t: a 300 px/s circle.
func _path(t: float) -> Vector2:
	return Vector2(960, 540) + Vector2(cos(t), sin(t)) * 300.0


## Runs a sender for sender_seconds and a receiver at 60 Hz, through a delay queue.
## Calls on_tick(timeline, now, previous_playback) after every sample.
func _run(timeline: RemoteTimeline, queue: DelayQueue, ticks: int, last_sequence: int, on_tick: Callable) -> void:
	var sequence := 0
	for tick: int in range(ticks):
		var now := tick * TICK
		# The sender sends whenever its next 50 ms step has come, up to last_sequence.
		while sequence < last_sequence and (sequence + 1) * STEP <= now:
			sequence += 1
			queue.push(sequence, _path(sequence * STEP), now)
		while queue.is_due(now):
			timeline.push(queue.peek_sequence(), queue.peek_position(), now)
			queue.pop()
		var before := timeline.playback_sec
		timeline.sample(now)
		on_tick.call(timeline, now, before)


func _smooth_under_lag_and_jitter() -> void:
	var timeline: RemoteTimeline = TimelineScript.new()
	var queue: DelayQueue = DelayQueueScript.new(150, 50, 7)
	var state := {"backward": false, "min_rate": INF, "max_rate": -INF, "started": false}
	_run(timeline, queue, 60 * 62, 20 * 62, func(t: RemoteTimeline, now: float, before: float) -> void:
		if not state.started:
			# The first sample after the first update places playback; measure after.
			state.started = t.playback_sec != 0.0
			return
		if t.playback_sec < before:
			state.backward = true
		var rate := (t.playback_sec - before) / TICK
		state.min_rate = minf(state.min_rate, rate)
		state.max_rate = maxf(state.max_rate, rate)
	)
	_expect_true("playback never goes backward", not state.backward)
	_expect_true("playback rate stays within +/-10%% (saw %.3f to %.3f)" % [state.min_rate, state.max_rate],
		state.min_rate >= 0.9 - RATE_SLACK and state.max_rate <= 1.1 + RATE_SLACK)
	_expect_true("no underruns over 60 s at 150 ms lag and 50 ms jitter (saw %d)" % timeline.underruns, timeline.underruns == 0)


func _extrapolates_then_holds() -> void:
	var timeline: RemoteTimeline = TimelineScript.new()
	var queue: DelayQueue = DelayQueueScript.new(0, 0, 1)
	# Straight line at 300 px/s for 2 s, then the updates stop.
	var sequence := 0
	var positions: Array[Vector2] = []
	for tick: int in range(60 * 4):
		var now := tick * TICK
		while sequence < 40 and (sequence + 1) * STEP <= now:
			sequence += 1
			timeline.push(sequence, Vector2(sequence * STEP * 300.0, 0), now)
		positions.append(timeline.sample(now))
	var last_sent := 40 * STEP * 300.0
	var hold := positions[positions.size() - 1]
	_expect_true("extrapolates past the last update", hold.x > last_sent + 1.0)
	_expect_near("extrapolation stops at 100 ms (%.1f px past)" % (hold.x - last_sent), hold.x, last_sent + 300.0 * 0.1, 0.5)
	_expect_true("then holds still", positions[positions.size() - 30] == hold)
	_expect_true("running dry counts one underrun (saw %d)" % timeline.underruns, timeline.underruns == 1)


func _snaps_on_a_big_jump() -> void:
	var timeline: RemoteTimeline = TimelineScript.new()
	for sequence: int in range(1, 21):
		timeline.push(sequence, Vector2(100 + sequence, 100), sequence * STEP)
		timeline.sample(sequence * STEP)
	timeline.take_snap()
	var far := Vector2(900, 700)
	timeline.push(21, far, 21 * STEP)
	_expect_true("a jump beyond the snap distance snaps", timeline.take_snap())
	_expect_true("the hero is drawn at the new spot at once", timeline.sample(21 * STEP + TICK) == far)
	timeline.push(22, far + Vector2(RemoteTimeline.SNAP_DISTANCE - 1.0, 0), 22 * STEP)
	_expect_true("a short step does not snap", not timeline.take_snap())


func _offset_settles() -> void:
	var timeline: RemoteTimeline = TimelineScript.new()
	# 5 s at 50 ms lag, then the lag steps up to 150 ms and stays there for 5 s.
	for sequence: int in range(1, 201):
		var lag := 0.05 if sequence <= 100 else 0.15
		timeline.push(sequence, _path(sequence * STEP), sequence * STEP + lag + CLOCK_SKEW)
	_expect_near("the clock offset settles under steady lag", timeline.offset_sec, CLOCK_SKEW + 0.15, 0.005)


## A hero plays for 5 s, is eliminated for 4 s (no sends, no samples), then
## respawns at SPAWN and plays 10 s more, through 150 ms lag and 50 ms jitter.
## Returns the timeline and what was seen after the respawn.
func _respawn_run(use_reset: bool) -> Dictionary:
	const SPAWN: Vector2 = Vector2(400, 300)
	const DEATH_SEQUENCE: int = 100
	## Moves in flight at the death are dropped, so the owner's sequence skips a few.
	const RESUME_SEQUENCE: int = 104
	var timeline: RemoteTimeline = TimelineScript.new()
	var queue: DelayQueue = DelayQueueScript.new(150, 50, 5)
	var seen := {"first": Vector2.INF, "backward": false, "old_ignored": true, "underruns_before": 0}
	var sequence := 0
	var next_send := STEP
	var eliminated := false
	var respawned := false
	for tick: int in range(60 * 20):
		var now := tick * TICK
		if not eliminated and not respawned and sequence == DEATH_SEQUENCE:
			eliminated = true
			seen.underruns_before = timeline.underruns
		if eliminated and now >= 9.0:
			respawned = true
			eliminated = false
			sequence = RESUME_SEQUENCE - 1
			next_send = now
			if use_reset:
				timeline.reset(SPAWN)
				seen.first = timeline.sample(now)
				timeline.push(DEATH_SEQUENCE, _path(0.0), now)
				seen.old_ignored = timeline.buffer_depth_sec() == 0.0
		# The sender: one update per 50 ms while alive. Its sequence stands still
		# while eliminated, so sequence x 50 ms falls 4 s behind real time.
		while not eliminated and now >= next_send:
			sequence += 1
			next_send += STEP
			var at := _path(sequence * STEP) if not respawned else SPAWN + Vector2(sequence - RESUME_SEQUENCE, 0) * 5.0
			queue.push(sequence, at, now)
		while queue.is_due(now):
			timeline.push(queue.peek_sequence(), queue.peek_position(), now)
			queue.pop()
		if eliminated:
			continue
		var before := timeline.playback_sec
		timeline.sample(now)
		if respawned and timeline.playback_sec < before and before != 0.0:
			seen.backward = true
	seen.timeline = timeline
	return seen


func _reset_on_respawn() -> void:
	var seen := _respawn_run(true)
	var timeline: RemoteTimeline = seen.timeline
	_expect_true("after reset the hero is drawn at the spawn point", seen.first == Vector2(400, 300))
	_expect_true("an update from before the death is ignored after reset", seen.old_ignored)
	_expect_true("a death and respawn add no underruns (before %d, after %d)" % [seen.underruns_before, timeline.underruns],
		seen.underruns_before == 0 and timeline.underruns == 0)
	_expect_true("playback never goes backward after the respawn", not seen.backward)
	var without := _respawn_run(false)
	var stale: RemoteTimeline = without.timeline
	_expect_true("without reset the same respawn does underrun (saw %d)" % stale.underruns, stale.underruns > 0)


func _expect_near(case_name: String, got: float, wanted: float, slack: float) -> void:
	_expect_true("%s: %.4f vs %.4f" % [case_name, got, wanted], absf(got - wanted) <= slack)


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

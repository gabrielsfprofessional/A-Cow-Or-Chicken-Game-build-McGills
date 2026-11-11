extends SceneTree
## Tests for card T25: damage numbers follow Settings.ui_scale, a headless run plays no
## sound, every hit and elimination shows a puff big enough to see, and an elimination
## always gets its own sound.
## Owner: John (game/ui). Run from the repo folder with APPDATA pointed at a temp folder:
##   godot --headless --path . --script res://game/ui/tools/test_hit_feedback.gd
## Exits with code 1 when any case is wrong. Autoloads exist only at run time, so the
## script reaches them by path and loads HitFeedback with load().

const ME: int = 2
const OTHER: int = 3
## The smallest puff John could see in a game window (the Nov 6 check missed 6 px for 0.35 s).
const MIN_PUFF_PX: float = 10.0
const MIN_PUFF_SEC: float = 0.45
const MIN_PUFF_COUNT: int = 8

var _failures: int = 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		print("FAIL ", what)
		_failures += 1


func _initialize() -> void:
	await process_frame
	var settings: Node = root.get_node(^"/root/Settings")
	var events: Node = root.get_node(^"/root/Events")
	var feedback_script: GDScript = load("res://game/ui/hit_feedback.gd")
	# A stand-in world: the current scene with Heroes/<peer id>, as in a match.
	var world: Node2D = Node2D.new()
	var heroes: Node = Node.new()
	heroes.name = &"Heroes"
	world.add_child(heroes)
	var other_hero: Node2D = Node2D.new()
	other_hero.name = StringName(str(OTHER))
	heroes.add_child(other_hero)
	root.add_child(world)
	current_scene = world
	var feedback: Control = feedback_script.new()
	feedback.own_peer_id = ME
	root.add_child(feedback)
	await process_frame
	var middle: Vector2 = feedback.get_viewport_rect().size * 0.5
	other_hero.global_position = middle + Vector2(150.0, 40.0)

	var base: int = feedback.number_font_size
	var expected: Dictionary = {1.0: 26, 1.25: 33, 1.5: 39}
	_check(base == 26, "number_font_size is 26 at 100%")
	for scale: float in [1.0, 1.25, 1.5, 1.0]:
		settings.ui_scale = scale
		settings.ui_scale_changed.emit(scale)
		var want: int = expected[scale]
		var label: Label = feedback._numbers[0]
		var got: int = label.get_theme_font_size(&"font_size")
		_check(got == want, "numbers measure %d px at UI scale %d%% (got %d)" % [want, roundi(scale * 100.0), got])

	# Nothing may play when headless: no voice may be busy after a hit.
	feedback.active = true
	feedback._play(feedback.HIT_SOUND, 0.0, middle)
	_check(_playing(feedback) == 0, "headless run starts no sound")
	_reset(feedback)

	# The puff must be big and long enough to see.
	var first_puff: CPUParticles2D = feedback._puffs[0]
	_check(first_puff.scale_amount_min >= MIN_PUFF_PX,
		"puff pieces are at least %d px (got %d)" % [roundi(MIN_PUFF_PX), roundi(first_puff.scale_amount_min)])
	_check(first_puff.lifetime >= MIN_PUFF_SEC,
		"puff lasts at least %.2f s (got %.2f)" % [MIN_PUFF_SEC, first_puff.lifetime])
	_check(first_puff.amount >= MIN_PUFF_COUNT,
		"puff has at least %d pieces (got %d)" % [MIN_PUFF_COUNT, first_puff.amount])

	# A hit absorbed by spawn protection (amount 0) shows and plays nothing.
	events.hero_damaged.emit(OTHER, ME, 0, other_hero.global_position)
	_check(_numbers_shown(feedback) == 0 and _puffs_going(feedback).is_empty() and _asked(feedback).is_empty(),
		"a hit of 0 shows no number, no puff and asks for no sound")

	# A hit on another hero: its number, a puff at the hit and the hit sound.
	events.hero_damaged.emit(OTHER, ME, 20, other_hero.global_position)
	var going: Array[CPUParticles2D] = _puffs_going(feedback)
	_check(_numbers_shown(feedback) == 1, "a hit on another hero shows its number")
	_check(going.size() == 1 and going[0].position.is_equal_approx(other_hero.global_position),
		"a hit on another hero starts a puff at the hit")
	_check(going.size() == 1 and is_equal_approx(going[0].scale.x, 1.0), "a hit's puff is normal size")
	_check(_asked(feedback) == [feedback.HIT_SOUND], "a hit asks for the hit sound")

	# The elimination that follows the killing hit: a bigger puff at the hero, and the
	# elimination sound takes the killing hit's voice so the two never blur into one.
	events.hero_eliminated.emit(OTHER, ME)
	going = _puffs_going(feedback)
	_check(going.size() == 2 and going[1].position.is_equal_approx(other_hero.global_position),
		"another hero's elimination starts a puff at that hero (the hero is found)")
	_check(going.size() == 2 and going[1].scale.x > 1.0, "an elimination's puff is bigger than a hit's")
	_check(_asked(feedback) == [feedback.ELIMINATED_SOUND],
		"the elimination sound replaces the killing hit's sound")
	var voice: AudioStreamPlayer = _voice_with(feedback, feedback.ELIMINATED_SOUND)
	_check(voice != null and voice.pitch_scale < 0.9,
		"the elimination sound is pitched lower than a hit, so it stands out")
	_reset(feedback)

	# Every voice busy with older hits: one more hit is dropped, an elimination still plays.
	for i: int in feedback.max_voices:
		events.hero_damaged.emit(OTHER, ME, 5, other_hero.global_position)
	_check(_asked(feedback).size() == feedback.max_voices, "every voice is busy with a hit")
	for i: int in feedback._voice_started_msec.size():
		feedback._voice_started_msec[i] -= 1000 + i
	events.hero_damaged.emit(OTHER, ME, 5, other_hero.global_position)
	_check(not _asked(feedback).has(feedback.ELIMINATED_SOUND) and _asked(feedback).size() == feedback.max_voices,
		"with every voice busy one more hit sound is dropped")
	events.hero_eliminated.emit(OTHER, ME)
	_check(_asked(feedback).count(feedback.ELIMINATED_SOUND) == 1,
		"with every voice busy the elimination sound still plays")
	_reset(feedback)

	# My own elimination, with my hero not in the world: puff and sound at the screen middle.
	events.hero_eliminated.emit(ME, OTHER)
	going = _puffs_going(feedback)
	_check(going.size() == 1 and going[0].position.is_equal_approx(middle),
		"my own elimination starts a puff at the middle of the screen")
	_check(_asked(feedback) == [feedback.ELIMINATED_SOUND], "my own elimination asks for the elimination sound")
	_reset(feedback)

	# A hero that is not in the world and is not me: nothing to point at, so nothing.
	events.hero_eliminated.emit(99, ME)
	_check(_puffs_going(feedback).is_empty() and _asked(feedback).is_empty(),
		"an elimination of a hero that is not in the world shows and plays nothing")

	# Too far away to hear.
	var far: Vector2 = middle + Vector2(feedback.get_viewport_rect().size.x * feedback.silent_beyond_screens + 10.0, 0.0)
	events.hero_damaged.emit(OTHER, ME, 20, far)
	_check(_asked(feedback).is_empty(), "a hit beyond the silent distance asks for no sound")

	settings.ui_scale = 1.0
	current_scene = null
	feedback.queue_free()
	world.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


## How many voices are really playing (always 0 on a headless run).
func _playing(feedback: Control) -> int:
	var playing: int = 0
	for voice: AudioStreamPlayer in feedback._voices:
		if voice.playing:
			playing += 1
	return playing


## The sounds the busy voices were asked to play, in voice order.
func _asked(feedback: Control) -> Array[AudioStream]:
	var asked: Array[AudioStream] = []
	var now: int = Time.get_ticks_msec()
	for i: int in feedback._voices.size():
		if feedback._voice_ends_msec[i] > now:
			var voice: AudioStreamPlayer = feedback._voices[i]
			asked.append(voice.stream)
	return asked


## The busy voice asked to play stream, or null.
func _voice_with(feedback: Control, stream: AudioStream) -> AudioStreamPlayer:
	var now: int = Time.get_ticks_msec()
	for i: int in feedback._voices.size():
		var voice: AudioStreamPlayer = feedback._voices[i]
		if feedback._voice_ends_msec[i] > now and voice.stream == stream:
			return voice
	return null


func _numbers_shown(feedback: Control) -> int:
	var shown: int = 0
	for label: Label in feedback._numbers:
		if label.visible:
			shown += 1
	return shown


## The puffs that are going, in the order they were started.
func _puffs_going(feedback: Control) -> Array[CPUParticles2D]:
	var going: Array[CPUParticles2D] = []
	for puff: CPUParticles2D in feedback._puffs:
		if puff.emitting:
			going.append(puff)
	return going


## Back to a quiet start: no number, no puff, every voice free.
func _reset(feedback: Control) -> void:
	for label: Label in feedback._numbers:
		label.visible = false
	for puff: CPUParticles2D in feedback._puffs:
		puff.emitting = false
	for i: int in feedback._voice_ends_msec.size():
		feedback._voice_ends_msec[i] = 0
		feedback._voice_started_msec[i] = 0
	feedback._next_puff = 0

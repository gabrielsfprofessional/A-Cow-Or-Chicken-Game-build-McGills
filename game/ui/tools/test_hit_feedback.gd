extends SceneTree
## Tests for card T25: damage numbers follow Settings.ui_scale and a headless run plays no sound.
## Owner: John (game/ui). Run from the repo folder with APPDATA pointed at a temp folder:
##   godot --headless --path . --script res://game/ui/tools/test_hit_feedback.gd
## Exits with code 1 when any case is wrong. Autoloads exist only at run time, so the
## script reaches them by path and loads HitFeedback with load().

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
	var feedback_script: GDScript = load("res://game/ui/hit_feedback.gd")
	var feedback: Control = feedback_script.new()
	root.add_child(feedback)
	await process_frame
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
	# Nothing may play when headless: no voice may be busy after a hit and an elimination.
	feedback.active = true
	feedback._play(feedback.HIT_SOUND, 0.0, Vector2.ZERO)
	var playing: int = 0
	for voice: AudioStreamPlayer in feedback._voices:
		if voice.playing:
			playing += 1
	_check(playing == 0, "headless run starts no sound")
	settings.ui_scale = 1.0
	feedback.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)

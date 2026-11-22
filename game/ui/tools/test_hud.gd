extends SceneTree
## Tests for card T17 part 2: the HUD's team scores, clock, your team and winner banner.
## Owner: John (game/ui). Run from the repo folder with APPDATA pointed at a temp folder
## so the real settings are never touched:
##   godot --headless --path . --script res://game/ui/tools/test_hud.gd
## It sends fake Events and reads what the Hud shows. Exits with code 1 when any case
## is wrong. Autoloads exist only at run time, so the script reaches them by path and
## loads the scene with load(), after they exist.

const SCENE_PATH: String = "res://game/ui/hud.tscn"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const ME: int = 7
const OTHER: int = 9
const THEME_PATH: String = "res://game/ui/main_theme.tres"
## The banner's text size at 1080p (main_theme.tres, BannerLabel).
const BANNER_PX: int = 56
## Every HUD label that is drawn in the theme's default size.
const HUD_LABELS: Array[String] = [
	"Corner/Stack/HealthRow/HealthText", "Corner/Stack/QBox/Row/Key", "Corner/Stack/QBox/Row/Name",
	"Corner/Stack/QBox/Row/State", "BackIn", "MatchBar/Row/BlueScore", "MatchBar/Row/Clock",
	"MatchBar/Row/OrangeScore", "MatchBar/MyTeam",
]

var _failures: int = 0
var _events: Node = null


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		print("FAIL ", what)
		_failures += 1


## A Hud in its own 1280x720 viewport (a headless window ignores its size), listening
## to Events the way Overlay makes it.
func _hud(listen: bool = true) -> Control:
	var hud: Control = (load(SCENE_PATH) as PackedScene).instantiate()
	var viewport: SubViewport = SubViewport.new()
	viewport.size = WINDOW_SIZE
	root.add_child(viewport)
	viewport.add_child(hud)
	if listen:
		hud.listen()
	return hud


func _free(hud: Control) -> void:
	hud.get_parent().queue_free()
	await process_frame


func _text(hud: Control, path: String) -> String:
	return (hud.get_node(path) as Label).text


func _color(hud: Control, path: String) -> Color:
	return (hud.get_node(path) as Label).get_theme_color(&"font_color")


func _shown(hud: Control, path: String) -> bool:
	return (hud.get_node(path) as CanvasItem).visible


func _initialize() -> void:
	await process_frame
	_events = root.get_node(^"/root/Events")
	var settings: Node = root.get_node(^"/root/Settings")
	settings.ui_scale = 1.0

	# Nothing is shown before the first event.
	var hud: Control = _hud()
	await process_frame
	_check(not _shown(hud, ^"MatchBar") and not _shown(hud, ^"Banner"), "no match bar or banner before any event")

	# Scores.
	_events.team_score_changed.emit(0, 3)
	_events.team_score_changed.emit(1, 12)
	_check(_shown(hud, ^"MatchBar"), "the match bar shows once an event arrives")
	_check(_text(hud, ^"MatchBar/Row/BlueScore") == "Blue 3", "Blue score reads 'Blue 3' (got '%s')" % _text(hud, ^"MatchBar/Row/BlueScore"))
	_check(_text(hud, ^"MatchBar/Row/OrangeScore") == "Orange 12", "Orange score reads 'Orange 12' (got '%s')" % _text(hud, ^"MatchBar/Row/OrangeScore"))
	_events.team_score_changed.emit(5, 99)
	_check(_text(hud, ^"MatchBar/Row/BlueScore") == "Blue 3" and _text(hud, ^"MatchBar/Row/OrangeScore") == "Orange 12", "a score for team 5 changes nothing")

	# Clock.
	var clock_sec: Array[int] = [1200, 59, 0, 61]
	var clock_text: Array[String] = ["20:00", "00:59", "00:00", "01:01"]
	for i: int in clock_sec.size():
		_events.match_clock_changed.emit(clock_sec[i])
		_check(_text(hud, ^"MatchBar/Row/Clock") == clock_text[i], "clock %d s shows %s (got '%s')" % [clock_sec[i], clock_text[i], _text(hud, ^"MatchBar/Row/Clock")])

	# Your team: only your own peer id counts, and a switch is followed.
	hud.set_own_peer(ME)
	_events.team_assigned.emit(OTHER, 1)
	_check(not _shown(hud, ^"MatchBar/MyTeam"), "another peer's team_assigned does not set my team")
	_events.team_assigned.emit(ME, 0)
	_check(_text(hud, ^"MatchBar/MyTeam") == "You are on Blue" and _shown(hud, ^"MatchBar/MyTeam"), "my team_assigned shows 'You are on Blue'")
	_check(_color(hud, ^"MatchBar/MyTeam").is_equal_approx(hud.blue_color), "'You are on Blue' is drawn in the Blue color")
	_events.team_assigned.emit(ME, 1)
	_check(_text(hud, ^"MatchBar/MyTeam") == "You are on Orange", "a second team_assigned for me (balance switch) shows Orange")
	_check(_color(hud, ^"MatchBar/MyTeam").is_equal_approx(hud.orange_color), "after the switch the line is drawn in the Orange color")
	_events.team_score_changed.emit(0, 3)
	_check(_color(hud, ^"MatchBar/MyTeam").is_equal_approx(hud.orange_color), "a score event leaves my team's color alone")
	_events.team_assigned.emit(OTHER, 0)
	_check(_text(hud, ^"MatchBar/MyTeam") == "You are on Orange", "another peer's later team_assigned leaves my team alone")
	_events.team_assigned.emit(ME, 7)
	_check(_text(hud, ^"MatchBar/MyTeam") == "You are on Orange", "team 7 is ignored")

	# Banner: from match_ended until match_started.
	_check(not _shown(hud, ^"Banner"), "no banner while the match runs")
	_events.match_ended.emit(0)
	_check(_shown(hud, ^"Banner") and _text(hud, ^"Banner") == "Blue wins!", "match_ended(0) shows 'Blue wins!'")
	_check(_color(hud, ^"Banner").is_equal_approx(hud.blue_color), "'Blue wins!' is drawn in the Blue color")
	_events.match_clock_changed.emit(0)
	_events.team_score_changed.emit(0, 5)
	_check(_shown(hud, ^"Banner"), "the banner stays through clock and score events")
	_events.match_ended.emit(1)
	_check(_text(hud, ^"Banner") == "Orange wins!", "match_ended(1) shows 'Orange wins!'")
	_check(_color(hud, ^"Banner").is_equal_approx(hud.orange_color), "'Orange wins!' is drawn in the Orange color")
	_events.match_ended.emit(-1)
	_check(_text(hud, ^"Banner") == "Draw", "match_ended(-1) shows 'Draw'")
	_check(_color(hud, ^"Banner").is_equal_approx(hud.draw_color), "'Draw' is drawn in the draw color")
	_events.match_started.emit(&"arena")
	_check(not _shown(hud, ^"Banner"), "match_started hides the banner")
	_events.match_ended.emit(0)
	_check(_color(hud, ^"Banner").is_equal_approx(hud.blue_color), "the next match's 'Blue wins!' is Blue again")
	_events.match_started.emit(&"arena")

	# Everything clears when I leave a match, and a new match starts from zero.
	_events.match_ended.emit(0)
	hud.clear_match()
	_check(not _shown(hud, ^"MatchBar") and not _shown(hud, ^"Banner") and not _shown(hud, ^"MatchBar/MyTeam"), "leaving a match hides bar, team and banner")
	_events.team_score_changed.emit(1, 1)
	_check(_text(hud, ^"MatchBar/Row/BlueScore") == "Blue 0" and _text(hud, ^"MatchBar/Row/OrangeScore") == "Orange 1", "after leaving, the old Blue score is gone")
	_check(_text(hud, ^"MatchBar/Row/Clock") == "--:--", "after leaving, the clock is blank until a new value comes")
	await _free(hud)

	# Values sent while the Hud is still hidden (the late-join replay) show when it opens,
	# even a team that arrives before the Hud knows which peer is me.
	hud = _hud()
	hud.visible = false
	_events.match_started.emit(&"arena")
	_events.team_assigned.emit(ME, 1)
	_events.team_score_changed.emit(0, 2)
	_events.team_score_changed.emit(1, 4)
	_events.match_clock_changed.emit(754)
	hud.set_own_peer(ME)
	hud.visible = true
	await process_frame
	_check(_text(hud, ^"MatchBar/Row/BlueScore") == "Blue 2" and _text(hud, ^"MatchBar/Row/OrangeScore") == "Orange 4", "replayed scores show when the HUD opens")
	_check(_text(hud, ^"MatchBar/Row/Clock") == "12:34", "the replayed clock shows when the HUD opens")
	_check(_text(hud, ^"MatchBar/MyTeam") == "You are on Orange", "a team replayed before my peer id was known shows")
	await _free(hud)

	# A Hud that never called listen() ignores Events (headless runs do not listen).
	hud = _hud(false)
	_events.team_score_changed.emit(0, 8)
	_check(not _shown(hud, ^"MatchBar"), "a Hud that does not listen shows nothing")
	await _free(hud)

	# Text sizes come from main_theme.tres (#90): no label sets its own, the HUD's text is
	# the theme's default size and the banner is the theme's BannerLabel.
	hud = _hud()
	await process_frame
	var theme: Theme = load(THEME_PATH) as Theme
	var own_sizes: Array[String] = []
	var wrong_sizes: Array[String] = []
	for path: String in HUD_LABELS:
		var label: Label = hud.get_node(path) as Label
		if label.has_theme_font_size_override(&"font_size"):
			own_sizes.append(path)
		if label.get_theme_font_size(&"font_size") != theme.default_font_size:
			wrong_sizes.append(path)
	var banner: Label = hud.get_node(^"Banner") as Label
	if banner.has_theme_font_size_override(&"font_size"):
		own_sizes.append("Banner")
	_check(own_sizes.is_empty(), "no HUD label sets its own text size (found: %s)" % ", ".join(own_sizes))
	_check(wrong_sizes.is_empty(), "the HUD's text is the theme's default size, %d px (not: %s)" % [theme.default_font_size, ", ".join(wrong_sizes)])
	_check(banner.get_theme_font_size(&"font_size") == theme.get_font_size(&"font_size", &"BannerLabel") and banner.get_theme_font_size(&"font_size") == BANNER_PX,
		"the banner is the theme's BannerLabel, %d px (got %d)" % [BANNER_PX, banner.get_theme_font_size(&"font_size")])
	await _free(hud)

	# A headless run (this one, the server, test bots) builds no HUD and does no work.
	var overlay: Node = root.get_node(^"/root/Overlay")
	_check(overlay.get_child_count() == 0, "on a headless run Overlay builds no HUD or hit feedback (%d children)" % overlay.get_child_count())
	_check(not overlay.is_processing(), "on a headless run Overlay does no work each frame")

	# Layout with everything visible, at each UI scale in a 1280x720 window.
	for scale: float in [1.0, 1.25, 1.5]:
		settings.ui_scale = scale
		hud = _hud()
		hud.set_own_peer(ME)
		_events.team_assigned.emit(ME, 1)
		_events.team_score_changed.emit(0, 12)
		_events.team_score_changed.emit(1, 12)
		_events.match_clock_changed.emit(1200)
		_events.match_ended.emit(1)
		await process_frame
		await process_frame
		var window: Rect2 = Rect2(Vector2.ZERO, Vector2(WINDOW_SIZE))
		var fits: bool = true
		var smallest: int = 999
		for path: String in ["MatchBar/Row/BlueScore", "MatchBar/Row/Clock", "MatchBar/Row/OrangeScore", "MatchBar/MyTeam", "Banner"]:
			var control: Label = hud.get_node(path) as Label
			var rect: Rect2 = control.get_global_transform() * Rect2(Vector2.ZERO, control.size)
			if not window.encloses(rect):
				fits = false
				print("  outside window: ", path, " ", rect)
			smallest = mini(smallest, control.get_theme_font_size(&"font_size"))
		_check(fits, "match bar and banner fit in 1280x720 at UI scale %d%%" % roundi(scale * 100.0))
		_check(smallest >= 18, "no text under 18 px at %d%% (smallest %d)" % [roundi(scale * 100.0), smallest])
		await _free(hud)
	settings.ui_scale = 1.0
	quit(1 if _failures > 0 else 0)

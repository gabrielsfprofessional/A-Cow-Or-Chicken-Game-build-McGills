extends SceneTree
## Tests for card T16: hero select. Owner: John (game/ui). Run from the repo folder with
## APPDATA pointed at a temp folder so the real settings are never touched:
##   godot --headless --path . --script res://game/ui/tools/test_hero_select.gd
## Exits with code 1 when any case is wrong. Autoloads exist only at run time, so the
## script reaches them by path and loads the scene with load(), after they exist.

const SCENE_PATH: String = "res://game/ui/hero_select.tscn"
const ROSTER: HeroRoster = preload("res://game/heroes/data/roster.tres")
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)

var _failures: int = 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		print("FAIL ", what)
		_failures += 1


func _screen() -> Control:
	var scene: PackedScene = load(SCENE_PATH)
	var screen: Control = scene.instantiate()
	screen.open_join_on_pick = false
	# A headless window ignores its size, so the screen gets its own 1280x720 viewport.
	var viewport: SubViewport = SubViewport.new()
	viewport.size = WINDOW_SIZE
	root.add_child(viewport)
	viewport.add_child(screen)
	return screen


func _initialize() -> void:
	await process_frame
	var settings: Node = root.get_node(^"/root/Settings")
	var net: Node = root.get_node(^"/root/Net")
	settings.last_hero = ""
	net.chosen_hero_index = -1

	# Cards follow the roster, in order.
	var screen: Control = _screen()
	await process_frame
	var cards: Array[Node] = screen.get_node(^"Margin/Rows/Cards").get_children()
	_check(cards.size() == ROSTER.heroes.size(), "one card per roster hero (%d)" % cards.size())
	var in_order: bool = true
	for slot: int in cards.size():
		var hero: HeroData = ROSTER.at(slot)
		var text: String = (cards[slot] as Button).text
		if not (text.contains(hero.display_name) and text.contains(hero.role) and text.contains(hero.ability.display_name) and text.contains(hero.default_weapon.display_name)):
			in_order = false
	_check(in_order, "each card shows its hero's name, role, Q ability and weapon, in roster order")
	_check(screen.start_slot() == 0, "no saved hero starts on the first hero")

	# A pick through a card's signal sets the slot and the saved key.
	var last: int = ROSTER.heroes.size() - 1
	(cards[last] as Button).pressed.emit()
	var file_name: String = ROSTER.at(last).resource_path.get_file().get_basename()
	_check(net.chosen_hero_index == last, "a pick sets Net.chosen_hero_index to slot %d" % last)
	_check(settings.last_hero == file_name, "a pick remembers the hero's file name (%s)" % file_name)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings.PATH))
	var saved_dict: Dictionary = saved if saved is Dictionary else {}
	_check(saved_dict.get("last_hero", "") == file_name, "settings.json holds last_hero")
	_check(int(saved_dict.get("version", 0)) == 1, "settings.json version stays 1")
	screen.get_parent().queue_free()
	await process_frame

	# The next visit starts on the last pick; a bad key falls back to the first hero.
	settings.last_hero = ""
	settings.load_settings()
	_check(settings.last_hero == file_name, "last_hero is read back from disk")
	screen = _screen()
	await process_frame
	var picked_card: Button = screen.get_node(^"Margin/Rows/Cards").get_child(last) as Button
	_check(screen.start_slot() == last and picked_card.button_pressed, "the next visit starts on the last pick, shown as picked")
	screen.get_parent().queue_free()
	await process_frame
	for bad: String in ["nobody", "../bruiser", "SCOUT "]:
		settings.last_hero = bad
		screen = _screen()
		await process_frame
		var expected: int = maxi(0, ROSTER.index_of(bad))
		_check(screen.start_slot() == expected, "key \"%s\" starts on slot %d" % [bad, expected])
		screen.get_parent().queue_free()
		await process_frame

	# Layout at each UI scale in a 1280x720 window.
	settings.last_hero = ""
	for scale: float in [1.0, 1.25, 1.5]:
		settings.ui_scale = scale
		screen = _screen()
		await process_frame
		await process_frame
		var window: Rect2 = Rect2(Vector2.ZERO, Vector2(WINDOW_SIZE))
		var fits: bool = true
		var smallest: int = 999
		var nodes: Array[Node] = screen.get_node(^"Margin/Rows").get_children()
		nodes.append_array(screen.get_node(^"Margin/Rows/Cards").get_children())
		for node: Node in nodes:
			var control: Control = node as Control
			if control == null or not control.is_visible_in_tree():
				continue
			if not window.encloses(control.get_global_rect()):
				fits = false
				print("  outside window: ", control.name, " ", control.get_global_rect())
			if control is Button or control is Label:
				smallest = mini(smallest, control.get_theme_font_size(&"font_size"))
		_check(fits, "everything fits in 1280x720 at UI scale %d%%" % roundi(scale * 100.0))
		_check(smallest >= 18, "no text under 18 px at %d%% (smallest %d)" % [roundi(scale * 100.0), smallest])
		screen.get_parent().queue_free()
		await process_frame
	settings.ui_scale = 1.0
	net.chosen_hero_index = -1
	quit(1 if _failures > 0 else 0)

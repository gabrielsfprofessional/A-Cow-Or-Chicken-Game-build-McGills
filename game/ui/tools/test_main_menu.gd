extends SceneTree
## Tests for the main menu's first-launch check (card T11, issue #94): a window started
## with "-- --profile=<file>" uses that file, so it opens on the menu, not "Your profile".
## Owner: John (game/ui). Run from the repo folder with APPDATA pointed at a temp folder:
##   godot --headless --path . --script res://game/ui/tools/test_main_menu.gd
## Exits with code 1 when any case is wrong. It writes only user://test_main_menu*.json
## and never reads the real profile.json. Autoloads exist only at run time, so the menu
## is loaded with load(), after they exist.

const SCENE_PATH: String = "res://game/ui/main_menu.tscn"
const ProfileScript: GDScript = preload("res://game/players/profile.gd")
## A stand-in for the player's own profile file, which is not there (a first launch).
const NO_PROFILE: String = "user://test_main_menu_none.json"
## The file a window is started with: -- --profile=<this>.
const FLAG_PROFILE: String = "user://test_main_menu_flag.json"
const FLAG_NAME: String = "Flagged"

var _failures: int = 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		print("FAIL ", what)
		_failures += 1


## A main menu that is not in the tree yet, started the way the test says.
func _menu(debug_build: bool, launch_args: PackedStringArray) -> Control:
	var menu: Control = (load(SCENE_PATH) as PackedScene).instantiate()
	menu.debug_build = debug_build
	menu.launch_args = launch_args
	menu.default_profile_path = NO_PROFILE
	return menu


func _initialize() -> void:
	await process_frame
	_clean()
	var flag: PackedStringArray = ["--profile=" + FLAG_PROFILE]
	_check(ProfileScript.save({"name": FLAG_NAME, "color": "#E63946"}, FLAG_PROFILE), "the test profile was written")

	var menu: Control = _menu(true, [])
	_check(menu._needs_profile(), "a first launch with no profile opens 'Your profile'")
	menu.free()

	menu = _menu(true, flag)
	_check(not menu._needs_profile(), "a window started with --profile=<a good file> opens on the main menu")
	# In the tree, the menu shows that file's name.
	root.add_child(menu)
	await process_frame
	var playing_as: Label = menu.get_node(^"Center/Menu/PlayingAs") as Label
	_check(playing_as.text == "Playing as %s" % FLAG_NAME, "the menu shows the --profile file's name (got '%s')" % playing_as.text)
	_check(current_scene == null, "no other screen was opened")
	menu.queue_free()
	await process_frame

	menu = _menu(true, ["--profile=user://test_main_menu_missing.json"])
	_check(menu._needs_profile(), "--profile=<a file that is not there> opens 'Your profile'")
	# After Save there (it writes the player's own file) the menu must open, not loop.
	menu.default_profile_path = FLAG_PROFILE
	_check(not menu._needs_profile(), "--profile=<a file that is not there> falls back to the player's own profile")
	menu.free()

	menu = _menu(false, flag)
	_check(menu._needs_profile(), "a release build ignores --profile= (debug builds only)")
	menu.free()

	_clean()
	quit(1 if _failures > 0 else 0)


## Removes every file this test wrote.
func _clean() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.begins_with("test_main_menu"):
			dir.remove(file)

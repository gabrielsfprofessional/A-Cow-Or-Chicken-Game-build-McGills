extends Control
## Placeholder main menu. Owner: John (game/ui).
## Play opens hero select (T16), which opens the Join screen (T10); Practice Range is wired in T20.
## Profile and "Playing as <name>" come from T11. With no profile yet, the profile
## screen opens first, except for servers and --join launches.

const HERO_SELECT_SCENE: String = "res://game/ui/hero_select.tscn"
const PROFILE_SCENE: String = "res://game/players/profile_screen.tscn"
const UPDATE_TEXT: String = "Update the game from the Drive folder"

## How this window was started. Fields, so a test can stand in for a launch.
var debug_build: bool = OS.is_debug_build()
var launch_args: PackedStringArray = OS.get_cmdline_user_args()
var default_profile_path: String = Profile.PATH

@onready var _version: Label = $Center/Menu/Version
@onready var _playing_as: Label = $Center/Menu/PlayingAs
@onready var _play: Button = $Center/Menu/PlayButton
@onready var _profile: Button = $Center/Menu/ProfileButton


func _ready() -> void:
	_version.text = "Version %s" % Game.version()
	# Servers and bots never read or write profile.json (their menu skips it all).
	if _skips_profile():
		_profile.disabled = true
		_play.grab_focus()
		return
	if _needs_profile():
		_open_profile_screen.call_deferred()
		return
	Events.profile_changed.connect(_show_profile)
	_show_profile()
	_play.grab_focus()


## True for --server and --bot launches: no profile load, no bad-file rename.
func _skips_profile() -> bool:
	return Game.is_server() or Net.debug_flag(debug_build, launch_args, "--bot=") != ""


## The profile file this window plays with: the debug "--profile=<file>" one when the
## window was started with it and it holds a profile (the file joining uses too), else
## the player's own. So Save on "Your profile", which writes the player's own file,
## always leads back to the menu.
func _profile_path() -> String:
	var path: String = Net.debug_flag(debug_build, launch_args, Net.PROFILE_FLAG)
	if path != "" and (Profile.exists(path) or Profile.newer_version_found(path)):
		return path
	return default_profile_path


## True on a normal launch with no readable profile. Servers, bots and --join launches go straight on.
func _needs_profile() -> bool:
	if _skips_profile() or Net.join_argument() != "":
		return false
	var path: String = _profile_path()
	return not Profile.exists(path) and not Profile.newer_version_found(path)


func _show_profile() -> void:
	var path: String = _profile_path()
	if Profile.newer_version_found(path):
		_playing_as.text = UPDATE_TEXT
		_playing_as.remove_theme_color_override("font_color")
		_profile.disabled = true
		return
	_profile.disabled = false
	if not Profile.exists(path):
		_playing_as.text = ""
		return
	var data: Dictionary = Profile.load_or_default(path)
	_playing_as.text = "Playing as %s" % data["name"]
	_playing_as.add_theme_color_override("font_color", Color(str(data["color"])))


func _open_profile_screen() -> void:
	get_tree().change_scene_to_file(PROFILE_SCENE)


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(HERO_SELECT_SCENE)


func _on_profile_pressed() -> void:
	_open_profile_screen()


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://game/ui/settings_screen.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()

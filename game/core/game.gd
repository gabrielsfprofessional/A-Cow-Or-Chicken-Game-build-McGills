extends Node
## Game-wide helpers and the input map (autoload "Game"). Owner: Gabe (game/core).
## Keys match docs/PROJECT_PLAN.md, section "Controls". Change keys here only.

const KEYS: Dictionary = {
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"ability": [KEY_Q],
	&"ultimate": [KEY_F],
	&"interact": [KEY_E],
	&"reload": [KEY_R],
	&"weapon_1": [KEY_1],
	&"weapon_2": [KEY_2],
	&"scoreboard": [KEY_TAB],
	&"menu": [KEY_ESCAPE],
}


func _ready() -> void:
	_register_inputs()


## Build version shown on the main menu and checked when joining a server.
func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## True for the exported server build, or when started with: godot --headless -- --server
func is_server() -> bool:
	return OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args()


func _register_inputs() -> void:
	for action: StringName in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			InputMap.action_add_event(action, event)
	if not InputMap.has_action(&"fire"):
		InputMap.add_action(&"fire")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(&"fire", click)

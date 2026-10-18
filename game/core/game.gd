extends Node
## Game-wide helpers, the input map and the debug run timer (autoload "Game").
## Owner: Gabe (game/core). Keys match docs/PROJECT_PLAN.md, section "Controls".
## Change keys here only.

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
## Debug builds: "-- --quit-after-sec=<n>" ends the run after n seconds (T09).
const QUIT_AFTER_FLAG: String = "--quit-after-sec="


func _ready() -> void:
	_register_inputs()
	_start_run_timer()


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


## Debug builds: "-- --quit-after-sec=<n>" ends the run after n seconds with an
## exit code a script can check (card T09: smoke's bot match, tools/run_bots.ps1).
## It lives here so it survives scene changes. Exit 0 for a server that hosted,
## or a client that joined and never lost the connection; 1 otherwise. A timed
## client whose join fails, or that loses its server, quits at once with 1. At
## the end it hangs up with Net.leave() first, so the shutdown logs stay clean.
func _start_run_timer() -> void:
	var value := Net.debug_flag(OS.is_debug_build(), OS.get_cmdline_user_args(), QUIT_AFTER_FLAG)
	if not value.is_valid_float() or value.to_float() <= 0.0:
		return
	Net.join_failed.connect(_end_run_early)
	Net.left.connect(_on_left)
	await get_tree().create_timer(value.to_float()).timeout
	var code := 0 if Net.state == Net.State.SERVER or Net.state == Net.State.CLIENT else 1
	print("[Game] quit-after-sec=%s: exit %d" % [value, code])
	Net.leave()
	get_tree().quit(code)


## Net.leave() says "" and is no loss; any other reason is a lost server.
func _on_left(reason: String) -> void:
	if reason != "":
		_end_run_early(reason)


func _end_run_early(reason: String) -> void:
	print("[Game] quit-after-sec: exit 1 now: %s" % reason)
	get_tree().quit(1)

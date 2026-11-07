extends Control
## Press F6 on hud_preview.tscn to see the HUD without a server (card T17). Owner: John (game/ui).
## Fake numbers only; the keys are listed on screen.

const MAX_HEALTH: int = 100
const COOLDOWN_SEC: float = 8.0
const CHARGES: int = 2
const RESPAWN_SEC: float = 5.0

var _health: int = 72
## When each charge is back, in seconds since the preview started.
var _ready_at: Array[float] = [0.0, 0.0]
var _respawn_left: float = 0.0
var _scout: bool = true
var _clock: float = 0.0

@onready var _hud: Hud = $Hud
@onready var _help: Label = $Help


func _ready() -> void:
	_help.add_theme_font_size_override(&"font_size", 24)
	_help.text = "HUD preview (fake numbers)\nUp / Down: health   Q: use Q   E: eliminated\nT: Scout (2 charges) or one charge   1 / 2 / 3: UI scale 100 / 125 / 150%"
	_refresh()


func _process(delta: float) -> void:
	_clock += delta
	if _respawn_left > 0.0:
		_respawn_left = maxf(0.0, _respawn_left - delta)
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_UP:
			_health = mini(_health + 10, MAX_HEALTH)
		KEY_DOWN:
			_health = maxi(_health - 10, 0)
		KEY_Q:
			_use_q()
		KEY_E:
			_respawn_left = RESPAWN_SEC if _respawn_left <= 0.0 else 0.0
		KEY_T:
			_scout = not _scout
		KEY_1:
			Settings.set_ui_scale(1.0)
		KEY_2:
			Settings.set_ui_scale(1.25)
		KEY_3:
			Settings.set_ui_scale(1.5)


func _use_q() -> void:
	for i: int in _total():
		if _ready_at[i] <= _clock:
			_ready_at[i] = _clock + COOLDOWN_SEC
			return


func _total() -> int:
	return CHARGES if _scout else 1


func _refresh() -> void:
	var left := 0
	var soonest := INF
	for i: int in _total():
		if _ready_at[i] <= _clock:
			left += 1
		soonest = minf(soonest, _ready_at[i])
	var ready_in := 0.0 if left > 0 else maxf(0.0, soonest - _clock)
	_hud.set_health(_health, MAX_HEALTH)
	_hud.set_ability("Jet Dash" if _scout else "Blink", ready_in, left, _total())
	_hud.set_respawn(_respawn_left)

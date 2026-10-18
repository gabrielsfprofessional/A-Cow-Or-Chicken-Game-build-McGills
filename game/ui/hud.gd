class_name Hud
extends Control
## The in-match display for your own hero (card T17, part 1). Owner: John (game/ui).
##
## It only shows what it is told: Overlay (or hud_preview.gd) calls set_health(),
## set_ability() and set_respawn(). It decides nothing and never takes a click, so
## left click still shoots. Sizes and colors are the @export values below.

## Text size at 1080p; the UI scaler (Settings.ui_scale) grows it.
@export_range(18, 64, 1, "suffix:px") var font_size: int = 28
@export var bar_size: Vector2 = Vector2(360.0, 32.0)
@export var bar_color: Color = Color(0.27, 0.65, 0.35)
@export var bar_low_color: Color = Color(0.94, 0.35, 0.35)
@export var bar_back_color: Color = Color(0.0, 0.0, 0.0, 0.55)
## Below this share of max health the bar turns bar_low_color.
@export_range(0.05, 0.9, 0.05) var low_health_share: float = 0.3
@export var ready_color: Color = Color(0.95, 0.95, 0.95)
@export var cooldown_color: Color = Color(0.7, 0.7, 0.7)
## How dim the Q box is while it cools down or you are eliminated.
@export_range(0.2, 1.0, 0.05) var dimmed_alpha: float = 0.55

@onready var _health_bar: ProgressBar = $Corner/Stack/HealthRow/HealthBar
@onready var _health_text: Label = $Corner/Stack/HealthRow/HealthText
@onready var _q_box: PanelContainer = $Corner/Stack/QBox
@onready var _q_key: Label = $Corner/Stack/QBox/Row/Key
@onready var _q_name: Label = $Corner/Stack/QBox/Row/Name
@onready var _q_state: Label = $Corner/Stack/QBox/Row/State
@onready var _back_in: Label = $BackIn

var _fill: StyleBoxFlat = StyleBoxFlat.new()


func _ready() -> void:
	for label: Label in [_health_text, _q_key, _q_name, _q_state, _back_in]:
		label.add_theme_font_size_override(&"font_size", font_size)
	_health_bar.custom_minimum_size = bar_size
	_health_bar.add_theme_stylebox_override(&"fill", _fill)
	var back := StyleBoxFlat.new()
	back.bg_color = bar_back_color
	_health_bar.add_theme_stylebox_override(&"background", back)
	set_health(0, 1)
	set_ability("", 0.0, 0, 0)
	set_respawn(0.0)


## Health bar and the "72 / 100" text.
func set_health(current: int, maximum: int) -> void:
	maximum = maxi(maximum, 1)
	current = clampi(current, 0, maximum)
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_text.text = health_text(current, maximum)
	_fill.bg_color = bar_low_color if float(current) / maximum < low_health_share else bar_color


## The Q box. An empty name hides it (a hero without an ability). `charges_total`
## above 1 shows "x2" or "x1" while a charge is ready.
func set_ability(display_name: String, ready_in_sec: float, charges_left: int, charges_total: int) -> void:
	_q_box.visible = display_name != ""
	_q_name.text = display_name
	_q_state.text = ability_text(ready_in_sec, charges_left, charges_total)
	var cooling := ready_in_sec > 0.0 and charges_left <= 0
	_q_state.add_theme_color_override(&"font_color", cooldown_color if cooling else ready_color)
	_q_box.modulate.a = dimmed_alpha if cooling else 1.0


## Seconds until you are back; 0 or less while you are alive.
func set_respawn(seconds_left: float) -> void:
	_back_in.visible = seconds_left > 0.0
	_back_in.text = respawn_text(seconds_left)
	if seconds_left > 0.0:
		_q_box.modulate.a = dimmed_alpha


static func health_text(current: int, maximum: int) -> String:
	return "%d / %d" % [current, maximum]


static func ability_text(ready_in_sec: float, charges_left: int, charges_total: int) -> String:
	if charges_left <= 0 and ready_in_sec > 0.0:
		return "%d" % ceili(ready_in_sec)
	if charges_total > 1:
		return "READY x%d" % charges_left
	return "READY"


static func respawn_text(seconds_left: float) -> String:
	return "Back in %d s" % ceili(seconds_left)

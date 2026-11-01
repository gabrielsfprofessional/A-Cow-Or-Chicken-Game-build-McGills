extends Control
## Pick a name and a color once; the game remembers them (card T11). Owner: John (game/players).
## Only Save writes the file. With no profile yet, Back is hidden until the first Save.

const MENU_SCENE: String = "res://game/ui/main_menu.tscn"
const SWATCH_SIZE: Vector2 = Vector2(72, 72)
const EXAMPLE_NAME: String = "Your name"

@onready var _name: LineEdit = $Center/Rows/NameEdit
@onready var _problem: Label = $Center/Rows/Problem
@onready var _swatches: HBoxContainer = $Center/Rows/Swatches
@onready var _preview: Label = $Center/Rows/Preview
@onready var _save: Button = $Center/Rows/SaveButton
@onready var _back: Button = $Center/Rows/BackButton

var _color: Color = Color.WHITE
var _group: ButtonGroup = ButtonGroup.new()


func _ready() -> void:
	var data: Dictionary = Profile.load_or_default()
	_name.text = str(data["name"])
	_build_swatches(Color(str(data["color"])))
	_back.visible = Profile.exists() or Profile.newer_version_found()
	_name.text_changed.connect(_on_name_changed)
	_name.text_submitted.connect(_on_name_submitted)
	_save.pressed.connect(_on_save_pressed)
	_back.pressed.connect(_on_back_pressed)
	_refresh()
	_name.grab_focus()
	_name.caret_column = _name.text.length()


func _build_swatches(current: Color) -> void:
	var colors: Array[Color] = Profile.COLORS.swatches
	var chosen: int = 0
	for i: int in colors.size():
		if colors[i].to_html(false) == current.to_html(false):
			chosen = i
	for i: int in colors.size():
		var swatch: Button = Button.new()
		swatch.name = "Swatch%d" % (i + 1)
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.toggle_mode = true
		swatch.button_group = _group
		swatch.tooltip_text = "#" + colors[i].to_html(false).to_upper()
		swatch.add_theme_stylebox_override("normal", _swatch_style(colors[i], false))
		swatch.add_theme_stylebox_override("hover", _swatch_style(colors[i].lightened(0.15), false))
		swatch.add_theme_stylebox_override("pressed", _swatch_style(colors[i], true))
		swatch.add_theme_stylebox_override("hover_pressed", _swatch_style(colors[i], true))
		swatch.toggled.connect(_on_swatch_toggled.bind(colors[i]))
		_swatches.add_child(swatch)
		if i == chosen:
			swatch.set_pressed_no_signal(true)
			_color = colors[i]


## A flat square; the chosen one gets a thick white frame so it never depends on color alone.
func _swatch_style(color: Color, chosen: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	style.set_border_width_all(6 if chosen else 0)
	style.border_color = Color.WHITE
	return style


func _on_swatch_toggled(on: bool, color: Color) -> void:
	if on:
		_color = color
		_refresh()


func _on_name_changed(_text: String) -> void:
	_refresh()


func _on_name_submitted(_text: String) -> void:
	if not _save.disabled:
		_on_save_pressed()


## Names the broken rule under the box, grays Save out, and shows the name in its color.
func _refresh() -> void:
	var problem: String = Profile.name_problem(_name.text)
	_problem.text = problem
	_save.disabled = problem != "" or Profile.newer_version_found()
	var shown: String = _name.text.strip_edges()
	_preview.text = shown if problem == "" else EXAMPLE_NAME
	_preview.add_theme_color_override("font_color", _color)


func _on_save_pressed() -> void:
	var ok: bool = Profile.save({"name": _name.text, "color": "#" + _color.to_html(false)})
	if not ok:
		_problem.text = "Could not save your profile. Try again."
		return
	Events.profile_changed.emit()
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)

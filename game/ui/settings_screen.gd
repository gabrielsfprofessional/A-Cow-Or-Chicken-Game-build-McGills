extends Control
## Settings screen: volume sliders, UI scale, window mode, test sound. Owner: John (game/ui).
## Every change applies at once and is saved by the Settings autoload.

const MENU_SCENE: String = "res://game/ui/main_menu.tscn"

@onready var _master: HSlider = $Center/Rows/Grid/MasterSlider
@onready var _music: HSlider = $Center/Rows/Grid/MusicSlider
@onready var _sfx: HSlider = $Center/Rows/Grid/SfxSlider
@onready var _master_value: Label = $Center/Rows/Grid/MasterValue
@onready var _music_value: Label = $Center/Rows/Grid/MusicValue
@onready var _sfx_value: Label = $Center/Rows/Grid/SfxValue
@onready var _scale: OptionButton = $Center/Rows/Grid/ScaleOption
@onready var _window: OptionButton = $Center/Rows/Grid/WindowOption
@onready var _test_player: AudioStreamPlayer = $TestPlayer


func _ready() -> void:
	for factor: float in Settings.SCALES:
		_scale.add_item("%d%%" % roundi(factor * 100.0))
	_scale.selected = Settings.SCALES.find(Settings.ui_scale)
	_window.add_item("Windowed")
	_window.add_item("Fullscreen")
	_window.selected = 1 if Settings.fullscreen else 0
	_master.value = Settings.master
	_music.value = Settings.music
	_sfx.value = Settings.sfx
	_update_labels()
	_master.value_changed.connect(_on_volume_changed.bind(&"Master"))
	_music.value_changed.connect(_on_volume_changed.bind(&"Music"))
	_sfx.value_changed.connect(_on_volume_changed.bind(&"SFX"))
	_scale.item_selected.connect(_on_scale_selected)
	_window.item_selected.connect(_on_window_selected)
	$Center/Rows/TestButton.pressed.connect(_on_test_pressed)
	$Center/Rows/BackButton.pressed.connect(_on_back_pressed)


func _on_volume_changed(value: float, bus: StringName) -> void:
	Settings.set_volume(bus, roundi(value))
	Settings.save_settings()
	_update_labels()


func _on_scale_selected(index: int) -> void:
	Settings.set_ui_scale(Settings.SCALES[index])
	Settings.save_settings()


func _on_window_selected(index: int) -> void:
	Settings.set_fullscreen(index == 1)
	Settings.save_settings()


func _on_test_pressed() -> void:
	_test_player.play()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _update_labels() -> void:
	_master_value.text = "%d%%" % Settings.master
	_music_value.text = "%d%%" % Settings.music
	_sfx_value.text = "%d%%" % Settings.sfx

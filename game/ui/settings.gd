extends Node
## Player settings: volume, UI scale, window mode (autoload "Settings"). Owner: John (game/ui).
## Loads user://settings.json at startup and applies it, so it works even when the menu is skipped.

signal ui_scale_changed(scale: float)

const PATH: String = "user://settings.json"
const VERSION: int = 1
const SCALES: Array[float] = [1.0, 1.25, 1.5]
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX"]

var master: int = 100
var music: int = 100
var sfx: int = 100
var ui_scale: float = 1.0
var fullscreen: bool = false


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(PATH)) == OK else null
	if not parsed is Dictionary:
		push_warning("Settings: could not read %s, using defaults" % PATH)
		return
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != VERSION:
		push_warning("Settings: unknown version in %s, using defaults" % PATH)
		return
	master = clampi(int(data.get("master", master)), 0, 100)
	music = clampi(int(data.get("music", music)), 0, 100)
	sfx = clampi(int(data.get("sfx", sfx)), 0, 100)
	var wanted: float = float(data.get("ui_scale", ui_scale))
	ui_scale = wanted if wanted in SCALES else 1.0
	fullscreen = bool(data.get("fullscreen", fullscreen))


## Writes to a temp file first, then renames, so a crash never leaves a half-written file.
func save_settings() -> void:
	var data: Dictionary = {
		"version": VERSION,
		"master": master,
		"music": music,
		"sfx": sfx,
		"ui_scale": ui_scale,
		"fullscreen": fullscreen,
	}
	var tmp: String = PATH + ".tmp"
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("Settings: cannot write %s" % tmp)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH))


func apply_all() -> void:
	for bus: StringName in BUSES:
		_apply_volume(bus)
	_apply_window_mode()
	ui_scale_changed.emit(ui_scale)


func volume_of(bus: StringName) -> int:
	match bus:
		&"Music":
			return music
		&"SFX":
			return sfx
	return master


func set_volume(bus: StringName, percent: int) -> void:
	percent = clampi(percent, 0, 100)
	match bus:
		&"Music":
			music = percent
		&"SFX":
			sfx = percent
		_:
			master = percent
	_apply_volume(bus)


func set_ui_scale(value: float) -> void:
	ui_scale = value if value in SCALES else 1.0
	ui_scale_changed.emit(ui_scale)


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_window_mode()


func _apply_volume(bus: StringName) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return
	var percent: int = volume_of(bus)
	AudioServer.set_bus_mute(index, percent == 0)
	AudioServer.set_bus_volume_db(index, linear_to_db(percent / 100.0) if percent > 0 else -80.0)


func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)

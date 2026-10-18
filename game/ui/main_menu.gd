extends Control
## Placeholder main menu. Owner: John (game/ui).
## Play opens the Join screen (T10); Practice Range is wired in T20.

const JOIN_SCENE: String = "res://game/ui/join_screen.tscn"

@onready var _version: Label = $Center/Menu/Version
@onready var _play: Button = $Center/Menu/PlayButton


func _ready() -> void:
	_version.text = "Version %s" % Game.version()
	_play.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(JOIN_SCENE)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://game/ui/settings_screen.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()

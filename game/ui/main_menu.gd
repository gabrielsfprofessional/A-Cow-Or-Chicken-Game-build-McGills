extends Control
## Placeholder main menu. Owner: John (game/ui).
## Play is wired in T06/T10; Practice Range in T20.

@onready var _version: Label = $Center/Menu/Version


func _ready() -> void:
	_version.text = "Version %s" % Game.version()


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://game/ui/settings_screen.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()

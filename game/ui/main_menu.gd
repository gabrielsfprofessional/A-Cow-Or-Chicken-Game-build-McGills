extends Control
## Placeholder main menu. Owner: John (game/ui).
## Play is wired in T06/T10; Practice Range in T20.

@onready var _version: Label = $Center/Menu/Version


func _ready() -> void:
	_version.text = "Version %s" % Game.version()


func _on_quit_pressed() -> void:
	get_tree().quit()

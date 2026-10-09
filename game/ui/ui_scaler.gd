extends Node
## Scales one menu or HUD screen by Settings.ui_scale, never the game world. Owner: John (game/ui).
## Add as a child of a full-screen Control root. The root is scaled and shrunk to
## (screen size / scale), so it still fills the screen.

@onready var _root: Control = get_parent() as Control


func _ready() -> void:
	Settings.ui_scale_changed.connect(_apply)
	get_viewport().size_changed.connect(_apply)
	_apply()


func _apply(_unused: float = 0.0) -> void:
	var factor: float = Settings.ui_scale
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_root.pivot_offset = Vector2.ZERO
	_root.position = Vector2.ZERO
	_root.scale = Vector2(factor, factor)
	_root.size = get_viewport().get_visible_rect().size / factor

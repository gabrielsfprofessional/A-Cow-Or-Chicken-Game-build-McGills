@tool
class_name ArenaBlock
extends StaticBody2D
## One graybox wall or cover block. Owner: Adam (game/maps).
## The origin is the top-left corner. Change its size with "Size" in the Inspector,
## never with the scale handles. Size snaps to GRID px steps.
## The collision shape is local to each block, so resizing one never resizes the others.

## One art tile at 3x. Block positions and sizes sit on this grid.
const GRID: float = 48.0
const COLOR: Color = Color(0.45, 0.47, 0.5, 1)

@export_custom(PROPERTY_HINT_RANGE, "48,30720,48,or_greater,suffix:px") var size: Vector2 = Vector2(96, 96):
	set(value):
		size = (value / GRID).round().max(Vector2.ONE) * GRID
		_apply_size()


func _ready() -> void:
	set_notify_transform(Engine.is_editor_hint())
	_apply_size()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	if scale != Vector2.ONE or rotation != 0.0:
		return PackedStringArray(["Don't scale or rotate blocks. Set Scale to 1, 1 and Rotation to 0, and use Size instead."])
	return PackedStringArray()


func _apply_size() -> void:
	var shape_node: CollisionShape2D = get_node_or_null(^"Shape") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		(shape_node.shape as RectangleShape2D).size = size
		shape_node.position = size / 2.0
	queue_redraw()

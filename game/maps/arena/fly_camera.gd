extends Camera2D
## Free-flying camera for looking around a map with F6. Owner: Adam (game/maps).
## WASD or arrow keys move (the move_* actions from Game), mouse wheel zooms.
## A dev tool, not gameplay: it deletes itself unless its map is the scene played with F6
## in a window, so it never runs on the server or inside a match.

## How fast the camera flies, in pixels per second at zoom 1.
@export_range(100, 5000, 50, "suffix:px/s") var move_speed: float = 1200.0
## Most zoomed out.
@export_range(0.05, 1, 0.05) var min_zoom: float = 0.25
## Most zoomed in.
@export_range(1, 8, 0.25) var max_zoom: float = 2.0
## Each mouse wheel click multiplies or divides the zoom by this.
@export_range(1.01, 2, 0.01) var zoom_step: float = 1.1
## The area shown when the scene starts, in map pixels. A map with a map_size shows all of itself.
@export var start_view: Rect2 = Rect2(0, 0, 3840, 2160)


func _ready() -> void:
	if not ArenaMap.is_f6_run(owner):
		set_process(false)
		set_process_unhandled_input(false)
		queue_free()
		return
	var map_size: Variant = owner.get(&"map_size")
	if map_size is Vector2:
		start_view = Rect2(Vector2.ZERO, map_size)
	position = start_view.get_center()
	var fit: Vector2 = get_viewport_rect().size / start_view.size
	zoom = Vector2.ONE * clampf(minf(fit.x, fit.y), min_zoom, max_zoom)
	make_current()


func _process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	position += direction * move_speed * delta / zoom.x


func _unhandled_input(event: InputEvent) -> void:
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	if wheel == null or not wheel.pressed:
		return
	var factor: float = 1.0
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		factor = zoom_step
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		factor = 1.0 / zoom_step
	else:
		return
	zoom = Vector2.ONE * clampf(zoom.x * factor, min_zoom, max_zoom)

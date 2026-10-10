@tool
class_name ArenaMap
extends Node2D
## Graybox arena: Floor, Walls, Cover, Spawns, FlyCamera. Owner: Adam (game/maps).
## In the editor this script checks the map as you edit it and shows a yellow warning
## next to the root node in the Scene panel when something is wrong.
## tools/check_arena.gd runs the same check headless.

## Two heroes side by side. Blocks either touch or leave at least this much room.
const MIN_GAP: float = 96.0
## One hero. Spawns keep this much room from every block.
const SPAWN_ROOM: float = 48.0
## The smallest map: walls all around and one open cell in the middle.
const MIN_MAP_CELLS: int = 3
const MIN_COVER: int = 10
const MAX_COVER: int = 14
const SPAWN_NAMES: Array[String] = ["SpawnA1", "SpawnA2", "SpawnA3", "SpawnA4", "SpawnB1", "SpawnB2", "SpawnB3", "SpawnB4"]
## Team colors from PROJECT_PLAN (decided Oct 9): Blue and Orange.
const TEAM_A_COLOR: Color = Color("#3B82F6")
const TEAM_B_COLOR: Color = Color("#F97316")
const SPAWN_DOT_RADIUS: float = 18.0
## How often the editor looks for changes, in seconds.
const RECHECK_SECONDS: float = 0.25

## The whole map including the outer walls, in px, a multiple of 48. Walls must ring its edge.
@export var map_size: Vector2 = Vector2(3840, 2160)

var _since_check: float = 0.0
var _last_layout: int = 0


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	var spawns: Node2D = get_node_or_null(^"Spawns") as Node2D
	if spawns != null and (Engine.is_editor_hint() or is_played_alone()):
		spawns.draw.connect(_draw_spawn_dots.bind(spawns))
		spawns.queue_redraw()


## True when this map is the scene played with F6 in a window, not part of a match or the server.
func is_played_alone() -> bool:
	return is_f6_run(self)


## True when node is the scene the editor started with F6, in a window.
## The editor passes the scene's path (or its uid) on the command line; a match that loads
## a map as its current scene does not, and neither does the headless server.
static func is_f6_run(node: Node) -> bool:
	if node == null or not node.is_inside_tree() or Engine.is_editor_hint():
		return false
	if DisplayServer.get_name() == "headless" or node.get_tree().current_scene != node:
		return false
	var path: String = node.scene_file_path
	if path.is_empty():
		return false
	var args: PackedStringArray = OS.get_cmdline_args()
	return args.has(path) or args.has(ResourceUID.path_to_uid(path))


func _process(delta: float) -> void:
	_since_check += delta
	if _since_check < RECHECK_SECONDS:
		return
	_since_check = 0.0
	var layout: int = _layout_hash()
	if layout == _last_layout:
		return
	_last_layout = layout
	update_configuration_warnings()
	var spawns: Node2D = get_node_or_null(^"Spawns") as Node2D
	if spawns != null:
		spawns.queue_redraw()


func _get_configuration_warnings() -> PackedStringArray:
	return find_problems()


## Every problem with the map, in plain words. Empty means the map passes.
func find_problems() -> PackedStringArray:
	var cells: Vector2 = map_size / ArenaBlock.GRID
	if not _on_grid(map_size) or cells.x < MIN_MAP_CELLS or cells.y < MIN_MAP_CELLS:
		return PackedStringArray(["Map Size %s must be a multiple of 48 px and at least %d px each way." % [map_size, MIN_MAP_CELLS * ArenaBlock.GRID]])
	var problems: PackedStringArray = []
	var walls: Array[ArenaBlock] = _blocks("Walls", problems)
	var cover: Array[ArenaBlock] = _blocks("Cover", problems)
	var all: Array[ArenaBlock] = walls + cover
	_check_strays(problems)
	_check_blocks(all, problems)
	_check_walls(walls, problems)
	if cover.size() < MIN_COVER or cover.size() > MAX_COVER:
		problems.append("There are %d cover blocks; the arena needs %d-%d." % [cover.size(), MIN_COVER, MAX_COVER])
	_check_gaps(all, problems)
	var spawns: Dictionary = _check_spawns(all, problems)
	if spawns.has("SpawnA1"):
		_check_walkable(all, spawns, problems)
	return problems


func block_rect(block: ArenaBlock) -> Rect2:
	return Rect2(to_local(block.global_position), block.size)


func _blocks(group_name: String, problems: PackedStringArray) -> Array[ArenaBlock]:
	var found: Array[ArenaBlock] = []
	var group: Node = get_node_or_null(group_name)
	if group == null:
		problems.append("There is no %s node." % group_name)
		return found
	for child: Node in group.get_children():
		if child is ArenaBlock:
			found.append(child as ArenaBlock)
		else:
			problems.append("%s/%s is not a block. Only add blocks (block.tscn) here." % [group_name, child.name])
	return found


## Blocks anywhere else (at the map root, inside another block...) are not checked, so flag them.
func _check_strays(problems: PackedStringArray) -> void:
	for node: Node in find_children("*", "StaticBody2D", true, false):
		if node is ArenaBlock and not _is_placed(node):
			problems.append("%s is outside Walls and Cover. Drag it under Cover in the Scene panel." % get_path_to(node))


func _is_placed(block: Node) -> bool:
	var group: Node = block.get_parent()
	return group.get_parent() == self and (group.name == &"Walls" or group.name == &"Cover")


func _check_blocks(blocks: Array[ArenaBlock], problems: PackedStringArray) -> void:
	var shapes: Dictionary = {}
	for block: ArenaBlock in blocks:
		var label: String = _label(block)
		if block.collision_layer != 1:
			problems.append("%s must be on physics layer 1 only." % label)
		if block.scale != Vector2.ONE or block.rotation != 0.0:
			problems.append("%s is scaled or rotated. Set Scale to 1, 1 and Rotation to 0, and use Size." % label)
		var corner: Vector2 = block_rect(block).position
		if not _on_grid(corner) or not _on_grid(block.size):
			problems.append("%s is off the 48 px grid (at %s). Turn on grid snap and move it again." % [label, corner])
		var shape_node: CollisionShape2D = block.get_node_or_null(^"Shape") as CollisionShape2D
		var shape: RectangleShape2D = shape_node.shape as RectangleShape2D if shape_node != null else null
		if shape == null:
			problems.append("%s has no rectangle collision shape." % label)
			continue
		var id: int = shape.get_instance_id()
		if shapes.has(id):
			problems.append("%s shares its collision shape with %s." % [label, shapes[id]])
		shapes[id] = label
		if not shape.size.is_equal_approx(block.size) or not shape_node.position.is_equal_approx(block.size / 2.0):
			problems.append("%s collision shape does not match its Size." % label)


func _check_walls(walls: Array[ArenaBlock], problems: PackedStringArray) -> void:
	if walls.is_empty():
		problems.append("There are no outer walls.")
		return
	var rects: Array[Rect2] = []
	for wall: ArenaBlock in walls:
		rects.append(block_rect(wall))
	var cols: int = int(map_size.x / ArenaBlock.GRID)
	var rows: int = int(map_size.y / ArenaBlock.GRID)
	# Every 48 px cell on the outer ring must sit fully inside one wall block.
	for row: int in rows:
		for col: int in cols:
			if row != 0 and row != rows - 1 and col != 0 and col != cols - 1:
				continue
			var cell: Rect2 = Rect2(Vector2(col, row) * ArenaBlock.GRID, Vector2.ONE * ArenaBlock.GRID)
			var closed: bool = false
			for rect: Rect2 in rects:
				if rect.encloses(cell):
					closed = true
					break
			if not closed:
				problems.append("The outer wall has a hole at %s. Close it with a wall block." % cell.position)
				return


func _check_gaps(blocks: Array[ArenaBlock], problems: PackedStringArray) -> void:
	for i: int in blocks.size():
		for j: int in range(i + 1, blocks.size()):
			var gap: float = _gap(block_rect(blocks[i]), block_rect(blocks[j]))
			if gap > 0.0 and gap < MIN_GAP:
				problems.append("%s and %s are %.0f px apart. Make them touch or leave at least %.0f px." % [_label(blocks[i]), _label(blocks[j]), gap, MIN_GAP])


## Returns spawn name -> position for every spawn that exists.
func _check_spawns(blocks: Array[ArenaBlock], problems: PackedStringArray) -> Dictionary:
	var points: Dictionary = {}
	var group: Node = get_node_or_null(^"Spawns")
	if group == null:
		problems.append("There is no Spawns node.")
		return points
	if group.get_child_count() != SPAWN_NAMES.size():
		problems.append("Spawns has %d children; it needs exactly %d." % [group.get_child_count(), SPAWN_NAMES.size()])
	for spawn_name: String in SPAWN_NAMES:
		var marker: Marker2D = group.get_node_or_null(spawn_name) as Marker2D
		if marker == null:
			problems.append("Spawns/%s (a Marker2D) is missing." % spawn_name)
			continue
		var point: Vector2 = to_local(marker.global_position)
		if not Rect2(Vector2.ZERO, map_size).has_point(point):
			problems.append("%s is outside the walls." % spawn_name)
			continue
		if (point.x < map_size.x / 2.0) != spawn_name.begins_with("SpawnA"):
			problems.append("%s is on the wrong side (team A left, team B right)." % spawn_name)
		for block: ArenaBlock in blocks:
			if _distance(point, block_rect(block)) < SPAWN_ROOM:
				problems.append("%s is closer than %.0f px to %s." % [spawn_name, SPAWN_ROOM, _label(block)])
				break
		points[spawn_name] = point
	return points


## Flood fill over 48 px cells from SpawnA1. A cell is open when no block covers any of it.
## Every open cell and every spawn must be reachable, so there are no sealed-off spots.
func _check_walkable(blocks: Array[ArenaBlock], spawns: Dictionary, problems: PackedStringArray) -> void:
	var cols: int = int(map_size.x / ArenaBlock.GRID)
	var rows: int = int(map_size.y / ArenaBlock.GRID)
	var rects: Array[Rect2] = []
	for block: ArenaBlock in blocks:
		rects.append(block_rect(block))
	var open: PackedByteArray = PackedByteArray()
	open.resize(cols * rows)
	var open_count: int = 0
	for row: int in rows:
		for col: int in cols:
			var cell: Rect2 = Rect2(Vector2(col, row) * ArenaBlock.GRID, Vector2.ONE * ArenaBlock.GRID)
			var free: bool = true
			for rect: Rect2 in rects:
				if cell.intersects(rect):
					free = false
					break
			if free:
				open[row * cols + col] = 1
				open_count += 1
	var start: int = _cell_index(spawns["SpawnA1"], cols)
	if open[start] == 0:
		return
	var reached: PackedByteArray = PackedByteArray()
	reached.resize(cols * rows)
	reached[start] = 1
	var reached_count: int = 1
	var stack: Array[int] = [start]
	while not stack.is_empty():
		var index: int = stack.pop_back()
		var col: int = index % cols
		@warning_ignore("integer_division")
		var row: int = index / cols
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var c: int = col + step.x
			var r: int = row + step.y
			if c < 0 or r < 0 or c >= cols or r >= rows:
				continue
			var next: int = r * cols + c
			if open[next] == 1 and reached[next] == 0:
				reached[next] = 1
				reached_count += 1
				stack.append(next)
	for spawn_name: String in spawns:
		if reached[_cell_index(spawns[spawn_name], cols)] == 0:
			problems.append("%s can't be reached from SpawnA1." % spawn_name)
	if reached_count < open_count:
		for index: int in open.size():
			if open[index] == 1 and reached[index] == 0:
				@warning_ignore("integer_division")
				var spot: Vector2 = Vector2(index % cols, index / cols) * ArenaBlock.GRID
				problems.append("%d open spots can't be reached from SpawnA1, for example at %s." % [open_count - reached_count, spot])
				break


func _draw_spawn_dots(spawns: Node2D) -> void:
	for child: Node in spawns.get_children():
		var marker: Marker2D = child as Marker2D
		if marker != null:
			var color: Color = TEAM_A_COLOR if marker.name.begins_with("SpawnA") else TEAM_B_COLOR
			spawns.draw_circle(marker.position, SPAWN_DOT_RADIUS, color)


func _layout_hash() -> int:
	var layout: Array = [map_size]
	for node: Node in find_children("*", "StaticBody2D", true, false):
		if node is ArenaBlock:
			layout.append_array([get_path_to(node), (node as ArenaBlock).global_position])
	for group_name: String in ["Walls", "Cover", "Spawns"]:
		var group: Node = get_node_or_null(group_name)
		if group == null:
			continue
		for child: Node in group.get_children():
			layout.append(child.name)
			if child is Node2D:
				var node: Node2D = child as Node2D
				layout.append_array([node.global_position, node.scale, node.rotation])
			if child is ArenaBlock:
				layout.append((child as ArenaBlock).size)
	return hash(layout)


func _cell_index(point: Vector2, cols: int) -> int:
	var cell: Vector2i = Vector2i((point / ArenaBlock.GRID).floor())
	return cell.y * cols + cell.x


func _on_grid(value: Vector2) -> bool:
	var cells: Vector2 = value / ArenaBlock.GRID
	return cells.is_equal_approx(cells.round())


func _gap(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy: float = maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dy).length()


func _distance(point: Vector2, rect: Rect2) -> float:
	return point.distance_to(point.clamp(rect.position, rect.end))


func _label(node: Node) -> String:
	return "%s/%s" % [node.get_parent().name, node.name]

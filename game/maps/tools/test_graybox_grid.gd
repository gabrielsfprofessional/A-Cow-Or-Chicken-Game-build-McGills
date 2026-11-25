extends SceneTree
## Proves the faster map check (A01 part 1) finds exactly what the old one found. Owner: Adam (game/maps).
## The old outer-wall, gap, marker and no-dead-ends checks are kept below as plain functions on
## rects (the reference). On LAYOUTS seeded random layouts (3-40 cells each way, 0-60 blocks:
## touching, overlapping, off the grid, past the walls, sealed pockets, markers near blocks)
## GrayboxMap.find_problems() must give the same problem lines as the reference, as sorted lists,
## and GrayboxMap.blocked_cells() the same cells. Also checks when the editor rechecks (recheck_due).
## Run from the repo folder:
##   godot --headless --path . --script res://game/maps/tools/test_graybox_grid.gd
## Exits with code 1 when any case is wrong, or when the layouts didn't reach every kind of problem.

const BLOCK_PATH: String = "res://game/maps/arena/block.tscn"
const SEED: int = 4801
const LAYOUTS: int = 300
const MAX_BLOCKS: int = 60
const START: String = "M0"
## Words from each kind of problem line this test must have compared at least once.
const KINDS: PackedStringArray = ["outer wall has a hole", "px apart", "is closer than", "is outside the walls", "can't be reached from", "open spots can't be reached", "off the 48 px grid"]


## A graybox map whose markers are the Marker2D children of Markers, checked like spawns.
class TestMap extends GrayboxMap:
	func _check_layout(blocks: Array[ArenaBlock], _cover: Array[ArenaBlock], problems: PackedStringArray) -> Dictionary:
		var points: Dictionary = {}
		for child: Node in get_node(^"Markers").get_children():
			_check_marker(String(child.name), child as Marker2D, blocks, points, problems)
		return points

	func _walk_start() -> String:
		return "M0"


var _block_scene: PackedScene
var _failed: int = 0
var _lines: int = 0
var _kinds: Dictionary[String, int] = {}


func _initialize() -> void:
	print("GRID TEST: seed %d, %d layouts" % [SEED, LAYOUTS])
	_block_scene = load(BLOCK_PATH) as PackedScene
	_check_recheck()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var cells: int = 0
	for layout: int in LAYOUTS:
		var map: TestMap = _random_map(rng)
		root.add_child(map)
		cells += _compare(layout, map)
		map.free()
	for kind: String in KINDS:
		var count: int = _kinds.get(kind, 0)
		print("  %d lines with \"%s\"" % [count, kind])
		if count == 0:
			_failed += 1
			printerr("  FAIL no layout gave a line with \"%s\": the layouts don't test it" % kind)
	print("GRID TEST: compared %d layouts, %d problem lines, %d cells" % [LAYOUTS, _lines, cells])
	if _lines == 0 or cells == 0:
		_failed += 1
		printerr("GRID TEST: FAIL, nothing was compared")
	print("GRID TEST: %s" % ("PASS" if _failed == 0 else "FAIL, %d wrong" % _failed))
	quit(0 if _failed == 0 else 1)


## The editor checks only once a layout has stopped changing, and never twice for one layout.
func _check_recheck() -> void:
	var cases: Array[Array] = [
		["layout stopped, not checked yet", 7, 7, 3, true],
		["layout still changing", 7, 6, 3, false],
		["layout already checked", 7, 7, 7, false],
		["first look after loading", 7, 0, 0, false],
	]
	for case: Array in cases:
		var due: bool = GrayboxMap.recheck_due(case[1], case[2], case[3])
		if due == case[4]:
			print("  ok   recheck: %s" % case[0])
		else:
			_failed += 1
			printerr("  FAIL recheck: %s: expected %s, got %s" % [case[0], case[4], due])


## Compares one layout's problem lines and blocked cells with the reference. Returns the cells compared.
func _compare(layout: int, map: TestMap) -> int:
	var got: PackedStringArray = map.find_problems()
	var expected: PackedStringArray = _reference_problems(map)
	var got_sorted: Array = Array(got)
	var expected_sorted: Array = Array(expected)
	got_sorted.sort()
	expected_sorted.sort()
	if got_sorted != expected_sorted:
		_failed += 1
		printerr("  FAIL layout %d (%s): expected %s, got %s" % [layout, map.map_size, expected_sorted, got_sorted])
	_lines += expected.size()
	for line: String in expected:
		for kind: String in KINDS:
			if line.contains(kind):
				_kinds[kind] = _kinds.get(kind, 0) + 1
	var cols: int = int(map.map_size.x / ArenaBlock.GRID)
	var rows: int = int(map.map_size.y / ArenaBlock.GRID)
	var rects: Array[Rect2] = _rects(map, _blocks_in(map, "Walls") + _blocks_in(map, "Cover"))
	if GrayboxMap.blocked_cells(rects, cols, rows) != _reference_blocked(rects, cols, rows):
		_failed += 1
		printerr("  FAIL layout %d (%s): blocked cells differ" % [layout, map.map_size])
	return cols * rows


# --- The reference: find_problems() as it was before A01, on rects. ---

## The old find_problems() flow: the unchanged checks run on the map, the changed ones from below.
func _reference_problems(map: TestMap) -> PackedStringArray:
	var problems: PackedStringArray = []
	var walls: Array[ArenaBlock] = _blocks_in(map, "Walls")
	var all: Array[ArenaBlock] = walls + _blocks_in(map, "Cover")
	var rects: Array[Rect2] = _rects(map, all)
	var labels: PackedStringArray = []
	for block: ArenaBlock in all:
		labels.append("%s/%s" % [block.get_parent().name, block.name])
	map._check_strays(problems)
	map._check_blocks(all, problems)
	_reference_walls(_rects(map, walls), map.map_size, problems)
	_reference_gaps(rects, labels, problems)
	var points: Dictionary = {}
	for child: Node in map.get_node(^"Markers").get_children():
		_reference_marker(String(child.name), map.to_local((child as Marker2D).global_position), rects, labels, map.map_size, points, problems)
	if points.has(START):
		_reference_walkable(rects, points, map.map_size, problems)
	return problems


## The old outer-wall check: every ring cell inside one wall rect.
func _reference_walls(rects: Array[Rect2], map_size: Vector2, problems: PackedStringArray) -> void:
	if rects.is_empty():
		problems.append("There are no outer walls.")
		return
	var cols: int = int(map_size.x / ArenaBlock.GRID)
	var rows: int = int(map_size.y / ArenaBlock.GRID)
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


## The old gap check: blocks touch or leave MIN_GAP, every pair.
func _reference_gaps(rects: Array[Rect2], labels: PackedStringArray, problems: PackedStringArray) -> void:
	for i: int in rects.size():
		for j: int in range(i + 1, rects.size()):
			var a: Rect2 = rects[i]
			var b: Rect2 = rects[j]
			var dx: float = maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
			var dy: float = maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
			var gap: float = Vector2(dx, dy).length()
			if gap > 0.0 and gap < GrayboxMap.MIN_GAP:
				problems.append("%s and %s are %.0f px apart. Make them touch or leave at least %.0f px." % [labels[i], labels[j], gap, GrayboxMap.MIN_GAP])


## The old marker check: inside the walls and SPAWN_ROOM from every block.
func _reference_marker(label: String, point: Vector2, rects: Array[Rect2], labels: PackedStringArray, map_size: Vector2, points: Dictionary, problems: PackedStringArray) -> void:
	if not Rect2(Vector2.ZERO, map_size).has_point(point):
		problems.append("%s is outside the walls." % label)
		return
	for i: int in rects.size():
		if point.distance_to(point.clamp(rects[i].position, rects[i].end)) < GrayboxMap.SPAWN_ROOM:
			problems.append("%s is closer than %.0f px to %s." % [label, GrayboxMap.SPAWN_ROOM, labels[i]])
			break
	points[label] = point


## Every cell tested against every rect, as the old check did.
func _reference_blocked(rects: Array[Rect2], cols: int, rows: int) -> PackedByteArray:
	var blocked: PackedByteArray = PackedByteArray()
	blocked.resize(cols * rows)
	for row: int in rows:
		for col: int in cols:
			var cell: Rect2 = Rect2(Vector2(col, row) * ArenaBlock.GRID, Vector2.ONE * ArenaBlock.GRID)
			for rect: Rect2 in rects:
				if cell.intersects(rect):
					blocked[row * cols + col] = 1
					break
	return blocked


## The old no-dead-ends check: flood fill from START over the old blocked cells.
func _reference_walkable(rects: Array[Rect2], points: Dictionary, map_size: Vector2, problems: PackedStringArray) -> void:
	var cols: int = int(map_size.x / ArenaBlock.GRID)
	var rows: int = int(map_size.y / ArenaBlock.GRID)
	var blocked: PackedByteArray = _reference_blocked(rects, cols, rows)
	var open_count: int = blocked.count(0)
	var start: int = _cell_index(points[START], cols)
	if blocked[start] == 1:
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
			if blocked[next] == 0 and reached[next] == 0:
				reached[next] = 1
				reached_count += 1
				stack.append(next)
	for label: String in points:
		if reached[_cell_index(points[label], cols)] == 0:
			problems.append("%s can't be reached from %s." % [label, START])
	if reached_count < open_count:
		for index: int in blocked.size():
			if blocked[index] == 0 and reached[index] == 0:
				@warning_ignore("integer_division")
				var spot: Vector2 = Vector2(index % cols, index / cols) * ArenaBlock.GRID
				problems.append("%d open spots can't be reached from %s, for example at %s." % [open_count - reached_count, START, spot])
				break


## The row-by-row index of the cell point sits in.
func _cell_index(point: Vector2, cols: int) -> int:
	var cell: Vector2i = Vector2i((point / ArenaBlock.GRID).floor())
	return cell.y * cols + cell.x


# --- Random layouts ---

## A map 3-40 cells each way: an outer ring (sometimes split, sometimes with a hole), cover
## blocks that touch, overlap, sit off the grid or past the walls, sometimes a sealed pocket,
## and 1-5 markers, some near a block or outside the walls. M0 is where the flood fill starts.
func _random_map(rng: RandomNumberGenerator) -> TestMap:
	var map: TestMap = TestMap.new()
	var cols: int = rng.randi_range(GrayboxMap.MIN_MAP_CELLS, 40)
	var rows: int = rng.randi_range(GrayboxMap.MIN_MAP_CELLS, 40)
	var g: float = ArenaBlock.GRID
	map.map_size = Vector2(cols, rows) * g
	var walls: Node2D = _group(map, "Walls")
	var cover: Node2D = _group(map, "Cover")
	var markers: Node2D = _group(map, "Markers")
	var ring: Array[Rect2] = [Rect2(0, 0, cols, 1), Rect2(0, rows - 1, cols, 1), Rect2(0, 1, 1, rows - 2), Rect2(cols - 1, 1, 1, rows - 2)]
	for rect: Rect2 in ring:
		if rect.size.x > 2 and rng.randf() < 0.3:
			var cut: int = rng.randi_range(1, int(rect.size.x) - 1)
			_add_block(walls, Rect2(rect.position, Vector2(cut, 1)))
			_add_block(walls, Rect2(rect.position + Vector2(cut, 0), Vector2(rect.size.x - cut, 1)))
		else:
			_add_block(walls, rect)
	if rng.randf() < 0.1 and walls.get_child_count() > 0:
		var shortened: ArenaBlock = walls.get_child(rng.randi() % walls.get_child_count()) as ArenaBlock
		shortened.size = (shortened.size - Vector2.ONE * g).max(Vector2.ONE * g)
	if rng.randf() < 0.25 and cols >= 5 and rows >= 5:
		var at: Vector2 = Vector2(rng.randi_range(1, cols - 4), rng.randi_range(1, rows - 4))
		_add_block(cover, Rect2(at, Vector2(3, 1)))
		_add_block(cover, Rect2(at + Vector2(0, 2), Vector2(3, 1)))
		_add_block(cover, Rect2(at + Vector2(0, 1), Vector2(1, 1)))
		_add_block(cover, Rect2(at + Vector2(2, 1), Vector2(1, 1)))
	var count: int = rng.randi_range(0, MAX_BLOCKS - walls.get_child_count() - cover.get_child_count())
	for i: int in count:
		var size: Vector2 = Vector2(rng.randi_range(1, mini(6, cols)), rng.randi_range(1, mini(6, rows)))
		var at: Vector2 = Vector2(rng.randi_range(-1, cols), rng.randi_range(-1, rows))
		var last: ArenaBlock = cover.get_child(cover.get_child_count() - 1) as ArenaBlock if cover.get_child_count() > 0 else null
		if last != null and rng.randf() < 0.2:
			at = (last.position + Vector2(last.size.x, 0)) / g
		var block: ArenaBlock = _add_block(cover, Rect2(at, size))
		if rng.randf() < 0.15:
			block.position += Vector2(rng.randf_range(-47.0, 47.0), rng.randf_range(-47.0, 47.0))
	for i: int in rng.randi_range(1, 5):
		var marker: Marker2D = Marker2D.new()
		marker.name = "M%d" % i if i > 0 else START
		marker.position = Vector2(rng.randf_range(-24.0, map.map_size.x + 24.0), rng.randf_range(-24.0, map.map_size.y + 24.0))
		if cover.get_child_count() > 0 and rng.randf() < 0.3:
			var near: ArenaBlock = cover.get_child(rng.randi() % cover.get_child_count()) as ArenaBlock
			marker.position = near.position + near.size + Vector2(rng.randf_range(0.0, 60.0), rng.randf_range(0.0, 60.0))
		markers.add_child(marker)
	return map


## Adds an empty child group (Walls, Cover or Markers) to map.
func _group(map: TestMap, group_name: String) -> Node2D:
	var group: Node2D = Node2D.new()
	group.name = group_name
	map.add_child(group)
	return group


## A block at cells.position with cells.size, both in cells.
func _add_block(parent: Node, cells: Rect2) -> ArenaBlock:
	var block: ArenaBlock = _block_scene.instantiate() as ArenaBlock
	block.name = "B%d" % parent.get_child_count()
	block.position = cells.position * ArenaBlock.GRID
	block.size = cells.size * ArenaBlock.GRID
	parent.add_child(block)
	return block


## The blocks under map's group, in order.
func _blocks_in(map: TestMap, group_name: String) -> Array[ArenaBlock]:
	var found: Array[ArenaBlock] = []
	for child: Node in map.get_node(group_name).get_children():
		found.append(child as ArenaBlock)
	return found


## Each block's rect worked out the old way, from its position in map space and its Size.
func _rects(map: TestMap, blocks: Array[ArenaBlock]) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for block: ArenaBlock in blocks:
		rects.append(Rect2(map.to_local(block.global_position), block.size))
	return rects

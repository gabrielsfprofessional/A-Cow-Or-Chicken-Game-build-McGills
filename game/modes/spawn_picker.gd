class_name SpawnPicker
extends RefCounted
## Which spawn point a returning hero gets (card T12). Owner: Adam (game/modes).
## Pure math, no nodes: ArenaRules hands it the allowed points and the living heroes.
## Distances are straight lines.


## Index into `points` of the point whose nearest enemy is farthest away. Ties go to
## the point whose nearest teammate is farthest away, then to the slot `stable`
## (0 up to 1) lands on among the points still tied, the way MapRules picks.
## Nobody on a side counts as infinitely far, so that rule ties everywhere.
## -1 when `points` is empty.
static func pick(points: Array[Vector2], enemies: Array[Vector2], teammates: Array[Vector2], stable: float) -> int:
	var tied: Array[int] = []
	for i: int in points.size():
		tied.append(i)
	tied = _farthest(points, tied, enemies)
	tied = _farthest(points, tied, teammates)
	if tied.is_empty():
		return -1
	var slot := int(stable * tied.size())
	return tied[clampi(slot, 0, tied.size() - 1)]


## Straight-line distance from `from` to the closest of `others`; INF when there are none.
static func nearest_distance(from: Vector2, others: Array[Vector2]) -> float:
	var nearest := INF
	for other: Vector2 in others:
		nearest = minf(nearest, from.distance_to(other))
	return nearest


## The indexes, in their order, whose nearest of `others` is farthest away (all that tie).
static func _farthest(points: Array[Vector2], indexes: Array[int], others: Array[Vector2]) -> Array[int]:
	var kept: Array[int] = []
	var best := -1.0
	for i: int in indexes:
		var distance := nearest_distance(points[i], others)
		if kept.is_empty() or (distance > best and not is_equal_approx(distance, best)):
			kept = [i]
			best = distance
		elif is_equal_approx(distance, best):
			kept.append(i)
			best = maxf(best, distance)
	return kept

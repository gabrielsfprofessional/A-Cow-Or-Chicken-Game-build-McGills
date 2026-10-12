class_name ChargeSweep
extends RefCounted
## The server's hit test for a Shield Charge dash (card T14). Owner: Gabe (game/heroes).
## No autoloads, so tests/charge_sweep_test.gd can run it against a real physics space.

## Physics layer 2 ("heroes"): what the sweep looks for.
const HERO_MASK: int = 2
## Most bodies one sweep reports. More than a match ever has.
const MAX_HITS: int = 32


## Every body on the heroes layer that the hero-sized `shape` touches on its way
## from `from` to `to`, except those in `exclude`. Eliminated heroes have their
## collider off, so they never show up.
static func find(space: PhysicsDirectSpaceState2D, shape: Shape2D, from: Vector2, to: Vector2,
		exclude: Array[RID]) -> Array[Node]:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, from)
	query.motion = to - from
	query.collision_mask = HERO_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = exclude
	var found: Array[Node] = []
	for hit: Dictionary in space.intersect_shape(query, MAX_HITS):
		var body := hit.collider as Node
		if body != null and not found.has(body):
			found.append(body)
	return found

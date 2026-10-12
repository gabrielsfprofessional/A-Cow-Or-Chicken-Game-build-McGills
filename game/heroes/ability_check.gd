class_name AbilityCheck
extends RefCounted
## The server's check on one hero's ability requests. Owner: Gabe (game/heroes). Card T14.
## Pure logic, like ShotCheck: the clock is passed in, so tests/ability_check_test.gd
## can drive it.
##
## The cooldown is booked on the server's clock when a request is accepted and is
## kept through death. The owner starts its own countdown only when the answer
## arrives, so an honest owner's next request always lands after the server's
## ready time; no slack is needed.

enum Result {
	ACCEPTED,
	WRONG_OWNER,   ## Sent by someone other than the hero's owner. Dropped.
	OTHER_LIFE,    ## Sent in another life (before a death). Answered, not logged.
	ELIMINATED,    ## The hero is eliminated. Answered, not logged.
	BAD_DIRECTION, ## NaN, INF or zero direction. Refused.
	COOLING_DOWN,  ## Asked before the cooldown ran out. Refused.
}

var owner_id: int
var cooldown_sec: float
## The accepted request's direction, normalized.
var direction: Vector2 = Vector2.RIGHT
## Refusals since the hero joined (the dropped and answered kinds not counted).
var refused: int = 0

var _ready_at_sec: float = -INF


func _init(owner_peer: int, cooldown: float) -> void:
	owner_id = owner_peer
	cooldown_sec = cooldown


## Checks one request. request_life is the life it was sent in; current_life and
## alive are the hero's now. On ACCEPTED, direction holds the normalized aim and
## the cooldown starts.
func check(sender_id: int, request_life: int, current_life: int, alive: bool,
		new_direction: Vector2, now_sec: float) -> Result:
	if sender_id != owner_id:
		return Result.WRONG_OWNER
	if request_life != current_life:
		return Result.OTHER_LIFE
	if not alive:
		return Result.ELIMINATED
	if not new_direction.is_finite() or new_direction.is_zero_approx():
		refused += 1
		return Result.BAD_DIRECTION
	if now_sec < _ready_at_sec:
		refused += 1
		return Result.COOLING_DOWN
	_ready_at_sec = now_sec + cooldown_sec
	direction = new_direction.normalized()
	return Result.ACCEPTED


## Seconds until the next request may be accepted; 0 when ready.
func ready_in_sec(now_sec: float) -> float:
	return maxf(0.0, _ready_at_sec - now_sec)


## True for the kinds that print an [Ability] line (an honest owner never causes one).
static func is_refusal(result: Result) -> bool:
	return result == Result.BAD_DIRECTION or result == Result.COOLING_DOWN


static func result_name(result: Result) -> String:
	return Result.keys()[result].to_lower().replace("_", " ")

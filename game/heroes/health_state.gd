class_name HealthState
extends RefCounted
## The rules for one hero's health. Owner: Gabe (game/heroes). Cards T08, T18.
## Pure logic, tested by tests/health_test.gd. Health (health.gd) wraps it.

var max_health: int
var health: int
var eliminated: bool = false


func _init(start_health: int) -> void:
	max_health = maxi(1, start_health)
	health = max_health


## Takes up to `amount` health and returns how much it took. Nothing while
## eliminated or for amount <= 0. Health never goes below 0; reaching 0 eliminates.
func damage(amount: int) -> int:
	if eliminated or amount <= 0:
		return 0
	var taken := mini(amount, health)
	health -= taken
	if health == 0:
		eliminated = true
	return taken


## Gives back up to `amount` health and returns how much it gave (T18). Nothing
## while eliminated or for amount <= 0. Health never goes above max_health.
func heal(amount: int) -> int:
	if eliminated or amount <= 0:
		return 0
	var healed := mini(amount, max_health - health)
	health += healed
	return healed


## Back to full health and alive.
func restore() -> void:
	health = max_health
	eliminated = false


## Client mirror: the health the server says the hero has after a hit.
func mirror(health_after: int) -> void:
	if eliminated:
		return
	health = clampi(health_after, 0, max_health)


## Client mirror: the server says the hero is eliminated.
func eliminate() -> void:
	health = 0
	eliminated = true


## Late join: take the server's whole state at once. An eliminated hero has 0 health.
func sync(new_health: int, is_eliminated: bool) -> void:
	eliminated = is_eliminated
	health = 0 if is_eliminated else clampi(new_health, 0, max_health)

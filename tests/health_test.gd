extends SceneTree
## Tests for HealthState and Health (cards T08, T18). Owner: Gabe.
## Run: godot --headless --path . --script res://tests/health_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.

const HealthStateScript: GDScript = preload("res://game/heroes/health_state.gd")
const HealthScene: PackedScene = preload("res://game/heroes/health.tscn")

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_damage()
	_floor_at_zero()
	_eliminated_exactly_once()
	_no_damage_while_eliminated()
	_respawn_restores()
	_ignores_bad_amounts()
	_late_join_sync()
	_client_mirror()
	_heal()
	_heal_caps_at_max()
	_no_heal_while_eliminated()
	_heal_ignores_bad_amounts()
	_health_heal_signal()
	_client_heal_mirror()
	print("HEALTH TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _new_state() -> HealthState:
	return HealthStateScript.new(100)


## A Health node in the tree, with counters on its signals.
func _new_health() -> Array:
	var health := HealthScene.instantiate() as Health
	root.add_child(health)
	var counts := {"damaged": 0, "eliminated": 0, "restored": 0, "last_after": -1, "healed": 0, "healed_amount": 0, "healed_after": -1}
	health.damaged.connect(func(_amount: int, _attacker: int, _shot: int, after: int, _at: Vector2) -> void:
		counts.damaged += 1
		counts.last_after = after
	)
	health.eliminated.connect(func(_attacker: int) -> void: counts.eliminated += 1)
	health.restored.connect(func() -> void: counts.restored += 1)
	health.healed.connect(func(amount: int, _healer: int, after: int) -> void:
		counts.healed += 1
		counts.healed_amount = amount
		counts.healed_after = after
	)
	return [health, counts]


func _damage() -> void:
	var state := _new_state()
	_expect_true("a hit takes its damage", state.damage(20) == 20 and state.health == 80)
	_expect_true("and leaves the hero alive", not state.eliminated)


func _floor_at_zero() -> void:
	var state := _new_state()
	state.damage(90)
	_expect_true("an overkill hit only takes what is left", state.damage(20) == 10)
	_expect_true("health stops at 0", state.health == 0)


func _eliminated_exactly_once() -> void:
	var pair := _new_health()
	var health := pair[0] as Health
	var counts: Dictionary = pair[1]
	for i: int in range(7):
		health.take_damage(20, 9, i + 1, Vector2.ZERO)
	_expect_true("five hits of 20 eliminate (saw %d damaged)" % counts.damaged, counts.damaged == 5 and not health.is_alive())
	_expect_true("eliminated fires exactly once (saw %d)" % counts.eliminated, counts.eliminated == 1)
	health.free()


func _no_damage_while_eliminated() -> void:
	var state := _new_state()
	state.damage(100)
	_expect_true("no damage while eliminated", state.damage(20) == 0 and state.health == 0 and state.eliminated)


func _respawn_restores() -> void:
	var pair := _new_health()
	var health := pair[0] as Health
	var counts: Dictionary = pair[1]
	health.take_damage(100, 9, 1, Vector2.ZERO)
	health.restore()
	_expect_true("respawn restores full health", health.is_alive() and health.health() == 100 and counts.restored == 1)
	_expect_true("and the hero can be hit again", health.take_damage(20, 9, 2, Vector2.ZERO) == 20)
	health.free()


func _ignores_bad_amounts() -> void:
	var state := _new_state()
	_expect_true("zero or negative damage does nothing", state.damage(0) == 0 and state.damage(-5) == 0 and state.health == 100)


func _late_join_sync() -> void:
	var pair := _new_health()
	var health := pair[0] as Health
	var counts: Dictionary = pair[1]
	health.sync(40, false)
	_expect_true("sync sets a damaged hero's health", health.health() == 40 and health.is_alive())
	health.sync(0, true)
	_expect_true("sync eliminates", not health.is_alive() and health.health() == 0)
	_expect_true("sync emits nothing", counts.damaged == 0 and counts.eliminated == 0 and counts.restored == 0)
	health.sync(70, true)
	_expect_true("an eliminated hero always has 0 health", health.health() == 0)
	health.sync(500, false)
	_expect_true("sync clamps to max health", health.health() == 100)
	health.sync(30, true)
	health.restore()
	_expect_true("a synced elimination ends with a respawn", health.is_alive() and health.health() == 100)
	health.free()


func _client_mirror() -> void:
	var pair := _new_health()
	var health := pair[0] as Health
	var counts: Dictionary = pair[1]
	health.show_damage(20, 9, 1, 80, Vector2.ZERO)
	_expect_true("a mirrored hit takes the server's health", health.health() == 80 and counts.last_after == 80)
	health.show_damage(20, 9, 2, 0, Vector2.ZERO)
	_expect_true("a mirrored hit to 0 waits for the elimination message", health.is_alive())
	health.show_elimination(9)
	health.show_elimination(9)
	_expect_true("a mirrored elimination fires once", not health.is_alive() and counts.eliminated == 1)
	health.free()


# --- healing (T18) -----------------------------------------------------------------

func _heal() -> void:
	var state := _new_state()
	state.damage(50)
	_expect_true("a heal gives its amount and returns it", state.heal(5) == 5 and state.health == 55)


func _heal_caps_at_max() -> void:
	var state := _new_state()
	state.damage(3)
	_expect_true("a heal near max returns only what fit", state.heal(5) == 3 and state.health == 100)
	_expect_true("a heal at max returns 0", state.heal(5) == 0 and state.health == 100)


func _no_heal_while_eliminated() -> void:
	var state := _new_state()
	state.damage(100)
	_expect_true("no heal while eliminated", state.heal(5) == 0 and state.health == 0 and state.eliminated)


func _heal_ignores_bad_amounts() -> void:
	var state := _new_state()
	state.damage(50)
	_expect_true("zero or negative heal does nothing", state.heal(0) == 0 and state.heal(-5) == 0 and state.health == 50)


func _health_heal_signal() -> void:
	var pair := _new_health()
	var health := pair[0] as Health
	var counts: Dictionary = pair[1]
	health.take_damage(20, 9, 1, Vector2.ZERO)
	_expect_true("Health.heal returns what it gave", health.heal(5, 7) == 5 and health.health() == 85)
	_expect_true("and emits healed once with it", counts.healed == 1 and counts.healed_amount == 5 and counts.healed_after == 85)
	health.heal(50, 7)
	_expect_true("a heal to max emits what fit", counts.healed == 2 and counts.healed_amount == 15 and health.health() == 100)
	health.heal(5, 7)
	_expect_true("a heal that gives nothing emits nothing", counts.healed == 2)
	health.take_damage(100, 9, 2, Vector2.ZERO)
	_expect_true("an eliminated hero is not healed", health.heal(5, 7) == 0 and counts.healed == 2 and health.health() == 0)
	health.free()


func _client_heal_mirror() -> void:
	var pair := _new_health()
	var health := pair[0] as Health
	var counts: Dictionary = pair[1]
	health.show_damage(30, 9, 1, 70, Vector2.ZERO)
	health.show_heal(5, 7, 75)
	_expect_true("a mirrored heal takes the server's health", health.health() == 75 and counts.healed == 1 and counts.healed_after == 75)
	health.show_elimination(9)
	health.show_heal(5, 7, 80)
	_expect_true("a mirrored heal while eliminated does nothing", health.health() == 0 and counts.healed == 1)
	health.free()


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

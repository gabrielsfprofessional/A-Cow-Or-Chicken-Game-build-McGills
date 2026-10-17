class_name MatchRules
extends RefCounted
## Who hits whom, where and when heroes respawn, and spawn protection. Server
## only. Owner: Gabe (game/core). Week-3 seams for Adam's T12 and T15.
##
## These defaults are the game before teams: no teams, everyone hits and heals
## everyone, the T06 respawn ring, combat.tres respawn_sec, no protection.
## A mode extends this class, overrides what it needs and installs it on the
## server with world.set_rules(...) before heroes spawn. Heroes, shots and bots
## ask the world for it, the same way they ask for respawn_point() and shots().

const COMBAT: CombatData = preload("res://game/heroes/data/combat.tres")
## The T06 ring: every hero's spot around the middle of the 1920x1080 test world.
const RING_RADIUS: float = 260.0
const WORLD_CENTER: Vector2 = Vector2(960.0, 540.0)
## Golden-ratio step, so nearby peer ids land far apart on the ring.
const RING_STEP: float = 0.618034


## The peer's team (0 = Blue, 1 = Orange), or -1 for none.
func team_of(_peer_id: int) -> int:
	return -1


## True when a's shots and Shield Charge should hurt b. Never true for a == b.
## Default: everyone else is an enemy.
func is_enemy(a: int, b: int) -> bool:
	return a != b


## Where the hero spawns and respawns.
func respawn_point(peer_id: int) -> Vector2:
	var angle := fposmod(float(peer_id) * RING_STEP, 1.0) * TAU
	return WORLD_CENTER + Vector2(cos(angle), sin(angle)) * RING_RADIUS


## Seconds from elimination to respawn.
func respawn_delay_sec(_peer_id: int) -> float:
	return COMBAT.respawn_sec


## Seconds after each respawn with no damage and no knockback (healing still works).
func spawn_protection_sec() -> float:
	return 0.0


## Not for overriding: who the Heal Drone heals. Self, everyone while the healer
## has no team, else non-enemies.
func can_heal(healer: int, target: int) -> bool:
	return healer == target or team_of(healer) < 0 or not is_enemy(healer, target)

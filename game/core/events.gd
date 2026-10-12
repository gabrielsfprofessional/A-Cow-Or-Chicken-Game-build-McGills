extends Node
## Signal bus (autoload "Events"). Systems talk through these signals instead of
## holding references to each other. Owner: Gabe (game/core).
## Add a signal here before any system emits or listens to it.

@warning_ignore("unused_signal")
signal match_started(mode: StringName)
@warning_ignore("unused_signal")
signal match_ended(winning_team: int)
## Combat (T08). All three fire on every peer: on the server when it decides,
## on each client when the server's message arrives.
@warning_ignore("unused_signal")
signal hero_damaged(victim_peer_id: int, attacker_peer_id: int, amount: int, position: Vector2)
@warning_ignore("unused_signal")
signal hero_eliminated(victim_peer_id: int, attacker_peer_id: int)
@warning_ignore("unused_signal")
signal hero_respawned(peer_id: int, position: Vector2)
## Abilities (T14). Both fire on every peer, like hero_damaged. ready_in_sec is
## how long until that hero's Q works again (exact on its owner and the server).
@warning_ignore("unused_signal")
signal ability_used(peer_id: int, ready_in_sec: float)
@warning_ignore("unused_signal")
signal hero_knocked_back(victim_peer_id: int, attacker_peer_id: int)
@warning_ignore("unused_signal")
signal profile_changed()

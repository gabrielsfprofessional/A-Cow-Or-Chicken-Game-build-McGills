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
@warning_ignore("unused_signal")
signal profile_changed()

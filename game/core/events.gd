extends Node
## Signal bus (autoload "Events"). Systems talk through these signals instead of
## holding references to each other. Owner: Gabe (game/core).
## Add a signal here before any system emits or listens to it.

@warning_ignore("unused_signal")
signal match_started(mode: StringName)
# Match (week-3 seams, for T15-T17). Teams: 0 = Blue #3B82F6, 1 = Orange #F97316.
# Adam's mode emits these on every peer (the server and each client) and
# replays the current state to a late joiner once the server has its
# client_ready (world.is_peer_ready()). Gabe's code only listens; the world
# keeps the teams it heard (teams_seen()), so the replay may come before or
# after the joiner's hero spawns.

## The match is over. winning_team is 0 or 1, or -1 for a draw.
@warning_ignore("unused_signal")
signal match_ended(winning_team: int)
## This peer is on this team (0 or 1) for the match.
@warning_ignore("unused_signal")
signal team_assigned(peer_id: int, team: int)
## A team's score is now `score`.
@warning_ignore("unused_signal")
signal team_score_changed(team: int, score: int)
## Whole seconds left on the match clock; at most once a second.
@warning_ignore("unused_signal")
signal match_clock_changed(seconds_left: int)
## Combat (T08). All three fire on every peer: on the server when it decides,
## on each client when the server's message arrives.
## hero_damaged's amount can be 0: a hit absorbed by spawn protection (the shot
## still ends on that hero). Skip numbers, sounds and assists for 0.
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
## Healing (T18). Fires on every peer like hero_damaged, only when amount > 0.
@warning_ignore("unused_signal")
signal hero_healed(peer_id: int, healer_peer_id: int, amount: int)
@warning_ignore("unused_signal")
signal profile_changed()

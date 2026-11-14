class_name MatchStats
extends RefCounted
## What each peer did in the match being played, for the player saves (card T22).
## Owner: Gabe (server). No network and no files: Net feeds it the Events signals on
## the server and hands what it answers to PlayerRegistry.add_stats().
## tests/match_stats_test.gd drives it.
##
## - Counts only between match_started and match_ended: damage dealt (amount above 0,
##   never to yourself) and eliminations (by a peer, never of yourself).
## - Teams are kept from every team_assigned, in a match or not: a mode gives them
##   when a player arrives and keeps them into the next match.
## - match_ended(): each peer on a team gets a match, a win when its team won (none on
##   a draw), what it counted and its hero.
## - peer_left(): a peer that leaves mid-match keeps what it counted, with no match.
## - A match nobody finishes never reaches match_ended, so it counts nothing more.
##
## An answer is a delta in the shape of a save's "stats":
## {"matches", "wins", "eliminations", "damage", "heroes": {<hero file name>: 1}}.

const TEAM_COUNT: int = 2

var _playing: bool = false
## Peer id -> team (0 or 1), from team_assigned. A peer that left is not here.
var _teams: Dictionary[int, int] = {}
## Peer id -> eliminations in this match. A leaver's shot still in flight can put it back
## here; with no team it gets nothing at match_ended, and the next start or end clears it.
var _eliminations: Dictionary[int, int] = {}
## Peer id -> damage dealt in this match (a leaver can come back here the same way).
var _damage: Dictionary[int, int] = {}


## True between match_started() and match_ended().
func is_playing() -> bool:
	return _playing


## A match starts: every count is 0 again. Teams stay.
func match_started() -> void:
	_playing = true
	_eliminations.clear()
	_damage.clear()


## A peer is on a team (0 or 1). Anything else is ignored.
func team_assigned(peer_id: int, team: int) -> void:
	if team < 0 or team >= TEAM_COUNT:
		return
	_teams[peer_id] = team


## A hero was hit. Counts for the attacker during a match, when the amount is above 0
## (0 is a hit that spawn protection absorbed) and it didn't hit itself.
func hero_damaged(victim_peer_id: int, attacker_peer_id: int, amount: int) -> void:
	if not _playing or amount <= 0 or attacker_peer_id <= 0 or attacker_peer_id == victim_peer_id:
		return
	_damage[attacker_peer_id] = int(_damage.get(attacker_peer_id, 0)) + amount


## A hero was eliminated. Counts for the attacker during a match, when a peer did it
## (attacker above 0) and it wasn't itself.
func hero_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	if not _playing or attacker_peer_id <= 0 or attacker_peer_id == victim_peer_id:
		return
	_eliminations[attacker_peer_id] = int(_eliminations.get(attacker_peer_id, 0)) + 1


## A peer left. Answers its eliminations and damage of the match being played, with no
## match and no hero, or {} when it counted nothing. The peer is forgotten either way.
func peer_left(peer_id: int) -> Dictionary:
	var eliminations: int = _eliminations.get(peer_id, 0)
	var damage: int = _damage.get(peer_id, 0)
	_teams.erase(peer_id)
	_eliminations.erase(peer_id)
	_damage.erase(peer_id)
	# Outside a match both are 0: match_started() and match_ended() clear the counts.
	if eliminations == 0 and damage == 0:
		return {}
	return _delta(0, 0, eliminations, damage, "")


## The match is over; winning_team is 0 or 1, or -1 for a draw. Answers one delta per
## peer on a team: peer id -> delta. hero_of.call(peer_id) gives the file name of the
## hero that peer plays ("" when it has none: then no hero is counted). {} when no
## match was being played.
func match_ended(winning_team: int, hero_of: Callable) -> Dictionary[int, Dictionary]:
	var deltas: Dictionary[int, Dictionary] = {}
	if not _playing:
		return deltas
	_playing = false
	for peer_id: int in _teams:
		# A draw's -1 is no team, so nobody wins it.
		var won: bool = _teams[peer_id] == winning_team
		var hero: Variant = hero_of.call(peer_id)
		deltas[peer_id] = _delta(1, 1 if won else 0, _eliminations.get(peer_id, 0), _damage.get(peer_id, 0),
			hero if hero is String else "")
	_eliminations.clear()
	_damage.clear()
	return deltas


## The peers this class knows: on a team, or with a count in the match being played.
func peers() -> Array[int]:
	var known: Array[int] = _teams.keys()
	for peer_id: int in _eliminations.keys() + _damage.keys():
		if not known.has(peer_id):
			known.append(peer_id)
	return known


## One answer for one peer: what to add to its save.
static func _delta(matches: int, wins: int, eliminations: int, damage: int, hero: String) -> Dictionary:
	var heroes: Dictionary = {}
	if hero != "":
		heroes[hero] = 1
	return {"matches": matches, "wins": wins, "eliminations": eliminations, "damage": damage, "heroes": heroes}

class_name TeamBook
extends RefCounted
## Who plays for which team in the arena (card T15). Server only, no network:
## ArenaTeamRules asks it, ArenaMode tells everyone. Owner: Adam (game/modes).
##
## - A new peer gets a team the first time anyone asks team_of() (the server asks
##   for its spawn point before its hero exists): the smaller team, then the team
##   behind on score, then Blue.
## - When someone leaves and one team is 2 bigger, its newest player moves over.
## - A peer that left keeps its last team for its shots still in flight (ShotSim asks
##   about the shooter every step, and its last shot can still eliminate someone),
##   is never counted in team sizes and is never given a team again.
##   new_match() forgets its team (world.respawn_all() clears the shots).

## A peer got a team, or moved to the other one to even the sizes.
signal team_changed(peer_id: int, team: int)

const BLUE: int = 0
const ORANGE: int = 1
const NO_TEAM: int = -1

## Optional: (team: int) -> int, that team's score, for the join tie-break.
var score_of: Callable = Callable()

## Playing peers -> team.
var _team: Dictionary[int, int] = {}
## Playing peers, oldest first, so the newest is the one that moves.
var _order: Array[int] = []
## Peers that left this match -> their last team.
var _left_team: Dictionary[int, int] = {}
## Every peer that ever left. Never given a team again.
var _gone: Dictionary[int, bool] = {}


## The peer's team. A new peer gets one now (see the top of this file); a peer that
## left gets its last team, or none, and never a new one. Ids 0 and 1 (no peer,
## the server) never get one.
func team_of(peer_id: int) -> int:
	var known := peek(peer_id)
	if known != NO_TEAM or peer_id <= 1 or _gone.has(peer_id):
		return known
	var team := _pick_team()
	_team[peer_id] = team
	_order.append(peer_id)
	team_changed.emit(peer_id, team)
	return team


## The peer's team without giving it one: playing, or left this match, else -1.
func peek(peer_id: int) -> int:
	if _team.has(peer_id):
		return _team[peer_id]
	return _left_team.get(peer_id, NO_TEAM)


## Playing peers on each team: [Blue, Orange]. Peers that left never count.
func sizes() -> PackedInt32Array:
	var counts := PackedInt32Array([0, 0])
	for peer_id: int in _team:
		counts[_team[peer_id]] += 1
	return counts


## How many peers play for a team.
func player_count() -> int:
	return _team.size()


## Playing peers -> team, a copy.
func playing() -> Dictionary[int, int]:
	return _team.duplicate()


## The peer left. Returns the peers moved to even the teams (each told by team_changed).
func peer_left(peer_id: int) -> Array[int]:
	_gone[peer_id] = true
	if not _team.has(peer_id):
		return []
	_left_team[peer_id] = _team[peer_id]
	_team.erase(peer_id)
	_order.erase(peer_id)
	return _even_out()


## A new match: peers that left are forgotten (their shots are gone). They still
## never get a team again.
func new_match() -> void:
	_left_team.clear()


## While one team is 2 or more bigger, its newest player moves to the other.
func _even_out() -> Array[int]:
	var moved: Array[int] = []
	var counts := sizes()
	while absi(counts[BLUE] - counts[ORANGE]) >= 2:
		var big := BLUE if counts[BLUE] > counts[ORANGE] else ORANGE
		var newest := 0
		for i: int in range(_order.size() - 1, -1, -1):
			if _team[_order[i]] == big:
				newest = _order[i]
				break
		var small := 1 - big
		_team[newest] = small
		counts[big] -= 1
		counts[small] += 1
		moved.append(newest)
		team_changed.emit(newest, small)
	return moved


func _pick_team() -> int:
	var counts := sizes()
	if counts[BLUE] != counts[ORANGE]:
		return BLUE if counts[BLUE] < counts[ORANGE] else ORANGE
	if score_of.is_valid():
		var blue_score := int(score_of.call(BLUE))
		var orange_score := int(score_of.call(ORANGE))
		if orange_score < blue_score:
			return ORANGE
	return BLUE

class_name ArenaMatch
extends RefCounted
## One arena match's scores, clock and winner (card T15). No network: ArenaMode
## feeds it and tells everyone. Owner: Adam (game/modes).
## A match ends when a team reaches the score limit (score_per_player x players)
## or the clock runs out (the higher score wins; equal is a draw). The next one
## starts next_match_delay_sec later.

enum Phase { WAITING, PLAYING, OVER }

## What tick() saw happen.
enum Tick { NOTHING, ENDED, RESTART }

const DRAW: int = -1

var phase: Phase = Phase.WAITING
## [Blue, Orange].
var scores: PackedInt32Array = PackedInt32Array([0, 0])
var seconds_left: float = 0.0
## 0 or 1, or DRAW. Meaningful once the phase is OVER.
var winner: int = DRAW

var _length_sec: float
var _score_per_player: int
var _restart_delay_sec: float
var _restart_in: float = 0.0


func _init(length_sec: float, score_per_player: int, restart_delay_sec: float) -> void:
	_length_sec = length_sec
	_score_per_player = score_per_player
	_restart_delay_sec = restart_delay_sec


## A fresh match: scores 0, the full clock.
func start() -> void:
	phase = Phase.PLAYING
	scores = PackedInt32Array([0, 0])
	seconds_left = _length_sec
	winner = DRAW


## Nobody is playing: wait for the next player.
func stop() -> void:
	phase = Phase.WAITING
	scores = PackedInt32Array([0, 0])
	seconds_left = _length_sec
	winner = DRAW


## The score that wins with this many players (at least 1).
func score_limit(players: int) -> int:
	return maxi(1, _score_per_player * players)


## Whole seconds on the clock, as the HUD shows them.
func clock() -> int:
	return ceili(seconds_left)


## One point for `team` while the match is on. False when it didn't count.
func add_point(team: int) -> bool:
	if phase != Phase.PLAYING or team < 0 or team > 1:
		return false
	scores[team] += 1
	return true


## Ends the match when a team has reached the limit for this many players. True when it ended.
func check_limit(players: int) -> bool:
	if phase != Phase.PLAYING or maxi(scores[0], scores[1]) < score_limit(players):
		return false
	_end()
	return true


## Runs the clock and the wait for the next match.
func tick(delta: float) -> Tick:
	if phase == Phase.PLAYING:
		seconds_left = maxf(0.0, seconds_left - delta)
		if seconds_left <= 0.0:
			_end()
			return Tick.ENDED
	elif phase == Phase.OVER:
		_restart_in -= delta
		if _restart_in <= 0.0:
			start()
			return Tick.RESTART
	return Tick.NOTHING


func _end() -> void:
	phase = Phase.OVER
	_restart_in = _restart_delay_sec
	if scores[0] == scores[1]:
		winner = DRAW
	else:
		winner = 0 if scores[0] > scores[1] else 1

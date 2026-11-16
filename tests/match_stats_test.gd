extends SceneTree
## Tests for the match's stats (card T22): MatchStats counts damage and eliminations
## between match_started and match_ended, and answers what each peer's save gains.
## Owner: Gabe.
## Run: godot --headless --path . --script res://tests/match_stats_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.

const BLUE: int = 0
const ORANGE: int = 1
const DRAW: int = -1
## Peers: A and B on Blue, C on Orange.
const A: int = 11
const B: int = 12
const C: int = 13
const HEROES: Dictionary[int, String] = {A: "scout", B: "bruiser", C: "mage"}

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_a_win()
	_a_draw()
	_outside_a_match()
	_hits_that_never_count()
	_a_leaver()
	_nobody_finishes()
	_teams()
	_a_peer_with_no_hero()
	_ended_twice()
	print("MATCH STATS TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


## Blue wins: every peer on a team gets a match, its counts and its hero; only Blue a win.
func _a_win() -> void:
	var stats: MatchStats = _three_players()
	_expect_true("no match is being played before match_started", not stats.is_playing())
	stats.match_started()
	_expect_true("a match is being played after match_started", stats.is_playing())
	stats.hero_damaged(C, A, 30)
	stats.hero_damaged(C, A, 45)
	stats.hero_eliminated(C, A)
	stats.hero_damaged(A, C, 20)
	stats.hero_eliminated(C, B)
	var deltas: Dictionary[int, Dictionary] = stats.match_ended(BLUE, _hero_of)
	_expect_true("a match is over after match_ended", not stats.is_playing())
	_expect_true("three peers on teams: three answers", deltas.size() == 3)
	_expect_equal("the winner who hit twice and eliminated once", deltas.get(A),
		{"matches": 1, "wins": 1, "eliminations": 1, "damage": 75, "heroes": {"scout": 1}})
	_expect_equal("a winner with an elimination and no damage", deltas.get(B),
		{"matches": 1, "wins": 1, "eliminations": 1, "damage": 0, "heroes": {"bruiser": 1}})
	_expect_equal("the loser: a match, no win, its damage", deltas.get(C),
		{"matches": 1, "wins": 0, "eliminations": 0, "damage": 20, "heroes": {"mage": 1}})
	# The next match starts from 0, with the same teams.
	stats.match_started()
	stats.hero_damaged(A, C, 10)
	deltas = stats.match_ended(ORANGE, _hero_of)
	_expect_equal("the next match counts from 0 and Orange wins it", deltas.get(C),
		{"matches": 1, "wins": 1, "eliminations": 0, "damage": 10, "heroes": {"mage": 1}})
	_expect_equal("and Blue keeps its team into the next match, without a win", deltas.get(A),
		{"matches": 1, "wins": 0, "eliminations": 0, "damage": 0, "heroes": {"scout": 1}})


## A draw (-1): every player on a team gets the match and its hero, nobody a win.
func _a_draw() -> void:
	var stats: MatchStats = _three_players()
	stats.match_started()
	stats.hero_eliminated(C, A)
	var deltas: Dictionary[int, Dictionary] = stats.match_ended(DRAW, _hero_of)
	var wins: int = 0
	for peer_id: int in deltas:
		wins += int(deltas[peer_id]["wins"])
	_expect_true("a draw: a match for everyone, a win for no one", deltas.size() == 3 and wins == 0
		and deltas[A]["matches"] == 1 and deltas[A]["eliminations"] == 1)
	_expect_equal("a draw: Orange gets its match and hero too", deltas.get(C),
		{"matches": 1, "wins": 0, "eliminations": 0, "damage": 0, "heroes": {HEROES[C]: 1}})


## Before the first match, and between match_ended and the next match_started.
func _outside_a_match() -> void:
	var stats: MatchStats = _three_players()
	stats.hero_damaged(C, A, 50)
	stats.hero_eliminated(C, A)
	stats.match_started()
	var deltas: Dictionary[int, Dictionary] = stats.match_ended(BLUE, _hero_of)
	_expect_true("a hit and an elimination before match_started count nothing",
		deltas[A]["damage"] == 0 and deltas[A]["eliminations"] == 0)
	stats.hero_damaged(C, A, 50)
	stats.hero_eliminated(C, A)
	stats.match_started()
	deltas = stats.match_ended(BLUE, _hero_of)
	_expect_true("a hit and an elimination after match_ended count nothing",
		deltas[A]["damage"] == 0 and deltas[A]["eliminations"] == 0)


## Hits and eliminations that never count: 0 or less damage, yourself, and no peer (0, -1).
func _hits_that_never_count() -> void:
	var stats: MatchStats = _three_players()
	stats.match_started()
	stats.hero_damaged(C, A, 0)
	stats.hero_damaged(C, A, -5)
	stats.hero_damaged(A, A, 40)
	stats.hero_eliminated(A, A)
	stats.hero_eliminated(A, 0)
	stats.hero_damaged(A, 0, 40)
	stats.hero_eliminated(A, -1)
	_expect_true("an elimination or a hit by no peer (0, -1) is kept for no one",
		not stats.peers().has(0) and not stats.peers().has(-1) and stats.peer_left(0).is_empty() and stats.peer_left(-1).is_empty())
	var deltas: Dictionary[int, Dictionary] = stats.match_ended(BLUE, _hero_of)
	_expect_true("a 0-damage hit (spawn protection) and a negative one count nothing", deltas[A]["damage"] == 0)
	_expect_true("hitting or eliminating yourself counts nothing", deltas[A]["eliminations"] == 0)
	_expect_true("and makes no answer at the end", deltas.size() == 3)
	stats.match_started()
	stats.hero_damaged(C, A, 1)
	deltas = stats.match_ended(BLUE, _hero_of)
	_expect_true("a 1-damage hit counts 1", deltas[A]["damage"] == 1)


## A peer that leaves mid-match keeps its eliminations and damage, with no match.
func _a_leaver() -> void:
	var stats: MatchStats = _three_players()
	stats.match_started()
	stats.hero_damaged(C, A, 60)
	stats.hero_eliminated(C, A)
	_expect_equal("a leaver keeps its counts, with no match, win or hero", stats.peer_left(A),
		{"matches": 0, "wins": 0, "eliminations": 1, "damage": 60, "heroes": {}})
	_expect_equal("leaving twice answers nothing the second time", stats.peer_left(A), {})
	_expect_equal("a peer that counted nothing leaves with nothing", stats.peer_left(B), {})
	stats.hero_eliminated(C, A)  # A shot of A's still in flight.
	var deltas: Dictionary[int, Dictionary] = stats.match_ended(BLUE, _hero_of)
	_expect_true("the match ends without the leavers", deltas.size() == 1 and deltas.has(C))
	stats.hero_damaged(A, C, 30)
	stats.hero_eliminated(A, C)
	_expect_equal("leaving between matches answers nothing", stats.peer_left(C), {})
	_expect_true("everyone who left is forgotten", stats.peers().is_empty())


## Everyone leaves, so the mode never says match_ended: the next match starts clean.
func _nobody_finishes() -> void:
	var stats: MatchStats = _three_players()
	stats.match_started()
	stats.hero_damaged(C, A, 60)
	for peer_id: int in [A, B, C]:
		stats.peer_left(peer_id)
	stats.team_assigned(A, BLUE)
	stats.match_started()
	var deltas: Dictionary[int, Dictionary] = stats.match_ended(BLUE, _hero_of)
	_expect_equal("the unfinished match adds nothing to the next one", deltas.get(A),
		{"matches": 1, "wins": 1, "eliminations": 0, "damage": 0, "heroes": {"scout": 1}})
	_expect_true("and only the peer that came back gets a match", deltas.size() == 1)
	# A match that starts again without ending (nobody left): its counts are dropped too.
	stats = _three_players()
	stats.match_started()
	stats.hero_damaged(C, A, 60)
	stats.hero_eliminated(C, A)
	stats.match_started()
	deltas = stats.match_ended(BLUE, _hero_of)
	_expect_true("a match that starts again without ending keeps no counts",
		deltas[A]["damage"] == 0 and deltas[A]["eliminations"] == 0 and deltas[A]["matches"] == 1)


## Teams: a late joiner, a balance move (the last team counts) and a team that isn't 0 or 1.
func _teams() -> void:
	var stats := MatchStats.new()
	stats.team_assigned(A, BLUE)
	stats.match_started()
	stats.team_assigned(B, ORANGE)  # A late joiner.
	stats.team_assigned(A, ORANGE)  # Moved by the balance: the last team counts.
	stats.team_assigned(C, 2)
	stats.team_assigned(C, -1)
	stats.hero_damaged(A, C, 25)  # C is on no team.
	_expect_true("peers() names a peer with a count and no team", stats.peers().has(C) and stats.peers().size() == 3)
	var deltas: Dictionary[int, Dictionary] = stats.match_ended(ORANGE, _hero_of)
	_expect_true("a late joiner on a team gets the match", deltas.has(B) and deltas[B]["matches"] == 1 and deltas[B]["wins"] == 1)
	_expect_true("a peer moved to the other team wins or loses with its last team", deltas.has(A) and deltas[A]["wins"] == 1)
	_expect_true("a team that isn't 0 or 1 is no team: no match for that peer", not deltas.has(C))
	_expect_true("peers() names every peer it knows", stats.peers().has(A) and stats.peers().has(B))


## A peer with no hero, or a hero that isn't text, gets the match and no hero count.
func _a_peer_with_no_hero() -> void:
	var stats := MatchStats.new()
	stats.team_assigned(99, BLUE)
	stats.match_started()
	var deltas: Dictionary[int, Dictionary] = stats.match_ended(BLUE, _hero_of)
	_expect_equal("a peer with no hero gets the match and no hero count", deltas.get(99),
		{"matches": 1, "wins": 1, "eliminations": 0, "damage": 0, "heroes": {}})
	stats.match_started()
	deltas = stats.match_ended(BLUE, func(_peer_id: int) -> int: return 7)
	_expect_equal("a hero that isn't text is no hero", deltas.get(99),
		{"matches": 1, "wins": 1, "eliminations": 0, "damage": 0, "heroes": {}})


## match_ended with no match being played, or a second time, answers nothing.
func _ended_twice() -> void:
	var stats: MatchStats = _three_players()
	_expect_true("match_ended with no match being played answers nothing", stats.match_ended(BLUE, _hero_of).is_empty())
	stats.match_started()
	stats.match_ended(BLUE, _hero_of)
	_expect_true("a second match_ended answers nothing", stats.match_ended(BLUE, _hero_of).is_empty())


## A MatchStats with A and B on Blue and C on Orange, no match started.
func _three_players() -> MatchStats:
	var stats := MatchStats.new()
	stats.team_assigned(A, BLUE)
	stats.team_assigned(B, BLUE)
	stats.team_assigned(C, ORANGE)
	return stats


## Stands in for Net's _hero_file(): each test peer's hero file name, or "".
func _hero_of(peer_id: int) -> String:
	return HEROES.get(peer_id, "")


## One check: `got` has the same type and value as `wanted`.
func _expect_equal(case_name: String, got: Variant, wanted: Variant) -> void:
	_expect_true("%s (got %s)" % [case_name, got], typeof(got) == typeof(wanted) and got == wanted)


## One check: prints ok or FAIL with its name and counts it.
func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)

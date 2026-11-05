extends SceneTree
## Tests for card T15: TeamBook (teams, balance, peers that left), ArenaTeamRules
## (who is an enemy, which side spawns where), ArenaMatch (score limit, clock, draw,
## next match) and the new numbers in data/arena_rules.tres. Owner: Adam (game/modes).
## No network: ArenaMode only passes these along. Run from the repo folder:
##   godot --headless --path . --script res://game/modes/tools/test_arena_teams.gd
## Exits with code 1 when any case is wrong. tools/smoke.ps1 runs it.

const DATA_PATH: String = "res://game/modes/data/arena_rules.tres"

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_joiners_alternate()
	_join_tie_goes_to_the_team_behind()
	_server_and_no_peer_get_no_team()
	_leave_evens_the_teams()
	_leave_within_one_moves_nobody()
	_peer_that_left_keeps_its_team()
	_next_match_forgets_peers_that_left()
	_rules_enemies_and_spawn_sides()
	_rules_shooter_that_left()
	_match_score_limit()
	_match_clock_and_winner()
	_match_draw()
	_match_next_starts_after_the_pause()
	_match_ignores_points_after_the_end()
	_data_file()
	print("ARENA TEAMS TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


## Records every team_changed, as ArenaMode would send them.
class Heard:
	var lines: Array[Array] = []

	func on_changed(peer_id: int, team: int) -> void:
		lines.append([peer_id, team])


func _book_with(peers: Array[int]) -> TeamBook:
	var book := TeamBook.new()
	for peer: int in peers:
		book.team_of(peer)
	return book


func _joiners_alternate() -> void:
	var book := TeamBook.new()
	var heard := Heard.new()
	book.team_changed.connect(heard.on_changed)
	var teams: Array[int] = []
	for peer: int in [11, 12, 13, 14, 15]:
		teams.append(book.team_of(peer))
	_expect(teams == [0, 1, 0, 1, 0], "joiners fill the smaller team, Blue first", str(teams))
	_expect(book.sizes() == PackedInt32Array([3, 2]), "sizes count every playing peer", str(book.sizes()))
	book.team_of(11)
	_expect(heard.lines.size() == 5, "asking again gives no new team", str(heard.lines))


func _join_tie_goes_to_the_team_behind() -> void:
	var book := _book_with([11, 12])
	book.score_of = func(team: int) -> int: return [5, 2][team]
	_expect(book.team_of(13) == 1, "equal sizes: the joiner helps the team behind on score", str(book.playing()))


func _server_and_no_peer_get_no_team() -> void:
	var book := TeamBook.new()
	_expect(book.team_of(1) == -1 and book.team_of(0) == -1 and book.player_count() == 0,
		"the server (1) and no peer (0) never get a team", str(book.playing()))


func _leave_evens_the_teams() -> void:
	# Blue 11, 13, 15; Orange 12, 14. Orange 12 leaves: 3 against 1, so Blue's newest (15) moves.
	var book := _book_with([11, 12, 13, 14, 15])
	var heard := Heard.new()
	book.team_changed.connect(heard.on_changed)
	var moved := book.peer_left(12)
	_expect(moved == [15], "when a team is 2 bigger, its newest player moves", str(moved))
	_expect(book.peek(15) == 1 and heard.lines == [[15, 1]], "the move is told once, as Orange", str(heard.lines))
	_expect(book.sizes() == PackedInt32Array([2, 2]), "the teams are even again", str(book.sizes()))


func _leave_within_one_moves_nobody() -> void:
	var book := _book_with([11, 12, 13, 14])
	var moved := book.peer_left(11)
	_expect(moved.is_empty() and book.sizes() == PackedInt32Array([1, 2]), "within 1 after a leave: nobody moves", str(book.playing()))


## Adam's A4: a peer that left keeps its last team for its shots in flight, is
## never counted in team sizes and is never given a team again.
func _peer_that_left_keeps_its_team() -> void:
	# Blue 11, 13; Orange 12, 14. Orange 12 leaves: 2 against 1, so nobody moves.
	var book := _book_with([11, 12, 13, 14])
	var heard := Heard.new()
	book.team_changed.connect(heard.on_changed)
	book.peer_left(12)
	_expect(book.team_of(12) == 1, "after peer_left, team_of() gives its last team (Orange)", str(book.team_of(12)))
	_expect(heard.lines.is_empty(), "after peer_left, team_of() gives no one a team", str(heard.lines))
	_expect(book.sizes() == PackedInt32Array([2, 1]) and book.player_count() == 3,
		"team sizes don't count it", str(book.sizes()))
	_expect(not book.playing().has(12), "it is not among the playing peers", str(book.playing()))
	book.peer_left(77)
	_expect(book.team_of(77) == -1 and heard.lines.is_empty(), "a peer that left before getting a team never gets one", str(heard.lines))


func _next_match_forgets_peers_that_left() -> void:
	var book := _book_with([11, 12])
	var heard := Heard.new()
	book.team_changed.connect(heard.on_changed)
	book.peer_left(12)
	book.new_match()
	_expect(book.peek(12) == -1 and book.team_of(12) == -1, "the next match forgets its team", str(book.peek(12)))
	_expect(heard.lines.is_empty() and book.sizes() == PackedInt32Array([1, 0]), "and still never gives it one", str(heard.lines))
	_expect(book.team_of(11) == 0, "players who stayed keep their team", str(book.playing()))


func _points() -> Dictionary[String, Vector2]:
	var points: Dictionary[String, Vector2] = {}
	for i: int in 4:
		points["SpawnA%d" % (i + 1)] = Vector2(100.0, 100.0 + 200.0 * i)
		points["SpawnB%d" % (i + 1)] = Vector2(1800.0, 100.0 + 200.0 * i)
	return points


func _rules(book: TeamBook) -> ArenaTeamRules:
	var none := func() -> Dictionary[int, Vector2]: return {}
	return ArenaTeamRules.new(_points(), none, book)


func _rules_enemies_and_spawn_sides() -> void:
	var book := TeamBook.new()
	var rules := _rules(book)
	var blue_spot := rules.point_name(11)
	var orange_spot := rules.point_name(12)
	_expect(blue_spot.begins_with("SpawnA") and orange_spot.begins_with("SpawnB"),
		"the first spawn gives the team and its side (Blue A, Orange B)", "%s, %s" % [blue_spot, orange_spot])
	book.team_of(13)
	_expect(not rules.is_enemy(11, 13) and rules.is_enemy(11, 12) and not rules.is_enemy(11, 11),
		"teammates are not enemies, the other team is, nobody is their own", str(book.playing()))
	var allies := rules.allies_among(11, [11, 12, 13])
	_expect(allies == [13], "shots pass through teammates only", str(allies))
	_expect(rules.can_heal(11, 13) and not rules.can_heal(11, 12), "the Heal Drone heals teammates only", "")
	_expect(rules.is_enemy(11, 99) and book.peek(99) == -1, "is_enemy() gives no one a team; no team is an enemy", str(book.playing()))


func _rules_shooter_that_left() -> void:
	var book := _book_with([11, 12, 13])
	var rules := _rules(book)
	book.peer_left(13)
	_expect(rules.allies_among(13, [11, 12]) == [11], "a shooter that left: its shots still pass through its old team",
		str(rules.allies_among(13, [11, 12])))
	_expect(book.sizes() == PackedInt32Array([1, 1]), "and asking about it counts no ghost", str(book.sizes()))


func _match(length: float = 1200.0) -> ArenaMatch:
	var game := ArenaMatch.new(length, 8, 10.0)
	game.start()
	return game


func _match_score_limit() -> void:
	var game := _match()
	_expect(game.score_limit(2) == 16 and game.score_limit(0) == 1, "the limit is 8 per player, at least 1", str(game.score_limit(2)))
	for i: int in 15:
		game.add_point(1)
	_expect(not game.check_limit(2), "15 of 16 does not end it", str(game.scores))
	game.add_point(1)
	_expect(game.check_limit(2) and game.winner == 1, "16 of 16 ends it: Orange wins", str(game.winner))
	var shrink := _match()
	for i: int in 9:
		shrink.add_point(0)
	_expect(shrink.check_limit(1) and shrink.winner == 0, "a lower limit after a leave can end it at once", str(shrink.scores))


func _match_clock_and_winner() -> void:
	var game := _match(60.0)
	game.add_point(0)
	_expect(game.clock() == 60, "the clock starts full", str(game.clock()))
	_expect(game.tick(30.5) == ArenaMatch.Tick.NOTHING and game.clock() == 30, "it counts down in whole seconds, rounded up", str(game.clock()))
	_expect(game.tick(30.0) == ArenaMatch.Tick.ENDED and game.winner == 0 and game.clock() == 0,
		"at 0 the higher score wins", str(game.winner))


func _match_draw() -> void:
	var game := _match(60.0)
	game.add_point(0)
	game.add_point(1)
	game.tick(61.0)
	_expect(game.phase == ArenaMatch.Phase.OVER and game.winner == ArenaMatch.DRAW, "equal scores at 0 are a draw", str(game.winner))


func _match_next_starts_after_the_pause() -> void:
	var game := _match(60.0)
	game.add_point(1)
	game.tick(60.0)
	_expect(game.tick(9.0) == ArenaMatch.Tick.NOTHING, "the pause lasts next_match_delay_sec", "")
	_expect(game.tick(1.0) == ArenaMatch.Tick.RESTART and game.phase == ArenaMatch.Phase.PLAYING,
		"then the next match starts", str(game.phase))
	_expect(game.scores == PackedInt32Array([0, 0]) and game.clock() == 60, "with scores 0 and a full clock", str(game.scores))


func _match_ignores_points_after_the_end() -> void:
	var game := _match(60.0)
	game.tick(60.0)
	_expect(not game.add_point(0) and game.scores == PackedInt32Array([0, 0]), "eliminations in the pause don't score", str(game.scores))
	var waiting := ArenaMatch.new(60.0, 8, 10.0)
	_expect(not waiting.add_point(0) and waiting.tick(100.0) == ArenaMatch.Tick.NOTHING,
		"before the first player, nothing runs", str(waiting.phase))


func _data_file() -> void:
	var data := load(DATA_PATH) as ArenaRulesData
	_expect(data != null, "data/arena_rules.tres loads", DATA_PATH)
	if data == null:
		return
	_expect(data.score_per_player == 8 and is_equal_approx(data.match_length_sec, 1200.0)
		and is_equal_approx(data.next_match_delay_sec, 10.0), "8 per player, 20 minutes, 10 s pause",
		"%d, %s, %s" % [data.score_per_player, data.match_length_sec, data.next_match_delay_sec])
	_expect(data.validate().is_empty(), "the file is in range", ", ".join(data.validate()))


func _expect(ok: bool, what: String, problem: String) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s: %s" % [what, problem])

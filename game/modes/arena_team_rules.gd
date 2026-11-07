class_name ArenaTeamRules
extends ArenaRules
## The arena's rules with two teams (card T15). Server only. Owner: Adam (game/modes).
## ArenaRules' spawn pick and protection, plus teams from a TeamBook: shots pass
## through teammates, Shield Charge knocks back enemies only, the Heal Drone heals
## teammates only, and each team spawns on its own side.

var _book: TeamBook


func _init(points: Dictionary[String, Vector2], living_heroes: Callable, book: TeamBook) -> void:
	super(points, living_heroes)
	_book = book if book != null else TeamBook.new()


## Gives a new peer its team (TeamBook.team_of()).
func team_of(peer_id: int) -> int:
	return _book.team_of(peer_id)


## Enemies are on different teams; a peer with no team is everyone's enemy.
## Never gives anyone a team.
func is_enemy(a: int, b: int) -> bool:
	if a == b:
		return false
	var team_a := _book.peek(a)
	var team_b := _book.peek(b)
	return team_a < 0 or team_b < 0 or team_a != team_b

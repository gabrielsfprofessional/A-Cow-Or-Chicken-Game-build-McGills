extends Control
## Press F6 on hit_feedback_preview.tscn to see and hear hit feedback without a server (card T25).
## Owner: John (game/ui). Fake hits only; the keys are listed on screen.

const ME: int = 2
const OTHER: int = 3

var _feedback: HitFeedback = HitFeedback.new()
var _other_hero: Node2D = Node2D.new()

@onready var _help: Label = $Help


func _ready() -> void:
	_help.add_theme_font_size_override(&"font_size", 24)
	_help.text = "Hit feedback preview (fake hits)\n1: someone else is hit   2: you are hit   3: hit absorbed by spawn protection (nothing)\n4: someone else is eliminated   5: you are eliminated   6: 30 hits at once"
	var heroes := Node.new()
	heroes.name = &"Heroes"
	add_child(heroes)
	_other_hero.name = StringName(str(OTHER))
	heroes.add_child(_other_hero)
	_feedback.own_peer_id = ME
	_feedback.active = true
	add_child(_feedback)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			Events.hero_damaged.emit(OTHER, ME, 20, _random_spot())
		KEY_2:
			Events.hero_damaged.emit(ME, OTHER, 15, size * 0.5)
		KEY_3:
			Events.hero_damaged.emit(OTHER, ME, 0, _random_spot())
		KEY_4:
			_other_hero.position = _random_spot()
			Events.hero_eliminated.emit(OTHER, ME)
		KEY_5:
			Events.hero_eliminated.emit(ME, OTHER)
		KEY_6:
			for i: int in 30:
				Events.hero_damaged.emit(OTHER, ME, 5 + i, _random_spot())


func _random_spot() -> Vector2:
	return Vector2(randf_range(0.2, 0.8) * size.x, randf_range(0.3, 0.8) * size.y)

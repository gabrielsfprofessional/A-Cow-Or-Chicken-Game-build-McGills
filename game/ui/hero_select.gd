extends Control
## Hero select (card T16): one card per hero in the roster, in roster order, so the card's
## position is the roster slot the world spawns. Owner: John (game/ui).
## A pick sets Net.chosen_hero_index, remembers the hero in Settings.last_hero and opens the
## Join screen, which calls Net.play(). Back or Esc returns to the main menu.
## It decides nothing for the match: the server still spawns the hero it is told.

const MENU_SCENE: String = "res://game/ui/main_menu.tscn"
const JOIN_SCENE: String = "res://game/ui/join_screen.tscn"
const ROSTER: HeroRoster = preload("res://game/heroes/data/roster.tres")

## Size of one hero card, in pixels at UI scale 100.
@export var card_size: Vector2 = Vector2(190, 210)
## Tests turn this off so a pick does not leave the scene.
@export var open_join_on_pick: bool = true

var _cards: Array[Button] = []

@onready var _cards_box: HFlowContainer = $Margin/Rows/Cards
@onready var _hint: Label = $Margin/Rows/Hint
@onready var _back: Button = $Margin/Rows/BackButton


func _ready() -> void:
	_back.pressed.connect(_on_back_pressed)
	if ROSTER.heroes.is_empty():
		_hint.text = "No heroes were found. Ask Gabe."
		_back.grab_focus()
		return
	for slot: int in ROSTER.heroes.size():
		var card: Button = _make_card(slot)
		_cards_box.add_child(card)
		_cards.append(card)
	var start: int = start_slot()
	_mark(start)
	_cards[start].grab_focus()


## The slot the screen starts on: the last pick, else the first hero.
func start_slot() -> int:
	return maxi(0, ROSTER.index_of(Settings.last_hero))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _make_card(slot: int) -> Button:
	var hero: HeroData = ROSTER.at(slot)
	var card: Button = Button.new()
	card.name = "Card%d" % slot
	card.theme_type_variation = &"HeroCard"
	card.toggle_mode = true
	card.custom_minimum_size = card_size
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.text = card_text(hero)
	card.pressed.connect(_on_card_pressed.bind(slot))
	return card


## What a card says, from the hero's data: name, role, Q ability and default weapon.
static func card_text(hero: HeroData) -> String:
	var ability_name: String = hero.ability.display_name if hero.ability != null else "none"
	var weapon_name: String = hero.default_weapon.display_name if hero.default_weapon != null else "none"
	return "%s\n%s\nQ: %s\nWeapon: %s" % [hero.display_name, hero.role, ability_name, weapon_name]


## Shows slot as the picked card (the others off).
func _mark(slot: int) -> void:
	for i: int in _cards.size():
		_cards[i].set_pressed_no_signal(i == slot)


func _on_card_pressed(slot: int) -> void:
	_mark(slot)
	var file_name: String = ROSTER.at(slot).resource_path.get_file().get_basename()
	Net.chosen_hero_index = slot
	Settings.last_hero = file_name
	Settings.save_settings()
	print("[UI] hero picked: %s (slot %d)" % [file_name, slot])
	if open_join_on_pick:
		get_tree().change_scene_to_file(JOIN_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)

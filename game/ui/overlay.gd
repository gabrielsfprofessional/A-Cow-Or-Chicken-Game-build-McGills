extends CanvasLayer
## Shows the HUD over the game while you are in a match as a client (card T17).
## Autoload "Overlay". Owner: John (game/ui).
##
## It finds your hero in the world's Heroes node and copies its numbers into the
## Hud every frame. It decides nothing. Hidden in menus and on the server.

const HUD_SCENE: PackedScene = preload("res://game/ui/hud.tscn")

var _hud: Hud = null


func _ready() -> void:
	layer = 10
	_hud = HUD_SCENE.instantiate() as Hud
	add_child(_hud)
	_hud.visible = false


func _process(_delta: float) -> void:
	var hero := _own_hero()
	_hud.visible = hero != null
	if hero == null:
		return
	var health := hero.get_node_or_null(^"Health") as Health
	if health != null:
		_hud.set_health(health.health(), health.max_health)
	if hero.has_ability():
		var ability := hero.hero_data.ability
		_hud.set_ability(ability.display_name, hero.ability_ready_in_sec(),
			hero.ability_charges_left(), ability.charges)
	else:
		_hud.set_ability("", 0.0, 0, 0)
	_hud.set_respawn(hero.respawn_in_sec())


## Your hero in the current world, or null (menus, the server, before it spawns).
func _own_hero() -> NetHero:
	if Net.state != Net.State.CLIENT:
		return null
	var world := get_tree().current_scene
	if world == null:
		return null
	return world.get_node_or_null("Heroes/%d" % multiplayer.get_unique_id()) as NetHero

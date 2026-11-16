extends CanvasLayer
## Shows the HUD over the game while you are in a match as a client (card T17).
## Autoload "Overlay". Owner: John (game/ui).
##
## It finds your hero in the world's Heroes node and copies its numbers into the
## Hud every frame. It decides nothing. Hidden in menus and on the server. A headless
## run (the server, test bots) has nobody to show it to, so it builds nothing and does
## no work each frame.

const HUD_SCENE: PackedScene = preload("res://game/ui/hud.tscn")
## The canvas layer the HUD and the hit feedback draw on. Above it: nothing yet (a
## pause or results screen would go higher). Below it: the game world and the heroes'
## own labels (layer 0), and menus, which are never open during a match.
const HUD_LAYER: int = 10

var _hud: Hud = null
var _hit_feedback: HitFeedback = null


func _ready() -> void:
	layer = HUD_LAYER
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_hud = HUD_SCENE.instantiate() as Hud
	add_child(_hud)
	_hud.visible = false
	# Listen now, before this client is ready, so the late-join replay is not missed.
	_hud.listen()
	_hit_feedback = HitFeedback.new()
	add_child(_hit_feedback)


func _process(_delta: float) -> void:
	# The match values belong to one session: forget them when we are not a client
	# (left the match, back in the menu). Your peer id lets the HUD pick your team.
	if Net.state == Net.State.CLIENT:
		_hud.set_own_peer(multiplayer.get_unique_id())
	else:
		_hud.clear_match()
	var hero: NetHero = _own_hero()
	_hud.visible = hero != null
	_hit_feedback.active = hero != null
	if hero == null:
		return
	var health := hero.get_node_or_null(^"Health") as Health
	if health != null:
		_hud.set_health(health.health(), health.max_health)
	if hero.has_ability():
		var ability: AbilityData = hero.hero_data.ability
		_hud.set_ability(ability.display_name, hero.ability_ready_in_sec(),
			hero.ability_charges_left(), ability.charges)
	else:
		_hud.set_ability("", 0.0, 0, 0)
	_hud.set_respawn(hero.respawn_in_sec())


## Your hero in the current world, or null (menus, the server, before it spawns).
func _own_hero() -> NetHero:
	if Net.state != Net.State.CLIENT:
		return null
	var world: Node = get_tree().current_scene
	if world == null:
		return null
	return world.get_node_or_null("Heroes/%d" % multiplayer.get_unique_id()) as NetHero

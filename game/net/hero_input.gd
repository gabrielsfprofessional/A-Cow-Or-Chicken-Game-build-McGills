class_name HeroInput
extends Node
## What the owner's hero wants this physics tick: move, aim, fire and Q. Owner: Gabe
## (game/net). Cards T09, T14.
##
## The owner's NetHero makes one in _ready, as its child "Input", and sets `hero`
## first. NetHero and Weapon read it instead of Input and the mouse. This base
## reads the keyboard and mouse; BotBrain overrides it for test bots. T14 adds
## the Q ability.

## The hero this input drives. Set before the node enters the tree.
var hero: NetHero = null


## Which way to walk, length 0 to 1.
func move() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


## Where to aim, as an offset from the hero's center. Zero keeps the last aim.
func aim() -> Vector2:
	return hero.get_global_mouse_position() - hero.global_position


## True while fire is held (automatic weapons).
func fire_held() -> bool:
	return Input.is_action_pressed(&"fire")


## True on the tick fire goes down (one shot per click).
func fire_pressed() -> bool:
	return Input.is_action_just_pressed(&"fire")


## True on the tick Q (the "ability" action) goes down. The hero's Ability reads it (T14).
func ability_pressed() -> bool:
	return Input.is_action_just_pressed(&"ability")

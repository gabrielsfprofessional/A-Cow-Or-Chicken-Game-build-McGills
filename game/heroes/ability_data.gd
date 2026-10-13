class_name AbilityData
extends Resource
## What every hero ability has, tuned in the Inspector. Owner: Gabe (game/heroes).
## Cards T14, T18. Each ability's own data extends it (DashData so far) and builds
## its node with make(), and HeroData.ability points at one file in data/.

## The script every ability node extends; make() refuses any other.
const ABILITY_SCRIPT_PATH: String = "res://game/heroes/ability.gd"

## Name shown in the HUD, for example "Shield Charge".
@export var display_name: String = ""
## Seconds before a used charge is back, counted from its own use. Kept through death.
@export_range(1.0, 60.0, 0.1, "suffix:s") var cooldown_sec: float = 10.0
## Uses the hero can bank (T18). Each comes back cooldown_sec after its own use.
@export_range(1, 5, 1) var charges: int = 1


## A new node for this ability (an Ability), with `data` set to this file.
## NetHero.setup() adds it as the hero's "Ability" child. Null, with an error,
## when this data names no node script, or one that is missing or doesn't extend
## Ability (checked before it is built).
func make() -> Node:
	var path := node_script_path()
	var source := resource_path if resource_path != "" else "an unsaved ability data"
	if path == "":
		push_error("%s names no node script; override node_script_path()" % source)
		return null
	var script := load(path) as GDScript if ResourceLoader.exists(path) else null
	if script == null:
		push_error("%s names node script %s, which does not load" % [source, path])
		return null
	if not extends_ability(script):
		push_error("%s names node script %s, which does not extend %s" % [source, path, ABILITY_SCRIPT_PATH])
		return null
	var node := script.new() as Node
	node.set(&"data", self)
	return node


## The node script's path, loaded only by make(). A path, not a preload or a
## class name: the node uses the Net autoload, and data files must also load
## where there is none (tests/data_test.gd). Each ability's own data overrides it.
func node_script_path() -> String:
	return ""


## True when `script` is ability.gd or extends it (T18), compared by path so this
## file never loads the Ability class itself.
static func extends_ability(script: Script) -> bool:
	while script != null:
		if script.resource_path == ABILITY_SCRIPT_PATH:
			return true
		script = script.get_base_script()
	return false


## This ability's problems in plain words. Empty when the file is fine.
## An ability's own data adds its checks after these.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	DataCheck.require_text(problems, "display_name", display_name)
	problems.append_array(DataCheck.ranges(self))
	return problems

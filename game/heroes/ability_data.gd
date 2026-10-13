class_name AbilityData
extends Resource
## What every hero ability has, tuned in the Inspector. Owner: Gabe (game/heroes).
## Cards T14, T18. Each ability's own data extends it (DashData so far) and builds
## its node with make(), and HeroData.ability points at one file in data/.

## Name shown in the HUD, for example "Shield Charge".
@export var display_name: String = ""
## Seconds before a used charge is back, counted from its own use. Kept through death.
@export_range(1.0, 60.0, 0.1, "suffix:s") var cooldown_sec: float = 10.0
## Uses the hero can bank (T18). Each comes back cooldown_sec after its own use.
@export_range(1, 5, 1) var charges: int = 1


## A new node for this ability (an Ability), with `data` set to this file.
## NetHero.setup() adds it as the hero's "Ability" child. Null, with an error,
## when this data names no node script.
func make() -> Node:
	var path := _node_script_path()
	if path == "":
		push_error("%s names no node script; override _node_script_path()" % get_script().resource_path)
		return null
	var node := (load(path) as GDScript).new() as Node
	node.set(&"data", self)
	return node


## The node script's path, loaded only by make(). A path, not a preload or a
## class name: the node uses the Net autoload, and data files must also load
## where there is none (tests/data_test.gd). Each ability's own data overrides it.
func _node_script_path() -> String:
	return ""


## This ability's problems in plain words. Empty when the file is fine.
## An ability's own data adds its checks after these.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	DataCheck.require_text(problems, "display_name", display_name)
	problems.append_array(DataCheck.ranges(self))
	return problems

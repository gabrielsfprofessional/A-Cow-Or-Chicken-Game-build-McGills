class_name HeroData
extends Resource
## One hero's numbers, tuned in the Inspector. Owner: Gabe (game/heroes). Cards T13, T14.
## The four heroes live in data/ (bruiser, mage, scout, medic.tres) and data/roster.tres
## lists them. NetHero.setup() hands one to each hero; tests/data_test.gd checks them all.

## Name shown in hero select and the HUD, for example "Fantasy Bruiser".
@export var display_name: String = ""
## One line for hero select that says what this hero is for, for example "Front line, soaks damage".
@export var role: String = ""
## How fast this hero walks, in pixels per second. The server checks every move against it.
@export_range(50.0, 1000.0, 10.0, "suffix:px/s") var move_speed: float = 300.0
## Health this hero starts and respawns with.
@export_range(1, 1000, 1, "suffix:HP") var max_health: int = 100
## The gun this hero spawns with: a WeaponData file from game/weapons/data.
@export var default_weapon: WeaponData
## The Q ability: an AbilityData file such as shield_charge.tres. Empty means no
## ability (Mage, Scout and Medic until T18).
@export var ability: AbilityData


## This hero's problems in plain words, its weapon's and ability's included. Empty when the file is fine.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	DataCheck.require_text(problems, "display_name", display_name)
	DataCheck.require_text(problems, "role", role)
	problems.append_array(DataCheck.ranges(self))
	if default_weapon == null:
		problems.append("default_weapon is empty; pick a WeaponData file such as sidearm.tres")
	else:
		var label := "default_weapon (%s)" % DataCheck.file_name(default_weapon)
		for problem: String in default_weapon.validate():
			problems.append("%s: %s" % [label, problem])
	if ability != null:
		var ability_label := "ability (%s)" % DataCheck.file_name(ability)
		for problem: String in ability.validate():
			problems.append("%s: %s" % [ability_label, problem])
	return problems

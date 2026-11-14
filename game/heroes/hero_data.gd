class_name HeroData
extends Resource
## One hero's numbers, tuned in the Inspector. Owner: Gabe (game/heroes). Cards T13, T14, T18.
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
## The Q ability: an AbilityData file such as shield_charge.tres. Required (T18).
@export var ability: AbilityData
## Optional art for the hero's body (T31): a transparent top-down PNG from assets/heroes.
## Empty keeps the plain square tinted by player. The collider never changes with it.
@export var body_texture: Texture2D
## How big the body art is drawn: its longer side, in pixels. Its shape is kept.
@export_range(16.0, 128.0, 1.0, "suffix:px") var body_size_px: float = 48.0


## The scale that draws a texture of `size` with its longer side at `longest_px`.
## 1.0 for an empty size, so a broken texture never scales to infinity.
static func body_scale(size: Vector2, longest_px: float) -> float:
	var longest: float = maxf(size.x, size.y)
	if longest <= 0.0:
		return 1.0
	return longest_px / longest


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
	if ability == null:
		problems.append("ability is empty; pick an AbilityData file such as shield_charge.tres")
	else:
		var ability_label := "ability (%s)" % DataCheck.file_name(ability)
		for problem: String in ability.validate():
			problems.append("%s: %s" % [ability_label, problem])
	if body_texture != null and (body_texture.get_width() <= 0 or body_texture.get_height() <= 0):
		problems.append("body_texture (%s) has no pixels; pick a PNG from assets/heroes, or leave it empty"
			% DataCheck.file_name(body_texture))
	return problems

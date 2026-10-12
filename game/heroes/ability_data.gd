class_name AbilityData
extends Resource
## What every hero ability has, tuned in the Inspector. Owner: Gabe (game/heroes).
## Card T14. Each ability's own data extends it (T14: ShieldChargeData; T18 the
## rest), and HeroData.ability points at one file in data/.

## Name shown in the HUD, for example "Shield Charge".
@export var display_name: String = ""
## Seconds before the ability can be used again. Kept through death.
@export_range(1.0, 60.0, 0.1, "suffix:s") var cooldown_sec: float = 10.0


## This ability's problems in plain words. Empty when the file is fine.
## An ability's own data adds its checks after these.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	DataCheck.require_text(problems, "display_name", display_name)
	problems.append_array(DataCheck.ranges(self))
	return problems

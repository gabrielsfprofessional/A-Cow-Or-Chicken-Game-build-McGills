class_name AbilitySoundSet
extends Resource
## Which sound each hero ability plays, and how loud (card T32). Owner: John (game/ui).
## The one file of this kind is game/ui/data/ability_sounds.tres; change it in the Inspector.

## One sound per ability. The key is the ability's file name in game/heroes/data
## without ".tres", for example "blink" for blink.tres.
@export var sounds: Dictionary[String, AudioStream] = {}
@export_range(-24.0, 6.0, 0.5, "suffix:dB") var volume_db: float = -6.0
## +/- share of pitch change on every sound, so two uses never sound identical.
@export_range(0.0, 0.2, 0.01) var pitch_spread: float = 0.05
## Most ability sounds at once; one more is dropped.
@export_range(1, 16, 1) var max_voices: int = 6
## Silent when the hero is this many screen widths away from the middle of your screen.
@export_range(0.5, 4.0, 0.1, "suffix:screens") var silent_beyond_screens: float = 1.5


## The sound for an ability's data file, or null when it has none.
func sound_for(ability: Resource) -> AudioStream:
	if ability == null:
		return null
	var key: String = ability.resource_path.get_file().get_basename()
	var stream: AudioStream = sounds.get(key)
	return stream

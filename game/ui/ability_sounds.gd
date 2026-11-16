class_name AbilitySounds
extends Node
## Plays a sound when any hero uses its Q ability (card T32). Owner: John (game/ui).
##
## Overlay creates this. It listens to Events.ability_used, which fires on every peer,
## finds the hero at Heroes/<peer id> in the current world and plays the sound its
## ability has in game/ui/data/ability_sounds.tres. It decides nothing. The voice rules
## are HitFeedback's: a fixed pool, quieter with distance, and a headless run picks a
## voice the same way but never starts a sound.

const SOUND_SET_PATH: String = "res://game/ui/data/ability_sounds.tres"
const SFX_BUS: StringName = &"SFX"

## The sounds and volumes. A test may swap it before the node enters the tree.
var sound_set: AbilitySoundSet = load(SOUND_SET_PATH) as AbilitySoundSet

var _voices: Array[AudioStreamPlayer] = []
## Per voice: when its sound ends (Time.get_ticks_msec()). Kept here, not read from the
## player, so the choice of voice is the same on a headless run.
var _voice_ends_msec: Array[int] = []


func _ready() -> void:
	for i: int in sound_set.max_voices:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		add_child(voice)
		_voices.append(voice)
		_voice_ends_msec.append(0)
	Events.ability_used.connect(_on_ability_used)


func _on_ability_used(peer_id: int, _ready_in_sec: float) -> void:
	var hero: Node2D = _hero(peer_id)
	if hero == null:
		return
	var hero_data: HeroData = hero.get(&"hero_data") as HeroData
	if hero_data == null:
		return
	var stream: AudioStream = sound_set.sound_for(hero_data.ability)
	if stream == null:
		return
	_play(stream, hero.global_position)


## Plays stream at a world point, quieter the further it is from the middle of the
## screen. Dropped when it is too far to hear or every voice is busy.
func _play(stream: AudioStream, world_position: Vector2) -> void:
	var view: Viewport = get_viewport()
	var screen: Vector2 = view.get_visible_rect().size
	var middle: Vector2 = view.get_canvas_transform().affine_inverse() * (screen * 0.5)
	var reach: float = screen.x * sound_set.silent_beyond_screens
	var distance: float = world_position.distance_to(middle)
	if distance >= reach:
		return
	var now: int = Time.get_ticks_msec()
	var i: int = _free_voice(now)
	if i < 0:
		return
	var voice: AudioStreamPlayer = _voices[i]
	voice.stream = stream
	voice.pitch_scale = 1.0 + randf_range(-sound_set.pitch_spread, sound_set.pitch_spread)
	voice.volume_db = sound_set.volume_db + linear_to_db(1.0 - distance / reach)
	_voice_ends_msec[i] = now + roundi(stream.get_length() / voice.pitch_scale * 1000.0)
	# Headless runs (the server, test bots) have no listener, and a sound still playing
	# when one quits leaks its playback at exit, which fails the smoke test.
	if DisplayServer.get_name() != "headless":
		voice.play()


## The first voice that is not busy, or -1.
func _free_voice(now: int) -> int:
	for i: int in _voices.size():
		if _voice_ends_msec[i] <= now:
			return i
	return -1


func _hero(peer_id: int) -> Node2D:
	var world: Node = get_tree().current_scene
	if world == null:
		return null
	return world.get_node_or_null("Heroes/%d" % peer_id) as Node2D

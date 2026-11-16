extends SceneTree
## Tests for card T32 (ability sounds): every hero on the roster has a sound for its
## ability, a use asks for that hero's sound, a headless run starts no sound, and the
## distance and voice limits hold.
## Owner: John (game/ui). Run from the repo folder with APPDATA pointed at a temp folder:
##   godot --headless --path . --script res://game/ui/tools/test_ability_sounds.gd
## Exits with code 1 when any case is wrong. Autoloads exist only at run time, so the
## script reaches them by path and loads AbilitySounds with load().

const ROSTER_PATH: String = "res://game/heroes/data/roster.tres"
const SOUND_FOLDER: String = "res://audio/ability/"
const FIRST_PEER: int = 2
## A stand-in hero: a point in the world that carries the hero's data, as NetHero does.
const HERO_STUB_SOURCE: String = "extends Node2D\nvar hero_data: Resource = null\n"

var _failures: int = 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		print("FAIL ", what)
		_failures += 1


func _initialize() -> void:
	await process_frame
	var events: Node = root.get_node(^"/root/Events")
	var sounds_script: GDScript = load("res://game/ui/ability_sounds.gd")
	var roster: Resource = load(ROSTER_PATH)
	var hero_list: Array = roster.heroes
	var stub: GDScript = GDScript.new()
	stub.source_code = HERO_STUB_SOURCE
	stub.reload()
	# A stand-in world: the current scene with Heroes/<peer id>, one per roster hero.
	var world: Node2D = Node2D.new()
	var heroes: Node = Node.new()
	heroes.name = &"Heroes"
	world.add_child(heroes)
	root.add_child(world)
	current_scene = world
	var sounds: Node = sounds_script.new()
	root.add_child(sounds)
	await process_frame
	var sound_set: Resource = sounds.sound_set
	var screen: Vector2 = root.get_visible_rect().size
	var middle: Vector2 = screen * 0.5
	var hero_nodes: Array[Node2D] = []
	for i: int in hero_list.size():
		var hero: Node2D = stub.new()
		hero.name = StringName(str(FIRST_PEER + i))
		hero.hero_data = hero_list[i]
		heroes.add_child(hero)
		hero.global_position = middle + Vector2(60.0 * i, 20.0)
		hero_nodes.append(hero)

	_check(hero_list.size() >= 4, "the roster has at least 4 heroes (got %d)" % hero_list.size())
	_check(sounds._voices.size() == sound_set.max_voices and sound_set.max_voices >= hero_list.size(),
		"there is a fixed pool of voices, at least one per hero (got %d)" % sounds._voices.size())
	var all_on_sfx: bool = true
	for voice: AudioStreamPlayer in sounds._voices:
		all_on_sfx = all_on_sfx and voice.bus == &"SFX"
	_check(all_on_sfx, "every voice plays on the SFX bus")

	# The rule: every hero on the roster has a sound for its ability, from audio/ability.
	var seen: Array[AudioStream] = []
	for i: int in hero_list.size():
		var ability: Resource = hero_list[i].ability
		var ability_name: String = ability.display_name if ability != null else "none"
		var stream: AudioStream = sound_set.sound_for(ability)
		_check(stream != null, "%s (%s) has an ability sound" % [ability_name, hero_list[i].display_name])
		if stream == null:
			continue
		_check(stream.resource_path.begins_with(SOUND_FOLDER),
			"%s's sound is a file in audio/ability (%s)" % [ability_name, stream.resource_path.get_file()])
		_check(stream.get_length() > 0.05 and stream.get_length() <= 1.5,
			"%s's sound is short (%.2f s)" % [ability_name, stream.get_length()])
		_check(not seen.has(stream), "%s's sound is not another ability's sound" % ability_name)
		seen.append(stream)

	# A use by each hero asks for that hero's sound, and a headless run starts none.
	for i: int in hero_list.size():
		_reset(sounds)
		events.ability_used.emit(FIRST_PEER + i, 8.0)
		var want: AudioStream = sound_set.sound_for(hero_list[i].ability)
		_check(want != null and _asked(sounds) == [want],
			"a use by %s asks for its own sound" % hero_list[i].display_name)
	_check(_playing(sounds) == 0, "headless run starts no sound")
	_reset(sounds)

	# Quieter with distance, silent beyond the limit.
	events.ability_used.emit(FIRST_PEER, 8.0)
	var near_db: float = _busy_voice(sounds).volume_db
	_reset(sounds)
	hero_nodes[0].global_position = middle + Vector2(screen.x, 0.0)
	events.ability_used.emit(FIRST_PEER, 8.0)
	var far_voice: AudioStreamPlayer = _busy_voice(sounds)
	_check(far_voice != null and far_voice.volume_db < near_db, "a use one screen away is quieter than one next to you")
	_reset(sounds)
	hero_nodes[0].global_position = middle + Vector2(screen.x * sound_set.silent_beyond_screens + 10.0, 0.0)
	events.ability_used.emit(FIRST_PEER, 8.0)
	_check(_asked(sounds).is_empty(), "a use beyond the silent distance asks for no sound")
	hero_nodes[0].global_position = middle

	# A hero that is not in the world: nothing to point at, so nothing.
	events.ability_used.emit(99, 8.0)
	_check(_asked(sounds).is_empty(), "a use by a hero that is not in the world asks for no sound")

	# Every voice busy: one more use is dropped, never stacked.
	for i: int in sound_set.max_voices + 1:
		events.ability_used.emit(FIRST_PEER, 8.0)
	_check(_asked(sounds).size() == sound_set.max_voices, "with every voice busy one more sound is dropped")
	_reset(sounds)

	current_scene = null
	sounds.queue_free()
	world.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


## How many voices are really playing (always 0 on a headless run).
func _playing(sounds: Node) -> int:
	var playing: int = 0
	for voice: AudioStreamPlayer in sounds._voices:
		if voice.playing:
			playing += 1
	return playing


## The sounds the busy voices were asked to play, in voice order.
func _asked(sounds: Node) -> Array[AudioStream]:
	var asked: Array[AudioStream] = []
	var now: int = Time.get_ticks_msec()
	for i: int in sounds._voices.size():
		if sounds._voice_ends_msec[i] > now:
			var voice: AudioStreamPlayer = sounds._voices[i]
			asked.append(voice.stream)
	return asked


## The first busy voice, or null.
func _busy_voice(sounds: Node) -> AudioStreamPlayer:
	var now: int = Time.get_ticks_msec()
	for i: int in sounds._voices.size():
		if sounds._voice_ends_msec[i] > now:
			return sounds._voices[i]
	return null


## Frees every voice, as if all sounds had ended.
func _reset(sounds: Node) -> void:
	for i: int in sounds._voice_ends_msec.size():
		sounds._voice_ends_msec[i] = 0

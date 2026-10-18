class_name HitFeedback
extends Control
## Shows and plays every hit: a damage number, a red edge flash when you are hit, a
## cartoon puff when someone else is, and hit / elimination sounds (card T25).
## Owner: John (game/ui).
##
## Overlay creates this and sets `active` while you are in a match as a client, so it
## stays silent in menus and on the server. It listens to the Events hits and decides
## nothing. An amount of 0 is a hit absorbed by spawn protection: nothing shows or plays.
## Sizes, colors, times and volumes are the @export values below.

const HIT_SOUND: AudioStream = preload("res://audio/hit/hit.ogg")
const ELIMINATED_SOUND: AudioStream = preload("res://audio/hit/eliminated.ogg")
const SFX_BUS: StringName = &"SFX"

## Set by Overlay; while false every hit is ignored.
var active: bool = false
## Whose hero is "me". -1 means this game's own network id (the preview sets a fake one).
var own_peer_id: int = -1

@export_group("Damage numbers")
## Text size at 1080p; the UI scaler grows it.
@export_range(18, 64, 1, "suffix:px") var number_font_size: int = 26
@export var number_color: Color = Color(1.0, 1.0, 1.0)
@export var number_outline_color: Color = Color(0.05, 0.05, 0.08)
@export_range(0, 12, 1, "suffix:px") var number_outline_size: int = 6
@export_range(10.0, 120.0, 1.0, "suffix:px") var number_rise: float = 40.0
@export_range(0.2, 2.0, 0.05, "suffix:s") var number_life_sec: float = 0.7
## Most numbers on screen at once; the oldest is reused.
@export_range(4, 64, 1) var max_numbers: int = 24

@export_group("Flash and puff")
## Edge flash when your hero is hit.
@export var flash_color: Color = Color(0.9, 0.1, 0.1)
@export_range(0.05, 0.35, 0.05) var flash_max_opacity: float = 0.3
@export_range(0.05, 0.25, 0.01, "suffix:s") var flash_sec: float = 0.2
@export_range(8, 120, 1, "suffix:px") var flash_edge_size: int = 40
## Flashes closer together than this are skipped, so it can never strobe (0.34 = 3 a second).
@export_range(0.34, 2.0, 0.01, "suffix:s") var flash_min_gap_sec: float = 0.34
@export var puff_color: Color = Color(1.0, 0.9, 0.4)
@export_range(2, 16, 1) var puff_count: int = 6
@export_range(2, 16, 1) var max_puffs: int = 8

@export_group("Sounds")
@export_range(1, 16, 1) var max_voices: int = 8
## +/- share of pitch change on every sound.
@export_range(0.0, 0.2, 0.01) var pitch_spread: float = 0.05
@export_range(-24.0, 6.0, 0.5, "suffix:dB") var hit_volume_db: float = -6.0
@export_range(-24.0, 6.0, 0.5, "suffix:dB") var eliminated_volume_db: float = -3.0
## Silent when the hit is this many screen widths away from the middle of your screen.
@export_range(0.5, 4.0, 0.1, "suffix:screens") var silent_beyond_screens: float = 1.5

var _numbers: Array[Label] = []
var _number_age: Array[float] = []
var _number_pos: Array[Vector2] = []
var _next_number: int = 0
var _puffs: Array[CPUParticles2D] = []
var _next_puff: int = 0
var _voices: Array[AudioStreamPlayer] = []
var _flash: Panel = Panel.new()
var _flash_left: float = 0.0
var _last_flash_msec: int = -100000


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_flash()
	for i: int in max_numbers:
		_numbers.append(_make_number())
		_number_age.append(number_life_sec)
		_number_pos.append(Vector2.ZERO)
	for i: int in max_puffs:
		_puffs.append(_make_puff())
	for i: int in max_voices:
		var voice := AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		add_child(voice)
		_voices.append(voice)
	Events.hero_damaged.connect(_on_hero_damaged)
	Events.hero_eliminated.connect(_on_hero_eliminated)


func _process(delta: float) -> void:
	var to_screen: Transform2D = get_viewport().get_canvas_transform()
	for i: int in _numbers.size():
		var label: Label = _numbers[i]
		if not label.visible:
			continue
		_number_age[i] += delta
		var t: float = _number_age[i] / number_life_sec
		if t >= 1.0:
			label.visible = false
			continue
		_place_number(i, to_screen, t)
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		_flash.modulate.a = flash_max_opacity * (_flash_left / flash_sec)
		_flash.visible = _flash_left > 0.0


func _on_hero_damaged(victim_peer_id: int, _attacker_peer_id: int, amount: int, hit_position: Vector2) -> void:
	if not active or amount <= 0:
		return
	_show_number(amount, hit_position)
	if victim_peer_id == _me():
		_start_flash()
	else:
		_show_puff(hit_position)
	_play(HIT_SOUND, hit_volume_db, hit_position)


func _on_hero_eliminated(victim_peer_id: int, _attacker_peer_id: int) -> void:
	if not active:
		return
	var hero := _hero(victim_peer_id)
	var spot: Vector2 = _screen_middle_in_world()
	if hero != null:
		spot = hero.global_position
	elif victim_peer_id != _me():
		return
	_show_puff(spot)
	_play(ELIMINATED_SOUND, eliminated_volume_db, spot)


func _show_number(amount: int, world_position: Vector2) -> void:
	var i: int = _next_number
	_next_number = (_next_number + 1) % _numbers.size()
	_numbers[i].text = str(amount)
	_numbers[i].reset_size()
	_number_age[i] = 0.0
	_number_pos[i] = world_position
	_place_number(i, get_viewport().get_canvas_transform(), 0.0)
	_numbers[i].visible = true


## Puts number i where its world point is on screen, t (0 to 1) of the way through its life.
func _place_number(i: int, to_screen: Transform2D, t: float) -> void:
	var label: Label = _numbers[i]
	label.position = to_screen * _number_pos[i] - label.size * 0.5 - Vector2(0.0, number_rise * t)
	label.modulate.a = 1.0 - t


func _start_flash() -> void:
	var now: int = Time.get_ticks_msec()
	if float(now - _last_flash_msec) / 1000.0 < flash_min_gap_sec:
		return
	_last_flash_msec = now
	_flash_left = flash_sec
	_flash.modulate.a = flash_max_opacity
	_flash.visible = true


func _show_puff(world_position: Vector2) -> void:
	var puff: CPUParticles2D = _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % _puffs.size()
	puff.position = get_viewport().get_canvas_transform() * world_position
	puff.restart()
	puff.emitting = true


func _play(stream: AudioStream, volume_db: float, world_position: Vector2) -> void:
	var reach: float = get_viewport_rect().size.x * silent_beyond_screens
	var distance: float = world_position.distance_to(_screen_middle_in_world())
	if distance >= reach:
		return
	for voice: AudioStreamPlayer in _voices:
		if voice.playing:
			continue
		voice.stream = stream
		voice.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
		voice.volume_db = volume_db + linear_to_db(1.0 - distance / reach)
		voice.play()
		return


func _me() -> int:
	return own_peer_id if own_peer_id >= 0 else multiplayer.get_unique_id()


func _hero(peer_id: int) -> Node2D:
	var world := get_tree().current_scene
	if world == null:
		return null
	return world.get_node_or_null("Heroes/%d" % peer_id) as Node2D


## The world point at the middle of the screen, which is where your hero is.
func _screen_middle_in_world() -> Vector2:
	var to_screen: Transform2D = get_viewport().get_canvas_transform()
	return to_screen.affine_inverse() * (get_viewport_rect().size * 0.5)


func _make_number() -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	label.add_theme_font_size_override(&"font_size", number_font_size)
	label.add_theme_color_override(&"font_color", number_color)
	label.add_theme_color_override(&"font_outline_color", number_outline_color)
	label.add_theme_constant_override(&"outline_size", number_outline_size)
	add_child(label)
	return label


func _make_puff() -> CPUParticles2D:
	var puff := CPUParticles2D.new()
	puff.emitting = false
	puff.one_shot = true
	puff.local_coords = true
	puff.explosiveness = 1.0
	puff.amount = puff_count
	puff.lifetime = 0.35
	puff.direction = Vector2.UP
	puff.spread = 180.0
	puff.initial_velocity_min = 60.0
	puff.initial_velocity_max = 120.0
	puff.gravity = Vector2.ZERO
	puff.scale_amount_min = 6.0
	puff.scale_amount_max = 12.0
	puff.color = puff_color
	add_child(puff)
	return puff


func _build_flash() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = flash_color
	style.set_border_width_all(flash_edge_size)
	_flash.add_theme_stylebox_override(&"panel", style)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.visible = false
	add_child(_flash)

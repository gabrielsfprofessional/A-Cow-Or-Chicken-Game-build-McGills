extends SceneTree
## Tests for T31's hero-art seam: HeroData.body_texture and body_size_px on NetHero. Owner: Gabe.
## Run: godot --headless --path . --script res://tests/hero_art_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
##
## 1. No texture: the Body square shows with the player's tint and there is no BodySprite.
## 2. A 64x64 texture (made here with Image.create, never a file): a BodySprite shows at 48 px,
##    centered, white (no tint), not turned; Body is hidden; the collider doesn't change.
## 3. A 96x32 texture keeps its shape: 48 x 16 px. body_rect() (the outline's rect) follows it.
## 4. body_size_px sets the longer side (96 px), and HeroData.body_scale() never divides by 0.
##
## NetHero uses the Events and Net autoloads, so this test never names it (see tests/README.md):
## it loads the hero scene at run time.

const HERO_SCENE_PATH: String = "res://game/heroes/net_hero.tscn"
const ROSTER_PATH: String = "res://game/heroes/data/roster.tres"
const TINT: Color = Color(0.2, 0.6, 0.9)
## The collider's radius in net_hero.tscn; art never changes it.
const COLLIDER_RADIUS: float = 20.0
## The node cases wait a frame for _ready. An error after an await would hang
## the test, so it fails itself after this long.
const DEADLINE_SEC: float = 10.0


## Stands in for the test world: the parent of "Heroes".
class FakeWorld:
	extends Node2D

	func teams_seen() -> Dictionary[int, int]:
		return {}

	func rules() -> MatchRules:
		return MatchRules.new()

	func is_peer_ready(_peer_id: int) -> bool:
		return false


var _failed: int = 0
var _count: int = 0
var _world: FakeWorld = null
var _next_peer: int = 10


func _initialize() -> void:
	create_timer(DEADLINE_SEC).timeout.connect(_on_deadline)
	_run()


func _on_deadline() -> void:
	printerr("  FAIL  the test did not finish within %d s (a script error after an await?)" % roundi(DEADLINE_SEC))
	quit(1)


func _run() -> void:
	_world = FakeWorld.new()
	_world.name = "World"
	root.add_child(_world)
	var heroes := Node2D.new()
	heroes.name = "Heroes"
	_world.add_child(heroes)
	_body_scale()
	await _no_texture()
	await _square_texture()
	await _wide_texture()
	await _bigger_size()
	_world.free()
	print("HERO ART TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _body_scale() -> void:
	_expect(is_equal_approx(HeroData.body_scale(Vector2(64.0, 64.0), 48.0), 0.75), "64x64 at 48 px scales by 0.75",
		"got %s" % HeroData.body_scale(Vector2(64.0, 64.0), 48.0))
	_expect(is_equal_approx(HeroData.body_scale(Vector2(32.0, 96.0), 48.0), 0.5), "the longer side sets the scale (32x96 at 48 px: 0.5)",
		"got %s" % HeroData.body_scale(Vector2(32.0, 96.0), 48.0))
	_expect(HeroData.body_scale(Vector2.ZERO, 48.0) == 1.0, "an empty size scales by 1, never infinity",
		"got %s" % HeroData.body_scale(Vector2.ZERO, 48.0))


## A hero built from the roster's first hero, with `texture` and `size_px`, in the fake world.
func _spawn(texture: Texture2D, size_px: float) -> Node2D:
	var roster := load(ROSTER_PATH) as HeroRoster
	var data := roster.first().duplicate() as HeroData
	data.body_texture = texture
	data.body_size_px = size_px
	var hero := (load(HERO_SCENE_PATH) as PackedScene).instantiate() as Node2D
	_next_peer += 1
	hero.call(&"setup", _next_peer, Vector2(100.0, 100.0), TINT, data)
	_world.get_node(^"Heroes").add_child(hero)
	await process_frame
	return hero


func _texture(width: int, height: int) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.9, 0.3, 0.1, 1.0))
	return ImageTexture.create_from_image(image)


## The BodySprite's drawn size in pixels, or ZERO when there is none.
func _drawn_size(hero: Node2D) -> Vector2:
	var sprite := hero.get_node_or_null(^"BodySprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return Vector2.ZERO
	return sprite.texture.get_size() * sprite.scale


func _collider_radius(hero: Node2D) -> float:
	var shape := (hero.get_node(^"Collider") as CollisionShape2D).shape as CircleShape2D
	return shape.radius if shape != null else -1.0


func _no_texture() -> void:
	var hero := await _spawn(null, 48.0)
	var body := hero.get_node(^"Body") as ColorRect
	_expect(body.visible, "no texture: the Body square shows", "it is hidden")
	_expect(body.color.is_equal_approx(TINT), "no texture: the Body keeps the player's tint", "its color is %s" % body.color)
	_expect(hero.get_node_or_null(^"BodySprite") == null, "no texture: there is no BodySprite", "there is one")
	_expect(hero.call(&"body_rect") == Rect2(-24.0, -24.0, 48.0, 48.0), "no texture: body_rect() is the Body square",
		"got %s" % hero.call(&"body_rect"))
	hero.free()


func _square_texture() -> void:
	var hero := await _spawn(_texture(64, 64), 48.0)
	var sprite := hero.get_node_or_null(^"BodySprite") as Sprite2D
	_expect(sprite != null and sprite.visible, "a 64x64 texture: a BodySprite shows", "there is none")
	if sprite == null:
		hero.free()
		return
	_expect(_drawn_size(hero).is_equal_approx(Vector2(48.0, 48.0)), "a 64x64 texture is drawn at 48 x 48 px",
		"drawn at %s" % _drawn_size(hero))
	_expect(not (hero.get_node(^"Body") as ColorRect).visible, "with a texture, the Body square is hidden", "it shows")
	_expect(sprite.modulate == Color.WHITE and sprite.self_modulate == Color.WHITE, "the sprite is not tinted",
		"modulate %s, self_modulate %s" % [sprite.modulate, sprite.self_modulate])
	_expect(sprite.centered and sprite.position == Vector2.ZERO and sprite.rotation == 0.0,
		"the sprite is centered on the hero and not turned", "centered %s, position %s, rotation %s" % [
			sprite.centered, sprite.position, sprite.rotation])
	_expect(is_equal_approx(_collider_radius(hero), COLLIDER_RADIUS), "the collider doesn't change (radius 20)",
		"radius %s" % _collider_radius(hero))
	_expect(sprite.get_index() == hero.get_node(^"Body").get_index() + 1, "the sprite takes the Body's place in the draw order",
		"index %d, Body %d" % [sprite.get_index(), hero.get_node(^"Body").get_index()])
	hero.free()


func _wide_texture() -> void:
	var hero := await _spawn(_texture(96, 32), 48.0)
	_expect(_drawn_size(hero).is_equal_approx(Vector2(48.0, 16.0)), "a 96x32 texture keeps its shape: 48 x 16 px",
		"drawn at %s" % _drawn_size(hero))
	var rect: Rect2 = hero.call(&"body_rect")
	_expect(rect.is_equal_approx(Rect2(-24.0, -8.0, 48.0, 16.0)), "body_rect() (the outline's rect) follows the sprite",
		"got %s" % rect)
	hero.free()


func _bigger_size() -> void:
	var hero := await _spawn(_texture(64, 64), 96.0)
	_expect(_drawn_size(hero).is_equal_approx(Vector2(96.0, 96.0)), "body_size_px 96 draws a 64x64 texture at 96 px",
		"drawn at %s" % _drawn_size(hero))
	_expect(is_equal_approx(_collider_radius(hero), COLLIDER_RADIUS), "a bigger drawing keeps the collider at radius 20",
		"radius %s" % _collider_radius(hero))
	hero.free()


func _expect(ok: bool, what: String, problem: String) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s: %s" % [what, problem])

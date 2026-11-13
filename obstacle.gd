extends Area2D
## A falling asteroid. Created in code by game.gd via setup().
## From Level 2 some asteroids sway side to side and/or drift diagonally (still falling down).

var fall_speed: float = 250.0
var spin: float = 0.0
var radius: float = 30.0

## Side-to-side sway (0 = falls straight).
var sway_amount: float = 0.0
var sway_speed: float = 0.0
## Constant sideways drift in pixels/second (bounces off the screen edges).
var drift: float = 0.0
## Swaying/drifting asteroids glow orange so players can spot them.
var tricky: bool = false

var _time: float = 0.0
var _phase: float = 0.0
var _base_x: float = 0.0
var _color: Color
var _outline: PackedVector2Array
var _body: PackedVector2Array
var _shadow: PackedVector2Array
var _highlight: PackedVector2Array
var _craters: Array[Vector3] = []  # x, y, radius
var _glow: Sprite2D
var _sprite: Sprite2D

## Soft round glow texture shared by all asteroids (set once by game.gd).
static var glow_tex: Texture2D
## How fast the rocket is flying forward (1 = normal, higher while boosting). Everything
## coming toward the rocket falls faster by this much. Set by game.gd.
static var world_speed: float = 1.0

## Performance: game.gd pre-renders 8 asteroid shapes + the warning glow into ONE texture
## ("atlas") at startup. Each asteroid is then just a sprite cut from that atlas, so every
## asteroid on screen shares one texture and Godot draws them all in one batch instead of
## ~15 draw calls each. (If the atlas isn't ready yet, asteroids fall back to vector drawing.)
static var atlas: Texture2D
const ATLAS_CELL := 128
const ATLAS_COLUMNS := 4
const ATLAS_ROCKS := 8
const ATLAS_GLOW_CELL := 8
## Radius the rock shapes are baked at, and their neutral base colour (tinted per planet).
const BAKE_RADIUS := 56.0
const BAKE_GRAY := 0.8


static func atlas_region(cell: int) -> Rect2:
	return Rect2((cell % ATLAS_COLUMNS) * ATLAS_CELL, (cell / ATLAS_COLUMNS) * ATLAS_CELL, ATLAS_CELL, ATLAS_CELL)


func setup(size: float, tint: Color) -> void:
	radius = size
	_color = tint.lightened(randf_range(-0.12, 0.12))
	_phase = randf() * TAU

	var shape := CircleShape2D.new()
	shape.radius = radius * 0.85  # slightly forgiving hitbox
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)

	if atlas:
		_sprite = Sprite2D.new()
		_sprite.texture = atlas
		_sprite.region_enabled = true
		_sprite.region_rect = atlas_region(randi() % ATLAS_ROCKS)
		_sprite.scale = Vector2.ONE * radius / BAKE_RADIUS
		# The baked rock is neutral gray; tinting it gives this planet's rock colour.
		_sprite.modulate = Color(_color.r / BAKE_GRAY, _color.g / BAKE_GRAY, _color.b / BAKE_GRAY)
		add_child(_sprite)
		return

	# Lumpy outline, plus shifted/shrunk copies for shadow and highlight (gives a 3D look).
	var count := randi_range(9, 13)
	for i in count:
		var angle := TAU * i / count + randf_range(-0.15, 0.15)
		_outline.append(Vector2.from_angle(angle) * radius * randf_range(0.78, 1.08))
	for p in _outline:
		_shadow.append(p)
		_body.append(p * 0.9 + Vector2(-radius * 0.06, -radius * 0.06))
		_highlight.append(p * 0.5 + Vector2(-radius * 0.22, -radius * 0.24))

	for i in randi_range(2, 4):
		var pos := Vector2.from_angle(randf() * TAU) * radius * randf_range(0.0, 0.5)
		_craters.append(Vector3(pos.x, pos.y, radius * randf_range(0.12, 0.22)))


func _ready() -> void:
	_base_x = position.x
	if tricky and (atlas or glow_tex):
		# Warning glow as a sprite behind the rock: pulsing it is just a colour change,
		# so the asteroid itself never has to be redrawn. Taken from the shared atlas when
		# available so it batches with the rocks.
		_glow = Sprite2D.new()
		if atlas:
			_glow.texture = atlas
			_glow.region_enabled = true
			_glow.region_rect = atlas_region(ATLAS_GLOW_CELL)
			_glow.scale = Vector2.ONE * radius * 2.9 / ATLAS_CELL
		else:
			_glow.texture = glow_tex
			_glow.scale = Vector2.ONE * radius * 2.9 / glow_tex.get_width()
		_glow.show_behind_parent = true
		_glow.modulate = Color(1.0, 0.45, 0.15, 0.5)
		add_child(_glow)


func _process(delta: float) -> void:
	_time += delta
	var width := get_viewport_rect().size.x

	_base_x += drift * delta
	if _base_x < radius or _base_x > width - radius:
		drift = -drift
		_base_x = clampf(_base_x, radius, width - radius)

	position.x = _base_x + sin(_time * sway_speed + _phase) * sway_amount
	position.y += fall_speed * world_speed * delta
	rotation += spin * delta
	if _glow:
		_glow.modulate.a = 0.35 + 0.25 * sin(_time * 6.0)

	if position.y > get_viewport_rect().size.y + radius + 60.0:
		queue_free()


## Vector drawing: used to bake the atlas, and as a fallback before it exists.
## Drawn once; spinning and falling only move/rotate the node.
func _draw() -> void:
	if _outline.is_empty():
		return  # sprite asteroid
	draw_colored_polygon(_shadow, _color.darkened(0.35))
	draw_colored_polygon(_body, _color)
	draw_colored_polygon(_highlight, _color.lightened(0.14))

	for c in _craters:
		var pos := Vector2(c.x, c.y)
		draw_circle(pos, c.z, _color.darkened(0.25))
		draw_circle(pos + Vector2(c.z * 0.2, c.z * 0.2), c.z * 0.7, _color.darkened(0.12))

	var closed := _outline.duplicate()
	closed.append(_outline[0])
	draw_polyline(closed, _color.darkened(0.5), 1.5, true)

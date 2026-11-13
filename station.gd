extends Area2D
## Refuel station: drifts down the screen on every even level. Fly into it to refill the booster.
## It never hurts the rocket; once used it powers down (greys out).

const Obstacle := preload("res://obstacle.gd")
const Palette := preload("res://palette.gd")

var fall_speed: float = 110.0
var used: bool = false

var _time: float = 0.0


func _ready() -> void:
	var shape := CircleShape2D.new()
	shape.radius = 58.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)


func _process(delta: float) -> void:
	_time += delta
	# Approaches faster while the rocket boosts forward (same world speed as asteroids).
	position.y += fall_speed * Obstacle.world_speed * delta
	queue_redraw()
	if position.y > get_viewport_rect().size.y + 140.0:
		queue_free()


func _draw() -> void:
	# Flat palette station: pale metal, teal solar panels, aqua "fuel here" light.
	var metal := Color("c9d6dc") if not used else Palette.SLATE
	var dark := metal.darkened(0.3)
	var panel := Palette.TEAL if not used else Palette.INDIGO
	var glow := Palette.AQUA if not used else Palette.TEXT_DIM

	# Pulsing "fly here" ring.
	if not used:
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		draw_arc(Vector2.ZERO, 62.0 + pulse * 8.0, 0.0, TAU, 48, Color(glow, 0.35 + 0.3 * pulse), 3.0, true)

	# Solar panel wings on a truss.
	draw_rect(Rect2(-112, -3, 224, 6), dark)
	for side in [-1.0, 1.0]:
		var s: float = side
		for i in 3:
			var x := s * (42.0 + i * 24.0) - (22.0 if s < 0 else 0.0)
			draw_rect(Rect2(x, -18, 22, 36), panel)
			draw_line(Vector2(x + 11, -18), Vector2(x + 11, 18), panel.lightened(0.2), 1.0)

	# Rotating outer ring with spokes.
	var spin := _time * 0.8
	draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 48, metal, 7.0, true)
	for i in 4:
		var dir := Vector2.from_angle(spin + i * TAU / 4.0)
		draw_line(dir * 14.0, dir * 37.0, dark, 3.0)

	# Central hub with the fuel tank.
	draw_circle(Vector2.ZERO, 18.0, metal)
	draw_circle(Vector2.ZERO, 12.0, glow.darkened(0.2))
	draw_circle(Vector2(-3, -3), 5.0, glow.lightened(0.4))

	# Blinking navigation lights.
	var blink := fmod(_time, 1.0) < 0.5
	draw_circle(Vector2(-112, 0), 4.0, Palette.ORANGE if blink else Palette.RUST.darkened(0.5))
	draw_circle(Vector2(112, 0), 4.0, Palette.AQUA if not blink else Palette.TEAL_DEEP)

	# Label.
	var font := ThemeDB.fallback_font
	var text := "FUEL" if not used else "EMPTY"
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(-width / 2.0, 66.0 + 18.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, glow)

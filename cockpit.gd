extends Control
## Ship-interior frame drawn around the screen: hull top bar, side pillars, window braces,
## glass reflections, and the instrument console along the bottom.
##
## Performance: drawn once (not every frame), and built mostly from rectangles and a few
## shared textures so Godot can batch them into very few draw calls - draw calls are the
## expensive part on the web (WebGL).

const TOP := 50.0
const SIDE := 16.0

## Height of the bottom console (game.gd sets it: taller on portrait phones).
var dash_height: float = 70.0:
	set(value):
		dash_height = value
		queue_redraw()

var _time: float = 0.0
## The frame itself is drawn once; only this small child with the blinking LEDs redraws,
## and only when an LED actually switches on/off.
var _leds: Control
var _led_mask: int = -1

var _rivet_tex: Texture2D
var _hazard_tex: Texture2D
var _shadow_tex: Texture2D  # dark at the top, fading out downward (rotated for other edges)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_textures()
	resized.connect(queue_redraw)
	_leds = Control.new()
	_leds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leds.draw.connect(_draw_leds)
	add_child(_leds)


func _process(delta: float) -> void:
	_time += delta
	var mask := 0
	for i in 5:
		if fmod(_time * 1.5 + i * 0.37, 1.0) < 0.6:
			mask |= 1 << i
	if mask != _led_mask:
		_led_mask = mask
		_leds.queue_redraw()


func _draw_leds() -> void:
	var cx := size.x / 2.0
	for i in 5:
		var on := (_led_mask & (1 << i)) != 0
		var led := Color(0.3, 1.0, 0.5) if i != 2 else Color(0.4, 0.75, 1.0)
		_leds.draw_rect(Rect2(cx - 43 + i * 20, TOP + 1, 6, 6), led if on else led.darkened(0.7))


func _draw() -> void:
	var s := size
	var steel := Color(0.17, 0.19, 0.24)
	var steel_hi := Color(0.36, 0.4, 0.48)
	var steel_dark := Color(0.08, 0.09, 0.12)
	var console_top := s.y - dash_height
	var window := Rect2(SIDE, TOP, s.x - SIDE * 2.0, console_top - TOP)

	# Window glass: soft shadow along each inner edge (one shared gradient texture)...
	var depth := 34.0
	draw_texture_rect(_shadow_tex, Rect2(window.position, Vector2(window.size.x, depth)), false)
	draw_set_transform(Vector2(window.end.x, window.end.y), PI)
	draw_texture_rect(_shadow_tex, Rect2(Vector2.ZERO, Vector2(window.size.x, depth)), false)
	draw_set_transform(Vector2(window.position.x, window.end.y), -PI / 2.0)
	draw_texture_rect(_shadow_tex, Rect2(Vector2.ZERO, Vector2(window.size.y, depth)), false)
	draw_set_transform(Vector2(window.end.x, window.position.y), PI / 2.0)
	draw_texture_rect(_shadow_tex, Rect2(Vector2.ZERO, Vector2(window.size.y, depth)), false)
	draw_set_transform(Vector2.ZERO)
	# ...and a couple of faint diagonal reflections.
	draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.66, TOP), Vector2(s.x * 0.74, TOP),
		Vector2(s.x * 0.56, console_top * 0.6), Vector2(s.x * 0.48, console_top * 0.6)]), Color(1, 1, 1, 0.03))
	draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.77, TOP), Vector2(s.x * 0.79, TOP),
		Vector2(s.x * 0.61, console_top * 0.6), Vector2(s.x * 0.59, console_top * 0.6)]), Color(1, 1, 1, 0.03))

	# Top hull bar, side pillars and console: plain rectangles (these batch together).
	draw_rect(Rect2(0, 0, s.x, TOP), steel)
	draw_rect(Rect2(0, 0, s.x, 3), steel_hi.darkened(0.2))
	draw_rect(Rect2(0, TOP - 4, s.x, 4), steel_hi)
	draw_rect(Rect2(0, TOP, s.x, 3), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(0, 0, SIDE, s.y), steel)
	draw_rect(Rect2(s.x - SIDE, 0, SIDE, s.y), steel)
	draw_rect(Rect2(SIDE - 2.0, TOP, 2, console_top - TOP), steel_hi)
	draw_rect(Rect2(s.x - SIDE, TOP, 2, console_top - TOP), steel_hi)
	draw_rect(Rect2(0, console_top, s.x, dash_height), steel_dark.lerp(steel, 0.45))
	draw_rect(Rect2(0, console_top, s.x, 4), steel_hi)

	# Hazard stripe along the console's top edge: one tiled texture.
	draw_texture_rect(_hazard_tex, Rect2(0, console_top + 4.0, s.x, 6), true)

	# Centre housing for the status LEDs.
	var cx := s.x / 2.0
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 90, TOP - 2), Vector2(cx + 90, TOP - 2),
		Vector2(cx + 70, TOP + 12), Vector2(cx - 70, TOP + 12)]), steel)
	draw_rect(Rect2(cx - 70, TOP + 11, 140, 2), steel_hi)

	# Window braces in the inner corners.
	var brace := 46.0
	var rivets: Array[Vector2] = []
	for corner in [[Vector2(SIDE, TOP), 1.0, 1.0], [Vector2(s.x - SIDE, TOP), -1.0, 1.0],
			[Vector2(SIDE, console_top), 1.0, -1.0], [Vector2(s.x - SIDE, console_top), -1.0, -1.0]]:
		var p: Vector2 = corner[0]
		var dx: float = corner[1]
		var dy: float = corner[2]
		draw_colored_polygon(PackedVector2Array([p, p + Vector2(brace * dx, 0), p + Vector2(0, brace * dy)]), steel)
		rivets.append(p + Vector2(12 * dx, 12 * dy))

	# Rivets: all the same small texture, so they're a single batched draw.
	var rx := 40.0
	while rx < s.x - 30.0:
		rivets.append(Vector2(rx, TOP - 12.0))
		rx += 90.0
	for px in [8.0, s.x - 8.0]:
		var ry := TOP + 40.0
		while ry < console_top - 20.0:
			rivets.append(Vector2(px, ry))
			ry += 90.0
	for at in rivets:
		draw_texture_rect(_rivet_tex, Rect2(at - Vector2(4, 4), Vector2(8, 8)), false)


func _make_textures() -> void:
	# Rivet: dome with a highlight toward the top-left and a dark rim.
	var rivet := Gradient.new()
	rivet.set_color(0, Color(0.5, 0.54, 0.62))
	rivet.set_color(1, Color(0, 0, 0, 0))
	rivet.add_point(0.55, Color(0.1, 0.11, 0.14))
	rivet.add_point(0.7, Color(0.06, 0.07, 0.09, 0.8))
	var rivet_tex := GradientTexture2D.new()
	rivet_tex.width = 16
	rivet_tex.height = 16
	rivet_tex.fill = GradientTexture2D.FILL_RADIAL
	rivet_tex.fill_from = Vector2(0.38, 0.38)
	rivet_tex.fill_to = Vector2(0.95, 0.38)
	rivet_tex.gradient = rivet
	_rivet_tex = rivet_tex

	# Edge shadow: dark at the top fading to clear.
	var shadow := Gradient.new()
	shadow.set_color(0, Color(0, 0, 0, 0.5))
	shadow.set_color(1, Color(0, 0, 0, 0))
	var shadow_tex := GradientTexture2D.new()
	shadow_tex.width = 4
	shadow_tex.height = 64
	shadow_tex.fill_from = Vector2(0, 0)
	shadow_tex.fill_to = Vector2(0, 1)
	shadow_tex.gradient = shadow
	_shadow_tex = shadow_tex

	# Hazard stripes: a small yellow/black diagonal tile, repeated across the console.
	var image := Image.create(16, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in 16:
			var yellow := (x + (5 - y)) % 16 < 8
			image.set_pixel(x, y, Color(0.95, 0.75, 0.1, 0.8) if yellow else Color(0.1, 0.1, 0.1))
	_hazard_tex = ImageTexture.create_from_image(image)

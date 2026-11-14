extends Control
## Ship-interior frame drawn around the screen: hull top bar, side pillars, window braces,
## glass reflections, and the instrument console along the bottom.
##
## Performance: drawn once (not every frame), and built mostly from rectangles and a few
## shared textures so Godot can batch them into very few draw calls - draw calls are the
## expensive part on the web (WebGL).

const Palette := preload("res://scripts/game/palette.gd")
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
		var led: Color = Palette.AQUA if i != 2 else Palette.AMBER
		var r := Rect2(cx - 46 + i * 20, TOP + 2, 12, 5)
		_leds.draw_rect(r, led if on else Palette.SLATE)


## Flat frame (minimal vector style): dark ink bars, rounded inner corners, one thin aqua
## line where glass meets frame, and a few small lights. No rivets, gradients or stripes.
func _draw() -> void:
	var s := size
	var console_top := s.y - dash_height
	var frame := Palette.INK
	var line := Color(Palette.AQUA, 0.35)

	# Bars: top, sides, console.
	draw_rect(Rect2(0, 0, s.x, TOP), frame)
	draw_rect(Rect2(0, 0, SIDE, s.y), frame)
	draw_rect(Rect2(s.x - SIDE, 0, SIDE, s.y), frame)
	draw_rect(Rect2(0, console_top, s.x, dash_height), Palette.NAVY)
	draw_rect(Rect2(0, console_top, s.x, 3), Palette.INDIGO)

	# Rounded inner corners of the window (flat quarter-circle fillets).
	var r := 22.0
	for corner in [[Vector2(SIDE, TOP), 1.0, 1.0], [Vector2(s.x - SIDE, TOP), -1.0, 1.0],
			[Vector2(SIDE, console_top), 1.0, -1.0], [Vector2(s.x - SIDE, console_top), -1.0, -1.0]]:
		var p: Vector2 = corner[0]
		var dx: float = corner[1]
		var dy: float = corner[2]
		# Corner p, then an arc around centre p + (dx*r, dy*r) that bows toward p.
		var centre := p + Vector2(dx * r, dy * r)
		var pts := PackedVector2Array([p])
		for k in 9:
			var a := PI / 2.0 * k / 8.0
			pts.append(centre + Vector2(-dx * r * cos(a), -dy * r * sin(a)))
		draw_colored_polygon(pts, frame if dy > 0.0 else Palette.NAVY)

	# Thin aqua edge where the glass meets the frame.
	draw_line(Vector2(SIDE + r, TOP), Vector2(s.x - SIDE - r, TOP), line, 1.5)
	draw_line(Vector2(SIDE, TOP + r), Vector2(SIDE, console_top - r), line, 1.5)
	draw_line(Vector2(s.x - SIDE, TOP + r), Vector2(s.x - SIDE, console_top - r), line, 1.5)

	# Centre tab for the status lights.
	var cx := s.x / 2.0
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 76, TOP - 1), Vector2(cx + 76, TOP - 1),
		Vector2(cx + 64, TOP + 12), Vector2(cx - 64, TOP + 12)]), frame)



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

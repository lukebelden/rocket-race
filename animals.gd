extends Control
## Animal pilots: duck, mouse, dog, cat, bear, raccoon, monkey, drawn with simple shapes.
## As a Control it's an avatar (menus, hangar, lobby) that blinks now and then.
## draw_face() is also used by the pilot cards on the HUD (pilot_card.gd).
##
## Moods change the eyes, brows and mouth: "normal", "happy", "excited", "worried",
## "hurt" and "out" (knocked out: X eyes).

var animal: String = "duck":
	set(value):
		animal = value
		queue_redraw()
var mood: String = "normal":
	set(value):
		mood = value
		queue_redraw()

var _t := 0.0
var _blink_at := 2.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_t += delta
	# Redraw only around blinks.
	if _t >= _blink_at - 0.02 and _t <= _blink_at + 0.2:
		queue_redraw()
	elif _t > _blink_at + 0.2:
		_blink_at = _t + randf_range(2.0, 5.0)
		queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.36
	var blink := _t >= _blink_at and _t < _blink_at + 0.13
	draw_face(self, size / 2.0 + Vector2(0, r * 0.08), r, animal, mood, blink)


# --- Palette ---------------------------------------------------------------------------------

## Main fur/feather colour (pilot cards use it for paws).
static func fur(id: String) -> Color:
	match id:
		"duck": return Color(1.0, 0.84, 0.26)
		"mouse": return Color(0.7, 0.7, 0.76)
		"dog": return Color(0.86, 0.66, 0.42)
		"cat": return Color(1.0, 0.62, 0.28)
		"bear": return Color(0.56, 0.37, 0.23)
		"raccoon": return Color(0.6, 0.6, 0.64)
		"monkey": return Color(0.52, 0.34, 0.21)
	return Color(0.8, 0.8, 0.85)


# --- Shape helpers -------------------------------------------------------------------------

static func _ellipse(c: Vector2, rx: float, ry: float, rot := 0.0, n := 22) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


static func _w(r: float, k: float) -> float:
	return maxf(r * k, 1.0)


## Soft light from the top left and shade at the bottom, so heads look round.
static func _shade(canvas: CanvasItem, c: Vector2, r: float) -> void:
	canvas.draw_colored_polygon(_ellipse(c + Vector2(r * 0.12, r * 0.18), r * 0.92, r * 0.86), Color(0, 0, 0, 0.1))
	canvas.draw_circle(c + Vector2(-r * 0.32, -r * 0.4), r * 0.42, Color(1, 1, 1, 0.13))


## Eyes for every mood. spread/y are fractions of r; iris = coloured ring.
static func _eyes(canvas: CanvasItem, c: Vector2, r: float, mood: String, blink: bool,
		spread := 0.36, y := -0.08, size := 1.0, iris := Color(0.25, 0.17, 0.1), mask := false) -> void:
	var ink := Color(0.08, 0.07, 0.1)
	var er := r * 0.17 * size
	for s in [-1.0, 1.0]:
		var e: Vector2 = c + Vector2(s * r * spread, r * y)
		match mood:
			"out":
				var xc := Color(1, 1, 1) if mask else ink
				canvas.draw_line(e + Vector2(-er, -er), e + Vector2(er, er), xc, _w(r, 0.07))
				canvas.draw_line(e + Vector2(-er, er), e + Vector2(er, -er), xc, _w(r, 0.07))
				continue
			"happy":
				canvas.draw_arc(e + Vector2(0, er * 0.4), er, PI * 1.15, PI * 1.85, 10, Color(1, 1, 1) if mask else ink, _w(r, 0.07))
				continue
			"hurt":
				canvas.draw_line(e + Vector2(-er, -er * 0.6 * s), e + Vector2(er * 0.8, 0), ink if not mask else Color(1, 1, 1), _w(r, 0.07))
				canvas.draw_line(e + Vector2(-er, er * 0.6 * s), e + Vector2(er * 0.8, 0), ink if not mask else Color(1, 1, 1), _w(r, 0.07))
				continue
		if blink:
			canvas.draw_line(e + Vector2(-er, 0), e + Vector2(er, 0), Color(1, 1, 1) if mask else ink, _w(r, 0.06))
			continue
		var big := 1.18 if mood == "excited" or mood == "worried" else 1.0
		canvas.draw_circle(e, er * big, Color(1, 1, 1))
		canvas.draw_circle(e + Vector2(0, er * 0.12), er * 0.68 * big, iris)
		canvas.draw_circle(e + Vector2(0, er * 0.12), er * 0.4 * big, ink)
		canvas.draw_circle(e + Vector2(-er * 0.28, -er * 0.22), er * 0.24, Color(1, 1, 1))
		if mood == "excited":  # sparkle
			canvas.draw_circle(e + Vector2(er * 0.3, er * 0.35), er * 0.1, Color(1, 1, 1))
	# Brows tell the mood quickest.
	var brow := Color(0.1, 0.08, 0.08, 0.85)
	for s in [-1.0, 1.0]:
		var b: Vector2 = c + Vector2(s * r * spread, r * y - er * 1.75)
		match mood:
			"worried":
				canvas.draw_line(b + Vector2(-s * er * 0.9, -er * 0.05), b + Vector2(s * er * 0.6, er * 0.5), brow, _w(r, 0.06))
			"hurt", "out":
				canvas.draw_line(b + Vector2(-s * er * 0.9, er * 0.5), b + Vector2(s * er * 0.7, -er * 0.1), brow, _w(r, 0.06))
			"excited":
				canvas.draw_arc(b + Vector2(0, er * 0.5), er * 0.8, PI * 1.2, PI * 1.8, 8, brow, _w(r, 0.055))


## Mouth for every mood, centred at m (width w).
static func _mouth(canvas: CanvasItem, m: Vector2, w: float, r: float, mood: String, ink := Color(0.15, 0.08, 0.06)) -> void:
	match mood:
		"happy", "excited":
			var pts := PackedVector2Array([m + Vector2(-w, 0)])
			for i in 9:
				var a := PI * i / 8.0
				pts.append(m + Vector2(-cos(a) * w, sin(a) * w * 0.9))
			canvas.draw_colored_polygon(pts, Color(0.45, 0.1, 0.12))
			canvas.draw_colored_polygon(_ellipse(m + Vector2(0, w * 0.55), w * 0.5, w * 0.28), Color(1.0, 0.45, 0.5))
		"worried":
			canvas.draw_arc(m + Vector2(0, w * 0.7), w * 0.7, PI * 1.2, PI * 1.8, 8, ink, _w(r, 0.05))
		"hurt":
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(m + Vector2(-w + w * 2.0 * i / 6.0, (w * 0.18) * (1 if i % 2 == 0 else -1)))
			canvas.draw_polyline(pts, ink, _w(r, 0.05))
		"out":
			canvas.draw_colored_polygon(_ellipse(m + Vector2(0, w * 0.2), w * 0.32, w * 0.4), Color(0.45, 0.1, 0.12))
		_:
			canvas.draw_arc(m + Vector2(0, -w * 0.35), w * 0.75, PI * 0.2, PI * 0.8, 10, ink, _w(r, 0.05))


static func _cheeks(canvas: CanvasItem, c: Vector2, r: float, spread := 0.58, y := 0.2) -> void:
	for s in [-1.0, 1.0]:
		canvas.draw_colored_polygon(_ellipse(c + Vector2(s * r * spread, r * y), r * 0.15, r * 0.09), Color(1.0, 0.4, 0.45, 0.35))


static func _whiskers(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	for s in [-1.0, 1.0]:
		for dy in [-0.05, 0.08]:
			canvas.draw_line(c + Vector2(s * r * 0.28, r * (0.3 + dy)), c + Vector2(s * r * 0.9, r * (0.2 + dy * 1.9)), color, _w(r, 0.03))


# --- Faces -----------------------------------------------------------------------------------

## Draws an animal face centred on c with head radius r.
static func draw_face(canvas: CanvasItem, c: Vector2, r: float, id: String, mood := "normal", blink := false) -> void:
	var f := fur(id)
	match id:
		"duck":
			# Feather tuft, round head, wide beak that opens with the mood.
			for i in 3:
				canvas.draw_colored_polygon(_ellipse(c + Vector2(r * (0.05 + i * 0.14), -r * 0.98), r * 0.08, r * 0.24, 0.3 + i * 0.25), f.darkened(0.12))
			canvas.draw_circle(c, r, f)
			_shade(canvas, c, r)
			_cheeks(canvas, c, r, 0.62, 0.18)
			_eyes(canvas, c, r, mood, blink, 0.38, -0.16, 1.0, Color(0.15, 0.3, 0.55))
			var open := mood == "happy" or mood == "excited" or mood == "out"
			var bill := Color(1.0, 0.56, 0.14)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.36), r * 0.52, r * 0.19), bill)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * (0.58 if open else 0.48)), r * 0.4, r * (0.15 if open else 0.1)), bill.darkened(0.15))
			if open:
				canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.5), r * 0.32, r * 0.07), Color(0.5, 0.12, 0.1))
			for s in [-1.0, 1.0]:
				canvas.draw_circle(c + Vector2(s * r * 0.14, r * 0.3), r * 0.03, Color(0.55, 0.25, 0.05))
		"mouse":
			for s in [-1.0, 1.0]:
				canvas.draw_circle(c + Vector2(s * r * 0.8, -r * 0.7), r * 0.56, f)
				canvas.draw_circle(c + Vector2(s * r * 0.8, -r * 0.7), r * 0.38, Color(1.0, 0.72, 0.78))
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.05), r * 0.92, r * 0.88), f)
			_shade(canvas, c, r * 0.92)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.38), r * 0.42, r * 0.3), Color(0.92, 0.9, 0.94))
			_cheeks(canvas, c, r, 0.55, 0.22)
			_eyes(canvas, c, r, mood, blink, 0.33, -0.1, 0.95)
			_whiskers(canvas, c, r, Color(0.35, 0.35, 0.4))
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.3), r * 0.13, r * 0.1), Color(1.0, 0.5, 0.62))
			_mouth(canvas, c + Vector2(0, r * 0.47), r * 0.15, r, mood)
			if mood == "normal" or mood == "worried":  # buck teeth
				canvas.draw_rect(Rect2(c + Vector2(-r * 0.07, r * 0.46), Vector2(r * 0.14, r * 0.1)), Color(1, 1, 1))
		"dog":
			var brown := Color(0.5, 0.3, 0.18)
			canvas.draw_circle(c, r, f)
			_shade(canvas, c, r)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(-r * 0.36, -r * 0.12), r * 0.26, r * 0.24), brown.lightened(0.15))  # eye patch
			for s in [-1.0, 1.0]:
				var flop := 0.25 if mood == "excited" or mood == "happy" else 0.0
				canvas.draw_colored_polygon(_ellipse(c + Vector2(s * r * 0.9, r * (0.08 - flop)), r * 0.28, r * 0.62, s * (-0.3 - flop)), brown)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.42), r * 0.5, r * 0.36), Color(0.98, 0.9, 0.78))
			_eyes(canvas, c, r, mood, blink, 0.36, -0.14)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.26), r * 0.18, r * 0.12), Color(0.12, 0.1, 0.1))
			canvas.draw_circle(c + Vector2(-r * 0.05, r * 0.22), r * 0.04, Color(1, 1, 1, 0.6))
			_mouth(canvas, c + Vector2(0, r * 0.48), r * 0.2, r, mood)
			if mood == "happy":  # tongue out
				canvas.draw_colored_polygon(_ellipse(c + Vector2(r * 0.05, r * 0.7), r * 0.11, r * 0.16), Color(1.0, 0.45, 0.5))
		"cat":
			for s in [-1.0, 1.0]:
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(s * r * 0.22, -r * 0.75),
					c + Vector2(s * r * 0.95, -r * 1.12), c + Vector2(s * r * 0.92, -r * 0.28)]), f)
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(s * r * 0.42, -r * 0.68),
					c + Vector2(s * r * 0.86, -r * 0.92), c + Vector2(s * r * 0.84, -r * 0.45)]), Color(1.0, 0.75, 0.8))
			canvas.draw_circle(c, r * 0.96, f)
			_shade(canvas, c, r * 0.96)
			for dx in [-0.2, 0.0, 0.2]:  # forehead stripes
				canvas.draw_line(c + Vector2(r * dx, -r * 0.92), c + Vector2(r * dx * 0.7, -r * 0.6), f.darkened(0.3), _w(r, 0.07))
			for s in [-1.0, 1.0]:
				canvas.draw_line(c + Vector2(s * r * 0.95, r * 0.0), c + Vector2(s * r * 0.72, r * 0.05), f.darkened(0.3), _w(r, 0.06))
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.4), r * 0.4, r * 0.28), Color(1.0, 0.92, 0.85))
			_eyes(canvas, c, r, mood, blink, 0.36, -0.08, 1.05, Color(0.3, 0.6, 0.2))
			_whiskers(canvas, c, r, Color(0.3, 0.2, 0.15))
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.11, r * 0.22),
				c + Vector2(r * 0.11, r * 0.22), c + Vector2(0, r * 0.34)]), Color(1.0, 0.48, 0.6))
			_mouth(canvas, c + Vector2(0, r * 0.46), r * 0.16, r, mood)
		"bear":
			for s in [-1.0, 1.0]:
				canvas.draw_circle(c + Vector2(s * r * 0.72, -r * 0.72), r * 0.33, f)
				canvas.draw_circle(c + Vector2(s * r * 0.72, -r * 0.72), r * 0.18, f.lightened(0.35))
			canvas.draw_circle(c, r, f)
			_shade(canvas, c, r)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.38), r * 0.44, r * 0.34), Color(0.86, 0.72, 0.54))
			_cheeks(canvas, c, r, 0.6, 0.15)
			_eyes(canvas, c, r, mood, blink, 0.36, -0.2, 0.9)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.24), r * 0.17, r * 0.12), Color(0.14, 0.09, 0.07))
			canvas.draw_circle(c + Vector2(-r * 0.05, r * 0.2), r * 0.04, Color(1, 1, 1, 0.5))
			_mouth(canvas, c + Vector2(0, r * 0.48), r * 0.17, r, mood)
		"raccoon":
			for s in [-1.0, 1.0]:
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(s * r * 0.3, -r * 0.8),
					c + Vector2(s * r * 0.86, -r * 1.06), c + Vector2(s * r * 0.92, -r * 0.35)]), f.darkened(0.25))
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(s * r * 0.45, -r * 0.74),
					c + Vector2(s * r * 0.8, -r * 0.9), c + Vector2(s * r * 0.82, -r * 0.5)]), Color(0.92, 0.92, 0.92))
			canvas.draw_circle(c, r, f)
			_shade(canvas, c, r)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, -r * 0.55), r * 0.12, r * 0.3), f.darkened(0.3))  # forehead stripe
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.42), r * 0.52, r * 0.36), Color(0.95, 0.95, 0.95))
			for s in [-1.0, 1.0]:  # the bandit mask
				canvas.draw_colored_polygon(_ellipse(c + Vector2(s * r * 0.4, -r * 0.06), r * 0.38, r * 0.24, s * 0.25), Color(0.15, 0.15, 0.17))
			_eyes(canvas, c, r, mood, blink, 0.4, -0.06, 0.95, Color(0.35, 0.22, 0.1), true)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.28), r * 0.14, r * 0.1), Color(0.1, 0.1, 0.1))
			_mouth(canvas, c + Vector2(0, r * 0.5), r * 0.17, r, mood)
		"monkey":
			var face := Color(0.96, 0.81, 0.63)
			for s in [-1.0, 1.0]:
				canvas.draw_circle(c + Vector2(s * r * 0.98, r * 0.02), r * 0.33, f)
				canvas.draw_circle(c + Vector2(s * r * 0.98, r * 0.02), r * 0.19, face)
			canvas.draw_circle(c, r, f)
			_shade(canvas, c, r)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, -r * 0.9), r * 0.18, r * 0.12, 0.4), f.darkened(0.2))  # hair tuft
			canvas.draw_circle(c + Vector2(-r * 0.3, -r * 0.12), r * 0.37, face)
			canvas.draw_circle(c + Vector2(r * 0.3, -r * 0.12), r * 0.37, face)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.36), r * 0.6, r * 0.44), face)
			_cheeks(canvas, c, r, 0.48, 0.25)
			_eyes(canvas, c, r, mood, blink, 0.3, -0.12, 0.95)
			for s in [-1.0, 1.0]:
				canvas.draw_circle(c + Vector2(s * r * 0.08, r * 0.24), r * 0.045, Color(0.35, 0.2, 0.1))
			_mouth(canvas, c + Vector2(0, r * 0.48), r * 0.26, r, mood, Color(0.35, 0.2, 0.1))
		_:
			canvas.draw_circle(c, r, f)
			_eyes(canvas, c, r, mood, blink)

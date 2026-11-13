extends Control
## Animal pilots: duck, mouse, dog, cat, bear, raccoon, monkey. Drawn with simple shapes.
## As a Control it's an avatar (menus, hangar, lobby); draw_face() is also used by the rocket
## to put your pilot in its porthole window.

var animal: String = "duck":
	set(value):
		animal = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.36
	draw_face(self, size / 2.0 + Vector2(0, r * 0.08), r, animal)


static func _ellipse(c: Vector2, rx: float, ry: float, rot := 0.0, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


static func _eyes(canvas: CanvasItem, c: Vector2, r: float, spread := 0.36, y := -0.08, white := false) -> void:
	for s in [-1.0, 1.0]:
		var e := c + Vector2(s * r * spread, r * y)
		if white:
			canvas.draw_circle(e, r * 0.17, Color(1, 1, 1))
		canvas.draw_circle(e, r * 0.11, Color(0.08, 0.08, 0.1))
		canvas.draw_circle(e + Vector2(-r * 0.03, -r * 0.04), r * 0.04, Color(1, 1, 1))


static func _whiskers(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var w := maxf(r * 0.04, 1.0)
	for s in [-1.0, 1.0]:
		for dy in [-0.05, 0.08]:
			canvas.draw_line(c + Vector2(s * r * 0.25, r * (0.3 + dy)), c + Vector2(s * r * 0.85, r * (0.22 + dy * 1.8)), color, w)


## Draws an animal face centred on c with head radius r.
static func draw_face(canvas: CanvasItem, c: Vector2, r: float, id: String) -> void:
	match id:
		"duck":
			var yellow := Color(1.0, 0.85, 0.25)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(r * 0.1, -r * 0.95), r * 0.12, r * 0.28, 0.4), yellow.darkened(0.1))
			canvas.draw_circle(c, r, yellow)
			_eyes(canvas, c, r, 0.38, -0.15)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.38), r * 0.5, r * 0.2), Color(1.0, 0.55, 0.15))
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.48), r * 0.38, r * 0.12), Color(0.9, 0.42, 0.1))
		"mouse":
			var grey := Color(0.68, 0.68, 0.74)
			for s in [-1.0, 1.0]:
				canvas.draw_circle(c + Vector2(s * r * 0.8, -r * 0.72), r * 0.55, grey)
				canvas.draw_circle(c + Vector2(s * r * 0.8, -r * 0.72), r * 0.36, Color(1.0, 0.72, 0.78))
			canvas.draw_circle(c, r * 0.92, grey)
			_eyes(canvas, c, r, 0.34, -0.1)
			_whiskers(canvas, c, r, Color(0.35, 0.35, 0.4))
			canvas.draw_circle(c + Vector2(0, r * 0.32), r * 0.14, Color(1.0, 0.5, 0.6))
		"dog":
			var tan := Color(0.85, 0.66, 0.42)
			var brown := Color(0.5, 0.3, 0.18)
			canvas.draw_circle(c, r, tan)
			for s in [-1.0, 1.0]:
				canvas.draw_colored_polygon(_ellipse(c + Vector2(s * r * 0.88, r * 0.05), r * 0.28, r * 0.6, s * -0.3), brown)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.4), r * 0.48, r * 0.36), Color(0.98, 0.9, 0.78))
			_eyes(canvas, c, r, 0.36, -0.15)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.25), r * 0.17, r * 0.12), Color(0.12, 0.1, 0.1))
			canvas.draw_line(c + Vector2(0, r * 0.35), c + Vector2(0, r * 0.52), Color(0.12, 0.1, 0.1), maxf(r * 0.05, 1.0))
		"cat":
			var orange := Color(1.0, 0.6, 0.25)
			for s in [-1.0, 1.0]:
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(s * r * 0.25, -r * 0.75),
					c + Vector2(s * r * 0.95, -r * 1.1), c + Vector2(s * r * 0.9, -r * 0.3)]), orange)
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(s * r * 0.42, -r * 0.68),
					c + Vector2(s * r * 0.85, -r * 0.92), c + Vector2(s * r * 0.82, -r * 0.45)]), Color(1.0, 0.75, 0.8))
			canvas.draw_circle(c, r * 0.95, orange)
			for s in [-1.0, 1.0]:  # stripes
				canvas.draw_line(c + Vector2(s * r * 0.15, -r * 0.9), c + Vector2(s * r * 0.1, -r * 0.55), orange.darkened(0.3), maxf(r * 0.08, 1.0))
			_eyes(canvas, c, r, 0.36, -0.08)
			_whiskers(canvas, c, r, Color(0.3, 0.2, 0.15))
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.12, r * 0.22),
				c + Vector2(r * 0.12, r * 0.22), c + Vector2(0, r * 0.36)]), Color(1.0, 0.5, 0.6))
		"bear":
			var brown := Color(0.55, 0.36, 0.22)
			for s in [-1.0, 1.0]:
				canvas.draw_circle(c + Vector2(s * r * 0.72, -r * 0.72), r * 0.32, brown)
				canvas.draw_circle(c + Vector2(s * r * 0.72, -r * 0.72), r * 0.17, brown.lightened(0.35))
			canvas.draw_circle(c, r, brown)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.35), r * 0.42, r * 0.33), Color(0.85, 0.7, 0.52))
			_eyes(canvas, c, r, 0.36, -0.18)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.22), r * 0.16, r * 0.11), Color(0.12, 0.08, 0.06))
		"raccoon":
			var grey := Color(0.58, 0.58, 0.62)
			for s in [-1.0, 1.0]:
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(s * r * 0.3, -r * 0.8),
					c + Vector2(s * r * 0.85, -r * 1.05), c + Vector2(s * r * 0.92, -r * 0.35)]), grey.darkened(0.25))
			canvas.draw_circle(c, r, grey)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.4), r * 0.5, r * 0.36), Color(0.95, 0.95, 0.95))
			for s in [-1.0, 1.0]:  # the bandit mask
				canvas.draw_colored_polygon(_ellipse(c + Vector2(s * r * 0.4, -r * 0.08), r * 0.36, r * 0.22, s * 0.25), Color(0.15, 0.15, 0.17))
			_eyes(canvas, c, r, 0.4, -0.08, true)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.28), r * 0.13, r * 0.09), Color(0.1, 0.1, 0.1))
		"monkey":
			var brown := Color(0.5, 0.32, 0.2)
			var face := Color(0.95, 0.8, 0.62)
			for s in [-1.0, 1.0]:
				canvas.draw_circle(c + Vector2(s * r * 0.98, 0), r * 0.32, brown)
				canvas.draw_circle(c + Vector2(s * r * 0.98, 0), r * 0.18, face)
			canvas.draw_circle(c, r, brown)
			canvas.draw_circle(c + Vector2(-r * 0.3, -r * 0.12), r * 0.36, face)
			canvas.draw_circle(c + Vector2(r * 0.3, -r * 0.12), r * 0.36, face)
			canvas.draw_colored_polygon(_ellipse(c + Vector2(0, r * 0.35), r * 0.58, r * 0.42), face)
			_eyes(canvas, c, r, 0.3, -0.12)
			for s in [-1.0, 1.0]:
				canvas.draw_circle(c + Vector2(s * r * 0.08, r * 0.25), r * 0.05, Color(0.3, 0.18, 0.1))
			canvas.draw_arc(c + Vector2(0, r * 0.32), r * 0.22, 0.3, PI - 0.3, 10, Color(0.3, 0.18, 0.1), maxf(r * 0.06, 1.0))
		_:
			canvas.draw_circle(c, r, Color(0.8, 0.8, 0.85))

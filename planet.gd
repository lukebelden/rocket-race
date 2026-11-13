extends Node2D
## The planet you're flying past. Drawn once when the level changes; game.gd just moves it
## each frame (moving a node is nearly free, redrawing all these shapes every frame is not).

## Shared textures, made once by game.gd.
static var glow_tex: Texture2D
static var shade_tex: Texture2D

var data: Dictionary = {}:
	set(value):
		data = value
		queue_redraw()


func _draw() -> void:
	if data.is_empty():
		return
	var r: float = data["radius"]
	var color: Color = data["color"]
	var style: String = data["style"]

	# Soft glow around the gas and ice giants (thin atmosphere halo).
	if style != "craters" and style != "polar":
		draw_texture_rect(glow_tex, Rect2(-Vector2(r, r) * 1.3, Vector2(r, r) * 2.6), false, Color(color.lightened(0.2), 0.3))

	if style == "rings":
		_draw_ring(r, color, true)

	var body := circle_points(Vector2.ZERO, r, 96)
	draw_colored_polygon(body, color)

	# Surface features are semi-transparent so the shading shows through.
	match style:
		"craters":
			for crater in [Vector3(-0.35, -0.2, 0.18), Vector3(0.3, 0.25, 0.14), Vector3(0.1, -0.45, 0.1),
					Vector3(-0.1, 0.45, 0.12), Vector3(0.45, -0.2, 0.08), Vector3(-0.55, 0.25, 0.07), Vector3(0.6, 0.35, 0.06)]:
				var pos := Vector2(crater.x, crater.y) * r
				draw_circle(pos + Vector2(-1, -1) * crater.z * r * 0.15, crater.z * r * 1.05, Color(1, 1, 1, 0.12))  # rim light
				draw_circle(pos, crater.z * r, Color(color.darkened(0.35), 0.55))
		"polar":
			draw_colored_polygon(_band_points(r, -r * 0.97, -r * 0.72), Color(0.97, 0.95, 0.95, 0.9))
			draw_colored_polygon(_band_points(r, r * 0.8, r * 0.95), Color(0.97, 0.95, 0.95, 0.6))
			for patch in [Vector3(-0.3, -0.1, 0.2), Vector3(0.25, 0.2, 0.16), Vector3(0.0, 0.45, 0.12)]:
				draw_circle(Vector2(patch.x, patch.y) * r, patch.z * r, Color(color.darkened(0.3), 0.4))
		"bands", "rings":
			for band in [[-0.6, -0.48], [-0.32, -0.18], [-0.05, 0.08], [0.22, 0.36], [0.5, 0.62]]:
				draw_colored_polygon(_band_points(r, r * band[0], r * band[1]), Color(color.darkened(0.3), 0.45))
			for band in [[-0.45, -0.38], [0.1, 0.18], [0.4, 0.46]]:
				draw_colored_polygon(_band_points(r, r * band[0], r * band[1]), Color(color.lightened(0.25), 0.3))

	if data.has("spot"):
		# Jupiter's Great Red Spot / Neptune's Great Dark Spot.
		var spot: Color = data["spot"]
		var at := Vector2(r * 0.25, r * 0.3)
		draw_colored_polygon(_ellipse_points(at, r * 0.24, r * 0.13), Color(spot.lightened(0.2), 0.5))
		draw_colored_polygon(_ellipse_points(at, r * 0.18, r * 0.09), spot)

	# Smooth sphere shading on top of everything: lit from the top-left, dark on the far side.
	draw_colored_polygon(body, Color.WHITE, _circle_uvs(96), shade_tex)

	if style == "rings":
		_draw_ring(r, color, false)


## Saturn's rings: two bands with a gap, drawn in halves so the planet sits "inside" them.
func _draw_ring(r: float, color: Color, back_half: bool) -> void:
	var start := PI if back_half else 0.0
	for ring in [[1.95, 0.12, color.lightened(0.2)], [1.62, 0.16, color.darkened(0.1)]]:
		var points := PackedVector2Array()
		var ring_scale: float = ring[0]
		for i in 41:
			var a := start + PI * i / 40.0
			points.append(Vector2(cos(a) * r * ring_scale, sin(a) * r * ring_scale * 0.22).rotated(-0.25))
		var ring_color: Color = ring[2]
		if back_half:
			ring_color = ring_color.darkened(0.25)  # far side of the ring is in shadow
		draw_polyline(points, ring_color, r * ring[1], true)


## Smooth circle outline (draw_circle looks faceted on huge circles).
static func circle_points(c: Vector2, r: float, segments: int = 256) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(segments)
	for i in segments:
		points[i] = c + Vector2.from_angle(TAU * i / segments) * r
	return points


## Texture coordinates matching circle_points(), so a texture can be drawn clipped to a circle.
func _circle_uvs(segments: int) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for i in segments:
		uvs.append(Vector2(0.5, 0.5) + Vector2.from_angle(TAU * i / segments) * 0.5)
	return uvs


func _ellipse_points(c: Vector2, rx: float, ry: float, segments: int = 32) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		points.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return points


## Polygon for a horizontal stripe of a circle between heights y1 and y2 (relative to centre).
func _band_points(r: float, y1: float, y2: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 10
	for i in steps + 1:
		var y := lerpf(y1, y2, float(i) / steps)
		points.append(Vector2(-sqrt(maxf(r * r - y * y, 1.0)), y))
	for i in steps + 1:
		var y := lerpf(y2, y1, float(i) / steps)
		points.append(Vector2(sqrt(maxf(r * r - y * y, 1.0)), y))
	return points

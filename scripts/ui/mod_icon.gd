extends Control
## Icon for a ship modification (or an empty slot), drawn with simple shapes.
## Used in the SHIP MODS panel and on the station's mod cards.

const ModInfo := preload("res://scripts/game/mods.gd")

var mod_id: String = "":
	set(value):
		mod_id = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var u := s / 32.0  # drawing unit: icons are designed on a 32x32 grid

	if mod_id == "":
		# Empty slot: dashed rounded outline with a faint plus.
		draw_rect(Rect2(c - Vector2(s, s) / 2.0 + Vector2(u, u), Vector2(s, s) - Vector2(u, u) * 2.0), Color(1, 1, 1, 0.18), false, 1.5)
		draw_line(c + Vector2(-6, 0) * u, c + Vector2(6, 0) * u, Color(1, 1, 1, 0.25), 2.0)
		draw_line(c + Vector2(0, -6) * u, c + Vector2(0, 6) * u, Color(1, 1, 1, 0.25), 2.0)
		return

	var color: Color = ModInfo.MODS[mod_id]["color"]
	# Tile background.
	draw_rect(Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), color.darkened(0.65))
	draw_rect(Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), color, false, 2.0)
	var white := Color(0.95, 0.97, 1.0)

	match mod_id:
		"thruster":
			draw_colored_polygon(_pts(c, u, [[-5, -10], [5, -10], [8, 2], [-8, 2]]), white)
			draw_colored_polygon(_pts(c, u, [[-7, 2], [7, 2], [0, 13]]), Color(1, 0.6, 0.15))
			draw_colored_polygon(_pts(c, u, [[-3.5, 2], [3.5, 2], [0, 8]]), Color(1, 0.95, 0.5))
		"rcs":
			draw_rect(Rect2(c + Vector2(-3, -9) * u, Vector2(6, 18) * u), white)
			draw_colored_polygon(_pts(c, u, [[-6, -4], [-13, 0], [-6, 4]]), color.lightened(0.3))
			draw_colored_polygon(_pts(c, u, [[6, -4], [13, 0], [6, 4]]), color.lightened(0.3))
		"radar":
			for i in 3:
				draw_arc(c + Vector2(0, 8) * u, (6 + i * 5) * u, -PI * 0.85, -PI * 0.15, 12, white, 1.8, true)
			draw_circle(c + Vector2(0, 8) * u, 2.2 * u, Color(1, 0.35, 0.3))
			draw_circle(c + Vector2(6, -4) * u, 1.8 * u, Color(1, 0.35, 0.3))
		"hull":
			draw_colored_polygon(_pts(c, u, [[0, -12], [10, -8], [9, 4], [0, 12], [-9, 4], [-10, -8]]), white)
			draw_colored_polygon(_pts(c, u, [[0, -8], [6, -5.5], [5.5, 3], [0, 8], [-5.5, 3], [-6, -5.5]]), color.darkened(0.2))
		"healing":
			draw_rect(Rect2(c + Vector2(-3, -10) * u, Vector2(6, 20) * u), white)
			draw_rect(Rect2(c + Vector2(-10, -3) * u, Vector2(20, 6) * u), white)
		"missile":
			draw_set_transform(c, -PI / 4.0)
			draw_rect(Rect2(Vector2(-2.5, -8) * u, Vector2(5, 15) * u), white)
			draw_colored_polygon(_pts(Vector2.ZERO, u, [[-2.5, -8], [2.5, -8], [0, -13]]), Color(1, 0.35, 0.3))
			draw_colored_polygon(_pts(Vector2.ZERO, u, [[-2.5, 3], [-6, 8], [-2.5, 7]]), color.lightened(0.2))
			draw_colored_polygon(_pts(Vector2.ZERO, u, [[2.5, 3], [6, 8], [2.5, 7]]), color.lightened(0.2))
			draw_colored_polygon(_pts(Vector2.ZERO, u, [[-2, 7], [2, 7], [0, 12]]), Color(1, 0.65, 0.2))
			draw_set_transform(Vector2.ZERO)


func _pts(c: Vector2, u: float, coords: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in coords:
		points.append(c + Vector2(p[0], p[1]) * u)
	return points

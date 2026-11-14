extends Node2D
## Multiplayer: the other racers' rockets, drawn as see-through "ghosts" of the ship they
## picked (ship type, paint and fitted mods), with their name tag in their racer colour.
## Everyone flies the same course, so a rival's height on screen shows how far ahead of or
## behind you they are. Rivals too far away become markers at the top/bottom edge.
## They're only visual: you can't bump into each other.

## Screen pixels per unit of distance flown (1 unit = one second of normal-speed flight).
const PIXELS_PER_UNIT := 160.0
## Metres per distance unit, matching the nav beacon's scale (game.gd METERS_PER_PIXEL x fall speed).
const METERS_PER_UNIT := 1320.0

const Rocket := preload("res://scripts/game/rocket.gd")
## How see-through the ghost ships are.
const GHOST_ALPHA := 0.5

## id -> {name, color, x (0..1), d, hull, boost, status, shown_x, shown_d, ship: Rocket, scale}
var rivals: Dictionary = {}
## Set by game.gd every frame.
var my_distance: float = 0.0
var rocket_y: float = 0.0
var rocket_x: float = 0.0
var top_limit: float = 70.0
var bottom_limit: float = 600.0

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func add_rival(id: int, rival_name: String, color: Color, ship := "small", paint: Dictionary = {},
		mods: Array = [], ship_scale := 1.0) -> void:
	remove_rival(id)  # a ghost left over from an earlier race
	# Their rocket as a display model (it doesn't fly itself: we move it every frame).
	var r := Rocket.new()
	r.ship = ship
	r.paint_main = Color.html(str(paint.get("main", "#e5683b")))
	r.paint_dark = Color.html(str(paint.get("dark", "#a8432a")))
	r.paint_body = Color.html(str(paint.get("body", "#e6efe9")))
	for m in mods:
		r.mods.append(str(m))
	r.missile_count = 2
	r.active = false
	r.flame_on = true
	r.monitoring = false
	r.monitorable = false
	r.scale = Vector2.ONE * ship_scale
	r.modulate = Color(1, 1, 1, GHOST_ALPHA)
	r.visible = false
	add_child(r)
	r.set_process(false)
	r.set_process_unhandled_input(false)
	rivals[id] = {"name": rival_name, "color": color, "x": 0.5, "d": 0.0, "hull": 1.0,
		"boost": false, "status": "racing", "shown_x": 0.5, "shown_d": 0.0, "ship": r, "scale": ship_scale}


func update_rival(id: int, data: Dictionary) -> void:
	if not rivals.has(id):
		return
	var r: Dictionary = rivals[id]
	r["x"] = float(data.get("x", r["x"]))
	r["d"] = float(data.get("d", r["d"]))
	r["hull"] = float(data.get("h", r["hull"]))
	r["boost"] = bool(data.get("b", false))


func set_status(id: int, status: String, distance: float) -> void:
	if rivals.has(id):
		rivals[id]["status"] = status
		rivals[id]["d"] = distance


## New race: drop every ghost from the last one.
func clear() -> void:
	for id in rivals.keys():
		remove_rival(id)


func remove_rival(id: int) -> void:
	if rivals.has(id) and is_instance_valid(rivals[id]["ship"]):
		rivals[id]["ship"].queue_free()
	rivals.erase(id)


## Your position in the race right now (1 = leading): finished rivals and anyone further along.
func my_place(i_finished: bool) -> int:
	var place := 1
	for r in rivals.values():
		if r["status"] == "finished" and not i_finished:
			place += 1
		elif r["status"] != "finished" and not i_finished and float(r["d"]) > my_distance:
			place += 1
	return place


func _process(delta: float) -> void:
	# Updates arrive ~10 times a second: glide between them so ghosts move smoothly.
	var k := clampf(delta * 12.0, 0.0, 1.0)
	for r in rivals.values():
		r["shown_x"] = lerpf(r["shown_x"], r["x"], k)
		r["shown_d"] = lerpf(r["shown_d"], r["d"], k)
		# Keep the ghost ship's engine animating (it isn't processing on its own).
		var ship: Rocket = r["ship"]
		ship._anim += delta * 10.0
		ship._flicker = randf_range(0.75, 1.2)
		ship.boosting = r["boost"]
		ship.queue_redraw()
	queue_redraw()


func _draw() -> void:
	var width := get_viewport_rect().size.x
	for r in rivals.values():
		var color: Color = r["color"]
		var x := clampf(float(r["shown_x"]) * width, 44.0, width - 44.0)
		var ahead := float(r["shown_d"]) - my_distance
		var y := rocket_y - ahead * PIXELS_PER_UNIT
		var out: bool = r["status"] == "crashed"
		var done: bool = r["status"] == "finished"
		var tag: String = r["name"] + ("  · OUT" if out else ("  · FINISHED" if done else ""))
		var ship: Rocket = r["ship"]
		ship.visible = false
		if y < top_limit or done:
			_draw_edge_marker(Vector2(x, top_limit + 14.0), true, color, tag, ahead)
		elif y > bottom_limit:
			# Behind you: marker along the bottom, nudged aside so it never covers your own rocket.
			var mx := x
			if absf(mx - rocket_x) < 110.0:
				mx = rocket_x + (110.0 if mx >= rocket_x else -110.0)
				if mx > width - 60.0 or mx < 60.0:
					mx = rocket_x - (mx - rocket_x)
			_draw_edge_marker(Vector2(mx, bottom_limit - 14.0), false, color, tag, ahead)
		elif not out:
			ship.visible = true
			ship.position = Vector2(x, y)
			_draw_tag(Vector2(x, y - 66.0 * float(r["scale"])), tag, color)  # above the nose, clear of the flame


func _draw_tag(at: Vector2, text: String, color: Color) -> void:
	var size := 15
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_rect(Rect2(at + Vector2(-w / 2.0 - 6.0, -14.0), Vector2(w + 12.0, 20.0)), Color(0, 0, 0, 0.45))
	draw_string(_font, at + Vector2(-w / 2.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color.lightened(0.3))


## Rival out of view: arrow at the edge with their name and how far ahead/behind they are.
func _draw_edge_marker(at: Vector2, up: bool, color: Color, text: String, ahead: float) -> void:
	var dir := -1.0 if up else 1.0
	draw_colored_polygon(PackedVector2Array([at + Vector2(-10, 0), at + Vector2(10, 0),
		at + Vector2(0, 12.0 * dir)]), color)
	var meters := absf(ahead) * METERS_PER_UNIT
	var dist := ("%.1f km" % (meters / 1000.0)) if meters >= 1000.0 else ("%d m" % int(meters))
	var label := "%s  %s%s" % [text, "+" if ahead >= 0.0 else "-", dist]
	_draw_tag(at + Vector2(0, -18.0 * dir + (6.0 if up else 0.0)), label, color)

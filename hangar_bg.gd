extends Control
## The hangar the menus sit in: back wall, a big bay window onto space (with Earth below),
## ceiling lamps, a gantry with blinking beacons, and your rocket on its launch platform -
## big, with the ship, paint and fitted mods from the hangar of the mode you're in.
## Landscape: rocket on the left, menu on the right. Portrait: rocket on top, menu below.

const Rocket := preload("res://rocket.gd")

var rocket: Area2D
## The bay window's view (space + Earth), clipped to the window.
var _view: Control
var _front: Control
var _t := 0.0
var _ship_size := 1.0
var _stars: Array[Vector3] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 70:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.5, 1.6)))
	_view = Control.new()
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	_front = Control.new()
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.draw.connect(_draw_front)
	add_child(_front)
	rocket = Rocket.new()
	rocket.active = false
	rocket.flame_on = false
	rocket.monitoring = false
	rocket.monitorable = false
	rocket.missile_count = 5
	add_child(rocket)
	rocket.set_process(false)  # a display model: it doesn't fly
	rocket.set_process_unhandled_input(false)
	resized.connect(_layout)
	show_loadout("sp")


## Show the rocket from one mode's hangar ("sp" or "mp").
func show_loadout(track: String) -> void:
	if rocket == null:
		return
	var d := Profile.design(track)
	rocket.paint_main = Color.html(str(d.get("main", "#db3333")))
	rocket.paint_dark = Color.html(str(d.get("dark", "#991a1f")))
	rocket.paint_body = Color.html(str(d.get("body", "#f2f5fa")))
	rocket.mods.assign(Profile.loadout(track)["mods"])
	_ship_size = float(Profile.ship(track).get("size", 1.0))
	_layout()


func _portrait() -> bool:
	return size.y > size.x


## Where the rocket stands: x, the floor line, and its scale.
func _spot() -> Dictionary:
	if _portrait():
		return {"x": size.x * 0.5, "floor": size.y * 0.37, "scale": size.y / 1152.0 * 2.6 * _ship_size}
	return {"x": size.x * 0.27, "floor": size.y * 0.82, "scale": size.y / 648.0 * 3.6 * _ship_size}


func _layout() -> void:
	if rocket == null:
		return
	var spot := _spot()
	rocket.scale = Vector2.ONE * float(spot["scale"])
	rocket.position = Vector2(spot["x"], float(spot["floor"]) - 16.0 - 27.0 * float(spot["scale"]))
	rocket.queue_redraw()
	var win := _window_rect()
	_view.position = win.position
	_view.size = win.size
	queue_redraw()


func _window_rect() -> Rect2:
	var spot := _spot()
	var top := size.y * (0.04 if _portrait() else 0.1)
	var win_w := size.x * (0.8 if _portrait() else 0.42)
	return Rect2(float(spot["x"]) - win_w / 2.0, top, win_w, float(spot["floor"]) - top - 6.0)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	_view.queue_redraw()
	_front.queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var spot := _spot()
	var cx: float = spot["x"]
	var floor_y: float = spot["floor"]
	var sc: float = spot["scale"]

	# Back wall: dark steel, lighter towards the middle.
	for i in 10:
		var y0 := h * i / 10.0
		draw_rect(Rect2(0, y0, w, h / 10.0 + 1.0), Color(0.1, 0.12, 0.17).lerp(Color(0.16, 0.18, 0.24), sin(PI * (i + 0.5) / 10.0)))
	for x in range(0, int(w) + 90, 90):  # wall panels
		draw_line(Vector2(x, 0), Vector2(x, floor_y), Color(0, 0, 0, 0.25), 2.0)
		draw_line(Vector2(x + 2, 0), Vector2(x + 2, floor_y), Color(1, 1, 1, 0.03), 1.0)
	for y in [floor_y * 0.35, floor_y * 0.7]:
		draw_line(Vector2(0, y), Vector2(w, y), Color(0, 0, 0, 0.25), 2.0)

	# Bay window frame (the view itself is drawn by _draw_view, clipped to the glass).
	var win := _window_rect()
	draw_rect(win.grow(10.0), Color(0.24, 0.26, 0.32))
	_hazard(Rect2(win.position.x - 10.0, win.end.y, win.size.x + 20.0, 10.0))

	# Ceiling truss and lamps with soft light cones.
	draw_rect(Rect2(0, 0, w, h * 0.05), Color(0.08, 0.09, 0.12))
	var step := w / 4.0
	for i in 4:
		var lx := step * (i + 0.5)
		var top := h * 0.05
		draw_colored_polygon(PackedVector2Array([Vector2(lx - 26, top), Vector2(lx + 26, top),
			Vector2(lx + 150, floor_y), Vector2(lx - 150, floor_y)]), Color(1, 0.95, 0.8, 0.045))
		draw_rect(Rect2(lx - 26, top - 6, 52, 10), Color(0.3, 0.32, 0.36))
		draw_rect(Rect2(lx - 20, top + 2, 40, 4), Color(1, 0.96, 0.82))
	for i in int(w / 40.0) + 1:  # truss zig-zag
		var x := i * 40.0
		draw_line(Vector2(x, 0), Vector2(x + 20, h * 0.05), Color(0.18, 0.2, 0.25), 2.0)
		draw_line(Vector2(x + 20, h * 0.05), Vector2(x + 40, 0), Color(0.18, 0.2, 0.25), 2.0)

	# Floor with perspective lines and hazard stripes at the front.
	draw_rect(Rect2(0, floor_y, w, h - floor_y), Color(0.13, 0.14, 0.18))
	var vp := Vector2(cx, floor_y - h * 0.6)
	for i in 13:
		var x := w * (i - 1) / 10.0
		var from := vp.lerp(Vector2(x, h), (floor_y - vp.y) / (h - vp.y))
		draw_line(from, Vector2(x, h), Color(1, 1, 1, 0.05), 1.5)
	draw_line(Vector2(0, floor_y), Vector2(w, floor_y), Color(0.3, 0.32, 0.38), 3.0)

	_hazard(Rect2(0, h - 14, w, 14))


## Launch platform and gantry, drawn in front of the bay window (a separate layer, because
## the window view is a child control and would otherwise cover them).
func _draw_front() -> void:
	var spot := _spot()
	var cx: float = spot["x"]
	var floor_y: float = spot["floor"]
	var sc: float = spot["scale"]
	# Launch platform with a glowing ring, and its reflection on the floor.
	var pw := 150.0 * sc / 3.6
	_front.draw_colored_polygon(_ellipse(Vector2(cx, floor_y + 10), pw * 1.5, pw * 0.3), Color(0.35, 0.75, 1.0, 0.08 + 0.04 * sin(_t * 2.0)))
	_front.draw_rect(Rect2(cx - pw, floor_y - 16, pw * 2.0, 16), Color(0.32, 0.34, 0.4))
	_front.draw_rect(Rect2(cx - pw, floor_y - 16, pw * 2.0, 3), Color(0.5, 0.52, 0.6))
	_front.draw_rect(Rect2(cx - pw * 0.8, floor_y - 6, pw * 1.6, 3), Color(0.4, 0.85, 1.0, 0.6 + 0.3 * sin(_t * 3.0)))

	# Gantry tower beside the rocket with a service arm and blinking beacons.
	var gx := cx + pw * 1.25
	var gtop := floor_y - 95.0 * sc
	var gc := Color(0.55, 0.3, 0.25)
	_front.draw_rect(Rect2(gx, gtop, 10, floor_y - gtop), gc)
	_front.draw_rect(Rect2(gx + 34, gtop, 10, floor_y - gtop), gc)
	var rungs := int((floor_y - gtop) / 28.0)
	for i in rungs:
		var y := gtop + i * 28.0
		_front.draw_line(Vector2(gx + 10, y), Vector2(gx + 34, y + 28), gc.darkened(0.2), 3.0)
		_front.draw_line(Vector2(gx + 34, y), Vector2(gx + 10, y + 28), gc.darkened(0.2), 3.0)
	_front.draw_rect(Rect2(cx + 12.0 * sc, gtop + 30.0 * sc, gx - cx - 12.0 * sc, 8), gc)  # service arm
	for i in 2:
		var on := fmod(_t + i * 0.5, 1.0) < 0.5
		_front.draw_circle(Vector2(gx + 5 + i * 34, gtop - 6), 5.0, Color(1, 0.25, 0.2) if on else Color(0.35, 0.08, 0.08))
		if on:
			_front.draw_circle(Vector2(gx + 5 + i * 34, gtop - 6), 12.0, Color(1, 0.25, 0.2, 0.2))


func _hazard(r: Rect2) -> void:
	draw_rect(r, Color(0.95, 0.75, 0.15))
	var x := r.position.x - r.size.y
	while x < r.end.x:
		draw_colored_polygon(PackedVector2Array([Vector2(maxf(x, r.position.x), r.position.y),
			Vector2(minf(x + 14, r.end.x), r.position.y), Vector2(clampf(x + 14 - r.size.y, r.position.x, r.end.x), r.end.y),
			Vector2(clampf(x - r.size.y, r.position.x, r.end.x), r.end.y)]), Color(0.12, 0.12, 0.14))
		x += 28.0


func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Through the bay window: stars, and Earth rising at the bottom.
func _draw_view() -> void:
	var sz := _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.08))
	for st in _stars:
		_view.draw_circle(Vector2(st.x * sz.x, st.y * sz.y * 0.8), st.z * 0.9,
			Color(1, 1, 1, 0.3 + 0.5 * absf(sin(_t * st.z * 0.8 + st.x * 20.0))))
	var r := sz.x * 0.9
	var c := Vector2(sz.x * 0.62, sz.y + r * 0.8)
	_view.draw_circle(c, r + 16.0, Color(0.5, 0.75, 1.0, 0.22))
	_view.draw_circle(c, r, Color(0.15, 0.4, 0.82))
	_view.draw_circle(c + Vector2(-r * 0.38, -r * 0.1), r * 0.3, Color(0.24, 0.6, 0.3))
	_view.draw_circle(c + Vector2(r * 0.32, -r * 0.05), r * 0.22, Color(0.3, 0.62, 0.32))
	_view.draw_circle(c + Vector2(r * 0.02, -r * 0.1), r * 0.1, Color(0.85, 0.75, 0.5))
	for i in 5:  # drifting cloud bands
		var x := fmod(i * 0.23 * sz.x + _t * 6.0, sz.x * 1.2) - sz.x * 0.1
		_view.draw_colored_polygon(_ellipse(Vector2(x, sz.y - r * 0.12 + i * 6.0), 50.0 + i * 8.0, 7.0), Color(1, 1, 1, 0.35))
	for i in range(1, 3):  # window struts
		var x := sz.x * i / 3.0
		_view.draw_line(Vector2(x, 0), Vector2(x, sz.y), Color(0.24, 0.26, 0.32), 6.0)
	_view.draw_line(Vector2(0, sz.y * 0.02), Vector2(sz.x, sz.y * 0.4), Color(1, 1, 1, 0.04), 30.0)  # glass glare

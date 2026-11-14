extends Control
## The launch lab the menus sit in (minimal flat-vector sci-fi, see palette.gd):
## a bright haze shaft with a big round light behind the rocket, misty far tanks and pipes,
## dark catwalks with warm capsule lamps, near pipes in silhouette, and your rocket on its
## lit launch platform - with the ship, paint and mods from the hangar of the mode you're in.
## Landscape: rocket on the left, menu on the right (in the Hangar screen: in its middle
## column, see set_focus_x). Portrait: rocket on top, menu below.

const Rocket := preload("res://scripts/game/rocket.gd")
const Palette := preload("res://scripts/game/palette.gd")
const Cosmetics := preload("res://scripts/game/cosmetics.gd")
## Hangar workers wandering the deck (art: sprites/licensed/workers, see cosmetics.gd).
const WORKERS := 3
const WORKER_SPEED := 38.0  # px per second at the 648 px reference height

var rocket: Area2D
var _t := 0.0
var _ship_size := 1.0
var _motes: Array[Vector3] = []
## Hangar screen: stand the rocket here (x in this control) instead of the usual spot. -1 = off.
var _focus_x := -1.0
## Decorations from the Hangar (catalog "decor" ids, in slot order).
var _decor: Array = []
## Decor and workers draw on this layer, in front of the rocket, sorted by depth.
var _front: Node2D
## Each worker: {sheet: which of the 16, pos (0-1 of the deck area), target, wait, dir, walk}.
var _workers: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 26:
		_motes.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.6, 1.6)))
	rocket = Rocket.new()
	rocket.active = false
	rocket.flame_on = false
	rocket.monitoring = false
	rocket.monitorable = false
	rocket.missile_count = 5
	add_child(rocket)
	rocket.set_process(false)  # a display model: it doesn't fly
	rocket.set_process_unhandled_input(false)
	_front = Node2D.new()
	_front.draw.connect(_draw_front)
	add_child(_front)  # after the rocket: drawn over it
	_rng.randomize()
	var picks: Array = range(Cosmetics.WORKER_COUNT)
	picks.shuffle()
	for i in WORKERS:
		_workers.append({"sheet": picks[i], "pos": Vector2(_rng.randf(), _rng.randf()),
			"target": Vector2(_rng.randf(), _rng.randf()), "wait": _rng.randf_range(0.0, 2.0),
			"dir": 0, "walk": 0.0})
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
	rocket.finish = str(Profile.loadout(track).get("finish", "none"))
	rocket.mods.assign(Profile.loadout(track)["mods"])
	_ship_size = float(Profile.ship(track).get("size", 1.0))
	rocket.ship = str(Profile.loadout(track)["ship"])
	_decor = (Profile.loadout(track).get("decor", []) as Array).duplicate()
	_layout()


## The full-screen Hangar puts the rocket in its middle column; -1 returns it to the menu spot.
func set_focus_x(x: float) -> void:
	if is_equal_approx(x, _focus_x):
		return
	_focus_x = x
	_layout()


func _portrait() -> bool:
	return size.y > size.x


## Where the rocket stands: x, the floor line, and its scale.
func _spot() -> Dictionary:
	if _portrait():
		return {"x": size.x * 0.5, "floor": size.y * 0.37, "scale": size.y / 1152.0 * 2.6 * _ship_size}
	# In the Hangar screen the rocket stands a bit smaller, so its decorations fit in the
	# middle column beside it.
	return {"x": _focus_x if _focus_x >= 0.0 else size.x * 0.27, "floor": size.y * 0.82,
		"scale": size.y / 648.0 * 3.6 * _ship_size * (0.8 if _focus_x >= 0.0 else 1.0)}


func _layout() -> void:
	if rocket == null:
		return
	var spot := _spot()
	rocket.scale = Vector2.ONE * float(spot["scale"])
	rocket.position = Vector2(spot["x"], float(spot["floor"]) - 18.0 - 27.0 * float(spot["scale"]))
	rocket.queue_redraw()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	_update_workers(delta)
	_front.queue_redraw()


# --- Decorations and workers on the deck --------------------------------------------------

## Size unit: 1 at the 648 px reference height (decor and workers don't grow with the ship).
func _unit() -> float:
	return size.y / 1152.0 * 2.6 / 3.6 if _portrait() else size.y / 648.0


## The deck strip in front of the platform where workers walk.
func _deck() -> Rect2:
	var spot := _spot()
	var u := _unit()
	var top := float(spot["floor"]) + 42.0 * u
	var h := minf(46.0 * u, size.y - top - 12.0 * u)
	if _focus_x >= 0.0:  # Hangar screen: stay in the open middle column
		var half := size.x * 0.17
		return Rect2(_focus_x - half, top, half * 2.0, h)
	return Rect2(size.x * 0.05, top, size.x * 0.9, h)


## Where each decor slot stands (bottom-centre) and its max height: beside the platform on
## both sides, then in front of it, left and right of the rocket.
func _decor_slots() -> Array:
	var spot := _spot()
	var cx: float = spot["x"]
	var fy: float = spot["floor"]
	var u := _unit()
	var pw := 150.0 * float(spot["scale"]) / 3.6
	var side := 40.0 if _focus_x >= 0.0 else 58.0  # tucked in closer in the Hangar screen
	var side_h := 78.0 if _focus_x >= 0.0 else 92.0
	return [
		[Vector2(cx - pw - side * u, fy + 4.0 * u), side_h * u],
		[Vector2(cx + pw + side * u, fy + 4.0 * u), side_h * u],
		[Vector2(cx - pw * 0.78, fy + 40.0 * u), 70.0 * u],
		[Vector2(cx + pw * 0.78, fy + 40.0 * u), 70.0 * u],
	]


func _update_workers(delta: float) -> void:
	var deck := _deck()
	if deck.size.x <= 0.0 or deck.size.y <= 0.0:
		return
	var speed := WORKER_SPEED * _unit()
	for w in _workers:
		if float(w["wait"]) > 0.0:
			w["wait"] = float(w["wait"]) - delta
			w["walk"] = 0.0
			continue
		var at: Vector2 = deck.position + (w["pos"] as Vector2) * deck.size
		var goal: Vector2 = deck.position + (w["target"] as Vector2) * deck.size
		var step := goal - at
		if step.length() <= speed * delta:
			# Arrived: stand around a bit (facing you), then pick somewhere new.
			w["pos"] = w["target"]
			w["dir"] = 0
			w["wait"] = _rng.randf_range(1.5, 4.5)
			w["target"] = Vector2(_rng.randf(), _rng.randf())
			continue
		at += step.normalized() * speed * delta
		w["pos"] = (at - deck.position) / deck.size
		w["dir"] = (1 if step.x < 0.0 else 2) if absf(step.x) > absf(step.y) else (0 if step.y > 0.0 else 3)
		w["walk"] = float(w["walk"]) + delta


## Decorations and workers, nearest (lowest on screen) drawn last.
func _draw_front() -> void:
	var u := _unit()
	var items: Array = []  # [depth y, kind, data]
	var slots := _decor_slots()
	for i in mini(_decor.size(), slots.size()):
		var tex := Cosmetics.decor(str(_decor[i]))
		if tex:
			items.append([(slots[i][0] as Vector2).y, "decor", [tex, slots[i][0], slots[i][1]]])
	var sheet := Cosmetics.workers()
	if sheet:
		var deck := _deck()
		for w in _workers:
			var at: Vector2 = deck.position + (w["pos"] as Vector2) * deck.size
			items.append([at.y, "worker", [w, at]])
	items.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	for it in items:
		if it[1] == "decor":
			var tex: Texture2D = it[2][0]
			var base: Vector2 = it[2][1]
			var max_h: float = it[2][2]
			var k := minf(max_h / tex.get_height(), max_h * 1.3 / tex.get_width())
			var sz := Vector2(tex.get_width(), tex.get_height()) * k
			_front.draw_set_transform(base + Vector2(0, -sz.y * 0.04), 0.0, Vector2(1, 0.3))
			_front.draw_circle(Vector2.ZERO, sz.x * 0.45, Color(0, 0, 0, 0.25))  # contact shadow
			_front.draw_set_transform(Vector2.ZERO)
			_front.draw_texture_rect(tex, Rect2(base - Vector2(sz.x * 0.5, sz.y), sz), false)
		else:
			var w: Dictionary = it[2][0]
			var at: Vector2 = it[2][1]
			var walking := float(w["walk"]) > 0.0
			var step: int = [0, 1, 2, 1][int(float(w["walk"]) * 7.0) % 4] if walking else 1
			var src := Cosmetics.worker_region(int(w["sheet"]), int(w["dir"]), step)
			var sz := src.size * 2.6 * u
			_front.draw_set_transform(at, 0.0, Vector2(1, 0.3))
			_front.draw_circle(Vector2.ZERO, sz.x * 0.42, Color(0, 0, 0, 0.3))
			_front.draw_set_transform(Vector2.ZERO)
			_front.draw_texture_rect_region(sheet, Rect2(at - Vector2(sz.x * 0.5, sz.y - 2.0 * u), sz), src)


# --- Drawing helpers (all flat: one colour per shape) ---------------------------------------

func _round_rect(r: Rect2, radius: float, color: Color) -> void:
	radius = minf(radius, minf(r.size.x, r.size.y) / 2.0)
	draw_rect(Rect2(r.position.x + radius, r.position.y, r.size.x - radius * 2.0, r.size.y), color)
	draw_rect(Rect2(r.position.x, r.position.y + radius, r.size.x, r.size.y - radius * 2.0), color)
	for c in [r.position + Vector2(radius, radius), Vector2(r.end.x - radius, r.position.y + radius),
			Vector2(r.position.x + radius, r.end.y - radius), r.end - Vector2(radius, radius)]:
		draw_circle(c, radius, color)


## Vertical pipe with joints; horizontal when horizontal = true.
func _pipe(from: Vector2, length: float, width: float, color: Color, horizontal := false) -> void:
	var r := Rect2(from, Vector2(length, width) if horizontal else Vector2(width, length))
	draw_rect(r, color)
	var shade := color.darkened(0.25)
	if horizontal:
		draw_rect(Rect2(r.position.x, r.end.y - width * 0.3, r.size.x, width * 0.3), shade)
	else:
		draw_rect(Rect2(r.end.x - width * 0.3, r.position.y, width * 0.3, r.size.y), shade)
	var k := 40.0
	while k < length - 10.0:
		var j := Rect2(from + (Vector2(k, -3) if horizontal else Vector2(-3, k)),
			Vector2(10, width + 6) if horizontal else Vector2(width + 6, 10))
		draw_rect(j, color.lightened(0.06))
		k += 120.0


## Storage tank: rounded body with a dome, a band and a shaded side.
func _tank(base: Vector2, w: float, h: float, color: Color) -> void:
	_round_rect(Rect2(base.x - w / 2.0, base.y - h, w, h), w * 0.18, color)
	draw_circle(Vector2(base.x, base.y - h + w * 0.18), w * 0.42, color)
	draw_rect(Rect2(base.x - w / 2.0, base.y - h * 0.55, w, h * 0.08), color.darkened(0.2))
	draw_rect(Rect2(base.x + w * 0.2, base.y - h, w * 0.3, h), color.darkened(0.15))


## Warm capsule lamp with a flat glow.
func _lamp(at: Vector2, w: float, pulse: float) -> void:
	Palette.glow(self, at, w * 1.6, Palette.AMBER, 0.8 + 0.4 * pulse)
	_round_rect(Rect2(at.x - w / 2.0, at.y - w * 0.28, w, w * 0.56), w * 0.28, Palette.ORANGE)
	draw_rect(Rect2(at.x - w * 0.3, at.y - w * 0.16, w * 0.6, w * 0.12), Palette.AMBER)


## Catwalk: deck, railing posts and rail, support struts.
func _catwalk(x0: float, x1: float, y: float, color: Color) -> void:
	draw_rect(Rect2(x0, y, x1 - x0, 10), color)
	draw_rect(Rect2(x0, y + 10, x1 - x0, 4), color.darkened(0.25))
	draw_line(Vector2(x0, y - 22), Vector2(x1, y - 22), color, 3.0)
	var x := x0 + 6.0
	while x < x1:
		draw_line(Vector2(x, y), Vector2(x, y - 22), color, 2.0)
		x += 34.0
	for sx in [x0 + 24.0, x1 - 24.0]:
		draw_colored_polygon(PackedVector2Array([Vector2(sx - 4, y + 14), Vector2(sx + 4, y + 14),
			Vector2(sx + 18, y + 60), Vector2(sx + 10, y + 60)]), color.darkened(0.15))


func _draw() -> void:
	var w := size.x
	var h := size.y
	var spot := _spot()
	var cx: float = spot["x"]
	var floor_y: float = spot["floor"]
	var sc: float = spot["scale"]
	var portrait := _portrait()

	# 1) Far back: deep teal wall with a bright haze shaft and a big round light.
	draw_rect(Rect2(0, 0, w, h), Palette.TEAL_DEEP)
	var shaft_w := w * (0.34 if not portrait else 0.6)
	draw_rect(Rect2(cx - shaft_w / 2.0, 0, shaft_w, floor_y), Color(Palette.MIST, 0.12))
	draw_rect(Rect2(cx - shaft_w * 0.3, 0, shaft_w * 0.6, floor_y), Color(Palette.MIST, 0.12))
	var moon := Vector2(cx + (w * 0.05 if not portrait else 0.0), h * (0.28 if not portrait else 0.13))
	var moon_r := minf(w, h) * 0.13
	Palette.glow(self, moon, moon_r * 2.4, Palette.MIST, 1.2)
	draw_circle(moon, moon_r, Color(Palette.MIST, 0.9))

	# 2) Far structures in haze (lighter, low contrast): tanks and tall pipes.
	var far := Palette.hazed(Palette.TEAL, 0.45)
	for spec in [[0.06, 0.34, 0.16], [0.52, 0.42, 0.13], [0.66, 0.3, 0.1], [0.9, 0.38, 0.15]]:
		_tank(Vector2(w * float(spec[0]), floor_y), w * float(spec[2]) * (0.8 if portrait else 1.0), h * float(spec[1]), far)
	for x in [0.16, 0.42, 0.6, 0.79]:
		_pipe(Vector2(w * x, 0), floor_y, 16.0, far.darkened(0.08))
	_pipe(Vector2(0, h * 0.16), w, 14.0, far.darkened(0.12), true)

	# Floating dust in the light.
	for m in _motes:
		var p := Vector2(m.x * w, fmod(m.y * floor_y - _t * 6.0 * m.z + floor_y * 2.0, floor_y))
		draw_circle(p, m.z * 1.2, Color(Palette.MIST, 0.35))

	# 3) Mid layer: dark catwalks with warm capsule lamps.
	var mid := Palette.INDIGO
	if not portrait:
		_catwalk(w * 0.48, w * 0.98, h * 0.42, mid)
		_catwalk(0, w * 0.13, h * 0.5, mid)
		_lamp(Vector2(w * 0.58, h * 0.42 - 34), 26.0, sin(_t * 2.0))
		_lamp(Vector2(w * 0.86, h * 0.42 - 34), 26.0, sin(_t * 2.0 + 1.3))
		_lamp(Vector2(w * 0.06, h * 0.5 - 34), 26.0, sin(_t * 2.0 + 2.1))
	else:
		_catwalk(0, w * 0.3, h * 0.16, mid)
		_catwalk(w * 0.7, w, h * 0.22, mid)
		_lamp(Vector2(w * 0.12, h * 0.16 - 34), 24.0, sin(_t * 2.0))
		_lamp(Vector2(w * 0.86, h * 0.22 - 34), 24.0, sin(_t * 2.0 + 1.3))

	# 4) Floor: dark deck with a lighter lip, and the launch platform with a light strip.
	draw_rect(Rect2(0, floor_y, w, h - floor_y), Palette.NAVY)
	draw_rect(Rect2(0, floor_y, w, 5), Palette.SLATE)
	var pw := 150.0 * sc / 3.6
	Palette.glow(self, Vector2(cx, floor_y - 4), pw * 1.3, Palette.AQUA, 0.6 + 0.2 * sin(_t * 2.5))
	_round_rect(Rect2(cx - pw, floor_y - 18, pw * 2.0, 22), 6.0, Palette.SLATE)
	draw_rect(Rect2(cx - pw * 0.75, floor_y - 9, pw * 1.5, 4), Color(Palette.AQUA, 0.7 + 0.3 * sin(_t * 3.0)))

	# Gantry: a flat dark tower with an arm and two warm beacons.
	var gx := cx + pw * 1.25
	var gtop := floor_y - 95.0 * sc
	draw_rect(Rect2(gx, gtop, 14, floor_y - gtop), Palette.INDIGO)
	draw_rect(Rect2(gx + 34, gtop, 14, floor_y - gtop), Palette.INDIGO)
	var y := gtop + 20.0
	while y < floor_y - 10.0:
		draw_rect(Rect2(gx + 14, y, 20, 6), Palette.INDIGO.darkened(0.2))
		y += 34.0
	draw_rect(Rect2(cx + 12.0 * sc, gtop + 30.0 * sc, gx - cx - 12.0 * sc, 10), Palette.INDIGO)
	for i in 2:
		var on := fmod(_t + i * 0.5, 1.2) < 0.6
		var b := Vector2(gx + 7 + i * 34, gtop - 6)
		if on:
			Palette.glow(self, b, 18.0, Palette.ORANGE)
		draw_circle(b, 5.0, Palette.ORANGE if on else Palette.RUST.darkened(0.4))

	# 5) Foreground silhouettes (darkest): big pipes framing the scene.
	var near := Palette.INK
	_pipe(Vector2(0, h * 0.06), w, 26.0, near, true)
	_pipe(Vector2(w * (0.035 if not portrait else 0.04), 0), floor_y + 30, 34.0, near)
	if not portrait:
		_pipe(Vector2(w * 0.44, h * 0.06), h * 0.2, 22.0, near)
		_round_rect(Rect2(w * 0.44 - 14, h * 0.26, 50, 30), 10.0, near)
	draw_rect(Rect2(0, h - 16, w, 16), Palette.INK)

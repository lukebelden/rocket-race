extends Control
## Multiplayer ready-up: a full-screen line-up of 4 launch bays, yours on the left.
## Each bay shows that racer's own rocket (ship type, paint, fitted mods) on its launch pad,
## and below it their pilot monitor behind an airlock door. The door slides open when the
## pilot arrives and seals shut when they press READY; the light beside the monitor turns
## green. Empty bays show a bare pad and a dead monitor. When the server says go, the
## engines light and the bays slide away to the launch pad.

signal ready_pressed

const Pilots := preload("res://pilots.gd")
const Palette := preload("res://palette.gd")
const Rocket := preload("res://rocket.gd")
const SLOTS := 4
const STAGGER := 0.35  # seconds between bays appearing
const APPEAR := 0.2

const METAL := Color("2a2e35")
const METAL_HI := Color("4b525d")
const METAL_LO := Color("14161a")
const PHOSPHOR := Color("06120f")
const HAZARD := Color("e8b52b")
const GREEN := Color("7ed6a0")

## [{id, name, character, color: Color, me: bool, ship, paint: {main, dark, body}, mods}] - you first.
var pilots: Array = []
var _ready_ids: Dictionary = {}  # id -> time they pressed READY
var _left_ids: Dictionary = {}   # id -> time they left
var _arrived: Dictionary = {}    # slot -> arrival sound played
var _rockets: Dictionary = {}    # slot -> Rocket node
var _t := 0.0
var _exit_t := -1.0
var _deadline := 0.0
var _button: Button
var _status: Label
var _font: Font
var _stars: Array[Vector3] = []


func setup(players: Array, ready_timeout: float) -> void:
	pilots = players
	_deadline = ready_timeout


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind it can be clicked
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel pilot feeds
	_font = ThemeDB.fallback_font
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 120:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.5, 1.8)))

	# Each racer's real rocket, as a display model standing on its pad.
	for i in mini(pilots.size(), SLOTS):
		var p: Dictionary = pilots[i]
		var r := Rocket.new()
		r.ship = str(p.get("ship", "small"))
		var paint: Dictionary = p.get("paint", {})
		r.paint_main = Color.html(str(paint.get("main", "#e5683b")))
		r.paint_dark = Color.html(str(paint.get("dark", "#a8432a")))
		r.paint_body = Color.html(str(paint.get("body", "#e6efe9")))
		for m in p.get("mods", []):
			r.mods.append(str(m))
		r.missile_count = 2
		r.active = false
		r.flame_on = false
		r.monitoring = false
		r.monitorable = false
		r.visible = false
		add_child(r)
		r.set_process(false)  # just a picture until the engines light
		r.set_process_unhandled_input(false)
		_rockets[i] = r

	_button = Button.new()
	_button.text = "READY!"
	_button.custom_minimum_size = Vector2(260, 54)
	_button.add_theme_font_size_override("font_size", 26)
	_button.anchor_left = 0.5
	_button.anchor_right = 0.5
	_button.anchor_top = 1.0
	_button.anchor_bottom = 1.0
	_button.offset_left = -130
	_button.offset_right = 130
	_button.offset_top = -92
	_button.offset_bottom = -38
	_button.disabled = true  # until your own airlock has opened
	_button.pressed.connect(_on_ready)
	add_child(_button)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_top = -32
	_status.offset_bottom = -10
	add_child(_status)


func _on_ready() -> void:
	_button.disabled = true
	_button.text = "You're ready!"
	ready_pressed.emit()


## Server update: these player ids have pressed Ready (their airlock seals).
func set_ready(ids: Array) -> void:
	for id in ids:
		if not _ready_ids.has(int(id)):
			_ready_ids[int(id)] = _t
			Sound.play("detach", 0.9, -4.0)  # airlock door clunks shut


func pilot_left(id: int) -> void:
	_left_ids[id] = _t


## Everyone's ready: engines light, the bays slide away (then it frees itself).
func play_exit() -> void:
	if _exit_t < 0.0:
		_exit_t = 0.0
		_button.visible = false
		_status.visible = false
		for r: Rocket in _rockets.values():
			r.flame_on = true
			r.flame_power = 0.2


func _process(delta: float) -> void:
	_t += delta
	if _exit_t >= 0.0:
		_exit_t += delta
		for r: Rocket in _rockets.values():
			r.flame_power = minf(r.flame_power + delta * 1.6, 1.4)
		if _exit_t > 1.5:
			queue_free()
	else:
		# Your READY button wakes up once your own airlock is open.
		if _button.disabled and _button.text == "READY!" and _t > APPEAR + 1.0:
			_button.disabled = false
			_button.grab_focus()
		var left := maxf(_deadline - _t, 0.0)
		_status.text = "Race starts automatically in %ds" % ceili(left)
	queue_redraw()


# --- Layout --------------------------------------------------------------------------------

func _ease_back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)


func _slot_rects() -> Array[Rect2]:
	var w := size.x
	var h := size.y
	var rects: Array[Rect2] = []
	var top := 74.0
	var bottom := h - 104.0
	if h > w:  # portrait: 2 x 2
		var cw := (w - 36.0) / 2.0
		var ch := (bottom - top - 12.0) / 2.0
		for i in SLOTS:
			rects.append(Rect2(12.0 + (i % 2) * (cw + 12.0), top + (i / 2) * (ch + 12.0), cw, ch))
	else:
		var gap := 14.0
		var cw := minf((w - 40.0 - gap * 3.0) / 4.0, 290.0)
		var x0 := (w - (cw * 4.0 + gap * 3.0)) / 2.0
		for i in SLOTS:
			rects.append(Rect2(x0 + i * (cw + gap), top, cw, bottom - top))
	return rects


# --- Drawing -------------------------------------------------------------------------------

func _draw() -> void:
	var fade := 1.0
	if _exit_t >= 0.0:
		fade = 1.0 - clampf((_exit_t - 0.9) / 0.6, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK, 0.97 * fade))
	for s in _stars:
		draw_circle(Vector2(s.x * size.x, fmod(s.y * size.y + _t * 8.0 * s.z, size.y)), s.z * 0.8,
			Color(Palette.MIST, (0.2 + 0.4 * absf(sin(_t * s.z + s.x * 30.0))) * fade))
	var title := "PILOTS, TO YOUR ROCKETS!"
	var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	draw_string(_font, Vector2((size.x - tw) / 2.0, 52), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(Palette.AMBER, fade))

	var rects := _slot_rects()
	for i in SLOTS:
		_draw_slot(i, rects[i], pilots[i] if i < pilots.size() else {})


func _draw_slot(i: int, rect: Rect2, p: Dictionary) -> void:
	var t := _t - (APPEAR + i * STAGGER)
	var rocket: Rocket = _rockets.get(i)
	if t < 0.0:
		return
	var appear := clampf(t / 0.3, 0.0, 1.0)
	var lift := 0.0  # exit: bays slide up and away, left to right
	if _exit_t >= 0.0:
		lift = clampf((_exit_t - 0.6 - i * 0.06) / 0.55, 0.0, 1.0)
	var r := rect
	r.position.y += (1.0 - appear) * 30.0 - lift * lift * (r.end.y + 60.0)
	var alpha := appear
	var empty := p.is_empty()
	var id := -1 if empty else int(p["id"])
	var gone := not empty and _left_ids.has(id)
	var color: Color = Palette.SLATE if empty else p["color"]

	# Column frame.
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(Palette.NAVY, 0.95 * alpha)
	frame.border_color = Color(color, alpha * (0.45 if empty else 0.9))
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(12)
	frame.corner_detail = 1
	draw_style_box(frame, r)

	# --- Launch bay: backdrop, pad, the racer's rocket ---------------------------------
	var bay := Rect2(r.position + Vector2(8, 8), Vector2(r.size.x - 16, r.size.y * 0.54))
	draw_rect(bay, Color("10141a", alpha))
	for k in 5:  # gantry struts behind the rocket
		var x := bay.position.x + bay.size.x * (0.12 + k * 0.19)
		draw_rect(Rect2(x, bay.position.y, 3, bay.size.y), Color(METAL, 0.6 * alpha))
	draw_rect(Rect2(bay.position.x, bay.position.y + bay.size.y * 0.3, bay.size.x, 3), Color(METAL, 0.6 * alpha))
	var pad_y := bay.end.y - 16.0
	var pad := Rect2(bay.position.x + bay.size.x * 0.16, pad_y, bay.size.x * 0.68, 10)
	draw_rect(pad, Color(METAL_HI, alpha))
	draw_rect(Rect2(pad.position.x, pad.position.y + 10, pad.size.x, 6), Color(METAL_LO, alpha))
	var stripe_x := pad.position.x + 4.0
	while stripe_x < pad.end.x - 6.0:  # hazard edge on the pad
		draw_rect(Rect2(stripe_x, pad.position.y + 2, 6, 3), Color(HAZARD, 0.85 * alpha))
		stripe_x += 12.0
	var lamps_on := not empty and not gone
	for s: float in [0.0, 1.0]:  # pad lamps
		var lx := pad.position.x + 4.0 + s * (pad.size.x - 8.0)
		draw_rect(Rect2(lx - 1, pad_y - 14, 2, 14), Color(METAL_HI, alpha))
		var lamp := (Color(Palette.AMBER) if fmod(_t + s * 0.5, 1.0) < 0.6 else Color(Palette.RUST)) if lamps_on else Color(METAL_LO)
		if lamps_on:
			Palette.glow(self, Vector2(lx, pad_y - 16), 9.0, Palette.AMBER, alpha)
		draw_circle(Vector2(lx, pad_y - 16), 2.6, Color(lamp, alpha))
	if rocket:
		var k := minf(bay.size.y * 0.9 / 92.0, bay.size.x * 0.6 / 44.0)
		rocket.visible = not gone or (_t - float(_left_ids.get(id, _t))) < 0.4
		rocket.scale = Vector2.ONE * k
		rocket.position = Vector2(bay.get_center().x, pad_y - 26.0 * k)
		rocket.modulate.a = alpha * (0.35 if gone else 1.0)
		rocket.queue_redraw()
	if empty:
		_center_text("EMPTY BAY", Vector2(bay.get_center().x, bay.position.y + 22), 13, Color(Palette.TEXT_DIM, 0.7 * alpha))

	# --- Pilot monitor behind an airlock door, ready light beside it -----------------------
	var mon_top := bay.end.y + 10.0
	var light_w := 22.0
	var mon := Rect2(r.position.x + 8, mon_top, r.size.x - 16 - light_w - 6, r.end.y - mon_top - 40)
	_draw_monitor(i, mon, p, t, alpha)
	var ready := not empty and _ready_ids.has(id)
	_draw_light(Rect2(mon.end.x + 6, mon.position.y, light_w, mon.size.y), ready, empty or gone, alpha)

	# Name plate (YOU tag) under the monitor.
	var name_c := Vector2(r.get_center().x, r.end.y - 20)
	if empty:
		_center_text("Waiting for pilot...", name_c, 14, Color(Palette.TEXT_DIM, 0.8 * alpha))
	else:
		var label := str(p["name"]).left(14)
		if bool(p.get("me", false)):
			label = "YOU · " + label
		_center_text(label, name_c, 16, Color(color.lightened(0.35) if not gone else Palette.TEXT_DIM, alpha))
		if gone:
			_center_text("LEFT", Vector2(mon.get_center().x, mon.get_center().y), 20, Color(Palette.BAD, alpha))


## Gunmetal monitor: pixel feed of the pilot, with the airlock's two doors sliding over it.
func _draw_monitor(i: int, mon: Rect2, p: Dictionary, t: float, alpha: float) -> void:
	draw_rect(mon, Color(METAL, alpha))
	draw_rect(mon, Color(METAL_HI, alpha), false, 2.0)
	var scr := mon.grow(-6)
	draw_rect(scr, Color(PHOSPHOR, alpha))
	var empty := p.is_empty()
	if empty:
		_center_text("NO PILOT", scr.get_center(), 13, Color(Palette.TEXT_DIM, 0.5 * alpha))
		return
	var id := int(p["id"])
	# Pixel feed of the whole pilot (fitted to the screen, centred), scanlines on top.
	var tex := Pilots.pixel_texture(str(p.get("character", "")), 40)
	var ts := tex.get_size()
	var k := minf(scr.size.x / ts.x, scr.size.y / ts.y)
	var feed := Rect2(scr.get_center() - ts * k / 2.0, ts * k)
	var flick := 0.93 + 0.07 * sin(_t * 29.0 + i)
	draw_texture_rect(tex, feed, false, Color(flick, flick, flick, alpha))
	var y := scr.position.y
	while y < scr.end.y:
		draw_rect(Rect2(scr.position.x, y, scr.size.x, 1), Color(0, 0, 0, 0.3 * alpha))
		y += 3.0
	draw_circle(scr.position + Vector2(7, 7), 2.5, Color("ef3b3b", alpha) if fmod(_t, 1.2) < 0.75 else Color("5a1e1e", alpha))

	# Airlock: shut when the bay appears, slides open as the pilot arrives, seals on READY
	# (and when they leave, or as the race starts).
	var open := clampf((t - 0.45) / 0.45, 0.0, 1.0)
	if t > 0.45 and not _arrived.has(i) and _exit_t < 0.0:
		_arrived[i] = true
		Sound.play("dock", 1.2 + i * 0.08, -8.0)
	if _ready_ids.has(id):
		open = minf(open, 1.0 - clampf((_t - float(_ready_ids[id])) / 0.3, 0.0, 1.0))
	if _left_ids.has(id):
		open = minf(open, 1.0 - clampf((_t - float(_left_ids[id])) / 0.3, 0.0, 1.0))
	if _exit_t >= 0.0:
		open = minf(open, 1.0 - clampf(_exit_t / 0.3, 0.0, 1.0))
	var half := scr.size.x / 2.0 * (1.0 - open)
	if half > 0.5:
		for s: int in [0, 1]:
			var door := Rect2(scr.position.x, scr.position.y, half, scr.size.y) if s == 0 \
				else Rect2(scr.end.x - half, scr.position.y, half, scr.size.y)
			draw_rect(door, Color("3a4049", alpha))
			draw_rect(Rect2(door.position, Vector2(door.size.x, 3)), Color(METAL_HI, alpha))
			# hazard stripes on the meeting edge
			var edge_x := door.end.x - 7.0 if s == 0 else door.position.x
			var by := door.position.y
			var on := true
			while by < door.end.y:
				draw_rect(Rect2(edge_x, by, minf(7.0, door.size.x), minf(6.0, door.end.y - by)), Color(HAZARD if on else METAL_LO, alpha))
				on = not on
				by += 6.0
			# rivets
			if door.size.x > 16.0:
				var rx := door.position.x + 5.0 if s == 0 else door.end.x - 5.0
				for ry: float in [door.position.y + 8.0, door.end.y - 8.0]:
					draw_circle(Vector2(rx, ry), 1.6, Color(METAL_LO, alpha))
		if open <= 0.01 and _ready_ids.has(id) and not _left_ids.has(id):
			_center_text("SEALED", scr.get_center() + Vector2(0, scr.size.y * 0.3), 11, Color(GREEN, 0.9 * alpha))


## Status light beside the monitor: green when ready, slow amber pulse while waiting.
func _draw_light(r: Rect2, ready: bool, dead: bool, alpha: float) -> void:
	draw_rect(r, Color(METAL, alpha))
	draw_rect(r, Color(METAL_HI, alpha), false, 1.0)
	var c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.3)
	var lens := 7.0
	var col: Color
	if dead:
		col = METAL_LO
	elif ready:
		col = GREEN
		Palette.glow(self, c, 22.0, GREEN, 1.6 * alpha)
	else:
		col = Color(Palette.AMBER).lerp(Color(Palette.RUST), 0.5 + 0.5 * sin(_t * 3.0))
	draw_circle(c, lens + 2.0, Color(METAL_LO, alpha))
	draw_circle(c, lens, Color(col, alpha))
	draw_circle(c + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.45 * alpha))
	# little stack of indicator ticks under the lens
	for k in 3:
		var on := ready or (not dead and k == 0)
		draw_rect(Rect2(r.position.x + 6, c.y + 14 + k * 8, r.size.x - 12, 4), Color(GREEN if (ready and on) else (Palette.AMBER if on else METAL_LO), alpha * (0.9 if on else 0.6)))


func _center_text(text: String, c: Vector2, fs: int, color: Color) -> void:
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(c.x - tw / 2.0, c.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

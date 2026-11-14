extends Control
## Multiplayer pre-race intro: a full-screen line-up of up to 4 rockets, yours on the left.
## One by one (left to right) each rocket's hatch swings open and the pilot pops out and
## waves, with their name below. Everyone presses READY; when the server says go, the
## pilots duck back in, the hatches close and the panels slide away to the launch pad.

signal ready_pressed

const Pilots := preload("res://pilots.gd")
const Palette := preload("res://palette.gd")
const SLOTS := 4
const STAGGER := 0.45  # seconds between panels appearing
const APPEAR := 0.25

## [{id, name, character, color: Color, me: bool}] - you first.
var pilots: Array = []
var _ready_ids: Dictionary = {}  # id -> time the READY stamp appeared
var _left_ids: Dictionary = {}   # id -> time they left
var _popped: Dictionary = {}     # slot -> pop sound played
var _t := 0.0
var _exit_t := -1.0
var _deadline := 0.0
var _button: Button
var _status: Label
var _font: Font
var _blink: Array[float] = []
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
	for i in SLOTS:
		_blink.append(rng.randf_range(1.0, 3.0))

	_button = Button.new()
	_button.text = "READY!"
	_button.custom_minimum_size = Vector2(260, 58)
	_button.add_theme_font_size_override("font_size", 28)
	_button.anchor_left = 0.5
	_button.anchor_right = 0.5
	_button.anchor_top = 1.0
	_button.anchor_bottom = 1.0
	_button.offset_left = -130
	_button.offset_right = 130
	_button.offset_top = -112
	_button.offset_bottom = -54
	_button.disabled = true  # until your own pilot has popped out
	_button.pressed.connect(_on_ready)
	add_child(_button)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_top = -46
	_status.offset_bottom = -20
	add_child(_status)


func _on_ready() -> void:
	_button.disabled = true
	_button.text = "You're ready!"
	Sound.play("coin")
	ready_pressed.emit()


## Server update: these player ids have pressed Ready.
func set_ready(ids: Array) -> void:
	for id in ids:
		if not _ready_ids.has(int(id)):
			_ready_ids[int(id)] = _t
			Sound.play("beep", 1.4, -6.0)


func pilot_left(id: int) -> void:
	_left_ids[id] = _t


## Everyone's ready: pilots duck back in, hatches close, panels slide away (then it frees itself).
func play_exit() -> void:
	if _exit_t < 0.0:
		_exit_t = 0.0
		_button.visible = false
		_status.visible = false


func _process(delta: float) -> void:
	_t += delta
	if _exit_t >= 0.0:
		_exit_t += delta
		if _exit_t > 1.4:
			queue_free()
	else:
		# Your READY button wakes up once your own pilot is out of the hatch.
		if _button.disabled and _button.text == "READY!" and _t > APPEAR + 1.1:
			_button.disabled = false
			_button.grab_focus()
		var ready_count := 0
		for p in pilots:
			if _ready_ids.has(int(p["id"])):
				ready_count += 1
		var left := maxf(_deadline - _t, 0.0)
		_status.text = "%d / %d ready   ·   race starts automatically in %ds" % [ready_count, pilots.size(), ceili(left)]
	queue_redraw()


# --- Drawing -------------------------------------------------------------------------------

func _ease_back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)


func _slot_rects() -> Array[Rect2]:
	var w := size.x
	var h := size.y
	var rects: Array[Rect2] = []
	var portrait := h > w
	var top := 96.0
	var bottom := h - 130.0
	if portrait:
		var cw := (w - 48.0) / 2.0
		var ch := (bottom - top - 16.0) / 2.0
		for i in SLOTS:
			rects.append(Rect2(16.0 + (i % 2) * (cw + 16.0), top + (i / 2) * (ch + 16.0), cw, ch))
	else:
		var gap := 16.0
		var cw := minf((w - 48.0 - gap * 3.0) / 4.0, 300.0)
		var x0 := (w - (cw * 4.0 + gap * 3.0)) / 2.0
		for i in SLOTS:
			rects.append(Rect2(x0 + i * (cw + gap), top, cw, bottom - top))
	return rects


func _draw() -> void:
	var fade := 1.0
	if _exit_t >= 0.0:
		fade = 1.0 - clampf((_exit_t - 0.8) / 0.6, 0.0, 1.0)
	# Backdrop: deep space.
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK, 0.97 * fade))
	for s in _stars:
		draw_circle(Vector2(s.x * size.x, fmod(s.y * size.y + _t * 8.0 * s.z, size.y)), s.z * 0.8,
			Color(Palette.MIST, (0.25 + 0.45 * absf(sin(_t * s.z + s.x * 30.0))) * fade))
	var title := "PILOTS, TO YOUR ROCKETS!"
	var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	draw_string(_font, Vector2((size.x - tw) / 2.0, 62), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(Palette.AMBER, fade))

	var rects := _slot_rects()
	for i in SLOTS:
		_draw_slot(i, rects[i], pilots[i] if i < pilots.size() else {})


func _draw_slot(i: int, rect: Rect2, p: Dictionary) -> void:
	var t := _t - (APPEAR + i * STAGGER)
	if t < 0.0:
		return
	var appear := clampf(t / 0.35, 0.0, 1.0)
	var lift := 0.0  # exit: panels slide up and away, left to right
	if _exit_t >= 0.0:
		lift = clampf((_exit_t - 0.55 - i * 0.06) / 0.5, 0.0, 1.0)
	var r := rect
	r.position.x += (1.0 - appear) * -40.0
	r.position.y -= lift * lift * (r.end.y + 40.0)
	var alpha := appear
	var empty := p.is_empty()
	var color: Color = Palette.SLATE if empty else p["color"]

	# Panel: a launch bay with stars behind the rocket.
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(Palette.NAVY, 0.96 * alpha)
	panel.border_color = Color(color, alpha * (0.5 if empty else 1.0))
	panel.set_border_width_all(3)
	panel.set_corner_radius_all(18)
	draw_style_box(panel, r)
	if empty:
		_draw_rocket(r, Color(Palette.SLATE, alpha), 0.0, alpha)
		_center_text("Empty seat", Vector2(r.get_center().x, r.end.y - 34), 18, Color(Palette.TEXT_DIM, alpha))
		return

	var id := int(p["id"])
	var gone := _left_ids.has(id)
	# Hatch: swings open after the panel arrives; closes again on exit (or if they leave).
	var open := clampf((t - 0.35) / 0.35, 0.0, 1.0)
	var pop := _ease_back((t - 0.6) / 0.45)
	if _exit_t >= 0.0:
		var back := clampf(_exit_t / 0.3, 0.0, 1.0)
		pop *= 1.0 - back
		open = minf(open, 1.0 - clampf((_exit_t - 0.25) / 0.25, 0.0, 1.0))
	if gone:
		var g := clampf((_t - float(_left_ids[id])) / 0.4, 0.0, 1.0)
		pop *= 1.0 - g
		open = minf(open, 1.0 - g)
	if t > 0.6 and not _popped.has(i) and _exit_t < 0.0:
		_popped[i] = true
		Sound.play("dock", 1.3 + i * 0.08, -6.0)
	var hatch := _draw_rocket(r, Color(color, alpha), open, alpha)

	# Pilot on the hatch's porthole screen: the feed pops on with a bounce, scanlines over it.
	if pop > 0.01:
		var hr: float = hatch["r"]
		var c: Vector2 = hatch["c"]
		var pr := hr * 0.92 * minf(pop, 1.08)
		var tex := Pilots.pixel_texture(str(p["character"]), 36)
		var src := Pilots.source_rect(tex.get_size(), Vector2.ONE)
		var ts := tex.get_size()
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for k in 32:
			var a := TAU * k / 32.0
			var d := Vector2(cos(a), sin(a))
			pts.append(c + d * pr)
			uvs.append((src.position + (d * 0.5 + Vector2(0.5, 0.5)) * src.size) / ts)
		var flick := 0.93 + 0.07 * sin(_t * 29.0 + i)
		draw_colored_polygon(pts, Color(flick, flick, flick, alpha), uvs, tex)
		var y := c.y - pr
		while y < c.y + pr:  # scanlines, clipped to the circle
			var dx := sqrt(maxf(pr * pr - (y - c.y) * (y - c.y), 0.0))
			draw_line(Vector2(c.x - dx, y), Vector2(c.x + dx, y), Color(0, 0, 0, 0.28 * alpha), 1.0)
			y += 3.0
		draw_arc(c, pr, 0.0, TAU, 40, Color(Palette.INK, alpha), maxf(hr * 0.1, 2.0))

	# Name plate (and YOU tag), then the READY stamp.
	var name_y := r.end.y - 36.0
	var label := str(p["name"]).left(14)
	_plate(Vector2(r.get_center().x, name_y), label, color, alpha * (0.4 if gone else 1.0))
	if bool(p.get("me", false)):  # "YOU" tag in the top-left corner of your panel
		var tag := StyleBoxFlat.new()
		tag.bg_color = Color(Palette.AMBER, alpha)
		tag.set_corner_radius_all(6)
		draw_style_box(tag, Rect2(r.position.x + 12, r.position.y + 12, 46, 22))
		_center_text("YOU", Vector2(r.position.x + 35, r.position.y + 22), 14, Color(Palette.INK, alpha))
	if gone:
		_center_text("LEFT", r.get_center() + Vector2(0, -r.size.y * 0.32), 22, Color(Palette.BAD, alpha))
	elif _ready_ids.has(id):
		var st := clampf((_t - float(_ready_ids[id])) / 0.25, 0.0, 1.0)
		_stamp(Vector2(r.end.x - 52, r.position.y + 40), _ease_back(st), alpha)


## The rocket in a panel: nose cone in the pilot's colour, white body, big round hatch.
## Returns the hatch centre/radius. open: 0 = hatch shut, 1 = swung fully open.
func _draw_rocket(r: Rect2, color: Color, open: float, alpha: float) -> Dictionary:
	var cx := r.get_center().x
	var bw := r.size.x * 0.56
	var top := r.position.y + r.size.y * 0.08
	var nose_h := r.size.y * 0.2
	var body_top := top + nose_h
	var body_bottom := r.end.y - 64.0
	var white := Color(Palette.TEXT, alpha)
	var shade := Color(Palette.TEXT.lerp(Palette.HAZE, 0.35), alpha)
	# Fins
	for s in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([Vector2(cx + s * bw * 0.5, body_bottom - r.size.y * 0.16),
			Vector2(cx + s * bw * 0.78, body_bottom), Vector2(cx + s * bw * 0.5, body_bottom)]), color.darkened(0.2))
	# Body + right-side shading + stripe
	draw_rect(Rect2(cx - bw / 2.0, body_top, bw, body_bottom - body_top), white)
	draw_rect(Rect2(cx + bw * 0.22, body_top, bw * 0.28, body_bottom - body_top), shade)
	draw_rect(Rect2(cx - bw / 2.0, body_bottom - r.size.y * 0.08, bw, r.size.y * 0.03), color)
	# Nose cone
	draw_colored_polygon(PackedVector2Array([Vector2(cx, top), Vector2(cx + bw / 2.0, body_top + 1), Vector2(cx - bw / 2.0, body_top + 1)]), color)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, top), Vector2(cx + bw / 2.0, body_top + 1), Vector2(cx + bw * 0.12, body_top + 1)]), color.darkened(0.2))
	# Hatch: rim, dark opening, and the door swinging open on a hinge at the left.
	var hr := bw * 0.36
	var hc := Vector2(cx, body_top + (body_bottom - body_top) * 0.36)
	draw_circle(hc, hr * 1.12, Color(Palette.INDIGO, alpha))
	draw_circle(hc, hr, Color(Palette.INK, alpha))
	if open < 1.0:
		var door_w := hr * cos(open * PI / 2.0)
		var door_c := hc + Vector2(-hr + door_w, 0)
		var pts := PackedVector2Array()
		for k in 28:
			var a := TAU * k / 28.0
			pts.append(door_c + Vector2(cos(a) * door_w, sin(a) * hr))
		draw_colored_polygon(pts, Color(Palette.SLATE.lightened(0.2), alpha))
		if door_w > 4.0:
			draw_circle(door_c + Vector2(-door_w * 0.3, -hr * 0.3), hr * 0.25 * (door_w / hr), Color(Palette.AQUA, 0.9 * alpha))
			draw_circle(door_c + Vector2(door_w * 0.7, 0), 3.0, Color(Palette.INK, alpha))  # handle
	return {"c": hc, "r": hr}


func _plate(c: Vector2, text: String, color: Color, alpha: float) -> void:
	var fs := 18
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.INK, alpha)
	box.border_color = Color(color, alpha)
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	draw_style_box(box, Rect2(c.x - tw / 2.0 - 12, c.y - 15, tw + 24, 30))
	draw_string(_font, Vector2(c.x - tw / 2.0, c.y + 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color.lightened(0.35), alpha))


func _center_text(text: String, c: Vector2, fs: int, color: Color) -> void:
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(c.x - tw / 2.0, c.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Green "READY" stamp, slightly tilted, popping in.
func _stamp(c: Vector2, s: float, alpha: float) -> void:
	if s <= 0.01:
		return
	draw_set_transform(c, -0.18, Vector2.ONE * s)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.AQUA, 0.95 * alpha)
	box.set_corner_radius_all(8)
	draw_style_box(box, Rect2(-46, -16, 92, 32))
	var tw := _font.get_string_size("READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(_font, Vector2(-tw / 2.0, 7), "READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(Palette.INK, alpha))
	draw_set_transform(Vector2.ZERO)

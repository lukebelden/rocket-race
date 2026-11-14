extends Control
## Multiplayer room screen (ready-up): what you see as soon as you create or join a room.
## A line-up of 4 launch bays, yours on the left. Each bay shows that racer's own rocket
## (ship type, paint, fitted mods) on its pad, and below it their pilot monitor behind an
## airlock door: open while they're getting ready, sealed once they press READY, with a light
## beside it that turns green. Empty bays show a bare pad and a dead monitor.
##
## Buttons: Hangar / Shop (change your build - your bay updates for everyone), READY (a
## toggle) and Leave. Once every pilot is ready the server launches the race: the doors seal,
## the engines light and the bays slide away (play_exit).

signal ready_toggled(on: bool)
signal hangar_pressed
signal shop_pressed
signal leave_pressed

const Pilots := preload("res://scripts/ui/pilots.gd")
const Palette := preload("res://scripts/game/palette.gd")
const Rocket := preload("res://scripts/game/rocket.gd")
const SLOTS := 4
const STAGGER := 0.3  # seconds between bays appearing when the screen opens

const METAL := Color("2a2e35")
const METAL_HI := Color("4b525d")
const METAL_LO := Color("14161a")
const PHOSPHOR := Color("06120f")
const HAZARD := Color("e8b52b")
const GREEN := Color("7ed6a0")

## [{id, name, character, color: Color, me: bool, ship, paint: {main, dark, body}, mods}] - you first.
var pilots: Array = []
var code := ""
var min_players := 2
var last_results: Array = []
## Everyone's ready: the race launches at this time (Time.get_ticks_msec), 0 = not launching.
var launch_at := 0

var _arrived_at: Dictionary = {}   # id -> time their bay appeared
var _ready_at: Dictionary = {}     # id -> time they became ready
var _unready_at: Dictionary = {}   # id -> time they cancelled ready
var _arrive_sound: Dictionary = {} # id -> arrival sound played
var _rockets: Dictionary = {}      # id -> Rocket node
var _looks: Dictionary = {}        # id -> look signature (rebuild the rocket when it changes)
var _my_id := -1
var _t := 0.0
var _exit_t := -1.0
var _font: Font
var _stars: Array[Vector3] = []
var _bar: HBoxContainer
var _ready_button: Button
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind it can be clicked
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel pilot feeds
	_font = ThemeDB.fallback_font
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 120:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.5, 1.8)))

	# Bottom row: Hangar, Shop, READY (toggle), Leave.
	_bar = HBoxContainer.new()
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_theme_constant_override("separation", 12)
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_top = -92
	_bar.offset_bottom = -40
	add_child(_bar)
	_bar_button("Hangar", 150, func() -> void: hangar_pressed.emit())
	_bar_button("Shop", 150, func() -> void: shop_pressed.emit())
	_ready_button = _bar_button("READY!", 230, _on_ready_pressed)
	_ready_button.add_theme_font_size_override("font_size", 24)
	_ready_button.disabled = true  # until your airlock has opened
	_bar_button("Leave", 150, func() -> void: leave_pressed.emit())
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_top = -34
	_status.offset_bottom = -12
	add_child(_status)


func _bar_button(text: String, width: float, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	_bar.add_child(b)
	return b


func _is_ready(id: int) -> bool:
	return _ready_at.has(id)


func _on_ready_pressed() -> void:
	ready_toggled.emit(not _is_ready(_my_id))


## The room as the server sees it (players, who's ready): rebuild the line-up.
func set_room(room: Dictionary, my_id: int) -> void:
	_my_id = my_id
	code = str(room.get("code", ""))
	min_players = int(room.get("min", 2))
	var launch_in := float(room.get("launch_in", 0.0))
	launch_at = Time.get_ticks_msec() + int(launch_in * 1000.0) if launch_in > 0.0 else 0
	var list: Array = []
	for p in room.get("players", []):
		var id := int(p.get("id", 0))
		var entry := {"id": id, "name": str(p.get("name", "Pilot")), "character": str(p.get("character", "falcon")),
			"color": Color.html(str(p.get("color", "#ffffff"))), "me": id == my_id, "ship": str(p.get("ship", "small")),
			"paint": p.get("paint", {}) if p.get("paint") is Dictionary else {},
			"mods": p.get("mods", []) if p.get("mods") is Array else []}
		if id == my_id:
			list.push_front(entry)
		else:
			list.append(entry)
	pilots = list.slice(0, SLOTS)

	# Arrivals (staggered when the screen first opens) and departures.
	var ids := {}
	for i in pilots.size():
		var id := int(pilots[i]["id"])
		ids[id] = true
		if not _arrived_at.has(id):
			_arrived_at[id] = _t + (i * STAGGER if _t < 0.5 else 0.0)
	for id in _rockets.keys():
		if not ids.has(id):
			_rockets[id].queue_free()
			_rockets.erase(id)
			_looks.erase(id)
	for id in _arrived_at.keys():
		if not ids.has(id):
			_arrived_at.erase(id)
			_ready_at.erase(id)
			_unready_at.erase(id)

	# Who's ready: doors seal (with a clunk) or reopen.
	var ready_now := {}
	for r in room.get("ready", []):
		ready_now[int(r)] = true
	for id in ids:
		if ready_now.has(id) and not _ready_at.has(id):
			_ready_at[id] = _t
			_unready_at.erase(id)
			Sound.play("detach", 0.9, -4.0)
		elif not ready_now.has(id) and _ready_at.has(id):
			_ready_at.erase(id)
			_unready_at[id] = _t

	# Each racer's rocket: rebuilt when their build changes in the hangar or shop.
	for p in pilots:
		var id := int(p["id"])
		var look := JSON.stringify([p["ship"], p["paint"], p["mods"]])
		if _looks.get(id, "") == look:
			continue
		if _rockets.has(id):
			_rockets[id].queue_free()
		_rockets[id] = _make_rocket(p)
		_looks[id] = look
	if _ready_button:
		_ready_button.text = "CANCEL READY" if _is_ready(_my_id) else "READY!"


func set_last_results(ranking: Array) -> void:
	last_results = ranking


func _make_rocket(p: Dictionary) -> Rocket:
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
	move_child(r, 0)  # behind the buttons
	r.set_process(false)  # just a picture until the engines light
	r.set_process_unhandled_input(false)
	return r


## Everyone's ready: engines light, the bays slide away (then it frees itself).
func play_exit() -> void:
	if _exit_t < 0.0:
		_exit_t = 0.0
		_bar.visible = false
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
		if _ready_button.disabled and _t - float(_arrived_at.get(_my_id, 0.0)) > 0.9:
			_ready_button.disabled = false
			_ready_button.grab_focus()
		var ready_count := 0
		for p in pilots:
			if _is_ready(int(p["id"])):
				ready_count += 1
		var waiting := pilots.size() - ready_count
		if pilots.size() < min_players:
			_status.text = "Waiting for at least %d pilots - share the room code with your friends!" % min_players
		elif waiting > 0:
			_status.text = "Waiting for %d pilot%s to get ready" % [waiting, "" if waiting == 1 else "s"]
		elif launch_at > 0:
			var secs := ceili(maxf(launch_at - Time.get_ticks_msec(), 0) / 1000.0)
			_status.text = "All pilots ready - launching in %d...   (Cancel Ready to wait)" % secs
		else:
			_status.text = "All pilots ready - launching!"
	queue_redraw()


# --- Layout --------------------------------------------------------------------------------

func _slot_rects() -> Array[Rect2]:
	var w := size.x
	var h := size.y
	var rects: Array[Rect2] = []
	var top := 84.0
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
	var title := "ROOM  %s" % code if code != "" else "PILOTS, TO YOUR ROCKETS!"
	_center_text(title, Vector2(size.x / 2.0, 36), 32, Color(Palette.AMBER, fade))
	var sub := "Share this code with friends so they can join"
	if not last_results.is_empty():
		var podium: Array[String] = []
		for row in last_results:
			if row is Dictionary:
				podium.append("%d. %s" % [int(row.get("rank", 0)), str(row.get("name", "?"))])
		sub = "Last race:  " + "   ".join(podium)
	_center_text(sub, Vector2(size.x / 2.0, 66), 14, Color(Palette.TEXT_DIM, fade))

	var rects := _slot_rects()
	for i in SLOTS:
		_draw_slot(i, rects[i], pilots[i] if i < pilots.size() else {})


func _draw_slot(i: int, rect: Rect2, p: Dictionary) -> void:
	var empty := p.is_empty()
	var id := -1 if empty else int(p["id"])
	var t := _t - (float(_arrived_at.get(id, 0.0)) if not empty else i * STAGGER)
	var rocket: Rocket = _rockets.get(id)
	if t < 0.0:
		if rocket:
			rocket.visible = false
		return
	var appear := clampf(t / 0.3, 0.0, 1.0)
	var lift := 0.0  # exit: bays slide up and away, left to right
	if _exit_t >= 0.0:
		lift = clampf((_exit_t - 0.6 - i * 0.06) / 0.55, 0.0, 1.0)
	var r := rect
	r.position.y += (1.0 - appear) * 30.0 - lift * lift * (r.end.y + 60.0)
	var alpha := appear
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
	for s: float in [0.0, 1.0]:  # pad lamps
		var lx := pad.position.x + 4.0 + s * (pad.size.x - 8.0)
		draw_rect(Rect2(lx - 1, pad_y - 14, 2, 14), Color(METAL_HI, alpha))
		var lamp := (Color(Palette.AMBER) if fmod(_t + s * 0.5, 1.0) < 0.6 else Color(Palette.RUST)) if not empty else Color(METAL_LO)
		if not empty:
			Palette.glow(self, Vector2(lx, pad_y - 16), 9.0, Palette.AMBER, alpha)
		draw_circle(Vector2(lx, pad_y - 16), 2.6, Color(lamp, alpha))
	if rocket:
		var k := minf(bay.size.y * 0.9 / 92.0, bay.size.x * 0.6 / 44.0)
		rocket.visible = true
		rocket.scale = Vector2.ONE * k
		rocket.position = Vector2(bay.get_center().x, pad_y - 26.0 * k)
		rocket.modulate.a = alpha
		rocket.queue_redraw()
	if empty:
		_center_text("EMPTY BAY", Vector2(bay.get_center().x, bay.position.y + 22), 13, Color(Palette.TEXT_DIM, 0.7 * alpha))

	# --- Pilot monitor behind an airlock door, ready light beside it -----------------------
	var mon_top := bay.end.y + 10.0
	var light_w := 22.0
	var mon := Rect2(r.position.x + 8, mon_top, r.size.x - 16 - light_w - 6, r.end.y - mon_top - 40)
	_draw_monitor(i, mon, p, t, alpha)
	_draw_light(Rect2(mon.end.x + 6, mon.position.y, light_w, mon.size.y), not empty and _is_ready(id), empty, alpha)

	# Name plate (YOU tag) under the monitor.
	var name_c := Vector2(r.get_center().x, r.end.y - 20)
	if empty:
		_center_text("Waiting for pilot...", name_c, 14, Color(Palette.TEXT_DIM, 0.8 * alpha))
	else:
		var label := str(p["name"]).left(14)
		if bool(p.get("me", false)):
			label = "YOU · " + label
		_center_text(label, name_c, 16, Color(color.lightened(0.35), alpha))


## Gunmetal monitor: pixel feed of the pilot, with the airlock's two doors sliding over it.
func _draw_monitor(i: int, mon: Rect2, p: Dictionary, t: float, alpha: float) -> void:
	draw_rect(mon, Color(METAL, alpha))
	draw_rect(mon, Color(METAL_HI, alpha), false, 2.0)
	var scr := mon.grow(-6)
	draw_rect(scr, Color(PHOSPHOR, alpha))
	if p.is_empty():
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

	# Airlock: shut when the bay appears, slides open as the pilot arrives, seals on READY,
	# reopens if they cancel, and seals as the race launches.
	var open := clampf((t - 0.45) / 0.45, 0.0, 1.0)
	if t > 0.45 and not _arrive_sound.has(id) and _exit_t < 0.0:
		_arrive_sound[id] = true
		Sound.play("dock", 1.2 + i * 0.08, -8.0)
	if _ready_at.has(id):
		open = minf(open, 1.0 - clampf((_t - float(_ready_at[id])) / 0.3, 0.0, 1.0))
	elif _unready_at.has(id):
		open = minf(open, clampf((_t - float(_unready_at[id])) / 0.35, 0.0, 1.0))
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
			if door.size.x > 16.0:  # rivets
				var rx := door.position.x + 5.0 if s == 0 else door.end.x - 5.0
				for ry: float in [door.position.y + 8.0, door.end.y - 8.0]:
					draw_circle(Vector2(rx, ry), 1.6, Color(METAL_LO, alpha))
		if open <= 0.01 and _ready_at.has(id):
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
	for k in 3:  # indicator ticks under the lens
		var on := ready or (not dead and k == 0)
		draw_rect(Rect2(r.position.x + 6, c.y + 14 + k * 8, r.size.x - 12, 4),
			Color(GREEN if (ready and on) else (Palette.AMBER if on else METAL_LO), alpha * (0.9 if on else 0.6)))


func _center_text(text: String, c: Vector2, fs: int, color: Color) -> void:
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(c.x - tw / 2.0, c.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

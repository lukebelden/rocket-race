extends Control
## HUD pilot monitor: a gunmetal console screen showing a live pixel feed of the pilot, with
## scanlines, a LIVE light, signal bars and a status readout. Your own monitor sits bottom
## right (big = true); in races the other pilots get smaller monitors bottom left.
##
## The feed reacts: base_mood follows what's happening every frame (boosting -> "excited",
## low hull -> "worried", crashed -> "out"), and react() shows a mood for a moment (a hit,
## a level up, docking).

const Pilots := preload("res://pilots.gd")
const Palette := preload("res://palette.gd")

## Pilot id (name kept from the animal-pilot days).
var animal: String = Pilots.DEFAULT
var pilot_name: String = ""
var accent: Color = Color("e8892b")
var big: bool = true
## "" or a short badge in the top corner, e.g. "1st" or "OUT".
var badge: String = ""
var base_mood: String = "normal"

var _mood: String = "normal"
var _mood_time := 0.0
var _t := 0.0
var _glitch := 0.0
var _font: Font

const METAL := Color("2a2e35")
const METAL_HI := Color("4b525d")
const METAL_LO := Color("14161a")
const PHOSPHOR := Color("06120f")
const STATUS := {
	"normal": ["NOMINAL", Color("7ed6a0")],
	"happy": ["NOMINAL", Color("7ed6a0")],
	"excited": ["BOOST", Color("ffc56b")],
	"worried": ["HULL LOW", Color("ef6a5a")],
	"hurt": ["IMPACT", Color("ef6a5a")],
	"out": ["OFFLINE", Color("8fa6b0")],
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel feed
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(196, 166) if big else Vector2(118, 112)
	size = custom_minimum_size


## Show a mood for a moment ("hurt", "happy", ...), then go back to base_mood.
func react(mood: String, seconds := 1.2) -> void:
	_mood = mood
	_mood_time = seconds
	if mood == "hurt":
		_glitch = 0.45


func _process(delta: float) -> void:
	_t += delta
	_glitch = maxf(_glitch - delta, 0.0)
	if _mood_time > 0.0:
		_mood_time -= delta
	queue_redraw()


func mood() -> String:
	if base_mood == "out":
		return "out"
	return _mood if _mood_time > 0.0 else base_mood


func _draw() -> void:
	var w := size.x
	var h := size.y
	var m := mood()
	var out := m == "out"
	var pad := 8.0 if big else 5.0
	var foot := 26.0 if big else 18.0  # nameplate strip under the screen

	# Bezel: chamfered gunmetal plate with a bevel and an accent stripe on top.
	var ch := 10.0 if big else 6.0
	var plate := PackedVector2Array([Vector2(ch, 0), Vector2(w - ch, 0), Vector2(w, ch), Vector2(w, h - ch),
		Vector2(w - ch, h), Vector2(ch, h), Vector2(0, h - ch), Vector2(0, ch)])
	draw_colored_polygon(plate, METAL)
	draw_polyline(PackedVector2Array([plate[6], plate[7], plate[0], plate[1]]), METAL_HI, 2.0)
	draw_polyline(PackedVector2Array([plate[2], plate[3], plate[4], plate[5]]), METAL_LO, 2.0)
	draw_rect(Rect2(ch + 4, 2, w - ch * 2 - 8, 2), accent if not out else Palette.SLATE)
	if big:
		for p in [Vector2(6, 6), Vector2(w - 6, 6), Vector2(6, h - 6), Vector2(w - 6, h - 6)]:
			draw_circle(p, 2.6, METAL_LO)
			draw_line(p + Vector2(-1.6, -1.0), p + Vector2(1.6, 1.0), METAL_HI, 1.0)

	# Screen.
	var scr := Rect2(pad, pad + 3, w - pad * 2, h - pad * 2 - foot - 3)
	draw_rect(scr.grow(2), METAL_LO)
	draw_rect(scr, PHOSPHOR)
	var tex := Pilots.pixel_texture(animal, 44 if big else 30)
	var src := Rect2(Vector2.ZERO, tex.get_size())
	# Square feed of the pilot; on the big monitor a telemetry column fills the rest.
	var feed := Rect2(scr.position, Vector2(scr.size.y, scr.size.y))
	if not big:
		feed.position.x = scr.get_center().x - scr.size.y / 2.0
	var full := scr
	scr = feed
	var flicker := 0.94 + 0.06 * sin(_t * 31.0) * sin(_t * 7.3)
	var tint := Color(0.92, 1.0, 0.97) * flicker
	if out:
		tint = Color(0.25, 0.3, 0.3)
	elif _glitch > 0.0:
		tint = Color(1.5, 0.55, 0.5)
	elif m == "worried" and fmod(_t, 0.8) < 0.4:
		tint = Color(1.25, 0.85, 0.7)
	tint.a = 1.0
	if _glitch > 0.0 and not out:
		# Hit: the feed tears into sideways-shifted slices.
		var slices := 6
		for i in slices:
			var sy := src.size.y / slices
			var dy := scr.size.y / slices
			var off := randf_range(-8.0, 8.0) * (_glitch / 0.45)
			draw_texture_rect_region(tex, Rect2(scr.position.x + off, scr.position.y + dy * i, scr.size.x, dy),
				Rect2(src.position.x, src.position.y + sy * i, src.size.x, sy), tint)
	else:
		draw_texture_rect_region(tex, scr, src, tint)
	if out:
		# No signal: static snow.
		var cell := 4.0 if big else 3.0
		var y := scr.position.y
		while y < scr.end.y:
			var x := scr.position.x
			while x < scr.end.x:
				if randf() < 0.45:
					draw_rect(Rect2(x, y, cell, cell), Color(1, 1, 1, randf_range(0.08, 0.35)))
				x += cell
			y += cell

	scr = full
	if big:
		_telemetry(Rect2(feed.end.x + 4, scr.position.y + 20, scr.end.x - feed.end.x - 8, scr.size.y - 24), m)
	else:
		draw_rect(Rect2(scr.position, Vector2(feed.position.x - scr.position.x, scr.size.y)), Color(1, 1, 1, 0.03))
		draw_rect(Rect2(Vector2(feed.end.x, scr.position.y), Vector2(scr.end.x - feed.end.x, scr.size.y)), Color(1, 1, 1, 0.03))

	# CRT: scanlines, a slow rolling bright band, darker edges.
	var line_y := scr.position.y
	while line_y < scr.end.y:
		draw_rect(Rect2(scr.position.x, line_y, scr.size.x, 1), Color(0, 0, 0, 0.32))
		line_y += 3.0
	var band_y := scr.position.y + fmod(_t * 28.0, scr.size.y + 30.0) - 15.0
	draw_rect(Rect2(scr.position.x, clampf(band_y, scr.position.y, scr.end.y), scr.size.x,
		clampf(band_y + 10.0, scr.position.y, scr.end.y) - clampf(band_y, scr.position.y, scr.end.y)), Color(0.6, 1.0, 0.85, 0.06))
	for i in 4:
		var e := float(i + 1) * 2.0
		draw_rect(scr.grow(-e + 2.0), Color(0, 0, 0, 0.09), false, 2.0)

	# Overlays on the glass: LIVE light, signal bars, warnings.
	var fs := 11 if big else 9
	var live_on := fmod(_t, 1.2) < 0.75 and not out
	draw_circle(Vector2(scr.position.x + 8, scr.position.y + 8), 3.0 if big else 2.2, Color("ef3b3b") if live_on else Color("5a1e1e"))
	if big:
		draw_string(_font, Vector2(scr.position.x + 14, scr.position.y + 12), "LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75))
	for i in 4:
		var strength := 0 if out else (3 if m == "hurt" else 4)
		var on := i < strength and not (m == "hurt" and randf() < 0.3)
		var bh := 3.0 + i * 2.5
		draw_rect(Rect2(scr.end.x - 26 + i * 5, scr.position.y + 15 - bh, 3, bh), Color("7ed6a0") if on else Color(1, 1, 1, 0.15))
	if out:
		_center(Vector2(scr.get_center().x, scr.get_center().y + 4), "SIGNAL LOST", fs + (3 if big else 1),
			Color("ef6a5a") if fmod(_t, 1.0) < 0.6 else Color("8a3a33"))
	elif m == "worried" and fmod(_t, 0.8) < 0.4:
		draw_rect(Rect2(scr.position.x, scr.end.y - (16 if big else 12), scr.size.x, 12 if big else 9), Color(0.94, 0.42, 0.35, 0.75))
		_center(Vector2(scr.get_center().x, scr.end.y - (10 if big else 7.5)), "WARNING", fs - 1, Color.WHITE)

	# Nameplate strip: pilot name left, status right.
	var name_y := h - pad - 6.0
	var st: Array = STATUS.get(m, STATUS["normal"])
	var name_fs := 14 if big else 11
	draw_string(_font, Vector2(pad + 2, name_y), pilot_name.to_upper().left(12), HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs,
		Color("e6f1ee") if not out else Color("8fa6b0"))
	if big:
		var label: String = st[0]
		var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(w - pad - lw - 10, name_y - fs - 3, lw + 8, fs + 6), Color(st[1], 0.18))
		draw_string(_font, Vector2(w - pad - lw - 6, name_y - 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, st[1])
	else:
		draw_circle(Vector2(w - pad - 4, name_y - 4), 3.0, st[1])

	# Badge (race place / OUT / FINISHED) in the top corner.
	if badge != "":
		var bs := 12 if big else 10
		var bw := _font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x + 10
		var br := Rect2(w - bw - 4, -6, bw, bs + 6)
		draw_rect(br, Palette.BAD if badge == "OUT" else Color("ffc56b"))
		draw_string(_font, Vector2(br.position.x + 5, br.end.y - 4), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, METAL_LO)


## Vital signs beside the feed: heart rate, oxygen and a running ECG trace.
func _telemetry(r: Rect2, m: String) -> void:
	var green := Color("7ed6a0")
	var amber := Color("ffc56b")
	var red := Color("ef6a5a")
	if m == "out":
		draw_string(_font, r.position + Vector2(0, 10), "HR ---", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("8fa6b0"))
		draw_line(Vector2(r.position.x, r.end.y - 12), Vector2(r.end.x, r.end.y - 12), red, 1.0)
		return
	var bpm: int = int({"excited": 128, "worried": 112, "hurt": 140, "happy": 92}.get(m, 84)) + int(sin(_t * 0.7) * 3.0)
	var col: Color = green if bpm < 105 else (amber if bpm < 125 else red)
	draw_string(_font, r.position + Vector2(0, 10), "HR %d" % bpm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	var o2 := 97 if m != "worried" else 91
	draw_string(_font, r.position + Vector2(0, 24), "O2 %d%%" % o2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, green if o2 > 94 else amber)
	# ECG: flat line with a beat spike, scrolling left.
	var base := r.end.y - 14.0
	var pts := PackedVector2Array()
	var period := 60.0 / float(bpm)
	var x := 0.0
	while x <= r.size.x:
		var ph := fmod(_t - x / 70.0, period) / period
		var y := 0.0
		if ph < 0.06:
			y = -10.0 * sin(ph / 0.06 * PI)
		elif ph < 0.1:
			y = 4.0 * sin((ph - 0.06) / 0.04 * PI)
		pts.append(Vector2(r.position.x + x, base + y))
		x += 2.0
	draw_polyline(pts, Color(col, 0.9), 1.0)


func _center(c: Vector2, text: String, fs: int, color: Color) -> void:
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(c.x - tw / 2.0, c.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

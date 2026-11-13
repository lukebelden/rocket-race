extends Control
## HUD pilot card: an animal pilot in a headset, sitting at a little console inside a
## rounded box, with their name on the console's nameplate. Your own card sits bottom right
## (big = true); in races the other pilots get smaller cards bottom left.
##
## The pilot reacts: base_mood follows what's happening every frame (boosting -> excited,
## low hull -> worried, crashed -> out), and react() shows a mood for a moment (a hit,
## a level up, docking).

const Animals := preload("res://animals.gd")

var animal: String = "duck"
var pilot_name: String = ""
var accent: Color = Color(0.45, 0.8, 1.0)
var big: bool = true
## "" or a short badge in the top corner, e.g. "1st" or "OUT".
var badge: String = ""
var base_mood: String = "normal"

var _mood: String = "normal"
var _mood_time := 0.0
var _t := 0.0
var _blink_at := 1.5
var _shake := 0.0
var _font: Font
## Fixed little star field behind the pilot (the cockpit window).
var _stars: Array[Vector3] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(190, 152) if big else Vector2(116, 108)
	size = custom_minimum_size
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pilot_name + animal)
	for i in (14 if big else 9):
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.6, 1.6)))


## Show a mood for a moment ("hurt", "happy", ...), then go back to base_mood.
func react(mood: String, seconds := 1.2) -> void:
	_mood = mood
	_mood_time = seconds
	if mood == "hurt":
		_shake = 0.35


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(_shake - delta, 0.0)
	if _mood_time > 0.0:
		_mood_time -= delta
	if _t > _blink_at + 0.14:
		_blink_at = _t + randf_range(2.0, 4.5)
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

	# Rounded box.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.06, 0.11, 0.9)
	box.border_color = accent if not out else Color(0.45, 0.45, 0.5)
	box.set_border_width_all(2)
	box.set_corner_radius_all(16)
	draw_style_box(box, Rect2(Vector2.ZERO, size))

	# Cockpit window behind the pilot, with stars drifting past.
	var win := Rect2(8, 8, w - 16, h * 0.62)
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color(0.07, 0.12, 0.25)
	glass.set_corner_radius_all(11)
	draw_style_box(glass, win)
	for s in _stars:
		var x := win.position.x + fmod(s.x * win.size.x + _t * 6.0 * s.z, win.size.x)
		var y := win.position.y + 4.0 + s.y * (win.size.y - 8.0)
		draw_circle(Vector2(x, y), s.z * 0.8, Color(1, 1, 1, 0.35 + 0.4 * absf(sin(_t * s.z + s.x * 9.0))))

	var desk_y := h * 0.66  # top edge of the console
	var r := h * 0.19
	var bob := 0.0 if out else sin(_t * 2.2) * 1.4
	var shake := Vector2(randf_range(-2.5, 2.5), randf_range(-1.5, 1.5)) * (_shake / 0.35) if _shake > 0.0 else Vector2.ZERO
	var head := Vector2(w / 2.0, desk_y - r * 1.3 + bob) + shake
	if out:
		head += Vector2(r * 0.15, r * 0.25)  # slumped

	# Seat back, then shoulders in a flight suit (the card's colour).
	var seat := StyleBoxFlat.new()
	seat.bg_color = Color(0.2, 0.22, 0.28)
	seat.set_corner_radius_all(int(r * 0.5))
	draw_style_box(seat, Rect2(head.x - r * 1.35, head.y - r * 0.2, r * 2.7, desk_y - head.y + r * 0.4))
	var suit := accent.darkened(0.35) if not out else Color(0.35, 0.36, 0.4)
	var body := PackedVector2Array([
		Vector2(head.x - r * 1.15, desk_y + 2), Vector2(head.x - r * 1.0, head.y + r * 0.9),
		Vector2(head.x - r * 0.45, head.y + r * 0.72), Vector2(head.x + r * 0.45, head.y + r * 0.72),
		Vector2(head.x + r * 1.0, head.y + r * 0.9), Vector2(head.x + r * 1.15, desk_y + 2)])
	draw_colored_polygon(body, suit)
	draw_colored_polygon(PackedVector2Array([head + Vector2(-r * 0.4, r * 0.75), head + Vector2(r * 0.4, r * 0.75),
		head + Vector2(0, r * 1.15)]), Color(0.92, 0.93, 0.96))  # collar
	draw_circle(head + Vector2(-r * 0.62, r * 1.12), r * 0.12, Color(1, 0.8, 0.3))  # badge

	Animals.draw_face(self, head, r, animal, m, _t >= _blink_at and _t < _blink_at + 0.13)

	# Headset: band over the head, ear cups, and a mic in front of the mouth.
	var band := Color(0.18, 0.19, 0.23)
	draw_arc(head, r * 1.06, PI * 1.08, PI * 1.92, 16, band, maxf(r * 0.13, 2.0))
	for s in [-1.0, 1.0]:
		var cup := head + Vector2(s * r * 1.0, r * 0.05)
		draw_colored_polygon(Animals._ellipse(cup, r * 0.17, r * 0.27), band)
		draw_colored_polygon(Animals._ellipse(cup, r * 0.09, r * 0.17), accent if not out else Color(0.4, 0.4, 0.45))
	draw_polyline(PackedVector2Array([head + Vector2(r * 1.0, r * 0.25), head + Vector2(r * 0.85, r * 0.62),
		head + Vector2(r * 0.42, r * 0.66)]), band, maxf(r * 0.06, 1.5))
	draw_circle(head + Vector2(r * 0.38, r * 0.66), r * 0.08, Color(0.1, 0.1, 0.12))

	# The console in front: desk top, front panel with blinking lights and a little screen.
	var desk := PackedVector2Array([Vector2(6, desk_y), Vector2(w - 6, desk_y), Vector2(w - 2, h - 6), Vector2(2, h - 6)])
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.22, 0.24, 0.3)
	panel.corner_radius_bottom_left = 14
	panel.corner_radius_bottom_right = 14
	draw_style_box(panel, Rect2(2, desk_y, w - 4, h - desk_y - 2))
	draw_rect(Rect2(6, desk_y - 3, w - 12, 6), Color(0.38, 0.4, 0.48))  # desk lip
	var lights := [Color(1, 0.35, 0.3), Color(1, 0.8, 0.3), Color(0.4, 1, 0.55)]
	for i in 3:
		var on := fmod(_t * (1.3 + i * 0.7) + i, 2.0) < 1.2 and not out
		draw_circle(Vector2(14 + i * 9, desk_y + 12), 2.6, lights[i] if on else lights[i].darkened(0.7))
	var screen := Rect2(w - 34, desk_y + 7, 24, 11)
	draw_rect(screen, Color(0.05, 0.25, 0.2) if not out else Color(0.15, 0.08, 0.08))
	for i in 3:
		var bar := 3.0 + 6.0 * absf(sin(_t * 3.0 + i)) if not out else 1.5
		draw_rect(Rect2(screen.position.x + 3 + i * 7, screen.end.y - 1 - bar, 4, bar), Color(0.4, 1, 0.6) if not out else Color(1, 0.3, 0.3))

	# Paws resting on the desk (on the controls when excited).
	var paw := Animals.fur(animal)
	var reach := 0.0 if m != "excited" else sin(_t * 18.0) * 1.5
	for s in [-1.0, 1.0]:
		var p := Vector2(head.x + s * r * 0.85, desk_y + 1 + reach * s)
		draw_colored_polygon(Animals._ellipse(p, r * 0.27, r * 0.18), paw)
		draw_colored_polygon(Animals._ellipse(p + Vector2(0, r * 0.03), r * 0.16, r * 0.08), paw.lightened(0.25))

	# Nameplate.
	var size_px := 15 if big else 12
	var text := pilot_name.left(14)
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var plate := Rect2(w / 2.0 - tw / 2.0 - 7, h - 6 - size_px - 9, tw + 14, size_px + 6)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.06, 0.09)
	ps.set_corner_radius_all(5)
	ps.border_color = (accent if not out else Color(0.45, 0.45, 0.5)).darkened(0.2)
	ps.set_border_width_all(1)
	draw_style_box(ps, plate)
	draw_string(_font, Vector2(plate.position.x + 7, plate.end.y - 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px,
		accent.lightened(0.3) if not out else Color(0.65, 0.65, 0.7))

	# Badge (race place / OUT / FINISHED) in the top corner.
	if badge != "":
		var bs := 12 if big else 11
		var bw := _font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x + 12
		var br := Rect2(w - bw - 10, 12, bw, bs + 6)
		var bstyle := StyleBoxFlat.new()
		bstyle.bg_color = Color(0.85, 0.25, 0.22) if badge == "OUT" else Color(1, 0.75, 0.25)
		bstyle.set_corner_radius_all(6)
		draw_style_box(bstyle, br)
		draw_string(_font, Vector2(br.position.x + 6, br.end.y - 4), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, Color(0.08, 0.06, 0.05))

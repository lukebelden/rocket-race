extends Area2D
## The player's rocket. Glides left/right along the bottom of the screen with momentum.
## Has a side booster: hold "boost" for extra speed until the fuel runs out, then it drops off for good.

signal booster_lost(pod_positions: Array)

## Distance from the bottom of the screen (keeps the rocket above the cockpit console).
## game.gd sets it per screen orientation.
var bottom_gap: float = 135.0

@export var max_speed: float = 480.0
## How quickly thrust builds up speed (pixels per second, per second).
@export var acceleration: float = 1500.0
## How quickly the rocket slows when you let go. Lower = longer glide.
@export var glide_drag: float = 2.0
## Boosting mainly makes you fly FORWARD faster (game.gd speeds up the whole world).
## It also gives a little extra sideways agility so you can react at the higher speed.
@export var boost_multiplier: float = 1.25
## Fuel used per second of boosting (fuel goes from 1.0 to 0.0): ~4.5 s per full tank.
@export var boost_drain: float = 0.22

var active: bool = true
## Engine flame size multiplier (the launch intro ramps this up).
var flame_power: float = 1.0
var flame_on: bool = true
var velocity_x: float = 0.0

var has_booster: bool = true
var fuel: float = 1.0
var boosting: bool = false
## Set by the on-screen BOOST button (touch); keyboard uses the "boost" input action.
var boost_button_held: bool = false
## Touches that start inside these rects (on-screen BOOST / MISSILE buttons) don't steer.
var no_steer_rects: Array[Rect2] = []
## Side-to-side speed multiplier (the RCS Jets mod raises it).
var agility: float = 1.0
## Fitted ship mods (set by game.gd) - each one changes how the rocket looks, using the
## same colours as its mod icon. missile_count = missiles left in the Missile Pod.
var mods: Array[String] = []
var missile_count: int = 0
var _time: float = 0.0

const ModInfo := preload("res://mods.gd")
const Animals := preload("res://animals.gd")
const Palette := preload("res://palette.gd")

## Ship sprites (built by art/build_rockets.gd from art/source/rocket_sheet.png).
## Ship id from the catalog ("small" / "medium" / "heavy") picks the sprite set.
var ship: String = "medium":
	set(value):
		ship = value
		queue_redraw()
const SHIP_FILES := {"small": "scout", "medium": "cruiser", "heavy": "hauler"}
const SPRITE_SCALE := 0.2
const FRAMES := 6
## Local y of the nozzle bottoms (sprites hang above it, the flame below).
const NOZZLE_Y := 26.0
## Sprite geometry, in sprite pixels: h = height, boosters = booster centre x offsets,
## fin = outer fin tip x (with boosters) / fin_bare (boosters dropped), flame_w = flame width.
const SHIPS := {
	"scout": {"h": 272, "boosters": [-46.0, 46.0], "fin": 88.0, "fin_bare": 60.0, "flame_w": 0.9},
	"cruiser": {"h": 328, "boosters": [-46.0, 46.0], "fin": 88.0, "fin_bare": 60.0, "flame_w": 1.0},
	"hauler": {"h": 365, "boosters": [-71.0, -46.0, 46.0, 71.0], "fin": 113.0, "fin_bare": 60.0, "flame_w": 1.25},
}
const CORE_HALF := 31.0
const NOZ_HALF := 36.0
const NOSE_ROW := 8
const WINDOW_ROW := 112
const BOOST_TOP_ROW := 104
const HATCH_FROM_BOTTOM := 116
const FLAME_TEX := preload("res://sprites/rockets/flame.png")
const POD_TEX := preload("res://sprites/rockets/booster.png")
const BODY_TEX := {
	"scout": preload("res://sprites/rockets/scout.png"), "scout_bare": preload("res://sprites/rockets/scout_bare.png"),
	"cruiser": preload("res://sprites/rockets/cruiser.png"), "cruiser_bare": preload("res://sprites/rockets/cruiser_bare.png"),
	"hauler": preload("res://sprites/rockets/hauler.png"), "hauler_bare": preload("res://sprites/rockets/hauler_bare.png"),
}
const PAINT_SHADER := """
shader_type canvas_item;
uniform float hue_shift = 0.0;
uniform float sat_mul = 1.0;
uniform float val_mul = 1.0;
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
void fragment() {
	vec4 col = COLOR;  // already the texture x modulate
	vec3 hsv = rgb2hsv(col.rgb);
	float hue_dist = min(hsv.x, 1.0 - hsv.x);  // distance from pure red
	float is_red = (1.0 - smoothstep(0.035, 0.05, hue_dist)) * smoothstep(0.3, 0.42, hsv.y);
	vec3 painted = hsv2rgb(vec3(fract(hsv.x + hue_shift), clamp(hsv.y * sat_mul, 0.0, 1.0), clamp(hsv.z * val_mul, 0.0, 1.0)));
	COLOR = vec4(mix(col.rgb, painted, is_red), col.a);
}
"""
static var _shader: Shader
var _body: Sprite2D
var _flame: Sprite2D
var _anim: float = 0.0

## Paint job (shop "designs") and the animal pilot in the window. Set by game.gd from Profile.
var paint_main := Color("e5683b")
var paint_dark := Color("a8432a")
var paint_body := Color("e6efe9")
var pilot: String = ""

## Screen x position of the finger steering the rocket, or NAN when not touching.
var touch_x: float = NAN
var _steer_finger: int = -1

var _flicker: float = 1.0
var _trail: CPUParticles2D


func _ready() -> void:
	_make_sprites()
	_trail = _make_exhaust_trail()
	add_child(_trail)


func _unhandled_input(event: InputEvent) -> void:
	# Touch steering: the rocket glides toward your finger. Multi-touch aware, so you can
	# steer with one finger while holding BOOST with another.
	if event is InputEventScreenTouch:
		if event.pressed:
			if _steer_finger == -1 and not _on_button(event.position):
				_steer_finger = event.index
				touch_x = event.position.x
		elif event.index == _steer_finger:
			_steer_finger = -1
			touch_x = NAN
	elif event is InputEventScreenDrag and event.index == _steer_finger:
		touch_x = event.position.x


func _process(delta: float) -> void:
	# Stay pinned near the bottom even if the window/browser is resized.
	var screen := get_viewport_rect().size
	position.y = screen.y - bottom_gap

	_time += delta
	_anim += delta * 10.0
	_flicker = randf_range(0.75, 1.2)
	_trail.emitting = flame_on
	queue_redraw()

	if not active:
		velocity_x = 0.0
		boosting = false
		return

	# Booster: burns fuel while held; when the tank runs dry it detaches for good.
	var wants_boost := Input.is_action_pressed("boost") or boost_button_held
	boosting = has_booster and fuel > 0.0 and wants_boost
	if boosting:
		fuel = maxf(fuel - boost_drain * delta, 0.0)
		if fuel <= 0.0:
			_detach_booster()

	var top_speed := max_speed * agility * (boost_multiplier if boosting else 1.0)
	var thrust := acceleration * agility * (boost_multiplier if boosting else 1.0)

	var dir := Input.get_axis("ui_left", "ui_right")
	# A / D by key position (WASD on any layout) AND by the letter printed on the key, so
	# they work on AZERTY, Dvorak and other keyboard layouts too.
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_label_pressed(KEY_A):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_label_pressed(KEY_D):
		dir += 1.0
	dir = clampf(dir, -1.0, 1.0)

	if not is_nan(touch_x):
		# Glide toward the finger: faster when far away, easing in as it gets close.
		var desired := clampf((touch_x - position.x) * 5.0, -top_speed, top_speed)
		velocity_x = move_toward(velocity_x, desired, thrust * 1.4 * delta)
	elif dir != 0.0:
		# Counter-thrust is stronger, so changing direction doesn't feel sluggish.
		var accel := thrust * (1.7 if signf(dir) != signf(velocity_x) else 1.0)
		velocity_x = move_toward(velocity_x, dir * top_speed, accel * delta)
	else:
		# No input: keep gliding and slowly lose speed.
		velocity_x *= exp(-glide_drag * delta)
	# After a boost ends, ease back down to normal top speed instead of snapping.
	if absf(velocity_x) > top_speed:
		velocity_x = move_toward(velocity_x, signf(velocity_x) * top_speed, thrust * delta)

	position.x += velocity_x * delta

	# Soft bounce off the screen edges.
	if position.x < 44.0:
		position.x = 44.0
		velocity_x = absf(velocity_x) * 0.3
	elif position.x > screen.x - 44.0:
		position.x = screen.x - 44.0
		velocity_x = -absf(velocity_x) * 0.3

	# Bank into the movement.
	rotation = lerpf(rotation, velocity_x / max_speed * 0.32, 8.0 * delta)


func _on_button(at: Vector2) -> bool:
	for rect in no_steer_rects:
		if rect.has_point(at):
			return true
	return false


## Fill the tank back up (refuel station). Does nothing once the booster has fallen off.
func refuel() -> bool:
	if not has_booster:
		return false
	fuel = 1.0
	return true


func _detach_booster() -> void:
	has_booster = false
	boosting = false
	fuel = 0.0
	var g: Dictionary = SHIPS[_ship_file()]
	var mid := _px(0, (BOOST_TOP_ROW + int(g["h"])) / 2).y
	var spots := []
	for bx in g["boosters"]:
		spots.append(to_global(Vector2(float(bx) * SPRITE_SCALE, mid)))
	booster_lost.emit(spots)


func _draw() -> void:
	_sync_sprites()
	var g: Dictionary = SHIPS[_ship_file()]
	var thruster := mods.has("thruster")
	var core := CORE_HALF * SPRITE_SCALE

	# Booster pods fire blue-white flames while boosting.
	if has_booster and boosting:
		for bx in g["boosters"]:
			var x: float = float(bx) * SPRITE_SCALE
			var bf := _flicker * 1.2
			draw_colored_polygon(PackedVector2Array([Vector2(x - 3, NOZZLE_Y), Vector2(x + 3, NOZZLE_Y), Vector2(x, NOZZLE_Y + 2 + 24 * bf)]), Color(Palette.AQUA, 0.9))
			draw_colored_polygon(PackedVector2Array([Vector2(x - 1.5, NOZZLE_Y), Vector2(x + 1.5, NOZZLE_Y), Vector2(x, NOZZLE_Y + 1 + 13 * bf)]), Palette.MIST)

	# Bigger Thruster: glowing rim across the engine bells.
	if thruster:
		var tc: Color = ModInfo.MODS["thruster"]["color"]
		draw_line(Vector2(-NOZ_HALF * SPRITE_SCALE - 1, NOZZLE_Y), Vector2(NOZ_HALF * SPRITE_SCALE + 1, NOZZLE_Y), tc, 2.5)

	# Missile Pod: a pylon wing on each fin tip with a missile hung on its outer side
	# (left one fires first; both pylons stay, empty, when you're out of missiles).
	if mods.has("missile"):
		var fin: float = float(g["fin"] if has_booster else g["fin_bare"]) * SPRITE_SCALE + 1.5
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			_draw_pylon(fin * s, s)
			if missile_count > 1 - i:
				draw_missile(self, Vector2(fin * s + s * 4.6, 13.0), 0.95)

	# Radar: a thin mast on the nose tip with a blinking light, plus a little side antenna
	# (round mount, rod, light tip) sticking out of the nose cone.
	if mods.has("radar"):
		var rc: Color = ModInfo.MODS["radar"]["color"]
		var nose := _px(0, NOSE_ROW).y
		var on := fmod(_time, 1.0) < 0.5
		draw_line(Vector2(0, nose + 1), Vector2(0, nose - 12), Color("6b7682"), 1.4)
		draw_line(Vector2(-0.35, nose + 1), Vector2(-0.35, nose - 12), Color("a9b5c1"), 0.6)
		if on:
			draw_circle(Vector2(0, nose - 13.5), 4.0, Color(rc, 0.25))
		draw_rect(Rect2(-1.6, nose - 15.5, 3.2, 3.6), rc if on else rc.darkened(0.55))
		draw_rect(Rect2(-1.6, nose - 15.5, 1.4, 3.6), Color(1, 1, 1, 0.35 if on else 0.15))
		var base := _px(-15, NOSE_ROW + 30)
		var tip := base + Vector2(-5.5, -9.0)
		draw_line(base, tip, Color("6b7682"), 1.3)
		draw_line(tip.lerp(base, 0.28), tip, Color("b4c0cc"), 2.2)
		draw_circle(base, 2.3, Color("b4c0cc"))
		draw_circle(base, 1.1, Color("5b6470"))

	# Reinforced Hull: bolted steel armour plates down both sides of the core.
	if mods.has("hull"):
		var hc: Color = ModInfo.MODS["hull"]["color"]
		var top := _px(0, WINDOW_ROW + 18).y
		var bottom := _px(0, int(g["h"]) - 70).y
		for s in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(minf(s * (core - 2.2), s * (core + 0.8)), top), Vector2(3.0, bottom - top)), hc.darkened(0.25))
			var y := top + 4.0
			while y < bottom - 2.0:
				draw_circle(Vector2(s * (core - 0.7), y), 0.9, hc.darkened(0.55))
				y += 8.0

	# RCS Jets: thruster nubs on the core under the nose that puff when you steer.
	if mods.has("rcs"):
		var cc: Color = ModInfo.MODS["rcs"]["color"]
		var ry := _px(0, BOOST_TOP_ROW - 4).y
		for s in [-1.0, 1.0]:
			draw_rect(Rect2(s * (core + 1.0) - 1.5, ry, 3, 5), cc)
		# Moving right fires the left jet (it pushes you right), and vice versa.
		if absf(velocity_x) > 40.0 and active:
			var s := -1.0 if velocity_x > 0.0 else 1.0
			var length := 6.0 + 6.0 * _flicker * clampf(absf(velocity_x) / max_speed, 0.3, 1.0)
			draw_colored_polygon(PackedVector2Array([Vector2((core + 2.5) * s, ry + 0.5), Vector2((core + 2.5 + length) * s, ry + 2.5), Vector2((core + 2.5) * s, ry + 4.5)]), Color(cc.lightened(0.4), 0.85))

	# Healing Panel: a pulsing green repair cross over the hatch.
	if mods.has("healing"):
		var gc: Color = ModInfo.MODS["healing"]["color"]
		var pulse := 0.75 + 0.25 * sin(_time * 4.0)
		var dark := gc.darkened(0.55)
		var c := _px(0, int(g["h"]) - HATCH_FROM_BOTTOM)
		draw_circle(c, 6.5, Color(gc, 0.3 * pulse))  # soft glow
		draw_rect(Rect2(c + Vector2(-2.2, -4.8), Vector2(4.4, 9.6)), dark)  # dark outline so it reads on the white hull
		draw_rect(Rect2(c + Vector2(-4.8, -2.2), Vector2(9.6, 4.4)), dark)
		draw_rect(Rect2(c + Vector2(-1.3, -3.9), Vector2(2.6, 7.8)), gc.lightened(0.2 * pulse))
		draw_rect(Rect2(c + Vector2(-3.9, -1.3), Vector2(7.8, 2.6)), gc.lightened(0.2 * pulse))


## Sprite pixel (x from the rocket's centre line, y = row from the sprite's top) -> local position.
func _px(x: float, row: int) -> Vector2:
	var h: float = SHIPS[_ship_file()]["h"]
	return Vector2(x * SPRITE_SCALE, NOZZLE_Y - (h - row) * SPRITE_SCALE)


func _ship_file() -> String:
	return SHIP_FILES.get(ship, "cruiser")


## Builds the flame + body sprites (drawn behind this node's own mod overlays).
func _make_sprites() -> void:
	_flame = Sprite2D.new()
	_flame.texture = FLAME_TEX
	_flame.hframes = FRAMES
	_flame.centered = false
	_flame.show_behind_parent = true
	_flame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_flame)
	_body = Sprite2D.new()
	_body.hframes = FRAMES
	_body.centered = false
	_body.show_behind_parent = true
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var m := ShaderMaterial.new()
	m.shader = _paint_shader()
	_body.material = m
	add_child(_body)


func _sync_sprites() -> void:
	if _body == null:
		return
	var file := _ship_file()
	var g: Dictionary = SHIPS[file]
	var tex: Texture2D = BODY_TEX[file + ("" if has_booster else "_bare")]
	if _body.texture != tex:
		_body.texture = tex
	var frame := int(_anim) % FRAMES
	_body.frame = frame
	var fw := float(tex.get_width()) / FRAMES
	_body.scale = Vector2.ONE * SPRITE_SCALE
	_body.position = Vector2(-fw * 0.5 * SPRITE_SCALE, NOZZLE_Y - float(g["h"]) * SPRITE_SCALE)
	# Paint job: recolour the red parts towards the design colour (Classic = as drawn).
	var base := Color("e5683b")
	var mat := _body.material as ShaderMaterial
	mat.set_shader_parameter("hue_shift", paint_main.h - base.h)
	mat.set_shader_parameter("sat_mul", paint_main.s / base.s)
	mat.set_shader_parameter("val_mul", paint_main.v / base.v)
	# Engine flame: flickers, bigger while boosting and with the Bigger Thruster mod.
	_flame.visible = flame_on
	_flame.frame = frame
	var thruster := mods.has("thruster")
	var f := flame_power * _flicker * (1.5 if boosting else 1.0) * (1.3 if thruster else 1.0)
	var w: float = float(g["flame_w"]) * (1.35 if thruster else 1.0)
	_flame.scale = Vector2(SPRITE_SCALE * w, SPRITE_SCALE * clampf(f, 0.05, 3.0))
	_flame.position = Vector2(-96.0 * SPRITE_SCALE * w, NOZZLE_Y - 1.0)


static func _paint_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = PAINT_SHADER
	return _shader


## Missile pylon on a fin tip (s = -1 left, +1 right): grey wing plate angled down from the
## fin, an upright post with a red stripe and red tip, and a mounting bolt.
func _draw_pylon(x: float, s: float) -> void:
	var light := Color("a9b5c1")
	var mid := Color("8794a2")
	var dark := Color("5f6a77")
	var red := Color("c8283a")
	var plate := PackedVector2Array([Vector2(x - s * 3.5, 15), Vector2(x + s * 1.5, 11), Vector2(x + s * 1.5, 25), Vector2(x - s * 3.5, 23)])
	draw_colored_polygon(plate, mid)
	draw_colored_polygon(PackedVector2Array([plate[3], plate[2], Vector2(x + s * 1.5, 26.2), Vector2(x - s * 3.5, 24.2)]), dark)
	draw_line(plate[0], plate[1], light, 1.0)
	draw_circle(Vector2(x - s * 1.4, 18.5), 1.0, Color("4d5663"))
	var px := x + s * 1.5
	draw_rect(Rect2(px - 1.4, 4, 2.8, 22), light)
	draw_rect(Rect2(px + 0.2, 4, 1.2, 22), dark)
	draw_rect(Rect2(px - 1.4, 9, 2.8, 8), red)
	draw_rect(Rect2(px - 1.4, 9, 1.0, 8), red.lightened(0.25))
	draw_rect(Rect2(px - 1.4, 3, 2.8, 2.2), red.lightened(0.15))


## One missile pointing up (-y), centred on `at`: shaded grey body with a rounded nose, two
## red bands, a centre fin and two dark swept fins. Used on the pylons and in flight.
static func draw_missile(canvas: CanvasItem, at: Vector2, k: float = 1.0) -> void:
	var light := Color("b9c6d2")
	var dark := Color("7d8a98")
	var fin := Color("5b6470")
	var red := Color("c8283a")
	var p := func(x: float, y: float) -> Vector2: return at + Vector2(x, y) * k
	# swept fins (behind the body)
	for s in [-1.0, 1.0]:
		canvas.draw_colored_polygon(PackedVector2Array([p.call(s * 2.6, 3.0), p.call(s * 6.5, 8.5), p.call(s * 6.5, 10.5), p.call(s * 2.6, 9.0)]), fin)
	# body: lit left half, shaded right half, rounded nose
	var nose := PackedVector2Array()
	for i in 9:
		var a := PI + PI * i / 8.0
		nose.append(p.call(cos(a) * 3.0, -7.0 + sin(a) * 5.5))
	var body := PackedVector2Array(nose)
	body.append(p.call(3.0, 9.5))
	body.append(p.call(-3.0, 9.5))
	canvas.draw_colored_polygon(body, dark)
	var lit := PackedVector2Array()
	for i in 5:
		lit.append(nose[i])
	lit.append(p.call(0.4, 9.5))
	lit.append(p.call(-3.0, 9.5))
	canvas.draw_colored_polygon(lit, light)
	canvas.draw_line(p.call(-2.0, -8.5), p.call(-2.0, 7.5), Color(1, 1, 1, 0.35), 0.8 * k)
	# red bands
	for band in [[-3.6, 2.6], [0.4, 1.4]]:
		canvas.draw_rect(Rect2(p.call(-3.0, band[0]), Vector2(6.0, band[1]) * k), red)
		canvas.draw_rect(Rect2(p.call(-3.0, band[0]), Vector2(2.4, band[1]) * k), red.lightened(0.2))
	# centre fin + exhaust nub
	canvas.draw_rect(Rect2(p.call(-0.6, 4.0), Vector2(1.2, 6.5) * k), fin)
	canvas.draw_rect(Rect2(p.call(-1.8, 9.5), Vector2(3.6, 1.2) * k), Color("3a4256"))


## One detached booster pod (game.gd draws them tumbling away). Centred on `at`.
static func draw_pod(canvas: CanvasItem, at: Vector2) -> void:
	var size := Vector2(POD_TEX.get_size()) * SPRITE_SCALE
	canvas.draw_texture_rect(POD_TEX, Rect2(at - size * 0.5, size), false)


## Little sparks streaming out of the engine (left behind in space as the rocket moves).
func _make_exhaust_trail() -> CPUParticles2D:
	var trail := CPUParticles2D.new()
	trail.position = Vector2(0, 26)
	trail.show_behind_parent = true
	trail.local_coords = false
	trail.amount = 36
	trail.lifetime = 0.55
	trail.direction = Vector2(0, 1)
	trail.spread = 14.0
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 170.0
	trail.initial_velocity_max = 260.0
	trail.scale_amount_min = 2.0
	trail.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.4, 1.0))
	ramp.set_color(1, Color(0.9, 0.3, 0.1, 0.0))
	ramp.add_point(0.4, Color(1.0, 0.55, 0.15, 0.8))
	trail.color_ramp = ramp
	trail.emitting = false
	return trail

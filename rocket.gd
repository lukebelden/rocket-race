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

## Paint job (shop "designs") and the animal pilot in the window. Set by game.gd from Profile.
var paint_main := Color(0.86, 0.2, 0.2)
var paint_dark := Color(0.6, 0.1, 0.12)
var paint_body := Color(0.95, 0.96, 0.98)
var pilot: String = ""

## Screen x position of the finger steering the rocket, or NAN when not touching.
var touch_x: float = NAN
var _steer_finger: int = -1

var _flicker: float = 1.0
var _trail: CPUParticles2D


func _ready() -> void:
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
	booster_lost.emit([to_global(Vector2(-17, 6)), to_global(Vector2(17, 6))])


func _draw() -> void:
	var red := paint_main
	var dark_red := paint_dark
	var white := paint_body
	var shade := paint_body.darkened(0.18)

	var thruster := mods.has("thruster")

	# Engine flame: layered outer / inner / core, flickering. Bigger while boosting, and
	# wider/longer with the Bigger Thruster mod.
	if flame_on:
		var f := flame_power * _flicker * (1.5 if boosting else 1.0) * (1.3 if thruster else 1.0)
		var w := 1.4 if thruster else 1.0
		var y0 := 27.0 if thruster else 22.0
		draw_colored_polygon(PackedVector2Array([Vector2(-9 * w, y0), Vector2(9 * w, y0), Vector2(4 * w, y0 + 16 * f), Vector2(0, y0 + 2 + 30 * f), Vector2(-4 * w, y0 + 16 * f)]), Color(1.0, 0.45, 0.1, 0.9))
		draw_colored_polygon(PackedVector2Array([Vector2(-6 * w, y0), Vector2(6 * w, y0), Vector2(0, y0 + 1 + 20 * f)]), Color(1.0, 0.82, 0.25))
		draw_colored_polygon(PackedVector2Array([Vector2(-3 * w, y0), Vector2(3 * w, y0), Vector2(0, y0 + 1 + 9 * f)]), Color(1, 1, 0.9))

	# Booster pod flames (blue-white, hotter looking).
	if has_booster and boosting:
		for s in [-1.0, 1.0]:
			var x: float = 17.0 * s
			var bf := _flicker * 1.2
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4, 22), Vector2(x + 4, 22), Vector2(x, 24 + 26 * bf)]), Color(0.45, 0.75, 1.0, 0.85))
			draw_colored_polygon(PackedVector2Array([Vector2(x - 2, 22), Vector2(x + 2, 22), Vector2(x, 23 + 14 * bf)]), Color(0.9, 0.97, 1.0))

	# Nozzle (Bigger Thruster: a wider engine bell with a glowing orange rim).
	if thruster:
		var tc: Color = ModInfo.MODS["thruster"]["color"]
		draw_colored_polygon(PackedVector2Array([Vector2(-8, 16), Vector2(8, 16), Vector2(13, 27), Vector2(-13, 27)]), Color(0.26, 0.27, 0.31))
		draw_line(Vector2(-11, 22), Vector2(11, 22), Color(0.45, 0.47, 0.52), 1.5)
		draw_line(Vector2(-13, 27), Vector2(13, 27), tc, 2.5)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(-7, 17), Vector2(7, 17), Vector2(9, 24), Vector2(-9, 24)]), Color(0.3, 0.32, 0.36))
		draw_line(Vector2(-8, 21), Vector2(8, 21), Color(0.45, 0.47, 0.52), 1.5)

	# Side fins (with a darker lower edge).
	for side in [-1.0, 1.0]:
		var s: float = side
		draw_colored_polygon(PackedVector2Array([Vector2(10 * s, -2), Vector2(23 * s, 18), Vector2(23 * s, 27), Vector2(10 * s, 19)]), red)
		draw_colored_polygon(PackedVector2Array([Vector2(23 * s, 22), Vector2(23 * s, 27), Vector2(10 * s, 19), Vector2(10 * s, 15)]), dark_red)

	# Missile Pod: launch rails on the fin tips with the loaded missiles on them
	# (left rail empties first; both empty when you're out of missiles).
	if mods.has("missile"):
		var mc: Color = ModInfo.MODS["missile"]["color"]
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			var x := 27.0 * s
			draw_rect(Rect2(x - 1.5, 4, 3, 22), Color(0.3, 0.32, 0.36))
			if missile_count > 1 - i:
				draw_rect(Rect2(x - 2.2, 2, 4.4, 15), Color(0.93, 0.94, 0.97))
				draw_colored_polygon(PackedVector2Array([Vector2(x - 2.2, 2), Vector2(x + 2.2, 2), Vector2(x, -4)]), mc)
				draw_colored_polygon(PackedVector2Array([Vector2(x - 2.2, 13), Vector2(x - 4.5, 18), Vector2(x - 2.2, 17)]), mc.darkened(0.3))
				draw_colored_polygon(PackedVector2Array([Vector2(x + 2.2, 13), Vector2(x + 4.5, 18), Vector2(x + 2.2, 17)]), mc.darkened(0.3))

	# Booster pods strapped to the sides.
	if has_booster:
		for side in [-1.0, 1.0]:
			_draw_pod(Vector2(17.0 * side, 6.0))

	# Body with shading on the right side.
	draw_colored_polygon(PackedVector2Array([Vector2(0, -34), Vector2(6, -27), Vector2(9, -18), Vector2(10, -8), Vector2(10, 18), Vector2(-10, 18), Vector2(-10, -8), Vector2(-9, -18), Vector2(-6, -27)]), white)
	draw_colored_polygon(PackedVector2Array([Vector2(4, -29), Vector2(9, -18), Vector2(10, -8), Vector2(10, 18), Vector2(5, 18), Vector2(5, -20)]), shade)

	# Nose cone.
	draw_colored_polygon(PackedVector2Array([Vector2(0, -34), Vector2(6, -27), Vector2(9, -19), Vector2(-9, -19), Vector2(-6, -27)]), red)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -34), Vector2(6, -27), Vector2(9, -19), Vector2(3, -19)]), dark_red)

	# Radar: antenna mast and dish on the nose, with a blinking beacon.
	if mods.has("radar"):
		var rc: Color = ModInfo.MODS["radar"]["color"]
		draw_line(Vector2(0, -34), Vector2(0, -45), Color(0.6, 0.63, 0.7), 1.5)
		draw_arc(Vector2(0, -41), 7.0, PI * 1.15, PI * 1.85, 10, rc, 2.0, true)
		draw_circle(Vector2(0, -46), 1.8, rc if fmod(_time, 1.0) < 0.5 else rc.darkened(0.6))

	# Reinforced Hull: bolted steel armour plates along both sides of the body.
	if mods.has("hull"):
		var hc: Color = ModInfo.MODS["hull"]["color"]
		for s in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([Vector2(11 * s, -13), Vector2(7 * s, -15), Vector2(7 * s, 17), Vector2(11 * s, 18)]), hc.darkened(0.25))
			draw_line(Vector2(7 * s, -15), Vector2(7 * s, 17), hc.darkened(0.5), 1.0)
			for ry in [-9.0, 1.0, 11.0]:
				draw_circle(Vector2(9 * s, ry), 1.0, hc.darkened(0.55))

	# RCS Jets: small thruster nubs on the sides that puff when you steer.
	if mods.has("rcs"):
		var cc: Color = ModInfo.MODS["rcs"]["color"]
		for s in [-1.0, 1.0]:
			draw_rect(Rect2(10.5 * s - 1.5, -17, 3, 5), cc)
		# Moving right fires the left jet (it pushes you right), and vice versa.
		if absf(velocity_x) > 40.0 and active:
			var s := -1.0 if velocity_x > 0.0 else 1.0
			var length := 6.0 + 6.0 * _flicker * clampf(absf(velocity_x) / max_speed, 0.3, 1.0)
			draw_colored_polygon(PackedVector2Array([Vector2(12 * s, -16.5), Vector2((12 + length) * s, -14.5), Vector2(12 * s, -12.5)]), Color(cc.lightened(0.4), 0.85))

	# Panel line and red band.
	draw_line(Vector2(-10, 2), Vector2(10, 2), Color(0.6, 0.63, 0.7), 1.0)
	draw_rect(Rect2(-10, 10, 20, 4), red)

	# Porthole window with a rim and glint (and your animal pilot looking out).
	if pilot != "":
		draw_circle(Vector2(0, -8), 8.5, Color(0.55, 0.58, 0.65))
		draw_circle(Vector2(0, -8), 7.2, Color(0.55, 0.78, 1.0))
		Animals.draw_face(self, Vector2(0, -7.5), 5.4, pilot)
		draw_arc(Vector2(0, -8), 6.4, PI * 1.1, PI * 1.45, 6, Color(1, 1, 1, 0.75), 1.2)
	else:
		draw_circle(Vector2(0, -7), 6.5, Color(0.55, 0.58, 0.65))
		draw_circle(Vector2(0, -7), 5.0, Color(0.2, 0.55, 0.95))
		draw_circle(Vector2(1.5, -5.5), 2.5, Color(0.12, 0.35, 0.75))
		draw_circle(Vector2(-1.8, -8.8), 1.6, Color(1, 1, 1, 0.9))

	# Healing Panel: a pulsing green repair cross on the hull.
	if mods.has("healing"):
		var gc: Color = ModInfo.MODS["healing"]["color"]
		var pulse := 0.75 + 0.25 * sin(_time * 4.0)
		var dark := gc.darkened(0.55)
		draw_circle(Vector2(0, 6), 6.5, Color(gc, 0.3 * pulse))  # soft glow
		draw_rect(Rect2(-2.2, 1.2, 4.4, 9.6), dark)  # dark outline so it reads on the white hull
		draw_rect(Rect2(-4.8, 3.8, 9.6, 4.4), dark)
		draw_rect(Rect2(-1.3, 2.1, 2.6, 7.8), gc.lightened(0.2 * pulse))
		draw_rect(Rect2(-3.9, 4.7, 7.8, 2.6), gc.lightened(0.2 * pulse))

	# Centre fin (in front of the body).
	draw_colored_polygon(PackedVector2Array([Vector2(-1.8, 6), Vector2(1.8, 6), Vector2(1.8, 26), Vector2(-1.8, 26)]), dark_red)


## One booster pod (also used by game.gd to draw the detached pods tumbling away).
func _draw_pod(at: Vector2) -> void:
	draw_pod(self, at)


static func draw_pod(canvas: CanvasItem, at: Vector2) -> void:
	var body := Color(0.88, 0.62, 0.2)
	var dark := Color(0.62, 0.4, 0.12)
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-4, -14), at + Vector2(0, -20), at + Vector2(4, -14)]), Color(0.9, 0.9, 0.92))
	canvas.draw_rect(Rect2(at + Vector2(-4, -14), Vector2(8, 28)), body)
	canvas.draw_rect(Rect2(at + Vector2(1, -14), Vector2(3, 28)), dark)
	canvas.draw_rect(Rect2(at + Vector2(-4, -6), Vector2(8, 3)), Color(0.25, 0.25, 0.28))
	canvas.draw_rect(Rect2(at + Vector2(-4, 6), Vector2(8, 3)), Color(0.25, 0.25, 0.28))
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-3, 14), at + Vector2(3, 14), at + Vector2(4, 17), at + Vector2(-4, 17)]), Color(0.3, 0.32, 0.36))


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

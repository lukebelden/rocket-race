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
## Touches that start inside this rect (the BOOST button) don't steer.
var no_steer_rect: Rect2 = Rect2()

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
			if _steer_finger == -1 and not no_steer_rect.has_point(event.position):
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

	var top_speed := max_speed * (boost_multiplier if boosting else 1.0)
	var thrust := acceleration * (boost_multiplier if boosting else 1.0)

	var dir := Input.get_axis("ui_left", "ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
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
	var red := Color(0.86, 0.2, 0.2)
	var dark_red := Color(0.6, 0.1, 0.12)
	var white := Color(0.95, 0.96, 0.98)
	var shade := Color(0.75, 0.78, 0.84)

	# Engine flame: layered outer / inner / core, flickering. Bigger while boosting.
	if flame_on:
		var f := flame_power * _flicker * (1.5 if boosting else 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-9, 22), Vector2(9, 22), Vector2(4, 22 + 16 * f), Vector2(0, 24 + 30 * f), Vector2(-4, 22 + 16 * f)]), Color(1.0, 0.45, 0.1, 0.9))
		draw_colored_polygon(PackedVector2Array([Vector2(-6, 22), Vector2(6, 22), Vector2(0, 23 + 20 * f)]), Color(1.0, 0.82, 0.25))
		draw_colored_polygon(PackedVector2Array([Vector2(-3, 22), Vector2(3, 22), Vector2(0, 23 + 9 * f)]), Color(1, 1, 0.9))

	# Booster pod flames (blue-white, hotter looking).
	if has_booster and boosting:
		for s in [-1.0, 1.0]:
			var x: float = 17.0 * s
			var bf := _flicker * 1.2
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4, 22), Vector2(x + 4, 22), Vector2(x, 24 + 26 * bf)]), Color(0.45, 0.75, 1.0, 0.85))
			draw_colored_polygon(PackedVector2Array([Vector2(x - 2, 22), Vector2(x + 2, 22), Vector2(x, 23 + 14 * bf)]), Color(0.9, 0.97, 1.0))

	# Nozzle.
	draw_colored_polygon(PackedVector2Array([Vector2(-7, 17), Vector2(7, 17), Vector2(9, 24), Vector2(-9, 24)]), Color(0.3, 0.32, 0.36))
	draw_line(Vector2(-8, 21), Vector2(8, 21), Color(0.45, 0.47, 0.52), 1.5)

	# Side fins (with a darker lower edge).
	for side in [-1.0, 1.0]:
		var s: float = side
		draw_colored_polygon(PackedVector2Array([Vector2(10 * s, -2), Vector2(23 * s, 18), Vector2(23 * s, 27), Vector2(10 * s, 19)]), red)
		draw_colored_polygon(PackedVector2Array([Vector2(23 * s, 22), Vector2(23 * s, 27), Vector2(10 * s, 19), Vector2(10 * s, 15)]), dark_red)

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

	# Panel line and red band.
	draw_line(Vector2(-10, 2), Vector2(10, 2), Color(0.6, 0.63, 0.7), 1.0)
	draw_rect(Rect2(-10, 10, 20, 4), red)

	# Porthole window with a rim and glint.
	draw_circle(Vector2(0, -7), 6.5, Color(0.55, 0.58, 0.65))
	draw_circle(Vector2(0, -7), 5.0, Color(0.2, 0.55, 0.95))
	draw_circle(Vector2(1.5, -5.5), 2.5, Color(0.12, 0.35, 0.75))
	draw_circle(Vector2(-1.8, -8.8), 1.6, Color(1, 1, 1, 0.9))

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

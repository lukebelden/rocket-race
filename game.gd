extends Node2D
## Rocket Dodge: steer the rocket and avoid the falling asteroids.

const Obstacle := preload("res://obstacle.gd")

enum State { READY, PLAYING, OVER }

@export var start_spawn_interval: float = 0.9
@export var min_spawn_interval: float = 0.25
@export var start_fall_speed: float = 220.0

## Kept across restarts while the game is running.
static var best_score: float = 0.0

var state: State = State.READY
var score: float = 0.0
var elapsed: float = 0.0
var spawn_timer: float = 0.0
var over_time: float = 0.0  # seconds since crashing
var stars: Array[Vector3] = []  # x, y, speed
## Show tap instructions on phones/tablets (native or in a mobile browser).
var touch_ui: bool = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

@onready var rocket: Area2D = $Rocket
@onready var obstacles: Node2D = $Obstacles
@onready var score_label: Label = $UI/ScoreLabel
@onready var message_label: Label = $UI/MessageLabel


func _ready() -> void:
	randomize()
	_update_layout()
	get_window().size_changed.connect(_update_layout)
	var size := get_viewport_rect().size
	rocket.position = Vector2(size.x / 2.0, size.y - 90.0)
	rocket.area_entered.connect(_on_rocket_hit)

	for i in 120:
		stars.append(Vector3(randf() * size.x, randf() * size.y, randf_range(20.0, 120.0)))

	if touch_ui:
		_show_message("ROCKET DODGE\n\nHold and drag to steer\nTap to launch")
	else:
		_show_message("ROCKET DODGE\n\nMove: Left / Right or A / D\nPress Space to launch")
	_update_score_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_on_launch_pressed()


func _process(delta: float) -> void:
	_update_stars(delta)

	if Input.is_action_just_pressed("ui_accept"):
		_on_launch_pressed()

	match state:
		State.OVER:
			over_time += delta
		State.PLAYING:
			elapsed += delta
			score += delta * 10.0
			_update_score_label()

			spawn_timer -= delta
			if spawn_timer <= 0.0:
				_spawn_obstacle()
				# Asteroids come faster the longer you survive.
				spawn_timer = maxf(min_spawn_interval, start_spawn_interval - elapsed * 0.02)


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.08))
	for s in stars:
		var b := remap(s.z, 20.0, 120.0, 0.3, 1.0)
		draw_circle(Vector2(s.x, s.y), 0.8 + b, Color(b, b, b))


## Use a tall base resolution on portrait screens (phones) so things aren't tiny.
func _update_layout() -> void:
	var window := get_window()
	var portrait := window.size.y > window.size.x
	window.content_scale_size = Vector2i(648, 1152) if portrait else Vector2i(1152, 648)


## Space / Enter / tap: launch from the title screen, or restart after crashing.
func _on_launch_pressed() -> void:
	match state:
		State.READY:
			_start()
		State.OVER:
			# Short pause so a finger still on the screen doesn't restart instantly.
			if over_time > 0.6:
				get_tree().reload_current_scene()


func _start() -> void:
	state = State.PLAYING
	message_label.visible = false


func _spawn_obstacle() -> void:
	var size := get_viewport_rect().size
	var radius := randf_range(18.0, 46.0)

	var rock := Obstacle.new()
	rock.fall_speed = start_fall_speed + elapsed * 8.0 + randf_range(0.0, 140.0)
	rock.spin = randf_range(-2.0, 2.0)
	rock.position = Vector2(randf_range(radius, size.x - radius), -radius)

	var shape := CircleShape2D.new()
	shape.radius = radius * 0.85  # slightly forgiving hitbox
	var collision := CollisionShape2D.new()
	collision.shape = shape
	rock.add_child(collision)

	var body := Polygon2D.new()
	body.polygon = _rock_points(radius)
	var shade := randf_range(0.35, 0.55)
	body.color = Color(shade + 0.1, shade, shade - 0.05)
	rock.add_child(body)

	obstacles.add_child(rock)


func _rock_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := randi_range(7, 11)
	for i in count:
		var angle := TAU * i / count
		points.append(Vector2.from_angle(angle) * radius * randf_range(0.75, 1.1))
	return points


func _update_stars(delta: float) -> void:
	var size := get_viewport_rect().size
	for i in stars.size():
		var s := stars[i]
		s.y += s.z * delta
		if s.y > size.y:
			s.y = 0.0
			s.x = randf() * size.x
		stars[i] = s
	queue_redraw()


func _on_rocket_hit(_area: Area2D) -> void:
	if state != State.PLAYING:
		return
	state = State.OVER
	rocket.active = false
	rocket.modulate = Color(1.0, 0.4, 0.3)
	rocket.get_node("Flame").visible = false
	best_score = maxf(best_score, score)
	var again := "Tap to try again" if touch_ui else "Press Space to try again"
	_show_message("CRASH!\n\nScore: %d    Best: %d\n%s" % [int(score), int(best_score), again])


func _show_message(text: String) -> void:
	message_label.text = text
	message_label.visible = true


func _update_score_label() -> void:
	score_label.text = "Score: %d" % int(score)

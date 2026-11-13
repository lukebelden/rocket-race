extends Area2D
## The player's rocket. Moves left/right along the bottom of the screen.

@export var speed: float = 520.0

var active: bool = true

## Screen x position of the finger steering the rocket, or NAN when not touching.
var touch_x: float = NAN

@onready var flame: Polygon2D = $Flame


func _unhandled_input(event: InputEvent) -> void:
	# Touch steering: the rocket follows your finger left/right.
	if event is InputEventScreenTouch:
		touch_x = event.position.x if event.pressed else NAN
	elif event is InputEventScreenDrag:
		touch_x = event.position.x


func _process(delta: float) -> void:
	# Stay pinned near the bottom even if the window/browser is resized.
	var screen := get_viewport_rect().size
	position.y = screen.y - 90.0

	if not active:
		return

	var dir := Input.get_axis("ui_left", "ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir += 1.0
	if not is_nan(touch_x):
		# Full speed when far from the finger, easing in as it gets close (no jitter).
		dir += (touch_x - position.x) / 40.0
	dir = clampf(dir, -1.0, 1.0)

	position.x += dir * speed * delta
	position.x = clampf(position.x, 24.0, screen.x - 24.0)

	# Lean into the turn and flicker the engine flame.
	rotation = lerpf(rotation, dir * 0.3, 10.0 * delta)
	flame.scale.y = randf_range(0.7, 1.25)

extends MeshInstance3D

## Spin speed in degrees per second.
@export var spin_speed: float = 90.0


func _process(delta: float) -> void:
	rotate_y(deg_to_rad(spin_speed) * delta)

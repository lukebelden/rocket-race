extends Area2D
## A falling asteroid. Created in code by game.gd.

var fall_speed: float = 250.0
var spin: float = 0.0


func _process(delta: float) -> void:
	position.y += fall_speed * delta
	rotation += spin * delta
	if position.y > get_viewport_rect().size.y + 100.0:
		queue_free()

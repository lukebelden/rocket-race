extends Control
## MASTER CAUTION warning lamp on the console. Blinks red while `on`.
## Only redraws when the lamp actually switches between lit and dark.

var on: bool = false
var _time: float = 0.0
var _lit: bool = false


func _process(delta: float) -> void:
	_time += delta
	var lit := on and fmod(_time, 0.6) < 0.38
	if lit != _lit:
		_lit = lit
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	draw_circle(c, r + 3.0, Color(0.05, 0.05, 0.07))  # bezel
	draw_arc(c, r + 3.0, 0.0, TAU, 32, Color(0.45, 0.48, 0.55), 1.5, true)
	if _lit:
		draw_circle(c, r * 2.2, Color(1.0, 0.2, 0.1, 0.18))  # glow
		draw_circle(c, r * 1.5, Color(1.0, 0.25, 0.12, 0.25))
		draw_circle(c, r, Color(1.0, 0.28, 0.15))
		draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1, 0.85, 0.75, 0.9))
	else:
		draw_circle(c, r, Color(0.28, 0.06, 0.05))
		draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.3, Color(1, 1, 1, 0.12))

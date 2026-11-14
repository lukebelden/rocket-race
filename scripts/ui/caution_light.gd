extends Control

const Palette := preload("res://scripts/game/palette.gd")
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
	draw_circle(c, r + 3.0, Palette.INK)  # bezel
	if _lit:
		Palette.glow(self, c, r * 2.4, Palette.BAD, 1.4)
		draw_circle(c, r, Palette.BAD)
		draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.3, Color(1, 0.9, 0.85, 0.8))
	else:
		draw_circle(c, r, Palette.RUST.darkened(0.6))

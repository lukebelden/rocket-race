extends Node2D
## One scrolling background layer (stars, or faint nebula clouds).
## Its contents are drawn once; scrolling just moves the node and wraps around, drawing a
## second copy one screen-height above so there's never a gap. Much cheaper than redrawing
## every star every frame.

enum Kind { STARS, NEBULA }

var kind: Kind = Kind.STARS
var count: int = 50
var speed: float = 40.0
## Star dot radius range and brightness range.
var size_range: Vector2 = Vector2(0.8, 1.4)
var brightness: Vector2 = Vector2(0.4, 0.8)
## Multiplies scroll speed (the launch intro speeds stars up).
var speed_scale: float = 1.0
var twinkle_rate: float = 1.0

static var glow_tex: Texture2D

var _height: float = 648.0
var _items: Array = []
var _time: float = 0.0


## (Re)build the layer for a screen size.
func build(screen: Vector2) -> void:
	_height = screen.y
	_items.clear()
	for i in count:
		var pos := Vector2(randf() * screen.x, randf() * screen.y)
		if kind == Kind.STARS:
			var b := randf_range(brightness.x, brightness.y)
			_items.append([pos, randf_range(size_range.x, size_range.y), Color(b, b, minf(b + 0.08, 1.0))])
		else:
			var colors := [Color(0.55, 0.3, 0.9), Color(0.2, 0.6, 0.8), Color(0.85, 0.3, 0.55), Color(0.3, 0.4, 0.95)]
			_items.append([pos, randf_range(160.0, 320.0), colors[i % colors.size()]])
	position.y = fmod(position.y, _height)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	position.y = fmod(position.y + speed * speed_scale * delta, _height)
	if kind == Kind.STARS:
		# Gentle twinkle for the whole layer (a colour tint, no redraw needed).
		self_modulate.a = 0.8 + 0.2 * sin(_time * twinkle_rate)


## Every star/nebula is a textured rectangle using the same soft-glow texture, so Godot
## batches the whole layer into a single draw call (draw_circle would be one call per star).
func _draw() -> void:
	for copy_y in [0.0, -_height]:
		for item in _items:
			var pos: Vector2 = item[0] + Vector2(0, copy_y)
			if kind == Kind.STARS:
				var r: float = item[1] * 2.2  # glow falls off softly, so draw it a bit bigger
				draw_texture_rect(glow_tex, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false, item[2])
			else:
				var r: float = item[1]
				draw_texture_rect(glow_tex, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(item[2], 0.12))

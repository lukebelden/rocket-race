extends Node2D
## One scrolling background layer: stars, faint nebula clouds, or a tiled space image.
## Its contents are drawn once; scrolling just moves the node and wraps around, drawing a
## second copy one screen-height (or one tile) above so there's never a gap. Much cheaper
## than redrawing every star every frame.

enum Kind { STARS, NEBULA, IMAGE }

var kind: Kind = Kind.STARS
var count: int = 50
var speed: float = 40.0
## Star dot radius range and brightness range.
var size_range: Vector2 = Vector2(0.8, 1.4)
var brightness: Vector2 = Vector2(0.4, 0.8)
## Multiplies scroll speed (the launch intro speeds stars up).
var speed_scale: float = 1.0
var twinkle_rate: float = 1.0
## IMAGE layers: a seamless (tileable) texture, repeated to cover the screen.
var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
## IMAGE layers: tile size as a fraction of the screen height.
var tile_scale: float = 1.2

static var glow_tex: Texture2D

var _height: float = 648.0
var _screen: Vector2 = Vector2(1152, 648)
var _items: Array = []
var _time: float = 0.0


## (Re)build the layer for a screen size.
func build(screen: Vector2) -> void:
	_screen = screen
	_height = screen.y
	_items.clear()
	if kind == Kind.IMAGE:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # smooth when scaled
		_height = roundf(screen.y * tile_scale)  # wrap on whole tiles so the seams line up
	for i in count if kind != Kind.IMAGE else 0:
		var pos := Vector2(randf() * screen.x, randf() * screen.y)
		if kind == Kind.STARS:
			var b := randf_range(brightness.x, brightness.y)
			_items.append([pos, randf_range(size_range.x, size_range.y), Color("a8e2d4").lerp(Color.WHITE, 0.4) * Color(b, b, b)])
		else:
			# Hazy teal/indigo clouds (palette.gd), not bright colours.
			var colors := [Color("2c6d6f"), Color("36405f"), Color("4fb8a8"), Color("262d52")]
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
	if kind == Kind.IMAGE:
		if texture == null:
			return
		# Square tiles, centred across the width; rows from one tile above the screen down.
		var tile := _height
		var across := ceili(_screen.x / tile) + 1
		var x0 := (_screen.x - across * tile) / 2.0
		var y := -tile
		while y < _screen.y:
			for c in across:
				draw_texture_rect(texture, Rect2(x0 + c * tile, y, tile, tile), false)
			y += tile
		return
	for copy_y in [0.0, -_height]:
		for item in _items:
			var pos: Vector2 = item[0] + Vector2(0, copy_y)
			if kind == Kind.STARS:
				var r: float = item[1] * 2.2  # glow falls off softly, so draw it a bit bigger
				draw_texture_rect(glow_tex, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false, item[2])
			else:
				var r: float = item[1]
				draw_texture_rect(glow_tex, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(item[2], 0.2))

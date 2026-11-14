extends Control
## Pilot portraits (pixel art, cut from art/source/pilots_sheet.webp by art/build_pilots.gd).
## As a node it shows one pilot's portrait (menu avatar, pilot pick cards); the static helpers
## draw a portrait anywhere, or a chunky low-res version for the pixel monitor screens.

const DEFAULT := "falcon"
const TEX := {
	"falcon": preload("res://sprites/pilots/falcon.png"),
	"torque": preload("res://sprites/pilots/torque.png"),
	"nova": preload("res://sprites/pilots/nova.png"),
	"lotus": preload("res://sprites/pilots/lotus.png"),
	"grizzly": preload("res://sprites/pilots/grizzly.png"),
	"rivet": preload("res://sprites/pilots/rivet.png"),
	"scarlet": preload("res://sprites/pilots/scarlet.png"),
	"viper": preload("res://sprites/pilots/viper.png"),
	"echo": preload("res://sprites/pilots/echo.png"),
	"titan": preload("res://sprites/pilots/titan.png"),
}
## Profiles saved before the crew change had animal pilots: give them a new pilot.
const OLD := {"duck": "falcon", "mouse": "echo", "dog": "torque", "cat": "scarlet", "bear": "grizzly",
	"raccoon": "viper", "monkey": "rivet", "penguin": "titan"}

static var _pixel_cache: Dictionary = {}

## Which pilot to show (node use).
var pilot: String = DEFAULT:
	set(value):
		pilot = value
		queue_redraw()
## Older code calls it "animal".
var animal: String:
	set(value):
		pilot = value
	get:
		return pilot
## 1.0 = whole portrait, smaller = just the head and shoulders (from the top).
var crop: float = 1.0
## Dark backing + thin border behind the portrait.
var framed: bool = true
var accent: Color = Color("e8892b")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if framed:
		draw_rect(r, Color("15181d"))
		draw_portrait(self, r.grow(-2), pilot, crop)
		draw_rect(r, Color(accent, 0.8), false, 2.0)
	else:
		draw_portrait(self, r, pilot, crop)


static func id_of(id: String) -> String:
	if TEX.has(id):
		return id
	return str(OLD.get(id, DEFAULT))


static func texture(id: String) -> Texture2D:
	return TEX[id_of(id)]


## The part of a portrait (size `ts`) that fills `target` without stretching: the top `crop`
## of the picture, trimmed at the sides (or bottom) to match the target's shape.
static func source_rect(ts: Vector2, target: Vector2, crop := 1.0) -> Rect2:
	var src := Rect2(0, 0, ts.x, ts.y * crop)
	var want := target.x / maxf(target.y, 1.0)
	if src.size.x / src.size.y > want:
		var w := src.size.y * want
		src.position.x = (ts.x - w) / 2.0
		src.size.x = w
	else:
		src.size.y = src.size.x / want
	return src


static func draw_portrait(canvas: CanvasItem, rect: Rect2, id: String, crop := 1.0, modulate := Color.WHITE) -> void:
	var tex := texture(id)
	canvas.draw_texture_rect_region(tex, rect, source_rect(tex.get_size(), rect.size, crop), modulate)


## A chunky low-res square of the head and shoulders (`cols` pixels wide) for pixel monitors.
## Draw it with nearest-neighbour filtering so every pixel shows as a crisp block.
static func pixel_texture(id: String, cols := 40) -> Texture2D:
	var key := "%s:%d" % [id_of(id), cols]
	if _pixel_cache.has(key):
		return _pixel_cache[key]
	var img := texture(id).get_image()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var src := source_rect(img.get_size(), Vector2.ONE, 0.78)  # square: head and shoulders
	var head := img.get_region(Rect2i(src))
	var rows := int(round(cols * src.size.y / src.size.x))
	head.resize(cols, rows, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(head)
	_pixel_cache[key] = tex
	return tex

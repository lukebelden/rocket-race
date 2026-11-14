extends SceneTree
## Cuts the 10 pilot portraits out of art/source/pilots_sheet.webp (2 rows x 5, white gutters)
## into sprites/pilots/<id>.png.
##   godot --headless --path <any project> -s "<this file>"
const ROOT := "C:/Users/lukeb/Godot Projects/godot-test-game/"
const IDS := ["falcon", "torque", "nova", "lotus", "grizzly", "rivet", "scarlet", "viper", "echo", "titan"]

func _init() -> void:
	var img := Image.load_from_file(ROOT + "art/source/pilots_sheet.webp")
	img.convert(Image.FORMAT_RGBA8)
	print("sheet ", img.get_size())
	# Regular 5 x 2 grid; inset each cell a little to drop the white gutters.
	var cw := img.get_width() / 5.0
	var ch := img.get_height() / 2.0
	var inset := 7
	var i := 0
	for r in 2:
		for c in 5:
			var rect := Rect2i(int(c * cw) + inset, int(r * ch) + inset, int(cw) - inset * 2, int(ch) - inset * 2)
			var tile := img.get_region(rect)
			_clear_gutter(tile)
			tile.save_png(ROOT + "sprites/pilots/%s.png" % IDS[i])
			i += 1
	print("saved ", i)
	quit()

## Spans of non-white columns (vertical=true) or rows along the sheet.
func _runs(img: Image, vertical: bool) -> Array[Vector2i]:
	var n := img.get_width() if vertical else img.get_height()
	var m := img.get_height() if vertical else img.get_width()
	var out: Array[Vector2i] = []
	var start := -1
	for a in n + 1:
		var ink := false
		if a < n:
			var dark := 0
			for b in range(0, m, 3):
				var col := img.get_pixel(a, b) if vertical else img.get_pixel(b, a)
				if col.r + col.g + col.b < 2.7:
					dark += 1
			ink = dark > m / 3 / 20  # more than ~5% of the line is not white
		if ink and start < 0:
			start = a
		elif not ink and start >= 0:
			if a - start > 60:
				out.append(Vector2i(start, a))
			start = -1
	return out


## Near-white pixels within 14px of a tile edge are leftovers of the white gutters: clear them.
func _clear_gutter(tile: Image) -> void:
	var w := tile.get_width()
	var h := tile.get_height()
	for y in h:
		for x in w:
			if mini(mini(x, w - 1 - x), mini(y, h - 1 - y)) > 14:
				continue
			var c := tile.get_pixel(x, y)
			if c.a > 0.0 and c.r > 0.88 and c.g > 0.88 and c.b > 0.88:
				tile.set_pixel(x, y, Color(0, 0, 0, 0))

extends SceneTree
## Builds the rocket sprites from art/source/rocket_sheet.png (6 animation frames, 192px apart).
##   godot --headless --path <any project> -s "<this file>"
## Writes to sprites/rockets/:
##   <ship>.png       body frames side by side (scout/cruiser/hauler), boosters attached
##   <ship>_bare.png  same, boosters dropped (fins moved onto the core)
##   flame.png        engine flame frames, booster.png  one detached booster pod
## Small and large are cut / extended from the original pixels so the style matches exactly.

const ROOT := "C:/Users/lukeb/Godot Projects/godot-test-game/"
const FW := 192
const FRAMES := 6
# Column layout of the source rocket (frame-local x).
const FIN_L := 36        # x <= this: left fin
const FIN_R := 155       # x >= this: right fin
const BOOST_L := Vector2i(37, 63)    # left booster columns
const BOOST_R := Vector2i(128, 154)  # right booster columns
const CORE := Vector2i(65, 126)      # core columns (body), nozzles are wider:
const NOZ := Vector2i(60, 131)
const NOZ_ROW := 288                 # nozzle rows start here (source rows)
const BOOST_TOP := 95


func _init() -> void:
	var src := Image.load_from_file(ROOT + "art/source/rocket_sheet.png")
	src.convert(Image.FORMAT_RGBA8)
	var split := _flame_row(src)
	print("flame starts at row ", split)
	var ships := {
		"scout": {"rows": [[0, 130], [186, split]], "boosters": 2},
		"cruiser": {"rows": [[0, split]], "boosters": 2},
		"hauler": {"rows": [[0, 166], [129, 166], [166, split]], "boosters": 4},
	}
	for ship in ships:
		var spec: Dictionary = ships[ship]
		var full: Array[Image] = []
		var bare: Array[Image] = []
		for f in FRAMES:
			var frame := src.get_region(Rect2i(f * FW, 0, FW, split))
			var body := _rows(frame, spec["rows"])
			var nozzle_row := NOZ_ROW + (body.get_height() - split)
			full.append(_assemble(body, int(spec["boosters"]), nozzle_row))
			bare.append(_assemble(body, 0, nozzle_row))
		_strip(full).save_png(ROOT + "sprites/rockets/%s.png" % ship)
		_strip(bare).save_png(ROOT + "sprites/rockets/%s_bare.png" % ship)
		print(ship, " ", full[0].get_size())
	var flames: Array[Image] = []
	for f in FRAMES:
		var fl := src.get_region(Rect2i(f * FW, split, FW, src.get_height() - split))
		_clear_cols(fl, 0, NOZ.x - 16, 0)  # fin tips poke into these rows: keep only the flame
		_clear_cols(fl, NOZ.y + 16, FW - 1, 0)
		flames.append(_trim_bottom(fl))
	var fh := 0
	for im in flames:
		fh = maxi(fh, im.get_height())
	for i in flames.size():
		var pad := Image.create_empty(FW, fh, false, Image.FORMAT_RGBA8)
		pad.blit_rect(flames[i], Rect2i(Vector2i.ZERO, flames[i].get_size()), Vector2i.ZERO)
		flames[i] = pad
	_strip(flames).save_png(ROOT + "sprites/rockets/flame.png")
	# One booster pod on its own (for when it drops off).
	var f0 := src.get_region(Rect2i(0, 0, FW, split))
	var pod := Image.create_empty(BOOST_L.y - BOOST_L.x + 1, split - BOOST_TOP, false, Image.FORMAT_RGBA8)
	pod.blit_rect(f0, Rect2i(BOOST_L.x, BOOST_TOP, pod.get_width(), pod.get_height()), Vector2i.ZERO)
	_clear_cols(pod, NOZ.x - BOOST_L.x, pod.get_width() - 1, NOZ_ROW - BOOST_TOP)  # bit of core nozzle
	pod.save_png(ROOT + "sprites/rockets/booster.png")
	print("flame ", flames[0].get_size(), " booster ", pod.get_size())
	quit()


## First row (below the nozzles) where the centre column turns into bright flame.
func _flame_row(src: Image) -> int:
	for y in range(300, src.get_height()):
		var c := src.get_pixel(96, y)
		if c.a > 0.5 and c.r > 0.8 and c.g > 0.55:
			return y
	return 329


## Stack the given [from, to) row ranges into a new image.
func _rows(img: Image, ranges: Array) -> Image:
	var h := 0
	for r in ranges:
		h += int(r[1]) - int(r[0])
	var out := Image.create_empty(img.get_width(), h, false, Image.FORMAT_RGBA8)
	var y := 0
	for r in ranges:
		var n := int(r[1]) - int(r[0])
		out.blit_rect(img, Rect2i(0, int(r[0]), img.get_width(), n), Vector2i(0, y))
		y += n
	return out


func _cols(img: Image, x0: int, x1: int, y0: int = 0, y1: int = -1) -> Image:
	if y1 < 0:
		y1 = img.get_height()
	var out := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(x0, y0, x1 - x0 + 1, y1 - y0), Vector2i(x0, y0))
	return out


func _clear_cols(img: Image, x0: int, x1: int, from_row: int) -> void:
	for y in range(from_row, img.get_height()):
		for x in range(x0, x1 + 1):
			img.set_pixel(x, y, Color(0, 0, 0, 0))


## Put a ship together: core (+ nozzles), 0 / 2 / 4 boosters, fins on the outside.
func _assemble(body: Image, boosters: int, nozzle_row: int) -> Image:
	var h := body.get_height()
	var extra := 25 if boosters == 4 else 0      # outer booster pair width
	var shift := 0 if boosters > 0 else CORE.x - FIN_L - 1  # bare: fins move in onto the core
	var w := FW + extra * 2
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var ox := extra
	var left_fin := _cols(body, 0, FIN_L)
	var right_fin := _cols(body, FIN_R, FW - 1)
	var all := Rect2i(0, 0, FW, h)
	if boosters == 4:  # outer pair, behind the inner pair
		var l := _cols(body, BOOST_L.x, NOZ.x - 1, BOOST_TOP)
		var r := _cols(body, NOZ.y + 1, BOOST_R.y, BOOST_TOP)
		out.blend_rect(l, all, Vector2i(ox - extra, 0))
		out.blend_rect(r, all, Vector2i(ox + extra, 0))
	if boosters > 0:
		out.blend_rect(_cols(body, FIN_L + 1, FIN_R - 1), all, Vector2i(ox, 0))
	else:
		out.blend_rect(_cols(body, CORE.x, CORE.y, 0, nozzle_row), all, Vector2i(ox, 0))
		out.blend_rect(_cols(body, NOZ.x, NOZ.y, nozzle_row), all, Vector2i(ox, 0))
	out.blend_rect(left_fin, all, Vector2i(ox - extra + shift, 0))
	out.blend_rect(right_fin, all, Vector2i(ox + extra - shift, 0))
	return out


func _strip(frames: Array[Image]) -> Image:
	var w := frames[0].get_width()
	var out := Image.create_empty(w * frames.size(), frames[0].get_height(), false, Image.FORMAT_RGBA8)
	for i in frames.size():
		out.blit_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), Vector2i(i * w, 0))
	return out


func _trim_bottom(img: Image) -> Image:
	var used := img.get_used_rect()
	return img.get_region(Rect2i(0, 0, img.get_width(), used.end.y))

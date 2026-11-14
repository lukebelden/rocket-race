extends RefCounted
## Art for hull finishes, hangar decorations and the hangar workers. It lives in
## res://sprites/licensed/, which is git-ignored (some of these licences forbid publishing the
## files: see sprites/licensed/LICENSES.txt), so it's loaded only if present. A fresh clone
## without it still runs: finishes are skipped, decor and workers just don't appear.

const ROOT := "res://sprites/licensed/"
## Worker sheet: 16 workers in a 4 x 4 grid; each has 3 walk frames x 4 rows (down, left,
## right, up) of 18 x 26 px frames.
const WORKER_FRAME := Vector2i(18, 26)
const WORKER_COUNT := 16

static var _cache: Dictionary = {}


static func _tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


static func finish(id: String) -> Texture2D:
	return null if id == "" or id == "none" else _tex(ROOT + "finishes/%s.png" % id)


## Average brightness of a texture (0-1), worked out once per texture.
static func average_brightness(tex: Texture2D) -> float:
	var key := "avg:" + str(tex.get_rid())
	if not _cache.has(key):
		var img := tex.get_image()
		var avg := 0.5
		if img:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.resize(8, 8, Image.INTERPOLATE_BILINEAR)
			var sum := 0.0
			for y in 8:
				for x in 8:
					var c := img.get_pixel(x, y)
					sum += (c.r + c.g + c.b) / 3.0
			avg = sum / 64.0
		_cache[key] = avg
	return _cache[key]


static func decor(id: String) -> Texture2D:
	return _tex(ROOT + "decor/%s.png" % id)


## The worker sheet, set to crisp pixel filtering (it shares a layer with smooth decor art).
static func workers() -> Texture2D:
	if not _cache.has("workers"):
		var tex := _tex(ROOT + "workers/workers.png")
		var crisp: CanvasTexture = null
		if tex:
			crisp = CanvasTexture.new()
			crisp.diffuse_texture = tex
			crisp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_cache["workers"] = crisp
	return _cache["workers"]


## Frame of one worker: dir 0 = down (facing you), 1 = left, 2 = right, 3 = up; step 0-2.
static func worker_region(worker: int, dir: int, step: int) -> Rect2:
	var col := (worker % 4) * 3 + step
	var row := (worker / 4) * 4 + dir
	return Rect2(Vector2(col * WORKER_FRAME.x, row * WORKER_FRAME.y), Vector2(WORKER_FRAME))

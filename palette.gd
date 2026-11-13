extends RefCounted
## Rocket Race palette: minimal flat-vector sci-fi.
## Darks are indigo/navy, mid tones teal/aqua, and warm orange/amber is used ONLY for
## lights and important things (buttons you should press, danger, glows). Every shape is
## flat: one base colour plus one darker shade, no outlines, no gradients. Depth comes from
## haze: far layers are lighter and greener, near layers darker.

# Darks (backgrounds, silhouettes, panels)
const INK := Color("12152a")      # deepest: foreground silhouettes, panel backs
const NAVY := Color("1b2140")
const INDIGO := Color("262d52")
const SLATE := Color("36405f")

# Teals (mid tones, far layers, haze)
const TEAL_DEEP := Color("1d4249")
const TEAL := Color("2c6d6f")
const AQUA := Color("4fb8a8")
const MIST := Color("a8e2d4")     # brightest haze / light shafts
const HAZE := Color("5f9c9b")

# Warm accents (lights, highlights, calls to action)
const ORANGE := Color("f0893c")
const AMBER := Color("ffc56b")
const RUST := Color("b9502c")

# Text and status
const TEXT := Color("e6f1ee")
const TEXT_DIM := Color("8fa6b0")
const GOOD := Color("7ed6a0")
const BAD := Color("ef6a5a")


## A colour pushed back into the haze (0 = unchanged, 1 = fully haze).
static func hazed(c: Color, amount: float) -> Color:
	return c.lerp(HAZE, clampf(amount, 0.0, 1.0))


## Flat soft glow: a few rings of fading alpha (no gradients), like the lamps in the style.
static func glow(canvas: CanvasItem, at: Vector2, radius: float, color: Color, strength := 1.0) -> void:
	for i in 8:
		var k := 1.0 - i / 8.0
		canvas.draw_circle(at, radius * (0.35 + 0.65 * k), Color(color, 0.035 * strength))

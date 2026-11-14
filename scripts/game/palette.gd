extends RefCounted
## Rocket Race palette: gritty sci-fi, matched to the pilot portraits.
## Darks are gunmetal, mid tones muted steel, and warm orange/amber is used ONLY for lights
## and important things (buttons you should press, danger, glows). Shapes stay flat: one base
## colour plus one darker shade. Depth comes from haze: far layers lighter and greyer.

# Darks (backgrounds, silhouettes, panels)
const INK := Color("0e1014")      # deepest: foreground silhouettes, panel backs
const NAVY := Color("16191e")
const INDIGO := Color("21252c")
const SLATE := Color("343a44")

# Teals (mid tones, far layers, haze)
const TEAL_DEEP := Color("1f2a2e")
const TEAL := Color("34494e")
const AQUA := Color("5fa8a0")
const MIST := Color("b4c2c0")     # brightest haze / light shafts
const HAZE := Color("66767a")

# Warm accents (lights, highlights, calls to action)
const ORANGE := Color("e8892b")
const AMBER := Color("ffbf5a")
const RUST := Color("a8461f")

# Text and status
const TEXT := Color("e8e6df")
const TEXT_DIM := Color("8a9199")
const GOOD := Color("8fcf72")
const BAD := Color("e5533d")


## A colour pushed back into the haze (0 = unchanged, 1 = fully haze).
static func hazed(c: Color, amount: float) -> Color:
	return c.lerp(HAZE, clampf(amount, 0.0, 1.0))


## Flat soft glow: a few rings of fading alpha (no gradients), like the lamps in the style.
static func glow(canvas: CanvasItem, at: Vector2, radius: float, color: Color, strength := 1.0) -> void:
	for i in 8:
		var k := 1.0 - i / 8.0
		canvas.draw_circle(at, radius * (0.35 + 0.65 * k), Color(color, 0.035 * strength))

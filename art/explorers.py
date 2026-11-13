# Rocket Race - sculpted "Explorer" astronaut pilots (Blender, rendered to PNGs).
#
#   "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" -b -P art/explorers.py -- duck cat ...
# (no names = all eight). Writes art/renders/explorer_<animal>_full.png and _face.png.
#
# Sculpted, not assembled: each group (suit, boots, gloves, backpack, head) is blocked out
# from simple shapes, then melted into ONE continuous surface (voxel remesh) and smoothed,
# with soft fabric wrinkles on the suit - like a sculpted vinyl figure. Small painted-on
# details (eyes, nose, bill, lights) stay separate glossy pieces.

import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ALL = ["duck", "mouse", "dog", "cat", "bear", "raccoon", "monkey", "penguin"]
ANIMALS = ARGS or ALL
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "renders")
os.makedirs(OUT, exist_ok=True)

# Trim colour per pilot (gloves, stripes) so the lineup reads clearly.
TRIM = {"duck": "f0893c", "mouse": "4fb8a8", "dog": "5aa9e6", "cat": "9a73d6",
        "bear": "e5683b", "raccoon": "7ed6a0", "monkey": "ffc56b", "penguin": "ef6a5a"}


def hex_rgba(h, a=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)


_mats = {}


def mat(color, rough=0.55, metal=0.0, glass=False, emit=0.0, coat=0.15, sss=0.0):
    key = (color, rough, metal, glass, emit, coat, sss)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("M_" + color)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_rgba(color)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Coat Weight"].default_value = coat
    if sss:
        b.inputs["Subsurface Weight"].default_value = sss
    if glass:
        b.inputs["Transmission Weight"].default_value = 1.0
        b.inputs["IOR"].default_value = 1.15
        b.inputs["Roughness"].default_value = 0.02
    if emit:
        b.inputs["Emission Color"].default_value = hex_rgba(color)
        b.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


# --- Blocking shapes (raw, no material: they get fused) ------------------------------------

def _active():
    return bpy.context.object


def blob(loc, scale, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=loc, rotation=rot)
    o = _active()
    o.scale = scale
    return o


def slab(loc, size, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = _active()
    o.scale = size
    return o


def ring(loc, major, minor, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=rot,
                                     major_segments=40, minor_segments=12)
    o = _active()
    o.scale = scale
    return o


def cone(loc, r1, r2, depth, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
    return _active()


def tube(a, b, ra, rb):
    """Tapered limb between two points, with rounded ends."""
    a, b = Vector(a), Vector(b)
    d = b - a
    o = cone((a + b) / 2, ra, rb, d.length)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    return [o, blob(a, (ra, ra, ra)), blob(b, (rb, rb, rb))]


def fuse(parts, material, voxel=0.03, smooth=0.6, wrinkle=0.0, name="Sculpt"):
    """Melt the blocking shapes into one continuous sculpted surface."""
    flat = []
    for p in parts:
        flat.extend(p if isinstance(p, list) else [p])
    bpy.ops.object.select_all(action="DESELECT")
    for p in flat:
        p.select_set(True)
    bpy.context.view_layer.objects.active = flat[0]
    bpy.ops.object.convert(target="MESH")
    if len(flat) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    rm = o.modifiers.new("Remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    rm.use_smooth_shade = True
    sm = o.modifiers.new("Smooth", "SMOOTH")
    sm.factor = smooth
    sm.iterations = 12
    if wrinkle:
        tex = bpy.data.textures.new("Wrinkles", "CLOUDS")
        tex.noise_scale = 0.35
        tex.noise_depth = 2
        dp = o.modifiers.new("Wrinkle", "DISPLACE")
        dp.texture = tex
        dp.strength = wrinkle
        dp.mid_level = 0.5
        sm2 = o.modifiers.new("Soften", "SMOOTH")
        sm2.factor = 0.5
        sm2.iterations = 3
    o.data.materials.append(material)
    for poly in o.data.polygons:
        poly.use_smooth = True
    return o


def detail(loc, scale, material, rot=(0, 0, 0), subdiv=1):
    """A separate painted-on detail (eyes, nose, lights)."""
    o = blob(loc, scale, rot)
    o.data.materials.append(material)
    for p in o.data.polygons:
        p.use_smooth = True
    if subdiv:
        s = o.modifiers.new("Sub", "SUBSURF")
        s.levels = s.render_levels = subdiv
    return o


def hose(points, radius, material):
    curve = bpy.data.curves.new("Hose", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 4
    curve.use_fill_caps = True
    spl = curve.splines.new("BEZIER")
    spl.bezier_points.add(len(points) - 1)
    for bp, p in zip(spl.bezier_points, points):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    o = bpy.data.objects.new("Hose", curve)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(material)
    return o


# --- Scene ---------------------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 128
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = hex_rgba("cfe3e6")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    bpy.ops.mesh.primitive_plane_add(size=6)
    _active().is_shadow_catcher = True
    for loc, energy, size in [((-3.5, -5.0, 8.5), 750, 7.0), ((5.0, -4.0, 4.0), 260, 7.0), ((2.0, 5.0, 6.5), 650, 4.0)]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        lt = _active()
        lt.data.energy = energy
        lt.data.size = size
        lt.rotation_mode = "QUATERNION"
        lt.rotation_quaternion = (Vector((0, 0, 2.6)) - Vector(loc)).to_track_quat("-Z", "Y")


def shoot(target, distance, height, res, path):
    sc = bpy.context.scene
    for o in [o for o in bpy.data.objects if o.type == "CAMERA"]:
        bpy.data.objects.remove(o)
    sc.render.resolution_x, sc.render.resolution_y = res
    angle = math.radians(-24)
    loc = Vector((math.sin(angle) * distance, -math.cos(angle) * distance, height))
    bpy.ops.object.camera_add(location=loc)
    cam = _active()
    cam.data.lens = 50
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (Vector(target) - loc).to_track_quat("-Z", "Y")
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


# --- Sculpted Explorer suit ---------------------------------------------------------------

HEAD = Vector((0, -0.04, 4.5))
K = 0.62


def explorer_suit(trim_hex):
    white = mat("ebe7df", 0.62, sss=0.05)
    grey = mat("cbc7be", 0.6)
    trim = mat(trim_hex, 0.5)
    metal = mat("9aa7b8", 0.3, metal=0.7)

    # Suit: torso, hips, sleeves and legs melted into one padded form, with ribbing.
    parts = [slab((0, 0, 3.05), (1.25, 0.78, 1.4)), slab((0, 0, 2.25), (1.05, 0.68, 0.55)),
             blob((0, 0, 3.55), (0.68, 0.42, 0.32))]
    for s in (-1, 1):
        parts += tube((s * 0.82, 0, 3.55), (s * 1.0, -0.06, 2.78), 0.25, 0.22)
        parts += tube((s * 1.0, -0.06, 2.78), (s * 1.03, -0.18, 2.1), 0.22, 0.2)
        parts += tube((s * 0.35, 0, 2.15), (s * 0.37, -0.05, 1.2), 0.3, 0.26)
        parts += tube((s * 0.37, -0.05, 1.2), (s * 0.37, 0.0, 0.5), 0.26, 0.24)
        for z, r in ((3.1, 0.22), (2.95, 0.21)):  # elbow ribbing
            parts.append(ring((s * 1.0, -0.07, z - 0.3), r, 0.045, rot=(math.radians(8), s * math.radians(12), 0)))
        for z in (1.32, 1.18, 1.04):  # knee ribbing
            parts.append(ring((s * 0.37, -0.05, z), 0.27, 0.045))
    fuse(parts, white, voxel=0.028, smooth=0.55, wrinkle=0.035, name="Suit")

    # Moon boots: chunky, rounded toe, thick sole.
    boots = []
    for s in (-1, 1):
        boots += [slab((s * 0.37, -0.12, 0.3), (0.52, 0.8, 0.45)), blob((s * 0.37, -0.42, 0.25), (0.27, 0.3, 0.24))]
    fuse(boots, grey, voxel=0.03, smooth=0.6, name="Boots")
    soles = [slab((s * 0.37, -0.14, 0.06), (0.58, 0.88, 0.12)) for s in (-1, 1)]
    fuse(soles, mat("36405f", 0.7), voxel=0.03, smooth=0.4, name="Soles")

    # Gloves: mitts with a cuff.
    gloves = []
    for s in (-1, 1):
        gloves += [blob((s * 1.04, -0.22, 1.92), (0.2, 0.18, 0.24)), blob((s * 0.95, -0.3, 1.98), (0.08, 0.07, 0.11)),
                   ring((s * 1.03, -0.18, 2.12), 0.21, 0.07)]
    fuse(gloves, trim, voxel=0.025, smooth=0.5, name="Gloves")

    # Life-support backpack with vents.
    pack = [slab((0, 0.62, 3.1), (1.15, 0.6, 1.45)), slab((0, 0.95, 3.45), (0.8, 0.12, 0.35))]
    fuse(pack, grey, voxel=0.03, smooth=0.45, name="Pack")

    # Chest control box with lights, trim stripes, hoses from pack to chest.
    fuse([slab((0, -0.47, 3.08), (0.62, 0.2, 0.42))], mat("36405f", 0.45), voxel=0.025, smooth=0.35, name="ChestBox")
    for i, c in enumerate(["ef6a5a", "ffc56b", "4fb8a8"]):
        detail((-0.17 + i * 0.17, -0.58, 3.14), (0.045, 0.02, 0.045), mat(c, 0.3, emit=1.8), subdiv=0)
    for s in (-1, 1):
        fuse([slab((s * 0.5, -0.42, 2.62), (0.09, 0.08, 0.95))], trim, voxel=0.02, smooth=0.3, name="Stripe")
        hose([(s * 0.55, 0.4, 3.5), (s * 0.85, -0.2, 3.35), (s * 0.35, -0.55, 2.95)], 0.05, mat("4a5578", 0.5))
    # Helmet: metal neck ring with two lamps, glass dome over the head.
    fuse([blob((0, -0.02, 4.02), (0.56, 0.5, 0.2))], mat("4a5578", 0.6), voxel=0.025, smooth=0.5, name="Collar")  # head sits in the suit
    fuse([ring((0, 0, 3.92), 0.64, 0.09)], metal, voxel=0.02, smooth=0.3, name="Ring")
    for s in (-1, 1):
        detail((s * 0.62, -0.28, 4.02), (0.07, 0.05, 0.05), mat("ffc56b", 0.3, emit=3.0))
    dome = detail(HEAD + Vector((0, 0, 0.06)), (0.98, 0.98, 1.0), mat("e2f4f1", glass=True), subdiv=2)
    return dome


# --- Sculpted heads ---------------------------------------------------------------------------

def P(x, y, z):
    """Head-relative position (head radius ~1 before scaling by K)."""
    return HEAD + Vector((x * K, y * K, z * K))


def S(x, y, z):
    return (x * K, y * K, z * K)


def eyes(spread=0.36, h=0.12, fwd=0.74, size=0.16, mask=None):
    ink = mat("12152a", 0.05, coat=0.9)
    shine = mat("ffffff", 0.2, emit=3.0)
    for s in (-1, 1):
        if mask:
            detail(P(s * spread, -fwd + 0.06, h), S(0.3, 0.1, 0.22), mask, rot=(0, 0, s * 0.25))
        e = P(s * spread, -fwd, h)
        detail(e, S(size * 0.82, size * 0.5, size), ink)
        detail(e + Vector(S(-0.05, -0.07, 0.06)), S(0.045, 0.02, 0.045), shine, subdiv=0)


def cheeks(spread=0.6, h=-0.17, fwd=0.57):
    for s in (-1, 1):
        detail(P(s * spread, -fwd, h), S(0.15, 0.04, 0.09), mat("f2a0a8", 0.6), subdiv=0)


def head_duck():
    white = mat("ece6da", 0.55, sss=0.1)
    fuse([blob(P(0, 0, 0), S(0.95, 0.88, 0.92))] +
         [blob(P(dx, 0, 0.98 + 0.05 * (i == 1)), S(0.08, 0.08, 0.22), rot=(0, rz, 0))
          for i, (dx, rz) in enumerate([(-0.08, -0.4), (0.05, 0.0), (0.18, 0.4)])], white, voxel=0.018, name="Head")
    fuse([blob(P(0, -0.81, -0.23), S(0.48, 0.32, 0.12))], mat("f0893c", 0.3), voxel=0.015, smooth=0.4, name="Bill")
    fuse([blob(P(0, -0.75, -0.35), S(0.38, 0.26, 0.08))], mat("c96a2a", 0.35), voxel=0.015, smooth=0.4, name="Bill2")
    eyes(fwd=0.76)
    cheeks()


def head_mouse():
    grey = mat("b4b4bf", 0.6, sss=0.08)
    parts = [blob(P(0, 0, 0), S(0.88, 0.84, 0.86)), blob(P(0, -0.62, -0.22), S(0.4, 0.42, 0.3))]
    for s in (-1, 1):
        parts.append(blob(P(s * 0.62, 0.08, 0.6), S(0.42, 0.12, 0.42), rot=(0, s * -0.4, 0)))
    fuse(parts, grey, voxel=0.018, name="Head")
    for s in (-1, 1):
        detail(P(s * 0.62, 0.0, 0.6), S(0.28, 0.05, 0.28), mat("f2a0a8", 0.6), rot=(0, s * -0.4, 0))
    detail(P(0, -1.0, -0.14), S(0.1, 0.08, 0.08), mat("ef7a8f", 0.3, coat=0.6))
    eyes(spread=0.32, fwd=0.72)
    cheeks(spread=0.5)


def head_dog():
    tan = mat("d9a46a", 0.6, sss=0.08)
    brown = mat("7d4c2e", 0.65)
    fuse([blob(P(0, 0, 0), S(0.95, 0.9, 0.9)), blob(P(0, -0.66, -0.26), S(0.44, 0.42, 0.32))], tan, voxel=0.018, name="Head")
    fuse([blob(P(0, -0.74, -0.32), S(0.36, 0.3, 0.22))], mat("f6e4c8", 0.6), voxel=0.015, name="Muzzle")
    for s in (-1, 1):
        fuse([blob(P(s * 0.9, 0.05, 0.02), S(0.2, 0.3, 0.58), rot=(0, s * 0.35, 0))], brown, voxel=0.018, name="Ear")
    detail(P(0, -1.04, -0.12), S(0.15, 0.1, 0.1), mat("12152a", 0.2, coat=0.7))
    detail(P(-0.36, -0.68, 0.14), S(0.24, 0.08, 0.22), brown)  # eye patch
    eyes(fwd=0.78)


def head_cat():
    orange = mat("f29e4c", 0.6, sss=0.08)
    parts = [blob(P(0, 0, 0), S(1.04, 0.9, 0.86))]
    for s in (-1, 1):
        parts.append(cone(P(s * 0.52, 0.02, 0.78), 0.3 * K, 0.02 * K, 0.55 * K, rot=(0, s * 0.35, 0)))
        parts.append(blob(P(s * 0.86, -0.25, -0.2), S(0.24, 0.22, 0.2)))  # cheek fluff
    fuse(parts, orange, voxel=0.018, name="Head")
    for s in (-1, 1):
        fuse([cone(P(s * 0.5, -0.08, 0.76), 0.18 * K, 0.02 * K, 0.36 * K, rot=(0, s * 0.35, 0))], mat("f2a0a8", 0.6), voxel=0.012, name="EarIn")
    fuse([blob(P(0, -0.72, -0.24), S(0.36, 0.26, 0.22))], mat("fbeee0", 0.6), voxel=0.015, name="Muzzle")
    for dx in (-0.18, 0.0, 0.18):  # forehead stripes
        detail(P(dx, -0.62, 0.62), S(0.05, 0.05, 0.16), mat("c46a28", 0.6))
    detail(P(0, -0.95, -0.12), S(0.08, 0.05, 0.06), mat("ef7a8f", 0.3, coat=0.6))
    eyes(fwd=0.74, size=0.17)
    cheeks(spread=0.62)


def head_bear():
    brown = mat("8e5e3a", 0.65, sss=0.06)
    parts = [blob(P(0, 0, 0), S(1.0, 0.92, 0.92))]
    for s in (-1, 1):
        parts.append(blob(P(s * 0.66, 0.05, 0.68), S(0.28, 0.16, 0.28)))
    fuse(parts, brown, voxel=0.018, name="Head")
    for s in (-1, 1):
        detail(P(s * 0.66, -0.04, 0.68), S(0.16, 0.06, 0.16), mat("c99a6b", 0.6))
    fuse([blob(P(0, -0.72, -0.26), S(0.42, 0.34, 0.3))], mat("d9b48a", 0.6), voxel=0.015, name="Muzzle")
    detail(P(0, -1.02, -0.12), S(0.16, 0.1, 0.1), mat("12152a", 0.2, coat=0.7))
    eyes(fwd=0.8, size=0.14)
    cheeks(spread=0.62)


def head_raccoon():
    grey = mat("9a9aa3", 0.6, sss=0.06)
    parts = [blob(P(0, 0, 0), S(1.0, 0.9, 0.88)), blob(P(0, -0.66, -0.25), S(0.36, 0.4, 0.26))]
    for s in (-1, 1):
        parts.append(cone(P(s * 0.55, 0.02, 0.74), 0.27 * K, 0.03 * K, 0.5 * K, rot=(0, s * 0.4, 0)))
        parts.append(blob(P(s * 0.9, -0.15, -0.22), S(0.22, 0.2, 0.18)))  # cheek tufts
    fuse(parts, grey, voxel=0.018, name="Head")
    fuse([blob(P(0, -0.76, -0.3), S(0.34, 0.28, 0.2))], mat("f1f0ee", 0.6), voxel=0.015, name="Muzzle")
    detail(P(0, -1.04, -0.18), S(0.1, 0.07, 0.07), mat("12152a", 0.2, coat=0.7))
    eyes(fwd=0.8, mask=mat("262b40", 0.6))


def head_monkey():
    brown = mat("86573a", 0.65, sss=0.06)
    face = mat("f3cfa0", 0.6, sss=0.08)
    parts = [blob(P(0, 0, 0), S(0.95, 0.92, 0.95))]
    for s in (-1, 1):
        parts.append(blob(P(s * 0.95, 0.02, 0.0), S(0.3, 0.16, 0.3)))
    fuse(parts, brown, voxel=0.018, name="Head")
    fuse([blob(P(-0.3, -0.62, 0.12), S(0.36, 0.2, 0.34)), blob(P(0.3, -0.62, 0.12), S(0.36, 0.2, 0.34)),
          blob(P(0, -0.66, -0.32), S(0.56, 0.32, 0.36))], face, voxel=0.015, name="Face")
    for s in (-1, 1):
        detail(P(s * 0.96, -0.08, 0.0), S(0.18, 0.05, 0.18), face)
        detail(P(s * 0.08, -0.98, -0.18), S(0.04, 0.03, 0.04), mat("5a3420", 0.4))
    eyes(spread=0.3, fwd=0.8)
    cheeks(spread=0.48, h=-0.22, fwd=0.78)


def head_penguin():
    dark = mat("262b40", 0.45, coat=0.3)
    white = mat("f3f6f8", 0.5)
    fuse([blob(P(0, 0, 0), S(0.92, 0.9, 1.0)), blob(P(0.05, 0, 1.0), S(0.12, 0.1, 0.16))], dark, voxel=0.018, name="Head")
    fuse([blob(P(-0.3, -0.58, 0.02), S(0.4, 0.3, 0.4)), blob(P(0.3, -0.58, 0.02), S(0.4, 0.3, 0.4)),
          blob(P(0, -0.6, -0.32), S(0.56, 0.32, 0.4))], white, voxel=0.015, name="Face")
    fuse([cone(P(0, -0.98, -0.2), 0.16 * K, 0.01 * K, 0.36 * K, rot=(math.radians(90), 0, 0))], mat("f0893c", 0.3),
         voxel=0.012, smooth=0.3, name="Beak")
    eyes(spread=0.3, fwd=0.82)
    cheeks(spread=0.5, h=-0.2, fwd=0.82)


HEADS = {"duck": head_duck, "mouse": head_mouse, "dog": head_dog, "cat": head_cat, "bear": head_bear,
         "raccoon": head_raccoon, "monkey": head_monkey, "penguin": head_penguin}

for animal in (ANIMALS if __name__ == "__main__" else []):  # importable by toon.py
    reset()
    dome = explorer_suit(TRIM[animal])
    HEADS[animal]()
    shoot((0, 0, 2.7), 12.0, 3.2, (560, 820), os.path.join(OUT, f"explorer_{animal}_full.png"))
    dome.hide_render = True  # close-up: no glass glare over the face
    shoot(HEAD + Vector((0, 0, -0.15)), 4.3, HEAD.z + 0.25, (512, 512), os.path.join(OUT, f"explorer_{animal}_face.png"))
    print("RENDERED", animal)

# Rocket Race - astronaut pilot concepts (3D, rendered in Blender).
#
#   "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" -b -P art/astronauts.py -- explorer ranger testpilot scout
# Renders art/renders/astro_<variant>.png for each variant (transparent background).
#
# Less "bubbly" than the first toy pilot: grown-up proportions (head ~1/5 of the height),
# harder armour-like pieces with tight bevels, tapered limbs, knee pads, chunky boots,
# gloves and space gear. Space gear only - no weapons. The duck is the test pilot so the
# variants only differ in suit and helmet.

import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
VARIANTS = ARGS or ["explorer", "ranger", "testpilot", "scout"]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "renders")
os.makedirs(OUT, exist_ok=True)


def hex_rgba(h, a=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)


_mats = {}


def mat(color, rough=0.5, metal=0.0, glass=False, emit=0.0, coat=0.1):
    key = (color, rough, metal, glass, emit, coat)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("M_" + color)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_rgba(color)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
    if glass:
        b.inputs["Transmission Weight"].default_value = 1.0
        b.inputs["IOR"].default_value = 1.2
        b.inputs["Roughness"].default_value = 0.03
    if emit:
        b.inputs["Emission Color"].default_value = hex_rgba(color)
        b.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


def _finish(o, m, subdiv=1):
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = True
    if subdiv:
        s = o.modifiers.new("Subdiv", "SUBSURF")
        s.levels = s.render_levels = subdiv
    return o


def sphere(loc, scale, m, rot=(0, 0, 0), subdiv=1):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = scale
    return _finish(o, m, subdiv)


def box(loc, size, m, rot=(0, 0, 0), bevel=0.12):
    """Hard-edged armour piece: tight bevel, light smoothing (not a bubble)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    bv = o.modifiers.new("Bevel", "BEVEL")
    bv.width = min(size) * bevel
    bv.segments = 3
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = True
    o.modifiers.new("WN", "WEIGHTED_NORMAL")
    return o


def torus(loc, major, minor, m, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=rot,
                                     major_segments=48, minor_segments=12)
    o = bpy.context.object
    o.scale = scale
    return _finish(o, m, 1)


def limb(a, b, r_a, r_b, m, joint=True):
    """Tapered limb segment from a to b (radius r_a -> r_b)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=r_a, radius2=r_b, depth=d.length, location=(a + b) / 2)
    o = bpy.context.object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    _finish(o, m, 1)
    if joint:
        sphere(a, (r_a, r_a, r_a), m)
    return o


def hose(points, radius, m):
    """Flexible hose along a curve (oxygen line, cables)."""
    curve = bpy.data.curves.new("Hose", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 4
    spl = curve.splines.new("BEZIER")
    spl.bezier_points.add(len(points) - 1)
    for bp, p in zip(spl.bezier_points, points):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    o = bpy.data.objects.new("Hose", curve)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(m)
    return o


def cut_sphere(loc, scale, m, cutter_loc, cutter_size):
    """Sphere with a box cut out of it (helmet shell with a face opening)."""
    o = sphere(loc, scale, m, subdiv=1)
    bpy.ops.mesh.primitive_cube_add(size=1, location=cutter_loc)
    c = bpy.context.object
    c.scale = cutter_size
    c.hide_render = True
    c.display_type = "WIRE"
    bo = o.modifiers.new("Cut", "BOOLEAN")
    bo.operation = "DIFFERENCE"
    bo.object = c
    o.modifiers.move(o.modifiers.find("Cut"), 0)
    return o


# --- Scene ------------------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 96
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
    bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
    bpy.context.object.is_shadow_catcher = True
    for loc, energy, size in [((-3.5, -5.0, 8.5), 700, 7.0), ((5.0, -4.0, 4.0), 260, 7.0), ((2.0, 5.0, 6.5), 600, 4.0)]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        lt = bpy.context.object
        lt.data.energy = energy
        lt.data.size = size
        lt.rotation_mode = "QUATERNION"
        lt.rotation_quaternion = (Vector((0, 0, 2.6)) - Vector(loc)).to_track_quat("-Z", "Y")
    sc.render.resolution_x, sc.render.resolution_y = 560, 900
    angle = math.radians(-24)
    loc = Vector((math.sin(angle) * 15.5, -math.cos(angle) * 15.5, 3.4))
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object
    cam.data.lens = 50
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (Vector((0, 0, 2.75)) - loc).to_track_quat("-Z", "Y")
    sc.camera = cam


# --- The duck's head (smaller, grown-up proportions) ---------------------------------------

HEAD = Vector((0, -0.04, 4.55))
K = 0.62  # head size


def duck_head():
    white = mat("ece6da", 0.55)
    sphere(HEAD, (0.95 * K, 0.88 * K, 0.92 * K), white)
    for i, (dx, rz) in enumerate([(-0.08, -0.4), (0.05, 0.0), (0.18, 0.4)]):
        sphere(HEAD + Vector((dx * K, 0, 0.97 * K + 0.05 * (i == 1) * K)), (0.08 * K, 0.08 * K, 0.22 * K), white, rot=(0, rz, 0))
    sphere(HEAD + Vector((0, -0.81 * K, -0.23 * K)), (0.48 * K, 0.32 * K, 0.12 * K), mat("f0893c", 0.3))
    sphere(HEAD + Vector((0, -0.75 * K, -0.35 * K)), (0.38 * K, 0.26 * K, 0.08 * K), mat("c96a2a", 0.35))
    ink = mat("12152a", 0.05, coat=0.8)
    shine = mat("ffffff", 0.2, emit=3.0)
    for s in (-1, 1):
        e = HEAD + Vector((s * 0.36 * K, -0.74 * K, 0.12 * K))
        sphere(e, (0.13 * K, 0.08 * K, 0.16 * K), ink)
        sphere(e + Vector((-0.04 * K, -0.07 * K, 0.06 * K)), (0.04 * K, 0.02 * K, 0.04 * K), shine, subdiv=0)
        sphere(HEAD + Vector((s * 0.6 * K, -0.57 * K, -0.17 * K)), (0.15 * K, 0.04 * K, 0.09 * K), mat("f2a0a8", 0.6), subdiv=0)


# --- Shared astronaut body -----------------------------------------------------------------

def body(suit, suit2, plate, boot, glove, knee=None, shoulder=None):
    """Taller body: hips, torso, tapered arms/legs, boots, gloves. Returns nothing."""
    # Legs
    for s in (-1, 1):
        limb((s * 0.34, 0, 2.15), (s * 0.36, -0.04, 1.2), 0.27, 0.22, suit)
        limb((s * 0.36, -0.04, 1.2), (s * 0.36, 0.02, 0.42), 0.22, 0.18, suit)
        box((s * 0.36, -0.12, 0.22), (0.46, 0.78, 0.42), boot, bevel=0.2)  # boot
        box((s * 0.36, -0.12, 0.05), (0.5, 0.82, 0.1), mat("12152a", 0.7))  # sole
        if knee:
            box((s * 0.36, -0.22, 1.2), (0.36, 0.16, 0.4), knee, bevel=0.3)
    # Hips and torso
    box((0, 0, 2.25), (1.08, 0.66, 0.5), suit2, bevel=0.25)
    box((0, 0, 3.05), (1.3, 0.78, 1.45), suit, bevel=0.22)
    # Arms
    for s in (-1, 1):
        limb((s * 0.82, 0, 3.55), (s * 1.0, -0.06, 2.78), 0.21, 0.18, suit)
        limb((s * 1.0, -0.06, 2.78), (s * 1.02, -0.2, 2.08), 0.18, 0.16, suit)
        box((s * 1.03, -0.22, 1.9), (0.3, 0.3, 0.34), glove, bevel=0.3)  # glove
        torus((s * 1.02, -0.19, 2.12), 0.17, 0.05, plate, rot=(math.radians(-10), 0, 0))  # cuff
        if shoulder:
            box((s * 0.86, 0, 3.62), (0.5, 0.62, 0.3), shoulder, rot=(0, s * math.radians(-18), 0), bevel=0.3)
    # Neck ring
    torus((0, 0, 3.86), 0.42, 0.09, plate)


def backpack(m, size=(1.05, 0.5, 1.3), z=3.1):
    box((0, 0.6, z), size, m, bevel=0.15)


# --- Variants --------------------------------------------------------------------------------

def explorer():
    """Classic white EVA suit, orange trim, clear dome helmet, big life-support pack."""
    white, white2 = mat("e9e6df", 0.55), mat("d6d2c9", 0.6)
    orange = mat("f0893c", 0.45)
    body(white, white2, mat("9aa7b8", 0.35, metal=0.6), boot=white2, glove=orange, knee=white2, shoulder=None)
    backpack(white2, (1.15, 0.6, 1.45))
    box((0, -0.45, 3.1), (0.62, 0.18, 0.42), mat("36405f", 0.4))  # chest control box
    for i, c in enumerate(["ef6a5a", "ffc56b", "4fb8a8"]):
        sphere((-0.18 + i * 0.18, -0.55, 3.18), (0.05, 0.02, 0.05), mat(c, 0.3, emit=1.5), subdiv=0)
    for s in (-1, 1):
        box((s * 0.5, -0.4, 2.62), (0.08, 0.1, 0.9), orange)  # orange stripes
        box((s * 0.36, -0.1, 1.62), (0.48, 0.05, 0.08), orange, rot=(0, 0, 0))
    duck_head()
    sphere(HEAD + Vector((0, 0, 0.05)), (0.95, 0.95, 0.98), mat("dff4f2", glass=True))  # glass dome
    torus((0, 0, 3.92), 0.62, 0.08, mat("9aa7b8", 0.3, metal=0.7))  # helmet ring


def ranger():
    """Armoured ranger: dark suit, chest rig with pouches, shoulder plates, hard helmet, visor up."""
    suit, suit2 = mat("1d4a4c", 0.7), mat("163a3c", 0.7)
    armour = mat("36405f", 0.45)
    pouch = mat("4a5578", 0.6)
    body(suit, suit2, mat("12152a", 0.4), boot=mat("2a2f45", 0.6), glove=mat("12152a", 0.6), knee=armour, shoulder=armour)
    box((0, -0.12, 3.12), (1.38, 0.68, 1.15), armour, bevel=0.12)  # plate carrier
    for i in range(3):
        box((-0.42 + i * 0.42, -0.5, 2.72), (0.34, 0.16, 0.38), pouch, bevel=0.15)  # mag-style pouches
        box((-0.42 + i * 0.42, -0.5, 2.92), (0.34, 0.17, 0.06), armour)
    box((0.3, -0.48, 3.42), (0.36, 0.12, 0.26), mat("4fb8a8", 0.4, emit=0.6))  # chest screen
    box((0, 0, 2.38), (1.15, 0.72, 0.16), mat("12152a", 0.5))  # belt
    for s in (-1, 1):
        box((s * 0.6, -0.3, 2.15), (0.28, 0.2, 0.34), pouch, bevel=0.15)  # thigh pouches
    backpack(armour, (0.95, 0.42, 1.1))
    duck_head()
    shell = cut_sphere(HEAD + Vector((0, 0.04, 0.06)), (0.82, 0.8, 0.84), mat("2a2f45", 0.35),
                       HEAD + Vector((0, -0.75, -0.2)), (1.1, 0.9, 1.0))
    box(HEAD + Vector((0, -0.62, 0.55)), (0.95, 0.28, 0.22), mat("f0893c", 0.1, coat=0.8), rot=(math.radians(-35), 0, 0))  # visor up
    for s in (-1, 1):
        box(HEAD + Vector((s * 0.78, 0.05, 0.0)), (0.14, 0.4, 0.4), armour, bevel=0.3)  # ear plates
    torus((0, 0, 3.9), 0.46, 0.1, armour)


def testpilot():
    """Orange flight suit, white hard helmet with a tinted visor, harness, oxygen hose, patches."""
    orange, orange2 = mat("f0893c", 0.65), mat("d06f2c", 0.65)
    white = mat("e9e6df", 0.35)
    ink = mat("12152a", 0.6)
    body(orange, orange2, white, boot=mat("2a2f45", 0.55), glove=white, knee=orange2)
    for s in (-1, 1):  # harness straps
        box((s * 0.35, -0.42, 3.05), (0.14, 0.06, 1.45), ink, rot=(0, s * math.radians(8), 0))
        box((s * 0.36, -0.2, 2.02), (0.5, 0.05, 0.12), ink)
    box((0, -0.43, 2.55), (0.3, 0.08, 0.28), mat("9aa7b8", 0.3, metal=0.7))  # harness buckle
    box((0.42, -0.42, 3.42), (0.26, 0.04, 0.18), mat("5aa9e6", 0.5))  # patch
    box((-0.42, -0.42, 3.42), (0.26, 0.04, 0.18), mat("ffc56b", 0.5))  # patch
    backpack(mat("4a5578", 0.5), (0.8, 0.35, 0.9), z=3.2)
    duck_head()
    cut_sphere(HEAD + Vector((0, 0.03, 0.06)), (0.8, 0.8, 0.84), white, HEAD + Vector((0, -0.78, -0.18)), (1.0, 0.9, 0.95))
    sphere(HEAD + Vector((0, -0.4, 0.35)), (0.72, 0.5, 0.32), mat("2c6d6f", glass=True))  # tinted visor
    hose([(0.25, -0.5, 2.75), (0.6, -0.7, 3.4), (0.5, -0.55, 4.05), (0.3, -0.6, 4.25)], 0.06, mat("36405f", 0.6))
    torus((0, 0, 3.9), 0.44, 0.09, white)


def scout():
    """Sleek teal suit with glowing aqua strips, slim helmet with collar, small thrusters."""
    teal, teal2 = mat("2c6d6f", 0.4), mat("1d4a4c", 0.45)
    glow = mat("4fb8a8", 0.3, emit=2.5)
    navy = mat("1b2140", 0.4)
    body(teal, teal2, navy, boot=navy, glove=navy, knee=navy)
    for s in (-1, 1):
        box((s * 0.34, -0.4, 3.05), (0.06, 0.05, 1.2), glow)  # chest light strips
        box((s * 0.38, -0.22, 1.7), (0.05, 0.05, 0.7), glow)  # leg strips
        limb((s * 0.32, 0.62, 2.8), (s * 0.32, 0.62, 3.5), 0.16, 0.18, navy)  # thrusters
        sphere((s * 0.32, 0.62, 2.72), (0.13, 0.13, 0.06), mat("f0893c", 0.3, emit=3.0))
    box((0, -0.42, 2.45), (0.5, 0.08, 0.16), glow)  # belt light
    duck_head()
    sphere(HEAD + Vector((0, 0.0, 0.05)), (0.86, 0.86, 0.9), mat("e6f6f3", glass=True))
    torus((0, 0, 3.92), 0.52, 0.12, navy)
    torus((0, 0, 3.92), 0.53, 0.03, glow)


BUILD = {"explorer": explorer, "ranger": ranger, "testpilot": testpilot, "scout": scout}

for v in VARIANTS:
    reset()
    BUILD[v]()
    bpy.context.scene.render.filepath = os.path.join(OUT, f"astro_{v}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", v)

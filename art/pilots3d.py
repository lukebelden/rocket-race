# Rocket Race - 3D toy-style pilots, built from code in Blender and rendered to PNGs.
#
# Run (from the project folder):
#   "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" -b -P art/pilots3d.py -- duck
# Renders art/renders/<animal>_full.png (whole pilot) and <animal>_face.png (head close-up)
# with a transparent background and a soft floor shadow.
#
# Style: soft, rounded "vinyl toy" shapes with gentle studio light (the look the game is
# going for). The design is our own: animal pilots in a teal flight suit, slate vest with
# pouches and a chest strap, belt, scarf, gloves and goggles.

import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ANIMAL = ARGS[0] if ARGS else "duck"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "renders")
os.makedirs(OUT, exist_ok=True)

# Palette (matches palette.gd)
C = {
    "suit": "2c6d6f", "vest": "36405f", "pouch": "4a5578", "ink": "12152a", "amber": "ffc56b",
    "orange": "f0893c", "lens": "2c6d6f", "frame": "4a5578", "white": "f4f1ea", "cheek": "f2a0a8",
}


def hex_rgba(h, a=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)


_mats = {}


def mat(name, color, rough=0.45, sss=0.0, gloss=False, emit=0.0):
    key = (name, color, rough, gloss, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hex_rgba(color)
    b.inputs["Roughness"].default_value = 0.12 if gloss else rough
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = 0.6 if gloss else 0.15
    if sss and "Subsurface Weight" in b.inputs:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = (0.3, 0.2, 0.15)
    if emit and "Emission Strength" in b.inputs:
        b.inputs["Emission Color"].default_value = hex_rgba(color)
        b.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


def finish(obj, material, subdiv=2, smooth=True):
    obj.data.materials.append(material)
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    if subdiv:
        mod = obj.modifiers.new("Subdiv", "SUBSURF")
        mod.levels = subdiv
        mod.render_levels = subdiv
    return obj


def sphere(loc, scale, material, rot=(0, 0, 0), subdiv=1):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = scale
    return finish(o, material, subdiv)


def rbox(loc, size, material, rot=(0, 0, 0), bevel=0.3):
    """Rounded box: cube + bevel + subdivision (soft toy edges)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    b = o.modifiers.new("Bevel", "BEVEL")
    b.width = min(size) * bevel
    b.segments = 3
    return finish(o, material, 2)


def torus(loc, major, minor, material, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=rot,
                                     major_segments=48, minor_segments=16)
    o = bpy.context.object
    o.scale = scale
    return finish(o, material, 1)


def capsule(a, b, radius, material):
    """Rounded limb from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=d.length, location=(a + b) / 2)
    o = bpy.context.object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    finish(o, material, 1)
    sphere(a, (radius, radius, radius), material)
    sphere(b, (radius, radius, radius), material)
    return o


# --- Scene ------------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"  # keep palette colours true
    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = hex_rgba("cfe3e6")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    # Floor that only catches the soft shadow.
    bpy.ops.mesh.primitive_plane_add(size=5, location=(0, 0, 0))
    bpy.context.object.is_shadow_catcher = True
    # Soft studio lights: big key from front-left above, fill from right, rim from behind.
    for name, loc, energy, size in [("Key", (-3.0, -4.0, 7.5), 520, 7.0), ("Fill", (4.5, -3.5, 3.5), 220, 7.0),
                                    ("Rim", (1.5, 4.5, 5.0), 380, 4.0)]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = size
        light.rotation_mode = "QUATERNION"
        light.rotation_quaternion = (Vector((0, 0, 1.4)) - Vector(loc)).to_track_quat("-Z", "Y")


def camera(target, distance, height, lens, res):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = res
    angle = math.radians(-22)  # three-quarter view
    loc = Vector((math.sin(angle) * distance, -math.cos(angle) * distance, height))
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object
    cam.data.lens = lens
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (Vector(target) - loc).to_track_quat("-Z", "Y")
    sc.camera = cam
    return cam


# --- The pilot ----------------------------------------------------------------------------

def build_body(feet="boots"):
    suit = mat("Suit", C["suit"], 0.6)
    suit_dark = mat("SuitDark", "1d4a4c", 0.6)
    vest = mat("Vest", C["vest"], 0.55)
    pouch = mat("Pouch", C["pouch"], 0.5)
    ink = mat("Ink", C["ink"], 0.4)
    amber = mat("Amber", C["amber"], 0.3)
    scarf = mat("Scarf", C["orange"], 0.7)

    # Legs and feet
    for s in (-1, 1):
        capsule((s * 0.32, 0, 0.45), (s * 0.32, 0, 0.95), 0.2, suit_dark)
        if feet == "webbed":
            sphere((s * 0.36, -0.18, 0.12), (0.3, 0.42, 0.12), mat("Feet", C["orange"], 0.35))
        else:
            sphere((s * 0.34, -0.12, 0.2), (0.26, 0.36, 0.2), ink)
    # Torso (suit) and vest over it
    sphere((0, 0, 1.55), (0.72, 0.6, 0.78), suit, subdiv=1)
    rbox((0, -0.26, 1.58), (1.2, 0.5, 0.95), vest, bevel=0.35)
    for s in (-1, 1):
        rbox((s * 0.3, -0.53, 1.32), (0.32, 0.12, 0.3), pouch, bevel=0.3)
    rbox((0.05, -0.53, 1.68), (0.14, 0.06, 1.15), ink, rot=(0, math.radians(38), 0), bevel=0.4)  # chest strap
    torus((0, 0, 1.06), 0.66, 0.08, ink, scale=(1.0, 0.85, 1.0))  # belt
    rbox((0, -0.58, 1.06), (0.22, 0.08, 0.16), amber, bevel=0.3)  # buckle
    # Arms with gloves
    for s in (-1, 1):
        capsule((s * 0.7, -0.05, 1.95), (s * 0.95, -0.15, 1.35), 0.17, suit)
        sphere((s * 0.98, -0.18, 1.22), (0.2, 0.2, 0.2), ink)
    # Scarf around the neck, tail flicking to the side
    torus((0, -0.02, 2.22), 0.5, 0.14, scarf, scale=(1.0, 0.85, 1.0))
    rbox((0.42, -0.42, 2.0), (0.22, 0.08, 0.5), scarf, rot=(math.radians(10), math.radians(-25), 0), bevel=0.4)


def goggles(head_center, head_scale, tilt=0.0):
    """Goggles pushed up on the forehead: strap around the head, two lenses in frames."""
    hx, hy, hz = head_center
    frame = mat("Frame", C["frame"], 0.35)
    lens = mat("Lens", C["lens"], 0.1, gloss=True)
    strap = mat("Strap", C["ink"], 0.6)
    lift = 0.5  # how far up the head the strap sits (0 = middle, 1 = top)
    z = hz + head_scale[2] * lift
    ring = math.sqrt(max(1.0 - lift * lift, 0.0)) * 1.02  # head radius at that height
    torus((hx, hy, z), 1.0, 0.06, strap, scale=(head_scale[0] * ring, head_scale[1] * ring, 1.0))
    for s in (-1, 1):
        p = (hx + s * 0.3, hy - head_scale[1] * ring * 0.96, z + 0.02)
        torus(p, 0.2, 0.06, frame, rot=(math.radians(78), 0, 0))
        sphere((p[0], p[1] - 0.02, p[2]), (0.18, 0.08, 0.18), lens)


def eyes(head_center, spread, height, forward, size=0.16):
    black = mat("Eye", C["ink"], 0.05, gloss=True)
    shine = mat("Shine", "ffffff", 0.2, emit=3.0)
    hx, hy, hz = head_center
    for s in (-1, 1):
        e = (hx + s * spread, hy - forward, hz + height)
        sphere(e, (size * 0.85, size * 0.5, size), black)
        sphere((e[0] - 0.05, e[1] - size * 0.42, e[2] + size * 0.4), (0.05, 0.03, 0.05), shine, subdiv=0)
        sphere((e[0] + 0.05, e[1] - size * 0.45, e[2] - size * 0.35), (0.025, 0.02, 0.025), shine, subdiv=0)


def duck():
    build_body(feet="webbed")
    white = mat("Feathers", "ece6da", 0.55, sss=0.1)
    head_c, head_s = (0, -0.05, 3.05), (0.95, 0.88, 0.92)
    sphere(head_c, head_s, white, subdiv=1)
    # Feather tuft
    for i, (dx, rz) in enumerate([(-0.08, -0.4), (0.05, 0.0), (0.18, 0.4)]):
        sphere((dx, -0.05, 4.02 + 0.06 * (i == 1)), (0.08, 0.08, 0.22), white, rot=(0, rz, 0))
    # Broad flat bill: upper and lower halves
    bill = mat("Bill", C["orange"], 0.3)
    sphere((0, -0.86, 2.82), (0.48, 0.32, 0.12), bill)
    sphere((0, -0.8, 2.7), (0.38, 0.26, 0.08), mat("BillDark", "c96a2a", 0.35))
    eyes(head_c, 0.36, 0.12, 0.74)
    blush = mat("Cheek", C["cheek"], 0.6)
    for s in (-1, 1):
        sphere((s * 0.6, -0.62, 2.88), (0.16, 0.05, 0.1), blush, subdiv=0)
    goggles(head_c, head_s)
    return head_c


BUILDERS = {"duck": duck}


def main():
    reset_scene()
    head = BUILDERS[ANIMAL]()
    sc = bpy.context.scene
    # Whole pilot
    cam = camera((0, 0, 2.05), 8.6, 2.6, 50, (640, 800))
    sc.render.filepath = os.path.join(OUT, f"{ANIMAL}_full.png")
    bpy.ops.render.render(write_still=True)
    # Head close-up (for HUD cards / icons)
    bpy.data.objects.remove(cam)
    camera((head[0], head[1], head[2] - 0.1), 4.6, head[2] + 0.3, 50, (512, 512))
    sc.render.filepath = os.path.join(OUT, f"{ANIMAL}_face.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", ANIMAL)


main()

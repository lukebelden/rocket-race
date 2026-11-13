# Rocket Race - 2D "sticker" style astronaut pilots, rendered from 3D in Blender.
#
#   "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" -b -P art/toon.py -- duck cat ...
# (no names = all eight). Writes art/renders/toon_<animal>_full.png and _face.png.
#
# Same sculpted heads as explorers.py, on a chibi body (big head, short round suit, helmet
# ring + bubble). Rendered in EEVEE with cel shading (flat colour + one hard shadow tone)
# and inverted-hull ink outlines, so it reads as flat 2D cartoon art.

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import explorers as X  # noqa: E402  (reuses shape helpers + head builders)

ANIMALS = X.ARGS or X.ALL
OUT = X.OUT
INK = "0b0d1a"

# Chibi proportions: the head is about as big as the whole body.
X.HEAD = Vector((0, -0.02, 2.35))
X.K = 0.95
HEAD = X.HEAD

def big_eyes(spread=0.36, h=0.12, fwd=0.74, size=0.16, mask=None):
    """Cartoon eyes: tall glossy ovals with a big and a small white highlight."""
    ink = X.mat("12152a", 0.3, emit=1.0)  # flat, unshaded
    white = X.mat("ffffff", 0.3, emit=1.0)
    size *= 1.3
    for s in (-1, 1):
        if mask:
            X.detail(X.P(s * spread * 1.05, -fwd + 0.06, h), X.S(0.33, 0.1, 0.25), mask, rot=(0, 0, s * 0.25))
        e = X.P(s * spread * 1.05, -fwd, h)
        X.detail(e, X.S(size * 0.8, size * 0.45, size), ink)
        front = e + Vector((0, -size * 0.45 * X.K, 0))
        X.detail(front + Vector(X.S(-size * 0.28, -0.01, size * 0.35)), X.S(size * 0.3, 0.02, size * 0.3), white, subdiv=0)
        X.detail(front + Vector(X.S(size * 0.3, -0.01, -size * 0.4)), X.S(size * 0.14, 0.02, size * 0.14), white, subdiv=0)


X.eyes = big_eyes


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    X._mats.clear()
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(-35)))
    sun = bpy.context.object
    sun.data.energy = 2.6
    sun.data.angle = math.radians(3)
    sun.data.use_shadow = False  # flat cel look: no cast shadows (glass dome, ring)


# --- Chibi astronaut suit ------------------------------------------------------------------

def chibi_suit(trim_hex):
    white = X.mat("f1eee8", 0.6)
    grey = X.mat("c7ccd6", 0.6)
    trim = X.mat(trim_hex, 0.5)
    dark = X.mat("36405f", 0.5)
    blob, slab, ring, tube, fuse, detail = X.blob, X.slab, X.ring, X.tube, X.fuse, X.detail

    parts = [blob((0, 0, 1.0), (0.66, 0.52, 0.62)), blob((0, 0, 0.62), (0.58, 0.48, 0.4))]
    for s in (-1, 1):
        parts += tube((s * 0.56, 0, 1.28), (s * 0.82, -0.12, 0.9), 0.19, 0.16)
        parts += tube((s * 0.27, 0, 0.55), (s * 0.29, -0.04, 0.22), 0.2, 0.19)
        parts.append(ring((s * 0.28, -0.03, 0.36), 0.2, 0.04))  # knee rib
    fuse(parts, white, voxel=0.022, smooth=0.7, name="Suit")

    boots = []
    for s in (-1, 1):
        boots += [blob((s * 0.29, -0.1, 0.15), (0.24, 0.33, 0.17)), blob((s * 0.29, 0.0, 0.2), (0.21, 0.22, 0.16))]
    fuse(boots, grey, voxel=0.022, smooth=0.6, name="Boots")
    fuse([blob((s * 0.29, -0.07, 0.05), (0.25, 0.35, 0.06)) for s in (-1, 1)], dark, voxel=0.018, smooth=0.4, name="Soles")

    gloves = []
    for s in (-1, 1):
        gloves += [blob((s * 0.85, -0.16, 0.78), (0.17, 0.15, 0.19)), blob((s * 0.75, -0.25, 0.84), (0.07, 0.06, 0.08)),
                   ring((s * 0.83, -0.13, 0.91), 0.155, 0.05)]
    fuse(gloves, trim, voxel=0.018, smooth=0.5, name="Gloves")

    fuse([slab((0, 0.48, 1.1), (0.95, 0.4, 0.95))], grey, voxel=0.025, smooth=0.5, name="Pack")
    fuse([ring((0, 0, 0.74), 0.6, 0.055, scale=(1.0, 0.84, 1.0))], trim, voxel=0.018, smooth=0.4, name="Belt")
    fuse([slab((0, -0.47, 1.04), (0.46, 0.14, 0.3))], dark, voxel=0.02, smooth=0.35, name="ChestBox")
    for i, c in enumerate(["ef6a5a", "ffc56b", "4fb8a8"]):
        detail((-0.12 + i * 0.12, -0.55, 1.07), (0.04, 0.02, 0.04), X.mat(c, 0.3, emit=1.5), subdiv=0)
    detail((0.34, -0.4, 1.24), (0.1, 0.03, 0.1), trim, rot=(0, 0, 0.5))  # mission patch

    # Helmet: dark collar, metal ring, glass bubble with an ink rim and a shine.
    fuse([blob((0, 0, 1.55), (0.55, 0.5, 0.15))], X.mat("4a5578", 0.6), voxel=0.022, smooth=0.5, name="Collar")
    fuse([ring((0, 0, 1.52), 0.6, 0.09)], X.mat("aeb9cc", 0.4), voxel=0.018, smooth=0.3, name="Ring")
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, location=HEAD + Vector((0, 0, 0.03)),
                                         radius=X.K * 1.1)
    dome = bpy.context.object
    dome.name = "Dome"
    for p in dome.data.polygons:
        p.use_smooth = True
    dome.data.materials.append(glass_mat())
    d = Vector((-0.72, -0.42, 0.55)).normalized()
    shine = detail(HEAD + Vector((0, 0, 0.03)) + d * X.K * 1.1, (0.24, 0.05, 0.02), X.mat("ffffff", emit=1.0))
    shine.name = "Shine"
    shine.rotation_mode = "QUATERNION"
    shine.rotation_quaternion = d.to_track_quat("Z", "Y")


def glass_mat():
    m = bpy.data.materials.new("Glass")
    m.use_nodes = True
    try:
        m.surface_render_method = "BLENDED"
    except AttributeError:
        m.blend_method = "BLEND"
    m.use_backface_culling = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    ramp.color_ramp.elements[1].position = 0.9
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(lw.outputs["Facing"], ramp.inputs["Fac"])
    tint = nt.nodes.new("ShaderNodeEmission")
    tint.inputs["Color"].default_value = X.hex_rgba("dff3f6")
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    glassy = nt.nodes.new("ShaderNodeMixShader")
    glassy.inputs["Fac"].default_value = 0.05
    nt.links.new(clear.outputs[0], glassy.inputs[1])
    nt.links.new(tint.outputs[0], glassy.inputs[2])
    rim = nt.nodes.new("ShaderNodeEmission")
    rim.inputs["Color"].default_value = X.hex_rgba("bfe3ea")  # pale glass rim: reads on dark and light
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(ramp.outputs["Color"], mix.inputs["Fac"])
    nt.links.new(glassy.outputs[0], mix.inputs[1])
    nt.links.new(rim.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return m


# --- Toon conversion ---------------------------------------------------------------------

def toonify(m):
    nt = m.node_tree
    if not nt:
        return
    b = nt.nodes.get("Principled BSDF")
    if not b:
        return
    base = tuple(b.inputs["Base Color"].default_value)
    glowing = b.inputs["Emission Strength"].default_value > 0
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    if glowing:
        em.inputs["Color"].default_value = base
        return
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(diff.outputs[0], s2r.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = X.hex_rgba("a3acd0")  # cool shadow tone
    ramp.color_ramp.elements[1].position = 0.42
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    mul.inputs[0].default_value = base[:3]
    nt.links.new(ramp.outputs["Color"], mul.inputs[1])
    nt.links.new(mul.outputs[0], em.inputs["Color"])


def ink_outlines(thickness):
    ink = bpy.data.materials.new("Ink")
    ink.use_nodes = True
    ink.use_backface_culling = True
    nt = ink.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = X.hex_rgba(INK)
    nt.links.new(em.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    curves = [o for o in bpy.data.objects if o.type == "CURVE"]
    if curves:
        bpy.ops.object.select_all(action="DESELECT")
        for c in curves:
            c.select_set(True)
        bpy.context.view_layer.objects.active = curves[0]
        bpy.ops.object.convert(target="MESH")
    for o in bpy.data.objects:
        if o.type != "MESH" or o.name.startswith(("Dome", "Shine")) or max(o.scale) < 0.05:
            continue
        for m in o.data.materials:
            if m:
                m.use_backface_culling = True
        o.data.materials.append(ink)
        sol = o.modifiers.new("Outline", "SOLIDIFY")
        sol.thickness = thickness
        sol.offset = 1.0
        sol.use_flip_normals = True
        sol.use_rim = False
        sol.material_offset = len(o.data.materials) - 1


def shoot(target, scale, res, path):
    sc = bpy.context.scene
    for o in [o for o in bpy.data.objects if o.type == "CAMERA"]:
        bpy.data.objects.remove(o)
    sc.render.resolution_x, sc.render.resolution_y = res
    a = math.radians(-22)
    loc = Vector(target) + Vector((math.sin(a) * 20, -math.cos(a) * 20, 5.0))
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = scale
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (Vector(target) - loc).to_track_quat("-Z", "Y")
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


for animal in ANIMALS:
    reset()
    chibi_suit(X.TRIM[animal])
    X.HEADS[animal]()
    for m in list(bpy.data.materials):
        if m.name not in ("Glass",):
            toonify(m)
    ink_outlines(0.034)
    shoot((0, 0, 1.68), 3.75, (560, 820), os.path.join(OUT, f"toon_{animal}_full.png"))
    shoot(HEAD + Vector((0, 0, -0.25)), 2.7, (512, 512), os.path.join(OUT, f"toon_{animal}_face.png"))
    print("RENDERED", animal)

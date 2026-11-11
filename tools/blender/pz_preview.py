"""Render the machines for the Workshop preview (tools/make-preview.ps1).

  blender -b --factory-startup --python tools/blender/pz_preview.py -- <media dir> <out.png> [size] [samples]

Draws the mod's own fourteen models (media/models_X/TLG, each with its
media/textures/TLG texture) at their in-game scales (media/scripts/
TLG_models.txt) on a shadow-catching floor, in Cycles, with a transparent
background: the floor keeps only the shadows. The machines stand in three
rows, the tall ones at the back, and the small items lie in front of them:
a 35 mm lens close to the group draws those larger than a long lens would.
A low warm light from behind and a cool fill from the front. The camera
frames the group in the lower part of the picture, leaving the top for the
title that make-preview.ps1 draws. [samples] (default 96) sets the Cycles
samples: a low number gives a quick draft while the layout is tuned. No
game asset is drawn.
"""
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

# name, in-game scale, (x, y) on the floor in metres, turn about Z in degrees
LAYOUT = (
    # The back row: the tall machines.
    ("WoodRetort", 0.87, (-0.95, 1.30), 0.0),
    ("BiodieselWashTank", 1.0, (0.35, 1.40), 0.0),
    ("RefluxStill", 0.9, (1.05, 1.35), -15.0),
    # The middle row.
    ("AshBarrel", 0.6, (-1.55, 0.40), 20.0),
    ("BiodieselReactor", 0.77, (-0.08, 0.30), 0.0),
    ("Fermenter", 0.5, (0.50, -0.05), 25.0),
    ("DryingColumn", 0.55, (0.95, 0.40), -30.0),
    ("LyeLeacher", 0.73, (1.55, 0.50), 180.0),
    # The front row, nearest the camera: the pot still and the small items.
    ("PotStill", 0.7, (1.10, -0.55), -25.0),
    ("ManualFuelSystems", 0.16, (-0.80, -0.95), 20.0),
    ("FuelSampleKit", 0.225, (-0.40, -1.00), 0.0),
    ("YeastStarter", 0.108, (-0.02, -1.10), 0.0),
    ("FuelStabilizer", 0.115, (0.25, -0.95), 0.0),
    ("FuelFilter", 0.1, (0.50, -1.10), 10.0),
)
# The group spans this much of the frame's width, its feet this far up.
SPAN, FEET, TOP = 0.92, 0.05, 0.66


def _material(name, texture):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(texture)
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7
    return mat


def _place(media, name, scale, xy, turn):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(media, "models_X", "TLG", name + ".fbx"))
    new = [o for o in bpy.context.scene.objects if o not in before]
    mat = _material(name, os.path.join(media, "textures", "TLG", name + ".png"))
    holder = bpy.data.objects.new(name + "_at", None)
    bpy.context.scene.collection.objects.link(holder)
    for o in new:
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(mat)
        if o.parent is None:
            o.parent = holder
    holder.scale = (scale, scale, scale)
    holder.location = (xy[0], xy[1], 0.0)
    holder.rotation_euler = (0.0, 0.0, math.radians(turn))
    return [o for o in new if o.type == "MESH"]


def _sun(name, direction, energy, colour):
    light = bpy.data.lights.new(name, "SUN")
    light.energy = energy
    light.color = colour
    light.angle = math.radians(3.0)
    obj = bpy.data.objects.new(name, light)
    obj.rotation_euler = (-Vector(direction).normalized()).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(obj)


def _bounds(cam, pts):
    scene = bpy.context.scene
    bpy.context.view_layer.update()
    uv = [world_to_camera_view(scene, cam, p) for p in pts]
    return min(c.x for c in uv), max(c.x for c in uv), min(c.y for c in uv), max(c.y for c in uv)


def render(media, out, size=1024, samples=96):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    meshes = []
    for name, scale, xy, turn in LAYOUT:
        meshes += _place(media, name, scale, xy, turn)
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]

    bpy.ops.mesh.primitive_plane_add(size=40.0, location=(0.0, 0.0, 0.0))
    floor = bpy.context.active_object
    floor.is_shadow_catcher = True

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.20, 0.17, 0.14, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35

    # Warm, low, from behind on the left; a cool fill from the front right.
    _sun("key", (0.55, -0.85, 0.30), 4.5, (1.0, 0.62, 0.32))
    _sun("fill", (-0.8, -0.6, -0.45), 1.2, (0.62, 0.72, 1.0))
    _sun("top", (0.0, 0.0, -1.0), 0.6, (1.0, 0.92, 0.82))

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 35.0
    cam_data.sensor_fit = "HORIZONTAL"
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    centre = Vector((sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts), 0.35))
    view = Vector((0.22, -1.0, 0.50)).normalized()
    cam.rotation_euler = (-view).to_track_quat("-Z", "Y").to_euler()
    lo, hi = 0.5, 30.0
    for _ in range(40):
        dist = (lo + hi) / 2
        cam.location = centre + view * dist
        cam_data.shift_x = cam_data.shift_y = 0.0
        x0, x1, y0, y1 = _bounds(cam, pts)
        if x1 - x0 > SPAN or y1 - y0 > TOP - FEET:
            lo = dist
        else:
            hi = dist
    cam.location = centre + view * hi
    x0, x1, y0, y1 = _bounds(cam, pts)
    cam_data.shift_x = (x0 + x1) / 2 - 0.5
    cam_data.shift_y = y0 - FEET
    x0, x1, y0, y1 = _bounds(cam, pts)

    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PZP wrote %s: %dx%d, group spans x %.3f..%.3f y %.3f..%.3f, camera %.2f m from the group" % (
        out, size, size, x0, x1, y0, y1, hi))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    render(args[0], args[1], int(args[2]) if len(args) > 2 else 1024, int(args[3]) if len(args) > 3 else 96)

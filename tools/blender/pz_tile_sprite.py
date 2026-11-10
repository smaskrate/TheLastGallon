"""Renders a shape built by pz_icon_props.py as a tile sprite of the game.

Usage: blender -b --factory-startup --python pz_tile_sprite.py -- <prop name> <out.png> [azimuth]

The picture is 128 by 256 pixels, the size of one tile's sprite at the
game's 2x tiles: the tile's floor is the diamond in the bottom 64 rows, its
centre 32 pixels above the bottom edge in the middle column. The view is
the game's: orthographic, from 30 degrees above the ground (a 2:1
diamond), turned 45 degrees, one tile side (1 unit of the shape, taken as
a metre) 90.51 pixels along the diamond's edge. The shape stands on the
tile's centre. `azimuth` turns the view round the shape (default 45: its
front, -Y, and its right side are seen).

The picture is not in a texture pack: the mod's tile definitions name the
sprite (tools/make-tile-sprites.ps1) and the mod's Lua gives it this
picture with IsoSprite.LoadSingleTexture (Generators.loadSprites).
"""
import math
import os
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pz_icon_props  # noqa: E402

WIDTH, HEIGHT, SUPER = 128, 256, 4
PIXELS_PER_UNIT = 128.0 / math.sqrt(2.0)
ORIGIN_ABOVE_BOTTOM = 32


def render(name, out, azimuth=45.0):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    pz_icon_props.ICON_ONLY[name]()
    bpy.context.view_layer.update()
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = WIDTH * SUPER, HEIGHT * SUPER
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.3, 0.3, 0.3, 1.0)

    a, e = math.radians(azimuth), math.radians(30.0)
    view = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    rot = (-view).to_track_quat("-Z", "Y")
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    # ortho_scale spans the larger side of the picture, its height.
    cam_data.ortho_scale = HEIGHT / PIXELS_PER_UNIT
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    # The tile's centre sits ORIGIN_ABOVE_BOTTOM pixels above the bottom edge.
    cam.location = up * ((HEIGHT / 2 - ORIGIN_ABOVE_BOTTOM) / PIXELS_PER_UNIT) + view * 20.0
    cam.rotation_euler = rot.to_euler()
    cam_data.clip_end = 60.0
    scene.camera = cam
    for lname, direction, energy in (("key", -right + up * 1.2 + view * 0.8, 2.2), ("fill", right + view * 0.5, 0.7)):
        light = bpy.data.lights.new(lname, "SUN")
        light.energy = energy
        obj = bpy.data.objects.new(lname, light)
        obj.rotation_euler = (-direction.normalized()).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(obj)

    big = os.path.join(tempfile.mkdtemp(prefix="pz_tile_"), "render.png")
    scene.render.filepath = big
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(big)
    px = np.array(img.pixels[:], dtype=np.float64).reshape(HEIGHT, SUPER, WIDTH, SUPER, 4)
    alpha = px[..., 3].mean(axis=(1, 3))
    rgb = (px[..., :3] * px[..., 3:4]).sum(axis=(1, 3)) / np.maximum(px[..., 3].sum(axis=(1, 3)), 1e-9)[..., None]
    tile = np.zeros((HEIGHT, WIDTH, 4))
    tile[..., :3] = rgb
    tile[..., 3] = np.where(alpha >= 0.5, 1.0, 0.0)
    tile[tile[..., 3] == 0.0] = 0.0
    solid = tile[..., 3] > 0
    rows, cols = np.where(solid)
    small = bpy.data.images.new("tile", WIDTH, HEIGHT, alpha=True)
    small.pixels = tile.reshape(-1).tolist()
    small.filepath_raw = out
    small.file_format = "PNG"
    small.save()
    # Rows are counted from the bottom edge, as Blender stores them.
    print("PZT wrote %s: %dx%d, %d pixels solid, columns %d..%d, rows %d..%d from the bottom; engine %s" % (
        out, WIDTH, HEIGHT, int(solid.sum()), cols.min(), cols.max(), rows.min(), rows.max(), scene.render.engine))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    render(args[0], args[1], float(args[2]) if len(args) > 2 else 45.0)

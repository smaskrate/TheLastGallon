"""Render an inventory icon (32x32 RGBA PNG) from one of the mod's models.

  blender -b --factory-startup --python tools/blender/pz_icon.py -- <model.fbx> <texture.png> <out.png> [azimuth] [elevation]

The model is drawn with its own texture, orthographic, from `azimuth`
degrees round from its front (the side Blender's FBX import turns to -Y;
positive turns the view to the model's right) and `elevation` degrees
above, lit from the upper left as the game's icons are, and rendered at
eight times the size. Each 8x8 block is then averaged (weighted by
coverage) into one pixel, a pixel is kept whole where the block is at
least half covered and dropped elsewhere, the kept pixels' contrast is
raised a quarter and their colours reduced to twelve, and a one-pixel
outline in the fermenter icon's #1E150C (Item_TLG_Fermenter.png,
tools/make-icons.ps1) goes round the outside: hard edges and a few flat
tones, like the drawn icon. The model fills 30 of the 32 pixels across
its larger side, leaving room for the outline. Two renders of the same
inputs gave the same icon, though the large Eevee renders differed in a
few pixels. The large render goes to a temporary folder, never beside
the icon.
"""
import math
import os
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Vector

SIZE, SUPER, FILL = 32, 8, 30
COLOURS, CONTRAST = 12, 1.25
OUTLINE = (0x1E / 255.0, 0x15 / 255.0, 0x0C / 255.0, 1.0)


def _material(texture):
    mat = bpy.data.materials.new("icon")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(texture)
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    return mat


def _flatten(colours, count=COLOURS, contrast=CONTRAST):
    """The solid pixels' colours with their spread round the mean raised by
    `contrast`, then reduced to `count` colours (k-means, seeded from
    evenly spaced pixels by brightness), as a drawn icon has a few flat
    tones rather than a render's blur."""
    c = np.clip(colours.mean(axis=0) + (colours - colours.mean(axis=0)) * contrast, 0.0, 1.0)
    order = np.argsort(c.sum(axis=1))
    centres = c[order[np.linspace(0, len(c) - 1, min(count, len(c))).astype(int)]]
    for _ in range(20):
        label = ((c[:, None, :] - centres[None, :, :]) ** 2).sum(axis=2).argmin(axis=1)
        for k in range(len(centres)):
            if (label == k).any():
                centres[k] = c[label == k].mean(axis=0)
    return centres[label]


def render(fbx, texture, out, azimuth=15.0, elevation=20.0):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fbx)
    mat = _material(texture)
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(mat)
    render_scene(out, azimuth, elevation)


def render_scene(out, azimuth=15.0, elevation=20.0):
    """Every mesh in the current scene, with its own materials, rendered and
    reduced to the icon `out` as the module docstring says (tools/blender/
    pz_icon_props.py builds scenes for items that have no model)."""
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]

    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = SIZE * SUPER
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.18, 0.18, 0.18, 1.0)

    a, e = math.radians(azimuth), math.radians(elevation)
    view = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    rot = (-view).to_track_quat("-Z", "Y")
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    xs, ys = [p.dot(right) for p in pts], [p.dot(up) for p in pts]
    centre = right * (min(xs) + max(xs)) / 2 + up * (min(ys) + max(ys)) / 2
    depth = max(p.dot(view) for p in pts)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(max(xs) - min(xs), max(ys) - min(ys)) * SIZE / FILL
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = centre + view * (depth + 10.0)
    cam.rotation_euler = rot.to_euler()
    cam_data.clip_end = depth + 30.0
    scene.camera = cam

    # Key light from the upper left of the view, a weaker fill from the right.
    for name, direction, energy in (("key", -right + up * 1.2 + view * 0.8, 2.0), ("fill", right + view * 0.5, 0.5)):
        light = bpy.data.lights.new(name, "SUN")
        light.energy = energy
        obj = bpy.data.objects.new(name, light)
        obj.rotation_euler = (-direction.normalized()).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(obj)

    big_path = os.path.join(tempfile.mkdtemp(prefix="pz_icon_"), "render.png")
    scene.render.filepath = big_path
    bpy.ops.render.render(write_still=True)

    img = bpy.data.images.load(big_path)
    px = np.array(img.pixels[:], dtype=np.float64).reshape(SIZE * SUPER, SIZE * SUPER, 4)
    blocks = px.reshape(SIZE, SUPER, SIZE, SUPER, 4)
    alpha = blocks[..., 3].mean(axis=(1, 3))
    rgb = (blocks[..., :3] * blocks[..., 3:4]).sum(axis=(1, 3)) / np.maximum(blocks[..., 3].sum(axis=(1, 3)), 1e-9)[..., None]
    solid = alpha >= 0.5
    icon = np.zeros((SIZE, SIZE, 4))
    icon[solid, :3] = _flatten(rgb[solid])
    icon[solid, 3] = 1.0
    grown = np.zeros_like(solid)
    grown[1:, :] |= solid[:-1, :]
    grown[:-1, :] |= solid[1:, :]
    grown[:, 1:] |= solid[:, :-1]
    grown[:, :-1] |= solid[:, 1:]
    icon[grown & ~solid] = OUTLINE

    small = bpy.data.images.new("icon", SIZE, SIZE, alpha=True)
    small.pixels = icon.reshape(-1).tolist()
    small.filepath_raw = out
    small.file_format = "PNG"
    small.save()
    print("PZI wrote %s: %d of %d pixels solid, %d outline; view %.0f/%.0f; engine %s" % (
        out, int(solid.sum()), SIZE * SIZE, int((grown & ~solid).sum()), azimuth, elevation, scene.render.engine))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    render(args[0], args[1], args[2], float(args[3]) if len(args) > 3 else 15.0,
           float(args[4]) if len(args) > 4 else 20.0)

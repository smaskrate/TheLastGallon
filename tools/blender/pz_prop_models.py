"""Build the floor models of the items that have no supplied model from
the shapes their icons are rendered from (pz_icon_props.py), and write
each as the supplied models ship: an FBX and its texture.

  blender -b --factory-startup --python tools/blender/pz_prop_models.py -- <models_dir> <textures_dir>

writes <models_dir>/<Name>.fbx and <textures_dir>/<Name>.png for each
prop in pz_icon_props.PROPS, as it lies on the floor (`floor`): the
sampling kit's hose coiled flat in front of its jars, the manual on its
back; the others stand. They have half the icons' sides (DETAIL 0.5),
which keeps each under about 1,000 triangles.

The FBX is the supplied models' kind (docs/engine-capabilities.md, "The
supplied fermenter, an FBX"): one mesh with one material, Y up through
the node's -90 degree turn about X, metres given as UnitScaleFactor 100
and no node scaling (the game sizes a model by the node's scaling, not
the unit), triangles, its base at the origin and 1.0 along its largest
side, so the model script's scale (times 1.5) sets its true size. Edges
sharper than SHARP degrees are kept sharp: a jar's rim is, the hose's
six sides are not.

The texture is a palette: each colour of the shapes is a stripe the
full height of a 256x256 PNG, and every face's UVs sit in the middle of
its colour's stripe. A face is one flat colour, a flipped V reads the
same, and the mipmaps keep each colour whole down to 16x16. The PNG is
written here, byte for byte the same each time. The FBX carries the time
it was written, and ids from Python's string hash, which Blender seeds
anew each run unless it is started with PYTHONHASHSEED set and
--python-use-system-env (tools/make-prop-models.ps1 does).
"""
import math
import os
import struct
import sys
import zlib

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pz_icon_props  # noqa: E402

TEXTURE, STRIPES = 256, 8
DETAIL, SHARP = 0.5, 65.0


def _png(path, colours):
    """A TEXTURE x TEXTURE RGB PNG, one vertical stripe per colour (the
    last repeated to fill), from "#RRGGBB" colours."""
    width = TEXTURE // STRIPES
    row = b"".join(bytes(int(colours[min(i, len(colours) - 1)][k:k + 2], 16) for k in (1, 3, 5)) * width
                   for i in range(STRIPES))
    raw = b"".join(b"\x00" + row for _ in range(TEXTURE))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", TEXTURE, TEXTURE, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def export(name, build, models_dir, textures_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build(floor=True)
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mesh = obj.data

    # Each material is named after its colour (pz_icon_props._mat): one
    # stripe per colour, then one material for the whole mesh.
    slot_colours = [m.name[:7] for m in mesh.materials]
    colours = list(dict.fromkeys(slot_colours))
    if len(colours) > STRIPES:
        raise ValueError("%s has %d colours, the palette holds %d" % (name, len(colours), STRIPES))
    uv = mesh.uv_layers.active
    for poly in mesh.polygons:
        u = (colours.index(slot_colours[poly.material_index]) + 0.5) / STRIPES
        for i in poly.loop_indices:
            uv.data[i].uv = (u, 0.5)
        poly.material_index = 0
    mesh.materials.clear()
    mesh.materials.append(bpy.data.materials.new(name))

    # Base at the origin, centred across, 1.0 along the largest side.
    lo = Vector([min(v.co[k] for v in mesh.vertices) for k in range(3)])
    hi = Vector([max(v.co[k] for v in mesh.vertices) for k in range(3)])
    extent = hi - lo
    size = max(extent)
    base = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for v in mesh.vertices:
        v.co = (v.co - base) / size
    # Triangles split one fixed way and listed in one order: two builds of
    # the yeast starter gave the same triangles in a different order.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="FIXED", ngon_method="EAR_CLIP")
    bm.verts.index_update()
    for seq, key in ((bm.faces, lambda f: tuple(v.index for v in f.verts)),
                     (bm.edges, lambda e: tuple(sorted(v.index for v in e.verts)))):
        for rank, elem in enumerate(sorted(seq, key=key)):
            elem.index = rank
        seq.sort(key=lambda elem: elem.index)
    bm.to_mesh(mesh)
    bm.free()
    mesh.shade_smooth()
    mesh.set_sharp_from_angle(angle=math.radians(SHARP))
    mesh.update()
    obj.name = mesh.name = name

    fbx = os.path.join(models_dir, name + ".fbx")
    bpy.ops.export_scene.fbx(filepath=fbx, object_types={"MESH"}, apply_scale_options="FBX_SCALE_UNITS",
                             axis_forward="-Z", axis_up="Y", bake_space_transform=False, mesh_smooth_type="FACE",
                             use_triangles=False, colors_type="NONE", add_leaf_bones=False, bake_anim=False,
                             path_mode="STRIP", embed_textures=False)
    _png(os.path.join(textures_dir, name + ".png"), colours)
    triangles = sum(len(p.vertices) - 2 for p in mesh.polygons)
    print("PZP %s: %.3f x %.3f x %.3f shape units (across, deep, tall), largest %.3f; %d triangles; %d colours %s"
          % (name, extent.x, extent.y, extent.z, size, triangles, len(colours), " ".join(colours)))


if __name__ == "__main__":
    models_dir, textures_dir = sys.argv[sys.argv.index("--") + 1:][:2]
    pz_icon_props.DETAIL = DETAIL
    for prop, builder in pz_icon_props.PROPS.items():
        export(prop, builder, models_dir, textures_dir)

"""Build simple shapes for the items that have no supplied model and
render their inventory icons through pz_icon.render_scene, so they look
like the icons rendered from the supplied models.

  blender -b --factory-startup --python tools/blender/pz_icon_props.py -- <out_dir>

writes Item_TLG_<Name>.png for each prop below. The shapes are this
script's own (no outside asset); each is drawn to read apart from the
others at 32 pixels, three of them being jars. The same shapes are the
items' floor models (pz_prop_models.py), built with `floor` as each lies
on the floor and with fewer sides (DETAIL):
- FuelSampleKit: three small jars of fuel (petrol, ethanol, diesel
  colours) and a red rubber hose, the kit's recipe (3 jars, a hose).
- YeastStarter: a jar of cream culture under a cloth dome tied with
  string, a live culture.
- FuelStabilizer: a corked bottle of black wood tar with a paper label (2
  charcoal in a jar): the one bottle among the jars.
- ManualFuelSystems: an olive field manual with a title band and an
  orange badge.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pz_icon  # noqa: E402

GLASS = "#C9D6D8"
# Sides of the round shapes against the icons' (40 round a cylinder); the
# floor models use fewer.
DETAIL = 1.0


def _sides(count):
    return max(6, int(round(count * DETAIL)))


def _linear(hex_colour):
    """An sRGB hex colour as Blender's linear RGBA."""
    out = []
    for i in (1, 3, 5):
        c = int(hex_colour[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def _mat(hex_colour, roughness=0.6, metallic=0.0):
    key = "%s_%.2f_%.2f" % (hex_colour, roughness, metallic)
    mat = bpy.data.materials.get(key)
    if mat is None:
        mat = bpy.data.materials.new(key)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = _linear(hex_colour)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return mat


def _finish(obj, colour, roughness=0.6, metallic=0.0, smooth=True):
    obj.data.materials.append(_mat(colour, roughness, metallic))
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    return obj


def cylinder(x, y, z0, radius, height, colour, **kw):
    bpy.ops.mesh.primitive_cylinder_add(vertices=_sides(40), radius=radius, depth=height,
                                        location=(x, y, z0 + height / 2))
    return _finish(bpy.context.active_object, colour, **kw)


def cone(x, y, z0, r_bottom, r_top, height, colour, **kw):
    bpy.ops.mesh.primitive_cone_add(vertices=_sides(40), radius1=r_bottom, radius2=r_top, depth=height,
                                    location=(x, y, z0 + height / 2))
    return _finish(bpy.context.active_object, colour, **kw)


def box(x, y, z0, width, depth, height, colour, **kw):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, z0 + height / 2))
    obj = bpy.context.active_object
    obj.scale = (width, depth, height)
    return _finish(obj, colour, smooth=False, **kw)


def torus(x, y, z, major, minor, colour, tilt=(0.0, 0.0, 0.0), **kw):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=(x, y, z), rotation=tilt,
                                     major_segments=_sides(48), minor_segments=_sides(12))
    return _finish(bpy.context.active_object, colour, **kw)


def jar(x, y, radius, height, fill, contents, lid, lid_metal=False):
    """A jar: its contents up to `fill` of the body, glass above, a lid."""
    cylinder(x, y, 0.0, radius, height * fill, contents)
    cylinder(x, y, height * fill, radius, height * (1.0 - fill), GLASS, roughness=0.2)
    cylinder(x, y, height, radius * 0.86, height * 0.1, lid, roughness=0.4, metallic=0.8 if lid_metal else 0.0)


def fuel_sample_kit(floor=False):
    for dx, dy, fuel in ((-0.62, 0.0, "#C27A1E"), (0.0, -0.12, "#E0C25A"), (0.62, 0.0, "#5E3414")):
        jar(dx, dy, 0.25, 0.62, 0.62, fuel, "#3B3B3B")
    if floor:
        # The coil flat on the floor, clear of the jars (in the icon it is
        # tipped towards the eye and runs into the middle jar's foot).
        torus(0.0, -0.95, 0.065, 0.48, 0.065, "#9A2F22")
    else:
        torus(0.0, -0.62, 0.07, 0.48, 0.065, "#9A2F22", tilt=(math.radians(8), 0.0, 0.0))
    return 15.0, 28.0


def yeast_starter(floor=False):
    # The culture with a foam line, glass above it, and a cloth dome over
    # the mouth whose hem hangs round the neck, tied with dark string.
    cylinder(0.0, 0.0, 0.0, 0.36, 0.5, "#E3D2A6")
    cylinder(0.0, 0.0, 0.5, 0.36, 0.05, "#F3EDDA")
    cylinder(0.0, 0.0, 0.55, 0.36, 0.2, GLASS, roughness=0.2)
    cone(0.0, 0.0, 0.64, 0.44, 0.4, 0.12, "#EDE5CF", roughness=0.9)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=_sides(40), ring_count=_sides(20), radius=0.42,
                                         location=(0.0, 0.0, 0.75))
    dome = bpy.context.active_object
    dome.scale = (1.0, 1.0, 0.35)
    _finish(dome, "#EDE5CF", roughness=0.9)
    torus(0.0, 0.0, 0.7, 0.42, 0.03, "#5C3B1E")
    return 15.0, 22.0


def fuel_stabilizer(floor=False):
    # A corked bottle of tar, black to the shoulder, with a paper label and
    # a red band: the one bottle among the jars.
    cylinder(0.0, 0.0, 0.0, 0.3, 0.5, "#2A1A10")
    cylinder(0.0, 0.0, 0.5, 0.3, 0.06, GLASS, roughness=0.2)
    cone(0.0, 0.0, 0.56, 0.3, 0.11, 0.16, GLASS, roughness=0.2)
    cylinder(0.0, 0.0, 0.72, 0.11, 0.14, GLASS, roughness=0.2)
    cylinder(0.0, 0.0, 0.86, 0.095, 0.1, "#B08A5A", roughness=0.9)
    cylinder(0.0, 0.0, 0.1, 0.305, 0.26, "#E8DCC0", roughness=0.9)
    cylinder(0.0, 0.0, 0.3, 0.307, 0.05, "#B23A2A", roughness=0.9)
    return 15.0, 18.0


def manual_fuel_systems(floor=False):
    # Front and back covers with the pages between them, whose edge shows on
    # the right, a dark spine on the left, and on the front a title band and
    # a badge. On the floor it lies on its back, the front (-Y) up.
    for y in (-0.0375, 0.0375):
        box(0.0, y, 0.0, 0.72, 0.015, 0.96, "#5B6B3A", roughness=0.8)
    box(0.01, 0.0, 0.015, 0.7, 0.06, 0.93, "#EDE9DD", roughness=0.9)
    box(-0.36, 0.0, 0.0, 0.03, 0.09, 0.96, "#3F4A28", roughness=0.8)
    box(0.02, -0.047, 0.7, 0.56, 0.006, 0.15, "#E8DCC0", roughness=0.9)
    bpy.ops.mesh.primitive_cylinder_add(vertices=_sides(40), radius=0.15, depth=0.006, location=(0.02, -0.048, 0.4),
                                        rotation=(math.radians(90), 0.0, 0.0))
    _finish(bpy.context.active_object, "#D9822B", roughness=0.7)
    if floor:
        turn = Matrix.Rotation(math.radians(-90.0), 4, "X")
        for obj in bpy.context.scene.objects:
            obj.matrix_world = turn @ obj.matrix_world
    return 30.0, 12.0


PROPS = {"FuelSampleKit": fuel_sample_kit, "YeastStarter": yeast_starter, "FuelStabilizer": fuel_stabilizer,
         "ManualFuelSystems": manual_fuel_systems}

if __name__ == "__main__":
    out_dir = sys.argv[sys.argv.index("--") + 1:][0]
    for name, build in PROPS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        azimuth, elevation = build()
        pz_icon.render_scene(os.path.join(out_dir, "Item_TLG_%s.png" % name), azimuth, elevation)

"""Project Zomboid DirectX .x files in Blender (text format only).

The game's character body (media/models_X/Skinned/MaleBody.x) and its
clips (media/anims_X/Bob/*.x) are text DirectX files: a "Frame" hierarchy
(Dummy01 > Bip01 > Bip01_Pelvis ...), each frame with a row-vector
FrameTransformMatrix relative to its parent. Blender 4.5 has no .x
importer, so this reads the frames itself and builds an armature: one
bone per frame, placed at the frame's world position and turned with it
(the frame's X axis becomes the bone's Y axis, Biped bones point along
+X). Each bone keeps its frame's rest matrix as a custom property, so a
pose can be written back as the frame-relative keys the game reads.

Run headless (Blender 4.5 LTS):
  blender -b --factory-startup --python tools/blender/pz_x.py -- skeleton <in.x> [out.blend]
prints the bones and where the head, hands and feet stand.
"""
import re
import sys

import bpy
from mathutils import Matrix, Vector

_TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_\-.]*|\{|\}|-?\d+(?:\.\d*)?(?:[eE][-+]?\d+)?")


def parse_frames(path):
    """The frame hierarchy of a text .x file: [(name, parent name, 4x4 rows)]."""
    with open(path, "r", encoding="latin-1") as f:
        text = f.read()
    if not text.startswith("xof ") or text[8:11] != "txt":
        raise ValueError("%s is not a text .x file" % path)
    tokens = _TOKEN.findall(text[16:])
    frames, stack, i = [], [], 0

    def skip_block(j):
        depth = 0
        while j < len(tokens):
            if tokens[j] == "{":
                depth += 1
            elif tokens[j] == "}":
                depth -= 1
                if depth == 0:
                    return j + 1
            j += 1
        return j

    while i < len(tokens):
        t = tokens[i]
        if t == "Frame" and i + 2 < len(tokens) and tokens[i + 2] == "{":
            frames.append([tokens[i + 1], stack[-1] if stack else None, None])
            stack.append(tokens[i + 1])
            i += 3
        elif t == "FrameTransformMatrix" and tokens[i + 1] == "{":
            values = [float(v) for v in tokens[i + 2:i + 18]]
            frames[_index(frames, stack[-1])][2] = [values[0:4], values[4:8], values[8:12], values[12:16]]
            i = skip_block(i + 1)
        elif t == "}":
            if stack:
                stack.pop()
            i += 1
        elif t == "{":
            i = skip_block(i)
        elif i + 1 < len(tokens) and tokens[i + 1] == "{":
            i = skip_block(i + 1)
        elif i + 2 < len(tokens) and tokens[i + 2] == "{":
            i = skip_block(i + 2)
        else:
            i += 1
    return [tuple(fr) for fr in frames if fr[2] is not None]


def parse_animation(path):
    """The first AnimationSet of a text .x file: (name, ticks per second,
    {bone: {"S"|"R"|"T": [(time, (values...))]}}). Keys are typed by their
    keyType (1 scale, 0 rotation w x y z, 2 position), as the game's
    clips write them (AnimationKey S/R/T)."""
    with open(path, "r", encoding="latin-1") as f:
        text = f.read()
    tps = re.search(r"AnimTicksPerSecond\s*\{\s*(\d+)\s*;", text)
    m = re.search(r"AnimationSet\s+([A-Za-z0-9_\-.]+)\s*\{", text)
    if m is None:
        raise ValueError("%s has no AnimationSet" % path)
    tokens = _TOKEN.findall(text[m.end():])
    bones, i, depth = {}, 0, 1
    while i < len(tokens) and depth > 0:
        t = tokens[i]
        if t == "Animation":
            j = i + 1 if tokens[i + 1] == "{" else i + 2
            j, d, bone, keys = j + 1, 1, None, {}
            while d > 0:
                tk = tokens[j]
                if tk == "{" and bone is None and tokens[j + 2] == "}":
                    bone, j = tokens[j + 1], j + 3
                elif tk == "AnimationKey":
                    k = (j + 1 if tokens[j + 1] == "{" else j + 2) + 1
                    kind, n, k, out = int(tokens[k]), int(tokens[k + 1]), k + 2, []
                    for _ in range(n):
                        cnt = int(tokens[k + 1])
                        out.append((int(float(tokens[k])), tuple(float(v) for v in tokens[k + 2:k + 2 + cnt])))
                        k += 2 + cnt
                    keys[{0: "R", 1: "S", 2: "T", 4: "M"}.get(kind, str(kind))] = out
                    j = k + 1
                else:
                    d += 1 if tk == "{" else -1 if tk == "}" else 0
                    j += 1
            bones[bone] = keys
            i = j
        else:
            depth += 1 if t == "{" else -1 if t == "}" else 0
            i += 1
    return m.group(1), int(tps.group(1)) if tps else 4800, bones


def _index(frames, name):
    for k in range(len(frames) - 1, -1, -1):
        if frames[k][0] == name:
            return k
    raise KeyError(name)


def local_matrix(rows):
    """A .x row-vector matrix as a Blender (column-vector) matrix."""
    return Matrix(rows).transposed()


def world_matrices(frames):
    world = {}
    for name, parent, rows in frames:
        m = local_matrix(rows)
        world[name] = world[parent] @ m if parent in world else m
    return world


# Biped bones point along their frame's +X; Blender bones along +Y.
_FRAME_TO_BONE = Matrix(((0.0, 1.0, 0.0, 0.0), (-1.0, 0.0, 0.0, 0.0), (0.0, 0.0, 1.0, 0.0), (0.0, 0.0, 0.0, 1.0)))


def build_armature(frames, name="PZ_Skeleton"):
    world = world_matrices(frames)
    children = {}
    for n, p, _ in frames:
        children.setdefault(p, []).append(n)
    arm = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bones = {}
    for n, p, rows in frames:
        b = arm.edit_bones.new(n)
        m = world[n]
        head = m.translation
        length = 0.0
        for c in children.get(n, []):
            length = max(length, (world[c].translation - head).length)
        b.head = head
        b.tail = head + Vector((0.0, 0.0, 0.02))
        b.matrix = m @ _FRAME_TO_BONE
        b.length = length if length > 1e-4 else 0.02
        bones[n] = b
    for n, p, _ in frames:
        if p in bones:
            bones[n].parent = bones[p]
    bpy.ops.object.mode_set(mode="OBJECT")
    for n, p, rows in frames:
        obj.data.bones[n]["pz_rest_rows"] = [v for r in rows for v in r]
        obj.data.bones[n]["pz_parent"] = p or ""
    return obj, world


def _skeleton(argv):
    path = argv[0]
    frames = parse_frames(path)
    obj, world = build_armature(frames)
    print("PZX frames=%d bones=%d" % (len(frames), len(obj.data.bones)))
    print("PZX names " + " ".join(n for n, _, _ in frames))
    for n in ("Bip01", "Bip01_Pelvis", "Bip01_Head", "Bip01_HeadNub", "Bip01_R_Hand", "Bip01_L_Hand",
              "Bip01_Prop1", "Bip01_Prop2", "Bip01_R_Foot", "Bip01_L_Foot", "Bip01_R_Toe0Nub"):
        if n in world:
            t = world[n].translation
            print("PZX at %-16s %8.4f %8.4f %8.4f" % (n, t.x, t.y, t.z))
    if len(argv) > 1:
        bpy.ops.wm.save_as_mainfile(filepath=argv[1])
        print("PZX saved " + argv[1])


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if args and args[0] == "skeleton":
        _skeleton(args[1:])

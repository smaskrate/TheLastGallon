"""Retarget the arms of a Mixamo clip onto the game's skeleton and write a
game clip (.x text, the form of media/anims_X/Bob/*.x).

Only the arms are carried over: a hold pose drives the clavicles' subtrees
and the prop bones (AnimSets/player/maskingright), the rest of the body
keeps the game's own animation. Each frame the Mixamo arm segments
(shoulder, upper arm, forearm, hand) are read as directions in the chest's
frame (left, up, forward) and laid on the game's skeleton in its own
chest's frame, from the first frame of Bob_Idle.x. The game's coordinates
are mirrored against Blender's (its left x up points backward), so the
mapping goes by those named axes, never by coordinates. From the game's
clips (docs/engine-capabilities.md, animation tooling): bones point along
X, an elbow bends about the forearm's and upper arm's Y (cross(upper arm,
forearm) is +Y), a hand's palm faces its Z; rotation keys are the
transposed quaternion of the column-convention local rotation, w x y z.
Bones keep the game's lengths. Bip01_Prop1, the held item's bone, is a
child of Bip01: it is placed between the hands, turned as Bob_Idle_Bag.x
turns it relative to Bip01, so an item's hand model needs its usual
Bip01_Prop1 attachment only.

  blender -b --factory-startup --python tools/blender/pz_arms.py -- <clip.fbx> <out.x> <ClipName> [step] [forward] [down] [clip2.fbx] [blend]

writes every step-th frame (default 2) at 4800 ticks per second, 160 per
frame of 30 fps; the other bones hold the first frame of Bob_Idle.x.
forward and down move the held item from between the hands (file units,
defaults PROP_FORWARD and 0). clip2.fbx, the same clip exported with
another arm spacing, is blended in by blend (default 0.5).
"""
import os
import re
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pz_x  # noqa: E402

GAME = r"G:\SteamLibrary\steamapps\common\ProjectZomboid\media\anims_X\Bob"
REFERENCE = os.path.join(GAME, "Bob_Idle.x")
PROP_REFERENCE = os.path.join(GAME, "Bob_Idle_Bag.x")
TICKS_PER_FRAME = 160
SIDES = (("L", "Left"), ("R", "Right"))
# The held item, from run 91: centred between the hands it sank into the
# belly, so it sits this far forward (file units; a character is about 0.9
# tall), turned a quarter about the body's up so that the barrel's tap,
# which pointed to the character's left, points forward.
PROP_FORWARD = 0.05
PROP_TURN_LEFT_TO_FORWARD = True


def _mixamo_positions(arm, prefix):
    names = ["Spine2", "Neck"]
    for _, m in SIDES:
        names += [m + n for n in ("Shoulder", "Arm", "ForeArm", "Hand", "HandMiddle1", "HandIndex1", "HandPinky1")]
    out = {}
    for n in names:
        pb = arm.pose.bones[prefix + n]
        out[n] = arm.matrix_world @ pb.head
    return out


def _frame(left, up, forward_sign):
    left = left.normalized()
    up = (up - left * up.dot(left)).normalized()
    return left, up, left.cross(up) * forward_sign


def _rotation(x, y=None, z=None):
    """Columns x, y, z (right-handed: z = x cross y, y = z cross x)."""
    x = x.normalized()
    if y is not None:
        y = (y - x * y.dot(x)).normalized()
        z = x.cross(y)
    else:
        z = (z - x * z.dot(x)).normalized()
        y = z.cross(x)
    return Matrix((x, y, z)).transposed()


def _vectors(m, left_p, up_p, fwd_p):
    """One frame's arm segments, palms included, as unit directions on the
    game's skeleton: each read in the Mixamo chest's frame (left, up,
    forward) and laid in the game chest's."""
    left_m, up_m, fwd_m = _frame(m["LeftArm"] - m["RightArm"], m["Neck"] - m["Spine2"], 1.0)

    def to_game(v):
        return (left_p * v.dot(left_m) + up_p * v.dot(up_m) + fwd_p * v.dot(fwd_m)).normalized()

    out = {}
    for s, mx in SIDES:
        a, b = m[mx + "HandMiddle1"] - m[mx + "Hand"], m[mx + "HandIndex1"] - m[mx + "HandPinky1"]
        out[s] = {"clav": to_game(m[mx + "Arm"] - m[mx + "Shoulder"]), "up": to_game(m[mx + "ForeArm"] - m[mx + "Arm"]),
                  "fore": to_game(m[mx + "Hand"] - m[mx + "ForeArm"]), "hand": to_game(a),
                  "palm": to_game(a.cross(b) if s == "L" else b.cross(a))}
    return out


def _import(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o not in before)
    prefix = arm.data.bones[0].name.split(":")[0] + ":" if ":" in arm.data.bones[0].name else ""
    return arm, prefix


def retarget(fbx, out_path, clip_name, step=2, forward=PROP_FORWARD, down=0.0, fbx2=None, blend=0.5):
    """With fbx2 (the same clip with another arm spacing, frame for frame),
    each direction is blended: (1 - blend) of fbx's, blend of fbx2's."""
    ref = pz_x.parse_frames(REFERENCE)
    parent = {n: p for n, p, _ in ref}
    local_ref = {n: pz_x.local_matrix(rows) for n, _, rows in ref}
    world_ref = pz_x.world_matrices(ref)
    prop_local = {n: pz_x.local_matrix(rows) for n, _, rows in pz_x.parse_frames(PROP_REFERENCE)}["Bip01_Prop1"]
    p = {n: world_ref[n].translation for n in world_ref}
    left_p, up_p, fwd_p = _frame(p["Bip01_L_UpperArm"] - p["Bip01_R_UpperArm"], p["Bip01_Neck"] - p["Bip01_Spine1"], -1.0)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    arm, prefix = _import(fbx)
    second = _import(fbx2) if fbx2 else None
    first, last = (int(v) for v in arm.animation_data.action.frame_range)

    chains = {s: ["Bip01_%s_Clavicle" % s, "Bip01_%s_UpperArm" % s, "Bip01_%s_Forearm" % s, "Bip01_%s_Hand" % s]
              for s, _ in SIDES}
    fingers = {s: [n for n in local_ref if parent.get(n) == "Bip01_%s_Hand" % s or
                   (parent.get(n) or "").startswith("Bip01_%s_Finger" % s)] for s, _ in SIDES}
    keyed = [b for s, _ in SIDES for b in chains[s] + fingers[s]] + ["Bip01_Prop1"]
    keys = {b: [] for b in keyed}
    report = []
    for f in range(first, last + 1, step):
        bpy.context.scene.frame_set(f)
        vec = _vectors(_mixamo_positions(arm, prefix), left_p, up_p, fwd_p)
        if second:
            vec2 = _vectors(_mixamo_positions(*second), left_p, up_p, fwd_p)
            vec = {s: {k: (v * (1.0 - blend) + vec2[s][k] * blend).normalized() for k, v in d.items()}
                   for s, d in vec.items()}

        world = {"Bip01_Neck": world_ref["Bip01_Neck"]}
        hands = {}
        for s, mx in SIDES:
            d_clav, d_up, d_fore = vec[s]["clav"], vec[s]["up"], vec[s]["fore"]
            d_hand, palm = vec[s]["hand"], vec[s]["palm"]
            hinge = d_up.cross(d_fore)
            clav_ref = world_ref["Bip01_%s_Clavicle" % s].to_3x3()
            targets = [clav_ref.col[0].normalized().rotation_difference(d_clav).to_matrix() @ clav_ref,
                       None, None, _rotation(d_hand, z=palm)]
            if hinge.length < 0.17:
                hinge = world_ref["Bip01_%s_Forearm" % s].to_3x3().col[1]
            targets[1] = _rotation(d_up, y=hinge)
            targets[2] = _rotation(d_fore, y=hinge)
            for bone, rot in zip(chains[s], targets):
                pw = world[parent[bone]]
                lrot = pw.to_3x3().transposed() @ rot
                local = Matrix.Translation(local_ref[bone].translation) @ lrot.to_4x4()
                world[bone] = pw @ local
                keys[bone].append((f, lrot))
            for bone in fingers[s]:
                world[bone] = world[parent[bone]] @ local_ref[bone]
                keys[bone].append((f, local_ref[bone].to_3x3()))
            hands[s] = world["Bip01_%s_Hand" % s].translation
        # The held item: between the hands and a little forward, turned as
        # the bag pose turns it, then a quarter about the body's up.
        mid = (hands["L"] + hands["R"]) * 0.5 + fwd_p * forward - up_p * down
        prop_world = world_ref["Bip01"] @ prop_local
        if PROP_TURN_LEFT_TO_FORWARD:
            turn = left_p.rotation_difference(fwd_p).to_matrix()
            prop_world = (turn @ prop_world.to_3x3()).to_4x4()
        prop_world.translation = mid
        prop = world_ref["Bip01"].inverted() @ prop_world
        keys["Bip01_Prop1"].append((f, prop.to_3x3(), prop.translation.copy()))
        if f == first:
            report.append("PZA hands L %s R %s apart %.3f; hand height over pelvis %.3f" % (
                tuple(round(v, 3) for v in hands["L"]), tuple(round(v, 3) for v in hands["R"]),
                (hands["L"] - hands["R"]).length, mid.dot(up_p) - p["Bip01_Pelvis"].dot(up_p)))
    _write(out_path, clip_name, keys, first, last)
    for r in report:
        print(r)
    print("PZA wrote %s: %d frames of %s, %d bones keyed" % (out_path, len(keys["Bip01_Prop1"]), clip_name, len(keys)))


def _quat(rot3, prev):
    q = rot3.transposed().to_quaternion()
    if prev is not None and q.dot(prev) < 0.0:
        q.negate()
    return q


def _key_lines(kind, keys):
    out = ["  AnimationKey %s {" % {0: "R", 1: "S", 2: "T"}[kind], "   %d;" % kind, "   %d;" % len(keys)]
    for i, (t, vals) in enumerate(keys):
        end = ";;;" if i == len(keys) - 1 else ";;,"
        out.append("   %d;%d;%s%s" % (t, len(vals), ",".join("%.6f" % v for v in vals), end))
    out.append("  }")
    return out


def _write(out_path, clip_name, keys, first, last):
    with open(REFERENCE, "r", encoding="latin-1") as f:
        text = f.read()
    header = text[:re.search(r"^AnimationSet\s", text, re.M).start()]
    _, _, template = pz_x.parse_animation(REFERENCE)
    end = (last - first) * TICKS_PER_FRAME
    lines = ["AnimationSet %s {" % clip_name]
    for bone, tkeys in template.items():
        lines += [" Animation {", "  ", "  { %s }" % bone, ""]
        if bone in keys:
            rows, prev = [], None
            for entry in keys[bone]:
                q = _quat(entry[1], prev)
                prev = q
                rows.append(((entry[0] - first) * TICKS_PER_FRAME, (q.w, q.x, q.y, q.z)))
            t0 = tkeys["T"][0][1] if "T" in tkeys else (0.0, 0.0, 0.0)
            trows = [((e[0] - first) * TICKS_PER_FRAME, tuple(e[2])) for e in keys[bone]] if len(keys[bone][0]) > 2 \
                else [(0, t0), (end, t0)]
            lines += _key_lines(1, [(0, (1.0, 1.0, 1.0)), (end, (1.0, 1.0, 1.0))]) + [""]
            lines += _key_lines(0, rows) + [""] + _key_lines(2, trows)
        else:
            r0 = tkeys["R"][0][1] if "R" in tkeys else (1.0, 0.0, 0.0, 0.0)
            t0 = tkeys["T"][0][1] if "T" in tkeys else (0.0, 0.0, 0.0)
            lines += _key_lines(1, [(0, (1.0, 1.0, 1.0)), (end, (1.0, 1.0, 1.0))]) + [""]
            lines += _key_lines(0, [(0, r0), (end, r0)]) + [""] + _key_lines(2, [(0, t0), (end, t0)])
        lines += [" }", ""]
    lines.append("}")
    with open(out_path, "w", encoding="latin-1", newline="\n") as f:
        f.write(header + "\n".join(lines) + "\n")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    retarget(args[0], args[1], args[2], int(args[3]) if len(args) > 3 else 2,
             float(args[4]) if len(args) > 4 else PROP_FORWARD, float(args[5]) if len(args) > 5 else 0.0,
             args[6] if len(args) > 6 else None, float(args[7]) if len(args) > 7 else 0.5)

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
child of Bip01 in the file: it is placed between the hands, turned as
Bob_Idle_Bag.x turns it relative to Bip01, so an item's hand model needs
its usual Bip01_Prop1 attachment only. A player's animation player
reparents bones (BC IsoPlayer.onAnimPlayerCreated): the clavicles under
Bip01_Spine1, Bip01_Prop1 under Bip01_R_Hand, Bip01_Prop2 under
Bip01_L_Hand. Such a bone keeps the offset to its new parent that the
clip's own pose gives it at the track's time (BC
AnimationPlayer.getTrackTransform; run 110), so the clip's other bones
must hold the body pose the arms were keyed for, and the held item stays
where the right hand takes it.

  blender -b --factory-startup --python tools/blender/pz_arms.py -- <clip.fbx> <out.x> <ClipName> [step] [forward] [down] [clip2.fbx] [blend] [--body <clip.x>] [--arms chest|world] [--body-key N | --sync]

writes every step-th frame (default 2) at 4800 ticks per second, 160 per
frame of 30 fps; the other bones hold the first frame of Bob_Idle.x (of
the --body clip with --body). forward and down move the held item from
between the hands (file units, defaults PROP_FORWARD and 0). clip2.fbx,
the same clip exported with another arm spacing, is blended in by blend
(default 0.5).

--body keys the clip for another body pose, the first frame of a game
clip such as Bob_IdleSneak.x, whose chest a crouch turns 60-73 degrees
from standing. The item keeps its standing turn and its offsets run along
the standing body's axes, so it stays upright. --arms chest (the default)
reads the arm directions in that pose's chest, so the arms bend with it;
--arms world reads them in the standing chest, so they keep their
standing directions from wherever the shoulders are.

--body-key N takes the body pose at the clip's N-th key time instead of
its first frame. --sync keys the clip for the whole body clip, one key at
each of its key times, each against the body pose at that time, with the
Mixamo frame at the same fraction of its range (step is unused). The
other bones carry the body clip's own keys, so the clip runs as long as
it. A looping track in a sub-layer is moved every update to the time
fraction of the parent layer's sync track (BC AnimLayer.updateInternal
and findSyncTrack; a node's m_SyncTrackingEnabled defaults to true), and
the masking layer's parent is the body's, so the arms follow the body's
cycle. The sprint's chest twists through a stride, up to 76 degrees from
its first frame in Bob_Sprint.x (under 10 in the crouch clips), which
one frame cannot answer.
"""
import bisect
import os
import re
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

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


def _chest(world):
    p = {n: world[n].translation for n in world}
    return _frame(p["Bip01_L_UpperArm"] - p["Bip01_R_UpperArm"], p["Bip01_Neck"] - p["Bip01_Spine1"], -1.0)


def _sample(track, t, rot):
    """A key track's value at tick t: its neighbouring keys interpolated
    (rotations slerped), held past either end."""
    i = bisect.bisect_right([k[0] for k in track], t) - 1
    if i < 0:
        return track[0][1]
    if i >= len(track) - 1 or track[i][0] == t:
        return track[i][1]
    (t0, v0), (t1, v1) = track[i], track[i + 1]
    f = (t - t0) / float(t1 - t0)
    if rot:
        q = Quaternion(v0).slerp(Quaternion(v1), f)
        return (q.w, q.x, q.y, q.z)
    return tuple(a + (b - a) * f for a, b in zip(v0, v1))


def _pose_at(frames, keys, t):
    """World matrices of a game clip's bones at tick t, from its keys (the
    file's frame for a bone without rotation and position keys)."""
    out = []
    for name, parent, rows in frames:
        k = keys.get(name, {})
        if "R" in k and "T" in k:
            m = Quaternion(_sample(k["R"], t, True)).to_matrix().transposed().to_4x4()
            m.translation = Vector(_sample(k["T"], t, False))
            rows = [list(r) for r in m.transposed()]
        out.append((name, parent, rows))
    return pz_x.world_matrices(out)


def _key_times(keys):
    return sorted({k[0] for tracks in keys.values() for track in tracks.values() for k in track})


def retarget(fbx, out_path, clip_name, step=2, forward=PROP_FORWARD, down=0.0, fbx2=None, blend=0.5, body=None,
             arms="chest", body_key=None, sync=False):
    """With fbx2 (the same clip with another arm spacing, frame for frame),
    each direction is blended: (1 - blend) of fbx's, blend of fbx2's. With
    body (a game clip), the clip is keyed for that clip's first frame, its
    body_key-th key time, or with sync each of its key times (module
    docstring)."""
    ref = pz_x.parse_frames(REFERENCE)
    parent = {n: p for n, p, _ in ref}
    local_ref = {n: pz_x.local_matrix(rows) for n, _, rows in ref}
    world_ref = pz_x.world_matrices(ref)
    hold = None
    # The arm bones' offsets from their parents: Bob_Idle's, which the
    # shipped clips were built with; with --body-key or --sync the body
    # clip's own (its clavicles sit up to 0.011 from Bob_Idle's), which
    # the written file carries.
    offsets = {b: m.translation for b, m in local_ref.items()}
    if body and (sync or body_key is not None):
        body_frames, body_keys = pz_x.parse_frames(body), pz_x.parse_animation(body)[2]
        times = _key_times(body_keys)
        if body_key is not None:
            hold = times[body_key]
        world_body = _pose_at(body_frames, body_keys, hold or 0)
        offsets.update({b: Vector(k["T"][0][1]) for b, k in body_keys.items() if "T" in k})
    else:
        world_body = pz_x.world_matrices(pz_x.parse_frames(body)) if body else world_ref
    prop_local = {n: pz_x.local_matrix(rows) for n, _, rows in pz_x.parse_frames(PROP_REFERENCE)}["Bip01_Prop1"]
    p = {n: world_ref[n].translation for n in world_ref}
    left_p, up_p, fwd_p = _chest(world_ref)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    arm, prefix = _import(fbx)
    second = _import(fbx2) if fbx2 else None
    first, last = (int(v) for v in arm.animation_data.action.frame_range)
    if sync:
        samples = [(t, first + int(round(t * (last - first) / float(times[-1])))) for t in times]
        end = times[-1]
    else:
        samples = [((f - first) * TICKS_PER_FRAME, f) for f in range(first, last + 1, step)]
        end = (last - first) * TICKS_PER_FRAME

    chains = {s: ["Bip01_%s_Clavicle" % s, "Bip01_%s_UpperArm" % s, "Bip01_%s_Forearm" % s, "Bip01_%s_Hand" % s]
              for s, _ in SIDES}
    fingers = {s: [n for n in local_ref if parent.get(n) == "Bip01_%s_Hand" % s or
                   (parent.get(n) or "").startswith("Bip01_%s_Finger" % s)] for s, _ in SIDES}
    keyed = [b for s, _ in SIDES for b in chains[s] + fingers[s]] + ["Bip01_Prop1"]
    keys = {b: [] for b in keyed}
    report, held = [], []
    for tick, f in samples:
        if sync:
            world_body = _pose_at(body_frames, body_keys, tick)
        world_arms = world_ref if arms == "world" else world_body
        left_a, up_a, fwd_a = _chest(world_arms)
        bpy.context.scene.frame_set(f)
        vec = _vectors(_mixamo_positions(arm, prefix), left_a, up_a, fwd_a)
        if second:
            vec2 = _vectors(_mixamo_positions(*second), left_a, up_a, fwd_a)
            vec = {s: {k: (v * (1.0 - blend) + vec2[s][k] * blend).normalized() for k, v in d.items()}
                   for s, d in vec.items()}

        world = {"Bip01_Neck": world_body["Bip01_Neck"]}
        hands = {}
        for s, mx in SIDES:
            d_clav, d_up, d_fore = vec[s]["clav"], vec[s]["up"], vec[s]["fore"]
            d_hand, palm = vec[s]["hand"], vec[s]["palm"]
            hinge = d_up.cross(d_fore)
            clav_ref = world_arms["Bip01_%s_Clavicle" % s].to_3x3()
            targets = [clav_ref.col[0].normalized().rotation_difference(d_clav).to_matrix() @ clav_ref,
                       None, None, _rotation(d_hand, z=palm)]
            if hinge.length < 0.17:
                hinge = world_arms["Bip01_%s_Forearm" % s].to_3x3().col[1]
            targets[1] = _rotation(d_up, y=hinge)
            targets[2] = _rotation(d_fore, y=hinge)
            for bone, rot in zip(chains[s], targets):
                pw = world[parent[bone]]
                lrot = pw.to_3x3().transposed() @ rot
                local = Matrix.Translation(offsets[bone]) @ lrot.to_4x4()
                world[bone] = pw @ local
                keys[bone].append((tick, lrot))
            for bone in fingers[s]:
                world[bone] = world[parent[bone]] @ local_ref[bone]
                keys[bone].append((tick, local_ref[bone].to_3x3()))
            hands[s] = world["Bip01_%s_Hand" % s].translation
        # The held item: between the hands and a little forward, turned as
        # the bag pose turns it, then a quarter about the body's up. These
        # are the standing body's axes, so with --body it stays upright.
        mid = (hands["L"] + hands["R"]) * 0.5 + fwd_p * forward - up_p * down
        prop_world = world_ref["Bip01"] @ prop_local
        if PROP_TURN_LEFT_TO_FORWARD:
            turn = left_p.rotation_difference(fwd_p).to_matrix()
            prop_world = (turn @ prop_world.to_3x3()).to_4x4()
        prop_world.translation = mid
        prop = world_body["Bip01"].inverted() @ prop_world
        keys["Bip01_Prop1"].append((tick, prop.to_3x3(), prop.translation.copy()))
        held.append((mid, hands["L"] - mid, hands["R"] - mid, world_body["Bip01_Neck"].translation - mid))
        if tick == samples[0][0]:
            chest = p["Bip01_Spine1"].dot(fwd_p)
            report.append("PZA hands L %s R %s apart %.3f; item height over pelvis %.3f; forward of Bip01_Spine1: "
                          "hands %.3f, item %.3f" % (
                              tuple(round(v, 3) for v in hands["L"]), tuple(round(v, 3) for v in hands["R"]),
                              (hands["L"] - hands["R"]).length, mid.dot(up_p) - p["Bip01_Pelvis"].dot(up_p),
                              (hands["L"] + hands["R"]).dot(fwd_p) * 0.5 - chest, mid.dot(fwd_p) - chest))
            if body:
                # Standing axes: up, and forward of each body part.
                b = {n: world_body[n].translation for n in ("Bip01_Pelvis", "Bip01_Spine1", "Bip01_Neck",
                                                            "Bip01_L_Calf", "Bip01_R_Calf", "Bip01_L_Foot")}
                knee = (b["Bip01_L_Calf"] + b["Bip01_R_Calf"]) * 0.5
                report.append("PZA body %s (arms %s), up/forward of the left foot: pelvis %.3f/%.3f, chest %.3f/%.3f,"
                              " neck %.3f/%.3f, knees %.3f/%.3f, hands %.3f/%.3f, item %.3f/%.3f" % tuple(
                                  [os.path.basename(body), arms] + [v for pt in (
                                      b["Bip01_Pelvis"], b["Bip01_Spine1"], b["Bip01_Neck"], knee,
                                      (hands["L"] + hands["R"]) * 0.5, mid)
                                      for v in ((pt - b["Bip01_L_Foot"]).dot(up_p), (pt - b["Bip01_L_Foot"]).dot(fwd_p))]))

    def spread(vs):
        mean = sum(vs, Vector()) / len(vs)
        return max((v - mean).length for v in vs)

    neck = [(n.dot(up_p), n.dot(fwd_p)) for _, _, _, n in held]
    report.append("PZA over %d keys (%d ticks): the item moves up to %.3f from its mean; against the item the left "
                  "hand moves up to %.3f, the right %.3f; the neck over the item %.3f to %.3f, in front of it %.3f to "
                  "%.3f" % (len(held), end, spread([h[0] for h in held]), spread([h[1] for h in held]),
                            spread([h[2] for h in held]), min(u for u, _ in neck), max(u for u, _ in neck),
                            min(fw for _, fw in neck), max(fw for _, fw in neck)))
    _write(out_path, clip_name, keys, end, body or REFERENCE, hold, sync)
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


def _write(out_path, clip_name, keys, end, body=REFERENCE, hold=None, copy=False):
    """The keyed bones' keys, at their ticks, to tick end; every other bone,
    and the file's frames, hold the first frame of body (its pose at tick
    hold, with hold), or with copy carry body's own keys."""
    with open(body, "r", encoding="latin-1") as f:
        text = f.read()
    header = text[:re.search(r"^AnimationSet\s", text, re.M).start()]
    _, _, template = pz_x.parse_animation(body)
    lines = ["AnimationSet %s {" % clip_name]
    for bone, tkeys in template.items():
        lines += [" Animation {", "  ", "  { %s }" % bone, ""]
        if bone in keys:
            rows, prev = [], None
            for entry in keys[bone]:
                q = _quat(entry[1], prev)
                prev = q
                rows.append((entry[0], (q.w, q.x, q.y, q.z)))
            t0 = tkeys["T"][0][1] if "T" in tkeys else (0.0, 0.0, 0.0)
            trows = [(e[0], tuple(e[2])) for e in keys[bone]] if len(keys[bone][0]) > 2 else [(0, t0), (end, t0)]
            lines += _key_lines(1, [(0, (1.0, 1.0, 1.0)), (end, (1.0, 1.0, 1.0))]) + [""]
            lines += _key_lines(0, rows) + [""] + _key_lines(2, trows)
        else:
            r0 = tkeys["R"][0][1] if "R" in tkeys else (1.0, 0.0, 0.0, 0.0)
            t0 = tkeys["T"][0][1] if "T" in tkeys else (0.0, 0.0, 0.0)
            if hold is not None:
                r0 = _sample(tkeys["R"], hold, True) if "R" in tkeys else r0
                t0 = _sample(tkeys["T"], hold, False) if "T" in tkeys else t0
            rrows, trows = [(0, r0), (end, r0)], [(0, t0), (end, t0)]
            if copy:
                rrows, trows = tkeys.get("R", rrows), tkeys.get("T", trows)
            lines += _key_lines(1, [(0, (1.0, 1.0, 1.0)), (end, (1.0, 1.0, 1.0))]) + [""]
            lines += _key_lines(0, rrows) + [""] + _key_lines(2, trows)
        lines += [" }", ""]
    lines.append("}")
    with open(out_path, "w", encoding="latin-1", newline="\n") as f:
        f.write(header + "\n".join(lines) + "\n")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    named = {}
    for flag in ("--body", "--arms", "--body-key"):
        if flag in args:
            i = args.index(flag)
            named[flag[2:]] = args[i + 1]
            del args[i:i + 2]
    sync = "--sync" in args
    if sync:
        args.remove("--sync")
    if (sync or "body-key" in named) and "body" not in named:
        sys.exit("pz_arms: --sync and --body-key need --body")
    retarget(args[0], args[1], args[2], int(args[3]) if len(args) > 3 else 2,
             float(args[4]) if len(args) > 4 else PROP_FORWARD, float(args[5]) if len(args) > 5 else 0.0,
             args[6] if len(args) > 6 else None, float(args[7]) if len(args) > 7 else 0.5,
             named.get("body"), named.get("arms", "chest"),
             int(named["body-key"]) if "body-key" in named else None, sync)

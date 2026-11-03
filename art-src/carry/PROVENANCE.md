# Carry animation: provenance

Supplied for the mod on 2026-11-02 in `<game>/createdAssets/`. They are
not kept in this repository, because each holds Mixamo's "Beta"
character as well as the animation:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `Carrying.fbx` | 2,484,432 | `DBFD95401B5BE788D949D5E9BB1541BFED13974D195CBD6EB9A370466E015238` |
| `CarryingBiggerArmSpace.fbx` | 2,482,848 | `9EDC2C3C36FF95ABE26EA525280D58CA92F64D54C5571C0A83DDCBADFB1BC88A` |

What they are, read in Blender 4.5.15 LTS: Mixamo's "Carrying"
animation on its 65-bone `mixamorig` skeleton, with the `Beta_Joints` and
`Beta_Surface` meshes. Each is 301 frames at 30 fps (10 s), exported with
two arm spacings: the hands about 0.45 m and 0.95 m apart.

Shipped: `media/anims_X/Bob/Bob_TLG_CarryVessel.x` (307,616 bytes, SHA-256
`ECC4C4134E71A20CB8856E9AB46F384B4E28E3EC76B69E0D9D294AC53AC0EFCB`),
written by:

```
blender -b --factory-startup --python tools/blender/pz_arms.py -- Carrying.fbx Bob_TLG_CarryVessel.x Bob_TLG_CarryVessel 2 0.17 0.06 CarryingBiggerArmSpace.fbx 0.5
```

The clip holds rotations of the game's own arm bones, made from the two
clips' arm directions blended halfway. It also holds where the held
item's bone stands: 0.17 file units in front of the hands and 0.06 down.
The other bones hold the first frame of the game's own `Bob_Idle.x`. No
Mixamo bone, mesh or texture is in it. It plays through
`media/AnimSets/player/maskingright/tlgcarryvessel.xml` with the hand
model `TLG.FermenterHeld` (`media/scripts/TLG_models.txt`). In-game
checks: `docs/test-results.md`, launches 91–96.

Shipped for the crouch (2026-11-03), written from the same two files, in
the same folder:

| File | Bytes | SHA-256 | Body pose (`--body`) |
| --- | --- | --- | --- |
| `Bob_TLG_CarryVesselSneak.x` | 248,250 | `658AC930FE4F9DECDC7DCB2C532034708EE32A6BE83D69A8F0DCBAD1606967C6` | `Bob_WalkSneak.x` |
| `Bob_TLG_CarryVesselSneakIdle.x` | 307,579 | `FCBB621A5996DF47168BF7671DD7FD0CEE86C3969B3EAF3FA7C5B3498CC2A975` | `Bob_IdleSneak.x` |

```
blender -b --factory-startup --python tools/blender/pz_arms.py -- Carrying.fbx Bob_TLG_CarryVesselSneak.x Bob_TLG_CarryVesselSneak 2 0.17 0.12 CarryingBiggerArmSpace.fbx 0.5 --body <game>/media/anims_X/Bob/Bob_WalkSneak.x --arms world
blender -b --factory-startup --python tools/blender/pz_arms.py -- Carrying.fbx Bob_TLG_CarryVesselSneakIdle.x Bob_TLG_CarryVesselSneakIdle 2 0.17 0.12 CarryingBiggerArmSpace.fbx 0.5 --body <game>/media/anims_X/Bob/Bob_IdleSneak.x --arms world
```

Each holds the same arms in their standing directions, laid from the
shoulders of the game's crouch walk or crouch idle, and the held item
upright, 0.17 file units in front of the hands and 0.12 down. Their other
bones hold the first frame of the game's own clip named as the body
pose. No Mixamo bone, mesh or texture is in them. They play through
`tlgcarryvesselsneak.xml` and `tlgcarryvesselsneakidle.xml` in the same
`maskingright` folder. In-game checks: `docs/test-results.md`, launches
109–113.

Shipped for sprinting (2026-11-03), written from the same two files, in
the same folder:

| File | Bytes | SHA-256 | Body (`--body`, with `--sync`) |
| --- | --- | --- | --- |
| `Bob_TLG_CarryVesselSprint.x` | 192,047 | `2D36AC574CD6F1D26E4756AF0EE1217947A9EF889FB6FC20FEEB380B2D39141E` | `Bob_Sprint.x` |

```
blender -b --factory-startup --python tools/blender/pz_arms.py -- Carrying.fbx Bob_TLG_CarryVesselSprint.x Bob_TLG_CarryVesselSprint 2 0.17 0.10 CarryingBiggerArmSpace.fbx 0.5 --body <game>/media/anims_X/Bob/Bob_Sprint.x --arms world --sync
```

It runs as long as the game's sprint clip, 3200 ticks, with a key at
each of that clip's 21 key times. Each key holds the same arms in their
standing directions, laid from the shoulders of the sprint's pose at that
time, from the Mixamo frame at the same fraction of the clip. The held
item stands upright, 0.17 file units in front of the hands and 0.10 down.
Its other bones carry the game's own `Bob_Sprint.x` keys. No Mixamo bone,
mesh or texture is in it. It plays through `tlgcarryvesselsprint.xml` in
the same `maskingright` folder. In-game checks: `docs/test-results.md`,
launches 116–117.

Licence, recorded 2026-11-02:

* Adobe's Mixamo FAQ (helpx.adobe.com/creative-cloud/faq/mixamo-faq.html,
  "Last updated on Sep 14, 2021", read in the desktop app's browser): "You
  can use both characters and animations royalty free for personal,
  commercial, and non-profit projects", video games among them.
* Not read: Adobe's General Terms of Use and any terms specific to
  Mixamo.

Any further Mixamo clip needs the same record.

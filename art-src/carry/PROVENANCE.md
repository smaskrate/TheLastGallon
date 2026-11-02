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

Licence, recorded 2026-11-02:

* Adobe's Mixamo FAQ (helpx.adobe.com/creative-cloud/faq/mixamo-faq.html,
  "Last updated on Sep 14, 2021", read in the desktop app's browser): "You
  can use both characters and animations royalty free for personal,
  commercial, and non-profit projects", video games among them.
* Not read: Adobe's General Terms of Use and any terms specific to
  Mixamo.

Any further Mixamo clip needs the same record.

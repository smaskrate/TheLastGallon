# Biodiesel wash tank model: provenance

Supplied for the mod on 2026-11-10 in `<game>/createdAssets/BiodieselWashtank/`,
and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `tripo_convert_5ef5305a-ab51-4683-b265-a1bc2b4de111.fbx` | 49.004 | `0A5C8E37B6476F9FC58737B57BB17132D165A3B2DCEABF30B9151168AD4F0985` |
| `BiodieselWashTank_basecolor.JPEG` (from the `.fbm` folder beside it) | 134.456 | `92D3F37474900F45B6D77CCABF758998CC3810B2AC53158A17DFD737C6DA5901` |

What the files say about themselves (read with a binary dump and in
Blender 4.5.15 LTS):

* The FBX is binary, written by "Blender (stable FBX IO) - 5.0.1 -
  5.14.0". Its node, mesh and material names begin with `tripo_`: the
  same kind of file as the models supplied on 2026-11-03
  (`art-src/potstill/PROVENANCE.md`). No date was found in it; the file's
  time stamp reads 2026-11-11, a day after it was supplied (this
  machine's clock).
* One mesh: 542 vertices, 1,040 triangles. As imported it is 0.71 wide, 0.71 deep and 1.00 tall, its base at the origin.
* The texture is a 512x512 JPEG.
* What it shows: a steel drum with a cone bottom on three legs, a drain pipe under the cone.

Runtime copies in the mod: `media/models_X/TLG/BiodieselWashTank.fbx` (byte for
byte) and `media/textures/TLG/BiodieselWashTank.png` (the JPEG saved as PNG with
.NET's System.Drawing, the method that gives the pot still's shipped PNG
byte for byte: 656.728 bytes, SHA-256 `C6AF5A92A183D246221794A50AE39EC03EEAA68EADB130B836DDBBE1921A89E6`). The
model script is `TLG.BiodieselWashTank` in `media/scripts/TLG_models.txt`.

Not supplied: editable sources and an inventory icon. The icon,
`media/textures/Item_TLG_BiodieselWashTank.png` (32x32, 995 bytes, SHA-256
`1493083C96ADEB7711786509A2896F5379D08DB93284994DC3A8D0501D90633B`), was rendered
for the mod from this model and its PNG texture by
`tools/make-model-icons.ps1`; it holds nothing but that render.

Redistribution rights, recorded 2026-11-10:

* The user supplied the model for the mod ("I've put the new 3d models and
  textures to use in the createdAssets folder ... Use these").
* The basis is the one recorded for the earlier models
  (`art-src/potstill/PROVENANCE.md`): the user's statement of 2026-11-02
  that they hold a commercial Tripo licence. Whether this model was
  generated under that plan was not asked.
* Not read: Tripo's Terms of Service, nor the plan or licence document.

It replaces the shape-built placeholder the mod made for this machine on
2026-11-10 (D-036).
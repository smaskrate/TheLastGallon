# Biodiesel reactor model: provenance

Supplied for the mod on 2026-11-10 in `<game>/createdAssets/BiodieselReactor/`,
and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `tripo_convert_0d055d62-47ca-4021-ae23-376956c4445f.fbx` | 51.004 | `77922D8D02681B5470E3D17F457A80C661F61C003B83F191D2AE4B2953B30521` |
| `BiodieselReactor_basecolor.JPEG` (from the `.fbm` folder beside it) | 121.040 | `05205465FD0B53FD4A4D64BE89C2FECEB44825C6FD58608F7E1252FD0B95A331` |

What the files say about themselves (read with a binary dump and in
Blender 4.5.15 LTS):

* The FBX is binary, written by "Blender (stable FBX IO) - 5.0.1 -
  5.14.0". Its node, mesh and material names begin with `tripo_`: the
  same kind of file as the models supplied on 2026-11-03
  (`art-src/potstill/PROVENANCE.md`). No date was found in it; the file's
  time stamp reads 2026-11-11, a day after it was supplied (this
  machine's clock).
* One mesh: 552 vertices, 1,073 triangles. As imported it is 0.58 wide, 0.52 deep and 1.00 tall, its base at the origin.
* The texture is a 512x512 JPEG.
* What it shows: an open steel drum with a bar across its top, a stirrer's crank above it and a drain pipe at its foot.

Runtime copies in the mod: `media/models_X/TLG/BiodieselReactor.fbx` (byte for
byte) and `media/textures/TLG/BiodieselReactor.png` (the JPEG saved as PNG with
.NET's System.Drawing, the method that gives the pot still's shipped PNG
byte for byte: 601.657 bytes, SHA-256 `364C3290228361289427BC9D1F575F544E7DFFC4E34709561EEB1ED4017DE9D2`). The
model script is `TLG.BiodieselReactor` in `media/scripts/TLG_models.txt`.

Not supplied: editable sources and an inventory icon. The icon,
`media/textures/Item_TLG_BiodieselReactor.png` (32x32, 1.009 bytes, SHA-256
`03EBD097C0D8F4370E887DF8484F4A908301C5D481EB70464A0CF41EDAD967F4`), was rendered
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
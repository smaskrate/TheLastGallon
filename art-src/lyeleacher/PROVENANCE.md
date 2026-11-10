# Lye leacher model: provenance

Supplied for the mod on 2026-11-10 in `<game>/createdAssets/LyeLeacher/`,
and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `tripo_convert_c78fcf2e-acd8-4f1b-814e-2f77273a1307.fbx` | 47.948 | `C6890E444DB89B0BB8438CB8C0D69ED41970499FA5D8ADC5DE2EC23E51A69141` |
| `LyeLeacher_basecolor.JPEG` (from the `.fbm` folder beside it) | 121.596 | `7A758E008FC368AD7DFCABFE9888484309AD3A9FE8712DC061ED72FC86739D82` |

What the files say about themselves (read with a binary dump and in
Blender 4.5.15 LTS):

* The FBX is binary, written by "Blender (stable FBX IO) - 5.0.1 -
  5.14.0". Its node, mesh and material names begin with `tripo_`: the
  same kind of file as the models supplied on 2026-11-03
  (`art-src/potstill/PROVENANCE.md`). No date was found in it; the file's
  time stamp reads 2026-11-11, a day after it was supplied (this
  machine's clock).
* One mesh: 534 vertices, 910 triangles. As imported it is 0.82 wide, 0.76 deep and 1.00 tall, its base at the origin.
* The texture is a 512x512 JPEG.
* What it shows: a wooden stand with a cloth holding ash in its top and a cooking pot under it.

Runtime copies in the mod: `media/models_X/TLG/LyeLeacher.fbx` (byte for
byte) and `media/textures/TLG/LyeLeacher.png` (the JPEG saved as PNG with
.NET's System.Drawing, the method that gives the pot still's shipped PNG
byte for byte: 634.148 bytes, SHA-256 `793464753E7863B66CF8AE2AE1749952F7CE82F77F7A454EC2D9E983C1D95EB4`). The
model script is `TLG.LyeLeacher` in `media/scripts/TLG_models.txt`.

Not supplied: editable sources and an inventory icon. The icon,
`media/textures/Item_TLG_LyeLeacher.png` (32x32, 1.111 bytes, SHA-256
`F71E2128EC4499B3D22CD2D1A01025AB55E380DB65761AA24302939E19B29405`), was rendered
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
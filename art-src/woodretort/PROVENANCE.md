# Wood retort model: provenance

Supplied for the mod on 2026-11-10 in `<game>/createdAssets/woodRetort/`,
and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `tripo_convert_46709b8b-8858-43d1-b89f-45f7ddf23ac0.fbx` | 48.652 | `15ADB6540A8B71D7D5BE6583E6528A650207A3C53C8F5D2681026CDD62DDDF81` |
| `WoodRetor_basecolor.JPEG` (from the `.fbm` folder beside it) | 123.020 | `B97630FF0F0DD7DA86A4E11517C8039815C0CB01C04AC965E52D8F1EB212071C` |

What the files say about themselves (read with a binary dump and in
Blender 4.5.15 LTS):

* The FBX is binary, written by "Blender (stable FBX IO) - 5.0.1 -
  5.14.0". Its node, mesh and material names begin with `tripo_`: the
  same kind of file as the models supplied on 2026-11-03
  (`art-src/potstill/PROVENANCE.md`). No date was found in it; the file's
  time stamp reads 2026-11-11, a day after it was supplied (this
  machine's clock).
* One mesh: 539 vertices, 910 triangles. As imported it is 0.85 wide, 1.00 long and 0.98 tall, its base at the origin.
* The texture is a 512x512 JPEG.
* What it shows: a drum lying on a firebox with a stack behind it, a pipe from the drum into a bucket standing on the same base.

Runtime copies in the mod: `media/models_X/TLG/WoodRetort.fbx` (byte for
byte) and `media/textures/TLG/WoodRetort.png` (the JPEG saved as PNG with
.NET's System.Drawing, the method that gives the pot still's shipped PNG
byte for byte: 586.985 bytes, SHA-256 `0532C9F57BE45490C6145C88695847B9984C44E8BFCD947BEDD48DC416466969`). The
model script is `TLG.WoodRetort` in `media/scripts/TLG_models.txt`.

Not supplied: editable sources and an inventory icon. The icon,
`media/textures/Item_TLG_WoodRetort.png` (32x32, 1.157 bytes, SHA-256
`1AE764327D3CA46993CC19A15B2392E4FEB1C7EC827D47102441D7825E06E71B`), was rendered
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
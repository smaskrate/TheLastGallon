# Wood gasifier model: provenance

Supplied for the mod on 2026-11-15 in `<game>/createdAssets/woodGasifier/`,
and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `tripo_convert_ee6ca48a-acbb-49e1-a790-4d3b161e4d22.fbx` | 48.812 | `8CF19926F3BF6A2E217D0F56025E7758C3781736F359BC24C2AA65DE6A7A2132` |
| `woodGasifier_basecolor.jpg` (from the `.fbm` folder beside it) | 112.030 | `87D586DAE1CE8AA71B24C199F90A80CC69AC984A457A307C5BAECEB2054D359B` |

What the files say about themselves (read with a binary dump and in
Blender 4.5.15 LTS):

* The FBX is binary, written by "Blender (stable FBX IO) - 5.0.1 -
  5.14.0". Its node, mesh and material names begin with `tripo_`: the
  same kind of file as the models supplied on 2026-11-03 and 2026-11-10
  (`art-src/potstill/PROVENANCE.md`, `art-src/woodretort/PROVENANCE.md`).
  Its date fields read 1970-01-01. The texture's path inside it is a
  folder of Tripo Studio's server named `20261115`. The file's time stamp
  reads 2026-11-15 (this machine's clock).
* One mesh: 554 vertices, 873 triangles. As imported it is 1.00 wide, 0.64 long and 0.93 tall, its base at the origin.
* The texture is a 512x512 JPEG.
* What it shows: a green steel drum with a lid and an ash door at its
  foot, a pipe from its side into a grey filter drum with an outlet, both
  on a steel frame with four feet.

Runtime copies in the mod: `media/models_X/TLG/Gasifier.fbx` (byte for
byte) and `media/textures/TLG/Gasifier.png` (the JPEG saved as PNG with
.NET's System.Drawing, the method that gives the wood retort's shipped PNG
byte for byte: 595.168 bytes, SHA-256 `FDF43DBAA3F3CE7F74FBC5555062A175DAE10CCF906B90D15F6CBF2AAEB3DAD0`). The
model script is `TLG.Gasifier` in `media/scripts/TLG_models.txt`.

Not supplied: editable sources and an inventory icon. The icon,
`media/textures/Item_TLG_Gasifier.png` (32x32, 1.284 bytes, SHA-256
`B76F4B413ACE1774B1A3D90CBF2E6456FFE9EA91DABD30E8D90A49A36E32E0E2`), was rendered
for the mod from this model and its PNG texture by
`tools/make-model-icons.ps1`, from the front; it holds nothing but that
render.

Redistribution rights, recorded 2026-11-15:

* The user supplied the model for the mod ("I've put the wood gasifier in
  the createdAssets folder. Replace the current model with that").
* The basis is the one recorded for the earlier models
  (`art-src/potstill/PROVENANCE.md`): the user's statement of 2026-11-02
  that they hold a commercial Tripo licence. Whether this model was
  generated under that plan was not asked.
* Not read: Tripo's Terms of Service, nor the plan or licence document.

It replaces the shape-built placeholder the mod made for this machine on
2026-11-13 (D-040).

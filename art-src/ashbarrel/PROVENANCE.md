# Ash barrel model: provenance

Supplied for the mod on 2026-11-10 in `<game>/createdAssets/metalBarrel/`,
and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `tripo_convert_8b62e9a9-ee49-4d42-bcce-e61165fb4979.fbx` | 49.948 | `7B574A2644A8243E17EA97602138DADA5BA9D0517C7152A2E1B10D380CC92DD8` |
| `MetalBarrel_basecolor.JPEG` (from the `.fbm` folder beside it) | 116.524 | `40ABD3A3F44CB56BDCCD5E74C61BD53ECC84D929E40254E60D7A007535714E7C` |

What the files say about themselves (read with a binary dump and in
Blender 4.5.15 LTS):

* The FBX is binary, written by "Blender (stable FBX IO) - 5.0.1 -
  5.14.0". Its node, mesh and material names begin with `tripo_`: the
  same kind of file as the models supplied on 2026-11-03
  (`art-src/potstill/PROVENANCE.md`). No date was found in it; the file's
  time stamp reads 2026-11-11, a day after it was supplied (this
  machine's clock).
* One mesh: 588 vertices, 1,084 triangles. As imported it is 0.76 wide over its handles, 0.64 deep and 1.00 tall, its base at the origin.
* The texture is a 512x512 JPEG.
* What it shows: a lidded steel drum with two side handles and two bungs in its lid. The folder it came in is named metalBarrel; it is used for the ash barrel.

Runtime copies in the mod: `media/models_X/TLG/AshBarrel.fbx` (byte for
byte) and `media/textures/TLG/AshBarrel.png` (the JPEG saved as PNG with
.NET's System.Drawing, the method that gives the pot still's shipped PNG
byte for byte: 555.370 bytes, SHA-256 `8B5CD3ED67F50929EC47CA2439D1A294D1C1734414AD93F4C61AF22D8F7FA3E6`). The
model script is `TLG.AshBarrel` in `media/scripts/TLG_models.txt`.

Not supplied: editable sources and an inventory icon. The icon,
`media/textures/Item_TLG_AshBarrel.png` (32x32, 1.128 bytes, SHA-256
`46E8A4F6F316FE90732039BEB16E2653DB94D873797F3F29130506362F2E96B5`), was rendered
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
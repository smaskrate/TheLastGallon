# Fuel filter model: provenance

Supplied for the mod on 2026-11-03 in `<game>/createdAssets/FuelFilter/`,
and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `tripo_convert_a151627a-670c-4e70-8229-13202e13306c.fbx` | 47,564 | `715C592AB70D5C3A93EFE0DFB6CAD3097448E52EE2EA93547CFB3E5CECA89E0A` |
| `FuelFilter_basecolor.JPEG` (from the `.fbm` folder beside it) | 128,890 | `52C93422058D067062182820D030E7DA1033EE2E65C44607CB1C7FBFAC505AF6` |

What the files say about themselves (read with a binary FBX dump and in
Blender 4.5.15 LTS):

* The FBX is binary, version 7400, written by "Blender (stable FBX IO) -
  5.0.1 - 5.14.0".
* Its node, mesh and material names begin with `tripo_`, and its texture
  reference is a path under `/mnt/pfs/server/tripo-studio/20261103/`: the
  model was generated with Tripo Studio on 2026-11-03.
* Y up, metres (`UnitScaleFactor` 100). One mesh: 525 vertices, 993
  triangles, UVs within 0..1. The node turns the Z-up geometry −90° about
  X, so the model is 0.91 wide, 1.00 tall and 0.90 deep, its base at the origin.
* The texture is a 512×512 RGB JPEG with no alpha.
* What it shows: a squat canister with a screw lid.

Runtime copies in the mod: `media/models_X/TLG/FuelFilter.fbx` (byte for
byte) and `media/textures/TLG/FuelFilter.png` (the JPEG saved as PNG,
512×512, 603,980 bytes, SHA-256 `17D2181FF3CA136583BE5E70AF71E8C109D17634EFF282D04F17CBCB10D2E9DE`), made as the fermenter's
was: that method gives the fermenter's shipped PNG byte for byte. The
model script is `TLG.FuelFilter` in `media/scripts/TLG_models.txt`.

Not supplied: editable sources (a `.blend` file or the Tripo project) and
an inventory icon. The icon, `media/textures/Item_TLG_FuelFilter.png` (32×32,
1100 bytes, SHA-256 `21198A5BCA9B6BA3FE166C56C24676F0E974DC8DD6BC3103B491E94B24D44111`), was rendered for the mod
from this model and its PNG texture by `tools/make-model-icons.ps1`
(`tools/blender/pz_icon.py`: Blender 4.5.15 LTS, Eevee, reduced to
twelve colours with the fermenter icon's outline); it holds nothing but
that render.

Redistribution rights, recorded 2026-11-03:

* The user stated, in the asset-requirements session on 2026-11-02: "I
  have a commercial license for tripo". This model was generated the next
  day (the date in its texture path) and supplied by the user for the mod.
  Whether the paid plan was still active that day was not asked.
* Basis, as for the fermenter (`art-src/fermenter/PROVENANCE.md`): Tripo's
  help pages, as a web search summarised them, give a paid plan's user
  full rights to use, modify, distribute and commercially exploit the
  models they generate (Terms §5.2.2).
* Not read: the Terms of Service text itself, nor the plan or licence
  document.

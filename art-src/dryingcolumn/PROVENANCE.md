# Drying column model: provenance

Supplied for the mod on 2026-11-03 in `<game>/createdAssets/DryingColumn/`,
and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `tripo_convert_56d1d910-1bfe-45e6-b11e-cd13a0c18f59.fbx` | 48,156 | `E5E400B909EF54B4A38FE8C810B322C6A1908F34D5AE46815CC052B41B6AFA9B` |
| `salt_grinder_3d_model_basecolor.JPEG` (from the `.fbm` folder beside it) | 114,215 | `ED96DE4DCD83A8479F48676AF22666C16FDF9105B2BA5AA6B10C80A8D8C2C863` |

What the files say about themselves (read with a binary FBX dump and in
Blender 4.5.15 LTS):

* The FBX is binary, version 7400, written by "Blender (stable FBX IO) -
  5.0.1 - 5.14.0".
* Its node, mesh and material names begin with `tripo_`, and its texture
  reference is a path under `/mnt/pfs/server/tripo-studio/20261103/`: the
  model was generated with Tripo Studio on 2026-11-03.
* Y up, metres (`UnitScaleFactor` 100). One mesh: 534 vertices, 1036
  triangles, UVs within 0..1. The node turns the Z-up geometry −90° about
  X, so the model is 0.43 wide, 1.00 tall and 0.43 deep, its base at the origin.
* The texture is a 512×512 RGB JPEG with no alpha.
* What it shows: a pipe column standing in a jar (the receiver), the jar
  0.425 across and 0.48 tall. Tripo named the texture after a salt
  grinder; the name is kept as delivered.

Runtime copies in the mod: `media/models_X/TLG/DryingColumn.fbx` (byte for
byte) and `media/textures/TLG/DryingColumn.png` (the JPEG saved as PNG,
512×512, 544,252 bytes, SHA-256 `EEE14CD98C3C0444BA6A65168EF32F4C3442482032F007E025905F41F08BC8AF`), made as the fermenter's
was: that method gives the fermenter's shipped PNG byte for byte. The
model script is `TLG.DryingColumn` in `media/scripts/TLG_models.txt`.

Not supplied: editable sources (a `.blend` file or the Tripo project) and
an inventory icon; the item still shows a vanilla icon.

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

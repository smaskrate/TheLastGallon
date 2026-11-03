# Reflux still model: provenance

Supplied for the mod on 2026-11-03 in `<game>/createdAssets/RefluxStill/`,
and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `tripo_convert_a229838f-3607-4fa4-ba42-d309659bc9e2.fbx` | 52,524 | `AB2F8A5020CAD4B65E1CB9D5B012A9BB2D2232955D2A78DC69DFF6323A266896` |
| `RefluxStill_basecolor.JPEG` (from the `.fbm` folder beside it) | 157,795 | `249F8400DCB77FEA92FAD4D7002D10BAD83FB277F46CDB6F9F62D14EB9489933` |

What the files say about themselves (read with a binary FBX dump and in
Blender 4.5.15 LTS):

* The FBX is binary, version 7400, written by "Blender (stable FBX IO) -
  5.0.1 - 5.14.0".
* Its node, mesh and material names begin with `tripo_`, and its texture
  reference is a path under `/mnt/pfs/server/tripo-studio/20261103/`: the
  model was generated with Tripo Studio on 2026-11-03.
* Y up, metres (`UnitScaleFactor` 100). One mesh: 579 vertices, 1076
  triangles, UVs within 0..1. The node turns the Z-up geometry −90° about
  X, so the model is 0.77 wide, 1.00 tall and 0.67 deep, its base at the origin.
* The texture is a 512×512 RGB JPEG with no alpha.
* What it shows: a pot boiler 0.41 across under a column with a
  condenser box, its outlet hose ending in the air.

Runtime copies in the mod: `media/models_X/TLG/RefluxStill.fbx` (byte for
byte) and `media/textures/TLG/RefluxStill.png` (the JPEG saved as PNG,
512×512, 674,213 bytes, SHA-256 `4D53145F72100A8F374DC8813FA44392BA4327469FC0E82B3F7D81300230CCFA`), made as the fermenter's
was: that method gives the fermenter's shipped PNG byte for byte. The
model script is `TLG.RefluxStill` in `media/scripts/TLG_models.txt`.

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

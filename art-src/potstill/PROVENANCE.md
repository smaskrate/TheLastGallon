# Pot still model: provenance

Supplied for the mod on 2026-11-03 in `<game>/createdAssets/PotStill/`,
and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `tripo_convert_606baa46-ed11-4803-9192-8f9db6a4cd47.fbx` | 47,596 | `75B28B816990B1D06FBBD8C7F1E712CC0B08D76DDC12C735577A2EFFABFCF437` |
| `PotStill_basecolor.JPEG` (from the `.fbm` folder beside it) | 143,967 | `A82BD941C31967D8D532E0792F89E3EFF6FBFB1B01E0BC5D5FCDF333E13D22F3` |

What the files say about themselves (read with a binary FBX dump and in
Blender 4.5.15 LTS):

* The FBX is binary, version 7400, written by "Blender (stable FBX IO) -
  5.0.1 - 5.14.0".
* Its node, mesh and material names begin with `tripo_`, and its texture
  reference is a path under `/mnt/pfs/server/tripo-studio/20261103/`: the
  model was generated with Tripo Studio on 2026-11-03.
* Y up, metres (`UnitScaleFactor` 100). One mesh: 522 vertices, 981
  triangles, UVs within 0..1. The node turns the Z-up geometry −90° about
  X, so the model is 1.00 wide, 0.65 tall and 0.64 deep, its base at the origin.
* The texture is a 512×512 RGB JPEG with no alpha.
* What it shows: a lidded pot whose swan neck arcs over to a hose. The
  pot is 0.42 across; both its bottom and the hose's end stand on the
  base.

Runtime copies in the mod: `media/models_X/TLG/PotStill.fbx` (byte for
byte) and `media/textures/TLG/PotStill.png` (the JPEG saved as PNG,
512×512, 663,927 bytes, SHA-256 `2FA8395F592E4BCFC10AEC9B41F6B5A2B7BEF01D9C9C594AB56AAAA5FC94AA1A`), made as the fermenter's
was: that method gives the fermenter's shipped PNG byte for byte. The
model script is `TLG.PotStill` in `media/scripts/TLG_models.txt`.

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

# Fermenter model: provenance

Supplied for the mod on 2026-11-02 as `<game>/createdAssets/fermenter.fbx`
and `fermenter.fbm/fermenter_basecolor.JPEG`, and kept here as delivered:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `fermenter.fbx` | 49,836 | `D1D509A5F1108F78774C0EC0E6E8FB5A7D6DF89CBA1438C4FF34393E4455681E` |
| `fermenter_basecolor.jpg` | 113,165 | `64FF30AC24F71B15D0857150F3B972EAAD3B64D994B482E02AFC908F2835560F` |

What the files say about themselves (read with a binary FBX dump):

* The FBX is binary, version 7400, written by "Blender (stable FBX IO) -
  5.0.1 - 5.14.0".
* Its node, mesh and material names begin with `tripo_`, and its texture
  reference is a path under `/mnt/pfs/server/tripo-studio/20261102/`: the
  model was generated with Tripo Studio.
* Y up, metres (`UnitScaleFactor` 100). One mesh: 550 vertices, 949
  triangles, UVs within 0..1. The node turns the Z-up geometry −90° about
  X, so the model is 0.86 wide, 1.00 tall and 1.00 deep, its base at the
  origin.
* The texture is a 512×512 RGB JPEG with no alpha.

Runtime copies in the mod: `media/models_X/TLG/Fermenter.fbx` (byte for
byte) and `media/textures/TLG/Fermenter.png` (the JPEG saved as PNG,
512×512, 603,001 bytes, SHA-256 `15E80F61…3A6F77`). The model script is
`TLG.Fermenter` in `media/scripts/TLG_models.txt`.

Not supplied: editable sources (a `.blend` file or the Tripo project) and
an inventory icon.

Redistribution rights: not recorded. They follow from the terms that
applied to the Tripo account that generated the model, and must be
confirmed before any public release (release gate 9).

# Notices

* The package copies no game assets (`docs/asset-audit.csv`). Every
  item's icon (`media/textures/Item_TLG_*.png`) was made for the mod: the
  vessel's drawn by `tools/make-icons.ps1`, the stills', the drying
  column's and the fuel filter's rendered from their own supplied models
  by `tools/make-model-icons.ps1`, and the sampling kit's, the yeast
  starter's, the stabilizer's and the manual's rendered by the same tool
  from simple shapes built for them (`tools/blender/pz_icon_props.py`).
* The floor models of the sampling kit, the yeast starter, the stabilizer
  and the manual (`FuelSampleKit`, `YeastStarter`, `FuelStabilizer` and
  `ManualFuelSystems` in `media/models_X/TLG` and `media/textures/TLG`)
  were made for the mod from the same shapes by
  `tools/make-prop-models.ps1` (`tools/blender/pz_prop_models.py`).
* The fermentation vessel's model and texture
  (`media/models_X/TLG/Fermenter.fbx`, `media/textures/TLG/Fermenter.png`)
  were supplied for this mod on 2026-11-02, and the pot still's, the
  reflux still's, the drying column's and the fuel filter's
  (`PotStill`, `RefluxStill`, `DryingColumn` and `FuelFilter` in the same
  folders) on 2026-11-03; each model file names Tripo Studio as the tool
  that generated it. They were generated under a commercial Tripo
  licence, which Tripo's published help pages say allows their
  distribution (`PROVENANCE.md` in `art-src/fermenter`, `art-src/potstill`,
  `art-src/refluxstill`, `art-src/dryingcolumn` and `art-src/fuelfilter`).
* The biodiesel chain's five machines' models and textures (`WoodRetort`,
  `AshBarrel`, `LyeLeacher`, `BiodieselReactor` and `BiodieselWashTank` in
  the same folders) were supplied for this mod on 2026-11-10. Each model
  file's names are Tripo's, as the earlier models' are. The basis for
  their distribution is the same commercial Tripo licence; whether these
  five were generated under it was not asked (`PROVENANCE.md` in
  `art-src/woodretort`, `art-src/ashbarrel`, `art-src/lyeleacher`,
  `art-src/biodieselreactor` and `art-src/biodieselwashtank`).
* The diesel generator's tile sprite and icon
  (`media/textures/TLG/Tile_DieselGenerator.png`,
  `media/textures/Item_TLG_DieselGenerator.png`) were made for the mod
  from its own shapes by `tools/make-tile-sprites.ps1` and
  `tools/make-model-icons.ps1`.
* The fermentation vessel's carry animations
  (`media/anims_X/Bob/Bob_TLG_CarryVessel.x`, and the crouched and sprint
  clips `Bob_TLG_CarryVesselSneak.x`, `Bob_TLG_CarryVesselSneakIdle.x` and
  `Bob_TLG_CarryVesselSprint.x`) were made for this mod from
  Mixamo's "Carrying" animation (Adobe), supplied on 2026-11-02. Only the
  arm movement was carried over, onto the game's own skeleton; no Mixamo
  character, bone or mesh is included. Adobe's Mixamo FAQ says its
  animations may be used royalty free in video games
  (`art-src/carry/PROVENANCE.md`).
* The Workshop preview and the mod list's poster (`preview.png` beside
  the item's `Contents` folder, and `42/poster.png`, the same picture)
  were made for the mod by `tools/make-preview.ps1`: the five supplied
  machine models above rendered in Blender (`tools/blender/pz_preview.py`)
  under the title, set in Bahnschrift (Microsoft) and Stencil (URW and
  Microsoft), fonts installed on the computer it was made on. The picture
  holds only their rendered letters, no font file. The mod list's icon
  (`42/icon.png`) is the fermentation vessel's inventory icon.
* Licence: `LICENSE.md`. The supplied models and the carry animations are
  not under the mod's licence.
* No external mods, libraries or Workshop content are bundled or required.
* Real-world references in the specification (R8–R13) informed abstract game
  rules only; no text or data from them is reproduced.

# Visual slice V1 provenance

All changed models are generated from the existing original Dead Days scripts in
`tools/generate_*.py`. The structural surface maps are original outputs of
`tools/generate_surface_maps.py` (NumPy/Pillow), not scans or extracted game art.
The PBR recipe registry is `godot/data/material_library_v1.json`. Generated source
projects pack their texture images. The project owner determines release terms;
this record does not invent a repository-wide third-party license.

`visual-slice-v1-manifest.json` records matching source/GLB hashes and material/map
manifest hashes. Map-level provenance and SHA values are in
`godot/assets/materials_v1/manifest.json`.

No new external runtime asset is introduced. The pre-existing Poly Haven ground
diffuse remains CC0 with evidence in `art-library/index/LICENSE_LEDGER.md`.
User-provided screenshots and the AI appearance sheet are design references only,
with provenance in `art/references/manifest.json`; they are outside `godot/` and
must not ship as game textures or publicity captures.

Operation audio V1 is original deterministic PCM synthesis in
`godot/scripts/game_audio.gd`, with recipes in `godot/data/audio.json`.
It contains no external recording, downloaded sample, or reference-game audio.
No additional third-party commercial-use permission is required for sample inputs;
repository-wide release terms remain the project owner's decision.

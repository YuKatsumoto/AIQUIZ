# Santorini waterfront infrastructure

Authored in the visible Blender 5.1 session through Higgsfield Bridge and Blender MCP on 2026-09-14. No paid generation, downloaded models or new third-party textures were used. The existing project-authored Santorini town and terrace are references; their original GLBs and Blender files remain unchanged.

## Editable source

- `source/20260914_waterfront_final.blend`: complete editable design, original protected Scene, modular source scene and inspection cameras. Saved as a copy from the live Blender window.
- `source/live_waterfront.py`: staged live-session construction functions, not a destructive standalone reset script. Inspect the existing scene before running a phase again.
- The source folder has `.gdignore` to avoid importing authoring data into Godot.

## Exported modules

| File | Purpose |
| --- | --- |
| waterfront_foundations.glb | One seabed and 13 separate district foundation extensions |
| santorini_open_terrace_grounded.glb | Existing low terrace with 18 columns and 18 footings extended to the seabed; rear aisle openings |
| access_stair.glb | 36 risers, two flights, intermediate landing, handrails and grounded supports |
| pier_bay.glb | Repeated 4m pier bay with paving, rails and grounded supports |
| quay_gateway.glb | Open arch, arrival threshold, side walls and open blue shutters |
| gate_filler.glb | Closes unused terrace openings and excess width beside the stairs |

Blender uses metres and Z up. Export converts to Godot Y up. Sea Y = -9.2; seabed top and conveyor bottom Y = -17.2; terrace entry Y = 1.52; quay deck Y = -5.16. Existing district bottoms Y = -14.2 receive 3m extensions. Terrace support bottoms extend downward by 7.2m while seat levels remain fixed.

`scripts/world/santorini_waterfront.gd` attaches two routes to each stand's real aisles. The stair remains at metre scale while pier bays span to the nearest town promenade. Bays and unused gate rails use MultiMesh. Layout changes resynchronize routes. Low quality disables their shadows; geometry GI remains disabled to match the existing town.

The infrastructure is scenery, with no new collision bodies or navigation simulation. It does not add player access or walking spectators. Existing gameplay collisions and fall/shark paths remain in charge.

Verification and images: `docs/santorini_waterfront_design.md`, `artifacts/santorini_waterfront/`, and the `waterfront_*` sequences in `artifacts/santorini_renovation/`. The live test fixture is `tests/santorini_waterfront_runtime.gd`.

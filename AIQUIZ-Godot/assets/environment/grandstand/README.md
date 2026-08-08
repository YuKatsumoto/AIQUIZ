# AIQUIZ Ocean Grandstand

Original, game-ready ocean grandstand created for AIQUIZ.

- 160 m long architectural asset aligned to the nominal gameplay conveyor
- Exact roof-to-purlin-to-truss-to-column-to-foundation load-path detailing
- More than 1,400 individually modeled seats, generated deterministically
- Central broadcast booth, glass wind screens, roof trusses, aisle rails, signage, and architectural lighting
- Ocean-depth pile foundation aligned around the AIQUIZ course floor datum
- One GLB instance is reused for the left and right sides of the gameplay course
- Blender source contains a compact LOD1 silhouette for future distance-range tuning

Runtime asset: `aiquiz_ocean_grandstand.glb`

Editable source: `source/aiquiz_ocean_grandstand.blend`

Deterministic generator: `source/build_grandstand.py`

The `source` directory is excluded from Godot import scanning with `.gdignore`; only the GLB is loaded at runtime.

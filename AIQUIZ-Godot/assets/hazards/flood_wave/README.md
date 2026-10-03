# Flash flood (鉄砲水) — milestone 4 art

The flood of the 2P sudden death (docs/sudden_death_underground.md 6.6). Built in the user's live Blender
(`source/flood_wave.blend`, scripts in `source/`, run through `source/jobs.py`; never `blender --background`).
Everything is self-authored (procedural geometry and numpy noise; no downloaded, purchased or generated images).

## Files

| File | Content |
| --- | --- |
| `flood_front.glb` | The front as a fixed grid: 229 columns across the whole hall (x = -45..45 m, 0.25 m in the 24 m corridor, 0.5 m in the aisles) x 72 rows along the profile (from the flat water 9 m behind, over the crest and the lip, down the face to the toe on the floor). 16,488 vertices, 32,376 triangles. UV0 = metres / 4 (u across, v along the profile), UV1 = VAT address |
| `textures/flood_front_vat_pos.exr` | VAT, RGBA half: position (Godot metres) + foam (0..1). 4096 wide; frame f is rows `f * 5 .. f * 5 + 4` from the top |
| `textures/flood_front_vat_nrm.png` | VAT, RGBA8: normal * 0.5 + 0.5, same layout |
| `textures/flood_foam.png` | tileable 1024: R bubble lace (Worley cell walls, two scales), G coarse patches, B streaks |
| `textures/flood_water_normal.png` | tileable 1024 OpenGL normal map of churned water |
| `textures/flood_spray.png` | 4 x 4 sprite atlas (white + alpha): row 0 mist veils, 1 spume wisps, 2 droplet clusters, 3 droplet streaks |
| `flood_wave_layout.json` | counts, VAT layout, crest height, water depth, back edge, baked bounds (checked by tests/sudden_death_unit.gd) |
| `source/previews/front_f12.png` | review render of frame 12 |

## The front

Godot coordinates (x across, y up, z = direction of travel), the toe at z = 0 on the floor. A turbulent bore
3.4 m high that settles into 1.2 m of water 9 m behind. Each column runs a 2.0 s roller cycle — the lip throws
forward, plunges onto the face and is swallowed by the next — with its own phase, a smooth function of x, so
the crest breaks unevenly across the hall without seams. Travelling turbulence (22 sine trains with whole
cycles per loop) rides on the profile, strongest on the lip and the face. 48 frames at 24 fps loop exactly.

Foam per vertex (VAT alpha): whitewater on the lip (0.62–1), falling foam on the upper face (0.35–0.85), streaky
churn lower down (0.06–0.44), an apron at the toe (0.5–0.9), a few streaks on the back slope (0.04–0.26). The
Godot shader breaks it up with the foam texture.

Why not a fluid simulation (as the spec first said): a simulated mesh changes vertex count every frame and does
not loop; a VAT needs one fixed topology and a seamless loop.

## Godot side

`scripts/world/sudden_death/flood_wave.gd` (FloodWave) with `shaders/sudden_death/flood_front.gdshader` (VAT,
opaque) and `flood_water.gdshader` (the water behind, transparent with refraction). The VAT lookup:

```glsl
int px = int(UV2.x * 4096.0);
int row = int((1.0 - UV2.y) * 8.0);     // glTF flips V
vec4 p = texelFetch(vat_pos, ivec2(px, frame * 5 + row), 0);   // xyz position, w foam
```

Import settings: the VAT textures lossless without mipmaps (nearest), the others VRAM compressed with mipmaps;
the GLB without LODs or shadow meshes (LODs would rebuild the index buffer from the rest pose). The builder
(tools/sudden_death/build_cistern_scenes.gd) saves the front's mesh as
`scenes/sudden_death/cistern_generated/flood/front_mesh.res` and hands all six assets to CisternStage, so
they load on the loader's thread.

## Rebuild (live Blender only)

```python
ns = {"__name__": "flood_jobs"}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/hazards/flood_wave/source/jobs.py", encoding="utf-8").read(), ns)
ns["start"]("all", [("build_flood_wave.py", "build_front", ()), ("build_flood_wave.py", "bake_textures", ()),
	("build_flood_wave.py", "export_front", ()), ("build_flood_wave.py", "render_preview", ()), ("jobs.py", "save", ())])
```

Progress goes to `%TEMP%/aiquiz_flood_jobs/<name>.json`. The front object `FLW_Front` carries one shape key per
frame keyed in sequence, so the loop plays in Blender's viewport (frames 1–48). Then reimport in Godot and rerun
the builder.

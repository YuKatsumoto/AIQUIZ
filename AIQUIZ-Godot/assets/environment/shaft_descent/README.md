# Shaft descent (黄色いランプの縦穴)

Assets for the 2P sudden-death descent loading (docs/sudden_death_underground.md ch.5):
a reinforced-concrete shaft (inner diameter 14 m) lit by caged explosion-proof sodium
lamps, the surface mouth with its iris hatch and rotating beacons, the elevator deck and
the depth signs. Original self-authored geometry and procedural materials (no purchased,
downloaded or generated images). Used by `scripts/world/sudden_death/shaft_descent.gd`
(`scenes/sudden_death/shaft_descent.tscn`).

## Files

| File | Content |
| --- | --- |
| `shaft_tile.glb` | One 5.0 m ring of the shaft (lamp row period). `SHD_Tile_Wall` (UV0 = baked textures), `_Rails` (2 I-beam guide rails at ±X), `_Galv` (2 galvanized pipes, caged maintenance ladder, ladder-type cable tray, lamp conduit ring), `_Cables`, `_LampBody`, `_LampGlass`. 28.4k triangles. Godot stacks 12 with MultiMeshes. |
| `shaft_deck.glb` | `SHD_Deck_Root`: R5.2 deck, top at y = 0, body 0.45 m. Grating disc (shaded procedurally in Godot), hazard edge band, frame (8 radial I-beams, ring beams, hub), opaque pad plates (r 1.3 at x = ±2.2, full deck depth), guide shoes reaching the rails at ±X (top −0.06), 4 wire anchors (`SHD_Deck_WireAnchor_k` empties at r 4.4, 45°+90°k, y 0.30). 6.6k triangles. |
| `shaft_mouth.glb` | `SHD_Mouth_Root`: collar ring r 7.0–7.6 (top 8 mm proud of the floor plane so it never z-fights it), steel liner (r 6.985, below a blade slot), 8 iris blades `SHD_Blade_0..7` (origin = hinge pivot at r 7.10, y −0.045), 4 beacons `SHD_Beacon_k` with `_Lens` and `_Reflector` children (beam = reflector local +X). |
| `shaft_sign.glb` | `SHD_Sign_Root`: blank 1.5 × 0.75 m enamel board in a steel frame on two stand-offs, facing Godot −Z; `SHD_Sign_TextAnchor` on the face. |
| `textures/shaft_wall_masks.png` | 8192 × 1024, wall UV: R tone (linear albedo), G wetness, B efflorescence, A rust bleed. |
| `textures/shaft_wall_normal.png` | RGB tangent normal (OpenGL, +V up: tie holes, plywood grain, bugholes, panel joints), A cavity. |
| `textures/shaft_wall_light.png` | 2048 × 512 lamp lightmap (white light): centre tile of a 5-tile stack, direct + blurred bounce, value = (E / light_max)^(1/2.2). |
| `textures/shaft_concrete_detail_normal.png` | 1 m × 1 m tileable micro relief for close-ups. |
| `textures/shaft_bake.json` | Bake metadata: `light_max_over_C` = 3.1706 converts the lightmap to the units of the analytic lamp term `C·cosθ/d²` used in the shaders. |
| `shaft_descent_layout.json` | Godot-space numbers (lamp positions, rails, anchors, iris, collar). |
| `source/` | `shaft_descent.blend`, `shaft_common.py`, `build_shaft.py`, `bake_shaft.py`, `export_shaft.py`, review renders in `previews/` (`.gdignore`d). |

All tile props repeat every 5 m. Form joints are real 40 × 20 mm grooves at y = 0.5 +
1.667 k (the spec's 1.5 m pour height rounded to three pours per lamp row so the tile
stays seamless). Godot azimuths (from +X toward +Z): rails 0°/180°, lamps 45°/135°/225°/315°
(rotated 45° off the axes so the guide rails at ±X stay clear), pipes 60°/67°, ladder 112°,
cable tray 160°, depth signs 90°. Lamp light centre: r 6.55, y 2.95 in the tile. The
innermost prop (ladder cage) is at r 6.08.

## Rebuild (live Blender only)

Per AGENTS.md, run everything in the user's open Blender through the Higgsfield `bl_execute`
connector (never `blender --background`), then save the `.blend`:

```python
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/shaft_descent/source/build_shaft.py", encoding="utf-8").read(), {"__name__": "__main__"})
ns = {}; exec(open(".../source/bake_shaft.py", encoding="utf-8").read(), ns)
ns["bake_mask"](1)  # ... 2, 3, 4, 5 (one call each; ~3 s on an RTX 5070)
ns["bake_detail"](); ns["bake_light"]("DIRECT"); ns["bake_light"]("INDIRECT"); ns["calibrate"](); ns["pack"]()
exec(open(".../source/export_shaft.py", encoding="utf-8").read(), {"__name__": "__main__"})
bpy.ops.wm.save_mainfile()
```

Then `Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`. The texture
`.import` files are hand-set: BC7 for the packed RGBA maps with `fix_alpha_border=false`
(the alpha channels are data), RGTC for the detail normal.

The concrete is one procedural Cycles material (`SHD_Concrete`): cast-in-place tone with
per-panel and per-pour variation, form-tie holes (some mortar-patched, some rusting),
panel-joint paste bands, bugholes denser near the top of each pour, seepage and water
streaks below the cold joints, efflorescence crusts and runs, rust bleed under every steel
bracket. Every pattern is periodic around the shaft and every 5 m, using 4D noise on
(x, y, ρ·cos 2πz/5, ρ·sin 2πz/5). The lamp lightmap is baked with point lights in the 20
lamps of a 5-tile stack, the glass invisible to shadow rays, so the housing's upward
cut-off and the shadows of rails, pipes, ladder and cage are in the light.

## In Godot

Walls and hardware are unshaded: the wall shader multiplies the baked light by the sodium
colour, adds GGX highlights of the 12 nearest lamps on the wet streaks, relights the normal
map toward the nearest lamp, and breaks the 5 m repeat with world-space noise in wall
coordinates (`w = local_y − scroll`, so stains move with the wall). Props use the same
analytic lamp term plus a bounce estimate from the lightmap, so every row reads lit with
only 12 real lights. Deck, collar, blades, beacons and characters use real lights.

The iris opens by folding each blade down about the tangent through its pivot (92°): the
blade swings into the shaft and ends behind the concrete in the wall pocket (r ≥ 7.05),
so nothing of the hatch ever shows outside the collar or above the floor.

Review images: `artifacts/sudden_death/shaft/<shot>_<quality>.png` from
`tests/shaft_descent_bootstrap.gd` (see the header of `tests/shaft_descent_preview.gd`).

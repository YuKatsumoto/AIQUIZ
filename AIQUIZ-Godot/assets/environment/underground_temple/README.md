# Underground cistern (地下神殿) — milestone 3 art

Environment modules for the 2P sudden-death stage (docs/sudden_death_underground.md ch.6, contract
docs/sudden_death_m3_interface.md): a fictional pressure-control tank — raw formwork concrete
pillars in a dark forest, wet reflective floor, white floodlights and amber safety lamps. All
geometry and every texture are self-authored in Blender (procedural Cycles materials baked to
images; no downloaded, purchased or generated images, no real facility names or logos).

## Files

| File | Content |
| --- | --- |
| `cistern_bay_a.glb` / `_b` / `_c` | one 15 m bay (z −7.5..7.5): floor with drain channels, 6 pillars, walls, beams, soffit, railings, trays, pipes, 2 floods, amber lamps. Variants differ in dirt (lightmap), puddles (vertex colour) and props |
| `cistern_bay_opening.glb` | bay k = 0 with the R 7.0 ceiling opening, rim y 18–19 and hazard band, no beam across the opening |
| `cistern_end_upstream.glb` | world z −30.6..−22.5 (+ tunnel to −45): end wall, inflow tunnel, `CIS_InflowGate`, control room + balcony |
| `cistern_end_downstream.glb` | world z 202.5..211.2: end wall, 2 caged ladders, walkway y 6, `CIS_Hatch_L` / `CIS_Hatch_R`, pump intake screens, fictional sign |
| `cistern_layout.json` | everything Godot needs: per module light anchors (colour, power, suggested Godot light), `light_max`, triangle counts, moving nodes; hall dimensions; UV0 scales; encodings |
| `textures/` | tiling PBR sets, per-module lightmaps `<module>_light.png`, `cistern_sign.png`. No decal atlas: the Godot builder (`tools/sudden_death/build_cistern_scenes.gd`) draws the decal sprites (pillar numbers, rust runs, efflorescence, stains) procedurally; the dirt that belongs to the surfaces is baked into the lightmaps |
| `DELIVERY.log` | one line per delivered file |
| `source/` | `underground_temple.blend` and the scripts (`.gdignore`d), review renders in `source/previews/` |

Delivery status: see `DELIVERY.log`.

## Conventions

- Godot units (m), Y up, flood flows toward +Z. Module floor at y = 0; Godot places modules at
  y = `SuddenDeathLayout.FLOOR_Y`. Bays are module-local (z −7.5..7.5, pillars at z 0..7, place at
  world z = 15 k); the two ends are authored in world z and placed at the origin.
- Nodes: meshes `CIS_Shell` (concrete), `CIS_Floor`, `CIS_Steel`, `CIS_Galv`, `CIS_Grate`,
  `CIS_FloodLens` (white emissive fronts), `CIS_AmberLens`, and per module extras (`CIS_Hazard`,
  `CIS_Sign`, `CIS_WindowGlass`, `CIS_Interior`, `CIS_Void`, `CIS_InflowGate`, `CIS_Hatch_L/R`).
  Light anchors are empties `CIS_Light_<Flood|Amber|Window>_<n>`; their −Z is the light direction.
- glTF materials (by name only, Godot builds the shaders):

| Material | Use | Maps (textures/) | UV0 m / unit |
| --- | --- | --- | --- |
| `CIS_Concrete` | walls, pillars, soffit, beams, rubble | `concrete_albedo/normal/orm` | 3.75 |
| `CIS_Floor` | floor slab, channel walls | `floor_albedo/normal/orm/wet` + COLOR_0 | 3.75 |
| `CIS_SteelPaint` | fixtures, brackets, cabinets, drums, cables | `steel_albedo/normal/orm`, tint = COLOR_0 | 1.0 |
| `CIS_Galvanized` | pipes, trays, railings, cages, grating frames | `galv_albedo/normal/orm` | 1.0 |
| `CIS_Grate` | channel gratings (alpha scissor) | `grate_albedo` (A = coverage), `grate_normal/orm` | 0.5 |
| `CIS_Hazard` | yellow/black bands | `hazard_albedo` + `steel_normal/orm` | 1.0 |
| `CIS_LampLens` | flood fronts (emissive, ~5000 K) | — | — |
| `CIS_LampLensAmber` | safety-lamp glass (emissive, ~2000 K) | — | — |
| `CIS_Sign`, `CIS_WindowGlass`, `CIS_Interior`, `CIS_Void` | ends only (sign board, control-room glass, room interior, black voids behind screens) | see below | |

- `orm` = R ambient occlusion (cavity), G roughness, B metallic. Normal maps are OpenGL (+Y),
  imported as normal maps (RGTC) — use `hint_normal`. Albedo maps are sRGB (`source_color`).
- `detail_normal.png`: 1 m tileable micro relief for close-ups (sample at UV0 × metres-per-unit).
- UV2 (glTF TEXCOORD_1): per-module non-overlapping lightmap atlas. Architecture texel ≈ 0.058 m
  (bays, 2048²); small hardware is packed at 0.3–0.45 of that density.

## Baked light (UV2)

`textures/<module>_light.png`, RGBA8, imported BC7 without sRGB:

```
light_rgb = pow(tex.rgb, 2.2) * light_max      // light_max per module in cistern_layout.json
ao        = tex.a                               // ambient occlusion, 1 m
```

`light_rgb` = Cycles diffuse bake (direct + one or more indirect bounces, denoised with OIDN) of
the module's static lights × the module's dirt multiplier. It is "what a white Lambertian
surface would show" in scene-linear units at exposure 0 (the review renders use AgX, exposure 0
and a camera white balance of 5000 K, like the reference photos). Bays were baked as the middle
of three copies of themselves (neighbour floods included); ends with one bay attached. The
hottest 0.2 % of texels (inside the luminaires) clip.

The per-module dirt is multiplied into the light (allowed by the contract): the 1.5 m waterline
(darker, algae-tinted band, wavy tide line, two older tide lines, mineral band above), mud
splash at the foot of walls, runoff streaks (stronger high up), efflorescence crust and runs
under every cold joint, rust runs under the floods / amber lamps / tray brackets, ceiling damp
patches and efflorescence lines, per-pillar tone. Near the module ends (|z| > 6 m) every bay
variant uses the same 15 m-periodic field, so bays join in any order without a seam.

## Godot material recipe (static meshes, render layer 11)

```glsl
// all stage materials
vec3  albedo = texture(albedo_tex, UV).rgb;                  // source_color
vec3  orm    = texture(orm_tex, UV).rgb;
vec4  lm     = texture(light_tex, UV2);                       // no source_color
vec3  light  = pow(lm.rgb, vec3(2.2)) * light_max * row_brightness;
ALBEDO = vec3(0.0);
EMISSION = albedo * (light + ambient * lm.a);                 // + reflections (probe / SSR) * lm.a
ROUGHNESS = orm.g; METALLIC = orm.b;
// CIS_SteelPaint: albedo = mix(tex.rgb, tex.rgb * COLOR.rgb, tex.a)   (A = paint coverage)
// CIS_Grate:      ALPHA = albedo_tex.a, alpha scissor 0.5
// CIS_Floor (COLOR_0: R puddle potential, G damp, B silt; floor_wet: R puddle threshold, G damp, B silt):
vec3 w = texture(floor_wet_tex, UV).rgb;
float puddle = smoothstep(-0.035, 0.035, COLOR.r - w.r);
float damp   = clamp(COLOR.g * (0.55 + 0.6 * w.g), 0.0, 1.0);
float silt   = clamp(COLOR.b * (0.3 + 0.9 * w.b), 0.0, 1.0);
albedo *= (1.0 - 0.45 * damp) * (1.0 - 0.25 * puddle);
albedo  = mix(albedo, albedo * vec3(0.62, 0.55, 0.44), silt);
float r = mix(mix(orm.g, 0.28, damp), 0.6, 0.5 * silt);
ROUGHNESS = mix(r, 0.04, puddle);                             // near-mirror puddles
NORMAL_MAP = mix(normal_tex, vec3(0.5, 0.5, 1.0), puddle);
```

Lens materials: `EMISSION = colour * strength * row_brightness` (floods 5000 K, amber 2000 K).
Light anchors give the positions/directions for the few real lights that light the characters;
`cistern_layout.json` has `color_linear`, `blender_power_w` and suggested `godot_energy`/`range`.

## Rebuild (live Blender only)

Per AGENTS.md everything runs in the user's open Blender through the Higgsfield `bl_execute`
connector (never `blender --background`), then the `.blend` is saved. Long steps run through
`source/jobs.py` (a `bpy.app.timers` queue that writes progress to
`%TEMP%/aiquiz_cistern_jobs/<name>.json`) so the connector never blocks:

```python
S = "C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/"
ns = {"__name__": "x"}; exec(open(S + "jobs.py", encoding="utf-8").read(), ns)
ns["start"]("all", [
  ("bake_textures.py", "bake_set", ("concrete",)), ("bake_textures.py", "pack_set", ("concrete",)),  # + floor, steel, galv, grate, hazard, detail
  ("materials_cistern.py", "setup_materials", ()),
  ("build_cistern.py", "build_module", ("A",)),          # A B C O U D
  ("bake_cistern.py", "unwrap", ("A",)),
  ("bake_cistern.py", "bake", ("A", "GRIME")), ("bake_cistern.py", "bake", ("A", "AO")),
  ("bake_cistern.py", "bake", ("A", "LIGHT")), ("bake_cistern.py", "denoise", ("A",)),
  ("bake_cistern.py", "pack", ("A",)),
  ("export_cistern.py", "export_module", ("A",)), ("export_cistern.py", "write_texture_imports", ()),
])
```

Then `Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`. Scripts:
`cistern_common.py` (dimensions, Godot-space mesh builder), `bake_textures.py` (tiling PBR sets),
`materials_cistern.py` (look-dev materials + grime field), `build_cistern.py` (modules, lights,
anchors), `bake_cistern.py` (UV2, bakes, OIDN, packing), `export_cistern.py` (GLB, layout JSON,
.import presets), `review_cistern.py` (instanced corridor layout, fog, cameras, renders).

## Budgets

| Item | Budget | Now |
| --- | --- | --- |
| triangles per bay | ≤ 60k | bay A 18.6k |
| lightmap per bay / end | ≤ 2048² / ≤ 4096² | 2048² |

## Deviations from the interface

- Concrete and floor UV0 use 3.75 m per UV unit (not 2 m): the form-panel grid
  (0.9375 × 1.875 m ≈ 0.9 × 1.8 m) must tile, and 3.75 divides the 15 m bay so UVs stay seamless
  across modules (2 m would jump by half a tile at every other module boundary).
- Extra materials: `CIS_LampLensAmber`, `CIS_Hazard`, `CIS_WindowGlass`, `CIS_Interior`, `CIS_Void`.
- Dirt (waterline, streaks, efflorescence, rust) lives in the lightmap RGB; puddles/damp/silt
  in the floor vertex colour.

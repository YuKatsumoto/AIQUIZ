# Surge tank (首都圏外郭放水路 調圧水槽) — underground stage art

The pressure-adjusting water tank of the Metropolitan Area Outer Underground Discharge Channel rebuilt from the
MLIT plan and sections for the 2P sudden-death underground stage. Survey, sources and the reasoning behind every
number: `docs/surge_tank_reproduction.md`. All geometry is built by script in the user's live Blender (Higgsfield
`bl_execute`, never a headless Blender) and lit with Cycles bakes; no downloaded, purchased or generated images.
The tiling PBR sets (concrete, floor, steel, galvanised, grating, detail normal) are the self-authored procedural
sets of the earlier `underground_temple` delivery, copied here.

## Files

| File | Content |
| --- | --- |
| `tank_line_00.glb` .. `tank_line_10.glb` | pillar line k (z = 112 - 14 k), z from line - 8 to line + 6: pillars, coffers with the pendant lamps of the line, the transverse beam on the shaft side, trench floor, slopes, shelves, wall fillets, side walls (chamfered in line 10), catwalks, wall floods |
| `tank_end_pump.glb` | pump end (z 118 .. 132.8): gate face, five dividing walls with round tips, four intake channels ("altars": sill, dark slot, curved ramp, ledge, catwalk, lamps), the lamps over the channels, the transverse beam before line 0 |
| `tank_end_shaft.glb` | shaft-side end (z -36 .. -38.6 and the passage): last coffer, end wall with two 10 m openings and the 2 x 8 m pier, passage to shaft No.1 with chamfered jamb feet, fence, concrete blocks, lamps under the lintel |
| `tank_shaft1.glb` | shaft No.1 (centre z = -62.6, inner radius 15.8): wall with the window of the passage, roof with daylight opening, stair tower, pipes, ring catwalk, floods |
| `tank_stairs.glb` | visitor access: door portal in the -x side wall (z ~ -19.5), walkway over the shelf, two-flight steel stair into the trench, green exit light, bollards (z = -3.2) |
| `tank_layout.json` | survey numbers, module triangle counts, light anchors (kind, position, direction, colour, Blender power, suggested Godot light), one instance per module with its light map and `light_max` |
| `textures/<module>_light.png` | one light map per module |
| `textures/<set>_{albedo,normal,orm}.png` | tiling sets (UV0 3.75 m per repeat for concrete and floor; walls, beams, coffers and floor are world-projected in Godot) |
| `source/` | `surge_tank.blend` and the scripts (`.gdignore`d), review renders in `source/previews/` |

## Conventions

- Godot units (m), Y up. x = -v across the tank (side walls at +-35.5), z = 132.8 - u along it, u measured from
  the pump-side gate face (z = 132.8) to the shaft-side end wall (z = -38.6). Trench floor at y = 0 (Godot places
  the modules at y = `SuddenDeathLayout.FLOOR_Y`), shelves at y = 5, slab soffit at 17.7.
- Every module is authored in hall coordinates (plan metres) and placed at the origin. Godot scales the whole stage
  by `SuddenDeathLayout.TANK_SCALE` (1.5) about the landing point (0, FLOOR_Y, 0), so that the game's characters
  (2.1 m tall, 0.44 m heads) stand to the pillars like the visitors in the photos; the shaders do their plan lookups
  in plan coordinates (`tank_scale` uniform).
- Objects per material: `TK_Concrete` (walls, slopes, beams, coffers: world-projected), `TK_Pillar` (pillars, dividing
  walls, the opening pier and the shaft wall: UV0 wrapped round), `TK_Floor` (trench floor, shelves, passage),
  `TK_Steel` (luminaire bodies, brackets), `TK_Paint` (painted catwalk brackets, stairs; vertex colour = paint),
  `TK_Galv` (rails, pipes), `TK_Grate` (decks, treads; alpha cutout), `TK_Lens` (emissive lamp glass), `TK_Sky`
  (daylight disc), `TK_Void` (dark openings).
- Light anchors: empties `TK_Light_<Bay|Wall|Strip|Shaft|Sky|Exit>_<name>`, local -Z = beam direction.
- UV2 (glTF TEXCOORD_1): one non-overlapping atlas per module.

## Baked light (UV2)

```
light_rgb = pow(tex.rgb, 2.2) * light_max      // light_max per module in tank_layout.json
ao        = tex.a
```

`light_rgb` = Cycles diffuse bake (direct + indirect) of every lamp of the tank × the dirt field of
`materials_tank.py`, baked with the whole tank in the scene (each module selected on its own), denoised with OIDN.
The LED high-bays are Lambertian discs (0.45 m, 800 W, 4800 K) hanging in the middle of the coffers; wall floods are
110 deg spots, the intake strips area lights, shaft No.1 has 8 floods and a daylight disc.

## Rebuild (live Blender only)

```python
S = "C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank/source/"
def run(script, fn, *args):
    ns = {"__name__": "x"}; exec(open(S + script, encoding="utf-8").read(), ns); return ns[fn](*args)
units = ["K%02d" % k for k in range(11)] + ["P", "S", "Q", "T"]
for tag in units: run("build_tank.py", "build_module", tag)
run("materials_tank.py", "setup_materials")
for tag in units: run("bake_tank.py", "unwrap", tag)
# bakes through the timer queue (jobs.py), for every unit: bake LIGHT, bake AO, bake GRIME, denoise, pack
for tag in units: run("export_tank.py", "export_module", tag)
run("export_tank.py", "copy_shared_textures"); run("export_tank.py", "write_texture_imports"); run("export_tank.py", "write_layout")
```

Then `Godot_v4.7.2-stable_win64_console.exe --headless --path . --import` and
`Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/sudden_death/build_tank_scenes.gd`.

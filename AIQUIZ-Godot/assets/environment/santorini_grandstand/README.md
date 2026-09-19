# Santorini open spectator terrace

Original self-authored AIQUIZ geometry; no purchased or downloaded mesh, texture,
or generated image is included. Reference photographs informed the white stone,
blue chairs, open pergola, terracotta and bougainvillea palette:

- [Akrotiri Hotel terrace, Santorini](https://www.santorini-view.com/akrotiri-hotels/akrotiri-hotel/)
- [Skaramagas taverna, Kamari](https://skaramagaskamari.gr/en/Restaurant-Taverna-Kamari-Santorini)
- [Ancient Thera terrace, Kamari](https://ancientthera-apartments.com/)

The stand is a 160 m long open waterfront terrace. Four spectator rows replace
the previous ten-row stadium and its large roof. The tallest seated spectator is
about 3.1 m above the stage datum; three small rear pergolas cover 11.5% of the
length. The continuous rear railing is only 2.435 m high. White arcades and piers
reach below the -9.2 m ocean plane.

`source/santorini_open_terrace.blend` contains eight editable terrace sections,
shared materials, a review camera and three renders, and a presentation ocean that is
excluded from the GLB. `source/build_santorini_grandstand.py` rebuilds everything
deterministically in Blender 5.1 without dependencies beyond Blender itself.
The GLB combines the eight sections into one mesh with 13 shared material surfaces
to reduce draw calls. Geometry is original and untextured, and has no collision.

Run the builder in a separate Blender process:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' --background --factory-startup --python assets\environment\santorini_grandstand\source\build_santorini_grandstand.py
```

`asset_report.json` records measured geometry bounds, triangle count and seating
coordinates. `scripts/world/grandstand_crowd.gd` mirrors this seating grid. glTF
maps Blender `(X,Y,Z)` into Godot `(X,Z,-Y)`, so the actual seat-grid Z sign matters.
Keep the stage's opposite-side 180-degree rotation and the crowd's inverse length
compensation when changing stand placement. The deterministic side seeds, crowd
appearance, animation shader, P1/P2 mapping and build density remain unchanged.

The three preview PNGs are Blender asset review evidence only. Main-menu,
gameplay, side mirroring, spectator seating and course-extension acceptance must
be checked in Godot after integration.

`source/previews/santorini_terrace_godot_crowd.png` is an additional isolated
Godot 4.7.2 Forward+ render of the exported GLB with 508 animated spectators.
It confirms actual imported geometry and chair/body alignment using the existing
crowd shader. `source/preview_stand.gd` reproduces it; the lighting belongs only
to this asset review and does not alter the game's environment.
The paired `_after.png` frame is taken one second later with fixed camera and
lighting. `motion_validation.json` confirms active shader motion in Forward+
(170,143 changed image bytes over 1,083 ms in the recorded run).

`source/validate_seating.gd` is an isolated Godot validator for seeded rebuilds,
both mirrored stands, all rows/aisles, pose/color diversity, and body proportions
at stand length scales 0.5, 1.0 and 2.5. It requires a real rendering backend:
Godot's headless dummy backend does not preserve MultiMesh transform/color
readback. The graphical structural run passed all 3,009 scaled placements with
495 left and 508 right spectators. This is not gameplay screenshot evidence.

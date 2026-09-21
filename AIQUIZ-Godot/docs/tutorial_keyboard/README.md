# Tutorial keyboard

Production asset: `assets/ui/tutorial/keyboard/keyboard_hero.png` (1800 x 600 transparent RGBA).
Editable source: `assets/ui/tutorial/keyboard/source/keyboard.blend`.
The source directory is ignored by Godot so only the intended PNG is imported.

The supplied AI image reference was inspected before modeling. Higgsfield Bridge and Blender MCP both reported Blender 5.1.2, PID 34328, `Scene`. Creation occurred through Bridge; Blender MCP independently audited geometry, parenting and preserved objects. No additional paid generation was submitted. After Effects was not connected.

`TutorialKeyboardStudio` is a separate scene. The prior `Scene`, `SawOperator_Workbench`, and `SurfGear_Workbench` remain intact in the live instance. The delivered source includes only the tutorial scene and its dependencies. Neither checkpoint copy saves nor the final asset-only library write changed the original live file path.

The keyboard has 64 independently editable sculpted caps, 64 editable legends, a navy case and recessed deck. WASD and Space are orange; the separate inverted-T arrows and right Ctrl are cyan. Neutral caps are ivory. The simplified reference layout retains the physical stagger and the placement of every gameplay control; it is an explanatory compact keyboard rather than a particular commercial keyboard model.

Animation: 30 fps, frames 1–360 (12 seconds). A, D, W, S, Space, Left, Right, Up, Down and right Ctrl each descend 2.5 mm, hold and settle. A brief rim cue identifies the current key. Frame 1 and frame 360 are matching rest poses. The fixed camera preserves key-location literacy. Each key's legend follows the same press control. `animation_beats.json` gives exact frame ranges.

Validation:

- `structural_motion_audit.json`: all ten controls travel 2.5 mm and return; 64 keys and legends, camera, resolution, fps and original Scene objects checked.
- Blender MCP mesh audit: all 144 closed meshes have zero non-manifold edges. The original Cube, Light and Camera transforms are unchanged.
- Bounds, camera and side-view images were viewed before detailed modeling. Tapered caps, soft edges and homing bars remain editable.
- First lookdev preview was rejected for small labels and washed-out colors; second preview enlarged legends and reduced lighting. Final Cycles render was inspected at delivery size.
- World-only, zero-world, key-only, fill-only and no-fill diagnostic images plus the grayscale final were viewed. Key determines form; fill lifts the right-side controls; no clipped letters, crushed labels or missing textures. No atmosphere or generated environment was used.
- Opening, A press, Space press, right Ctrl press and final-rest renders were viewed; rim accents and physical travel stay attached and in frame.

Recreate in a fresh Blender 5.1 session:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' --background --python 'C:\AIQUIZ\AIQUIZ-Godot\tools\tutorial_keyboard\build_keyboard.py'
```

The script deliberately refuses to rebuild over an existing `TutorialKeyboardStudio`. It preserves unrelated scenes. The editable text uses `C:/Windows/Fonts/segoeuib.ttf`; this Windows font remains an external dependency, and is not redistributed in the asset. The hero PNG is self-contained.

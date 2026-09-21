# Tutorial keyboard production

refs_read: blender-scene, blender-scene-spec, blender-modeling, blender-lookdev, blender-lighting-camera, blender-animation, blender-audit-finalize

SCENE
- intent: immediately recognizable physical keyboard for the renewed all-age tutorial.
- deliverable: editable Blender source, transparent 1800 x 600 hero render, animated key presses.
- units: metres; axes: right-handed Z-up
- render: Cycles, 1800 x 600, 30 fps, frames 1-360
- dynamic: yes; explicit static request: none

HIERARCHY
- collection/object naming: TK_Keyboard, TK_Keycaps, TK_Legends, TK_Lighting; HERO_TK_, RIG_TK_, CAM_TK_, LGT_TK_ prefixes.
- parent/child relationships: each keycap and legend belong to one named press control; all controls belong to keyboard root.
- protected existing objects: Scene, Cube, Camera, Light, their transforms and datablocks; existing active file path.

ASSETS
- A01 HERO_TK_Case | route BLOCK | fidelity detailed | dimensions [0.369,0.110,0.015] m | location [0,0,0] | orientation [0,0,0] rad | center base origin | RIG_TK_Keyboard | navy chassis with inset deck and edge lip.
- A02 HERO_TK_Key_* | route BLOCK | fidelity detailed | standard pitch 0.01905 m, standard cap [0.0175,0.0175,0.007] | staggered QWERTY rows | orientation [0,0,0] | key rest center | RIG_TK_Key_* | readable tapered ivory/orange/cyan caps.
- A03 HERO_TK_Legend_* | route BLOCK | fidelity detailed | 0.005 m typical text height | top of corresponding cap | orientation [0,0,0] | center | RIG_TK_Key_* | accurate physical labels.
- generation estimate/submission state: no paid generation in this build; parent supplied image reference.

SHOT
- active camera: CAM_TK_Hero
- framing/lens/target: locked orthographic near-top view, slight front elevation; complete board, readable legends, equal horizontal margins.
- foreground, subject, background depth: front case edge, sculpted caps, transparent background.

LOOK
- material roles and palette: navy chassis, ivory neutral caps, warm orange WASD/Space, cyan inverted-T arrows/right Ctrl, navy legends.
- material route: NONE (procedural Principled materials).
- texture scale: subtle 0.0003 m molded-plastic grain using Generated coordinates.
- relief polarity: subtle bump only, no displacement.
- dielectric/metallic: caps dielectric roughness 0.32, anodized case roughness 0.30 and metal 0.4.
- world/background: weak neutral studio ambience, film transparent.

LIGHTING
- focal subject: WASD and Space; secondary: arrows and right Ctrl; darkest region: recessed key sockets.
- reference mood/time: soft studio product photography, time-neutral.
- environment route: NONE; true HDR-EXR required: no.
- world-only and zero-world baseline: produce reduced-size diagnostics.
- key: large upper-left rectangular area, same front side as camera, soft cast shadows.
- fill: broad right-side area restores legends while preserving directional chassis shadows.
- motivation: overhead softbox studio.
- reflection strategy: broad source produces calm controlled highlights on chamfered caps.
- gobos/flags/atmosphere: none required; atmosphere A/B not applicable.
- color management: AgX, medium high contrast, exposure 0, fixed across diagnostics.

MOTION
- fps/frame range: 30 / 1-360.
- beats: A, D, W, S, Space, Left, Right, Up, Down, Right Ctrl; each control descends 0.0025 m, holds, and settles; legends follow their caps.
- rest poses: opening frame 1 and final frame 360 identical; no camera motion to preserve key location literacy.

ACCEPTANCE
- structural: preserved original scene; unique named editable key parts; real staggered rows; separate inverted-T arrows; active camera and render output correct.
- motion: evaluated press controls descend exactly 0.0025 m and return, independently; labels remain attached.
- visual: all physical labels readable, clear orange/cyan roles, complete board unclipped, transparent alpha.
- lighting: viewed key-only/world-only/zero-world/fill-only/grayscale evidence; no clipped highlights or crushed legends; no atmosphere.

BUILD GATES
- [x] Module reads and Phase A passport.
- [x] Phase B pre-change screenshot, snapshot and recovery copy.
- [x] Phase C silhouette, proportion, depth, contact and camera-read gates.
- [x] Phase D editable detailed geometry, materials, lights and animation.
- [x] Phase E structural, motion and viewed render audits.

FINALIZATION
- Created: one independent TutorialKeyboardStudio scene, 276 objects (144 meshes, 64 text legends, 65 rig empties, one camera, two lights), procedural materials and ten press actions plus ten synchronized rim cues.
- Modified/deleted existing objects: none. Protected scenes and original empty active filepath preserved.
- All three structural/motion/visual audits: passed. Lighting isolation and grayscale diagnostics: viewed and passed. Mesh manifold audit: passed for all 144 meshes.
- Standalone source reopen: passed, active TutorialKeyboardStudio, expected camera and frame range.
- Rest frame 1 and camera CAM_TK_Hero restored. Hero: Cycles 96 samples, 1800 x 600 RGBA. Saved scene defaults: Cycles 64 samples.
- AE: unavailable (not connected); no AE work claimed. No paid generation submitted by this build.
- Active Blender session remains available for editing. Recovery checkpoints are in the Blender temporary tutorial_keyboard_checkpoints folder.

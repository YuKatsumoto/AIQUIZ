# Godot-kun operator console v3 — Scene Passport

SCENE
- intent: rebuild the operator console from scratch and give the existing Godot plush a new, varied set of state-driven motions.
- deliverable: editable Blender scene (GodotConsole_V3 in saw_operator_v3.blend), runtime GLB godot_console_v3.glb, Godot presentation, preview bake and evidence.
- units: metres; axes: right-handed Z-up; asset front -Y (Godot +Z), operator's left +X.
- render: EEVEE, 1400x1000 inspection (640x480 previews), 30 fps preview bake, frames 1-1770.
- dynamic: yes. Motion is evaluated in Godot and baked into Blender for preview only; the GLB is unanimated.

HIERARCHY
- ConsoleV3 root; every moving part is its own empty pivot (OP_Lever_L/R, OP_Pedal_L/R, OP_Key, OP_Guard, OP_Start, OP_Horn, OP_Dial, OP_Needle_*, OP_Beacon) with named contact empties; lamps (OP_Lamp_*, OP_Bar_*, OP_BeaconDome) keep separate meshes for per-lamp emission.
- REF_OperatorRuntime: the current saw_operator.glb imported as reference (seat, plush rig, chair-launch kit, dock mount; v2 console hidden). Not exported.
- protected: the live Blender file's own scene, the plush mesh/16-bone rig, seat, chair kit, dock mount, carriage, cameras, gameplay/collision/replay authority.

ASSETS
- A01 plush + seat + kit + mount | [EXISTING] | detailed | from saw_operator.glb | unchanged.
- A02 deck | [BLOCK] | detailed | 1.64 x 1.74 x 0.14 m at z .90 | same footprint as v2 (blade clearance 130 mm) | tread, pedal floor, hazard edge, bumpers.
- A03 control pods L/R | [BLOCK] | detailed | 0.34 x 0.94 m, top 1.46 m, centred x +-0.575, y -0.29 | ends at y .18 to clear the chair nozzles.
- A04 instrument dash | [BLOCK] | detailed | 0.81 x 0.24 m between the pods, face tilted 28 deg toward the eyes.
- A05 controls | [BLOCK] | detailed | all palm contacts within 0.2 m of the shoulder reach centre (limit 0.237 m).
- generation: none (no credits spent).

SHOT
- inspection cameras CAM_V3_Front/Operator/Side/Menu/Dash/Shoulder; CAM_V3_Preview is parented to ConsoleV3 so it follows the deck slide.
- Godot production cameras unchanged; the left end stays off-screen during the chase (earlier user decision).

LOOK
- graphite shell (metal .35 / rough .40), Godot-blue panels, safety-yellow trim and hazard stripes, machined steel, rubber, brass key, amber guard, dark gauge faces with white ticks and red zones.
- lamps: dark lenses with emission driven by Godot; beacon lens alpha .62.
- procedural node materials are not used; flat PBR constants export to glTF.

LIGHTING
- inspection only: warm area key front-right, cool fill left, rim behind; AgX. Game lighting remains authoritative.

MOTION
- transport sway, six waiting vignettes, start (key, guard, wind-up, START slam, fist pump), running routine per 7.2 s cycle, catch celebration with two horn presses, shutdown; pause/result hold; replay re-evaluates.

ACCEPTANCE
- structural: 140-node GLB, pivots and contacts named, no collision objects, deck/lift footprint and blade clearance unchanged.
- motion: every hand/foot target < 1 cm, 30/60/120 fps identical, head < .06 rad and hands < .075 m per 30 fps frame, seek-order independent.
- visual: real-camera menu and game captures, close-ups, Blender preview renders viewed.

refs_read: blender-scene, blender-scene-spec, blender-modeling, blender-lookdev, blender-lighting-camera, blender-animation, blender-audit-finalize.

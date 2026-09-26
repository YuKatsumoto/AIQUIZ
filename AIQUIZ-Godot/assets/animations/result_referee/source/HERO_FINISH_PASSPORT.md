# Winner foreground / loser background finish

SCENE
- intent: Low camera looking up at the winning player, with the losing player launched and bursting behind them. Continuous, motivated entrance, bat retrieval, grip, load, swing and reactions.
- deliverable: Editable live Blender choreography, exported referee GLB and evaluated player/camera tracks, integrated Godot sequence and rendered runtime evidence.
- units: metres; axes: right-handed Z-up
- render: Existing EEVEE, 1280x720, 60 fps. New action range 0-600; motion holds at frame 546 (9.1 seconds).
- dynamic: yes; explicit static request: none
- refs_read: blender-scene, blender-scene-spec, blender-animation, blender-lighting-camera, blender-volatile, blender-audit-finalize; imagegen

HIERARCHY
- collection/object naming: Retain AIQUIZ_RefereeFinish_v2 scene and RIG_Referee, WIN_*, LOSE_*, PRP_*, CTRL_*, CAM_Result names. Additional controls use CTRL_Foot_L/R.
- parent/child relationships: Original plush skeleton and player joint hierarchies retained. Bat is parented to RIG_Referee; grip target remains its child. Foot IK targets are independent world anchors.
- protected existing objects: All other scenes, mesh topology, character materials, hats, existing light rig, world/exposure. Original actions retained as datablocks and full live recovery copy before editing.

ASSETS
- A01 RIG_Referee/HERO_GodotPlush | route EXISTING | fidelity stylized | dimensions approx 1.95x1.04x1.64 m | location [0,0,0] at settle | orientation [0,0,0] | ground origin | no parent | referee
- A02 WIN_Actor | route EXISTING | fidelity stylized | jointed block character approx 1.3x0.6x2.6 m | location [-2.2,0,1.34] at entry | orientation [0,0,0] | pelvis root | no parent | foreground winner
- A03 LOSE_Actor | route EXISTING | fidelity stylized | same character proportions | location [2.2,0,1.34] at entry | orientation [0,0,0] | pelvis root | no parent | background launched loser
- A04 PRP_Bat | route EXISTING | fidelity stylized | length 1.60 m, barrel diameter 0.184 m | held behind shoulder then retrieved | orientation keyed | grip root | parent RIG_Referee | visible causal striking prop
- A05 CAM_Result | route EXISTING | fidelity detailed | perspective camera | low foreground winner shot | keys defined by lens and look target | no parent | final reference composition
- generation estimate/submission state: No generated 3D assets. Built-in imagegen made one composition reference, hero_low_angle_reference_20260924.png.

SHOT
- active camera: CAM_Result; change previous orthographic delivery to perspective for this requested low angle.
- framing/lens/target: Opening readable three-shot. After impact, descend and advance to the winner's lane, settle 0.16 m above the floor, looking upward by 28.2 degrees on the X axis. Final composition tested in actual Godot viewport, including UI.
- foreground, subject, background depth: Winner foreground; referee middle ground; loser moves upward and several metres behind the winner, separated laterally from winner head and raised fist. Mirror the whole shot for P2.

LOOK
- material roles and palette: Existing orange P1, cyan-blue P2, original Godot plush and wooden bat.
- material route EXISTING / all existing meshes.
- texture scale / relief / roughness: Unchanged.
- world/background: Real Godot conveyor, stadium and weather retained. Blender stage remains a preview surface only.

LIGHTING
- focal subject / secondary / darkest region: Winner / airborne loser and referee / background shadow planes.
- reference mood and time: Current bright outdoor stadium.
- environment route EXISTING; true HDR-EXR required: no.
- world-only and zero-world baseline: Existing light sources retained; isolate for diagnostic preview at final camera without changing delivered setup.
- key direction / softness: Retain existing LGT_Key; inspect its relationship from new low angle.
- fill / motivation / reflections: Existing arena key-fill-rim setup; no new lighting objects.
- atmosphere: Existing Godot hit/explosion/smoke, bounded behind winner.
- color management: AgX, exposure 0 preserved in Blender; actual game lighting authoritative.

MOTION
- fps/frame range: 60fps, 0-600, hold at 546. Real-time duration 10 seconds, replacing previous 12.67 seconds by removing 0.75x playback.
- beats: .4-1.8 referee foot-planted entry; 2.0-3.2 reveal the already gripped stowed bat; 3.2-6 score/reaction holds; 5.86-6.23 step and face the loser; 6.23-6.68 coil, plant and full swing; 6.68 contact; 6.76 release; 7.58 background burst; 9.1 background rest with continuing winner dance; 10 controls.
- winner: Recognize win, start the equipped first-slot FBX emote, advance 1.65 m to the foreground, orient the face toward the camera and continue dancing. Blender provides the carrier; Godot samples the actual selected emote, including all 16 choices and the four-part Thriller.
- loser: Wait, recognize loss, turn/react toward referee, recoil only on contact, then launch backward and upward; toy parts separate at burst.
- constraints: Plush arms are short: use one firm non-stretch grip and counterbalancing free arm. Do not stretch limbs to force two-handed reach. Foot support targets for entry and swing, bat is held continuously from entrance through retrieval and swing; short arms remain unstretched.
- rest poses and loops: Referee, loser and VFX have a deterministic final hold; the winning emote keeps playing while results are interactive. Draw retains both players grounded and no strike/flight/explosion.

ACCEPTANCE
- structural: Original geometry/materials/hats/identities and unrelated scenes retained; animation/camera tracks exported from Blender; no game HP or scoring changes.
- motion: Bat visible in a stowed position, already gripped and attached through reveal/swing; measurable hand contact, foot contact, impact/release/burst ordering and backward launch depth. No transform discontinuities or camera cuts through geometry.
- visual: Low angle clearly reads as looking up at winner; winner larger than loser; visible airborne loser and burst behind winner without head overlap; same success for both winners; score/UI readable.
- lighting: View final render, key-only and grayscale at locked exposure; game rendering validated across requested camera motion.

GATES / TODO
- [x] Read required modules; confirm both connections target PID 31368 and this scene.
- [x] Phase A: inspect, view existing scene, generate and inspect composition reference, specify scope.
- [x] Phase B: checkpoint live dirty Blender scene and preserve existing repository edits.
- [x] Phase C: camera/major pose blockout reviewed before motion detail.
- [x] Phase D: editable choreography, contact solve, export and integration.
- [x] Phase E: structural, motion and viewed render/runtime audits; recovery checkpoint of completed live edit.

FINAL EVIDENCE
- Motion contact audit: all 601 frames; hand gap <= 0.000092 m and ankle gap <= 0.000032 m. Referee faces the loser before loading; swing contact moves backward in the same direction as the launch.
- Viewed Blender retrieval, facing, load, contact, follow-through, final carrier, key-only and grayscale images. Actual selected winner emotes are validated in Godot, not represented as Blender-authored dance clips.
- Viewed native game renders: P1/P2, draw, strong X-axis angle, camera-facing dance, behind-winner burst, all 16 emotes and 17 hats. Tested 30/60/120 fps, score/HP and retry/history/menu paths.
- Recovery copy: source/checkpoints/hero_finish_verified_20260924.blend. Original active Blender path unchanged.
- Evidence and known pre-existing environment warnings: artifacts/result_ceremony/hero_low_angle_20260924/ACCEPTANCE.md.

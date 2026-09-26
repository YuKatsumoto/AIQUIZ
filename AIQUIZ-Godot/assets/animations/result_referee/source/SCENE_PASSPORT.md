# AIQUIZ Referee Finish v2

SCENE
- intent: comic result ceremony; the Godot plush referee declares the winner, swings a wooden bat into the loser's clothed rear, and the loser flies into a toy-block burst. All three remain legible during a gradual slowdown to a held tableau.
- deliverable: editable Blender animation, exported referee GLB and sampled player/camera animation; editable AE v2 and preview; integrated Godot ceremony.
- units: metres; axes: right-handed Z-up. Engine export: Godot Y-up.
- render: EEVEE, 1280x720, 60 fps, frames 0-760 (12.667 seconds).
- dynamic: yes; no loop. Rest until verdict, anticipation, contact, flight, burst, decelerating hold.

HIERARCHY
- collection/object naming: REF_Studio, RIG_Referee, PRP_Bat, WIN_*, LOSE_*, CAM_Result.
- parent/child relationships: existing plush skin/armature, bat grip controls and arm IK; existing block-player articulated nodes remain independent and editable.
- protected existing objects: every object in TutorialKeyboardStudio and all existing source assets. Work in a new scene; recovery copy before changes.

ASSETS
- A01 GodotPlush | [EXISTING] | detailed | approximately 1.65 m tall, centered, original skin retained | feet on floor | RIG_Referee | referee.
- A02 Winner/Loser | [EXISTING] | stylized | existing block-player geometry and proportions | foot origin | WIN_/LOSE_ | game player copies, runtime colors/hats.
- A03 Wooden bat | [BLOCK] | detailed | length 1.5 m, barrel diameter .18 m, grip .055 m | grip origin | PRP_Bat | readable rounded profile with grip and endcap.
- A04 Floor/backdrop | [BLOCK] | background | 18x12 m | world origin | ENV_* | dark navy, UltimateToon hatching in engine.
- No paid generation or purchases. Built-in concept image is a composition reference only.

SHOT
- active camera: CAM_Result.
- framing/lens/target: low three-quarter group framing; keep winner left, referee middle, airborne loser right, all visible above score cards. Preserve ample room for hats and debris.
- foreground/subject/background: scores in UI; actors at floor/front; burst behind loser; panels behind actors.

LOOK
- material roles/palette: P1 orange, P2 blue, original plush albedo, warm wood, navy surroundings; yellow/orange blast, gray smoke.
- material route: existing textures and result-only duplicated UltimateToon dot/hatching.
- texture scale: coarse screen-space dots/hatching in Godot, plain readable materials in Blender source.
- relief: none; original mesh unchanged except new bat prop.
- dielectric, roughness .5-.8; bat .4. No reflective floor.
- world: low neutral ambience, dark navy background.

LIGHTING
- focal subject: referee contact then airborne loser; secondary: winner reaction. Background darkest.
- mood: graphic game arena; fixed exposure and AgX in source preview.
- environment route: NONE, no HDRI.
- key: broad warm area above camera-left, defines plush and wooden bat.
- fill: weak cool frontal fill, preserves eyes and shaded faces.
- rim: warm rear edge separates all silhouettes.
- motivation: arena lighting; no moving lights, fog, or reflective cards.
- audits: key-only and complete render, grayscale separation, no blown face or hidden hand contact.

MOTION
- 0-2 s: three actors establish, referee holding bat ready; existing goal-state clock retained.
- 2-7.33: correct answers, HP, total; actors hold for reading.
- 7.33-8.45: verdict, referee turns and winds up, loser presents rear.
- 8.45: barrel contact at rear, short hit stop, winner recoils/cheers.
- 8.55-9.55: loser launches diagonally into open right space.
- 9.55-11.47: toy-block explosion develops as all motion smoothly slows to zero; camera settles into inclusive group framing.
- 11.47-12.67: hold tableau; 12.67 onward controls animate separately.
- draw: no hit or burst; referee holds bat down and both players acknowledge the result.
- rig controls/actions: sparse authored Blender keys; baking is only for game transfer and glTF bone constraints.

ACCEPTANCE
- structural: saved source + imports resolve; isolated result actors/materials; original player shapes/hats and HP unaffected.
- motion: anticipation, barrel/rear contact, hand/grip contact, flight, progressive slowdown, stable hold; no teleports or angle flips.
- visual: all three silhouettes, bat, hats and burst inside action safe area; UI avoids faces; P1/P2/draw at 16:9 and 4:3.
- lighting: viewed keyed poses, key-only/full and grayscale evidence.
- runtime: 30/60/120 FPS and large frame delays, low/high quality, history, repeat retry, covered menu return, cleanup.

refs_read: blender-scene; blender-scene-spec; blender-modeling; blender-lookdev; blender-lighting-camera; blender-animation; blender-audit-finalize; blender-volatile. AE: ae-clean-rig, reference-motion, editable-rigs, validation-delivery, scripting.

Production gates: A inspected/spec complete; B recovery copy; C silhouette/proportion/depth/contact/camera read; D editable asset, animation and export; E structural, motion, rendered and engine audits.

Final gates: A specification/reference reviewed; B protected-scene recovery saved; C blockout/contact/framing inspected; D sparse actions and glTF/sample exports saved; E key-only/full/grayscale, native AE motion/content-edit, and real Godot validation passed. Blender and engine hand/grip alignment checked separately. See artifacts/result_ceremony/referee/VERIFICATION.md for evidence and remaining unrelated logs.

# Saw operator scene passport

SCENE
- intent: precise heavy-machine controls operated by the existing Godot plush.
- deliverable: editable Blender source, separate animated GLB, Godot presentation and evidence.
- units: metres; right-handed Z-up; station faces -Y in asset space, Godot +Z.
- render: EEVEE, 1400x1000, 60 fps, frames 1-721; dynamic: yes.

HIERARCHY
- OperatorStation root; independently named controls and contact targets; Rig and existing plush mesh.
- Existing carriage GLB is inspection context only. Default Scene objects are protected.
- Existing gameplay/collision/replay authority and cameras are protected.

ASSETS
- A01 carriage [EXISTING] detailed | 24.42x3.36m footprint | unchanged.
- A02 plush [EXISTING] detailed | scale 0.80 | seated, animated original 16-bone rig.
- A03 station [BUILT] detailed final | 1.64x1.74m | Godot stowed (+10.70,0,0), deployed (+12.95,-0.628274,0), 2.25m lateral telescopic extension; yaw -90 degrees, facing right along the blade row.
- A04 reference images [GEN] completed with built-in imagegen after explicit user fallback choice.
- Higgsfield gpt_image_2 high/2k estimate: 6.5 credits per image, 19.5 for three. Submission rejected (Basic plan required); no jobs created. Built-in generation does not report model/cost; do not infer them.

SHOT
- Blender inspection camera: front three-quarter and side, 55mm. Godot production cameras unchanged.
- Station is attached to the left end outboard spine, with pale blue face separated from charcoal consoles; perimeter rails and feet removed at user request. Latest user direction supersedes the generated reference orientation.

LOOK
- Silver machined steel (metallic .85/roughness .28), charcoal painted shell (.25/.36), yellow safety trim (.15/.38), rubber (.0/.7), seat (.0/.65).
- Existing plush albedo; native geometry and exportable PBR constants. No generated textures needed.
- Neutral studio world, no atmospheric effects; actual game lighting remains authoritative.

LIGHTING
- Focal subject: plush and hand controls; secondary: seat and braces; darkest: under-platform mechanisms.
- Broad front-side key motivated by daylight; weaker opposite fill for shadow detail. Reflection bands expose silver pivots.
- AgX/exposure 0; inspect key-only/world-only/black-world and grayscale without changing final geometry.

MOTION
- State-evaluated control poses; fixed mounts and telescopic seat rails. Controls share the hand/foot contact solution.
- Shipping: rest -> drive input -> rest. Start: press -> covered toggle -> dial -> grips. Chase: measured drive and blade-lift input.
- Paused/result pose holds; skip/retry reset; replay seeks evaluate recorded time.

ACCEPTANCE
- structural: independent pivots/anchors, <= lift footprint, no gameplay colliders, supported editable source.
- motion: contact error below 1cm at controls; no instantaneous pose jumps in uninterrupted playback.
- visual: normal game camera readable, no body/console intersections, correct left side, original mascot appearance.
- lighting: material distinction, retained highlight/shadow detail; no added camera effects or fog.

refs_read: blender-scene, blender-scene-spec, blender-modeling, blender-lookdev, blender-lighting-camera, blender-animation, blender-generation, blender-audit-finalize, blender-volatile, imagegen.

Gates: inspection/connection PASS (Bridge recovered, both same scene); references PASS (authorized imagegen fallback); blockout PASS; detail PASS; contact/motion PASS; Blender geometry audit PASS at sampled transport poses; Godot runtime PASS.

Evidence: artifacts/saw_operator/v2_report.md contains structural and mesh-clearance audits, runtime contacts, lifecycle checks, normal-camera video and close-up video. Contact target error <=5.02mm in tested startup/drive/lift ranges. Actual sole-to-pedal surface clearance at 12 Blender poses: 2.46–2.80mm. Deployed static geometry to full left-blade vertical sweep: >=130.4mm. The console follows references/v2 with editable gates, bellows, bearings, labels and gauges. Source preview: 961 frames / 60fps, including signed travel and lift reversal.

Camera acceptance: user explicitly chose to retain the existing camera and prioritize transport/pre-start visibility after seeing that chase framing excludes the carriage ends. Do not widen the gameplay camera.

Limits: transport surface-intersection audit covers seven actual dock poses, not a continuous collision proof. Godot AI session aiquiz-godot@4659ba5bd9a96fd6 was verified against C:/AIQUIZ/AIQUIZ-Godot. Bridge and Blender MCP both inspected PID 33552 / SawOperator_Workbench. Validation used independent real Godot processes to preserve the user's running session. Existing unrelated editor/headless warnings are documented in the evidence report.

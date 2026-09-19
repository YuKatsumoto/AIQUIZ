# Shark locomotion — 2026-09-15

## Reference review

The following videos were inspected as time-ordered frames. They are observation
references, not motion capture or game assets. Angles below are animation tuning
for the existing low-poly rig, not measurements claimed for a live shark.

1. **Gremly Media, Playing with a great white shark (2015)**:
   https://commons.wikimedia.org/wiki/File:Playing_with_a_great_white_shark.webm
   (original: https://vimeo.com/142742333, CC BY 3.0).
   Inspected 4–15 s and 45–56 s: approach, circling, faster approach and turn away.
   The forebody is relatively stable while the rear body and tail supply the
   lateral stroke. A direction change has a curved body, not just a rigid yaw.
   This is bait-influenced footage, so it is not used as a resting cadence sample.
2. **Hoffmann et al., Biology Open (2019), Movie 1**:
   https://movie.biologists.com/video/10.1242/bio.037291/video-1
   Full 2.93 s sequence sampled at 0.25 s intervals. A Pacific spiny dogfish
   turns with asymmetric pectoral fin use. The inside fin changes orientation
   while the trunk follows the turn. The accompanying paper describes inside
   fin protraction, supination and depression:
   https://pmc.ncbi.nlm.nih.gov/articles/PMC6361209/
   This is another species; it supports the steering principle, not exact
   white-shark joint-angle values. The game approximates depression/protraction.
3. **Watanabe et al., Journal of Experimental Biology (2019), Movie 1**:
   https://movie.biologists.com/video/10.1242/jeb.185603/video-1
   Inspected ascent at 6–11 s and descent at 17–25 s. Shark-borne footage shows
   active swimming on ascent and more stable passive gliding on descent. This
   camera cannot directly establish tail-tip excursion.
4. **Colefax et al. (2020), coastal white shark tracking**:
   https://www.frontiersin.org/journals/marine-science/articles/10.3389/fmars.2020.00268/full
   Text consulted for steady, energy-conserving coastal movement and changes
   near fish schools. Supplementary video descriptions were accessible, but
   the actual two supplementary videos did not resolve from the current site;
   they are not counted as watched footage.

## Implementation

- `SharkSwim` remains a 1.6 s continuous source cycle. Relative lateral joint
  amplitudes, shoulder to caudal fin, are now 0.65 / 1.8 / 3.6 / 5.5 / 8 degrees
  (previously 1.8 / 4.5 / 8 / 12 / 18). Phase delays remain progressive.
- Head counter-motion is 0.55 degrees; pectoral cyclic motion is 0.35 degrees.
- The GLB and editable Blender source contain the same revised swim action.
  Geometry, weights, textures, saddle and socket were not rebuilt.
- `shark_locomotion_modifier.gd` adds steering after AnimationPlayer evaluation.
  SkeletonModifier3D restores the input pose after evaluation, avoiding drift.
  Bone axes come from imported rest transforms. Stroke scaling interpolates
  from each bone's **rest rotation**, not identity.
- Actual heading angular velocity and body-length/speed determine curvature.
  Head turns inward; successive rear joints trail outward along the arc.
  The inside pectoral fin depresses/protracts; left/right are mirrored.
- Cadence responds smoothly to speed. Gentle descending travel reduces stroke
  amplitude. The phase keeps running across transitions.
- Normal swimming rolls mildly about the travel axis. The old imported-model
  axis could pitch the nose when banking. Heading smoothing is exponential.
- The steering layer applies to `SharkSwim` only. `SharkBite` (0.4 s), authored
  ghost mount/arrival/departure clips and gameplay hit/event timings are retained.
  This does not replace the game's intentionally fantastical ghost sequences
  with a biological simulation.

## Validation

- Blender, 49 evaluated frames: tail-region lateral envelope/body length
  **0.3835 → 0.1732** (about 55% reduction). This measures mesh vertices with
  source X < -3.8, not just an individual joint angle. Source body length 9.1368.
- First/last loop evaluated mesh positions: maximum difference **0.0**.
- Actual Forward+ runtime, 18 s: cruise, left turn, right turn, descending glide,
  acceleration. Maximum steering change per 60 Hz frame: **0.01293**.
- At a frozen clip phase, each inside fin tip lowers ~0.143 source units;
  repeated modifier evaluation for 60 frames accumulates **0.0** displacement.
- Real main-menu scene: ten sequential samples, revised modifier active.
- Real game-world P1/P2 ocean falls and P1 portal rescue: one contact event each,
  player explosion confirmed, closed jaw maintained. All five imported clips
  parse/render; 10 bones, 12 meshes and the mount socket remain present.

Artifacts: `artifacts/shark_locomotion/shark_locomotion.mp4`,
`runtime_motion.json`, `asset_motion.json`, `menu.json`, `blender_sheet.png`.
Contact reports remain in `artifacts/shark_rig_rebuild/locomotion_*.json`.

Run the rendered probe with:

```powershell
./Godot_v4.7.2-stable_win64_console.exe --path . --script tests/shark_locomotion_bootstrap.gd --fixed-fps 60
./Godot_v4.7.2-stable_win64_console.exe --path . --script tests/shark_locomotion_bootstrap.gd --fixed-fps 60 -- menu
```

Use the existing `shark_contact_bootstrap.gd` with `-- asset`,
`-- tag=check player=1`, `player=2`, or `case=portal` for integration checks.

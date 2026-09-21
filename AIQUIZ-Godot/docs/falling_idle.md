# Helicopter airborne animation

The gameplay helicopter release uses the supplied `assets/animations/Falling Idle.fbx`
on both players until the existing physical floor-contact detection fires.

- Original input: `C:/Users/kykat/OneDrive/Downloads/Falling Idle.fbx`.
- SHA-256: `04D870E00A853957FAF5FCD9FA58B8E68D5A7BBC32384B2DEB7CBE336B174730` (copied unchanged).
- Godot import: `mixamo_com`, 0.683333 seconds, 43 animation tracks, 65 bones;
  all 46 avatar mapping entries resolve.
- Dedicated animation slot 26; existing emote and UAL slot numbers are unchanged.
- Each player's flight elapsed time independently samples the loop.
- Blend from the release pose over 0.15 seconds and into the existing `Jump_Land`
  over 0.12 seconds. The original `Idle_Loop` follows landing.
- The existing ragdoll still owns flight position, gravity, CCD and floor contacts.
  Its mesh is hidden during the animated flight; the regular avatar follows its
  torso. Hats follow the regular head. No helicopter trajectory or physics tuning
  was changed. Missing animation retains the previous physical visual fallback.
- Ordinary gameplay jumps, menu boarding, deaths and retry skip routing are unchanged.

## Verification (2026-09-21)

Real rendered menu Start -> gameplay helicopter -> touchdown -> idle -> retry:

| Run | Result |
| --- | --- |
| 1 player, 60 FPS cap | 15 checks passed |
| 2 players, 60 FPS cap | 26 checks passed |
| 2 players, 30 FPS cap | 30 checks passed, including three-cycle repeat and midair cancellation |
| 2 players, 30 FPS cap, animation disabled | 9 fallback checks passed |

Reports and screenshots are in `artifacts/falling_idle/`. Close-up screenshots use
additional test-only cameras sharing the actual world's geometry; the gameplay
camera is not changed. Both players retain visible hands/head, land at their own
starting marks within 2 cm horizontally, and release the start lock.

The separate real-time baseline and animated runs had final airborne samples
within 0.03 seconds of one another. These are not deterministic, identical-step
trajectory comparisons. The invariants checked directly are active physical
gravity/CCD and an animated root within 1 mm of the physical torso.

The tests instantiate all affected scripts and the imported FBX in Godot 4.7.2
Forward+ on the actual Start route. The editor's in-place hot reload returned code
43, so it is not counted as successful validation. Standalone runtime checks pass.
Pre-existing missing Fennara autoload, remote-config fetch and shutdown resource
warnings remain separate from the feature's passing acceptance checks.

Run with the project's Godot executable:

```text
--path C:/AIQUIZ/AIQUIZ-Godot --script res://tests/falling_idle_bootstrap.gd -- --players=2 --fps=30
```

Add `--baseline` to disable only the new animation slot for the physical fallback.

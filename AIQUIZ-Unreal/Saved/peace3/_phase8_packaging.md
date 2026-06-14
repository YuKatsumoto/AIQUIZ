# Phase 10 packaging

## summary
Phase 10 packaging script authored; full script on disk at script_path, parse-validated. GameMode loads the quiz bank by string path so the script force-cooks the content tree and passes the map switch.

## recipe
Constants Godot equals UE: gravity 18, jump 7, speed 7.6, X 6.5 per side hint, doors 2ch 3.5 hw1.8 and 4ch -5.8 -1.95 1.95 5.8 hw1.45 and coop 4.1 8.1 -8.1 -4.1 hw1.15, wall_start_z 22, spacing 30, hit offset plus0.4 applied wall_z minus 0.4, back cull -12.5, magma death y below -8, floor top -1.2 width 24, VISIBLE 28, MOVE_BUFFER 3.5, clamp 1 to 8, stage_factor 1.0 to 1.15 via index over 9. A B vs Godot: bank non-empty, Japanese no tofu, jump apex 1.30m, side run-off magma death, wall ramp 1.0 to 1.15, backcull -12.5, wrong answer bump stop at wall minus 0.4, deterministic score.

## risks
RunUAT flags unverified, drop any 5.7 rejects; load-bearing build cook stage pak archive archivedirectory map cookdir clientconfig Development platform Win64. Data-table cook-in is top risk; fallback add DirectoriesToAlwaysCook for the Data folder and the AiQuiz folder in DefaultGame ini; confirm bank non-empty in the exe. No default map in ini so script passes the map switch. Japanese and PIE and Standalone need visual checks; the font must be under the AiQuiz tree. door4 and coop halfwidths in C++ Centers arrays marked verify. Development is larger and slower than Shipping.

## hlsl
```hlsl

```

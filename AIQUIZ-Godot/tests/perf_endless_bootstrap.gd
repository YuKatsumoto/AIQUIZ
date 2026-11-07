extends "res://tests/perf_bootstrap_base.gd"

## Measure A: one long ENDLESS run (1P, OFFLINE, autoplay through the correct door).
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/perf_endless_bootstrap.gd -- --label=baseline
## Output: artifacts/perf/endless_<label>.json (+ endless_<label>_frames.json).


func _measure() -> String:
	return "endless"

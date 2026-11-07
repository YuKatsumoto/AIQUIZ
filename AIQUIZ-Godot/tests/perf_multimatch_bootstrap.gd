extends "res://tests/perf_bootstrap_base.gd"

## Measure B: several ENDLESS matches in a row through the real menu path
## (main menu -> game world -> pause "タイトルに戻る" -> main menu -> ...).
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/perf_multimatch_bootstrap.gd -- --label=baseline
## Output: artifacts/perf/multimatch_<label>.json (+ multimatch_<label>_frames.json).


func _measure() -> String:
	return "multimatch"

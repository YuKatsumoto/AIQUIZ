extends MainLoop

## Compares two outputs of the runtime performance harness (same measure).
## A bare MainLoop: no autoloads, no scene tree, no window needed.
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/perf_compare.gd -- \
##       --baseline=res://artifacts/perf/endless_baseline.json --current=res://artifacts/perf/endless_after.json
## Prints a table and writes artifacts/perf/compare_<measure>_<baseline>_vs_<current>.json.

const Util := preload("res://tests/perf_util.gd")

## Subtrees whose numeric leaves are compared (dotted paths).
const ENDLESS_KEYS: Array[String] = [
	"endless.walls_passed",
	"endless.play_seconds",
	"endless.frames_playing.avg_fps",
	"endless.frames_playing.dt_ms",
	"endless.frames_playing.over_25ms",
	"endless.frames_playing.over_33ms",
	"endless.frames_playing.over_50ms",
	"endless.frames_playing.over_100ms",
	"endless.frames_playing.process_ms",
	"endless.frames_playing.post_ms",
	"endless.frames_playing.draw_ms",
	"endless.hitches_total",
	"endless.hitches_per_wall",
	"endless.hitch_attribution.by_largest_segment",
	"endless.event_costs.current_wall_index_changed",
	"endless.event_costs.provider_refill_ran",
	"endless.event_costs.pipeline_compilation",
	"endless.trend_first10_vs_last10.first",
	"endless.trend_first10_vs_last10.last",
	"endless.growth_waiting_start_to_end.perf",
	"endless.growth_waiting_start_to_end.signal_totals",
]
const MULTIMATCH_KEYS: Array[String] = [
	"multimatch.matches_completed",
	"multimatch.trend_per_match.window_dt_mean_ms",
	"multimatch.trend_per_match.window_dt_p95_ms",
	"multimatch.trend_per_match.window_dt_p99_ms",
	"multimatch.trend_per_match.window_proc_mean_ms",
	"multimatch.trend_per_match.window_frames_over_33ms",
	"multimatch.trend_per_match.window_dt_mean_slope_ms_per_match",
	"multimatch.trend_per_match.window_dt_p95_slope_ms_per_match",
	"multimatch.trend_per_match.window_proc_mean_slope_ms_per_match",
	"multimatch.trend_per_match.menu_slopes",
	"multimatch.trend_per_match.menu_signal_total_slopes",
	"multimatch.trend_per_match.menu_series",
	"multimatch.menu_growth_total_first_to_last.perf",
	"multimatch.menu_growth_total_first_to_last.signal_totals",
	"multimatch.menu_growth_total_first_to_last.root_child_count",
	"multimatch.menu_growth_total_first_to_last.audio_manager_child_count",
	"multimatch.orphans_final.total_roots_and_children",
]

var _done := false


func _initialize() -> void:
	var args := Util.parse_args()
	var base_path := String(args.get("baseline", ""))
	var cur_path := String(args.get("current", ""))
	if base_path.is_empty() or cur_path.is_empty():
		printerr("usage: -- --baseline=<json> --current=<json>")
		_done = true
		return
	var base := _load(base_path)
	var cur := _load(cur_path)
	if base.is_empty() or cur.is_empty():
		printerr("could not read both files")
		_done = true
		return
	var measure := String(base.get("measure", ""))
	if measure != String(cur.get("measure", "")):
		printerr("different measures: %s vs %s" % [measure, cur.get("measure", "")])
	var keys: Array[String] = ENDLESS_KEYS if measure == "endless" else MULTIMATCH_KEYS
	var rows: Array = []
	for key: String in keys:
		var a: Dictionary = {}
		var b: Dictionary = {}
		_flatten(_dig(base, key), key, a)
		_flatten(_dig(cur, key), key, b)
		var names := {}
		for k: String in a.keys():
			names[k] = true
		for k: String in b.keys():
			names[k] = true
		var sorted_names := names.keys()
		sorted_names.sort()
		for k: String in sorted_names:
			var va: Variant = a.get(k)
			var vb: Variant = b.get(k)
			var row := {"metric": k, "baseline": va, "current": vb}
			if (va is float or va is int) and (vb is float or vb is int):
				row["delta"] = snappedf(float(vb) - float(va), 0.001)
				if absf(float(va)) > 0.000001:
					row["delta_pct"] = snappedf((float(vb) - float(va)) / absf(float(va)) * 100.0, 0.1)
			rows.append(row)
	print("perf compare  measure=%s  baseline=%s (%s)  current=%s (%s)" % [
		measure, base.get("label", "?"), base_path, cur.get("label", "?"), cur_path])
	for row: Dictionary in rows:
		print("%-78s %14s %14s %12s %9s" % [
			row["metric"], _fmt(row["baseline"]), _fmt(row["current"]),
			_fmt(row.get("delta", "")), ("%s%%" % row["delta_pct"]) if row.has("delta_pct") else ""])
	var out := Util.OUT_DIR + "compare_%s_%s_vs_%s.json" % [measure, base.get("label", "a"), cur.get("label", "b")]
	Util.write_json(out, {"measure": measure, "baseline": base_path, "current": cur_path, "rows": rows}, " ")
	print("wrote ", out)
	_done = true


func _process(_delta: float) -> bool:
	return _done


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _dig(root: Dictionary, dotted: String) -> Variant:
	var cur: Variant = root
	for part: String in dotted.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = (cur as Dictionary)[part]
		else:
			return null
	return cur


func _flatten(value: Variant, prefix: String, out: Dictionary) -> void:
	if value is Dictionary:
		for k: Variant in (value as Dictionary).keys():
			_flatten((value as Dictionary)[k], prefix + "." + String(k), out)
	elif value is Array:
		var arr: Array = value
		var numeric := true
		for v: Variant in arr:
			if not (v is float or v is int):
				numeric = false
				break
		if numeric:
			for i in range(arr.size()):
				out["%s[%d]" % [prefix, i]] = arr[i]
	elif value is float or value is int:
		out[prefix] = value


func _fmt(v: Variant) -> String:
	if v == null:
		return "-"
	if v is float:
		return str(snappedf(v, 0.01))
	return str(v)

extends RefCounted

## Static helpers for the runtime performance harness (tests/perf_*.gd):
## argument parsing, statistics, JSON output and the memory / signal / tree probes.
## No class_name on purpose (the global class cache is only refreshed by the editor).

const OUT_DIR := "res://artifacts/perf/"
const HARNESS_SCRIPT_PREFIX := "res://tests/perf_"


# ------------------------------------------------------------------ arguments

## `-- --key=value --flag` -> {"key": "value", "flag": "1"}
static func parse_args() -> Dictionary:
	var out := {}
	for raw: String in OS.get_cmdline_user_args():
		if not raw.begins_with("--"):
			continue
		var body := raw.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = "1"
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


static func arg_int(args: Dictionary, key: String, fallback: int) -> int:
	return int(args[key]) if args.has(key) and String(args[key]).is_valid_int() else fallback


static func arg_float(args: Dictionary, key: String, fallback: float) -> float:
	return float(args[key]) if args.has(key) and String(args[key]).is_valid_float() else fallback


# ------------------------------------------------------------------ statistics

static func percentile_sorted(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var rank := clampf(p, 0.0, 1.0) * float(sorted.size() - 1)
	var lo := int(floor(rank))
	var hi := mini(lo + 1, sorted.size() - 1)
	return lerpf(sorted[lo], sorted[hi], rank - float(lo))


static func stats(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v: float in sorted:
		total += v
	return {
		"n": sorted.size(),
		"mean": r2(total / float(sorted.size())),
		"p50": r2(percentile_sorted(sorted, 0.50)),
		"p90": r2(percentile_sorted(sorted, 0.90)),
		"p95": r2(percentile_sorted(sorted, 0.95)),
		"p99": r2(percentile_sorted(sorted, 0.99)),
		"max": r2(sorted[sorted.size() - 1]),
		"min": r2(sorted[0]),
	}


static func mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v: float in values:
		total += v
	return total / float(values.size())


static func count_over(values: PackedFloat32Array, threshold: float) -> int:
	var n := 0
	for v: float in values:
		if v > threshold:
			n += 1
	return n


## Least-squares slope of ys over xs (per unit of x).
static func slope(xs: Array, ys: Array) -> float:
	var n := mini(xs.size(), ys.size())
	if n < 2:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for i in range(n):
		mx += float(xs[i])
		my += float(ys[i])
	mx /= n
	my /= n
	var num := 0.0
	var den := 0.0
	for i in range(n):
		num += (float(xs[i]) - mx) * (float(ys[i]) - my)
		den += (float(xs[i]) - mx) * (float(xs[i]) - mx)
	return num / den if den > 0.0 else 0.0


static func r2(v: float) -> float:
	return snappedf(v, 0.01)


static func r3(v: float) -> float:
	return snappedf(v, 0.001)


# ------------------------------------------------------------------ output

static func ensure_out_dir() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	# Keep the editor from importing/scanning harness output.
	var ignore := OUT_DIR + ".gdignore"
	if not FileAccess.file_exists(ignore):
		var f := FileAccess.open(ignore, FileAccess.WRITE)
		if f != null:
			f.store_string("")


static func write_json(path: String, data: Variant, indent: String = "") -> bool:
	ensure_out_dir()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[perf] cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, indent, false))
	f.close()
	return true


static func packed_round(values: PackedFloat32Array, step: float = 0.01) -> Array:
	var out := []
	out.resize(values.size())
	for i in range(values.size()):
		out[i] = snappedf(values[i], step)
	return out


# ------------------------------------------------------------------ probes

static func is_harness_object(o: Object) -> bool:
	if o == null:
		return false
	var s: Variant = o if o is Script else o.get_script()
	if s is Script:
		return String((s as Script).resource_path).begins_with(HARNESS_SCRIPT_PREFIX)
	return false


static func script_file(o: Object) -> String:
	if o == null:
		return ""
	if o is Script:
		return String((o as Script).resource_path)
	var s: Variant = o.get_script()
	if s is Script:
		var path := String((s as Script).resource_path)
		return path if not path.is_empty() else "<built-in script>"
	return ""


static func describe_callable(cb: Callable) -> String:
	if not cb.is_valid():
		var dead_method := String(cb.get_method()) if not cb.is_custom() else "<custom>"
		return "INVALID(target freed).%s" % dead_method
	var o := cb.get_object()
	var method := String(cb.get_method())
	if method.is_empty():
		method = "<lambda>" if cb.is_custom() else "?"
	if o == null:
		return "<no object>.%s" % method
	var file := script_file(o).get_file()
	if o is Script:
		return "lambda@%s.%s" % [file, method]
	return "%s(%s).%s" % [o.get_class(), file, method]


## Connections into `obj`'s signals, harness connections excluded.
static func connection_report(obj: Object, with_targets: bool = true) -> Dictionary:
	if obj == null:
		return {"total": -1}
	var total := 0
	var invalid := 0
	var per_signal := {}
	var targets := {}
	for info: Dictionary in obj.get_signal_list():
		var signal_name := String(info.get("name", ""))
		var n := 0
		for conn: Dictionary in obj.get_signal_connection_list(signal_name):
			var cb: Callable = conn.get("callable", Callable())
			if is_harness_object(cb.get_object()):
				continue
			n += 1
			if not cb.is_valid():
				invalid += 1
			if with_targets:
				var key := signal_name + " -> " + describe_callable(cb)
				targets[key] = int(targets.get(key, 0)) + 1
		if n > 0:
			per_signal[signal_name] = n
		total += n
	var out := {"total": total, "invalid": invalid, "per_signal": per_signal}
	if with_targets:
		out["targets"] = targets
	return out


## Sizes of every script Array / Dictionary / Packed* variable of `obj`.
static func container_sizes(obj: Object) -> Dictionary:
	var out := {}
	if obj == null:
		return out
	for prop: Dictionary in obj.get_property_list():
		if (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var t := int(prop.get("type", TYPE_NIL))
		if t == TYPE_ARRAY or t == TYPE_DICTIONARY or (t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_VECTOR4_ARRAY):
			var value: Variant = obj.get(String(prop.get("name", "")))
			if value != null:
				out[String(prop.get("name", ""))] = value.size()
	return out


static func perf_numbers() -> Dictionary:
	return {
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_node_count": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"memory_static_mb": r3(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		"memory_static_max_mb": r3(Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0),
		"video_mem_mb": r3(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"texture_mem_mb": r3(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		"buffer_mem_mb": r3(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0),
		"objects_in_frame": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"draw_calls_in_frame": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives_in_frame": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	}


static func count_descendants(node: Node) -> int:
	var n := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		n += 1
		for child: Node in cur.get_children(true):
			stack.append(child)
	return n


## Node counts by "Class|script" over the whole tree (harness nodes excluded).
static func tree_census(root: Node) -> Dictionary:
	var counts := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if is_harness_object(cur):
			continue
		var key := cur.get_class()
		var file := script_file(cur)
		if not file.is_empty():
			key += "|" + file.trim_prefix("res://")
		counts[key] = int(counts.get(key, 0)) + 1
		for child: Node in cur.get_children(true):
			stack.append(child)
	return counts


static func _name_pattern(n: String) -> String:
	var rx := RegEx.create_from_string("[0-9]+")
	return rx.sub(n, "#", true)


## Orphan nodes (not in the tree, still alive) grouped by class / script / scene / name pattern.
static func orphan_census(sample_limit: int = 3) -> Dictionary:
	if not ClassDB.class_has_method("Node", "get_orphan_node_ids", true):
		return {"available": false}
	var ids: Variant = ClassDB.class_call_static("Node", "get_orphan_node_ids")
	var groups := {}
	var total := 0
	for id: Variant in ids:
		var node := instance_from_id(int(id)) as Node
		if node == null:
			continue
		total += 1
		var key := node.get_class()
		var file := script_file(node)
		if not file.is_empty():
			key += "|" + file.trim_prefix("res://")
		if not node.scene_file_path.is_empty():
			key += "|scene=" + node.scene_file_path.trim_prefix("res://")
		key += "|name=" + _name_pattern(String(node.name))
		var g: Dictionary = groups.get(key, {"count": 0, "descendants": 0, "samples": []})
		g["count"] = int(g["count"]) + 1
		g["descendants"] = int(g["descendants"]) + count_descendants(node) - 1
		if (g["samples"] as Array).size() < sample_limit:
			(g["samples"] as Array).append(String(node.name))
		groups[key] = g
	return {"available": true, "total_roots_and_children": total, "groups": groups}


static func top_deltas(before: Dictionary, after: Dictionary, limit: int = 30, min_abs: int = 1) -> Array:
	var keys := {}
	for k: Variant in before.keys():
		keys[k] = true
	for k: Variant in after.keys():
		keys[k] = true
	var rows := []
	for k: Variant in keys.keys():
		var a := int(before.get(k, 0))
		var b := int(after.get(k, 0))
		if absi(b - a) >= min_abs:
			rows.append({"key": String(k), "before": a, "after": b, "delta": b - a})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return absi(int(x["delta"])) > absi(int(y["delta"])))
	return rows.slice(0, limit)


## Group counts of an orphan census for diffing: key -> count.
static func orphan_counts(census: Dictionary) -> Dictionary:
	var out := {}
	var groups: Dictionary = census.get("groups", {})
	for k: Variant in groups.keys():
		out[k] = int((groups[k] as Dictionary).get("count", 0))
	return out

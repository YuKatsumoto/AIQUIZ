extends SceneTree

## 比較用: 生成結果（gen.json）を、ゲームと同じ解析・正規化・採用の判定（_filter_unique_candidates）に通す。
## ラウンド（区分 × 並び）ごとに、ゲームと同じく 6 本で重複の記録を共有する。API は呼ばない。
##   godot --headless --path <project> --script <this file> -- dir=<ab dir>


func _initialize() -> void:
	await process_frame
	await process_frame
	var dir := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("dir="):
			dir = arg.substr(4)
	var fetcher = load("res://scripts/core/online_fetch.gd").new()
	get_root().add_child(fetcher)
	var prompts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/prompts.json"))
	var gen: Array = JSON.parse_string(FileAccess.get_file_as_string(dir + "/gen.json"))
	var rounds := {}
	for rec: Dictionary in gen:
		var key := "%d-%s" % [int(rec["bucket"]), str(rec["arm"])]
		if not rounds.has(key):
			rounds[key] = []
		rounds[key].append(rec)
	var rows: Array = []
	for key: String in rounds:
		var recs: Array = rounds[key]
		recs.sort_custom(func(a, b): return int(a["batch"]) < int(b["batch"]))
		var bucket: Dictionary = prompts["buckets"][int(recs[0]["bucket"])]
		var subject: String = bucket["subject"]
		var grade: int = int(bucket["grade"])
		var difficulty: String = bucket["difficulty"]
		var history: Array[String] = []
		for h: Variant in bucket["history"]:
			history.append(str(h))
		var dedup_blocklist: Array = fetcher._collect_dedup_blocklist(subject, grade, difficulty, history)
		var exact_blocklist: Dictionary = fetcher._collect_exact_blocklist(subject, grade, history)
		var semantic_blocklist: Array[String] = QuizDedup.tail_texts(history, QuizDedup.SEMANTIC_HISTORY_MAX)
		var unique_seen := {}
		var answer_seen := {}
		for rec: Dictionary in recs:
			var units := PackedStringArray(bucket["batches"][int(rec["batch"])]["units"])
			var raw: Array = fetcher.extract_quizzes_from_text(str(rec.get("text", "")))
			var normalized: Array[QuizItem] = []
			for r: Variant in raw:
				if r is Dictionary:
					var item: QuizItem = fetcher.normalize_single(r, "CLAUDE_STREAM")
					if item != null:
						normalized.append(item)
			var accepted: Array[QuizItem] = fetcher._filter_unique_candidates(normalized, dedup_blocklist,
				semantic_blocklist, unique_seen, answer_seen, units, subject, exact_blocklist, grade)
			rows.append({"bucket": int(rec["bucket"]), "arm": rec["arm"], "batch": int(rec["batch"]),
				"raw": raw.size(), "normalized": _plain(normalized), "accepted": _plain(accepted)})
	var f := FileAccess.open(dir + "/accepted.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"rows": rows}, "\t"))
	f.close()
	print("wrote accepted.json rows=%d" % rows.size())
	quit(0)


func _plain(items: Array[QuizItem]) -> Array:
	var out: Array = []
	for it: QuizItem in items:
		out.append({"q": it.q, "c": Array(it.c), "a": it.a, "g": it.genre, "t": it.estimated_seconds})
	return out

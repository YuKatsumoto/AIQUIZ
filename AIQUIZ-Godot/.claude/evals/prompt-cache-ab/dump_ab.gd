extends SceneTree

## 比較用: 同じ単元・出題アプローチ・出題済みリストで、今の並び（HEAD の compose_prompt）と
## 新しい並び（compose_prompt_parts + _generation_body）の generate の本文を書き出す。API は呼ばない。
##   godot --headless --path <project> --script <this file> -- out=<json> old=<old_online_fetch.gd>

const BUCKETS := [
	["国語", 2, "簡単"], ["国語", 4, "普通"], ["国語", 6, "難しい"],
	["算数", 2, "簡単"], ["算数", 3, "普通"], ["算数", 5, "難しい"],
	["理科", 3, "簡単"], ["理科", 4, "難しい"], ["理科", 6, "普通"],
	["社会", 3, "普通"], ["社会", 5, "簡単"], ["社会", 6, "難しい"],
	["英語", 3, "簡単"], ["英語", 5, "普通"], ["英語", 6, "難しい"],
]
## online_fetch.gd の 10 問モードと同じ
const FOCUSES: Array[String] = [
	"逆向きに考える問題、誤った考え方を見抜く問題、正しい手順や理由を選ぶ問題を中心にする。",
	"二段階の日常場面、複数の条件や情報を組み合わせて判断する問題を中心にする。",
	"比較・分類・規則性・成り立つ条件を考え、理由まで判断する問題を中心にする。",
	"図や具体物を頭の中で操作し、結果を予想する問題や、条件から逆算する問題を中心にする。",
]


func _initialize() -> void:
	await process_frame
	await process_frame
	var out_path := ""
	var old_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_path = arg.substr(4)
		elif arg.begins_with("old="):
			old_path = arg.substr(4)
	var new_fetcher = load("res://scripts/core/online_fetch.gd").new()
	get_root().add_child(new_fetcher)
	var old_fetcher = load(old_path).new()
	get_root().add_child(old_fetcher)
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://offline_bank.json"))
	var out := {"buckets": []}
	for b: Array in BUCKETS:
		var subject: String = b[0]
		var grade: int = b[1]
		var difficulty: String = b[2]
		# 出題済みリスト: 同梱の問題から 20 問（同じ教科・学年。プレイヤーの直近 20 問の代わり）
		var history: Array[String] = []
		var items: Variant = (bank.get(subject, {}) as Dictionary).get(str(grade), [])
		if items is Dictionary:
			var flat: Array = []
			for v: Variant in (items as Dictionary).values():
				if v is Array:
					flat.append_array(v)
			items = flat
		var step := maxi(1, (items as Array).size() / 20)
		for k in range(0, (items as Array).size(), step):
			var it: Variant = items[k]
			if it is Dictionary and history.size() < 20:
				history.append(str((it as Dictionary).get("q", "")))
		var batches: Array = new_fetcher._allocate_units_to_batches(subject, grade, 6, 4)
		var rows: Array = []
		for i in range(6):
			var units: PackedStringArray = batches[i] if i < batches.size() else PackedStringArray()
			var focus: String = FOCUSES[i % FOCUSES.size()]
			var old_prompt: String = old_fetcher.compose_prompt(subject, grade, difficulty, 4, history, false, units, true, focus)
			var old_body := ClaudeRequest.body(ClaudeRequest.TASK_GENERATE,
				old_prompt + old_fetcher.GENERATION_OUTPUT_FORMAT, old_fetcher.compose_system_instruction())
			var parts: Dictionary = new_fetcher.compose_prompt_parts(subject, grade, difficulty, 4, history, false, units, true, focus)
			rows.append({"units": Array(units), "focus_index": i % FOCUSES.size(),
				"old": JSON.parse_string(old_body), "new": JSON.parse_string(new_fetcher._generation_body(parts))})
		out["buckets"].append({"subject": subject, "grade": grade, "difficulty": difficulty,
			"history": history, "batches": rows})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("wrote ", out_path)
	quit(0)

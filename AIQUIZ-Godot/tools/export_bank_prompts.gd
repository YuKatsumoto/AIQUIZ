extends SceneTree

## 共有バンクの補充ジョブ（aiquiz-proxy/bank-builder.js）が使う生成プロンプトを書き出す。
## ゲームの 10 問モードと同じ compose_prompt で、区分（教科×学年×難易度）ごとに
## 単元の割り当てと出題アプローチを変えた PROMPTS_PER_BUCKET 本を作る。バンク用なので解説つき。
##
##   godot --headless --path . --script res://tools/export_bank_prompts.gd -- out=<json path>
##
## カリキュラム（assets/curriculum）やプロンプトを変えたら書き出し直してプロキシを更新する。

const PROMPTS_PER_BUCKET := 6
const QUESTIONS_PER_PROMPT := 4
const FOCUSES: Array[String] = [
	"逆向きに考える問題、誤った考え方を見抜く問題、正しい手順や理由を選ぶ問題を中心にする。",
	"二段階の日常場面、複数の条件や情報を組み合わせて判断する問題を中心にする。",
	"比較・分類・規則性・成り立つ条件を考え、理由まで判断する問題を中心にする。",
	"図や具体物を頭の中で操作し、結果を予想する問題や、条件から逆算する問題を中心にする。",
]
const DIFFICULTIES: Array[String] = ["簡単", "普通", "難しい"]


func _initialize() -> void:
	# --script モードではオートロードの登録を 1 フレーム待つ
	await process_frame
	var out_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_path = arg.substr(4)
	if out_path.is_empty():
		push_error("out=<json path> is required")
		quit(1)
		return
	var fetcher = load("res://scripts/core/online_fetch.gd").new()
	get_root().add_child(fetcher)
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://offline_bank.json"))

	var prompts: Array = []
	for subject: String in ["国語", "算数", "理科", "社会", "英語"]:
		var grades: Array = (bank.get(subject, {}) as Dictionary).keys()
		grades.sort_custom(func(a, b): return int(a) < int(b))
		for grade_text: Variant in grades:
			var grade := int(grade_text)
			for difficulty: String in DIFFICULTIES:
				var batches: Array = fetcher._allocate_units_to_batches(
					subject, grade, PROMPTS_PER_BUCKET, QUESTIONS_PER_PROMPT)
				for i in range(PROMPTS_PER_BUCKET):
					var units: PackedStringArray = batches[i] if i < batches.size() else PackedStringArray()
					var empty_history: Array[String] = []
					prompts.append({
						"subject": subject,
						"grade": grade,
						"difficulty": difficulty,
						"units": Array(units),
						"prompt": fetcher.compose_prompt(subject, grade, difficulty, QUESTIONS_PER_PROMPT,
							empty_history, false, units, false, FOCUSES[i % FOCUSES.size()]),
					})
	var data := {
		"version": 1,
		"questions_per_prompt": QUESTIONS_PER_PROMPT,
		"system": fetcher.compose_system_instruction(),
		"prompts": prompts,
	}
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	print("[export] wrote %d prompts to %s" % [prompts.size(), out_path])
	quit(0)

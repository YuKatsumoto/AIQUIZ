extends SceneTree

## 1〜3年の問題文と選択肢が、選んだ学年までに習う漢字だけになっていることを確かめる（学年別漢字配当表）。
## 4年以上は漢字を制限しない。
## godot --headless --path . --script res://tests/kanji_grade_unit.gd
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	# --script ではオートロードの登録前にクラスがコンパイルされるので、1フレーム待ってから読む
	await process_frame
	_check_table()
	_check_offline_bank()
	_check_generation()
	_check_shared_bank()
	_check_english_tags()
	print("KANJI_GRADE_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _check_table() -> void:
	check(KanjiGrade.is_available(), "table loads")
	var sizes := {}
	for line: String in KanjiGrade.allowed_kanji_lines(6):
		var parts := line.split(": ")
		sizes[parts[0]] = parts[1].length()
	check(sizes == {"1年": 80, "2年": 160, "3年": 200, "4年": 202, "5年": 193, "6年": 191}, "1026 kanji by grade: %s" % sizes)
	for pair: Array in [["山", 1], ["何", 2], ["漢", 3], ["英", 4], ["岡", 4], ["個", 5], ["誕", 6],
			["江", KanjiGrade.NOT_IN_TABLE], ["あ", 0], ["ア", 0], ["A", 0], ["々", 0], ["？", 0], ["卍", 0], ["阝", 0]]:
		check(KanjiGrade.grade_of(pair[0]) == pair[1], "grade_of(%s) == %d" % pair)
	check(KanjiGrade.over_grade_in_quiz("地図記号「卍」が表している場所は？", PackedStringArray(["お寺", "神社"]), 3).is_empty(),
		"map symbols are fine at grade 3")
	check(KanjiGrade.checks_grade(3) and not KanjiGrade.checks_grade(4), "only grades 1-3 are checked")
	check(KanjiGrade.over_grade_in_quiz("昆虫の体は？", PackedStringArray(["頭", "胸"]), 4).is_empty(), "grade 4 is not restricted")
	check(KanjiGrade.over_grade("「大きい」の反対の意味の言葉はどれ？", 2) == PackedStringArray(["反", "対", "意", "味", "葉"]),
		"over_grade lists each unlearned kanji once")
	check(KanjiGrade.over_grade("「大きい」の反対の意味の言葉はどれ？", 3).is_empty(), "all learned by grade 3")
	check(KanjiGrade.over_grade("「大きい」のはんたいのいみのことばはどれ？", 1).is_empty(), "hiragana passes")
	check(KanjiGrade.over_grade_in_quiz("どれ？", PackedStringArray(["山", "重い"]), 2) == PackedStringArray(["重"]),
		"choices are checked too")
	check(KanjiGrade.allowed_kanji_lines(2).size() == 2, "prompt list stops at the grade")


## 同梱の問題（offline_bank.json）。ゲームで選べる教科・学年のうち、漢字を制限する学年だけを見る。
func _check_offline_bank() -> void:
	var bank := QuizProvider.shared_bank()
	check(not bank.is_empty(), "offline bank loads")
	for subject: String in bank.keys():
		for grade in Constants.grades_for_subject(subject):
			if not KanjiGrade.checks_grade(grade):
				continue
			var items: Variant = (bank[subject] as Dictionary).get(str(grade), [])
			var bad := PackedStringArray()
			for raw: Variant in items:
				var item: Dictionary = raw
				var over: PackedStringArray = KanjiGrade.over_grade_in_quiz(str(item.get("q", "")), PackedStringArray(item.get("c", [])), grade)
				if not over.is_empty():
					bad.append("%s (%s)" % [str(item["q"]).left(30), "".join(over)])
			check(bad.is_empty(), "%s%d年: %d questions use unlearned kanji, e.g. %s" % [subject, grade, bad.size(), bad.slice(0, 3)])


## AI 生成：プロンプトに使ってよい漢字を渡し、守っていない候補は捨てる。
func _check_generation() -> void:
	var fetcher: Node = load("res://scripts/core/online_fetch.gd").new()
	root.add_child(fetcher)
	var history: Array[String] = []
	var prompt: String = fetcher.compose_prompt("理科", 3, "普通", 4, history)
	check(prompt.contains("小学3年生までに習う下の漢字だけ"), "prompt states the kanji rule")
	check(prompt.contains("3年: ") and not prompt.contains("4年: "), "prompt lists kanji up to grade 3")
	var ok := QuizItem.create("こん虫の体はいくつに分かれていますか？", PackedStringArray(["2つ", "3つ", "4つ", "6つ"]), 1, "", "GEMINI")
	var bad_q := QuizItem.create("昆虫の体はいくつに分かれていますか？", PackedStringArray(["2つ", "3つ", "4つ", "5つ"]), 1, "", "GEMINI")
	var bad_c := QuizItem.create("じしゃくにつくものはどれ？", PackedStringArray(["鉄", "銅", "紙", "木"]), 0, "", "GEMINI")
	var candidates: Array[QuizItem] = [ok, bad_q, bad_c]
	var kept: Array = fetcher._filter_unique_candidates(candidates, [], [], {}, {}, PackedStringArray(), "理科", {}, 3)
	check(kept.size() == 1 and kept[0] == ok, "filter keeps only questions within grade 3 (銅 is grade 5)")
	var no_grade: Array[QuizItem] = [bad_q]
	check(fetcher._filter_unique_candidates(no_grade, [], [], {}, {}).size() == 1, "grade 0 skips the kanji check")
	var grade_4: Array[QuizItem] = [bad_q]
	check(fetcher._filter_unique_candidates(grade_4, [], [], {}, {}, PackedStringArray(), "理科", {}, 4).size() == 1,
		"grade 4 keeps kanji above the grade")
	var prompt_4: String = fetcher.compose_prompt("理科", 4, "普通", 4, history)
	check(not prompt_4.contains("までに習う下の漢字だけ"), "grade 4 prompt has no kanji list")
	fetcher.queue_free()


## 共有バンク（Firebase）から受け取る問題・送る問題も同じ基準で弾く。
func _check_shared_bank() -> void:
	var cache: Object = load("res://scripts/core/firebase_quiz_cache.gd").new()
	var item := {"q": "こん虫はどれ？", "c": ["チョウ", "クモ", "ダンゴムシ", "ムカデ"], "a": 0,
		"subject": "理科", "grade": 3, "difficulty": "簡単", "src": "GEMINI"}
	check(cache._is_valid_cache_item(item), "shared item within grade is accepted")
	item["q"] = "昆虫はどれ？"
	check(not cache._is_valid_cache_item(item), "shared item above grade is rejected")
	cache.free()


## 英語3年は【基本】【応用】の代わりにひらがなのタグを使う。難しさの振り分けは同じに効く。
func _check_english_tags() -> void:
	var provider := QuizProvider.new()
	var basic := QuizItem.create("【きほん】「雨」を表すえい語は？", PackedStringArray(["rainy", "sunny"]), 0)
	var advanced := QuizItem.create("【おうよう】「雨」を表すえい語は？", PackedStringArray(["rainy", "sunny"]), 0)
	var gap: float = provider._complexity_score(advanced, "英語", 3) - provider._complexity_score(basic, "英語", 3)
	check(gap > 3.0, "hiragana level tags still split basic/advanced (gap %.2f)" % gap)
	provider.free()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL " + label)

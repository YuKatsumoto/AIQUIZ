extends Node
class_name QuizProvider

## オフラインクイズプロバイダー
## Python版 quiz_provider.py の OfflineQuizProvider 相当

var bank_path: String
var bank: Dictionary = {}

func _init(path: String = "res://offline_bank.json") -> void:
	bank_path = path
	bank = _load_bank()

func _load_bank() -> Dictionary:
	if not FileAccess.file_exists(bank_path):
		push_warning("[QuizProvider] Bank file not found: %s" % bank_path)
		return {}
	var file := FileAccess.open(bank_path, FileAccess.READ)
	if not file:
		push_warning("[QuizProvider] Failed to open bank: %s" % bank_path)
		return {}
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_warning("[QuizProvider] JSON parse error: %s" % json.get_error_message())
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

func total_count() -> int:
	var total := 0
	for subj_data: Variant in bank.values():
		if subj_data is Dictionary:
			for grade_list: Variant in subj_data.values():
				if grade_list is Array:
					total += grade_list.size()
	return total

func begin_round(_subject: String, _grade: int, _difficulty: String,
		_mode: String, _target_count: int) -> void:
	pass

func end_round() -> void:
	pass

func stop() -> void:
	pass

func submit_result(_quiz: QuizItem, _correct: bool) -> void:
	pass

# ---------- Normalize ----------

func _normalize(raw: Variant) -> QuizItem:
	if not raw is Dictionary:
		return null
	var q_text: String = str(raw.get("q", "")).strip_edges()
	var c_raw: Variant = raw.get("c", [])
	var a_raw: Variant = raw.get("a", null)

	if q_text.is_empty() or not c_raw is Array:
		return null
	if c_raw.size() != 2 and c_raw.size() != 4:
		return null

	var a_int: int
	if a_raw is float:
		a_int = int(a_raw)
	elif a_raw is int:
		a_int = a_raw
	elif a_raw is String and a_raw.is_valid_int():
		a_int = int(a_raw)
	else:
		return null

	if a_int < 0 or a_int >= c_raw.size():
		return null

	var e_text: String = str(raw.get("e", raw.get("exp", ""))).strip_edges()
	var src_text: String = str(raw.get("src", "OFFLINE")).strip_edges()
	if src_text.is_empty():
		src_text = "OFFLINE"

	var cleaned := PackedStringArray()
	for x: Variant in c_raw:
		var s := str(x).strip_edges()
		if s.is_empty():
			return null
		cleaned.append(s)

	var img_text: String = str(raw.get("img", "")).strip_edges()
	var ci_raw: Variant = raw.get("choice_img", raw.get("choiceImg", []))
	var choice_imgs := PackedStringArray()
	if ci_raw is Array:
		for ci: Variant in ci_raw:
			choice_imgs.append(str(ci))

	return QuizItem.create(q_text, cleaned, a_int, e_text, src_text, img_text, choice_imgs)

# ---------- Difficulty bucketing ----------

func _complexity_score(item: QuizItem, subject: String, grade: int) -> float:
	var text: String = "%s %s %s" % [item.q, " ".join(PackedStringArray(item.c)), item.e]
	var q_text: String = item.q

	var score: float = 0.0
	score += float(q_text.length()) / 40.0
	score += float(item.e.length()) / 80.0

	# Count digits
	var regex_digit := RegEx.new()
	regex_digit.compile("\\d")
	score += regex_digit.search_all(text).size() * 0.08

	# Count operators
	var regex_op := RegEx.new()
	regex_op.compile("[\\+\\-\\*/÷×%]")
	score += regex_op.search_all(text).size() * 0.25

	# Count brackets
	var regex_bracket := RegEx.new()
	regex_bracket.compile("[()（）]")
	score += regex_bracket.search_all(text).size() * 0.2

	if "【応用】" in q_text:
		score += 1.2
	if "【基本】" in q_text:
		score -= 0.6

	if subject == "算数":
		for token: String in ["割合", "比", "速さ", "体積", "平均", "合同", "比例", "反比例"]:
			if token in text:
				score += 0.9
		var regex_big_num := RegEx.new()
		regex_big_num.compile("\\d{3,}")
		if regex_big_num.search(text):
			score += 0.4
	elif subject == "理科":
		for token: String in ["実験", "観察", "原因", "結果", "規則", "電磁石", "水溶液", "燃焼", "光合成"]:
			if token in text:
				score += 0.7
	elif subject == "国語":
		for token: String in ["敬語", "四字熟語", "古典", "短歌", "俳句", "歴史的仮名遣い", "比喩"]:
			if token in text:
				score += 0.9

	score -= maxf(0.0, float(grade - 1)) * 0.08
	return score

func _bucket_by_difficulty(items: Array[QuizItem], subject: String,
		grade: int, difficulty: String) -> Array[QuizItem]:
	if items.size() <= 2:
		return items

	# Score and sort
	var scored: Array = []
	for it: QuizItem in items:
		scored.append({"score": _complexity_score(it, subject, grade), "item": it})
	scored.sort_custom(func(a_val: Dictionary, b_val: Dictionary) -> bool:
		return a_val["score"] < b_val["score"])

	var n: int = scored.size()
	var low_end: int = maxi(1, n / 3)
	var high_start: int = maxi(low_end, (2 * n) / 3)

	var bucket: Array[QuizItem] = []
	if difficulty == "簡単":
		for i: int in range(low_end):
			bucket.append(scored[i]["item"])
	elif difficulty == "難しい":
		for i: int in range(high_start, n):
			bucket.append(scored[i]["item"])
	else:
		for i: int in range(low_end, high_start):
			bucket.append(scored[i]["item"])

	return bucket if not bucket.is_empty() else items

# ---------- Fallback ----------

func _fallback_question(subject: String, grade: int) -> QuizItem:
	var a_val: int = randi_range(2, 20)
	var b_val: int = randi_range(1, 10)
	var ans: int = a_val + b_val
	var wrong: int = ans + [-2, -1, 1, 2].pick_random()
	var choices: Array[String] = [str(ans), str(wrong)]
	choices.shuffle()
	var ans_idx: int = choices.find(str(ans))
	return QuizItem.create(
		"[%s%d年] %d+%d はどちら？" % [subject, grade, a_val, b_val],
		PackedStringArray(choices),
		ans_idx,
		"%d+%d=%d" % [a_val, b_val, ans],
		"FALLBACK"
	)

# ---------- Main API ----------

func get_quizzes(subject: String, grade: int, difficulty: String,
		mode: String, count: int) -> Array[QuizItem]:
	var grade_str := str(grade)
	var subj_data: Variant = bank.get(subject, {})
	var raw_items_data: Variant
	if subj_data is Dictionary:
		raw_items_data = subj_data.get(grade_str, [])
	else:
		raw_items_data = []

	var items: Array[QuizItem] = []
	if raw_items_data is Array:
		for raw: Variant in raw_items_data:
			var n := _normalize(raw)
			if n:
				items.append(n)

	if items.is_empty():
		if mode == Constants.MODE_TEN:
			var fallbacks: Array[QuizItem] = []
			for i: int in range(maxi(1, count)):
				fallbacks.append(_fallback_question(subject, grade))
			return fallbacks
		return [_fallback_question(subject, grade)]

	var pool := _bucket_by_difficulty(items, subject, grade, difficulty)
	pool.shuffle()

	if mode == Constants.MODE_TEN:
		var uniq: Array[QuizItem] = []
		var seen: Dictionary = {}
		for q_item: QuizItem in pool:
			if q_item.q in seen:
				continue
			seen[q_item.q] = true
			uniq.append(q_item)
			if uniq.size() >= count:
				break
		# Also check from full items if pool was too small
		if uniq.size() < count:
			for q_item: QuizItem in items:
				if q_item.q in seen:
					continue
				seen[q_item.q] = true
				uniq.append(q_item)
				if uniq.size() >= count:
					break
		while uniq.size() < count:
			uniq.append(_fallback_question(subject, grade))
		return uniq

	return [pool.pick_random()]

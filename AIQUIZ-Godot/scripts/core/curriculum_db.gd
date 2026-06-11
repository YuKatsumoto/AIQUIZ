extends RefCounted
class_name CurriculumDB

## 教科書準拠カリキュラムデータベース
## assets/curriculum/<教科>/grade_<N>.json を読み込み、
## ランダム単元選択 → compose_prompt 向け Dictionary を組み立てる。

# ── キャッシュ（同一フレーム内で同じJSONを何度も読まないようにする） ──
static var _cache: Dictionary = {}


static func load_grade(subject: String, grade: int) -> Dictionary:
	var path := _resolve_path(subject, grade)
	
	# キャッシュ確認
	if _cache.has(path):
		return _cache[path]
	
	if not FileAccess.file_exists(path):
		push_warning("CurriculumDB: File not found: %s" % path)
		return {}
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CurriculumDB: Cannot open: %s" % path)
		return {}
	
	var text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning("CurriculumDB: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	
	var data: Dictionary = json.get_data()
	_cache[path] = data
	return data


## 指定学年の全単元から count 個をランダム選択して返す
static func pick_random_units(subject: String, grade: int, count: int = 3) -> Array:
	var data := load_grade(subject, grade)
	if data.is_empty() or not data.has("units"):
		return []
	
	var units: Array = data["units"]
	if units.size() <= count:
		return units.duplicate()
	
	var shuffled := units.duplicate()
	shuffled.shuffle()
	return shuffled.slice(0, count)


## compose_prompt 用の curriculum Dictionary を組み立てる
## 既存の _get_curriculum() と同じ shape を返す
static func build_curriculum(subject: String, grade: int, unit_count: int = 3) -> Dictionary:
	var data := load_grade(subject, grade)
	if data.is_empty():
		return {}
	
	var selected_units := pick_random_units(subject, grade, unit_count)
	if selected_units.is_empty():
		return {}
	
	return _assemble_curriculum(data, selected_units)


## 指定した単元名のみで curriculum Dictionary を組み立てる
## バッチ単元割当（_allocate_units_to_batches）と連動し、
## 「出題範囲」をバッチの担当単元に限定するために使う。
static func build_curriculum_for_units(subject: String, grade: int, unit_names: PackedStringArray) -> Dictionary:
	var data := load_grade(subject, grade)
	if data.is_empty() or not data.has("units"):
		return {}
	
	var name_set := {}
	for n in unit_names:
		name_set[str(n)] = true
	
	var selected_units: Array = []
	for unit in data["units"]:
		if unit is Dictionary and name_set.has(str(unit.get("name", ""))):
			selected_units.append(unit)
	
	if selected_units.is_empty():
		return {}
	
	return _assemble_curriculum(data, selected_units)


## selected_units 配列から compose_prompt 用 Dictionary を組み立てる共通処理
static func _assemble_curriculum(data: Dictionary, selected_units: Array) -> Dictionary:
	# ── 選択した単元名を結合 ──
	var topic_names: PackedStringArray = []
	for unit: Dictionary in selected_units:
		topic_names.append(unit.get("name", ""))
	
	# ── 各単元から key_concepts / typical_mistakes / examples を集約 ──
	var all_mistakes: Array[String] = []
	var all_examples: Array[String] = []
	var all_json_examples: Array[String] = []
	var all_concepts: Array[String] = []
	
	for unit: Dictionary in selected_units:
		# key_concepts
		for c: String in unit.get("key_concepts", []):
			all_concepts.append(c)
		
		# typical_mistakes
		for m: String in unit.get("typical_mistakes", []):
			all_mistakes.append(m)
		
		# sample_questions → テキスト例 + JSON例に変換
		for sq in unit.get("sample_questions", []):
			if sq is Dictionary:
				var q_text: String = sq.get("q", "")
				var choices: Array = sq.get("c", [])
				var a_idx: int = int(sq.get("a", 0))
				var answer_text := ""
				if choices.size() > a_idx:
					answer_text = str(choices[a_idx])
				all_examples.append("%s（正解: %s）" % [q_text, answer_text])
				all_json_examples.append(JSON.stringify(sq))
	
	# ── grade-level データ ──
	var keywords: String = str(data.get("keywords", ""))
	
	var bad_examples: Array[String] = []
	for b in data.get("bad_examples", []):
		bad_examples.append(str(b))
	
	# ── 出題範囲の明示指示 ──
	var topics_str := ", ".join(topic_names)
	
	return {
		"topics": topics_str,
		"keywords": keywords,
		"examples": all_examples,
		"easy_desc": "",
		"normal_desc": "",
		"hard_desc": "",
		"bad_examples": bad_examples,
		"typical_mistakes": all_mistakes,
		"good_json_examples": all_json_examples,
		# 新規フィールド（compose_prompt で活用）
		"key_concepts": all_concepts,
		"selected_unit_names": topic_names,
	}


## キャッシュをクリア（テスト用）
static func clear_cache() -> void:
	_cache.clear()


# ── private ──

static func _resolve_path(subject: String, grade: int) -> String:
	# 理科・社会の1-2年は生活科（grade_1.json に統合）
	var effective_grade := grade
	if (subject == "理科" or subject == "社会") and grade <= 2:
		effective_grade = 1
	return "res://assets/curriculum/%s/grade_%d.json" % [subject, effective_grade]

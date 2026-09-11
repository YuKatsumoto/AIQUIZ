extends RefCounted
class_name GeneratedBank

## オンライン生成の余剰候補を次ラウンドへ引き継ぐローカルプール。
## キーは {教科}_{学年}_{難易度}。同一ジャンル偏りと TTL 切れを保存時に弾く。

const SAVE_PATH: String = "user://generated_bank.json"
const SCHEMA_VERSION: int = 1
const MAX_PER_CATEGORY: int = 40
const MAX_PER_GENRE: int = 4
const TTL_SEC: int = 30 * 24 * 60 * 60
const SRC_TAG: String = "GEMINI_POOL"

var _data: Dictionary = {"version": SCHEMA_VERSION, "categories": {}}
var _loaded: bool = false


func category_key(subject: String, grade: int, difficulty: String) -> String:
	return "%s_%d_%s" % [subject, grade, difficulty]


func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var root: Dictionary = parsed
		if int(root.get("version", 0)) != SCHEMA_VERSION:
			print("[GeneratedBank] Schema mismatch, starting empty pool")
			return
		var cats: Variant = root.get("categories", {})
		if cats is Dictionary:
			_data = {"version": SCHEMA_VERSION, "categories": (cats as Dictionary).duplicate(true)}
	_prune_expired()


func save() -> void:
	ensure_loaded()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_data))
	f.close()


func list_question_texts(subject: String, grade: int, difficulty: String) -> Array[String]:
	var texts: Array[String] = []
	for item in _category_items(subject, grade, difficulty):
		var q_text := str(item.get("q", ""))
		if not q_text.is_empty() and q_text not in texts:
			texts.append(q_text)
	return texts


func take_items(subject: String, grade: int, difficulty: String) -> Array[QuizItem]:
	var out: Array[QuizItem] = []
	for raw in _category_items(subject, grade, difficulty):
		var item := QuizItem.from_pool_dict(raw)
		if item.q.is_empty() or item.c.is_empty():
			continue
		if item.a < 0 or item.a >= item.c.size():
			continue
		out.append(item)
	return out


func remove_questions(subject: String, grade: int, difficulty: String, questions: Array[String]) -> void:
	if questions.is_empty():
		return
	ensure_loaded()
	var key := category_key(subject, grade, difficulty)
	var cats: Dictionary = _data.get("categories", {})
	var kept: Array = []
	for raw in cats.get(key, []):
		if not raw is Dictionary:
			continue
		var q_text := str((raw as Dictionary).get("q", ""))
		if q_text in questions:
			continue
		kept.append(raw)
	cats[key] = kept
	_data["categories"] = cats
	save()


func store_items(items: Array[QuizItem], subject: String, grade: int, difficulty: String) -> int:
	if items.is_empty():
		return 0
	ensure_loaded()
	var key := category_key(subject, grade, difficulty)
	var cats: Dictionary = _data.get("categories", {})
	var bucket: Array = []
	var existing_texts: Array[String] = []
	var genre_counts := {}
	for raw in cats.get(key, []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if _is_expired(entry):
			continue
		var q_text := str(entry.get("q", ""))
		if q_text.is_empty():
			continue
		bucket.append(entry)
		existing_texts.append(q_text)
		var g := str(entry.get("genre", ""))
		genre_counts[g] = int(genre_counts.get(g, 0)) + 1

	var stored := 0
	for quiz in items:
		if quiz == null or quiz.q.strip_edges().is_empty():
			continue
		if QuizDedup.is_strict_duplicate_to_any(quiz.q, existing_texts):
			continue
		if QuizDedup.is_similar_to_any(quiz.q, existing_texts):
			continue
		var genre := quiz.genre.strip_edges()
		if genre.is_empty():
			genre = "未分類"
			quiz.genre = genre
		if int(genre_counts.get(genre, 0)) >= MAX_PER_GENRE:
			continue
		var payload := quiz.to_pool_dict()
		payload["src"] = SRC_TAG
		payload["genre"] = genre
		bucket.append(payload)
		existing_texts.append(quiz.q)
		genre_counts[genre] = int(genre_counts.get(genre, 0)) + 1
		stored += 1

	while bucket.size() > MAX_PER_CATEGORY:
		bucket.pop_front()
	cats[key] = bucket
	_data["categories"] = cats
	if stored > 0:
		save()
		print("[GeneratedBank] Stored %d surplus quizzes in %s (now %d)" % [stored, key, bucket.size()])
	return stored


func _category_items(subject: String, grade: int, difficulty: String) -> Array:
	ensure_loaded()
	var cats: Dictionary = _data.get("categories", {})
	var raw: Variant = cats.get(category_key(subject, grade, difficulty), [])
	return raw if raw is Array else []


func _is_expired(entry: Dictionary) -> bool:
	var stored_at := int(entry.get("stored_at", 0))
	if stored_at <= 0:
		return false
	return int(Time.get_unix_time_from_system()) - stored_at > TTL_SEC


func _prune_expired() -> void:
	var cats: Dictionary = _data.get("categories", {})
	var now := int(Time.get_unix_time_from_system())
	for key in cats.keys():
		var kept: Array = []
		for raw in cats[key]:
			if not raw is Dictionary:
				continue
			var entry: Dictionary = raw
			var stored_at := int(entry.get("stored_at", 0))
			if stored_at > 0 and now - stored_at > TTL_SEC:
				continue
			kept.append(entry)
		while kept.size() > MAX_PER_CATEGORY:
			kept.pop_front()
		cats[key] = kept
	_data["categories"] = cats

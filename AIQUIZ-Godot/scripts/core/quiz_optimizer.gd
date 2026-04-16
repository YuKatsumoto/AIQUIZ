extends Node
class_name QuizOptimizer

signal evaluation_completed(good_count: int, bad_count: int)

var ratings: Dictionary = {
	"good": [],
	"bad": []
}

func _ready() -> void:
	_load_ratings()

func _load_ratings() -> void:
	if FileAccess.file_exists("user://quiz_ratings.json"):
		var f := FileAccess.open("user://quiz_ratings.json", FileAccess.READ)
		var json = JSON.parse_string(f.get_as_text())
		if json is Dictionary:
			if json.has("good"): ratings["good"] = json["good"]
			if json.has("bad"): ratings["bad"] = json["bad"]
	elif FileAccess.file_exists("res://quiz_ratings.json"):
		var f := FileAccess.open("res://quiz_ratings.json", FileAccess.READ)
		var json = JSON.parse_string(f.get_as_text())
		if json is Dictionary:
			if json.has("good"): ratings["good"] = json["good"]
			if json.has("bad"): ratings["bad"] = json["bad"]

func _save_ratings() -> void:
	var f := FileAccess.open("user://quiz_ratings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(ratings, "  "))

func evaluate_history(history: Array[Dictionary], subject: String, grade: int, difficulty: String) -> void:
	var to_evaluate: Array[Dictionary] = []
	for entry in history:
		var q: QuizItem = entry.get("quiz")
		if not q: continue
		if entry.get("rated", "") == "" and (q.src == "GEMINI" or q.src == "OPENAI"):
			to_evaluate.append(entry)
			
	if to_evaluate.is_empty():
		return
		
	var items := []
	for i in range(to_evaluate.size()):
		var entry = to_evaluate[i]
		var q: QuizItem = entry["quiz"]
		items.append({
			"id": i,
			"q": q.q,
			"c": q.c,
			"a": q.a,
			"e": q.e
		})
		
	var prompt := "あなたは小学校の教員で、クイズ作成AIの生成結果を評価する役割です。\n"
	prompt += "以下のクイズは「%s」の「%s年生」向けに出題されたものです。\n" % [subject, str(grade)]
	prompt += "各問題について、以下の違反基準に1つでも該当する場合は「悪い問題（bad）」とし、そうでない場合は「良い問題（good）」と判定してください。\n"
	prompt += "【違反基準】\n"
	prompt += "1. 対象学年の学習範囲を超えている（小さすぎる、大きすぎる）。\n"
	prompt += "2. 選択肢の中に正しい答えが含まれていない、または正解が複数存在する。\n"
	prompt += "3. 思考力が不要なほど簡単すぎる、あるいは「偶数はどれ？」のような一般的すぎる内容。\n\n"
	prompt += "以下のJSON配列フォーマットのみで出力してください（マークダウン等不要）。\n"
	prompt += "[\n  {\"id\": 0, \"rating\": \"good\" または \"bad\", \"reason\": \"理由（簡潔に）\"}\n]\n\n"
	prompt += "対象問題データ:\n"
	prompt += JSON.stringify(items, "  ")
	
	_fetch_evaluation(prompt, to_evaluate, subject, grade, difficulty)

func _fetch_evaluation(prompt: String, to_evaluate: Array[Dictionary], subject: String, grade: int, difficulty: String) -> void:
	var key := ApiStatusAutoload.get_env("GOOGLE_API_KEY")
	if key.is_empty():
		key = ApiStatusAutoload.get_env("GEMINI_API_KEY")
	if key.is_empty():
		return
		
	var target_model := "gemini-3.1-pro-preview"
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [target_model, key]
	
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 20.0
	
	var body := JSON.stringify({
		"contents": [{"parts": [{"text": prompt}]}],
		"generationConfig": {"temperature": 0.2, "responseMimeType": "application/json"}
	})
	
	http.request_completed.connect(func(result: int, response_code: int, _h, b: PackedByteArray):
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.parse_string(b.get_string_from_utf8())
			if json is Dictionary and json.has("candidates"):
				var text: String = json["candidates"][0]["content"]["parts"][0].get("text", "")
				var res = _extract_json_array(text)
				if res:
					_process_evaluation_results(res, to_evaluate, subject, grade, difficulty)
		http.queue_free()
	)
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func _extract_json_array(text: String) -> Variant:
	text = text.strip_edges()
	if text.begins_with("```json"): text = text.substr(7)
	elif text.begins_with("```"): text = text.substr(3)
	if text.ends_with("```"): text = text.substr(0, text.length() - 3)
	text = text.strip_edges()
	var json := JSON.new()
	if json.parse(text) == OK:
		var d = json.get_data()
		if d is Array: return d
	return null

func _process_evaluation_results(eval_results: Array, to_evaluate: Array[Dictionary], subject: String, grade: int, difficulty: String) -> void:
	var new_good := 0
	var new_bad := 0
	
	for res in eval_results:
		if not res is Dictionary or not res.has("id") or not res.has("rating"):
			continue
		var idx = res["id"]
		if typeof(idx) != 2 and typeof(idx) != 3: # Not int or float
			if typeof(idx) == TYPE_STRING and (idx as String).is_valid_int():
				idx = int(idx)
			else:
				continue
		
		var rating: String = str(res["rating"]).to_lower()
		var reason: String = res.get("reason", "")
		
		if idx >= 0 and idx < to_evaluate.size():
			var entry = to_evaluate[idx]
			var q: QuizItem = entry["quiz"]
			entry["rated"] = rating
			
			var payload := {
				"q": q.q,
				"c": Array(q.c),
				"a": q.a,
				"e": q.e,
				"subject": subject,
				"grade": str(grade),
				"difficulty": difficulty,
				"reason": reason,
				"ts": int(Time.get_unix_time_from_system())
			}
			
			if rating == "good":
				ratings["good"].append(payload)
				new_good += 1
				QuizManager.firebase_ratings.send_rating(q, true, subject, grade, difficulty)
			elif rating == "bad":
				ratings["bad"].append(payload)
				new_bad += 1
				QuizManager.firebase_ratings.send_rating(q, false, subject, grade, difficulty)
				
	if new_good > 0 or new_bad > 0:
		_limit_cache()
		_save_ratings()
		evaluation_completed.emit(new_good, new_bad)
		print("[QuizOptimizer] Evaluated %d new quizzes: %d good, %d bad." % [to_evaluate.size(), new_good, new_bad])

func _limit_cache() -> void:
	var MAX_ITEMS = 100
	if ratings["good"].size() > MAX_ITEMS:
		ratings["good"] = ratings["good"].slice(ratings["good"].size() - MAX_ITEMS)
	if ratings["bad"].size() > MAX_ITEMS:
		ratings["bad"] = ratings["bad"].slice(ratings["bad"].size() - MAX_ITEMS)

func get_feedback_examples(subject: String, grade: int, limit: int = 3) -> Dictionary:
	var res := {"good": [] as Array[String], "bad": [] as Array[String]}
	
	for type in ["good", "bad"]:
		var matches := []
		for item in ratings[type]:
			if str(item.get("subject", "")) == subject and str(item.get("grade", "")) == str(grade):
				var txt := "%s (解答: %s)" % [item["q"], item["c"][item["a"]]]
				if item.has("reason") and not item["reason"].is_empty():
					txt += " ※%s" % item["reason"]
				matches.append(txt)
		
		matches.reverse()
		for i in range(mini(matches.size(), limit)):
			res[type].append(matches[i])
			
	return res

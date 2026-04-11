extends Node
class_name OnlineFetch

signal fetch_completed(quizzes: Array[QuizItem])

func extract_json_from_text(text: String) -> Variant:
	text = text.strip_edges()
	if text.begins_with("```json"):
		text = text.substr(7)
	elif text.begins_with("```"):
		text = text.substr(3)
	if text.ends_with("```"):
		text = text.substr(0, text.length() - 3)
	text = text.strip_edges()
	
	if text.is_empty():
		return null
		
	var starts := []
	for i in range(text.length()):
		if text[i] == "[" or text[i] == "{":
			starts.append(i)
	if starts.is_empty():
		return null
	
	var ends := []
	for i in range(text.length() - 1, -1, -1):
		if text[i] == "]" or text[i] == "}":
			ends.append(i)
	if ends.is_empty():
		return null
	
	var json := JSON.new()
	for start in starts:
		for end in ends:
			if end < start:
				continue
			var sub := text.substr(start, end - start + 1)
			var err := json.parse(sub)
			if err == OK:
				return json.get_data()
	return null

func extract_quizzes_from_text(raw_text: String) -> Array:
	var obj = extract_json_from_text(raw_text)
	if obj == null:
		return []
	if obj is Array:
		var arr := []
		for x in obj:
			if x is Dictionary:
				arr.append(x)
		return arr
	if obj is Dictionary:
		var quizzes = obj.get("quizzes", [])
		if quizzes is Array:
			var arr := []
			for x in quizzes:
				if x is Dictionary:
					arr.append(x)
			return arr
	return []

func normalize_single(raw: Dictionary, src: String) -> QuizItem:
	var q := str(raw.get("q", "")).strip_edges()
	var c_raw = raw.get("c", [])
	var a = raw.get("a", null)
	var e := str(raw.get("e", raw.get("exp", ""))).strip_edges()
	
	if q.is_empty() or not (c_raw is Array) or (c_raw.size() != 2 and c_raw.size() != 4):
		return null
		
	var a_int: int
	if typeof(a) == TYPE_INT:
		a_int = a
	elif typeof(a) == TYPE_FLOAT:
		a_int = int(a)
	elif typeof(a) == TYPE_STRING and (a as String).is_valid_int():
		a_int = int(a)
	else:
		return null
	
	if a_int < 0 or a_int >= c_raw.size():
		return null
		
	var cleaned: PackedStringArray = []
	for x in c_raw:
		var s := str(x).strip_edges()
		if s.is_empty(): return null
		cleaned.append(s)
		
	var item := QuizItem.new()
	item.q = q
	item.c = cleaned
	item.a = a_int
	item.e = e
	item.src = src
	return item

func compose_prompt(subject: String, grade: int, difficulty: String, count: int, history: Array[String]) -> String:
	var prompt = "あなたは教員用クイズ生成AIです。\n"
	prompt += "以下の条件に従って、JSON形式でクイズ問題を出力してください。\n\n"
	prompt += "【条件】\n"
	prompt += "- 対象: 小学%d年生の%s\n" % [grade, subject]
	if not difficulty.is_empty():
		prompt += "- 難易度: %s\n" % difficulty
	prompt += "- 問題数: %d問\n" % count
	prompt += "- 形式: 4択 または 2択\n"
	prompt += "- 出力は配列のみのJSON（キーなし）としてください。\n\n"

	# 難しいモード用の追加指示
	if difficulty == "難しい":
		prompt += "【重要：難しい難易度における選択肢の作り方】\n"
		prompt += "この難易度では、不正解の選択肢（ダミー選択肢）を非常に紛らわしく作成してください。\n"
		prompt += "以下のルールを必ず守ること：\n"
		prompt += "- 不正解の選択肢は、正解と非常に似た値・表現にすること\n"
		prompt += "- 計算問題の場合：正解に±1〜±3程度の近い数値や、よくある計算ミスの結果を選択肢に含めること\n"
		prompt += "- 知識問題の場合：同じカテゴリに属する紛らわしい用語・概念を選択肢に含めること\n"
		prompt += "- 「明らかに違う」選択肢は絶対に入れないこと（例：桁が全く違う数値、無関係な単語）\n"
		prompt += "- 児童がよく間違える「典型的な誤答」を選択肢に含めること\n"
		prompt += "- 例：正解が「42」なら、「40」「43」「48」など近い数値をダミーにする\n"
		prompt += "- 例：正解が「光合成」なら、「呼吸」「蒸散」「吸水」など同分野の用語をダミーにする\n\n"

	if history.size() > 0:
		prompt += "【注意】以下の問題は既に出題済なので、重複しないようにしてください:\n"
		var max_h = min(15, history.size())
		for i in range(max_h):
			prompt += "- " + history[history.size() - 1 - i] + "\n"
		prompt += "\n"
	
	prompt += "【JSONフォーマット例（必ず下記のキー構成にすること）】\n"
	prompt += "[\n  {\n"
	prompt += "    \"q\": \"問題文\",\n"
	prompt += "    \"c\": [\"選択肢1\", \"選択肢2\", \"選択肢3\", \"選択肢4\"],\n"
	prompt += "    \"a\": 0, // 正解のインデックス(0から開始)\n"
	prompt += "    \"e\": \"解説文\"\n"
	prompt += "  }\n]\n"
	return prompt

func fetch_quiz_parallel(subject: String, grade: int, difficulty: String, count: int, history: Array[String]) -> void:
	var prompt := compose_prompt(subject, grade, difficulty, count, history)
	
	# We run Gemini and OpenAI concurrently. We'll wait until both are done
	# or at least collect whatever finishes within 10 seconds.
	var results: Array[QuizItem] = []
	var expected_calls: int = 2
	var completed_calls: int = 0
	
	var on_complete = func(items: Array[QuizItem]):
		results.append_array(items)
		completed_calls += 1
		if completed_calls >= expected_calls:
			_dedup_and_emit(results)
	
	var timer := get_tree().create_timer(10.0)
	timer.timeout.connect(func():
		if completed_calls < expected_calls:
			# Force emit on timeout
			completed_calls = 999 
			_dedup_and_emit(results)
	)
	
	_fetch_gemini(prompt, on_complete)
	_fetch_openai(prompt, on_complete)

func _dedup_and_emit(items: Array[QuizItem]) -> void:
	var unique: Array[QuizItem] = []
	var seen := {}
	items.shuffle()
	for q in items:
		if seen.has(q.q): continue
		seen[q.q] = true
		unique.append(q)
	fetch_completed.emit(unique)

func _fetch_gemini(prompt: String, callback: Callable) -> void:
	var key := ApiStatusAutoload.get_env("GOOGLE_API_KEY")
	if key.is_empty():
		key = ApiStatusAutoload.get_env("GEMINI_API_KEY")
	if key.is_empty():
		callback.call([])
		return
		
	var model := ApiStatusAutoload.gemini_model
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [model, key]
	
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 15.0
	
	var body := JSON.stringify({
		"contents": [{"parts": [{"text": prompt}]}],
		"generationConfig": {"temperature": 0.45, "responseMimeType": "application/json"}
	})
	
	http.request_completed.connect(func(result: int, response_code: int, _h, b: PackedByteArray):
		var out: Array[QuizItem] = []
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.parse_string(b.get_string_from_utf8())
			if json is Dictionary and json.has("candidates"):
				var text: String = json["candidates"][0]["content"]["parts"][0].get("text", "")
				var raw_arr = extract_quizzes_from_text(text)
				for r in raw_arr:
					var p = normalize_single(r, "GEMINI")
					if p: out.append(p)
		http.queue_free()
		callback.call(out)
	)
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func _fetch_openai(prompt: String, callback: Callable) -> void:
	var key := ApiStatusAutoload.get_env("OPENAI_API_KEY")
	if key.is_empty():
		callback.call([])
		return
		
	var model := ApiStatusAutoload.get_env("OPENAI_FAST_MODEL", "gpt-4o-mini")
	var url := "https://api.openai.com/v1/chat/completions"
	
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 15.0
	
	var body := JSON.stringify({
		"model": model,
		"messages": [{"role": "user", "content": prompt}],
		"temperature": 0.45
	})
	
	http.request_completed.connect(func(result: int, response_code: int, _h, b: PackedByteArray):
		var out: Array[QuizItem] = []
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.parse_string(b.get_string_from_utf8())
			if json is Dictionary and json.has("choices"):
				var text: String = json["choices"][0]["message"].get("content", "")
				var raw_arr = extract_quizzes_from_text(text)
				for r in raw_arr:
					var p = normalize_single(r, "OPENAI")
					if p: out.append(p)
		http.queue_free()
		callback.call(out)
	)
	http.request(url, ["Content-Type: application/json", "Authorization: Bearer " + key], HTTPClient.METHOD_POST, body)

func fetch_explanation(subject: String, grade: int, quiz_q: String, quiz_c: PackedStringArray, quiz_a: int, callback: Callable) -> void:
	var key := ApiStatusAutoload.get_env("GOOGLE_API_KEY")
	if key.is_empty():
		key = ApiStatusAutoload.get_env("GEMINI_API_KEY")
	if key.is_empty():
		callback.call("解説を取得できませんでした")
		return
		
	var model := ApiStatusAutoload.gemini_model
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [model, key]
	
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 10.0
	
	var q_str := "問題: " + quiz_q + "\n"
	q_str += "選択肢: " + ", ".join(quiz_c) + "\n"
	q_str += "正解: " + quiz_c[quiz_a] + "\n"
	q_str += "この正解となる理由を、小学" + str(grade) + "年生向けに15文字以内で簡潔に説明してください。出力は解説のテキストのみにしてください。"
	
	var body := JSON.stringify({
		"contents": [{"parts": [{"text": q_str}]}],
		"generationConfig": {"temperature": 0.2}
	})
	
	http.request_completed.connect(func(result: int, response_code: int, _h, b: PackedByteArray):
		var ans := "解説を取得できませんでした"
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.parse_string(b.get_string_from_utf8())
			if json is Dictionary and json.has("candidates"):
				var text: String = json["candidates"][0]["content"]["parts"][0].get("text", "")
				ans = text.strip_edges().trim_prefix('"').trim_suffix('"').strip_edges()
		http.queue_free()
		callback.call(ans)
	)
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

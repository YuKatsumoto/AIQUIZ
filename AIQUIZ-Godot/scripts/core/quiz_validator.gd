extends Node
class_name QuizValidator

## 2段階バリデーションパイプライン
## 生成された問題を Flash モデルで検証し、不合格なものを除外する。
## チェック項目:
##  - 正解が本当に正しいか（独立に解かせて一致確認）
##  - 問題文・選択肢の文字数制約
##  - 選択肢の重複チェック
##  - 学年レベルの適正さ

signal validation_completed(valid: Array[QuizItem], invalid_reasons: Array[String])

const MAX_RETRY: int = 2
const FLASH_MODEL: String = "gemini-3.6-flash"
const THINKING_VALIDATION: String = "low"

## ルールベースのバリデーション（即時・無料）
func validate_rules(items: Array[QuizItem]) -> Dictionary:
	var valid: Array[QuizItem] = []
	var invalid: Array[QuizItem] = []
	var reasons: Array[String] = []
	
	for item in items:
		var issues: PackedStringArray = []

		# 文字化けチェック（UTF-8デコード失敗による置換文字 U+FFFD を含む問題は破棄）
		if _has_mojibake(item.q):
			issues.append("問題文に文字化け(�)を含む")
		for i in range(item.c.size()):
			if _has_mojibake(item.c[i]):
				issues.append("選択肢%dに文字化け(�)を含む" % i)
		if _has_mojibake(item.e):
			# 解説の文字化けは問題本体を捨てず解説だけクリアする
			item.e = ""

		# 問題文の文字数チェック
		if item.q.length() > 60:
			issues.append("問題文が%d文字（60文字超過）" % item.q.length())
		
		# 選択肢の文字数チェック
		for i in range(item.c.size()):
			if item.c[i].length() > 20:
				issues.append("選択肢%dが%d文字（20文字超過）" % [i, item.c[i].length()])
		
		# 正解インデックスの範囲チェック
		if item.a < 0 or item.a >= item.c.size():
			issues.append("正解インデックス%dが範囲外（選択肢数%d）" % [item.a, item.c.size()])
		
		# 選択肢の重複チェック
		var seen := {}
		for i in range(item.c.size()):
			var normalized := item.c[i].strip_edges().to_lower()
			if seen.has(normalized):
				issues.append("選択肢%dと%dが重複" % [seen[normalized], i])
			seen[normalized] = i
		
		# 選択肢数チェック (2 or 4)
		if item.c.size() != 2 and item.c.size() != 4:
			issues.append("選択肢数が%d（2か4のみ許可）" % item.c.size())
		
		# 空文字チェック
		if item.q.strip_edges().is_empty():
			issues.append("問題文が空")
		for i in range(item.c.size()):
			if item.c[i].strip_edges().is_empty():
				issues.append("選択肢%dが空" % i)
		
		if issues.is_empty():
			valid.append(item)
		else:
			invalid.append(item)
			reasons.append("%s → %s" % [item.q.left(30), ", ".join(issues)])
	
	return {"valid": valid, "invalid": invalid, "reasons": reasons}


## 文字化け（UTF-8置換文字 U+FFFD = "�"）を含むかどうか
func _has_mojibake(text: String) -> bool:
	return text.contains("�")


## LLMベースの正解検証（Flash で独立に解かせる）
func validate_answers_llm(items: Array[QuizItem], subject: String, grade: int,
		callback: Callable) -> void:
	if items.is_empty():
		callback.call(items, [])
		return
	
	var url := ApiStatusAutoload.gemini_endpoint(FLASH_MODEL)
	if url.is_empty():
		callback.call(items, [])
		return
	
	# Build the verification prompt
	var quiz_data := []
	for i in range(items.size()):
		var item := items[i]
		quiz_data.append({
			"id": i,
			"q": item.q,
			"c": Array(item.c),
			"claimed_answer": item.a
		})
	
	var prompt := "あなたは小学校の教員です。以下のクイズ問題について、正解が正しいかを検証してください。\n"
	prompt += "対象: 小学%d年生の%s\n\n" % [grade, subject]
	prompt += "各問題について:\n"
	prompt += "1. 問題を自分で解いて、正しい答えのインデックスを特定してください\n"
	prompt += "2. claimed_answer（AIが主張する正解）が正しいか判定してください\n"
	prompt += "3. 問題が小学%d年生の学習範囲として適切かも判定してください\n\n" % grade
	prompt += "以下のJSON配列で出力（マークダウン不要）:\n"
	prompt += "[{\"id\": 0, \"correct_answer\": 実際の正解インデックス, \"claimed_ok\": true/false, \"grade_ok\": true/false, \"issue\": \"問題があれば理由\"}]\n\n"
	prompt += "問題データ:\n"
	prompt += JSON.stringify(quiz_data, "  ")
	
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 15.0
	
	var body := JSON.stringify({
		"contents": [{"parts": [{"text": prompt}]}],
		"generationConfig": {
			"temperature": 0.1,
			"responseMimeType": "application/json",
			"thinkingConfig": {"thinkingLevel": THINKING_VALIDATION}
		}
	})
	
	http.request_completed.connect(func(result: int, response_code: int, _h, b: PackedByteArray):
		var valid_items: Array[QuizItem] = []
		var invalid_reasons: Array[String] = []
		
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.parse_string(b.get_string_from_utf8())
			if json is Dictionary and json.has("candidates"):
				var text: String = json["candidates"][0]["content"]["parts"][0].get("text", "")
				var results = _parse_validation_results(text)
				
				for i in range(items.size()):
					var item := items[i]
					var check = _find_result_for_id(results, i)
					
					if check == null:
						# No validation result, pass through
						item.validated = true
						valid_items.append(item)
					elif check.get("claimed_ok", true) and check.get("grade_ok", true):
						item.validated = true
						valid_items.append(item)
					else:
						var issue: String = check.get("issue", "不明な問題")
						invalid_reasons.append("%s → %s" % [item.q.left(30), issue])
						
						# If the correct answer is different, try to fix it
						if not check.get("claimed_ok", true):
							var correct_idx = check.get("correct_answer", -1)
							if typeof(correct_idx) == TYPE_FLOAT:
								correct_idx = int(correct_idx)
							if correct_idx >= 0 and correct_idx < item.c.size():
								# Fix the answer and include the item
								item.a = correct_idx
								item.validated = true
								valid_items.append(item)
								invalid_reasons[invalid_reasons.size() - 1] += "（正解を修正して採用）"
								print("[QuizValidator] Fixed answer: %s → %d" % [item.q.left(30), correct_idx])
		else:
			# Validation failed, pass all through rather than blocking
			valid_items = items
			print("[QuizValidator] LLM validation failed (code=%d), passing all items through" % response_code)
		
		http.queue_free()
		callback.call(valid_items, invalid_reasons)
	)
	http.request(url, ApiStatusAutoload.get_proxy_headers(), HTTPClient.METHOD_POST, body)


func _parse_validation_results(text: String) -> Array:
	text = text.strip_edges()
	if text.begins_with("```json"): text = text.substr(7)
	elif text.begins_with("```"): text = text.substr(3)
	if text.ends_with("```"): text = text.substr(0, text.length() - 3)
	text = text.strip_edges()
	var json := JSON.new()
	if json.parse(text) == OK:
		var d = json.get_data()
		if d is Array: return d
	return []


func _find_result_for_id(results: Array, target_id: int) -> Variant:
	for r in results:
		if not r is Dictionary:
			continue
		var rid = r.get("id", -1)
		if typeof(rid) == TYPE_FLOAT:
			rid = int(rid)
		if typeof(rid) == TYPE_STRING and (rid as String).is_valid_int():
			rid = int(rid)
		if rid == target_id:
			return r
	return null

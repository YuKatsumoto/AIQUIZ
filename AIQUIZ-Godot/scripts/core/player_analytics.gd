extends Node
class_name PlayerAnalytics

## プレイヤー行動分析モジュール
## 回答時間・正答率・誤答パターンから問題品質シグナルを抽出する

const SAVE_PATH := "user://player_analytics.json"
const MAX_ENTRIES := 500

## 各問題の行動データ
## {q: String, response_time: float, correct: bool, chosen: int, 
##  subject: String, grade: int, difficulty: String, ts: int}
var entries: Array[Dictionary] = []

## 集計キャッシュ: "subject_grade_difficulty" -> {total: int, correct_count: int, ...}
var _stats_cache: Dictionary = {}
var _cache_dirty: bool = true

func _ready() -> void:
	_load()


# ── データ記録 ──

func record(quiz: QuizItem, response_time: float, correct: bool, 
		chosen_index: int, subject: String, grade: int, difficulty: String) -> void:
	var entry := {
		"q": quiz.q,
		"response_time": snappedf(response_time, 0.01),
		"correct": correct,
		"chosen": chosen_index,
		"answer": quiz.a,
		"num_choices": quiz.c.size(),
		"src": quiz.src,
		"subject": subject,
		"grade": grade,
		"difficulty": difficulty,
		"ts": int(Time.get_unix_time_from_system())
	}
	entries.append(entry)
	_cache_dirty = true
	
	# Limit entries
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)
	
	_save()
	_send_to_firebase(entry)

func _send_to_firebase(entry: Dictionary) -> void:
	var db_url := ApiStatusAutoload.get_env("FIREBASE_DB_URL", "")
	if db_url.is_empty():
		return
	
	var url := "%s/telemetry/sessions.json" % db_url.trim_suffix("/")
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 5.0
	
	http.request_completed.connect(func(result: int, response_code: int, _headers, _body):
		http.queue_free()
	)
	
	var err := http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(entry))
	if err != OK:
		http.queue_free()


# ── 品質シグナル抽出 ──

## 最近の問題の品質シグナルを取得
## Returns: {"avg_time": float, "accuracy": float, "suspicious_count": int,
##           "too_easy": Array[String], "too_hard": Array[String], 
##           "good_difficulty": Array[String]}
func get_quality_signals(subject: String, grade: int, difficulty: String, 
		limit: int = 50) -> Dictionary:
	var filtered := _filter_entries(subject, grade, difficulty, limit)
	
	if filtered.is_empty():
		return {
			"avg_time": 0.0, "accuracy": 0.0, "suspicious_count": 0,
			"too_easy": [] as Array[String], "too_hard": [] as Array[String],
			"good_difficulty": [] as Array[String]
		}
	
	var total_time: float = 0.0
	var correct_count: int = 0
	var too_easy: Array[String] = []
	var too_hard: Array[String] = []
	var good_difficulty: Array[String] = []
	var suspicious_count: int = 0
	
	# 問題ごとに集計
	var question_stats: Dictionary = {} # q -> {correct: int, total: int, times: Array}
	for e in filtered:
		var q: String = e["q"]
		if not question_stats.has(q):
			question_stats[q] = {"correct": 0, "total": 0, "times": []}
		question_stats[q]["total"] += 1
		if e["correct"]:
			question_stats[q]["correct"] += 1
		question_stats[q]["times"].append(e["response_time"])
		
		total_time += e["response_time"]
		if e["correct"]:
			correct_count += 1
	
	var avg_time: float = total_time / filtered.size()
	var accuracy: float = float(correct_count) / filtered.size()
	
	# 問題ごとの品質判定
	for q: String in question_stats:
		var stats: Dictionary = question_stats[q]
		if stats["total"] < 1:
			continue
		var q_accuracy: float = float(stats["correct"]) / stats["total"]
		var avg_response: float = 0.0
		for t: float in stats["times"]:
			avg_response += t
		avg_response /= stats["times"].size()
		
		# 品質判定
		if q_accuracy >= 1.0 and avg_response < 1.5:
			# 全員正解 + 即答 → 簡単すぎる
			too_easy.append(q)
			suspicious_count += 1
		elif q_accuracy <= 0.0 and stats["total"] >= 1:
			# 全員不正解 → 難しすぎるか正解が間違い
			too_hard.append(q)
			suspicious_count += 1
		elif q_accuracy >= 0.3 and q_accuracy <= 0.8 and avg_response >= 2.0 and avg_response <= 10.0:
			# 適度な正答率 + 適度な回答時間 → 良問
			good_difficulty.append(q)
	
	return {
		"avg_time": avg_time,
		"accuracy": accuracy,
		"suspicious_count": suspicious_count,
		"too_easy": too_easy,
		"too_hard": too_hard,
		"good_difficulty": good_difficulty
	}


## プロンプト注入用のフィードバック文字列を生成
func get_prompt_feedback(subject: String, grade: int, difficulty: String) -> String:
	var signals := get_quality_signals(subject, grade, difficulty)
	var feedback := ""
	
	if signals["too_easy"].size() > 0:
		feedback += "【プレイヤーデータより：簡単すぎた問題（即答で全員正解）】\n"
		for i in range(mini(signals["too_easy"].size(), 3)):
			feedback += "  × %s\n" % signals["too_easy"][i]
		feedback += "→ 上記のような自明な問題は避けてください\n\n"
	
	if signals["too_hard"].size() > 0:
		feedback += "【プレイヤーデータより：全員不正解だった問題（正解が間違い or 難しすぎ）】\n"
		for i in range(mini(signals["too_hard"].size(), 3)):
			feedback += "  ⚠ %s\n" % signals["too_hard"][i]
		feedback += "→ 正解が確実に正しいことを必ず確認してください\n\n"
	
	if signals["good_difficulty"].size() > 0:
		feedback += "【プレイヤーデータより：良い難易度だった問題（参考にしてください）】\n"
		for i in range(mini(signals["good_difficulty"].size(), 3)):
			feedback += "  ✓ %s\n" % signals["good_difficulty"][i]
		feedback += "\n"
	
	return feedback


# ── 永続化 ──

func _filter_entries(subject: String, grade: int, difficulty: String, 
		limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# 新しい順に走査
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if e.get("subject", "") == subject and e.get("grade", 0) == grade \
				and e.get("difficulty", "") == difficulty:
			result.append(e)
			if result.size() >= limit:
				break
	return result


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(entries, "  "))


func _load() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var json = JSON.parse_string(f.get_as_text())
			if json is Array:
				for item in json:
					if item is Dictionary:
						entries.append(item)

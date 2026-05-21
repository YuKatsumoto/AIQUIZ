extends Node
class_name FirebaseRatings

## Firebase Realtime Database に問題評価データを送信するモジュール
## REST API (POST) で非同期送信。失敗してもゲームをブロックしない。

var _db_url: String = ""
var _ratings_path: String = "quiz_ratings/shared"

func _ready() -> void:
	_db_url = ApiStatusAutoload.get_env("FIREBASE_DB_URL", "")
	_ratings_path = ApiStatusAutoload.get_env("FIREBASE_RATINGS_PATH", "quiz_ratings/shared")
	if _db_url.is_empty():
		push_warning("[FirebaseRatings] FIREBASE_DB_URL is not set in .env")
	else:
		print("[FirebaseRatings] Ready — DB: %s / Path: %s" % [_db_url, _ratings_path])


func send_rating(quiz: QuizItem, good: bool, subject: String, grade: int, difficulty: String, reason: String = "") -> void:
	"""Send a quiz rating to Firebase Realtime Database."""
	if _db_url.is_empty():
		push_warning("[FirebaseRatings] Cannot send rating: FIREBASE_DB_URL not configured")
		return
	if not quiz:
		return

	var url: String = "%s/%s.json" % [_db_url.trim_suffix("/"), _ratings_path]

	var payload := {
		"q": quiz.q,
		"c": Array(quiz.c),
		"a": quiz.a,
		"e": quiz.e,
		"good": good,
		"subject": subject,
		"grade": grade,
		"difficulty": difficulty,
		"src": quiz.src,
		"reason": reason,
		"ts": int(Time.get_unix_time_from_system())
	}

	var body := JSON.stringify(payload)

	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 10.0

	http.request_completed.connect(func(result: int, response_code: int, _headers, response_body: PackedByteArray):
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			print("[FirebaseRatings] Rating sent successfully: %s (%s)" % [
				quiz.q.left(30), "good" if good else "bad"
			])
		else:
			push_warning("[FirebaseRatings] Failed to send rating: result=%d code=%d" % [result, response_code])
			if response_body.size() > 0:
				push_warning("[FirebaseRatings] Response: %s" % response_body.get_string_from_utf8().left(200))
		http.queue_free()
	)

	var err := http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("[FirebaseRatings] HTTP request failed to start: %d" % err)
		http.queue_free()

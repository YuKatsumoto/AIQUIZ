extends Node
class_name FirebaseRatings

## 問題評価を永続アウトボックスへ渡す互換ファサード。
## 実際の送信は FirebaseQuizCache が Cloud Run 経由で行い、従来の
## quiz_ratings/shared と共有問題バンクを同じ評価イベントから更新する。

func _ready() -> void:
	print("[FirebaseRatings] Ready — durable proxy-backed quiz bank outbox")


func send_rating(quiz: QuizItem, good: bool, subject: String, grade: int, difficulty: String, reason: String = "") -> void:
	"""Queue a quiz rating without blocking gameplay."""
	if quiz == null:
		return
	if QuizManager.firebase_quiz_cache == null:
		push_warning("[FirebaseRatings] Quiz bank cache service is unavailable")
		return
	QuizManager.firebase_quiz_cache.queue_evaluation(
		quiz, good, subject, grade, difficulty, reason
	)

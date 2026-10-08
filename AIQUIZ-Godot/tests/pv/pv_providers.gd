extends RefCounted

## Stand-ins for the PV runs: a quiz source that hands out real Gemini-written questions
## (tests/pv/pv_quizzes.json) a few at a time, as the online generator does, and a rating
## sink that never reaches Firebase.

const QUIZZES := "res://tests/pv/pv_quizzes.json"


## Delivers its questions one by one: the first after first_delay_frames, then one every
## interval_frames. No network and no bank; the order is the authored one. While `held` it
## delivers nothing (the run releases it once the world is on screen, so the arrivals are seen).
class GeneratingProvider extends QuizProvider:
	var items: Array[QuizItem] = []
	var first_delay_frames := 50
	var interval_frames := 26
	var delivered := 0
	var held := false
	var _start_frame := -1

	func release() -> void:
		held = false
		_start_frame = Engine.get_process_frames()

	func _load_bank() -> Dictionary:
		return {}

	func begin_round(_subject: String, _grade: int, _difficulty: String, _mode: String, _target_count: int) -> void:
		delivered = 0
		if not held:
			_start_frame = Engine.get_process_frames()

	func get_quizzes(_subject: String, _grade: int, _difficulty: String, _mode: String, count: int,
			_exclude_texts: Array[String] = []) -> Array[QuizItem]:
		var out: Array[QuizItem] = []
		if held:
			return out
		if _start_frame < 0:
			_start_frame = Engine.get_process_frames()
		var elapsed := Engine.get_process_frames() - _start_frame - first_delay_frames
		var due := 0 if elapsed < 0 else mini(items.size(), elapsed / maxi(1, interval_frames) + 1)
		while delivered < due and out.size() < count:
			out.append(items[delivered])
			delivered += 1
		return out

	func submit_result(_quiz: QuizItem, _correct: bool) -> void:
		pass


## Swallows the history panel's good/bad ratings.
class RatingsStub extends FirebaseRatings:
	var sent := 0

	func _ready() -> void:
		pass

	func send_rating(_quiz: QuizItem, _good: bool, _subject: String, _grade: int, _difficulty: String, _reason: String = "") -> void:
		sent += 1


## {subject, grade, difficulty, items: Array[QuizItem]} for a set in pv_quizzes.json.
static func load_set(set_name: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(QUIZZES))
	var entry: Dictionary = data[set_name]
	var items: Array[QuizItem] = []
	for raw: Dictionary in entry.items:
		var item := QuizItem.create(str(raw.q), PackedStringArray(raw.c), int(raw.a), str(raw.e), "GEMINI_POOL")
		item.estimated_seconds = 4.0
		items.append(item)
	return {"subject": str(entry.subject), "grade": int(entry.grade), "difficulty": str(entry.difficulty), "items": items}

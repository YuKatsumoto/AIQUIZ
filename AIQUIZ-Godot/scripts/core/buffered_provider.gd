extends QuizProvider
class_name BufferedQuizProvider

var offline_provider: QuizProvider
var online_fetcher: OnlineFetch

var buffer: Array[QuizItem] = []
var inflight: int = 0
var target_count: int = 10
var yielded_count: int = 0

var current_subject: String = "算数"
var current_grade: int = 3
var current_difficulty: String = "普通"
var current_mode: String = Constants.MODE_TEN
var is_active_round: bool = false
var llm_mode: String = "OFFLINE"

var recent_questions: Array[String] = []
var play_history: Array[String] = []

var _poll_timer: Timer

func _init() -> void:
	super._init()

func _ready() -> void:
	offline_provider = QuizProvider.new("res://offline_bank.json")
	add_child(offline_provider)
	
	online_fetcher = OnlineFetch.new()
	online_fetcher.fetch_completed.connect(_on_fetch_completed)
	add_child(online_fetcher)
	
	ApiStatusAutoload.set_offline_count(offline_provider.total_count())

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer)

func total_count() -> int:
	return offline_provider.total_count()

func set_llm_mode(mode: String) -> void:
	llm_mode = "ONLINE" if mode.to_upper() == "ONLINE" else "OFFLINE"

func begin_round(subject: String, grade: int, difficulty: String,
		mode: String, t_count: int) -> void:
	current_subject = subject
	current_grade = grade
	current_difficulty = difficulty
	current_mode = mode
	target_count = t_count
	is_active_round = true
	
	buffer.clear()
	inflight = 0
	yielded_count = 0
	recent_questions.clear()
	play_history.clear()

func end_round() -> void:
	is_active_round = false

func submit_result(quiz: QuizItem, _correct: bool) -> void:
	if quiz and quiz.q:
		play_history.append(quiz.q)
		if play_history.size() > 90:
			play_history.pop_front()

func _target_buffer_size() -> int:
	return 10 if current_mode == Constants.MODE_TEN else 6

func _worker_should_fill() -> bool:
	if not is_active_round:
		return false
		
	var pending = buffer.size() + inflight
	if current_mode == Constants.MODE_TEN:
		var needed = max(0, target_count - yielded_count)
		if pending >= needed:
			return false
	return pending < _target_buffer_size()

func _on_poll() -> void:
	if not _worker_should_fill():
		return
	
	inflight += 1
	var fetch_count := 3
	if current_mode == Constants.MODE_TEN:
		fetch_count = 5
		
	if llm_mode == "ONLINE" and (ApiStatusAutoload.gemini_key_set or ApiStatusAutoload.openai_key_set):
		online_fetcher.fetch_quiz_parallel(current_subject, current_grade, current_difficulty, fetch_count, play_history)
	else:
		# Offline fallback
		var b_size := 2
		if current_mode == Constants.MODE_TEN:
			b_size = clampi(target_count, 6, 10)
		var out = offline_provider.get_quizzes(current_subject, current_grade, current_difficulty, current_mode, b_size)
		_on_fetch_completed(out)

func _on_fetch_completed(quizzes: Array[QuizItem]) -> void:
	inflight = max(0, inflight - 1)
	
	var accepted := false
	for q in quizzes:
		# Very naive deduplication
		var is_sim := false
		for rq in recent_questions:
			if rq == q.q:
				is_sim = true
				break
		if is_sim:
			continue
			
		recent_questions.append(q.q)
		if recent_questions.size() > 80:
			recent_questions.pop_front()
		buffer.append(q)
		accepted = true

func get_quizzes(_subject: String, _grade: int, _difficulty: String,
		_mode: String, count: int) -> Array[QuizItem]:
	var out: Array[QuizItem] = []
	while buffer.size() > 0 and out.size() < count:
		out.append(buffer.pop_front())
	yielded_count += out.size()
	return out

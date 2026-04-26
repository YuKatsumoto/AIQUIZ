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
var llm_mode: String = "ONLINE"

var recent_questions: Array[String] = []
var play_history: Array[String] = []

## オフラインの緊急キャッシュ — オンライン生成が間に合わない時の保険
var _emergency_cache: Array[QuizItem] = []
const EMERGENCY_CACHE_SIZE: int = 5

var _poll_timer: Timer

func _init() -> void:
	super._init()

func _ready() -> void:
	offline_provider = QuizProvider.new("res://offline_bank.json")
	add_child(offline_provider)
	
	online_fetcher = OnlineFetch.new()
	online_fetcher.fetch_completed.connect(_on_fetch_completed)
	online_fetcher.fetch_partial.connect(_on_fetch_partial)
	add_child(online_fetcher)
	
	ApiStatusAutoload.set_offline_count(offline_provider.total_count())

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.25  # Slightly faster polling (was 0.3)
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
	_emergency_cache.clear()
	
	# ラウンド開始時にオフラインの緊急キャッシュを事前準備（10問・エンドレス共通）
	_prepare_emergency_cache()
	
	# ★★★ 速度最適化: ポーリング待ちを廃止し、即座に最初のリクエストを発火 ★★★
	_fire_immediate_fetch()

func end_round() -> void:
	is_active_round = false

func submit_result(quiz: QuizItem, _correct: bool) -> void:
	if quiz and quiz.q:
		play_history.append(quiz.q)
		if play_history.size() > 90:
			play_history.pop_front()

## エンドレスモードのバッファ目標サイズ
## 15問を確保 — 1問5秒でプレイしても75秒分のストック
func _target_buffer_size() -> int:
	return 10 if current_mode == Constants.MODE_TEN else 15

## 補充リクエストを飛ばすべきかの判定
func _worker_should_fill() -> bool:
	if not is_active_round:
		return false
	# エンドレスモード: 最大4つの同時リクエスト
	# 10問モード: fetch_quiz_parallel内部で4並列管理するのでproviderレベルは1で十分
	var max_inflight: int = 4 if current_mode == Constants.MODE_ENDLESS else 1
	if inflight >= max_inflight:
		return false
	var per_batch_estimate: int = 15  # 4バッチ×4問 − dedup ≈ 15問期待
	var pending = buffer.size() + inflight * per_batch_estimate
	if current_mode == Constants.MODE_TEN:
		var needed = max(0, target_count - yielded_count)
		if pending >= needed:
			return false
	return pending < _target_buffer_size()

## begin_round()から即座に呼ばれる高速初回フェッチ
## ポーリングタイマーの0.25秒待ちをスキップしてAPIリクエストを即発火
func _fire_immediate_fetch() -> void:
	if not _worker_should_fill():
		return
	_on_poll()  # 即座に最初のリクエストを発火

func _on_poll() -> void:
	if not _worker_should_fill():
		return
	
	inflight += 1
	# エンドレス: 7問ずつ、10問モード: 残り必要数を一括リクエスト
	var fetch_count: int
	if current_mode == Constants.MODE_ENDLESS:
		fetch_count = 7
	else:
		fetch_count = clampi(target_count - yielded_count - buffer.size(), 2, 10)
		
	if llm_mode == "ONLINE" and (ApiStatusAutoload.gemini_key_set or ApiStatusAutoload.openai_key_set):
		# 10問モード: バッファ内の既存問題もhistoryに含め、LLMに「既出」と伝える
		var full_history: Array[String] = play_history.duplicate()
		if current_mode == Constants.MODE_TEN:
			for bq in buffer:
				if bq.q not in full_history:
					full_history.append(bq.q)
			for rq in recent_questions:
				if rq not in full_history:
					full_history.append(rq)
		var is_ten: bool = current_mode == Constants.MODE_TEN
		online_fetcher.fetch_quiz_parallel(current_subject, current_grade, current_difficulty, fetch_count, full_history, is_ten)
	else:
		# Offline fallback
		var b_size := 6
		if current_mode == Constants.MODE_TEN:
			b_size = clampi(target_count, 6, 10)
		var out = offline_provider.get_quizzes(current_subject, current_grade, current_difficulty, current_mode, b_size)
		_on_fetch_completed(out)

func _on_fetch_partial(quizzes: Array[QuizItem]) -> void:
	if quizzes.size() == 0:
		return
		
	var accepted := false
	for q in quizzes:
		# Advanced deduplication: 完全一致 + 文字列類似度 + セマンティック判定
		var is_sim := false
		for rq in recent_questions:
			# 完全一致チェック
			if rq == q.q:
				is_sim = true
				break
			# 文字列類似度チェック（閾値を厳しく: 0.75 → 0.65）
			if rq.similarity(q.q) > 0.65:
				is_sim = true
				print("[BufferedProvider] Dedup: similarity %.2f '%s' ≈ '%s'" % [rq.similarity(q.q), q.q.left(25), rq.left(25)])
				break
		if is_sim:
			continue
			
		recent_questions.append(q.q)
		if recent_questions.size() > 120:
			recent_questions.pop_front()
		buffer.append(q)
		accepted = true
	
	# 全問題が重複で弾かれた場合 → 履歴をクリアして問題を再利用可能にする
	if not accepted and quizzes.size() > 0 and buffer.size() == 0:
		recent_questions.clear()
		# 履歴クリア後、取得した問題をそのまま投入
		for q in quizzes:
			recent_questions.append(q.q)
			buffer.append(q)
			accepted = true

func _on_fetch_completed(quizzes: Array[QuizItem]) -> void:
	inflight = max(0, inflight - 1)
	_on_fetch_partial(quizzes)

func get_quizzes(_subject: String, _grade: int, _difficulty: String,
		_mode: String, count: int) -> Array[QuizItem]:
	var out: Array[QuizItem] = []
	while buffer.size() > 0 and out.size() < count:
		out.append(buffer.pop_front())
	
	# バッファが空の場合の処理（10問・エンドレス共通）
	if out.is_empty():
		# オンラインリクエストが処理中 → 空を返してPRELOADING待ちにさせる
		if inflight > 0:
			# リクエスト中なので何も返さない → game_state がPRELOADINGに遷移して待つ
			pass
		elif _emergency_cache.size() > 0:
			# リクエストもゼロ、バッファも空 → 最後の手段としてオフライン緊急キャッシュ
			var needed_from_cache := maxi(1, count - out.size())
			for _i in range(mini(needed_from_cache, _emergency_cache.size())):
				out.append(_emergency_cache.pop_front())
			print("[BufferedProvider] Emergency cache used! Gave %d, Remaining: %d" % [out.size(), _emergency_cache.size()])
			if _emergency_cache.size() < 3:
				_prepare_emergency_cache()
	
	yielded_count += out.size()
	return out


## オフライン問題から緊急用キャッシュを準備する
func _prepare_emergency_cache() -> void:
	if _emergency_cache.size() >= EMERGENCY_CACHE_SIZE:
		return
	var needed: int = EMERGENCY_CACHE_SIZE - _emergency_cache.size()
	var fallback := offline_provider.get_quizzes(
		current_subject, current_grade, current_difficulty,
		Constants.MODE_ENDLESS, needed
	)
	for q in fallback:
		_emergency_cache.append(q)
	if _emergency_cache.size() > 0:
		print("[BufferedProvider] Emergency cache prepared: %d offline questions" % _emergency_cache.size())

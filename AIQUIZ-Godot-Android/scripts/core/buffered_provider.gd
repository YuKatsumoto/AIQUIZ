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

## ラウンド間で引き継ぐ問題履歴の最大サイズ
const CROSS_ROUND_HISTORY_MAX: int = 60
const HISTORY_SAVE_PATH: String = "user://recent_quiz_history.json"

## オフラインの緊急キャッシュ — オンライン生成が間に合わない時の保険
var _emergency_cache: Array[QuizItem] = []
const EMERGENCY_CACHE_SIZE: int = 5

var _poll_timer: Timer
var _explanation_inflight: bool = false
## 解説待ちのクイズを追跡（重複リクエスト防止）
var _explanation_requested_ids: Dictionary = {}

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
	
	# ラウンド間の問題履歴をディスクから復元
	_load_cross_round_history()

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.25  # Slightly faster polling (was 0.3)
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer)

func total_count() -> int:
	return offline_provider.total_count()

func set_llm_mode(mode: String) -> void:
	llm_mode = "ONLINE" if mode.to_upper() == "ONLINE" else "OFFLINE"


func _online_api_available() -> bool:
	return ApiStatusAutoload.gemini_key_set or ApiStatusAutoload.openai_key_set


func _should_use_offline_quizzes() -> bool:
	return llm_mode != "ONLINE" or not _online_api_available()

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
	# recent_questions はクリアしない — ラウンド間で引き継いで重複を防ぐ
	play_history.clear()
	_emergency_cache.clear()
	_explanation_inflight = false
	_explanation_requested_ids.clear()
	
	# オンライン＋API利用可のときはオフライン緊急キャッシュを温めない（即オフライン化を防ぐ）
	if _should_use_offline_quizzes():
		_prepare_emergency_cache()
	else:
		_emergency_cache.clear()
	
	# ★★★ 速度最適化: ポーリング待ちを廃止し、即座に最初のリクエストを発火 ★★★
	_fire_immediate_fetch()

func end_round() -> void:
	is_active_round = false
	if is_instance_valid(online_fetcher) and online_fetcher.has_method("cancel_all"):
		online_fetcher.cancel_all()
	inflight = 0
	# プレイ中に出題した問題を recent_questions にマージして次のラウンドに引き継ぐ
	for q in play_history:
		if q not in recent_questions:
			recent_questions.append(q)
	# 上限を超えたら古いものから削除
	while recent_questions.size() > CROSS_ROUND_HISTORY_MAX:
		recent_questions.pop_front()
	# ディスクに保存
	_save_cross_round_history()

func submit_result(quiz: QuizItem, _correct: bool) -> void:
	if quiz and quiz.q:
		play_history.append(quiz.q)
		if play_history.size() > 90:
			play_history.pop_front()

## エンドレスモードのバッファ目標サイズ
## 序盤は過剰生成を防ぐため小さく(3)、長く生き残れば最大(6)まで拡張
func _target_buffer_size() -> int:
	if current_mode == Constants.MODE_TEN:
		return 10
	else:
		if yielded_count < 3:
			return 3
		elif yielded_count < 10:
			return 4
		else:
			return 6

## 補充リクエストを飛ばすべきかの判定
func _worker_should_fill() -> bool:
	if not is_active_round:
		return false
	# 10問モード: fetch_quiz_parallel内部で4並列管理するのでproviderレベルは1で十分
	# エンドレスモードでも内部で5並列管理しているため1で十分
	var max_inflight: int = 1
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
	var fetch_count: int
	if current_mode == Constants.MODE_ENDLESS:
		# 目標バッファサイズを満たすための必要最小限のみをリクエスト (最小1)
		fetch_count = maxi(1, _target_buffer_size() - buffer.size())
	else:
		fetch_count = clampi(target_count - yielded_count - buffer.size(), 2, 10)
		
	if llm_mode == "ONLINE" and _online_api_available():
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
		print(
			"[BufferedProvider] Using offline bank (llm_mode=%s, api=%s)"
			% [llm_mode, str(_online_api_available())]
		)
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
	
	# 全問題が重複で弾かれた場合のフォールバック
	# yielded_count == 0（まだ1問もプレイヤーに渡していない）場合のみ履歴をクリア
	# それ以外はオフライン緊急キャッシュに委ねる
	if not accepted and quizzes.size() > 0 and buffer.size() == 0 and yielded_count == 0:
		# 最古の履歴を半分だけ削除（完全クリアより重複リスクが低い）
		var half := recent_questions.size() / 2
		for _i in range(half):
			if recent_questions.size() > 0:
				recent_questions.pop_front()
		# 再フィルタして重複しないものだけ投入
		for q in quizzes:
			var still_dup := false
			for rq in recent_questions:
				if rq == q.q or rq.similarity(q.q) > 0.65:
					still_dup = true
					break
			if not still_dup:
				recent_questions.append(q.q)
				buffer.append(q)
				accepted = true
		# それでも空なら最後の手段で1問だけ投入
		if not accepted and quizzes.size() > 0:
			recent_questions.append(quizzes[0].q)
			buffer.append(quizzes[0])

func _on_fetch_completed(quizzes: Array[QuizItem]) -> void:
	inflight = max(0, inflight - 1)
	_on_fetch_partial(quizzes)
	# フェッチ完了時にバッファ内の解説未取得問題をまとめて解説生成
	_kick_explanation_batch()

func get_quizzes(_subject: String, _grade: int, _difficulty: String,
		_mode: String, count: int) -> Array[QuizItem]:
	var out: Array[QuizItem] = []
	while buffer.size() > 0 and out.size() < count:
		out.append(buffer.pop_front())
	
	# バッファが空の場合の処理（10問・エンドレス共通）
	if out.is_empty():
		if _should_use_offline_quizzes():
			# オフラインモード、または API 未設定時のみ緊急キャッシュを使う
			if _emergency_cache.is_empty():
				_prepare_emergency_cache()
			if _emergency_cache.size() > 0:
				var needed_from_cache := maxi(1, count - out.size())
				for _i in range(mini(needed_from_cache, _emergency_cache.size())):
					var eq = _emergency_cache.pop_front()
					eq.src = "OFFLINE_FALLBACK"
					out.append(eq)
				print(
					"[BufferedProvider] Offline/emergency cache used: %d (remaining %d)"
					% [out.size(), _emergency_cache.size()]
				)
				if _emergency_cache.size() < 3:
					_prepare_emergency_cache()
		elif inflight > 0:
			# オンライン生成待ち — 空配列のまま PRELOADING で待機
			pass
		else:
			# オンラインだが応答待ちでない＝生成失敗直後など。再リクエストを促す
			print("[BufferedProvider] Online buffer empty, waiting for next fetch (no offline fallback)")
	
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

## バッファ内の解説未取得問題に対してバックグラウンドで解説生成をキック
func _kick_explanation_batch() -> void:
	if _explanation_inflight:
		return
	if _should_use_offline_quizzes():
		return
	
	# 解説が空のオンライン生成問題を収集
	var need_explanation: Array[QuizItem] = []
	for q in buffer:
		if q.e.strip_edges().is_empty() and q.src != "OFFLINE" and not _explanation_requested_ids.has(q.q):
			need_explanation.append(q)
			_explanation_requested_ids[q.q] = true
	
	if need_explanation.is_empty():
		return
	
	_explanation_inflight = true
	print("[BufferedProvider] Kicking explanation batch for %d quizzes" % need_explanation.size())
	online_fetcher.fetch_explanations_batch(need_explanation, current_subject, current_grade)
	
	# 完了時にフラグをリセット（シグナル接続）
	if not online_fetcher.explanations_ready.is_connected(_on_explanations_ready):
		online_fetcher.explanations_ready.connect(_on_explanations_ready)

func _on_explanations_ready(_quizzes: Array[QuizItem]) -> void:
	_explanation_inflight = false
	print("[BufferedProvider] Explanations received, checking for more...")
	# まだ解説未取得の問題があれば次のバッチをキック
	_kick_explanation_batch()


## ── ラウンド間 問題履歴の永続化 ──

func _load_cross_round_history() -> void:
	if not FileAccess.file_exists(HISTORY_SAVE_PATH):
		return
	var f := FileAccess.open(HISTORY_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var json = JSON.parse_string(f.get_as_text())
	f.close()
	if json is Array:
		recent_questions.clear()
		for item in json:
			if item is String and not (item as String).is_empty():
				recent_questions.append(item as String)
		# 上限を超えたら古いものから削除
		while recent_questions.size() > CROSS_ROUND_HISTORY_MAX:
			recent_questions.pop_front()
		if recent_questions.size() > 0:
			print("[BufferedProvider] Loaded %d cross-round history entries from disk" % recent_questions.size())

func _save_cross_round_history() -> void:
	var save_data: Array[String] = []
	for q in recent_questions:
		save_data.append(q)
	var f := FileAccess.open(HISTORY_SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save_data))
		f.close()
		print("[BufferedProvider] Saved %d cross-round history entries to disk" % save_data.size())

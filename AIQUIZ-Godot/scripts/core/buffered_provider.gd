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
var recent_history_entries: Array[Dictionary] = []
var play_history: Array[String] = []

## ラウンド間で引き継ぐ問題履歴の最大サイズ（新鮮さ確保のため大きめに保持）
const CROSS_ROUND_HISTORY_MAX: int = 1000
const HISTORY_SAVE_PATH: String = "user://recent_quiz_history.json"
const MIN_REFETCH_INTERVAL_SEC: float = 1.2
const HISTORY_SAVE_DEBOUNCE_SEC: float = 0.2
## 履歴が多い条件では候補の大半が新規性ゲートで落ちるため、
## 10問プリロードの不足補充は1〜2候補だけでなく余裕を持って生成する。
const TEN_PRELOAD_MIN_CANDIDATES: int = 6

## オフラインモードで同期払い出しに使う緊急キャッシュ
var _emergency_cache: Array[QuizItem] = []
const EMERGENCY_CACHE_SIZE: int = 5

var _poll_timer: Timer
var _explanation_inflight: bool = false
## 解説待ちのクイズを追跡（重複リクエスト防止）
var _explanation_requested_ids: Dictionary = {}
## このラウンドで払い出し済みのオンライン生成クイズ（QuizItem は参照共有なので
## 解説の書き戻しや正解修正が後からでもゲーム側に反映される）
var _dispatched_items: Array[QuizItem] = []
## プリロード中でも解説バッチを先行キックする未充填問題数のしきい値
const EXPLANATION_KICK_MIN: int = 5
## 10問モードのプリロード完了後に1回だけ実行する正解一括検証
var _answer_validation_done: bool = false

## ── 出題ジャンル分散（10問モード） ──
## 1ラウンド内で同一ジャンルを出しすぎないための上限
const GENRE_CAP_PER_ROUND: int = 2
## 上限超過でバッファに入れなかった問題の控え（10問に満たない時の補充用）
var _overflow_buffer: Array[QuizItem] = []
## 直近で払い出した問題のジャンル（連続同ジャンルを避けるために追跡）
var _last_dispatched_genre: String = ""
var _dedup_retry_count: int = 0
var _fetch_scheduled: bool = false
var _last_refetch_ms: int = 0
var _history_save_scheduled: bool = false
var _initial_ten_fetch_started: bool = false
var generated_bank: GeneratedBank
var _round_candidates_seen: int = 0
var _round_candidates_blocked: int = 0
var _quality_stats_logged: bool = false

func _init() -> void:
	super._init()

func _ready() -> void:
	offline_provider = QuizProvider.new("res://offline_bank.json")
	add_child(offline_provider)
	
	online_fetcher = OnlineFetch.new()
	online_fetcher.fetch_completed.connect(_on_fetch_completed)
	online_fetcher.fetch_partial.connect(_on_fetch_partial)
	online_fetcher.explanations_ready.connect(_on_explanations_ready)
	add_child(online_fetcher)
	generated_bank = GeneratedBank.new()
	
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
	if llm_mode == "ONLINE":
		_emergency_cache.clear()
		buffer = _filter_online_only(buffer)
		_overflow_buffer = _filter_online_only(_overflow_buffer)


func _online_api_available() -> bool:
	return ApiStatusAutoload.is_proxy_available()


func _should_use_offline_quizzes() -> bool:
	return llm_mode != "ONLINE"


func _is_offline_quiz_item(q: QuizItem) -> bool:
	if q == null:
		return true
	var src := q.src.strip_edges().to_upper()
	return src == "OFFLINE" or src == "OFFLINE_FALLBACK" or src.begins_with("OFFLINE")


func _filter_online_only(items: Array[QuizItem]) -> Array[QuizItem]:
	var kept: Array[QuizItem] = []
	for q in items:
		if not _is_offline_quiz_item(q):
			kept.append(q)
	return kept

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
	_overflow_buffer.clear()
	_last_dispatched_genre = ""
	_dedup_retry_count = 0
	_fetch_scheduled = false
	_last_refetch_ms = 0
	_initial_ten_fetch_started = false
	_explanation_inflight = false
	_explanation_requested_ids.clear()
	_dispatched_items.clear()
	_answer_validation_done = false
	_round_candidates_seen = 0
	_round_candidates_blocked = 0
	_quality_stats_logged = false

	# オフライン問題は直後の同期フェッチで取得できるため、開始時の緊急キャッシュ生成は不要。
	# ここで過去履歴との意味比較を走らせると、準備画面を長時間ブロックしてしまう。
	if _should_use_offline_quizzes():
		_emergency_cache.clear()
	else:
		_emergency_cache.clear()
		buffer = _filter_online_only(buffer)
		_overflow_buffer = _filter_online_only(_overflow_buffer)
	
	# ★★★ 速度最適化: ポーリング待ちを廃止し、即座に最初のリクエストを発火 ★★★
	if llm_mode == "ONLINE" and not _online_api_available():
		print("[BufferedProvider] Online mode selected but PROXY_URL is not configured — waiting (no offline fallback)")
	elif _should_use_offline_quizzes() or _online_api_available():
		if llm_mode == "ONLINE":
			_seed_from_generated_bank()
		_fire_immediate_fetch()

func end_round() -> void:
	is_active_round = false
	_store_leftovers_to_pool()
	if is_instance_valid(online_fetcher) and online_fetcher.has_method("cancel_all"):
		online_fetcher.cancel_all()
	inflight = 0
	# ゲームオーバー画面・履歴パネル用: 払い出し済みで解説が未充填のものは
	# 駆け込みで一括充填を依頼する（cancel_all は解説リクエストを生かす）
	_flush_pending_explanations_on_end()
	# プレイ中に出題した問題を recent_history_entries にマージして次のラウンドに引き継ぐ
	for q_text: String in play_history:
		_append_history_entry(q_text, "")
	_save_cross_round_history()


## ラウンド終了時、出題済み（プレイヤーが実際に見た）問題のうち
## 解説が未充填かつ未リクエストのものをまとめて充填依頼する
func _flush_pending_explanations_on_end() -> void:
	if _should_use_offline_quizzes() or not _online_api_available():
		return
	var pending: Array[QuizItem] = []
	for q in _dispatched_items:
		if q.e.strip_edges().is_empty() \
				and not _is_offline_quiz_item(q) \
				and not _explanation_requested_ids.has(q.q):
			pending.append(q)
			_explanation_requested_ids[q.q] = true
	if pending.is_empty():
		return
	print("[BufferedProvider] End-of-round explanation flush for %d quizzes" % pending.size())
	online_fetcher.fetch_explanations_batch(pending, current_subject, current_grade)

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
	if current_mode == Constants.MODE_TEN:
		var have := yielded_count + buffer.size()
		var needed := maxi(0, target_count - have)
		if needed == 0:
			return false
		# プリロード中は inflight 見積もりで過剰判定しない（dedup で実際は少ない）
		if _is_preloading():
			return true
		var pending := buffer.size() + inflight * 15
		return pending < needed
	var per_batch_estimate: int = 15  # 4バッチ×4問 − dedup ≈ 15問期待
	var estimated_pending = buffer.size() + inflight * per_batch_estimate
	return estimated_pending < _target_buffer_size()

## begin_round()から即座に呼ばれる高速初回フェッチ
## ポーリングタイマーの0.25秒待ちをスキップしてAPIリクエストを即発火
func _fire_immediate_fetch() -> void:
	if not _worker_should_fill():
		return
	_on_poll()

func _schedule_fetch(delay_sec: float = 0.0) -> void:
	if not is_active_round or _fetch_scheduled:
		return
	if llm_mode == "ONLINE" and not _online_api_available():
		return
	var wait_sec := delay_sec
	if online_fetcher.has_method("get_rate_limit_wait_sec"):
		wait_sec = maxf(wait_sec, online_fetcher.get_rate_limit_wait_sec())
	var now_ms := Time.get_ticks_msec()
	var since_last_ms := now_ms - _last_refetch_ms
	var min_wait_ms := int(MIN_REFETCH_INTERVAL_SEC * 1000.0)
	if since_last_ms < min_wait_ms:
		wait_sec = maxf(wait_sec, float(min_wait_ms - since_last_ms) / 1000.0)
	_fetch_scheduled = true
	if wait_sec > 0.05:
		get_tree().create_timer(wait_sec).timeout.connect(func():
			_fetch_scheduled = false
			_fire_immediate_fetch()
		, CONNECT_ONE_SHOT)
	else:
		_fetch_scheduled = false
		call_deferred("_fire_immediate_fetch")

func _on_poll() -> void:
	# 補充とは独立して、解説充填と正解検証のバックグラウンド処理を進める
	_kick_explanation_batch()
	_run_answer_validation_once()
	# 失敗後の遅延フェッチを予約している間は、0.25秒タイマーから重複実行しない。
	if _fetch_scheduled:
		return

	if not _worker_should_fill():
		return

	if llm_mode == "ONLINE" and not _online_api_available():
		return
	if online_fetcher.has_method("is_rate_limited") and online_fetcher.is_rate_limited():
		return
	
	_last_refetch_ms = Time.get_ticks_msec()
	inflight += 1
	var fetch_count: int = _calculate_fetch_candidate_count()
		
	if llm_mode == "ONLINE":
		var full_history: Array[String] = _build_fetch_history()
		# 初回だけ24候補の高速並列生成。不足分の補充は重複落ちを見越して余裕を持たせる。
		var is_initial_ten := current_mode == Constants.MODE_TEN \
			and not _initial_ten_fetch_started \
			and yielded_count == 0 and _preload_buffer_count() == 0 and fetch_count >= 6
		if is_initial_ten:
			_initial_ten_fetch_started = true
		online_fetcher.fetch_quiz_parallel(
			current_subject, current_grade, current_difficulty,
			fetch_count, full_history, is_initial_ten
		)
	else:
		print("[BufferedProvider] Using offline bank (llm_mode=%s)" % llm_mode)
		var b_size := 6
		if current_mode == Constants.MODE_TEN:
			b_size = clampi(target_count, 6, 10)
		var out = offline_provider.get_quizzes(current_subject, current_grade, current_difficulty, current_mode, b_size)
		_on_fetch_completed(out)


func _calculate_fetch_candidate_count() -> int:
	if current_mode == Constants.MODE_ENDLESS:
		# 目標バッファサイズを満たすための必要最小限のみをリクエスト (最小1)
		return maxi(1, _target_buffer_size() - buffer.size())
	var missing: int = target_count - yielded_count - buffer.size()
	if current_mode == Constants.MODE_TEN and _is_preloading():
		return clampi(maxi(missing, TEN_PRELOAD_MIN_CANDIDATES), 2, 10)
	return clampi(missing, 2, 10)

func _is_preloading() -> bool:
	# yielded_count は get_quizzes 呼び出しごとに増えるため、
	# 「バッファ空」ではなく「ラウンド分が揃うまで」をプリロードとみなす
	return is_active_round and (_preload_buffer_count() + yielded_count) < target_count


func _preload_buffer_count() -> int:
	# overflow はジャンル上限超過の控えであり、10問充足には数えない。
	# 数えると同一ジャンルでプリロードが埋まって多様性要件が崩れる。
	return buffer.size()


func _needs_more_preload() -> bool:
	return _is_preloading() and _preload_buffer_count() < target_count


func _should_block_quiz(question: String, batch_accepted: Array[String], during_preload: bool) -> bool:
	# ローカルバンクでは過去ラウンド全体との意味類似判定を行わない。
	# 計算問題など同じ書式の別問題まで全拒否され、同期補充が無限再試行になるため。
	# 現在のラウンド内だけ厳密重複を防げば、同一問題の連続出題は回避できる。
	if _should_use_offline_quizzes():
		if QuizDedup.is_strict_duplicate_to_any(question, batch_accepted):
			return true
		for bq in buffer:
			if QuizDedup.is_strict_duplicate(question, bq.q):
				return true
		for ph in play_history:
			if QuizDedup.is_strict_duplicate(question, ph):
				return true
		for oq in _overflow_buffer:
			if QuizDedup.is_strict_duplicate(question, oq.q):
				return true
		return false

	var question_core := QuizDedup.extract_core_concept(question)
	if QuizDedup.is_similar_to_any_with_core(question, question_core, batch_accepted):
		return true
	if QuizDedup.is_strict_duplicate_to_any(question, recent_questions):
		return true
	if during_preload:
		# プリロード中: バッファ内・プレイ中 + 直近の cross-round 履歴（新鮮さ確保）を照合
		for bq in buffer:
			if QuizDedup.is_semantically_similar_with_cores(question, question_core, bq.q, QuizDedup.extract_core_concept(bq.q)):
				return true
		for ph in play_history:
			if QuizDedup.is_semantically_similar(question, ph):
				return true
		for oq in _overflow_buffer:
			if QuizDedup.is_semantically_similar(question, oq.q):
				return true
		if QuizDedup.is_similar_to_any_with_core(question, question_core, recent_history_entries):
			return true
		return false
	var active_texts := _collect_active_question_texts(false)
	if QuizDedup.is_strict_duplicate_to_any(question, active_texts):
		return true
	return QuizDedup.is_similar_to_any(
		question, QuizDedup.tail_texts(active_texts, QuizDedup.SEMANTIC_HISTORY_MAX)
	)


func _on_fetch_partial(quizzes: Array[QuizItem]) -> void:
	if quizzes.size() == 0:
		return

	var accepted := false
	var history_changed := false
	var batch_accepted: Array[String] = []
	var during_preload := _is_preloading()
	var surplus: Array[QuizItem] = []
	var adopted_units: Array[String] = []
	var ordered: Array[QuizItem] = []
	var rest: Array[QuizItem] = []
	for q in quizzes:
		if q == null:
			continue
		if q.genre.strip_edges().is_empty():
			q.genre = "未分類"
		if _genre_count_in_round(q.genre) == 0:
			ordered.append(q)
		else:
			rest.append(q)
	ordered.append_array(rest)

	for q in ordered:
		_round_candidates_seen += 1
		if current_mode == Constants.MODE_TEN \
				and yielded_count + _preload_buffer_count() >= target_count:
			surplus.append(q)
			continue
		if llm_mode == "ONLINE" and _is_offline_quiz_item(q):
			print("[BufferedProvider] Rejected offline quiz in online mode: '%s'" % q.q.left(30))
			continue
		if _should_block_quiz(q.q, batch_accepted, during_preload):
			_round_candidates_blocked += 1
			print("[BufferedProvider] Dedup blocked: '%s'" % q.q.left(30))
			continue
		batch_accepted.append(q.q)
		if llm_mode == "ONLINE" and _append_history_entry(q.q, q.genre):
			history_changed = true
		if current_mode == Constants.MODE_TEN \
				and _genre_count_in_round(q.genre) >= _effective_genre_cap():
			# 上限超過はプールへ。枯渇時（cap緩和後）だけ overflow で本ラウンドを埋める。
			if _dedup_retry_count >= 2 and _needs_more_preload():
				_overflow_buffer.append(q)
				accepted = true
				print("[BufferedProvider] Genre cap relaxed for '%s', queued to overflow: '%s'" % [q.genre, q.q.left(20)])
			else:
				surplus.append(q)
				print("[BufferedProvider] Genre cap reached for '%s', stored to pool: '%s'" % [q.genre, q.q.left(20)])
			continue
		buffer.append(q)
		accepted = true
		if not q.genre.is_empty() and q.genre not in adopted_units:
			adopted_units.append(q.genre)

	if history_changed:
		_schedule_history_save()
	if adopted_units.size() > 0 and is_instance_valid(online_fetcher) \
			and online_fetcher.has_method("record_adopted_units"):
		online_fetcher.record_adopted_units(current_subject, current_grade, adopted_units)
	if surplus.size() > 0 and llm_mode == "ONLINE" and generated_bank != null:
		generated_bank.store_items(surplus, current_subject, current_grade, current_difficulty)

	if accepted and online_fetcher.has_method("reset_rate_limit"):
		online_fetcher.reset_rate_limit()

	if not _quality_stats_logged and not _needs_more_preload() and current_mode == Constants.MODE_TEN:
		_log_round_quality_stats()

	# 新規性を満たさない候補は絶対に採用せず、別単元・別形式で不足分だけ再生成する。
	if not accepted and quizzes.size() > 0 and _needs_more_preload():
		_dedup_retry_count += 1
		print("[BufferedProvider] All candidates rejected by novelty gate; refilling missing questions (%d)" % _dedup_retry_count)
		_schedule_fetch()

func _on_fetch_completed(quizzes: Array[QuizItem]) -> void:
	inflight = max(0, inflight - 1)
	_on_fetch_partial(quizzes)
	# フェッチ完了時にバッファ内の解説未取得問題をまとめて解説生成
	_kick_explanation_batch()

func get_quizzes(_subject: String, _grade: int, _difficulty: String,
		_mode: String, count: int, _exclude_texts: Array[String] = []) -> Array[QuizItem]:
	var out: Array[QuizItem] = []
	# 10問モード: 連続同ジャンルを避けるようバッファを並べ替えてから払い出す
	if current_mode == Constants.MODE_TEN and buffer.size() > 1:
		_reorder_buffer_for_genre_spread()
	while buffer.size() > 0 and out.size() < count:
		var picked: QuizItem = buffer.pop_front()
		if llm_mode == "ONLINE" and _is_offline_quiz_item(picked):
			print("[BufferedProvider] Skipped offline quiz in online buffer: '%s'" % picked.q.left(30))
			continue
		_last_dispatched_genre = picked.genre
		_track_dispatched_unexplained(picked)
		out.append(picked)

	# バッファが足りない場合、ジャンル上限で控えに回した問題から補充する
	if current_mode == Constants.MODE_TEN and out.size() < count:
		var skipped: Array[QuizItem] = []
		while _overflow_buffer.size() > 0 and out.size() < count:
			var ov: QuizItem = _overflow_buffer.pop_front()
			if llm_mode == "ONLINE" and _is_offline_quiz_item(ov):
				continue
			var played := _genre_count_in_played(ov.genre, out)
			if played >= _effective_genre_cap() and _overflow_has_other_genre(ov.genre):
				skipped.append(ov)
				continue
			_last_dispatched_genre = ov.genre
			_track_dispatched_unexplained(ov)
			out.append(ov)
		for skipped_item in skipped:
			_overflow_buffer.append(skipped_item)
	
	# バッファが空の場合の処理（10問・エンドレス共通）
	if out.is_empty():
		if _should_use_offline_quizzes():
			# オフラインモードのみ緊急キャッシュを使う
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
		else:
			if inflight == 0 and _online_api_available():
				_schedule_fetch()
			# ONLINEはモードを問わず、オンライン問題が届くまで待機する。
			# オフライン問題による一時補完は行わない。
			print("[BufferedProvider] Online buffer empty, waiting for AI fetch (no offline fallback)")

	yielded_count += out.size()
	return out


## バッファ内に同一ジャンルが何問あるか数える
func _genre_count_in_buffer(genre: String) -> int:
	return _genre_count_in_round(genre)


func _genre_count_in_round(genre: String) -> int:
	var n := 0
	for q in buffer:
		if q.genre == genre:
			n += 1
	for q in _dispatched_items:
		if q.genre == genre:
			n += 1
	return n


func _genre_count_in_played(genre: String, extra: Array[QuizItem]) -> int:
	var n := 0
	for q in _dispatched_items:
		if q.genre == genre:
			n += 1
	for q in extra:
		if q.genre == genre:
			n += 1
	return n


func _overflow_has_other_genre(genre: String) -> bool:
	for q in _overflow_buffer:
		if q.genre != genre:
			return true
	return false


func _effective_genre_cap() -> int:
	if current_mode != Constants.MODE_TEN:
		return GENRE_CAP_PER_ROUND
	if _dedup_retry_count >= 2:
		return GENRE_CAP_PER_ROUND + 1
	return GENRE_CAP_PER_ROUND

## バッファを「連続して同じジャンルにならない」よう貪欲法で並べ替える。
## 最頻ジャンルを優先しつつ直前ジャンルを避けることで偏りを最小化する。
func _reorder_buffer_for_genre_spread() -> void:
	var pool: Array[QuizItem] = buffer.duplicate()
	var result: Array[QuizItem] = []
	var prev_genre := _last_dispatched_genre
	while pool.size() > 0:
		# 残プールのジャンル別出現数を集計
		var counts := {}
		for it in pool:
			counts[it.genre] = int(counts.get(it.genre, 0)) + 1
		# 直前ジャンル以外が残っているか
		var has_other := false
		for g in counts.keys():
			if g != prev_genre:
				has_other = true
				break
		# 直前ジャンルを避けつつ、最も多く残るジャンルの問題を選ぶ
		var best_idx := -1
		var best_count := -1
		for i in range(pool.size()):
			var g: String = pool[i].genre
			if g == prev_genre and has_other:
				continue
			var cnt: int = int(counts[g])
			if cnt > best_count:
				best_count = cnt
				best_idx = i
		if best_idx == -1:
			best_idx = 0
		var chosen: QuizItem = pool[best_idx]
		result.append(chosen)
		pool.remove_at(best_idx)
		prev_genre = chosen.genre
	buffer = result

## オフライン問題から緊急用キャッシュを準備する
func _prepare_emergency_cache() -> void:
	if _emergency_cache.size() >= EMERGENCY_CACHE_SIZE:
		return
	var needed: int = EMERGENCY_CACHE_SIZE - _emergency_cache.size()
	var active_texts := _collect_active_question_texts()
	var fallback := offline_provider.get_quizzes(
		current_subject, current_grade, current_difficulty,
		Constants.MODE_ENDLESS, needed * 3, active_texts
	)
	for q in fallback:
		if QuizDedup.is_similar_to_any(q.q, active_texts):
			continue
		active_texts.append(q.q)
		_emergency_cache.append(q)
		if _emergency_cache.size() >= EMERGENCY_CACHE_SIZE:
			break
	if _emergency_cache.size() > 0:
		print("[BufferedProvider] Emergency cache prepared: %d offline questions" % _emergency_cache.size())

## 払い出し済みのオンライン問題を追跡リストに登録する
## （解説の後充填・正解の一括検証の対象にするため）
func _track_dispatched_unexplained(q: QuizItem) -> void:
	if q == null or _is_offline_quiz_item(q):
		return
	_dispatched_items.append(q)
	while _dispatched_items.size() > 30:
		_dispatched_items.pop_front()


## バッファ内・払い出し済みの解説未取得問題に対してバックグラウンドで解説生成をキック。
## 10問モードでは生成時に解説を省略して高速化しているため、
## プリロード中でも未充填が一定数たまり次第、先行してバッチ充填を始める。
func _kick_explanation_batch() -> void:
	if _explanation_inflight:
		return
	if not is_active_round:
		return
	if _should_use_offline_quizzes():
		return

	# 解説が空のオンライン生成問題を収集（バッファ・控え・払い出し済みすべて対象）
	var need_explanation: Array[QuizItem] = []
	var candidates: Array[QuizItem] = []
	for q in buffer:
		candidates.append(q)
	for q in _overflow_buffer:
		candidates.append(q)
	for q in _dispatched_items:
		candidates.append(q)
	for q in candidates:
		if q.e.strip_edges().is_empty() \
				and not _is_offline_quiz_item(q) \
				and not _explanation_requested_ids.has(q.q):
			need_explanation.append(q)

	if need_explanation.is_empty():
		return

	# プリロード中は、しきい値以上たまるまで待つ（生成帯域をクイズ本体に集中しつつ先行充填）
	if _is_preloading() and need_explanation.size() < EXPLANATION_KICK_MIN:
		return

	for q in need_explanation:
		_explanation_requested_ids[q.q] = true

	_explanation_inflight = true
	print("[BufferedProvider] Kicking explanation batch for %d quizzes" % need_explanation.size())
	online_fetcher.fetch_explanations_batch(need_explanation, current_subject, current_grade)

func _on_explanations_ready(quizzes: Array[QuizItem]) -> void:
	_explanation_inflight = false
	# game_state 側は4→2択変換時に QuizItem をクローンするため、
	# 参照共有では届かないケースに備えて問題文一致でも解説を伝播させる
	_propagate_explanations_to_game(quizzes)
	print("[BufferedProvider] Explanations received, checking for more...")
	# まだ解説未取得の問題があれば次のバッチをキック
	_kick_explanation_batch()


## 充填された解説を、game_state が保持するクローン（4→2択変換後の QuizItem）にも
## 問題文の一致で書き写す。current_quiz と quiz_history の両方が対象。
func _propagate_explanations_to_game(quizzes: Array[QuizItem]) -> void:
	var gs = QuizManager.game_state
	if gs == null:
		return
	for src_q in quizzes:
		if src_q == null or src_q.e.strip_edges().is_empty():
			continue
		var cq = gs.current_quiz
		if cq != null and cq != src_q and cq.q == src_q.q and cq.e.strip_edges().is_empty():
			cq.e = src_q.e
		for entry in gs.quiz_history:
			if not entry is Dictionary:
				continue
			var hq = (entry as Dictionary).get("quiz", null)
			if hq is QuizItem and hq != src_q and hq.q == src_q.q and hq.e.strip_edges().is_empty():
				hq.e = src_q.e


## 10問モード: プリロード完了後に1回だけ、ラウンド全問の正解をLLMで一括検証する。
## QuizItem は参照共有のため、誤りが見つかった場合は item.a がその場で修正され、
## すでに壁が構築済みでも衝突判定（current_quiz.a 参照）に正しく反映される。
func _run_answer_validation_once() -> void:
	if _answer_validation_done:
		return
	if not is_active_round or current_mode != Constants.MODE_TEN:
		return
	if _should_use_offline_quizzes() or not _online_api_available():
		return
	if _is_preloading():
		return
	var validator: QuizValidator = QuizManager.quiz_validator
	if validator == null:
		return

	var targets: Array[QuizItem] = []
	for q in buffer:
		if not _is_offline_quiz_item(q) and not q.validated:
			targets.append(q)
	for q in _overflow_buffer:
		if not _is_offline_quiz_item(q) and not q.validated:
			targets.append(q)
	for q in _dispatched_items:
		if q not in targets and not q.validated:
			targets.append(q)
	if targets.is_empty():
		return

	_answer_validation_done = true
	print("[BufferedProvider] Running one-shot answer validation for %d quizzes" % targets.size())
	validator.validate_answers_llm(targets, current_subject, current_grade,
		func(_valid_items: Array[QuizItem], invalid_reasons: Array[String]):
			for item in _valid_items:
				item.validated = true
			if invalid_reasons.size() > 0:
				print("[BufferedProvider] Answer validation flagged %d items:" % invalid_reasons.size())
				for reason in invalid_reasons:
					print("  - %s" % reason)
	)


## ── ラウンド間 問題履歴の永続化 ──

func _seed_from_generated_bank() -> void:
	if generated_bank == null or llm_mode != "ONLINE":
		return
	var candidates := generated_bank.take_items(current_subject, current_grade, current_difficulty)
	if candidates.is_empty():
		return
	var ordered: Array[QuizItem] = []
	var rest: Array[QuizItem] = []
	for q in candidates:
		if q.genre.strip_edges().is_empty():
			q.genre = "未分類"
		if _genre_count_in_round(q.genre) == 0:
			ordered.append(q)
		else:
			rest.append(q)
	ordered.append_array(rest)
	var used: Array[String] = []
	var batch_accepted: Array[String] = []
	var adopted_units: Array[String] = []
	for q in ordered:
		if current_mode == Constants.MODE_TEN \
				and yielded_count + _preload_buffer_count() >= target_count:
			break
		if _should_block_quiz(q.q, batch_accepted, true):
			continue
		if current_mode == Constants.MODE_TEN \
				and _genre_count_in_round(q.genre) >= _effective_genre_cap():
			continue
		batch_accepted.append(q.q)
		_append_history_entry(q.q, q.genre)
		buffer.append(q)
		used.append(q.q)
		if not q.genre.is_empty() and q.genre not in adopted_units:
			adopted_units.append(q.genre)
	if used.size() > 0:
		generated_bank.remove_questions(current_subject, current_grade, current_difficulty, used)
		_schedule_history_save()
		print("[BufferedProvider] Seeded %d quizzes from generated bank" % used.size())
	if adopted_units.size() > 0 and is_instance_valid(online_fetcher) \
			and online_fetcher.has_method("record_adopted_units"):
		online_fetcher.record_adopted_units(current_subject, current_grade, adopted_units)


func _store_leftovers_to_pool() -> void:
	if llm_mode != "ONLINE" or generated_bank == null:
		return
	var leftovers: Array[QuizItem] = []
	for q in buffer:
		if not _is_offline_quiz_item(q):
			leftovers.append(q)
	for q in _overflow_buffer:
		if not _is_offline_quiz_item(q):
			leftovers.append(q)
	if leftovers.is_empty():
		return
	generated_bank.store_items(leftovers, current_subject, current_grade, current_difficulty)


func _log_round_quality_stats() -> void:
	_quality_stats_logged = true
	var genres := {}
	var unlabeled := 0
	var items: Array[QuizItem] = []
	items.append_array(buffer)
	items.append_array(_overflow_buffer)
	items.append_array(_dispatched_items)
	for q in items:
		if q.genre.strip_edges().is_empty() or q.genre == "未分類":
			unlabeled += 1
		genres[q.genre] = true
	print("[BufferedProvider] Round quality: items=%d genres=%d unlabeled=%d seen=%d blocked=%d" % [
		items.size(), genres.size(), unlabeled, _round_candidates_seen, _round_candidates_blocked
	])


func _build_fetch_history() -> Array[String]:
	var merged: Array[String] = []
	for rq in QuizDedup.tail_texts(recent_questions, QuizDedup.BLOCKLIST_HISTORY_MAX):
		if rq not in merged:
			merged.append(rq)
	for ph in play_history:
		if ph not in merged:
			merged.append(ph)
	for bq in buffer:
		if bq.q not in merged:
			merged.append(bq.q)
	for oq in _overflow_buffer:
		if oq.q not in merged:
			merged.append(oq.q)
	if generated_bank != null:
		for pool_q: String in generated_bank.list_question_texts(
				current_subject, current_grade, current_difficulty):
			if pool_q not in merged:
				merged.append(pool_q)
	return QuizDedup.tail_texts(merged, QuizDedup.BLOCKLIST_HISTORY_MAX)


func _collect_active_question_texts(during_preload: bool = false) -> Array[String]:
	var texts: Array[String] = []
	var history_cap := QuizDedup.PRELOAD_ACCEPT_HISTORY_MAX if during_preload else QuizDedup.BLOCKLIST_HISTORY_MAX
	for rq in QuizDedup.tail_texts(recent_questions, history_cap):
		if rq not in texts:
			texts.append(rq)
	for ph in play_history:
		if ph not in texts:
			texts.append(ph)
	for bq in buffer:
		if bq.q not in texts:
			texts.append(bq.q)
	for oq in _overflow_buffer:
		if oq.q not in texts:
			texts.append(oq.q)
	if generated_bank != null:
		for pool_q: String in generated_bank.list_question_texts(
				current_subject, current_grade, current_difficulty):
			if pool_q not in texts:
				texts.append(pool_q)
	if QuizManager.quiz_optimizer != null:
		for item: Variant in QuizManager.quiz_optimizer.ratings.get("bad", []):
			if not item is Dictionary:
				continue
			var entry: Dictionary = item
			if str(entry.get("subject", "")) != current_subject:
				continue
			if str(entry.get("grade", "")) != str(current_grade):
				continue
			var q_text := str(entry.get("q", ""))
			if not q_text.is_empty() and q_text not in texts:
				texts.append(q_text)
	if QuizManager.player_analytics != null:
		var signals := QuizManager.player_analytics.get_quality_signals(
			current_subject, current_grade, current_difficulty
		)
		for q_text: String in signals.get("too_easy", []):
			if not q_text.is_empty() and q_text not in texts:
				texts.append(q_text)
	return texts


func _append_history_entry(question: String, genre: String) -> bool:
	if question.is_empty():
		return false
	if QuizDedup.is_strict_duplicate_to_any(question, recent_history_entries):
		return false
	if QuizDedup.is_similar_to_any(
			question,
			QuizDedup.tail_texts(recent_history_entries, QuizDedup.SEMANTIC_HISTORY_MAX)
		):
		return false
	var history_entry := QuizDedup.make_history_entry(question, genre)
	history_entry["subject"] = current_subject
	history_entry["grade"] = current_grade
	history_entry["difficulty"] = current_difficulty
	history_entry["reserved_at"] = int(Time.get_unix_time_from_system())
	recent_history_entries.append(history_entry)
	while recent_history_entries.size() > CROSS_ROUND_HISTORY_MAX:
		recent_history_entries.pop_front()
	_sync_recent_questions_from_entries()
	return true

func _sync_recent_questions_from_entries() -> void:
	recent_questions.clear()
	for entry in recent_history_entries:
		var text := QuizDedup.history_entry_text(entry)
		if not text.is_empty():
			recent_questions.append(text)


func _load_cross_round_history() -> void:
	if not FileAccess.file_exists(HISTORY_SAVE_PATH):
		return
	var f := FileAccess.open(HISTORY_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var json = JSON.parse_string(f.get_as_text())
	f.close()
	if json is Array:
		recent_history_entries.clear()
		for item in json:
			if item is String and not (item as String).is_empty():
				recent_history_entries.append(QuizDedup.make_history_entry(item as String, ""))
			elif item is Dictionary:
				var entry: Dictionary = item
				var q_text := str(entry.get("q", ""))
				if q_text.is_empty():
					continue
				if not entry.has("core"):
					entry["core"] = QuizDedup.extract_core_concept(q_text)
				recent_history_entries.append(entry)
		while recent_history_entries.size() > CROSS_ROUND_HISTORY_MAX:
			recent_history_entries.pop_front()
		_sync_recent_questions_from_entries()
		if recent_questions.size() > 0:
			print("[BufferedProvider] Loaded %d cross-round history entries from disk" % recent_questions.size())

func _save_cross_round_history() -> void:
	var save_data: Array = []
	for entry in recent_history_entries:
		if entry is Dictionary:
			save_data.append(entry)
		else:
			var text := QuizDedup.history_entry_text(entry)
			if not text.is_empty():
				save_data.append(QuizDedup.make_history_entry(text, ""))
	var f := FileAccess.open(HISTORY_SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save_data))
		f.close()
		print("[BufferedProvider] Saved %d cross-round history entries to disk" % save_data.size())


func _schedule_history_save() -> void:
	if _history_save_scheduled:
		return
	_history_save_scheduled = true
	get_tree().create_timer(HISTORY_SAVE_DEBOUNCE_SEC).timeout.connect(func():
		_history_save_scheduled = false
		_save_cross_round_history()
	, CONNECT_ONE_SHOT)

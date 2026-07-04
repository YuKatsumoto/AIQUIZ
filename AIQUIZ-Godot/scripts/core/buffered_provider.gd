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
const CROSS_ROUND_HISTORY_MAX: int = 300
const HISTORY_SAVE_PATH: String = "user://recent_quiz_history.json"
const DEDUP_RETRY_MAX: int = 1
const MIN_REFETCH_INTERVAL_SEC: float = 1.2

## オフラインの緊急キャッシュ — オンライン生成が間に合わない時の保険
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

## エンドレスモード(ONLINE)でバッファが空になり続けている開始時刻（0=空でない）
var _endless_empty_since_ms: int = 0
## この秒数だけオンライン生成を待っても間に合わなければオフライン問題で一時補完する
const ENDLESS_OFFLINE_FALLBACK_DELAY_SEC: float = 1.5

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
	_explanation_inflight = false
	_explanation_requested_ids.clear()
	_dispatched_items.clear()
	_answer_validation_done = false
	_endless_empty_since_ms = 0

	# オンラインモードでは通常オフライン緊急キャッシュを使わないが、
	# エンドレスモードに限り、生成が遅延した際の一時補完用に緊急キャッシュを使う
	if _should_use_offline_quizzes():
		_prepare_emergency_cache()
	else:
		_emergency_cache.clear()
		buffer = _filter_online_only(buffer)
		_overflow_buffer = _filter_online_only(_overflow_buffer)
	
	# ★★★ 速度最適化: ポーリング待ちを廃止し、即座に最初のリクエストを発火 ★★★
	if llm_mode == "ONLINE" and not _online_api_available():
		print("[BufferedProvider] Online mode selected but PROXY_URL is not configured — waiting (no offline fallback)")
	elif _should_use_offline_quizzes() or _online_api_available():
		_fire_immediate_fetch()

func end_round() -> void:
	is_active_round = false
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
		if q.e.strip_edges().is_empty() and q.src != "OFFLINE" and not _explanation_requested_ids.has(q.q):
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
		var have := yielded_count + buffer.size() + _overflow_buffer.size()
		var needed := maxi(0, target_count - have)
		if needed == 0:
			return false
		# プリロード中は inflight 見積もりで過剰判定しない（dedup で実際は少ない）
		if _is_preloading():
			return true
		var pending := buffer.size() + inflight * 15
		return pending < needed
	var per_batch_estimate: int = 15  # 4バッチ×4問 − dedup ≈ 15問期待
	var pending = buffer.size() + inflight * per_batch_estimate
	return pending < _target_buffer_size()

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

	if not _worker_should_fill():
		return

	if llm_mode == "ONLINE" and not _online_api_available():
		return
	if online_fetcher.has_method("is_rate_limited") and online_fetcher.is_rate_limited():
		return
	
	_last_refetch_ms = Time.get_ticks_msec()
	inflight += 1
	var fetch_count: int
	if current_mode == Constants.MODE_ENDLESS:
		# 目標バッファサイズを満たすための必要最小限のみをリクエスト (最小1)
		fetch_count = maxi(1, _target_buffer_size() - buffer.size())
	else:
		fetch_count = clampi(target_count - yielded_count - buffer.size(), 2, 10)
		
	if llm_mode == "ONLINE":
		var full_history: Array[String] = _build_fetch_history()
		var is_ten: bool = current_mode == Constants.MODE_TEN
		online_fetcher.fetch_quiz_parallel(current_subject, current_grade, current_difficulty, fetch_count, full_history, is_ten)
	else:
		print("[BufferedProvider] Using offline bank (llm_mode=%s)" % llm_mode)
		var b_size := 6
		if current_mode == Constants.MODE_TEN:
			b_size = clampi(target_count, 6, 10)
		var out = offline_provider.get_quizzes(current_subject, current_grade, current_difficulty, current_mode, b_size)
		_on_fetch_completed(out)

func _is_preloading() -> bool:
	# yielded_count は get_quizzes 呼び出しごとに増えるため、
	# 「バッファ空」ではなく「ラウンド分が揃うまで」をプリロードとみなす
	return is_active_round and (_preload_buffer_count() + yielded_count) < target_count


func _preload_buffer_count() -> int:
	return buffer.size() + _overflow_buffer.size()


func _needs_more_preload() -> bool:
	return _is_preloading() and _preload_buffer_count() < target_count


func _should_block_quiz(question: String, batch_accepted: Array[String], during_preload: bool) -> bool:
	if QuizDedup.is_similar_to_any(question, batch_accepted):
		return true
	if during_preload:
		# プリロード中: バッファ内・プレイ中 + 直近の cross-round 履歴（新鮮さ確保）を照合
		for bq in buffer:
			if QuizDedup.is_semantically_similar(question, bq.q):
				return true
		for ph in play_history:
			if QuizDedup.is_semantically_similar(question, ph):
				return true
		for oq in _overflow_buffer:
			if QuizDedup.is_semantically_similar(question, oq.q):
				return true
		for rq in QuizDedup.tail_texts(recent_questions, QuizDedup.PRELOAD_ACCEPT_HISTORY_MAX):
			if QuizDedup.is_semantically_similar(question, rq):
				return true
		return false
	return QuizDedup.is_similar_to_any(question, _collect_active_question_texts(false))


func _try_force_accept_preload(quizzes: Array[QuizItem], batch_accepted: Array[String]) -> bool:
	for q in quizzes:
		if llm_mode == "ONLINE" and _is_offline_quiz_item(q):
			continue
		if q.q in batch_accepted:
			continue
		var dup_in_buffer := false
		for bq in buffer:
			if bq.q == q.q:
				dup_in_buffer = true
				break
		if dup_in_buffer:
			continue
		buffer.append(q)
		print("[BufferedProvider] Preload force-accepted: '%s'" % q.q.left(30))
		return true
	if quizzes.size() > 0:
		var fallback: QuizItem = quizzes[0]
		if not (llm_mode == "ONLINE" and _is_offline_quiz_item(fallback)):
			buffer.append(fallback)
			print("[BufferedProvider] Preload last-resort accept: '%s'" % fallback.q.left(30))
			return true
	return false


func _on_fetch_partial(quizzes: Array[QuizItem]) -> void:
	if quizzes.size() == 0:
		return
		
	var accepted := false
	var batch_accepted: Array[String] = []
	var during_preload := _is_preloading()
	for q in quizzes:
		if llm_mode == "ONLINE" and _is_offline_quiz_item(q):
			print("[BufferedProvider] Rejected offline quiz in online mode: '%s'" % q.q.left(30))
			continue
		if _should_block_quiz(q.q, batch_accepted, during_preload):
			print("[BufferedProvider] Dedup blocked: '%s'" % q.q.left(30))
			continue
		batch_accepted.append(q.q)
		# バッファ投入時は cross-round 履歴を更新しない（end_round / submit_result で永続化）
		# 10問モード: 同一ジャンルが上限に達していたら控え(overflow)に回す
		if current_mode == Constants.MODE_TEN and not q.genre.strip_edges().is_empty() \
				and _genre_count_in_buffer(q.genre) >= GENRE_CAP_PER_ROUND:
			_overflow_buffer.append(q)
			print("[BufferedProvider] Genre cap reached for '%s', queued to overflow: '%s'" % [q.genre, q.q.left(20)])
			continue
		buffer.append(q)
		accepted = true
	
	if accepted and online_fetcher.has_method("reset_rate_limit"):
		online_fetcher.reset_rate_limit()
	
	# プリロード中に全部弾かれた場合: リトライ → 履歴トリム → 強制受理
	if not accepted and quizzes.size() > 0 and _needs_more_preload():
		if _dedup_retry_count < DEDUP_RETRY_MAX and _preload_buffer_count() == 0:
			_dedup_retry_count += 1
			print("[BufferedProvider] All duplicates blocked, retry fetch (%d/%d)" % [_dedup_retry_count, DEDUP_RETRY_MAX])
			_schedule_fetch(1.0)
			return
		if recent_history_entries.size() > 20 and _preload_buffer_count() == 0:
			var trim_count := maxi(1, int(recent_history_entries.size() * 0.25))
			for _i in range(trim_count):
				if recent_history_entries.size() > 0:
					recent_history_entries.pop_front()
			_sync_recent_questions_from_entries()
			print("[BufferedProvider] Trimmed %d oldest history entries after dedup exhaustion" % trim_count)
			for q in quizzes:
				if _should_block_quiz(q.q, batch_accepted, true):
					continue
				buffer.append(q)
				accepted = true
				break
		if not accepted:
			accepted = _try_force_accept_preload(quizzes, batch_accepted)

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
		while _overflow_buffer.size() > 0 and out.size() < count:
			var ov: QuizItem = _overflow_buffer.pop_front()
			if llm_mode == "ONLINE" and _is_offline_quiz_item(ov):
				continue
			_last_dispatched_genre = ov.genre
			_track_dispatched_unexplained(ov)
			out.append(ov)
	
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
			if current_mode == Constants.MODE_ENDLESS:
				# エンドレスモード: オンライン生成が遅延した場合のみオフラインで一時補完する
				# （生成自体は止めず、バックグラウンドで継続する）
				out = _endless_online_fallback(count)
			else:
				# 10問モード: 純粋なオンライン問題のみを維持するためフォールバックしない
				print("[BufferedProvider] Online buffer empty, waiting for AI fetch (no offline fallback)")

	if out.size() > 0:
		_endless_empty_since_ms = 0
	yielded_count += out.size()
	return out


## エンドレスモード(ONLINE)専用: バッファ空が一定時間続いたらオフライン問題で一時補完する。
## オンライン生成は止めない（_schedule_fetch は呼び出し側で既に手配済み）。
## 猶予時間内であれば空配列を返し、プレイヤーは通常どおり生成完了を待つ。
func _endless_online_fallback(count: int) -> Array[QuizItem]:
	var now := Time.get_ticks_msec()
	if _endless_empty_since_ms == 0:
		_endless_empty_since_ms = now
	var elapsed_sec := float(now - _endless_empty_since_ms) / 1000.0
	if elapsed_sec < ENDLESS_OFFLINE_FALLBACK_DELAY_SEC:
		return []

	var out: Array[QuizItem] = []
	if _emergency_cache.is_empty():
		_prepare_emergency_cache()
	if _emergency_cache.size() > 0:
		var needed := maxi(1, count)
		for _i in range(mini(needed, _emergency_cache.size())):
			var eq: QuizItem = _emergency_cache.pop_front()
			eq.src = "OFFLINE_FALLBACK"
			out.append(eq)
		print("[BufferedProvider] Endless: online generation lagging (%.1fs) — filled %d from offline fallback" % [elapsed_sec, out.size()])
		if _emergency_cache.size() < 3:
			_prepare_emergency_cache()
	return out


## バッファ内に同一ジャンルが何問あるか数える
func _genre_count_in_buffer(genre: String) -> int:
	var n := 0
	for q in buffer:
		if q.genre == genre:
			n += 1
	return n

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
		if q.e.strip_edges().is_empty() and q.src != "OFFLINE" and not _explanation_requested_ids.has(q.q):
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

	# 完了時にフラグをリセット（シグナル接続）
	if not online_fetcher.explanations_ready.is_connected(_on_explanations_ready):
		online_fetcher.explanations_ready.connect(_on_explanations_ready)

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
		if not _is_offline_quiz_item(q):
			targets.append(q)
	for q in _overflow_buffer:
		if not _is_offline_quiz_item(q):
			targets.append(q)
	for q in _dispatched_items:
		if q not in targets:
			targets.append(q)
	if targets.is_empty():
		return

	_answer_validation_done = true
	print("[BufferedProvider] Running one-shot answer validation for %d quizzes" % targets.size())
	validator.validate_answers_llm(targets, current_subject, current_grade,
		func(_valid_items: Array[QuizItem], invalid_reasons: Array[String]):
			if invalid_reasons.size() > 0:
				print("[BufferedProvider] Answer validation flagged %d items:" % invalid_reasons.size())
				for reason in invalid_reasons:
					print("  - %s" % reason)
	)


## ── ラウンド間 問題履歴の永続化 ──

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


func _append_history_entry(question: String, genre: String) -> void:
	if question.is_empty():
		return
	for entry in recent_history_entries:
		if QuizDedup.is_semantically_similar(question, QuizDedup.history_entry_text(entry)):
			return
	recent_history_entries.append(QuizDedup.make_history_entry(question, genre))
	while recent_history_entries.size() > CROSS_ROUND_HISTORY_MAX:
		recent_history_entries.pop_front()
	_sync_recent_questions_from_entries()


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

extends Node

## ONLINEモードがOFFLINE系クイズを一切払い出さず、旧OnlineFetchを使う回帰テスト。

var _failures: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	var provider := BufferedQuizProvider.new()
	add_child(provider)
	await get_tree().process_frame
	provider._poll_timer.stop()

	_assert_true(
		provider.online_fetcher != null
			and provider.online_fetcher.get_script().resource_path \
				== "res://scripts/core/online_fetch.gd",
		"旧OnlineFetchが通常のオンライン生成器として接続される"
	)

	provider.llm_mode = "ONLINE"
	provider.current_mode = Constants.MODE_TEN
	provider.is_active_round = true
	provider.target_count = 10
	provider.buffer.assign([
		_make_quiz("offline", "OFFLINE"),
		_make_quiz("fallback", "OFFLINE_FALLBACK"),
		_make_quiz("offline alias", "OFFLINE_CACHE"),
		_make_quiz("legacy gemini", "GEMINI"),
		_make_quiz("legacy stream", "GEMINI_STREAM"),
	])
	var online_items := provider.get_quizzes("算数", 3, "普通", Constants.MODE_TEN, 10)
	_assert_true(online_items.size() == 2, "ONLINE払い出しではオンライン生成問題だけが残る")
	for quiz: QuizItem in online_items:
		_assert_false(
			quiz.src.strip_edges().to_upper().begins_with("OFFLINE"),
			"ONLINE払い出しにOFFLINE系ソースが含まれない"
		)

	provider.current_mode = Constants.MODE_ENDLESS
	provider.buffer.clear()
	# 空バッファ時の実API再取得はこの単体テストの対象外。inflight扱いにして
	# 払い出し側が緊急オフラインキャッシュを消費しないことだけを検証する。
	provider.inflight = 1
	provider._emergency_cache.assign([
		_make_quiz("emergency", "OFFLINE_FALLBACK"),
	])
	var endless_items := provider.get_quizzes(
		"算数", 3, "普通", Constants.MODE_ENDLESS, 1
	)
	_assert_true(
		endless_items.is_empty(),
		"ONLINEエンドレスでも緊急オフライン補完を使わずオンライン到着を待つ"
	)
	_assert_true(
		provider._emergency_cache.size() == 1,
		"ONLINE待機中にオフライン緊急キャッシュを消費しない"
	)

	var net_state := NetGameState.new()
	_assert_false(
		net_state._is_online_quiz_source("OFFLINE"),
		"ネットワーク送受信でもOFFLINEを拒否する"
	)
	_assert_false(
		net_state._is_online_quiz_source("OFFLINE_FALLBACK"),
		"ネットワーク送受信でもOFFLINE_FALLBACKを拒否する"
	)
	_assert_false(
		net_state._is_online_quiz_source(""),
		"ネットワーク送受信では出典不明も拒否する"
	)
	_assert_true(
		net_state._is_online_quiz_source("GEMINI_STREAM"),
		"旧オンライン生成ソースは許可する"
	)

	net_state.free()
	provider.queue_free()
	await get_tree().process_frame
	# Autoloadの起動時設定取得が解放されるまで待ち、テスト終了時の偽リーク警告を避ける。
	await get_tree().create_timer(1.0).timeout
	if _failures == 0:
		print("[OnlineSourceContractTest] ALL PASSED")
		get_tree().quit(0)
	else:
		push_error("[OnlineSourceContractTest] FAILED: %d assertion(s)" % _failures)
		get_tree().quit(1)


func _make_quiz(question: String, source: String) -> QuizItem:
	return QuizItem.create(
		question,
		PackedStringArray(["A", "B"]),
		0,
		"explanation",
		source
	)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("  PASS: %s" % label)
		return
	_failures += 1
	push_error("  FAIL: %s" % label)


func _assert_false(value: bool, label: String) -> void:
	_assert_true(not value, label)

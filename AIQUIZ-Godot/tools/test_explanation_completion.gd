extends SceneTree

var failures: int = 0


func _initialize() -> void:
	await process_frame
	var fetcher = load("res://scripts/core/online_fetch.gd").new()
	get_root().add_child(fetcher)

	var blank := QuizItem.create(
		"1 + 1 は？", PackedStringArray(["1", "2"]), 1, "", "CLAUDE"
	)
	var existing := QuizItem.create(
		"空はなぜ青い？", PackedStringArray(["光", "海"]), 0, "既存の解説", "CLAUDE"
	)
	var emitted_sizes: Array[int] = []
	fetcher.explanations_ready.connect(func(items: Array[QuizItem]) -> void:
		emitted_sizes.append(items.size())
	)
	var test_items: Array[QuizItem] = [blank, existing]
	fetcher._complete_explanation_batch(test_items, "test failure")

	_assert_true(not blank.e.is_empty(), "空の解説は失敗メッセージで完了する")
	_assert_true(blank.e == fetcher.EXPLANATION_UNAVAILABLE_TEXT, "失敗メッセージが一定")
	_assert_true(existing.e == "既存の解説", "既存の解説を上書きしない")
	_assert_true(emitted_sizes == [2], "失敗時も explanations_ready を通知する")
	_assert_true(ClaudeRequest.response_text({}).is_empty(), "空レスポンスを安全に処理する")
	_assert_true(ClaudeRequest.response_text(null).is_empty(), "読めないレスポンスを安全に処理する")
	_assert_true(ClaudeRequest.response_text({"text": 3}).is_empty(), "text が文字列でなければ空")
	_assert_true(
		ClaudeRequest.response_text({"text": " 解説本文 ", "stop_reason": "end_turn"}) == "解説本文",
		"正常レスポンスから解説を取得する"
	)

	var protected_request := HTTPRequest.new()
	protected_request.set_meta("preserve_on_round_end", true)
	fetcher.add_child(protected_request)
	var normal_request := HTTPRequest.new()
	fetcher.add_child(normal_request)
	var stream := ClaudeStreamClient.new()
	fetcher.add_child(stream)
	var stream_finished := [false]
	stream.stream_finished.connect(func(_ok: bool, _text: String) -> void: stream_finished[0] = true)
	fetcher.cancel_all()
	_assert_true(not protected_request.is_queued_for_deletion(), "解説リクエストはラウンド終了時も保持する")
	_assert_true(normal_request.is_queued_for_deletion(), "通常リクエストはラウンド終了時に破棄する")
	_assert_true(stream.is_queued_for_deletion(), "ストリーミングもラウンド終了時に止めて破棄する")
	_assert_true(not stream_finished[0], "止めたストリーミングは完了を通知しない")
	protected_request.queue_free()
	fetcher.queue_free()

	if failures == 0:
		print("[ExplanationCompletionTest] ALL PASSED")
	else:
		printerr("[ExplanationCompletionTest] FAILED: %d" % failures)
	quit(failures)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("[PASS] %s" % label)
	else:
		failures += 1
		printerr("[FAIL] %s" % label)

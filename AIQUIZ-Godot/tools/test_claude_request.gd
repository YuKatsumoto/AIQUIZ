extends SceneTree

## プロキシ（/claude・/claude-stream）への本文と、返事の読み取りのテスト。
## 実行: Godot --headless --path . --script res://tools/test_claude_request.gd

var failures: int = 0


func _initialize() -> void:
	await process_frame

	var body: Variant = JSON.parse_string(ClaudeRequest.body(ClaudeRequest.TASK_GENERATE, "問題", "先生"))
	_assert_true(body is Dictionary and body.size() == 3, "本文は task・prompt・system だけ")
	_assert_true(body["task"] == "generate" and body["prompt"] == "問題" and body["system"] == "先生", "本文の中身")
	var no_system: Variant = JSON.parse_string(ClaudeRequest.body(ClaudeRequest.TASK_VALIDATE, "確認"))
	_assert_true(not no_system.has("system"), "system が空なら送らない（プロキシの安全指示だけになる）")
	_assert_true(not no_system.has("model"), "モデルはゲームから指定しない")

	_assert_true(ClaudeRequest.response_text({"text": "[1]"}) == "[1]", "text を取り出す")
	_assert_true(ClaudeRequest.response_text({"candidates": []}).is_empty(), "Gemini の形は読まない")

	var client := ClaudeStreamClient.new()
	get_root().add_child(client)
	var chunks: Array[String] = []
	client.text_chunk_received.connect(func(_all: String, chunk: String) -> void: chunks.append(chunk))
	client._process_sse_chunk(": keep-alive\n\n")
	client._process_sse_chunk("data: {\"type\":\"text\",\"text\":\"[{\\\"q\\\":\"}\n\ndata: {\"type\":\"te")
	client._process_sse_chunk("xt\",\"text\":\"\\\"あ\\\"}]\"}\n\ndata: {\"type\":\"done\",\"stop_reason\":\"end_turn\"}\n\n")
	_assert_true(chunks == ["[{\"q\":", "\"あ\"}]"], "text の行だけを順に受け取る（行が分かれて届いても）")
	_assert_true(client._accumulated_text == "[{\"q\":\"あ\"}]", "本文を積み上げる")
	_assert_true(client.stream_error.is_empty(), "done は失敗にしない")
	client._process_sse_chunk("data: {\"type\":\"error\",\"error\":\"refusal\"}\n\n")
	_assert_true(client.stream_error == "refusal", "error を記録する")
	client.queue_free()

	if failures == 0:
		print("[ClaudeRequestTest] ALL PASSED")
	else:
		printerr("[ClaudeRequestTest] FAILED: %d" % failures)
	quit(failures)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("[PASS] %s" % label)
	else:
		failures += 1
		printerr("[FAIL] %s" % label)

extends Node

## 本物のプロキシ（PROXY_URL、既定は aiquiz-proxy-claude）に、ゲームと同じコードで 10 問モードの 1 ラウンドを頼む実機テスト。
## 許可証の取得 → 6 本同時のストリーミング生成 → 正解の確かめ → 解説の補充 を通し、かかった時間と費用（/health の差）を出す。
## Claude を呼ぶので費用がかかる（1 回 約 0.1 ドル）。APP_SECRET が要る（.env）。
## Godot --headless --path . --script res://tests/claude_live_bootstrap.gd

const SUBJECT := "算数"
const GRADE := 3
const DIFFICULTY := "普通"

var _items: Array[QuizItem] = []
var _first_ms := -1
var _start_ms := 0
var _failures: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	print("[ClaudeLive] PROXY_URL=%s" % ApiStatusAutoload.get_proxy_url())
	var session: Node = ApiStatusAutoload.device_session
	session.ensure_token()
	var waited := 0.0
	while not session.has_valid_token() and waited < 30.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	_check(session.has_valid_token(), "許可証を取れた")
	var before := await _spent_usd()

	var fetcher := OnlineFetch.new()
	add_child(fetcher)
	fetcher.fetch_partial.connect(func(items: Array[QuizItem]) -> void:
		if _first_ms < 0:
			_first_ms = Time.get_ticks_msec() - _start_ms
		_items.append_array(items)
	)
	var done := [false]
	fetcher.fetch_completed.connect(func(items: Array[QuizItem]) -> void:
		_items.append_array(items)
		done[0] = true
	)
	_start_ms = Time.get_ticks_msec()
	var history: Array[String] = []
	fetcher.fetch_quiz_parallel(SUBJECT, GRADE, DIFFICULTY, 10, history, true)
	while not done[0] and Time.get_ticks_msec() - _start_ms < 45000:
		await get_tree().process_frame
	var gen_ms := Time.get_ticks_msec() - _start_ms
	print("[ClaudeLive] generated=%d first=%dms all=%dms" % [_items.size(), _first_ms, gen_ms])
	_check(_items.size() >= 10, "10 問以上が届いた（%d 問）" % _items.size())
	_check(_first_ms >= 0 and _first_ms < 8000, "最初の 1 問が 8 秒以内に届いた（%d ms）" % _first_ms)
	for item in _items:
		_check(item.src == "CLAUDE_STREAM" or item.src == "CLAUDE", "出どころが Claude（%s）" % item.src)
	for i in range(mini(3, _items.size())):
		print("[ClaudeLive] Q%d %s / %s / a=%d t=%.1f g=%s" % [i + 1, _items[i].q, ", ".join(_items[i].c), _items[i].a,
			_items[i].estimated_seconds, _items[i].genre])

	var round_items: Array[QuizItem] = []
	for i in range(mini(10, _items.size())):
		round_items.append(_items[i])
	var validated := [null, null]
	var v_start := Time.get_ticks_msec()
	QuizManager.quiz_validator.validate_answers_llm(round_items, SUBJECT, GRADE,
		func(valid: Array[QuizItem], reasons: Array[String]) -> void:
			validated[0] = valid
			validated[1] = reasons
	)
	while validated[0] == null and Time.get_ticks_msec() - v_start < 45000:
		await get_tree().process_frame
	var checked := 0
	if validated[0] != null:
		for item: QuizItem in validated[0]:
			if item.validated:
				checked += 1
	print("[ClaudeLive] validate %dms: kept=%d validated=%d rejected=%s" % [Time.get_ticks_msec() - v_start,
		(validated[0] as Array).size() if validated[0] != null else -1, checked, validated[1]])
	_check(validated[0] != null and checked > 0, "正解の確かめが返り、確認済みの問題がある")

	for item in round_items:
		item.e = ""
	var explained := [false]
	fetcher.explanations_ready.connect(func(_items_done: Array[QuizItem]) -> void: explained[0] = true)
	var e_start := Time.get_ticks_msec()
	fetcher.fetch_explanations_batch(round_items, SUBJECT, GRADE)
	while not explained[0] and Time.get_ticks_msec() - e_start < 45000:
		await get_tree().process_frame
	var filled := 0
	for item in round_items:
		if not item.e.is_empty() and item.e != OnlineFetch.EXPLANATION_UNAVAILABLE_TEXT:
			filled += 1
	print("[ClaudeLive] explain %dms: filled=%d/%d e1=%s" % [Time.get_ticks_msec() - e_start, filled,
		round_items.size(), round_items[0].e if not round_items.is_empty() else ""])
	_check(filled == round_items.size(), "解説がすべて埋まった（%d/%d）" % [filled, round_items.size()])

	# 費用はプロキシが 10 秒ごとに書き出し、/health は 30 秒ごとに読み直すので少し待つ
	await get_tree().create_timer(45.0).timeout
	var after := await _spent_usd()
	print("[ClaudeLive] round cost: $%.4f (before $%.4f after $%.4f)" % [after - before, before, after])

	if _failures.is_empty():
		print("[ClaudeLive] ALL PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("[ClaudeLive] FAIL: %s" % failure)
		get_tree().quit(1)


func _spent_usd() -> float:
	var http := HTTPRequest.new()
	add_child(http)
	http.request(ApiStatusAutoload.get_proxy_url() + "/health", ApiStatusAutoload.get_app_headers())
	var result: Array = await http.request_completed
	http.queue_free()
	var json: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if json is Dictionary and json.has("budget"):
		return float(json["budget"].get("monthly_usd", 0.0))
	return -1.0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)

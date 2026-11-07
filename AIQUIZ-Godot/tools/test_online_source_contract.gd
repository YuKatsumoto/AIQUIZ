extends Node

## ONLINEモードがOFFLINE系クイズを一切払い出さず、OnlineFetchを使う回帰テスト。
## AI 生成が使えない・止まったときは、問題バンクへ自動で切り替わることも確かめる。

var _failures: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	# AI 生成できる設定として始める（実際の通信はしない）。終わったら元の設定に戻す。
	var saved_env: Dictionary = ApiStatusAutoload.env_vars.duplicate()
	if ApiStatusAutoload.get_env("APP_SECRET").is_empty():
		ApiStatusAutoload.env_vars["APP_SECRET"] = "contract-test"
	var saved_paused_until: int = ApiStatusAutoload._online_paused_until_ms
	ApiStatusAutoload._online_paused_until_ms = 0
	if ApiStatusAutoload.device_session != null:
		ApiStatusAutoload.device_session.set("_fetching", false)

	var provider := BufferedQuizProvider.new()
	add_child(provider)
	await get_tree().process_frame
	provider._poll_timer.stop()
	# 端末内の問題プールとラウンド間の履歴（ユーザーのデータ）を書き換えない
	provider.generated_bank = null

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
		_make_quiz("claude stream", "CLAUDE_STREAM"),
		_make_quiz("legacy stream", "GEMINI_STREAM"),
	])
	# 同じジャンルは 2 問までなので、オンライン生成の問題は 2 問にしておく
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

	_check_stall_switches_to_bank(provider, Constants.MODE_TEN)
	_check_stall_switches_to_bank(provider, Constants.MODE_ENDLESS)
	_check_bank_only_when_not_configured(provider)

	# 共有バンクへの候補・評価の対象になる出どころ
	_assert_false(ClaudeRequest.is_online_source("OFFLINE"), "OFFLINEはAI生成として扱わない")
	_assert_false(ClaudeRequest.is_online_source("OFFLINE_FALLBACK"), "OFFLINE_FALLBACKはAI生成として扱わない")
	_assert_false(ClaudeRequest.is_online_source(""), "出典不明はAI生成として扱わない")
	_assert_true(ClaudeRequest.is_online_source("CLAUDE_STREAM"), "Claudeの生成はAI生成として扱う")
	_assert_true(ClaudeRequest.is_online_source("gemini_stream"), "切り替え前に保存されたGeminiの問題も扱う")

	provider._history_save_pending = false
	provider.is_active_round = false
	provider.queue_free()
	ApiStatusAutoload.env_vars = saved_env
	ApiStatusAutoload._online_paused_until_ms = saved_paused_until
	await get_tree().process_frame
	# Autoloadの起動時設定取得が解放されるまで待ち、テスト終了時の偽リーク警告を避ける。
	await get_tree().create_timer(1.0).timeout
	if _failures == 0:
		print("[OnlineSourceContractTest] ALL PASSED")
		get_tree().quit(0)
	else:
		push_error("[OnlineSourceContractTest] FAILED: %d assertion(s)" % _failures)
		get_tree().quit(1)


## AI の問題を待ったまま届かないと、ラウンドの残りを問題バンクで埋める。
func _check_stall_switches_to_bank(provider: BufferedQuizProvider, mode: String) -> void:
	provider.llm_mode = "ONLINE"
	provider.current_subject = "算数"
	provider.current_grade = 3
	provider.current_difficulty = "普通"
	provider.current_mode = mode
	provider.target_count = 10
	provider.is_active_round = true
	provider.yielded_count = 0
	provider.buffer.clear()
	provider._overflow_buffer.clear()
	provider._emergency_cache.clear()
	provider._round_bank_fallback = false
	provider._round_plan_pending = false
	provider._fetch_scheduled = false
	provider._online_wait_started_ms = 0
	# 生成の返事を待っている途中
	provider.inflight = 1

	provider._check_online_stall()
	_assert_false(provider._round_bank_fallback, "%s: 待ち始めたばかりではバンクへ切り替えない" % mode)
	provider._online_wait_started_ms = Time.get_ticks_msec() \
		- int((BufferedQuizProvider.ONLINE_STALL_FALLBACK_SEC + 1.0) * 1000.0)
	provider._check_online_stall()
	_assert_true(provider._round_bank_fallback, "%s: 長く届かなければラウンドの残りを問題バンクへ切り替える" % mode)
	_assert_true(provider.inflight == 0, "%s: 届かない生成の数え上げで補充を止めない" % mode)

	provider._on_poll()
	_assert_true(provider.buffer.size() > 0, "%s: 切り替えたあとは問題バンクから補充する" % mode)
	for quiz: QuizItem in provider.buffer:
		_assert_true(
			quiz.src.strip_edges().to_upper().begins_with("OFFLINE"),
			"%s: 補充した問題は問題バンクのもの" % mode
		)
		break


## AI 生成を使えない設定（APP_SECRET なし）では、待たずに最初から問題バンクで出題する。
func _check_bank_only_when_not_configured(provider: BufferedQuizProvider) -> void:
	provider.is_active_round = false
	provider.llm_mode = "ONLINE"
	_assert_false(provider.uses_bank_only(), "生成できる設定ならラウンドの外では AI 生成の予定")
	provider.llm_mode = "OFFLINE"
	_assert_true(provider.uses_bank_only(), "llm_mode が OFFLINE ならバンクだけ（テスト・チュートリアル用）")
	provider.llm_mode = "ONLINE"

	# GameManager は .env の値を OS の環境変数にも入れるので、両方を空にする
	var os_secret := OS.get_environment("APP_SECRET")
	OS.set_environment("APP_SECRET", "")
	ApiStatusAutoload.env_vars["APP_SECRET"] = ""
	_assert_false(provider._online_generation_configured(), "APP_SECRET がなければ AI 生成できない設定")
	provider.begin_round("算数", 3, "普通", Constants.MODE_TEN, 10)
	_assert_true(provider.uses_bank_only(), "APP_SECRET がなければラウンドの始まりからバンクだけ")
	_assert_false(provider._round_plan_pending, "APP_SECRET がなければ round-plan を問い合わせない")
	_assert_true(provider.buffer.size() > 0, "APP_SECRET がなければ待たずに問題バンクで埋める")
	if os_secret.is_empty():
		OS.unset_environment("APP_SECRET")
	else:
		OS.set_environment("APP_SECRET", os_secret)


func _make_quiz(question: String, source: String) -> QuizItem:
	# 10問モードは4択で払い出す（2択を4択に増やせない問題は払い出さない）
	return QuizItem.create(
		question,
		PackedStringArray(["A", "B", "C", "D"]),
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

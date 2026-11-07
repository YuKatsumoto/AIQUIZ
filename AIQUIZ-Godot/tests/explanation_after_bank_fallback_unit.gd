extends Node

## AI の生成が途中で止まって、ラウンドの残りを問題バンクに切り替えた（_round_bank_fallback）あとも、
## すでに届いた AI の問題の解説は取りに行く（BufferedQuizProvider._kick_explanation_batch /
## _flush_pending_explanations_on_end）。以前は切り替えた時点で取りに行かなくなり、その問題で脱落すると
## GAME OVER の解説が「解説を読み込み中…」のまま変わらなかった。通信はしない（取りに行く役を差し替える）。
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/explanation_after_bank_fallback_bootstrap.gd

class FakeFetch extends OnlineFetch:
	var asked: Array[int] = []
	func fetch_explanations_batch(quizzes: Array[QuizItem], _subject: String, _grade: int) -> void:
		asked.append(quizzes.size())

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var had_secret := OS.get_environment("APP_SECRET")
	OS.set_environment("APP_SECRET", "test-secret")
	var provider := BufferedQuizProvider.new()
	var fetch := FakeFetch.new()
	provider.online_fetcher = fetch
	provider.llm_mode = "ONLINE"
	provider.is_active_round = true
	provider.target_count = 10
	provider.yielded_count = 10  # 準備は終わっている（試合中）
	var ai_quiz := QuizItem.create("AI の問題 1", PackedStringArray(["a", "b"]), 0, "", "CLAUDE_STREAM")
	var bank_quiz := QuizItem.create("バンクの問題", PackedStringArray(["a", "b"]), 0, "", "OFFLINE")
	provider._dispatched_items.append(ai_quiz)
	provider._dispatched_items.append(bank_quiz)
	provider._round_bank_fallback = true
	_check(ApiStatusAutoload.is_proxy_available(), "fixture: a proxy URL is set (the test env points it at a closed port)")
	provider._kick_explanation_batch()
	_check(fetch.asked == [1], "after the bank fallback the AI question's explanation is still requested", fetch.asked)
	# ラウンドの終わりの駆け込み依頼も、まだ頼んでいない AI の問題を拾う
	var fetch_end := FakeFetch.new()
	provider.online_fetcher = fetch_end
	provider._explanation_requested_ids.clear()
	provider._explanation_inflight = false
	provider._flush_pending_explanations_on_end()
	_check(fetch_end.asked == [1], "the end-of-round flush also asks after the bank fallback", fetch_end.asked)
	# OFFLINE のラウンドでは取りに行かない
	var fetch_offline := FakeFetch.new()
	provider.online_fetcher = fetch_offline
	provider._explanation_requested_ids.clear()
	provider._explanation_inflight = false
	provider.llm_mode = "OFFLINE"
	provider._kick_explanation_batch()
	_check(fetch_offline.asked.is_empty(), "an OFFLINE round never asks", fetch_offline.asked)
	OS.set_environment("APP_SECRET", had_secret)
	fetch.free()
	fetch_end.free()
	fetch_offline.free()
	provider.free()
	print("EXPLANATION_AFTER_BANK_FALLBACK " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String, detail: Variant = null) -> void:
	checks += 1
	if not ok:
		failures.append(label if detail == null else "%s: %s" % [label, str(detail)])

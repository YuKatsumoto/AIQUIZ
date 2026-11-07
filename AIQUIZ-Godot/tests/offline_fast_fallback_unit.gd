extends Node

## ネットにつながらない PC（プロキシに続けて届かない）では、AI の問題を 12 秒待たずに、
## そのラウンドを問題バンクで出題する（BufferedQuizProvider._check_online_stall と OnlineFetch.proxy_unreachable）。
## 届かなかった数はラウンドごとに数え直す（begin_round）。返事が 1 回でも届けば 0 に戻る。通信はしない。
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/offline_fast_fallback_bootstrap.gd

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var had_secret := OS.get_environment("APP_SECRET")
	OS.set_environment("APP_SECRET", "test-secret")
	var fetch := OnlineFetch.new()
	_check(not fetch.proxy_unreachable(), "a fresh fetcher is not unreachable")
	fetch.note_transport_result(HTTPRequest.RESULT_CANT_CONNECT)
	_check(not fetch.proxy_unreachable(), "one failure is not enough")
	fetch.note_transport_result(HTTPRequest.RESULT_CANT_RESOLVE)
	_check(fetch.proxy_unreachable(), "two failures in a row mean unreachable")
	fetch.note_transport_result(HTTPRequest.RESULT_SUCCESS)
	_check(not fetch.proxy_unreachable(), "any answer resets the count")

	# 届かないとき：待たずに切り替える
	var provider := _provider(fetch)
	fetch.transport_failures = 2
	provider._check_online_stall()  # 待ち始め
	provider._check_online_stall()
	_check(provider._round_bank_fallback, "an unreachable proxy switches the round to the bank at once")

	# 届いているときは 12 秒の待ちのまま（すぐには切り替えない）
	var fetch_ok := OnlineFetch.new()
	var waiting := _provider(fetch_ok)
	waiting._check_online_stall()
	waiting._check_online_stall()
	_check(not waiting._round_bank_fallback, "a reachable proxy keeps waiting for the AI questions")

	# 新しいラウンドで数え直す
	fetch.transport_failures = 5
	provider.begin_round("算数", 3, "普通", Constants.MODE_TEN, 10)
	_check(fetch.transport_failures == 0, "begin_round resets the unreachable count")

	OS.set_environment("APP_SECRET", had_secret)
	provider.free()
	waiting.free()
	fetch.free()
	fetch_ok.free()
	print("OFFLINE_FAST_FALLBACK " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _provider(fetch: OnlineFetch) -> BufferedQuizProvider:
	var provider := BufferedQuizProvider.new()
	provider.online_fetcher = fetch
	provider.llm_mode = "ONLINE"
	provider.is_active_round = true
	provider.current_mode = Constants.MODE_TEN
	provider.target_count = 10
	return provider


func _check(ok: bool, label: String, detail: Variant = null) -> void:
	checks += 1
	if not ok:
		failures.append(label if detail == null else "%s: %s" % [label, str(detail)])

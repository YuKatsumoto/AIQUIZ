extends Node

## 共有バンクの全件の取り込み（FirebaseQuizCache._download_snapshot）は、手元の判定に合わない問題が
## 1 件混ざっていても、その 1 件だけを飛ばして残りを取り込む（差分の取り込みと同じ）。
## 以前は全体を失敗にしていて、はじめて起動した PC（必ず全件を取り込む）で共有バンクが一度も入らなかった。
## 通信はしない（サーバーへの問い合わせを差し替える）。
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/firebase_snapshot_skip_bootstrap.gd

class FakeCache extends FirebaseQuizCache:
	var pages: Array = []
	func _request_json(_method: int, _url: String, _payload: Dictionary) -> Dictionary:
		return {"ok": true, "code": 200, "data": pages.pop_front()}

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var cache := FakeCache.new()
	var good_a := {"id": "a", "q": "3 + 4 は いくつ？", "c": ["7", "8"], "a": 0, "subject": "算数", "grade": 1, "difficulty": "普通"}
	var good_b := {"id": "b", "q": "5 + 1 は いくつ？", "c": ["6", "9"], "a": 0, "subject": "算数", "grade": 1, "difficulty": "普通"}
	var bad_empty := {"id": "c", "q": "", "c": ["1", "2"], "a": 0, "subject": "算数", "grade": 1, "difficulty": "普通"}
	var bad_answer := {"id": "d", "q": "2 + 2 は？", "c": ["4", "5"], "a": 5, "subject": "算数", "grade": 1, "difficulty": "普通"}
	cache.pages = [
		{"version": FirebaseQuizCache.CACHE_VERSION, "revision": 7, "sync_since": 100, "items": [good_a, bad_empty], "next_cursor": "p2"},
		{"version": FirebaseQuizCache.CACHE_VERSION, "revision": 7, "items": [bad_answer, good_b], "next_cursor": ""},
	]
	var result: Dictionary = await cache._download_snapshot()
	_check(bool(result.get("ok", false)), "a snapshot with a few bad items still succeeds", result)
	var ids: Array[String] = []
	for item: Dictionary in result.get("items", []):
		ids.append(str(item.get("id", "")))
	_check(ids == ["a", "b"], "the good items are kept and the bad ones skipped", ids)
	_check(int(result.get("revision", 0)) == 7 and int(result.get("sync_since", 0)) == 100, "revision and sync point are kept", result)
	cache.free()
	print("FIREBASE_SNAPSHOT_SKIP " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String, detail: Variant = null) -> void:
	checks += 1
	if not ok:
		failures.append(label if detail == null else "%s: %s" % [label, str(detail)])

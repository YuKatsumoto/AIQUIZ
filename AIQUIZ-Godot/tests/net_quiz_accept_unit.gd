extends Node

## オンライン対戦のゲストが、ホストから届いた問題を受け入れるか（NetGameState.is_playable_network_quiz）。
## ホストは同じ問題で扉を判定するので、内蔵の問題にある長い問題文・長い選択肢（60 字・20 字を超える）でも
## ゲストは捨ててはいけない（捨てるとゲストだけ前の問題のまま走る）。壊れたデータだけを弾く。
## 内蔵の問題（offline_bank.json）を全部通して、1 問も捨てないことも確かめる。
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/net_quiz_accept_bootstrap.gd

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var long_question := QuizItem.create("【くらべかた】2つのコップの水のおおさをくらべるには、どうすればいいですか？ もういちど よく かんがえて こたえを えらぼう。",
		PackedStringArray(["ちがうかたちのコップに入れる", "おなじかたちのコップにうつしかえてくらべる", "おもさをはかる", "ひやす"]), 1)
	_check(long_question.q.length() > 60, "fixture: the question is longer than 60 characters")
	_check(NetGameState.is_playable_network_quiz(long_question), "Long bank question is accepted by the guest")
	_check(NetGameState.is_playable_network_quiz(QuizItem.create("1+1は？", PackedStringArray(["2", "3"]), 0)), "Two-door question is accepted")
	_check(not NetGameState.is_playable_network_quiz(null), "Missing question is rejected")
	_check(not NetGameState.is_playable_network_quiz(QuizItem.create("  ", PackedStringArray(["a", "b"]), 0)), "Empty question text is rejected")
	_check(not NetGameState.is_playable_network_quiz(QuizItem.create("q", PackedStringArray(["a"]), 0)), "One choice is rejected")
	_check(not NetGameState.is_playable_network_quiz(QuizItem.create("q", PackedStringArray(["a", "b", "c", "d", "e"]), 0)), "Five choices are rejected")
	_check(not NetGameState.is_playable_network_quiz(QuizItem.create("q", PackedStringArray(["a", ""]), 0)), "Empty choice is rejected")
	_check(not NetGameState.is_playable_network_quiz(QuizItem.create("q", PackedStringArray(["a", "b"]), 2)), "Answer out of range is rejected")
	_check(not NetGameState.is_playable_network_quiz(QuizItem.create("q", PackedStringArray(["a", "b"]), -1)), "Negative answer is rejected")
	_check_bank()
	print("NET_QUIZ_ACCEPT " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)


## 内蔵の問題は、どれもゲストが受け入れる（ホストがそのまま出すので）。
func _check_bank() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://offline_bank.json"))
	var items: Array = []
	_collect(parsed, items)
	_check(items.size() > 1000, "fixture: the bundled bank has questions", items.size())
	var rejected: Array[String] = []
	for raw: Dictionary in items:
		var quiz := QuizItem.create(str(raw.get("q", "")), PackedStringArray(raw.get("c", [])), int(raw.get("a", 0)))
		if not NetGameState.is_playable_network_quiz(quiz):
			rejected.append(str(raw.get("q", "")).left(30))
	_check(rejected.is_empty(), "Every bundled question is playable for the guest", rejected.slice(0, 5))


func _collect(node: Variant, out: Array) -> void:
	if node is Dictionary:
		var dict := node as Dictionary
		if dict.has("q") and dict.has("c"):
			out.append(dict)
			return
		for value: Variant in dict.values():
			_collect(value, out)
	elif node is Array:
		for value: Variant in node:
			_collect(value, out)


func _check(ok: bool, label: String, detail: Variant = null) -> void:
	checks += 1
	if not ok:
		failures.append(label if detail == null else "%s: %s" % [label, str(detail)])

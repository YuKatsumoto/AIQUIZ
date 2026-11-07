extends Node

## 「難しい」の選択肢の作り替え（QuizProvider._harden_distractors）。
## 計算の問題は誤答を正解の近くの数に置き換えて紛らわしくする。性質や大きさで選ばせる問題
## （「〜でない数はどれ」「倍数はどれ」「いちばん大きい」「およそ」）は置き換えない
## （置き換えた数も条件に当てはまり、正解がいくつもある問題になるため）。
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/harden_distractors_bootstrap.gd

class TestProvider extends QuizProvider:
	func _load_bank() -> Dictionary:
		return {}

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var provider := TestProvider.new()
	var not_divisor := QuizItem.create("16と40の公約数でない数はどれですか？", PackedStringArray(["2", "16", "4", "8"]), 1)
	for i: int in range(20):
		var out := provider._harden_distractors(not_divisor)
		_check(out.c == not_divisor.c and out.a == 1, "\"でない\" question keeps its own choices", out.c)
	var multiple := QuizItem.create("6と9の公倍数はどれですか？", PackedStringArray(["12", "18", "24", "30"]), 1)
	_check(provider._harden_distractors(multiple).c == multiple.c, "multiple question keeps its own choices")
	var biggest := QuizItem.create("いちばんおおきいかずはどれでしょう？", PackedStringArray(["15", "51", "100", "99"]), 2)
	_check(provider._harden_distractors(biggest).c == biggest.c, "\"いちばん\" question keeps its own choices")
	var about := QuizItem.create("富士山の高さはおよそ何mですか？", PackedStringArray(["3776m", "1000m", "8848m", "634m"]), 0)
	_check(provider._harden_distractors(about).c == about.c, "\"およそ\" question keeps its own choices")
	# 計算の問題はこれまでどおり近い数に置き換わり、正解はちょうど 1 つ
	var sum := QuizItem.create("【けいさん】48 ＋ 7 ＝ ？", PackedStringArray(["55", "57", "56", "155"]), 0)
	var hardened_once := false
	for i: int in range(20):
		var out := provider._harden_distractors(sum)
		if out.c != sum.c:
			hardened_once = true
		_check(out.c.size() == 4 and out.c[out.a] == "55", "computation keeps the right answer", [out.c, out.a])
		var seen := {}
		for choice: String in out.c:
			seen[choice] = true
		_check(seen.size() == 4, "computation choices stay distinct", out.c)
	_check(hardened_once, "computation choices are still made harder")
	provider.free()
	print("HARDEN_DISTRACTORS " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String, detail: Variant = null) -> void:
	checks += 1
	if not ok:
		failures.append(label if detail == null else "%s: %s" % [label, str(detail)])

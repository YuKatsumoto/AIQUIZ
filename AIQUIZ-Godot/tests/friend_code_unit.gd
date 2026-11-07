extends Node

## 「ともだちと あそぶ」のコードの入力（OnlineFriendPage.normalize_code / is_code_text）。
## 日本語入力が ON のまま打った全角の英数字を半角に直し、空白を取り、大文字にする。かなは使えない文字として見分ける。
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/friend_code_bootstrap.gd

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	_expect("Ｋ７ＸＱＭ", "K7XQM", "full-width code becomes half-width")
	_expect("ｋ７ｘｑｍ", "K7XQM", "full-width lowercase becomes upper half-width")
	_expect("k7xqm", "K7XQM", "lowercase becomes upper")
	_expect(" K7X QM ", "K7XQM", "spaces are removed")
	_expect("K7X　QM", "K7XQM", "full-width space is removed")
	_expect("K7XQM", "K7XQM", "a typed code is unchanged")
	_check(OnlineFriendPage.is_code_text("K7XQM"), "letters and digits are code text")
	_check(not OnlineFriendPage.is_code_text(OnlineFriendPage.normalize_code("か7XQM")), "kana is not code text")
	_check(not OnlineFriendPage.is_code_text("K7-QM"), "symbols are not code text")
	print("FRIEND_CODE " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(typed: String, wanted: String, label: String) -> void:
	var got := OnlineFriendPage.normalize_code(typed)
	_check(got == wanted, label, got)


func _check(ok: bool, label: String, detail: Variant = null) -> void:
	checks += 1
	if not ok:
		failures.append(label if detail == null else "%s: %s" % [label, str(detail)])

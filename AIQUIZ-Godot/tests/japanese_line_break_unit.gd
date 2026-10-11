extends SceneTree

## 扉と問題文の改行位置: 文節の切れ目で改行し、語の途中や1文字だけの行を作らない。
## Run: Godot --headless --path . --script tests/japanese_line_break_unit.gd

const Breaker = preload("res://scripts/core/japanese_line_breaker.gd")
const FONT: Font = preload("res://resources/fonts/NotoSansJP-Regular.otf")
const SIZE := 64

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	# 1行に入る全角文字数で幅を指定する。
	_expect("針が0を指すか確認する", 5, "針が0を\n指すか\n確認する")
	_expect("ななめの場所に置く", 5, "ななめの\n場所に置く")
	_expect("りんごをたべる", 5, "りんごを\nたべる")
	_expect("ランプ → あんどん → 電球", 6, "ランプ →\nあんどん →\n電球")
	_expect("線対称でも点対称でもない", 6, "線対称でも\n点対称でも\nない")
	_expect("富士山", 5, "富士山")
	_expect("3\n──\n5", 5, "3\n──\n5")
	_expect("【重さのはかり方】はかりを使うときの正しい使い方はどれですか？", 20,
		"【重さのはかり方】はかりを使うときの\n正しい使い方はどれですか？")
	# 収まらない長い語は割るが、行頭禁則と1文字の行は避ける。
	var long := Breaker.layout("フランシスコ・ザビエル", FONT, SIZE, _width(5))
	_check(long.split_words > 0, "long word is split when it cannot fit")
	for line: String in long.text.split("\n"):
		_check(line.length() > 1 and not line.begins_with("・") and not line.begins_with("ー"), "no orphan or prohibited line start: " + long.text)
	print("japanese_line_break_unit: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures:
		printerr(failure)
	quit(1 if failures.size() > 0 else 0)


func _width(chars: int) -> float:
	return FONT.get_string_size("あ", HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x * chars + 1.0


func _expect(text: String, chars: int, expected: String) -> void:
	var result := Breaker.layout(text, FONT, SIZE, _width(chars))
	_check(result.text == expected and result.split_words == 0,
		"%s -> %s (expected %s)" % [text.c_escape(), String(result.text).c_escape(), expected.c_escape()])


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

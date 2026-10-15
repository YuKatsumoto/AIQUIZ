extends SceneTree

## 扉の選択肢が語の途中で改行されないことを確かめる。
## godot --headless --path . --script res://tests/choice_line_breaker_unit.gd
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	var wall: Node3D = load("res://scripts/world/quiz_wall.gd").new()
	root.add_child(wall)
	wall.set_quiz(QuizItem.create("q", PackedStringArray(["a", "b", "c", "d"]), 0), 4)
	var font: Font = wall.door_labels[0].font
	var box: Vector2 = wall._door_label_box(0)
	# 改行してはいけない位置 ("|" の前後) を含む例。
	for case: String in ["二酸化炭|素を出し、酸素を受け取る", "雨でも、ぬれずに買い|物ができる", "生産|量の増加",
			"ビニー|ルシート", "Because I like swim|ming.", "魚屋やスー|パー→漁港で水あげ→市場でせり→家庭",
			"せんたく|ばさみ", "1a（アー|ル）", "元禄文|化・化政文化"]:
		var text := case.replace("|", "")
		var forbidden := case.find("|")
		var laid := ChoiceLineBreaker.layout(text, font, box, wall.CHOICE_FONT_SIZE_MIN, wall.CHOICE_FONT_SIZE_MAX)
		check(not laid.is_empty(), "laid out: " + text)
		if laid.is_empty():
			continue
		var shown: String = laid.text
		check(shown.replace("\n", "").replace(" ", "") == text.replace(" ", ""), "keeps every character: " + shown)
		check(not _breaks_at(shown, text, forbidden), "no break inside a word: " + shown.replace("\n", " | "))
		check(int(laid.font_size) >= wall.CHOICE_FONT_SIZE_MIN, "readable size: %s @%d" % [text, laid.font_size])
		check(_fits(shown, font, laid.font_size, box), "fits the door: " + text)
	# 1行で十分大きく出せる短い答えは改行しない。
	for text: String in ["東京", "富士山", "じゅういち", "何時ちょうど"]:
		var laid := ChoiceLineBreaker.layout(text, font, box, wall.CHOICE_FONT_SIZE_MIN, wall.CHOICE_FONT_SIZE_MAX)
		check(not laid.is_empty() and not String(laid.text).contains("\n"), "single line: " + text)
	# 縦積みの分数はそのまま従来の折り返しに任せる。
	check(ChoiceLineBreaker.layout("3\n──\n5", font, box, 36, 120).is_empty(), "stacked fraction untouched")
	print("CHOICE_LINE_BREAKER_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


## shown の改行位置が、元の文字列の forbidden 文字目の直前に当たるか。
func _breaks_at(shown: String, text: String, forbidden: int) -> bool:
	var index := 0
	for c: String in shown:
		if c == "\n":
			if index == forbidden:
				return true
			continue
		while index < text.length() and text[index] == " " and c != " ":
			index += 1
		index += 1
	return false


func _fits(text: String, font: Font, font_size: int, box: Vector2) -> bool:
	var tp := TextParagraph.new()
	tp.add_string(text, font, font_size)
	var outline := maxi(1, roundi(float(font_size) / 6.0))
	var size := tp.get_size() + Vector2.ONE * outline * 2.0
	return size.x <= box.x and size.y <= box.y


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

extends RefCounted
class_name KanjiGrade

## 学年別漢字配当表（assets/curriculum/kanji_grades.json）で、問題の文字がその学年までに習う漢字だけか調べる。
## その学年とそれより下の学年の字は使ってよい。表にない漢字（中学以降）は使わない。
## 問題を弾くのは CHECKED_UP_TO_GRADE 年生まで。それより上の学年は漢字を制限しない。
## ひらがな・カタカナ・英数字・記号、踊り字の「々」、地図記号や部首の形（表の symbols）は数えない。

const TABLE_PATH := "res://assets/curriculum/kanji_grades.json"
## 表にない漢字の学年（小学校では習わない）
const NOT_IN_TABLE := 7
## 漢字の学年で問題を弾く一番上の学年
const CHECKED_UP_TO_GRADE := 3

## 漢字 → 配当学年（1〜6）。初めて使うときに読む。
static var _grade_of: Dictionary = {}
## 学年に関係なく使ってよい字（地図記号・部首の形）
static var _symbols: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if file == null:
		push_warning("KanjiGrade: Cannot open: %s" % TABLE_PATH)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary or not (data as Dictionary).get("grades") is Dictionary:
		push_warning("KanjiGrade: Bad table: %s" % TABLE_PATH)
		return
	var grades: Dictionary = data["grades"]
	for key: Variant in grades.keys():
		var chars := str(grades[key])
		for i in range(chars.length()):
			_grade_of[chars[i]] = int(key)
	var symbols := str((data as Dictionary).get("symbols", ""))
	for i in range(symbols.length()):
		_symbols[symbols[i]] = true


## 表を読めたか。読めないときは over_grade が何も返さない（問題を弾かない）。
static func is_available() -> bool:
	_ensure_loaded()
	return not _grade_of.is_empty()


## grade 年生の問題を漢字の学年で弾くか。
static func checks_grade(grade: int) -> bool:
	return grade >= 1 and grade <= CHECKED_UP_TO_GRADE


## 漢字なら配当学年（表になければ NOT_IN_TABLE）、漢字でないか学年に関係なく使える字なら 0。
static func grade_of(ch: String) -> int:
	if ch.is_empty() or not _is_kanji(ch.unicode_at(0)):
		return 0
	_ensure_loaded()
	if _symbols.has(ch):
		return 0
	return int(_grade_of.get(ch, NOT_IN_TABLE))


## text の中の、grade 年生ではまだ習わない漢字（重複なし、出てきた順）。
static func over_grade(text: String, grade: int) -> PackedStringArray:
	var found := PackedStringArray()
	if not is_available():
		return found
	for i in range(text.length()):
		var ch := text[i]
		if grade_of(ch) > grade and not found.has(ch):
			found.append(ch)
	return found


## 問題文と選択肢の、grade 年生ではまだ習わない漢字。弾かない学年では空。
static func over_grade_in_quiz(question: String, choices: PackedStringArray, grade: int) -> PackedStringArray:
	if not checks_grade(grade):
		return PackedStringArray()
	return over_grade(question + "\n" + "\n".join(choices), grade)


## プロンプトに渡す、grade 年生までに習う漢字の一覧（学年ごとに1行）。
static func allowed_kanji_lines(grade: int) -> PackedStringArray:
	_ensure_loaded()
	var by_grade: Dictionary = {}
	for ch: String in _grade_of.keys():
		var g := int(_grade_of[ch])
		if g <= grade:
			by_grade[g] = str(by_grade.get(g, "")) + ch
	var lines := PackedStringArray()
	for g in range(1, grade + 1):
		if by_grade.has(g):
			lines.append("%d年: %s" % [g, by_grade[g]])
	return lines


static func _is_kanji(code: int) -> bool:
	return (code >= 0x4E00 and code <= 0x9FFF) \
		or (code >= 0x3400 and code <= 0x4DBF) \
		or (code >= 0xF900 and code <= 0xFAFF) \
		or (code >= 0x20000 and code <= 0x2FA1F)

extends RefCounted

## 地下神殿の講義の時間割と、教科の授業の台本づくり（docs/lecture_hall_plan.md の項目 50〜57）。
## 設定画面を開くたびに次の講義へ進む（user:// に回数を保存）: 第 1 講 連結チップソー概論 → 算数 → 理科 → 国語（縦書き）
## → 社会 → 英語 → 小テスト → 連結チップソー（実演つき）→ 期末テスト → 卒業式 → また第 1 講（学年が 1 つ上がる）。
## 教科の授業は res://offline_bank.json（教科 → 学年 → [{q, c, a, exp}]）から 1 問ずつ選び、問題・選択肢を書いて
## 「わかる人？」→ 答えを赤で囲む → 解説を書く。学年が低いほど字が大きい。教科ごとに図（筆算・図・年表・4 本線）を添える。
## 台本の段は lessons/lesson_03.json と同じ形（lecture_director.gd がそのまま流す）。

const BANK_PATH := "res://offline_bank.json"
const VISITS_PATH := "user://lecture_visits.json"
const PLAN := [
	{"kind": "hazard"}, {"kind": "subject", "subject": "算数"}, {"kind": "subject", "subject": "理科"},
	{"kind": "subject", "subject": "国語"}, {"kind": "subject", "subject": "社会"}, {"kind": "subject", "subject": "英語"},
	{"kind": "quiz"}, {"kind": "hazard"}, {"kind": "exam"}, {"kind": "graduation"},
]
## 板書の範囲（黒板 F の u、m）と、手の届く高さの 3 行（v、m）。
const LEFT_U := 0.4
const RIGHT_U := 3.6
const ROWS := [0.42, 0.22, 0.03]
const ERAS := ["縄文", "弥生", "古墳", "飛鳥", "奈良", "平安", "鎌倉", "室町", "江戸", "明治"]

var glyphs = null
var rng := RandomNumberGenerator.new()
var _bank: Dictionary = {}


func _init(glyph_book) -> void:
	glyphs = glyph_book


## 訪問の回数を 1 進めて返す（0 から）。
static func next_visit() -> int:
	var visits := 0
	if FileAccess.file_exists(VISITS_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(VISITS_PATH))
		if data is Dictionary:
			visits = int((data as Dictionary).get("visits", 0))
	var forced := OS.get_environment("AIQUIZ_LECTURE_VISIT")
	if forced != "":
		return int(forced)
	var file := FileAccess.open(VISITS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"visits": visits + 1}))
	return visits


## visit 回目の講義: {kind, subject, grade, number, title, subtitle}。
static func lecture(visit: int) -> Dictionary:
	var plan: Dictionary = PLAN[visit % PLAN.size()]
	var lec := plan.duplicate()
	lec.number = visit + 1
	lec.grade = 1 + int(visit / PLAN.size()) % 6
	match str(plan.kind):
		"hazard":
			lec.title = "連結チップソー概論"
			lec.subtitle = "第%d講　安全な観察距離と回転数" % lec.number
		"subject":
			lec.title = str(plan.subject)
			lec.subtitle = "第%d講　%d年生のおさらい" % [lec.number, lec.grade]
		"quiz":
			lec.title = "小テスト"
			lec.subtitle = "第%d講　前回までのまとめ" % lec.number
		"exam":
			lec.title = "期末テスト"
			lec.subtitle = "第%d講　時間は30分" % lec.number
		"graduation":
			lec.title = "卒業おめでとう"
			lec.subtitle = "第%d講　卒業式" % lec.number
	return lec


func _load_bank() -> void:
	if not _bank.is_empty() or not FileAccess.file_exists(BANK_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BANK_PATH))
	if data is Dictionary:
		_bank = data


## 教科の授業の周（3 周、問題は毎周ちがう）。
func build_subject(subject: String, grade: int, seed_value: int) -> Array:
	_load_bank()
	rng.seed = seed_value
	var cycles: Array = []
	var used := {}
	for k in range(3):
		var q := _pick_question(subject, grade, used)
		if q.is_empty():
			break
		cycles.append({"name": "%s %d" % [subject, k + 1], "steps": _subject_cycle(subject, grade, q, k)})
	return cycles


func _pick_question(subject: String, grade: int, used: Dictionary) -> Dictionary:
	var grades: Dictionary = _bank.get(subject, {})
	if grades.is_empty():
		return {}
	var keys := grades.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return absi(int(str(a)) - grade) < absi(int(str(b)) - grade))
	var vertical := subject == "国語"
	var h := _char_height(grade, vertical)
	for key: Variant in keys:
		var items: Array = grades[key]
		var tries := 0
		while tries < 200:
			tries += 1
			var q: Dictionary = items[rng.randi() % items.size()]
			var text := _clean(str(q.get("q", "")))
			if used.has(text) or not _all_glyphs(text + str(q.get("exp", "")) + "".join(PackedStringArray(q.get("c", [])))):
				continue
			if not _fits(text, q, h, vertical):
				continue
			used[text] = true
			var out := q.duplicate()
			out.q = text
			out.grade_used = int(str(key))
			return out
	return {}


static func _clean(text: String) -> String:
	# 【たし算】のような見出しは黒板の頭の教科名で足りるので外す
	var t := text.strip_edges()
	if t.begins_with("【") and t.find("】") > 0:
		t = t.substr(t.find("】") + 1)
	return t.replace(" ", "").replace("　", "")


func _all_glyphs(text: String) -> bool:
	for ch in text:
		if ch.strip_edges() != "" and not glyphs.has_glyph(ch):
			return false
	return true


func _char_height(grade: int, vertical: bool) -> float:
	# 1 年生は大きな字、6 年生は細かい字（項目 54）
	var h := lerpf(0.19, 0.13, clampf((grade - 1) / 5.0, 0.0, 1.0))
	return h * (0.82 if vertical else 1.0)


func _fits(text: String, q: Dictionary, h: float, vertical: bool) -> bool:
	if vertical:
		return text.length() <= 32 and str(q.get("exp", "")).length() <= 20
	var per_line := int((RIGHT_U - LEFT_U) / (h * 1.0))
	if text.length() > per_line * 2 or str(q.get("exp", "")).length() > 22:
		return false
	var choices := _choices_line(q)
	return glyphs.measure(choices, 0.12) < 3.3


static func _choices_line(q: Dictionary) -> String:
	var marks := ["①", "②", "③", "④"]
	var parts: Array = []
	var c: Array = q.get("c", [])
	for i in range(mini(4, c.size())):
		parts.append(marks[i] + str(c[i]))
	return "  ".join(PackedStringArray(parts))


## 1 周の台本: 問題を書く → 図 → わかる人？ → 答えを赤で囲む → 解説 → 指して読む → 消す。
func _subject_cycle(subject: String, grade: int, q: Dictionary, index: int) -> Array:
	var vertical := subject == "国語"
	var h := _char_height(grade, vertical)
	var steps: Array = [
		{"do": "walk", "to": "lectern", "face": 180},
		{"do": "explain", "secs": 2.5, "cue": "listen"},
		{"do": "pick", "color": "white"},
	]
	if vertical:
		steps.append_array(_vertical_question(q, h))
	else:
		steps.append_array(_horizontal_question(subject, q, h))
	steps.append_array(_subject_drawing(subject, q))
	steps.append({"do": "ask", "text": "？", "at": [3.55 if not vertical else 4.4, 0.42], "call": ["student_hand", "student_notes"][index % 2]})
	steps.append_array(_answer(subject, q, h, vertical))
	steps.append({"do": "gag", "pool": ["clock", "sneeze", "snap_chalk", "look_up"]})
	steps.append({"do": "explain", "secs": 2.5, "cue": "listen"})
	steps.append({"do": "erase", "rect": [0.3, 0.0, 7.2 if vertical else 6.6, 0.62], "messy": index == 1})
	return steps


func _horizontal_question(subject: String, q: Dictionary, h: float) -> Array:
	var steps: Array = []
	var tag := "【%s】" % subject
	steps.append({"do": "write", "text": tag, "at": [LEFT_U, ROWS[0]], "h": h * 0.85, "color": "yellow", "cue": "notes"})
	var text: String = q.q
	var x0: float = LEFT_U + glyphs.measure(tag, h * 0.85) + 0.05
	var first_room := int((RIGHT_U - x0) / h)
	var line1 := text.substr(0, first_room)
	var line2 := text.substr(first_room)
	steps.append({"do": "write", "text": line1, "at": [x0, ROWS[0]], "h": h})
	if line2 != "":
		steps.append({"do": "write", "text": line2, "at": [LEFT_U, ROWS[1]], "h": h})
	steps.append({"do": "write", "text": _choices_line(q), "at": [LEFT_U, ROWS[2]], "h": 0.12})
	return steps


## 国語は縦書き（項目 51）: 黒板の右端から左へ、1 行 4 字で縦に下ろす。先生は右から左へ横歩きする。
func _vertical_question(q: Dictionary, h: float) -> Array:
	var steps: Array = []
	var text: String = q.q
	# 手の届く高さ（v 0.06〜0.6）に入る字数で折り返す
	var per_col := maxi(2, int(0.54 / (h * 1.04)))
	var u := 7.15
	var cols := ceili(float(text.length()) / per_col)
	for k in range(cols):
		var chunk := text.substr(k * per_col, per_col)
		steps.append({"do": "write_v", "text": chunk, "at": [u - h, 0.6 - h], "h": h, "color": "white", "cue": "notes" if k == 0 else ""})
		u -= h * 1.3
	# 選択肢: 1 つずつ縦に
	var c: Array = q.get("c", [])
	var marks := ["①", "②", "③", "④"]
	for i in range(mini(4, c.size())):
		steps.append({"do": "write_v", "text": marks[i] + str(c[i]).substr(0, 3), "at": [u - 0.12, 0.6 - 0.12], "h": 0.12, "color": "yellow"})
		u -= 0.17
	_last_vertical_u = u
	return steps


var _last_vertical_u := 0.0


## 教科ごとの図（項目 52）: 算数は筆算か数直線、理科は太陽と芽と矢印、社会は年表、英語は 4 本線。
func _subject_drawing(subject: String, q: Dictionary) -> Array:
	var steps: Array = []
	match subject:
		"算数":
			var re := RegEx.create_from_string("(\\d+)\\s*([＋+－\\-×x])\\s*(\\d+)")
			var m := re.search(str(q.q))
			if m != null:
				var a := m.get_string(1)
				var op := m.get_string(2).replace("+", "＋").replace("-", "－").replace("x", "×")
				var b := m.get_string(3)
				var width: int = maxi(a.length(), b.length()) + 1
				steps.append({"do": "write", "text": a.lpad(width), "at": [4.3, 0.42], "h": 0.15})
				steps.append({"do": "write", "text": op + b.lpad(width - 1), "at": [4.3, 0.25], "h": 0.15})
				steps.append({"do": "line", "from": [4.25, 0.22], "to": [4.3 + width * 0.1 + 0.08, 0.22], "color": "white"})
			else:
				steps.append({"do": "line", "from": [4.0, 0.25], "to": [5.6, 0.25], "color": "white"})
				for k in range(9):
					var u := 4.05 + k * 0.19
					steps.append({"do": "line", "from": [u, 0.21], "to": [u, 0.29], "color": "white"})
		"理科":
			steps.append({"do": "circle", "at": [4.35, 0.42], "r": 0.08, "color": "yellow"})
			steps.append({"do": "arc_jump", "from": [4.5, 0.36], "to": [5.1, 0.2], "height": 0.06, "color": "yellow"})
			steps.append({"do": "line", "from": [5.3, 0.05], "to": [5.3, 0.3], "color": "white"})
			steps.append({"do": "circle", "at": [5.22, 0.26], "r": 0.05, "color": "white"})
			steps.append({"do": "circle", "at": [5.38, 0.2], "r": 0.05, "color": "white"})
		"社会":
			steps.append({"do": "line", "from": [3.9, 0.2], "to": [6.3, 0.2], "color": "white"})
			var mentioned := ""
			for era: String in ERAS:
				if str(q.q).contains(era) or str(q.get("exp", "")).contains(era) or "".join(PackedStringArray(q.get("c", []))).contains(era):
					mentioned = era
			for k in range(6):
				var u := 3.95 + k * 0.4
				steps.append({"do": "line", "from": [u, 0.17], "to": [u, 0.24], "color": "white"})
				steps.append({"do": "write", "text": ERAS[k], "at": [u - 0.04, 0.27], "h": 0.08,
					"color": "red" if ERAS[k] == mentioned else "white"})
		"英語":
			# 4 本線（英語のノートと同じ）
			for k in range(4):
				var v := 0.1 + k * 0.045
				steps.append({"do": "line", "from": [3.95, v], "to": [6.2, v], "color": "white" if k != 2 else "red"})
	return steps


## 答え: 横書きは選択肢を赤で囲み、右に「答え」と解説。縦書きは選んだ選択肢の列を赤で囲み、左に解説を縦に。
func _answer(subject: String, q: Dictionary, h: float, vertical: bool) -> Array:
	var steps: Array = []
	var a := int(q.get("a", 0))
	var c: Array = q.get("c", [])
	var exp := str(q.get("exp", ""))
	if vertical:
		var u_choice: float = _last_vertical_u + 0.17 * (4 - a) - 0.06
		steps.append({"do": "circle", "at": [u_choice, 0.42], "r": 0.12, "color": "red", "wobble": 0.0})
		var u: float = _last_vertical_u - 0.05
		var per_col := maxi(2, int(0.54 / (0.12 * 1.04)))
		for k in range(ceili(float(exp.length()) / per_col)):
			steps.append({"do": "write_v", "text": exp.substr(k * per_col, per_col), "at": [u - 0.12, 0.6 - 0.12], "h": 0.12, "color": "yellow"})
			u -= 0.16
		return steps
	# 正しい選択肢の位置（①…の並びの中）
	var line := _choices_line(q)
	var mark: String = ["①", "②", "③", "④"][clampi(a, 0, 3)]
	var start := line.find(mark)
	var before := line.substr(0, start)
	var x0: float = LEFT_U + glyphs.measure(before, 0.12)
	var w: float = glyphs.measure(mark + str(c[a] if a < c.size() else ""), 0.12)
	steps.append({"do": "circle", "at": [x0 + w * 0.5, ROWS[2] + 0.06], "r": maxf(0.09, w * 0.6), "color": "red"})
	if subject == "英語":
		# 答えの語を 4 本線の上に（筆記体らしく傾けて続け書き）
		steps.append({"do": "write_cursive", "text": str(c[a] if a < c.size() else ""), "at": [4.0, 0.1], "h": 0.135, "color": "white"})
	elif subject == "算数" and steps.size() > 0:
		steps.append({"do": "write", "text": "答え " + str(c[a] if a < c.size() else ""), "at": [4.3, 0.04], "h": 0.13, "color": "red"})
	# 解説: 図の右（社会は年表の上）に 2 行まで
	var ex_u := 3.95 if subject == "社会" else 5.6
	var per_line := 11 if subject != "社会" else 20
	var ex_lines := [exp.substr(0, per_line), exp.substr(per_line, per_line)]
	steps.append({"do": "write", "text": ex_lines[0], "at": [ex_u, 0.47], "h": 0.11, "color": "yellow"})
	if ex_lines[1] != "" and subject != "社会":
		steps.append({"do": "write", "text": ex_lines[1], "at": [ex_u, 0.32], "h": 0.11, "color": "yellow"})
	return steps


# ------------------------------------------------------------------ quiz / exam / graduation

## 小テスト・期末テスト（項目 57）: プリントを配る → 解く → チャイムで集める → 教壇で赤ペン採点 → 平均点を書く。
func build_test(exam: bool, seed_value: int) -> Array:
	rng.seed = seed_value
	var title := "期末テスト" if exam else "小テスト"
	var steps: Array = [
		{"do": "walk", "to": "lectern", "face": 180},
		{"do": "explain", "secs": 2.0, "cue": "listen"},
		{"do": "pick", "color": "white"},
		{"do": "write", "text": title, "at": [0.5, 0.36], "h": 0.22, "color": "yellow"},
		{"do": "write", "text": "はじめ！", "at": [1.9 if exam else 1.6, 0.36], "h": 0.2, "color": "red"},
		{"do": "handout"},
		{"do": "chime"},
		{"do": "solve", "secs": 28.0 if exam else 18.0},
		{"do": "chime"},
		{"do": "collect"},
		{"do": "grade_papers", "secs": 14.0},
		{"do": "write", "text": "平均%d点" % rng.randi_range(72, 96), "at": [0.5, 0.08], "h": 0.2, "color": "white"},
		{"do": "clip", "name": "T_HappyHop"},
		{"do": "erase", "rect": [0.3, 0.0, 3.4, 0.62]},
	]
	return [{"name": title, "steps": steps}]


## 卒業式: 黒板に「卒業おめでとう」と花、日直の号令、ひとりずつ卒業証書を受け取る、保護者も拍手、最後はみんなでばんざい。
func build_graduation() -> Array:
	var steps: Array = [
		{"do": "event", "name": "parent"},
		{"do": "walk", "to": "lectern", "face": 180},
		{"do": "pick", "color": "white"},
		{"do": "write", "text": "卒業おめでとう", "at": [0.5, 0.33], "h": 0.24, "color": "yellow"},
		{"do": "hanamaru", "at": [2.75, 0.3], "r": 0.2, "color": "red"},
		{"do": "hanamaru", "at": [3.25, 0.18], "r": 0.13, "color": "blue"},
		{"do": "walk", "to": "lectern", "face": 180},
		{"do": "event", "name": "rei"},
		{"do": "diplomas"},
		{"do": "cheer_all"},
		{"do": "event", "name": "parent_leave"},
	]
	return [{"name": "卒業式", "steps": steps}]

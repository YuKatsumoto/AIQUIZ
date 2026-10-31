@tool
extends RefCounted

## チュートリアルのセリフ（scripts/practice/practice_texts.gd の TEXTS）を読み書きする。セリフの下パネル（practice_text_dock.gd）の中身。
## 書き戻すのは直した行の値だけ（行の並び・コメント・改行コードはそのまま）。
## 台本の表（docs/new_tutorial/courseN_script.md の「4. 文字の一覧」）も、同じ ID の行の「文字」を直す。

const TEXTS_PATH := "res://scripts/practice/practice_texts.gd"
const DOC_PATH := "res://docs/new_tutorial/course%d_script.md"
const SCRIPTS_ROOT := "res://scripts"
## 台本 1.1 の文字の決まり。
const BUBBLE_MAX := 18
const WALL_LINES_MAX := 2
const WALL_LINE_MAX := 14
const DOOR_MAX := 5
const SIGN_LINES_MAX := 2
## 特例：吹き出しの文字数の決まり（BUBBLE_MAX）を超えても1つの吹き出しのまま出すセリフの ID（吹き出しは折り返さず1行で出る）。
const BUBBLE_LONG_OK := ["c5.speed.4"]

static var _entry_re := RegEx.create_from_string(r'^\t"([^"]+)": "((?:[^"\\]|\\.)*)",(.*)$')
static var _doc_row_re := RegEx.create_from_string(r'^\| (\S+) \| ([^|]*) \| (.*) \|$')
static var _course_re := RegEx.create_from_string(r'^c(\d+)\.')
static var _section_re := RegEx.create_from_string(r'コース(\S)\s*「([^」]+)」')
static var _literal_re := RegEx.create_from_string(r'"([A-Za-z][\w%]*(?:\.[\w%]+)+)"')
static var _text_id_re := RegEx.create_from_string(r'text_id\("([^"]+)"\)')

## 読み書きするファイル（テストでは写しに差し替える）。
var texts_path := TEXTS_PATH
var doc_path := DOC_PATH

## 1つのセリフ：{id, text, where, section, line, suffix}。text は読み込んだときの文字、where は行末のコメント（出る所）、
## section は sections の番号、line は TEXTS の行の番号（0 から）、suffix は値のあとの「,」より後ろ（コメント）。
var entries: Array[Dictionary] = []
## TEXTS の中の見出し（「# コース① 「基本操作」 台本…」の「#」より後ろ）の並び。
var sections: Array[String] = []

var _lines := PackedStringArray()
var _by_id := {}


## texts_path を読む。うまくいけば ""、だめなら理由。
func load_file() -> String:
	if not FileAccess.file_exists(texts_path):
		return "%s が見つからない" % texts_path
	var source := FileAccess.get_file_as_string(texts_path)
	if source.is_empty():
		return "%s を読めなかった（%s）" % [texts_path, error_string(FileAccess.get_open_error())]
	return parse(source)


## practice_texts.gd の中身を読む。うまくいけば ""、だめなら理由。
func parse(source: String) -> String:
	entries.clear()
	sections.clear()
	_by_id.clear()
	_lines = source.split("\n")
	var inside := false
	for i in _lines.size():
		var line := _lines[i].trim_suffix("\r")
		if not inside:
			inside = line.begins_with("const TEXTS")
			continue
		if line.begins_with("}"):
			break
		var m := _entry_re.search(line)
		if m != null:
			if sections.is_empty():
				sections.append("（見出しなし）")
			var suffix := m.get_string(3)
			var entry := {
				"id": m.get_string(1),
				"text": unescape(m.get_string(2)),
				"where": suffix.strip_edges().trim_prefix("#").strip_edges(),
				"section": sections.size() - 1,
				"line": i,
				"suffix": suffix,
			}
			entries.append(entry)
			_by_id[entry.id] = entry
			continue
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			sections.append(stripped.trim_prefix("#").strip_edges())
	if entries.is_empty():
		return "TEXTS の中にセリフが見つからない"
	return ""


func find(id: String) -> Dictionary:
	return _by_id.get(id, {})


## changes（ID → 新しい文字）を入れた practice_texts.gd の中身。直さない行は1文字も変えない。
func build_source(changes: Dictionary) -> String:
	var lines := _lines.duplicate()
	for entry in entries:
		if not changes.has(entry.id):
			continue
		var cr := "\r" if lines[entry.line].ends_with("\r") else ""
		lines[entry.line] = "\t\"%s\": \"%s\",%s%s" % [entry.id, escape(changes[entry.id]), entry.suffix, cr]
	return "\n".join(lines)


## changes を practice_texts.gd と台本の表に書く。originals は読み込んだときの文字（ID → 文字）。
## 書く直前にファイルを読み直し、読み込んだときから文字が変わっていた ID（ほかで直された）は書かずに conflicts に入れる。
## 返り値：{error, saved, conflicts, docs, doc_missing}。docs は書いた台本、doc_missing は台本の表に行がなかった ID。
func save_changes(changes: Dictionary, originals: Dictionary) -> Dictionary:
	var result := {"error": "", "saved": [], "conflicts": [], "docs": [], "doc_missing": []}
	var disk = _new_store()
	var err: String = disk.load_file()
	if not err.is_empty():
		result.error = err
		return result
	var apply := {}
	for id: String in changes:
		var entry: Dictionary = disk.find(id)
		if entry.is_empty() or entry.text != originals.get(id, entry.text):
			result.conflicts.append(id)
		else:
			apply[id] = changes[id]
	if apply.is_empty():
		return result
	var source: String = disk.build_source(apply)
	# 書く前に読み直して、セリフの数と直した文字がそろっているか確かめる。
	var check_store = _new_store()
	var parse_err: String = check_store.parse(source)
	if not parse_err.is_empty() or check_store.entries.size() != disk.entries.size():
		result.error = "書き戻した中身を読み直せなかった（%s）" % parse_err
		return result
	for id: String in apply:
		if check_store.find(id).get("text", null) != apply[id]:
			result.error = "「%s」をうまく書き戻せなかった" % id
			return result
	var write_err := _write(texts_path, source)
	if write_err != OK:
		result.error = "%s に書けなかった（%s）" % [texts_path, error_string(write_err)]
		return result
	result.saved = apply.keys()
	_save_docs(apply, result)
	return result


## 台本の表に、直した文字を入れる（コース①〜⑤の ID だけ。画面の文字は台本の表にない）。
func _save_docs(apply: Dictionary, result: Dictionary) -> void:
	var by_course := {}
	for id: String in apply:
		var course := course_of(id)
		if course > 0:
			var group: Dictionary = by_course.get_or_add(course, {})
			group[id] = apply[id]
	for course: int in by_course:
		var path := doc_path % course
		var group: Dictionary = by_course[course]
		if not FileAccess.file_exists(path):
			result.doc_missing.append_array(group.keys())
			continue
		var doc := FileAccess.get_file_as_string(path)
		var replaced := replace_doc_rows(doc, group)
		for id: String in group:
			if not replaced.updated.has(id):
				result.doc_missing.append(id)
		if replaced.text == doc:
			continue
		var err := _write(path, replaced.text)
		if err != OK:
			result.error = "%s に書けなかった（%s）。practice_texts.gd は書いた" % [path, error_string(err)]
		else:
			result.docs.append(path)


## 台本の中身 doc の表の行のうち、changes の ID の行の「文字」を差し替える。{text, updated: 差し替えた ID}。
static func replace_doc_rows(doc: String, changes: Dictionary) -> Dictionary:
	var lines := doc.split("\n")
	var updated: Array[String] = []
	for i in lines.size():
		if not lines[i].begins_with("| "):
			continue
		var cr := "\r" if lines[i].ends_with("\r") else ""
		var m := _doc_row_re.search(lines[i].trim_suffix("\r"))
		if m == null or not changes.has(m.get_string(1)):
			continue
		var id := m.get_string(1)
		lines[i] = "| %s | %s | %s |%s" % [id, m.get_string(2), String(changes[id]).replace("|", "\\|"), cr]
		updated.append(id)
	return {"text": "\n".join(lines), "updated": updated}


## ID のコースの番号（"c3.push.1" → 3）。コースの ID でなければ 0。
static func course_of(id: String) -> int:
	var m := _course_re.search(id)
	return m.get_string(1).to_int() if m != null else 0


## 見出しの短い名前（「コース① 「基本操作」 台本…」→「① 基本操作」、「画面の文字（…）」→「画面の文字」）。
static func section_label(title: String) -> String:
	var m := _section_re.search(title)
	if m != null:
		return "%s %s" % [m.get_string(1), m.get_string(2)]
	var cut := title.find("（")
	return title.substr(0, cut) if cut > 0 else title


## GDScript の "…" の中に書ける形にする。
static func escape(text: String) -> String:
	return text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t")


## escape の逆（\n・\t のほかは、\ の次の文字をそのまま）。
static func unescape(literal: String) -> String:
	var out := ""
	var i := 0
	while i < literal.length():
		var c := literal[i]
		if c == "\\" and i + 1 < literal.length():
			i += 1
			c = literal[i]
			if c == "n":
				c = "\n"
			elif c == "t":
				c = "\t"
		out += c
		i += 1
	return out


## 文字の決まり（台本 1.1）に合わない所と、元の文字から消えると困るもの。注意の文の並び（なければ空）。
static func check(text: String, where: String, original: String, id := "") -> PackedStringArray:
	var notes := PackedStringArray()
	if text.strip_edges().is_empty():
		notes.append("空になっている")
		return notes
	var parts := text.split("／")
	var before := original.split("／").size()
	if parts.size() != before:
		notes.append("「／」の区切りが %d つ → %d つ（元と数が違う）" % [before, parts.size()])
	if where.begins_with("ハテナ") and text.length() > BUBBLE_MAX and not BUBBLE_LONG_OK.has(id):
		notes.append("吹き出しは %d 文字まで（今 %d 文字）。長いときは吹き出しを2つに分ける" % [BUBBLE_MAX, text.length()])
	elif where.begins_with("壁のドア"):
		for part in parts:
			if part.length() > DOOR_MAX:
				notes.append("ドアの文字は %d 文字まで（「%s」は %d 文字）" % [DOOR_MAX, part, part.length()])
	elif where.begins_with("壁"):
		if parts.size() > WALL_LINES_MAX:
			notes.append("壁の問題文は %d 行まで" % WALL_LINES_MAX)
		for i in parts.size():
			if parts[i].length() > WALL_LINE_MAX:
				notes.append("壁の問題文は1行 %d 文字まで（%d 行目が %d 文字）" % [WALL_LINE_MAX, i + 1, parts[i].length()])
	elif where.begins_with("看板") and parts.size() > SIGN_LINES_MAX:
		notes.append("看板は %d 行まで" % SIGN_LINES_MAX)
	for spec in ["%d", "%s"]:
		if original.count(spec) != text.count(spec):
			notes.append("「%s」は数字や名前が入る所なので消さない" % spec)
	return notes


## 一覧に出す文字数（「／」で区切ってあれば、部品ごとの数を「・」でつなぐ）。
static func count_label(text: String) -> String:
	var counts := PackedStringArray()
	for part in text.split("／"):
		counts.append(str(part.length()))
	return "・".join(counts)


## ドアの番号の色（2択は 0 青・1 赤、4択は 0 青・1 緑・2 オレンジ・3 赤）。ほかの数なら空。
static func door_colors(count: int) -> PackedStringArray:
	match count:
		2:
			return PackedStringArray(["青", "赤"])
		4:
			return PackedStringArray(["青", "緑", "オレンジ", "赤"])
	return PackedStringArray()


## コードでセリフを使っている所（ID → [{path, line, code}]）。root の下の .gd を読む。
## "c1.move.1" のようにそのまま書いた ID のほか、"select.players.%d" のような組み立てと、コースの text_id("clear.1") も拾う。
func build_usage_index(root := SCRIPTS_ROOT) -> Dictionary:
	var index := {}
	var files := PackedStringArray()
	_collect_scripts(root, files)
	for path in files:
		if path == texts_path:
			continue
		var source := FileAccess.get_file_as_string(path)
		if source.is_empty():
			continue
		var hits: Array = []
		for m in _literal_re.search_all(source):
			hits.append([m.get_start(), _ids_for_literal(m.get_string(1))])
		for m in _text_id_re.search_all(source):
			hits.append([m.get_start(), _ids_for_suffix(m.get_string(1))])
		if hits.is_empty():
			continue
		hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var lines := source.split("\n")
		var line := 0
		var offset := 0
		for hit: Array in hits:
			if hit[1].is_empty():
				continue
			line += source.count("\n", offset, hit[0]) if hit[0] > offset else 0
			offset = hit[0]
			for id: String in hit[1]:
				var list: Array = index.get_or_add(id, [])
				if not list.is_empty() and list[-1].path == path and list[-1].line == line + 1:
					continue
				list.append({"path": path, "line": line + 1, "code": lines[line].strip_edges()})
	return index


func _ids_for_literal(literal: String) -> Array[String]:
	var ids: Array[String] = []
	if _by_id.has(literal):
		ids.append(literal)
	elif literal.contains("%d") or literal.contains("%s"):
		var pattern := "^" + _regex_escape(literal).replace("%d", "\\d+").replace("%s", ".+") + "$"
		var re := RegEx.create_from_string(pattern)
		for entry in entries:
			if re.search(entry.id) != null:
				ids.append(entry.id)
	return ids


func _ids_for_suffix(suffix: String) -> Array[String]:
	var ids: Array[String] = []
	for entry in entries:
		var id: String = entry.id
		if course_of(id) > 0 and id.substr(id.find(".") + 1) == suffix:
			ids.append(id)
	return ids


static func _regex_escape(text: String) -> String:
	var out := ""
	for c in text:
		out += "\\" + c if ".^$*+?()[]{}|\\".contains(c) else c
	return out


static func _collect_scripts(dir: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_collect_scripts(dir.path_join(sub), out)


static func _write(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


func _new_store() -> RefCounted:
	var store: RefCounted = (get_script() as GDScript).new()
	store.texts_path = texts_path
	store.doc_path = doc_path
	return store

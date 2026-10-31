extends SceneTree

## セリフの下パネル（addons/practice_text_editor）の読み書きを確かめる。
## 本物の practice_texts.gd を読めること、直さない行が1文字も変わらないこと、書き戻した中身がスクリプトとして読めること、
## 台本の表の行の差し替え、ほかで直された ID を書かないこと、文字の決まりの注意、コードでの使用箇所。
## 保存は user://test_practice_text_store/ の写しに書く（本物のファイルには触れない）。
## godot --headless --path . --script res://tests/practice_text_store_unit.gd

const Store := preload("res://addons/practice_text_editor/practice_text_store.gd")
const TMP := "user://test_practice_text_store"

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	var source := FileAccess.get_file_as_string(Store.TEXTS_PATH)
	var store := Store.new()
	check(store.load_file().is_empty(), "loads practice_texts.gd")
	check(store.entries.size() == PracticeTexts.TEXTS.size(), "every text: %d / %d" % [store.entries.size(), PracticeTexts.TEXTS.size()])
	for entry in store.entries:
		check(PracticeTexts.TEXTS.get(entry.id) == entry.text, "same text as the game: " + entry.id)
	check(store.find("c1.welcome.1").where == "ハテナ", "where comes from the comment")
	check(Store.section_label(store.sections[0]) == "① 基本操作", "course section label: " + Store.section_label(store.sections[0]))
	check(Store.section_label(store.sections[-1]) == "画面の文字", "screen section label: " + Store.section_label(store.sections[-1]))
	check(store.build_source({}) == source, "no change keeps the file byte for byte")

	# 直した行だけが変わり、改行コードもそのまま。引用符・\・| も書き戻せる。
	var tricky := "テスト\"引用\"と\\n|縦棒"
	var edited := store.build_source({"c1.welcome.1": tricky})
	var before := source.split("\n")
	var after := edited.split("\n")
	check(before.size() == after.size(), "same line count")
	var diff := 0
	for i in before.size():
		if before[i] != after[i]:
			diff += 1
			check(after[i].ends_with("\r") == before[i].ends_with("\r"), "keeps the line ending")
			check(after[i].contains("# ハテナ"), "keeps the comment")
	check(diff == 1, "only one line changes: %d" % diff)
	var reread := Store.new()
	check(reread.parse(edited).is_empty() and reread.find("c1.welcome.1").text == tricky, "reads back the tricky text")
	var compiled := GDScript.new()
	compiled.source_code = edited.replace("class_name PracticeTexts", "")
	check(compiled.reload() == OK, "edited file compiles")
	check(compiled.get_script_constant_map().get("TEXTS", {}).get("c1.welcome.1") == tricky, "compiled TEXTS has the new text")
	for text: String in ["a\\nb", "\"", "\\", "改\n行", "タブ\tあり"]:
		check(Store.unescape(Store.escape(text)) == text, "escape round trip: " + text.c_escape())

	_check_save(source)
	_check_doc_rows()
	_check_notes()
	_check_usage(store)
	print("PRACTICE_TEXT_STORE_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _check_save(source: String) -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var texts_path := TMP.path_join("practice_texts.gd")
	var doc1 := TMP.path_join("course1_script.md")
	_write(texts_path, source)
	_write(doc1, FileAccess.get_file_as_string(Store.DOC_PATH % 1))
	if FileAccess.file_exists(TMP.path_join("course2_script.md")):
		DirAccess.remove_absolute(TMP.path_join("course2_script.md"))
	var store := Store.new()
	store.texts_path = texts_path
	store.doc_path = TMP.path_join("course%d_script.md")
	store.load_file()
	var changes := {"c1.welcome.1": "ようこそ|テスト", "select.title": "練習", "c2.jump.1": "跳ぼう", "c1.move.1": "ほか"}
	var originals := {}
	for id: String in changes:
		originals[id] = store.find(id).text
	originals["c1.move.1"] = "読み込んだ後にほかで直された"
	var result := store.save_changes(changes, originals)
	check(result.error.is_empty(), "save without error: " + str(result.error))
	check(result.conflicts == ["c1.move.1"], "changed elsewhere is not written: " + str(result.conflicts))
	check(result.saved.size() == 3, "saved three: " + str(result.saved))
	check(result.docs == [doc1], "writes course1 doc: " + str(result.docs))
	check(result.doc_missing == ["c2.jump.1"], "course2 doc is missing in the copy: " + str(result.doc_missing))
	var saved := Store.new()
	saved.texts_path = texts_path
	saved.load_file()
	check(saved.find("c1.welcome.1").text == "ようこそ|テスト", "saved course text")
	check(saved.find("select.title").text == "練習", "saved screen text")
	check(saved.find("c1.move.1").text == PracticeTexts.TEXTS["c1.move.1"], "conflict left as it was")
	check(FileAccess.get_file_as_string(doc1).contains("| c1.welcome.1 | ハテナ | ようこそ\\|テスト |"), "doc row updated and | escaped")


func _check_doc_rows() -> void:
	var doc := "| ID | 出る所 | 文字 |\r\n|---|---|---|\r\n| c1.a | ハテナ | 古い |\r\n| c1.b | 看板 | そのまま |\r\n"
	var replaced := Store.replace_doc_rows(doc, {"c1.a": "新しい", "c1.zz": "ない"})
	check(replaced.text == doc.replace("| c1.a | ハテナ | 古い |", "| c1.a | ハテナ | 新しい |"), "doc row replaced in place with CRLF")
	check(replaced.updated == ["c1.a"], "reports updated rows only")
	check(Store.course_of("c3.push.1") == 3 and Store.course_of("menu.button") == 0, "course number from id")


func _check_notes() -> void:
	check(Store.check("あ".repeat(18), "ハテナ", "x").is_empty(), "18 letters fit the bubble")
	check(Store.check("あ".repeat(19), "ハテナ", "x").size() == 1, "19 letters are too long for the bubble")
	check(Store.check("青い色のドア／赤", "壁のドア", "青／赤").size() == 1, "door text over 5 letters")
	check(Store.check("あ".repeat(15), "壁（1-7 壁1）", "x").size() == 1, "wall line over 14 letters")
	check(Store.check("あ／い／う", "壁", "あ／い／う").size() == 1, "wall over 2 lines")
	check(Store.check("A", "看板", "A／B").size() == 1, "separator count changed")
	check(Store.check("約分", "コース選択", "約%d分").size() == 1, "%d removed")
	check(Store.check(" ", "ハテナ", "x").size() == 1, "empty text")
	check(Store.count_label("青／赤い") == "1・2", "count label per part")
	check(Store.door_colors(4) == PackedStringArray(["青", "緑", "オレンジ", "赤"]), "four door colors")


func _check_usage(store: RefCounted) -> void:
	var index: Dictionary = store.build_usage_index()
	check(_used_in(index, "c1.move.1", "res://scripts/practice/courses/course_1.gd"), "direct id in course_1.gd")
	check(_used_in(index, "c1.clear.1", "res://scripts/practice/practice_director.gd"), "text_id(\"clear.1\") in the director")
	check(_used_in(index, "select.players.2", "res://scripts/practice/ui/practice_course_select.gd"), "select.players.%d")
	check(_used_in(index, "c5.go.1", "res://scripts/practice/menu/practice_customize_guide.gd"), "course 5 lines in the customize guide")


func _used_in(index: Dictionary, id: String, path: String) -> bool:
	for use: Dictionary in index.get(id, []):
		if use.path == path and use.line > 0 and String(use.code).length() > 0:
			return true
	return false


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

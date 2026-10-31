@tool
extends VBoxContainer

## 下パネル「セリフ」：チュートリアルのセリフ（scripts/practice/practice_texts.gd）を一覧で直す。
## 一覧の「セリフ」の列をダブルクリック（か Enter）するか、右の欄で直して「保存」。台本の表（docs/new_tutorial/courseN_script.md）も同じ ID の行が直る。
## 保存していない直しは、Ctrl+S やゲームの実行のときにも保存する（plugin.gd の _save_external_data）。
## 直したセリフは、ゲームを実行し直すと出る。

const Store := preload("res://addons/practice_text_editor/practice_text_store.gd")

const COL_ID := 0
const COL_WHERE := 1
const COL_TEXT := 2
const COL_COUNT := 3
const CHANGED_BG := Color(1.0, 0.78, 0.2, 0.16)
const WARN_COLOR := Color(1.0, 0.55, 0.3)
const OK_COLOR := Color(0.45, 0.85, 0.5)
const RULES := "決まり（台本 1.1）：吹き出しは18文字まで／壁の問題文は2行・1行14文字まで／ドアは5文字まで。" \
		+ "「／」は区切り（壁と看板は2行、ボタンとカウントダウンは並び、ドアは番号の順）。" \
		+ "ドアの文字の順を入れ替えると正解のドアも変わるので、答えの位置は「使っている所」のコードで確かめる。"

var _store := Store.new()
## 直したけれどまだ保存していない文字（ID → 文字）。
var _edits := {}
## コードでセリフを使っている所（ID → [{path, line, code}]）。最初に要るときに作る。
var _usage := {}
var _usage_ready := false
var _loaded_time := 0
var _selected_id := ""

var _section_filter: OptionButton
var _search: LineEdit
var _only_changed: CheckBox
var _only_warn: CheckBox
var _message: Label
var _status: Label
var _revert_button: Button
var _save_button: Button
var _tree: Tree
var _detail_id: Label
var _detail_where: Label
var _editor: LineEdit
var _parts: Label
var _warns: Label
var _original: Label
var _revert_one: Button
var _usages: ItemList
var _confirm: ConfirmationDialog
var _confirm_action := Callable()


func _ready() -> void:
	size_flags_vertical = SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 240) * _scale()
	_build_ui()
	_reload()


func _enter_tree() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if not fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.disconnect(_on_filesystem_changed)


func has_edits() -> bool:
	return not _edits.is_empty()


## 保存していない直しを書く（「保存」と、plugin.gd の _save_external_data から）。
func save() -> void:
	if _edits.is_empty():
		return
	var originals := {}
	for id: String in _edits:
		originals[id] = _store.find(id).get("text", "")
	var result := _store.save_changes(_edits, originals)
	if not result.error.is_empty() and result.saved.is_empty():
		_say("保存できなかった：" + result.error, true)
		return
	for id: String in result.saved:
		_edits.erase(id)
	_refresh_editor_copy()
	_reload(true)
	var lines := PackedStringArray()
	lines.append("%d 件を保存した（台本の表 %d つ）。ゲームを実行し直すと出る" % [result.saved.size(), result.docs.size()])
	if not result.conflicts.is_empty():
		lines.append("ほかで直されていたので保存しなかった：%s（読み直した文字を見て、もう一度保存）" % ", ".join(result.conflicts))
	if not result.doc_missing.is_empty():
		lines.append("台本の表に行がなかった：" + ", ".join(result.doc_missing))
	if not result.error.is_empty():
		lines.append(result.error)
	_say("　".join(lines), not result.conflicts.is_empty() or not result.error.is_empty())


func _build_ui() -> void:
	# 狭いエディタでもはみ出さないように、上の列は折り返す。
	var bar := HFlowContainer.new()
	add_child(bar)
	_section_filter = OptionButton.new()
	_section_filter.tooltip_text = "コースで絞る"
	_section_filter.item_selected.connect(_on_filter_changed)
	bar.add_child(_section_filter)
	_search = LineEdit.new()
	_search.placeholder_text = "ID・セリフ・出る所で探す"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.x = 180 * _scale()
	_search.text_changed.connect(_on_filter_changed)
	bar.add_child(_search)
	_only_changed = _add_check(bar, "直したものだけ")
	_only_warn = _add_check(bar, "注意があるものだけ")
	_message = Label.new()
	_message.size_flags_horizontal = SIZE_EXPAND_FILL
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.mouse_filter = MOUSE_FILTER_PASS
	bar.add_child(_message)
	_status = Label.new()
	bar.add_child(_status)
	_add_button(bar, "読み直す", "practice_texts.gd を読み直す（保存していない直しは消える）", _on_reload_pressed)
	_revert_button = _add_button(bar, "直しを全部取り消す", "保存していない直しを全部元に戻す", _on_revert_all_pressed)
	_save_button = _add_button(bar, "保存", "practice_texts.gd と台本の表（courseN_script.md）に書く", save)

	var split := HSplitContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(split)

	_tree = Tree.new()
	_tree.columns = 4
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.size_flags_stretch_ratio = 1.8
	var titles := ["ID", "出る所", "セリフ（ダブルクリックか Enter で直す）", "文字数"]
	var widths := [150, 96, 0, 60]
	for col in _tree.columns:
		_tree.set_column_title(col, titles[col])
		_tree.set_column_title_alignment(col, HORIZONTAL_ALIGNMENT_LEFT)
		_tree.set_column_expand(col, col == COL_TEXT)
		if widths[col] > 0:
			_tree.set_column_custom_minimum_width(col, int(widths[col] * _scale()))
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_activated)
	_tree.item_edited.connect(_on_item_edited)
	split.add_child(_tree)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = SIZE_EXPAND_FILL
	side.custom_minimum_size.x = 240 * _scale()
	split.add_child(side)
	var head := HBoxContainer.new()
	side.add_child(head)
	_detail_id = Label.new()
	head.add_child(_detail_id)
	_detail_where = Label.new()
	_detail_where.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail_where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_where.modulate = Color(1, 1, 1, 0.65)
	head.add_child(_detail_where)
	_editor = LineEdit.new()
	_editor.placeholder_text = "セリフ"
	_editor.add_theme_font_size_override("font_size", int(18 * _scale()))
	_editor.text_changed.connect(_on_editor_changed)
	side.add_child(_editor)
	_parts = _add_wrapped_label(side)
	_warns = _add_wrapped_label(side)
	_warns.add_theme_color_override("font_color", WARN_COLOR)
	var original_row := HBoxContainer.new()
	side.add_child(original_row)
	_original = Label.new()
	_original.size_flags_horizontal = SIZE_EXPAND_FILL
	_original.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_original.modulate = Color(1, 1, 1, 0.65)
	original_row.add_child(_original)
	_revert_one = _add_button(original_row, "この行を戻す", "このセリフを保存してある文字に戻す", _on_revert_one_pressed)
	var usage_title := Label.new()
	usage_title.text = "使っている所（ダブルクリックでスクリプトを開く）"
	side.add_child(usage_title)
	_usages = ItemList.new()
	_usages.size_flags_vertical = SIZE_EXPAND_FILL
	_usages.custom_minimum_size.y = 60 * _scale()
	_usages.item_activated.connect(_on_usage_activated)
	side.add_child(_usages)
	var rules := _add_wrapped_label(side)
	rules.text = RULES
	rules.modulate = Color(1, 1, 1, 0.55)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "セリフ"
	_confirm.ok_button_text = "はい"
	_confirm.cancel_button_text = "やめる"
	_confirm.confirmed.connect(_on_confirmed)
	add_child(_confirm)


## ファイルから読み直す。keep_edits なら保存していない直しは残す（元と同じになったものは消す）。
func _reload(keep_edits := false) -> void:
	var err := _store.load_file()
	_usage_ready = false
	_usage.clear()
	if not keep_edits:
		_edits.clear()
	for id: String in _edits.keys():
		var entry := _store.find(id)
		if entry.is_empty() or entry.text == _edits[id]:
			_edits.erase(id)
	_loaded_time = FileAccess.get_modified_time(_store.texts_path)
	_rebuild_section_filter()
	_refresh_tree()
	_show_detail()
	if not err.is_empty():
		_say(err, true)


func _rebuild_section_filter() -> void:
	var keep := _section_filter.get_item_text(_section_filter.selected) if _section_filter.selected >= 0 else ""
	_section_filter.clear()
	_section_filter.add_item("すべて", 0)
	for i in _store.sections.size():
		_section_filter.add_item(Store.section_label(_store.sections[i]), i + 1)
		_section_filter.set_item_tooltip(i + 1, _store.sections[i])
	var index := 0
	for i in _section_filter.item_count:
		if _section_filter.get_item_text(i) == keep:
			index = i
	_section_filter.select(index)


func _refresh_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var section := _section_filter.get_selected_id() - 1
	var query := _search.text.strip_edges().to_lower()
	var parents := {}
	var keep: TreeItem = null
	for entry in _store.entries:
		if section >= 0 and entry.section != section:
			continue
		if _only_changed.button_pressed and not _edits.has(entry.id):
			continue
		if _only_warn.button_pressed and _notes_of(entry).is_empty():
			continue
		if not query.is_empty() and not _matches(entry, query):
			continue
		if not parents.has(entry.section):
			parents[entry.section] = _add_section_item(root, entry.section)
		var item := _tree.create_item(parents[entry.section])
		item.set_metadata(COL_ID, entry.id)
		item.set_editable(COL_TEXT, true)
		_fill_item(item, entry)
		if entry.id == _selected_id:
			keep = item
	if keep != null:
		_tree.set_selected(keep, COL_TEXT)
		_tree.scroll_to_item(keep)
	_update_status()


func _add_section_item(root: TreeItem, section: int) -> TreeItem:
	var item := _tree.create_item(root)
	item.set_text(COL_ID, Store.section_label(_store.sections[section]))
	item.set_custom_color(COL_ID, get_theme_color("accent_color", "Editor"))
	item.set_text(COL_TEXT, _store.sections[section])
	item.set_custom_color(COL_TEXT, Color(1, 1, 1, 0.45))
	for col in _tree.columns:
		item.set_selectable(col, false)
	return item


func _fill_item(item: TreeItem, entry: Dictionary) -> void:
	var text := _text_of(entry)
	var notes := Store.check(text, entry.where, entry.text, entry.id)
	var changed := _edits.has(entry.id)
	item.set_text(COL_ID, entry.id)
	item.set_text(COL_WHERE, entry.where)
	item.set_text(COL_TEXT, text)
	item.set_tooltip_text(COL_TEXT, "元：" + entry.text if changed else text)
	item.set_text(COL_COUNT, ("" if notes.is_empty() else "⚠ ") + Store.count_label(text))
	item.set_tooltip_text(COL_COUNT, "\n".join(notes))
	if notes.is_empty():
		item.clear_custom_color(COL_COUNT)
	else:
		item.set_custom_color(COL_COUNT, WARN_COLOR)
	for col in _tree.columns:
		if changed:
			item.set_custom_bg_color(col, CHANGED_BG)
		else:
			item.clear_custom_bg_color(col)


## 詳しい欄（右側）。refresh_editor が false なら、入力欄の文字はそのまま（入力欄で打っている最中）。
func _show_detail(refresh_editor := true) -> void:
	var entry := _store.find(_selected_id)
	_editor.editable = not entry.is_empty()
	if entry.is_empty():
		_detail_id.text = "左の一覧からセリフを選ぶ"
		_detail_where.text = ""
		_editor.text = ""
		_parts.hide()
		_warns.hide()
		_original.text = ""
		_revert_one.hide()
		_usages.clear()
		return
	var text := _text_of(entry)
	var changed := _edits.has(entry.id)
	_detail_id.text = entry.id
	_detail_where.text = "　%s ・ %s" % [entry.where, Store.section_label(_store.sections[entry.section])]
	if refresh_editor:
		_editor.text = text
		_fill_usages(entry.id)
	var parts := text.split("／")
	_parts.visible = parts.size() > 1
	if _parts.visible:
		var colors := Store.door_colors(parts.size()) if entry.where.begins_with("壁のドア") else PackedStringArray()
		var shown := PackedStringArray()
		for i in parts.size():
			shown.append("%s：%s" % [colors[i] if i < colors.size() else str(i + 1), parts[i]])
		_parts.text = "区切ると　" + "　｜　".join(shown)
	var notes := Store.check(text, entry.where, entry.text, entry.id)
	_warns.visible = not notes.is_empty()
	_warns.text = "⚠ " + "\n⚠ ".join(notes)
	_original.text = "元の文字：" + entry.text if changed else "保存してある文字のまま"
	_revert_one.visible = changed


func _fill_usages(id: String) -> void:
	_usages.clear()
	if not _usage_ready:
		_usage = _store.build_usage_index()
		_usage_ready = true
	var list: Array = _usage.get(id, [])
	if list.is_empty():
		_usages.add_item("見つからない（まだ使っていないか、ID を組み立てて使っている）", null, false)
		return
	for use: Dictionary in list:
		var label := "%s:%d　%s" % [String(use.path).trim_prefix("res://"), use.line, use.code]
		var index := _usages.add_item(label)
		_usages.set_item_metadata(index, use)
		_usages.set_item_tooltip(index, label)


func _set_text(id: String, text: String, from_editor := false) -> void:
	var entry := _store.find(id)
	if entry.is_empty():
		return
	text = text.replace("\r", "").replace("\n", "")
	if text == entry.text:
		_edits.erase(id)
	else:
		_edits[id] = text
	var item := _find_item(id)
	if item != null:
		_fill_item(item, entry)
	if id == _selected_id:
		_show_detail(not from_editor)
	_update_status()


func _update_status() -> void:
	var warn_count := 0
	for id: String in _edits:
		if not _notes_of(_store.find(id)).is_empty():
			warn_count += 1
	_status.text = "直した %d / %d 件%s" % [_edits.size(), _store.entries.size(), "（注意 %d）" % warn_count if warn_count > 0 else ""]
	_save_button.disabled = _edits.is_empty()
	_revert_button.disabled = _edits.is_empty()
	_save_button.text = "保存（%d）" % _edits.size() if not _edits.is_empty() else "保存"


## 保存したファイルを、エディタが持っている写しにも入れる（スクリプトエディタで古い中身が出ないように）。
func _refresh_editor_copy() -> void:
	EditorInterface.get_resource_filesystem().update_file(Store.TEXTS_PATH)
	if ResourceLoader.has_cached(Store.TEXTS_PATH):
		var script := load(Store.TEXTS_PATH) as GDScript
		if script != null:
			script.source_code = FileAccess.get_file_as_string(Store.TEXTS_PATH)
			script.reload(true)


func _text_of(entry: Dictionary) -> String:
	return _edits.get(entry.id, entry.text)


func _notes_of(entry: Dictionary) -> PackedStringArray:
	return Store.check(_text_of(entry), entry.where, entry.text, entry.id)


func _matches(entry: Dictionary, query: String) -> bool:
	for value: String in [entry.id, entry.where, entry.text, _text_of(entry)]:
		if value.to_lower().contains(query):
			return true
	return false


func _find_item(id: String) -> TreeItem:
	var root := _tree.get_root()
	if root == null:
		return null
	for section_item in root.get_children():
		for item in section_item.get_children():
			if item.get_metadata(COL_ID) == id:
				return item
	return null


func _say(text: String, is_error := false) -> void:
	_message.text = text
	_message.tooltip_text = text
	_message.add_theme_color_override("font_color", WARN_COLOR if is_error else OK_COLOR)


## 保存していない直しがあれば、消してよいか聞いてから action を呼ぶ。
func _ask(question: String, action: Callable) -> void:
	if _edits.is_empty():
		action.call()
		return
	_confirm.dialog_text = question % _edits.size()
	_confirm_action = action
	_confirm.popup_centered()


func _on_confirmed() -> void:
	if _confirm_action.is_valid():
		_confirm_action.call()


func _on_filter_changed(_value: Variant = null) -> void:
	_refresh_tree()


func _on_filesystem_changed() -> void:
	if _edits.is_empty() and FileAccess.get_modified_time(_store.texts_path) != _loaded_time:
		_reload()


func _on_reload_pressed() -> void:
	_ask("保存していない直しが %d 件あります。消して読み直しますか？", _reload)


func _on_revert_all_pressed() -> void:
	_ask("保存していない直し %d 件を、全部元に戻しますか？", _revert_all)


func _revert_all() -> void:
	_edits.clear()
	_refresh_tree()
	_show_detail()


func _on_revert_one_pressed() -> void:
	var entry := _store.find(_selected_id)
	if not entry.is_empty():
		_set_text(_selected_id, entry.text)


func _on_item_selected() -> void:
	var item := _tree.get_selected()
	if item == null or item.get_metadata(COL_ID) == null:
		return
	_selected_id = item.get_metadata(COL_ID)
	_show_detail()


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null or item.get_metadata(COL_ID) == null:
		return
	_tree.set_selected(item, COL_TEXT)
	_tree.edit_selected(true)


func _on_item_edited() -> void:
	var item := _tree.get_edited()
	if item == null or _tree.get_edited_column() != COL_TEXT:
		return
	_set_text(String(item.get_metadata(COL_ID)), item.get_text(COL_TEXT))


func _on_editor_changed(text: String) -> void:
	if not _selected_id.is_empty():
		_set_text(_selected_id, text, true)


func _on_usage_activated(index: int) -> void:
	var use: Variant = _usages.get_item_metadata(index)
	if not use is Dictionary:
		return
	var script := load(use.path) as Script
	if script == null:
		return
	EditorInterface.edit_script(script, use.line)
	EditorInterface.set_main_screen_editor("Script")


func _add_check(parent: Control, text: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.toggled.connect(_on_filter_changed)
	parent.add_child(box)
	return box


func _add_button(parent: Control, text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _add_wrapped_label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 1
	parent.add_child(label)
	return label


func _scale() -> float:
	return EditorInterface.get_editor_scale()

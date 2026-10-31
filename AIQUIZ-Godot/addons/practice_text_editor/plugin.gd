@tool
extends EditorPlugin

## 下パネルに「セリフ」を足す（チュートリアルのセリフを一覧で直す。practice_text_dock.gd）。

const DockContent := preload("res://addons/practice_text_editor/practice_text_dock.gd")

var _dock: EditorDock
var _content: Control


func _enter_tree() -> void:
	_content = DockContent.new()
	_dock = EditorDock.new()
	_dock.title = "セリフ"
	_dock.layout_key = "PracticeTextEditor"
	_dock.icon_name = &"Translation"
	_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	_dock.add_child(_content)
	add_dock(_dock)


func _exit_tree() -> void:
	if _dock == null:
		return
	remove_dock(_dock)
	_dock.queue_free()
	_dock = null
	_content = null


## エディタを閉じるときに、保存していない直しを知らせる。
func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and _content != null and _content.has_edits():
		return "チュートリアルのセリフに、保存していない直しがあります。保存しますか？"
	return ""


## Ctrl+S やゲームの実行の前にも、直しを保存する。
func _save_external_data() -> void:
	if _content != null and _content.has_edits():
		_content.save()

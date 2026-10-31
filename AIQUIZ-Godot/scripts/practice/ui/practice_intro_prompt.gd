class_name PracticeIntroPrompt
extends Control

## 初回の案内（docs/new_tutorial/foundation_design.md 9章、plan.md 4章）。メインメニューの上に重ねる。
## 「はじめまして！ ハテナと れんしゅう する？」［する］［あとで］。［する］で accepted（メニューが①を始める）、
## ［あとで］と Esc で declined。どちらでも GameManager.mark_practice_intro_seen() を呼び、次からは出さない。

signal accepted
signal declined

const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const TEXT := Color(0.95, 0.97, 1.0)
const ACCENT := Color("#ffd94a")
const PANEL_FACE := Color(0.05, 0.09, 0.16, 0.96)
const FADE_SECONDS := 0.2
## パネルの上のハテナ（HatenaPortrait.show_inline）の大きさ
const HATENA_SIZE := Vector2(168, 150)

var _sheet: PanelContainer = null
var _yes: Button = null
var _later: Button = null
var _tween: Tween = null
var _open := false
var _hatena_holder: CenterContainer = null
## 開いている間だけ入れる 3D のハテナ（雲に乗って手をふる）
var _hatena: HatenaPortrait = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func is_open() -> bool:
	return _open


## ボタン（テスト用）：0 = する、1 = あとで
func button(index: int) -> Button:
	return _yes if index == 0 else _later


func open() -> void:
	_open = true
	visible = true
	_yes.disabled = false
	_later.disabled = false
	if _hatena == null:
		_hatena = HatenaPortrait.new()
		_hatena.name = "IntroHatena"
		_hatena_holder.add_child(_hatena)
		_hatena.show_inline(HATENA_SIZE)
		_hatena.play(&"wave")
	if _tween != null:
		_tween.kill()
	modulate.a = 0.0
	_sheet.pivot_offset = _sheet.size * 0.5
	_sheet.scale = Vector2(0.9, 0.9)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	_tween.tween_property(_sheet, "scale", Vector2.ONE, FADE_SECONDS * 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_yes.grab_focus.call_deferred()


func _close() -> void:
	_open = false
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(func() -> void:
		if not _open:
			visible = false
			if _hatena != null:
				_hatena.queue_free()
				_hatena = null)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_later()


func _on_yes() -> void:
	if not _open:
		return
	GameManager.mark_practice_intro_seen()
	_close()
	accepted.emit()


func _on_later() -> void:
	if not _open:
		return
	GameManager.mark_practice_intro_seen()
	_close()
	declined.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.06, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_sheet = PanelContainer.new()
	_sheet.name = "Sheet"
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_FACE
	style.border_color = Color(ACCENT, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(30)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.shadow_color = Color(0.0, 0.02, 0.06, 0.45)
	style.shadow_size = 14
	_sheet.add_theme_stylebox_override("panel", style)
	center.add_child(_sheet)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	_sheet.add_child(column)
	# ハテナの置き場（開くときに、ハテナの小窓と同じ 3D の絵を入れる。メニューを開くたびに読み込まないように）
	_hatena_holder = CenterContainer.new()
	_hatena_holder.name = "HatenaHolder"
	_hatena_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hatena_holder.custom_minimum_size = HATENA_SIZE
	column.add_child(_hatena_holder)
	var question := Label.new()
	question.text = PracticeTexts.get_text("menu.intro")
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.add_theme_font_override("font", FONT)
	question.add_theme_font_size_override("font_size", 30)
	question.add_theme_color_override("font_color", TEXT)
	column.add_child(question)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	var labels := PracticeTexts.get_parts("menu.intro.buttons")
	_yes = _button(labels[0], true)
	_yes.name = "YesBtn"
	_yes.pressed.connect(_on_yes)
	row.add_child(_yes)
	_later = _button(labels[1] if labels.size() > 1 else "", false)
	_later.name = "LaterBtn"
	_later.pressed.connect(_on_later)
	row.add_child(_later)
	_yes.focus_neighbor_left = _yes.get_path_to(_later)
	_yes.focus_neighbor_right = _yes.get_path_to(_later)
	_later.focus_neighbor_left = _later.get_path_to(_yes)
	_later.focus_neighbor_right = _later.get_path_to(_yes)


func _button(text: String, featured: bool) -> Button:
	var node := MenuMetalButton.new()
	node.text = text
	node.compact = not MobileUi.is_touch_ui()
	node.featured = featured
	node.custom_minimum_size = Vector2(200, MobileUi.touch(56))
	node.add_theme_font_size_override("font_size", MobileUi.font(22))
	return node


class_name PracticeCourseSelect
extends Control

## コース選択（docs/new_tutorial/foundation_design.md 9章）。メインメニューの上に重ねるパネル。
## 5枚のカード（番号・名前・人数・目安時間・スタンプ）。スタンプのない最初のコースに「次はこれ」。
## 遊べないコース（PracticeCatalog の available = false）は「準備中」で押せない。
## 「← もどる」と Esc で閉じる。矢印キーと Enter でも選べる。選ぶと course_chosen（ゲームへ移るのはメニュー）。

signal course_chosen(course_id: String)
signal closed

const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const CARD_SIZE := Vector2(216, 300)
const TEXT := Color(0.95, 0.97, 1.0)
const MUTED := Color(0.64, 0.70, 0.80)
const ACCENT := Color("#ffd94a")
const CARD_FACE := Color(0.10, 0.17, 0.27, 0.98)
const CARD_HOVER := Color(0.14, 0.23, 0.36, 0.98)
const PANEL_FACE := Color(0.05, 0.09, 0.16, 0.96)
const FADE_SECONDS := 0.18

## id → カードのボタン
var _cards := {}
## id → 「次はこれ」の札
var _ribbons := {}
var _back: Button = null
var _row: HBoxContainer = null
var _sheet: PanelContainer = null
var _tween: Tween = null
var _ribbon_tween: Tween = null
var _open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func is_open() -> bool:
	return _open


## カードのボタン（テストと、メニューの確かめ用）。
func card(course_id: String) -> Button:
	return _cards.get(course_id) as Button


func open() -> void:
	_refresh()
	_open = true
	visible = true
	_fade(1.0)
	var focus := card(_recommended_available())
	if focus == null:
		focus = _first_available()
	focus.grab_focus.call_deferred()


func close() -> void:
	if not _open:
		return
	_open = false
	_fade(0.0)
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _fade(alpha: float) -> void:
	if _tween != null:
		_tween.kill()
	if alpha > 0.0:
		modulate.a = 0.0
		_sheet.scale = Vector2(0.96, 0.96)
	_sheet.pivot_offset = _sheet.size * 0.5
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", alpha, FADE_SECONDS)
	_tween.tween_property(_sheet, "scale", Vector2.ONE, FADE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if alpha <= 0.0:
		_tween.chain().tween_callback(func() -> void:
			if not _open:
				visible = false)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.06, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_sheet = PanelContainer.new()
	_sheet.name = "Sheet"
	_sheet.add_theme_stylebox_override("panel", _box(PANEL_FACE, Color(1, 1, 1, 0.12), 1, 18, 28))
	center.add_child(_sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	_sheet.add_child(column)
	var heading := _label(PracticeTexts.get_text("select.title"), 30, ACCENT)
	column.add_child(heading)
	_row = HBoxContainer.new()
	_row.name = "Cards"
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 16)
	column.add_child(_row)
	for course: Dictionary in PracticeCatalog.COURSES:
		_row.add_child(_build_card(course))
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_child(footer)
	_back = MenuMetalButton.new()
	_back.name = "BackBtn"
	_back.compact = not MobileUi.is_touch_ui()
	_back.text = PracticeTexts.get_text("select.back")
	_back.custom_minimum_size = Vector2(200, MobileUi.touch(50))
	_back.add_theme_font_size_override("font_size", MobileUi.font(18))
	_back.pressed.connect(close)
	footer.add_child(_back)


func _build_card(course: Dictionary) -> Button:
	var id := str(course.id)
	var button := Button.new()
	button.name = "Course_%s" % id
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _box(CARD_FACE, Color(1, 1, 1, 0.16), 2, 14, 0))
	button.add_theme_stylebox_override("hover", _box(CARD_HOVER, Color(1, 1, 1, 0.3), 2, 14, 0))
	button.add_theme_stylebox_override("pressed", _box(CARD_FACE.darkened(0.2), ACCENT, 3, 14, 0))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), ACCENT, 3, 14, 0))
	button.add_theme_stylebox_override("disabled", _box(Color(0.08, 0.11, 0.16, 0.9), Color(1, 1, 1, 0.08), 2, 14, 0))
	button.pressed.connect(_choose.bind(id))
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -12
	content.offset_top = 26
	content.offset_bottom = -12
	content.alignment = BoxContainer.ALIGNMENT_BEGIN
	content.add_theme_constant_override("separation", 4)
	button.add_child(content)
	# 名前は「① はじめの いっぽ」の丸数字と残り
	var parts := str(course.title).split(" ", false, 1)
	content.add_child(_label(parts[0], 44, ACCENT))
	var name_label := _label(parts[1] if parts.size() > 1 else "", 20, TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(CARD_SIZE.x - 24, 0)
	content.add_child(name_label)
	var players_key := "select.players.%d" % int(course.players)
	content.add_child(_label(PracticeTexts.get_text(players_key), 17, MUTED))
	content.add_child(_label(PracticeTexts.get_text("select.minutes") % int(course.minutes), 17, MUTED))
	var stamp_holder := CenterContainer.new()
	stamp_holder.name = "StampHolder"
	stamp_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(stamp_holder)
	# 遊べないコースは、スタンプの代わりに「準備中」
	var soon := _label(PracticeTexts.get_text("select.soon"), 18, MUTED)
	soon.name = "Soon"
	soon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	soon.visible = false
	content.add_child(soon)
	var ribbon := PanelContainer.new()
	ribbon.name = "NextRibbon"
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.add_theme_stylebox_override("panel", _box(ACCENT, Color(1, 1, 1, 0.0), 0, 10, 0, Vector4(12, 2, 12, 3)))
	ribbon.add_child(_label(PracticeTexts.get_text("select.next"), 15, Color(0.12, 0.10, 0.02)))
	ribbon.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ribbon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ribbon.offset_top = -12
	ribbon.visible = false
	button.add_child(ribbon)
	_cards[id] = button
	_ribbons[id] = ribbon
	return button


## スタンプ・おすすめ・遊べるかを今の保存から出し直す（開くたびに呼ぶ）。
func _refresh() -> void:
	var recommended := _recommended_available()
	var enabled: Array[Button] = []
	for course: Dictionary in PracticeCatalog.COURSES:
		var id := str(course.id)
		var button := card(id)
		var available := bool(course.available)
		button.disabled = not available
		button.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if available else Control.CURSOR_ARROW
		button.modulate = Color(1, 1, 1, 1.0 if available else 0.62)
		(button.find_child("Soon", true, false) as CanvasItem).visible = not available
		var holder := button.find_child("StampHolder", true, false) as Container
		holder.visible = available
		for child: Node in holder.get_children():
			child.queue_free()
		var stamped := GameManager.has_practice_stamp(id)
		var star := stamped and GameManager.practice_stamp_star(id)
		holder.add_child(PracticeOverlay.make_stamp(str(course.number), star, 66.0, stamped))
		(_ribbons[id] as CanvasItem).visible = id == recommended
		if available:
			enabled.append(button)
	_link_focus(enabled, card(recommended))
	_pulse_ribbon(_ribbons.get(recommended) as Control)


## 最初の遊べるカード（なければ「← もどる」）。おすすめが遊べないときに選んでおく。
func _first_available() -> Button:
	for course: Dictionary in PracticeCatalog.COURSES:
		if bool(course.available):
			return card(course.id)
	return _back


## おすすめ（スタンプのない最初のコース）が遊べるならその id、遊べなければ ""。
func _recommended_available() -> String:
	var id := PracticeCatalog.next_recommended()
	return id if PracticeCatalog.is_available(id) else ""


## 矢印キーで動く先：カードの左右は遊べるカードの中で回す。下は「← もどる」、もどるの上はおすすめのカード。
func _link_focus(enabled: Array[Button], recommended: Button) -> void:
	for i in range(enabled.size()):
		var button := enabled[i]
		button.focus_neighbor_left = button.get_path_to(enabled[wrapi(i - 1, 0, enabled.size())])
		button.focus_neighbor_right = button.get_path_to(enabled[wrapi(i + 1, 0, enabled.size())])
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(_back)
	var up: Button = recommended if recommended != null else _first_available()
	_back.focus_neighbor_top = _back.get_path_to(up)
	_back.focus_neighbor_left = _back.get_path_to(_back)
	_back.focus_neighbor_right = _back.get_path_to(_back)
	_back.focus_neighbor_bottom = _back.get_path_to(_back)


func _pulse_ribbon(ribbon: Control) -> void:
	if _ribbon_tween != null:
		_ribbon_tween.kill()
		_ribbon_tween = null
	if ribbon == null:
		return
	_ribbon_tween = create_tween().set_loops()
	_ribbon_tween.tween_property(ribbon, "modulate", Color(1.25, 1.25, 1.25, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	_ribbon_tween.tween_property(ribbon, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)


func _choose(course_id: String) -> void:
	if not _open or not PracticeCatalog.is_available(course_id):
		return
	_open = false
	_fade(0.0)
	course_chosen.emit(course_id)


static func _box(face: Color, edge: Color, border: int, radius: int, margin: int, margins := Vector4(-1, -1, -1, -1)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = face
	style.border_color = edge
	style.set_border_width_all(border)
	style.set_corner_radius_all(radius)
	if margins.x >= 0.0:
		style.content_margin_left = margins.x
		style.content_margin_top = margins.y
		style.content_margin_right = margins.z
		style.content_margin_bottom = margins.w
	else:
		style.set_content_margin_all(margin)
	return style


static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

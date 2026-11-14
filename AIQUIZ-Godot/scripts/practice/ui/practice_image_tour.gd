class_name PracticeImageTour
extends CanvasLayer

## 画像カードの紹介（コース⑤「カスタマイズ」。以前のチュートリアルのカスタマイズ紹介と同じ形）。
## 大きな画像の該当箇所を枠で囲み、右に見出し・説明・補足を置く。← → か［← 戻る］［次へ →］でページをめくり、
## 最後のページの［紹介を終える］で finished(true)。Esc でとばすと finished(false)。
## 画面いっぱいの幕で、下のメニューは押せない（キーも下へ流さない）。画像は tests/customize_tour_capture_bootstrap.gd で撮る。

## 紹介を終えた。completed は最後まで見たか（false は Esc でとばした）
signal finished(completed: bool)
## 見ているページが変わった（0 から）
signal page_changed(index: int)

const MobileUi = preload("res://scripts/core/mobile_ui.gd")
## PracticeOverlay（20）の下：クリアカードと吹き出しは、紹介より上に出る
const LAYER := 19
## 画像を出す枠の大きさ（16:9）と、右の文字の列の幅
const IMAGE_SIZE := Vector2(768.0, 432.0)
const GUIDE_WIDTH := 360.0
const SHADE := Color(0.02, 0.04, 0.08, 0.5)
const BADGE_INK := Color("2a1d00")

## ページ：{id: StringName, image: Texture2D, focus: Rect2（画像に対する割合。空なら枠なし）, title, body, note: String}
var pages: Array[Dictionary] = []
var header := ""
var index := 0

var _shield: ColorRect = null
var _image: TextureRect = null
var _focus: Control = null
var _progress: Label = null
var _title: Label = null
var _body: Label = null
var _note: Label = null
var _dots: HBoxContainer = null
var _hint: Label = null
var _back: Button = null
var _next: Button = null
var _button_texts := PackedStringArray()
var _done := false


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


## pages と、ページの上の見出し（「⑤ カスタマイズ」）を渡す。ツリーに入る前に呼ぶ。
func setup(tour_pages: Array[Dictionary], tour_header: String) -> void:
	pages = tour_pages
	header = tour_header


func _ready() -> void:
	_button_texts = PracticeTexts.get_parts("c5.tour.buttons")
	_build()
	show_page(0)


func _build() -> void:
	var root := Control.new()
	root.name = "ImageTourRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_shield = ColorRect.new()
	_shield.name = "InputShield"
	_shield.color = Color(0.02, 0.04, 0.09, 0.82)
	_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_shield)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var card := PracticeOverlay._panel(Color(0.07, 0.13, 0.22, 0.98), 22, Vector4(22, 22, 26, 22))
	card.name = "ImageTourCard"
	var card_style := card.get_theme_stylebox("panel") as StyleBoxFlat
	card_style.border_color = Color(PracticeOverlay.ACCENT, 0.8)
	card_style.set_border_width_all(2)
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	card_style.shadow_size = 16
	center.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var frame := PracticeOverlay._panel(Color(0.008, 0.018, 0.038, 1.0), 14, Vector4(3, 3, 3, 3))
	frame.name = "ImageFrame"
	(frame.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(0.17, 0.25, 0.4)
	(frame.get_theme_stylebox("panel") as StyleBoxFlat).set_border_width_all(2)
	frame.custom_minimum_size = IMAGE_SIZE
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.clip_contents = true
	row.add_child(frame)

	_image = TextureRect.new()
	_image.name = "PageImage"
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_image)

	# 画像の該当箇所を枠で囲み、枠の外を少し暗くする
	_focus = Control.new()
	_focus.name = "FocusRing"
	_focus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_focus.draw.connect(_draw_focus)
	_image.add_child(_focus)

	var guide := VBoxContainer.new()
	guide.name = "Guide"
	guide.custom_minimum_size = Vector2(GUIDE_WIDTH, 0.0)
	guide.add_theme_constant_override("separation", 12)
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(guide)

	_progress = _text(15, PracticeOverlay.MUTED)
	guide.add_child(_progress)
	_title = _text(38, PracticeOverlay.ACCENT)
	guide.add_child(_title)
	_body = _text(21, PracticeOverlay.TEXT, true)
	_body.add_theme_constant_override("line_spacing", 6)
	guide.add_child(_body)
	_note = _text(16, PracticeOverlay.MUTED, true)
	_note.add_theme_constant_override("line_spacing", 4)
	guide.add_child(_note)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	guide.add_child(spacer)

	_dots = HBoxContainer.new()
	_dots.name = "PageDots"
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.add_theme_constant_override("separation", 8)
	guide.add_child(_dots)
	for i in range(pages.size()):
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.custom_minimum_size = Vector2(28.0, 6.0)
		_dots.add_child(dot)

	_hint = _text(14, PracticeOverlay.MUTED)
	_hint.text = PracticeTexts.get_text("c5.tour.hint")
	_hint.visible = not _hint.text.is_empty()
	guide.add_child(_hint)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	guide.add_child(buttons)
	_back = _button(_button_texts[0] if _button_texts.size() > 0 else "←")
	_back.name = "PreviousPage"
	_back.pressed.connect(show_previous)
	buttons.add_child(_back)
	_next = _button(_button_texts[1] if _button_texts.size() > 1 else "→")
	_next.name = "NextPage"
	_next.pressed.connect(show_next)
	buttons.add_child(_next)
	_back.focus_neighbor_right = _back.get_path_to(_next)
	_next.focus_neighbor_left = _next.get_path_to(_back)


## ページ i を出す
func show_page(i: int) -> void:
	if pages.is_empty():
		return
	index = clampi(i, 0, pages.size() - 1)
	var page: Dictionary = pages[index]
	_progress.text = "%s  %d / %d" % [header, index + 1, pages.size()]
	_title.text = str(page.get("title", ""))
	_body.text = str(page.get("body", ""))
	_note.text = str(page.get("note", ""))
	_note.visible = not _note.text.is_empty()
	_image.texture = page.get("image") as Texture2D
	_focus.queue_redraw()
	var dot_index := 0
	for dot: Node in _dots.get_children():
		var style := StyleBoxFlat.new()
		style.bg_color = PracticeOverlay.ACCENT if dot_index == index else Color(1.0, 1.0, 1.0, 0.18)
		style.set_corner_radius_all(3)
		(dot as Panel).add_theme_stylebox_override("panel", style)
		dot_index += 1
	_back.disabled = index == 0
	_next.text = (_button_texts[2] if _button_texts.size() > 2 else "OK") if is_last_page() \
		else (_button_texts[1] if _button_texts.size() > 1 else "→")
	# スマホはフォーカスを置かない（デスクトップは Enter で次へ進めるように）
	if not MobileUi.is_touch_ui():
		_next.grab_focus.call_deferred()
	page_changed.emit(index)


func is_last_page() -> bool:
	return index >= pages.size() - 1


func page_id() -> StringName:
	return StringName(pages[index].get("id", &"")) if not pages.is_empty() else &""


func show_previous() -> void:
	if _done or index <= 0:
		return
	show_page(index - 1)


func show_next() -> void:
	if _done:
		return
	if is_last_page():
		_finish(true)
		return
	show_page(index + 1)


## Esc：残りのページをとばす
func skip() -> void:
	_finish(false)


func _finish(completed: bool) -> void:
	if _done:
		return
	_done = true
	visible = false
	finished.emit(completed)


## 紹介の間は、キーとパッドのボタンを下のメニューへ流さない
func _input(event: InputEvent) -> void:
	if _done or not visible:
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		skip()
	elif event.is_action_pressed(&"ui_left"):
		show_previous()
	elif event.is_action_pressed(&"ui_right"):
		show_next()
	elif event.is_action_pressed(&"ui_accept"):
		if get_viewport().gui_get_focus_owner() == _back and not _back.disabled:
			show_previous()
		else:
			show_next()


func _draw_focus() -> void:
	if pages.is_empty() or _image.texture == null:
		return
	var focus: Rect2 = pages[index].get("focus", Rect2())
	if focus.size == Vector2.ZERO:
		return
	# 画像は枠の中で縦横比のまま真ん中に置かれる：画像の出ている四角に合わせる
	var area := _focus.size
	var texture_size := _image.texture.get_size()
	var fit := minf(area.x / texture_size.x, area.y / texture_size.y)
	var shown := texture_size * fit
	var origin := (area - shown) * 0.5
	var ring := Rect2(origin + focus.position * shown, focus.size * shown).grow(4.0)
	_focus.draw_rect(Rect2(0.0, 0.0, area.x, ring.position.y), SHADE)
	_focus.draw_rect(Rect2(0.0, ring.end.y, area.x, area.y - ring.end.y), SHADE)
	_focus.draw_rect(Rect2(0.0, ring.position.y, ring.position.x, ring.size.y), SHADE)
	_focus.draw_rect(Rect2(ring.end.x, ring.position.y, area.x - ring.end.x, ring.size.y), SHADE)
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.border_color = PracticeOverlay.ACCENT
	border.set_border_width_all(4)
	border.set_corner_radius_all(12)
	_focus.draw_style_box(border, ring)
	var badge := ring.position + Vector2(2.0, 2.0)
	_focus.draw_circle(badge, 17.0, PracticeOverlay.ACCENT)
	var font := PracticeOverlay.FONT
	var number := str(index + 1)
	var text_size := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	_focus.draw_string(font, badge + Vector2(-text_size.x * 0.5, 6.5), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, BADGE_INK)


func _text(font_size: int, color: Color, wrap := false) -> Label:
	var label := PracticeOverlay._label("", font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(GUIDE_WIDTH, 0.0)
	return label


func _button(text: String) -> Button:
	var button := MenuMetalButton.new()
	button.compact = not MobileUi.is_touch_ui()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, MobileUi.touch(52))
	button.add_theme_font_size_override("font_size", MobileUi.font(18))
	# スマホはフォーカスを持たせない（タップしたボタンに残ったフォーカスで、決定のキーが前のページへ戻さないように）
	if MobileUi.is_touch_ui():
		button.focus_mode = Control.FOCUS_NONE
	return button

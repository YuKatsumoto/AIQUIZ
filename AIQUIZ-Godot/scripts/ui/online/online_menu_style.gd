class_name OnlineMenuStyle
extends RefCounted

## オンライン専用メニュー画面の見た目（色・文字・部品）。ページはここの部品だけで組み立てる。
## デザインを作り直すときは、まずここを差し替える（docs/online_menu.md）。

const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")

const BG_TOP := Color("#0f2a44")
const BG_BOTTOM := Color("#081420")
## カード：3D の看板（スキン設定）と同じ紺。後ろのヘリが透けてにごらないよう、ほぼ不透明にする。
const CARD := Color(0.075, 0.145, 0.227, 0.94)
const CARD_EDGE := Color(1.0, 1.0, 1.0, 0.10)
const CARD_SHADOW := Color(0.0, 0.02, 0.06, 0.38)
## 入力欄と値の表示枠（カードより一段へこんだ色）
const FIELD := Color("#0a1624")
const FIELD_EDGE := Color(0.35, 0.62, 0.82, 0.45)
const ACCENT := Color("#ffd94a")
## メインメニューの「オンライン対戦」ボタンと、この画面の差し色。
const ACCENT_ONLINE := Color("#4fc3f7")
const TEXT := Color(0.93, 0.95, 0.99)
const MUTED := Color(0.62, 0.69, 0.8)
const WARN := Color(1.0, 0.66, 0.48)
const ME := Color(0.55, 0.85, 1.0)
const THEM := Color(1.0, 0.62, 0.56)


static func label(text: String, size: int, color: Color = TEXT, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var node := Label.new()
	node.text = text
	node.horizontal_alignment = align
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


static func wrap_label(text: String, size: int, color: Color = MUTED) -> Label:
	var node := label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


## メインメニューと同じ金属プレートのボタン。featured は画面でいちばん押してほしいもの。
static func button(text: String, min_size: Vector2, font_size: int, featured := false) -> MenuMetalButton:
	var node := MenuMetalButton.new()
	node.text = text
	node.compact = not featured
	node.featured = featured
	node.accent = ACCENT_ONLINE
	node.custom_minimum_size = min_size
	node.add_theme_font_size_override("font_size", font_size)
	return node


## ◀ ▶ の小さい矢印ボタン（せっていの切り替え用）。
static func arrow_button(text: String) -> MenuMetalButton:
	var node := MenuMetalButton.new()
	node.text = text
	node.arrow_button = true
	node.accent = ACCENT_ONLINE
	node.custom_minimum_size = Vector2(52, 48)
	node.add_theme_font_size_override("font_size", 18)
	return node


## 角丸のカード（紺、細いふち、うすい影）。中身は返り値の VBoxContainer に入れる。
static func card(parent: Control, separation := 10) -> VBoxContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = CARD
	box.border_color = CARD_EDGE
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 14
	box.content_margin_bottom = 16
	box.shadow_color = CARD_SHADOW
	box.shadow_size = 10
	box.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", box)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	panel.add_child(column)
	return column


## カードの見出し：左の黄色い帯と黄色の文字。hint は右に小さく出す補足。
static func section(parent: Control, title: String, hint := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var bar := ColorRect.new()
	bar.color = ACCENT
	bar.custom_minimum_size = Vector2(4, 20)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var heading := label(title, 18, ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not hint.is_empty():
		var note := label(hint, 14, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(note)
	return row


## へこんだ表示枠の中の値（◀ ▶ のあいだ）。横に広がる。返り値の Label に text を入れる。
static func readout(parent: Control, font_size: int) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _field_box(FIELD_EDGE, 1))
	parent.add_child(panel)
	var value := label("", font_size)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(value)
	return value


static func line_edit(placeholder: String, max_length: int, min_size: Vector2, font_size: int) -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.max_length = max_length
	node.alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.custom_minimum_size = min_size
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_stylebox_override("normal", _field_box(FIELD_EDGE, 2))
	node.add_theme_stylebox_override("focus", _field_box(ACCENT_ONLINE, 2, true))
	node.add_theme_stylebox_override("read_only", _field_box(FIELD_EDGE, 2))
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_placeholder_color", Color(MUTED, 0.6))
	node.add_theme_color_override("caret_color", ACCENT_ONLINE)
	node.add_theme_color_override("selection_color", Color(ACCENT_ONLINE, 0.35))
	return node


## 入力欄と表示枠の箱（へこんだ紺、角丸 8）。focus はフォーカス中の光るふち（中は描かない）。
static func _field_box(edge: Color, width: int, focus := false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0) if focus else FIELD
	box.draw_center = not focus
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(8)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


static func spacer(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 3D の上に載せる文字の影（明るい空や海の前でも読める）。
static func shadow(node: Label) -> void:
	node.add_theme_color_override("font_shadow_color", Color(0.0, 0.03, 0.08, 0.7))
	node.add_theme_constant_override("shadow_offset_x", 0)
	node.add_theme_constant_override("shadow_offset_y", 2)
	node.add_theme_constant_override("shadow_outline_size", 6)


## 左の列の下に敷く暗いぼかし（左端が濃く、画面の 6 割ほどで透明になる）。
static func scrim_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.05, 0.09, 0.78))
	gradient.set_color(1, Color(0.02, 0.05, 0.09, 0.0))
	gradient.set_offset(0, 0.0)
	gradient.set_offset(1, 0.62)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 8
	return texture


static func background_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, BG_TOP)
	gradient.set_color(1, BG_BOTTOM)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 8
	texture.height = 256
	return texture

class_name OnlineMenuStyle
extends RefCounted

## オンライン専用メニュー画面の見た目（色・文字・部品）。ページはここの部品だけで組み立てる。
## デザインを作り直すときは、まずここを差し替える（docs/online_menu.md）。

const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")

const BG_TOP := Color("#0f2a44")
const BG_BOTTOM := Color("#081420")
const CARD := Color(0.07, 0.11, 0.17, 0.86)
const CARD_EDGE := Color(0.35, 0.62, 0.82, 0.55)
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


## 角丸の半透明カード。中身は返り値の VBoxContainer に入れる。
static func card(parent: Control, separation := 10) -> VBoxContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = CARD
	box.border_color = CARD_EDGE
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", box)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	panel.add_child(column)
	return column


static func line_edit(placeholder: String, max_length: int, min_size: Vector2, font_size: int) -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.max_length = max_length
	node.alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.custom_minimum_size = min_size
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", font_size)
	return node


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

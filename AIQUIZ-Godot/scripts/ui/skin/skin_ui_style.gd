extends RefCounted
class_name SkinUiStyle

## スキン編集 UI の共通の色・文字・描画ヘルパー。
## ボタン類は BaseButton を継承して自前で描く（メニューの一括スタイルが Button だけを上書きするため）。

const FONT_BOLD: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const FONT_MEDIUM: Font = preload("res://resources/fonts/NotoSansJP-Medium.otf")

const GOLD := Color(1.0, 0.82, 0.26)
const GOLD_SOFT := Color(1.0, 0.88, 0.42)
const TEXT := Color(0.92, 0.94, 1.0)
const MUTED := Color(0.62, 0.68, 0.80)
const DIM := Color(0.42, 0.47, 0.58)
const WARN := Color(1.0, 0.74, 0.30)
const CARD_BG := Color(0.10, 0.12, 0.18, 0.96)
const CARD_BG_HOVER := Color(0.15, 0.18, 0.26, 0.98)
const CARD_BORDER := Color(0.26, 0.31, 0.42, 0.92)
const CARD_BORDER_HOVER := Color(0.48, 0.58, 0.78, 1.0)
const PANEL_BG := Color(0.05, 0.08, 0.12, 0.86)
const PANEL_BORDER := Color(0.3, 0.4, 0.6, 0.5)
const FOCUS := Color(0.55, 0.85, 1.0, 1.0)


static func label(text: String, font_size: int = 15, color: Color = TEXT, bold: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override(&"font_size", font_size)
	node.add_theme_color_override(&"font_color", color)
	if bold:
		node.add_theme_font_override(&"font", FONT_BOLD)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 「② 色」のような番号付きの見出し。detail は右側の補足（対象パーツ名など）。
static func section_header(number: String, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := label(number, 15, Color(0.06, 0.08, 0.12), true)
	badge.name = "Badge"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(22, 22)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = GOLD
	badge_style.set_corner_radius_all(11)
	badge.add_theme_stylebox_override(&"normal", badge_style)
	row.add_child(badge)
	var title_label := label(title, 16, GOLD_SOFT, true)
	title_label.name = "Title"
	row.add_child(title_label)
	var detail := label("", 14, MUTED)
	detail.name = "Detail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(detail)
	return row


static func panel_style(radius: int = 20, margin: float = 18.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_border_width_all(2)
	style.border_color = PANEL_BORDER
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style


## BaseButton の自前描画で使うカードの背景（状態別）。
static func draw_card(item: CanvasItem, rect: Rect2, hovered: bool, selected: bool, accent: Color = GOLD, radius: int = 9) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG_HOVER if hovered else CARD_BG
	if selected:
		style.bg_color = accent.darkened(0.72)
		style.bg_color.a = 0.98
	style.border_color = accent if selected else (CARD_BORDER_HOVER if hovered else CARD_BORDER)
	style.set_border_width_all(3 if selected else 1)
	style.set_corner_radius_all(radius)
	item.draw_style_box(style, rect)


static func draw_focus_ring(item: CanvasItem, rect: Rect2, radius: int = 11) -> void:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = FOCUS
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(radius)
	ring.expand_margin_left = 3.0
	ring.expand_margin_right = 3.0
	ring.expand_margin_top = 3.0
	ring.expand_margin_bottom = 3.0
	item.draw_style_box(ring, rect)


## 中央寄せの1行テキスト。
static func draw_text_centered(item: CanvasItem, rect: Rect2, text: String, font_size: int, color: Color, bold: bool = false) -> void:
	var font := FONT_BOLD if bold else FONT_MEDIUM
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline_y := rect.position.y + (rect.size.y - text_size.y) * 0.5 + font.get_ascent(font_size)
	item.draw_string(
		font,
		Vector2(rect.position.x, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		font_size,
		color,
	)


## 色の上に載せる文字色（明るい色には黒、暗い色には白）。
static func ink_on(color: Color) -> Color:
	return Color(0.06, 0.07, 0.10) if color.get_luminance() > 0.55 else Color(1, 1, 1)

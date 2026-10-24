extends RefCounted
class_name TutorialUiStyle

## チュートリアル V7 の画面（ミッションバー・ルール表示・章バナー・クリア画面・
## コース選択・カスタマイズ紹介）で共通に使う色・文字・枠。
## 色は 3D のキーキャップ（res://scripts/world/tutorial_keycap_3d.gd）とそろえる。

const FONT_BOLD: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const FONT_MEDIUM: Font = preload("res://resources/fonts/NotoSansJP-Medium.otf")

const NAVY := Color("0b1424")
const PANEL := Color(0.035, 0.067, 0.13, 0.9)
const PANEL_SOLID := Color(0.035, 0.067, 0.13, 0.97)
const LINE := Color(0.63, 0.73, 0.9, 0.24)
const ACCENT := Color("ffcc40")
const P1 := Color("ffa440")
const P2 := Color("51d8ec")
const DONE := Color("5cff99")
const DANGER := Color("ff5a4e")
const TEXT := Color("eef3fc")
const MUTED := Color("9fb0cc")
const IVORY := Color("f5f1e8")
const IVORY_SIDE := Color("c9c0ab")
const KEY_INK := Color("1d2433")
const HINT_WARN := Color("ffb3ab")
const HINT_GOOD := Color("a6ffc9")


static func player_color(player_index: int) -> Color:
	return P2 if player_index == 2 else P1


static func make_label(text: String, font_size: int, color: Color, font: Font = FONT_BOLD) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func box(
		bg: Color,
		border: Color = Color.TRANSPARENT,
		border_width: int = 0,
		radius: int = 12,
		margin_x: float = 0.0,
		margin_y: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	style.anti_aliasing = true
	return style


## 丸い下地にアイコンを1つ載せた円盤（ミッションバーの左端・コースカードの章など）。
static func glyph_disc(glyph: String, diameter: float, disc_color: Color, glyph_color: Color) -> Control:
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.custom_minimum_size = Vector2(diameter, diameter)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.add_theme_stylebox_override("panel", box(disc_color, Color.TRANSPARENT, 0, int(diameter * 0.5)))
	var icon := TutorialGlyph.new()
	icon.name = "Glyph"
	icon.glyph = glyph
	icon.color = glyph_color
	icon.cut_color = disc_color
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := diameter * 0.21
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
	disc.add_child(icon)
	return disc


## 実際のキー配列どおりに並べたキーの小さな図（コース選択の説明用）。
## rows はキーの行の配列で、1行は [{"text": String, "units": float, "offset": float}]。
## offset は行頭からの空き（キー何個分か）。WASD なら W の行に offset 1 を置く。
static func key_cluster(rows: Array, accent: Color, unit: float) -> Control:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", int(unit * 0.12))
	for row_variant: Variant in rows:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", int(unit * 0.12))
		column.add_child(row)
		for key_variant: Variant in row_variant:
			var key: Dictionary = key_variant
			var offset := float(key.get("offset", 0.0))
			if offset > 0.0:
				# キー offset 個分の幅。行の間隔（unit × 0.12）は次のキーとの間に別に入る。
				var spacer := Control.new()
				spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
				spacer.custom_minimum_size = Vector2(
					offset * unit + maxf(0.0, offset - 1.0) * unit * 0.12, 1.0
				)
				row.add_child(spacer)
			var chip := TutorialKeyChip.new()
			chip.setup(
				str(key.get("text", "")),
				TutorialKeyChip.Look.TARGET,
				Color(key.get("color", accent)),
				unit,
				float(key.get("units", 1.0))
			)
			row.add_child(chip)
	return column

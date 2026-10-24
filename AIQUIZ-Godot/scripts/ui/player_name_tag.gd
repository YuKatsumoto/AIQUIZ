extends Label
class_name PlayerNameTag

## オンライン対戦で、各プレイヤーの頭上に出す小さな名前の札。
## じゃまにならないよう半透明で、試合中はずっと出しておく。
## 問題の選択肢や問題文に重なったときは、文字を読むじゃまをしないようさらに薄くする。
## 位置はゲームHUDが毎フレーム渡す（point_at）。

const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const FONT_SIZE := 17
const OUTLINE_SIZE := 6
const OUTLINE_COLOR := Color(0.025, 0.035, 0.05, 0.85)
const OPACITY := 0.62
## 選択肢・問題文に重なっているときの濃さ。
const OVERLAP_OPACITY := 0.16
## 濃さが切り替わる速さ（1 秒あたり）。
const FADE_SPEED := 4.0
## プレイヤー色をどれだけ白に混ぜるか（文字は白寄りにして読みやすく）。
const TINT := 0.35
const BOX_WIDTH := 260.0


func _ready() -> void:
	if name.is_empty():
		name = "PlayerNameTag"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_theme_font_override("font", FONT)
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	add_theme_constant_override("outline_size", OUTLINE_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80
	size = Vector2(BOX_WIDTH, FONT_SIZE * 1.6)
	visible = false


func configure(player_name: String, accent_color: Color) -> void:
	if text != player_name:
		text = player_name
	add_theme_color_override("font_color", Color.WHITE.lerp(accent_color, TINT))


## 頭上の点（画面座標）に札の下端の中央を合わせて表示する。
## avoid_rects（画面座標）のどれかに文字が重なっていたら薄くする。
func point_at(screen_point: Vector2, avoid_rects: Array[Rect2], delta: float) -> void:
	position = screen_point - Vector2(size.x * 0.5, size.y)
	var target := OPACITY
	var text_rect := _text_rect()
	for rect: Rect2 in avoid_rects:
		if rect.intersects(text_rect):
			target = OVERLAP_OPACITY
			break
	if visible:
		modulate.a = move_toward(modulate.a, target, delta * FADE_SPEED)
	else:
		# 出し直したときは、重なっているかどうかの濃さからいきなり始める。
		modulate.a = target
		visible = true


## 実際に文字が描かれている範囲（札の箱は名前より広いので、そのままだと重なり判定が大きすぎる）。
func _text_rect() -> Rect2:
	var font := get_theme_font("font")
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	text_size.x = minf(text_size.x, size.x)
	text_size += Vector2.ONE * OUTLINE_SIZE
	return Rect2(position + Vector2((size.x - text_size.x) * 0.5, size.y - text_size.y), text_size)


func hide_tag() -> void:
	visible = false

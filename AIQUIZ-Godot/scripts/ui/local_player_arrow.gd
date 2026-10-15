extends Control
class_name LocalPlayerArrow

## オンライン対戦で、自分が操作しているキャラの頭上に出す下向きの矢印。
## カウントダウンが終わって走り出したときに「ぽん」と大きく出て「じぶん」の札を見せ、
## 1 枚目の問題（壁）を突破したら札を消して、少し小さめの矢印だけが頭上でゆれ続ける。
## 位置と札を出すかどうかは、ゲームHUDが毎フレーム渡す（point_at）。

const DRAW_SIZE := Vector2(140.0, 150.0)
## 矢印の先端（ここが頭上の基準点に重なる）。
const TIP := Vector2(70.0, 138.0)
const HEAD_HALF_WIDTH := 24.0
const HEAD_LENGTH := 26.0
const SHAFT_HALF_WIDTH := 10.0
const SHAFT_LENGTH := 22.0
const OUTLINE := 3.0
const OUTLINE_COLOR := Color(0.025, 0.035, 0.05, 0.92)

## 札を見せているあいだと、札を消したあとの大きさ。
const INTRO_SCALE := 1.35
const SETTLED_SCALE := 1.0
const POP_SECONDS := 0.35
## 札が消えて小さくなるまでの秒数。
const SETTLE_SECONDS := 0.5
const BOB_SPEED := 5.0
const BOB_PIXELS := 7.0

var _accent_color := Color(1.0, 0.48, 0.14)
var _label: Label = null
var _pop_time := 0.0
var _settle := 0.0
var _bob_time := 0.0


func _ready() -> void:
	if name.is_empty():
		name = "LocalPlayerArrow"
	size = DRAW_SIZE
	custom_minimum_size = DRAW_SIZE
	pivot_offset = TIP
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80
	visible = false

	_label = Label.new()
	_label.name = "SelfLabel"
	_label.text = "じぶん"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_label.add_theme_constant_override("outline_size", 8)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 矢印の軸のすぐ上に置く。
	_label.position = Vector2(0.0, TIP.y - HEAD_LENGTH - SHAFT_LENGTH - 46.0)
	_label.size = Vector2(DRAW_SIZE.x, 42.0)
	add_child(_label)
	queue_redraw()


func configure(accent_color: Color) -> void:
	_accent_color = accent_color
	queue_redraw()


## 頭上の点（画面座標）に矢印の先端を合わせて表示する。show_label が false になると札を消す。
func point_at(screen_point: Vector2, delta: float, show_label: bool) -> void:
	if not visible:
		visible = true
		if not show_label:
			# 札を消したあとに画面外から戻っただけなら、小さい矢印のまま出す。
			_settle = 1.0
	# 出だしの「ぽん」は試合で最初に出たときだけ（画面外から戻っても繰り返さない）。
	_pop_time = minf(_pop_time + delta, POP_SECONDS)
	_bob_time = fmod(_bob_time + delta * BOB_SPEED, TAU)
	_settle = move_toward(_settle, 0.0 if show_label else 1.0, delta / SETTLE_SECONDS)

	# 0 から少し行きすぎてから戻る（back-out）。
	var p := _pop_time / POP_SECONDS - 1.0
	var pop_scale := 1.0 + 2.70158 * p * p * p + 1.70158 * p * p
	scale = Vector2.ONE * lerpf(INTRO_SCALE, SETTLED_SCALE, _settle) * pop_scale

	var bob_amount := BOB_PIXELS * (1.6 - 0.6 * _settle)
	position = screen_point - TIP + Vector2(0.0, -absf(sin(_bob_time)) * bob_amount)
	if _label != null:
		_label.modulate.a = 1.0 - _settle
		_label.visible = _settle < 1.0


func hide_arrow() -> void:
	visible = false


func _draw() -> void:
	var shaft_top := TIP.y - HEAD_LENGTH - SHAFT_LENGTH
	var head_base := TIP.y - HEAD_LENGTH
	var arrow := PackedVector2Array([
		Vector2(TIP.x - SHAFT_HALF_WIDTH, shaft_top),
		Vector2(TIP.x + SHAFT_HALF_WIDTH, shaft_top),
		Vector2(TIP.x + SHAFT_HALF_WIDTH, head_base),
		Vector2(TIP.x + HEAD_HALF_WIDTH, head_base),
		TIP,
		Vector2(TIP.x - HEAD_HALF_WIDTH, head_base),
		Vector2(TIP.x - SHAFT_HALF_WIDTH, head_base),
	])
	# 外側に黒いふちを一周させてから、プレイヤー色で塗る（オフスクリーンマーカーと同じ見た目）。
	var outline := PackedVector2Array([
		Vector2(TIP.x - SHAFT_HALF_WIDTH - OUTLINE, shaft_top - OUTLINE),
		Vector2(TIP.x + SHAFT_HALF_WIDTH + OUTLINE, shaft_top - OUTLINE),
		Vector2(TIP.x + SHAFT_HALF_WIDTH + OUTLINE, head_base - OUTLINE),
		Vector2(TIP.x + HEAD_HALF_WIDTH + OUTLINE * 1.8, head_base - OUTLINE),
		TIP + Vector2(0.0, OUTLINE * 1.9),
		Vector2(TIP.x - HEAD_HALF_WIDTH - OUTLINE * 1.8, head_base - OUTLINE),
		Vector2(TIP.x - SHAFT_HALF_WIDTH - OUTLINE, head_base - OUTLINE),
	])
	draw_colored_polygon(outline, OUTLINE_COLOR)
	draw_colored_polygon(arrow, _accent_color)
	# 左半分を少し明るくして立体感を出す。
	var highlight := PackedVector2Array([
		Vector2(TIP.x - SHAFT_HALF_WIDTH, shaft_top),
		Vector2(TIP.x, shaft_top),
		Vector2(TIP.x, TIP.y - 2.0),
		Vector2(TIP.x - HEAD_HALF_WIDTH, head_base),
		Vector2(TIP.x - SHAFT_HALF_WIDTH, head_base),
	])
	draw_colored_polygon(highlight, Color(1.0, 1.0, 1.0, 0.22))

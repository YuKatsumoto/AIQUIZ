extends Control
## エモート設定タブの右ボックスに横並びで表示する「バックライト式メカニカルキーボード風キーキャップ」。
## 下から見上げる斜めパースで、ベージュのキャップ上にプレイヤーアクセント色で光る刻印・
## アンダーグローを描く。set_key() でキー文字・アクセント色・選択状態を渡すと再描画する。

const LEGEND_FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")

var _key_text: String = "1"
var _accent: Color = Color.WHITE
var _selected: bool = false

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(66, 88)

func set_key(text: String, accent: Color, selected: bool = false) -> void:
	_key_text = text
	_accent = accent
	_selected = selected
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 1.0 or h <= 1.0:
		return
	var ci := get_canvas_item()
	var glow := _accent
	glow.a = 1.0
	var sel_mul := 1.6 if _selected else 1.0

	# ── 上面（台形）と前面（壁）の頂点（見上げ視点：奥が狭く・手前が広い）──
	var t_bl := Vector2(w * 0.18, h * 0.10) # 上面 奥左
	var t_br := Vector2(w * 0.82, h * 0.10) # 上面 奥右
	var t_fr := Vector2(w * 0.90, h * 0.40) # 上面 手前右
	var t_fl := Vector2(w * 0.10, h * 0.40) # 上面 手前左
	var f_br := Vector2(w * 0.86, h * 0.92) # 前面 下右
	var f_bl := Vector2(w * 0.14, h * 0.92) # 前面 下左

	# ── 0. アンダーグロー（最背面：半透明角丸を重ねて擬似発光）──
	var rr := roundi(w * 0.28)
	for gi in range(4):
		var gt := float(gi) / 3.0 # 0=外側(淡い大) … 1=内側(明るい小)
		var grow: float = lerpf(16.0, 1.0, gt)
		var ga: float = clampf(lerpf(0.05, 0.16, gt) * sel_mul, 0.0, 0.5)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(glow.r, glow.g, glow.b, ga)
		sb.set_corner_radius_all(rr)
		var pos := Vector2(w * 0.10 - grow, h * 0.34 - grow * 0.6)
		var sz := Vector2(w * 0.80 + grow * 2.0, h * 0.60 + grow)
		sb.draw(ci, Rect2(pos, sz))

	# ── 1. 前面の壁（手前に高い。下端はアンダーグローが映り込む）──
	var front := _rounded_polygon(
		PackedVector2Array([t_fl, t_fr, f_br, f_bl]), w * 0.10, 3
	)
	var front_top := Color(0.70, 0.66, 0.60)
	var front_bot := Color(0.55, 0.50, 0.45).lerp(glow, 0.5 if _selected else 0.35)
	draw_polygon(front, _vgrad_colors(front, h * 0.40, h * 0.92, front_top, front_bot))

	# ── 2. 上面（ベージュ・縦グラデ）──
	var top := _rounded_polygon(
		PackedVector2Array([t_bl, t_br, t_fr, t_fl]), w * 0.10, 3
	)
	var top_c1 := Color(0.92, 0.89, 0.82)
	var top_c2 := Color(0.83, 0.79, 0.71)
	if _selected:
		top_c1 = top_c1.lightened(0.06)
		top_c2 = top_c2.lightened(0.06)
	draw_polygon(top, _vgrad_colors(top, h * 0.10, h * 0.40, top_c1, top_c2))

	# ── 3. 上面リムライト（奥エッジの艶）──
	var rim_a := 0.18 if _selected else 0.10
	draw_line(
		t_bl + Vector2(w * 0.03, 1.0), t_br + Vector2(-w * 0.03, 1.0),
		Color(1.0, 1.0, 1.0, rim_a), 2.0, true
	)
	if _selected:
		draw_line(t_bl, t_br, Color(glow.r, glow.g, glow.b, 0.45), 2.0, true)

	# ── 4. 底のアンダーグロー帯（RGBライン）──
	draw_line(
		Vector2(w * 0.16, h * 0.915), Vector2(w * 0.84, h * 0.915),
		Color(glow.r, glow.g, glow.b, clampf(0.55 * sel_mul, 0.0, 0.9)),
		maxf(h * 0.02, 2.0), true
	)

	# ── 5. 刻印（左上寄せ・発光。台形に乗るよう軽く圧縮＋剪断）──
	var font: Font = LEGEND_FONT if LEGEND_FONT else get_theme_default_font()
	if font:
		var fs := maxi(roundi(h * 0.21), 12)
		var ascent := font.get_ascent(fs)
		var anchor := Vector2(w * 0.21, h * 0.12)
		draw_set_transform_matrix(
			Transform2D(Vector2(1.0, 0.0), Vector2(-0.12, 0.82), anchor)
		)
		var base := Vector2(0.0, ascent)
		var glow_col := Color(glow.r, glow.g, glow.b, 0.28)
		for off in [Vector2(1.4, 0.0), Vector2(-1.4, 0.0), Vector2(0.0, 1.4), Vector2(0.0, -1.4), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
			draw_string(
				font, base + off, _key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, glow_col
			)
		var core := glow.lightened(0.6) if _selected else glow.lightened(0.45)
		draw_string(font, base, _key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, core)
		draw_set_transform_matrix(Transform2D.IDENTITY)

## 4頂点のクアッドを角丸ポリゴンへ。各コーナーを半径rで丸める（簡易ベジェ弧）。
func _rounded_polygon(corners: PackedVector2Array, radius: float, segs: int = 3) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := corners.size()
	for i in range(n):
		var cur := corners[i]
		var prev := corners[(i - 1 + n) % n]
		var nxt := corners[(i + 1) % n]
		var r := minf(radius, minf(cur.distance_to(prev), cur.distance_to(nxt)) * 0.5)
		var pa := cur + (prev - cur).normalized() * r
		var pb := cur + (nxt - cur).normalized() * r
		out.append(pa)
		for s in range(1, segs):
			var tt := float(s) / float(segs)
			out.append(pa.lerp(cur, tt).lerp(cur.lerp(pb, tt), tt))
		out.append(pb)
	return out

## ポリゴン各点の y 位置に応じて c_top→c_bot を線形補間した頂点カラー配列を返す。
func _vgrad_colors(pts: PackedVector2Array, y_top: float, y_bot: float, c_top: Color, c_bot: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	var span := maxf(y_bot - y_top, 0.001)
	for p in pts:
		cols.append(c_top.lerp(c_bot, clampf((p.y - y_top) / span, 0.0, 1.0)))
	return cols

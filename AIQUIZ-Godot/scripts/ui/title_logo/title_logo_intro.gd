class_name TitleLogoIntro
extends Control

## タイトル「TESTOPIA」のロゴ（2D）。登場演出を再生し、終わったら最後の姿のまま残る（ベルトコンベアの上のロゴ）。
##   1. 黄色い線が伸びて太くなり、ロゴの下のベルトコンベアになる
##   2. 文字がベルトの右端へ上から 1 文字ずつ落ちてきて、ベルトが左の定位置まで運ぶ。ベルトは左へ流れるので左の部品（扉のブロック）から落とす。
##      T（1つ目）と E は、問題の壁と同じ灰色の枠に青と赤の扉がはまった 1 つのブロック（DOOR_KEY）として落ちてくる
##   3. 全部そろうとベルトが止まり、ブロックが震えて爆散し（破片 SHARD_KEY<n>）、中から T と E が飛び出す
##   4. 最後の姿（ベルトの上のロゴ）のまま残る
## 部品は画面の外（上）から落ちてくる。文字は白一色の面と紺の厚み（立体のブロック）、
## 扉のブロックは灰色の厚み
##
## 動き（時間・キー・イージング）は After Effects で作る（tools/title_logo_ae、docs/title_logo_intro.md）。
## ここでは AE から書き出した MOTION_PATH を再生するだけで、次の値を読む。
##   CTRL のスライダー：Form（0 = 黄色い線、1 = ベルト）、Travel（ベルトが送った距離、論理ピクセル）
##   L_<部品>：部品の形のレイヤー（親の M_<部品> と合わせた変形）、DUST_<n>：着地の土ぼこり（文字の下）、
##   FX_<名前>：文字の上に描く小さな図形（爆散の煙）
## 部品の形は build_layout() がロゴの JSON（TitleLogoGeometry）とブロックの寸法から作り、AE にも同じ値を渡す
## （tools/title_logo_ae/export_layout.gd）。ベルトの描き方（_draw）は、AE の BELT レイヤーの式と同じ計算。
##
## 大きく見せるときは view_scale で拡大して作る（ノードの scale で拡大すると縁のぼかしまで太る）。
## メニューのどの手順でも、立体のベルトの上の立体の文字のまま。

signal finished
## AE のコンポのマーカー（LAND <部品>・ALL SEATED・BURST など）を再生が通り過ぎたとき
signal marker_passed(marker: String)

const MOTION_PATH := "res://assets/ui/title_logo/title_logo_motion.json"
## T（1つ目）と E をまとめて運ぶ扉のブロックと、その破片
const DOOR_KEY := "door"
const DOOR_LETTERS: Array[String] = ["t1", "e"]
const SHARD_KEY := "shard"
const SHARD_COLS := 6
const SHARD_ROWS := 4
## 扉のブロックの色：問題の壁の灰色と、2 択の扉の青・赤（quiz_wall.gd の DOOR_COLORS_2）
const WALL_COLOR := Color(0.64, 0.66, 0.68)
const WALL_RIM_COLOR := Color(0.545, 0.565, 0.596)
const DOOR_COLORS: Array[Color] = [Color(0.10, 0.60, 0.95), Color(0.90, 0.15, 0.10)]
const DOOR_HIGHLIGHT := 0.18
## 扉のブロックの厚み（文字の紺の厚みと同じ向きと長さで、壁の陰の灰色）。破片には厚みも縁も付けない
const WALL_DEPTH_COLOR := Color(0.33, 0.35, 0.39)
const WALL_DEPTH_EDGE_COLOR := Color(0.45, 0.47, 0.51)
## main_menu の TitleAccentBar と同じ色
const BAR_COLOR := Color(1.0, 0.88, 0.25)
## 立体のベルトコンベア（TitleLogoIntro._draw と AE の BELT は同じ計算）：
##   前の面：鉄の枠（黄色い手前の縁・その下の光・止まっているリベット・下の暗い縁・両端の回るローラー）
##   上の面：奥（文字の厚みと同じ右上の向き）へ伸びる帯。板の溝と板の角の光が右へ流れ、奥の縁が明るい
##   側面：前の面を奥へずらした形とのあいだ（右の端と、ローラーに巻き付く所）
const BELT_COLOR := Color(0.13, 0.17, 0.27)
const BELT_BOTTOM_COLOR := Color(0.03, 0.05, 0.10)
const ROLLER_COLOR := Color(0.20, 0.25, 0.36)
const BELT_SIDE_COLOR := Color(0.07, 0.09, 0.16)
const BELT_TOP_COLOR := Color(0.30, 0.36, 0.50)
const BELT_TOP_EDGE_COLOR := Color(0.55, 0.62, 0.78)
const BELT_SLAT_COLOR := Color(0.16, 0.20, 0.31)
const BELT_SLAT_LIGHT_COLOR := Color(0.44, 0.51, 0.66)
const FRAME_HIGHLIGHT_COLOR := Color(0.30, 0.37, 0.52)
const RIVET_COLOR := Color(0.47, 0.54, 0.69)
const RIVET_SPACING := 16.0
## 上の面の見える奥行き（論理ピクセル。奥へ 1 進むと右へ BELT_SKEW ずれる）
const BELT_TOP_DEPTH := 8.0
## 文字の紺の厚み（立体のブロック）：奥（右上）へずらした同じ形を、1 画面ピクセルより細かい間で重ねて描く。
## ベルトの上の面が奥へ伸びる向きと同じにして、文字がベルトの上に立って見えるようにする。
## 一番手前の 1 枚だけ少し明るい紺（縁）。光・つや（ロゴの JSON の flat）には付けない
const DEPTH_OFFSET := Vector2(3.0, -3.8)
const BELT_SKEW := DEPTH_OFFSET.x / -DEPTH_OFFSET.y
const DEPTH_COLOR := Color(0.106, 0.165, 0.29)
const DEPTH_EDGE_COLOR := Color(0.2, 0.278, 0.435)
const DEPTH_STEP_PX := 0.9
## 文字のブロック（面＋厚み）のまわりを囲む、濃い紺の太い縁（明るい空や白いビルに文字が溶けないように）。
## ブロックの形を CanvasGroup にまとめて描き、shaders/title_logo_outline.gdshader で外へ広げて塗る
const LETTER_OUTLINE_SHADER: Shader = preload("res://shaders/title_logo_outline.gdshader")
## 文字の面と厚みの縁をならす（Polygon2D は縁をなめらかに描かないので、面と厚みを CanvasGroup にまとめて
## shaders/title_logo_smooth.gdshader で 1 画素ぶんならす）
const SMOOTH_SHADER: Shader = preload("res://shaders/title_logo_smooth.gdshader")
## 文字（縁取り・厚み・面・爆散の煙）は、画面の SUPERSAMPLE 倍の解像度の SubViewport に描き、
## shaders/title_logo_downsample.gdshader で SUPERSAMPLE × SUPERSAMPLE の画素の平均にして縮めて見せる
## （Polygon2D の縁はなめらかでないので、描いてから縮めてなめらかにする。2026-10-19〜）。
## ベルトと土ぼこりはこの Control に直接描く（円と長方形は Godot がなめらかに描く）
const SUPERSAMPLE := 4
## SubViewport の一辺の上限（画素）。超えるときは倍率を下げる（大きな画面では 3 倍・2 倍になる）
const SUPERSAMPLE_MAX_PX := 4096
## SubViewport に描く範囲：ロゴのまわりの余白（論理ピクセル × view_scale）。
## 部品は上の画面の外から落ちる（落ちはじめは文字の上の端がロゴの 280 ほど上）。爆散の破片は左へ 500・下へ 970 ほどまで
## 飛ぶので SubViewport には入れない（_loose_layer）
## （2026-10-19 に測った範囲：文字と扉のブロックは左右 10・上 282・下 65、煙は左 27・下 61 まで）
const SUPERSAMPLE_PAD_SIDE := 48.0
const SUPERSAMPLE_PAD_TOP := 300.0
const SUPERSAMPLE_PAD_BOTTOM := 72.0
const DOWNSAMPLE_SHADER: Shader = preload("res://shaders/title_logo_downsample.gdshader")
const LETTER_OUTLINE_COLOR := Color(0.04, 0.06, 0.125)
## 縁の太さ（論理ピクセル）
const LETTER_OUTLINE_WIDTH := 1.5
## 文字の前の面の下の端（縁の外側）を、上の面の手前の縁から何ピクセル奥に立たせるか（立体のベルトのとき。AE の接地影も使う）
const BELT_STAND_MARGIN := 1.0
## ベルトの上の縁は、文字の面の下の端（baseline）より BELT_DROP だけ下。
## 平らなベルト（FLAT_BELT）では、書体の比較ページの見本と同じく文字の縁の下の端がベルトの黄色い縁に少し重なる
## （0.012 em。em は文字の高さ 55.7 を Stereofunk の字の高さ 0.8 em で割った 69.65 論理ピクセル）。
## build_layout の belt_rect に入れるので、AE（build_title_logo.jsx）も同じ場所にベルトを描き、文字をそこへ落とす
const BELT_DROP := 0.84
## 文字の足もとの接地影（立体のベルトの上の面に落ちる。文字が高く上がるほど薄い。AE の CS_<文字> と同じ計算）
const CONTACT_SHADOW_ALPHA := 0.45
const CONTACT_SHADOW_FADE := 24.0
## 立体のベルトの影（main_menu._apply_title_logo の影と同じ）
const SHADOW_OFFSET := Vector2(3, 3)
## ベルトの高さと、文字の外への張り出し（見本と同じ：高さ 0.17 em、T の字の原点から左へ 0.2 em・A の字の送り幅の右へ 0.2 em）
const BELT_HEIGHT := 11.84
const BELT_RIGHT_PAD := 14.77
const BELT_LEFT_PAD := 9.89
const RIB_SPACING := 8.0
## true：書体の比較ページ（tools の見本、stereofunk_heads.html の A 案）と同じ平らなベルトを描く（2026-10-19〜）。
## false：立体のベルト（上の面・板・リベット・接地影）。AE（build_title_logo.jsx）の BELT はいまも立体のまま（Godot は読まない）
const FLAT_BELT := true
## 平らなベルト：紺の棒（BELT_COLOR）・下の暗い帯（下から 20%）・目盛り・両端のローラーと、上の縁の黄色い板（左へ流れる）。
## 寸法は見本の em の比率をそのまま論理ピクセルにしたもの
const FLAT_BELT_SHADOW_COLOR := Color(0.016, 0.035, 0.086, 0.32)
const FLAT_BELT_SHADOW_X := 1.39
const FLAT_BELT_TICK_COLOR := Color(0.294, 0.357, 0.494)
const FLAT_BELT_TICK_SPACING := 4.88
const FLAT_BELT_TICK_WIDTH := 0.84
const FLAT_BELT_DASH := 18.11
const FLAT_BELT_GAP := 2.44
## AE で作るときの黄色い線の場所（ロゴの左下。実際の場所は start() で受け取る）
const DEFAULT_BAR_RECT := Rect2(0, 68, 96, 4)
const FAST_FORWARD := 5.0
## 消える部品（扉のブロック）の定位置を測る時刻：消える何秒前か（爆散の前に震えるので、その前の止まった姿で測る）
const REST_BEFORE_OUT := 0.34

class Piece:
	var key := ""
	var face: Node2D
	## 厚み（無ければ null）と、厚みを付ける多角形（flat でないもの）、厚みの色（奥・一番手前の縁）
	var depth: Node2D
	var flat: Array[bool] = []
	var depth_color := DEPTH_COLOR
	var depth_edge_color := DEPTH_EDGE_COLOR
	## 縁の元になる形（Outline のグループの中。面＋厚みのブロック全体の形。無ければ null）
	var outline: Node2D
	## 定位置（部品の外接矩形の中心、ロゴの中の論理ピクセル）
	var slot := Vector2.ZERO
	## 部品の形（論理ピクセル、部品の中心が原点）と色（多角形ごと）
	var outlines: Array[PackedVector2Array] = []
	var colors: Array[Color] = []
	var face_shapes: Array[Polygon2D] = []
	## AE のレイヤー L_<key>
	var layer: Dictionary = {}
	## AE で作ったときの定位置と今の定位置の差（AE を作り直さずにロゴエディタで形を直したときのずれ）
	var rest_shift := Vector2.ZERO
	## 部品の幅と、中心から足もと（baseline）までの下向きの距離（論理ピクセル）。今の足もとの場所（接地影に使う）
	var width := 0.0
	var foot_offset := 0.0
	var foot := Vector2.ZERO

var _motion: Dictionary = {}
var _layers: Dictionary = {}
var _k := 1.0
var _origin := Vector2.ZERO
var _duration := 0.0
var _markers: Dictionary = {}
var _logo_size := Vector2.ZERO
var _view_scale := 1.0
var _pieces: Array[Piece] = []
var _depth_layer: Node2D
var _outline_group: CanvasGroup
var _outline_material: ShaderMaterial
var _face_group: CanvasGroup
## 文字を描く高解像度の SubViewport と、それを縮めて見せる TextureRect（SUPERSAMPLE）
var _ss_viewport: SubViewport
var _ss_view: TextureRect
var _ss_material: ShaderMaterial
var _ss_rect := Rect2()
var _ss_factor := SUPERSAMPLE
## 爆散の破片（SHARD_KEY<n>）は画面の遠くまで飛ぶので、SubViewport に入れずこの Control に直接描く（縮めた絵の上）
var _loose_layer: Node2D
var _bar_rect := DEFAULT_BAR_RECT
var _belt_rect := Rect2()
## 土ぼこり（AE の DUST_<n>、文字の下）と、文字の上に描く小さな図形（FX_<名前>）
var _dust: Array[Dictionary] = []
var _fx_layers: Array[Dictionary] = []
var _fx: Node2D

var _running := false
var _t := 0.0
var _speed := 1.0
var _debug_speed := 1.0
## その時刻のスライダーの値（_apply_frame で決めて _draw で使う）
var _form := 0.0
var _travel := 0.0
## デバッグ用：演出を一定の間隔で撮って user://title_logo_frames/ に保存する（End キーで次の再生から）
var _debug_capture := false
var _debug_capture_next := 0.0
var _debug_capture_index := 0
const DEBUG_CAPTURE_STEP := 0.05


func _init() -> void:
	name = "TitleLogoIntro"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## ロゴの部品の定位置・形・色とベルトの場所（論理ピクセル、ロゴの左上が原点）。
## tools/title_logo_ae/export_layout.gd が AE に渡すのも、この値。
##   pieces：部品（key・slot・size・outlines・colors・flat・depth・outline・depth_colors・rides・rest）。
##     文字（rides = ベルトで運ぶ。DOOR_LETTERS はブロックが爆散したときに出る）、
##     扉のブロック DOOR_KEY（rides）、破片 SHARD_KEY<n>（爆散してから。厚みも縁もない）
##   rest：AE のレイヤーのどの時刻の位置が定位置か（"end" 最後、"out" 消える REST_BEFORE_OUT 秒前、"in" 出たとき）
##   order：落とす順（右の部品から）
static func build_layout(logo_size: Vector2) -> Dictionary:
	var geometry := TitleLogoGeometry.build(TitleLogoGeometry.load_model())
	if geometry.is_empty() or (geometry.get("pieces", []) as Array).is_empty():
		return {}
	var bounds: Rect2 = geometry.bounds
	var s := minf(logo_size.x / bounds.size.x, logo_size.y / bounds.size.y)
	var center := logo_size * 0.5
	var baseline := center.y - float(geometry.baseline) * s
	var pieces: Array = []
	var letters := {}
	for info: Dictionary in geometry.pieces:
		var piece_center: Vector2 = info.center
		var outlines: Array[PackedVector2Array] = []
		for poly: PackedVector2Array in info.polys:
			var points := PackedVector2Array()
			for p: Vector2 in poly:
				points.append(Vector2(p.x, -p.y) * s)
			outlines.append(points)
		var record := {
			"key": str(info.key), "slot": center + Vector2(piece_center.x, -piece_center.y) * s,
			"size": (info.size as Vector2) * s, "outlines": outlines, "colors": info.colors, "flat": info.flat,
			"depth": true, "outline": true,
			"depth_colors": [DEPTH_COLOR, DEPTH_EDGE_COLOR],
			"rides": not DOOR_LETTERS.has(str(info.key)), "rest": "end",
		}
		letters[record.key] = record
		pieces.append(record)
	for key: String in DOOR_LETTERS:
		if not letters.has(key):
			return {}
	var door := _door_layout(letters[DOOR_LETTERS[0]], letters[DOOR_LETTERS[1]], baseline)
	pieces.append(door.block)
	pieces.append_array(door.shards)
	var riders: Array = []
	for record: Dictionary in pieces:
		if record.rides:
			riders.append(record)
	# ベルトの右の端に落とし、左へ流す（2026-10-19〜。それまでは左の端に落として右へ流していた）。
	# 左の部品（扉のブロック）から落とす。どの部品も、右の端がいちばん右の部品（A）の右の端にそろう所へ落ちる
	riders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.slot.x < b.slot.x)
	var left := INF
	var landing_right := -INF
	var order: Array[String] = []
	for record: Dictionary in riders:
		left = minf(left, (record.slot as Vector2).x - (record.size as Vector2).x * 0.5)
		landing_right = maxf(landing_right, (record.slot as Vector2).x + (record.size as Vector2).x * 0.5)
		order.append(str(record.key))
	left -= BELT_LEFT_PAD
	return {
		"logo_size": logo_size, "logo_center": center, "pieces": pieces, "order": order,
		"landing_right": landing_right, "baseline": baseline,
		"belt_rect": Rect2(left, baseline + BELT_DROP, landing_right + BELT_RIGHT_PAD - left, BELT_HEIGHT),
		"door": {"key": DOOR_KEY, "letters": DOOR_LETTERS, "rect": door.rect, "cols": SHARD_COLS, "rows": SHARD_ROWS},
	}


## 扉のブロック：T と E を囲む灰色の枠（上・左右・まん中の柱が同じ太さ）に、同じ幅の青と赤の扉。
## 扉は下の辺まで届く。寸法は文字の高さに比例させる（試作の 55.6 px の文字で枠 7 px・はみ出し 6 px）。
## 厚みは灰色の枠（いちばん外の長方形）にだけ付ける（中の扉は同じ面の上に描く）。
static func _door_layout(first: Dictionary, second: Dictionary, baseline: float) -> Dictionary:
	var cap: float = (first.size as Vector2).y
	var u := cap / 55.6
	var frame := 7.0 * u
	var margin := 6.0 * u
	var x0: float = (first.slot as Vector2).x - (first.size as Vector2).x * 0.5 - margin
	var x1: float = (second.slot as Vector2).x + (second.size as Vector2).x * 0.5 + margin
	var bh := cap * 1.2
	var rect := Rect2(x0, baseline - bh, x1 - x0, bh)
	var block_center := rect.get_center()
	var half := rect.size * 0.5
	var door_w := (rect.size.x - frame * 3.0) / 2.0
	var door_h := bh - frame
	# 部品の中心から見た長方形と色（描く順）
	var rects: Array = [[Rect2(-half, rect.size), WALL_COLOR]]
	for k: int in 2:
		var dx := -half.x + frame + k * (door_w + frame)
		var top := -half.y + frame
		rects.append([Rect2(dx - 1.5 * u, top - 1.5 * u, door_w + 3.0 * u, door_h + 1.5 * u), WALL_RIM_COLOR])
		rects.append([Rect2(dx, top, door_w, door_h), DOOR_COLORS[k]])
		rects.append([Rect2(dx, top, door_w, 4.0 * u), DOOR_COLORS[k].lerp(Color.WHITE, DOOR_HIGHLIGHT)])
	var block := _rect_piece(DOOR_KEY, block_center, rect.size, rects, Rect2(-half, rect.size), true, true, "out")
	var shards: Array = []
	var cell := Vector2(rect.size.x / SHARD_COLS, rect.size.y / SHARD_ROWS)
	for n: int in SHARD_COLS * SHARD_ROWS:
		var c := Rect2(-half + Vector2(n % SHARD_COLS, n / SHARD_COLS) * cell, cell)
		var shard := _rect_piece("%s%d" % [SHARD_KEY, n], block_center + c.get_center(), cell, rects, c, false, false, "in")
		shards.append(shard)
	return {"rect": rect, "block": block, "shards": shards}


## 長方形を clip で切り取った部品（形は clip の中心が原点）。solid：厚みと縁を付ける（いちばん外の長方形にだけ厚み）。
static func _rect_piece(key: String, slot: Vector2, size: Vector2, rects: Array, clip: Rect2, solid: bool,
		rides: bool, rest: String) -> Dictionary:
	var outlines: Array[PackedVector2Array] = []
	var colors: Array[Color] = []
	var flat: Array[bool] = []
	var c := clip.get_center()
	for item: Array in rects:
		var r := (item[0] as Rect2).intersection(clip)
		if r.size.x <= 0.01 or r.size.y <= 0.01:
			continue
		r.position -= c
		outlines.append(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
		colors.append(item[1])
		flat.append(not flat.is_empty())
	return {"key": key, "slot": slot, "size": size, "outlines": outlines, "colors": colors, "flat": flat,
		"depth": solid, "outline": solid, "depth_colors": [WALL_DEPTH_COLOR, WALL_DEPTH_EDGE_COLOR],
		"rides": rides, "rest": rest}


## logo_size：ロゴの大きさ（論理ピクセル。AE はこの大きさで作る）。view_scale：描く倍率（ロゴを大きく見せるとき）。
func setup(logo_size: Vector2, view_scale: float = 1.0) -> bool:
	var layout := build_layout(logo_size)
	if layout.is_empty() or not _load_motion():
		return false
	_logo_size = logo_size
	_belt_rect = layout.belt_rect
	_ss_viewport = SubViewport.new()
	_ss_viewport.name = "Supersample"
	_ss_viewport.transparent_bg = true
	_ss_viewport.disable_3d = true
	_ss_viewport.gui_disable_input = true
	_ss_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	add_child(_ss_viewport)
	_ss_material = ShaderMaterial.new()
	_ss_material.shader = DOWNSAMPLE_SHADER
	_ss_view = TextureRect.new()
	_ss_view.name = "SupersampleView"
	_ss_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ss_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ss_view.stretch_mode = TextureRect.STRETCH_SCALE
	_ss_view.texture = _ss_viewport.get_texture()
	_ss_view.material = _ss_material
	add_child(_ss_view)
	_loose_layer = Node2D.new()
	_loose_layer.name = "Shards"
	add_child(_loose_layer)
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = LETTER_OUTLINE_SHADER
	_outline_material.set_shader_parameter("outline_color", LETTER_OUTLINE_COLOR)
	_outline_group = CanvasGroup.new()
	_outline_group.name = "Outline"
	_outline_group.fit_margin = 24.0
	_outline_group.clear_margin = 24.0
	_outline_group.material = _outline_material
	_ss_viewport.add_child(_outline_group)
	var smooth := ShaderMaterial.new()
	smooth.shader = SMOOTH_SHADER
	var depth_group := CanvasGroup.new()
	depth_group.material = smooth
	_depth_layer = depth_group
	_depth_layer.name = "Depth"
	_ss_viewport.add_child(_depth_layer)
	_face_group = CanvasGroup.new()
	_face_group.name = "Faces"
	_face_group.material = smooth
	_ss_viewport.add_child(_face_group)
	_fx = Node2D.new()
	_fx.name = "Effects"
	_fx.draw.connect(_draw_effects)
	_ss_viewport.add_child(_fx)
	for record: Dictionary in layout.pieces:
		var layer: Dictionary = _layers.get("L_" + str(record.key), {})
		if layer.is_empty():
			return false
		var piece := Piece.new()
		piece.key = record.key
		piece.slot = record.slot
		piece.width = (record.size as Vector2).x
		piece.foot_offset = float(layout.baseline) - piece.slot.y
		piece.outlines = record.outlines
		for c: Color in record.colors:
			piece.colors.append(c)
		for flat: bool in record.flat:
			piece.flat.append(flat)
		var depth_colors: Array = record.depth_colors
		piece.depth_color = depth_colors[0]
		piece.depth_edge_color = depth_colors[1]
		piece.layer = layer
		var rest_t := _duration
		match str(record.rest):
			"out": rest_t = float(layer.get("outPoint", _duration)) - REST_BEFORE_OUT
			"in": rest_t = float(layer.get("inPoint", 0.0))
		piece.rest_shift = piece.slot - _layer_transform(layer, rest_t).origin
		piece.face = _piece_node(piece)
		if piece.key.begins_with(SHARD_KEY):
			_loose_layer.add_child(piece.face)
		else:
			_face_group.add_child(piece.face)
		if record.depth:
			piece.depth = Node2D.new()
			piece.depth.visible = false
			_depth_layer.add_child(piece.depth)
		if record.outline:
			piece.outline = Node2D.new()
			piece.outline.visible = false
			_outline_group.add_child(piece.outline)
		_pieces.append(piece)
	for layer_name: String in _layers:
		if layer_name.begins_with("DUST_"):
			_dust.append(_layers[layer_name])
		elif layer_name.begins_with("FX_"):
			_fx_layers.append(_layers[layer_name])
	set_view_scale(view_scale)
	return true


func _load_motion() -> bool:
	if not FileAccess.file_exists(MOTION_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MOTION_PATH))
	if not parsed is Dictionary:
		return false
	_motion = parsed
	_layers = _motion.get("layers", {})
	_k = float(_motion.get("scale", 1.0))
	var origin: Array = _motion.get("origin", [0, 0])
	_origin = Vector2(float(origin[0]), float(origin[1]))
	_duration = float(_motion.get("duration", 0.0))
	_markers = _motion.get("markers", {})
	return _duration > 0.0 and not _layers.is_empty()


static func _piece_node(piece: Piece) -> Node2D:
	var node := Node2D.new()
	for i: int in piece.outlines.size():
		var shape := Polygon2D.new()
		shape.color = piece.colors[i] if i < piece.colors.size() else Color.WHITE
		shape.antialiased = true
		node.add_child(shape)
		piece.face_shapes.append(shape)
	node.visible = false
	return node


## 描く倍率を変える（形を作り直す。ノードの scale は 1 のまま使う）。
func set_view_scale(view_scale: float) -> void:
	_view_scale = maxf(view_scale, 0.01)
	size = _logo_size * _view_scale
	for piece: Piece in _pieces:
		for i: int in piece.outlines.size():
			piece.face_shapes[i].polygon = _scaled(piece, i)
		_build_depth(piece)
		_build_outline(piece)
	_update_supersample()
	_apply_frame()


## 厚みを今の倍率で作り直す（重ねる枚数は、画面の上で DEPTH_STEP_PX ごとに 1 枚）。
func _build_depth(piece: Piece) -> void:
	if piece.depth == null:
		return
	for child: Node in piece.depth.get_children():
		piece.depth.remove_child(child)
		child.free()
	var offset := DEPTH_OFFSET * _view_scale
	var steps := maxi(3, ceili(offset.length() / DEPTH_STEP_PX))
	for i: int in piece.outlines.size():
		if i < piece.flat.size() and piece.flat[i]:
			continue
		var scaled := _scaled(piece, i)
		for k: int in range(steps, 0, -1):
			var shape := Polygon2D.new()
			shape.polygon = scaled
			shape.color = piece.depth_edge_color if k == 1 else piece.depth_color
			shape.antialiased = true
			shape.position = offset * (float(k) / steps)
			piece.depth.add_child(shape)


## 縁の元になる形を今の倍率で作り直す（ブロック全体の形 = 面の形を厚みの向きへずらして重ねたもの）。
func _build_outline(piece: Piece) -> void:
	if piece.outline == null:
		return
	for child: Node in piece.outline.get_children():
		piece.outline.remove_child(child)
		child.free()
	var offset := DEPTH_OFFSET * _view_scale
	var steps := maxi(2, ceili(offset.length() / 1.5))
	for i: int in piece.outlines.size():
		var scaled := _scaled(piece, i)
		for k: int in range(steps + 1):
			var shape := Polygon2D.new()
			shape.polygon = scaled
			shape.antialiased = true
			shape.position = offset * (float(k) / steps)
			piece.outline.add_child(shape)


## 多角形 i を view_scale 倍にした形。
func _scaled(piece: Piece, i: int) -> PackedVector2Array:
	return Transform2D(0.0, Vector2.ONE * _view_scale, 0.0, Vector2.ZERO) * piece.outlines[i]


## 文字を描く SubViewport の範囲と解像度を、画面の上の大きさ（倍率と、ウィンドウの拡大）に合わせる。
## SubViewport の 1 画素は画面の 1 / _ss_factor 画素。縁の太さも SubViewport の画素で渡す。
func _update_supersample() -> void:
	if _ss_viewport == null:
		return
	var stretch := 1.0
	if is_inside_tree():
		stretch = get_global_transform_with_canvas().get_scale().x * get_viewport().get_final_transform().get_scale().x
	stretch = maxf(stretch, 0.01)
	var pad_lt := Vector2(SUPERSAMPLE_PAD_SIDE, SUPERSAMPLE_PAD_TOP) * _view_scale
	var pad_rb := Vector2(SUPERSAMPLE_PAD_SIDE, SUPERSAMPLE_PAD_BOTTOM) * _view_scale
	_ss_rect = Rect2(-pad_lt, size + pad_lt + pad_rb)
	var screen_px := _ss_rect.size * stretch
	_ss_factor = clampi(floori(SUPERSAMPLE_MAX_PX / maxf(screen_px.x, screen_px.y)), 1, SUPERSAMPLE)
	var k := stretch * _ss_factor
	_ss_viewport.size = Vector2i(ceili(_ss_rect.size.x * k), ceili(_ss_rect.size.y * k))
	# 描画の側に SubViewport の絵の台（canvas）ができるのは木に入ったあとの 1 フレーム目なので、遅らせて渡す
	if _ss_viewport.is_inside_tree():
		_ss_viewport.set_deferred("canvas_transform", Transform2D(0.0, Vector2.ONE * k, 0.0, -_ss_rect.position * k))
	_ss_view.position = _ss_rect.position
	_ss_view.size = Vector2(_ss_viewport.size) / k
	_ss_material.set_shader_parameter("factor", _ss_factor)
	_outline_material.set_shader_parameter("radius_px", LETTER_OUTLINE_WIDTH * _view_scale * k)
	_refresh_supersample_mode()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_update_supersample.call_deferred()
		if not get_viewport().size_changed.is_connected(_update_supersample):
			get_viewport().size_changed.connect(_update_supersample)
	elif what == NOTIFICATION_EXIT_TREE:
		if get_viewport().size_changed.is_connected(_update_supersample):
			get_viewport().size_changed.disconnect(_update_supersample)


func view_scale() -> float:
	return _view_scale


func is_running() -> bool:
	return _running


## AE のマーカーの時刻（秒）。無ければ -1。
func marker_time(marker: String) -> float:
	return float(_markers.get(marker, -1.0))


## 演出の長さ（秒、等倍）。
func duration() -> float:
	return _duration


## 演出を始める。bar_rect：始まりの黄色い線の場所（ロゴから見た位置、論理ピクセル）。
func start(bar_rect: Rect2 = DEFAULT_BAR_RECT) -> void:
	_bar_rect = bar_rect
	_running = true
	_t = 0.0
	_speed = 1.0
	_debug_capture_next = 0.0
	_debug_capture_index = 0
	visible = true
	_apply_frame()


## 演出なしで、最後の姿（ベルトの上のロゴ）を見せる。
func show_final() -> void:
	_running = false
	_t = _duration
	visible = true
	_apply_frame()


## 早送り（キーやクリック）。
func fast_forward() -> void:
	if _running:
		_speed = FAST_FORWARD


## すぐ最後の姿にする（飛ばしたマーカーも知らせる）。
func finish_now() -> void:
	if _running:
		var before := _t
		_t = _duration
		_apply_frame()
		_emit_markers(before, _t)
		_finish()


func _emit_markers(from_t: float, to_t: float) -> void:
	for marker: String in _markers:
		var at := float(_markers[marker])
		if at > from_t and at <= to_t:
			marker_passed.emit(marker)


func _finish() -> void:
	_running = false
	_refresh_supersample_mode()
	finished.emit()


## 文字の高解像度の絵は、演出のあいだは毎フレーム、止まっているときは変わったときに 1 回だけ描き直す。
func _refresh_supersample_mode() -> void:
	if _ss_viewport != null:
		_ss_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE if _running else SubViewport.UPDATE_ONCE


# ---------- 毎フレーム ----------

func _process(delta: float) -> void:
	if not _running:
		return
	var before := _t
	_t += delta * _speed * _debug_speed
	_apply_frame()
	_emit_markers(before, _t)
	if _debug_capture and _t >= _debug_capture_next:
		_debug_capture_next += DEBUG_CAPTURE_STEP
		_save_debug_frame.call_deferred(_debug_capture_index, _t)
		_debug_capture_index += 1
	if _t >= _duration:
		_finish()


func _apply_frame() -> void:
	if _pieces.is_empty():
		return
	var t := minf(_t, _duration)
	_form = _control("Form", t)
	_travel = _control("Travel", t)
	for piece: Piece in _pieces:
		var layer := piece.layer
		var shown := t >= float(layer.get("inPoint", 0.0)) and t < float(layer.get("outPoint", INF))
		# 最後のフレームはレイヤーの終わりと重なるので、最後まで出ているレイヤーは出したままにする
		if not shown and t >= _duration and float(layer.get("outPoint", 0.0)) >= _duration:
			shown = true
		if not shown:
			_place(piece, false, Transform2D.IDENTITY, 0.0)
			continue
		var xform := _layer_transform(layer, t)
		xform.origin += piece.rest_shift
		_place(piece, true, xform, _opacity(layer, t))
	queue_redraw()
	_fx.queue_redraw()
	_refresh_supersample_mode()


## AE のスライダー（CTRL のエフェクト）の値。
func _control(control_name: String, t: float) -> float:
	var record: Variant = (_motion.get("controls", {}) as Dictionary).get(control_name)
	if not record is Dictionary:
		return 0.0
	return float(AeMotion.Layer.sample_track(record.get("track"), record.get("value", 0.0), t * AeMotion.FPS))


func _sample(layer: Dictionary, key: String, t: float) -> Variant:
	return AeMotion.Layer.sample_track((layer.get("tracks", {}) as Dictionary).get(key), layer.base[key], t * AeMotion.FPS)


func _opacity(layer: Dictionary, t: float) -> float:
	return clampf(float(_sample(layer, "opacity", t)) / 100.0, 0.0, 1.0)


## AE のレイヤーの変形を親までたどって合わせ、論理ピクセルの変形にする（形は論理ピクセルで渡す）。
## AE：親の空間の点 = 位置 + 回転・拡大 × (レイヤーの点 − アンカー)
func _layer_transform(layer: Dictionary, t: float) -> Transform2D:
	var comp := Transform2D.IDENTITY
	var current := layer
	while not current.is_empty():
		var anchor: Vector2 = _sample(current, "anchor", t)
		var pos: Vector2 = _sample(current, "position", t)
		var scale_xy: Vector2 = (_sample(current, "scale", t) as Vector2) / 100.0
		var rot := deg_to_rad(float(_sample(current, "rotation", t)))
		comp = Transform2D(rot, scale_xy, 0.0, pos) * Transform2D(0.0, -anchor) * comp
		var parent: Variant = current.get("parent")
		current = _layers.get(parent, {}) if parent != null else {}
	# AE のピクセル → 論理ピクセル（形は論理ピクセルなので K 倍してから載せる）
	return Transform2D(0.0, Vector2.ONE / _k, 0.0, _origin) * comp * Transform2D(0.0, Vector2.ONE * _k, 0.0, Vector2.ZERO)


func _place(piece: Piece, shown: bool, xform: Transform2D, alpha: float) -> void:
	piece.face.visible = shown and alpha > 0.0
	if piece.depth != null:
		piece.depth.visible = piece.face.visible
	if piece.outline != null:
		piece.outline.visible = piece.face.visible
	if not piece.face.visible:
		return
	# 形は view_scale 倍で作ってあるので、変形もその座標に直す（拡大 × 変形 × 縮小）
	var vs := _view_scale
	var x := Transform2D(xform.x, xform.y, xform.origin * vs)
	piece.face.transform = x
	piece.foot = xform * Vector2(0.0, piece.foot_offset)
	piece.face.modulate.a = alpha
	if piece.depth != null:
		piece.depth.transform = x
		piece.depth.modulate.a = alpha
	if piece.outline != null:
		piece.outline.transform = x
		piece.outline.modulate.a = alpha


# ---------- ベルトコンベアを描く（AE の BELT レイヤーの式と同じ計算） ----------

func _draw() -> void:
	if not visible or _pieces.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _view_scale)
	var f := _form
	# 横に伸びてから、太くなって持ち上がる
	var ex := smoothstep(0.0, 1.0, clampf(f / 0.6, 0.0, 1.0))
	var ey := maxf((f - 0.35) / 0.65, 0.0)
	var x0 := lerpf(_bar_rect.position.x, _belt_rect.position.x, ex)
	var x1 := lerpf(_bar_rect.end.x, _belt_rect.end.x, ex)
	var y0 := lerpf(_bar_rect.position.y, _belt_rect.position.y, smoothstep(0.0, 1.0, minf(ey, 1.0)))
	var h := lerpf(_bar_rect.size.y, BELT_HEIGHT, ey)
	var belt := smoothstep(0.25, 0.75, f)
	var r := h * 0.5 * belt
	# 上の面の奥行き（線の姿では無い）と、奥の端へのずれ（文字の厚みと同じ右上の向き）
	var top := BELT_TOP_DEPTH * belt
	var back := Vector2(top * BELT_SKEW, -top)
	var detail := smoothstep(0.6, 1.0, f)
	if FLAT_BELT:
		_draw_flat_belt(x0, x1, y0, h, r, belt, detail)
		_draw_shapes(self, _dust)
		draw_set_transform(Vector2.ZERO)
		return
	if belt > 0.0:
		# 影（ロゴと同じ向き）と側面：前の面と、それを奥へずらした形をつないだ形
		var body := _belt_body(x0, x1, y0, h, r, back)
		var shadow := PackedVector2Array()
		for p: Vector2 in body:
			shadow.append(p + SHADOW_OFFSET)
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.4 * belt))
		_draw_polygon_aa(body, BAR_COLOR.lerp(BELT_SIDE_COLOR, belt))
	if top > 0.25:
		var tl := Vector2(x0 + r, y0)
		var tr := Vector2(x1 - r, y0)
		_draw_polygon_aa(PackedVector2Array([tl, tr, tr + back, tl + back]), BELT_TOP_COLOR)
		# 板：溝と、そのすぐ右の板の角の光が、奥へ斜めに並んで左へ流れる（Travel が増えると左へ）
		var groove := BELT_SLAT_COLOR
		groove.a = detail
		var light := BELT_SLAT_LIGHT_COLOR
		light.a = detail
		var sx := x0 + r + fposmod(-_travel, RIB_SPACING)
		while sx < x1 - r:
			_draw_slat(sx - 0.5, 1.0, y0, back, groove)
			if sx + 1.3 < x1 - r:
				_draw_slat(sx + 0.5, 0.8, y0, back, light)
			sx += RIB_SPACING
		_draw_band(tl + back, tr + back, 0.8, BELT_TOP_EDGE_COLOR)
	_draw_stadium(Rect2(x0, y0, x1 - x0, h), r, BAR_COLOR.lerp(BELT_COLOR, belt), Vector2.ZERO)
	if belt > 0.0:
		# 下の縁を少し暗く
		var bottom := BAR_COLOR.lerp(BELT_BOTTOM_COLOR, belt)
		draw_rect(Rect2(x0 + r, y0 + h - 2.0, x1 - x0 - r * 2.0, 2.0), bottom)
		# 鉄の枠：上の縁のすぐ下の光と、止まっているリベット
		var shine := FRAME_HIGHLIGHT_COLOR
		shine.a = detail
		draw_rect(Rect2(x0 + r, y0 + 2.0, maxf(x1 - x0 - r * 2.0, 0.0), 0.8), shine)
		var rivet := RIVET_COLOR
		rivet.a = detail
		var rx := x0 + r + RIVET_SPACING * 0.5
		while rx < x1 - r - 1.0:
			draw_circle(Vector2(rx, y0 + h * 0.5), 0.9, rivet, true, -1.0, true)
			rx += RIVET_SPACING
		# 両端のローラー（ハブと十字が回る。ベルトが左へ流れるので反時計回り）
		var hub := maxf(r - 2.0, 0.0) * smoothstep(0.55, 1.0, f)
		if hub > 0.3:
			var angle := -_travel / maxf(r, 1.0)
			for cx: float in [x0 + r, x1 - r]:
				var c := Vector2(cx, y0 + h * 0.5)
				draw_circle(c, hub, ROLLER_COLOR, true, -1.0, true)
				for k: int in 2:
					var d := Vector2.from_angle(angle + k * PI * 0.5) * hub
					draw_line(c - d, c + d, BAR_COLOR, 1.2, true)
				draw_circle(c, hub * 0.35, BAR_COLOR, true, -1.0, true)
	# 上の縁は黄色（線の色のまま残る）
	if belt > 0.0 and x1 - x0 > r * 2.0:
		draw_rect(Rect2(x0 + r, y0, x1 - x0 - r * 2.0, 2.0), BAR_COLOR)
	# 文字の足もとの接地影（文字より下、ベルトより上）
	if top > 0.25:
		for piece: Piece in _pieces:
			# 破片（厚みのない部品）は飛んでいくので影を落とさない
			if piece.face.visible and piece.depth != null:
				_draw_contact_shadow(piece)
	_draw_shapes(self, _dust)
	draw_set_transform(Vector2.ZERO)


## 平らなベルト（書体の比較ページの見本の drawBelt と同じ計算）。belt：線の姿 0 〜 ベルト 1、detail：細部の濃さ。
## 黄色い線のあいだは全部黄色で、ベルトになるにつれて紺の棒・目盛り・ローラーが出てくる。
## 上の縁の黄色は板の並び（すき間で区切る）で、Travel が増えると左へ流れる
func _draw_flat_belt(x0: float, x1: float, y0: float, h: float, r: float, belt: float, detail: float) -> void:
	if belt > 0.0:
		var shadow := FLAT_BELT_SHADOW_COLOR
		shadow.a *= belt
		_draw_stadium(Rect2(x0, y0, x1 - x0, h), r, shadow, Vector2(FLAT_BELT_SHADOW_X, h * 0.3) * belt)
	var body := BAR_COLOR.lerp(BELT_COLOR, belt)
	_draw_stadium(Rect2(x0, y0, x1 - x0, h), r, body, Vector2.ZERO)
	if belt <= 0.0:
		return
	# 下の暗い帯（棒の形で切り抜く）
	var band := PackedVector2Array([Vector2(x0 - 1.0, y0 + h * 0.8), Vector2(x1 + 1.0, y0 + h * 0.8),
		Vector2(x1 + 1.0, y0 + h + 1.0), Vector2(x0 - 1.0, y0 + h + 1.0)])
	for part: PackedVector2Array in Geometry2D.intersect_polygons(_stadium_points(x0, x1, y0, h, r, Vector2.ZERO), band):
		draw_colored_polygon(part, BAR_COLOR.lerp(BELT_BOTTOM_COLOR, belt))
	# 目盛り（止まっている）
	var tick := FLAT_BELT_TICK_COLOR
	tick.a = detail
	var tx := x0 + r * 1.6
	while tx < x1 - r * 1.6:
		draw_rect(Rect2(tx, y0 + h * 0.42, FLAT_BELT_TICK_WIDTH, h * 0.28), tick)
		tx += FLAT_BELT_TICK_SPACING
	# 上の縁の黄色い板：全部黄色に塗ってから、板のすき間を棒の色で抜く（すき間は左へ流れる）
	var left := x0 + r
	var right := x1 - r
	if right > left:
		var th := h * 0.2
		draw_rect(Rect2(left, y0, right - left, th), BAR_COLOR)
		var gap_color := body
		gap_color.a = detail
		var period := FLAT_BELT_DASH + FLAT_BELT_GAP
		var gx := left + fposmod(-_travel, period) - period + FLAT_BELT_DASH
		while gx < right:
			var a := maxf(gx, left)
			var b := minf(gx + FLAT_BELT_GAP, right)
			if b > a:
				draw_rect(Rect2(a, y0, b - a, th), gap_color)
			gx += period
	# 両端のローラー
	var roller := ROLLER_COLOR
	roller.a = detail
	for cx: float in [x0 + r, x1 - r]:
		var c := Vector2(cx, y0 + h * 0.5)
		draw_circle(c, r * 0.78, roller, true, -1.0, true)
		draw_circle(c, r * 0.3, tick, true, -1.0, true)


## ベルトの形（前の面と、それを奥へ back だけずらした形をつないだ形）。AE の BELT の hull(stadPts(...)) と同じ。
func _belt_body(x0: float, x1: float, y0: float, h: float, r: float, back: Vector2) -> PackedVector2Array:
	var points := _stadium_points(x0, x1, y0, h, r, Vector2.ZERO)
	points.append_array(_stadium_points(x0, x1, y0, h, r, back))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return hull


## _draw_stadium と同じ形の輪郭の点（両端の半円を 12 等分）。
static func _stadium_points(x0: float, x1: float, y: float, h: float, r: float, shift: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if r <= 0.25:
		for p: Vector2 in [Vector2(x0, y), Vector2(x1, y), Vector2(x1, y + h), Vector2(x0, y + h)]:
			out.append(p + shift)
		return out
	var rr := minf(r, h * 0.5)
	var cy := y + h * 0.5 + shift.y
	for i: int in 13:
		out.append(Vector2(x1 - r + shift.x, cy) + Vector2.from_angle(-PI * 0.5 + PI * i / 12.0) * rr)
	for i: int in 13:
		out.append(Vector2(x0 + r + shift.x, cy) + Vector2.from_angle(PI * 0.5 + PI * i / 12.0) * rr)
	return out


## 塗った多角形の縁を、同じ色の細い線でなめらかにする（draw_colored_polygon は縁がぎざぎざ）。
func _draw_polygon_aa(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, color)
	var ring := points.duplicate()
	ring.append(points[0])
	draw_polyline(ring, color, 0.6, true)


## 上の面の板（幅 w の、奥へ斜めに伸びる細い平行四辺形）。
func _draw_slat(x: float, w: float, y0: float, back: Vector2, color: Color) -> void:
	var a := Vector2(x, y0)
	draw_colored_polygon(PackedVector2Array([a, a + Vector2(w, 0.0), a + Vector2(w, 0.0) + back, a + back]), color)


## 横の細い帯（左の点から右の点まで、下へ thickness）。
func _draw_band(left: Vector2, right: Vector2, thickness: float, color: Color) -> void:
	var down := Vector2(0.0, thickness)
	draw_colored_polygon(PackedVector2Array([left, right, right + down, left + down]), color)


## 文字の足もとの接地影：足もとから奥（文字の厚みの向き）へ伸びる平行四辺形を、広く薄く・狭く濃くの 2 枚。
## 文字が上がっているほど薄く、CONTACT_SHADOW_FADE 上がると消える。AE の CS_<文字> と同じ計算。
func _draw_contact_shadow(piece: Piece) -> void:
	var rest_y := _belt_rect.position.y - BELT_DROP
	var lift := rest_y - piece.foot.y
	var a := CONTACT_SHADOW_ALPHA * pow(clampf(1.0 - lift / CONTACT_SHADOW_FADE, 0.0, 1.0), 2.0) * piece.face.modulate.a
	if a <= 0.004:
		return
	var y := _belt_rect.position.y - BELT_STAND_MARGIN
	var back := DEPTH_OFFSET * 1.4
	for spec: Array in [[2.5, 1.0, 0.45], [1.0, 0.5, 1.0]]:
		var pad: float = spec[0]
		var left := Vector2(piece.foot.x - piece.width * 0.5 - pad, y + float(spec[1]))
		var right := Vector2(piece.foot.x + piece.width * 0.5 + pad, y + float(spec[1]))
		draw_colored_polygon(PackedVector2Array([left, right, right + back, left + back]), Color(0, 0, 0, a * float(spec[2])))


func _draw_effects() -> void:
	if visible:
		_draw_shapes(_fx, _fx_layers)


func _draw_stadium(rect: Rect2, radius: float, color: Color, offset: Vector2) -> void:
	var rr := rect
	rr.position += offset
	if radius <= 0.25:
		draw_rect(rr, color)
		return
	draw_rect(Rect2(rr.position.x + radius, rr.position.y, maxf(rr.size.x - radius * 2.0, 0.0), rr.size.y), color)
	draw_circle(Vector2(rr.position.x + radius, rr.position.y + rr.size.y * 0.5), minf(radius, rr.size.y * 0.5), color, true, -1.0, true)
	draw_circle(Vector2(rr.end.x - radius, rr.position.y + rr.size.y * 0.5), minf(radius, rr.size.y * 0.5), color, true, -1.0, true)


## AE の小さな図形のレイヤー（土ぼこり・爆散の煙）を、位置・回転・拡大・不透明度のとおりに描く。
## 円（塗り、または線の輪）と角丸の長方形（両端の丸い棒）。
func _draw_shapes(canvas: CanvasItem, layers: Array[Dictionary]) -> void:
	var t := minf(_t, _duration)
	var view := Transform2D(0.0, Vector2.ONE * _view_scale, 0.0, Vector2.ZERO)
	for layer: Dictionary in layers:
		if t < float(layer.get("inPoint", 0.0)) or t >= float(layer.get("outPoint", INF)):
			continue
		var alpha := _opacity(layer, t)
		var shape: Dictionary = layer.get("shape", {})
		if alpha <= 0.0 or shape.is_empty():
			continue
		var pos: Vector2 = _sample(layer, "position", t)
		var scale_xy: Vector2 = (_sample(layer, "scale", t) as Vector2) / 100.0
		if scale_xy.x <= 0.0 or scale_xy.y <= 0.0:
			continue
		var rot := deg_to_rad(float(_sample(layer, "rotation", t)))
		var size_px: Array = shape.size
		var extent := Vector2(float(size_px[0]), float(size_px[1])) / _k
		canvas.draw_set_transform_matrix(view * Transform2D(rot, scale_xy, 0.0, pos / _k + _origin))
		if shape.has("fill"):
			var color := _shape_color(shape.fill, alpha * float(shape.get("fillOpacity", 100.0)) / 100.0)
			if shape.get("kind") == "rect":
				var half := maxf(extent.x - extent.y, 0.0) * 0.5
				canvas.draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), color, extent.y, true)
				if float(shape.get("radius", 0.0)) > 0.0:
					canvas.draw_circle(Vector2(-half, 0.0), extent.y * 0.5, color, true, -1.0, true)
					canvas.draw_circle(Vector2(half, 0.0), extent.y * 0.5, color, true, -1.0, true)
			else:
				canvas.draw_circle(Vector2.ZERO, extent.x * 0.5, color, true, -1.0, true)
		if shape.has("stroke"):
			canvas.draw_arc(Vector2.ZERO, extent.x * 0.5, 0.0, TAU, 64, _shape_color(shape.stroke, alpha),
				float(shape.get("strokeWidth", 1.0)) / _k, true)
	canvas.draw_set_transform_matrix(view)


static func _shape_color(rgb: Array, alpha: float) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]), alpha)


# ---------- デバッグ（エディタから動かしたときだけ。書き出した製品版では効かない） ----------

func _input(event: InputEvent) -> void:
	if not OS.has_feature("editor") or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# PageUp でもう一度、PageDown でゆっくり（0.25 倍）、End で撮影（F7・F8 はエディタの実行の操作と重なる）
	if key.keycode == KEY_PAGEUP:
		start(_bar_rect)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_PAGEDOWN:
		_debug_speed = 0.25 if is_equal_approx(_debug_speed, 1.0) else 1.0
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_END:
		_debug_capture = not _debug_capture
		get_viewport().set_input_as_handled()


func _save_debug_frame(index: int, at: float) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://title_logo_frames")
	image.save_png("user://title_logo_frames/frame_%03d_t%04d.png" % [index, int(at * 1000.0)])

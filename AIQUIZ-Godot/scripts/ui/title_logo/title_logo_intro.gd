class_name TitleLogoIntro
extends Control

## メインメニューのタイトルの登場演出（2D）。TitleLogo（2D のロゴの画像を載せた入れ物）の子に置く。
##   1. タイトルの下の黄色い線が伸びて太くなり、ロゴの下のベルトコンベアになる
##   2. ロゴの文字がベルトの左端へ上から落ちてきて、ベルトが右の定位置まで運ぶ。
##      ベルトは右へ流れるので、右の文字（Z）から順に落とす（ベルトの上の並びはいつも「…QUIZ」）
##   3. 最後に A→Q の斜め線が Q の切れ目から、なめらかに加速しながら A の足もとまで伸びる
##   4. ベルトコンベアが縮んで黄色い線に戻り、文字はいつもの 2D のロゴ（画像）に入れ替わる
##
## 動き（時間・キー・イージング）は After Effects で作る（tools/title_logo_ae、docs/title_logo_intro.md）。
## ここでは AE から書き出した MOTION_PATH を再生するだけで、次の値を読む。
##   CTRL のスライダー：Form（0 = 黄色い線、1 = ベルト）、Travel（ベルトが送った距離、論理ピクセル）、
##                      Reveal（斜め線の伸び 0〜1）
##   L_<文字>：文字の形のレイヤー（親の M_<文字> と合わせた変形）、DUST_<n>：着地の土ぼこり（文字の下）、
##   FX_<名前>：あれば文字の上に描く小さな図形（今の AE には無い）
## 文字の形はロゴの JSON から作る（TitleLogoGeometry）。ロゴエディタで直した形がそのまま使われ、
## 定位置にそろうと 2D のロゴの画像とぴったり重なる（影も同じ右下 3 px・黒 75％）。
## ベルトの描き方（_draw）は、AE の BELT レイヤーの式と同じ計算にしてある。

signal finished

const MOTION_PATH := "res://assets/ui/title_logo/title_logo_motion.json"
## A→Q の斜め線。ベルトには載せず、最後に Q から伸ばす
const BRIDGE_KEY := "d1"
## main_menu の TitleAccentBar と同じ色
const BAR_COLOR := Color(1.0, 0.88, 0.25)
const BELT_COLOR := Color(0.08, 0.11, 0.19)
const BELT_BOTTOM_COLOR := Color(0.03, 0.05, 0.10)
const RIB_COLOR := Color(0.36, 0.42, 0.56)
const ROLLER_COLOR := Color(0.20, 0.25, 0.36)
## main_menu._apply_title_logo の影と同じ
const SHADOW_OFFSET := Vector2(3, 3)
const SHADOW_ALPHA := 0.75
const BELT_HEIGHT := 11.0
const BELT_RIGHT_PAD := 8.0
const BELT_LEFT_PAD := 6.0
const RIB_SPACING := 8.0
## AE で作るときの黄色い線の場所（main_menu のいつもの配置。実際の場所は start() で受け取る）
const DEFAULT_BAR_RECT := Rect2(0, 68, 96, 4)
const FAST_FORWARD := 5.0

class Piece:
	var key := ""
	var face: Node2D
	var shadow: Node2D
	## 定位置（部品の外接矩形の中心、TitleLogo の中の論理ピクセル）
	var slot := Vector2.ZERO
	## 部品の形（論理ピクセル、部品の中心が原点）と、描いている Polygon2D（斜め線を伸ばすときに切り取る）
	var outlines: Array[PackedVector2Array] = []
	var face_shapes: Array[Polygon2D] = []
	var shadow_shapes: Array[Polygon2D] = []
	## AE のレイヤー L_<key>
	var layer: Dictionary = {}
	## AE で作ったときの定位置と今の定位置の差（AE を作り直さずにロゴエディタで形を直したときのずれ）
	var rest_shift := Vector2.ZERO

var _motion: Dictionary = {}
var _layers: Dictionary = {}
var _k := 1.0
var _origin := Vector2.ZERO
var _duration := 0.0
var _logo_layers: Array[CanvasItem] = []
var _accent_bar: CanvasItem
var _pieces: Array[Piece] = []
var _bridge: Piece = null
var _bridge_axis := Vector2.RIGHT
var _bridge_min := 0.0
var _bridge_max := 0.0
var _shadow_group: CanvasGroup
var _face_group: CanvasGroup
var _bar_rect := Rect2()
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


## ロゴの部品の定位置・形とベルトの場所（論理ピクセル、TitleLogo の左上が原点）。
## tools/title_logo_ae/export_layout.gd が AE に渡すのも、この値。
static func build_layout(logo_size: Vector2) -> Dictionary:
	var geometry := TitleLogoGeometry.build(TitleLogoGeometry.load_model())
	if geometry.is_empty() or (geometry.get("pieces", []) as Array).is_empty():
		return {}
	var bounds: Rect2 = geometry.bounds
	var s := minf(logo_size.x / bounds.size.x, logo_size.y / bounds.size.y)
	var center := logo_size * 0.5
	var pieces: Array = []
	var belt_pieces: Array = []
	for info: Dictionary in geometry.pieces:
		var piece_center: Vector2 = info.center
		var piece_size: Vector2 = info.size
		var outlines: Array[PackedVector2Array] = []
		for poly: PackedVector2Array in info.polys:
			var points := PackedVector2Array()
			for p: Vector2 in poly:
				points.append(Vector2(p.x, -p.y) * s)
			outlines.append(points)
		var record := {
			"key": str(info.key), "slot": center + Vector2(piece_center.x, -piece_center.y) * s,
			"size": piece_size * s, "outlines": outlines,
		}
		pieces.append(record)
		if record.key != BRIDGE_KEY:
			belt_pieces.append(record)
	if belt_pieces.is_empty():
		return {}
	# 右の文字から落とす（ベルトは右へ流れる）。落ちる場所はいちばん左の文字（A）の定位置
	belt_pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.slot.x > b.slot.x)
	var landing_x: float = (belt_pieces[belt_pieces.size() - 1].slot as Vector2).x
	var baseline := center.y - float(geometry.baseline) * s
	var widest := 0.0
	var right := -INF
	var order: Array[String] = []
	for record: Dictionary in belt_pieces:
		widest = maxf(widest, (record.size as Vector2).x)
		right = maxf(right, (record.slot as Vector2).x + (record.size as Vector2).x * 0.5)
		order.append(str(record.key))
	var left := landing_x - widest * 0.5 - BELT_LEFT_PAD
	var layout := {
		"logo_size": logo_size, "logo_center": center, "pieces": pieces, "order": order,
		"landing_x": landing_x, "baseline": baseline,
		"belt_rect": Rect2(left, baseline, right + BELT_RIGHT_PAD - left, BELT_HEIGHT),
	}
	for record: Dictionary in pieces:
		if record.key == BRIDGE_KEY:
			layout.bridge = _measure_bridge(record.outlines)
	return layout


## 斜め線の長い向き（形の点の広がりがいちばん大きい向き）と、その向きに測った形の範囲（部品の中心から）。
## 右（Q）の側を + にする。
static func _measure_bridge(outlines: Array[PackedVector2Array]) -> Dictionary:
	var points := PackedVector2Array()
	for outline: PackedVector2Array in outlines:
		points.append_array(outline)
	var mean := Vector2.ZERO
	for p: Vector2 in points:
		mean += p
	mean /= maxf(points.size(), 1)
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for p: Vector2 in points:
		var d := p - mean
		sxx += d.x * d.x
		syy += d.y * d.y
		sxy += d.x * d.y
	var axis := Vector2.from_angle(0.5 * atan2(2.0 * sxy, sxx - syy))
	if axis.x < 0.0:
		axis = -axis
	var lo := INF
	var hi := -INF
	for p: Vector2 in points:
		lo = minf(lo, p.dot(axis))
		hi = maxf(hi, p.dot(axis))
	return {"axis": axis, "min": lo, "max": hi}


## logo_size：TitleLogo の大きさ（2D のロゴの画像はこの中にまん中ぞろえで縦横比を保って描かれる）。
## logo_layers：2D のロゴの画像（影と白）。演出のあいだ隠し、最後に見せる。
## accent_bar：タイトルの下の黄色い線。作れなければ false（2D のロゴのまま）。
func setup(logo_size: Vector2, logo_layers: Array[CanvasItem], accent_bar: CanvasItem) -> bool:
	var layout := build_layout(logo_size)
	if layout.is_empty() or not _load_motion():
		return false
	_logo_layers = logo_layers
	_accent_bar = accent_bar
	size = logo_size
	_belt_rect = layout.belt_rect
	_shadow_group = CanvasGroup.new()
	_shadow_group.name = "Shadows"
	_shadow_group.self_modulate = Color(1, 1, 1, SHADOW_ALPHA)
	add_child(_shadow_group)
	_face_group = CanvasGroup.new()
	_face_group.name = "Faces"
	add_child(_face_group)
	_fx = Node2D.new()
	_fx.name = "Effects"
	_fx.draw.connect(_draw_effects)
	add_child(_fx)
	for record: Dictionary in layout.pieces:
		var layer: Dictionary = _layers.get("L_" + str(record.key), {})
		if layer.is_empty():
			return false
		var piece := Piece.new()
		piece.key = record.key
		piece.slot = record.slot
		piece.outlines = record.outlines
		piece.layer = layer
		piece.rest_shift = piece.slot - _layer_transform(layer, _duration).origin
		piece.shadow = _piece_node(piece.outlines, Color.BLACK, piece.shadow_shapes)
		_shadow_group.add_child(piece.shadow)
		piece.face = _piece_node(piece.outlines, Color.WHITE, piece.face_shapes)
		_face_group.add_child(piece.face)
		if piece.key == BRIDGE_KEY:
			_bridge = piece
			var bridge: Dictionary = layout.bridge
			_bridge_axis = bridge.axis
			_bridge_min = bridge.min
			_bridge_max = bridge.max
		_pieces.append(piece)
	for layer_name: String in _layers:
		if layer_name.begins_with("DUST_"):
			_dust.append(_layers[layer_name])
		elif layer_name.begins_with("FX_"):
			_fx_layers.append(_layers[layer_name])
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
	return _duration > 0.0 and not _layers.is_empty()


static func _piece_node(outlines: Array[PackedVector2Array], color: Color, shapes: Array[Polygon2D]) -> Node2D:
	var node := Node2D.new()
	for points: PackedVector2Array in outlines:
		var shape := Polygon2D.new()
		shape.polygon = points
		shape.color = color
		shape.antialiased = true
		node.add_child(shape)
		shapes.append(shape)
	node.visible = false
	return node


func is_running() -> bool:
	return _running


## 演出の長さ（秒、等倍）。
func duration() -> float:
	return _duration


## 2D のロゴを隠して演出を始める。bar_rect：黄色い線の場所（TitleLogo から見た位置）。
func start(bar_rect: Rect2) -> void:
	_bar_rect = bar_rect
	_running = true
	_t = 0.0
	_speed = 1.0
	_debug_capture_next = 0.0
	_debug_capture_index = 0
	_set_logo_visible(false)
	visible = true
	_apply_frame()


## 早送り（キーやクリック）。
func fast_forward() -> void:
	if _running:
		_speed = FAST_FORWARD


## すぐ終わらせる。
func finish_now() -> void:
	if _running:
		_finish()


func _set_logo_visible(on: bool) -> void:
	for layer: CanvasItem in _logo_layers:
		if is_instance_valid(layer):
			layer.visible = on
	if is_instance_valid(_accent_bar):
		_accent_bar.self_modulate.a = 1.0 if on else 0.0


func _finish() -> void:
	_running = false
	visible = false
	_set_logo_visible(true)
	finished.emit()


# ---------- 毎フレーム ----------

func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta * _speed * _debug_speed
	_apply_frame()
	if _debug_capture and _t >= _debug_capture_next:
		_debug_capture_next += DEBUG_CAPTURE_STEP
		_save_debug_frame.call_deferred(_debug_capture_index, _t)
		_debug_capture_index += 1
	if _t >= _duration:
		_finish()


func _apply_frame() -> void:
	var t := minf(_t, _duration)
	_form = _control("Form", t)
	_travel = _control("Travel", t)
	for piece: Piece in _pieces:
		var layer := piece.layer
		var shown := t >= float(layer.get("inPoint", 0.0)) and t < float(layer.get("outPoint", INF))
		if shown and piece == _bridge:
			var reveal := _control("Reveal", t)
			shown = reveal > 0.002
			if shown:
				_clip_bridge(lerpf(_bridge_max, _bridge_min, reveal))
		if not shown:
			_place(piece, false, Transform2D.IDENTITY, 0.0)
			continue
		var xform := _layer_transform(layer, t)
		xform.origin += piece.rest_shift
		_place(piece, true, xform, _opacity(layer, t))
	queue_redraw()
	_fx.queue_redraw()


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
	piece.shadow.visible = piece.face.visible
	if not piece.face.visible:
		return
	piece.face.transform = xform
	piece.face.modulate.a = alpha
	piece.shadow.transform = Transform2D(xform.x, xform.y, xform.origin + SHADOW_OFFSET)
	piece.shadow.modulate.a = alpha


## 斜め線を、向きに測って cut より Q の側だけ残して描く（影も同じ）。AE の L_d1 のマスクと同じ。
func _clip_bridge(cut: float) -> void:
	var perp := Vector2(-_bridge_axis.y, _bridge_axis.x)
	var origin := _bridge_axis * cut
	var big := 4096.0
	var keep := PackedVector2Array([origin + perp * big, origin - perp * big,
		origin - perp * big + _bridge_axis * big, origin + perp * big + _bridge_axis * big])
	for i: int in _bridge.outlines.size():
		var shown := PackedVector2Array()
		if cut <= _bridge_min + 0.01:
			shown = _bridge.outlines[i]
		else:
			var parts := Geometry2D.intersect_polygons(_bridge.outlines[i], keep)
			if not parts.is_empty():
				shown = parts[0]
		_bridge.face_shapes[i].polygon = shown
		_bridge.shadow_shapes[i].polygon = shown


# ---------- ベルトコンベアを描く（AE の BELT レイヤーの式と同じ計算） ----------

func _draw() -> void:
	if not _running:
		return
	var f := _form
	# 横に伸びてから、太くなって持ち上がる（戻るときは逆の順）
	var ex := smoothstep(0.0, 1.0, clampf(f / 0.6, 0.0, 1.0))
	var ey := maxf((f - 0.35) / 0.65, 0.0)
	var x0 := lerpf(_bar_rect.position.x, _belt_rect.position.x, ex)
	var x1 := lerpf(_bar_rect.end.x, _belt_rect.end.x, ex)
	var y0 := lerpf(_bar_rect.position.y, _belt_rect.position.y, smoothstep(0.0, 1.0, minf(ey, 1.0)))
	var h := lerpf(_bar_rect.size.y, BELT_HEIGHT, ey)
	var belt := smoothstep(0.25, 0.75, f)
	var r := h * 0.5 * belt
	# 影（ロゴと同じ向き。線の姿では影なし）
	if belt > 0.0:
		_draw_stadium(Rect2(x0, y0, x1 - x0, h), r, Color(0, 0, 0, 0.45 * belt), SHADOW_OFFSET)
	_draw_stadium(Rect2(x0, y0, x1 - x0, h), r, BAR_COLOR.lerp(BELT_COLOR, belt), Vector2.ZERO)
	if belt > 0.0:
		# 下の縁を少し暗く
		var bottom := BAR_COLOR.lerp(BELT_BOTTOM_COLOR, belt)
		draw_rect(Rect2(x0 + r, y0 + h - 2.0, x1 - x0 - r * 2.0, 2.0), bottom)
		# 桟（右へ流れる）
		var rib := RIB_COLOR
		rib.a = smoothstep(0.6, 1.0, f)
		var x := x0 + r + fposmod(_travel, RIB_SPACING)
		while x < x1 - r:
			draw_rect(Rect2(x - 0.7, y0 + 3.0, 1.4, h - 5.5), rib)
			x += RIB_SPACING
		# 両端のローラー（ハブと十字が回る）
		var hub := maxf(r - 2.0, 0.0) * smoothstep(0.55, 1.0, f)
		if hub > 0.3:
			var angle := _travel / maxf(r, 1.0)
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
	_draw_shapes(self, _dust)


func _draw_effects() -> void:
	if _running:
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


## AE の小さな図形のレイヤー（土ぼこり・光・輪・火花）を、位置・回転・拡大・不透明度のとおりに描く。
## 円（塗り、または線の輪）と角丸の長方形（火花。両端の丸い棒）。
func _draw_shapes(canvas: CanvasItem, layers: Array[Dictionary]) -> void:
	var t := minf(_t, _duration)
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
		canvas.draw_set_transform(pos / _k + _origin, rot, scale_xy)
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
		canvas.draw_set_transform(Vector2.ZERO)


static func _shape_color(rgb: Array, alpha: float) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]), alpha)


# ---------- デバッグ（デバッグビルドだけ） ----------

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# PageUp でもう一度、PageDown でゆっくり（0.25 倍）、End で撮影（F7・F8 はエディタの実行の操作と重なる）
	if key.keycode == KEY_PAGEUP and _bar_rect.size.x > 0.0:
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

class_name ChalkCanvas
extends SubViewport

## 黒板 1 枚の面の絵（docs/lecture_hall_plan.md の 3a）。黒板面（PRP_BoardSurface_F / _B）の材質の色を、この
## ビューポートの絵に差し替える。絵は消さない（CLEAR_MODE_NEVER）ので、描いたものが積もっていく:
##   1. 最初の 1 フレームに、Blender で焼いた黒板の色（ホーロー・前の授業の消し跡・チョーク画）を下地として描く
##   2. stroke_to() でチョークの線を少しずつ描き足す（黒板の凹凸でかすれる: 粒の閾値をブラシのシェーダーで掛ける）
##   3. erase_at() で黒板の色を薄く重ねて消す（何度も消さないと跡が残る = 消し跡）
## 座標は黒板の面の上のメートル（u = 見る人の左端から右へ、v = 下端から上へ）。黒板の大きさは board_size。

const CHALK := {
	"white": Color(0.93, 0.93, 0.89),
	"yellow": Color(0.96, 0.86, 0.42),
	"red": Color(0.94, 0.52, 0.55),
	"blue": Color(0.55, 0.74, 0.95),
}
const BOARD_GREEN := Color(0.110, 0.227, 0.180)
const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
## 文字を一度に書き付けるときの材質: 文字の形（アルファ）に黒板の粒を掛けてチョークらしくかすれさせる。
const TEXT_SHADER := """
shader_type canvas_item;
render_mode blend_mix;
uniform sampler2D grain : filter_linear, repeat_enable;
uniform float pressure = 0.85;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = 0.7 * texture(grain, SCREEN_UV * 7.0).r + 0.3 * texture(grain, SCREEN_UV * 2.2).r;
	float th = mix(0.66, 0.3, pressure) + 0.25 * (1.0 - c.a);
	float cov = smoothstep(th - 0.08, th + 0.08, g) * smoothstep(0.15, 0.6, c.a);
	COLOR = vec4(c.rgb, cov * 0.92);
}
"""

## チョークのブラシ: 頂点の色のアルファ = 筆圧（0..1）。黒板の粒（SCREEN_UV = 黒板の面で固定）の山にだけ乗り、
## 筆圧が弱いほど・線の縁ほどかすれる。
const CHALK_SHADER := """
shader_type canvas_item;
render_mode blend_mix;
uniform sampler2D grain : filter_linear, repeat_enable;
uniform float grain_scale = 7.0;
void fragment() {
	float pressure = COLOR.a;
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float edge = 1.0 - smoothstep(0.6, 1.0, r);
	float g = 0.7 * texture(grain, SCREEN_UV * grain_scale).r + 0.3 * texture(grain, SCREEN_UV * grain_scale * 0.31).r;
	float th = mix(0.68, 0.28, pressure) + 0.42 * r * r;
	float cov = smoothstep(th - 0.08, th + 0.08, g) * edge;
	// スタンプは約 2 回重なるので、1 回分の不透明度を下げて重なりで本来の濃さになるようにする
	COLOR = vec4(COLOR.rgb, cov * (0.6 + 0.3 * pressure));
}
"""
## 黒板消しのブラシ: 頂点の色のアルファ = 強さ。拭いた向き（横）の筋と、雲のようなむら。
const ERASE_SHADER := """
shader_type canvas_item;
render_mode blend_mix;
uniform sampler2D grain : filter_linear, repeat_enable;
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float edge = (1.0 - smoothstep(0.7, 1.0, abs(d.x))) * (1.0 - smoothstep(0.6, 1.0, abs(d.y)));
	float streak = texture(grain, vec2(0.37, SCREEN_UV.y * 30.0)).r;
	float cloud = texture(grain, SCREEN_UV * 0.9).r;
	float cov = edge * mix(0.75, 1.15, streak) * mix(0.8, 1.1, cloud);
	COLOR = vec4(COLOR.rgb, clamp(COLOR.a * cov, 0.0, 1.0));
}
"""

## 濡れ雑巾の濡れ具合（別の小さなビューポート、浮動小数で描く）。黒板の材質が暗く・つやつやにする。
## DRY_SECONDS でほぼ乾く（指数で減る）。
const DRY_SECONDS := 22.0
const WET_SIZE := Vector2i(512, 116)

@export var board_size := Vector2(7.53, 1.71)
var px_per_m := 272.0
var _pending_chalk: Array = []   # [from_px, to_px, width_px, color, pressure]
var _pending_erase: Array = []   # [centre_px, size_px, color, strength]
var _brush: _Brush = null
var _eraser: _Brush = null
var _base: TextureRect = null
var _overlay: TextureRect = null
var _overlay_frames := 0
var _base_frames := 0
var _last_point := {}         # stroke id -> Vector2 (px)
var _grain: ImageTexture = null
var _rng := RandomNumberGenerator.new()
var _stamps: Array = []       # [Label, 残りのフレーム数]
var _wet: SubViewport = null
var _wet_brush: _WetBrush = null


class _WetBrush:
	extends Node2D
	var pending: Array = []      # [Rect2, amount]
	var dry := 0.0               # このフレームに乾かす割合
	var soft: Texture2D = null

	func _draw() -> void:
		var area := Rect2(Vector2.ZERO, Vector2(get_viewport_rect().size))
		if dry > 0.0:
			draw_rect(area, Color(0, 0, 0, dry))
		for item: Array in pending:
			draw_texture_rect(soft, item[0], false, Color(1, 1, 1, float(item[1])))
		pending.clear()


class _Brush:
	extends Node2D
	var canvas = null
	var stamp: Texture2D = null
	var kind := "chalk"
	var dirty := false

	func _draw() -> void:
		if canvas != null:
			canvas._flush(self)


func setup(base_texture: Texture2D, size_m: Vector2, resolution := 2048) -> void:
	board_size = size_m
	size = Vector2i(resolution, int(round(resolution * size_m.y / size_m.x)))
	px_per_m = float(size.x) / size_m.x
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	disable_3d = true
	_rng.seed = 0xC4A1
	_base = TextureRect.new()
	_base.name = "Base"
	_base.texture = base_texture
	_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_base.stretch_mode = TextureRect.STRETCH_SCALE
	_base.size = Vector2(size)
	add_child(_base)
	# 黒板の粒（その場で作る。NoiseTexture2D は別スレッドで作られて最初のフレームに間に合わない）
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.frequency = 0.35
	noise.fractal_octaves = 2
	noise.seed = 1729
	var grain_image := noise.get_seamless_image(256, 256)
	grain_image.convert(Image.FORMAT_L8)
	_grain = ImageTexture.create_from_image(grain_image)
	_eraser = _make_brush("Eraser", "erase", ERASE_SHADER)
	_brush = _make_brush("Chalk", "chalk", CHALK_SHADER)
	_setup_wet()


func _setup_wet() -> void:
	_wet = SubViewport.new()
	_wet.name = "Wet"
	_wet.size = WET_SIZE
	_wet.use_hdr_2d = true
	_wet.transparent_bg = false
	_wet.disable_3d = true
	_wet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_wet.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(_wet)
	_wet_brush = _WetBrush.new()
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var d := Vector2((x - 15.5) / 15.5, (y - 15.5) / 15.5)
			var a := clampf(1.0 - maxf(absf(d.x), absf(d.y)) ** 3.0, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a))
	_wet_brush.soft = ImageTexture.create_from_image(image)
	_wet.add_child(_wet_brush)


## 濡れ具合の絵（黒板の材質が使う）。
func wet_texture() -> Texture2D:
	return _wet.get_texture() if _wet != null else null


## 濡れ雑巾で拭いたところを濡らす（uv_m は中心、size_m は雑巾の大きさ、amount 0..1）。
func wet_at(uv_m: Vector2, size_m := Vector2(0.32, 0.22), amount := 0.8) -> void:
	if _wet_brush == null:
		return
	var scale := Vector2(WET_SIZE) / board_size
	var centre := Vector2(uv_m.x, board_size.y - uv_m.y) * scale
	_wet_brush.pending.append([Rect2(centre - size_m * scale * 0.5, size_m * scale), amount])


func _make_brush(node_name: String, kind: String, code: String) -> _Brush:
	var brush := _Brush.new()
	brush.name = node_name
	brush.canvas = self
	brush.kind = kind
	brush.stamp = _make_stamp()
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = code
	mat.shader = shader
	mat.set_shader_parameter("grain", _grain)
	brush.material = mat
	add_child(brush)
	return brush


## 下地は最初の 2 フレームだけ描き、あとは隠す（消さない描画先に残る）。
## 前に来たときの板書を薄く重ねる（項目 25「先週の続き」）。下地と同じ最初の 2 フレームだけ描く。
func overlay_previous(image: Image, alpha: float) -> void:
	if image == null or image.is_empty():
		return
	_overlay = TextureRect.new()
	_overlay.name = "Previous"
	_overlay.texture = ImageTexture.create_from_image(image)
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay.size = Vector2(size)
	_overlay.modulate = Color(1, 1, 1, alpha)
	_overlay_frames = 0
	add_child(_overlay)
	move_child(_overlay, _base.get_index() + 1)


func _process(delta: float) -> void:
	if _overlay != null:
		# 前の板書は 1 フレームだけ重ねて消す（何度も重ねると濃くなる）
		_overlay_frames += 1
		if _overlay_frames > 1:
			_overlay.queue_free()
			_overlay = null
	if _wet_brush != null:
		_wet_brush.dry = 1.0 - exp(-delta * 3.0 / DRY_SECONDS)
		_wet_brush.queue_redraw()
	if _base != null and _base.visible:
		_base_frames += 1
		if _base_frames > 2:
			_base.visible = false
	for item: Array in _stamps:
		item[1] = int(item[1]) - 1
		if int(item[1]) <= 0 and is_instance_valid(item[0]):
			(item[0] as Node).queue_free()
	_stamps = _stamps.filter(func(item: Array) -> bool: return int(item[1]) > 0)
	# ブラシの描画命令は毎フレーム描き直されるので、描いた次のフレームには空の命令で描き直して消す
	# （そうしないと、消したあとに同じ線がまた描かれる）。
	for brush: _Brush in [_brush, _eraser]:
		if brush == null:
			continue
		var pending := _pending_chalk if brush.kind == "chalk" else _pending_erase
		if not pending.is_empty() or brush.dirty:
			brush.queue_redraw()


func to_px(uv_m: Vector2) -> Vector2:
	return Vector2(uv_m.x * px_per_m, (board_size.y - uv_m.y) * px_per_m)


## チョークの線を stroke_id の前の点から uv_m まで描く（最初の点は「押し当て」の点だけ）。pressure 0..1。
func stroke_to(stroke_id: int, uv_m: Vector2, chalk := "white", width_m := 0.02, pressure := 1.0) -> void:
	var p := to_px(uv_m)
	var from: Vector2 = _last_point.get(stroke_id, p)
	_last_point[stroke_id] = p
	_pending_chalk.append([from, p, width_m * px_per_m, CHALK.get(chalk, CHALK.white), pressure])


func end_stroke(stroke_id: int) -> void:
	_last_point.erase(stroke_id)


## 文字を一度に書き付ける（書き順のデータがない間の題字など）。uv_m は文字の左下（m）、height_m は字の高さ。
## 2 フレームだけ描いて消す（消さない描画先に残る）。
func stamp_text(text: String, uv_m: Vector2, height_m: float, chalk := "white", pressure := 0.85) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	var px := int(round(height_m * px_per_m * 1.3))
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", CHALK.get(chalk, CHALK.white))
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = TEXT_SHADER
	mat.shader = shader
	mat.set_shader_parameter("grain", _grain)
	mat.set_shader_parameter("pressure", pressure)
	label.material = mat
	add_child(label)
	var p := to_px(uv_m)
	label.position = Vector2(p.x, p.y - float(px) * 1.25)
	_stamps.append([label, 3])


## 黒板消し: 幅 w・高さ h（m）の長方形で、黒板の色を strength の割合だけ重ねる（筋入り）。
func erase_at(uv_m: Vector2, size_m := Vector2(0.22, 0.09), strength := 0.35) -> void:
	_pending_erase.append([to_px(uv_m), size_m * px_per_m, BOARD_GREEN, strength])


## 濡れ雑巾: 濃い緑で拭く（乾くのは黒板面の材質の側で、時間で戻す）。
func wipe_wet(uv_m: Vector2, size_m := Vector2(0.3, 0.2)) -> void:
	_pending_erase.append([to_px(uv_m), size_m * px_per_m, BOARD_GREEN.darkened(0.25), 0.9])


## 2 本のブラシの _draw から、それぞれ自分の分だけ描いて空にする。同じフレームに両方あるときは、
## 木の順（Eraser が先）で消しの上にチョークが乗る。
func _flush(brush: _Brush) -> void:
	if brush.kind == "chalk":
		brush.dirty = not _pending_chalk.is_empty()
		for item: Array in _pending_chalk:
			_draw_chalk(brush, item[0], item[1], float(item[2]), item[3], float(item[4]))
		_pending_chalk.clear()
	else:
		brush.dirty = not _pending_erase.is_empty()
		for item: Array in _pending_erase:
			_draw_erase(brush, item[0], item[1], item[2], float(item[3]))
		_pending_erase.clear()


func _draw_chalk(brush: _Brush, a: Vector2, b: Vector2, width: float, color: Color, pressure: float) -> void:
	var length := a.distance_to(b)
	var steps := maxi(1, int(ceil(length / maxf(1.0, width * 0.5))))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t) + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
		var w := width * _rng.randf_range(0.9, 1.08)
		var c := Color(color.r, color.g, color.b, clampf(pressure, 0.0, 1.0))
		brush.draw_texture_rect(brush.stamp, Rect2(p - Vector2(w, w) * 0.5, Vector2(w, w)), false, c)


func _draw_erase(brush: _Brush, centre: Vector2, size_px: Vector2, color: Color, strength: float) -> void:
	var c := Color(color.r, color.g, color.b, strength)
	brush.draw_texture_rect(brush.stamp, Rect2(centre - size_px * 0.5, size_px), false, c)


func _make_stamp() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

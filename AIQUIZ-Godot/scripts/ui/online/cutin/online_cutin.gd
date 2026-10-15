class_name OnlineCutin
extends Control

## オンライン対戦の VS カットイン（仕様書 S8 カットインが入る・S9 読み込み・7 見た目）。
## 3D（並走の 2 機）の上に重ねる 2D の層。基準の大きさ 1920×1080 で組み、画面の高さに合わせて縮める。
## 時刻は play() からの秒（CUTIN_IN の始まり）。CUTIN_IN のあとは読み込みのあいだの動き（hold）を続ける。
##   play(info)              info：me / them（名前）、rules、my_slot、my_hat、their_hat、short
##   set_progress(p, wait)   ゲージ（0〜1）と「あいての つうしんを まっています…」
##   hide_now()              すぐ消す（やめる・探し直し）
## 部品の順（下から）：パネル（online_cutin_panel）→ キャラ → 稲妻（online_cutin_seam）→ VS → 名前の帯 → ゲージ → 白い光

const DESIGN := Vector2(1920.0, 1080.0)
const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")
const PANEL_SHADER := preload("res://shaders/online_cutin_panel.gdshader")
const SEAM_SHADER := preload("res://shaders/online_cutin_seam.gdshader")
const NAVY := Color("#1B2A41")
const STAR_YELLOW := Color("#FFD23F")
const STAR_ORANGE := Color("#FF8A00")
const VS_CENTER := Vector2(0.5, 0.40)
const NAME_BAND := Vector2(560.0, 84.0)

var actors: CutinActors
var time := 0.0
var playing := false
var _sting_sent := false
## prime() で先に描いたキャラ絵の中身（play() で同じなら描き直さない）
var _primed_key := ""
## SWAP の直前：ゲージを満たして「じゅんび OK！」にする（この絵を写して覆いにする）
var _ready_look := false

var _root: Control
var _panel: ColorRect
var _panel_material: ShaderMaterial
var _seam: ColorRect
var _seam_material: ShaderMaterial
var _chars: Array[TextureRect] = []
var _vs_root: Control
var _star: Polygon2D
var _star_rim: Polygon2D
var _vs_label: Label
var _rules: Label
var _bands: Array[Control] = []
var _band_names: Array[Label] = []
var _band_tags: Array[Label] = []
var _gauge_root: Control
var _gauge_fill: ColorRect
var _gauge_label: Label
var _flash: ColorRect
var _progress := 0.0
var _shown_progress := 0.0
var _waiting := false
var _colors := [PlayerController.P1_BODY, PlayerController.P2_BODY]
var _scale := 1.0
var _design_size := DESIGN


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	actors = CutinActors.new()
	actors.name = "Actors"
	add_child(actors)
	actors.set_low_quality(GameManager.graphics_quality == "low")
	_root = Control.new()
	_root.name = "Design"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = ColorRect.new()
	_panel.name = "Panels"
	_panel_material = ShaderMaterial.new()
	_panel_material.shader = PANEL_SHADER
	_panel.material = _panel_material
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	for i in range(2):
		var tex := TextureRect.new()
		tex.name = "Char%d" % i
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(tex)
		_chars.append(tex)
	_seam = ColorRect.new()
	_seam.name = "Seam"
	_seam_material = ShaderMaterial.new()
	_seam_material.shader = SEAM_SHADER
	_seam.material = _seam_material
	_seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_seam)
	_build_vs()
	_build_bands()
	_build_gauge()
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)
	resized.connect(_layout)
	_layout()
	_apply_seam_points()


func _build_vs() -> void:
	_vs_root = Control.new()
	_vs_root.name = "VS"
	_vs_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vs_root)
	_star_rim = Polygon2D.new()
	_star_rim.polygon = _star_points(168.0, 118.0)
	_star_rim.color = STAR_ORANGE
	_vs_root.add_child(_star_rim)
	_star = Polygon2D.new()
	_star.polygon = _star_points(150.0, 104.0)
	_star.color = STAR_YELLOW
	_vs_root.add_child(_star)
	_vs_label = Label.new()
	_vs_label.text = "VS"
	_vs_label.add_theme_font_override("font", FONT)
	_vs_label.add_theme_font_size_override("font_size", 170)
	_vs_label.add_theme_color_override("font_color", Color.WHITE)
	_vs_label.add_theme_color_override("font_outline_color", NAVY)
	_vs_label.add_theme_constant_override("outline_size", 24)
	_vs_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_vs_label.add_theme_constant_override("shadow_offset_x", 0)
	_vs_label.add_theme_constant_override("shadow_offset_y", 8)
	_vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vs_label.size = Vector2(420, 260)
	_vs_label.position = Vector2(-210, -138)
	_vs_root.add_child(_vs_label)
	_rules = Label.new()
	_rules.add_theme_font_override("font", FONT)
	_rules.add_theme_font_size_override("font_size", 30)
	_rules.add_theme_color_override("font_color", Color.WHITE)
	_rules.add_theme_color_override("font_outline_color", NAVY)
	_rules.add_theme_constant_override("outline_size", 10)
	_rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rules.size = Vector2(700, 48)
	_rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rules)


func _build_bands() -> void:
	for i in range(2):
		var band := Panel.new()
		band.name = "NameBand%d" % i
		band.size = NAME_BAND
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.92)
		box.set_border_width_all(6)
		box.set_corner_radius_all(18)
		band.add_theme_stylebox_override("panel", box)
		_root.add_child(band)
		var name_label := Label.new()
		name_label.add_theme_font_override("font", FONT)
		name_label.add_theme_font_size_override("font_size", 46)
		name_label.add_theme_color_override("font_color", NAVY)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.size = NAME_BAND - Vector2(24, 0)
		name_label.position = Vector2(12, 0)
		band.add_child(name_label)
		# 帯の上の札（「じぶん」「あいて」）：チームの色の丸い札に白い字
		var pill := PanelContainer.new()
		pill.name = "Tag"
		var pill_box := StyleBoxFlat.new()
		pill_box.set_corner_radius_all(16)
		pill_box.content_margin_left = 18
		pill_box.content_margin_right = 18
		pill_box.content_margin_top = 2
		pill_box.content_margin_bottom = 4
		pill.add_theme_stylebox_override("panel", pill_box)
		pill.position = Vector2(22, -40)
		band.add_child(pill)
		var tag := Label.new()
		tag.add_theme_font_override("font", FONT)
		tag.add_theme_font_size_override("font_size", 26)
		tag.add_theme_color_override("font_color", Color.WHITE)
		pill.add_child(tag)
		_bands.append(band)
		_band_names.append(name_label)
		_band_tags.append(tag)


func _build_gauge() -> void:
	_gauge_root = Control.new()
	_gauge_root.name = "Gauge"
	_gauge_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_gauge_root)
	_gauge_label = Label.new()
	_gauge_label.add_theme_font_override("font", FONT)
	_gauge_label.add_theme_font_size_override("font_size", 28)
	_gauge_label.add_theme_color_override("font_color", Color.WHITE)
	_gauge_label.add_theme_color_override("font_outline_color", NAVY)
	_gauge_label.add_theme_constant_override("outline_size", 10)
	_gauge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gauge_label.size = Vector2(900, 44)
	_gauge_label.position = Vector2(-450, -52)
	_gauge_root.add_child(_gauge_label)
	var back := ColorRect.new()
	back.color = Color(0.06, 0.09, 0.16, 0.75)
	back.size = Vector2(600, 16)
	back.position = Vector2(-300, 0)
	_gauge_root.add_child(back)
	_gauge_fill = ColorRect.new()
	_gauge_fill.color = STAR_YELLOW
	_gauge_fill.size = Vector2(0, 16)
	_gauge_fill.position = Vector2(-300, 0)
	_gauge_root.add_child(_gauge_fill)


static func _star_points(outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(24):
		var r := outer if i % 2 == 0 else inner
		var a := -PI / 2.0 + TAU * float(i) / 24.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


func _layout() -> void:
	var s := size if size.x > 0.0 and size.y > 0.0 else DESIGN
	_scale = s.y / DESIGN.y
	_design_size = Vector2(s.x / _scale, DESIGN.y)
	_root.scale = Vector2(_scale, _scale)
	_root.size = _design_size
	_panel.size = _design_size
	_seam.size = _design_size
	_flash.size = _design_size
	_panel_material.set_shader_parameter("rect_size", _design_size)
	_seam_material.set_shader_parameter("rect_size", _design_size)
	var w := _design_size.x
	var char_size := Vector2(720, 800)
	_chars[0].size = char_size
	_chars[0].pivot_offset = Vector2(char_size.x * 0.5, char_size.y)
	_chars[1].size = char_size
	_chars[1].pivot_offset = Vector2(char_size.x * 0.5, char_size.y)
	_chars[0].position = Vector2(w * 0.25 - char_size.x * 0.5, 905 - char_size.y)
	_chars[1].position = Vector2(w * 0.75 - char_size.x * 0.5, 905 - char_size.y)
	_vs_root.position = Vector2(w * VS_CENTER.x, DESIGN.y * VS_CENTER.y)
	_rules.position = Vector2(w * 0.5 - _rules.size.x * 0.5, DESIGN.y * VS_CENTER.y + 182)
	_bands[0].position = Vector2(w * 0.25 - NAME_BAND.x * 0.5, 900)
	_bands[1].position = Vector2(w * 0.75 - NAME_BAND.x * 0.5, 900)
	_gauge_root.position = Vector2(w * 0.5, 1030)


func _apply_seam_points() -> void:
	var pts: Array = OnlineStagingTimeline.SEAM_POINTS
	for i in range(pts.size()):
		_panel_material.set_shader_parameter("seam_%d" % i, pts[i])
		_seam_material.set_shader_parameter("seam_%d" % i, pts[i])


## 稲妻の点（画面の割合）と左右の色。中央の線が開く遷移（SceneTransition.hold_versus_split）にも渡す。
func seam_points() -> Array:
	return OnlineStagingTimeline.SEAM_POINTS


func side_colors() -> Array:
	return _colors


func play(info: Dictionary) -> void:
	var my_slot := int(info.get("my_slot", 1))
	_colors = [OnlineHeliportStage.slot_color(my_slot), OnlineHeliportStage.slot_color(3 - my_slot)]
	_panel_material.set_shader_parameter("left_color", _colors[0])
	_panel_material.set_shader_parameter("right_color", _colors[1])
	_seam_material.set_shader_parameter("left_color", (_colors[0] as Color).lightened(0.15))
	_seam_material.set_shader_parameter("right_color", (_colors[1] as Color).lightened(0.15))
	var me := str(info.get("me", ""))
	var them := str(info.get("them", ""))
	_set_name(0, me, "じぶん")
	_set_name(1, them, "あいて")
	_rules.text = str(info.get("rules", ""))
	if _actor_key(info) != _primed_key:
		_prepare_actors(info)
	_primed_key = ""
	time = 0.0
	_sting_sent = false
	_progress = 0.0
	_shown_progress = 0.0
	_waiting = false
	_ready_look = false
	playing = true
	visible = true
	# パネル・稲妻・白い光・VS の着地・名前の帯・札・ルールまでの時刻に合わせた 1 本の音
	AudioManager.play_sfx(&"versus_cutin_in")
	_layout()
	_update(0.0)


## カットインのキャラ絵（左右の SubViewport）を先に描いておく。play() の最初のフレームで描くと、
## カットインの入りのフレームが重くなる（カクつく）ので、合流の始まりなど前もって呼ぶ。info は play() と同じ。
func prime(info: Dictionary) -> void:
	_prepare_actors(info)
	_primed_key = _actor_key(info)


func _prepare_actors(info: Dictionary) -> void:
	if actors == null:
		return
	var my_skin: Variant = info.get("my_skin", {})
	var their_skin: Variant = info.get("their_skin", {})
	actors.prepare(int(info.get("my_slot", 1)), int(info.get("my_hat", 0)), int(info.get("their_hat", 0)),
		OnlineStagingTimeline.cutin_pose_index(str(info.get("me", ""))),
		OnlineStagingTimeline.cutin_pose_index(str(info.get("them", ""))),
		my_skin if my_skin is Dictionary else {}, their_skin if their_skin is Dictionary else {})
	_chars[0].texture = actors.left_texture()
	_chars[1].texture = actors.right_texture()


static func _actor_key(info: Dictionary) -> String:
	return var_to_str([info.get("my_slot", 1), info.get("my_hat", 0), info.get("their_hat", 0),
		info.get("me", ""), info.get("them", ""), info.get("my_skin", {}), info.get("their_skin", {})])


func _set_name(i: int, text: String, tag: String) -> void:
	_band_names[i].text = text
	_band_names[i].add_theme_font_size_override("font_size", 46 if text.length() <= 9 else 32)
	_band_tags[i].text = tag
	var colour: Color = _colors[i]
	var pill_box := (_band_tags[i].get_parent() as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	if pill_box != null:
		pill_box.bg_color = colour.darkened(0.1)
	var box := (_bands[i] as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	if box != null:
		box.border_color = colour


## ゲーム画面へ切り替える直前に呼ぶ：ゲージを満たして「じゅんび OK！」を出す。次に描いた絵が覆いの静止画になる。
func show_ready() -> void:
	_ready_look = true
	_progress = 1.0
	_shown_progress = 1.0
	_update(0.0)


## SWAP：この層を覆い（SceneTransition.hold_versus_split の live）へ渡す前に呼ぶ。キャラ絵は左右の SubViewport に
## 1 回だけ描いたものなので画像に写し、SubViewport（3D の人形）はこの画面と一緒に捨てる。渡したあとも動き続ける。
func detach_actors() -> void:
	if actors == null:
		return
	for tex_rect: TextureRect in _chars:
		var image := tex_rect.texture.get_image() if tex_rect.texture != null else null
		if image == null or image.is_empty():
			# 写せない（画面のないテスト）：SubViewport を残してそのまま使う
			return
		tex_rect.texture = ImageTexture.create_from_image(image)
	actors.queue_free()
	actors = null


func hide_now() -> void:
	playing = false
	visible = false


func set_progress(p: float, waiting: bool) -> void:
	_progress = clampf(p, 0.0, 1.0)
	_waiting = waiting


## 今の画面の名前の読み（テスト用）。
func names() -> Array[String]:
	return [_band_names[0].text, _band_names[1].text]


func _process(delta: float) -> void:
	if not playing:
		return
	time += delta
	if not _sting_sent and time >= OnlineStagingTimeline.STING_AT:
		_sting_sent = true
		AudioManager.play_sting(&"versus")
	_update(delta)


func _update(delta: float) -> void:
	var C: Dictionary = OnlineStagingTimeline.CUTIN
	var t := time
	_panel_material.set_shader_parameter("time", t)
	_seam_material.set_shader_parameter("time", t)
	# 周辺の暗がりと集中線
	_panel_material.set_shader_parameter("vignette", clampf(t / float(C.vignette_end), 0.0, 1.0))
	# パネル：左から・右から入る（行きすぎて戻る 1.2）
	var pu := clampf(t / float(C.panels_end), 0.0, 1.0)
	var slide := 1.2 * (1.0 - _ease_out_back(pu, float(C.panels_overshoot)))
	_panel_material.set_shader_parameter("slide_left", -slide)
	_panel_material.set_shader_parameter("slide_right", slide)
	# 稲妻：上から下へ描く。白い光は 1 回だけ（45%、0.06 秒）
	_seam_material.set_shader_parameter("draw", clampf((t - float(C.bolt_start)) / (float(C.bolt_end) - float(C.bolt_start)), 0.0, 1.0))
	_seam_material.set_shader_parameter("sparks", clampf((t - 0.9) / 0.3, 0.0, 1.0))
	var flash_t := t - float(C.bolt_end)
	_flash.color.a = float(C.flash_alpha) if flash_t >= 0.0 and flash_t < float(C.flash_seconds) else 0.0
	# キャラ：縮尺 0.85 → 1.05 → 1.0。読み込みのあいだは息をする（縦 ±1.2%、2.2 秒）
	var cu := clampf((t - float(C.chars_start)) / (float(C.chars_end) - float(C.chars_start)), 0.0, 1.0)
	var pop := lerpf(0.85, 1.05, smoothstep(0.0, 0.6, cu)) if cu < 0.6 else lerpf(1.05, 1.0, smoothstep(0.6, 1.0, cu))
	var breathe := sin(TAU * maxf(t - 0.9, 0.0) / 2.2) * 0.012
	for i in range(2):
		_chars[i].modulate.a = smoothstep(0.0, 0.25, cu)
		_chars[i].scale = Vector2(pop, pop * (1.0 + breathe * (1.0 if i == 0 else -1.0)))
	# VS：上から落ちる（縮尺 2.2 → 0.92 → 1.0、回転 -12° → 0°）。星は毎秒 10° 回る
	var vu := clampf((t - float(C.vs_start)) / (float(C.vs_end) - float(C.vs_start)), 0.0, 1.0)
	var vs_scale := lerpf(2.2, 0.92, smoothstep(0.0, 0.7, vu)) if vu < 0.7 else lerpf(0.92, 1.0, smoothstep(0.7, 1.0, vu))
	var pulse := 1.0 + sin(TAU * maxf(t - 0.9, 0.0) / 1.1) * 0.02
	_vs_root.visible = t >= float(C.vs_start)
	_vs_root.scale = Vector2.ONE * vs_scale * pulse
	_vs_root.rotation = deg_to_rad(-12.0) * (1.0 - smoothstep(0.0, 0.8, vu))
	_vs_root.modulate.a = smoothstep(0.0, 0.2, vu)
	_star.rotation = deg_to_rad(10.0) * t
	_star_rim.rotation = _star.rotation
	# 2D の層を ±6 px で 0.18 秒揺らす（VS が着いたとき）
	var shake_t := t - float(C.vs_start) - (float(C.vs_end) - float(C.vs_start)) * 0.7
	if shake_t >= 0.0 and shake_t < float(C.shake_seconds):
		var k := 1.0 - shake_t / float(C.shake_seconds)
		_root.position = Vector2(sin(shake_t * 97.0), cos(shake_t * 83.0)) * float(C.shake_px) * k * _scale
	else:
		_root.position = Vector2.ZERO
	# 名前の帯：下から上がる（+40 px → 0、不透明度 0 → 1）
	var nu := clampf((t - float(C.names_start)) / (float(C.names_end) - float(C.names_start)), 0.0, 1.0)
	for i in range(2):
		_bands[i].modulate.a = smoothstep(0.0, 1.0, nu)
		_bands[i].position.y = 900.0 + 40.0 * (1.0 - _ease_out_cubic(nu))
	# ルールの行
	_rules.modulate.a = smoothstep(0.0, 1.0, (t - float(C.rules_start)) / (float(C.rules_end) - float(C.rules_start)))
	# ゲージ：CUTIN_IN のあと 0.2 秒で出す
	var hold_t := t - 0.9
	_gauge_root.modulate.a = clampf(hold_t / float(C.gauge_in), 0.0, 1.0)
	_shown_progress = move_toward(_shown_progress, _progress, delta * 1.5)
	_gauge_fill.size.x = 600.0 * _shown_progress
	if _ready_look:
		_gauge_label.text = "じゅんび OK！"
	elif _waiting:
		_gauge_label.text = "あいての つうしんを まっています…"
	else:
		var dots := int(fmod(maxf(hold_t, 0.0) * 2.5, 4.0))
		_gauge_label.text = "じゅんび ちゅう" + "．".repeat(dots)


static func _ease_out_back(t: float, overshoot: float) -> float:
	var c1 := overshoot
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


static func _ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

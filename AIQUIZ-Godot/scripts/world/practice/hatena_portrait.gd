class_name HatenaPortrait
extends Control

## ハテナの小窓（docs/new_tutorial/phase5_design.md 4.3、台本②の 1.2）。ポーズ画面・リザルトのカードの上では、
## ステージの 3D のハテナは暗い幕の下になって見えないので、雲に乗ったハテナを小さな 3D の窓で出す。
## 自分専用の SubViewport（own_world_3d・背景は透明）に、カメラ・光・HatenaGuide（客席のハテナの体と雲。ステージの
## ハテナと同じ部品）を置き、その絵を TextureRect で出す。ポーズ中も動く（PROCESS_MODE_ALWAYS）。
## マウスは受けない（mouse_filter = IGNORE。小窓が重なっても下のボタンを押せる）。
## 画面のコーチ（PracticeCoach。layer 106 の CanvasLayer）が子にして使う。親は CanvasLayer か、画面いっぱいの Control にする
## （position を画面の座標として扱う）。
##
##   setup(quality) / slide_in(corner, seconds) -> Signal / slide_out(seconds) -> Signal / move_to(pos, seconds) -> Signal
##   show_inline(min_size)（コンテナの中にそのまま出す。初回の案内）
##   play(action) / set_dancing(on) / bubble_anchor() -> Vector2 / is_shown() / home_position(corner) / guide()
## 大きさは画面の高さの約 1/4（HEIGHT_RATIO。画面の大きさが変わると合わせる。auto_size = false なら size をそのまま使う）。
## 置き場所は slide_in の角から MARGIN だけ内側。光らせる部品にかかるときは、コーチが position を直接変えるか move_to で動かしてよい。

## すべり込んだ（slide_in の返り値の signal と同じ時）・出ていって見えなくなった（slide_out と同じ時）
signal slid_in
signal slid_out

const WallMaterials = preload("res://scripts/world/wall_materials.gd")

## 小窓の高さ（画面の高さに対して）と、幅 / 高さ、画面の角からの内側のすきま（画面の座標）
const HEIGHT_RATIO := 0.25
const ASPECT := 1.12
const MARGIN := Vector2(28.0, 20.0)
const CORNERS: Array[StringName] = [&"bottom_right", &"bottom_left", &"top_right", &"top_left"]
## 小窓の 3D：ハテナの足の裏を y = 0 に置く。雲は小さめ（CLOUD_SIZE。足の裏から −0.62 m まで）、「？」のてっぺんは
## +2.65 m（ふわふわで ±0.06 m、ばんざいで +0.2 m ほど）。その全部が入り、ハテナができるだけ大きく写るカメラ。
const CLOUD_SIZE := 0.75
const CAMERA_FOV := 30.0
const CAMERA_EYE := Vector3(0.0, 1.7, 6.9)
const CAMERA_LOOK := Vector3(0.0, 1.13, 0.0)
## 吹き出しの付け根の高さ（等倍のハテナの空間。「？」のてっぺん 2.04 m の少し上）
const BUBBLE_HEIGHT := 2.12
## 画面の真ん中のほうへ顔を向ける角度（右の角なら画面の左へ）
const FACE_TURN := 0.38
## 光：ステージ（stage_environment.gd）に近い明るさ・色。前の左上からの光と、うしろの右からの青い縁の光
const AMBIENT_COLOR := Color(0.60, 0.68, 0.82)
const AMBIENT_ENERGY := 0.95
const KEY_LIGHT_DIR := Vector3(0.45, -0.62, -0.64)
const KEY_LIGHT_COLOR := Color(1.0, 0.97, 0.92)
const KEY_LIGHT_ENERGY := 1.2
const RIM_LIGHT_DIR := Vector3(-0.55, -0.25, 0.8)
const RIM_LIGHT_COLOR := Color(0.75, 0.86, 1.0)
const RIM_LIGHT_ENERGY := 0.55
## 縁どり：明るい地（カードなど）の上でも、白いハテナと雲がまぎれないように紺の縁を付ける（画面の px）
const OUTLINE_COLOR := Color(0.08, 0.11, 0.27, 0.85)
const OUTLINE_PIXELS := 2.0
## 解像度：画面の拡大に合わせ、この範囲に収める（px）
const MIN_PIXELS := 96
const MAX_PIXELS := 768
## すべるときの体の傾き（rad）と雲のなびき（m）。画面の座標の速さ（px/秒）で割る値
const SLIDE_LEAN := 0.22
const SLIDE_TRAIL := 0.12
const SLIDE_SPEED_FULL := 1400.0
const SLIDE_SFX := &"sd_cloud_whoosh"
const SLIDE_SFX_DB := -8.0

## true なら、画面の大きさに合わせて size を決める（HEIGHT_RATIO・ASPECT）
var auto_size := true

## 縁どりの shader（小窓どうしで共有）
static var _outline_shader: Shader = null

var _built := false
var _viewport: SubViewport = null
var _view: TextureRect = null
var _camera: Camera3D = null
var _hatena: HatenaGuide = null
var _shown := false
var _tween: Tween = null
var _serial := 0
var _last_position := Vector2.ZERO
var _lean := 0.0
## show_inline で出した（すべらない。傾けない）
var _inline := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			var root := get_viewport()
			if root != null and not root.size_changed.is_connected(_fit_to_screen):
				root.size_changed.connect(_fit_to_screen)
			_fit_to_screen()
		NOTIFICATION_EXIT_TREE:
			var root := get_viewport()
			if root != null and root.size_changed.is_connected(_fit_to_screen):
				root.size_changed.disconnect(_fit_to_screen)
		NOTIFICATION_RESIZED:
			_fit_pixels()


func setup(quality: String) -> void:
	if _built:
		return
	_built = true
	var q := GraphicsQuality.normalize(quality)
	_viewport = SubViewport.new()
	_viewport.name = "PortraitViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if q == GraphicsQuality.LOW else Viewport.MSAA_4X
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.size = Vector2i(MIN_PIXELS, MIN_PIXELS)
	add_child(_viewport)
	_build_world()
	_hatena = HatenaGuide.new()
	_hatena.name = "PortraitHatena"
	# 小窓はポーズ中も動く（HatenaGuide はふつうポーズで止まる）
	_hatena.process_mode = Node.PROCESS_MODE_INHERIT
	_hatena.run_while_paused = true
	_viewport.add_child(_hatena)
	_hatena.setup(quality)
	_hatena.place_at(Vector3(0.0, -HatenaGuide.FOOT_Y, 0.0), -FACE_TURN)
	_hatena.set_cloud_size(CLOUD_SIZE)
	_hatena.set_cloud(true)
	_hatena.play(&"wave")
	_view = TextureRect.new()
	_view.name = "PortraitView"
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.texture = _viewport.get_texture()
	_view.material = _outline_material()
	add_child(_view)
	_fit_to_screen()


func _ensure_built() -> void:
	if not _built:
		setup(WallMaterials.current_quality())


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	for light_spec: Array in [[KEY_LIGHT_DIR, KEY_LIGHT_COLOR, KEY_LIGHT_ENERGY], [RIM_LIGHT_DIR, RIM_LIGHT_COLOR, RIM_LIGHT_ENERGY]]:
		var light := DirectionalLight3D.new()
		light.light_color = light_spec[1]
		light.light_energy = light_spec[2]
		light.shadow_enabled = false
		light.transform = Transform3D(Basis.looking_at((light_spec[0] as Vector3).normalized(), Vector3.UP), Vector3.ZERO)
		_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.name = "PortraitCamera"
	_camera.fov = CAMERA_FOV
	_camera.near = 0.1
	_camera.far = 50.0
	_camera.transform = Transform3D(Basis.looking_at(CAMERA_LOOK - CAMERA_EYE, Vector3.UP), CAMERA_EYE)
	_camera.current = true
	_viewport.add_child(_camera)


## 縁どり：まわりの不透明な所から OUTLINE_PIXELS の所に、紺の縁を描く（絵の下に重ねる）。
func _outline_material() -> ShaderMaterial:
	if _outline_shader == null:
		_outline_shader = Shader.new()
		_outline_shader.code = """
shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.08, 0.11, 0.27, 0.85);
uniform float outline_px = 2.0;
varying vec4 tint;
void vertex() {
	// fragment() の COLOR には絵の色も掛かっているので、modulate だけを受け取っておく
	tint = COLOR;
}
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float near_alpha = 0.0;
	for (int i = 0; i < 12; i++) {
		float angle = float(i) * 0.5235988;
		near_alpha = max(near_alpha, texture(TEXTURE, UV + vec2(cos(angle), sin(angle)) * TEXTURE_PIXEL_SIZE * outline_px).a);
	}
	float edge_alpha = outline_color.a * near_alpha * (1.0 - base.a);
	float alpha = base.a + edge_alpha;
	vec3 rgb = (base.rgb * base.a + outline_color.rgb * edge_alpha) / max(alpha, 0.0001);
	COLOR = vec4(rgb, alpha) * tint;
}
"""
	var material := ShaderMaterial.new()
	material.shader = _outline_shader
	material.set_shader_parameter("outline_color", OUTLINE_COLOR)
	material.set_shader_parameter("outline_px", OUTLINE_PIXELS)
	return material


# ---------- 大きさ ----------

## 画面の座標での見えている広さ（CanvasLayer の子なら、Control の position と同じ座標）。
func _canvas_size() -> Vector2:
	if is_inside_tree():
		return get_viewport_rect().size
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 1280),
		ProjectSettings.get_setting("display/window/size/viewport_height", 720))


func _fit_to_screen() -> void:
	if auto_size:
		var height := roundf(_canvas_size().y * HEIGHT_RATIO)
		size = Vector2(roundf(height * ASPECT), height)
	_fit_pixels()


## SubViewport の解像度を、画面に出る実際の大きさ（ウィンドウの拡大込み）に合わせる。
func _fit_pixels() -> void:
	if _viewport == null:
		return
	var scale_to_window := 1.0
	if is_inside_tree():
		var window := get_viewport() as Window
		var shown := get_viewport_rect().size
		if window != null and shown.y > 0.0:
			scale_to_window = float(window.size.y) / shown.y
	var pixels := (size * scale_to_window).round()
	var longest := maxf(pixels.x, pixels.y)
	if longest > MAX_PIXELS:
		pixels *= MAX_PIXELS / longest
	elif longest < MIN_PIXELS and longest > 0.0:
		pixels *= MIN_PIXELS / longest
	_viewport.size = Vector2i(maxi(int(pixels.x), 8), maxi(int(pixels.y), 8))
	if _view != null and _view.material is ShaderMaterial:
		# 縁の太さは画面の px でそろえる（SubViewport の px = 画面の px × 拡大）
		(_view.material as ShaderMaterial).set_shader_parameter("outline_px", OUTLINE_PIXELS * float(_viewport.size.y) / maxf(size.y, 1.0))


## その角に置いたときの position（画面の座標。角から MARGIN だけ内側）。
func home_position(corner: StringName = &"bottom_right") -> Vector2:
	var canvas := _canvas_size()
	match corner:
		&"bottom_left":
			return Vector2(MARGIN.x, canvas.y - size.y - MARGIN.y)
		&"top_right":
			return Vector2(canvas.x - size.x - MARGIN.x, MARGIN.y)
		&"top_left":
			return MARGIN
		_:
			if corner != &"bottom_right":
				push_warning("HatenaPortrait: unknown corner %s" % corner)
			return canvas - size - MARGIN


# ---------- 出す・しまう ----------

## 画面の端から雲に乗って入ってくる（右の角なら右の端から、左の角なら左の端から）。corner は CORNERS の名前か、
## 置きたい position（Vector2）。もう出ていれば、いまの所からそこへすべる。着いた時刻に返り値の signal が来る（ポーズ中も来る）。
func slide_in(corner: Variant = &"bottom_right", seconds := 0.4) -> Signal:
	_ensure_built()
	_fit_to_screen()
	var target: Vector2 = corner if corner is Vector2 else home_position(StringName(corner))
	var canvas := _canvas_size()
	var from_right := target.x + size.x * 0.5 >= canvas.x * 0.5
	if not _shown:
		position = Vector2(canvas.x + 8.0 if from_right else -size.x - 8.0, target.y)
		_last_position = position
	_shown = true
	visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# 画面の真ん中のほうを向く
	_hatena.rotation.y = -FACE_TURN if from_right else FACE_TURN
	_play_sfx(SLIDE_SFX, SLIDE_SFX_DB)
	_tween_to(target, seconds, Tween.TRANS_BACK, Tween.EASE_OUT)
	var timer := _timer(seconds)
	timer.timeout.connect(_on_slid_in.bind(_serial))
	return timer.timeout


## 近いほうの画面の端へ雲で出ていき、見えなくなる。出ていった時刻に返り値の signal が来る（ポーズ中も来る）。
func slide_out(seconds := 0.3) -> Signal:
	_ensure_built()
	if not _shown:
		return _timer(0.0).timeout
	var canvas := _canvas_size()
	var to_right := position.x + size.x * 0.5 >= canvas.x * 0.5
	var target := Vector2(canvas.x + 8.0 if to_right else -size.x - 8.0, position.y)
	_play_sfx(SLIDE_SFX, SLIDE_SFX_DB - 2.0)
	_tween_to(target, seconds, Tween.TRANS_BACK, Tween.EASE_IN)
	var timer := _timer(seconds)
	timer.timeout.connect(_on_slid_out.bind(_serial))
	return timer.timeout


## 出ているまま、pos（position）へすべる（光らせる部品をよけるときなど）。着いた時刻に返り値の signal が来る。
func move_to(pos: Vector2, seconds := 0.35) -> Signal:
	_ensure_built()
	if not _shown:
		position = pos
		return _timer(0.0).timeout
	_tween_to(pos, seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	return _timer(seconds).timeout


## すべらずに、親のコンテナが決める所にそのまま出す（初回の案内のパネルの中など）。大きさは min_size（auto_size はやめる）。
## 顔は正面を向き、すべる傾きは付けない。
func show_inline(min_size: Vector2) -> void:
	auto_size = false
	_inline = true
	custom_minimum_size = min_size
	size = min_size
	_ensure_built()
	_shown = true
	visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_hatena.rotation.y = 0.0
	_fit_pixels()


func is_shown() -> bool:
	return _shown


func _tween_to(target: Vector2, seconds: float, trans: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	_serial += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 小窓は PROCESS_MODE_ALWAYS なので、この Tween もポーズ中に進む
	_tween = create_tween()
	_tween.tween_property(self, "position", target, maxf(seconds, 0.01)).set_trans(trans).set_ease(ease_type)


func _on_slid_in(serial: int) -> void:
	if serial == _serial:
		slid_in.emit()


func _on_slid_out(serial: int) -> void:
	if serial != _serial:
		return
	_shown = false
	visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	slid_out.emit()


func _timer(seconds: float) -> SceneTreeTimer:
	# ポーズ中も時間どおりに来る（process_always = true）
	return (Engine.get_main_loop() as SceneTree).create_timer(seconds, true)


# ---------- ハテナ ----------

## HatenaGuide と同じ名前の動き（&"wave"・&"point"・&"cheer"・&"clap"・&"dance"・&"proud"・&"tilt" など）。
func play(action: StringName) -> void:
	_ensure_built()
	_hatena.play(action)


func set_dancing(on: bool) -> void:
	_ensure_built()
	_hatena.set_dancing(on)


## 小窓の中のハテナ（ほかの動き：spin・tremble・offer_hand など）。
func guide() -> HatenaGuide:
	_ensure_built()
	return _hatena


## 頭の上（吹き出しの付け根）の画面の位置。この小窓と同じ層の Control の global_position と同じ座標。
## 出ていない（slide_out のあと・slide_in の前）ときは Vector2.INF。
func bubble_anchor() -> Vector2:
	if not _built or not _shown or not is_inside_tree() or _camera == null:
		return Vector2.INF
	var head := _hatena.bubble_point(BUBBLE_HEIGHT)
	if _camera.is_position_behind(head):
		return Vector2.INF
	var uv := _camera.unproject_position(head) / Vector2(_viewport.size)
	return get_global_transform_with_canvas() * (uv * size)


# ---------- 毎フレーム ----------

func _process(delta: float) -> void:
	if not _built or not visible or delta <= 0.0 or _inline:
		return
	# すべる速さで体を傾け、雲をうしろへなびかせる（左へ動くと、体のてっぺんは右へ残る）
	var velocity := (position - _last_position) / delta
	_last_position = position
	var amount := clampf(velocity.x / SLIDE_SPEED_FULL, -1.0, 1.0)
	_lean = lerpf(_lean, amount * SLIDE_LEAN, minf(1.0, delta * 12.0))
	_hatena.rotation.z = _lean
	_hatena.set_cloud_trail(_hatena.basis.inverse() * Vector3(-amount * SLIDE_TRAIL, 0.0, 0.0))


func _play_sfx(cue: StringName, volume_db: float) -> void:
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(cue, volume_db)

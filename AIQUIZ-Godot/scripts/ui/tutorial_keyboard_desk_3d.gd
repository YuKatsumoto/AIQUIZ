extends Control

## ローカル2Pのキーボード説明の3D版。プレイヤーの席から机を見下ろす構図で、
## モニター・キーボード・P1の左手（オレンジ）とP2の右手（青）を見せる。
## どのキーが誰のものか・いま押されているかは TutorialKeyboard（tutorial_keyboard.gd）が持ち、
## ここは見た目だけを受け持つ。説明画面（tutorial_keyboard_intro.gd）が毎フレーム advance() を呼ぶ。
##
## 長さの単位はキー1個分の間隔（約19mm）を 1.0 とする。+Y が上、-Z がモニターの方向。

## enter_monitor() で始めた、モニターへ寄る演出が終わった（画面がモニターの映像だけになった）。
signal monitor_entered

const KeycapScript = preload("res://scripts/world/keycap_3d.gd")
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const HAND_SHADER := preload("res://shaders/tutorial_desk_hand.gdshader")

## 構図は16:9の画面で決める。ほかの比率では、この16:9の枠が丸ごと入るように画角を合わせる
## （説明画面の 1280×720 の板と同じ収め方なので、左右のカードとキーボードの位置関係が変わらない）。
const DESIGN_ASPECT := 16.0 / 9.0
const CAMERA_POSITION := Vector3(0.0, 20.5, 13.0)
const CAMERA_TARGET := Vector3(0.0, 0.5, -3.0)
const CAMERA_FOV := 50.0
## チュートリアルを始めるとき、席からモニターの画面いっぱいまでカメラを寄せる時間。
const ENTER_SECONDS := 1.4
## 描画の解像度の上限（メニューの背景の LiveViewport と同じ4K相当）。
const MAX_RENDER_WIDTH := 3840.0

## 2Dのキー配列表（tutorial_keyboard.gd）からの換算。キー幅28＋すき間3が1キー分。
const LAYOUT_PITCH := 31.0
const LAYOUT_LEFT := 14.0
const LAYOUT_RIGHT := 612.0
const LAYOUT_ROW_TOP := 44.0
const LAYOUT_ROW_STEP := 29.0
const KEY_ROWS := 5

const CASE_MARGIN := 0.55
const CASE_HEIGHT := 0.9
const DESK_Y := -CASE_HEIGHT
## モニターは実物より低く近くに置き、画面の下のほうが構図に入るようにする。
const MONITOR_Z := -16.0
const SCREEN_SIZE := Vector2(23.0, 12.9375)
const SCREEN_BOTTOM := 2.5
## 画面の外の左奥にあるデスクライトの位置と、照らす所（キーボードの少し左）。
const LAMP_POSITION := Vector3(-15.0, 13.0, -7.0)
const LAMP_TARGET := Vector3(-1.0, 0.0, 1.0)
## ハテナの置物（客席のハテナ。高さ約2mを約10cmの置物にする）。机の右奥で、キーボードのほうへ向ける。
## 客席のハテナは本編の自動読み込みに頼るスクリプトとつながっているので、使うときに読み込む
## （--script で流すテストでも、この机のスクリプトを読み込めるように）。
const STAND_MASCOT_PATH := "res://scripts/world/crowd/stand_mascot.gd"
const MASCOT_POSITION := Vector3(12.5, DESK_Y, -12.0)
const MASCOT_SCALE := 2.1
const MASCOT_YAW := -0.8
const MASCOT_POSE_SECONDS := 0.6

const NAVY := Color("0c1728")
const P1_KEY := Color("ffa440")
const P2_KEY := Color("51d8ec")
## 本編のキャラの手足の色（player_controller.gd の P1_LIMB・P2_LIMB）。
const P1_LIMB := Color(0.85, 0.48, 0.18)
const P2_LIMB := Color(0.15, 0.55, 0.80)

## 手は本編のキャラの手（player_controller.gd の _create_detailed_hand）の形・比率をもとに作る。
## 指の間隔 0.044 がキー1個分より少し狭くなる倍率（手前にある手が大きく見えすぎないように）。
## 指は本編より細くし、指のすき間から隣のキーが見えるようにする。
const HAND_SCALE := 0.85 / 0.044
const FINGER_NAMES := ["index", "middle", "ring", "pinky"]
const FINGER_LENGTHS := [0.08, 0.09, 0.085, 0.065]
const FINGER_SIZE := Vector2(0.034, 0.042)
## 指先を置く所。キーの中央から手前（+Z）へ寄せ、指が刻印にかぶらないようにする。
const TOUCH_FORWARD := 0.3
const TOUCH_HEIGHT := 0.35
## 手の不透明度（輪郭以外）。手の下に隠れたキーの色と刻印が透けて見えるようにする。
const HAND_ALPHA := 0.5
## 手の位置を決める指（置き方の anchor）の付け根を、その指のキーからどれだけ上・手前に置くか（手の向きに沿って）。
const KNUCKLE_LIFT := 1.0
const KNUCKLE_BACK := 2.4
## 親指が anchor のときの付け根の位置（キーから手の外側・上・手前。手の向きに沿って）。
const THUMB_ANCHOR := Vector3(2.4, 0.3, 2.6)
## 親指の先は付け根から手の内側へこれだけ寄せた所に置く（横長の Space で、付け根の真上に縮こまらないように）。
const THUMB_SPREAD := 2.6
## 手のひらの傾き（負で指の付け根側が上がる）。手首は低く、指をキーへ曲げ下ろす。
const HAND_TILT := -0.30
## 指の付け根をどこまで反らせるか（手のひら側への曲げ角の下限）。指は手の傾きを打ち消すところまでにして
## 手の甲より上へ盛り上がらないようにし、親指は少し持ち上げてから曲げ下ろせるようにする。
const FINGER_MIN_ROOT := -HAND_TILT
const THUMB_MIN_ROOT := -0.4
## 前腕の下がり角。手首で折り、机の少し上をほぼ水平に手前へ伸ばす。
const FOREARM_DROP := 0.06
## キーを受け持たない指の曲げ方（手の座標。-Y が指先の向き、+Z が手のひら側）。
const RELAXED_CURL := Vector3(0.0, -1.9, 1.4)
## 手の置き方を変える速さと、指を伸ばす速さ（大きいほど早く追いつく）。
const HAND_SPEED := 12.0
const FINGER_SPEED := 24.0
## 手の置き方。rest は指を置くキー、keys は押せるキーとその指、anchor は手の位置を決める指。
## 定位置（home）より前に並べた置き方は、trigger のキーを押している間だけ手をそこへ動かす。
## park がある置き方は、指をキーに置かず手首をその位置（画面の外）へ下げておく。
## P1は左手で A S D と Space（W は中指を奥へ伸ばす）、P2は右手で ← ↓ →（↑ は中指）。
## P2の右Ctrl は矢印から離れているので、押す間だけ親指が届く所まで手を寄せる（指は矢印に残す）。
## P2のエモート（8 9 0）は左手で押す。ふだんは画面の下の外に下げておき、押す間だけ出してくる。
const P1_POSES := {
	"numbers": {"anchor": "middle", "trigger": ["1", "2", "3"], "rest": {"ring": "1", "middle": "2", "index": "3"},
		"keys": {"1": "ring", "2": "middle", "3": "index"}},
	"home": {"anchor": "middle", "rest": {"pinky": "ShiftL", "ring": "A", "middle": "S", "index": "D", "thumb": "Space"},
		"keys": {"A": "ring", "S": "middle", "D": "index", "W": "middle", "Space": "thumb"}},
}
const P2_POSES := {
	"jump": {"anchor": "thumb", "trigger": ["CtrlR"], "rest": {"thumb": "CtrlR", "index": "←", "middle": "↓", "ring": "→"},
		"keys": {"CtrlR": "thumb", "←": "index", "↓": "middle", "→": "ring", "↑": "middle"}},
	"home": {"anchor": "middle", "rest": {"index": "←", "middle": "↓", "ring": "→"},
		"keys": {"←": "index", "↓": "middle", "→": "ring", "↑": "middle"}},
}
const P2_LEFT_POSES := {
	"numbers": {"anchor": "middle", "trigger": ["8", "9", "0"], "rest": {"ring": "8", "middle": "9", "index": "0"},
		"keys": {"8": "ring", "9": "middle", "0": "index"}},
	"home": {"park": Vector3(4.0, 0.6, 18.0), "rest": {}, "keys": {}},
}
## 上から見た手の向き（正で左回り）。両手とも内側へ向け、腕は画面の下の左右の角から入れる。
## P2の左手はP2の席（右手前）から、キーボードの真ん中の数字の列へ伸ばす。
const P1_YAW := -0.35
const P2_YAW := 0.35
const P2_LEFT_YAW := 0.3

var _container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _scene: Node3D
var _source: TutorialKeyboard = null
var _keys: Dictionary = {}
## key_id -> {"center": Vector3, "half_width": float}
var _key_boxes: Dictionary = {}
var _case_half := Vector3.ZERO
var _hands: Array[Dictionary] = []
var _screen_material: StandardMaterial3D
var _placeholder_screen: Texture2D
## "live"（メニューの背景の映像）か "placeholder"（仮の絵）。
var _monitor_source := "placeholder"
var _mascot: Node3D = null
## モニターへ寄る演出の経過秒（負なら演出していない）と、始めたときのカメラ。
var _enter_time := -1.0
var _seat_xform := Transform3D.IDENTITY


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container = SubViewportContainer.new()
	_container.name = "DeskView"
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.name = "DeskViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_container.add_child(_viewport)
	_scene = Node3D.new()
	_scene.name = "Desk"
	_viewport.add_child(_scene)
	_build_lighting()
	_build_room()
	_build_monitor()
	_build_keyboard_case()
	_camera = Camera3D.new()
	_camera.name = "SeatCamera"
	_camera.fov = CAMERA_FOV
	_camera.near = 0.5
	_camera.far = 400.0
	_camera.transform = Transform3D(Basis.looking_at(CAMERA_TARGET - CAMERA_POSITION), CAMERA_POSITION)
	_camera.current = true
	_scene.add_child(_camera)


## 状態の元（2Dのキーボード）をつなぐ。キーと手は初回に同じ配列表から作り、色（誰のキーか）は毎回合わせ直す。
func bind_keyboard(source: TutorialKeyboard) -> void:
	_source = source
	reset_camera()
	if _keys.is_empty():
		_build_keys(source.get_key_layout())
		_hands = [
			_build_hand("P1", P1_LIMB, true, P1_POSES, P1_YAW),
			_build_hand("P2", P2_LIMB, false, P2_POSES, P2_YAW),
			_build_hand("P2_left", P2_LIMB, true, P2_LEFT_POSES, P2_LEFT_YAW),
		]
		_build_mascot(_quality())
	for key_id: String in _keys:
		var key: Keycap3D = _keys[key_id]
		var player := source.get_key_player(key_id)
		key.accent = P2_KEY if player == 2 else P1_KEY
		key.set_look(Keycap3D.Look.TARGET if player > 0 else Keycap3D.Look.IDLE)
	for hand: Dictionary in _hands:
		_update_hand(hand, 0.0, true, true)


## 実際の入力に合わせてキーを沈め、手と指を動かす。自動で押して見せる演出は持たない。
## 2Dのキーボードが「動きを減らす」になっているときは、手は定位置のまま動かさない。
func advance(delta: float) -> void:
	if _source == null:
		return
	for key_id: String in _keys:
		var key: Keycap3D = _keys[key_id]
		key.set_pressed(_source.is_key_down(key_id))
		key.advance(delta)
	var still := bool(_source.get_action_state().get("reduced_motion", false))
	for hand: Dictionary in _hands:
		_update_hand(hand, delta, still, false)
	if _enter_time >= 0.0 and _enter_time < ENTER_SECONDS:
		_enter_time = minf(_enter_time + delta, ENTER_SECONDS)
		_camera.transform = _seat_xform.interpolate_with(_monitor_xform(), smoothstep(0.0, 1.0, _enter_time / ENTER_SECONDS))
		if _enter_time >= ENTER_SECONDS:
			monitor_entered.emit()


## チュートリアルを始めるときの演出。カメラをモニターの正面へ回しながら寄せ、画面いっぱいにする。
## 終わると monitor_entered を出す。
func enter_monitor() -> void:
	_seat_xform = _camera.transform
	_enter_time = 0.0


func is_entering() -> bool:
	return _enter_time >= 0.0


## いま描いている画面の静止画。モニターへ寄り終えた画面を、本編へ移る間の覆いにする。描けていなければ null。
func capture_frame() -> Texture2D:
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## 席から見る位置へ戻す（説明画面を開き直したとき）。
func reset_camera() -> void:
	_enter_time = -1.0
	_camera.transform = Transform3D(Basis.looking_at(CAMERA_TARGET - CAMERA_POSITION), CAMERA_POSITION)


## モニターの画面が画面いっぱい（枠が見えない）になる、画面の真正面のカメラ。
func _monitor_xform() -> Transform3D:
	var aspect := float(_viewport.size.x) / maxf(_viewport.size.y, 1.0)
	var vertical := deg_to_rad(_camera.fov)
	var horizontal := 2.0 * atan(tan(vertical * 0.5) * aspect)
	if _camera.keep_aspect == Camera3D.KEEP_WIDTH:
		horizontal = deg_to_rad(_camera.fov)
		vertical = 2.0 * atan(tan(horizontal * 0.5) / aspect)
	# 縦と横のどちらも画面が枠からはみ出す距離（少し近めにして、枠の縁が映り込まないように）。
	var distance := minf(SCREEN_SIZE.y * 0.5 / tan(vertical * 0.5), SCREEN_SIZE.x * 0.5 / tan(horizontal * 0.5)) * 0.97
	var center := Vector3(0.0, DESK_Y + SCREEN_BOTTOM + SCREEN_SIZE.y * 0.5, MONITOR_Z + 0.02)
	return Transform3D(Basis.IDENTITY, center + Vector3(0.0, 0.0, distance))


## モニターに映す映像（メインメニューの背景の LiveViewport）。null なら空と海の色の仮の絵に戻す。
func set_monitor_texture(texture: Texture2D) -> void:
	_screen_material.albedo_texture = texture if texture != null else _placeholder_screen
	_monitor_source = "live" if texture != null else "placeholder"
	_fit_monitor_picture()


## 画面の大きさに合わせて、描画の解像度とカメラの画角を合わせる。説明画面の _layout() から毎回呼ぶ。
func fit_to_view(logical: Vector2) -> void:
	if logical.x <= 0.0 or logical.y <= 0.0:
		return
	# canvas_items stretch の拡大率。物理解像度 = 論理解像度 × 拡大率
	var target := logical * get_window().get_final_transform().get_scale()
	if target.x > MAX_RENDER_WIDTH:
		target *= MAX_RENDER_WIDTH / target.x
	target = target.round().max(Vector2(64.0, 36.0))
	if _container.size != target:
		_container.size = target
		GraphicsQualityRules.apply_text_viewport(_viewport, _quality())
	_container.scale = logical / target
	_fit_monitor_picture()
	if logical.x / logical.y >= DESIGN_ASPECT:
		_camera.keep_aspect = Camera3D.KEEP_HEIGHT
		_camera.fov = CAMERA_FOV
	else:
		# 16:9 より縦長の画面では、16:9 のときの横の画角を保つ（上下に余白が増える）。
		_camera.keep_aspect = Camera3D.KEEP_WIDTH
		_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(CAMERA_FOV) * 0.5) * DESIGN_ASPECT))


## キーボード（ケースとキー）が画面に映る範囲。この Control の座標。
func get_keyboard_screen_rect() -> Rect2:
	if not _camera.is_inside_tree():
		return Rect2()
	var rect := Rect2()
	for corner: int in range(8):
		var local := Vector3(
			_case_half.x * (1.0 if corner & 1 else -1.0),
			KeycapScript.CAP_HEIGHT if corner & 2 else -CASE_HEIGHT,
			_case_half.z * (1.0 if corner & 4 else -1.0))
		var point := _camera.unproject_position(local) * _container.scale
		rect = Rect2(point, Vector2.ZERO) if corner == 0 else rect.expand(point)
	return rect


func get_evidence() -> Dictionary:
	var hands := {}
	for hand: Dictionary in _hands:
		var root: Node3D = hand["root"]
		var digits := {}
		for digit_name: String in hand["digits"]:
			var digit: Dictionary = hand["digits"][digit_name]
			if str(digit["key"]).is_empty():
				continue
			var target := root.transform * (digit["target"] as Vector3)
			digits[digit_name] = {"key": digit["key"], "tip_error": snappedf(_digit_tip(hand, digit).distance_to(target), 0.001)}
		# 手のひらの真ん中が画面に入っているか（P2の左手はふだん画面の下の外にいる）。
		var palm := root.transform * Vector3(0.0, -0.10 * HAND_SCALE, 0.0)
		hands[hand["label"]] = {"pose": hand["pose"], "pressing": hand["pressing"], "digits": digits,
			"in_view": _camera.is_inside_tree() and _camera.is_position_in_frustum(palm)}
	var sunk: Array[String] = []
	for key_id: String in _keys:
		if (_keys[key_id] as Keycap3D).press_depth() > 0.5:
			sunk.append(key_id)
	return {"keyboard_rect": get_keyboard_screen_rect(), "key_count": _keys.size(), "hands": hands, "sunk_keys": sunk,
		"viewport_size": _viewport.size, "camera_fov": snappedf(_camera.fov, 0.01),
		"keep_aspect": "height" if _camera.keep_aspect == Camera3D.KEEP_HEIGHT else "width",
		"monitor_source": _monitor_source, "monitor_crop": Vector2(_screen_material.uv1_scale.x, _screen_material.uv1_scale.y),
		"mascot": _mascot != null}


# ---------- 部屋・モニター・キーボード ----------

## 夜の部屋。主光は左奥のデスクライト（暖色）。モニターの光（青白）と、壁を照らすモニター裏の間接照明、
## キーの刻印を読みやすくする手前からの弱い補助光を足す。
func _build_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = NAVY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("3f5378")
	environment.ambient_light_energy = 0.5
	# 明るい画面と光ったキーを少しにじませる。
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_hdr_threshold = 0.85
	var world := WorldEnvironment.new()
	world.environment = environment
	_scene.add_child(world)
	# この場面はキー1個分が1単位で光源まで20単位ほど離れるので、距離では暗くせず、届く範囲の端でだけ弱める。
	var lamp := SpotLight3D.new()
	lamp.name = "DeskLamp"
	lamp.light_color = Color("ffd8a6")
	lamp.light_energy = 1.6
	lamp.spot_range = 48.0
	lamp.spot_attenuation = 0.0
	lamp.spot_angle = 40.0
	lamp.spot_angle_attenuation = 0.7
	lamp.shadow_enabled = true
	lamp.transform = Transform3D(Basis.looking_at(LAMP_TARGET - LAMP_POSITION), LAMP_POSITION)
	_scene.add_child(lamp)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color("c9d8ff")
	fill.light_energy = 0.5
	fill.transform = Transform3D(Basis.looking_at(Vector3(0.0, -0.75, -0.65)), Vector3.ZERO)
	_scene.add_child(fill)
	var screen_center := Vector3(0.0, DESK_Y + SCREEN_BOTTOM + SCREEN_SIZE.y * 0.5, MONITOR_Z)
	var screen_light := OmniLight3D.new()
	screen_light.name = "ScreenLight"
	screen_light.light_color = Color("8cc4ff")
	screen_light.light_energy = 0.5
	screen_light.omni_range = 24.0
	screen_light.omni_attenuation = 0.0
	screen_light.position = screen_center + Vector3(0.0, 0.0, 4.0)
	_scene.add_child(screen_light)
	var backlight := OmniLight3D.new()
	backlight.name = "MonitorBacklight"
	backlight.light_color = Color("4d8cff")
	backlight.light_energy = 1.2
	backlight.omni_range = 12.0
	backlight.omni_attenuation = 0.0
	backlight.position = screen_center + Vector3(0.0, 0.0, -2.5)
	_scene.add_child(backlight)


## 机の天板（キーボードのケースの底と同じ高さ）は木目、奥の壁は紺。壁の影は机へ落とさない。
func _build_room() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 60.0)
	var desk := MeshInstance3D.new()
	desk.name = "DeskTop"
	desk.mesh = plane
	desk.material_override = _wood_material()
	desk.position = Vector3(0.0, DESK_Y, -2.0)
	_scene.add_child(desk)
	var wall := _box(_scene, Vector3(200.0, 90.0, 1.0), Vector3(0.0, DESK_Y + 35.0, MONITOR_Z - 10.0), _material(Color("0f1b2f"), 0.95))
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_monitor() -> void:
	var monitor := Node3D.new()
	monitor.name = "Monitor"
	monitor.position = Vector3(0.0, DESK_Y, MONITOR_Z)
	_scene.add_child(monitor)
	var body := _material(Color("0b111b"), 0.45, 0.35)
	var screen_center_y := SCREEN_BOTTOM + SCREEN_SIZE.y * 0.5
	var frame := SCREEN_SIZE * 0.5 + Vector2(0.45, 0.45)
	# 角を丸めた板を立てて前の枠と背面にし、首と台を足す。モニターの影はキーボードへ落とさない。
	var bezel := _slab(monitor, frame.x, frame.y, 0.7, 0.8, 0.12, body)
	bezel.rotation.x = PI * 0.5
	bezel.position = Vector3(0.0, screen_center_y, 0.0)
	var back := _slab(monitor, frame.x - 1.5, frame.y - 1.5, 1.2, 0.9, 0.3, body)
	back.rotation.x = PI * 0.5
	back.position = Vector3(0.0, screen_center_y, -0.8)
	var neck := _box(monitor, Vector3(2.2, SCREEN_BOTTOM + 3.0, 0.9), Vector3(0.0, (SCREEN_BOTTOM + 3.0) * 0.5, -1.9), body)
	var base := _slab(monitor, 5.5, 3.6, 1.6, 0.35, 0.1, body)
	base.position = Vector3(0.0, 0.35, -1.6)
	for part: MeshInstance3D in [bezel, back, neck, base]:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 画面。メニューから映像を受け取るまでは、空と海の色の仮の絵。
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.42, 0.43, 1.0])
	gradient.colors = PackedColorArray([Color("bfe6fa"), Color("8fcbed"), Color("3a8fd0"), Color("235f9c")])
	var picture := GradientTexture2D.new()
	picture.gradient = gradient
	picture.fill_to = Vector2(0.0, 1.0)
	picture.width = 8
	picture.height = 128
	_placeholder_screen = picture
	_screen_material = StandardMaterial3D.new()
	_screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_material.albedo_texture = picture
	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	screen.mesh = quad
	screen.material_override = _screen_material
	screen.position = Vector3(0.0, screen_center_y, 0.02)
	monitor.add_child(screen)


func _build_keyboard_case() -> void:
	var rows_half := (KEY_ROWS - 1) * 0.5 + (KeycapScript.PITCH - KeycapScript.GAP) * 0.5
	_case_half = Vector3((LAYOUT_RIGHT - LAYOUT_LEFT) * 0.5 / LAYOUT_PITCH + CASE_MARGIN, CASE_HEIGHT * 0.5, rows_half + CASE_MARGIN)
	var keyboard_case := _slab(_scene, _case_half.x, _case_half.z, 0.8, CASE_HEIGHT, 0.18, _material(Color("17283f"), 0.4, 0.35))
	keyboard_case.name = "KeyboardCase"


## 机の右奥（モニターの横）の、案内役のハテナの置物。キーボードのほうを指さした姿で止めておく。
func _build_mascot(quality: String) -> void:
	var mascot_script := load(STAND_MASCOT_PATH) as GDScript
	if mascot_script == null or not mascot_script.can_instantiate():
		return
	var mascot: Node3D = mascot_script.new()
	mascot.name = "HatenaFigure"
	if not bool(mascot.call("setup", quality)):
		mascot.free()
		return
	mascot.call("play", &"point", true)
	mascot.call("advance", MASCOT_POSE_SECONDS)
	mascot.scale = Vector3.ONE * MASCOT_SCALE
	mascot.position = MASCOT_POSITION
	mascot.rotation.y = MASCOT_YAW
	_scene.add_child(mascot)
	_mascot = mascot
	# 足もとの丸い影。客席のハテナは影を落とさないので、これで机に立って見えるようにする。
	var blot := Gradient.new()
	blot.colors = PackedColorArray([Color(0.0, 0.0, 0.0, 0.55), Color(0.0, 0.0, 0.0, 0.0)])
	var blot_texture := GradientTexture2D.new()
	blot_texture.gradient = blot
	blot_texture.fill = GradientTexture2D.FILL_RADIAL
	blot_texture.fill_from = Vector2(0.5, 0.5)
	blot_texture.fill_to = Vector2(1.0, 0.5)
	var shadow_material := StandardMaterial3D.new()
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.albedo_texture = blot_texture
	var quad := QuadMesh.new()
	quad.size = Vector2(3.4, 2.6)
	var shadow := MeshInstance3D.new()
	shadow.name = "HatenaShadow"
	shadow.mesh = quad
	shadow.material_override = shadow_material
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.rotation.x = -PI * 0.5
	shadow.position = MASCOT_POSITION + Vector3(0.0, 0.02, 0.0)
	_scene.add_child(shadow)


## 映像の縦横比が画面（16:9）と違うときは、真ん中を切り出して映す（21:9 のウィンドウなど）。
func _fit_monitor_picture() -> void:
	var crop := Vector2.ONE
	var texture := _screen_material.albedo_texture
	if _monitor_source == "live" and texture != null and texture.get_height() > 0:
		var ratio := (float(texture.get_width()) / texture.get_height()) / (SCREEN_SIZE.x / SCREEN_SIZE.y)
		crop = Vector2(1.0 / ratio, 1.0) if ratio > 1.0 else Vector2(1.0, ratio)
	_screen_material.uv1_scale = Vector3(crop.x, crop.y, 1.0)
	_screen_material.uv1_offset = Vector3((1.0 - crop.x) * 0.5, (1.0 - crop.y) * 0.5, 0.0)


## 机の木目。ノイズを横へ引き伸ばして筋にする。
static func _wood_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.015
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	ramp.colors = PackedColorArray([Color("2e2017"), Color("3d2b1f"), Color("4c3627")])
	var grain := NoiseTexture2D.new()
	grain.width = 512
	grain.height = 512
	grain.seamless = true
	grain.noise = noise
	grain.color_ramp = ramp
	var material := StandardMaterial3D.new()
	material.albedo_texture = grain
	material.uv1_scale = Vector3(3.0, 24.0, 1.0)
	material.roughness = 0.6
	return material


## 角を丸めた板（上面が y = 0、底が y = -height。机に置くので底は閉じない）。上の縁は bevel だけ面取りする。
## 輪の作り方はキーキャップ（keycap_3d.gd）と同じ。
static func _slab(parent: Node3D, half_x: float, half_z: float, radius: float, height: float, bevel: float, material: Material) -> MeshInstance3D:
	var rings: Array[PackedVector3Array] = [
		KeycapScript._rounded_ring(half_x, half_z, radius, -height),
		KeycapScript._rounded_ring(half_x, half_z, radius, -bevel),
		KeycapScript._rounded_ring(half_x - bevel, half_z - bevel, radius - bevel, 0.0),
		KeycapScript._rounded_ring(maxf(0.0, half_x - half_z), 0.0, 0.0, 0.0),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	KeycapScript._add_ring_strips(st, rings)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh


## 2Dの配列表と同じ並びでキーを置く。キーボードの中心が x = 0、行は奥（数字の列）から手前へ。
func _build_keys(layout: Array[Dictionary]) -> void:
	var keyboard := Node3D.new()
	keyboard.name = "Keys"
	_scene.add_child(keyboard)
	var center_x := (LAYOUT_LEFT + LAYOUT_RIGHT) * 0.5
	for spec: Dictionary in layout:
		var key_id := str(spec["id"])
		var rect: Rect2 = spec["rect"]
		var units := (rect.size.x + 3.0) / LAYOUT_PITCH
		var row := roundf((rect.position.y - LAYOUT_ROW_TOP) / LAYOUT_ROW_STEP)
		var center := Vector3((rect.get_center().x - center_x) / LAYOUT_PITCH, 0.0, row - (KEY_ROWS - 1) * 0.5)
		var legend := str(spec["label"])
		if legend == "⌫" and not KeycapScript.LEGEND_FONT.has_char(0x232B):
			legend = "Back"
		var key: Keycap3D = KeycapScript.new()
		key.name = "Key%02d" % _keys.size()
		key.show_plate = false
		key.steady_glow = true
		key.position = center
		keyboard.add_child(key)
		key.setup(legend, units, P1_KEY)
		key.set_shown(true, true)
		_keys[key_id] = key
		_key_boxes[key_id] = {"center": center, "half_width": units * 0.5}


# ---------- 手 ----------

func _build_hand(label: String, color: Color, is_left: bool, poses: Dictionary, yaw: float) -> Dictionary:
	var root := Node3D.new()
	root.name = ("Left" if is_left else "Right") + "Hand" + label.get_slice("_", 0)
	_scene.add_child(root)
	var material := ShaderMaterial.new()
	material.shader = HAND_SHADER
	material.set_shader_parameter("albedo", color)
	material.set_shader_parameter("body_alpha", HAND_ALPHA)
	var s := HAND_SCALE
	# 手の座標は本編と同じ：指が -Y、手のひらが +Z、親指は左手なら +X。
	_box(root, Vector3(0.18, 0.20, 0.08) * s, Vector3(0.0, -0.10, 0.0) * s, material)
	# 前腕。手首で手のひらの傾きを打ち消し、肘のほう（+Y）へ画面の手前の外まで伸ばす。
	var forearm := Node3D.new()
	forearm.name = "Forearm"
	forearm.rotation.x = FOREARM_DROP + HAND_TILT
	root.add_child(forearm)
	_box(forearm, Vector3(0.16, 0.70, 0.10) * s, Vector3(0.0, 0.35, 0.0) * s, material)
	var side := 1.0 if is_left else -1.0
	var digits := {}
	for index: int in range(4):
		var base_length: float = FINGER_LENGTHS[index]
		digits[FINGER_NAMES[index]] = _build_digit(root, Vector3(side * (0.066 - index * 0.044), -0.20, 0.0) * s,
			[base_length * 0.8 * s, base_length * 0.7 * s, base_length * 0.5 * s], FINGER_SIZE * s, material, FINGER_MIN_ROOT)
	# 親指は本編より付け根を指の側へ寄せて長くし、P1は Space、P2は右Ctrl まで届くようにする。
	digits["thumb"] = _build_digit(root, Vector3(side * 0.10, -0.14, 0.03) * s,
		[0.10 * s, 0.08 * s], Vector2(0.044, 0.05) * s, material, THUMB_MIN_ROOT)
	return {"label": label, "root": root, "digits": digits, "poses": poses, "yaw": yaw, "is_left": is_left, "side": side,
		"pose": "home", "pressing": {}, "targets": {}}


## 指1本（節ごとに関節のノードを重ねる）。各節は関節から -Y へ伸びる。
func _build_digit(parent: Node3D, base: Vector3, lengths: Array, size: Vector2, material: Material, min_root: float) -> Dictionary:
	var joints: Array[Node3D] = []
	var host := parent
	var offset := base
	for length: float in lengths:
		var joint := Node3D.new()
		joint.position = offset
		host.add_child(joint)
		_box(joint, Vector3(size.x, length, size.y), Vector3(0.0, -length * 0.5, 0.0), material)
		joints.append(joint)
		host = joint
		offset = Vector3(0.0, -length, 0.0)
	return {"joints": joints, "lengths": lengths, "base": base, "min_root": min_root, "target": base, "key": ""}


## 押されているキーから手の置き方と押す指を決め、手と指をそこへ寄せる。snap は途中を飛ばしてすぐ置く。
## 指の目標は手の座標で持つので、手が別の置き方へ滑る間も指は形を保ったまま手といっしょに動く。
func _update_hand(hand: Dictionary, delta: float, still: bool, snap: bool) -> void:
	var poses: Dictionary = hand["poses"]
	var pose_name := "home" if still else _pressed_pose(poses)
	var pose: Dictionary = poses[pose_name]
	var pressing := {}
	if not still:
		for key_id: String in pose["keys"]:
			if _source.is_key_down(key_id):
				pressing[pose["keys"][key_id]] = key_id
	var root: Node3D = hand["root"]
	var goal_xform := _hand_xform(hand, pose)
	root.transform = goal_xform if snap else root.transform.interpolate_with(goal_xform, 1.0 - exp(-delta * HAND_SPEED))
	var to_local := goal_xform.affine_inverse()
	var weight := 1.0 if snap else 1.0 - exp(-delta * FINGER_SPEED)
	var targets: Dictionary = hand["targets"]
	for digit_name: String in hand["digits"]:
		var digit: Dictionary = hand["digits"][digit_name]
		var base: Vector3 = digit["base"]
		var key_id := str(pressing.get(digit_name, (pose["rest"] as Dictionary).get(digit_name, "")))
		# キーを受け持たない指は、軽く曲げて浮かせておく。
		var goal := base + RELAXED_CURL
		if not key_id.is_empty():
			var near_x := (goal_xform * base).x
			if digit_name == "thumb":
				near_x += float(hand["side"]) * THUMB_SPREAD
			var point := _touch_point(key_id, near_x)
			if pressing.has(digit_name):
				# 押している指はキャップといっしょに沈める。
				point.y -= KeycapScript.TRAVEL * (_keys[key_id] as Keycap3D).press_depth()
			goal = to_local * point
		targets[digit_name] = goal if snap else (targets.get(digit_name, goal) as Vector3).lerp(goal, weight)
		_aim_digit(digit, targets[digit_name])
		digit["key"] = key_id
	hand["pose"] = pose_name
	hand["pressing"] = pressing


## trigger のキーが押されている置き方（前に並べたものが優先）。どれも押されていなければ定位置。
func _pressed_pose(poses: Dictionary) -> String:
	for pose_name: String in poses:
		for key_id: String in (poses[pose_name] as Dictionary).get("trigger", []):
			if _source.is_key_down(key_id):
				return pose_name
	return "home"


## 置き方の anchor の指が、その指のキーへ届く手の位置と向き。
func _hand_xform(hand: Dictionary, pose: Dictionary) -> Transform3D:
	var heading := Basis(Vector3.UP, float(hand["yaw"]))
	# 指を奥（-Z）へ、手のひらを下へ向け、HAND_TILT のぶん指の付け根側を上げる。
	var hand_basis := heading * Basis(Vector3.RIGHT, PI * 0.5 - HAND_TILT)
	if pose.has("park"):
		return Transform3D(hand_basis, pose["park"])
	var anchor := str(pose["anchor"])
	var offset := Vector3(0.0, KNUCKLE_LIFT, KNUCKLE_BACK)
	if anchor == "thumb":
		offset = Vector3(-float(hand["side"]) * THUMB_ANCHOR.x, THUMB_ANCHOR.y, THUMB_ANCHOR.z)
	var knuckle := _touch_point(str(pose["rest"][anchor]), NAN) + heading * offset
	return Transform3D(hand_basis, knuckle - hand_basis * ((hand["digits"][anchor] as Dictionary)["base"] as Vector3))


## 指先を置く点。キーの天面の手前寄りの少し上。横長のキーでは near_x にいちばん近い所。
func _touch_point(key_id: String, near_x: float) -> Vector3:
	var box: Dictionary = _key_boxes.get(key_id, {})
	if box.is_empty():
		return Vector3.ZERO
	var center: Vector3 = box["center"]
	var x := center.x
	if not is_nan(near_x):
		var reach := maxf(0.0, float(box["half_width"]) - 0.5)
		x = clampf(near_x, center.x - reach, center.x + reach)
	return Vector3(x, KeycapScript.CAP_HEIGHT + TOUCH_HEIGHT, center.z + TOUCH_FORWARD)


## 指（親指も）の先を、手の座標の target へ届かせる。付け根を手のひらの面の中で target の方へ振り、
## 関節を手のひら側（+Z）へ曲げる。
func _aim_digit(digit: Dictionary, target: Vector3) -> void:
	var joints: Array = digit["joints"]
	var to_target := target - (digit["base"] as Vector3)
	var spread := atan2(to_target.x, -to_target.y)
	var reach := Vector2(Vector2(to_target.x, to_target.y).length(), to_target.z)
	var bends := _solve_bends(digit["lengths"], reach, float(digit["min_root"]))
	(joints[0] as Node3D).basis = Basis(Vector3.BACK, spread) * Basis(Vector3.RIGHT, -bends[0])
	for index: int in range(1, joints.size()):
		(joints[index] as Node3D).basis = Basis(Vector3.RIGHT, -bends[index])
	digit["target"] = target


func _digit_tip(hand: Dictionary, digit: Dictionary) -> Vector3:
	var xform: Transform3D = (hand["root"] as Node3D).transform
	for joint: Node3D in digit["joints"]:
		xform = xform * joint.transform
	return xform * Vector3(0.0, -float((digit["lengths"] as Array)[-1]), 0.0)


## 平面の指の曲げ角（付け根から順。正で手のひら側）を CCD で求める。届かなければ target の方へ伸ばす。
## 付け根は min_root まで、ほかの関節はまっすぐまでしか反らさない。
static func _solve_bends(lengths: Array, target: Vector2, min_root: float) -> Array[float]:
	var bends: Array[float] = []
	for _length: Variant in lengths:
		bends.append(0.3)
	for _pass: int in range(16):
		for joint: int in range(lengths.size() - 1, -1, -1):
			var points := _digit_points(lengths, bends)
			var pivot: Vector2 = points[joint]
			var turn := wrapf((target - pivot).angle() - (points[-1] - pivot).angle(), -PI, PI)
			bends[joint] = clampf(bends[joint] + turn, min_root if joint == 0 else 0.0, 1.7)
	return bends


static func _digit_points(lengths: Array, bends: Array[float]) -> Array[Vector2]:
	var points: Array[Vector2] = [Vector2.ZERO]
	var heading := 0.0
	for index: int in range(lengths.size()):
		heading += bends[index]
		points.append(points[-1] + Vector2.from_angle(heading) * float(lengths[index]))
	return points


# ---------- 部品 ----------

## 画質の設定（GameManager がないテストでは「高」）。
func _quality() -> String:
	var manager := get_node_or_null("/root/GameManager")
	return str(manager.get("graphics_quality")) if manager != null else GraphicsQualityRules.HIGH


static func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


static func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh

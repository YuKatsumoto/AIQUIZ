extends Node3D

## 設定画面「地下神殿の講義室」（ui/settings_hall.tscn）の進行役。
## メニューの設定ボタンから黒いフェードの下で遷移してくる。立坑（ShaftDescent）を降りながら地下神殿
## （CisternStage）・Blender 製の小道具と 5 体のゴドーくん・連結チップソーの模型を別スレッドで読み込み、暗転をはさんでホールへ
## 降り立ち、照明が列ごとに点いたら左に設定 UI（SettingsHallPanel）を出す。
## 戻る（ボタン / Esc）はカメラが少し上がって黒へ落ち、メニューへ。
## 時計は実時間（SettingsHallDescent）。描画が止まった分は先へ飛ぶ。任意のキー・クリックで演出を飛ばせる。

const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const SettingsHallPanelScript := preload("res://scripts/ui/settings_hall_panel.gd")
const LectureSetScript := preload("res://scripts/world/settings_hall/lecture_set.gd")
const PracticeYardScript := preload("res://scripts/world/settings_hall/practice_yard.gd")
const YardDirectorScript := preload("res://scripts/world/settings_hall/yard_director.gd")
const DescentScript := preload("res://scripts/world/settings_hall/settings_hall_descent.gd")
const SHAFT_SCENE := preload("res://scenes/sudden_death/shaft_descent.tscn")

const MAIN_MENU_SCENE := "res://ui/main_menu.tscn"
const CISTERN_SCENE := "res://scenes/sudden_death/cistern_stage.tscn"
const SAW_GLB := "res://assets/hazards/linked_saw_carriage.glb"

const FLOOR_Y := SuddenDeathLayout.FLOOR_Y
## 講義セットの原点（ホールの床、着地点の少し下流）。+Z が黒板側。
const SET_ORIGIN := Vector3(0.0, FLOOR_Y, 5.0)
## 立坑はホールの真上、霧の向こう（本番の巡航と同じ高さ）。
const SHAFT_HEIGHT := SuddenDeathLayout.CRUISE_DECK_HEIGHT
const SHAFT_CLIP_TOP := 80.0
## 立坑の巡航ショット（昇降台の天面を原点とする、sudden_death_director と同じ）と真下を見るショット。
const CRUISE_EYE := Vector3(1.5, 3.4, -5.9)
const CRUISE_AIM := Vector3(-0.5, -3.6, 6.0)
const DOWN_EYE := Vector3(0.0, 12.5, -0.4)
const DOWN_BLEND := Vector2(1.2, 2.2)
const SHAFT_FOV := 60.0
const SHAFT_EXPOSURE_START := 0.55
const SHAFT_EXPOSURE_RAMP := 1.0
## 到着: 天井近くから最終の構図へ降りる。4.7 ページの構図（右にセット、左に暗い柱列）。
const ARRIVAL_EYE := Vector3(6.6, FLOOR_Y + 13.5, -7.6)
const FINAL_EYE := Vector3(5.8, FLOOR_Y + 6.6, -7.0)
const FINAL_AIM := Vector3(3.2, FLOOR_Y + 1.6, 6.0)
const ARRIVAL_FOV := 48.0
const FINAL_FOV := 42.0
## 実習場（PracticeYard）: 講義セットの右奥、柱のない区画（TANK_SCALE 2.0 で x −26〜−2、z 7〜49）に
## 本編の台車を実寸で縦に置く。台車のローカル +X（操縦席の端）がホールの +Z（奥）、前進（ローカル +Z）がホールの −X。
const YARD_ORIGIN := Vector3(-14.0, FLOOR_Y, 28.0)
const YARD_YAW := -PI * 0.5
## 「実習場を見る」の構図: 刃の列の手前の脇から奥の操縦席を見る。列が右手前から操縦席へ続き、
## 操縦席のゴドーくんはほぼ正面（画面の右 6 割の位置）。左 1/3 は暗いまま UI の背後に。
## 走行の中心での操縦者の頭は (−14.0, FLOOR_Y + 1.0, 41.2)。目はその右手前、狙いは頭から画面の左へ 1.3 m ずらす。
const PRACTICE_EYE := Vector3(-10.1, FLOOR_Y + 6.2, 27.5)
const PRACTICE_AIM := Vector3(-12.7, FLOOR_Y + 0.75, 41.6)
const PRACTICE_FOV := 36.0
## 台車は横へ ±2.4 m 走るので、実習場の視点はその分だけ（この割合で）ついていく。
const PRACTICE_FOLLOW := 0.85
## 視点の切り替え（秒）と、途中で上がる高さ（講義セットの上を越える）。
const VIEW_SECONDS := 1.6
const VIEW_ARC := 2.5
## 照明の行: セットに近い順に点く（sudden_death_director と同じ間隔とちらつき）。
const LIGHTS_START := 0.25
const LIGHTS_STEP := 0.12
const LIGHT_FLICKER := 0.09
const SET_LIGHTS_AT := 1.5
const HALL_AMBIENT_SCALE := 0.6
## 行の目標の明るさ（セットからの距離 m → 0〜1）。奥と左は暗いまま、UI の文字の背後に明かりを置かない。
const ROW_TARGETS: Array = [[12.0, 0.60], [30.0, 0.45], [55.0, 0.18]]
const ROW_TARGET_FAR := 0.08
const RETURN_RISE := 3.0
const RETURN_SECONDS := 0.5
## 戻るときに講義室の全員が手を振る間（秒）。
const GOODBYE_SECONDS := 0.9
const WARM_BUDGET_MS := 6.0

var _quality := GraphicsQualityRules.BALANCED
var _camera: Camera3D = null
var _shaft: ShaftDescent = null
var _cistern: CisternStage = null
var _lecture_set: LectureSetScript = null
var _yard: PracticeYardScript = null
## 視点: 0 = 講義室、1 = 実習場。_view_u がそこへ VIEW_SECONDS で動く。
var _view_target := 0.0
var _view_u := 0.0
var _camera_override: Dictionary = {}
var _yard_director: Node = null
var _ui: CanvasLayer = null
var _blackout: ColorRect = null
var _panel: SettingsHallPanelScript = null
var _descent: DescentScript = null
var _shaft_env: Environment = null
var _hall_env: Environment = null
var _hall_lit := 0.0
## 講義室の時間帯の暗さ（1 = 夜: 行の照明と環境光を落とす）。2 秒でなめらかに変わる。
var _night := 0.0
var _night_tween: Tween = null
var _started := false
var _leaving := false
var _settled := false
var _blackout_entered := false
var _arrival_entered := false
var _set_lights_on := false
var _last_usec := 0
var _clock := 0.0
## path -> true: a threaded request is outstanding.
var _pending: Dictionary = {}
var _cistern_parts_done := false
var _warm_queue: Array[Resource] = []
var _row_order: Array[int] = []
var _row_targets: Array[float] = []
## 露出のランプ (from, to, seconds)。
var _env_ramp := Vector3.ZERO
var _env_ramp_time := 0.0


func _ready() -> void:
	_quality = GraphicsQualityRules.normalize(GameManager.graphics_quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), _quality)
	get_window().size_changed.connect(_on_window_size_changed)
	AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_MENU)
	_descent = DescentScript.new()

	_camera = Camera3D.new()
	_camera.name = "HallCamera"
	_camera.near = 0.05
	_camera.far = 260.0
	_camera.fov = SHAFT_FOV
	add_child(_camera)
	_camera.current = true
	_shaft_env = ShaftDescent.make_environment(_quality)
	_hall_env = CisternStage.make_environment(_quality)
	_set_env(_shaft_env, SHAFT_EXPOSURE_START, 1.0, SHAFT_EXPOSURE_RAMP)

	_shaft = SHAFT_SCENE.instantiate() as ShaftDescent
	_shaft.name = "Shaft"
	_shaft.quality = _quality
	_shaft.position = Vector3(0.0, FLOOR_Y + SHAFT_HEIGHT, 0.0)
	add_child(_shaft)
	_shaft.set_mouth(false, 0.0, 1.0)
	_shaft.set_daylight(0.0)
	_shaft.set_beacons(false)
	_shaft.set_clip(SHAFT_CLIP_TOP, -INF)
	_shaft.set_view(0.0, 0.0)
	_shaft.set_depth_signs([])

	_lecture_set = LectureSetScript.new()
	_lecture_set.name = "LectureSet"
	_lecture_set.position = SET_ORIGIN
	_lecture_set.visible = false
	add_child(_lecture_set)
	_lecture_set.build(_quality)
	_lecture_set.mood_changed.connect(_on_lecture_mood)

	_yard = PracticeYardScript.new()
	_yard.name = "PracticeYard"
	_yard.position = YARD_ORIGIN
	_yard.rotation.y = YARD_YAW
	_yard.visible = false
	add_child(_yard)

	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_ui.layer = 1
	add_child(_ui)
	_blackout = ColorRect.new()
	_blackout.name = "Blackout"
	_blackout.color = Color.BLACK
	_blackout.mouse_filter = Control.MOUSE_FILTER_STOP
	_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blackout.visible = false
	_ui.add_child(_blackout)
	_panel = SettingsHallPanelScript.new()
	_panel.name = "Panel"
	_panel.visible = false
	_panel.back_requested.connect(_leave)
	_panel.graphics_quality_changed.connect(_on_panel_quality_changed)
	_panel.sfx_tested.connect(func() -> void: _lecture_call("on_sfx_test"))
	_panel.api_status_changed.connect(_on_panel_api_status_changed)
	_panel.view_toggled.connect(_on_panel_view_toggled)
	_ui.add_child(_panel)

	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	_request_loads()
	_update_shaft_view()
	# 立坑を 2 フレーム描いてから覆いを外す（初描画のコンパイルを黒の下に隠す）。
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	SceneTransition.reveal_current()
	_last_usec = Time.get_ticks_usec()
	_started = true


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)


func _on_window_size_changed() -> void:
	GraphicsQualityRules.apply_text_viewport(get_viewport(), _quality)


func _on_frame_post_draw() -> void:
	if _descent != null:
		_descent.note_frame_drawn()


# ------------------------------------------------------------------ frame

func _process(_delta: float) -> void:
	_poll_loads()
	if _cistern != null and not _cistern_parts_done:
		_step_cistern()
	if not _started:
		return
	var now := Time.get_ticks_usec()
	var dt := clampf(float(now - _last_usec) / 1000000.0, 0.0, 0.1)
	_last_usec = now
	_clock += dt
	_update_env_ramp(dt)
	if _yard.visible:
		_yard.advance(dt)
	if _leaving:
		return
	_descent.assets_ready = _assets_ready()
	_descent.advance(dt)
	# 1 フレームで複数の段階をまたいでも、受け渡しは順に全部行う。
	if _descent.phase >= DescentScript.Phase.BLACKOUT and not _blackout_entered:
		_enter_blackout()
	if _descent.phase >= DescentScript.Phase.ARRIVAL and not _arrival_entered:
		_enter_arrival()
	match _descent.phase:
		DescentScript.Phase.SHAFT:
			_update_shaft()
		DescentScript.Phase.ARRIVAL:
			_update_arrival()
		DescentScript.Phase.SETTLED:
			if not _settled:
				_enter_settled()
			_update_idle()


func _assets_ready() -> bool:
	return _pending.is_empty() and _warm_queue.is_empty() and (_cistern == null or _cistern_parts_done)


## 実習場は台車・座席・操作盤の GLB がすべてそろってから組み立てる（中の同期 load が待たないように）。
func _try_build_yard(path: String, packed: PackedScene) -> void:
	if not _yard.is_built() and _yard.hold_asset(path, packed):
		_yard.build()


# ------------------------------------------------------------------ shaft

func _update_shaft() -> void:
	_shaft.set_view(0.0, _descent.scroll)
	_shaft.set_motion_speed(_descent.speed)
	_shaft.set_depth_signs(_descent.depth_signs(0.0))
	_update_shaft_view()


## 巡航の構図（0.3°・0.5 Hz の揺れと昇降の細かい振動）から、少しずつ真下を見るショットへ。
func _update_shaft_view() -> void:
	if _shaft == null or _camera == null:
		return
	var deck := _shaft.global_position
	var cruise := _look(deck + CRUISE_EYE, deck + CRUISE_AIM)
	var down := Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), deck + DOWN_EYE)
	var blend := smoothstep(DOWN_BLEND.x, DOWN_BLEND.y, _descent.phase_time) if _descent != null else 0.0
	var pose := cruise.interpolate_with(down, blend * 0.7)
	var judder := clampf((_descent.speed if _descent != null else 0.0) / 10.0, 0.0, 1.0)
	var sway := Basis(Vector3.FORWARD, deg_to_rad(0.3) * sin(_clock * TAU * 0.5))
	sway = sway * Basis(Vector3.RIGHT, deg_to_rad(0.08) * judder * sin(_clock * 47.0) + deg_to_rad(0.05) * judder * sin(_clock * 71.0))
	pose.basis = pose.basis * sway
	_camera.global_transform = pose
	_camera.fov = SHAFT_FOV


# ------------------------------------------------------------------ blackout / arrival

func _enter_blackout() -> void:
	_blackout_entered = true
	_blackout.visible = true
	if _shaft != null:
		_shaft.visible = false
	if _cistern != null:
		_cistern.visible = true
		_cistern.set_all_rows(0.0)
		_plan_rows()
	_apply_hall_light(0.0)
	_set_env(_hall_env, 1.0, 1.0, 0.0)
	_lecture_set.visible = true
	_lecture_set.set_lit(0.0)
	_yard.visible = _yard.is_built()
	_yard.set_lit(0.0)
	_camera_pose(ARRIVAL_EYE, FINAL_AIM, ARRIVAL_FOV)


func _enter_arrival() -> void:
	_arrival_entered = true
	_blackout.visible = false


func _update_arrival() -> void:
	var u := _descent.arrival_u()
	_camera_pose(ARRIVAL_EYE.lerp(FINAL_EYE, u), FINAL_AIM, lerpf(ARRIVAL_FOV, FINAL_FOV, u))
	_update_row_lights(_descent.arrival_time())


func _enter_settled() -> void:
	_settled = true
	_update_row_lights(DescentScript.ARRIVAL_TIME)
	_camera_pose(FINAL_EYE, FINAL_AIM, FINAL_FOV)
	if _shaft != null:
		_shaft.queue_free()
		_shaft = null
	_panel.visible = true
	_panel.play_entrance()
	_panel.begin_api_check()


func _update_idle() -> void:
	var dt := clampf(get_process_delta_time(), 0.0, 0.1)
	_view_u = move_toward(_view_u, _view_target, dt / VIEW_SECONDS)
	var drift := Vector3(0.06 * sin(_clock * 0.37), 0.04 * sin(_clock * 0.29), 0.0)
	var follow := _yard.travel_offset() * PRACTICE_FOLLOW if _yard.is_built() else Vector3.ZERO
	var pose := view_pose(_view_u, follow)
	_try_yard_director()
	if _yard.is_built() and _view_u > 0.0:
		# 実習場: ときどき操作の手元へ寄る（項目 135）
		var close := _yard.closeup() * smoothstep(0.0, 1.0, _view_u)
		if close > 0.0:
			pose.eye = (pose.eye as Vector3).lerp(_yard.closeup_eye(), close)
			pose.aim = (pose.aim as Vector3).lerp(_yard.closeup_target(), close)
			pose.fov = lerpf(float(pose.fov), 30.0, close)
	if not _camera_override.is_empty():
		pose = _camera_override
		drift = Vector3.ZERO
	_camera_pose(pose.eye + drift, pose.aim, pose.fov)


## テスト・確認用: 到着後のカメラを講義セットのローカル座標の目と狙いで固定する（空の辞書で解除）。
func set_camera_override(eye_local: Vector3, aim_local: Vector3, fov: float) -> void:
	_camera_override = {"eye": SET_ORIGIN + eye_local, "aim": SET_ORIGIN + aim_local, "fov": fov}


func clear_camera_override() -> void:
	_camera_override = {}


## 視点 u（0 = 講義室、1 = 実習場）のカメラ。目と狙いは途中で少し上がる弧を描く。
## follow: 実習場の視点が台車について動く量（ワールド）。
static func view_pose(u: float, follow: Vector3 = Vector3.ZERO) -> Dictionary:
	var w := smoothstep(0.0, 1.0, u)
	var lift := Vector3.UP * VIEW_ARC * sin(PI * w)
	return {
		"eye": FINAL_EYE.lerp(PRACTICE_EYE + follow, w) + lift,
		"aim": FINAL_AIM.lerp(PRACTICE_AIM + follow, w) + lift * 0.4,
		"fov": lerpf(FINAL_FOV, PRACTICE_FOV, w),
	}


func _on_panel_view_toggled(practice: bool) -> void:
	_view_target = 1.0 if practice else 0.0


## テスト用: 視点をすぐ切り替える（u = 0 講義室 / 1 実習場）。
func set_view_now(u: float) -> void:
	_view_target = clampf(u, 0.0, 1.0)
	_view_u = _view_target


## 行をセットに近い順に並べ、距離で目標の明るさを決める。
func _plan_rows() -> void:
	_row_order.clear()
	_row_targets.clear()
	if _cistern == null:
		return
	for row in range(_cistern.row_count()):
		_row_order.append(row)
	_row_order.sort_custom(func(a: int, b: int) -> bool:
		return absf(_cistern.light_row_z(a) - SET_ORIGIN.z) < absf(_cistern.light_row_z(b) - SET_ORIGIN.z))
	for row in _row_order:
		var distance := absf(_cistern.light_row_z(row) - SET_ORIGIN.z)
		var target := ROW_TARGET_FAR
		for entry: Array in ROW_TARGETS:
			if distance < float(entry[0]):
				target = float(entry[1])
				break
		_row_targets.append(target)


## 到着 time 秒: 行が順に点く（短いちらつき、目標の明るさ）。SET_LIGHTS_AT でセットのスポットが一気に点く。
func _update_row_lights(time: float) -> void:
	if _cistern != null:
		var lit_sum := 0.0
		var target_sum := 0.0
		for index in range(_row_order.size()):
			var row := _row_order[index]
			var target := _row_targets[index]
			target_sum += target
			var local := time - (LIGHTS_START + LIGHTS_STEP * float(index))
			var amount := 0.0
			if local >= 0.0:
				if local > LIGHT_FLICKER * 2.0:
					amount = target
				else:
					amount = target * (0.75 if fmod(local, LIGHT_FLICKER) < LIGHT_FLICKER * 0.5 else 0.25)
			_cistern.set_row_brightness(row, amount * _night_scale())
			lit_sum += amount
		_apply_hall_light(HALL_AMBIENT_SCALE * lit_sum / maxf(target_sum, 0.001) * lerpf(1.0, 0.35, _night))
	if time >= SET_LIGHTS_AT and not _set_lights_on:
		_set_lights_on = true
		_lecture_set.set_lit(1.0)
		_yard.set_lit(1.0)
		if _cistern != null:
			_cistern.refresh_reflections()


func _apply_hall_light(amount: float) -> void:
	_hall_lit = clampf(amount, 0.0, 1.0)
	CisternStage.apply_hall_light(_hall_env, _hall_lit)


# ------------------------------------------------------------------ loading

func _request_loads() -> void:
	var paths: Array[String] = [CISTERN_SCENE, SAW_GLB]
	paths.append_array(LectureSetScript.asset_paths())
	for path: String in PracticeYardScript.asset_paths():
		if not paths.has(path):
			paths.append(path)
	for path: String in paths:
		if ResourceLoader.has_cached(path):
			_attach(path, ResourceLoader.load(path))
			continue
		var error := ResourceLoader.load_threaded_request(path)
		if error != OK:
			push_warning("SettingsHall: load_threaded_request(%s): %s" % [path, error_string(error)])
			_attach_failed(path)
			continue
		_pending[path] = true


func _poll_loads() -> void:
	if _pending.is_empty():
		return
	for path: String in _pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(path)
			_pending.erase(path)
			_attach(path, resource)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("SettingsHall: failed to load %s" % path)
			_pending.erase(path)
			_attach_failed(path)


## 講義セットの GLB が読めなかった: セットに知らせる（そろうのを待っている進行役が止まらないように）。
func _attach_failed(path: String) -> void:
	if LectureSetScript.asset_paths().has(path):
		_lecture_set.attach_asset(path, null)


func _attach(path: String, resource: Resource) -> void:
	var packed := resource as PackedScene
	if packed == null:
		push_warning("SettingsHall: %s is not a PackedScene" % path)
		return
	match path:
		CISTERN_SCENE:
			_attach_cistern(packed)
		SAW_GLB:
			_lecture_set.attach_saw(packed)
		_:
			if not PracticeYardScript.asset_paths().has(path):
				_lecture_set.attach_asset(path, packed)
	_try_build_yard(path, packed)


## 地下神殿: 画質を合わせてから非表示で足し、材質とメッシュを少しずつ用意し、部分シーンを 1 フレームに 1 つ加える
## （SuddenDeathLoader と同じ順。タワーと水は作らない）。
func _attach_cistern(packed: PackedScene) -> void:
	if _cistern != null:
		return
	var node := packed.instantiate()
	_cistern = node as CisternStage
	if _cistern == null:
		push_warning("SettingsHall: %s root is not a CisternStage" % CISTERN_SCENE)
		if node != null:
			node.free()
		return
	_cistern.name = "CisternStage"
	_cistern.visible = false
	_cistern.apply_quality(_quality)
	add_child(_cistern)
	_collect_warm_resources(packed, {})


func _step_cistern() -> void:
	if not _warm_queue.is_empty():
		_warm_step()
		return
	if _cistern.add_part_step():
		_cistern_parts_done = true


## 初めての get_rid()（シェーダーの生成、1 つ約 50 ms になることがある）を 1 フレーム WARM_BUDGET_MS まで。
func _warm_step() -> void:
	var start := Time.get_ticks_usec()
	while not _warm_queue.is_empty():
		var resource: Resource = _warm_queue.pop_back()
		if resource is Material:
			(resource as Material).get_rid()
		elif resource is Mesh:
			(resource as Mesh).get_rid()
		if float(Time.get_ticks_usec() - start) / 1000.0 >= WARM_BUDGET_MS:
			break


func _collect_warm_resources(scene: PackedScene, seen: Dictionary) -> void:
	if scene == null or seen.has(scene):
		return
	seen[scene] = true
	var state := scene.get_state()
	for node in range(state.get_node_count()):
		for property in range(state.get_node_property_count(node)):
			_collect_warm_value(state.get_node_property_value(node, property), seen)


func _collect_warm_value(value: Variant, seen: Dictionary) -> void:
	if value is Array:
		for item: Variant in value:
			_collect_warm_value(item, seen)
	elif value is PackedScene:
		_collect_warm_resources(value as PackedScene, seen)
	elif value is MultiMesh:
		_collect_warm_value((value as MultiMesh).mesh, seen)
	elif (value is Material or value is Mesh) and not seen.has(value):
		seen[value] = true
		_warm_queue.append(value as Resource)


# ------------------------------------------------------------------ panel

func _on_panel_quality_changed(quality: String) -> void:
	_quality = GraphicsQualityRules.normalize(quality)
	_lecture_call("on_quality_changed")
	GraphicsQualityRules.apply_text_viewport(get_viewport(), _quality)
	if _cistern != null:
		_cistern.apply_quality(_quality)
	_hall_env = CisternStage.make_environment(_quality)
	CisternStage.apply_hall_light(_hall_env, _hall_lit)
	if _blackout_entered:
		_set_env(_hall_env, 1.0, 1.0, 0.0)
	_lecture_set.apply_quality(_quality)
	if _cistern != null and _settled:
		_cistern.refresh_reflections()


func _on_panel_api_status_changed(summary: Dictionary) -> void:
	_lecture_set.set_api_status(summary)


# ------------------------------------------------------------------ leave

func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not _started:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_leave()
		elif _descent.is_descending():
			_descent.skip = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and _descent.is_descending():
		_descent.skip = true


## 戻る: UI が左へ消え、照明が落ちながらカメラが少し上がり、黒へ。メニューの _ready が覆いを外す。
func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	if _settled:
		# 講義室の全員がこちらを向いて手を振ってから（項目 100）
		if _lecture_call("goodbye"):
			await get_tree().create_timer(GOODBYE_SECONDS).timeout
			if not is_inside_tree():
				return
		_panel.play_exit()
		var rise_from := _camera.position.y
		var tw := create_tween()
		tw.set_parallel(true)
		tw.set_ease(Tween.EASE_IN)
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.tween_method(_set_return_light, 1.0, 0.0, RETURN_SECONDS)
		tw.tween_property(_camera, "position:y", rise_from + RETURN_RISE, RETURN_SECONDS)
		await get_tree().create_timer(RETURN_SECONDS * 0.6).timeout
		if not is_inside_tree():
			return
	await SceneTransition.fade_to_color_and_wait(Color.BLACK)
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _night_scale() -> float:
	return lerpf(1.0, 0.18, _night)


func _on_lecture_mood(night: float) -> void:
	if _night_tween != null and _night_tween.is_valid():
		_night_tween.kill()
	_night_tween = create_tween()
	_night_tween.tween_method(_set_night, _night, night, 2.0)


func _set_night(value: float) -> void:
	_night = value
	if _cistern == null or not _settled:
		return
	for index in range(_row_order.size()):
		_cistern.set_row_brightness(_row_order[index], _row_targets[index] * _night_scale())
	_apply_hall_light(HALL_AMBIENT_SCALE * lerpf(1.0, 0.35, _night))


## 実習場の人物の進行役: 実習場が組み上がり、講義室の人物の GLB が読めたら 1 回だけ作る。
func _try_yard_director() -> void:
	if _yard_director != null or not _yard.is_built() or _lecture_set.director == null:
		return
	_yard_director = YardDirectorScript.new()
	_yard_director.name = "YardDirector"
	_yard.add_child(_yard_director)
	if not _yard_director.call("setup", _yard):
		push_warning("SettingsHall: yard director could not start")


## 講義室の進行役（いれば）の method を呼ぶ。呼べたら true。
func _lecture_call(method: String) -> bool:
	var director: Node = _lecture_set.director if _lecture_set != null else null
	if director == null or not director.has_method(method):
		return false
	director.call(method)
	return true


func _set_return_light(amount: float) -> void:
	if _cistern != null:
		for index in range(_row_order.size()):
			_cistern.set_row_brightness(_row_order[index], _row_targets[index] * amount)
	_apply_hall_light(HALL_AMBIENT_SCALE * amount)
	_lecture_set.set_lit(lerpf(0.3, 1.0, amount))
	_yard.set_lit(lerpf(0.3, 1.0, amount))


# ------------------------------------------------------------------ camera / environment

func _camera_pose(eye: Vector3, aim: Vector3, fov: float) -> void:
	_camera.global_transform = _look(eye, aim)
	_camera.fov = fov


static func _look(eye: Vector3, aim: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(aim - eye, Vector3.UP), eye)


## カメラに environment を載せ、露出を from → to へ seconds で（sudden_death_director._set_env と同じ）。
func _set_env(environment: Environment, from: float, to: float, seconds: float) -> void:
	if _camera == null or environment == null:
		return
	_camera.environment = environment
	_env_ramp = Vector3(from, to, maxf(seconds, 0.0))
	_env_ramp_time = 0.0
	environment.tonemap_exposure = from if seconds > 0.0 else to


func _update_env_ramp(dt: float) -> void:
	if _camera == null or _camera.environment == null or _env_ramp.z <= 0.0:
		return
	_env_ramp_time += dt
	var u := smoothstep(0.0, 1.0, _env_ramp_time / _env_ramp.z)
	_camera.environment.tonemap_exposure = lerpf(_env_ramp.x, _env_ramp.y, u)
	if u >= 1.0:
		_env_ramp.z = 0.0

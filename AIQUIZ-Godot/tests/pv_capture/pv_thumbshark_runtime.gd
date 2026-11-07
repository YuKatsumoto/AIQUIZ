extends "res://tests/pv_capture/pv_take_base.gd"

## 作品ページのサムネイル 4 枚目（サメ）：脱落した P2 がゴーストシャークに乗って突っ込み、生き残りの P1 が吹っ飛ぶ瞬間。
## 本物の GameWorld（ローカル 2P）で、P2 を壁で脱落させ、ゴーストの搭乗の演出から照準まで進めて、P1 へ突進させる。
## 当たったあとの吹っ飛び（ラグドール・回転・着地の砂ぼこり）は今のゲームの作りのまま（docs/ghost_hit_ragdoll_plan.md）。
## 見た目は PV と同じ（P1 プロペラ帽子・オレンジ、P2 キツネ帽子）。突進の撮影の作りは tests/ghost_hit_capture_runtime.gd と同じ。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumbshark quality=ultra sub=8 shutter=8 png tag=thumbshark_sub8 frames=98 slow_from=48 slow=0.25 only=88,89,90,91,92,93,94,95,96 cam=6.0,0.5,-14.5,5.2,2.0,-2.4,42
## 刻みの重ね方とテロップは docs/pv/thumbnail/pv_stills.py（only=shark）。手順と値は docs/pv/takes/thumb.md の「4 枚目」。
##
## 流れ（PV フレーム。60 fps）：撮り始め（1）で突進のためを放す → 予備動作（約 20 フレーム）→ 突進 → 命中 → 吹っ飛び。
## 引数（共通のほかに）:
##   power=<0〜1>                 突進の強さ（既定 0.85：PERFECT。0.72〜0.94 が PERFECT）
##   px=<m>                       照準の前に P1 を横のこの位置へ動かす（既定は正解の扉の前のまま）
##   pz=<m>                       照準の前に P1 を前（+）/ 後ろ（−）へこれだけ動かす
##   cam=ex,ey,ez,tx,ty,tz,fov    カメラ（P1 の足元から：x・床からの高さ・z、注視点も同じ、縦の画角）。無ければゲームのカメラ
##   dof=<先>,<幅>,<量>           背景のぼけ（cam= のとき。P1 より <先> m 奥からぼかし始め、<幅> m でぼけきる。量 0 でぼかさない）
##   hud=0                        HUD を隠す（既定は出す：ゲームの画面そのまま）
##   day=<0〜1>                   昼の位相（既定 0.25）
##   fast=<倍>                    照準までの待ちを何倍速で進めるか（既定 4。撮らないところ）
##   slow_from=<f>  slow=<倍>     そのフレームから時間を slow 倍にする（動きのブレを細かい刻みで重ねるため）
## 物理はゲームと同じ 60 Hz で進める（吹っ飛びのラグドールの姿が刻みの細かさで変わる。60×sub Hz だと丸まる）。
## ゲームは物理の補間を使わないので、そのままでは描く刻みの間でラグドールが止まる。撮影のあいだだけ物理の補間を入れ、
## ラグドールの木（RagdollLimbsP1/P2）だけを補間する（ほかは今までどおり。補間は 1 刻み遅れて見える）。
##   alts=<json>                  構図探し：ほかのカメラ（{"名前": [ex,ey,ez,tx,ty,tz,fov], ...} の JSON ファイル）からも
##                                960×540 で撮る（alt_<名前>_NNNN.jpg。only= のフレームだけ）

const P1_HAT := 11
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const P2_HAT := 12
const P2_SKIN_CODE := "034dbff2f5f5f0f5f5f01e1e221e1e22f5f5f0f5f5f01e1e221e1e221e1e221e1e22"
const FLOOR_Y := -1.2
const WARMUP_FRAMES := 120
## 壁の問題は PV と同じ（pv_thumb_runtime.gd）
const QUIZZES := [
	["【かけ算】7 × 8 ＝ ？", ["56", "54"]],
	["「たいよう」を漢字で書くと？", ["太陽", "太洋"]],
	["水が氷になる温度は？", ["0℃", "100℃"]],
]

var helper: Node
var gs: QuizGameState
var world: Node
var player: PlayerController
var ghost: GhostSharkRideController
var camera_controller: Node
var cam: Camera3D
var attrs: CameraAttributesPractical
var power := 0.85
var p1_x := NAN
var p1_dz := 0.0
var cam_cfg: Array = []
var dof_cfg: Array = [6.0, 18.0, 0.0]
var show_hud := true
var day_phase := 0.25
var fast := 4.0

var slow_from := 0
var slow := 1.0
var alts_path := ""
var _alts: Dictionary = {}
var _anchor := Vector3.ZERO
var _hit_frame := -1
var _windup_frame := -1
var _charging_frame := -1
var _trace: Array = []


func _init() -> void:
	take_name = "thumbshark"


func _default_frames() -> int:
	return 60


func _parse_arg(arg: String) -> void:
	var kv := arg.split("=", true, 1)
	if kv.size() != 2:
		return
	var v := Array(kv[1].split(",")).map(func(s: String) -> float: return float(s))
	match kv[0]:
		"power":
			power = clampf(float(kv[1]), 0.0, 1.0)
		"px":
			p1_x = float(kv[1])
		"pz":
			p1_dz = float(kv[1])
		"cam":
			cam_cfg = v
		"dof":
			dof_cfg = v
		"hud":
			show_hud = kv[1] not in ["0", "false"]
		"day":
			day_phase = float(kv[1])
		"fast":
			fast = maxf(1.0, float(kv[1]))
		"alts":
			alts_path = kv[1]
		"slow_from":
			slow_from = int(kv[1])
		"slow":
			slow = clampf(float(kv[1]), 0.05, 1.0)


func _setup() -> void:
	Engine.physics_ticks_per_second = int(FPS)
	await _build_world()
	_interpolate_ragdolls()
	if not show_hud:
		hide_overlays()
	attrs = CameraAttributesPractical.new()
	# P2 を壁で脱落させる（P1 は正解の扉、P2 は HP 1 で不正解の扉）
	gs._set_player_hp(2, 1)
	gs.player_x = helper.door(gs, true)
	gs.player2_x = helper.door(gs, false)
	gs.resolve_collision(true, true)
	# 搭乗の演出から照準まで（撮らない）。物理の刻みは 60×sub のまま、時間だけ速める
	Engine.time_scale = minf(fast, 8.0 / maxf(1.0, float(Engine.physics_ticks_per_second) / 480.0))
	var waited := 0
	while ghost.phase != ghost.Phase.AIMING and waited < 2400 * sub:
		gs.set("_active_wall_speed", 0.15)
		await get_tree().process_frame
		waited += 1
	Engine.time_scale = 1.0
	if ghost.phase != ghost.Phase.AIMING:
		failures.append("照準まで進まなかった（%s）" % ghost.Phase.keys()[ghost.phase])
	await _frames(30 * sub)
	if not is_nan(p1_x) or p1_dz != 0.0:
		# P1 を動かし、照準の基準点もそこへ移す（サメは床の外の横で待ち、前後は生き残りについてくる）
		if not is_nan(p1_x):
			gs.player_x = p1_x
			ghost._aim_origin.x = p1_x
		gs.player_z += p1_dz
		await _frames(30 * sub)
	# 照準を P1 の今の位置へ（基準点から ±8 m の内側）
	var survivor: Vector3 = ghost._player_position(1)
	var origin: Vector3 = ghost._aim_origin
	ghost._aim_offset = Vector2(survivor.x - origin.x, survivor.z - origin.z)
	await _frames(2 * sub)
	_anchor = _p1_feet()
	report["plan"] = {"power": power, "px": p1_x if not is_nan(p1_x) else null, "pz": p1_dz, "cam": cam_cfg, "dof": dof_cfg,
		"hud": show_hud, "day": day_phase, "anchor": [snappedf(_anchor.x, 0.01), snappedf(_anchor.y, 0.01), snappedf(_anchor.z, 0.01)],
		"shark_wait": _v(ghost._shark.global_position)}
	# 撮り始めの直前にためを放す（撮り始めの 1 フレーム目から予備動作）
	ghost._charging_input = true
	ghost._charge_amount = power
	ghost._commit_charge()
	report["plan"]["locked_direction"] = _v(ghost._locked_direction)
	report["plan"]["slow"] = [slow_from, slow]
	report["plan"]["physics_hz"] = Engine.physics_ticks_per_second
	_apply_camera()
	_build_alts()


## 物理の補間を入れ、ゲームの世界は補間しない。被弾のラグドールの木ができたら、その木だけ補間する。
func _interpolate_ragdolls() -> void:
	get_tree().physics_interpolation = true
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Node3D and String(node.name).begins_with("RagdollLimbs"):
			(node as Node3D).physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
			# 作った直後の置き直しを補間しない（原点から飛んでくる線が出ないように）
			_reset_interpolation.call_deferred(node))


func _reset_interpolation(node: Node) -> void:
	if is_instance_valid(node):
		for child: Node in node.find_children("*", "Node3D", true, false):
			(child as Node3D).reset_physics_interpolation()
		(node as Node3D).reset_physics_interpolation()


func _game_time_at(pv: float) -> float:
	var t0 := float(slow_from) / FPS
	if slow_from <= 0 or slow >= 1.0 or pv <= t0:
		return pv
	return t0 + (pv - t0) * slow


func _build_alts() -> void:
	if alts_path == "":
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(alts_path))
	if not data is Dictionary:
		failures.append("alts を読めない：%s" % alts_path)
		return
	var main_camera := get_viewport().get_camera_3d()
	for alt_name: String in data:
		var c: Array = data[alt_name]
		var vp := SubViewport.new()
		vp.size = Vector2i(960, 540)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.world_3d = get_tree().root.world_3d
		vp.msaa_3d = Viewport.MSAA_4X
		add_child(vp)
		var alt_cam := Camera3D.new()
		alt_cam.near = 0.05
		alt_cam.far = 4000.0
		alt_cam.fov = float(c[6])
		vp.add_child(alt_cam)
		alt_cam.current = true
		if main_camera != null:
			alt_cam.cull_mask = main_camera.cull_mask
			alt_cam.environment = main_camera.environment
		var eye := _anchor + Vector3(c[0], c[1], c[2])
		alt_cam.global_transform = Transform3D(Basis.looking_at(_anchor + Vector3(c[3], c[4], c[5]) - eye, Vector3.UP), eye)
		_alts[alt_name] = vp


func _build_world() -> void:
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2)
	for index in range(gs.quiz_list.size()):
		var e: Array = QUIZZES[index % QUIZZES.size()]
		var choices := PackedStringArray(e[1])
		if gs.num_choices_for_index(index) == 4:
			choices = PackedStringArray([choices[0], choices[1], "その他", "わからない"])
		gs.quiz_list[index] = QuizItem.create(e[0], choices, 0, "", "OFFLINE")
	gs.current_index = 0
	gs.current_wall_index = 0
	gs.load_current_quiz()
	gs.set_player_skin(1, PlayerSkin.from_code(P1_SKIN_CODE))
	gs.set_player_skin(2, PlayerSkin.from_code(P2_SKIN_CODE))
	gs.p1_hat = P1_HAT
	gs.p2_hat = P2_HAT
	gs.skip_start_helicopter_arrival = true
	gs.set("_active_wall_speed", 0.15)
	QuizManager.game_state = gs
	world = (load("res://scenes/game_world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	player = world.get_node("Player") as PlayerController
	player.prepare_for_loading(gs)
	player.reveal_without_intro_arrival()
	ghost = world.get("_ghost_shark_ride_controller")
	var stage: StageEnvironment = world.get("stage_env")
	var weather: Node = stage.get("weather_cycle") if stage != null else null
	if weather != null:
		weather.call("force_day_phase", day_phase)
	camera_controller = world.get("camera_controller")
	cam = camera_controller.get_node_or_null("Camera3D") as Camera3D
	# チップソーは画面に入れない
	gs.saw_transport_enabled = false
	await _frames(WARMUP_FRAMES * sub)


func _update(n: int, _t: float, _dt: float) -> void:
	gs.set("_active_wall_speed", 0.15)
	if _windup_frame < 0 and ghost.phase == ghost.Phase.WINDUP:
		_windup_frame = n
	if _charging_frame < 0 and ghost.phase == ghost.Phase.CHARGING:
		_charging_frame = n
	if _hit_frame < 0 and bool(ghost._hit_this_charge):
		_hit_frame = n
		report["hit_info"] = _jsonable(ghost.get("_last_hit_info"))
	_apply_camera()
	_record(n)
	if not _alts.is_empty() and (_step % sub) == 0 and (only_frames.is_empty() or only_frames.has(n)):
		RenderingServer.frame_post_draw.connect(_save_alts.bind(n), CONNECT_ONE_SHOT)


func _save_alts(n: int) -> void:
	for alt_name: String in _alts:
		var image := (_alts[alt_name] as SubViewport).get_texture().get_image()
		if image != null:
			image.save_jpg(ProjectSettings.globalize_path(out + "alt_%s_%04d.jpg" % [alt_name, n]), 0.9)


func _p1_feet() -> Vector3:
	var p := ghost._player_position(1)
	return Vector3(p.x, FLOOR_Y, p.z)


func _apply_camera() -> void:
	var saw_node := world.get_node_or_null("SawChaseController") as Node3D
	if saw_node != null:
		saw_node.visible = false
	if cam_cfg.size() < 7 or cam == null:
		return
	var c := cam_cfg
	var eye := _anchor + Vector3(c[0], c[1], c[2])
	var target := _anchor + Vector3(c[3], c[4], c[5])
	var pose := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	camera_controller.call("set_director_pose", pose, float(c[6]))
	cam.h_offset = 0.0
	cam.fov = float(c[6])
	cam.global_transform = pose
	if float(dof_cfg[2]) > 0.0:
		var subject := eye.distance_to(_anchor + Vector3.UP)
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = subject + float(dof_cfg[0])
		attrs.dof_blur_far_transition = float(dof_cfg[1])
		attrs.dof_blur_near_enabled = false
		attrs.dof_blur_amount = float(dof_cfg[2])
		cam.attributes = attrs
	else:
		cam.attributes = null


func _record(n: int) -> void:
	if (_step % sub) != 0:
		return
	var torso := Vector3.INF
	for body: Variant in player.get_ghost_hit_bodies(1):
		if (body as Node).name == "TorsoBody":
			torso = (body as Node3D).global_position
	var pelvis := (player.get("p1_parts") as Dictionary).get("pelvis") as Node3D
	var entry := {"f": n, "phase": str(ghost.Phase.keys()[ghost.phase]),
		"shark": _v(ghost._shark.global_position) if ghost._shark != null else null,
		"pelvis": _v(pelvis.global_position) if pelvis != null else null,
		"torso": _v(torso) if torso != Vector3.INF else null,
		"p1_y": snappedf(gs.player_y, 0.01), "ragdoll": bool(player.has_ghost_hit_ragdoll(1)),
		"alive": [gs.p1_alive, gs.p2_alive]}
	var vp_cam := get_viewport().get_camera_3d()
	if vp_cam != null:
		entry["cam"] = _v(vp_cam.global_position)
		if pelvis != null and not vp_cam.is_position_behind(pelvis.global_position):
			var s := vp_cam.unproject_position(pelvis.global_position)
			entry["pelvis_px"] = [roundi(s.x), roundi(s.y)]
		if ghost._shark != null and not vp_cam.is_position_behind(ghost._shark.global_position):
			var s2 := vp_cam.unproject_position(ghost._shark.global_position)
			entry["shark_px"] = [roundi(s2.x), roundi(s2.y)]
	_trace.append(entry)


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _jsonable(value: Variant) -> Variant:
	if value is Vector3:
		return _v(value)
	if value is Dictionary:
		var d := {}
		for k: Variant in value:
			d[str(k)] = _jsonable(value[k])
		return d
	if value is Array:
		return (value as Array).map(func(x: Variant) -> Variant: return _jsonable(x))
	if value is float:
		return snappedf(value, 0.001)
	return value


func _cleanup() -> void:
	get_tree().physics_interpolation = false


func _check() -> void:
	report["trace"] = _trace
	report["windup_frame"] = _windup_frame
	report["charging_frame"] = _charging_frame
	report["hit_frame"] = _hit_frame
	if _hit_frame < 0:
		failures.append("突進が P1 に当たらなかった")
	if gs.p2_alive:
		failures.append("P2 が脱落していない")

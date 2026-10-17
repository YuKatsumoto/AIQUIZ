extends Node

## ヘリの後ろの仕切り（コルクボード）に貼る写真 4 枚を、本物のステージ・観客・ハテナ・プレイヤー（ブロックマン）で撮る。
##   Godot --path . --resolution 768x768 --script res://tests/heli_board_photos_bootstrap.gd [-- only=goal,shark,wave,hatena] [preview]
## 出力：assets/vehicles/helicopter_boarding/source/textures/board_photos/<名前>.png（正方形）。
## ヘリのビルダー（hb_textures.py）がアトラスへ詰めるので、撮り直したらヘリを作り直す（assets/vehicles/helicopter_boarding/README.md）。
##   goal   ゴールで肩組み（P1・王冠、ハテナはチェッカーの旗。後ろにゴールのスタンドと電光掲示板）
##   shark  幽霊ザメに二人乗り（P2・海賊の帽子が鞍で手を振り、ハテナは背びれにしがみつく。海の上、後ろに右のスタンド）
##   wave   客席でウェーブ（P1・カエルの帽子とハテナが両手を上げる。右のスタンドの観客もウェーブ）
##   hatena 「？」のポーズ（P2・角帽が頭をかき、ハテナはほおに手を当てて首をかしげる。後ろにヘリ）

const StageScript = preload("res://scripts/world/stage_environment.gd")
const CrowdScript = preload("res://scripts/world/grandstand_crowd.gd")
const MASCOT_GLB := "res://assets/characters/aiquiz_mascot/mascot_model.glb"
const PILOT_GLB := "res://assets/characters/aiquiz_mascot/mascot_pilot.glb"
const SHARK_GLB := "res://assets/shark/shark_swim.glb"
const OUT := "res://assets/vehicles/helicopter_boarding/source/textures/board_photos/"
const PREVIEW_OUT := "res://artifacts/heli_board_photos/"
const NAMES := ["goal", "shark", "wave", "hatena"]
const DT := 1.0 / 60.0
## ブロックマンの足の裏は、根（build_player_skeleton の親）から 1.32 m 下。
const PLAYER_FOOT := 1.32

## ---------------------------------------------------------------- 「はてな？」の写真のプレイヤーのポーズ（ここを書き換える）
## 1 行が「関節・回す向き・角度（度）」。上の行から順に回す（肩を回すと、その先のひじ・手も一緒に動く）。
## 何もしない姿勢は「気をつけ」（両腕を下ろしてまっすぐ立つ）。プレイヤーはカメラを向いている。
## 関節（左右は写真で見たときの向き）
##   "spine" 胸から上   "head_pivot" 頭   "neck" 首
##   "l_shoulder" "l_elbow" "l_wrist"  画面の左の腕（肩・ひじ・手首）
##   "r_shoulder" "r_elbow" "r_wrist"  画面の右の腕
##   "l_hip" "l_knee" "l_ankle"        画面の左の脚（もも・ひざ・足首）  "r_hip" "r_knee" "r_ankle" 画面の右の脚
## 向き
##   "z" 写真の中でくるっと回す（+ で反時計回り。下ろした右腕は + で横へ上がり、左腕は − で横へ上がる。頭は + で画面の左へかしげる）
##   "x" 前後に振る（− で前＝カメラの方へ。腕・ももを前へ出すときは −）
##   "y" 上から見てひねる（+ で画面の右側が奥へ）
const HATENA_PLAYER_POSE := [
	["spine", "z", -3.0],
	["spine", "y", -12.0],
	["head_pivot", "z", 8.0],
	["head_pivot", "y", -8.0],
	["l_shoulder", "z", -84.0],
	["l_shoulder", "x", -40.0],
	["l_elbow", "y", 142.0],
	["l_elbow", "z", 8.0],
	["r_shoulder", "z", 8.0],
	["r_shoulder", "x", -8.0],
	["r_elbow", "x", -25.0],
	["r_elbow", "z", -38.0],
	["l_hip", "z", -15.0],
	["l_knee", "x", 8.0],
	["l_ankle", "x", 50.0],
	["r_hip", "z", 17.0],
	["r_hip", "x", -10.0],
	["r_knee", "x", 30.0],
	["r_ankle", "x", 50.0],
]
const AXES := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}


var stage: Node3D
var stand: GoalStand
var state: QuizGameState
var cues: CrowdCues
var camera: Camera3D
var props: Node3D
var report := {}
var only: PackedStringArray = []
## 調整用の値（`-- key=value`）。_v(key, 既定値) で読む。
var vars := {}
## preview：本物の写真（OUT）を書き換えず、artifacts/heli_board_photos/preview_<名前>.png に撮る。
var preview := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.trim_prefix("only=").split(",")
		elif arg == "preview":
			preview = true
		elif "=" in arg:
			vars[arg.get_slice("=", 0)] = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_OUT if preview else OUT))
	_build()
	await _frames(30)
	state.game_state = Constants.STATE_COUNTDOWN
	await _frames(40)
	state.game_state = Constants.STATE_PLAYING
	await _frames(20)
	for name: String in NAMES:
		if not only.is_empty() and not only.has(name):
			continue
		props = Node3D.new()
		props.name = "Photo_" + name
		add_child(props)
		match name:
			"goal":
				await _photo_goal()
			"shark":
				await _photo_shark()
			"wave":
				await _photo_wave()
			"hatena":
				await _photo_hatena()
		props.queue_free()
		await get_tree().process_frame
	print("HELI_BOARD_PHOTOS ", JSON.stringify(report))
	get_tree().quit()


func _build() -> void:
	stage = StageScript.new()
	add_child(stage)
	var config: Dictionary = stage.gameplay_build_config()
	config.floor_center_z = 60.0
	config.floor_length = 150.0
	stage.build(config)
	stand = GoalStand.new()
	add_child(stand)
	stand.setup("high")
	stand.position = Vector3(0.0, StageConstants.FLOOR_TOP_Y, 135.0 + GoalStand.GOAL_OFFSET)
	state = QuizGameState.new()
	state.num_players = 2
	state.mode = Constants.MODE_TEN
	state.game_state = Constants.STATE_WAITING_START
	state.p1_emote_slots = [EmoteData.EMOTE_YMCA]
	state.p2_emote_slots = [EmoteData.EMOTE_GANGNAM]
	cues = CrowdCues.new()
	camera = Camera3D.new()
	camera.far = 3000.0
	add_child(camera)
	camera.make_current()
	CrowdScript.prepare_dances(EmoteData.EMOTE_YMCA, EmoteData.EMOTE_GANGNAM)


## One game frame of the crowd, as game_world._update_crowd() runs it.
func _step() -> void:
	var stands := stage.get_node("Grandstands") as Node3D
	cues.course_z = stands.global_position.z
	cues.goal_course = stand.global_position.z - cues.course_z
	cues.update(DT, state, stand.side_crowd_reaction(), null)
	stand.update_stand(DT, state, null, camera, true, cues)
	CrowdScript.follow_cues(cues)
	CrowdScript.update_mascots(cues, DT, camera)


func _v(key: String, fallback: float) -> float:
	return float(vars[key]) if vars.has(key) else fallback


func _frames(count: int) -> void:
	for _i in range(count):
		_step()
		await get_tree().process_frame


func _shot(name: String, eye: Vector3, target: Vector3, fov: float) -> void:
	camera.fov = fov
	camera.look_at_from_position(eye, target)
	for _i in range(4):
		_step()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(PREVIEW_OUT + "preview_" + name + ".png" if preview else OUT + name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	report[name] = path


# ---------------------------------------------------------------- 人物

## ブロックマン（ゲームのプレイヤー）。feet は足の裏、yaw は向き（0 で +Z を向く）。
func _player(is_p1: bool, hat: int, feet: Vector3, yaw_deg: float) -> Dictionary:
	var root := Node3D.new()
	props.add_child(root)
	root.position = feet + Vector3(0.0, PLAYER_FOOT, 0.0)
	root.rotation_degrees.y = yaw_deg
	var parts: Dictionary = EmoteBlockmanPreview.build_player_skeleton(is_p1, root, hat)
	parts["root"] = root
	return parts


## 関節を、人物の向きの軸（+X＝画面の右の腕「r_」の側、+Y 上、+Z 前）のまわりに回す（世界で回す）。
func _turn(parts: Dictionary, joint: String, axis: Vector3, deg: float) -> void:
	var node := parts[joint] as Node3D
	var root := parts["root"] as Node3D
	var a := (root.global_basis * axis).normalized()
	node.global_basis = Basis(a, deg_to_rad(deg)) * node.global_basis


## ハテナ。clip が空なら初期姿勢。
func _hatena(feet: Vector3, yaw_deg: float, glb := "", clip := "", t := 0.0) -> Dictionary:
	var model := (load(MASCOT_GLB) as PackedScene).instantiate() as Node3D
	props.add_child(model)
	model.position = feet
	model.rotation_degrees.y = yaw_deg
	var skel := model.get_node("Rig/Skeleton3D") as Skeleton3D
	if clip != "":
		var source := (load(glb) as PackedScene).instantiate()
		var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var library := AnimationLibrary.new()
		for clip_name: StringName in source_player.get_animation_list():
			library.add_animation(clip_name, source_player.get_animation(clip_name).duplicate(true))
		source.free()
		var player := AnimationPlayer.new()
		model.add_child(player)
		player.root_node = NodePath("..")
		player.add_animation_library("", library)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.play(clip)
		player.seek(t, true)
	return {"model": model, "skel": skel}


## ハテナの骨を、ハテナの向きの軸（+X＝「.L」の側、+Y 上、+Z 前）のまわりに回す（骨の根もとで、世界で回す）。
func _bend(h: Dictionary, bone: String, axis: Vector3, deg: float) -> void:
	var skel := h.skel as Skeleton3D
	var i := skel.find_bone(bone)
	var a := (skel.global_basis.orthonormalized().inverse() * ((h.model as Node3D).global_basis * axis)).normalized()
	var pose := skel.get_bone_global_pose(i)
	var basis := Basis(a, deg_to_rad(deg)) * pose.basis
	var p := skel.get_bone_parent(i)
	var parent_basis := skel.get_bone_global_pose(p).basis if p >= 0 else Basis.IDENTITY
	skel.set_bone_pose_rotation(i, (parent_basis.inverse() * basis).get_rotation_quaternion())


## 骨の先（手のひらのあたり）の世界の位置。
func _bone_tip(h: Dictionary, bone: String, length: float) -> Vector3:
	var skel := h.skel as Skeleton3D
	var pose := skel.get_bone_global_pose(skel.find_bone(bone))
	return skel.global_transform * (pose.origin + pose.basis.y.normalized() * length)


## チェッカーの旗（棒の下を hand、上へ up の向き）。
func _checkered_flag(hand: Vector3, up: Vector3, side: Vector3) -> void:
	up = up.normalized()
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.022
	cyl.bottom_radius = 0.022
	cyl.height = 1.1
	pole.mesh = cyl
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.92, 0.92, 0.9)
	pole_mat.roughness = 0.4
	pole.material_override = pole_mat
	props.add_child(pole)
	var y := up
	var x := side.normalized().slide(y).normalized()
	var z := x.cross(y).normalized()
	pole.global_transform = Transform3D(Basis(x, y, z), hand + y * 0.4)
	var img := Image.create(96, 64, false, Image.FORMAT_RGB8)
	for py in 64:
		for px in 96:
			img.set_pixel(px, py, Color(0.06, 0.06, 0.07) if (px / 16 + py / 16) % 2 == 0 else Color(0.97, 0.97, 0.95))
	var flag := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.66, 0.44)
	flag.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	flag.material_override = mat
	props.add_child(flag)
	flag.global_transform = Transform3D(Basis(x, y, z).rotated(y, deg_to_rad(-12.0)), hand + y * 0.72 + x * 0.33)


# ---------------------------------------------------------------- 写真

## ゴールで肩組み：ゴールのスタンドを背に、画面の左に P1（王冠）、右にハテナ（チェッカーの旗）。
func _photo_goal() -> void:
	stand.mascot.visible = false
	var floor := StageConstants.FLOOR_TOP_Y
	var z := 124.0
	# 2 人はカメラ（-Z の側）を向く。カメラから見て左は +X
	var p := _player(true, HatData.HAT_CROWN, Vector3(0.55, floor, z), 180.0)
	_turn(p, "l_shoulder", Vector3(0, 0, 1), -150.0)
	_turn(p, "l_elbow", Vector3(0, 0, 1), -35.0)
	_turn(p, "r_shoulder", Vector3(0, 0, 1), 78.0)
	_turn(p, "r_shoulder", Vector3(0, 1, 0), 18.0)
	_turn(p, "r_elbow", Vector3(0, 0, 1), -35.0)
	_turn(p, "head_pivot", Vector3(0, 0, 1), -8.0)
	_turn(p, "l_hip", Vector3(0, 0, 1), -6.0)
	_turn(p, "r_hip", Vector3(0, 0, 1), 6.0)
	var h := _hatena(Vector3(-0.6, floor, z - 0.05), 180.0)
	_bend(h, "DEF-head", Vector3(0, 0, 1), 8.0)
	_bend(h, "DEF-upper_arm.R", Vector3(0, 0, 1), -40.0)
	_bend(h, "DEF-upper_arm.R", Vector3(0, 1, 0), -25.0)
	_bend(h, "DEF-upper_arm.L", Vector3(0, 0, 1), 115.0)
	_bend(h, "DEF-forearm.L", Vector3(0, 0, 1), 20.0)
	var model := h.model as Node3D
	_checkered_flag(_bone_tip(h, "DEF-hand.L", 0.05), model.global_basis * Vector3(0.35, 1.0, 0.0), model.global_basis * Vector3(1, 0, 0))
	await _frames(10)
	await _shot("goal", Vector3(0.0, floor + 1.35, z - 4.4), Vector3(0.0, floor + 1.75, z + 4.0), 50.0)


## 幽霊ザメに二人乗り：海の上に浮くサメ（鞍とハンドルつき）に P2（海賊の帽子）、後ろにハテナ。
func _photo_shark() -> void:
	var floor := StageConstants.FLOOR_TOP_Y
	var shark := (load(SHARK_GLB) as PackedScene).instantiate() as Node3D
	props.add_child(shark)
	shark.scale = Vector3.ONE * _v("shark_scale", 0.72)
	shark.position = Vector3(_v("shark_x", 16.0), floor + _v("shark_y", 3.2), 40.0)
	shark.rotation_degrees = Vector3(0.0, _v("shark_yaw", 90.0), 0.0)
	var anim := shark.get_node("AnimationPlayer") as AnimationPlayer
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.play(&"SharkSwim")
	anim.seek(_v("shark_t", 0.0), true)
	await get_tree().process_frame
	# 鞍の口（GhostMountSocket）：+Z がサメの頭の向き（+X は横）
	var seat := (shark.find_child("GhostMountSocket", true, false) as Node3D).global_transform
	var up := Vector3.UP
	var fwd := seat.basis.z.slide(up).normalized()
	var right := fwd.cross(up).normalized()
	var yaw := rad_to_deg(atan2(fwd.x, fwd.z))
	var p := _player(false, HatData.HAT_PIRATE, seat.origin + up * (_v("ride_y", 0.0) - 1.02), yaw)
	_turn(p, "l_hip", Vector3(0, 0, 1), -22.0)
	_turn(p, "r_hip", Vector3(0, 0, 1), 22.0)
	_turn(p, "l_hip", Vector3(1, 0, 0), -75.0)
	_turn(p, "r_hip", Vector3(1, 0, 0), -75.0)
	_turn(p, "l_knee", Vector3(1, 0, 0), 80.0)
	_turn(p, "r_knee", Vector3(1, 0, 0), 80.0)
	_turn(p, "spine", Vector3(1, 0, 0), 10.0)
	# 奥の手（l_）でハンドルを握り、手前の手（r_）を振る
	_turn(p, "l_shoulder", Vector3(1, 0, 0), -70.0)
	_turn(p, "l_shoulder", Vector3(0, 0, 1), 12.0)
	_turn(p, "r_shoulder", Vector3(0, 0, 1), 150.0)
	_turn(p, "r_elbow", Vector3(0, 0, 1), 25.0)
	_turn(p, "head_pivot", Vector3(0, 1, 0), _v("rider_look", -35.0))
	# ハテナは背びれのうしろで、背びれにしがみつく
	var behind := seat.origin - fwd * _v("hatena_back", 1.55)
	var h := _hatena(behind + up * (_v("hatena_y", 0.0) - 0.78), yaw + _v("hatena_yaw", 0.0), PILOT_GLB, "Pilot_Steer", _v("steer_t", 0.0))
	_bend(h, "DEF-head", Vector3(0, 0, 1), _v("hatena_tilt", -10.0))
	await _frames(10)
	var target := seat.origin + up * 0.3 - fwd * _v("aim_back", 0.5)
	var eye := target + fwd * _v("cam_f", 1.4) - right * _v("cam_r", 7.3) + up * _v("cam_u", 0.5)
	await _shot("shark", eye, target, _v("fov", 44.0))


## 客席でウェーブ：右のスタンドのマスコットの位置に、P1（カエルの帽子）とハテナ。2 人とも両手を上げる。
func _photo_wave() -> void:
	var side := stage.get_node("Grandstands/GrandstandRight") as Node3D
	var mascot := side.get_node("Spectators").mascot as Node3D
	var at := mascot.global_position
	mascot.visible = false
	cues.wave_started = cues.clock
	# 2 人はフィールド（-X）を向く。カメラから見て左は -Z
	var p := _player(true, HatData.HAT_FROG, at + Vector3(0.0, 0.0, -0.62), -90.0)
	_turn(p, "l_shoulder", Vector3(0, 0, 1), -158.0)
	_turn(p, "r_shoulder", Vector3(0, 0, 1), 158.0)
	_turn(p, "l_elbow", Vector3(0, 0, 1), -12.0)
	_turn(p, "r_elbow", Vector3(0, 0, 1), 12.0)
	_turn(p, "head_pivot", Vector3(1, 0, 0), -8.0)
	var h := _hatena(at + Vector3(0.0, 0.0, 0.62), -90.0)
	_bend(h, "DEF-upper_arm.L", Vector3(0, 0, 1), _v("hu", 92.0))
	_bend(h, "DEF-upper_arm.R", Vector3(0, 0, 1), -_v("hu", 92.0))
	_bend(h, "DEF-forearm.L", Vector3(0, 0, 1), 25.0)
	_bend(h, "DEF-forearm.R", Vector3(0, 0, 1), -25.0)
	await _frames(int(_v("wave_frames", 35.0)))
	await _shot("wave", at + Vector3(-_v("wave_cam_d", 5.0), _v("wave_cam_u", 1.6), _v("wave_cam_z", 0.0)), at + Vector3(0.0, 1.3, 0.0), _v("fov", 50.0))
	cues.wave_started = -INF


## 「？」のポーズ：ヘリ（横向き）の前で、P2（角帽）とハテナが首をかしげて考える。
func _photo_hatena() -> void:
	var floor := StageConstants.FLOOR_TOP_Y
	var z := 22.0
	var heli := OnlineHeliportHelicopter.new()
	props.add_child(heli)
	heli.setup(PlayerController.P1_BODY, false, false)
	heli.position = Vector3(_v("heli_x", 0.0), floor + 1.75, z + 7.5)
	heli.rotation_degrees.y = 90.0
	# 2 人はカメラ（-Z の側）を向く。カメラから見て左は +X
	var p := _player(false, HatData.HAT_GRADUATION_CAP, Vector3(0.62, floor, z), 180.0)
	for row: Array in HATENA_PLAYER_POSE:
		_turn(p, String(row[0]), AXES[row[1]], float(row[2]))
	var h := _hatena(Vector3(-0.62, floor, z), 180.0)
	_bend(h, "DEF-head", Vector3(0, 0, 1), _v("h_tilt", 14.0))
	_bend(h, "DEF-upper_arm.R", Vector3(0, 0, 1), _v("hr_z", -75.0))
	_bend(h, "DEF-upper_arm.R", Vector3(0, 1, 0), _v("hr_y", 55.0))
	_bend(h, "DEF-forearm.R", Vector3(0, 1, 0), _v("hf_y", 45.0))
	_bend(h, "DEF-forearm.L", Vector3(0, 0, 1), -40.0)
	await _frames(10)
	await _shot("hatena", Vector3(0.0, floor + _v("q_cam_u", 0.3), z - _v("q_cam_d", 4.6)), Vector3(0.0, floor + 1.25, z), _v("fov", 42.0))

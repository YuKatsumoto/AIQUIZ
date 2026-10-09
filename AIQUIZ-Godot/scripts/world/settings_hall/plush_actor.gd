extends RefCounted

## 地下神殿のゴドーくん 1 体を動かす部品（授業の進行役 lecture_director.gd が毎フレーム update する）。
## 体の動き（クリップ）は Blender で作った NLA のクリップ（T_/S_/P_/G_、build_lecture_set.py）。ここでは:
## - クリップ: ループ（loop）と 1 回きり（once。終わったら土台のループへ戻る）を 0.25 秒で混ぜてつなぐ
## - 移動: walk_to / side_to で足元（root の位置）を動かし、向きをなめらかに回す（歩きのクリップは足踏み）
## - 右手の IK: 手先（チョークの先）を set_tip() の点に合わせる（TwoBoneIK3D で手首、LookAtModifier3D で手の向き）
## - まばたき・目の表情: ぬいぐるみのテクスチャの目の 4 枠（開・開・半目・閉じ）を差し替えるシェーダー
## 位置はすべてセット（LectureSet）のローカル座標。向き yaw は度で 0 = +Z（黒板）を向く。

const BLEND := 0.25
const WALK_SPEED := 0.85
const SIDE_SPEED := 0.42
const TURN_SPEED := 5.0
## 手首から手先（ミトンの先 0.29 m + チョークの出ている分 7 cm）まで。リグの手のボーン（DEF-hand）の +Y が手の向き。
const HAND_TIP := 0.36
## 手首から IK で合わせる先までの長さ（ふだんは HAND_TIP、伸ばした指し棒でなぞるときは指し棒の先）。
var tip_length := 0.36
## 腕（上腕 + 前腕）の長さ。手首はこれ以上肩から離せない。
const ARM_REACH := 0.29
## 書くときの肩から手首までの長さ（腕を少し曲げる）。
const ARM_BENT := 0.24
const ARM_R := ["DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R"]
const ARM_L := ["DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L"]
## 1 回きりではなくループで回すクリップ（Blender の lsb_anim_* で「ループ」と書いたもの）。
const LOOPS := [
	"T_Idle", "T_IdleLook", "T_Walk", "T_SideStep", "T_WriteStance", "T_WriteTiptoe", "T_JumpWrite", "T_WipeLoop",
	"T_WipeMessy", "T_Explain", "T_SitGrade", "T_DozeStand",
	"S_SitIdle", "S_LookBoard", "S_CopyNotes", "S_FastWrite", "S_DozeDrift", "S_SleepSlumped", "S_Frenzy", "S_Clap",
	"S_RaiseHand", "S_RaiseHandEager",
	"P_Clipboard", "P_FanSelf",
	"G_Idle", "G_Walk", "G_Run", "G_Clap", "G_Chat", "G_JumpWrite",
	"Teach", "TakeNotes", "RaiseHand", "Doze", "Practice",
]

## ぬいぐるみの材質: 元の GK_Plush（アルベドだけ、粗さ 0.83、両面、Burley）とまったく同じ見た目に、目の差し替えだけを足す。
## テクスチャの上の段（v < 0.31）は目の 4 枠: 0 = 左目（開）、1 = 右目（開）、2 = 半目、3 = 閉じた目。
const PLUSH_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float roughness_value = 0.83;
instance uniform float eyes = 0.0;
void fragment() {
	vec2 uv = UV;
	if (eyes > 0.25 && uv.y < 0.31 && uv.x < 0.5) {
		float cell = floor(uv.x * 4.0);
		float local_u = uv.x - cell * 0.25;
		if (cell > 0.5) {
			local_u = 0.25 - local_u;
		}
		float target_cell = eyes > 1.5 ? 3.0 : 2.0;
		uv.x = target_cell * 0.25 + clamp(local_u, 0.004, 0.246);
	}
	ALBEDO = texture(albedo_tex, uv).rgb;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.5;
}
"""
const EYES := {"open": 0.0, "half": 1.0, "closed": 2.0}

static var _plush_materials: Dictionary = {}

var key := ""
var root: Node3D = null
var player: AnimationPlayer = null
var skeleton: Skeleton3D = null
var base_clip := ""
var current := ""
var eyes_mode := "open"
var blinking := true
## 歩き・横歩きのクリップ（先生は T_、ほかは G_）。
var walk_clip := "G_Walk"
var side_clip := "G_Walk"
var idle_clip := "G_Idle"

var _clips: Dictionary = {}       # 素の名前 -> AnimationPlayer の名前
var _once := false
var _goal := Vector3.ZERO
var _moving := false
var _sidestep := false
var _speed := WALK_SPEED
var _yaw_goal := 0.0
var _face_after := NAN
var _after_move := ""
var _timed_left := 0.0
## 足元の高さ（踏み台に乗ると上がる）と、1 画ごとの小さな上下（ばね）。
var stand_y := 0.0
var _bob := 0.0
var _bob_v := 0.0
var _timed_back := ""
var _rng := RandomNumberGenerator.new()
var _plush_meshes: Array[MeshInstance3D] = []
var _blink_left := 0.0
var _blink_hold := 0.0
var _eye_value := 0.0

# 右手の IK
var _set: Node3D = null
var _ik: TwoBoneIK3D = null
var _look: LookAtModifier3D = null
var _wrist: Marker3D = null
var _tip: Marker3D = null
var _pole: Marker3D = null
var _ik_goal := 0.0
var _ik_fade := 0.25
var ik_weight := 0.0
var tip_point := Vector3.ZERO     # 手先を合わせる点（セットのローカル）
## 左手の IK（三角定規を押さえる・コンパスの中心を押さえる・肩車でつかまる）。
var _ik_l: TwoBoneIK3D = null
var _look_l: LookAtModifier3D = null
var _wrist_l: Marker3D = null
var _tip_l: Marker3D = null
var _pole_l: Marker3D = null
var _ik_l_goal := 0.0
var ik_l_weight := 0.0
var tip_point_l := Vector3.ZERO
var _bone_idx: Dictionary = {}
var _held: Dictionary = {}         # "R"/"L" -> Node3D（手に持たせた小道具）
## IK などの仕上げのあとの手のボーンの姿勢（スケルトンの global 座標）。get_bone_global_pose は仕上げ前の
## 姿勢しか返さないので、skeleton_updated のときに写しておく。
var _final_pose: Dictionary = {}
## 伸縮式の指し棒（先生だけ）: Blender の HERO_<name>_Pointer（右手に固定）は隠して、こちらで手に持たせる。
## チョークや黒板消しを持つ間は縮めて左手に、指すときは右手で伸ばす。
const POINTER_SHORT := 0.2
const POINTER_LONG := 0.82
const POINTER_GRIP := 0.08
var _pointer: Node3D = null
var _pointer_shaft: MeshInstance3D = null
var _pointer_tip: MeshInstance3D = null
var _pointer_side := ""
var _pointer_len := POINTER_SHORT
var _pointer_goal := POINTER_SHORT
## 体ごと相手のほうへ向く（LookAtModifier3D を Body に、ヨーだけ ±35°）。
var _body_look: LookAtModifier3D = null
var _look_target: Marker3D = null
var _look_goal := 0.0
var look_weight := 0.0
## 待機を続けていると、ときどき別の待機（見回し・首かしげ）を挟む。
var _idle_time := 0.0
var _idle_next := 10.0
## 居眠り役の頭の上の Zzz（リグの "Zzz" ボーン）: 0 = 隠す、1 = 出す（眠っている）。
var zzz := 0.0
var _zzz_shown := -1.0
var _zzz_idx := -1
var _zzz_rest := Transform3D.IDENTITY


func _init(actor_key: String, character_root: Node3D, set_root: Node3D, seed_value: int) -> void:
	key = actor_key
	root = character_root
	_set = set_root
	_rng.seed = seed_value
	player = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for node: Node in root.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if player != null:
		for name: StringName in player.get_animation_list():
			var plain := str(name).get_file()
			_clips[plain] = str(name)
			var animation := player.get_animation(name)
			if animation != null:
				animation.loop_mode = Animation.LOOP_LINEAR if plain in LOOPS else Animation.LOOP_NONE
	if skeleton != null:
		for bone in ARM_R + ARM_L + ["Root", "Body", "DEF-head"]:
			_bone_idx[bone] = skeleton.find_bone(bone)
		skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_yaw_goal = root.rotation.y
	if has_clip("T_Walk"):
		walk_clip = "T_Walk"
		side_clip = "T_SideStep"
		idle_clip = "T_Idle"
	_setup_face()
	_blink_left = _rng.randf_range(1.0, 4.0)
	if skeleton != null:
		_zzz_idx = skeleton.find_bone("Zzz")
		if _zzz_idx >= 0:
			_zzz_rest = skeleton.get_bone_rest(_zzz_idx)
			_strip_bone_tracks("Zzz")


## glTF の書き出しは全部のボーンにキーを入れるので、ここで動かすボーン（Zzz）の軌跡はクリップから外す
## （1 本でも残っていると、ミキサーが毎フレーム休止の姿勢へ戻してしまう）。
func _strip_bone_tracks(bone: String) -> void:
	if player == null:
		return
	for name: StringName in player.get_animation_list():
		var animation := player.get_animation(name)
		for i in range(animation.get_track_count() - 1, -1, -1):
			if str(animation.track_get_path(i)).ends_with(":" + bone):
				animation.remove_track(i)


func has_clip(clip: String) -> bool:
	return _clips.has(clip)


func clip_length(clip: String) -> float:
	if player == null or not _clips.has(clip):
		return 0.0
	return player.get_animation(_clips[clip]).length


# ------------------------------------------------------------------ clips

## ループのクリップを土台にして流す（1 回きりが終わったら戻る先）。
func loop(clip: String, blend := BLEND, speed := 1.0) -> void:
	if not _clips.has(clip):
		return
	base_clip = clip
	_once = false
	if current != clip:
		_play(clip, blend, speed)


## 1 回きりのクリップ。終わったら土台のループ（then_base を指定すればそれ）へ戻る。長さ（秒）を返す。
func once(clip: String, then_base := "", blend := BLEND, speed := 1.0) -> float:
	if not _clips.has(clip):
		return 0.0
	if then_base != "":
		base_clip = then_base
	_timed_left = 0.0
	_once = true
	_play(clip, blend, speed)
	return clip_length(clip) / maxf(0.05, speed)


## ループのクリップを secs 秒だけ流してから then_base（省くと今の土台）へ戻る（拍手・おしゃべりなど）。
func loop_for(clip: String, secs: float, then_base := "") -> void:
	if not _clips.has(clip):
		return
	_timed_back = then_base if then_base != "" else (base_clip if base_clip != clip else idle_clip)
	_timed_left = secs
	_once = false
	base_clip = clip
	if current != clip:
		_play(clip, BLEND, 1.0)


## 動きの速さ（1 = ふつう。写すのを先生の 1 画に合わせるとき止め気味にする）。
func set_speed(scale: float) -> void:
	if player != null and not is_equal_approx(player.speed_scale, scale):
		player.speed_scale = scale


func is_busy() -> bool:
	return _moving or _once or _timed_left > 0.0 or absf(angle_difference(root.rotation.y, _yaw_goal)) > 0.02


func is_moving() -> bool:
	return _moving


func _play(clip: String, blend: float, speed: float) -> void:
	current = clip
	player.play(_clips[clip], blend, speed)


# ------------------------------------------------------------------ movement

## 歩いて at へ行き、着いたら face_yaw（度、NAN なら進んだ向きのまま）を向く。着いたら then_clip（既定は待機）。
func walk_to(at: Vector3, face_yaw := NAN, then_clip := "", clip := "", speed := 0.0) -> void:
	_goal = Vector3(at.x, root.position.y, at.z)
	_moving = root.position.distance_to(_goal) > 0.02
	_sidestep = false
	_speed = (speed if speed > 0.0 else WALK_SPEED) * _rng.randf_range(0.95, 1.05)
	_face_after = face_yaw
	_after_move = then_clip
	if _moving:
		loop(clip if clip != "" and has_clip(clip) else walk_clip, 0.2)
	elif not is_nan(face_yaw):
		face(face_yaw)


## 向きを変えずに横歩きで at へ（黒板の前で書く位置を変える）。speed 0 なら既定の速さ。
func side_to(at: Vector3, then_clip := "", speed := 0.0) -> void:
	_goal = Vector3(at.x, root.position.y, at.z)
	_moving = root.position.distance_to(_goal) > 0.01
	_sidestep = true
	_speed = speed if speed > 0.0 else SIDE_SPEED
	_face_after = NAN
	_after_move = then_clip
	if _moving:
		loop(side_clip, 0.15)


## 体を小さく沈める（1 画ごとの書く拍子、着地、驚き）。amount は沈む速さ（m/s）。
func kick(amount: float) -> void:
	_bob_v -= amount


func face(yaw_deg: float) -> void:
	_yaw_goal = deg_to_rad(yaw_deg)


func face_point(p: Vector3) -> void:
	var d := p - root.position
	if Vector2(d.x, d.z).length() > 0.01:
		_yaw_goal = atan2(d.x, d.z)


func yaw_deg() -> float:
	return rad_to_deg(root.rotation.y)


func update(delta: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	if _moving:
		var d := _goal - root.position
		d.y = 0.0
		var dist := d.length()
		var step := _speed * delta
		# 歩き出しと止まる前は少しゆっくり
		if dist < 0.25:
			step *= lerpf(0.55, 1.0, dist / 0.25)
		if dist <= step:
			root.position = _goal
			_moving = false
			if not is_nan(_face_after):
				face(_face_after)
			var next := _after_move if _after_move != "" else (idle_clip if base_clip in [walk_clip, side_clip, "G_Run"] else base_clip)
			loop(next, 0.25)
		else:
			root.position += d / dist * step
			if not _sidestep:
				_yaw_goal = atan2(d.x, d.z)
	var dyaw := angle_difference(root.rotation.y, _yaw_goal)
	if absf(dyaw) > 0.0005:
		root.rotation.y += clampf(dyaw, -TURN_SPEED * delta, TURN_SPEED * delta)
	if _timed_left > 0.0:
		_timed_left -= delta
		if _timed_left <= 0.0:
			loop(_timed_back, 0.3)
	if _once and player != null:
		if not player.is_playing() or str(player.current_animation).get_file() != current:
			_once = false
			var back := base_clip if base_clip != "" else idle_clip
			current = ""
			loop(back, 0.3)
	# 小さな上下（ばね）: kick() で沈み、すぐ戻る。沈むときはぽよんと横へつぶれ、跳ね返ると縦に伸びる
	_bob_v += (-180.0 * _bob - 16.0 * _bob_v) * delta
	_bob += _bob_v * delta
	root.position.y = stand_y + _bob
	var squash := clampf(-_bob * 3.2, -0.1, 0.12)
	root.scale = Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5)
	_update_idle(delta)
	if _body_look != null:
		look_weight = move_toward(look_weight, _look_goal, delta * 2.0)
		_body_look.influence = smoothstep(0.0, 1.0, look_weight) * 0.75
	_update_eyes(delta)
	_update_ik(delta)
	_update_zzz(delta)
	_update_pointer(delta)


# ------------------------------------------------------------------ eyes

func _setup_face() -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var replaced := false
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null:
				continue
			var material := _plush_material(source)
			mesh_instance.set_surface_override_material(surface, material)
			replaced = true
		if replaced:
			_plush_meshes.append(mesh_instance)


## ぬいぐるみの材質の使い回しを捨てる（講義セットを閉じたとき）。
static func clear_material_cache() -> void:
	_plush_materials.clear()


static func _plush_material(source: BaseMaterial3D) -> ShaderMaterial:
	var texture := source.albedo_texture
	var cache_key := texture.get_rid().get_id()
	if _plush_materials.has(cache_key):
		return _plush_materials[cache_key]
	var shader := Shader.new()
	shader.code = PLUSH_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_tex", texture)
	material.set_shader_parameter("roughness_value", source.roughness)
	_plush_materials[cache_key] = material
	return material


## 目の表情: "open"（まばたきあり）/ "half"（眠そう）/ "closed"（寝ている・笑っている）。
func set_eyes(mode: String) -> void:
	eyes_mode = mode


## すぐに 1 回まばたきする（驚いたとき、チョークがきしんだときなど）。
func blink() -> void:
	_blink_left = 0.0


func _update_eyes(delta: float) -> void:
	var value := float(EYES.get(eyes_mode, 0.0))
	if blinking and eyes_mode != "closed":
		_blink_left -= delta
		if _blink_left <= 0.0:
			_blink_hold = 0.12
			# たまに 2 回続けて
			_blink_left = _rng.randf_range(2.2, 5.5) if _rng.randf() > 0.15 else 0.28
		if _blink_hold > 0.0:
			_blink_hold -= delta
			value = 2.0 if _blink_hold > 0.04 else maxf(value, 1.0)
	if not is_equal_approx(value, _eye_value):
		_eye_value = value
		for mesh_instance in _plush_meshes:
			if is_instance_valid(mesh_instance):
				mesh_instance.set_instance_shader_parameter("eyes", value)


func _update_zzz(delta: float) -> void:
	if _zzz_idx < 0:
		return
	_zzz_shown = move_toward(maxf(_zzz_shown, 0.0), zzz, delta * 1.5)
	var t := Time.get_ticks_msec() / 1000.0
	# 寝息に合わせて少し浮き沈みし、ゆっくり揺れる
	var bob := Vector3(0.02 * sin(t * 0.9), 0.04 * sin(t * 1.6), 0.0)
	var s := maxf(0.001, _zzz_shown * (1.0 + 0.06 * sin(t * 1.6)))
	skeleton.set_bone_pose_position(_zzz_idx, _zzz_rest.origin + bob * _zzz_shown)
	skeleton.set_bone_pose_rotation(_zzz_idx, _zzz_rest.basis.get_rotation_quaternion())
	skeleton.set_bone_pose_scale(_zzz_idx, Vector3.ONE * s)


# ------------------------------------------------------------------ springs（項目 112）

## 揺れもの: 蝶ネクタイ（Tie）と帽子のつば（CapBrim）のボーンがあれば、SpringBoneSimulator3D で揺らす。
## 指し棒の先は _update_pointer のばねで揺れる。
const SPRINGS := {
	"Tie": {"length": 0.1, "stiffness": 1.4, "drag": 0.3, "gravity": 0.5},
	"CapBrim": {"length": 0.24, "stiffness": 2.4, "drag": 0.38, "gravity": 0.25},
}


func setup_springs() -> void:
	if skeleton == null:
		return
	var found: Array = []
	for bone: String in SPRINGS:
		if skeleton.find_bone(bone) >= 0:
			found.append(bone)
	if found.is_empty():
		return
	var sim := SpringBoneSimulator3D.new()
	sim.name = "Springs"
	sim.set_setting_count(found.size())
	for i in range(found.size()):
		var bone: String = found[i]
		var cfg: Dictionary = SPRINGS[bone]
		sim.set_root_bone_name(i, bone)
		sim.set_end_bone_name(i, bone)
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, float(cfg.length))
		sim.set_stiffness(i, float(cfg.stiffness))
		sim.set_drag(i, float(cfg.drag))
		sim.set_gravity(i, float(cfg.gravity))
		sim.set_radius(i, 0.02)
	skeleton.add_child(sim)


# ------------------------------------------------------------------ look / idle

## 体ごと相手へ向く仕組みを用意する（Body のヨーだけ、±35°、0.35 秒でなめらかに）。
func setup_look() -> void:
	if skeleton == null or _body_look != null or skeleton.find_bone("Body") < 0:
		return
	_look_target = Marker3D.new()
	_look_target.name = key + "_Look"
	_set.add_child(_look_target)
	_body_look = LookAtModifier3D.new()
	_body_look.name = "BodyLook"
	_body_look.bone_name = "Body"
	_body_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	_body_look.primary_rotation_axis = Vector3.AXIS_Y
	_body_look.use_secondary_rotation = false
	_body_look.use_angle_limitation = true
	_body_look.symmetry_limitation = true
	_body_look.primary_limit_angle = deg_to_rad(35.0)
	_body_look.primary_damp_threshold = 0.6
	_body_look.duration = 0.35
	_body_look.transition_type = Tween.TRANS_SINE
	skeleton.add_child(_body_look)
	skeleton.move_child(_body_look, 0)
	_body_look.target_node = _body_look.get_path_to(_look_target)
	_body_look.influence = 0.0


## 体ごと point（セットのローカル）のほうへ向く。weight 0 で戻す。
func look_toward(point: Vector3, weight := 1.0) -> void:
	if _look_target == null:
		return
	_look_target.position = point
	_look_goal = weight


func look_clear() -> void:
	_look_goal = 0.0


func _update_idle(delta: float) -> void:
	if _once or _moving or _timed_left > 0.0 or current != base_clip or not (base_clip in ["T_Idle", "G_Idle"]):
		_idle_time = 0.0
		return
	_idle_time += delta
	if _idle_time < _idle_next:
		return
	_idle_time = 0.0
	_idle_next = _rng.randf_range(9.0, 16.0)
	if base_clip == "T_Idle":
		if _rng.randf() < 0.6:
			loop_for("T_IdleLook", clip_length("T_IdleLook"), "T_Idle")
		else:
			once("T_HeadTilt", "T_Idle")
	else:
		once(["G_HeadTilt", "G_LookUp", "G_Nod"][_rng.randi() % 3], "G_Idle")


# ------------------------------------------------------------------ pointer

## 指し棒を用意する（Blender の指し棒のメッシュがあれば隠して置き換える）。
func setup_pointer() -> void:
	if skeleton == null or _pointer != null:
		return
	var baked := root.find_child("HERO_*_Pointer", true, false) as MeshInstance3D
	var silver: Material = null
	var red: Material = null
	if baked != null and baked.mesh != null:
		for surface in range(baked.mesh.get_surface_count()):
			var m := baked.get_active_material(surface) as BaseMaterial3D
			if m == null:
				continue
			if m.metallic > 0.5:
				silver = m
			else:
				red = m
		baked.visible = false
	if silver == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.47, 0.54)
		m.metallic = 0.9
		m.roughness = 0.35
		silver = m
	if red == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.67, 0.044, 0.044)
		m.roughness = 0.5
		red = m
	_pointer = Node3D.new()
	_pointer.name = "Pointer"
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.009
	shaft_mesh.bottom_radius = 0.014
	shaft_mesh.height = 1.0
	shaft_mesh.radial_segments = 10
	shaft_mesh.rings = 1
	_pointer_shaft = MeshInstance3D.new()
	_pointer_shaft.mesh = shaft_mesh
	_pointer_shaft.material_override = silver
	_pointer.add_child(_pointer_shaft)
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.032
	tip_mesh.height = 0.064
	tip_mesh.radial_segments = 12
	tip_mesh.rings = 6
	_pointer_tip = MeshInstance3D.new()
	_pointer_tip.mesh = tip_mesh
	_pointer_tip.material_override = red
	_pointer.add_child(_pointer_tip)
	pointer_to("R", false)
	_pointer_len = _pointer_goal
	_apply_pointer_length()


## 指し棒を見せる・隠す（両手がふさがるとき）。
func pointer_visible(shown: bool) -> void:
	if _pointer != null:
		_pointer.visible = shown


## 指し棒の先にテープで留めたチョーク（項目 29）。
var _pointer_chalk: MeshInstance3D = null


func pointer_chalk(on: bool, color := Color(0.93, 0.93, 0.89)) -> void:
	if _pointer == null:
		return
	if on and _pointer_chalk == null:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0095
		mesh.bottom_radius = 0.0099
		mesh.height = 0.07
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.97
		_pointer_chalk = MeshInstance3D.new()
		_pointer_chalk.mesh = mesh
		_pointer_chalk.material_override = material
		_pointer.add_child(_pointer_chalk)
	if not on and _pointer_chalk != null:
		_pointer_chalk.queue_free()
		_pointer_chalk = null


## 指し棒を side（"R" / "L"）の手へ。extended なら伸ばす。
func pointer_to(side: String, extended: bool) -> void:
	if _pointer == null:
		return
	_pointer_goal = POINTER_LONG if extended else POINTER_SHORT
	if side == _pointer_side:
		return
	_pointer_side = side
	var attach_name := "PointerHold_" + side
	var attach := skeleton.get_node_or_null(attach_name) as BoneAttachment3D
	if attach == null:
		attach = BoneAttachment3D.new()
		attach.name = attach_name
		attach.bone_name = ARM_R[2] if side == "R" else ARM_L[2]
		skeleton.add_child(attach)
	if _pointer.get_parent() != null:
		_pointer.get_parent().remove_child(_pointer)
	attach.add_child(_pointer)
	# 手の +Y（手先の向き）に沿って握る。左手は縮めて持つだけなので少し下へ傾ける
	_pointer.transform = Transform3D(Basis.IDENTITY if side == "R" else Basis(Vector3.RIGHT, 0.5), Vector3(0.0, POINTER_GRIP, 0.0))


func _update_pointer(delta: float) -> void:
	if _pointer == null:
		return
	_pointer_wobble(delta)
	if is_equal_approx(_pointer_len, _pointer_goal):
		return
	# 伸ばすときはシャキッと速く、縮めるときはゆっくり
	var speed := 4.0 if _pointer_goal > _pointer_len else 1.6
	_pointer_len = move_toward(_pointer_len, _pointer_goal, speed * delta)
	_apply_pointer_length()


## 指し棒の先のしなり: 手の動きに遅れてついていくばね（伸ばしているほど大きくしなる）。
var _ptr_tip := Vector3.ZERO
var _ptr_vel := Vector3.ZERO
var _ptr_ready := false


func _pointer_wobble(delta: float) -> void:
	if not _pointer.is_inside_tree() or delta <= 0.0:
		return
	var parent := _pointer.get_parent() as Node3D
	if parent == null:
		return
	var base := parent.global_transform * Transform3D(_pointer_rest_basis(), _pointer.position)
	var target := base * Vector3(0.0, _pointer_len, 0.0)
	if not _ptr_ready:
		_ptr_tip = target
		_ptr_vel = Vector3.ZERO
		_ptr_ready = true
	var k := lerpf(260.0, 70.0, clampf((_pointer_len - POINTER_SHORT) / (POINTER_LONG - POINTER_SHORT), 0.0, 1.0))
	_ptr_vel += ((target - _ptr_tip) * k - _ptr_vel * 9.0) * delta
	_ptr_tip += _ptr_vel * delta
	# 根元から見た、ばねの先とまっすぐの先の向きの差だけ、指し棒を傾ける
	var root_point := base.origin
	var want := (target - root_point).normalized()
	var have := (_ptr_tip - root_point).normalized()
	var bend := Quaternion(want, have) if want.dot(have) < 0.99999 else Quaternion.IDENTITY
	var local_bend := Basis(parent.global_basis.orthonormalized().inverse() * Basis(bend) * parent.global_basis.orthonormalized())
	_pointer.transform.basis = local_bend * _pointer_rest_basis()


func _pointer_rest_basis() -> Basis:
	return Basis.IDENTITY if _pointer_side == "R" else Basis(Vector3.RIGHT, 0.5)


func _apply_pointer_length() -> void:
	_pointer_shaft.scale = Vector3(1.0, _pointer_len, 1.0)
	_pointer_shaft.position = Vector3(0.0, _pointer_len * 0.5 - 0.05, 0.0)
	_pointer_tip.position = Vector3(0.0, _pointer_len - 0.05, 0.0)
	if _pointer_chalk != null:
		_pointer_chalk.position = Vector3(0.0, _pointer_len - 0.02, 0.0)


# ------------------------------------------------------------------ right-hand IK

## 右手の IK を用意する（先生だけ）。手先の点は tip_point（セットのローカル）。
func setup_hand_ik() -> void:
	if skeleton == null or _ik != null:
		return
	var right := _make_arm_ik("R")
	_ik = right.ik
	_look = right.look
	_wrist = right.wrist
	_tip = right.tip
	_pole = right.pole
	var left := _make_arm_ik("L")
	_ik_l = left.ik
	_look_l = left.look
	_wrist_l = left.wrist
	_tip_l = left.tip
	_pole_l = left.pole


func _make_arm_ik(side: String) -> Dictionary:
	var bones: Array = ARM_R if side == "R" else ARM_L
	var markers := {}
	for name in ["wrist", "tip", "pole"]:
		var marker := Marker3D.new()
		marker.name = "%s_%s_%s" % [key, side, name]
		_set.add_child(marker)
		markers[name] = marker
	var ik := TwoBoneIK3D.new()
	ik.name = "HandIK_" + side
	ik.set_setting_count(1)
	ik.set_root_bone_name(0, bones[0])
	ik.set_middle_bone_name(0, bones[1])
	ik.set_end_bone_name(0, bones[2])
	skeleton.add_child(ik)
	ik.set_target_node(0, ik.get_path_to(markers.wrist))
	ik.set_pole_node(0, ik.get_path_to(markers.pole))
	ik.influence = 0.0
	var look := LookAtModifier3D.new()
	look.name = "HandAim_" + side
	look.bone_name = bones[2]
	look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Y
	look.primary_rotation_axis = Vector3.AXIS_Z
	look.use_secondary_rotation = true
	skeleton.add_child(look)
	look.target_node = look.get_path_to(markers.tip)
	look.influence = 0.0
	return {"ik": ik, "look": look, "wrist": markers.wrist, "tip": markers.tip, "pole": markers.pole}


## 左手の IK（手先を point へ）。
func ik_left_on(fade := 0.25) -> void:
	_ik_l_goal = 1.0
	_ik_fade = fade


func ik_left_off(fade := 0.3) -> void:
	_ik_l_goal = 0.0
	_ik_fade = fade


func set_tip_left(point: Vector3) -> void:
	tip_point_l = point


func ik_on(fade := 0.25) -> void:
	_ik_goal = 1.0
	_ik_fade = fade


func ik_off(fade := 0.3) -> void:
	_ik_goal = 0.0
	_ik_fade = fade


func set_tip(point: Vector3) -> void:
	tip_point = point


## 右肩（上腕の付け根）の位置（セットのローカル）。
func shoulder_point() -> Vector3:
	return _bone_point(ARM_R[0])


## 実際の手先（手のボーンの +Y に HAND_TIP）の位置（セットのローカル）。
func hand_tip_point(side := "R") -> Vector3:
	var bone := ARM_R[2] if side == "R" else ARM_L[2]
	var idx := int(_bone_idx.get(bone, -1))
	if skeleton == null or idx < 0:
		return root.position
	var local: Transform3D = _final_pose.get(bone, skeleton.get_bone_global_pose(idx))
	var pose := skeleton.global_transform * local
	return _set.to_local(pose.origin + pose.basis.y.normalized() * HAND_TIP)


func _on_skeleton_updated() -> void:
	for bone in [ARM_R[2], ARM_L[2], ARM_R[0], ARM_L[0], "DEF-head"]:
		var idx := int(_bone_idx.get(bone, -1))
		if idx >= 0:
			_final_pose[bone] = skeleton.get_bone_global_pose(idx)


## 頭のてっぺん（歯の先、DEF-head の付け根から 0.83 m 上）。漫符はこの少し上に出す。
func head_point() -> Vector3:
	var idx := int(_bone_idx.get("DEF-head", -1))
	if skeleton == null or idx < 0:
		return root.position + Vector3(0.0, 1.62, 0.0)
	var local: Transform3D = _final_pose.get("DEF-head", skeleton.get_bone_global_pose(idx))
	var pose := skeleton.global_transform * local
	return _set.to_local(pose.origin + pose.basis.y.normalized() * 0.83)


func _bone_point(bone: String) -> Vector3:
	var idx := int(_bone_idx.get(bone, -1))
	if skeleton == null or idx < 0:
		return root.position
	var local: Transform3D = _final_pose.get(bone, skeleton.get_bone_global_pose(idx))
	return _set.to_local(skeleton.global_transform * local.origin)


func _update_ik(delta: float) -> void:
	if _ik == null:
		return
	ik_weight = move_toward(ik_weight, _ik_goal, delta / maxf(0.01, _ik_fade))
	ik_l_weight = move_toward(ik_l_weight, _ik_l_goal, delta / maxf(0.01, _ik_fade))
	_solve_arm("R", smoothstep(0.0, 1.0, ik_weight), tip_point, tip_length)
	_solve_arm("L", smoothstep(0.0, 1.0, ik_l_weight), tip_point_l, HAND_TIP)


func _solve_arm(side: String, w: float, tip_at: Vector3, reach_tip: float) -> void:
	var ik: TwoBoneIK3D = _ik if side == "R" else _ik_l
	var look: LookAtModifier3D = _look if side == "R" else _look_l
	ik.influence = w
	look.influence = w
	if w <= 0.0:
		return
	var shoulder := _bone_point(ARM_R[0] if side == "R" else ARM_L[0])
	var to_tip := tip_at - shoulder
	var d := to_tip.length()
	var axis := to_tip / d if d > 0.01 else Vector3.FORWARD
	# 手首は、肩から ARM_BENT（腕を少し曲げた長さ）・手先から reach_tip の 2 つの球の交わり（円）の上で、
	# 体の外側の下寄り（自然に肘を落とした位置）を選ぶ。遠ければ腕を伸ばして手先へ向ける。
	var outward := root.basis.x.normalized() * (-1.0 if side == "R" else 1.0)
	var prefer := (outward * 0.6 + Vector3.DOWN).normalized()
	var wrist: Vector3
	if d >= ARM_REACH + reach_tip - 0.005:
		wrist = shoulder + axis * minf(ARM_REACH, d - reach_tip)
	else:
		var a := clampf(ARM_BENT, absf(d - reach_tip) + 0.01, ARM_REACH)
		var x := (d * d + a * a - reach_tip * reach_tip) / (2.0 * d)
		var r := sqrt(maxf(0.0, a * a - x * x))
		var perp := prefer - axis * prefer.dot(axis)
		if perp.length() < 0.001:
			perp = axis.cross(Vector3.UP)
		wrist = shoulder + axis * x + perp.normalized() * r
	var markers: Array = [_wrist, _tip, _pole] if side == "R" else [_wrist_l, _tip_l, _pole_l]
	(markers[0] as Node3D).position = wrist
	(markers[1] as Node3D).position = tip_at
	# 肘は体の外側の下へ（黒板に書くとき肘が上がらない）
	(markers[2] as Node3D).position = shoulder + outward * 0.25 + Vector3(0.0, -0.35, 0.0) - axis * 0.1


# ------------------------------------------------------------------ held props

## 小道具を手に持たせる（手のボーンに付ける。offset は手首からの手の座標、+Y が手先）。
func hold(side: String, item: Node3D, offset := Transform3D(Basis.IDENTITY, Vector3(0.0, tip_length - 0.037, 0.0))) -> void:
	drop(side)
	if skeleton == null:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "Hold_" + side
	attach.bone_name = ARM_R[2] if side == "R" else ARM_L[2]
	skeleton.add_child(attach)
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	attach.add_child(item)
	item.transform = offset
	_held[side] = attach


## 持っている小道具を外す（返す: 小道具。親から外したまま）。
func drop(side: String) -> Node3D:
	if not _held.has(side):
		return null
	var attach: Node3D = _held[side]
	_held.erase(side)
	var item: Node3D = null
	if is_instance_valid(attach):
		if attach.get_child_count() > 0:
			item = attach.get_child(0) as Node3D
			var global := item.global_transform
			attach.remove_child(item)
			item.set_meta("dropped_global", global)
		attach.queue_free()
	return item


func holding(side: String) -> Node3D:
	if not _held.has(side) or not is_instance_valid(_held[side]):
		return null
	var attach: Node3D = _held[side]
	return attach.get_child(0) as Node3D if attach.get_child_count() > 0 else null

extends RefCounted
class_name RagdollBuilder

## HFF風アクティブラグドール: 表示用スケルトン(Node3Dブロック階層)の静止ポーズ
## 大域変換から、物理駆動体(RigidBody3D群)を別ツリーに手続き生成する。
##
## Phase1: 受動ラグドール(重力で垂れるだけ)。ジョイント/質量/レイヤー/アンカー
##         構成の破綻が無いことを検証する。
## Phase2: ActiveRagdollDriver が _target_rot を読んでトルク駆動する。
##
## 体幹(pelvis/spine)は当面キネマティックなままで、四肢ルート(上腕/腿/頭)は
## 単一の体幹アンカー(キネマRB)へジョイント接続する。アンカーは毎物理フレーム
## pelvis の大域変換へ同期されるため、後から pelvis を物理化する拡張も容易。

const LAYER_LIMB := 2          # 四肢の所属コリジョンレイヤー
const MASK_FLOOR := 1          # 床(layer1)のみと衝突 = 四肢自己衝突オフ

# 各駆動体の定義。
#   key   : 生成する物理ボディの識別子(_target_rot 等で参照)
#   mesh  : 箱の中心/姿勢を取得する表示スケルトンのノードキー
#   ext   : BoxShape の half_extents (_create_box と同じ寸法基準)
#   mass  : 質量(隣接10:1以内・HFFスケール目安)
#   parent: ジョイント接続先。"anchor"=体幹アンカー、それ以外=他ボディの key
#   joint : ジョイント中心(回転ピボット)を取得する表示ノードキー
#   jtype : "cone"=ConeTwistJoint3D / "hinge"=HingeJoint3D
#   swing : ConeTwist の swing 角(度) / hinge の場合は未使用
#   twist : ConeTwist の twist 角(度)
const LIMB_SPECS := [
	{"key": "head", "mesh": "head", "ext": Vector3(0.22, 0.22, 0.22), "mass": 5.0,
		"parent": "torso", "joint": "neck", "jtype": "cone", "swing": 50.0, "twist": 30.0},

	# 左腕
	{"key": "l_upp_arm", "mesh": "l_upp_arm", "ext": Vector3(0.12, 0.26, 0.12), "mass": 2.5,
		"parent": "torso", "joint": "l_shoulder", "jtype": "cone", "swing": 85.0, "twist": 45.0},
	{"key": "l_low_arm", "mesh": "l_low_arm", "ext": Vector3(0.12, 0.26, 0.12), "mass": 1.5,
		"parent": "l_upp_arm", "joint": "l_elbow", "jtype": "hinge", "limit_lo": -150.0, "limit_hi": 10.0},
	{"key": "l_hand", "mesh": "l_hand", "ext": Vector3(0.10, 0.10, 0.07), "mass": 0.5,
		"parent": "l_low_arm", "joint": "l_wrist", "jtype": "cone", "swing": 45.0, "twist": 30.0},

	# 右腕
	{"key": "r_upp_arm", "mesh": "r_upp_arm", "ext": Vector3(0.12, 0.26, 0.12), "mass": 2.5,
		"parent": "torso", "joint": "r_shoulder", "jtype": "cone", "swing": 85.0, "twist": 45.0},
	{"key": "r_low_arm", "mesh": "r_low_arm", "ext": Vector3(0.12, 0.26, 0.12), "mass": 1.5,
		"parent": "r_upp_arm", "joint": "r_elbow", "jtype": "hinge", "limit_lo": -150.0, "limit_hi": 10.0},
	{"key": "r_hand", "mesh": "r_hand", "ext": Vector3(0.10, 0.10, 0.07), "mass": 0.5,
		"parent": "r_low_arm", "joint": "r_wrist", "jtype": "cone", "swing": 45.0, "twist": 30.0},

	# 左脚
	{"key": "l_thigh", "mesh": "l_thigh", "ext": Vector3(0.18, 0.285, 0.18), "mass": 6.0,
		"parent": "torso", "joint": "l_hip", "jtype": "cone", "swing": 75.0, "twist": 40.0},
	{"key": "l_calf", "mesh": "l_calf", "ext": Vector3(0.16, 0.285, 0.16), "mass": 4.0,
		"parent": "l_thigh", "joint": "l_knee", "jtype": "hinge", "limit_lo": -10.0, "limit_hi": 150.0},
	{"key": "l_foot", "mesh": "l_foot", "ext": Vector3(0.14, 0.06, 0.22), "mass": 1.0,
		"parent": "l_calf", "joint": "l_ankle", "jtype": "cone", "swing": 40.0, "twist": 20.0},

	# 右脚
	{"key": "r_thigh", "mesh": "r_thigh", "ext": Vector3(0.18, 0.285, 0.18), "mass": 6.0,
		"parent": "torso", "joint": "r_hip", "jtype": "cone", "swing": 75.0, "twist": 40.0},
	{"key": "r_calf", "mesh": "r_calf", "ext": Vector3(0.16, 0.285, 0.16), "mass": 4.0,
		"parent": "r_thigh", "joint": "r_knee", "jtype": "hinge", "limit_lo": -10.0, "limit_hi": 150.0},
	{"key": "r_foot", "mesh": "r_foot", "ext": Vector3(0.14, 0.06, 0.22), "mass": 1.0,
		"parent": "r_calf", "joint": "r_ankle", "jtype": "cone", "swing": 40.0, "twist": 20.0},
]


## 四肢物理ツリーを container 配下に生成する。
##   container : 物理ボディ群の親(別ツリー RagdollLimbs)
##   pelvis    : 体幹アンカーの追従先(表示スケルトンの pelvis)
##   parts     : _build_player_skeleton が返す表示ノード辞書
## 戻り値: {"bodies": {key->RigidBody3D}, "joints": {key->Joint3D}, "anchor": RigidBody3D}
static func build(container: Node3D, pelvis: Node3D, parts: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var bodies := {}
	var joints := {}
	# 表示メッシュの色/不透明度。debug=true は半透明グリーン(隔離テスト用)、
	# false は実カラー(ゲーム内: 四肢/頭の色を渡す)。
	var debug: bool = opts.get("debug", true)
	var limb_color: Color = opts.get("limb_color", Color(0.2, 0.9, 0.4, 0.5))
	var head_color: Color = opts.get("head_color", limb_color)

	# --- 体幹アンカー(キネマティック) ---
	# pelvis に毎物理フレーム同期され、四肢ルートの接続元になる。
	var anchor := RigidBody3D.new()
	anchor.name = "TorsoAnchor"
	anchor.freeze = true
	anchor.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	# 原点(0,0,0)を経由するテレポート初速を避けるため add_child 前にローカル配置
	anchor.transform = container.global_transform.affine_inverse() * pelvis.global_transform
	container.add_child(anchor)
	# 形状無し警告回避用の極小ボックス(レイヤー0/マスク0で衝突しない)
	var a_shape := CollisionShape3D.new()
	var a_box := BoxShape3D.new()
	a_box.size = Vector3(0.1, 0.1, 0.1)
	a_shape.shape = a_box
	anchor.add_child(a_shape)
	bodies["anchor"] = anchor

	# --- 体幹物理体(動的) ---
	# anchor(=pelvis 目標)に PD(位置+回転)で追従するが、慣性遅れと四肢の反力で
	# 揺れる=HFFの"崩れかける/よろめき"感。四肢ルート(頭/上腕/腿)はこの torso に
	# ジョイント接続される。gravity_scale=0 で自重落下させず位置PDで定位置を保つ
	# (死亡時に脱力させる際は driver 側で gravity を有効化)。
	var body_color: Color = opts.get("torso_color", Color(0.85, 0.5, 0.2))
	var torso := RigidBody3D.new()
	torso.name = "TorsoBody"
	torso.mass = 12.0
	torso.gravity_scale = 0.0
	torso.linear_damp = 0.6
	torso.angular_damp = 0.1
	torso.can_sleep = false
	torso.collision_layer = LAYER_LIMB
	torso.collision_mask = MASK_FLOOR
	torso.transform = container.global_transform.affine_inverse() * pelvis.global_transform
	container.add_child(torso)
	torso.linear_velocity = Vector3.ZERO
	torso.angular_velocity = Vector3.ZERO
	var t_shape := CollisionShape3D.new()
	var t_box := BoxShape3D.new()
	t_box.size = Vector3(0.5, 0.82, 0.30)
	t_shape.shape = t_box
	t_shape.position = Vector3(0.0, 0.31, 0.0)
	torso.add_child(t_shape)
	# 表示メッシュ: lower_torso/upper_torso を pelvis 相対オフセットで子に持つ
	for m in [{"size": Vector3(0.76, 0.44, 0.44), "y": 0.15}, {"size": Vector3(0.76, 0.52, 0.44), "y": 0.48}]:
		var tmi := MeshInstance3D.new()
		var tbm := BoxMesh.new()
		tbm.size = m["size"]
		tmi.mesh = tbm
		tmi.position = Vector3(0.0, m["y"], 0.0)
		var tmat := StandardMaterial3D.new()
		if debug:
			tmat.albedo_color = Color(limb_color.r, limb_color.g, limb_color.b, 0.5)
			tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		else:
			tmat.albedo_color = body_color
		tmat.roughness = 0.7
		tmat.metallic = 0.1
		tmi.material_override = tmat
		torso.add_child(tmi)
	bodies["torso"] = torso

	# --- 駆動体生成 ---
	for spec in LIMB_SPECS:
		var mesh_node: Node3D = parts[spec["mesh"]]
		var body := RigidBody3D.new()
		body.name = "RB_" + str(spec["key"])
		body.mass = spec["mass"]
		body.gravity_scale = 1.0
		body.linear_damp = 0.4
		# 回転減衰は driver の PD(Kd)が担当。ここは数値安定の保険のみ(旧 1.0 は
		# Kd と二重減衰になり設計減衰比 zeta を上書きして「もっさり」化していた)。
		body.angular_damp = 0.1
		body.can_sleep = false
		body.collision_layer = LAYER_LIMB
		body.collision_mask = MASK_FLOOR
		# 原点経由のテレポート初速を避けるため add_child 前にローカル配置
		body.transform = container.global_transform.affine_inverse() * mesh_node.global_transform
		container.add_child(body)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec["ext"] * 2.0
		shape.shape = box
		body.add_child(shape)

		# 表示メッシュ。debug=半透明グリーン / 実ゲーム=四肢・頭の実カラー。
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec["ext"] * 2.0
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		var base_col: Color = head_color if str(spec["key"]) == "head" else limb_color
		mat.albedo_color = base_col
		mat.roughness = 0.7
		mat.metallic = 0.1
		if debug:
			mat.albedo_color = Color(base_col.r, base_col.g, base_col.b, 0.5)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		body.add_child(mi)

		bodies[spec["key"]] = body

	# --- ジョイント生成(全ボディ生成後) ---
	for spec in LIMB_SPECS:
		var body: RigidBody3D = bodies[spec["key"]]
		var parent_body: RigidBody3D = bodies[spec["parent"]]
		var joint_node: Node3D = parts[spec["joint"]]

		var is_hinge := str(spec["jtype"]) == "hinge"
		var joint: Joint3D
		if is_hinge:
			joint = HingeJoint3D.new()
		else:
			var cj := ConeTwistJoint3D.new()
			cj.swing_span = deg_to_rad(spec["swing"])
			cj.twist_span = deg_to_rad(spec["twist"])
			joint = cj

		joint.name = "J_" + str(spec["key"])
		container.add_child(joint)
		# ジョイントの大域変換 = 拘束基準フレーム。位置はピボット、姿勢は pelvis 基準。
		var jt := pelvis.global_transform
		jt.origin = joint_node.global_position
		if is_hinge:
			# HingeJoint3D の回転軸はローカルZ。肘/膝の曲げ軸(静止時=pelvisのX軸,
			# _animate_skeleton が rotation.x で屈曲)へ Z を合わせるよう基底をリマップ。
			var bend := pelvis.global_transform.basis.x.normalized()
			var up := pelvis.global_transform.basis.y.normalized()
			var nz := bend
			var nx := (up - nz * up.dot(nz)).normalized()
			var ny := nz.cross(nx).normalized()
			jt.basis = Basis(nx, ny, nz)
		joint.global_transform = jt
		joint.node_a = parent_body.get_path()
		joint.node_b = body.get_path()
		joint.exclude_nodes_from_collision = true
		if is_hinge:
			var hj := joint as HingeJoint3D
			hj.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			hj.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(spec["limit_lo"]))
			hj.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(spec["limit_hi"]))
		joints[spec["key"]] = joint

	return {"bodies": bodies, "joints": joints, "anchor": anchor}


## 体幹アンカーを pelvis の現在の大域変換へ同期する(毎 _physics_process で呼ぶ)。
static func sync_anchor(anchor: RigidBody3D, pelvis: Node3D) -> void:
	if anchor and is_instance_valid(anchor) and pelvis and is_instance_valid(pelvis):
		anchor.global_transform = pelvis.global_transform

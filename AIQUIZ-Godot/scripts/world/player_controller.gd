extends Node3D
class_name PlayerController

## ブロック人間プレイヤー (関節付き階層モデル)
## Python版 renderer.py の _draw_player_alive / _draw_player_exploding に相当

# Player colors
const P1_BODY := Color(0.95, 0.55, 0.20)
const P1_HEAD := Color(0.95, 0.65, 0.35)
const P1_LIMB := Color(0.85, 0.48, 0.18)

const P2_BODY := Color(0.20, 0.65, 0.90)
const P2_HEAD := Color(0.30, 0.75, 0.95)
const P2_LIMB := Color(0.15, 0.55, 0.80)

var p1_parts := {}
var p2_parts := {}
var p2_container: Node3D

# Hat state
var _p1_hat_id: int = 0
var _p2_hat_id: int = 0
var _p1_hat_node: Node3D = null
var _p2_hat_node: Node3D = null

var _p1_exploding: bool = false
var _p2_exploding: bool = false
var _p1_explosion_data: Array[Dictionary] = []
var _p2_explosion_data: Array[Dictionary] = []

var _p1_rigged: bool = false
var _p2_rigged: bool = false

var _time: float = 0.0
const BASE_Y: float = -1.2

var _rig_node1: Node3D = null
var _p1_anim_player: AnimationPlayer = null
var _p1_skeleton: Skeleton3D = null
var _taunt_anim_name1: String = ""
var _run_anim_name1: String = ""
var _bone_indices: Dictionary = {}
var _rig_debug_counter: int = 0

# 各アニメーション用の独立したFBXシーン(P1)
var _taunt_scene: Node3D = null
var _taunt_skeleton: Skeleton3D = null
var _taunt_ap: AnimationPlayer = null
var _taunt_bone_indices: Dictionary = {}

var _run_scene: Node3D = null
var _run_skeleton: Skeleton3D = null
var _run_ap: AnimationPlayer = null
var _run_bone_indices: Dictionary = {}

var _gangnam_scene: Node3D = null
var _gangnam_skeleton: Skeleton3D = null
var _gangnam_ap: AnimationPlayer = null
var _gangnam_bone_indices: Dictionary = {}
var _gangnam_anim_name1: String = ""

var _slide_scene: Node3D = null
var _slide_skeleton: Skeleton3D = null
var _slide_ap: AnimationPlayer = null
var _slide_bone_indices: Dictionary = {}
var _slide_anim_name1: String = ""

var _moonwalk_scene: Node3D = null
var _moonwalk_skeleton: Skeleton3D = null
var _moonwalk_ap: AnimationPlayer = null
var _moonwalk_bone_indices: Dictionary = {}
var _moonwalk_anim_name1: String = ""

var _drowning_scene: Node3D = null
var _drowning_skeleton: Skeleton3D = null
var _drowning_ap: AnimationPlayer = null
var _drowning_bone_indices: Dictionary = {}
var _drowning_anim_name1: String = ""

var _flair_scene: Node3D = null
var _flair_skeleton: Skeleton3D = null
var _flair_ap: AnimationPlayer = null
var _flair_bone_indices: Dictionary = {}
var _flair_anim_name1: String = ""

# 現在アクティブなスケルトンと骨インデックス(P1)
var _active_skeleton: Skeleton3D = null
var _active_bone_indices: Dictionary = {}
var _p1_mirror_x: bool = false

# P2 Rig state
var _p2_taunt_scene: Node3D = null
var _p2_taunt_skeleton: Skeleton3D = null
var _p2_taunt_ap: AnimationPlayer = null
var _p2_taunt_bone_indices: Dictionary = {}
var _p2_taunt_anim_name1: String = ""

var _p2_run_scene: Node3D = null
var _p2_run_skeleton: Skeleton3D = null
var _p2_run_ap: AnimationPlayer = null
var _p2_run_bone_indices: Dictionary = {}
var _p2_run_anim_name1: String = ""

var _p2_gangnam_scene: Node3D = null
var _p2_gangnam_skeleton: Skeleton3D = null
var _p2_gangnam_ap: AnimationPlayer = null
var _p2_gangnam_bone_indices: Dictionary = {}
var _p2_gangnam_anim_name1: String = ""

var _p2_slide_scene: Node3D = null
var _p2_slide_skeleton: Skeleton3D = null
var _p2_slide_ap: AnimationPlayer = null
var _p2_slide_bone_indices: Dictionary = {}
var _p2_slide_anim_name1: String = ""

var _p2_moonwalk_scene: Node3D = null
var _p2_moonwalk_skeleton: Skeleton3D = null
var _p2_moonwalk_ap: AnimationPlayer = null
var _p2_moonwalk_bone_indices: Dictionary = {}
var _p2_moonwalk_anim_name1: String = ""

var _p2_drowning_scene: Node3D = null
var _p2_drowning_skeleton: Skeleton3D = null
var _p2_drowning_ap: AnimationPlayer = null
var _p2_drowning_bone_indices: Dictionary = {}
var _p2_drowning_anim_name1: String = ""

var _p2_flair_scene: Node3D = null
var _p2_flair_skeleton: Skeleton3D = null
var _p2_flair_ap: AnimationPlayer = null
var _p2_flair_bone_indices: Dictionary = {}
var _p2_flair_anim_name1: String = ""

var _p2_active_skeleton: Skeleton3D = null
var _p2_active_bone_indices: Dictionary = {}
var _p2_mirror_x: bool = false

func _ready() -> void:
	p1_parts = _build_player_skeleton(true, self)
	_load_mixamo_rig()

func _load_mixamo_rig() -> void:
	# P1 煽りダンスFBXを独立シーンとして読み込み
	var taunt_data = _load_fbx_scene("res://assets/animations/Y Bot@Step Hip Hop Dance.fbx", "TauntRig")
	if taunt_data:
		_taunt_scene = taunt_data["node"]
		_taunt_skeleton = taunt_data["skeleton"]
		_taunt_ap = taunt_data["anim_player"]
		_taunt_bone_indices = taunt_data["bone_indices"]
		_taunt_anim_name1 = taunt_data["anim_name"]
		print("[RIG] P1 Taunt scene ready: ", _taunt_anim_name1)
	
	# P1 走りFBXを独立シーンとして読み込み
	var run_data = _load_fbx_scene("res://assets/animations/Run.fbx", "RunRig")
	if run_data:
		_run_scene = run_data["node"]
		_run_skeleton = run_data["skeleton"]
		_run_ap = run_data["anim_player"]
		_run_bone_indices = run_data["bone_indices"]
		_run_anim_name1 = run_data["anim_name"]
		print("[RIG] P1 Run scene ready: ", _run_anim_name1)
	
	# P1 Gangnam Style FBX
	var gangnam_data = _load_fbx_scene("res://assets/animations/Y Bot@Gangnam Style.fbx", "GangnamRig")
	if gangnam_data:
		_gangnam_scene = gangnam_data["node"]
		_gangnam_skeleton = gangnam_data["skeleton"]
		_gangnam_ap = gangnam_data["anim_player"]
		_gangnam_bone_indices = gangnam_data["bone_indices"]
		_gangnam_anim_name1 = gangnam_data["anim_name"]
		print("[RIG] P1 Gangnam scene ready: ", _gangnam_anim_name1)
	
	# P1 Slide Hip Hop Dance FBX
	var slide_data = _load_fbx_scene("res://assets/animations/Slide Hip Hop Dance.fbx", "SlideRig")
	if slide_data:
		_slide_scene = slide_data["node"]
		_slide_skeleton = slide_data["skeleton"]
		_slide_ap = slide_data["anim_player"]
		_slide_bone_indices = slide_data["bone_indices"]
		_slide_anim_name1 = slide_data["anim_name"]
		print("[RIG] P1 Slide scene ready: ", _slide_anim_name1)
	
	# P1 Moonwalk FBX
	var moonwalk_data = _load_fbx_scene("res://assets/animations/Moonwalk.fbx", "MoonwalkRig")
	if moonwalk_data:
		_moonwalk_scene = moonwalk_data["node"]
		_moonwalk_skeleton = moonwalk_data["skeleton"]
		_moonwalk_ap = moonwalk_data["anim_player"]
		_moonwalk_bone_indices = moonwalk_data["bone_indices"]
		_moonwalk_anim_name1 = moonwalk_data["anim_name"]
		print("[RIG] P1 Moonwalk scene ready: ", _moonwalk_anim_name1)
		
	# P1 Drowning FBX
	var drowning_data = _load_fbx_scene("res://assets/animations/Drowning.fbx", "DrowningRig")
	if drowning_data:
		_drowning_scene = drowning_data["node"]
		_drowning_skeleton = drowning_data["skeleton"]
		_drowning_ap = drowning_data["anim_player"]
		_drowning_bone_indices = drowning_data["bone_indices"]
		_drowning_anim_name1 = drowning_data["anim_name"]
		print("[RIG] P1 Drowning scene ready: ", _drowning_anim_name1)
		
	# P1 Flair FBX
	var flair_data = _load_fbx_scene("res://assets/animations/Flair.fbx", "FlairRig")
	if flair_data:
		_flair_scene = flair_data["node"]
		_flair_skeleton = flair_data["skeleton"]
		_flair_ap = flair_data["anim_player"]
		_flair_bone_indices = flair_data["bone_indices"]
		_flair_anim_name1 = flair_data["anim_name"]
		print("[RIG] P1 Flair scene ready: ", _flair_anim_name1)
		
	# P2 煽りダンスFBX
	var p2_taunt_data = _load_fbx_scene("res://assets/animations/Y Bot@Step Hip Hop Dance.fbx", "P2TauntRig")
	if p2_taunt_data:
		_p2_taunt_scene = p2_taunt_data["node"]
		_p2_taunt_skeleton = p2_taunt_data["skeleton"]
		_p2_taunt_ap = p2_taunt_data["anim_player"]
		_p2_taunt_bone_indices = p2_taunt_data["bone_indices"]
		_p2_taunt_anim_name1 = p2_taunt_data["anim_name"]
		print("[RIG] P2 Taunt scene ready: ", _p2_taunt_anim_name1)
	
	# P2 走りFBX
	var p2_run_data = _load_fbx_scene("res://assets/animations/Run.fbx", "P2RunRig")
	if p2_run_data:
		_p2_run_scene = p2_run_data["node"]
		_p2_run_skeleton = p2_run_data["skeleton"]
		_p2_run_ap = p2_run_data["anim_player"]
		_p2_run_bone_indices = p2_run_data["bone_indices"]
		_p2_run_anim_name1 = p2_run_data["anim_name"]
		print("[RIG] P2 Run scene ready: ", _p2_run_anim_name1)
	
	# P2 Gangnam Style FBX
	var p2_gangnam_data = _load_fbx_scene("res://assets/animations/Y Bot@Gangnam Style.fbx", "P2GangnamRig")
	if p2_gangnam_data:
		_p2_gangnam_scene = p2_gangnam_data["node"]
		_p2_gangnam_skeleton = p2_gangnam_data["skeleton"]
		_p2_gangnam_ap = p2_gangnam_data["anim_player"]
		_p2_gangnam_bone_indices = p2_gangnam_data["bone_indices"]
		_p2_gangnam_anim_name1 = p2_gangnam_data["anim_name"]
	
	# P2 Slide Hip Hop Dance
	var p2_slide_data = _load_fbx_scene("res://assets/animations/Slide Hip Hop Dance.fbx", "P2SlideRig")
	if p2_slide_data:
		_p2_slide_scene = p2_slide_data["node"]
		_p2_slide_skeleton = p2_slide_data["skeleton"]
		_p2_slide_ap = p2_slide_data["anim_player"]
		_p2_slide_bone_indices = p2_slide_data["bone_indices"]
		_p2_slide_anim_name1 = p2_slide_data["anim_name"]
	
	# P2 Moonwalk
	var p2_moonwalk_data = _load_fbx_scene("res://assets/animations/Moonwalk.fbx", "P2MoonwalkRig")
	if p2_moonwalk_data:
		_p2_moonwalk_scene = p2_moonwalk_data["node"]
		_p2_moonwalk_skeleton = p2_moonwalk_data["skeleton"]
		_p2_moonwalk_ap = p2_moonwalk_data["anim_player"]
		_p2_moonwalk_bone_indices = p2_moonwalk_data["bone_indices"]
		_p2_moonwalk_anim_name1 = p2_moonwalk_data["anim_name"]
	
	# P2 Drowning
	var p2_drowning_data = _load_fbx_scene("res://assets/animations/Drowning.fbx", "P2DrowningRig")
	if p2_drowning_data:
		_p2_drowning_scene = p2_drowning_data["node"]
		_p2_drowning_skeleton = p2_drowning_data["skeleton"]
		_p2_drowning_ap = p2_drowning_data["anim_player"]
		_p2_drowning_bone_indices = p2_drowning_data["bone_indices"]
		_p2_drowning_anim_name1 = p2_drowning_data["anim_name"]
	
	# P2 Flair
	var p2_flair_data = _load_fbx_scene("res://assets/animations/Flair.fbx", "P2FlairRig")
	if p2_flair_data:
		_p2_flair_scene = p2_flair_data["node"]
		_p2_flair_skeleton = p2_flair_data["skeleton"]
		_p2_flair_ap = p2_flair_data["anim_player"]
		_p2_flair_bone_indices = p2_flair_data["bone_indices"]
		_p2_flair_anim_name1 = p2_flair_data["anim_name"]
	
	# どちらかが読み込めたらリグモードON
	if _taunt_skeleton or _run_skeleton:
		_p1_rigged = true
	if _p2_taunt_skeleton or _p2_run_skeleton:
		_p2_rigged = true
		
	if _p1_rigged or _p2_rigged:
		print("[RIG] Rig mode ENABLED for active players")
	else:
		print("[RIG] No FBX loaded - procedural mode")

func _load_fbx_scene(path: String, node_name: String) -> Variant:
	"""FBXファイルを独立シーンとして読み込み、スケルトン・AP・骨インデックスを返す"""
	if not ResourceLoader.exists(path):
		print("[RIG] File not found: ", path)
		return null
	var scene = load(path) as PackedScene
	if not scene:
		print("[RIG] Failed to load: ", path)
		return null
	
	var node = scene.instantiate()
	node.name = node_name
	add_child(node)
	
	# Skeleton3D を探す
	var skeleton: Skeleton3D = null
	for child in node.find_children("*", "Skeleton3D", true, false):
		skeleton = child as Skeleton3D
		break
	if not skeleton:
		print("[RIG] No Skeleton3D in: ", path)
		node.queue_free()
		return null
	
	print("[RIG] [", node_name, "] Skeleton found, bones: ", skeleton.get_bone_count())
	
	# メッシュを非表示
	for child in node.find_children("*", "MeshInstance3D", true, false):
		child.hide()
	
	# AnimationPlayer を探す
	var ap: AnimationPlayer = null
	for child in node.find_children("*", "AnimationPlayer", true, false):
		ap = child as AnimationPlayer
		break
	if not ap:
		print("[RIG] No AnimationPlayer in: ", path)
		node.queue_free()
		return null
	
	# 最もトラック数の多いアニメーション、または "mixamo_com" を正解とする
	var anim_name := ""
	var max_tracks := -1
	for lib_name in ap.get_animation_library_list():
		var lib = ap.get_animation_library(lib_name)
		for a_name in lib.get_animation_list():
			var full = lib_name + "/" + a_name if lib_name != "" else a_name
			var anim = lib.get_animation(a_name)
			var tracks_count = anim.get_track_count()
			print("[RIG]   [", node_name, "] Anim: ", full, " (tracks: ", tracks_count, ", len: ", anim.length, ")")
			
			if "mixamo_com" in a_name:
				anim_name = full
				max_tracks = 9999 # 強制的に最優先
			elif tracks_count > max_tracks:
				max_tracks = tracks_count
				if anim_name == "" or not ("mixamo_com" in anim_name):
					anim_name = full
	
	# 骨インデックスをキャッシュ
	var bone_indices := {}
	var candidates: Dictionary = {
		"hips": ["Hips", "mixamorig:Hips"],
		"spine": ["Spine1", "mixamorig:Spine1", "Spine", "mixamorig:Spine"],
		"neck": ["Neck", "mixamorig:Neck"],
		"head": ["Head", "mixamorig:Head"],
		"l_upper_arm": ["LeftUpperArm", "mixamorig:LeftArm"],
		"l_lower_arm": ["LeftLowerArm", "mixamorig:LeftForeArm"],
		"l_hand": ["LeftHand", "mixamorig:LeftHand"],
		"r_upper_arm": ["RightUpperArm", "mixamorig:RightArm"],
		"r_lower_arm": ["RightLowerArm", "mixamorig:RightForeArm"],
		"r_hand": ["RightHand", "mixamorig:RightHand"],
		"l_upper_leg": ["LeftUpperLeg", "mixamorig:LeftUpLeg"],
		"l_lower_leg": ["LeftLowerLeg", "mixamorig:LeftLeg"],
		"l_foot": ["LeftFoot", "mixamorig:LeftFoot"],
		"l_toe": ["LeftToeBase", "mixamorig:LeftToeBase"],
		"r_upper_leg": ["RightUpperLeg", "mixamorig:RightUpLeg"],
		"r_lower_leg": ["RightLowerLeg", "mixamorig:RightLeg"],
		"r_foot": ["RightFoot", "mixamorig:RightFoot"],
		"r_toe": ["RightToeBase", "mixamorig:RightToeBase"]
	}
	for key in candidates.keys():
		for cand in candidates[key]:
			var idx = skeleton.find_bone(cand)
			if idx != -1:
				bone_indices[key] = idx
				break
	print("[RIG]   [", node_name, "] Mapped ", bone_indices.size(), "/18 bones")
	
	return {
		"node": node,
		"skeleton": skeleton,
		"anim_player": ap,
		"bone_indices": bone_indices,
		"anim_name": anim_name
	}

func _import_anim_fbx(path: String, lib_name: String) -> String:
	return ""

# 階層構造の構築
func _build_player_skeleton(is_p1: bool, parent_node: Node3D) -> Dictionary:
	var body_col: Color = P1_BODY if is_p1 else P2_BODY
	var head_col: Color = P1_HEAD if is_p1 else P2_HEAD
	var limb_col: Color = P1_LIMB if is_p1 else P2_LIMB

	var parts := {}

	# Pelvis (Root for all animations)
	var pelvis = Node3D.new()
	pelvis.name = "Pelvis"
	pelvis.position = Vector3(0, BASE_Y + 0.9, 0)
	parent_node.add_child(pelvis)
	parts["pelvis"] = pelvis

	# Lower Torso (hip/belly area)
	var lower_torso = _create_box(Vector3(0.38, 0.22, 0.22), body_col)
	lower_torso.position = Vector3(0, 0.15, 0)
	pelvis.add_child(lower_torso)
	parts["lower_torso"] = lower_torso

	# Spine pivot (between lower and upper torso) — enables upper body twist
	var spine = Node3D.new()
	spine.name = "Spine"
	spine.position = Vector3(0, 0.30, 0)
	pelvis.add_child(spine)
	parts["spine"] = spine

	# Upper Torso (chest) — child of spine
	var upper_torso = _create_box(Vector3(0.38, 0.26, 0.22), body_col)
	upper_torso.position = Vector3(0, 0.18, 0)
	spine.add_child(upper_torso)
	parts["upper_torso"] = upper_torso

	# Neck pivot — child of spine
	var neck = Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, 0.42, 0)
	spine.add_child(neck)
	parts["neck"] = neck

	# Head pivot — child of neck
	var head_pivot = Node3D.new()
	head_pivot.position = Vector3(0, 0.03, 0)
	neck.add_child(head_pivot)
	parts["head_pivot"] = head_pivot

	var head = _create_box(Vector3(0.22, 0.22, 0.22), head_col)
	head.position = Vector3(0, 0.22, 0)
	head_pivot.add_child(head)
	parts["head"] = head

	# Hat mount point (top of head)
	var hat_mount = Node3D.new()
	hat_mount.name = "HatMount"
	hat_mount.position = Vector3(0, 0.44, 0)
	head_pivot.add_child(hat_mount)
	parts["hat_mount"] = hat_mount

	# --- Left Arm (child of spine for upper body twist) ---
	var l_shoulder = Node3D.new()
	l_shoulder.position = Vector3(-0.52, 0.35, 0)
	spine.add_child(l_shoulder)
	parts["l_shoulder"] = l_shoulder

	var l_upp_arm = _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	l_upp_arm.position = Vector3(0, -0.20, 0)
	l_shoulder.add_child(l_upp_arm)
	parts["l_upp_arm"] = l_upp_arm

	var l_elbow = Node3D.new()
	l_elbow.position = Vector3(0, -0.40, 0)
	l_shoulder.add_child(l_elbow)
	parts["l_elbow"] = l_elbow

	var l_low_arm = _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	l_low_arm.position = Vector3(0, -0.20, 0)
	l_elbow.add_child(l_low_arm)
	parts["l_low_arm"] = l_low_arm

	# Left Wrist + Hand
	var l_wrist = Node3D.new()
	l_wrist.position = Vector3(0, -0.40, 0)
	l_elbow.add_child(l_wrist)
	parts["l_wrist"] = l_wrist

	var l_hand = _create_box(Vector3(0.08, 0.14, 0.10), limb_col)
	l_hand.position = Vector3(0, -0.10, 0)
	l_wrist.add_child(l_hand)
	parts["l_hand"] = l_hand

	# --- Right Arm (child of spine) ---
	var r_shoulder = Node3D.new()
	r_shoulder.position = Vector3(0.52, 0.35, 0)
	spine.add_child(r_shoulder)
	parts["r_shoulder"] = r_shoulder

	var r_upp_arm = _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	r_upp_arm.position = Vector3(0, -0.20, 0)
	r_shoulder.add_child(r_upp_arm)
	parts["r_upp_arm"] = r_upp_arm

	var r_elbow = Node3D.new()
	r_elbow.position = Vector3(0, -0.40, 0)
	r_shoulder.add_child(r_elbow)
	parts["r_elbow"] = r_elbow

	var r_low_arm = _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	r_low_arm.position = Vector3(0, -0.20, 0)
	r_elbow.add_child(r_low_arm)
	parts["r_low_arm"] = r_low_arm

	# Right Wrist + Hand
	var r_wrist = Node3D.new()
	r_wrist.position = Vector3(0, -0.40, 0)
	r_elbow.add_child(r_wrist)
	parts["r_wrist"] = r_wrist

	var r_hand = _create_box(Vector3(0.08, 0.14, 0.10), limb_col)
	r_hand.position = Vector3(0, -0.10, 0)
	r_wrist.add_child(r_hand)
	parts["r_hand"] = r_hand

	# --- Left Leg ---
	var l_hip = Node3D.new()
	l_hip.position = Vector3(-0.22, 0.0, 0)
	pelvis.add_child(l_hip)
	parts["l_hip"] = l_hip

	var l_thigh = _create_box(Vector3(0.18, 0.285, 0.18), limb_col)
	l_thigh.position = Vector3(0, -0.225, 0)
	l_hip.add_child(l_thigh)
	parts["l_thigh"] = l_thigh

	var l_knee = Node3D.new()
	l_knee.position = Vector3(0, -0.45, 0)
	l_hip.add_child(l_knee)
	parts["l_knee"] = l_knee

	var l_calf = _create_box(Vector3(0.16, 0.285, 0.16), limb_col)
	l_calf.position = Vector3(0, -0.225, 0)
	l_knee.add_child(l_calf)
	parts["l_calf"] = l_calf

	# Left Ankle + Foot + Toe
	var l_ankle = Node3D.new()
	l_ankle.position = Vector3(0, -0.45, 0)
	l_knee.add_child(l_ankle)
	parts["l_ankle"] = l_ankle

	var l_foot = _create_box(Vector3(0.14, 0.06, 0.22), limb_col)
	l_foot.position = Vector3(0, -0.06, 0.05)
	l_ankle.add_child(l_foot)
	parts["l_foot"] = l_foot

	var l_toe = Node3D.new()
	l_toe.position = Vector3(0, -0.06, 0.22)
	l_ankle.add_child(l_toe)
	parts["l_toe"] = l_toe

	var l_toe_mesh = _create_box(Vector3(0.12, 0.04, 0.08), limb_col)
	l_toe_mesh.position = Vector3(0, -0.02, 0.04)
	l_toe.add_child(l_toe_mesh)
	parts["l_toe_mesh"] = l_toe_mesh

	# --- Right Leg ---
	var r_hip = Node3D.new()
	r_hip.position = Vector3(0.22, 0.0, 0)
	pelvis.add_child(r_hip)
	parts["r_hip"] = r_hip

	var r_thigh = _create_box(Vector3(0.18, 0.285, 0.18), limb_col)
	r_thigh.position = Vector3(0, -0.225, 0)
	r_hip.add_child(r_thigh)
	parts["r_thigh"] = r_thigh

	var r_knee = Node3D.new()
	r_knee.position = Vector3(0, -0.45, 0)
	r_hip.add_child(r_knee)
	parts["r_knee"] = r_knee

	var r_calf = _create_box(Vector3(0.16, 0.285, 0.16), limb_col)
	r_calf.position = Vector3(0, -0.225, 0)
	r_knee.add_child(r_calf)
	parts["r_calf"] = r_calf

	# Right Ankle + Foot + Toe
	var r_ankle = Node3D.new()
	r_ankle.position = Vector3(0, -0.45, 0)
	r_knee.add_child(r_ankle)
	parts["r_ankle"] = r_ankle

	var r_foot = _create_box(Vector3(0.14, 0.06, 0.22), limb_col)
	r_foot.position = Vector3(0, -0.06, 0.05)
	r_ankle.add_child(r_foot)
	parts["r_foot"] = r_foot

	var r_toe = Node3D.new()
	r_toe.position = Vector3(0, -0.06, 0.22)
	r_ankle.add_child(r_toe)
	parts["r_toe"] = r_toe

	var r_toe_mesh = _create_box(Vector3(0.12, 0.04, 0.08), limb_col)
	r_toe_mesh.position = Vector3(0, -0.02, 0.04)
	r_toe.add_child(r_toe_mesh)
	parts["r_toe_mesh"] = r_toe_mesh

	# Add all meshes to a list for easy vis clipping / explosion
	parts["meshes"] = [
		lower_torso, upper_torso, head,
		l_upp_arm, l_low_arm, l_hand,
		r_upp_arm, r_low_arm, r_hand,
		l_thigh, l_calf, l_foot, l_toe_mesh,
		r_thigh, r_calf, r_foot, r_toe_mesh
	]
	parts["hat_meshes"] = []  # Populated when hat is set

	return parts

func _create_box(half_extents: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = half_extents * 2.0
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mat.metallic = 0.1
	mesh_inst.material_override = mat

	return mesh_inst

func _process(dt: float) -> void:
	_time += dt

func update_from_state(gs: QuizGameState) -> void:
	var pz: float = gs.player_z
	var walk_phase: float = _time * 8.0

	# Ensure P2 is created if needed
	if gs.num_players >= 2 and p2_container == null:
		p2_container = Node3D.new()
		p2_container.name = "Player2"
		add_child(p2_container)
		p2_parts = _build_player_skeleton(false, p2_container)
	if gs.num_players < 2 and p2_container != null:
		p2_container.queue_free()
		p2_container = null
		p2_parts.clear()

	# --- Player 1 ---
	position = Vector3(gs.player_x, gs.player_y, gs.player_local_z)
	
	if gs.p1_alive:
		_p1_exploding = false
		_set_parts_visible(p1_parts, true)
		if not _p1_rigged:
			_animate_skeleton(p1_parts, gs.player_y, gs.player_vel_y, gs.game_state == Constants.STATE_PLAYING, walk_phase, false, gs.p1_emote)
		else:
			var apply_rig := false
			# 全APリスト（排他的に止めるため）
			var all_p1_aps: Array = [_taunt_ap, _run_ap, _gangnam_ap, _slide_ap, _moonwalk_ap, _drowning_ap, _flair_ap]
			
			# リグモードの再生ロジック - 各FBXの独自APを使い分ける
			if gs.player_y < -1.0 and _drowning_ap and _drowning_anim_name1 != "":
				var target_ap: AnimationPlayer = _drowning_ap
				var target_skel: Skeleton3D = _drowning_skeleton
				var target_bones: Dictionary = _drowning_bone_indices
				var target_anim: String = _drowning_anim_name1
				
				for ap: AnimationPlayer in all_p1_aps:
					if ap and ap != target_ap and ap.is_playing():
						ap.stop()
				if not target_ap.is_playing():
					target_ap.play(target_anim)
				_active_skeleton = target_skel
				_active_bone_indices = target_bones
				_p1_mirror_x = true
				apply_rig = true
			elif gs.p1_emote > 0:
				# --- エモート再生 ---
				var target_ap: AnimationPlayer = null
				var target_skel: Skeleton3D = null
				var target_bones: Dictionary = {}
				var target_anim: String = ""
				
				if gs.p1_emote == 1 and _taunt_ap and _taunt_anim_name1 != "":
					target_ap = _taunt_ap; target_skel = _taunt_skeleton
					target_bones = _taunt_bone_indices; target_anim = _taunt_anim_name1
				elif gs.p1_emote == 2 and _gangnam_ap and _gangnam_anim_name1 != "":
					target_ap = _gangnam_ap; target_skel = _gangnam_skeleton
					target_bones = _gangnam_bone_indices; target_anim = _gangnam_anim_name1
				elif gs.p1_emote == 3 and _slide_ap and _slide_anim_name1 != "":
					target_ap = _slide_ap; target_skel = _slide_skeleton
					target_bones = _slide_bone_indices; target_anim = _slide_anim_name1
				elif gs.p1_emote == 4 and _flair_ap and _flair_anim_name1 != "":
					target_ap = _flair_ap; target_skel = _flair_skeleton
					target_bones = _flair_bone_indices; target_anim = _flair_anim_name1
				
				var mirror_x := true # 全てのFBX（+Z向き）を-Z向きのキャラクターに正しく適用するためXミラーを有効化
				if target_ap:
					# 他の全APを停止
					for ap: AnimationPlayer in all_p1_aps:
						if ap and ap != target_ap and ap.is_playing():
							ap.stop()
					if not target_ap.is_playing():
						target_ap.play(target_anim)
					_active_skeleton = target_skel
					_active_bone_indices = target_bones
					_p1_mirror_x = mirror_x
					apply_rig = true
			elif gs.game_state == Constants.STATE_PLAYING:
				if gs.p1_moving_back and _moonwalk_ap and _moonwalk_anim_name1 != "":
					# --- 後ろ歩き: Moonwalk再生 ---
					for ap: AnimationPlayer in all_p1_aps:
						if ap and ap != _moonwalk_ap and ap.is_playing():
							ap.stop()
					if not _moonwalk_ap.is_playing():
						_moonwalk_ap.play(_moonwalk_anim_name1)
					_active_skeleton = _moonwalk_skeleton
					_active_bone_indices = _moonwalk_bone_indices
					_p1_mirror_x = true
					apply_rig = true
				elif _run_ap and _run_anim_name1 != "":
					# --- 通常走り ---
					for ap: AnimationPlayer in all_p1_aps:
						if ap and ap != _run_ap and ap.is_playing():
							ap.stop()
					if not _run_ap.is_playing():
						_run_ap.play(_run_anim_name1)
					_active_skeleton = _run_skeleton
					_active_bone_indices = _run_bone_indices
					_p1_mirror_x = true
					apply_rig = true
			else:
				# 全停止（待機状態などはプロシージャルなIdleアニメーションに任せる）
				for ap: AnimationPlayer in all_p1_aps:
					if ap and ap.is_playing():
						ap.stop()
			
			# デバッグ: 1秒に1回、骨座標を出力
			_rig_debug_counter += 1
			if _rig_debug_counter % 60 == 1:
				if _active_skeleton and _active_bone_indices.has("hips"):
					var hips_rot = _active_skeleton.get_bone_pose_rotation(_active_bone_indices["hips"])
					var hips_pos = _active_skeleton.get_bone_global_pose(_active_bone_indices["hips"]).origin
					if _run_ap and _run_ap.is_playing():
						print("[RIG] DEBUG RUN position=", _run_ap.current_animation_position)
			
			if apply_rig:
				# 骨の座標をブロックに転写
				_apply_skeleton_pose(p1_parts, _active_skeleton, _active_bone_indices, _p1_mirror_x)
			else:
				# 停止時はプロシージャルアニメーション（Idleバウンスなど）を適用
				_animate_skeleton(p1_parts, gs.player_y, gs.player_vel_y, false, walk_phase, false, 0)
	elif gs.game_over_timer > 0:
		if gs.game_over_timer < 2.0:
			_set_parts_visible(p1_parts, true)
			var apply_rig := false
			if _p1_rigged and _drowning_ap and _drowning_anim_name1 != "":
				var target_ap: AnimationPlayer = _drowning_ap
				var target_skel: Skeleton3D = _drowning_skeleton
				var target_bones: Dictionary = _drowning_bone_indices
				var target_anim: String = _drowning_anim_name1
				
				var all_p1_aps: Array = [_taunt_ap, _run_ap, _gangnam_ap, _slide_ap, _moonwalk_ap, _drowning_ap, _flair_ap]
				for ap: AnimationPlayer in all_p1_aps:
					if ap and ap != target_ap and ap.is_playing():
						ap.stop()
				if not target_ap.is_playing():
					target_ap.play(target_anim)
				_active_skeleton = target_skel
				_active_bone_indices = target_bones
				_p1_mirror_x = true
				apply_rig = true
				_apply_skeleton_pose(p1_parts, _active_skeleton, _active_bone_indices, _p1_mirror_x)
			
			if not apply_rig:
				# FBXがない、またはマグマ以外の死因用
				if gs.player_y < -1.0:
					_animate_skeleton(p1_parts, gs.player_y, gs.player_vel_y, false, walk_phase, false, 0)
				else:
					_animate_struggle(p1_parts, gs.game_over_timer)
		else:
			if not _p1_exploding:
				_p1_exploding = true
				_init_explosion(p1_parts, true)
			_set_parts_visible(p1_parts, false)
			var is_magma = gs.player_y < -1.0
			_update_explosion(true, gs.game_over_timer - 2.0, is_magma)
	else:
		_set_parts_visible(p1_parts, false)

	# --- Player 2 ---
	if gs.num_players >= 2 and p2_container:
		p2_container.position = Vector3(gs.player2_x - gs.player_x, gs.player2_y - gs.player_y, gs.player2_local_z - gs.player_local_z)
		
		if gs.p2_alive:
			_p2_exploding = false
			_set_parts_visible(p2_parts, true)
			if not _p2_rigged:
				_animate_skeleton(p2_parts, gs.player2_y, gs.player2_vel_y, gs.game_state == Constants.STATE_PLAYING, walk_phase * 1.1, true, gs.p2_emote)
			else:
				var apply_rig := false
				var all_p2_aps: Array = [_p2_taunt_ap, _p2_run_ap, _p2_gangnam_ap, _p2_slide_ap, _p2_moonwalk_ap, _p2_drowning_ap, _p2_flair_ap]
				
				if gs.player2_y < -1.0 and _p2_drowning_ap and _p2_drowning_anim_name1 != "":
					var target_ap: AnimationPlayer = _p2_drowning_ap
					var target_skel: Skeleton3D = _p2_drowning_skeleton
					var target_bones: Dictionary = _p2_drowning_bone_indices
					var target_anim: String = _p2_drowning_anim_name1
					
					for ap: AnimationPlayer in all_p2_aps:
						if ap and ap != target_ap and ap.is_playing():
							ap.stop()
					if not target_ap.is_playing():
						target_ap.play(target_anim)
					_p2_active_skeleton = target_skel
					_p2_active_bone_indices = target_bones
					_p2_mirror_x = true
					apply_rig = true
				elif gs.p2_emote > 0:
					var target_ap: AnimationPlayer = null
					var target_skel: Skeleton3D = null
					var target_bones: Dictionary = {}
					var target_anim: String = ""
					
					if gs.p2_emote == 1 and _p2_taunt_ap and _p2_taunt_anim_name1 != "":
						target_ap = _p2_taunt_ap; target_skel = _p2_taunt_skeleton
						target_bones = _p2_taunt_bone_indices; target_anim = _p2_taunt_anim_name1
					elif gs.p2_emote == 2 and _p2_gangnam_ap and _p2_gangnam_anim_name1 != "":
						target_ap = _p2_gangnam_ap; target_skel = _p2_gangnam_skeleton
						target_bones = _p2_gangnam_bone_indices; target_anim = _p2_gangnam_anim_name1
					elif gs.p2_emote == 3 and _p2_slide_ap and _p2_slide_anim_name1 != "":
						target_ap = _p2_slide_ap; target_skel = _p2_slide_skeleton
						target_bones = _p2_slide_bone_indices; target_anim = _p2_slide_anim_name1
					elif gs.p2_emote == 4 and _p2_flair_ap and _p2_flair_anim_name1 != "":
						target_ap = _p2_flair_ap; target_skel = _p2_flair_skeleton
						target_bones = _p2_flair_bone_indices; target_anim = _p2_flair_anim_name1
					
					var p2_mirror_x := true # 全てのFBX（+Z向き）を-Z向きのキャラクターに正しく適用するためXミラーを有効化
					if target_ap:
						for ap: AnimationPlayer in all_p2_aps:
							if ap and ap != target_ap and ap.is_playing():
								ap.stop()
						if not target_ap.is_playing():
							target_ap.play(target_anim)
						_p2_active_skeleton = target_skel
						_p2_active_bone_indices = target_bones
						_p2_mirror_x = p2_mirror_x
						apply_rig = true
				elif gs.game_state == Constants.STATE_PLAYING:
					if gs.p2_moving_back and _p2_moonwalk_ap and _p2_moonwalk_anim_name1 != "":
						for ap: AnimationPlayer in all_p2_aps:
							if ap and ap != _p2_moonwalk_ap and ap.is_playing():
								ap.stop()
						if not _p2_moonwalk_ap.is_playing():
							_p2_moonwalk_ap.play(_p2_moonwalk_anim_name1)
						_p2_active_skeleton = _p2_moonwalk_skeleton
						_p2_active_bone_indices = _p2_moonwalk_bone_indices
						_p2_mirror_x = true
						apply_rig = true
					elif _p2_run_ap and _p2_run_anim_name1 != "":
						for ap: AnimationPlayer in all_p2_aps:
							if ap and ap != _p2_run_ap and ap.is_playing():
								ap.stop()
						if not _p2_run_ap.is_playing():
							_p2_run_ap.play(_p2_run_anim_name1)
						_p2_active_skeleton = _p2_run_skeleton
						_p2_active_bone_indices = _p2_run_bone_indices
						_p2_mirror_x = true
						apply_rig = true
				else:
					for ap: AnimationPlayer in all_p2_aps:
						if ap and ap.is_playing():
							ap.stop()
				
				if apply_rig:
					_apply_skeleton_pose(p2_parts, _p2_active_skeleton, _p2_active_bone_indices, _p2_mirror_x)
				else:
					_animate_skeleton(p2_parts, gs.player2_y, gs.player2_vel_y, false, walk_phase * 1.1, true, 0)
		elif gs.player2_game_over_timer > 0:
			if gs.player2_game_over_timer < 2.0:
				_set_parts_visible(p2_parts, true)
				var apply_rig := false
				if _p2_rigged and _p2_drowning_ap and _p2_drowning_anim_name1 != "":
					var target_ap: AnimationPlayer = _p2_drowning_ap
					var target_skel: Skeleton3D = _p2_drowning_skeleton
					var target_bones: Dictionary = _p2_drowning_bone_indices
					var target_anim: String = _p2_drowning_anim_name1
					
					var all_p2_aps: Array = [_p2_taunt_ap, _p2_run_ap, _p2_gangnam_ap, _p2_slide_ap, _p2_moonwalk_ap, _p2_drowning_ap]
					for ap: AnimationPlayer in all_p2_aps:
						if ap and ap != target_ap and ap.is_playing():
							ap.stop()
					if not target_ap.is_playing():
						target_ap.play(target_anim)
					_p2_active_skeleton = target_skel
					_p2_active_bone_indices = target_bones
					_p2_mirror_x = true
					apply_rig = true
					_apply_skeleton_pose(p2_parts, _p2_active_skeleton, _p2_active_bone_indices, _p2_mirror_x)
					
				if not apply_rig:
					if gs.player2_y < -1.0:
						_animate_skeleton(p2_parts, gs.player2_y, gs.player2_vel_y, false, walk_phase * 1.1, true, 0)
					else:
						_animate_struggle(p2_parts, gs.player2_game_over_timer)
			else:
				if not _p2_exploding:
					_p2_exploding = true
					_init_explosion(p2_parts, false)
				_set_parts_visible(p2_parts, false)
				var is_magma = gs.player2_y < -1.0
				_update_explosion(false, gs.player2_game_over_timer - 2.0, is_magma)
		else:
			_set_parts_visible(p2_parts, false)

	# 1P: only show player body during game over explosion, flyover, or menu
	if gs.num_players == 1:
		if gs.game_state == Constants.STATE_GAME_OVER and gs.game_over_timer > 0:
			visible = true
		elif gs.game_state == Constants.STATE_FLYOVER:
			visible = true
		elif gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_CORRECT, Constants.STATE_PRELOADING]:
			visible = false
		else:
			visible = false

func _set_parts_visible(parts: Dictionary, vis: bool) -> void:
	if not parts or not parts.has("meshes"): return
	for mesh: MeshInstance3D in parts["meshes"]:
		if mesh: mesh.visible = vis



func _animate_skeleton(parts: Dictionary, py: float, vy: float, is_playing: bool, phase: float, is_p2: bool, emote: int = 0) -> void:
	var pelvis: Node3D = parts["pelvis"]
	var spine_node: Node3D = parts["spine"]
	var neck_node: Node3D = parts["neck"]
	var head: Node3D = parts["head_pivot"]
	var l_shoulder: Node3D = parts["l_shoulder"]
	var r_shoulder: Node3D = parts["r_shoulder"]
	var l_elbow: Node3D = parts["l_elbow"]
	var r_elbow: Node3D = parts["r_elbow"]
	var l_wrist: Node3D = parts["l_wrist"]
	var r_wrist: Node3D = parts["r_wrist"]
	var l_hip: Node3D = parts["l_hip"]
	var r_hip: Node3D = parts["r_hip"]
	var l_knee: Node3D = parts["l_knee"]
	var r_knee: Node3D = parts["r_knee"]
	var l_ankle: Node3D = parts["l_ankle"]
	var r_ankle: Node3D = parts["r_ankle"]
	var l_toe: Node3D = parts["l_toe"]
	var r_toe: Node3D = parts["r_toe"]

	# Base resets — all joints
	pelvis.position = Vector3(0, BASE_Y + 0.9, 0)
	pelvis.rotation = Vector3.ZERO
	spine_node.rotation = Vector3.ZERO
	neck_node.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	l_shoulder.rotation = Vector3.ZERO
	r_shoulder.rotation = Vector3.ZERO
	l_elbow.rotation = Vector3.ZERO
	r_elbow.rotation = Vector3.ZERO
	l_wrist.rotation = Vector3.ZERO
	r_wrist.rotation = Vector3.ZERO
	l_hip.rotation = Vector3.ZERO
	r_hip.rotation = Vector3.ZERO
	l_knee.rotation = Vector3.ZERO
	r_knee.rotation = Vector3.ZERO
	l_ankle.rotation = Vector3.ZERO
	r_ankle.rotation = Vector3.ZERO
	l_toe.rotation = Vector3.ZERO
	r_toe.rotation = Vector3.ZERO
	
	if py < -1.0:
		# Flail — falling into magma
		var flail := sin(_time * 25.0) * PI * 0.4
		l_hip.rotation.x = flail
		r_hip.rotation.x = -flail
		l_shoulder.rotation.x = PI + flail
		r_shoulder.rotation.x = PI - flail
		l_wrist.rotation.x = sin(_time * 30.0) * 0.6
		r_wrist.rotation.x = -sin(_time * 30.0) * 0.6
		l_ankle.rotation.x = -PI / 6.0
		r_ankle.rotation.x = -PI / 6.0
		spine_node.rotation.z = sin(_time * 12.0) * 0.2
		var ang_speed = 5.0 if not is_p2 else 6.0
		pelvis.rotation.y = _time * ang_speed
	elif py > 0.01:
		# Jump
		spine_node.rotation.x = -0.08  # slight backward lean in air
		if vy > 0.0:
			l_hip.rotation.x = -PI / 4.0
			l_knee.rotation.x = PI / 4.0
			r_hip.rotation.x = 0.0
			r_knee.rotation.x = PI / 8.0
			l_shoulder.rotation.x = PI / 1.5
			r_shoulder.rotation.x = PI / 1.5
			l_elbow.rotation.x = -PI / 4.0
			r_elbow.rotation.x = -PI / 4.0
			# Toes point down during ascent
			l_ankle.rotation.x = -PI / 5.0
			r_ankle.rotation.x = -PI / 5.0
			l_toe.rotation.x = -PI / 8.0
			r_toe.rotation.x = -PI / 8.0
		else:
			l_hip.rotation.x = 0.0
			l_knee.rotation.x = 0.0
			r_hip.rotation.x = 0.0
			r_knee.rotation.x = 0.0
			l_shoulder.rotation.x = PI / 3.0
			r_shoulder.rotation.x = PI / 3.0
			l_elbow.rotation.x = -PI / 6.0
			r_elbow.rotation.x = -PI / 6.0
			# Ankles flex for landing
			l_ankle.rotation.x = PI / 8.0
			r_ankle.rotation.x = PI / 8.0
	else:
		if is_playing and emote > 0:
			_animate_emote(parts, emote)
		else:
			# Run/Stand
			var swing: float = 0.0
			var bob: float = 0.0
			if is_playing:
				swing = sin(phase)
				bob = abs(cos(phase)) * 0.15 # Bobbing
			pelvis.position.y = BASE_Y + 0.9 + bob
			pelvis.rotation.x = 0.15 # Forward lean
			
			# Spine: subtle counter-twist to hips for natural run
			spine_node.rotation.y = swing * 0.08
			spine_node.rotation.x = -0.05  # slight upright correction
			
			# Neck: counter the spine twist to keep head stable
			neck_node.rotation.y = -swing * 0.05
			neck_node.rotation.x = 0.03
			
			head.rotation.x = -0.1 # Keep head looking up
			
			# Hips
			l_hip.rotation.x = swing * 0.6
			r_hip.rotation.x = -swing * 0.6
			
			# Knees (bend when leg is going backward -> positive swing)
			l_knee.rotation.x = clampf(-swing * 0.8, 0.0, PI/2.0)
			r_knee.rotation.x = clampf(swing * 0.8, 0.0, PI/2.0)
			
			# Ankles: flex with step cycle
			l_ankle.rotation.x = swing * 0.15
			r_ankle.rotation.x = -swing * 0.15
			
			# Toes: push-off during running
			if is_playing:
				l_toe.rotation.x = clampf(swing * 0.3, -PI/8.0, PI/8.0)
				r_toe.rotation.x = clampf(-swing * 0.3, -PI/8.0, PI/8.0)
			
			# Shoulders
			l_shoulder.rotation.x = -swing * 0.7
			r_shoulder.rotation.x = swing * 0.7
			
			# Elbows
			l_elbow.rotation.x = -PI/4.0 + clampf(-swing * 0.2, -PI/8.0, 0.0)
			r_elbow.rotation.x = -PI/4.0 + clampf(swing * 0.2, -PI/8.0, 0.0)
			
			# Wrists: natural follow-through swing
			if is_playing:
				l_wrist.rotation.x = sin(phase + 0.4) * 0.15
				r_wrist.rotation.x = sin(phase + 0.4 + PI) * 0.15
		
		# Hat sway animation (subtle lag behind head movement)
		if parts.has("hat_mount") and parts["hat_mount"] != null:
			var hat_m: Node3D = parts["hat_mount"]
			if is_playing:
				# Slight delayed sway opposite to running motion
				var hat_sway_x := sin(phase + 0.3) * 0.06  # Forward/back lag
				var hat_sway_z := sin(phase * 0.7 + 0.5) * 0.04  # Side sway
				hat_m.rotation.x = hat_sway_x
				hat_m.rotation.z = hat_sway_z
			else:
				hat_m.rotation = Vector3.ZERO

func _animate_struggle(parts: Dictionary, timer: float) -> void:
	var pelvis: Node3D = parts["pelvis"]
	var spine_node: Node3D = parts["spine"]
	var neck_node: Node3D = parts["neck"]
	var l_shoulder: Node3D = parts["l_shoulder"]
	var r_shoulder: Node3D = parts["r_shoulder"]
	var l_elbow: Node3D = parts["l_elbow"]
	var r_elbow: Node3D = parts["r_elbow"]
	var l_wrist: Node3D = parts["l_wrist"]
	var r_wrist: Node3D = parts["r_wrist"]
	var l_hip: Node3D = parts["l_hip"]
	var r_hip: Node3D = parts["r_hip"]
	var l_knee: Node3D = parts["l_knee"]
	var r_knee: Node3D = parts["r_knee"]
	var l_ankle: Node3D = parts["l_ankle"]
	var r_ankle: Node3D = parts["r_ankle"]

	var decay: float = 1.0 - (timer / 2.0)
	var fast: float = sin(_time * 18.0) * decay
	var slow: float = sin(_time * 7.0) * decay
	
	pelvis.position = Vector3(0, BASE_Y + 0.9, 0)
	pelvis.rotation = Vector3(0, sin(_time * 4.0) * decay * 0.3, slow * 0.25)
	
	# Spine writhes in agony
	spine_node.rotation.z = sin(_time * 10.0) * decay * 0.3
	spine_node.rotation.x = cos(_time * 8.0) * decay * 0.15
	
	# Neck thrashes
	neck_node.rotation.x = sin(_time * 14.0) * decay * 0.25
	neck_node.rotation.z = cos(_time * 11.0) * decay * 0.2
	
	l_shoulder.rotation.x = -PI * 0.8 + fast * PI * 0.5
	r_shoulder.rotation.x = -PI * 0.8 - fast * PI * 0.5
	l_shoulder.rotation.z = slow * 0.4
	r_shoulder.rotation.z = -slow * 0.4
	
	l_elbow.rotation.x = -0.2
	r_elbow.rotation.x = -0.2
	
	# Wrists flail desperately
	l_wrist.rotation.x = sin(_time * 22.0) * decay * 0.5
	r_wrist.rotation.x = -sin(_time * 22.0) * decay * 0.5
	
	l_hip.rotation.x = fast * 0.6
	r_hip.rotation.x = -fast * 0.6
	l_knee.rotation.x = 0.5
	r_knee.rotation.x = 0.5
	
	# Ankles tense up
	l_ankle.rotation.x = -PI / 6.0 * decay
	r_ankle.rotation.x = -PI / 6.0 * decay

func _init_explosion(parts: Dictionary, is_p1: bool) -> void:
	if not parts or not parts.has("meshes"): return
	
	# Collect all meshes including hat meshes
	var all_meshes: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in parts["meshes"]:
		all_meshes.append(mesh)
	# Also add hat meshes if any
	if parts.has("hat_meshes"):
		for hat_mesh: MeshInstance3D in parts["hat_meshes"]:
			all_meshes.append(hat_mesh)
	
	var exp_data: Array[Dictionary] = []
	for mesh: MeshInstance3D in all_meshes:
		var gt = mesh.global_transform
		var old_parent = mesh.get_parent()
		if old_parent != self:
			old_parent.remove_child(mesh)
			self.add_child(mesh)
			mesh.global_transform = gt
			
		var gx = mesh.global_position.x - self.global_position.x
		var sx = 1.0 if gx >= 0 else -1.0
		
		var vel = Vector3(sx * randf_range(2.0, 6.0), randf_range(4.0, 9.0), randf_range(-3.0, 3.0))
		var rot_vel = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
		
		exp_data.append({
			"node": mesh,
			"base_pos": mesh.position,
			"base_rot": mesh.rotation,
			"velocity": vel,
			"rot_velocity": rot_vel
		})
		
	if is_p1:
		_p1_explosion_data = exp_data
	else:
		_p2_explosion_data = exp_data

func _update_explosion(is_p1: bool, timer: float, is_magma: bool = false) -> void:
	var data = _p1_explosion_data if is_p1 else _p2_explosion_data
	var gravity = 15.0
	var limit_y = -12.0 if is_magma else BASE_Y + 0.1
	var magma_surface = -9.2
	
	for d: Dictionary in data:
		var node: MeshInstance3D = d["node"]
		var base: Vector3 = d["base_pos"]
		var brot: Vector3 = d["base_rot"]
		var vel: Vector3 = d["velocity"]
		var rot_vel: Vector3 = d["rot_velocity"]
		
		var ey = base.y + vel.y * timer - 0.5 * gravity * timer * timer
		var ex = base.x + vel.x * timer
		var ez = base.z + vel.z * timer
		var current_rot = brot + rot_vel * timer
		
		# マグマに落ちた場合の処理：マグマ表面(-9.2)より下は沈み込みをゆっくりにする
		if is_magma and ey < magma_surface:
			var depth = magma_surface - ey
			ey = magma_surface - (depth * 0.05) # 沈降速度を遅らせる
			
			# マグマに浸かるとスケールを少しずつ小さくして溶ける演出にする
			var shrink = maxf(0.0, 1.0 - (depth * 0.1))
			node.scale = Vector3(shrink, shrink, shrink)
		else:
			node.scale = Vector3.ONE
		
		ey = maxf(limit_y, ey)
		
		node.position = Vector3(ex, ey, ez)
		node.rotation = current_rot
		node.visible = true


# ============================================================
# High-Quality Procedural Emotes
# ============================================================
# Each emote uses layered oscillations, secondary motion
# (follow-through on elbows/knees), weight-shifting, and
# distinct personality to feel alive and expressive.
# ============================================================

func _animate_emote(parts: Dictionary, emote: int) -> void:
	var t := _time
	if emote == 1:
		_emote_floss(t, parts) # Step Hip Hop fallback
	elif emote == 2:
		_emote_floss(t * 0.85, parts) # Gangnam fallback
	elif emote == 3:
		_emote_floss(t * 1.15, parts) # Slide Hip Hop fallback
	elif emote == 4:
		_emote_floss(t * 1.0, parts) # Flair fallback


# --- Emote 1: Floss Dance ---
# Arms swing in counter-rotation to hips. Snappy, rhythmic.
func _emote_floss(t: float, parts: Dictionary) -> void:
	var pelvis: Node3D = parts["pelvis"]
	var spine_node: Node3D = parts["spine"]
	var neck_node: Node3D = parts["neck"]
	var head: Node3D = parts["head_pivot"]
	var l_shoulder: Node3D = parts["l_shoulder"]
	var r_shoulder: Node3D = parts["r_shoulder"]
	var l_elbow: Node3D = parts["l_elbow"]
	var r_elbow: Node3D = parts["r_elbow"]
	var l_wrist: Node3D = parts["l_wrist"]
	var r_wrist: Node3D = parts["r_wrist"]
	var l_hip: Node3D = parts["l_hip"]
	var r_hip: Node3D = parts["r_hip"]
	var l_knee: Node3D = parts["l_knee"]
	var r_knee: Node3D = parts["r_knee"]
	var l_ankle: Node3D = parts["l_ankle"]
	var r_ankle: Node3D = parts["r_ankle"]

	var bpm_phase := t * 10.0
	var sharp := sin(bpm_phase)
	sharp = sign(sharp) * pow(abs(sharp), 0.6)

	pelvis.position.y = BASE_Y + 0.9
	var hip_bounce: float = abs(sin(bpm_phase * 2.0)) * 0.08
	pelvis.position.y += hip_bounce
	pelvis.rotation.y = sharp * 0.45
	pelvis.rotation.z = sin(bpm_phase) * 0.06

	# Spine counter-twist for emphasis
	spine_node.rotation.y = -sharp * 0.15
	spine_node.rotation.z = sin(bpm_phase + 0.5) * 0.04

	# Neck follows head lag
	neck_node.rotation.y = sharp * 0.08

	head.rotation.y = -sharp * 0.15
	head.rotation.x = sin(bpm_phase * 2.0) * 0.05

	var arm_swing := -sharp
	l_shoulder.rotation.x = 0.0
	l_shoulder.rotation.z = arm_swing * 0.9 + 0.1
	l_elbow.rotation.x = -0.15
	l_elbow.rotation.z = arm_swing * 0.3
	l_wrist.rotation.z = arm_swing * 0.2  # wrist follow-through

	r_shoulder.rotation.x = 0.0
	r_shoulder.rotation.z = arm_swing * 0.9 - 0.1
	r_elbow.rotation.x = -0.15
	r_elbow.rotation.z = arm_swing * 0.3
	r_wrist.rotation.z = arm_swing * 0.2

	# Legs: small alternating weight shift
	var leg_phase := sin(bpm_phase + PI / 4.0)
	l_hip.rotation.x = leg_phase * 0.15
	l_knee.rotation.x = abs(leg_phase) * 0.2
	r_hip.rotation.x = -leg_phase * 0.15
	r_knee.rotation.x = abs(-leg_phase) * 0.2


# --- Emote 2: Kazotsky Kick (Squat Dance) ---
# Alternating deep squats with leg kicks. High energy.
func _emote_kazotsky(t: float, parts: Dictionary) -> void:
	var pelvis: Node3D = parts["pelvis"]
	var spine_node: Node3D = parts["spine"]
	var neck_node: Node3D = parts["neck"]
	var head: Node3D = parts["head_pivot"]



# ============================================================
# Rigged Animation Support (Mixamo / FBX)
# ============================================================

func _apply_skeleton_pose(parts: Dictionary, skeleton: Skeleton3D, bone_indices: Dictionary, mirror_x: bool = false) -> void:
	"""毎フレーム Skeleton3D の骨座標を読み取り、ブロックのピボットに適用する"""
	if not skeleton or bone_indices.is_empty():
		return
	
	var pelvis: Node3D = parts.get("pelvis")
	if not pelvis:
		return
	
	var mirror_matrix = Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	
	# Hips（ペルビス）の位置と回転を適用
	if bone_indices.has("hips"):
		var bone_xform = skeleton.get_bone_global_pose(bone_indices["hips"])
		
		# 前進・後退のルートモーションを無効化し、Y軸（上下の揺れ）のみ適用
		pelvis.position = Vector3(
			0.0,
			BASE_Y + bone_xform.origin.y,
			0.0
		)
		
		var new_pelvis_basis = bone_xform.basis.orthonormalized()
		if mirror_x:
			new_pelvis_basis = mirror_matrix * new_pelvis_basis * mirror_matrix
		pelvis.quaternion = Quaternion(new_pelvis_basis)
	
	# 以降の各部位は、グローバル姿勢(Skeleton3D内のグローバル)をそのまま代入する。
	var apply_bone = func(part_name: String, bone_key: String, flip: bool = false):
		var node: Node3D = parts.get(part_name)
		if node and bone_indices.has(bone_key):
			var gl_pose = skeleton.get_bone_global_pose(bone_indices[bone_key])
			var new_basis = gl_pose.basis.orthonormalized()
			
			if mirror_x:
				# X軸の動きを鏡像化（行列式+1を維持しつつ左右の動きを反転）
				new_basis = mirror_matrix * new_basis * mirror_matrix
				
			if flip:
				# X軸周りに180度回転し、-Y方向が骨の+Y方向と一致するようにする
				new_basis = new_basis * Basis(Vector3.RIGHT, PI)
			node.global_basis = new_basis
	
	# 背骨・首（+Y方向に構築されているのでフリップ不要）
	apply_bone.call("spine", "spine", false)
	apply_bone.call("neck", "neck", false)
	
	# 頭（頭ブロックは+Y方向に作られているのでフリップ不要）
	apply_bone.call("head_pivot", "head", false)
	
	# 左腕・右腕（全て-Y方向に伸びて作られているのでフリップ必要）
	apply_bone.call("l_shoulder", "l_upper_arm", true)
	apply_bone.call("l_elbow", "l_lower_arm", true)
	apply_bone.call("l_wrist", "l_hand", true)
	
	apply_bone.call("r_shoulder", "r_upper_arm", true)
	apply_bone.call("r_elbow", "r_lower_arm", true)
	apply_bone.call("r_wrist", "r_hand", true)
	
	# 左脚・右脚（フリップ必要）
	apply_bone.call("l_hip", "l_upper_leg", true)
	apply_bone.call("l_knee", "l_lower_leg", true)
	apply_bone.call("l_ankle", "l_foot", true)
	apply_bone.call("l_toe", "l_toe", true)
	
	apply_bone.call("r_hip", "r_upper_leg", true)
	apply_bone.call("r_knee", "r_lower_leg", true)
	apply_bone.call("r_ankle", "r_foot", true)
	apply_bone.call("r_toe", "r_toe", true)

func bind_to_skeleton(player_id: int, skeleton: Skeleton3D) -> void:
	"""後方互換性のためのダミー関数 - 実際の処理は_apply_skeleton_poseで毎フレーム行う"""
	pass

# ============================================================
# Hat Management
# ============================================================

func set_hat(player_id: int, hat_id: int) -> void:
	"""Set a hat for the specified player (1 or 2)."""
	if player_id == 1:
		_set_hat_for_parts(p1_parts, hat_id, true)
	elif player_id == 2 and p2_parts and p2_parts.has("hat_mount"):
		_set_hat_for_parts(p2_parts, hat_id, false)

func _set_hat_for_parts(parts: Dictionary, hat_id: int, is_p1: bool) -> void:
	if not parts or not parts.has("hat_mount"):
		return
	
	var mount: Node3D = parts["hat_mount"]
	
	# Remove existing hat
	var old_hat := _p1_hat_node if is_p1 else _p2_hat_node
	if old_hat and is_instance_valid(old_hat):
		old_hat.queue_free()
	
	# Clear hat mesh references
	parts["hat_meshes"] = []
	
	if is_p1:
		_p1_hat_id = hat_id
		_p1_hat_node = null
	else:
		_p2_hat_id = hat_id
		_p2_hat_node = null
	
	if hat_id == HatData.HAT_NONE:
		return
	
	# Create new hat
	var hat_node := HatFactory.create_hat(hat_id)
	if hat_node == null:
		return
	
	mount.add_child(hat_node)
	
	# Collect hat meshes for explosion
	var hat_meshes := HatFactory.get_hat_meshes(hat_node)
	parts["hat_meshes"] = hat_meshes
	
	if is_p1:
		_p1_hat_node = hat_node
	else:
		_p2_hat_node = hat_node

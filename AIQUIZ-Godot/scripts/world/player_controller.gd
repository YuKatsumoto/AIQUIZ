extends Node3D
class_name PlayerController

## 繝悶Ο繝・け莠ｺ髢薙・繝ｬ繧､繝､繝ｼ (髢｢遽莉倥″髫主ｱ､繝｢繝・Ν)
## Python迚・renderer.py 縺ｮ _draw_player_alive / _draw_player_exploding 縺ｫ逶ｸ蠖・

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

# Animation Rig (P1/P2蜈ｱ騾壹け繝ｩ繧ｹ縺ｧ邂｡逅・
var _p1_rig: AnimationRig = AnimationRig.new("P1")
var _p2_rig: AnimationRig = AnimationRig.new("P2")

var _time: float = 0.0
const BASE_Y: float = -1.2
var _rig_debug_counter: int = 0

# ボブルヘッド（赤ベコ）バネ物理状態
var _p1_bobble: Dictionary = {"active": false, "vel_x": 0.0, "vel_z": 0.0, "angle_x": 0.0, "angle_z": 0.0, "prev_head_y": 0.0, "prev_pos_x": 0.0}
var _p2_bobble: Dictionary = {"active": false, "vel_x": 0.0, "vel_z": 0.0, "angle_x": 0.0, "angle_z": 0.0, "prev_head_y": 0.0, "prev_pos_x": 0.0}

func _ready() -> void:
	p1_parts = _build_player_skeleton(true, self)
	var gs = QuizManager.game_state
	_load_mixamo_rig(gs)

func _load_mixamo_rig(gs: QuizGameState) -> void:
	var loader := Callable(self, "_load_fbx_scene")
	var p1_slots: Array[int] = [1, 2, 3]
	var p2_slots: Array[int] = [1, 2, 3]
	if gs:
		p1_slots = gs.p1_emote_slots
		p2_slots = gs.p2_emote_slots
		
	if NetworkManager and NetworkManager.state == NetworkManager.State.IN_GAME:
		p2_slots = NetworkManager.opponent_emote_slots

	print("[RIG] _load_mixamo_rig - p1_slots: %s, p2_slots: %s" % [str(p1_slots), str(p2_slots)])
	_p1_rig.load_all(self, loader, p1_slots)
	_p2_rig.load_all(self, loader, p2_slots)
	if _p1_rig.is_rigged or _p2_rig.is_rigged:
		print("[RIG] Rig mode ENABLED for active players")
	else:
		print("[RIG] No FBX loaded - procedural mode")

func _load_fbx_scene(path: String, node_name: String) -> Variant:
	"""FBX繝輔ぃ繧､繝ｫ繧堤峡遶九す繝ｼ繝ｳ縺ｨ縺励※隱ｭ縺ｿ霎ｼ縺ｿ縲√せ繧ｱ繝ｫ繝医Φ繝ｻAP繝ｻ鬪ｨ繧､繝ｳ繝・ャ繧ｯ繧ｹ繧定ｿ斐☆"""
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
	
	# Skeleton3D 繧呈爾縺・
	var skeleton: Skeleton3D = null
	for child in node.find_children("*", "Skeleton3D", true, false):
		skeleton = child as Skeleton3D
		break
	if not skeleton:
		print("[RIG] No Skeleton3D in: ", path)
		node.queue_free()
		return null
	
	print("[RIG] [", node_name, "] Skeleton found, bones: ", skeleton.get_bone_count())
	
	# 繝｡繝・す繝･繧帝撼陦ｨ遉ｺ
	for child in node.find_children("*", "MeshInstance3D", true, false):
		child.hide()
	
	# AnimationPlayer 繧呈爾縺・
	var ap: AnimationPlayer = null
	for child in node.find_children("*", "AnimationPlayer", true, false):
		ap = child as AnimationPlayer
		break
	if not ap:
		print("[RIG] No AnimationPlayer in: ", path)
		node.queue_free()
		return null
	
	# 譛繧ゅヨ繝ｩ繝・け謨ｰ縺ｮ螟壹＞繧｢繝九Γ繝ｼ繧ｷ繝ｧ繝ｳ縲√∪縺溘・ "mixamo_com" 繧呈ｭ｣隗｣縺ｨ縺吶ｋ
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
				max_tracks = 9999 # 蠑ｷ蛻ｶ逧・↓譛蜆ｪ蜈・
			elif tracks_count > max_tracks:
				max_tracks = tracks_count
				if anim_name == "" or not ("mixamo_com" in anim_name):
					anim_name = full
					
	if anim_name != "":
		var anim = ap.get_animation(anim_name)
		if anim:
			var duplicated_anim = anim.duplicate()
			duplicated_anim.loop_mode = Animation.LOOP_LINEAR
			
			var split_idx = anim_name.find("/")
			var lib_name = ""
			var real_anim_name = anim_name
			if split_idx != -1:
				lib_name = anim_name.substr(0, split_idx)
				real_anim_name = anim_name.substr(split_idx + 1)
			
			var lib = ap.get_animation_library(lib_name)
			if lib:
				lib.add_animation(real_anim_name, duplicated_anim)
				print("[RIG]   [", node_name, "] Duplicated animation and set loop_mode: ", anim_name)
	
	# 鬪ｨ繧､繝ｳ繝・ャ繧ｯ繧ｹ繧偵く繝｣繝・す繝･
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
		"r_toe": ["RightToeBase", "mixamorig:RightToeBase"],
		
		# Fingers (Left)
		"l_thumb_prox": ["LeftThumbMetacarpal", "mixamorig:LeftHandThumb1", "mixamorig_LeftHandThumb1", "LeftHandThumb1"],
		"l_thumb_dist": ["LeftThumbProximal", "mixamorig:LeftHandThumb2", "mixamorig_LeftHandThumb2", "LeftHandThumb2"],
		"l_index_prox": ["LeftIndexProximal", "mixamorig:LeftHandIndex1", "mixamorig_LeftHandIndex1", "LeftHandIndex1"],
		"l_index_mid": ["LeftIndexIntermediate", "mixamorig:LeftHandIndex2", "mixamorig_LeftHandIndex2", "LeftHandIndex2"],
		"l_index_dist": ["LeftIndexDistal", "mixamorig:LeftHandIndex3", "mixamorig_LeftHandIndex3", "LeftHandIndex3"],
		"l_middle_prox": ["LeftMiddleProximal", "mixamorig:LeftHandMiddle1", "mixamorig_LeftHandMiddle1", "LeftHandMiddle1"],
		"l_middle_mid": ["LeftMiddleIntermediate", "mixamorig:LeftHandMiddle2", "mixamorig_LeftHandMiddle2", "LeftHandMiddle2"],
		"l_middle_dist": ["LeftMiddleDistal", "mixamorig:LeftHandMiddle3", "mixamorig_LeftHandMiddle3", "LeftHandMiddle3"],
		"l_ring_prox": ["LeftRingProximal", "mixamorig:LeftHandRing1", "mixamorig_LeftHandRing1", "LeftHandRing1"],
		"l_ring_mid": ["LeftRingIntermediate", "mixamorig:LeftHandRing2", "mixamorig_LeftHandRing2", "LeftHandRing2"],
		"l_ring_dist": ["LeftRingDistal", "mixamorig:LeftHandRing3", "mixamorig_LeftHandRing3", "LeftHandRing3"],
		"l_pinky_prox": ["LeftLittleProximal", "mixamorig:LeftHandPinky1", "mixamorig_LeftHandPinky1", "LeftHandPinky1"],
		"l_pinky_mid": ["LeftLittleIntermediate", "mixamorig:LeftHandPinky2", "mixamorig_LeftHandPinky2", "LeftHandPinky2"],
		"l_pinky_dist": ["LeftLittleDistal", "mixamorig:LeftHandPinky3", "mixamorig_LeftHandPinky3", "LeftHandPinky3"],
		
		# Fingers (Right)
		"r_thumb_prox": ["RightThumbMetacarpal", "mixamorig:RightHandThumb1", "mixamorig_RightHandThumb1", "RightHandThumb1"],
		"r_thumb_dist": ["RightThumbProximal", "mixamorig:RightHandThumb2", "mixamorig_RightHandThumb2", "RightHandThumb2"],
		"r_index_prox": ["RightIndexProximal", "mixamorig:RightHandIndex1", "mixamorig_RightHandIndex1", "RightHandIndex1"],
		"r_index_mid": ["RightIndexIntermediate", "mixamorig:RightHandIndex2", "mixamorig_RightHandIndex2", "RightHandIndex2"],
		"r_index_dist": ["RightIndexDistal", "mixamorig:RightHandIndex3", "mixamorig_RightHandIndex3", "RightHandIndex3"],
		"r_middle_prox": ["RightMiddleProximal", "mixamorig:RightHandMiddle1", "mixamorig_RightHandMiddle1", "RightHandMiddle1"],
		"r_middle_mid": ["RightMiddleIntermediate", "mixamorig:RightHandMiddle2", "mixamorig_RightHandMiddle2", "RightHandMiddle2"],
		"r_middle_dist": ["RightMiddleDistal", "mixamorig:RightHandMiddle3", "mixamorig_RightHandMiddle3", "RightHandMiddle3"],
		"r_ring_prox": ["RightRingProximal", "mixamorig:RightHandRing1", "mixamorig_RightHandRing1", "RightHandRing1"],
		"r_ring_mid": ["RightRingIntermediate", "mixamorig:RightHandRing2", "mixamorig_RightHandRing2", "RightHandRing2"],
		"r_ring_dist": ["RightRingDistal", "mixamorig:RightHandRing3", "mixamorig_RightHandRing3", "RightHandRing3"],
		"r_pinky_prox": ["RightLittleProximal", "mixamorig:RightHandPinky1", "mixamorig_RightHandPinky1", "RightHandPinky1"],
		"r_pinky_mid": ["RightLittleIntermediate", "mixamorig:RightHandPinky2", "mixamorig_RightHandPinky2", "RightHandPinky2"],
		"r_pinky_dist": ["RightLittleDistal", "mixamorig:RightHandPinky3", "mixamorig_RightHandPinky3", "RightHandPinky3"]
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

# 髫主ｱ､讒矩縺ｮ讒狗ｯ・
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

	# Spine pivot (between lower and upper torso) 窶・enables upper body twist
	var spine = Node3D.new()
	spine.name = "Spine"
	spine.position = Vector3(0, 0.30, 0)
	pelvis.add_child(spine)
	parts["spine"] = spine

	# Upper Torso (chest) 窶・child of spine
	var upper_torso = _create_box(Vector3(0.38, 0.26, 0.22), body_col)
	upper_torso.position = Vector3(0, 0.18, 0)
	spine.add_child(upper_torso)
	parts["upper_torso"] = upper_torso

	# Neck pivot 窶・child of spine
	var neck = Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, 0.42, 0)
	spine.add_child(neck)
	parts["neck"] = neck

	# Head pivot 窶・child of neck
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

	var l_hand_data = _create_detailed_hand(limb_col, true, parts, "l_")
	var l_hand = l_hand_data["root"]
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

	var r_hand_data = _create_detailed_hand(limb_col, false, parts, "r_")
	var r_hand = r_hand_data["root"]
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
	var m_list: Array[MeshInstance3D] = [
		lower_torso, upper_torso, head,
		l_upp_arm, l_low_arm,
		r_upp_arm, r_low_arm,
		l_thigh, l_calf, l_foot, l_toe_mesh,
		r_thigh, r_calf, r_foot, r_toe_mesh
	]
	
	for m in l_hand_data["meshes"]:
		m_list.append(m)
	for m in r_hand_data["meshes"]:
		m_list.append(m)
		
	parts["meshes"] = m_list
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

var _run_phase: float = 0.0

func _process(dt: float) -> void:
	_time += dt
	var gs = QuizManager.game_state
	var speed: float = gs._active_wall_speed if gs else 3.5
	var mult := 1.0
	if Input.is_key_pressed(KEY_W):
		mult = 2.0
	_run_phase += dt * 8.0 * (speed / 3.5) * mult

func update_from_state(gs: QuizGameState) -> void:
	var pz: float = gs.player_z
	var walk_phase: float = _run_phase
	var mult := 1.0
	if Input.is_key_pressed(KEY_W):
		mult = 2.0
	var speed_ratio: float = clampf((gs._active_wall_speed / 3.5) * mult, 0.3, 6.0)

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
		if not _p1_rig.is_rigged:
			var p1_is_playing := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
			_animate_skeleton(p1_parts, gs.player_y, gs.player_vel_y, p1_is_playing, walk_phase, false, gs.p1_emote)
		else:
			var is_active := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
			var apply_rig := _p1_rig.select_animation(
				gs.player_y, gs.p1_jump_trigger, gs.p1_emote,
				gs.p1_moving_back, is_active, _p1_rig.is_jump_playing())
			
			if apply_rig:
				_apply_skeleton_pose(p1_parts, _p1_rig.active_skeleton, _p1_rig.active_bone_indices, _p1_rig.mirror_x)
				var run_ap := _p1_rig.aps[1] as AnimationPlayer # SLOT_RUN
				if run_ap and run_ap.is_playing():
					run_ap.speed_scale = speed_ratio
			else:
				_animate_skeleton(p1_parts, gs.player_y, gs.player_vel_y, false, walk_phase, false, 0)
			# FBXリグモードでもボブルヘッドを更新
			_update_bobblehead(p1_parts, false, is_active, walk_phase)
	elif gs.game_over_timer > 0:
		if gs.game_over_timer < 2.0:
			_set_parts_visible(p1_parts, true)
			var apply_rig := false
			if _p1_rig.is_rigged and _p1_rig.play_slot(AnimationRig.SLOT_DROWNING):
				apply_rig = true
				_apply_skeleton_pose(p1_parts, _p1_rig.active_skeleton, _p1_rig.active_bone_indices, _p1_rig.mirror_x)
			
			if not apply_rig:
				# FBX縺後↑縺・√∪縺溘・繝槭げ繝樔ｻ･螟悶・豁ｻ蝗逕ｨ
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
			_update_explosion(true, gs.game_over_timer - 2.0, is_magma, gs.is_coop_mode(), -global_position.x)
	else:
		_set_parts_visible(p1_parts, false)

	# --- Player 2 ---
	if gs.num_players >= 2 and p2_container:
		p2_container.position = Vector3(gs.player2_x - gs.player_x, gs.player2_y - gs.player_y, gs.player2_local_z - gs.player_local_z)
		
		if gs.p2_alive:
			_p2_exploding = false
			_set_parts_visible(p2_parts, true)
			if not _p2_rig.is_rigged:
				var p2_is_playing := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
				_animate_skeleton(p2_parts, gs.player2_y, gs.player2_vel_y, p2_is_playing, walk_phase * 1.1, true, gs.p2_emote)
			else:
				var is_active := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
				var apply_rig := _p2_rig.select_animation(
					gs.player2_y, gs.p2_jump_trigger, gs.p2_emote,
					gs.p2_moving_back, is_active, _p2_rig.is_jump_playing())
				
				if apply_rig:
					_apply_skeleton_pose(p2_parts, _p2_rig.active_skeleton, _p2_rig.active_bone_indices, _p2_rig.mirror_x)
					var run_ap := _p2_rig.aps[1] as AnimationPlayer # SLOT_RUN
					if run_ap and run_ap.is_playing():
						run_ap.speed_scale = speed_ratio
				else:
					_animate_skeleton(p2_parts, gs.player2_y, gs.player2_vel_y, false, walk_phase * 1.1, true, 0)
				# FBXリグモードでもボブルヘッドを更新
				_update_bobblehead(p2_parts, true, is_active, walk_phase * 1.1)
		elif gs.player2_game_over_timer > 0:
			if gs.player2_game_over_timer < 2.0:
				_set_parts_visible(p2_parts, true)
				var apply_rig := false
				if _p2_rig.is_rigged and _p2_rig.play_slot(AnimationRig.SLOT_DROWNING):
					apply_rig = true
					_apply_skeleton_pose(p2_parts, _p2_rig.active_skeleton, _p2_rig.active_bone_indices, _p2_rig.mirror_x)
					
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
				_update_explosion(false, gs.player2_game_over_timer - 2.0, is_magma, gs.is_coop_mode(), -global_position.x)
		else:
			_set_parts_visible(p2_parts, false)

	# 1P: only show player body during game over explosion, flyover, menu, or replay
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

	# Base resets 窶・all joints
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
		# Flail 窶・falling into magma
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
			_animate_emote(parts, emote, is_p2)
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
		
		# Hat sway animation
		_update_bobblehead(parts, is_p2, is_playing, phase)

func _update_bobblehead(parts: Dictionary, is_p2: bool, is_playing: bool, phase: float) -> void:
	"""帽子のボブルヘッド/スウェイアニメーション更新（_animate_skeletonとFBXリグの両方から呼ばれる）"""
	if not parts.has("hat_mount") or parts["hat_mount"] == null:
		return
	var hat_m: Node3D = parts["hat_mount"]
	var bobble: Dictionary = _p1_bobble if not is_p2 else _p2_bobble
	
	if bobble["active"]:
		# 赤ベコモード: バネ物理で首を揺らす
		var spring_k: float = 18.0
		var damping: float = 3.5
		var max_angle: float = 0.4
		var delta: float = get_process_delta_time()
		
		var head_pivot: Node3D = parts.get("head_pivot", null)
		var force_x: float = 0.0
		var force_z: float = 0.0
		
		if head_pivot:
			var current_head_rot: float = head_pivot.rotation.x
			var head_delta: float = current_head_rot - float(bobble["prev_head_y"])
			bobble["prev_head_y"] = current_head_rot
			force_x += head_delta * 8.0
		
		if is_playing:
			force_x += sin(phase * 2.0) * 0.8
			force_z += cos(phase * 1.3) * 0.5
		
		var accel_x: float = -spring_k * float(bobble["angle_x"]) - damping * float(bobble["vel_x"]) + force_x * 6.0
		var accel_z: float = -spring_k * float(bobble["angle_z"]) - damping * float(bobble["vel_z"]) + force_z * 6.0
		bobble["vel_x"] = float(bobble["vel_x"]) + accel_x * delta
		bobble["vel_z"] = float(bobble["vel_z"]) + accel_z * delta
		bobble["angle_x"] = float(bobble["angle_x"]) + float(bobble["vel_x"]) * delta
		bobble["angle_z"] = float(bobble["angle_z"]) + float(bobble["vel_z"]) * delta
		
		bobble["angle_x"] = clampf(float(bobble["angle_x"]), -max_angle, max_angle)
		bobble["angle_z"] = clampf(float(bobble["angle_z"]), -max_angle, max_angle)
		
		hat_m.rotation.x = float(bobble["angle_x"])
		hat_m.rotation.z = float(bobble["angle_z"])
	elif is_playing:
		var hat_sway_x := sin(phase + 0.3) * 0.06
		var hat_sway_z := sin(phase * 0.7 + 0.5) * 0.04
		hat_m.rotation.x = hat_sway_x
		hat_m.rotation.z = hat_sway_z
	else:
		if not bobble["active"]:
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

func _create_detailed_hand(color: Color, is_left: bool, parts: Dictionary, prefix: String) -> Dictionary:
	var hand_root = Node3D.new()
	var meshes: Array = []

	# Palm
	var palm = _create_box(Vector3(0.09, 0.10, 0.05), color)
	palm.position = Vector3(0, -0.10, 0)
	hand_root.add_child(palm)
	meshes.append(palm)

	# Thumb - 2 segments
	var thumb_root = Node3D.new()
	var thumb_x = 0.10 if is_left else -0.10
	thumb_root.position = Vector3(thumb_x, -0.05, 0.04)
	thumb_root.rotation = Vector3(deg_to_rad(-20), deg_to_rad(45 if is_left else -45), deg_to_rad(30 if is_left else -30))
	hand_root.add_child(thumb_root)
	parts[prefix + "thumb_prox"] = thumb_root

	var thumb_prox = _create_box(Vector3(0.025, 0.04, 0.03), color)
	thumb_prox.position = Vector3(0, -0.04, 0)
	thumb_root.add_child(thumb_prox)
	meshes.append(thumb_prox)

	var thumb_joint = Node3D.new()
	thumb_joint.position = Vector3(0, -0.08, 0)
	thumb_joint.rotation = Vector3(deg_to_rad(-15), 0, 0)
	thumb_root.add_child(thumb_joint)
	parts[prefix + "thumb_dist"] = thumb_joint

	var thumb_dist = _create_box(Vector3(0.025, 0.035, 0.03), color)
	thumb_dist.position = Vector3(0, -0.035, 0)
	thumb_joint.add_child(thumb_dist)
	meshes.append(thumb_dist)

	# Fingers - 3 segments
	var finger_lengths = [0.08, 0.09, 0.085, 0.065]
	var finger_widths = 0.022
	var finger_depths = 0.025

	var finger_names = ["index", "middle", "ring", "pinky"]

	for i in range(4):
		var fname = finger_names[i]
		var base_length = finger_lengths[i]

		var finger_root = Node3D.new()
		var offset_x = (0.066 - (i * 0.044)) if is_left else (-0.066 + (i * 0.044))
		finger_root.position = Vector3(offset_x, -0.20, 0.0)

		var spread_angle = deg_to_rad((1.5 - i) * 5)
		if not is_left:
			spread_angle = -spread_angle
		finger_root.rotation = Vector3(deg_to_rad(-5), 0, spread_angle)
		hand_root.add_child(finger_root)
		parts[prefix + fname + "_prox"] = finger_root

		# Proximal
		var prox_len = base_length * 0.4
		var prox = _create_box(Vector3(finger_widths, prox_len, finger_depths), color)
		prox.position = Vector3(0, -prox_len, 0)
		finger_root.add_child(prox)
		meshes.append(prox)

		var joint1 = Node3D.new()
		joint1.position = Vector3(0, -prox_len * 2, 0)
		joint1.rotation = Vector3(deg_to_rad(-10), 0, 0)
		finger_root.add_child(joint1)
		parts[prefix + fname + "_mid"] = joint1

		# Middle
		var mid_len = base_length * 0.35
		var mid = _create_box(Vector3(finger_widths, mid_len, finger_depths), color)
		mid.position = Vector3(0, -mid_len, 0)
		joint1.add_child(mid)
		meshes.append(mid)

		var joint2 = Node3D.new()
		joint2.position = Vector3(0, -mid_len * 2, 0)
		joint2.rotation = Vector3(deg_to_rad(-10), 0, 0)
		joint1.add_child(joint2)
		parts[prefix + fname + "_dist"] = joint2

		# Distal
		var dist_len = base_length * 0.25
		var dist = _create_box(Vector3(finger_widths, dist_len, finger_depths), color)
		dist.position = Vector3(0, -dist_len, 0)
		joint2.add_child(dist)
		meshes.append(dist)

	return {"root": hand_root, "meshes": meshes}

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
			"base_scale": mesh.scale,
			"velocity": vel,
			"rot_velocity": rot_vel,
			"groove_offset": randf_range(-0.42, 0.42)
		})
		
	if is_p1:
		_p1_explosion_data = exp_data
	else:
		_p2_explosion_data = exp_data

func _update_explosion(
		is_p1: bool,
		timer: float,
		is_magma: bool = false,
		fall_to_groove: bool = false,
		groove_local_x: float = 0.0) -> void:
	var data = _p1_explosion_data if is_p1 else _p2_explosion_data
	var gravity = 15.0
	var should_sink := is_magma or fall_to_groove
	var limit_y = -12.0 if should_sink else BASE_Y + 0.1
	var magma_surface = -9.2
	
	for d: Dictionary in data:
		var node: MeshInstance3D = d["node"]
		var base: Vector3 = d["base_pos"]
		var brot: Vector3 = d["base_rot"]
		var bscale: Vector3 = d.get("base_scale", Vector3.ONE)
		var vel: Vector3 = d["velocity"]
		var rot_vel: Vector3 = d["rot_velocity"]
		
		var ey = base.y + vel.y * timer - 0.5 * gravity * timer * timer
		var ex = base.x + vel.x * timer
		var ez = base.z + vel.z * timer
		var current_rot = brot + rot_vel * timer

		if fall_to_groove:
			var groove_pull := clampf(timer / 1.8, 0.0, 1.0)
			groove_pull = 1.0 - pow(1.0 - groove_pull, 2.0)
			ex = lerpf(ex, groove_local_x + float(d.get("groove_offset", 0.0)), groove_pull)
		
		# Magma sink logic: slow down falling and shrink fragments
		if should_sink and ey < magma_surface:
			var depth = magma_surface - ey
			ey = magma_surface - (depth * 0.05) # Slower sink velocity
			
			# Shrink fragments over time when sunk
			var shrink = maxf(0.0, 1.0 - (depth * 0.1))
			node.scale = bscale * shrink
		else:
			node.scale = bscale
		
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

func _animate_emote(parts: Dictionary, emote: int, is_p2: bool = false) -> void:
	var t := _time
	var slots = _p2_rig.loaded_emotes if is_p2 else _p1_rig.loaded_emotes
	var idx = slots.find(emote)
	if idx == 0:
		_emote_floss(t, parts) # Step Hip Hop fallback
	elif idx == 1:
		_emote_floss(t * 0.85, parts) # Gangnam fallback
	elif idx == 2:
		_emote_floss(t * 1.15, parts) # Slide Hip Hop fallback
	else:
		_emote_floss(t * 1.0, parts) # Default fallback


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
	"""豈弱ヵ繝ｬ繝ｼ繝 Skeleton3D 縺ｮ鬪ｨ蠎ｧ讓吶ｒ隱ｭ縺ｿ蜿悶ｊ縲√ヶ繝ｭ繝・け縺ｮ繝斐・繝・ヨ縺ｫ驕ｩ逕ｨ縺吶ｋ"""
	if not skeleton or bone_indices.is_empty():
		return
	
	var pelvis: Node3D = parts.get("pelvis")
	if not pelvis:
		return
	
	var mirror_matrix = Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	
	# Hips・医・繝ｫ繝薙せ・峨・菴咲ｽｮ縺ｨ蝗櫁ｻ｢繧帝←逕ｨ
	if bone_indices.has("hips"):
		var bone_xform = skeleton.get_bone_global_pose(bone_indices["hips"])
		
		# 蜑埼€ｲ繝ｻ蠕碁€€縺ｮ繝ｫ繝ｼ繝医Δ繝ｼ繧ｷ繝ｧ繝ｳ繧堤┌蜉ｹ蛹悶＠縲〆霆ｸ・井ｸ贋ｸ九・謠ｺ繧鯉ｼ峨・縺ｿ驕ｩ逕ｨ
		pelvis.position = Vector3(
			0.0,
			BASE_Y + bone_xform.origin.y,
			0.0
		)
		
		var new_pelvis_basis = bone_xform.basis.orthonormalized()
		if mirror_x:
			new_pelvis_basis = mirror_matrix * new_pelvis_basis * mirror_matrix
		pelvis.quaternion = Quaternion(new_pelvis_basis)
	
	# 莉･髯阪・蜷・Κ菴阪・縲√げ繝ｭ繝ｼ繝舌Ν蟋ｿ蜍｢(Skeleton3D蜀・・繧ｰ繝ｭ繝ｼ繝舌Ν)繧偵◎縺ｮ縺ｾ縺ｾ莉｣蜈･縺吶ｋ縲・
	var apply_bone = func(part_name: String, bone_key: String, flip: bool = false):
		var node: Node3D = parts.get(part_name)
		if node and bone_indices.has(bone_key):
			var gl_pose = skeleton.get_bone_global_pose(bone_indices[bone_key])
			var new_basis = gl_pose.basis.orthonormalized()
			
			if mirror_x:
				# X霆ｸ縺ｮ蜍輔″繧帝升蜒丞喧・郁｡悟・蠑・1繧堤ｶｭ謖√＠縺､縺､蟾ｦ蜿ｳ縺ｮ蜍輔″繧貞渚霆｢・・
				new_basis = mirror_matrix * new_basis * mirror_matrix
				
			if flip:
				# X霆ｸ蜻ｨ繧翫↓180蠎ｦ蝗櫁ｻ｢縺励€・Y譁ｹ蜷代′鬪ｨ縺ｮ+Y譁ｹ蜷代→荳€閾ｴ縺吶ｋ繧医≧縺ｫ縺吶ｋ
				new_basis = new_basis * Basis(Vector3.RIGHT, PI)
			node.global_basis = new_basis
	
	# 閭碁ｪｨ繝ｻ鬥厄ｼ・Y譁ｹ蜷代↓讒狗ｯ峨＆繧後※縺・ｋ縺ｮ縺ｧ繝輔Μ繝・・荳崎ｦ・ｼ・
	apply_bone.call("spine", "spine", false)
	apply_bone.call("neck", "neck", false)
	
	# 鬆ｭ・磯ｭ繝悶Ο繝・け縺ｯ+Y譁ｹ蜷代↓菴懊ｉ繧後※縺・ｋ縺ｮ縺ｧ繝輔Μ繝・・荳崎ｦ・ｼ・
	apply_bone.call("head_pivot", "head", false)
	
	# 蟾ｦ閻輔・蜿ｳ閻包ｼ亥・縺ｦ-Y譁ｹ蜷代↓莨ｸ縺ｳ縺ｦ菴懊ｉ繧後※縺・ｋ縺ｮ縺ｧ繝輔Μ繝・・蠢・ｦ・ｼ・
	apply_bone.call("l_shoulder", "l_upper_arm", true)
	apply_bone.call("l_elbow", "l_lower_arm", true)
	apply_bone.call("l_wrist", "l_hand", true)
	
	apply_bone.call("r_shoulder", "r_upper_arm", true)
	apply_bone.call("r_elbow", "r_lower_arm", true)
	apply_bone.call("r_wrist", "r_hand", true)
	
	# 蟾ｦ閼壹・蜿ｳ閼夲ｼ医ヵ繝ｪ繝・・蠢・ｦ・ｼ・
	apply_bone.call("l_hip", "l_upper_leg", true)
	apply_bone.call("l_knee", "l_lower_leg", true)
	apply_bone.call("l_ankle", "l_foot", true)
	apply_bone.call("l_toe", "l_toe", true)
	
	apply_bone.call("r_hip", "r_upper_leg", true)
	apply_bone.call("r_knee", "r_lower_leg", true)
	apply_bone.call("r_ankle", "r_foot", true)
	apply_bone.call("r_toe", "r_toe", true)
	
	# Fingers (left)
	apply_bone.call("l_thumb_prox", "l_thumb_prox", true)
	apply_bone.call("l_thumb_dist", "l_thumb_dist", true)
	apply_bone.call("l_index_prox", "l_index_prox", true)
	apply_bone.call("l_index_mid", "l_index_mid", true)
	apply_bone.call("l_index_dist", "l_index_dist", true)
	apply_bone.call("l_middle_prox", "l_middle_prox", true)
	apply_bone.call("l_middle_mid", "l_middle_mid", true)
	apply_bone.call("l_middle_dist", "l_middle_dist", true)
	apply_bone.call("l_ring_prox", "l_ring_prox", true)
	apply_bone.call("l_ring_mid", "l_ring_mid", true)
	apply_bone.call("l_ring_dist", "l_ring_dist", true)
	apply_bone.call("l_pinky_prox", "l_pinky_prox", true)
	apply_bone.call("l_pinky_mid", "l_pinky_mid", true)
	apply_bone.call("l_pinky_dist", "l_pinky_dist", true)
	
	# Fingers (right)
	apply_bone.call("r_thumb_prox", "r_thumb_prox", true)
	apply_bone.call("r_thumb_dist", "r_thumb_dist", true)
	apply_bone.call("r_index_prox", "r_index_prox", true)
	apply_bone.call("r_index_mid", "r_index_mid", true)
	apply_bone.call("r_index_dist", "r_index_dist", true)
	apply_bone.call("r_middle_prox", "r_middle_prox", true)
	apply_bone.call("r_middle_mid", "r_middle_mid", true)
	apply_bone.call("r_middle_dist", "r_middle_dist", true)
	apply_bone.call("r_ring_prox", "r_ring_prox", true)
	apply_bone.call("r_ring_mid", "r_ring_mid", true)
	apply_bone.call("r_ring_dist", "r_ring_dist", true)
	apply_bone.call("r_pinky_prox", "r_pinky_prox", true)
	apply_bone.call("r_pinky_mid", "r_pinky_mid", true)
	apply_bone.call("r_pinky_dist", "r_pinky_dist", true)

func bind_to_skeleton(player_id: int, skeleton: Skeleton3D) -> void:
	"""蠕梧婿莠呈鋤諤ｧ縺ｮ縺溘ａ縺ｮ繝繝溘・髢｢謨ｰ - 螳滄圀縺ｮ蜃ｦ逅・・_apply_skeleton_pose縺ｧ豈弱ヵ繝ｬ繝ｼ繝陦後≧"""
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
	
	# ボブルヘッドフラグを設定
	var bobble: Dictionary = _p1_bobble if is_p1 else _p2_bobble
	bobble["active"] = HatFactory.is_bobblehead(hat_id)
	bobble["vel_x"] = 0.0
	bobble["vel_z"] = 0.0
	bobble["angle_x"] = 0.0
	bobble["angle_z"] = 0.0
	
	if is_p1:
		_p1_hat_node = hat_node
	else:
		_p2_hat_node = hat_node

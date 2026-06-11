extends RefCounted
class_name EmoteBlockmanPreview

## エモートFBXの Skeleton を読み取り、ゲーム本体と同じブロック人形へポーズを転写するプレビュー用ヘルパー。
const BASE_Y: float = -1.2


static func map_mixamo_bones(skeleton: Skeleton3D) -> Dictionary:
	var bone_indices := {}
	if not skeleton:
		return bone_indices
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
		"r_pinky_dist": ["RightLittleDistal", "mixamorig:RightHandPinky3", "mixamorig_RightHandPinky3", "RightHandPinky3"],
	}
	for key in candidates.keys():
		for cand in candidates[key]:
			var idx := skeleton.find_bone(cand)
			if idx != -1:
				bone_indices[key] = idx
				break
	return bone_indices


## エモートFBXの AnimationPlayer から「踊り本体」のアニメ名を選ぶ。
## mixamo_com を最優先、無ければトラック数最大のものを採用。
static func pick_best_emote_animation(ap: AnimationPlayer) -> String:
	if not ap:
		return ""
	var best_name := ""
	var best_tracks := -1
	for lib_name in ap.get_animation_library_list():
		var lib: AnimationLibrary = ap.get_animation_library(lib_name)
		for a_name in lib.get_animation_list():
			var full: String = str(lib_name) + "/" + str(a_name) if str(lib_name) != "" else str(a_name)
			var anim: Animation = lib.get_animation(a_name)
			if "mixamo_com" in a_name:
				best_name = full
				best_tracks = 9999
			elif anim.get_track_count() > best_tracks:
				best_tracks = anim.get_track_count()
				if not ("mixamo_com" in best_name):
					best_name = full
	return best_name


static func build_player_skeleton(is_p1: bool, parent_node: Node3D, hat_id: int) -> Dictionary:
	var body_col: Color = PlayerController.P1_BODY if is_p1 else PlayerController.P2_BODY
	var head_col: Color = PlayerController.P1_HEAD if is_p1 else PlayerController.P2_HEAD
	var limb_col: Color = PlayerController.P1_LIMB if is_p1 else PlayerController.P2_LIMB

	var parts := {}

	var pelvis := Node3D.new()
	pelvis.name = "Pelvis"
	pelvis.position = Vector3(0, BASE_Y + 0.9, 0)
	parent_node.add_child(pelvis)
	parts["pelvis"] = pelvis

	var lower_torso := _create_box(Vector3(0.38, 0.22, 0.22), body_col)
	lower_torso.position = Vector3(0, 0.15, 0)
	pelvis.add_child(lower_torso)
	parts["lower_torso"] = lower_torso

	var spine := Node3D.new()
	spine.name = "Spine"
	spine.position = Vector3(0, 0.30, 0)
	pelvis.add_child(spine)
	parts["spine"] = spine

	var upper_torso := _create_box(Vector3(0.38, 0.26, 0.22), body_col)
	upper_torso.position = Vector3(0, 0.18, 0)
	spine.add_child(upper_torso)
	parts["upper_torso"] = upper_torso

	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, 0.42, 0)
	spine.add_child(neck)
	parts["neck"] = neck

	var head_pivot := Node3D.new()
	head_pivot.position = Vector3(0, 0.03, 0)
	neck.add_child(head_pivot)
	parts["head_pivot"] = head_pivot

	var head := _create_box(Vector3(0.22, 0.22, 0.22), head_col)
	head.position = Vector3(0, 0.22, 0)
	head_pivot.add_child(head)
	parts["head"] = head

	var hat_mount := Node3D.new()
	hat_mount.name = "HatMount"
	hat_mount.position = Vector3(0, 0.44, 0)
	head_pivot.add_child(hat_mount)
	parts["hat_mount"] = hat_mount

	if hat_id != HatData.HAT_NONE:
		var hat_node := HatFactory.create_hat(hat_id)
		if hat_node:
			hat_mount.add_child(hat_node)

	var l_shoulder := Node3D.new()
	l_shoulder.position = Vector3(-0.52, 0.35, 0)
	spine.add_child(l_shoulder)
	parts["l_shoulder"] = l_shoulder

	var l_upp_arm := _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	l_upp_arm.position = Vector3(0, -0.20, 0)
	l_shoulder.add_child(l_upp_arm)
	parts["l_upp_arm"] = l_upp_arm

	var l_elbow := Node3D.new()
	l_elbow.position = Vector3(0, -0.40, 0)
	l_shoulder.add_child(l_elbow)
	parts["l_elbow"] = l_elbow

	var l_low_arm := _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	l_low_arm.position = Vector3(0, -0.20, 0)
	l_elbow.add_child(l_low_arm)
	parts["l_low_arm"] = l_low_arm

	var l_wrist := Node3D.new()
	l_wrist.position = Vector3(0, -0.40, 0)
	l_elbow.add_child(l_wrist)
	parts["l_wrist"] = l_wrist

	var l_hand_data := _create_detailed_hand(limb_col, true, parts, "l_")
	var l_hand: Node3D = l_hand_data["root"] as Node3D
	l_wrist.add_child(l_hand)
	parts["l_hand"] = l_hand

	var r_shoulder := Node3D.new()
	r_shoulder.position = Vector3(0.52, 0.35, 0)
	spine.add_child(r_shoulder)
	parts["r_shoulder"] = r_shoulder

	var r_upp_arm := _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	r_upp_arm.position = Vector3(0, -0.20, 0)
	r_shoulder.add_child(r_upp_arm)
	parts["r_upp_arm"] = r_upp_arm

	var r_elbow := Node3D.new()
	r_elbow.position = Vector3(0, -0.40, 0)
	r_shoulder.add_child(r_elbow)
	parts["r_elbow"] = r_elbow

	var r_low_arm := _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	r_low_arm.position = Vector3(0, -0.20, 0)
	r_elbow.add_child(r_low_arm)
	parts["r_low_arm"] = r_low_arm

	var r_wrist := Node3D.new()
	r_wrist.position = Vector3(0, -0.40, 0)
	r_elbow.add_child(r_wrist)
	parts["r_wrist"] = r_wrist

	var r_hand_data := _create_detailed_hand(limb_col, false, parts, "r_")
	var r_hand: Node3D = r_hand_data["root"] as Node3D
	r_wrist.add_child(r_hand)
	parts["r_hand"] = r_hand

	var l_hip := Node3D.new()
	l_hip.position = Vector3(-0.22, 0.0, 0)
	pelvis.add_child(l_hip)
	parts["l_hip"] = l_hip

	var l_thigh := _create_box(Vector3(0.18, 0.285, 0.18), limb_col)
	l_thigh.position = Vector3(0, -0.225, 0)
	l_hip.add_child(l_thigh)
	parts["l_thigh"] = l_thigh

	var l_knee := Node3D.new()
	l_knee.position = Vector3(0, -0.45, 0)
	l_hip.add_child(l_knee)
	parts["l_knee"] = l_knee

	var l_calf := _create_box(Vector3(0.16, 0.285, 0.16), limb_col)
	l_calf.position = Vector3(0, -0.225, 0)
	l_knee.add_child(l_calf)
	parts["l_calf"] = l_calf

	var l_ankle := Node3D.new()
	l_ankle.position = Vector3(0, -0.45, 0)
	l_knee.add_child(l_ankle)
	parts["l_ankle"] = l_ankle

	var l_foot := _create_box(Vector3(0.14, 0.06, 0.22), limb_col)
	l_foot.position = Vector3(0, -0.06, 0.05)
	l_ankle.add_child(l_foot)
	parts["l_foot"] = l_foot

	var l_toe := Node3D.new()
	l_toe.position = Vector3(0, -0.06, 0.22)
	l_ankle.add_child(l_toe)
	parts["l_toe"] = l_toe

	var l_toe_mesh := _create_box(Vector3(0.12, 0.04, 0.08), limb_col)
	l_toe_mesh.position = Vector3(0, -0.02, 0.04)
	l_toe.add_child(l_toe_mesh)
	parts["l_toe_mesh"] = l_toe_mesh

	var r_hip := Node3D.new()
	r_hip.position = Vector3(0.22, 0.0, 0)
	pelvis.add_child(r_hip)
	parts["r_hip"] = r_hip

	var r_thigh := _create_box(Vector3(0.18, 0.285, 0.18), limb_col)
	r_thigh.position = Vector3(0, -0.225, 0)
	r_hip.add_child(r_thigh)
	parts["r_thigh"] = r_thigh

	var r_knee := Node3D.new()
	r_knee.position = Vector3(0, -0.45, 0)
	r_hip.add_child(r_knee)
	parts["r_knee"] = r_knee

	var r_calf := _create_box(Vector3(0.16, 0.285, 0.16), limb_col)
	r_calf.position = Vector3(0, -0.225, 0)
	r_knee.add_child(r_calf)
	parts["r_calf"] = r_calf

	var r_ankle := Node3D.new()
	r_ankle.position = Vector3(0, -0.45, 0)
	r_knee.add_child(r_ankle)
	parts["r_ankle"] = r_ankle

	var r_foot := _create_box(Vector3(0.14, 0.06, 0.22), limb_col)
	r_foot.position = Vector3(0, -0.06, 0.05)
	r_ankle.add_child(r_foot)
	parts["r_foot"] = r_foot

	var r_toe := Node3D.new()
	r_toe.position = Vector3(0, -0.06, 0.22)
	r_ankle.add_child(r_toe)
	parts["r_toe"] = r_toe

	var r_toe_mesh := _create_box(Vector3(0.12, 0.04, 0.08), limb_col)
	r_toe_mesh.position = Vector3(0, -0.02, 0.04)
	r_toe.add_child(r_toe_mesh)
	parts["r_toe_mesh"] = r_toe_mesh

	return parts


static func apply_skeleton_pose(
	parts: Dictionary,
	skeleton: Skeleton3D,
	bone_indices: Dictionary,
	mirror_x: bool,
	motion_root: Node3D,
	rm: Dictionary,
	lane_base_x: float = 0.0,
) -> void:
	if not skeleton or bone_indices.is_empty():
		return

	var pelvis: Node3D = parts.get("pelvis")
	if not pelvis:
		return

	var mirror_matrix := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

	if bone_indices.has("hips"):
		var bone_xform := skeleton.get_bone_global_pose(bone_indices["hips"])
		if not rm.get("ready", false):
			rm["origin"] = bone_xform.origin
			rm["ready"] = true
		var root_motion: Vector3 = bone_xform.origin - rm["origin"]
		if mirror_x:
			root_motion.x = -root_motion.x
		if motion_root:
			motion_root.position = Vector3(lane_base_x + root_motion.x, 0.0, root_motion.z)
		pelvis.position = Vector3(
			0.0,
			BASE_Y + bone_xform.origin.y,
			0.0
		)
		var new_pelvis_basis := bone_xform.basis.orthonormalized()
		if mirror_x:
			new_pelvis_basis = mirror_matrix * new_pelvis_basis * mirror_matrix
		pelvis.quaternion = Quaternion(new_pelvis_basis)

	var apply_bone := func(part_name: String, bone_key: String, flip: bool = false):
		var node: Node3D = parts.get(part_name)
		if node and bone_indices.has(bone_key):
			var gl_pose := skeleton.get_bone_global_pose(bone_indices[bone_key])
			var new_basis := gl_pose.basis.orthonormalized()

			if mirror_x:
				new_basis = mirror_matrix * new_basis * mirror_matrix

			if flip:
				new_basis = new_basis * Basis(Vector3.RIGHT, PI)
			node.global_basis = new_basis

	apply_bone.call("spine", "spine", false)
	apply_bone.call("neck", "neck", false)
	apply_bone.call("head_pivot", "head", false)

	apply_bone.call("l_shoulder", "l_upper_arm", true)
	apply_bone.call("l_elbow", "l_lower_arm", true)
	apply_bone.call("l_wrist", "l_hand", true)

	apply_bone.call("r_shoulder", "r_upper_arm", true)
	apply_bone.call("r_elbow", "r_lower_arm", true)
	apply_bone.call("r_wrist", "r_hand", true)

	apply_bone.call("l_hip", "l_upper_leg", true)
	apply_bone.call("l_knee", "l_lower_leg", true)
	apply_bone.call("l_ankle", "l_foot", true)
	apply_bone.call("l_toe", "l_toe", true)

	apply_bone.call("r_hip", "r_upper_leg", true)
	apply_bone.call("r_knee", "r_lower_leg", true)
	apply_bone.call("r_ankle", "r_foot", true)
	apply_bone.call("r_toe", "r_toe", true)

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


static func setup_thriller_sequence_preview(
	entry: Dictionary,
	viewport: Node,
	lane_x: float,
	pick_best_anim: Callable,
) -> void:
	var parts_data: Array[Dictionary] = []
	for path in EmoteData.THRILLER_PART_PATHS:
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if not scene:
			continue
		var node := scene.instantiate() as Node3D
		node.position = Vector3(lane_x, 0.0, 0.0)
		node.visible = false
		viewport.add_child(node)
		for child in node.find_children("*", "MeshInstance3D", true, false):
			child.hide()
		var skel: Skeleton3D = null
		for child in node.find_children("*", "Skeleton3D", true, false):
			skel = child as Skeleton3D
			break
		var ap: AnimationPlayer = null
		for child in node.find_children("*", "AnimationPlayer", true, false):
			ap = child as AnimationPlayer
			break
		var anim_name := ""
		if ap:
			anim_name = str(pick_best_anim.call(ap))
		parts_data.append({"node": node, "skel": skel, "ap": ap, "anim": anim_name})

	if parts_data.is_empty():
		return

	entry["is_thriller_sequence"] = true
	entry["thriller_parts"] = parts_data
	entry["thriller_part_idx"] = 0
	entry["fbx"] = parts_data[0]["node"]
	play_thriller_part(entry, 0, false)


static func play_thriller_part(entry: Dictionary, part_idx: int, random_start: bool) -> void:
	var parts: Array = entry.get("thriller_parts", [])
	if parts.is_empty():
		return
	part_idx = clampi(part_idx, 0, parts.size() - 1)
	entry["thriller_part_idx"] = part_idx
	for i in range(parts.size()):
		var part: Dictionary = parts[i]
		var node: Node3D = part.get("node", null)
		if node and is_instance_valid(node):
			node.visible = i == part_idx

	var active: Dictionary = parts[part_idx]
	var skel: Skeleton3D = active.get("skel", null)
	var ap: AnimationPlayer = active.get("ap", null)
	var anim_name: String = active.get("anim", "")
	entry["skel"] = skel
	entry["bones"] = map_mixamo_bones(skel) if skel else {}
	entry["ap"] = ap
	var rm: Dictionary = entry.get("rm", {})
	rm["ready"] = false
	entry["rm"] = rm

	if not ap or anim_name == "":
		return
	if ap.animation_finished.is_connected(_on_thriller_animation_finished):
		ap.animation_finished.disconnect(_on_thriller_animation_finished)
	ap.animation_finished.connect(_on_thriller_animation_finished.bind(entry), CONNECT_ONE_SHOT)
	var anim: Animation = ap.get_animation(anim_name)
	if anim:
		anim.loop_mode = Animation.LOOP_NONE
	ap.play(anim_name)
	if random_start and anim and anim.length > 0.05:
		ap.advance(randf() * anim.length)


static func _on_thriller_animation_finished(_anim_name: StringName, entry: Dictionary) -> void:
	if not entry.get("is_thriller_sequence", false):
		return
	if not EmoteData.is_thriller_emote(int(entry.get("preview_emote_id", EmoteData.EMOTE_NONE))):
		return
	var parts: Array = entry.get("thriller_parts", [])
	if parts.is_empty():
		return
	var next_idx := int(entry.get("thriller_part_idx", 0)) + 1
	if next_idx >= parts.size():
		next_idx = 0
	play_thriller_part(entry, next_idx, false)


static func free_thriller_sequence(entry: Dictionary) -> void:
	if not entry.get("is_thriller_sequence", false):
		return
	for part in entry.get("thriller_parts", []):
		var node: Node3D = part.get("node", null)
		if node and is_instance_valid(node):
			var ap: AnimationPlayer = part.get("ap", null)
			if ap and ap.animation_finished.is_connected(_on_thriller_animation_finished):
				ap.animation_finished.disconnect(_on_thriller_animation_finished)
			node.queue_free()
	entry["is_thriller_sequence"] = false
	entry["thriller_parts"] = []
	entry["fbx"] = null
	entry["skel"] = null
	entry["ap"] = null
	entry["bones"] = {}


static func _create_box(half_extents: Vector3, color: Color) -> MeshInstance3D:
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


static func _create_detailed_hand(color: Color, is_left: bool, parts: Dictionary, prefix: String) -> Dictionary:
	var hand_root := Node3D.new()
	var meshes: Array = []

	var palm := _create_box(Vector3(0.09, 0.10, 0.05), color)
	palm.position = Vector3(0, -0.10, 0)
	hand_root.add_child(palm)
	meshes.append(palm)

	var thumb_root := Node3D.new()
	var thumb_x := 0.10 if is_left else -0.10
	thumb_root.position = Vector3(thumb_x, -0.05, 0.04)
	thumb_root.rotation = Vector3(deg_to_rad(-20), deg_to_rad(45 if is_left else -45), deg_to_rad(30 if is_left else -30))
	hand_root.add_child(thumb_root)
	parts[prefix + "thumb_prox"] = thumb_root

	var thumb_prox := _create_box(Vector3(0.025, 0.04, 0.03), color)
	thumb_prox.position = Vector3(0, -0.04, 0)
	thumb_root.add_child(thumb_prox)
	meshes.append(thumb_prox)

	var thumb_joint := Node3D.new()
	thumb_joint.position = Vector3(0, -0.08, 0)
	thumb_joint.rotation = Vector3(deg_to_rad(-15), 0, 0)
	thumb_root.add_child(thumb_joint)
	parts[prefix + "thumb_dist"] = thumb_joint

	var thumb_dist := _create_box(Vector3(0.025, 0.035, 0.03), color)
	thumb_dist.position = Vector3(0, -0.035, 0)
	thumb_joint.add_child(thumb_dist)
	meshes.append(thumb_dist)

	var finger_lengths := [0.08, 0.09, 0.085, 0.065]
	var finger_widths := 0.022
	var finger_depths := 0.025

	var finger_names := ["index", "middle", "ring", "pinky"]

	for i in range(4):
		var fname: String = finger_names[i]
		var base_length: float = finger_lengths[i]

		var finger_root := Node3D.new()
		var offset_x := (0.066 - (i * 0.044)) if is_left else (-0.066 + (i * 0.044))
		finger_root.position = Vector3(offset_x, -0.20, 0.0)

		var spread_angle := deg_to_rad((1.5 - i) * 5)
		if not is_left:
			spread_angle = -spread_angle
		finger_root.rotation = Vector3(deg_to_rad(-5), 0, spread_angle)
		hand_root.add_child(finger_root)
		parts[prefix + fname + "_prox"] = finger_root

		var prox_len := base_length * 0.4
		var prox := _create_box(Vector3(finger_widths, prox_len, finger_depths), color)
		prox.position = Vector3(0, -prox_len, 0)
		finger_root.add_child(prox)
		meshes.append(prox)

		var joint1 := Node3D.new()
		joint1.position = Vector3(0, -prox_len * 2, 0)
		joint1.rotation = Vector3(deg_to_rad(-10), 0, 0)
		finger_root.add_child(joint1)
		parts[prefix + fname + "_mid"] = joint1

		var mid_len := base_length * 0.35
		var mid := _create_box(Vector3(finger_widths, mid_len, finger_depths), color)
		mid.position = Vector3(0, -mid_len, 0)
		joint1.add_child(mid)
		meshes.append(mid)

		var joint2 := Node3D.new()
		joint2.position = Vector3(0, -mid_len * 2, 0)
		joint2.rotation = Vector3(deg_to_rad(-10), 0, 0)
		joint1.add_child(joint2)
		parts[prefix + fname + "_dist"] = joint2

		var dist_len := base_length * 0.25
		var dist := _create_box(Vector3(finger_widths, dist_len, finger_depths), color)
		dist.position = Vector3(0, -dist_len, 0)
		joint2.add_child(dist)
		meshes.append(dist)

	return {"root": hand_root, "meshes": meshes}

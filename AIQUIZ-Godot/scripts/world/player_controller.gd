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

# --- HFF風アクティブラグドール (Phase2) ---
# 四肢を物理ボディ化し、_animate_skeleton が動かす表示ピボットを目標として
# PDトルクで半追従させる。表示用の四肢メッシュは隠し、物理ボディが見える四肢
# として振る舞う(体幹はキネマのまま=Phase6で物理化予定)。
# NOTE: ラグドール仕様は一旦廃止(無効化)。false でラグドール生成/表示メッシュ非表示/
# 脱力崩壊をすべてスキップし、従来のブロック四肢アニメ+死亡時爆発に戻る。
# 関連コード(RagdollBuilder/ActiveRagdollDriver/_setup_ragdoll 等)は復活に備えて温存。
const USE_ACTIVE_RAGDOLL := false
const RagdollBuilderScript = preload("res://scripts/world/ragdoll_builder.gd")
const ActiveRagdollDriverScript = preload("res://scripts/world/active_ragdoll_driver.gd")
# 物理駆動に置き換えるため非表示にする表示メッシュのキー
const _RAGDOLL_HIDE_KEYS := [
	"head", "l_upp_arm", "l_low_arm", "r_upp_arm", "r_low_arm",
	"l_thigh", "l_calf", "l_foot", "r_thigh", "r_calf", "r_foot",
	"l_toe_mesh", "r_toe_mesh", "l_hand", "r_hand",
	"lower_torso", "upper_torso",  # Phase6: 体幹も物理体化したため表示メッシュを隠す
]
var _p1_ragdoll: Dictionary = {}
var _p2_ragdoll: Dictionary = {}
var _p1_driver: ActiveRagdollDriver = null
var _p2_driver: ActiveRagdollDriver = null

# Hat state
var _p1_hat_id: int = 0
var _p2_hat_id: int = 0
var _p1_hat_node: Node3D = null
var _p2_hat_node: Node3D = null

var _p1_exploding: bool = false
var _p2_exploding: bool = false
var _p1_explosion_bodies: Array[RigidBody3D] = []
var _p2_explosion_bodies: Array[RigidBody3D] = []

const EXPLOSION_DEBRIS_LIFETIME: float = 4.5
const EXPLOSION_SINK_SURFACE_Y: float = StageConstants.OCEAN_SURFACE_Y
const EXPLOSION_KILL_Y: float = -14.0
const EXPLOSION_MIN_COLLISION_SIZE: float = 0.10
const EXPLOSION_IMPULSE_X_MIN: float = 5.5
const EXPLOSION_IMPULSE_X_MAX: float = 15.0
const EXPLOSION_IMPULSE_Y_MIN: float = 9.0
const EXPLOSION_IMPULSE_Y_MAX: float = 20.0
const EXPLOSION_IMPULSE_Z_MIN: float = -9.0
const EXPLOSION_IMPULSE_Z_MAX: float = 9.0
const EXPLOSION_TORQUE_MIN: float = -22.0
const EXPLOSION_TORQUE_MAX: float = 22.0
const EXPLOSION_PHYSICS_FRICTION: float = 0.62
const EXPLOSION_PHYSICS_BOUNCE: float = 0.32

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
	# ラグドール生成は _process で self.position が実プレイヤー位置へ設定された後に
	# 遅延実行する(_ready 時点では原点のため、初フレームのアンカー瞬間移動を回避)。
	var gs = QuizManager.game_state
	_load_mixamo_rig(gs)


## 四肢物理ツリー+駆動器を生成する。
## 物理ボディは「移動するプレイヤーノード」の子にできない(物理が親変換と競合)。
## 静止した親(このコントローラの親)の下に別ツリーで生成し、キネマアンカーを
## pelvis のワールド変換へ毎物理フレーム同期して四肢を追従させる。
func _setup_ragdoll(parts: Dictionary, is_p1: bool) -> Dictionary:
	var host: Node = get_parent()
	if host == null:
		host = self
	var container := Node3D.new()
	container.name = "RagdollLimbsP1" if is_p1 else "RagdollLimbsP2"
	host.add_child(container)

	var limb_col: Color = P1_LIMB if is_p1 else P2_LIMB
	var head_col: Color = P1_HEAD if is_p1 else P2_HEAD
	var body_col: Color = P1_BODY if is_p1 else P2_BODY
	var rag: Dictionary = RagdollBuilderScript.build(container, parts["pelvis"], parts, {
		"debug": false, "limb_color": limb_col, "head_color": head_col, "torso_color": body_col,
	})

	# 物理駆動に置き換える表示メッシュを非表示にする(体幹は表示のまま)
	for key in _RAGDOLL_HIDE_KEYS:
		var n = parts.get(key)
		if n and is_instance_valid(n):
			n.visible = false

	var driver: ActiveRagdollDriver = ActiveRagdollDriverScript.new()
	driver.name = "ActiveRagdollDriverP1" if is_p1 else "ActiveRagdollDriverP2"
	driver.process_physics_priority = 10   # 目標アニメ(_process)の後に駆動
	container.add_child(driver)
	driver.setup(rag, parts, parts["pelvis"])

	return {"rag": rag, "driver": driver, "container": container}


## HFF: 死亡時の脱力。駆動を止め、全身(通常 gravity_scale=0 の体幹を含む)を
## 自重で崩れ落とす。爆発デブリではなくグニャっと崩れる HFF らしい死に方。
func _go_limp(ragdoll: Dictionary) -> void:
	var driver = ragdoll.get("driver")
	if driver and is_instance_valid(driver):
		driver.enabled = false
	var rag: Dictionary = ragdoll.get("rag", {})
	var rag_bodies: Dictionary = rag.get("bodies", {})
	for key in rag_bodies:
		var b = rag_bodies[key]
		if key != "anchor" and b is RigidBody3D and is_instance_valid(b):
			b.gravity_scale = 1.0   # 体幹(0だった)も含め全身を自重落下させる
			b.can_sleep = true       # 崩れて静止したらスリープ(負荷低減)


## ラグドールツリーを破棄する(別親に置いているため明示的に解放)。
func _teardown_ragdoll(ragdoll: Dictionary) -> void:
	if ragdoll.has("container"):
		var c = ragdoll["container"]
		if is_instance_valid(c):
			c.queue_free()


func _exit_tree() -> void:
	# 爆発デブリは get_parent() 配下(別ツリー)に生成されるため、明示解放しないと
	# このノード破棄時に孤児として残存リークする。
	_clear_explosion_bodies(true)
	_clear_explosion_bodies(false)
	_teardown_ragdoll(_p1_ragdoll)
	_teardown_ragdoll(_p2_ragdoll)


func _load_mixamo_rig(gs: QuizGameState) -> void:
	var loader := Callable(self, "_load_fbx_scene")
	var p1_slots: Array[int] = [1, 2, 3]
	var p2_slots: Array[int] = [1, 2, 3]
	if gs:
		p1_slots = gs.p1_emote_slots
		p2_slots = gs.p2_emote_slots
	if NetworkManager and NetworkManager.state == NetworkManager.State.IN_GAME:
		p2_slots = NetworkManager.opponent_emote_slots
	_apply_emote_rig_slots(p1_slots, p2_slots, loader)


func reload_emote_rigs(p1_slots: Array[int], p2_slots: Array[int]) -> void:
	_clear_rig_scene_nodes()
	_p1_rig = AnimationRig.new("P1")
	_p2_rig = AnimationRig.new("P2")
	_apply_emote_rig_slots(p1_slots, p2_slots, Callable(self, "_load_fbx_scene"))


func _is_emote_locked(gs: QuizGameState, is_p2: bool) -> bool:
	return gs.p2_emote_lock_timer > 0.0 if is_p2 else gs.p1_emote_lock_timer > 0.0


func start_thriller_sequence(is_p2: bool) -> void:
	var rig := _p2_rig if is_p2 else _p1_rig
	rig.start_thriller_sequence()


func reset_thriller_sequence(is_p2: bool) -> void:
	var rig := _p2_rig if is_p2 else _p1_rig
	rig.reset_thriller_sequence()


func get_loaded_emote_ids(is_p2: bool) -> Array[int]:
	var rig := _p2_rig if is_p2 else _p1_rig
	return rig.loaded_emotes.duplicate()


func ensure_emote_playback(is_p2: bool, emote_id: int) -> void:
	var rig := _p2_rig if is_p2 else _p1_rig
	if not rig.is_rigged:
		return
	var norm := EmoteData.normalize_emote_id(emote_id)
	if EmoteData.is_thriller_emote(norm):
		if not rig.is_thriller_locked():
			rig.start_thriller_sequence()
		return
	var idx := rig.loaded_emotes.find(norm)
	if idx < 0 or idx >= AnimationRig.EMOTE_RIG_SLOTS.size():
		return
	rig.play_slot(AnimationRig.EMOTE_RIG_SLOTS[idx], true)


func _clear_rig_scene_nodes() -> void:
	for child in get_children():
		var n := str(child.name)
		if n.begins_with("P1") or n.begins_with("P2"):
			child.queue_free()


func _apply_p1_rig_animation_fallback(gs: QuizGameState, is_active: bool, walk_phase: float, speed_ratio: float) -> void:
	var emote_lock := _is_emote_locked(gs, false)
	if emote_lock and gs.p1_emote > 0:
		if _p1_rig.select_animation(
			gs.player_y, false, gs.p1_emote, false, is_active, false, true
		):
			_apply_skeleton_pose(p1_parts, _p1_rig.active_skeleton, _p1_rig.active_bone_indices, _p1_rig.mirror_x)
		else:
			_animate_emote(p1_parts, gs.p1_emote, false)
		return
	if (gs.player_y > 0.01 or gs.p1_jump_trigger) and not (emote_lock and gs.p1_emote > 0):
		_animate_skeleton(p1_parts, gs.player_y, gs.player_vel_y, is_active, walk_phase, false, 0)
		return
	if _p1_rig.select_animation(
		gs.player_y, gs.p1_jump_trigger, gs.p1_emote if emote_lock else 0,
		gs.p1_moving_back, is_active, _p1_rig.is_jump_playing(), emote_lock
	):
		_apply_skeleton_pose(p1_parts, _p1_rig.active_skeleton, _p1_rig.active_bone_indices, _p1_rig.mirror_x)
		var run_ap := _p1_rig.aps[AnimationRig.SLOT_RUN] as AnimationPlayer
		if run_ap and run_ap.is_playing():
			run_ap.speed_scale = clampf(speed_ratio * gs.p1_run_anim_speed_mult, 0.3, 6.0)
	else:
		_animate_skeleton(p1_parts, gs.player_y, gs.player_vel_y, is_active, walk_phase, false, 0)


func _apply_p2_rig_animation_fallback(gs: QuizGameState, is_active: bool, walk_phase: float, speed_ratio: float) -> void:
	var emote_lock := _is_emote_locked(gs, true)
	if emote_lock and gs.p2_emote > 0:
		if _p2_rig.select_animation(
			gs.player2_y, false, gs.p2_emote, false, is_active, false, true
		):
			_apply_skeleton_pose(p2_parts, _p2_rig.active_skeleton, _p2_rig.active_bone_indices, _p2_rig.mirror_x)
		else:
			_animate_emote(p2_parts, gs.p2_emote, true)
		return
	if (gs.player2_y > 0.01 or gs.p2_jump_trigger) and not (emote_lock and gs.p2_emote > 0):
		_animate_skeleton(p2_parts, gs.player2_y, gs.player2_vel_y, is_active, walk_phase * 1.1, true, 0)
		return
	if _p2_rig.select_animation(
		gs.player2_y, gs.p2_jump_trigger, gs.p2_emote if emote_lock else 0,
		gs.p2_moving_back, is_active, _p2_rig.is_jump_playing(), emote_lock
	):
		_apply_skeleton_pose(p2_parts, _p2_rig.active_skeleton, _p2_rig.active_bone_indices, _p2_rig.mirror_x)
		var run_ap := _p2_rig.aps[AnimationRig.SLOT_RUN] as AnimationPlayer
		if run_ap and run_ap.is_playing():
			run_ap.speed_scale = clampf(speed_ratio * gs.p2_run_anim_speed_mult, 0.3, 6.0)
	else:
		_animate_skeleton(p2_parts, gs.player2_y, gs.player2_vel_y, is_active, walk_phase * 1.1, true, 0)


func _apply_emote_rig_slots(p1_slots: Array[int], p2_slots: Array[int], loader: Callable) -> void:
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
		# P2ラグドールは p2_container.position 確定後に遅延生成する
	if gs.num_players < 2 and p2_container != null:
		# 爆発デブリは別親(get_parent())に在り container 解放では消えないので明示解放。
		# _p2_exploding を残すと再エントリ時に二度目の爆発が初期化されない不具合になる。
		_p2_exploding = false
		_clear_explosion_bodies(false)
		if USE_ACTIVE_RAGDOLL:
			_teardown_ragdoll(_p2_ragdoll)
			_p2_ragdoll = {}
			_p2_driver = null
		p2_container.queue_free()
		p2_container = null
		p2_parts.clear()

	# --- Player 1 ---
	position = Vector3(gs.player_x, gs.player_y, gs.player_local_z)
	var p1_visual_hidden: bool = (
		gs.num_players == 1
		and not _is_preview_subviewport()
		and gs.game_state not in [Constants.STATE_GAME_OVER, Constants.STATE_FLYOVER]
	)

	# P1ラグドールは位置確定後の初回に生成(アンカー瞬間移動を回避)。
	# メニュープレビュー(SubViewport)では不要な物理負荷になるので生成しない
	# (表示メッシュも隠さないため、プレビューはブロック四肢のまま正しく描画される)。
	if USE_ACTIVE_RAGDOLL and not p1_visual_hidden and not _is_preview_subviewport() and _p1_ragdoll.is_empty() and not p1_parts.is_empty():
		_p1_ragdoll = _setup_ragdoll(p1_parts, true)
		_p1_driver = _p1_ragdoll.get("driver")

	if gs.p1_alive:
		if _p1_exploding or not _p1_explosion_bodies.is_empty():
			_p1_exploding = false
			_clear_explosion_bodies(true)
			_set_rig_scenes_visible(true, true)
			# 脱力崩壊したラグドールを破棄→次フレームで直立状態に再生成(復活)
			if USE_ACTIVE_RAGDOLL and not _p1_ragdoll.is_empty():
				_teardown_ragdoll(_p1_ragdoll)
				_p1_ragdoll = {}
				_p1_driver = null
		_set_parts_visible(p1_parts, not p1_visual_hidden)
		if p1_visual_hidden:
			pass
		elif not _p1_rig.is_rigged:
			var p1_is_playing := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
			_animate_skeleton(p1_parts, gs.player_y, gs.player_vel_y, p1_is_playing, walk_phase, false, 0)
		else:
			var is_active := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
			var p1_emote_lock := _is_emote_locked(gs, false)
			var apply_rig := _p1_rig.select_animation(
				gs.player_y, gs.p1_jump_trigger, gs.p1_emote,
				gs.p1_moving_back, is_active, _p1_rig.is_jump_playing(), p1_emote_lock)
			
			if apply_rig:
				_apply_skeleton_pose(p1_parts, _p1_rig.active_skeleton, _p1_rig.active_bone_indices, _p1_rig.mirror_x)
				var run_ap := _p1_rig.aps[AnimationRig.SLOT_RUN] as AnimationPlayer
				if run_ap and run_ap.is_playing():
					run_ap.speed_scale = clampf(
						speed_ratio * gs.p1_run_anim_speed_mult,
						0.3,
						6.0
					)
			elif p1_emote_lock and gs.p1_emote > 0:
				if _p1_rig.select_animation(
					gs.player_y, false, gs.p1_emote, false, is_active, false, true
				):
					_apply_skeleton_pose(p1_parts, _p1_rig.active_skeleton, _p1_rig.active_bone_indices, _p1_rig.mirror_x)
				elif not _p1_rig.is_rigged:
					_animate_emote(p1_parts, gs.p1_emote, false)
			else:
				_apply_p1_rig_animation_fallback(gs, is_active, walk_phase, speed_ratio)
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
			if not _p1_exploding and gs.player_y > StageConstants.OCEAN_ENTRY_Y:
				_p1_exploding = true
				# HFF: 死亡時は脱力崩壊。駆動を止め全身を重力で崩す。ラグドール非生成時
				# (プレビュー等)のみ従来の爆発にフォールバック。復活時にラグドールを
				# 破棄し再生成して直立復帰する(下の alive 分岐)。
				if USE_ACTIVE_RAGDOLL and not _p1_ragdoll.is_empty():
					_go_limp(_p1_ragdoll)
				else:
					_init_explosion(p1_parts, true)
			_set_parts_visible(p1_parts, false)
			if not _p1_explosion_bodies.is_empty():
				var sink_debris: bool = gs.player_y <= StageConstants.OCEAN_ENTRY_Y
				_update_explosion(true, gs.game_over_timer - 2.0, sink_debris, gs.is_coop_mode(), -global_position.x)
	else:
		_set_parts_visible(p1_parts, false)

	# --- Player 2 ---
	if gs.num_players >= 2 and p2_container:
		p2_container.position = Vector3(gs.player2_x - gs.player_x, gs.player2_y - gs.player_y, gs.player2_local_z - gs.player_local_z)

		# P2ラグドールは位置確定後の初回に生成(アンカー瞬間移動を回避)。
		# プレビュー(SubViewport)では生成しない(P1と同様)。
		if USE_ACTIVE_RAGDOLL and not _is_preview_subviewport() and _p2_ragdoll.is_empty() and not p2_parts.is_empty():
			_p2_ragdoll = _setup_ragdoll(p2_parts, false)
			_p2_driver = _p2_ragdoll.get("driver")

		if gs.p2_alive:
			if _p2_exploding or not _p2_explosion_bodies.is_empty():
				_p2_exploding = false
				_clear_explosion_bodies(false)
				_set_rig_scenes_visible(false, true)
				# 脱力崩壊したラグドールを破棄→次フレームで直立状態に再生成(復活)
				if USE_ACTIVE_RAGDOLL and not _p2_ragdoll.is_empty():
					_teardown_ragdoll(_p2_ragdoll)
					_p2_ragdoll = {}
					_p2_driver = null
			_set_parts_visible(p2_parts, true)
			if not _p2_rig.is_rigged:
				var p2_is_playing := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
				_animate_skeleton(p2_parts, gs.player2_y, gs.player2_vel_y, p2_is_playing, walk_phase * 1.1, true, 0)
			else:
				var is_active := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
				var p2_emote_lock := _is_emote_locked(gs, true)
				var apply_rig := _p2_rig.select_animation(
					gs.player2_y, gs.p2_jump_trigger, gs.p2_emote,
					gs.p2_moving_back, is_active, _p2_rig.is_jump_playing(), p2_emote_lock)
				
				if apply_rig:
					_apply_skeleton_pose(p2_parts, _p2_rig.active_skeleton, _p2_rig.active_bone_indices, _p2_rig.mirror_x)
					var run_ap := _p2_rig.aps[AnimationRig.SLOT_RUN] as AnimationPlayer
					if run_ap and run_ap.is_playing():
						run_ap.speed_scale = clampf(
							speed_ratio * gs.p2_run_anim_speed_mult,
							0.3,
							6.0
						)
				elif p2_emote_lock and gs.p2_emote > 0:
					if _p2_rig.select_animation(
						gs.player2_y, false, gs.p2_emote, false, is_active, false, true
					):
						_apply_skeleton_pose(p2_parts, _p2_rig.active_skeleton, _p2_rig.active_bone_indices, _p2_rig.mirror_x)
					elif not _p2_rig.is_rigged:
						_animate_emote(p2_parts, gs.p2_emote, true)
				else:
					_apply_p2_rig_animation_fallback(gs, is_active, walk_phase, speed_ratio)
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
				if not _p2_exploding and gs.player2_y > StageConstants.OCEAN_ENTRY_Y:
					_p2_exploding = true
					# HFF: 死亡時は脱力崩壊(P1と同様)。復活時に破棄→再生成で直立復帰。
					if USE_ACTIVE_RAGDOLL and not _p2_ragdoll.is_empty():
						_go_limp(_p2_ragdoll)
					else:
						_init_explosion(p2_parts, false)
				_set_parts_visible(p2_parts, false)
				if not _p2_explosion_bodies.is_empty():
					var sink_debris: bool = gs.player2_y <= StageConstants.OCEAN_ENTRY_Y
					_update_explosion(false, gs.player2_game_over_timer - 2.0, sink_debris, gs.is_coop_mode(), -global_position.x)
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
	# ラグドール有効時は、物理体に置換した表示メッシュ(_RAGDOLL_HIDE_KEYS)を
	# 表示要求時も隠したままにする。これをしないと毎フレームの再表示で表示メッシュ
	# (=目標ゴースト)が物理体と二重に描画され、揺れた瞬間に分離して見える。
	var hidden := {}
	if vis and USE_ACTIVE_RAGDOLL:
		var rag_active: bool = (not _p1_ragdoll.is_empty()) if parts == p1_parts else (not _p2_ragdoll.is_empty())
		if rag_active:
			for k in _RAGDOLL_HIDE_KEYS:
				var n = parts.get(k)
				if n: hidden[n] = true
	for mesh: MeshInstance3D in parts["meshes"]:
		if mesh: mesh.visible = vis and not hidden.has(mesh)



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
		# Flail 窶・falling into the ocean
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

func _get_explosion_spawn_root() -> Node:
	var parent := get_parent()
	return parent if parent else self


func _is_preview_subviewport() -> bool:
	return get_viewport() is SubViewport


func _set_rig_scenes_visible(is_p1: bool, vis: bool) -> void:
	var prefix := "P1" if is_p1 else "P2"
	for child in get_children():
		if str(child.name).begins_with(prefix):
			child.visible = vis


func _clear_explosion_bodies(is_p1: bool) -> void:
	var bodies := _p1_explosion_bodies if is_p1 else _p2_explosion_bodies
	for body in bodies:
		if is_instance_valid(body):
			body.queue_free()
	bodies.clear()


func _mesh_box_size(mesh_inst: MeshInstance3D) -> Vector3:
	var box := mesh_inst.mesh as BoxMesh
	var size := box.size if box else Vector3(0.18, 0.18, 0.18)
	return size.max(Vector3.ONE * EXPLOSION_MIN_COLLISION_SIZE)


func _init_explosion(parts: Dictionary, is_p1: bool) -> void:
	if not parts or not parts.has("meshes"):
		return
	_hide_rig_scenes(is_p1)
	_clear_explosion_bodies(is_p1)

	var all_meshes: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in parts["meshes"]:
		all_meshes.append(mesh)
	if parts.has("hat_meshes"):
		for hat_mesh: MeshInstance3D in parts["hat_meshes"]:
			all_meshes.append(hat_mesh)

	var spawn_root := _get_explosion_spawn_root()
	var is_preview := _is_preview_subviewport()
	var bodies: Array[RigidBody3D] = []

	for mesh: MeshInstance3D in all_meshes:
		if not is_instance_valid(mesh):
			continue
		mesh.visible = false

		var gt := mesh.global_transform
		var gx := gt.origin.x - global_position.x
		var sx := 1.0 if gx >= 0.0 else -1.0

		var piece := RigidBody3D.new()
		piece.mass = randf_range(0.22, 0.45)
		piece.gravity_scale = 2.0
		piece.linear_damp = 0.05
		piece.angular_damp = 0.06
		piece.continuous_cd = true
		piece.collision_layer = 0
		piece.collision_mask = 1
		var phys_mat := PhysicsMaterial.new()
		phys_mat.friction = EXPLOSION_PHYSICS_FRICTION
		phys_mat.bounce = EXPLOSION_PHYSICS_BOUNCE
		piece.physics_material_override = phys_mat
		piece.set_meta("player_death_shard", true)
		piece.set_meta("preview_death_shard_p1", is_p1)
		piece.set_meta("base_scale", mesh.scale)
		piece.set_meta("groove_offset", randf_range(-0.42, 0.42))

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = _mesh_box_size(mesh)
		col.shape = shape
		piece.add_child(col)

		var visual := MeshInstance3D.new()
		if mesh.mesh:
			visual.mesh = mesh.mesh
		if mesh.material_override:
			visual.material_override = mesh.material_override
		visual.scale = mesh.scale
		piece.add_child(visual)

		spawn_root.add_child(piece)
		piece.global_transform = gt

		var impulse := Vector3(
			sx * randf_range(EXPLOSION_IMPULSE_X_MIN, EXPLOSION_IMPULSE_X_MAX),
			randf_range(EXPLOSION_IMPULSE_Y_MIN, EXPLOSION_IMPULSE_Y_MAX),
			randf_range(EXPLOSION_IMPULSE_Z_MIN, EXPLOSION_IMPULSE_Z_MAX)
		)
		# X/Z 回転を強めにして着地後も転がりやすくする
		var torque := Vector3(
			randf_range(EXPLOSION_TORQUE_MIN, EXPLOSION_TORQUE_MAX),
			randf_range(EXPLOSION_TORQUE_MIN * 0.35, EXPLOSION_TORQUE_MAX * 0.35),
			randf_range(EXPLOSION_TORQUE_MIN, EXPLOSION_TORQUE_MAX)
		)
		if is_preview:
			piece.mass = randf_range(0.35, 0.65)
			piece.gravity_scale = 2.3
			piece.linear_damp = 0.06
			piece.angular_damp = 0.05
			impulse *= 1.45
			torque *= 1.35

		piece.apply_central_impulse(impulse)
		piece.apply_torque_impulse(torque)
		# 初速の回転を与えて床での転がりを強調
		piece.angular_velocity = Vector3(
			randf_range(-14.0, 14.0),
			randf_range(-4.0, 4.0),
			randf_range(-14.0, 14.0)
		)
		bodies.append(piece)

	if is_p1:
		_p1_explosion_bodies = bodies
	else:
		_p2_explosion_bodies = bodies


func _hide_rig_scenes(is_p1: bool) -> void:
	_set_rig_scenes_visible(is_p1, false)


func _update_explosion(
		is_p1: bool,
		timer: float,
		sink_debris: bool = false,
		fall_to_groove: bool = false,
		groove_local_x: float = 0.0) -> void:
	var bodies := _p1_explosion_bodies if is_p1 else _p2_explosion_bodies
	var should_sink := sink_debris or fall_to_groove
	var i := bodies.size() - 1
	while i >= 0:
		var body := bodies[i]
		if not is_instance_valid(body):
			bodies.remove_at(i)
			i -= 1
			continue

		if timer >= EXPLOSION_DEBRIS_LIFETIME or body.global_position.y <= EXPLOSION_KILL_Y:
			body.queue_free()
			bodies.remove_at(i)
			i -= 1
			continue

		if fall_to_groove and timer < 1.8:
			var target_x := groove_local_x + float(body.get_meta("groove_offset", 0.0))
			var dx := target_x - body.global_position.x
			body.apply_central_force(Vector3(dx * 12.0, 0.0, 0.0))

		if should_sink and body.global_position.y < EXPLOSION_SINK_SURFACE_Y:
			var depth := EXPLOSION_SINK_SURFACE_Y - body.global_position.y
			var bscale: Vector3 = body.get_meta("base_scale", Vector3.ONE)
			var shrink := maxf(0.0, 1.0 - depth * 0.1)
			for child in body.get_children():
				if child is MeshInstance3D:
					(child as MeshInstance3D).scale = bscale * shrink

		i -= 1


# ============================================================
# High-Quality Procedural Emotes
# ============================================================
# Each emote uses layered oscillations, secondary motion
# (follow-through on elbows/knees), weight-shifting, and
# distinct personality to feel alive and expressive.
# ============================================================

func _animate_emote(parts: Dictionary, emote: int, is_p2: bool = false) -> void:
	var norm := EmoteData.normalize_emote_id(emote)
	if norm == EmoteData.EMOTE_NONE:
		return
	var t := _time
	match norm:
		EmoteData.EMOTE_GANGNAM:
			_emote_floss(t * 0.82, parts)
		EmoteData.EMOTE_SLIDE_HIP_HOP:
			_emote_floss(t * 1.18, parts)
		EmoteData.EMOTE_MOONWALK:
			_emote_side_groove(t * 0.9, parts, -1.0)
		EmoteData.EMOTE_FLAIR:
			_emote_arm_wave(t * 1.25, parts, 1.15)
		EmoteData.EMOTE_HIP_HOP, EmoteData.EMOTE_HIP_HOP_1:
			_emote_side_groove(t * 1.05, parts, 1.0)
		EmoteData.EMOTE_SILLY:
			_emote_arm_wave(t * 1.35, parts, 0.75)
		EmoteData.EMOTE_SWING:
			_emote_side_groove(t * 0.75, parts, -0.85)
		EmoteData.EMOTE_THRILLER:
			_emote_arm_wave(t * 0.95, parts, 1.35)
		EmoteData.EMOTE_YMCA:
			_emote_arm_wave(t * 1.1, parts, 1.0)
		EmoteData.EMOTE_HOUSE:
			_emote_floss(t * 1.4, parts)
		EmoteData.EMOTE_HEAD_SPINNING:
			_emote_side_groove(t * 1.55, parts, 1.25)
		EmoteData.EMOTE_RUNNING_MAN:
			_emote_floss(t * 1.25, parts)
		_:
			_emote_floss(t, parts)


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


func _emote_side_groove(t: float, parts: Dictionary, sway_sign: float) -> void:
	var pelvis: Node3D = parts["pelvis"]
	var spine_node: Node3D = parts["spine"]
	var head: Node3D = parts["head_pivot"]
	var l_shoulder: Node3D = parts["l_shoulder"]
	var r_shoulder: Node3D = parts["r_shoulder"]
	var l_hip: Node3D = parts["l_hip"]
	var r_hip: Node3D = parts["r_hip"]
	var phase := t * 7.5
	var sway := sin(phase) * 0.55 * sway_sign
	pelvis.position.y = BASE_Y + 0.9 + abs(sin(phase * 2.0)) * 0.1
	pelvis.rotation.y = sway
	spine_node.rotation.y = -sway * 0.35
	head.rotation.y = sway * 0.2
	l_shoulder.rotation.z = sway * 0.55
	r_shoulder.rotation.z = -sway * 0.55
	l_hip.rotation.x = sin(phase + 0.4) * 0.22
	r_hip.rotation.x = -sin(phase + 0.4) * 0.22


func _emote_arm_wave(t: float, parts: Dictionary, amp: float) -> void:
	var pelvis: Node3D = parts["pelvis"]
	var spine_node: Node3D = parts["spine"]
	var head: Node3D = parts["head_pivot"]
	var l_shoulder: Node3D = parts["l_shoulder"]
	var r_shoulder: Node3D = parts["r_shoulder"]
	var l_elbow: Node3D = parts["l_elbow"]
	var r_elbow: Node3D = parts["r_elbow"]
	var phase := t * 6.0
	var wave := sin(phase) * amp
	pelvis.position.y = BASE_Y + 0.9 + abs(cos(phase)) * 0.07
	pelvis.rotation.y = sin(phase * 0.5) * 0.25
	spine_node.rotation.x = -0.06
	head.rotation.x = sin(phase * 2.0) * 0.08
	l_shoulder.rotation.x = -0.4 + wave * 0.35
	r_shoulder.rotation.x = -0.4 - wave * 0.35
	l_elbow.rotation.x = -0.55 + abs(wave) * 0.25
	r_elbow.rotation.x = -0.55 + abs(wave) * 0.25


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

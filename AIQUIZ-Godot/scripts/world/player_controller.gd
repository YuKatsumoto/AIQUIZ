extends Node3D
class_name PlayerController

const ToonPresets = preload("res://scripts/cosmetics/character_toon_presets.gd")

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
# 通常走行中のアクティブラグドールは無効。壁衝突死では同じ物理骨格をその瞬間だけ生成し、
# 受動ラグドールとして吹き飛ばす。
const USE_ACTIVE_RAGDOLL := false
const WALL_RAGDOLL_GAME_VELOCITY := Vector3(0.0, 7.0, -11.0)
const WALL_RAGDOLL_PREVIEW_VELOCITY := Vector3(0.0, 6.0, 8.0)
const WALL_RAGDOLL_SIDE_VELOCITY := 2.2
const WALL_RAGDOLL_SPIN := Vector3(5.5, 1.5, 3.3)
const INTRO_LANDED_TORSO_HEIGHT := 1.20
const INTRO_DROP_LINEAR_DAMP := 0.08
const INTRO_DROP_ANGULAR_DAMP := 0.05
const INTRO_DROP_FRICTION := 0.55
const INTRO_DROP_RESTITUTION := 0.08
const INTRO_SETTLE_SPEED := 0.45
const INTRO_SETTLE_HOLD := 0.25
const INTRO_GET_UP_DELAY := 2.00
const INTRO_GET_UP_DURATION := 2.20
const RagdollBuilderScript = preload("res://scripts/world/ragdoll_builder.gd")
const ActiveRagdollDriverScript = preload("res://scripts/world/active_ragdoll_driver.gd")
const GHOST_MOUNT_ANIMATION_PATH := "res://assets/animations/Ghost Shark Mount.fbx"
const GHOST_RIDER_MOUNT_SCALE: float = 0.62
const GHOST_RIDER_BIND_TRANSFORMS_META := &"ghost_mount_bind_transforms"
const GHOST_RIDER_MOUNT_SCALE_META := &"ghost_mount_scale"
const GHOST_RIDER_MOUNT_TRANSFORM_META := &"ghost_mount_target_transform"
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

# Arrival ragdolls are deliberately separate from the one-hit death presentation.
# They are short-lived and never participate in alive/dead state restoration.
var _intro_ragdolls: Dictionary = {}
var _intro_hat_restore: Dictionary = {}
var _intro_pending_players: Dictionary = {}

# Hat state
var _p1_hat_id: int = 0
var _p2_hat_id: int = 0
var _p1_hat_node: Node3D = null
var _p2_hat_node: Node3D = null
var _p1_toon_preset_id: int = -1
var _p2_toon_preset_id: int = -1

var _p1_exploding: bool = false
var _p2_exploding: bool = false
var _p1_result_exploded: bool = false
var _p2_result_exploded: bool = false
var _p1_result_explosion_elapsed: float = 0.0
var _p2_result_explosion_elapsed: float = 0.0
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
const WALL_EXPLOSION_BACKWARD_Z_MIN: float = 2.4
const WALL_EXPLOSION_BACKWARD_Z_MAX: float = 5.8
const WALL_EXPLOSION_SIDE_SPEED_MIN: float = 2.4
const WALL_EXPLOSION_SIDE_SPEED_MAX: float = 5.2
const WALL_EXPLOSION_UP_SPEED_MIN: float = 4.0
const WALL_EXPLOSION_UP_SPEED_MAX: float = 7.0
const WALL_EXPLOSION_SPIN_MAX: float = 5.5
const EXPLOSION_TORQUE_MIN: float = -22.0
const EXPLOSION_TORQUE_MAX: float = 22.0
const EXPLOSION_PHYSICS_FRICTION: float = 0.62
const EXPLOSION_PHYSICS_BOUNCE: float = 0.32

# Animation Rig (P1/P2蜈ｱ騾壹け繝ｩ繧ｹ縺ｧ邂｡逅・
var _p1_rig: AnimationRig = AnimationRig.new("P1")
var _p2_rig: AnimationRig = AnimationRig.new("P2")
var _ghost_mount_rig_data: Dictionary = {}

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
	_load_ghost_mount_rig()


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
		"toon_preset": _p1_toon_preset_id if is_p1 else _p2_toon_preset_id,
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


## 壁へ走り込んだ勢いを保ったまま、全身を後方・上方へ吹き飛ばす。
## 全ボディを同じ初速にそろえ、ジョイント経由でインパルスが重複増幅しないようにする。
func _launch_wall_ragdoll(ragdoll: Dictionary, is_p1: bool) -> void:
	_go_limp(ragdoll)
	var rag: Dictionary = ragdoll.get("rag", {})
	var rag_bodies: Dictionary = rag.get("bodies", {})
	var torso: RigidBody3D = rag_bodies.get("torso") as RigidBody3D
	var side_sign := 1.0 if (torso != null and torso.global_position.x >= 0.0) else -1.0
	if torso == null or absf(torso.global_position.x) < 0.05:
		side_sign = -1.0 if is_p1 else 1.0
	# メニューは壁が -Z 側から流れてくるため、コース前方が本編と逆向きになる。
	var launch_velocity := (
		WALL_RAGDOLL_PREVIEW_VELOCITY
		if _is_preview_subviewport()
		else WALL_RAGDOLL_GAME_VELOCITY
	)
	launch_velocity.x = WALL_RAGDOLL_SIDE_VELOCITY * side_sign
	for key: Variant in rag_bodies:
		if str(key) == "anchor":
			continue
		var body: RigidBody3D = rag_bodies[key] as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue
		body.sleeping = false
		body.linear_velocity = launch_velocity
		var spin_sign := -1.0 if (str(key).hash() & 1) == 0 else 1.0
		body.angular_velocity = Vector3(
			WALL_RAGDOLL_SPIN.x * spin_sign,
			WALL_RAGDOLL_SPIN.y * side_sign,
			WALL_RAGDOLL_SPIN.z * side_sign * spin_sign
		)


## ラグドールツリーを破棄する(別親に置いているため明示的に解放)。
func _teardown_ragdoll(ragdoll: Dictionary) -> void:
	if ragdoll.has("container"):
		var c = ragdoll["container"]
		if is_instance_valid(c):
			c.queue_free()


## Creates the short-lived arrival ragdoll at the helicopter release transform.
## The real player stays at its authoritative gameplay transform, but is hidden
## until complete_intro_drops() restores it.
func prepare_intro_arrival(player_count: int) -> void:
	_intro_pending_players.clear()
	var count := clampi(player_count, 1, 2)
	for player_index: int in range(1, count + 1):
		_intro_pending_players[player_index] = true
		var is_p1 := player_index == 1
		var parts: Dictionary = p1_parts if is_p1 else p2_parts
		_set_parts_visible(parts, false)
		_set_hat_visible(is_p1, false)
		_set_rig_scenes_visible(is_p1, false)


func begin_intro_drop(
	player_index: int,
	release_transform: Transform3D,
	inherited_velocity: Vector3 = Vector3.ZERO
) -> bool:
	if player_index not in [1, 2] or _intro_ragdolls.has(player_index):
		return false
	var is_p1 := player_index == 1
	var parts: Dictionary = p1_parts if is_p1 else p2_parts
	var root: Node3D = self if is_p1 else p2_container
	var pelvis := parts.get("pelvis") as Node3D
	if root == null or pelvis == null or not is_instance_valid(root) or not is_instance_valid(pelvis):
		return false

	# Build at the release point without changing the authoritative runner transform.
	var original_root_transform := root.global_transform
	var pelvis_from_root := root.global_transform.affine_inverse() * pelvis.global_transform
	root.global_transform = release_transform * pelvis_from_root.affine_inverse()
	var ragdoll := _setup_ragdoll(parts, is_p1)
	root.global_transform = original_root_transform
	if ragdoll.is_empty():
		return false

	_go_limp(ragdoll)
	var intro_driver: ActiveRagdollDriver = ragdoll.get("driver") as ActiveRagdollDriver
	if intro_driver != null and is_instance_valid(intro_driver):
		intro_driver.enabled = false
		intro_driver.set_physics_process(false)
	var rag: Dictionary = ragdoll.get("rag", {})
	var bodies: Dictionary = rag.get("bodies", {})
	var intro_anchor := bodies.get("anchor") as RigidBody3D
	if intro_anchor != null and is_instance_valid(intro_anchor):
		intro_anchor.freeze = true
		intro_anchor.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var intro_physics_material := PhysicsMaterial.new()
	intro_physics_material.friction = INTRO_DROP_FRICTION
	intro_physics_material.bounce = INTRO_DROP_RESTITUTION
	for key: Variant in bodies:
		if str(key) == "anchor":
			continue
		var body := bodies[key] as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue
		body.sleeping = false
		body.continuous_cd = true
		body.contact_monitor = true
		body.max_contacts_reported = 8
		body.physics_material_override = intro_physics_material
		body.linear_damp = INTRO_DROP_LINEAR_DAMP
		body.angular_damp = INTRO_DROP_ANGULAR_DAMP
		# Same world velocity on every body: the ragdoll was at rest in the aircraft.
		body.linear_velocity = inherited_velocity
		body.angular_velocity = Vector3.ZERO

	var hat: Node3D = _p1_hat_node if is_p1 else _p2_hat_node
	var head_body := bodies.get("head") as RigidBody3D
	if hat != null and is_instance_valid(hat) and head_body != null:
		_intro_hat_restore[player_index] = {
			"hat": hat,
			"parent": hat.get_parent(),
			"transform": hat.transform,
			"visible": hat.visible,
		}
		hat.reparent(head_body, true)

	_set_parts_visible(parts, false)
	_set_rig_scenes_visible(is_p1, false)
	_intro_pending_players.erase(player_index)
	ragdoll["drop"] = {
		"was_airborne": false,
		"floor_contacted": false,
		"settled": false,
		"settle_hold": 0.0,
		"peak_downward_speed": 0.0,
	}
	_intro_ragdolls[player_index] = ragdoll
	return true


## Freezes the ragdoll in its tumbled landing pose, then interpolates to the
## standing pose at the authoritative start position.
func begin_intro_get_up(player_index: int, landing_target: Vector3) -> bool:
	var ragdoll: Dictionary = _intro_ragdolls.get(player_index, {})
	if ragdoll.is_empty():
		return false
	var existing_recovery: Dictionary = ragdoll.get("recovery", {})
	if bool(existing_recovery.get("active", false)):
		return true

	var is_p1 := player_index == 1
	var parts: Dictionary = p1_parts if is_p1 else p2_parts
	var pelvis := parts.get("pelvis") as Node3D
	var rag: Dictionary = ragdoll.get("rag", {})
	var bodies: Dictionary = rag.get("bodies", {})
	var torso := bodies.get("torso") as RigidBody3D
	if torso == null or pelvis == null or not is_instance_valid(torso) or not is_instance_valid(pelvis):
		return false

	var target_offset := Vector3(
		landing_target.x - pelvis.global_position.x,
		0.0,
		landing_target.z - pelvis.global_position.z
	)
	var starts: Dictionary = {}
	var targets: Dictionary = {}
	for key: Variant in bodies:
		if str(key) == "anchor":
			continue
		var body := bodies[key] as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.gravity_scale = 0.0
		body.sleeping = true
		body.collision_layer = 0
		body.collision_mask = 0
		starts[key] = body.global_transform

		var target_node := pelvis if str(key) == "torso" else parts.get(str(key)) as Node3D
		if target_node == null or not is_instance_valid(target_node):
			return false
		var target_transform := target_node.global_transform
		target_transform.origin += target_offset
		targets[key] = target_transform

	ragdoll["recovery"] = {
		"active": true,
		"complete": false,
		"settle_elapsed": 0.0,
		"delay": INTRO_GET_UP_DELAY,
		"standing_started": false,
		"standing_elapsed": 0.0,
		"duration": INTRO_GET_UP_DURATION,
		"landing_target": landing_target,
		"starts": starts,
		"targets": targets,
	}
	_intro_ragdolls[player_index] = ragdoll
	return true


func _start_intro_get_up_motion(
	_player_index: int,
	_ragdoll: Dictionary,
	recovery: Dictionary
) -> bool:
	var starts: Dictionary = recovery.get("starts", {})
	var targets: Dictionary = recovery.get("targets", {})
	if starts.is_empty() or targets.is_empty():
		return false

	recovery["standing_started"] = true
	recovery["standing_elapsed"] = 0.0
	return true


func _intro_creepy_body_progress(body_key: String, progress: float) -> float:
	match body_key:
		"torso":
			return smoothstep(0.08, 0.78, progress)
		"head":
			# Keep the head limp, then make it catch up in one late snap.
			return smoothstep(0.54, 0.71, progress)
		"l_thigh", "r_thigh":
			return smoothstep(0.16, 0.76, progress)
		"l_calf", "r_calf":
			return smoothstep(0.24, 0.83, progress)
		"l_foot", "r_foot":
			return smoothstep(0.12, 0.68, progress)
		"l_upp_arm", "r_upp_arm":
			return smoothstep(0.30, 0.86, progress)
		"l_low_arm", "r_low_arm":
			return smoothstep(0.42, 0.93, progress)
		"l_hand", "r_hand":
			return smoothstep(0.55, 0.98, progress)
	return smoothstep(0.20, 0.90, progress)


func _intro_creepy_body_transform(
	body_key: String,
	start_transform: Transform3D,
	target_transform: Transform3D,
	progress: float,
	player_index: int
) -> Transform3D:
	var body_progress := _intro_creepy_body_progress(body_key, progress)
	var result := start_transform.interpolate_with(target_transform, body_progress)
	var player_side := -1.0 if player_index == 1 else 1.0
	var limb_side := -1.0 if body_key.begins_with("l_") else 1.0

	# A short involuntary tremor breaks the dead-still hold before the body rises.
	var twitch_envelope := 1.0 - smoothstep(0.0, 0.22, progress)
	var twitch := sin(progress * TAU * 7.0) * twitch_envelope
	var twitch_amount := 0.045 if body_key == "torso" else 0.085
	result.basis = Basis(Vector3.FORWARD, twitch * twitch_amount * limb_side) * result.basis

	if body_key == "torso":
		# The chest arches up first while turning slightly away from the camera.
		var arch_time := clampf((progress - 0.08) / 0.72, 0.0, 1.0)
		var arch := sin(arch_time * PI)
		result.origin += Vector3.UP * (0.34 * arch)
		result.basis = Basis(Vector3.UP, player_side * 0.30 * arch) * result.basis
		result.basis = Basis(Vector3.RIGHT, -0.22 * arch) * result.basis
	elif body_key == "head":
		# The head remains behind the torso, overshoots, then locks forward.
		var snap_time := clampf((progress - 0.53) / 0.34, 0.0, 1.0)
		var snap_arc := sin(snap_time * PI)
		result.origin += Vector3.UP * (0.12 * snap_arc)
		result.basis = Basis(Vector3.UP, player_side * 0.58 * snap_arc) * result.basis
		result.basis = Basis(Vector3.FORWARD, player_side * 0.24 * snap_arc) * result.basis
	elif body_key.contains("arm") or body_key.contains("hand"):
		# Arms hang after the torso, then reel inward with uneven spasms.
		var arm_time := clampf((progress - 0.28) / 0.70, 0.0, 1.0)
		var arm_arc := sin(arm_time * PI)
		var arm_spasm := sin(arm_time * TAU * 2.0) * (1.0 - arm_time)
		result.origin += Vector3.UP * (0.10 * arm_arc)
		result.basis = Basis(
			Vector3.FORWARD,
			limb_side * (0.32 * arm_arc + 0.12 * arm_spasm)
		) * result.basis
	elif body_key.contains("thigh") or body_key.contains("calf"):
		# Legs plant asymmetrically before the upper body finishes straightening.
		var leg_time := clampf((progress - 0.12) / 0.72, 0.0, 1.0)
		var leg_arc := sin(leg_time * PI)
		result.basis = Basis(Vector3.FORWARD, limb_side * 0.16 * leg_arc) * result.basis

	return result


func _update_intro_drop_physics(delta: float) -> void:
	for player_index: Variant in _intro_ragdolls.keys():
		var ragdoll: Dictionary = _intro_ragdolls.get(player_index, {})
		var recovery: Dictionary = ragdoll.get("recovery", {})
		if bool(recovery.get("active", false)):
			continue
		var drop: Dictionary = ragdoll.get("drop", {})
		if drop.is_empty():
			continue
		var rag: Dictionary = ragdoll.get("rag", {})
		var bodies: Dictionary = rag.get("bodies", {})
		var torso := bodies.get("torso") as RigidBody3D
		if torso == null or not is_instance_valid(torso):
			continue

		var maximum_body_speed := 0.0
		var contacting_floor := false
		for key: Variant in bodies:
			if str(key) == "anchor":
				continue
			var body := bodies[key] as RigidBody3D
			if body == null or not is_instance_valid(body):
				continue
			maximum_body_speed = maxf(maximum_body_speed, body.linear_velocity.length())
			if not body.freeze and body.contact_monitor and body.get_contact_count() > 0:
				contacting_floor = true

		var downward_speed := maxf(-torso.linear_velocity.y, 0.0)
		drop["peak_downward_speed"] = maxf(
			float(drop.get("peak_downward_speed", 0.0)),
			downward_speed
		)
		var height_above_floor := torso.global_position.y - StageConstants.FLOOR_TOP_Y
		if height_above_floor > INTRO_LANDED_TORSO_HEIGHT or downward_speed > 1.0:
			drop["was_airborne"] = true
		var near_floor := height_above_floor <= INTRO_LANDED_TORSO_HEIGHT + 0.35
		if bool(drop.get("was_airborne", false)):
			if contacting_floor or (near_floor and downward_speed < 2.0):
				drop["floor_contacted"] = true
		if height_above_floor > INTRO_LANDED_TORSO_HEIGHT + 1.25:
			drop["settled"] = false
			drop["settle_hold"] = 0.0

		var holding_still := (
			bool(drop.get("floor_contacted", false))
			and near_floor
			and maximum_body_speed <= INTRO_SETTLE_SPEED
		)
		if holding_still:
			drop["settle_hold"] = float(drop.get("settle_hold", 0.0)) + delta
		else:
			drop["settle_hold"] = 0.0
		if (
			not bool(drop.get("settled", false))
			and float(drop.get("settle_hold", 0.0)) >= INTRO_SETTLE_HOLD
		):
			drop["settled"] = true
		ragdoll["drop"] = drop
		_intro_ragdolls[player_index] = ragdoll


func _update_intro_get_ups(delta: float) -> void:
	_update_intro_drop_physics(delta)
	for player_index: Variant in _intro_ragdolls.keys():
		var ragdoll: Dictionary = _intro_ragdolls.get(player_index, {})
		var recovery: Dictionary = ragdoll.get("recovery", {})
		if not bool(recovery.get("active", false)) or bool(recovery.get("complete", false)):
			continue
		if not bool(recovery.get("standing_started", false)):
			var settle_elapsed := float(recovery.get("settle_elapsed", 0.0)) + delta
			recovery["settle_elapsed"] = settle_elapsed
			var hold_starts: Dictionary = recovery.get("starts", {})
			var hold_rag: Dictionary = ragdoll.get("rag", {})
			var hold_bodies: Dictionary = hold_rag.get("bodies", {})
			for key: Variant in hold_starts:
				var hold_body := hold_bodies.get(key) as RigidBody3D
				if hold_body == null or not is_instance_valid(hold_body):
					continue
				hold_body.linear_velocity = Vector3.ZERO
				hold_body.angular_velocity = Vector3.ZERO
				hold_body.global_transform = hold_starts[key]
			var delay := maxf(float(recovery.get("delay", INTRO_GET_UP_DELAY)), 0.0)
			if settle_elapsed >= delay:
				if not _start_intro_get_up_motion(int(player_index), ragdoll, recovery):
					continue
			ragdoll["recovery"] = recovery
			_intro_ragdolls[player_index] = ragdoll
			continue

		var elapsed := float(recovery.get("standing_elapsed", 0.0)) + delta
		var duration := maxf(float(recovery.get("duration", INTRO_GET_UP_DURATION)), 0.01)
		var progress := clampf(elapsed / duration, 0.0, 1.0)
		var starts: Dictionary = recovery.get("starts", {})
		var targets: Dictionary = recovery.get("targets", {})
		var rag: Dictionary = ragdoll.get("rag", {})
		var bodies: Dictionary = rag.get("bodies", {})
		for key: Variant in starts:
			var body := bodies.get(key) as RigidBody3D
			if body == null or not is_instance_valid(body) or not targets.has(key):
				continue
			var start_transform: Transform3D = starts[key]
			var target_transform: Transform3D = targets[key]
			body.global_transform = _intro_creepy_body_transform(
				str(key),
				start_transform,
				target_transform,
				progress,
				int(player_index)
			)

		recovery["standing_elapsed"] = elapsed
		if progress >= 1.0:
			recovery["complete"] = true
			for key: Variant in targets:
				var body := bodies.get(key) as RigidBody3D
				if body != null and is_instance_valid(body):
					body.global_transform = targets[key]
		ragdoll["recovery"] = recovery
		_intro_ragdolls[player_index] = ragdoll


## Returns physics evidence used by HelicopterArrivalDirector and runtime probes.
func get_intro_drop_state(player_index: int) -> Dictionary:
	var ragdoll: Dictionary = _intro_ragdolls.get(player_index, {})
	if ragdoll.is_empty():
		return {"active": false}
	var rag: Dictionary = ragdoll.get("rag", {})
	var bodies: Dictionary = rag.get("bodies", {})
	var torso := bodies.get("torso") as RigidBody3D
	if torso == null or not is_instance_valid(torso):
		return {"active": true, "physics_valid": false}
	var recovery: Dictionary = ragdoll.get("recovery", {})
	var drop: Dictionary = ragdoll.get("drop", {})
	var all_bodies_frozen := true
	var maximum_body_speed := 0.0
	for key: Variant in bodies:
		if str(key) == "anchor":
			continue
		var body := bodies[key] as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue
		all_bodies_frozen = all_bodies_frozen and (
			body.freeze or is_zero_approx(body.gravity_scale)
		)
		maximum_body_speed = maxf(maximum_body_speed, body.linear_velocity.length())
	var recovery_duration := maxf(
		float(recovery.get("duration", INTRO_GET_UP_DURATION)),
		0.01
	)
	var floor_contacted := bool(drop.get("floor_contacted", false))
	return {
		"active": true,
		"physics_valid": true,
		"position": torso.global_position,
		"linear_velocity": torso.linear_velocity,
		"speed": torso.linear_velocity.length(),
		"maximum_body_speed": maximum_body_speed,
		"all_bodies_frozen": all_bodies_frozen,
		"sleeping": torso.sleeping,
		"was_airborne": bool(drop.get("was_airborne", false)),
		"floor_contacted": floor_contacted,
		"landed": floor_contacted or bool(recovery.get("active", false)),
		"settled": bool(drop.get("settled", false)) or bool(recovery.get("active", false)),
		"peak_downward_speed": float(drop.get("peak_downward_speed", 0.0)),
		"recovering": bool(recovery.get("active", false)),
		"settle_elapsed": float(recovery.get("settle_elapsed", 0.0)),
		"get_up_delay": float(recovery.get("delay", INTRO_GET_UP_DELAY)),
		"standing_started": bool(recovery.get("standing_started", false)),
		"recovery_progress": clampf(
			float(recovery.get("standing_elapsed", 0.0)) / recovery_duration,
			0.0,
			1.0
		),
		"recovery_complete": bool(recovery.get("complete", false)),
	}


func has_intro_drops() -> bool:
	return not _intro_ragdolls.is_empty()


func has_intro_arrival() -> bool:
	return not _intro_pending_players.is_empty() or has_intro_drops()


## Builds and immediately releases the same physics trees while the transition
## cover is opaque, so first-use shapes, joints, meshes, and toon materials are warm.
func prewarm_intro_drop_ragdolls(player_count: int) -> void:
	if has_intro_drops():
		return
	var count := clampi(player_count, 1, 2)
	for player_index: int in range(1, count + 1):
		var is_p1 := player_index == 1
		var parts: Dictionary = p1_parts if is_p1 else p2_parts
		if parts.is_empty() or parts.get("pelvis") == null:
			continue
		var ragdoll := _setup_ragdoll(parts, is_p1)
		_teardown_ragdoll(ragdoll)
		var should_show := not _intro_pending_players.has(player_index)
		_set_parts_visible(parts, should_show)
		_set_hat_visible(is_p1, should_show)
		_set_rig_scenes_visible(is_p1, should_show)


## Restores hats before freeing their temporary ragdoll parents, then snaps the
## hidden presentation bodies back to the authoritative game-state positions.
func complete_intro_drops(gs: QuizGameState) -> void:
	_cleanup_intro_drops()
	if gs != null:
		update_from_state(gs)


func cancel_intro_drops() -> void:
	_cleanup_intro_drops()


func _cleanup_intro_drops() -> void:
	_intro_pending_players.clear()
	for player_index: Variant in _intro_hat_restore.keys():
		var restore: Dictionary = _intro_hat_restore[player_index]
		var hat := restore.get("hat") as Node3D
		var original_parent := restore.get("parent") as Node
		if hat != null and is_instance_valid(hat) and original_parent != null and is_instance_valid(original_parent):
			hat.reparent(original_parent, false)
			hat.transform = restore.get("transform", Transform3D.IDENTITY)
			hat.visible = bool(restore.get("visible", true))
	_intro_hat_restore.clear()

	for ragdoll: Dictionary in _intro_ragdolls.values():
		_teardown_ragdoll(ragdoll)
	_intro_ragdolls.clear()
	_set_parts_visible(p1_parts, true)
	_set_hat_visible(true, true)
	_set_rig_scenes_visible(true, true)
	if not p2_parts.is_empty():
		_set_parts_visible(p2_parts, true)
		_set_hat_visible(false, true)
		_set_rig_scenes_visible(false, true)


func _set_hat_visible(is_p1: bool, should_show: bool) -> void:
	var hat: Node3D = _p1_hat_node if is_p1 else _p2_hat_node
	if hat != null and is_instance_valid(hat):
		hat.visible = should_show


## 吹き飛んだラグドールの現在姿勢をそのまま四肢分散の開始位置へ引き継ぐ。
func _init_wall_ragdoll_explosion(ragdoll: Dictionary, fallback_parts: Dictionary, is_p1: bool) -> void:
	var ragdoll_meshes: Array[MeshInstance3D] = []
	var container: Node = ragdoll.get("container") as Node
	if container != null and is_instance_valid(container):
		for node: Node in container.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh != null and mesh.visible:
				ragdoll_meshes.append(mesh)

	if ragdoll_meshes.is_empty():
		_init_explosion(fallback_parts, is_p1, true)
	else:
		_init_explosion({"meshes": ragdoll_meshes}, is_p1, true)
	_teardown_ragdoll(ragdoll)


## 死亡演出で現在見えている身体の中心を返す。
## 壁ラグドール中は胴体、四肢分散後は全破片の重心を優先する。
func get_death_presentation_position(is_p1: bool) -> Vector3:
	var ragdoll: Dictionary = _p1_ragdoll if is_p1 else _p2_ragdoll
	var rag: Dictionary = ragdoll.get("rag", {})
	var rag_bodies: Dictionary = rag.get("bodies", {})
	var torso := rag_bodies.get("torso") as RigidBody3D
	if torso != null and is_instance_valid(torso):
		return torso.global_position

	var explosion_bodies := _p1_explosion_bodies if is_p1 else _p2_explosion_bodies
	var center := Vector3.ZERO
	var body_count := 0
	for body: RigidBody3D in explosion_bodies:
		if body != null and is_instance_valid(body):
			center += body.global_position
			body_count += 1
	if body_count > 0:
		return center / float(body_count)

	var parts: Dictionary = p1_parts if is_p1 else p2_parts
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis != null and is_instance_valid(pelvis):
		return pelvis.global_position
	if not is_p1 and p2_container != null and is_instance_valid(p2_container):
		return p2_container.global_position
	return global_position


func has_player_death_exploded(player_index: int) -> bool:
	if player_index == 1:
		return _p1_exploding
	if player_index == 2:
		return _p2_exploding
	return false


func play_result_explosion(player_index: int) -> void:
	var is_p1 := player_index == 1
	if not is_p1 and player_index != 2:
		return
	if (is_p1 and _p1_result_exploded) or (not is_p1 and _p2_result_exploded):
		return
	var parts: Dictionary = p1_parts if is_p1 else p2_parts
	if parts.is_empty():
		return
	if is_p1:
		_p1_result_exploded = true
		_p1_result_explosion_elapsed = 0.0
		_p1_exploding = true
	else:
		_p2_result_exploded = true
		_p2_result_explosion_elapsed = 0.0
		_p2_exploding = true
	_init_explosion(parts, is_p1, true)
	_set_parts_visible(parts, false)
	_set_hat_visible(is_p1, false)
	_set_rig_scenes_visible(is_p1, false)


func reset_result_presentation() -> void:
	_p1_result_exploded = false
	_p2_result_exploded = false
	_p1_result_explosion_elapsed = 0.0
	_p2_result_explosion_elapsed = 0.0
	_p1_exploding = false
	_p2_exploding = false
	_clear_explosion_bodies(true)
	_clear_explosion_bodies(false)
	_set_parts_visible(p1_parts, true)
	_set_hat_visible(true, true)
	_set_rig_scenes_visible(true, true)
	if not p2_parts.is_empty():
		_set_parts_visible(p2_parts, true)
		_set_hat_visible(false, true)
		_set_rig_scenes_visible(false, true)


func _exit_tree() -> void:
	# 爆発デブリは get_parent() 配下(別ツリー)に生成されるため、明示解放しないと
	# このノード破棄時に孤児として残存リークする。
	_clear_explosion_bodies(true)
	_clear_explosion_bodies(false)
	cancel_intro_drops()
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


func _load_ghost_mount_rig() -> void:
	_ghost_mount_rig_data.clear()
	var loaded: Variant = _load_fbx_scene(
		GHOST_MOUNT_ANIMATION_PATH,
		"GhostMountHeroicPoseRig"
	)
	if not (loaded is Dictionary):
		push_warning("Ghost mount animation could not be loaded")
		return
	_ghost_mount_rig_data = loaded
	var animation_player := _ghost_mount_rig_data.get("anim_player") as AnimationPlayer
	var animation_name := String(_ghost_mount_rig_data.get("anim_name", ""))
	if animation_player == null or animation_name.is_empty():
		_ghost_mount_rig_data.clear()
		push_warning("Ghost mount animation has no playable action")
		return
	var animation: Animation = animation_player.get_animation(animation_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_NONE
	animation_player.play(animation_name)
	animation_player.seek(0.0, true)
	animation_player.pause()


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
			var full: String = ("%s/%s" % [lib_name, a_name]) if not String(lib_name).is_empty() else String(a_name)
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
		if bone_indices.has(key):
			continue
		# Mixamo can number its namespace (for example mixamorig7_Hips).
		# Match the stable bone-name suffix so separately exported FBX clips retarget correctly.
		for cand in candidates[key]:
			var suffix: String = String(cand).replace("mixamorig:", "").replace("mixamorig_", "")
			for bone_idx: int in range(skeleton.get_bone_count()):
				var bone_name: String = skeleton.get_bone_name(bone_idx)
				if bone_name == suffix or bone_name.ends_with(":" + suffix) or bone_name.ends_with("_" + suffix):
					bone_indices[key] = bone_idx
					break
			if bone_indices.has(key):
				break
	print("[RIG]   [", node_name, "] Mapped ", bone_indices.size(), "/", candidates.size(), " bones")
	
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
	ToonPresets.remember_base_color(mesh_inst, color)

	return mesh_inst

var _run_phase: float = 0.0

func _process(dt: float) -> void:
	_time += dt
	_update_intro_get_ups(dt)
	var gs = QuizManager.game_state
	var speed: float = gs._active_wall_speed if gs else 3.5
	var mult := 1.0
	if Input.is_key_pressed(KEY_W):
		mult = 2.0
	_run_phase += dt * 8.0 * (speed / 3.5) * mult


## 黒画面中にプレイヤー表示モデルと選択中の帽子を実体化する。
## ゲーム状態やアニメーションは進めず、初回表示時の生成負荷だけを前倒しする。
func prepare_for_loading(gs: QuizGameState) -> void:
	if gs == null:
		return
	_sync_player_model_count(gs)
	set_hat(1, gs.p1_hat)
	set_toon_preset(1, ToonPresets.resolve_player_preset(gs, 1))
	if gs.num_players >= 2:
		set_hat(2, gs.p2_hat)
		set_toon_preset(2, ToonPresets.resolve_player_preset(gs, 2))


func _sync_player_model_count(gs: QuizGameState) -> void:
	# Ensure P2 is created if needed
	if gs.num_players >= 2 and p2_container == null:
		p2_container = Node3D.new()
		p2_container.name = "Player2"
		add_child(p2_container)
		p2_parts = _build_player_skeleton(false, p2_container)
		_p2_toon_preset_id = -1
		# P2ラグドールは p2_container.position 確定後に遅延生成する
	if gs.num_players < 2 and p2_container != null:
		# 爆発デブリは別親(get_parent())に在り container 解放では消えないので明示解放。
		# _p2_exploding を残すと再エントリ時に二度目の爆発が初期化されない不具合になる。
		_p2_exploding = false
		_clear_explosion_bodies(false)
		_teardown_ragdoll(_p2_ragdoll)
		_p2_ragdoll = {}
		_p2_driver = null
		p2_container.queue_free()
		p2_container = null
		p2_parts.clear()
		_p2_toon_preset_id = -1


func update_from_state(gs: QuizGameState) -> void:
	var pz: float = gs.player_z
	var walk_phase: float = _run_phase
	var mult := 1.0
	if Input.is_key_pressed(KEY_W):
		mult = 2.0
	var speed_ratio: float = clampf((gs._active_wall_speed / 3.5) * mult, 0.3, 6.0)

	_sync_player_model_count(gs)
	var desired_p1_toon := ToonPresets.resolve_player_preset(gs, 1)
	if desired_p1_toon != _p1_toon_preset_id:
		set_toon_preset(1, desired_p1_toon)
	if gs.num_players >= 2:
		var desired_p2_toon := ToonPresets.resolve_player_preset(gs, 2)
		if desired_p2_toon != _p2_toon_preset_id:
			set_toon_preset(2, desired_p2_toon)

	# --- Player 1 ---
	position = Vector3(gs.player_x, gs.player_y, gs.player_local_z)
	rotation.y = 0.0
	# The 1P avatar stays visible because normal solo play now uses a third-person camera.
	var p1_visual_hidden: bool = false

	# P1ラグドールは位置確定後の初回に生成(アンカー瞬間移動を回避)。
	# メニュープレビュー(SubViewport)では不要な物理負荷になるので生成しない
	# (表示メッシュも隠さないため、プレビューはブロック四肢のまま正しく描画される)。
	if USE_ACTIVE_RAGDOLL and not p1_visual_hidden and not _is_preview_subviewport() and _p1_ragdoll.is_empty() and not p1_parts.is_empty():
		_p1_ragdoll = _setup_ragdoll(p1_parts, true)
		_p1_driver = _p1_ragdoll.get("driver")

	if gs.p1_alive:
		if not _p1_result_exploded and (
			_p1_exploding or not _p1_explosion_bodies.is_empty() or not _p1_ragdoll.is_empty()
		):
			_p1_exploding = false
			_clear_explosion_bodies(true)
			_set_rig_scenes_visible(true, true)
			_set_hat_visible(true, true)
			# 脱力崩壊したラグドールを破棄→次フレームで直立状態に再生成(復活)
			if not _p1_ragdoll.is_empty():
				_teardown_ragdoll(_p1_ragdoll)
				_p1_ragdoll = {}
				_p1_driver = null
		_set_parts_visible(p1_parts, not p1_visual_hidden)
		if p1_visual_hidden:
			pass
		elif gs.p1_waiting_for_shark:
			var p1_float_pose_applied: bool = false
			if _p1_rig.is_rigged and _p1_rig.play_slot(AnimationRig.SLOT_TREADING_WATER):
				p1_float_pose_applied = true
				_apply_skeleton_pose(
					p1_parts,
					_p1_rig.active_skeleton,
					_p1_rig.active_bone_indices,
					_p1_rig.mirror_x
				)
			if not p1_float_pose_applied:
				_animate_struggle(p1_parts, gs.p1_ocean_float_time)
		elif not _p1_rig.is_rigged:
			var p1_is_playing := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE] or (
				gs.game_state == Constants.STATE_RESULT_CEREMONY
				and gs.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.MEADOW_RUN
			)
			_animate_skeleton(p1_parts, gs.player_y, gs.player_vel_y, p1_is_playing, walk_phase, false, 0)
		else:
			var is_active := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE] or (
				gs.game_state == Constants.STATE_RESULT_CEREMONY
				and gs.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.MEADOW_RUN
			)
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
		if _p1_result_exploded:
			_p1_result_explosion_elapsed += get_process_delta_time()
			_set_parts_visible(p1_parts, false)
			_set_hat_visible(true, false)
			_set_rig_scenes_visible(true, false)
			_update_explosion(true, _p1_result_explosion_elapsed)
	elif gs.game_over_timer > 0:
		if gs.p1_shark_killed:
			if not _p1_exploding:
				_p1_exploding = true
				_init_explosion(p1_parts, true)
			_set_parts_visible(p1_parts, false)
			if not _p1_explosion_bodies.is_empty():
				_update_explosion(
					true,
					gs.game_over_timer,
					true,
					gs.is_coop_mode(),
					-global_position.x
				)
		elif gs.p1_wall_impact:
			if gs.game_over_timer < QuizGameState.WALL_RAGDOLL_DURATION:
				if _p1_ragdoll.is_empty():
					_p1_ragdoll = _setup_ragdoll(p1_parts, true)
					_p1_driver = _p1_ragdoll.get("driver")
					_launch_wall_ragdoll(_p1_ragdoll, true)
			elif not _p1_exploding:
				_p1_exploding = true
				_init_wall_ragdoll_explosion(_p1_ragdoll, p1_parts, true)
				_p1_ragdoll = {}
				_p1_driver = null
			_set_hat_visible(true, false)
			_set_parts_visible(p1_parts, false)
			if not _p1_explosion_bodies.is_empty():
				_update_explosion(true, gs.game_over_timer - QuizGameState.WALL_RAGDOLL_DURATION)
		elif gs.game_over_timer < 2.0:
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
			if not _p2_result_exploded and (
				_p2_exploding or not _p2_explosion_bodies.is_empty() or not _p2_ragdoll.is_empty()
			):
				_p2_exploding = false
				_clear_explosion_bodies(false)
				_set_rig_scenes_visible(false, true)
				_set_hat_visible(false, true)
				# 脱力崩壊したラグドールを破棄→次フレームで直立状態に再生成(復活)
				if not _p2_ragdoll.is_empty():
					_teardown_ragdoll(_p2_ragdoll)
					_p2_ragdoll = {}
					_p2_driver = null
			_set_parts_visible(p2_parts, true)
			if gs.p2_waiting_for_shark:
				var p2_float_pose_applied: bool = false
				if _p2_rig.is_rigged and _p2_rig.play_slot(AnimationRig.SLOT_TREADING_WATER):
					p2_float_pose_applied = true
					_apply_skeleton_pose(
						p2_parts,
						_p2_rig.active_skeleton,
						_p2_rig.active_bone_indices,
						_p2_rig.mirror_x
					)
				if not p2_float_pose_applied:
					_animate_struggle(p2_parts, gs.p2_ocean_float_time)
			elif not _p2_rig.is_rigged:
				var p2_is_playing := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE] or (
					gs.game_state == Constants.STATE_RESULT_CEREMONY
					and gs.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.MEADOW_RUN
				)
				_animate_skeleton(p2_parts, gs.player2_y, gs.player2_vel_y, p2_is_playing, walk_phase * 1.1, true, 0)
			else:
				var is_active := gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE] or (
					gs.game_state == Constants.STATE_RESULT_CEREMONY
					and gs.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.MEADOW_RUN
				)
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
			if _p2_result_exploded:
				_p2_result_explosion_elapsed += get_process_delta_time()
				_set_parts_visible(p2_parts, false)
				_set_hat_visible(false, false)
				_set_rig_scenes_visible(false, false)
				_update_explosion(false, _p2_result_explosion_elapsed)
		elif gs.player2_game_over_timer > 0:
			if gs.p2_shark_killed:
				if not _p2_exploding:
					_p2_exploding = true
					_init_explosion(p2_parts, false)
				_set_parts_visible(p2_parts, false)
				if not _p2_explosion_bodies.is_empty():
					_update_explosion(
						false,
						gs.player2_game_over_timer,
						true,
						gs.is_coop_mode(),
						-global_position.x
					)
			elif gs.p2_wall_impact:
				if gs.player2_game_over_timer < QuizGameState.WALL_RAGDOLL_DURATION:
					if _p2_ragdoll.is_empty():
						_p2_ragdoll = _setup_ragdoll(p2_parts, false)
						_p2_driver = _p2_ragdoll.get("driver")
						_launch_wall_ragdoll(_p2_ragdoll, false)
				elif not _p2_exploding:
					_p2_exploding = true
					_init_wall_ragdoll_explosion(_p2_ragdoll, p2_parts, false)
					_p2_ragdoll = {}
					_p2_driver = null
				_set_hat_visible(false, false)
				_set_parts_visible(p2_parts, false)
				if not _p2_explosion_bodies.is_empty():
					_update_explosion(false, gs.player2_game_over_timer - QuizGameState.WALL_RAGDOLL_DURATION)
			elif gs.player2_game_over_timer < 2.0:
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

	_apply_result_camera_facing(gs)

	# The solo player root must remain visible for the third-person camera.
	# Individual meshes still control death/explosion visibility above.
	if gs.num_players == 1:
		visible = true


func _apply_result_camera_facing(gs: QuizGameState) -> void:
	if not (
		gs.result_presentation_active
		and gs.game_state in [Constants.STATE_RESULT_CEREMONY, Constants.STATE_CLEAR]
		and gs.result_ceremony_phase >= QuizGameState.ResultCeremonyPhase.SCORE_ROLL
	):
		return
	var p1_pelvis := p1_parts.get("pelvis") as Node3D
	if p1_pelvis != null:
		p1_pelvis.rotation.y = wrapf(p1_pelvis.rotation.y + PI, -PI, PI)
	var p2_pelvis := p2_parts.get("pelvis") as Node3D
	if p2_pelvis != null:
		p2_pelvis.rotation.y = wrapf(p2_pelvis.rotation.y + PI, -PI, PI)

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
	# Hands are Node3D roots containing several MeshInstance3D children. Restoring
	# only the child meshes leaves the hidden parent in place after a ragdoll ends.
	for key: String in _RAGDOLL_HIDE_KEYS:
		var part_root := parts.get(key) as Node3D
		if part_root != null and not part_root is MeshInstance3D:
			part_root.visible = vis and not hidden.has(part_root)
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


func _init_explosion(parts: Dictionary, is_p1: bool, force_non_forward: bool = false) -> void:
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

		var impulse_z := randf_range(EXPLOSION_IMPULSE_Z_MIN, EXPLOSION_IMPULSE_Z_MAX)
		if force_non_forward:
			# メニューは前方=-Z、本編は前方=+Z。どちらも必ず逆側へ分散させる。
			var backward_z_sign := 1.0 if is_preview else -1.0
			impulse_z = backward_z_sign * randf_range(
				WALL_EXPLOSION_BACKWARD_Z_MIN,
				WALL_EXPLOSION_BACKWARD_Z_MAX
			)
		var impulse := Vector3(
			sx * randf_range(EXPLOSION_IMPULSE_X_MIN, EXPLOSION_IMPULSE_X_MAX),
			randf_range(EXPLOSION_IMPULSE_Y_MIN, EXPLOSION_IMPULSE_Y_MAX),
			impulse_z
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

		if force_non_forward:
			# 壁衝突は質量に左右されない控えめな速度指定にし、画面外へ消えにくくする。
			piece.linear_velocity = Vector3(
				sx * randf_range(WALL_EXPLOSION_SIDE_SPEED_MIN, WALL_EXPLOSION_SIDE_SPEED_MAX),
				randf_range(WALL_EXPLOSION_UP_SPEED_MIN, WALL_EXPLOSION_UP_SPEED_MAX),
				impulse_z
			)
			piece.angular_velocity = Vector3(
				randf_range(-WALL_EXPLOSION_SPIN_MAX, WALL_EXPLOSION_SPIN_MAX),
				randf_range(-WALL_EXPLOSION_SPIN_MAX * 0.35, WALL_EXPLOSION_SPIN_MAX * 0.35),
				randf_range(-WALL_EXPLOSION_SPIN_MAX, WALL_EXPLOSION_SPIN_MAX)
			)
		else:
			if is_preview:
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


func create_ghost_rider_visual(player_index: int) -> Node3D:
	var rider := Node3D.new()
	rider.name = "GhostRiderP%d" % player_index
	var parts := _build_player_skeleton(player_index == 1, rider)
	rider.set_meta("ghost_mount_parts", parts)
	var bind_transforms: Dictionary = {}
	for part_name: Variant in parts:
		var part_variant: Variant = parts[part_name]
		if part_variant is Node3D:
			var part := part_variant as Node3D
			bind_transforms[part_name] = part.transform
	rider.set_meta(GHOST_RIDER_BIND_TRANSFORMS_META, bind_transforms)
	var mounted_transform := Transform3D(
		Basis.from_scale(Vector3.ONE * GHOST_RIDER_MOUNT_SCALE),
		Vector3.ZERO
	)
	rider.set_meta(GHOST_RIDER_MOUNT_SCALE_META, GHOST_RIDER_MOUNT_SCALE)
	rider.set_meta(GHOST_RIDER_MOUNT_TRANSFORM_META, mounted_transform)
	rider.transform = mounted_transform
	apply_ghost_rider_mounted_pose(rider)

	var hat_id := _p1_hat_id if player_index == 1 else _p2_hat_id
	if hat_id != HatData.HAT_NONE:
		var hat_node := HatFactory.create_hat(hat_id)
		if hat_node:
			parts["hat_mount"].add_child(hat_node)
			parts["hat_meshes"] = HatFactory.get_hat_meshes(hat_node)

	var ghost_meshes: Array[MeshInstance3D] = []
	for body_mesh: MeshInstance3D in parts["meshes"]:
		ghost_meshes.append(body_mesh)
	for hat_mesh: MeshInstance3D in parts["hat_meshes"]:
		ghost_meshes.append(hat_mesh)
	for mesh_instance in ghost_meshes:
		_apply_ghost_material(mesh_instance)
	_add_ghost_rider_aura(rider, player_index)
	return rider


func apply_ghost_rider_mounted_pose(
	rider: Node3D,
	blend_weight: float = 1.0,
	preserve_upper_body: bool = false
) -> bool:
	if rider == null or not is_instance_valid(rider):
		return false
	var parts_variant: Variant = rider.get_meta("ghost_mount_parts", {})
	if not (parts_variant is Dictionary):
		return false
	var parts: Dictionary = parts_variant
	var weight := clampf(blend_weight, 0.0, 1.0)
	var bind_transforms_variant: Variant = rider.get_meta(
		GHOST_RIDER_BIND_TRANSFORMS_META,
		{}
	)
	if bind_transforms_variant is Dictionary:
		var bind_transforms: Dictionary = bind_transforms_variant
		var lower_body_parts := {
			"pelvis": true,
			"l_hip": true,
			"r_hip": true,
			"l_knee": true,
			"r_knee": true,
			"l_ankle": true,
			"r_ankle": true,
			"l_toe": true,
			"r_toe": true,
		}
		for part_name: Variant in bind_transforms:
			if preserve_upper_body and not lower_body_parts.has(part_name):
				continue
			var part := parts.get(part_name) as Node3D
			var bind_transform_variant: Variant = bind_transforms[part_name]
			if part != null and bind_transform_variant is Transform3D:
				part.transform = part.transform.interpolate_with(
					bind_transform_variant as Transform3D,
					weight
				)
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null:
		return false
	# Put the bottom of the torso directly onto the fitted saddle seat.  The
	# former positive Y target left the rider visibly floating above the shark.
	pelvis.position = pelvis.position.lerp(Vector3(0.0, -0.25, 0.02), weight)
	_blend_ghost_rider_part_rotation(pelvis, Vector3.ZERO, weight)

	var lower_body_targets: Dictionary = {
		"l_hip": Vector3(62.0, 0.0, -24.0),
		"r_hip": Vector3(62.0, 0.0, 24.0),
		"l_knee": Vector3(-92.0, 0.0, 0.0),
		"r_knee": Vector3(-92.0, 0.0, 0.0),
		"l_ankle": Vector3(34.0, 0.0, 0.0),
		"r_ankle": Vector3(34.0, 0.0, 0.0),
		"l_toe": Vector3.ZERO,
		"r_toe": Vector3.ZERO,
	}
	for part_name: String in lower_body_targets:
		_blend_ghost_rider_part_rotation(
			parts.get(part_name) as Node3D,
			lower_body_targets[part_name],
			weight
		)

	if not preserve_upper_body:
		var upper_body_targets: Dictionary = {
			"spine": Vector3(-18.0, 0.0, 0.0),
			"neck": Vector3(14.0, 0.0, 0.0),
			"head_pivot": Vector3.ZERO,
			# These asymmetric targets follow the two animated grip centers rather
			# than mirroring around the shark's undeformed bind pose.
			"l_shoulder": Vector3(62.0, 0.0, 39.0),
			"r_shoulder": Vector3(83.0, 0.0, -36.0),
			"l_elbow": Vector3(-65.0, 0.0, -6.0),
			"r_elbow": Vector3(-86.0, 0.0, -12.0),
			"l_wrist": Vector3(0.0, 0.0, -8.0),
			"r_wrist": Vector3(0.0, 0.0, 8.0),
		}
		for part_name: String in upper_body_targets:
			_blend_ghost_rider_part_rotation(
				parts.get(part_name) as Node3D,
				upper_body_targets[part_name],
				weight
			)
	return true


func make_ghost_rider_opaque(rider: Node3D) -> void:
	if rider == null or not is_instance_valid(rider):
		return
	for node: Node in rider.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null:
			continue
		var material := mesh_instance.material_override as StandardMaterial3D
		if material == null:
			continue
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		var opaque_color := material.albedo_color
		opaque_color.a = 1.0
		material.albedo_color = opaque_color
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	# Soul motes look like the rider is still translucent after contact.
	var aura := rider.find_child("GhostAura", true, false) as GPUParticles3D
	if aura != null:
		aura.emitting = false
		aura.visible = false


func make_ghost_rider_translucent(rider: Node3D) -> void:
	if rider == null or not is_instance_valid(rider):
		return
	for node: Node in rider.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			_apply_ghost_material(mesh_instance)
	var aura := rider.find_child("GhostAura", true, false) as GPUParticles3D
	if aura != null:
		aura.visible = true
		aura.emitting = true


func apply_ghost_rider_result_pose(
	rider: Node3D,
	player_index: int,
	moving: bool,
	time_seconds: float
) -> bool:
	if rider == null or not is_instance_valid(rider):
		return false
	var parts_variant: Variant = rider.get_meta("ghost_mount_parts", {})
	if not (parts_variant is Dictionary):
		return false
	var parts: Dictionary = parts_variant
	var bind_transforms_variant: Variant = rider.get_meta(GHOST_RIDER_BIND_TRANSFORMS_META, {})
	if bind_transforms_variant is Dictionary:
		for part_name: Variant in bind_transforms_variant:
			var part := parts.get(part_name) as Node3D
			var bind_transform_variant: Variant = bind_transforms_variant[part_name]
			if part != null and bind_transform_variant is Transform3D:
				part.transform = bind_transform_variant as Transform3D
	_animate_skeleton(
		parts,
		0.0,
		0.0,
		moving,
		time_seconds * 5.5,
		player_index == 2,
		0
	)
	return true


func _blend_ghost_rider_part_rotation(
	part: Node3D,
	target_degrees: Vector3,
	weight: float
) -> void:
	if part == null:
		return
	var target_quaternion := Quaternion(
		Basis.from_euler(Vector3(
			deg_to_rad(target_degrees.x),
			deg_to_rad(target_degrees.y),
			deg_to_rad(target_degrees.z)
		))
	)
	part.quaternion = part.quaternion.slerp(target_quaternion, weight)


func sample_ghost_mount_pose(rider: Node3D, time_seconds: float) -> bool:
	if rider == null or not is_instance_valid(rider) or _ghost_mount_rig_data.is_empty():
		return false
	var parts_variant: Variant = rider.get_meta("ghost_mount_parts", {})
	if not (parts_variant is Dictionary):
		return false
	var parts: Dictionary = parts_variant
	var skeleton := _ghost_mount_rig_data.get("skeleton") as Skeleton3D
	var animation_player := _ghost_mount_rig_data.get("anim_player") as AnimationPlayer
	var bone_indices_variant: Variant = _ghost_mount_rig_data.get("bone_indices", {})
	var animation_name := String(_ghost_mount_rig_data.get("anim_name", ""))
	if (
		skeleton == null
		or animation_player == null
		or not (bone_indices_variant is Dictionary)
		or animation_name.is_empty()
	):
		return false
	var animation: Animation = animation_player.get_animation(animation_name)
	if animation == null:
		return false
	if animation_player.current_animation != animation_name:
		animation_player.play(animation_name)
		animation_player.pause()
	animation_player.seek(clampf(time_seconds, 0.0, animation.length), true)
	_apply_skeleton_pose(parts, skeleton, bone_indices_variant, true)
	return true


func apply_ghost_rider_mount_hold_pose(rider: Node3D) -> bool:
	# The imported clip supplies the approach only. Its global-basis mapping also
	# carries rig scale into the procedural pivots, so the hold must restore the
	# rider's bind transforms before applying the measured seat-and-grip pose.
	return apply_ghost_rider_mounted_pose(rider)


func apply_ghost_rider_emote_pose(
	rider: Node3D,
	player_index: int,
	emote_id: int
) -> bool:
	if rider == null or not is_instance_valid(rider) or emote_id <= 0:
		return false
	var parts_variant: Variant = rider.get_meta("ghost_mount_parts", {})
	if not (parts_variant is Dictionary):
		return false
	var parts: Dictionary = parts_variant
	var is_p2 := player_index == 2
	var rig := _p2_rig if is_p2 else _p1_rig
	var normalized_emote := EmoteData.normalize_emote_id(emote_id)
	if rig.is_rigged and rig.select_animation(
		0.0,
		false,
		normalized_emote,
		false,
		true,
		false,
		true
	):
		_apply_skeleton_pose(
			parts,
			rig.active_skeleton,
			rig.active_bone_indices,
			rig.mirror_x
		)
		return true
	_animate_emote(parts, normalized_emote, is_p2)
	return true


func stop_ghost_rider_emote(rider: Node3D, player_index: int) -> void:
	var rig := _p2_rig if player_index == 2 else _p1_rig
	rig.reset_thriller_sequence()
	rig.stop_all()
	if rider != null and is_instance_valid(rider):
		apply_ghost_rider_mount_hold_pose(rider)


func get_ghost_mount_animation_length() -> float:
	if _ghost_mount_rig_data.is_empty():
		return 0.0
	var animation_player := _ghost_mount_rig_data.get("anim_player") as AnimationPlayer
	var animation_name := String(_ghost_mount_rig_data.get("anim_name", ""))
	if animation_player == null or animation_name.is_empty():
		return 0.0
	var animation: Animation = animation_player.get_animation(animation_name)
	return animation.length if animation != null else 0.0


func _apply_ghost_material(mesh_instance: MeshInstance3D) -> void:
	if not mesh_instance:
		return
	var source_material: Material = mesh_instance.material_override
	if source_material == null and mesh_instance.mesh and mesh_instance.mesh.get_surface_count() > 0:
		source_material = mesh_instance.mesh.surface_get_material(0)
	var material := StandardMaterial3D.new()
	if source_material is StandardMaterial3D:
		material = source_material.duplicate()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.62
	material.emission_enabled = true
	material.emission = Color(material.albedo_color.r, material.albedo_color.g, material.albedo_color.b, 1.0)
	material.emission_energy_multiplier = 1.75
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_ghost_rider_aura(rider: Node3D, player_index: int) -> void:
	var aura_color := (
		Color(1.0, 0.48, 0.16, 0.74)
		if player_index == 1
		else Color(0.18, 0.68, 1.0, 0.74)
	)
	var aura := GPUParticles3D.new()
	aura.name = "GhostAura"
	aura.position = Vector3(0.0, 1.0, 0.0)
	aura.amount = 18
	aura.lifetime = 0.85
	aura.randomness = 0.42
	aura.visibility_aabb = AABB(Vector3(-1.2, -1.2, -1.2), Vector3(2.4, 3.0, 2.4))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.55
	process_material.direction = Vector3.UP
	process_material.spread = 32.0
	process_material.initial_velocity_min = 0.18
	process_material.initial_velocity_max = 0.55
	process_material.gravity = Vector3(0.0, 0.35, 0.0)
	process_material.scale_min = 0.55
	process_material.scale_max = 1.25
	aura.process_material = process_material
	var mote_mesh := SphereMesh.new()
	mote_mesh.radius = 0.028
	mote_mesh.height = 0.075
	var mote_material := StandardMaterial3D.new()
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_material.albedo_color = aura_color
	mote_material.emission_enabled = true
	mote_material.emission = Color(aura_color.r, aura_color.g, aura_color.b, 1.0)
	mote_material.emission_energy_multiplier = 1.8
	mote_mesh.material = mote_material
	aura.draw_pass_1 = mote_mesh
	rider.add_child(aura)

	var glow := OmniLight3D.new()
	glow.name = "GhostGlow"
	glow.position = Vector3(0.0, 1.0, 0.0)
	glow.light_color = Color(aura_color.r, aura_color.g, aura_color.b, 1.0)
	glow.light_energy = 0.45
	glow.omni_range = 3.2
	glow.shadow_enabled = false
	rider.add_child(glow)

# ============================================================
# Hat Management
# ============================================================

func set_toon_preset(player_id: int, preset_id: int) -> void:
	var normalized := ToonPresets.normalize(preset_id)
	if player_id == 1:
		ToonPresets.apply_to_parts(p1_parts, normalized)
		_p1_toon_preset_id = normalized
	elif player_id == 2 and not p2_parts.is_empty():
		ToonPresets.apply_to_parts(p2_parts, normalized)
		_p2_toon_preset_id = normalized


func set_hat(player_id: int, hat_id: int) -> void:
	"""Set a hat for the specified player (1 or 2)."""
	if player_id == 1:
		if _p1_hat_id == hat_id and (
			hat_id == HatData.HAT_NONE or is_instance_valid(_p1_hat_node)
		):
			return
		_set_hat_for_parts(p1_parts, hat_id, true)
	elif player_id == 2 and p2_parts and p2_parts.has("hat_mount"):
		if _p2_hat_id == hat_id and (
			hat_id == HatData.HAT_NONE or is_instance_valid(_p2_hat_node)
		):
			return
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

class_name MenuWallBackgroundPreview
extends Node

signal game_start_departure_finished(success: bool)

## メインメニュー背景: カスタマイズ「壁速度」タブ／壁速度設定画面と同型の3Dプレビュー

const WALL_SCENE: PackedScene = preload("res://scenes/quiz_wall.tscn")
const PLAYER_CONTROLLER_SCRIPT: Script = preload("res://scripts/world/player_controller.gd")
const MenuPreviewCameraSettingsScript = preload("res://scripts/ui/menu_preview_camera_settings.gd")
const MenuPreviewDoorLearnerScript = preload("res://scripts/ui/menu_preview_door_learner.gd")
const MenuPreviewActorAIStateScript = preload("res://scripts/ui/menu_preview_actor_ai_state.gd")
const PreviewWallMergeAnimatorScript = preload("res://scripts/ui/preview_wall_merge_animator.gd")
const HelicopterArrivalDirectorScript = preload("res://scripts/world/helicopter_arrival_director.gd")

const WALL_SPACING := 30.0
const MENU_INTRO_WALL_START_Z := -72.0
const PREVIEW_PLAYER_X: float = -3.5
const PREVIEW_PLAYER2_X: float = 3.5
const PREVIEW_DOOR_HALF_DEPTH_Z: float = 0.30
## 本編 game_state の wall_z - 0.4 を扉手前(+Z)基準に換算（0.4 + 扉半奥行0.3）
const PREVIEW_WALL_CONTACT_Z: float = 0.70
const PREVIEW_RED_DOOR_INDEX: int = 1
## quiz_wall.gd の 2択ドア位置（左=青, 右=赤）
const PREVIEW_DOOR_X_LEFT: float = 3.5
const PREVIEW_DOOR_X_RIGHT: float = -3.5
const PREVIEW_DOOR_HALF_WIDTH: float = 1.8
const PREVIEW_DOOR_PASS_MARGIN: float = 0.4
const PREVIEW_WALL_SHATTER_DIR_Z: float = 1.0
## キャラと壁が重ならないよう確保する Z 方向の最小クリアランス
const PREVIEW_WALL_PLAYER_CLEAR_Z: float = 5.5
const PREVIEW_WALL_PUSH_BACK_Z: float = 6.5
const AUTO_WALL_SPEED: float = 28.0 / (4.0 + 5.0)
const AI_STATE_NORMAL: int = 0
const AI_STATE_CRASH_RUNUP: int = 1
const AI_STATE_KNOCKBACK: int = 2
const AI_STATE_OCEAN_FALL: int = 3
const AI_STATE_DEAD: int = 4
const AI_STATE_RESPAWN: int = 5
const AI_STATE_ACROBATICS: int = 6
const AI_STATE_TAUNT: int = 7

const AI_ACTION_INTERVAL_MIN: float = 1.1
const AI_ACTION_INTERVAL_MAX: float = 2.6
## 2Pメニュープレビューでは行動の切り替え時刻をずらし、同時に同じ動きへ入るのを防ぐ。
const AI_2P_P1_ACTION_INTERVAL_SCALE: float = 0.82
const AI_2P_P2_ACTION_INTERVAL_SCALE: float = 1.18
## 目標位置と走行アニメの個体差。ゲーム本編には影響せず、メニュープレビューだけに適用する。
const AI_2P_TARGET_SEPARATION_X: float = 1.45
const AI_2P_TARGET_SEPARATION_Z: float = 1.10
const AI_2P_P1_RUN_ANIM_MULT: float = 0.92
const AI_2P_P2_RUN_ANIM_MULT: float = 1.08
const AI_WEIGHT_IDLE: float = 0.20
const AI_WEIGHT_LANE_SHIFT: float = 0.22
const AI_WEIGHT_STEP_FORWARD: float = 0.10
const AI_WEIGHT_STEP_BACK: float = 0.10
const AI_WEIGHT_JUMP: float = 0.05
const AI_WEIGHT_EMOTE: float = 0.26
const AI_WEIGHT_ACROBATICS: float = 0.07
const AI_DEPTH_STEP_MIN: float = 1.0
const AI_DEPTH_STEP_MAX: float = 3.4
## 本編で W 押下時と同様の走行アニメ加速（update_from_state の mult=2.0 相当）
const PREVIEW_RUN_ANIM_SPEED_MULT: float = 2.0
const PREVIEW_RUN_ANIM_SPEED_BASE: float = 3.0
const AI_WEIGHT_ACCIDENT: float = 0.11
## 2P では両者が左右ドアを占拠しやすく自然ミスが減るため、意図的事故の重みを上げる
const AI_2P_ACCIDENT_WEIGHT_MULT: float = 1.85
## 2P 中に左右ドア付近へ寄る確率
const AI_2P_EDGE_WANDER_CHANCE: float = 0.12
const AI_ACCIDENT_CRASH_RATIO: float = 0.45
const PENDING_ACCIDENT_NONE: int = 0
const PENDING_ACCIDENT_WALL: int = 1
const PENDING_ACCIDENT_OCEAN: int = 2
const AI_ACCIDENT_COOLDOWN_MIN: float = 7.5
const AI_ACCIDENT_COOLDOWN_MAX: float = 12.0

## 左右ドア（±3.5）の両方へ行ける X 範囲
const AI_PLAYER_X_MIN: float = PREVIEW_DOOR_X_RIGHT - 0.35
const AI_PLAYER_X_MAX: float = PREVIEW_DOOR_X_LEFT + 0.35
const AI_DOOR_VISIT_CHANCE: float = 0.55
const AI_LEARN_APPROACH_MIN_DIST: float = 0.4
const AI_LEARN_APPROACH_MAX_DIST: float = 18.0
const AI_LANE_SHIFT_SPEED_MIN: float = 2.2
const AI_LANE_SHIFT_SPEED_MAX: float = 3.6
const AI_DEPTH_RANGE_BACK: float = -4.8
const AI_DEPTH_RANGE_FRONT: float = 4.2
const AI_DEPTH_SHIFT_SPEED_MIN: float = 2.0
const AI_DEPTH_SHIFT_SPEED_MAX: float = 4.0
const AI_JUMP_SPEED_MIN: float = 6.4
const AI_JUMP_SPEED_MAX: float = 7.4
const AI_EMOTE_DURATION_MIN: float = 4.8
const AI_EMOTE_DURATION_MAX: float = 8.0
const AI_ACRO_EMOTE_BURST_DURATION_MIN: float = 2.8
const AI_ACRO_EMOTE_BURST_DURATION_MAX: float = 4.5
const AI_GRAVITY: float = 26.0
const AI_OCEAN_GRAVITY_SCALE: float = 1.35
const AI_DEAD_TO_RESPAWN_MIN: float = 3.2
const AI_DEAD_TO_RESPAWN_MAX: float = 4.1
const PREVIEW_DEATH_SHARD_LINGER_SEC: float = 5.0
const AI_TAUNT_EMOTE_LOCK: float = 99999.0
const AI_RESPAWN_START_Y_MIN: float = 5.5
const AI_RESPAWN_START_Y_MAX: float = 7.0
const AI_RESPAWN_DOWN_SPEED_MIN: float = 5.1
const AI_RESPAWN_DOWN_SPEED_MAX: float = 6.9
const AI_ACRO_DURATION_MIN: float = 2.4
const AI_ACRO_DURATION_MAX: float = 4.0
const AI_ACRO_JUMP_SPEED_MIN: float = 8.2
const AI_ACRO_JUMP_SPEED_MAX: float = 10.2
const AI_ACRO_BURST_INTERVAL_MIN: float = 1.15
const AI_ACRO_BURST_INTERVAL_MAX: float = 2.05
const AI_ACRO_EMOTE_BURST_CHANCE: float = 0.35
const AI_KNOCKBACK_DURATION_MIN: float = 0.45
const AI_KNOCKBACK_DURATION_MAX: float = 0.72
const AI_KNOCKBACK_DAMPING: float = 6.5
const AI_KNOCKBACK_X_RANGE_PAD: float = 1.0
const AI_KNOCKBACK_Z_BACK_PAD: float = 1.1
const AI_KNOCKBACK_Z_FRONT_PAD: float = 0.55
const PREVIEW_FLOOR_Y: float = 0.0
const PREVIEW_BELT_Z_MIN: float = AI_DEPTH_RANGE_BACK
const PREVIEW_BELT_Z_MAX: float = AI_DEPTH_RANGE_FRONT
const PREVIEW_BELT_EDGE_FALL_Z: float = 4.55
## 海落下待機中だけ通常上限(4.2)を超えて端まで進める
const PREVIEW_OCEAN_DEPTH_MAX: float = PREVIEW_BELT_EDGE_FALL_Z + 0.85
const PREVIEW_BELT_EDGE_RUSH_SPEED: float = 4.2

## 壁速度タブ基準から少し引いて左寄せ（UIが右側のため）
const PREVIEW_CAM_POS := Vector3(-18.0, 6.1, 23.15)
const PREVIEW_CAM_ROT_DEG := Vector3(-14.0, -19.0, 0.0)
const PREVIEW_CAM_FOV := 37.5
const PREVIEW_CAM_H_OFFSET := 0.05

var _viewport: SubViewport
var _preview_camera: Camera3D
var _stage_env: StageEnvironment = null
var _preview_walls: Array[Node3D] = []
var _wall_merge: PreviewWallMergeAnimator = null
var _preview_scroll_z: float = 0.0
var _preview_speed: float = AUTO_WALL_SPEED
var _conveyor_paused: bool = false
var _preview_player: Node3D
var _preview_gs: QuizGameState
var _ai_time: float = 0.0
var _linger_time: float = 0.0
var _p1_death_shard_clear_t: float = -1.0
var _p2_death_shard_clear_t: float = -1.0
var _applied_preview_p1_hat: int = -999
var _applied_preview_p2_hat: int = -999
var _p1_ai: MenuPreviewActorAIState
var _p2_ai: MenuPreviewActorAIState
## 本物の問題を壁に載せるためのオフライン問題プロバイダ (API不要)
var _quiz_provider: QuizProvider = null
var _preview_subject_idx: int = 0
var _menu_synced_player_count: int = 2
var _p2_remove_deadline: float = -1.0
var _preview_p1_rig_emote_ids: Array[int] = []
var _preview_p2_rig_emote_ids: Array[int] = []
## カスタマイズUIが共有ワールドを使用中はメニューAIを止めてカメラ制御を譲る
var _customize_active: bool = false
## スキン／エモートタブ時は流れる壁を隠して近接プレビューにする
var _customize_walls_hidden: bool = false
## カスタマイズ入場時のメニューカメラ姿勢（退場時に補間で復帰する）
var _menu_cam_pose: Dictionary = {}
var _menu_helicopter_intro: HelicopterArrivalDirector = null
var _menu_intro_active := false
var _menu_intro_requested_player_count := 2
var _menu_start_departure: HelicopterArrivalDirector = null
var _menu_start_departure_active := false
## Keep the extracted runners hidden until the menu scene is replaced.
var _menu_departure_hold := false


func _ready() -> void:
	_viewport = get_parent() as SubViewport
	_wall_merge = PreviewWallMergeAnimatorScript.new()
	_p1_ai = MenuPreviewActorAIStateScript.new()
	_p2_ai = MenuPreviewActorAIStateScript.new()
	_quiz_provider = QuizProvider.new()
	add_child(_quiz_provider)
	_preview_subject_idx = randi() % Constants.SUBJECTS.size()
	set_process(false)
	_resolve_preview_speed()
	_build_3d_scene()
	set_process(true)


func get_camera() -> Camera3D:
	return _preview_camera


func get_stage_environment() -> StageEnvironment:
	return _stage_env


func apply_graphics_quality() -> void:
	if _viewport:
		GraphicsQuality.apply_text_viewport(_viewport, GameManager.graphics_quality)
	if not _stage_env:
		return
	if _stage_env.environment_node and _stage_env.environment_node.environment:
		GraphicsQuality.apply_environment(
			_stage_env.environment_node.environment,
			GameManager.graphics_quality
		)
	if _stage_env.directional_light:
		_stage_env.directional_light.shadow_enabled = GraphicsQuality.preview_shadow_enabled(
			GameManager.graphics_quality
		)
	var ocean: MeshInstance3D = _stage_env.get_node_or_null("Ocean") as MeshInstance3D
	if ocean and ocean.mesh is PlaneMesh:
		var subdivisions: int = GraphicsQuality.ocean_subdivisions(GameManager.graphics_quality)
		var plane: PlaneMesh = ocean.mesh as PlaneMesh
		plane.subdivide_width = subdivisions
		plane.subdivide_depth = subdivisions


## カスタマイズUIがキャラ・スキン照明・エモートを載せる共有 SubViewport
func get_shared_viewport() -> SubViewport:
	return _viewport


## カスタマイズ画面に入る: メニューAIを停止・非表示にし、カメラ制御を譲る
func enter_customize_mode() -> void:
	_cancel_menu_helicopter_intro()
	_customize_active = true
	_set_customize_walls_hidden(false)
	_resume_preview_conveyor()
	if _preview_camera:
		_menu_cam_pose = {
			"position": _preview_camera.position,
			"rotation_degrees": _preview_camera.rotation_degrees,
			"fov": _preview_camera.fov,
			"h_offset": _preview_camera.h_offset,
		}
	if _preview_player:
		_preview_player.visible = false


## メニューへ戻る: メニューAIを再開し、カメラをメニュー画角へ滑らかに戻す
func exit_customize_mode() -> void:
	_customize_active = false
	_set_customize_walls_hidden(false)
	_resume_preview_conveyor()
	if _preview_player:
		_preview_player.visible = true
	_reset_applied_preview_cosmetics()
	_sync_preview_player_cosmetics(true)
	_start_camera_return_to_menu()


func enter_customize_control() -> void:
	enter_customize_mode()


func exit_customize_control() -> void:
	exit_customize_mode()


func set_customize_section(_section: int) -> void:
	pass


func set_customize_editing_player(_player_id: int) -> void:
	pass


func apply_actor_hat(player_id: int, _hat_id: int) -> void:
	if player_id == 1:
		_applied_preview_p1_hat = -999
	else:
		_applied_preview_p2_hat = -999
	if _preview_player and _preview_gs and _preview_player.has_method("update_from_state"):
		_preview_player.update_from_state(_preview_gs)
	_sync_preview_player_cosmetics(true)


func apply_actor_emote_slots() -> void:
	_reload_preview_emote_rigs()


func play_actor_emote(player_id: int, emote_id: int) -> void:
	if not _preview_gs:
		return
	var norm := EmoteData.normalize_emote_id(emote_id)
	if player_id == 2:
		_preview_gs.p2_emote = norm
	else:
		_preview_gs.p1_emote = norm


## カスタマイズの壁速度スライダーから共有ベルト速度を駆動
func set_belt_speed(speed: float) -> void:
	_preview_speed = maxf(0.0, speed)
	_conveyor_paused = false


func set_customize_walls_hidden(hidden: bool) -> void:
	_set_customize_walls_hidden(hidden)


func _set_customize_walls_hidden(hidden: bool) -> void:
	_customize_walls_hidden = hidden
	for i in range(_preview_walls.size()):
		var wall: Node3D = _preview_walls[i]
		if not is_instance_valid(wall):
			continue
		var show := (not hidden) and _wall_merge.is_wall_ready(i)
		wall.visible = show


func _start_camera_return_to_menu() -> void:
	if not _preview_camera:
		return
	var d := _menu_cam_pose if not _menu_cam_pose.is_empty() else MenuPreviewCameraSettingsScript.code_default_settings()
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_preview_camera, "position", d["position"], 0.45)
	tw.parallel().tween_property(_preview_camera, "rotation_degrees", d["rotation_degrees"], 0.45)
	tw.parallel().tween_property(_preview_camera, "fov", float(d["fov"]), 0.45)
	tw.parallel().tween_property(_preview_camera, "h_offset", float(d["h_offset"]), 0.45)


func _resolve_preview_speed() -> void:
	var tuning := QuizManager.game_state.tuning
	if tuning.wall_speed_override > 0.0:
		_preview_speed = tuning.wall_speed_override
	else:
		_preview_speed = AUTO_WALL_SPEED


func _get_effective_preview_speed() -> float:
	return 0.0 if _conveyor_paused else _preview_speed


func _pause_preview_conveyor() -> void:
	_conveyor_paused = true


func _resume_preview_conveyor() -> void:
	_conveyor_paused = false
	_resolve_preview_speed()


static func wall_front_touches_player(door_leading_z: float, player_local_z: float) -> bool:
	return door_leading_z >= player_local_z - PREVIEW_WALL_CONTACT_Z


func _process(dt: float) -> void:
	if not _viewport:
		return

	_linger_time += dt
	if _menu_intro_active or _menu_start_departure_active or _menu_departure_hold:
		if _stage_env:
			_stage_env.set_scroll_z(_preview_scroll_z)
		return

	var effective_speed := _get_effective_preview_speed()
	var move_dist := effective_speed * dt
	if not _conveyor_paused:
		_preview_scroll_z += move_dist

	if _stage_env:
		_stage_env.set_scroll_z(_preview_scroll_z)

	for i in range(_preview_walls.size() - 1, -1, -1):
		var wall := _preview_walls[i]
		if not is_instance_valid(wall):
			_on_learning_wall_removed(wall)
			_wall_merge.remove_slot_at(i)
			_preview_walls.remove_at(i)
			continue

		wall.position.z += move_dist

		var door_leading_z: float = wall.position.z + PREVIEW_DOOR_HALF_DEPTH_Z
		if _customize_active:
			# カスタマイズ中はAIを止めているため、固定レーンのキャラ位置(z≒0)で
			# 両ドアを自動的に開けてキャラが開口部に立つようにする（壁の貫通を防ぐ）
			if (
				not _customize_walls_hidden
				and wall.is_inside_tree()
				and wall.visible
				and not wall.get_meta("preview_door_broken", false)
				and wall_front_touches_player(door_leading_z, 0.0)
			):
				if wall.has_method("break_door"):
					wall.break_door(0)
					wall.break_door(PREVIEW_RED_DOOR_INDEX)
				wall.set_meta("preview_door_broken", true)
		elif wall.is_inside_tree() and wall.visible and not wall.get_meta("preview_door_broken", false):
			if (
				_preview_gs
				and _preview_gs.p1_alive
				and wall_front_touches_player(door_leading_z, _preview_gs.player_local_z)
			):
				_resolve_preview_actor_wall_contact(wall, _p1_ai, true)
			if (
				_is_local_2p_active()
				and _preview_gs.p2_alive
				and wall_front_touches_player(door_leading_z, _preview_gs.player2_local_z)
			):
				_resolve_preview_actor_wall_contact(wall, _p2_ai, false)
			_update_preview_wall_pass_completion(wall)

		if wall.position.z >= 8.0:
			if wall == _p1_ai.pending_accident_wall:
				_clear_pending_accident(_p1_ai)
			if wall == _p2_ai.pending_accident_wall:
				_clear_pending_accident(_p2_ai)
			_release_wall_accident_claim(wall)
			_on_learning_wall_removed(wall)
			_drop_wall_into_ocean(wall)
			wall.queue_free()
			_wall_merge.remove_slot_at(i)
			_preview_walls.remove_at(i)

	if not _customize_walls_hidden:
		_wall_merge.process(dt, _preview_walls, self)

	var furthest_z := 8.0
	for wall in _preview_walls:
		if is_instance_valid(wall) and wall.position.z < furthest_z:
			furthest_z = wall.position.z
	if furthest_z > 8.0 - WALL_SPACING * 2.5 and not (_customize_active and _customize_walls_hidden):
		_spawn_preview_wall(furthest_z - WALL_SPACING)

	if _preview_gs and not _customize_active:
		_update_p2_remove_timer(dt)
		var p1_body_start := Vector2(_preview_gs.player_x, _preview_gs.player_z)
		var p2_body_start := Vector2(_preview_gs.player2_x, _preview_gs.player2_z)
		_update_preview_actor_ai(dt)
		if _is_local_2p_active():
			_update_preview_actor2_ai(dt)
			# 本編と同じ2Pカプセル判定で、メニュー背景のAI同士も重なり・すり抜けを防ぐ。
			_preview_gs._resolve_two_player_body_collision(p1_body_start, p2_body_start)
	if _preview_player and _preview_gs and not _customize_active:
		_preview_gs._active_wall_speed = effective_speed
		_update_preview_run_anim_speed_multipliers()
		_preview_player.update_from_state(_preview_gs)
		_sync_preview_player_cosmetics()
		_preview_player.visible = true
		_force_preview_player_facing_away()
	elif _preview_player and _customize_active:
		_preview_player.visible = false

	_update_preview_debris_near_camera()
	_update_death_shard_cleanup()


func _build_3d_scene() -> void:
	if not _viewport:
		return

	_p1_ai.door_learner = MenuPreviewDoorLearnerScript.new()
	_p1_ai.door_learner.reset_session(MenuPreviewDoorLearner.ACTION_LEFT)
	_p2_ai.door_learner = MenuPreviewDoorLearnerScript.new()
	_p2_ai.door_learner.reset_session(MenuPreviewDoorLearner.ACTION_RIGHT)
	_clear_learning_commit(_p1_ai)
	_clear_learning_commit(_p2_ai)

	_preview_camera = Camera3D.new()
	MenuPreviewCameraSettingsScript.apply_code_defaults_to_camera(_preview_camera)
	_preview_camera.current = true
	_viewport.add_child(_preview_camera)

	_stage_env = StageEnvironment.new()
	_viewport.add_child(_stage_env)
	_stage_env.build({
		"floor_center_z": -64.0,
		"floor_length": 144.0,
		"scroll_sign": -1.0,
		"return_scroll_sign": 1.0,
		"include_back_roller": true,
		"include_floor_collision": true,
		"is_preview": true,
		"include_sharks": true,
		"include_grandstands": false,
	})

	_preview_gs = QuizGameState.new()
	_preview_gs.game_state = Constants.STATE_PLAYING
	_preview_gs.num_players = 2
	_preview_gs.p1_alive = true
	_preview_gs.p1_wall_impact = false
	_preview_gs.player_x = PREVIEW_PLAYER_X
	_preview_gs.player_y = 0.0
	_preview_gs.player_z = 0.0
	_preview_gs.world_scroll_z = 0.0
	_preview_gs.p1_emote = 0
	_preview_gs.p1_jump_trigger = false
	_preview_gs.p1_moving_back = false
	_preview_gs.player_vel_y = 0.0
	_preview_gs._active_wall_speed = _preview_speed
	_menu_synced_player_count = 2
	_apply_menu_player_count_to_gs()
	_rebuild_preview_player()
	if _menu_synced_player_count == 2:
		_enable_preview_p2_drop_in()
		_preview_gs.player2_x = PREVIEW_PLAYER2_X
		_preview_gs.player2_y = 0.0
		_preview_gs.player2_vel_y = 0.0
		_set_actor_local_z(false, 0.0)
	_reset_preview_ai_state()
	if _preview_player and _preview_player.has_method("update_from_state"):
		_preview_player.update_from_state(_preview_gs)
	_sync_preview_player_cosmetics(true)
	_begin_menu_helicopter_intro()


func _begin_menu_helicopter_intro() -> void:
	_menu_intro_active = true
	if not _viewport or not _preview_gs or not _preview_player or not _preview_camera:
		_finish_menu_helicopter_intro(false)
		return
	_menu_intro_requested_player_count = 2
	_preview_scroll_z = 0.0
	_preview_gs.world_scroll_z = 0.0
	_pause_preview_conveyor()
	if _stage_env:
		_stage_env.reset_scroll()

	_menu_helicopter_intro = HelicopterArrivalDirectorScript.new() as HelicopterArrivalDirector
	_menu_helicopter_intro.name = "MenuHelicopterArrivalDirector"
	_menu_helicopter_intro.presentation_finished.connect(_on_menu_helicopter_intro_finished)
	_viewport.add_child(_menu_helicopter_intro)
	_menu_helicopter_intro.setup_menu_preview(
		_preview_gs,
		_preview_player as PlayerController,
		_preview_camera
	)


func _on_menu_helicopter_intro_finished(success: bool) -> void:
	_finish_menu_helicopter_intro(success)


func _finish_menu_helicopter_intro(_success: bool) -> void:
	if not _menu_intro_active:
		return
	_menu_intro_active = false
	_preview_scroll_z = 0.0
	if _preview_gs:
		_preview_gs.world_scroll_z = 0.0
		_preview_gs.player_x = PREVIEW_PLAYER_X
		_preview_gs.player_y = 0.0
		_preview_gs.player_vel_y = 0.0
		_set_actor_local_z(true, 0.0)
		if _preview_gs.num_players >= 2:
			_preview_gs.player2_x = PREVIEW_PLAYER2_X
			_preview_gs.player2_y = 0.0
			_preview_gs.player2_vel_y = 0.0
			_set_actor_local_z(false, 0.0)
	if _stage_env:
		_stage_env.reset_scroll()
	if _preview_walls.is_empty():
		for wall_index: int in range(3):
			_spawn_preview_wall(MENU_INTRO_WALL_START_Z + wall_index * WALL_SPACING)
	_reset_preview_ai_state()
	if _is_local_2p_active():
		_reset_preview_actor2_ai_state()
	_resume_preview_conveyor()
	if _preview_player and _preview_gs:
		_preview_player.visible = true
		_preview_gs._active_wall_speed = _preview_speed
		_preview_player.update_from_state(_preview_gs)
		_sync_preview_player_cosmetics(true)
	var requested_count := _menu_intro_requested_player_count
	if requested_count != _menu_synced_player_count:
		sync_menu_player_count(requested_count)


func _cancel_menu_helicopter_intro() -> void:
	if not _menu_intro_active:
		return
	if _menu_helicopter_intro != null and is_instance_valid(_menu_helicopter_intro):
		_menu_helicopter_intro.cancel()
	if _menu_intro_active:
		_finish_menu_helicopter_intro(false)


func begin_game_start_departure(player_count: int) -> bool:
	if _menu_start_departure_active:
		return false
	_menu_departure_hold = false
	_cancel_menu_helicopter_intro()
	if not _viewport or not _preview_gs or not _preview_player or not _preview_camera:
		return false
	var count := clampi(player_count, 1, 2)
	_menu_start_departure_active = true
	_menu_synced_player_count = count
	_preview_gs.num_players = count
	_preview_gs.p1_emote = 0
	_preview_gs.p1_jump_trigger = false
	if count >= 2:
		_preview_gs.p2_alive = true
		_preview_gs.p2_emote = 0
		_preview_gs.p2_jump_trigger = false
	_pause_preview_conveyor()
	_menu_start_departure = HelicopterArrivalDirectorScript.new() as HelicopterArrivalDirector
	_menu_start_departure.name = "MenuHelicopterStartDepartureDirector"
	_menu_start_departure.presentation_finished.connect(_on_game_start_departure_finished)
	_viewport.add_child(_menu_start_departure)
	_menu_start_departure.setup_menu_departure(
		_preview_gs,
		_preview_player as PlayerController,
		_preview_camera,
		count
	)
	return _menu_start_departure_active


func is_game_start_departure_active() -> bool:
	return _menu_start_departure_active


func cancel_game_start_departure() -> void:
	if not _menu_start_departure_active:
		return
	if _menu_start_departure != null and is_instance_valid(_menu_start_departure):
		_menu_start_departure.cancel()
	if _menu_start_departure_active:
		_on_game_start_departure_finished(false)


func _on_game_start_departure_finished(success: bool) -> void:
	if not _menu_start_departure_active:
		return
	_menu_start_departure_active = false
	if success:
		_menu_departure_hold = true
		if _preview_player:
			_preview_player.visible = false
	else:
		_menu_departure_hold = false
		_reset_preview_ai_state()
		if _is_local_2p_active():
			_reset_preview_actor2_ai_state()
		_resume_preview_conveyor()
		if _preview_player and _preview_gs:
			_preview_player.update_from_state(_preview_gs)
			_sync_preview_player_cosmetics(true)
	game_start_departure_finished.emit(success)


func _exit_tree() -> void:
	if _menu_start_departure != null and is_instance_valid(_menu_start_departure):
		_menu_start_departure_active = false
		if _menu_start_departure.presentation_finished.is_connected(_on_game_start_departure_finished):
			_menu_start_departure.presentation_finished.disconnect(_on_game_start_departure_finished)
		_menu_start_departure.cancel()
	if _menu_helicopter_intro == null or not is_instance_valid(_menu_helicopter_intro):
		return
	_menu_intro_active = false
	if _menu_helicopter_intro.presentation_finished.is_connected(_on_menu_helicopter_intro_finished):
		_menu_helicopter_intro.presentation_finished.disconnect(_on_menu_helicopter_intro_finished)
	_menu_helicopter_intro.cancel()


func _pick_preview_quiz() -> QuizItem:
	## オフラインバンクから本物の問題を1問取得し、2択に変換する
	if not _quiz_provider:
		return null
	_preview_subject_idx = (_preview_subject_idx + 1) % Constants.SUBJECTS.size()
	var subject: String = Constants.SUBJECTS[_preview_subject_idx]
	var grade: int = randi_range(1, 6)
	var got: Array[QuizItem] = _quiz_provider.get_quizzes(
		subject, grade, "普通", Constants.MODE_ENDLESS, 1)
	if got.is_empty() or got[0] == null:
		return null
	var quiz := got[0]
	# 2択に変換 (本編 game_state.load_current_quiz の 4→2 変換と同じ要領)
	if quiz.c.size() > 2:
		var correct_text: String = quiz.c[quiz.a]
		var wrong_texts: PackedStringArray = []
		for i: int in range(quiz.c.size()):
			if i != quiz.a:
				wrong_texts.append(quiz.c[i])
		var chosen_wrong: String = wrong_texts[randi() % wrong_texts.size()]
		var pair := [correct_text, chosen_wrong]
		pair.shuffle()
		quiz.c = PackedStringArray(pair)
		quiz.a = pair.find(correct_text)
	return quiz


func _spawn_preview_wall(z_pos: float) -> void:
	var quiz := _pick_preview_quiz()
	if quiz == null:
		quiz = QuizItem.new()
		quiz.q = "プレビュー"
		quiz.c = ["A", "B"]

	var wall := WALL_SCENE.instantiate()
	wall.position.z = z_pos
	_viewport.add_child(wall)
	if wall.has_method("set_quiz"):
		wall.set_quiz(quiz, 2)
	if not quiz.q.is_empty() and quiz.q != "プレビュー":
		# 本物の問題: カメラ側に問題文・選択肢を表示し、AIが解く正解扉を記録
		if wall.has_method("set_preview_labels"):
			wall.set_preview_labels(quiz)
		wall.set_meta("preview_correct_door", quiz.a)
	wall.set_meta("preview_should_break_door", true)
	wall.set_meta("preview_collision_processed", false)
	wall.set_meta("preview_hit_p1", false)
	wall.set_meta("preview_hit_p2", false)
	wall.set_meta("preview_pass_shattered", false)
	_preview_walls.append(wall)
	_wall_merge.attach_new_wall(wall)


func _drop_wall_into_ocean(wall: Node3D) -> void:
	if not wall or not is_instance_valid(wall) or not _viewport:
		return
	if wall.has_method("shatter_wall"):
		wall.shatter_wall(PREVIEW_WALL_SHATTER_DIR_Z)


func _pick_ai_dash_target_x(bundle: MenuPreviewActorAIState) -> float:
	if _is_learning_commit_active(bundle):
		return bundle.learn_target_x
	if _is_local_2p_active() and randf() < AI_2P_EDGE_WANDER_CHANCE:
		var door_x := PREVIEW_DOOR_X_LEFT if randf() < 0.5 else PREVIEW_DOOR_X_RIGHT
		return clampf(door_x + randf_range(-0.35, 0.35), AI_PLAYER_X_MIN, AI_PLAYER_X_MAX)
	var skill := _get_door_learning_skill(bundle)
	var learned_pick_chance := lerpf(0.25, 0.75, skill)
	if bundle.door_learner and randf() < learned_pick_chance:
		var action: int = int(bundle.door_learner.pick_door_action())
		return clampf(bundle.door_learner.target_x_for_action(action), AI_PLAYER_X_MIN, AI_PLAYER_X_MAX)
	if randf() < AI_DOOR_VISIT_CHANCE:
		var door_x := PREVIEW_DOOR_X_LEFT if randf() < 0.5 else PREVIEW_DOOR_X_RIGHT
		return clampf(
			door_x + randf_range(-0.45, 0.45),
			AI_PLAYER_X_MIN,
			AI_PLAYER_X_MAX
		)
	return randf_range(AI_PLAYER_X_MIN, AI_PLAYER_X_MAX)


func _clear_pending_accident(bundle: MenuPreviewActorAIState) -> void:
	if bundle.pending_accident_wall != null and is_instance_valid(bundle.pending_accident_wall):
		if (
			bundle.pending_accident_wall.has_meta("preview_accident_owner")
			and bundle.pending_accident_wall.get_meta("preview_accident_owner") == bundle
		):
			bundle.pending_accident_wall.remove_meta("preview_accident_owner")
	bundle.pending_accident = PENDING_ACCIDENT_NONE
	bundle.pending_accident_wall = null
	bundle.crash_wall = null


func _pick_accident_crash_x(_bundle: MenuPreviewActorAIState) -> float:
	var roll := randf()
	var target_x := 0.0
	if roll < 0.35:
		target_x = PREVIEW_DOOR_X_LEFT + randf_range(-0.35, 0.35)
	elif roll < 0.70:
		target_x = PREVIEW_DOOR_X_RIGHT + randf_range(-0.35, 0.35)
	elif roll < 0.85:
		target_x = randf_range(-1.1, 1.1)
	else:
		target_x = PREVIEW_DOOR_X_LEFT if randf() < 0.5 else PREVIEW_DOOR_X_RIGHT
		target_x += randf_range(-0.35, 0.35)
	return clampf(target_x, AI_PLAYER_X_MIN, AI_PLAYER_X_MAX)


func _should_force_wall_accident_crash(bundle: MenuPreviewActorAIState, wall: Node3D) -> bool:
	return (
		bundle.pending_accident == PENDING_ACCIDENT_WALL
		and bundle.pending_accident_wall == wall
		and is_instance_valid(wall)
	)


func _resolve_preview_actor_wall_contact(
	wall: Node3D,
	bundle: MenuPreviewActorAIState,
	is_p1: bool
) -> void:
	if not wall or not _preview_gs:
		return
	var hit_key := "preview_hit_p1" if is_p1 else "preview_hit_p2"
	if wall.get_meta(hit_key, false):
		return
	if _should_force_wall_accident_crash(bundle, wall):
		wall.set_meta("preview_should_break_door", false)
		_clear_pending_accident(bundle)
		_handle_preview_wall_crash(wall, bundle, is_p1)
		return
	var should_break_door: bool = bool(wall.get_meta("preview_should_break_door", true))
	if should_break_door:
		var door_idx := _pick_preview_door_index(_actor_x(is_p1))
		var correct_door := int(wall.get_meta("preview_correct_door", -1))
		if door_idx >= 0 and (correct_door < 0 or door_idx == correct_door):
			_trigger_preview_door_pass(wall, door_idx, bundle, is_p1)
		else:
			# 不正解の扉は本編同様に通れない (激突扱い)
			_handle_preview_wall_crash(wall, bundle, is_p1)
	else:
		_handle_preview_wall_crash(wall, bundle, is_p1)


func _get_door_learning_skill(bundle: MenuPreviewActorAIState) -> float:
	return bundle.door_learner.get_skill() if bundle.door_learner else 0.0


func _is_learning_commit_active(bundle: MenuPreviewActorAIState) -> bool:
	return (
		bundle.learn_intended_action >= 0
		and bundle.learn_approach_wall != null
		and is_instance_valid(bundle.learn_approach_wall)
		and not bundle.learn_episode_reported
	)


func _clear_learning_commit(bundle: MenuPreviewActorAIState, home_x: float = PREVIEW_PLAYER_X) -> void:
	bundle.learn_approach_wall = null
	bundle.learn_intended_action = -1
	bundle.learn_target_x = home_x
	bundle.learn_episode_reported = false


func _update_door_learning_approach(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs or not bundle.door_learner:
		return
	var alive := _preview_gs.p1_alive if is_p1 else _preview_gs.p2_alive
	if not alive:
		return
	if bundle.ai_state != AI_STATE_NORMAL:
		return
	if _is_learning_commit_active(bundle):
		return
	var player_z := _preview_gs.player_local_z if is_p1 else _preview_gs.player2_local_z
	var candidate := _pick_learning_target_wall(player_z)
	if not candidate:
		return
	bundle.learn_approach_wall = candidate
	var learner_action := int(bundle.door_learner.pick_door_action())
	var correct_door := int(candidate.get_meta("preview_correct_door", -1))
	# 本物の問題が載った壁では正解の扉を狙う (迷い・ミスの揺らぎは door_learner が担う)
	bundle.learn_intended_action = correct_door if correct_door >= 0 else learner_action
	bundle.learn_target_x = clampf(
		bundle.door_learner.target_x_for_action(bundle.learn_intended_action),
		AI_PLAYER_X_MIN,
		AI_PLAYER_X_MAX
	)
	bundle.learn_episode_reported = false
	bundle.target_x = bundle.learn_target_x
	bundle.lane_shift_active = true


func _pick_learning_target_wall(player_z: float) -> Node3D:
	if not _preview_gs:
		return null
	var best_wall: Node3D = null
	var best_dist := INF
	for wall in _preview_walls:
		if not is_instance_valid(wall):
			continue
		if not wall.visible:
			continue
		if not bool(wall.get_meta("preview_should_break_door", true)):
			continue
		if bool(wall.get_meta("preview_door_broken", false)):
			continue
		var door_leading_z := wall.position.z + PREVIEW_DOOR_HALF_DEPTH_Z
		if wall_front_touches_player(door_leading_z, player_z):
			continue
		var dist := player_z - door_leading_z
		if dist < AI_LEARN_APPROACH_MIN_DIST or dist > AI_LEARN_APPROACH_MAX_DIST:
			continue
		if dist < best_dist:
			best_dist = dist
			best_wall = wall
	return best_wall


func _record_learning_outcome_for_wall(
	wall: Node3D,
	reward: float,
	bundle: MenuPreviewActorAIState,
	home_x: float
) -> void:
	if not wall:
		return
	if wall != bundle.learn_approach_wall:
		return
	if bundle.learn_episode_reported:
		return
	if bundle.learn_intended_action < 0:
		_clear_learning_commit(bundle, home_x)
		return
	if bundle.door_learner:
		bundle.door_learner.record_outcome(bundle.learn_intended_action, reward)
	bundle.learn_episode_reported = true
	_clear_learning_commit(bundle, home_x)


func _on_learning_wall_removed(wall: Node3D) -> void:
	for bundle in [_p1_ai, _p2_ai]:
		if wall != bundle.learn_approach_wall:
			continue
		if bundle.learn_episode_reported:
			_clear_learning_commit(bundle, _home_x_for_bundle(bundle))
			continue
		_record_learning_outcome_for_wall(wall, 0.0, bundle, _home_x_for_bundle(bundle))


func _pick_preview_door_index(player_x: float) -> int:
	var half_w := PREVIEW_DOOR_HALF_WIDTH + PREVIEW_DOOR_PASS_MARGIN
	if player_x >= PREVIEW_DOOR_X_RIGHT - half_w and player_x <= PREVIEW_DOOR_X_RIGHT + half_w:
		return PREVIEW_RED_DOOR_INDEX
	if player_x >= PREVIEW_DOOR_X_LEFT - half_w and player_x <= PREVIEW_DOOR_X_LEFT + half_w:
		return 0
	return -1


func _home_x_for_bundle(bundle: MenuPreviewActorAIState) -> float:
	return PREVIEW_PLAYER_X if bundle == _p1_ai else PREVIEW_PLAYER2_X


func _is_local_2p_active() -> bool:
	return _preview_gs != null and _preview_gs.num_players >= 2 and _menu_synced_player_count == 2


func sync_menu_player_count(count: int) -> void:
	count = 2 if count == 2 else 1
	if _menu_start_departure_active or _menu_departure_hold:
		return
	if _menu_intro_active:
		_menu_intro_requested_player_count = count
		return
	if not _preview_gs:
		return
	var prev := _menu_synced_player_count
	if prev == count:
		return
	_menu_synced_player_count = count
	if count == 2 and prev != 2:
		_enable_preview_p2_drop_in()
	elif prev == 2 and count != 2:
		_begin_preview_p2_explode_removal()
	else:
		_apply_menu_player_count_to_gs()


func _apply_menu_player_count_to_gs() -> void:
	if not _preview_gs:
		return
	if _menu_synced_player_count == 2:
		_preview_gs.num_players = 2
	else:
		_preview_gs.num_players = 1


func _enable_preview_p2_drop_in() -> void:
	if not _preview_gs:
		return
	_preview_gs.num_players = 2
	_preview_gs.p2_alive = true
	_preview_gs.p2_wall_impact = false
	_preview_gs.player2_game_over_timer = 0.0
	_preview_gs.p2_emote = 0
	_preview_gs.p2_jump_trigger = false
	_preview_gs.p2_moving_back = false
	_preview_gs.player2_x = clampf(
		_pick_ai_dash_target_x(_p2_ai),
		AI_PLAYER_X_MIN,
		AI_PLAYER_X_MAX
	)
	_set_actor_local_z(false, 0.0)
	_preview_gs.player2_y = randf_range(AI_RESPAWN_START_Y_MIN, AI_RESPAWN_START_Y_MAX)
	_preview_gs.player2_vel_y = -randf_range(AI_RESPAWN_DOWN_SPEED_MIN, AI_RESPAWN_DOWN_SPEED_MAX)
	_p2_remove_deadline = -1.0
	_reset_preview_actor2_ai_state()
	_applied_preview_p2_hat = -999
	_sync_preview_player_cosmetics(true)


func _reset_applied_preview_cosmetics() -> void:
	_applied_preview_p1_hat = -999
	_applied_preview_p2_hat = -999


func _sync_preview_player_cosmetics(force: bool = false) -> void:
	if not _preview_player or not _preview_gs:
		return
	var pc := _preview_player as PlayerController
	if pc == null or not pc.has_method("set_hat"):
		return
	var gm := QuizManager.game_state
	if pc.p1_parts.has("hat_mount") and (force or _applied_preview_p1_hat != gm.p1_hat):
		pc.set_hat(1, gm.p1_hat)
		_applied_preview_p1_hat = gm.p1_hat
	if not _preview_gs.num_players >= 2:
		_applied_preview_p2_hat = -999
		return
	if pc.p2_parts.has("hat_mount") and (force or _applied_preview_p2_hat != gm.p2_hat):
		pc.set_hat(2, gm.p2_hat)
		_applied_preview_p2_hat = gm.p2_hat


func _reload_preview_emote_rigs() -> void:
	if not _preview_player:
		return
	_preview_p1_rig_emote_ids = _pick_preview_rig_emote_ids(false)
	_preview_p2_rig_emote_ids = _pick_preview_rig_emote_ids(true)
	if _preview_player.has_method("reload_emote_rigs"):
		_preview_player.reload_emote_rigs(_preview_p1_rig_emote_ids, _preview_p2_rig_emote_ids)
	_fill_preview_actor_emote_pool(_p1_ai, _preview_p1_rig_emote_ids)
	_fill_preview_actor_emote_pool(_p2_ai, _preview_p2_rig_emote_ids)


func _begin_preview_p2_explode_removal() -> void:
	if not _preview_gs:
		return
	if _preview_gs.num_players < 2 or not _preview_gs.p2_alive:
		_apply_menu_player_count_to_gs()
		return
	_preview_gs.p2_wall_impact = false
	_preview_gs.p2_alive = false
	_preview_gs.player2_game_over_timer = 0.001
	_p2_ai.ai_state = AI_STATE_DEAD
	_p2_remove_deadline = _ai_time + 2.6


func _update_p2_remove_timer(_dt: float) -> void:
	if _p2_remove_deadline < 0.0:
		return
	if _ai_time < _p2_remove_deadline:
		return
	_p2_remove_deadline = -1.0
	_stop_survivor_taunt(false)
	_preview_gs.player2_game_over_timer = 0.0
	_preview_gs.p2_alive = true
	_preview_gs.p2_wall_impact = false
	_apply_menu_player_count_to_gs()
	_clear_learning_commit(_p2_ai, PREVIEW_PLAYER2_X)


func _actor_alive(is_p1: bool) -> bool:
	return _preview_gs.p1_alive if is_p1 else _preview_gs.p2_alive


func _actor_x(is_p1: bool) -> float:
	return _preview_gs.player_x if is_p1 else _preview_gs.player2_x


func _set_actor_x(is_p1: bool, value: float) -> void:
	if is_p1:
		_preview_gs.player_x = value
	else:
		_preview_gs.player2_x = value


func _actor_y(is_p1: bool) -> float:
	return _preview_gs.player_y if is_p1 else _preview_gs.player2_y


func _set_actor_y(is_p1: bool, value: float) -> void:
	if is_p1:
		_preview_gs.player_y = value
	else:
		_preview_gs.player2_y = value


func _actor_vel_y(is_p1: bool) -> float:
	return _preview_gs.player_vel_y if is_p1 else _preview_gs.player2_vel_y


func _set_actor_vel_y(is_p1: bool, value: float) -> void:
	if is_p1:
		_preview_gs.player_vel_y = value
	else:
		_preview_gs.player2_vel_y = value


func _actor_local_z(is_p1: bool) -> float:
	if not _preview_gs:
		return 0.0
	if is_p1:
		return _preview_gs.player_z - _preview_gs.world_scroll_z
	return _preview_gs.player2_z - _preview_gs.world_scroll_z


func _set_actor_local_z(is_p1: bool, value: float) -> void:
	if not _preview_gs:
		return
	var world_z := _preview_gs.world_scroll_z
	if is_p1:
		_preview_gs.player_z = value + world_z
	else:
		_preview_gs.player2_z = value + world_z


func _actor_emote(is_p1: bool) -> int:
	return _preview_gs.p1_emote if is_p1 else _preview_gs.p2_emote


func _set_actor_emote(is_p1: bool, value: int) -> void:
	if is_p1:
		_preview_gs.p1_emote = value
	else:
		_preview_gs.p2_emote = value


func _actor_jump_trigger(is_p1: bool) -> bool:
	return _preview_gs.p1_jump_trigger if is_p1 else _preview_gs.p2_jump_trigger


func _set_actor_jump_trigger(is_p1: bool, value: bool) -> void:
	if is_p1:
		_preview_gs.p1_jump_trigger = value
	else:
		_preview_gs.p2_jump_trigger = value


func _actor_moving_back(is_p1: bool) -> bool:
	return _preview_gs.p1_moving_back if is_p1 else _preview_gs.p2_moving_back


func _set_actor_moving_back(is_p1: bool, value: bool) -> void:
	if is_p1:
		_preview_gs.p1_moving_back = value
	else:
		_preview_gs.p2_moving_back = value


func _actor_game_over_timer(is_p1: bool) -> float:
	return _preview_gs.game_over_timer if is_p1 else _preview_gs.player2_game_over_timer


func _add_actor_game_over_timer(is_p1: bool, dt: float) -> void:
	if is_p1:
		_preview_gs.game_over_timer += dt
	else:
		_preview_gs.player2_game_over_timer += dt


func _set_actor_alive(is_p1: bool, value: bool) -> void:
	if is_p1:
		_preview_gs.p1_alive = value
	else:
		_preview_gs.p2_alive = value


func _set_actor_wall_impact(is_p1: bool, value: bool) -> void:
	if is_p1:
		_preview_gs.p1_wall_impact = value
	else:
		_preview_gs.p2_wall_impact = value


func _set_actor_game_over_timer(is_p1: bool, value: float) -> void:
	if is_p1:
		_preview_gs.game_over_timer = value
	else:
		_preview_gs.player2_game_over_timer = value


func _clamp_actor_before_wall_front(is_p1: bool, door_leading_z: float) -> void:
	var max_local_z := door_leading_z - PREVIEW_WALL_CONTACT_Z
	if _actor_local_z(is_p1) > max_local_z:
		_set_actor_local_z(is_p1, max_local_z)


func _handle_preview_wall_crash(wall: Node3D, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not wall or not _preview_gs:
		return
	var alive := _preview_gs.p1_alive if is_p1 else _preview_gs.p2_alive
	if not alive:
		return
	_clamp_actor_before_wall_front(is_p1, wall.position.z + PREVIEW_DOOR_HALF_DEPTH_Z)
	var hit_key := "preview_hit_p1" if is_p1 else "preview_hit_p2"
	if wall.get_meta(hit_key, false):
		return
	wall.set_meta(hit_key, true)
	_record_learning_outcome_for_wall(wall, -1.0, bundle, _home_x_for_bundle(bundle))
	_pause_preview_conveyor()
	bundle.blocking_wall = wall
	if is_p1:
		_separate_blocking_wall_from_player()
		_push_walls_away_from_player(_preview_gs.player_local_z)
		_trigger_preview_death("crash", bundle, true)
	else:
		_separate_blocking_wall_from_player_p2()
		_push_walls_away_from_player(_preview_gs.player2_local_z)
		_trigger_preview_death("crash", bundle, false)


func _trigger_preview_door_pass(
	wall: Node3D,
	door_index: int,
	bundle: MenuPreviewActorAIState,
	is_p1: bool
) -> void:
	if not wall:
		return
	_clamp_actor_before_wall_front(is_p1, wall.position.z + PREVIEW_DOOR_HALF_DEPTH_Z)
	var hit_key := "preview_hit_p1" if is_p1 else "preview_hit_p2"
	if wall.get_meta(hit_key, false):
		return
	wall.set_meta(hit_key, true)
	# 正解の扉を3回くぐるごとに、設定中のエモートからランダムに1つ選んで踊る
	bundle.door_passes_since_emote += 1
	if bundle.door_passes_since_emote >= 3:
		bundle.door_passes_since_emote = 0
		_start_ai_emote(bundle, is_p1)
	_record_learning_outcome_for_wall(wall, 1.0, bundle, _home_x_for_bundle(bundle))
	var door_key := "preview_broken_door_%d" % door_index
	if not wall.get_meta(door_key, false):
		wall.set_meta(door_key, true)
		if wall.has_method("break_door"):
			wall.break_door(door_index)


func _update_preview_wall_pass_completion(wall: Node3D) -> void:
	if wall.get_meta("preview_door_broken", false):
		return
	var wall_ready := false
	if _is_local_2p_active():
		wall_ready = wall.get_meta("preview_hit_p1", false) and wall.get_meta("preview_hit_p2", false)
	else:
		wall_ready = wall.get_meta("preview_hit_p1", false)
	if not wall_ready:
		return
	wall.set_meta("preview_door_broken", true)
	_shatter_preview_wall_after_pass(wall)


func _shatter_preview_wall_after_pass(wall: Node3D) -> void:
	if not wall or not is_instance_valid(wall):
		return
	if wall.get_meta("preview_pass_shattered", false):
		return
	wall.set_meta("preview_pass_shattered", true)
	if wall.has_method("shatter_wall"):
		wall.shatter_wall(PREVIEW_WALL_SHATTER_DIR_Z)


func _force_preview_player_facing_away() -> void:
	var pc := _preview_player as PlayerController
	if not pc:
		return
	_apply_preview_actor_facing(pc.p1_parts, _p1_ai, true)
	if _is_local_2p_active():
		_apply_preview_actor_facing(pc.p2_parts, _p2_ai, false)


func _apply_preview_actor_facing(parts: Dictionary, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not parts.has("pelvis"):
		return
	var pelvis := parts["pelvis"] as Node3D
	if not pelvis:
		return
	if bundle.ai_state == AI_STATE_TAUNT:
		# 死亡時の論理座標ではなく、実際に飛んでいるラグドール／破片を追い続ける。
		var pc := _preview_player as PlayerController
		if pc:
			var target_position := pc.get_death_presentation_position(not is_p1)
			bundle.taunt_target_x = target_position.x
			bundle.taunt_target_z = target_position.z
		pelvis.rotation.y = _facing_y_toward(
			_actor_x(is_p1),
			_actor_local_z(is_p1),
			bundle.taunt_target_x,
			bundle.taunt_target_z
		)
	elif bundle.is_emoting or _actor_emote(is_p1) != EmoteData.EMOTE_NONE:
		# エモート中はヨーを固定せず、FBXの回転を残して壁向き(+PI)だけ合わせる。
		pelvis.rotate_y(PI)
	else:
		pelvis.rotation.y = PI


func _clear_preview_death_shards(for_p1: bool) -> void:
	if not _viewport:
		return
	for child in _viewport.get_children():
		if not (child is RigidBody3D):
			continue
		var body := child as RigidBody3D
		if not bool(body.get_meta("player_death_shard", false)):
			continue
		if body.has_meta("preview_death_shard_p1"):
			if bool(body.get_meta("preview_death_shard_p1")) != for_p1:
				continue
		body.queue_free()


func _mark_death_shard_hold(for_p1: bool, hold_until: float) -> void:
	if not _viewport:
		return
	for child in _viewport.get_children():
		if not (child is RigidBody3D):
			continue
		var body := child as RigidBody3D
		if not bool(body.get_meta("player_death_shard", false)):
			continue
		if body.has_meta("preview_death_shard_p1"):
			if bool(body.get_meta("preview_death_shard_p1")) != for_p1:
				continue
		body.set_meta("preview_death_shard_hold_until", hold_until)


func _schedule_death_shard_cleanup(for_p1: bool) -> void:
	var clear_at := _linger_time + PREVIEW_DEATH_SHARD_LINGER_SEC
	if for_p1:
		_p1_death_shard_clear_t = clear_at
	else:
		_p2_death_shard_clear_t = clear_at
	_mark_death_shard_hold(for_p1, clear_at)


func _update_death_shard_cleanup() -> void:
	if _p1_death_shard_clear_t >= 0.0 and _linger_time >= _p1_death_shard_clear_t:
		_p1_death_shard_clear_t = -1.0
		_clear_preview_death_shards(true)
	if _p2_death_shard_clear_t >= 0.0 and _linger_time >= _p2_death_shard_clear_t:
		_p2_death_shard_clear_t = -1.0
		_clear_preview_death_shards(false)


func _death_shard_on_hold(body: RigidBody3D) -> bool:
	if not bool(body.get_meta("player_death_shard", false)):
		return false
	if not body.has_meta("preview_death_shard_hold_until"):
		return false
	return _linger_time < float(body.get_meta("preview_death_shard_hold_until"))


func _update_preview_debris_near_camera() -> void:
	if not _viewport or not _preview_camera:
		return

	const FADE_START_DIST: float = 7.5
	const KILL_DIST: float = 2.0
	const SCALE_FLOOR: float = 0.02

	for child in _viewport.get_children():
		if child is RigidBody3D:
			var body := child as RigidBody3D
			if body.get_meta("preview_door_shard", false) or body.get_meta("player_death_shard", false):
				if _death_shard_on_hold(body):
					continue
				var d_far_w := body.global_position.distance_to(_preview_camera.global_position)
				if d_far_w > 48.0 or body.global_position.y < -14.0:
					body.queue_free()
					continue
				var debris_dist := body.global_position.distance_to(_preview_camera.global_position)
				if debris_dist <= FADE_START_DIST:
					var t := clampf((debris_dist - KILL_DIST) / maxf(0.001, FADE_START_DIST - KILL_DIST), 0.0, 1.0)
					var visual_scale := maxf(SCALE_FLOOR, t)
					for mesh_child in body.get_children():
						if mesh_child is MeshInstance3D:
							(mesh_child as MeshInstance3D).scale = Vector3.ONE * visual_scale
				if debris_dist <= KILL_DIST:
					body.queue_free()
				continue
			if body.global_position.y < -14.0:
				body.queue_free()
				continue
			var dist := body.global_position.distance_to(_preview_camera.global_position)
			if dist <= FADE_START_DIST:
				var t := clampf((dist - KILL_DIST) / maxf(0.001, FADE_START_DIST - KILL_DIST), 0.0, 1.0)
				var visual_scale := maxf(SCALE_FLOOR, t)
				for mesh_child in body.get_children():
					if mesh_child is MeshInstance3D:
						(mesh_child as MeshInstance3D).scale = Vector3.ONE * visual_scale
			if dist <= KILL_DIST:
				body.queue_free()


func _pick_preview_rig_emote_ids(for_p2: bool) -> Array[int]:
	var gm := QuizManager.game_state
	var slots: Array[int] = gm.p2_emote_slots if for_p2 else gm.p1_emote_slots
	var merged := EmoteData.merge_emote_slot_ids(
		slots,
		EmoteData.get_playable_emote_ids(),
		EmoteData.MAX_EMOTES_ON_RIG
	)
	if merged.is_empty():
		merged = EmoteData.get_menu_preview_rig_slots(for_p2)
	return merged


func _fill_preview_actor_emote_pool(bundle: MenuPreviewActorAIState, rig_ids: Array[int]) -> void:
	bundle.available_emotes = rig_ids.duplicate()
	if bundle.available_emotes.is_empty():
		bundle.available_emotes = [EmoteData.EMOTE_STEP_HIP_HOP, EmoteData.EMOTE_GANGNAM, EmoteData.EMOTE_MOONWALK]


func _reset_preview_ai_state() -> void:
	_p1_ai.ai_state = AI_STATE_NORMAL
	_ai_time = 0.0
	_p1_ai.next_action_t = randf_range(0.55, 1.05)
	_p1_ai.emote_end_t = 0.0
	_p1_ai.dead_end_t = 0.0
	_p1_ai.state_end_t = 0.0
	_p1_ai.target_x = _preview_gs.player_x if _preview_gs else _pick_ai_dash_target_x(_p1_ai)
	_p1_ai.lane_shift_speed = AI_LANE_SHIFT_SPEED_MIN
	_p1_ai.lane_shift_active = false
	_p1_ai.target_local_z = 0.0
	_p1_ai.depth_shift_speed = AI_DEPTH_SHIFT_SPEED_MIN
	_p1_ai.depth_shift_active = false
	_p1_ai.jump_trigger_ttl = 0.0
	_p1_ai.is_emoting = false
	_clear_pending_accident(_p1_ai)
	_p1_ai.blocking_wall = null
	_p1_ai.accident_cooldown_t = _ai_time + randf_range(AI_ACCIDENT_COOLDOWN_MIN, AI_ACCIDENT_COOLDOWN_MAX)
	_p1_ai.next_acro_jump_t = 0.0
	_p1_ai.acro_seed = randf_range(-10.0, 10.0)
	_p1_ai.knockback_end_t = 0.0
	_p1_ai.knockback_vel_x = 0.0
	_p1_ai.knockback_vel_z = 0.0
	_p1_ai.knockback_is_lethal = true
	_clear_learning_commit(_p1_ai)
	_conveyor_paused = false
	_fill_preview_actor_emote_pool(_p1_ai, _preview_p1_rig_emote_ids)
	_p1_ai.last_emote = 0
	_start_ai_dash_move(false, _p1_ai, true)


func _reset_preview_actor2_ai_state() -> void:
	_p2_ai.ai_state = AI_STATE_NORMAL
	_p2_ai.next_action_t = randf_range(1.35, 2.05)
	_p2_ai.emote_end_t = 0.0
	_p2_ai.dead_end_t = 0.0
	_p2_ai.state_end_t = 0.0
	_p2_ai.target_x = _preview_gs.player2_x if _preview_gs else PREVIEW_PLAYER2_X
	_p2_ai.lane_shift_speed = AI_LANE_SHIFT_SPEED_MIN
	_p2_ai.lane_shift_active = false
	_p2_ai.target_local_z = 0.0
	_p2_ai.depth_shift_speed = AI_DEPTH_SHIFT_SPEED_MIN
	_p2_ai.depth_shift_active = false
	_p2_ai.jump_trigger_ttl = 0.0
	_p2_ai.is_emoting = false
	_clear_pending_accident(_p2_ai)
	_p2_ai.blocking_wall = null
	_p2_ai.accident_cooldown_t = _ai_time + randf_range(AI_ACCIDENT_COOLDOWN_MIN, AI_ACCIDENT_COOLDOWN_MAX)
	_p2_ai.next_acro_jump_t = 0.0
	_p2_ai.acro_seed = randf_range(-10.0, 10.0)
	_p2_ai.knockback_end_t = 0.0
	_p2_ai.knockback_vel_x = 0.0
	_p2_ai.knockback_vel_z = 0.0
	_p2_ai.knockback_is_lethal = true
	_clear_learning_commit(_p2_ai, PREVIEW_PLAYER2_X)
	_fill_preview_actor_emote_pool(_p2_ai, _preview_p2_rig_emote_ids)
	_p2_ai.last_emote = 0
	_start_ai_dash_move(false, _p2_ai, false)


func _update_preview_actor_ai(dt: float) -> void:
	if not _preview_gs:
		return
	_ai_time += dt
	_update_jump_trigger_ttl(dt, _p1_ai, true)
	_update_actor_ai(dt, _p1_ai, true)
	_enforce_floor_support(_p1_ai, true)


func _update_preview_actor2_ai(dt: float) -> void:
	if not _preview_gs or not _is_local_2p_active():
		return
	_update_jump_trigger_ttl(dt, _p2_ai, false)
	_update_actor_ai(dt, _p2_ai, false)
	_enforce_floor_support(_p2_ai, false)


func _update_actor_ai(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs:
		return

	match bundle.ai_state:
		AI_STATE_NORMAL:
			if bundle.pending_accident == PENDING_ACCIDENT_NONE:
				_update_door_learning_approach(bundle, is_p1)
			_update_lane_shift(dt, bundle, is_p1)
			_update_depth_shift(dt, bundle, is_p1)
			_reconcile_actor_moving_back(bundle, is_p1)
			_update_ground_movement(dt, bundle, is_p1)
			_update_pending_accident_wall(dt, bundle, is_p1)
			_update_pending_accident_ocean(dt, bundle, is_p1)
			if (
				bundle.pending_accident == PENDING_ACCIDENT_NONE
				and not bundle.lane_shift_active
				and not bundle.depth_shift_active
			):
				_start_ai_dash_move(false, bundle, is_p1)
			_update_emote_timer(bundle, is_p1)
			if _ai_time >= bundle.next_action_t:
				_roll_next_action(bundle, is_p1)
				bundle.next_action_t = _ai_time + _next_action_delay(is_p1)
		AI_STATE_CRASH_RUNUP:
			bundle.ai_state = AI_STATE_NORMAL
		AI_STATE_KNOCKBACK:
			_stop_ai_emote_if_needed(bundle, is_p1)
			_set_actor_moving_back(is_p1, false)
			_update_knockback_motion(dt, bundle, is_p1)
		AI_STATE_OCEAN_FALL:
			bundle.ai_state = AI_STATE_NORMAL
			bundle.pending_accident = PENDING_ACCIDENT_OCEAN
		AI_STATE_DEAD:
			_set_actor_moving_back(is_p1, false)
			_add_actor_game_over_timer(is_p1, dt)
			if _actor_y(is_p1) <= StageConstants.OCEAN_ENTRY_Y:
				_set_actor_y(is_p1, move_toward(
					_actor_y(is_p1),
					StageConstants.OCEAN_SINK_Y,
					StageConstants.OCEAN_SINK_SPEED * dt
				))
				_set_actor_vel_y(is_p1, 0.0)
			if _ai_time >= bundle.dead_end_t:
				_start_respawn(bundle, is_p1)
		AI_STATE_RESPAWN:
			_stop_ai_emote_if_needed(bundle, is_p1)
			_set_actor_moving_back(is_p1, false)
			_update_respawn_drop(dt, bundle, is_p1)
		AI_STATE_ACROBATICS:
			_update_acrobatic_action(dt, bundle, is_p1)
		AI_STATE_TAUNT:
			_set_actor_jump_trigger(is_p1, false)
			_set_actor_moving_back(is_p1, false)
			bundle.lane_shift_active = false
			bundle.depth_shift_active = false
			# リグ読込直後などに初回開始が失敗しても、死亡演出中は必ず再試行する。
			if _actor_emote(is_p1) == EmoteData.EMOTE_NONE:
				_start_taunt_emote(bundle, is_p1)
			if _actor_y(is_p1) > 0.01 or _actor_vel_y(is_p1) != 0.0:
				_set_actor_y(is_p1, PREVIEW_FLOOR_Y)
				_set_actor_vel_y(is_p1, 0.0)
	if bundle.ai_state != AI_STATE_DEAD:
		_enforce_floor_support(bundle, is_p1)


func _next_action_delay(is_p1: bool) -> float:
	var delay := randf_range(AI_ACTION_INTERVAL_MIN, AI_ACTION_INTERVAL_MAX)
	if not _is_local_2p_active():
		return delay
	return delay * (
		AI_2P_P1_ACTION_INTERVAL_SCALE if is_p1
		else AI_2P_P2_ACTION_INTERVAL_SCALE
	)


func _is_past_belt_edge(is_p1: bool) -> bool:
	if not _preview_gs:
		return false
	return _actor_local_z(is_p1) > PREVIEW_BELT_EDGE_FALL_Z


func _allows_below_floor(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	return bundle.pending_accident == PENDING_ACCIDENT_OCEAN and _is_past_belt_edge(is_p1)


func _enforce_floor_support(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs or _allows_below_floor(bundle, is_p1):
		return
	if _actor_y(is_p1) < PREVIEW_FLOOR_Y:
		_set_actor_y(is_p1, PREVIEW_FLOOR_Y)
	if _actor_y(is_p1) <= PREVIEW_FLOOR_Y + 0.001 and _actor_vel_y(is_p1) < 0.0:
		_set_actor_vel_y(is_p1, 0.0)


func _update_jump_trigger_ttl(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs:
		return
	if bundle.jump_trigger_ttl > 0.0:
		bundle.jump_trigger_ttl = maxf(0.0, bundle.jump_trigger_ttl - dt)
		if bundle.jump_trigger_ttl <= 0.0:
			_set_actor_jump_trigger(is_p1, false)


func _roll_next_action(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs or not _actor_alive(is_p1):
		return
	if bundle.is_emoting:
		return
	if bundle.pending_accident != PENDING_ACCIDENT_NONE:
		# エモートは正解の扉をくぐった時だけ再生するため、ここでは発生させない
		return
	var skill := _get_door_learning_skill(bundle)
	var accident_weight := AI_WEIGHT_ACCIDENT * (1.0 - 0.65 * skill)
	if _is_local_2p_active():
		accident_weight *= AI_2P_ACCIDENT_WEIGHT_MULT
	var roll := randf()
	var accum := AI_WEIGHT_IDLE
	if roll < accum:
		_start_ai_dash_move(false, bundle, is_p1)
		return
	accum += AI_WEIGHT_LANE_SHIFT
	if roll < accum:
		_start_ai_lane_shift(bundle, is_p1)
		return
	accum += AI_WEIGHT_STEP_FORWARD
	if roll < accum:
		if not _start_ai_depth_step(bundle, is_p1, true):
			_start_ai_lane_shift(bundle, is_p1)
		return
	accum += AI_WEIGHT_STEP_BACK
	if roll < accum:
		if not _start_ai_depth_step(bundle, is_p1, false):
			_start_ai_lane_shift(bundle, is_p1)
		return
	accum += AI_WEIGHT_JUMP
	if roll < accum:
		if not _start_ai_jump(bundle, is_p1):
			_start_ai_lane_shift(bundle, is_p1)
		return
	accum += AI_WEIGHT_EMOTE
	if roll < accum:
		# エモートは正解の扉をくぐった時だけ再生するため、ここでは通常移動にフォールバックする
		_start_ai_dash_move(false, bundle, is_p1)
		return
	accum += AI_WEIGHT_ACROBATICS
	if roll < accum:
		if not _start_ai_acrobatics(bundle, is_p1):
			_start_ai_dash_move(true, bundle, is_p1)
		return
	accum += accident_weight
	if roll >= accum:
		_start_ai_dash_move(false, bundle, is_p1)
		return
	if _is_learning_commit_active(bundle):
		_start_ai_dash_move(false, bundle, is_p1)
		return
	if _ai_time < bundle.accident_cooldown_t:
		_start_ai_dash_move(false, bundle, is_p1)
		return
	if randf() < AI_ACCIDENT_CRASH_RATIO:
		if not _start_ai_collision_accident(bundle, is_p1):
			if not _start_ai_ocean_accident(bundle, is_p1):
				_start_ai_dash_move(true, bundle, is_p1)
	else:
		if not _start_ai_ocean_accident(bundle, is_p1):
			if not _start_ai_collision_accident(bundle, is_p1):
				_start_ai_dash_move(true, bundle, is_p1)


func _start_ai_lane_shift(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	_start_ai_dash_move(false, bundle, is_p1)


func _max_depth_z_for_bundle(bundle: MenuPreviewActorAIState = null) -> float:
	if (
		bundle != null
		and (
			bundle.pending_accident == PENDING_ACCIDENT_OCEAN
			or (
				bundle.ai_state == AI_STATE_KNOCKBACK
				and not bundle.knockback_is_lethal
			)
		)
	):
		return PREVIEW_OCEAN_DEPTH_MAX
	return PREVIEW_BELT_Z_MAX


func _clamp_depth_target_z(z: float, bundle: MenuPreviewActorAIState = null) -> float:
	return clampf(z, PREVIEW_BELT_Z_MIN, _max_depth_z_for_bundle(bundle))


func _reconcile_actor_moving_back(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.is_emoting:
		return
	if bundle.depth_shift_active:
		_sync_actor_moving_back_for_depth(bundle, is_p1)
	elif _actor_moving_back(is_p1):
		_set_actor_moving_back(is_p1, false)


func _pick_depth_target_z(is_p1: bool, forward_hint: int = 0) -> float:
	var cur := _actor_local_z(is_p1)
	var step := randf_range(AI_DEPTH_STEP_MIN, AI_DEPTH_STEP_MAX)
	# 本編と同じ: 前進は -Z（壁方向）、後退は +Z
	if forward_hint > 0:
		return _clamp_depth_target_z(cur - step)
	if forward_hint < 0:
		return _clamp_depth_target_z(cur + step)
	return _clamp_depth_target_z(randf_range(PREVIEW_BELT_Z_MIN, PREVIEW_BELT_Z_MAX))


func _update_preview_run_anim_speed_multipliers() -> void:
	if not _preview_gs:
		return
	_preview_gs.p1_run_anim_speed_mult = _run_anim_speed_mult_for_actor(_p1_ai, true)
	_preview_gs.p2_run_anim_speed_mult = _run_anim_speed_mult_for_actor(_p2_ai, false)


func _run_anim_speed_mult_for_actor(bundle: MenuPreviewActorAIState, is_p1: bool) -> float:
	if not _preview_gs or not _actor_alive(is_p1):
		return 1.0
	var identity_mult := 1.0
	if _is_local_2p_active():
		identity_mult = AI_2P_P1_RUN_ANIM_MULT if is_p1 else AI_2P_P2_RUN_ANIM_MULT
	if bundle.is_emoting or bundle.ai_state != AI_STATE_NORMAL:
		return identity_mult
	if _actor_moving_back(is_p1):
		return identity_mult
	if bundle.depth_shift_active:
		var cur := _actor_local_z(is_p1)
		if bundle.target_local_z < cur - 0.03:
			var depth_factor := bundle.depth_shift_speed / PREVIEW_RUN_ANIM_SPEED_BASE
			return clampf(
				PREVIEW_RUN_ANIM_SPEED_MULT * (0.9 + depth_factor * 0.1) * identity_mult,
				1.6,
				2.8
			)
	return identity_mult


func _sync_actor_moving_back_for_depth(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not bundle.depth_shift_active or bundle.is_emoting:
		return
	_set_actor_moving_back(is_p1, bundle.target_local_z > _actor_local_z(is_p1) + 0.03)


func _start_ai_depth_step(bundle: MenuPreviewActorAIState, is_p1: bool, forward: bool) -> bool:
	if not _preview_gs:
		return false
	var cur := _actor_local_z(is_p1)
	var target := _clamp_depth_target_z(_pick_depth_target_z(is_p1, 1 if forward else -1))
	if absf(target - cur) < 0.3:
		return false
	bundle.target_local_z = target
	bundle.depth_shift_speed = randf_range(AI_DEPTH_SHIFT_SPEED_MIN, AI_DEPTH_SHIFT_SPEED_MAX)
	bundle.depth_shift_active = true
	bundle.lane_shift_active = false
	_sync_actor_moving_back_for_depth(bundle, is_p1)
	return true


func _start_ai_dash_move(is_acro: bool, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs:
		return
	var skill := _get_door_learning_skill(bundle)
	var min_x := AI_PLAYER_X_MIN
	var max_x := AI_PLAYER_X_MAX
	var next_x := clampf(_pick_ai_dash_target_x(bundle), min_x, max_x)
	if absf(next_x - _actor_x(is_p1)) < 0.28:
		next_x = clampf(
			next_x + randf_range(-0.85, 0.85),
			min_x,
			max_x
		)
	if _should_separate_2p_target(bundle):
		var other := _p2_ai if is_p1 else _p1_ai
		if absf(next_x - other.target_x) < AI_2P_TARGET_SEPARATION_X:
			next_x = clampf(
				other.target_x + (-AI_2P_TARGET_SEPARATION_X if is_p1 else AI_2P_TARGET_SEPARATION_X),
				min_x,
				max_x
			)
	bundle.target_x = next_x
	var lane_shift_max := lerpf(AI_LANE_SHIFT_SPEED_MAX, 3.8, skill)
	bundle.lane_shift_speed = randf_range(
		AI_LANE_SHIFT_SPEED_MIN + (0.7 if is_acro else 0.0),
		lane_shift_max + (1.1 if is_acro else 0.0)
	)
	bundle.lane_shift_active = true
	var depth_hint := 0
	if not is_acro and randf() < 0.72:
		depth_hint = 1 if randf() < 0.5 else -1
	var next_z := _clamp_depth_target_z(_pick_depth_target_z(is_p1, depth_hint), bundle)
	if _should_separate_2p_target(bundle):
		var other := _p2_ai if is_p1 else _p1_ai
		if absf(next_z - other.target_local_z) < AI_2P_TARGET_SEPARATION_Z:
			next_z = _clamp_depth_target_z(
				other.target_local_z + (-AI_2P_TARGET_SEPARATION_Z if is_p1 else AI_2P_TARGET_SEPARATION_Z),
				bundle
			)
	bundle.target_local_z = next_z
	bundle.depth_shift_speed = randf_range(
		AI_DEPTH_SHIFT_SPEED_MIN + (0.7 if is_acro else 0.0),
		AI_DEPTH_SHIFT_SPEED_MAX + (1.3 if is_acro else 0.0)
	)
	bundle.depth_shift_active = true
	_sync_actor_moving_back_for_depth(bundle, is_p1)


func _should_separate_2p_target(bundle: MenuPreviewActorAIState) -> bool:
	return (
		_is_local_2p_active()
		and bundle.pending_accident == PENDING_ACCIDENT_NONE
		and not _is_learning_commit_active(bundle)
	)


func _update_lane_shift(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs or not bundle.lane_shift_active:
		return
	_set_actor_x(is_p1, move_toward(
		_actor_x(is_p1),
		bundle.target_x,
		bundle.lane_shift_speed * dt
	))
	if absf(_actor_x(is_p1) - bundle.target_x) <= 0.03:
		_set_actor_x(is_p1, bundle.target_x)
		bundle.lane_shift_active = false


func _update_depth_shift(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs or not bundle.depth_shift_active:
		return
	bundle.target_local_z = _clamp_depth_target_z(bundle.target_local_z, bundle)
	var before_z := _actor_local_z(is_p1)
	var next_z := move_toward(before_z, bundle.target_local_z, bundle.depth_shift_speed * dt)
	next_z = _clamp_depth_target_z(next_z, bundle)
	_set_actor_local_z(is_p1, next_z)
	var reached := absf(next_z - bundle.target_local_z) <= 0.04
	var stuck := not reached and absf(next_z - before_z) < 0.0005
	if reached or stuck:
		if reached:
			_set_actor_local_z(is_p1, bundle.target_local_z)
		bundle.depth_shift_active = false
		if bundle.ai_state == AI_STATE_NORMAL:
			_set_actor_moving_back(is_p1, false)
	elif not bundle.is_emoting:
		_sync_actor_moving_back_for_depth(bundle, is_p1)


func _start_ai_jump(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not _preview_gs:
		return false
	if bundle.is_emoting:
		return false
	if _actor_y(is_p1) > 0.01 or _actor_vel_y(is_p1) != 0.0:
		return false
	_set_actor_vel_y(is_p1, randf_range(AI_JUMP_SPEED_MIN, AI_JUMP_SPEED_MAX))
	_set_actor_jump_trigger(is_p1, true)
	bundle.jump_trigger_ttl = 0.09
	return true


func _update_ground_movement(dt: float, _bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs:
		return
	_set_actor_vel_y(is_p1, _actor_vel_y(is_p1) - AI_GRAVITY * dt)
	var next_y := _actor_y(is_p1) + _actor_vel_y(is_p1) * dt
	if next_y <= PREVIEW_FLOOR_Y and _actor_y(is_p1) > PREVIEW_FLOOR_Y:
		_set_actor_y(is_p1, PREVIEW_FLOOR_Y)
		_set_actor_vel_y(is_p1, 0.0)
	else:
		_set_actor_y(is_p1, next_y)
		if _actor_y(is_p1) <= PREVIEW_FLOOR_Y:
			_set_actor_y(is_p1, PREVIEW_FLOOR_Y)
			if _actor_vel_y(is_p1) < 0.0:
				_set_actor_vel_y(is_p1, 0.0)


func _start_ai_emote(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not _preview_gs:
		return false
	if bundle.available_emotes.is_empty():
		return false
	if _actor_y(is_p1) > 0.01 or _actor_vel_y(is_p1) != 0.0:
		return false
	var emote_pool := bundle.available_emotes.duplicate()
	if emote_pool.size() > 1 and bundle.last_emote > 0:
		emote_pool.erase(bundle.last_emote)
	if emote_pool.is_empty():
		emote_pool = bundle.available_emotes.duplicate()
	var idx := randi() % emote_pool.size()
	_set_actor_emote(is_p1, int(emote_pool[idx]))
	bundle.last_emote = _actor_emote(is_p1)
	bundle.emote_end_t = _ai_time + randf_range(AI_EMOTE_DURATION_MIN, AI_EMOTE_DURATION_MAX)
	bundle.is_emoting = true
	bundle.next_action_t = maxf(bundle.next_action_t, bundle.emote_end_t + 0.25)
	_set_actor_moving_back(is_p1, false)
	return true


func _update_emote_timer(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not bundle.is_emoting:
		return
	if _ai_time >= bundle.emote_end_t:
		_stop_ai_emote_if_needed(bundle, is_p1)


func _set_actor_taunt_emote_lock(is_p1: bool, locked: bool) -> void:
	if not _preview_gs:
		return
	if is_p1:
		_preview_gs.p1_emote_lock_timer = AI_TAUNT_EMOTE_LOCK if locked else 0.0
	else:
		_preview_gs.p2_emote_lock_timer = AI_TAUNT_EMOTE_LOCK if locked else 0.0


func _clear_taunt_emote_lock(is_p1: bool) -> void:
	_set_actor_taunt_emote_lock(is_p1, false)
	var pc := _preview_player as PlayerController
	if pc:
		pc.reset_thriller_sequence(not is_p1)


func _get_preview_rig_emote_ids(is_p1: bool) -> Array[int]:
	var pc := _preview_player as PlayerController
	if not pc:
		return []
	return pc.get_loaded_emote_ids(not is_p1)


func _filter_emotes_for_rig(candidates: Array[int], is_p1: bool) -> Array[int]:
	var rig_ids := _get_preview_rig_emote_ids(is_p1)
	if rig_ids.is_empty():
		return candidates.duplicate()
	var filtered: Array[int] = []
	for raw in candidates:
		var id := EmoteData.normalize_emote_id(int(raw))
		if rig_ids.has(id):
			filtered.append(id)
	return filtered


func _stop_ai_emote_if_needed(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs:
		return
	bundle.is_emoting = false
	_set_actor_emote(is_p1, 0)
	if bundle.ai_state != AI_STATE_TAUNT:
		_clear_taunt_emote_lock(is_p1)
	if not bundle.depth_shift_active:
		_set_actor_moving_back(is_p1, false)


func _start_taunt_emote(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not _preview_gs or not _actor_alive(is_p1):
		return false
	if bundle.available_emotes.is_empty():
		return false
	if _actor_y(is_p1) > 0.01 or _actor_vel_y(is_p1) != 0.0:
		return false
	var emote_pool := _filter_emotes_for_rig(bundle.available_emotes, is_p1)
	if emote_pool.is_empty():
		emote_pool = _get_preview_rig_emote_ids(is_p1)
	if emote_pool.is_empty():
		emote_pool = bundle.available_emotes.duplicate()
	if emote_pool.size() > 1 and bundle.last_emote > 0:
		emote_pool.erase(bundle.last_emote)
	if emote_pool.is_empty():
		emote_pool = _filter_emotes_for_rig(bundle.available_emotes, is_p1)
	if emote_pool.is_empty():
		return false
	var idx := randi() % emote_pool.size()
	var emote_id := int(emote_pool[idx])
	_set_actor_emote(is_p1, emote_id)
	bundle.last_emote = emote_id
	_set_actor_moving_back(is_p1, false)
	_set_actor_taunt_emote_lock(is_p1, true)
	var pc := _preview_player as PlayerController
	if pc:
		if EmoteData.is_thriller_emote(emote_id):
			pc.reset_thriller_sequence(not is_p1)
			pc.start_thriller_sequence(not is_p1)
		else:
			pc.reset_thriller_sequence(not is_p1)
		pc.ensure_emote_playback(not is_p1, emote_id)
	return true


func _begin_survivor_taunt(dead_is_p1: bool) -> void:
	if not _is_local_2p_active():
		return
	var survivor_is_p1 := not dead_is_p1
	if not _actor_alive(survivor_is_p1):
		return
	var survivor := _p1_ai if survivor_is_p1 else _p2_ai
	survivor.taunt_target_x = _actor_x(dead_is_p1)
	survivor.taunt_target_z = _actor_local_z(dead_is_p1)
	survivor.ai_state = AI_STATE_TAUNT
	survivor.lane_shift_active = false
	survivor.depth_shift_active = false
	survivor.crash_wall = null
	survivor.blocking_wall = null
	_clear_pending_accident(survivor)
	_stop_ai_emote_if_needed(survivor, survivor_is_p1)
	_set_actor_moving_back(survivor_is_p1, false)
	_start_taunt_emote(survivor, survivor_is_p1)


func _stop_survivor_taunt(respawned_is_p1: bool) -> void:
	if not _is_local_2p_active():
		return
	var survivor_is_p1 := not respawned_is_p1
	var survivor := _p1_ai if survivor_is_p1 else _p2_ai
	if survivor.ai_state != AI_STATE_TAUNT:
		return
	survivor.ai_state = AI_STATE_NORMAL
	_stop_ai_emote_if_needed(survivor, survivor_is_p1)
	_clear_taunt_emote_lock(survivor_is_p1)
	survivor.next_action_t = _ai_time + randf_range(0.35, 0.9)


func _facing_y_toward(from_x: float, from_z: float, to_x: float, to_z: float) -> float:
	var dx := to_x - from_x
	var dz := to_z - from_z
	if dx * dx + dz * dz < 0.04:
		return PI
	return atan2(dx, dz)


func _start_ai_acrobatics(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not _preview_gs or not _actor_alive(is_p1):
		return false
	if bundle.is_emoting:
		return false
	bundle.ai_state = AI_STATE_ACROBATICS
	bundle.state_end_t = _ai_time + randf_range(AI_ACRO_DURATION_MIN, AI_ACRO_DURATION_MAX)
	bundle.next_acro_jump_t = _ai_time + randf_range(0.08, 0.35)
	bundle.acro_seed = randf_range(-12.0, 12.0)
	_start_ai_dash_move(true, bundle, is_p1)
	return true


func _update_acrobatic_action(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs:
		return
	_update_lane_shift(dt, bundle, is_p1)
	_update_depth_shift(dt, bundle, is_p1)
	_update_ground_movement(dt, bundle, is_p1)

	if not bundle.lane_shift_active or not bundle.depth_shift_active:
		_start_ai_dash_move(true, bundle, is_p1)
	elif randf() < 0.055:
		_start_ai_dash_move(true, bundle, is_p1)

	if _actor_y(is_p1) <= 0.02 and _ai_time >= bundle.next_acro_jump_t:
		_set_actor_vel_y(is_p1, randf_range(AI_ACRO_JUMP_SPEED_MIN, AI_ACRO_JUMP_SPEED_MAX))
		_set_actor_jump_trigger(is_p1, true)
		bundle.jump_trigger_ttl = 0.11
		bundle.next_acro_jump_t = _ai_time + randf_range(AI_ACRO_BURST_INTERVAL_MIN, AI_ACRO_BURST_INTERVAL_MAX)

	if _actor_y(is_p1) <= 0.03 and not bundle.is_emoting and randf() < AI_ACRO_EMOTE_BURST_CHANCE * dt:
		if _start_ai_emote(bundle, is_p1):
			bundle.emote_end_t = minf(
				bundle.emote_end_t,
				_ai_time + randf_range(AI_ACRO_EMOTE_BURST_DURATION_MIN, AI_ACRO_EMOTE_BURST_DURATION_MAX)
			)

	_set_actor_moving_back(
		is_p1,
		sin((_ai_time + bundle.acro_seed) * 8.5) > 0.0 and not bundle.is_emoting
	)
	_update_emote_timer(bundle, is_p1)

	if _ai_time >= bundle.state_end_t:
		_set_actor_moving_back(is_p1, false)
		bundle.ai_state = AI_STATE_NORMAL
		bundle.next_action_t = _ai_time + randf_range(0.55, 1.4)


func _start_ai_collision_accident(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not _preview_gs or not _actor_alive(is_p1):
		return false
	if _is_learning_commit_active(bundle):
		return false
	if bundle.pending_accident != PENDING_ACCIDENT_NONE:
		return false
	var wall := _pick_upcoming_wall_for_accident(bundle)
	if not wall:
		return false
	bundle.pending_accident = PENDING_ACCIDENT_WALL
	bundle.pending_accident_wall = wall
	bundle.crash_wall = wall
	wall.set_meta("preview_accident_owner", bundle)
	_set_actor_moving_back(is_p1, false)
	bundle.target_x = _pick_accident_crash_x(bundle)
	bundle.lane_shift_speed = randf_range(AI_LANE_SHIFT_SPEED_MIN, AI_LANE_SHIFT_SPEED_MAX)
	bundle.lane_shift_active = true
	bundle.target_local_z = _clamp_depth_target_z(
		_actor_local_z(is_p1) + randf_range(-0.8, 0.8)
	)
	bundle.depth_shift_speed = randf_range(AI_DEPTH_SHIFT_SPEED_MIN, AI_DEPTH_SHIFT_SPEED_MAX)
	bundle.depth_shift_active = true
	bundle.accident_cooldown_t = _ai_time + randf_range(AI_ACCIDENT_COOLDOWN_MIN, AI_ACCIDENT_COOLDOWN_MAX)
	return true


func _pick_upcoming_wall_for_accident(for_bundle: MenuPreviewActorAIState = null) -> Node3D:
	var candidate: Node3D = null
	var best_z := INF
	for wall in _preview_walls:
		if not is_instance_valid(wall):
			continue
		if not _wall_available_for_accident(wall, for_bundle):
			continue
		var z := wall.position.z
		if z < -26.0 or z > 4.0:
			continue
		if z < best_z:
			best_z = z
			candidate = wall
	return candidate


func _wall_available_for_accident(wall: Node3D, for_bundle: MenuPreviewActorAIState) -> bool:
	if not is_instance_valid(wall):
		return false
	if bool(wall.get_meta("preview_door_broken", false)):
		return false
	if wall.has_meta("preview_accident_owner"):
		var accident_owner = wall.get_meta("preview_accident_owner")
		if accident_owner != null and accident_owner != for_bundle:
			return false
	for bundle in [_p1_ai, _p2_ai]:
		if bundle == for_bundle:
			continue
		if (
			bundle.pending_accident == PENDING_ACCIDENT_WALL
			and bundle.pending_accident_wall == wall
		):
			return false
	return true


func _start_ai_ocean_accident(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not _preview_gs or not _actor_alive(is_p1):
		return false
	if bundle.pending_accident != PENDING_ACCIDENT_NONE:
		return false
	bundle.pending_accident = PENDING_ACCIDENT_OCEAN
	bundle.pending_accident_wall = null
	bundle.crash_wall = null
	bundle.lane_shift_active = false
	bundle.target_local_z = PREVIEW_BELT_EDGE_FALL_Z + randf_range(0.35, 0.65)
	bundle.depth_shift_speed = randf_range(AI_DEPTH_SHIFT_SPEED_MIN, AI_DEPTH_SHIFT_SPEED_MAX)
	bundle.depth_shift_active = true
	_sync_actor_moving_back_for_depth(bundle, is_p1)
	bundle.accident_cooldown_t = _ai_time + randf_range(AI_ACCIDENT_COOLDOWN_MIN, AI_ACCIDENT_COOLDOWN_MAX)
	return true


func _update_pending_accident_wall(_dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.pending_accident != PENDING_ACCIDENT_WALL:
		return
	if not is_instance_valid(bundle.pending_accident_wall):
		_clear_pending_accident(bundle)
		return
	if absf(_actor_x(is_p1) - bundle.target_x) <= 0.05:
		return
	bundle.lane_shift_active = true
	if bundle.lane_shift_speed <= 0.01:
		bundle.lane_shift_speed = randf_range(AI_LANE_SHIFT_SPEED_MIN, AI_LANE_SHIFT_SPEED_MAX)


func _update_pending_accident_ocean(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.pending_accident != PENDING_ACCIDENT_OCEAN:
		return
	if not _is_past_belt_edge(is_p1):
		var next_z := move_toward(
			_actor_local_z(is_p1),
			bundle.target_local_z,
			bundle.depth_shift_speed * dt
		)
		next_z = _clamp_depth_target_z(next_z, bundle)
		_set_actor_local_z(is_p1, next_z)
		if not bundle.is_emoting:
			_sync_actor_moving_back_for_depth(bundle, is_p1)
		return
	_set_actor_vel_y(is_p1, _actor_vel_y(is_p1) - AI_GRAVITY * AI_OCEAN_GRAVITY_SCALE * dt)
	var next_y := _actor_y(is_p1) + _actor_vel_y(is_p1) * dt
	_set_actor_y(is_p1, next_y)
	if _actor_y(is_p1) <= StageConstants.OCEAN_ENTRY_Y:
		_set_actor_y(is_p1, StageConstants.OCEAN_ENTRY_Y)
		_clear_pending_accident(bundle)
		_trigger_preview_death("ocean", bundle, is_p1)


func _start_crash_knockback(
	blocking_wall: Node3D = null,
	bundle: MenuPreviewActorAIState = null,
	is_p1: bool = true
) -> void:
	if bundle == null:
		bundle = _p1_ai
	if not _preview_gs or not _actor_alive(is_p1):
		return
	_pause_preview_conveyor()
	bundle.blocking_wall = blocking_wall
	if is_p1:
		_separate_blocking_wall_from_player()
	else:
		_separate_blocking_wall_from_player_p2()
	_push_walls_away_from_player(_actor_local_z(is_p1))
	bundle.ai_state = AI_STATE_KNOCKBACK
	bundle.knockback_is_lethal = true
	bundle.lane_shift_active = false
	bundle.depth_shift_active = false
	_stop_ai_emote_if_needed(bundle, is_p1)
	_set_actor_jump_trigger(is_p1, false)
	_set_actor_moving_back(is_p1, false)
	_set_actor_vel_y(is_p1, randf_range(4.9, 6.3))
	var home_x := PREVIEW_PLAYER_X if is_p1 else PREVIEW_PLAYER2_X
	var sx := signf(_actor_x(is_p1) - home_x)
	if sx == 0.0:
		sx = -1.0 if randf() < 0.5 else 1.0
	bundle.knockback_vel_x = sx * randf_range(4.2, 6.0)
	bundle.knockback_vel_z = -randf_range(3.3, 5.4)
	_set_actor_local_z(is_p1, _actor_local_z(is_p1) - 0.65)
	bundle.knockback_end_t = _ai_time + randf_range(AI_KNOCKBACK_DURATION_MIN, AI_KNOCKBACK_DURATION_MAX)


func _update_knockback_motion(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs:
		return
	bundle.knockback_vel_x = move_toward(bundle.knockback_vel_x, 0.0, AI_KNOCKBACK_DAMPING * dt)
	bundle.knockback_vel_z = move_toward(bundle.knockback_vel_z, 0.0, AI_KNOCKBACK_DAMPING * dt)
	_set_actor_x(is_p1, _actor_x(is_p1) + bundle.knockback_vel_x * dt)
	_set_actor_local_z(is_p1, _actor_local_z(is_p1) + bundle.knockback_vel_z * dt)
	_set_actor_x(is_p1, clampf(
		_actor_x(is_p1),
		AI_PLAYER_X_MIN - AI_KNOCKBACK_X_RANGE_PAD,
		AI_PLAYER_X_MAX + AI_KNOCKBACK_X_RANGE_PAD
	))
	_set_actor_local_z(is_p1, clampf(
		_actor_local_z(is_p1),
		PREVIEW_BELT_Z_MIN - AI_KNOCKBACK_Z_BACK_PAD,
		_max_depth_z_for_bundle(bundle)
	))
	_set_actor_vel_y(is_p1, _actor_vel_y(is_p1) - AI_GRAVITY * 1.1 * dt)
	var next_y := _actor_y(is_p1) + _actor_vel_y(is_p1) * dt
	if next_y <= PREVIEW_FLOOR_Y and _actor_y(is_p1) > PREVIEW_FLOOR_Y:
		_set_actor_y(is_p1, PREVIEW_FLOOR_Y)
		_set_actor_vel_y(is_p1, 0.0)
	else:
		_set_actor_y(is_p1, next_y)
		if _actor_y(is_p1) <= PREVIEW_FLOOR_Y:
			_set_actor_y(is_p1, PREVIEW_FLOOR_Y)
			if _actor_vel_y(is_p1) < 0.0:
				_set_actor_vel_y(is_p1, 0.0)
	if not bundle.knockback_is_lethal and _is_past_belt_edge(is_p1):
		bundle.ai_state = AI_STATE_NORMAL
		bundle.pending_accident = PENDING_ACCIDENT_OCEAN
		bundle.knockback_vel_x = 0.0
		bundle.knockback_vel_z = 0.0
		return
	if _ai_time >= bundle.knockback_end_t:
		if bundle.knockback_is_lethal:
			_trigger_preview_death("crash", bundle, is_p1)
		else:
			bundle.knockback_vel_x = 0.0
			bundle.knockback_vel_z = 0.0
			bundle.knockback_is_lethal = true
			bundle.ai_state = AI_STATE_NORMAL
			bundle.next_action_t = _ai_time + randf_range(0.35, 0.75)


func _trigger_preview_death(
	reason: String,
	bundle: MenuPreviewActorAIState = null,
	is_p1: bool = true
) -> void:
	if bundle == null:
		bundle = _p1_ai
	if not _preview_gs:
		return
	if is_p1:
		if not _actor_alive(is_p1):
			return
		# 本編と同じ死亡原因フラグを渡し、壁衝突だけを即時ラグドールへ分岐させる。
		# 海落下は従来の死亡演出を維持する。
		_set_actor_wall_impact(true, reason == "crash")
		_push_walls_away_from_player(_actor_local_z(is_p1))
		_separate_blocking_wall_from_player()
		_stop_ai_emote_if_needed(bundle, is_p1)
		_set_actor_jump_trigger(is_p1, false)
		_set_actor_moving_back(is_p1, false)
		_set_actor_alive(is_p1, false)
		_set_actor_game_over_timer(is_p1, 0.001)
		if reason == "ocean":
			_set_actor_y(is_p1, StageConstants.OCEAN_ENTRY_Y)
			_set_actor_vel_y(is_p1, -3.8)
		else:
			_set_actor_y(is_p1, maxf(_actor_y(is_p1), 0.0))
			_set_actor_vel_y(is_p1, minf(_actor_vel_y(is_p1), -0.9))
	else:
		if not _preview_gs.p2_alive:
			return
		_set_actor_wall_impact(false, reason == "crash")
		_push_walls_away_from_player(_preview_gs.player2_local_z)
		_separate_blocking_wall_from_player_p2()
		_stop_ai_emote_if_needed_p2()
		_preview_gs.p2_jump_trigger = false
		_preview_gs.p2_moving_back = false
		_preview_gs.p2_alive = false
		_preview_gs.player2_game_over_timer = 0.001
		if reason == "ocean":
			_preview_gs.player2_y = StageConstants.OCEAN_ENTRY_Y
			_preview_gs.player2_vel_y = -3.8
		else:
			_preview_gs.player2_y = maxf(_preview_gs.player2_y, 0.0)
			_preview_gs.player2_vel_y = minf(_preview_gs.player2_vel_y, -0.9)
	bundle.ai_state = AI_STATE_DEAD
	bundle.lane_shift_active = false
	bundle.depth_shift_active = false
	bundle.blocking_wall = null
	_clear_pending_accident(bundle)
	var death_duration := randf_range(AI_DEAD_TO_RESPAWN_MIN, AI_DEAD_TO_RESPAWN_MAX)
	if reason == "crash":
		death_duration = maxf(death_duration, QuizGameState.WALL_DEATH_SEQUENCE_DURATION)
	bundle.dead_end_t = _ai_time + death_duration
	_begin_survivor_taunt(is_p1)


func _start_respawn(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs:
		return
	_stop_survivor_taunt(is_p1)
	_clear_pending_accident(bundle)
	_schedule_death_shard_cleanup(is_p1)
	_rebuild_preview_player()
	bundle.ai_state = AI_STATE_RESPAWN
	bundle.knockback_is_lethal = true
	bundle.knockback_vel_x = 0.0
	bundle.knockback_vel_z = 0.0
	_set_actor_wall_impact(is_p1, false)
	_set_actor_alive(is_p1, true)
	_set_actor_game_over_timer(is_p1, 0.0)
	_set_actor_emote(is_p1, 0)
	_set_actor_jump_trigger(is_p1, false)
	_set_actor_moving_back(is_p1, false)
	_set_actor_x(is_p1, clampf(_pick_ai_dash_target_x(bundle), AI_PLAYER_X_MIN, AI_PLAYER_X_MAX))
	_set_actor_local_z(is_p1, _pick_safe_respawn_local_z())
	_push_walls_away_from_player(_actor_local_z(is_p1))
	_set_actor_y(is_p1, randf_range(AI_RESPAWN_START_Y_MIN, AI_RESPAWN_START_Y_MAX))
	_set_actor_vel_y(is_p1, -randf_range(AI_RESPAWN_DOWN_SPEED_MIN, AI_RESPAWN_DOWN_SPEED_MAX))
	bundle.target_x = _actor_x(is_p1)
	bundle.target_local_z = _actor_local_z(is_p1)
	bundle.accident_cooldown_t = _ai_time + randf_range(AI_ACCIDENT_COOLDOWN_MIN, AI_ACCIDENT_COOLDOWN_MAX)


func _update_respawn_drop(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not _preview_gs:
		return
	_set_actor_vel_y(is_p1, _actor_vel_y(is_p1) - AI_GRAVITY * dt)
	var next_y := _actor_y(is_p1) + _actor_vel_y(is_p1) * dt
	_set_actor_y(is_p1, next_y)
	if _actor_y(is_p1) <= 0.0:
		_set_actor_y(is_p1, 0.0)
		_set_actor_vel_y(is_p1, 0.0)
		_set_actor_moving_back(is_p1, false)
		bundle.ai_state = AI_STATE_NORMAL
		bundle.next_action_t = _ai_time + randf_range(0.45, 1.2)
		_resume_preview_conveyor()


func _separate_blocking_wall_from_player() -> void:
	if not _p1_ai.blocking_wall or not is_instance_valid(_p1_ai.blocking_wall):
		return
	if not _preview_gs:
		return
	var player_z := _preview_gs.player_local_z
	_p1_ai.blocking_wall.position.z = player_z - PREVIEW_WALL_PUSH_BACK_Z
	_p1_ai.blocking_wall.set_meta("preview_door_broken", true)
	_p1_ai.blocking_wall.set_meta("preview_collision_processed", true)
	if _p1_ai.blocking_wall.visible and _p1_ai.blocking_wall.has_method("shatter_wall"):
		_p1_ai.blocking_wall.shatter_wall(PREVIEW_WALL_SHATTER_DIR_Z)
	_p1_ai.blocking_wall.visible = false


func _push_walls_away_from_player(player_local_z: float) -> void:
	var back_z := player_local_z - PREVIEW_WALL_PUSH_BACK_Z
	var ahead_z := player_local_z + PREVIEW_WALL_PLAYER_CLEAR_Z
	for wall in _preview_walls:
		if not is_instance_valid(wall):
			continue
		if _wall_is_reserved_for_other_crash_runup(wall):
			continue
		var wall_z := wall.position.z
		var too_close := wall_z > player_local_z - 1.2 and wall_z < ahead_z
		if not too_close:
			continue
		wall.position.z = back_z
		wall.set_meta("preview_door_broken", true)
		wall.set_meta("preview_collision_processed", true)
		wall.set_meta("preview_accident_owner", null)
		if wall.visible and wall.has_method("shatter_wall"):
			wall.shatter_wall(PREVIEW_WALL_SHATTER_DIR_Z)
		wall.visible = false
		if wall == _p1_ai.blocking_wall:
			_p1_ai.blocking_wall = null
		if wall == _p2_ai.blocking_wall:
			_p2_ai.blocking_wall = null
		if wall == _p1_ai.pending_accident_wall:
			_clear_pending_accident(_p1_ai)
		if wall == _p2_ai.pending_accident_wall:
			_clear_pending_accident(_p2_ai)


func _wall_is_reserved_for_other_crash_runup(wall: Node3D) -> bool:
	for bundle in [_p1_ai, _p2_ai]:
		if bundle.pending_accident == PENDING_ACCIDENT_WALL and bundle.pending_accident_wall == wall:
			return true
	return false


func _release_wall_accident_claim(wall: Node3D) -> void:
	if not is_instance_valid(wall):
		return
	if wall.has_meta("preview_accident_owner"):
		wall.remove_meta("preview_accident_owner")


func _pick_safe_respawn_local_z() -> float:
	var best_z := 0.0
	var best_clearance := -INF
	for _i in range(10):
		var trial_z := randf_range(PREVIEW_BELT_Z_MIN * 0.35, PREVIEW_BELT_Z_MAX * 0.55)
		var clearance := _min_wall_front_gap(trial_z)
		if clearance > best_clearance:
			best_clearance = clearance
			best_z = trial_z
	if best_clearance < PREVIEW_WALL_PLAYER_CLEAR_Z * 0.55:
		return 0.0
	return best_z


func _min_wall_front_gap(player_local_z: float) -> float:
	var min_gap := INF
	for wall in _preview_walls:
		if not is_instance_valid(wall):
			continue
		var front_z := wall.position.z + PREVIEW_DOOR_HALF_DEPTH_Z
		var gap := front_z - player_local_z
		if gap < min_gap:
			min_gap = gap
	return min_gap


func _rebuild_preview_player() -> void:
	if not _viewport:
		return
	if _preview_player and is_instance_valid(_preview_player):
		_preview_player.queue_free()
	_preview_player = Node3D.new()
	_preview_player.set_script(PLAYER_CONTROLLER_SCRIPT)
	_viewport.add_child(_preview_player)
	_reset_applied_preview_cosmetics()
	_reload_preview_emote_rigs()


func _separate_blocking_wall_from_player_p2() -> void:
	if not _p2_ai.blocking_wall or not is_instance_valid(_p2_ai.blocking_wall):
		return
	if not _preview_gs:
		return
	var player_z := _preview_gs.player2_local_z
	_p2_ai.blocking_wall.position.z = player_z - PREVIEW_WALL_PUSH_BACK_Z
	_p2_ai.blocking_wall.set_meta("preview_door_broken", true)
	_p2_ai.blocking_wall.set_meta("preview_collision_processed", true)
	if _p2_ai.blocking_wall.visible and _p2_ai.blocking_wall.has_method("shatter_wall"):
		_p2_ai.blocking_wall.shatter_wall(PREVIEW_WALL_SHATTER_DIR_Z)
	_p2_ai.blocking_wall.visible = false


func _stop_ai_emote_if_needed_p2() -> void:
	_stop_ai_emote_if_needed(_p2_ai, false)

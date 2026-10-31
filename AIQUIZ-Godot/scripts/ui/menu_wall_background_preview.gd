class_name MenuWallBackgroundPreview
extends Node

signal game_start_departure_finished(success: bool)

## メインメニュー背景: カスタマイズ「壁速度」タブ／壁速度設定画面と同型の3Dプレビュー
## ランナーの AI は scripts/ui/menu_preview/ の部品（MenuActorAI ほか）が受け持ち、ここは舞台（壁・ノコギリ・押し合い・
## 出発演出・カメラ）と、部品が読み書きする共有の状態（_preview_gs・_p1_ai・_p2_ai・_ai_time）を持つ。

const WALL_SCENE: PackedScene = preload("res://scenes/quiz_wall.tscn")
const PLAYER_CONTROLLER_SCRIPT: Script = preload("res://scripts/world/player_controller.gd")
const LocalPushEffectsScript = preload("res://scripts/effects/local_push_effects.gd")
const MenuPreviewCameraSettingsScript = preload("res://scripts/ui/menu_preview_camera_settings.gd")
const MenuPreviewDoorLearnerScript = preload("res://scripts/ui/menu_preview_door_learner.gd")
const MenuPreviewActorAIStateScript = preload("res://scripts/ui/menu_preview_actor_ai_state.gd")
const PreviewWallMergeAnimatorScript = preload("res://scripts/ui/preview_wall_merge_animator.gd")
const HelicopterArrivalDirectorScript = preload("res://scripts/world/helicopter_arrival_director.gd")
const AiquizMenuStageScript = preload("res://scripts/world/menu_stage/aiquiz_menu_stage.gd")
const Geo = preload("res://scripts/ui/menu_preview/menu_preview_geometry.gd")
const MenuActorAIScript = preload("res://scripts/ui/menu_preview/menu_actor_ai.gd")
const MenuActorEmotesScript = preload("res://scripts/ui/menu_preview/menu_actor_emotes.gd")
const MenuActorAccidentsScript = preload("res://scripts/ui/menu_preview/menu_actor_accidents.gd")
const MenuDoorLearningScript = preload("res://scripts/ui/menu_preview/menu_door_learning.gd")
const MenuGhostRideDirectorScript = preload("res://scripts/ui/menu_preview/menu_ghost_ride_director.gd")

const WALL_SPACING := 30.0
const MENU_INTRO_WALL_START_Z := -72.0
const PREVIEW_PLAYER_X: float = Geo.PLAYER_X
const PREVIEW_PLAYER2_X: float = Geo.PLAYER2_X
const PREVIEW_DOOR_HALF_DEPTH_Z: float = Geo.DOOR_HALF_DEPTH_Z
## 本編 game_state の wall_z - 0.4 を扉手前(+Z)基準に換算（0.4 + 扉半奥行0.3）
const PREVIEW_WALL_CONTACT_Z: float = Geo.WALL_CONTACT_Z
const PREVIEW_RED_DOOR_INDEX: int = Geo.RED_DOOR_INDEX
## メニューの壁は本編と同じ面をカメラ(+Z)へ向けるため Y 軸で 180° 回す。
## そのため quiz_wall.gd の 2択ドア位置 (扉0=青 x=+3.5 / 扉1=赤 x=-3.5) はワールドでは左右が入れ替わる
## (画面左=青, 画面右=赤 で本編と同じ並び)。
const PREVIEW_WALL_YAW: float = PI
const PREVIEW_DOOR_X_LEFT: float = Geo.DOOR_X_LEFT
const PREVIEW_DOOR_X_RIGHT: float = Geo.DOOR_X_RIGHT
const PREVIEW_WALL_SHATTER_DIR_Z: float = 1.0
## キャラと壁が重ならないよう確保する Z 方向の最小クリアランス
const PREVIEW_WALL_PLAYER_CLEAR_Z: float = Geo.WALL_PLAYER_CLEAR_Z
const PREVIEW_WALL_PUSH_BACK_Z: float = Geo.WALL_PUSH_BACK_Z
const AUTO_WALL_SPEED: float = GameTuning.WALL_SPEED_AUTO_DEFAULT
## AI の状態と事故の種類（本体は MenuPreviewActorAIState。tests/ が preview.AI_STATE_NORMAL などで読む）
const AI_STATE_NORMAL: int = MenuPreviewActorAIStateScript.STATE_NORMAL
const AI_STATE_KNOCKBACK: int = MenuPreviewActorAIStateScript.STATE_KNOCKBACK
const AI_STATE_OCEAN_FALL: int = MenuPreviewActorAIStateScript.STATE_OCEAN_FALL
const AI_STATE_DEAD: int = MenuPreviewActorAIStateScript.STATE_DEAD
const AI_STATE_RESPAWN: int = MenuPreviewActorAIStateScript.STATE_RESPAWN
const AI_STATE_ACROBATICS: int = MenuPreviewActorAIStateScript.STATE_ACROBATICS
const AI_STATE_TAUNT: int = MenuPreviewActorAIStateScript.STATE_TAUNT
const PENDING_ACCIDENT_NONE: int = MenuPreviewActorAIStateScript.PENDING_ACCIDENT_NONE
const PENDING_ACCIDENT_WALL: int = MenuPreviewActorAIStateScript.PENDING_ACCIDENT_WALL
const PENDING_ACCIDENT_OCEAN: int = MenuPreviewActorAIStateScript.PENDING_ACCIDENT_OCEAN
const PENDING_ACCIDENT_SAW: int = MenuPreviewActorAIStateScript.PENDING_ACCIDENT_SAW
const PREVIEW_DEATH_SHARD_LINGER_SEC: float = 5.0
const PREVIEW_FLOOR_Y: float = Geo.FLOOR_Y
const PREVIEW_BELT_Z_MIN: float = Geo.BELT_Z_MIN
const PREVIEW_BELT_Z_MAX: float = Geo.BELT_Z_MAX
const PREVIEW_BELT_EDGE_FALL_Z: float = Geo.BELT_EDGE_FALL_Z
## 海落下待機中だけ通常上限(4.2)を超えて端まで進める
const PREVIEW_OCEAN_DEPTH_MAX: float = Geo.OCEAN_DEPTH_MAX

## 壁速度タブ基準から少し引いて左寄せ（UIが右側のため）
const PREVIEW_CAM_POS := Vector3(-18.0, 6.1, 23.15)
const PREVIEW_CAM_ROT_DEG := Vector3(-14.0, -19.0, 0.0)
const PREVIEW_CAM_FOV := 37.5
const PREVIEW_CAM_H_OFFSET := 0.05

var _viewport: SubViewport
var _preview_camera: Camera3D
var _stage_env: StageEnvironment = null
## メニュー専用ステージ（AIQUIZ HARBOR LAUNCH）。コンベアのデモはそのまま、まわりを港の桟橋・発進デッキ・街で飾る
var _menu_stage: AiquizMenuStage = null
var _preview_saw: SawChaseController
var _menu_saw := MenuSawChaseState.new()
var _saw_accident_owner := 0
const SAW_INITIAL_GRACE := 20.0
const SAW_TRIAL_INTERVAL := 10.0
const SAW_ACCIDENT_CHANCE := .15
const SAW_NEAR_MISS_CHANCE := .25
var _saw_accident_cooldown := SAW_INITIAL_GRACE
var _saw_next_trial := SAW_INITIAL_GRACE
var _saw_near_miss := false
var _saw_events: Array[Dictionary] = []
var _preview_walls: Array[Node3D] = []
var _menu_pickup_retracted_walls: Array[Dictionary] = []
var _wall_merge: PreviewWallMergeAnimator = null
var _preview_scroll_z: float = 0.0
var _preview_speed: float = AUTO_WALL_SPEED
var _conveyor_paused: bool = false
var _preview_player: Node3D
var _preview_gs: QuizGameState
var _menu_push_next_t := [0.0, 0.0]
var _ai_time: float = 0.0
var _linger_time: float = 0.0
var _p1_death_shard_clear_t: float = -1.0
var _p2_death_shard_clear_t: float = -1.0
var _applied_preview_p1_hat: int = -999
var _applied_preview_p2_hat: int = -999
var _p1_ai: MenuPreviewActorAIState
var _p2_ai: MenuPreviewActorAIState
## ランナーの AI の部品（_init で作るので、_ready を呼ばないテストの fixture でも使える）
var _ai: MenuActorAIScript
var _ai_emotes: MenuActorEmotesScript
var _accidents: MenuActorAccidentsScript
var _door_learning: MenuDoorLearningScript
## 2P で死んだランナーがときどきゴーストシャークに乗って相手を襲う（_ready で作る）
var _ghost: MenuGhostRideDirectorScript = null
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
## 初回の配置が済むまで AI と壁を止める（tests/menu_push_runtime.gd が直接下ろす）
var _menu_intro_active := false
var _menu_start_departure: HelicopterArrivalDirector = null
var _menu_start_departure_active := false
## Keep the extracted runners hidden until the menu scene is replaced.
var _menu_departure_hold := false
var _seat_departure_requested := false


func _init() -> void:
	_ai = MenuActorAIScript.new(self)
	_ai_emotes = MenuActorEmotesScript.new(self)
	_accidents = MenuActorAccidentsScript.new(self)
	_door_learning = MenuDoorLearningScript.new(self)


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
	_prepare_game_start_departure()
	_preview_player.apply_waiting_pose(_preview_gs.num_players, PI)
	set_process(true)


func get_camera() -> Camera3D:
	return _preview_camera


func get_stage_environment() -> StageEnvironment:
	return _stage_env


func get_menu_stage() -> AiquizMenuStage:
	return _menu_stage


## メニューのカメラの回転。メニュー専用ステージを出すときは街が画面に入るよう俯角を浅くする。
static func menu_camera_rotation_degrees() -> Vector3:
	if AiquizMenuStageScript.enabled():
		return AiquizMenuStageScript.camera_rotation_degrees()
	return PREVIEW_CAM_ROT_DEG


func apply_graphics_quality() -> void:
	if _viewport:
		GraphicsQuality.apply_text_viewport(_viewport, GameManager.graphics_quality)
	if _stage_env:
		_stage_env.apply_graphics_quality(GameManager.graphics_quality)
	if _menu_stage:
		_menu_stage.apply_graphics_quality(GameManager.graphics_quality)


## カスタマイズUIがキャラ・スキン照明・エモートを載せる共有 SubViewport
func get_shared_viewport() -> SubViewport:
	return _viewport


## カスタマイズ画面に入る: メニューAIを停止・非表示にし、カメラ制御を譲る
func enter_customize_mode() -> void:
	if _ghost:
		_ghost.abort_all()
	_reset_menu_push()
	_customize_active = true
	_set_customize_walls_hidden(false)
	_resume_preview_conveyor()
	if _preview_camera:
		_menu_cam_pose = {
			"position": _preview_camera.position,
			"rotation_degrees": _preview_camera.rotation_degrees,
			"fov": _preview_camera.fov,
			"h_offset": _preview_camera.h_offset,
			"v_offset": _preview_camera.v_offset,
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
	# スキン画面はキャラを中央の枠に収めるため縦にもずらすので、こちらも戻す。
	tw.parallel().tween_property(_preview_camera, "v_offset", float(d.get("v_offset", 0.0)), 0.45)


func _resolve_preview_speed() -> void:
	var tuning := QuizManager.game_state.tuning
	if tuning.wall_speed_override > 0.0:
		_preview_speed = clampf(
			tuning.wall_speed_override,
			GameTuning.WALL_SPEED_SLIDER_MIN,
			GameTuning.WALL_SPEED_SLIDER_MAX
		)
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
	return Geo.wall_front_touches_player(door_leading_z, player_local_z)


func _process(dt: float) -> void:
	if not _viewport:
		return
	if _preview_saw != null:
		var container := _viewport.get_parent() as CanvasItem
		var shown := (container == null or container.is_visible_in_tree()) and not SceneTransition.is_transitioning()
		var presented := shown and not _customize_walls_hidden
		if presented:
			QuizManager.set_meta("saw_dock_menu_seen", true)
		# The wall speed tab racks the blades (Blender "Stow" clip); leaving customize deploys them
		# again before the chase and the preview spin clock resume.
		_preview_saw.stow_target = _customize_active and (_preview_saw.dock == null or _preview_saw.dock.is_deployed())
		var saw_running := presented and not _customize_active and not _menu_start_departure_active and not _menu_departure_hold and _preview_saw.is_stow_clear()
		# An early Start lets the existing dock finish moving before the buckle.
		# Never teleport the whole station into place to show the new effect.
		var seat_waiting_dock := _seat_departure_requested and _menu_start_departure_active and _preview_saw.dock != null and not _preview_saw.dock.is_deployed()
		saw_running = saw_running or (presented and seat_waiting_dock)
		_preview_saw.update_preview(dt if saw_running else 0.0)
		# Skin/emote tabs hide only the walls: the carriage stays in view, racked beside the conveyor.
		_preview_saw.advance_stow(dt if shown else 0.0)
		if _seat_departure_requested and _menu_start_departure_active and not seat_waiting_dock:
			var transfer := _preview_saw.operator_seat.seat_transfer
			if transfer.phase == SeatLaunchPresentation.Phase.IDLE: transfer.begin_buckle()
		if not presented:
			# The reveal pauses preview AI, but its visible actors still need a pose.
			if not _customize_active and not _menu_start_departure_active and not _menu_departure_hold:
				_preview_player.apply_waiting_pose(_preview_gs.num_players, PI)
			if _ghost:
				_ghost.abort_all()
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
			_door_learning.on_wall_removed(wall)
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

		if wall.position.z >= _wall_break_z():
			if wall == _p1_ai.pending_accident_wall:
				_clear_pending_accident(_p1_ai)
			if wall == _p2_ai.pending_accident_wall:
				_clear_pending_accident(_p2_ai)
			_accidents.release_wall_claim(wall)
			_door_learning.on_wall_removed(wall)
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
		var saw_start1 := Vector2(_actor_x(true),_actor_local_z(true))
		var saw_start2 := Vector2(_actor_x(false),_actor_local_z(false))
		_update_preview_actor_ai(dt)
		if _is_local_2p_active():
			_update_preview_actor2_ai(dt)
			_update_menu_push(dt, p1_body_start, p2_body_start)
			# 本編と同じ2Pカプセル判定で、メニュー背景のAI同士も重なり・すり抜けを防ぐ。
			_preview_gs._resolve_two_player_body_collision(p1_body_start, p2_body_start)
			_preview_gs._flush_local_push_events()
		elif _preview_gs.local_push.time > 0.0:
			_reset_menu_push()
		_update_menu_saw(dt,saw_start1,saw_start2)
	if _preview_player and _preview_gs and not _customize_active:
		_preview_gs._active_wall_speed = effective_speed
		_ai.update_run_anim_speed_multipliers()
		_preview_player.update_from_state(_preview_gs)
		_sync_preview_player_cosmetics()
		_preview_player.visible = true
		_force_preview_player_facing_away()
		if _ghost:
			_ghost.update(dt)
	elif _preview_player and _customize_active:
		_preview_player.visible = false

	_update_preview_debris_near_camera()
	_update_death_shard_cleanup()


## While the stow machine stands over the belt (davit beams, clamps, upright blades), walls break
## short of its reach instead of passing through it. Flat chase blades and blades hung beside
## the conveyor keep the original cliff edge.
func _wall_break_z() -> float:
	if _preview_saw == null or not _preview_saw.stow_blocks_walls():
		return 8.0
	return minf(8.0, _preview_saw.position.z - _preview_saw.wall_reach_y() - 0.1 - PREVIEW_DOOR_HALF_DEPTH_Z)


func _reset_menu_push() -> void:
	if _preview_gs:
		_preview_gs.local_push.reset()
	_menu_push_next_t = [randf_range(0.3, 0.7), randf_range(0.3, 0.7)]


func _menu_push_actor_valid(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	return (
		_actor_alive(is_p1)
		and bundle.ai_state in [AI_STATE_NORMAL, AI_STATE_ACROBATICS]
		and bundle.pending_accident == PENDING_ACCIDENT_NONE
		and not _is_past_belt_edge(is_p1)
	)


func _update_menu_push(dt: float, p1_start: Vector2, p2_start: Vector2) -> void:
	if dt <= 0.0:
		return
	var duel = _preview_gs.local_push
	var valid := [_menu_push_actor_valid(_p1_ai, true), _menu_push_actor_valid(_p2_ai, false)]
	var grounded := [_actor_y(true) <= 0.001, _actor_y(false) <= 0.001]
	var starts := Vector2(p1_start.x, p2_start.x)
	# AI has already chosen its X/Z movement. Feed that X velocity through the
	# gameplay solver once, so held pressure and shoulder hits own the result.
	var velocity := (Vector2(_actor_x(true), _actor_x(false)) - starts) / dt
	for i in range(2):
		var direction := int(signf(velocity[i])) if valid[i] else 0
		for key_direction in [-1, 1]:
			var bit := 1 if key_direction > 0 else 2
			var was_down: bool = (int(duel.held[i]) & bit) != 0
			if was_down != (direction == key_direction):
				duel.queue_key(i + 1, key_direction, direction == key_direction)
		# Deliberate release/repress uses the same windup/cooldown as real input.
		# Independent reaction times let either actor win or occasionally clash.
		if not duel.contact or duel.stalemate < duel.STALEMATE_TIME:
			_menu_push_next_t[i] = duel.time + randf_range(0.3, 0.7)
		elif valid[i] and grounded[i] and direction == int(duel.pose_direction[i]) and duel.time >= _menu_push_next_t[i]:
			duel.queue_key(i + 1, direction, false)
			duel.queue_key(i + 1, direction, true)
			_menu_push_next_t[i] = duel.time + randf_range(0.7, 1.3)
	var positions: Vector2 = duel.advance(dt, starts,
		_actor_local_z(false) - _actor_local_z(true), valid, grounded, velocity, 1.0,
		absf(_actor_y(true) - _actor_y(false)) < QuizGameState.PLAYER_BODY_HEIGHT)
	for i in range(2):
		if valid[i]:
			_set_actor_x(i == 0, positions[i])
	if duel.contact:
		if _p1_ai.is_emoting:
			_stop_ai_emote_if_needed(_p1_ai, true)
		if _p2_ai.is_emoting:
			_stop_ai_emote_if_needed(_p2_ai, false)


func _update_menu_saw(dt: float, start1: Vector2, start2: Vector2) -> void:
	if _preview_saw==null:return
	# Racked or deploying blades neither chase nor cut; the chase resumes once they are back.
	if not _preview_saw.is_stow_clear():return
	if _saw_accident_owner==2 and not _is_local_2p_active():
		_clear_pending_accident(_p2_ai);_saw_accident_owner=0
	if _saw_accident_owner!=0:
		var owner := _p1_ai if _saw_accident_owner==1 else _p2_ai
		if owner.pending_accident!=PENDING_ACCIDENT_SAW:_saw_accident_owner=0
	var ready := (_preview_saw.dock==null or _preview_saw.dock.is_deployed()) and _preview_saw._preview_elapsed>=SawChaseState.SPINUP_SECONDS
	# ゴーストのライド中は持ち場へ戻って待つ（吹き飛ばされた先が刃にならないように）。終われば GRACE から追跡に戻る。
	var ghost_hold := _ghost_ride_holds_saw()
	if ghost_hold and _menu_saw.victim_mask==0 and _menu_saw.phase in [MenuSawChaseState.Phase.CHASING,MenuSawChaseState.Phase.GRACE]:
		_menu_saw.phase=MenuSawChaseState.Phase.RETURNING;_menu_saw.clock=0.0
	var leader := INF
	var rear := -INF
	var landed := true
	for index: int in [1,2]:
		var active := index==1 or _is_local_2p_active()
		var is_p1 := index==1
		if active and _actor_alive(is_p1) and (_p1_ai if is_p1 else _p2_ai).ai_state!=AI_STATE_RESPAWN:
			leader=minf(leader,_actor_local_z(is_p1))
			rear=maxf(rear,_actor_local_z(is_p1))
		if active and _menu_saw.victim_mask & (1<<(index-1)):
			landed=landed and _actor_alive(is_p1) and _actor_y(is_p1)<=.01
	var old_phase := _menu_saw.phase
	_menu_saw.advance(dt,ready,leader,landed and not ghost_hold,rear)
	if old_phase!=MenuSawChaseState.Phase.GRACE and _menu_saw.phase==MenuSawChaseState.Phase.GRACE:
		# Start the shared rest period after the victims have landed, not at death.
		_saw_accident_cooldown=_ai_time+randf_range(45.0,60.0)
		_saw_next_trial=_saw_accident_cooldown
	if not ghost_hold:_update_saw_accident_trial()
	var mask := 0
	if ready:
		for index: int in [1,2]:
			var is_p1 := index==1
			var bundle := _p1_ai if is_p1 else _p2_ai
			if index==2 and not _is_local_2p_active():continue
			if not _actor_alive(is_p1) or bundle.ai_state in [AI_STATE_RESPAWN,AI_STATE_OCEAN_FALL]:continue
			if ( _preview_gs.p1_waiting_for_shark if is_p1 else _preview_gs.p2_waiting_for_shark):continue
			if _menu_saw.hit(start1 if is_p1 else start2,Vector2(_actor_x(is_p1),_actor_local_z(is_p1))):mask|=1<<(index-1)
	if mask:
		_menu_saw.catch_players(mask)
		_saw_accident_cooldown=INF # Released only after the return and landing.
		_saw_events.append({"event":"catch","time":_ai_time,"mask":mask,"z":_menu_saw.local_z})
		for index: int in [1,2]:
			if mask & (1<<(index-1)):_trigger_preview_death("saw",_p1_ai if index==1 else _p2_ai,index==1)
	if old_phase!=_menu_saw.phase:
		_saw_events.append({"event":"phase","time":_ai_time,"phase":_menu_saw.phase,"z":_menu_saw.local_z})
	while _saw_events.size()>64:_saw_events.pop_front()
	_preview_gs.saw.enabled=ready
	_preview_gs.saw.local_z=_menu_saw.local_z
	_preview_gs.saw.wheel_distance=_menu_saw.travel
	_preview_saw.apply_menu_chase(_preview_gs,_menu_saw,dt)

func _update_saw_accident_trial() -> void:
	if _menu_saw.phase!=MenuSawChaseState.Phase.CHASING or _ai_time<_saw_next_trial or _ai_time<_saw_accident_cooldown:return
	_saw_next_trial=_ai_time+SAW_TRIAL_INTERVAL
	if _saw_accident_owner!=0:return
	var roll := randf()
	if roll>=SAW_ACCIDENT_CHANCE+SAW_NEAR_MISS_CHANCE:return
	var near_miss := roll>=SAW_ACCIDENT_CHANCE
	var order: Array[int]=[1,2]
	if randf()<.5:order.reverse()
	for index in order:
		if index==2 and not _is_local_2p_active():continue
		if _start_saw_accident(_p1_ai if index==1 else _p2_ai,index==1,near_miss):break

func _saw_safe_depth() -> float:
	return _menu_saw.local_z-SawChaseState.BLADE_RADIUS-QuizGameState.PLAYER_BODY_RADIUS-MenuSawChaseState.SAFE_GAP

func _escape_from_saw(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	_clear_pending_accident(bundle)
	_clear_learning_commit(bundle)
	if _saw_accident_owner==(1 if is_p1 else 2):_saw_accident_owner=0
	bundle.target_local_z=maxf(PREVIEW_BELT_Z_MIN,_saw_safe_depth()-.8)
	bundle.depth_shift_speed=4.2
	bundle.depth_shift_active=true
	bundle.next_action_t=maxf(bundle.next_action_t,_ai_time+1.0)
	_set_actor_moving_back(is_p1,false)

func _avoid_saw(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.pending_accident==PENDING_ACCIDENT_SAW or bundle.is_emoting or _is_past_belt_edge(is_p1):return
	if _actor_local_z(is_p1)>=_saw_safe_depth()-.12:
		# This also interrupts an ocean run-up whose rearward path is blocked by the saw.
		_escape_from_saw(bundle,is_p1)

func _ghost_ride_holds_saw() -> bool:
	return _ghost != null and _ghost.wants_saw_clear()

func _start_saw_accident(bundle: MenuPreviewActorAIState, is_p1: bool, near_miss: bool=false) -> bool:
	if _menu_saw.phase!=MenuSawChaseState.Phase.CHASING or _saw_accident_owner!=0 or _ai_time<_saw_accident_cooldown:return false
	if _ghost_ride_holds_saw():return false
	if bundle.pending_accident!=PENDING_ACCIDENT_NONE or bundle.ai_state!=AI_STATE_NORMAL or bundle.is_emoting or not _actor_alive(is_p1):return false
	var target := _menu_saw.local_z-SawChaseState.BLADE_RADIUS-QuizGameState.PLAYER_BODY_RADIUS+.35
	if near_miss:target=_saw_safe_depth()
	if target>PREVIEW_BELT_Z_MAX or target<=_actor_local_z(is_p1)+.4:return false
	_clear_learning_commit(bundle)
	bundle.pending_accident=PENDING_ACCIDENT_SAW
	bundle.lane_shift_active=false
	bundle.depth_shift_active=true
	bundle.target_local_z=target
	bundle.depth_shift_speed=2.4
	_saw_accident_owner=1 if is_p1 else 2
	_saw_near_miss=near_miss
	_saw_events.append({"event":"near_miss_start" if near_miss else "accident_start","time":_ai_time,"player":_saw_accident_owner})
	bundle.state_end_t=_ai_time+6.0
	return true

func _update_pending_saw_accident(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.pending_accident!=PENDING_ACCIDENT_SAW:return
	if _saw_near_miss and _actor_local_z(is_p1)>=_saw_safe_depth()-.12:
		_saw_events.append({"event":"near_miss_escape","time":_ai_time,"player":1 if is_p1 else 2})
		_escape_from_saw(bundle,is_p1)
		return
	if _menu_saw.phase!=MenuSawChaseState.Phase.CHASING or _ai_time>=bundle.state_end_t:
		_clear_pending_accident(bundle);_saw_accident_owner=0
		_saw_accident_cooldown=maxf(_saw_accident_cooldown,_ai_time+5.0)
		return
	bundle.target_local_z=minf(PREVIEW_BELT_Z_MAX,_saw_safe_depth() if _saw_near_miss else _menu_saw.local_z-SawChaseState.BLADE_RADIUS-QuizGameState.PLAYER_BODY_RADIUS+.35)
	bundle.depth_shift_active=true
	_set_actor_moving_back(is_p1,true)

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
	_preview_saw = SawChaseController.new()
	_preview_saw.name = "MenuSawCarriage"
	_viewport.add_child(_preview_saw)
	_preview_saw.configure_entrance(true, not QuizManager.has_meta("saw_dock_menu_seen"))
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
		"include_harbor_city": false,
		# The camera can turn round (customize screen): the game's lighthouse, islands
		# and skyline lie behind it, and the menu has its own city in front.
		"include_stadium_scenery": false,
	})
	if AiquizMenuStageScript.enabled():
		_menu_stage = AiquizMenuStageScript.new() as AiquizMenuStage
		_menu_stage.name = "AiquizMenuStage"
		_viewport.add_child(_menu_stage)
		_menu_stage.build(GameManager.graphics_quality)

	_preview_gs = QuizGameState.new()
	var push_effects := LocalPushEffectsScript.new()
	push_effects.name = "MenuPushEffects"
	_viewport.add_child(push_effects)
	_preview_gs.local_push_event.connect(func(event: Dictionary) -> void:
		if event.kind in ["hit", "clash"]:
			push_effects.spawn(event)
	)
	_ghost = MenuGhostRideDirectorScript.new(self)
	_viewport.add_child(_ghost)
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
	# メニュー初回表示はキャラクターを配置済みの状態から始める。
	_place_actors_for_menu_start()


## メニュー初回表示のランナーと壁の配置（ヘリ到着・ラグドール降下は生成せず、通常のプレビューをすぐ動かす）。
func _place_actors_for_menu_start() -> void:
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


func _prepare_game_start_departure() -> void:
	if not _viewport or not _preview_gs or not _preview_player or not _preview_camera:
		return
	_menu_start_departure = HelicopterArrivalDirectorScript.new() as HelicopterArrivalDirector
	_menu_start_departure.name = "MenuHelicopterStartDepartureDirector"
	_menu_start_departure.presentation_finished.connect(_on_game_start_departure_finished)
	_menu_start_departure.menu_boost_launched.connect(_launch_operator_chair)
	_viewport.add_child(_menu_start_departure)
	_menu_start_departure.prepare_menu_departure(
		_preview_gs, _preview_player as PlayerController, _preview_camera
	)


func begin_game_start_departure(player_count: int) -> bool:
	if _ghost:
		_ghost.abort_all()
	_reset_menu_push()
	if _menu_start_departure_active:
		return false
	_menu_departure_hold = false
	SeatLaunchPresentation.clear_handoff()
	_seat_departure_requested = SeatLaunchPresentation.eligible(QuizManager.game_state, NetworkManager.state == NetworkManager.State.IN_GAME)
	if not _viewport or not _preview_gs or not _preview_player or not _preview_camera:
		return false
	var count := clampi(player_count, 1, 2)
	_menu_start_departure_active = true
	_menu_synced_player_count = count
	_preview_gs.num_players = count
	_menu_saw.reset()
	_saw_accident_owner=0
	_preview_gs.p1_saw_killed=false
	_preview_gs.p2_saw_killed=false
	_clear_pending_accident(_p1_ai)
	_clear_pending_accident(_p2_ai)
	# Always begin the cinematic from a readable, grounded runner pose.  The
	# ambient menu AI may have been emoting, airborne, or recovering from an
	# accident when Start was pressed; carrying that pose into the suction made
	# the hand-off look like a pop rather than an intentional pickup.
	_preview_gs.p1_alive = true
	_preview_gs.p1_waiting_for_shark = false
	_preview_gs.p1_wall_impact = false
	_preview_gs.player_y = 0.0
	_preview_gs.player_vel_y = 0.0
	_preview_gs.p1_emote = 0
	_preview_gs.p1_jump_trigger = false
	if count >= 2:
		_preview_gs.p2_alive = true
		_preview_gs.p2_waiting_for_shark = false
		_preview_gs.p2_wall_impact = false
		_preview_gs.player2_y = 0.0
		_preview_gs.player2_vel_y = 0.0
		_preview_gs.p2_emote = 0
		_preview_gs.p2_jump_trigger = false
	_pause_preview_conveyor()
	_preview_gs._active_wall_speed = 0.0
	_preview_player.update_from_state(_preview_gs)
	if _preview_player.has_method("prepare_intro_pickup_pose"):
		_preview_player.call("prepare_intro_pickup_pose", count, PI)
	if not is_instance_valid(_menu_start_departure) or _menu_start_departure._cancelled:
		if is_instance_valid(_menu_start_departure):
			_menu_start_departure.queue_free()
		_prepare_game_start_departure()
	_menu_start_departure.setup_menu_departure(
		_preview_gs,
		_preview_player as PlayerController,
		_preview_camera,
		count
	)
	_menu_start_departure.menu_launch_ready = _operator_chair_ready if _seat_departure_requested else Callable()
	_clear_game_start_pickup_area(_menu_start_departure.get_menu_pickup_clearance_z())
	return _menu_start_departure_active


func _clear_game_start_pickup_area(back_z: float) -> void:
	# Retract only walls in the pickup corridor before anyone begins running.
	# Lower them into the floor instead of sweeping a wall through an actor.
	var front_z := maxf(_preview_gs.player_local_z, _preview_gs.player2_local_z) + 2.0
	for wall: Node3D in _preview_walls:
		if not is_instance_valid(wall) or not wall.visible:
			continue
		if wall.position.z <= back_z or wall.position.z >= front_z:
			continue
		var retract := create_tween()
		_menu_pickup_retracted_walls.append({
			"wall": wall, "position": wall.position, "tween": retract,
			"collision_processed": wall.get_meta("preview_collision_processed", false),
		})
		wall.set_meta("preview_collision_processed", true)
		retract.tween_property(wall, "position:y", StageConstants.FLOOR_TOP_Y - 8.0, 0.35)
		retract.tween_callback(wall.hide)


func is_game_start_departure_active() -> bool:
	return _menu_start_departure_active


func is_ready_for_scene_cover(cover_duration: float = -1.0) -> bool:
	if _menu_start_departure != null and is_instance_valid(_menu_start_departure):
		return _menu_start_departure.is_ready_for_scene_cover(cover_duration)
	return not _menu_start_departure_active


func skip_game_start_departure() -> void:
	if not _menu_start_departure_active:
		return
	if _seat_departure_requested: _preview_saw.operator_seat.seat_transfer.skip_departure()
	if _menu_start_departure != null and is_instance_valid(_menu_start_departure):
		_menu_start_departure.skip_menu_departure()
		return
	cancel_game_start_departure()


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
		if _seat_departure_requested: _preview_saw.operator_seat.seat_transfer.reset()
		_seat_departure_requested = false
		SeatLaunchPresentation.clear_handoff()
		for entry: Dictionary in _menu_pickup_retracted_walls:
			var retract := entry["tween"] as Tween
			if retract != null and retract.is_valid():
				retract.kill()
			var wall := entry["wall"] as Node3D
			if is_instance_valid(wall):
				wall.position = entry["position"]
				wall.visible = true
				wall.set_meta("preview_collision_processed", entry["collision_processed"])
		_reset_preview_ai_state()
		if _is_local_2p_active():
			_reset_preview_actor2_ai_state()
		_resume_preview_conveyor()
		if _preview_player and _preview_gs:
			_preview_player.update_from_state(_preview_gs)
			_sync_preview_player_cosmetics(true)
	_menu_pickup_retracted_walls.clear()
	game_start_departure_finished.emit(success)


func _operator_chair_ready() -> bool:
	# Buckling goes ahead; only the launch waits while a stowing rack crosses the chair's column.
	return (not _seat_departure_requested or _preview_saw.operator_seat.seat_transfer.is_buckled()) and _preview_saw.chair_launch_clear(1.5)


func _launch_operator_chair() -> void:
	if _seat_departure_requested: _preview_saw.operator_seat.seat_transfer.launch()


func _exit_tree() -> void:
	if _seat_departure_requested and _preview_saw != null and is_instance_valid(_preview_saw.operator_seat):
		# The existing wipe can finish just before the helicopter emits completion.
		# Preserve that covered handoff; an uncovered mid-flight exit is cancellation.
		var transfer := _preview_saw.operator_seat.seat_transfer
		var covered_flight := SceneTransition.is_fully_covered() and transfer.phase in [SeatLaunchPresentation.Phase.LAUNCHING, SeatLaunchPresentation.Phase.AWAY]
		if not _menu_departure_hold and not covered_flight:
			SeatLaunchPresentation.clear_handoff()
	if _menu_start_departure != null and is_instance_valid(_menu_start_departure):
		_menu_start_departure_active = false
		if _menu_start_departure.presentation_finished.is_connected(_on_game_start_departure_finished):
			_menu_start_departure.presentation_finished.disconnect(_on_game_start_departure_finished)
		_menu_start_departure.cancel()
	if _ghost:
		_ghost.shutdown()


func _pick_preview_quiz() -> QuizItem:
	## オフラインバンクから本物の問題を1問取得し、2択に変換する
	if not _quiz_provider:
		return null
	_preview_subject_idx = (_preview_subject_idx + 1) % Constants.SUBJECTS.size()
	var subject: String = Constants.SUBJECTS[_preview_subject_idx]
	var subject_grades := Constants.grades_for_subject(subject)
	var grade: int = subject_grades.pick_random()
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
	# 本編のプレイヤー側の面 (問題文パネル・扉に収めた選択肢) をメニューカメラへ向ける
	wall.rotation.y = PREVIEW_WALL_YAW
	_viewport.add_child(wall)
	var is_real_quiz := not quiz.q.is_empty() and quiz.q != "プレビュー"
	wall.set_quiz(quiz if is_real_quiz else null, 2)
	if is_real_quiz:
		# 本物の問題: 本編と同じ問題文・選択肢を表示し、AIが解く正解扉を記録
		wall.set_gameplay_question(FractionFormatter.format_question(quiz.q), true)
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


## tests/ 互換用の入口（本体は MenuActorAccidents）
func _clear_pending_accident(bundle: MenuPreviewActorAIState) -> void:
	_accidents.clear_pending(bundle)


## tests/ 互換用の入口（本体は MenuDoorLearning）
func _clear_learning_commit(bundle: MenuPreviewActorAIState, home_x: float = PREVIEW_PLAYER_X) -> void:
	_door_learning.clear_commit(bundle, home_x)


## tests/ 互換用の入口（本体は MenuActorEmotes）
func _stop_ai_emote_if_needed(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	_ai_emotes.stop_emote(bundle, is_p1)


## tests/ 互換用の入口（本体は MenuActorAI）
func _update_depth_shift(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	_ai.update_depth_shift(dt, bundle, is_p1)


## tests/ 互換用の入口（本体は MenuActorAI）
func _clamp_depth_target_z(z: float, bundle: MenuPreviewActorAIState = null) -> float:
	return _ai.clamp_depth_target_z(z, bundle)


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
	if _accidents.should_force_wall_crash(bundle, wall):
		wall.set_meta("preview_should_break_door", false)
		_clear_pending_accident(bundle)
		_handle_preview_wall_crash(wall, bundle, is_p1)
		return
	var should_break_door: bool = bool(wall.get_meta("preview_should_break_door", true))
	if should_break_door:
		var door_idx := Geo.door_index_at(_actor_x(is_p1))
		var correct_door := int(wall.get_meta("preview_correct_door", -1))
		if door_idx >= 0 and (correct_door < 0 or door_idx == correct_door):
			_trigger_preview_door_pass(wall, door_idx, bundle, is_p1)
		else:
			# 不正解の扉は本編同様に通れない (激突扱い)
			_handle_preview_wall_crash(wall, bundle, is_p1)
	else:
		_handle_preview_wall_crash(wall, bundle, is_p1)


func _is_local_2p_active() -> bool:
	return _preview_gs != null and _preview_gs.num_players >= 2 and _menu_synced_player_count == 2


func sync_menu_player_count(count: int) -> void:
	count = 2 if count == 2 else 1
	if _menu_start_departure_active or _menu_departure_hold:
		return
	if not _preview_gs:
		return
	var prev := _menu_synced_player_count
	if prev == count:
		return
	_reset_menu_push()
	_menu_synced_player_count = count
	if count == 2 and prev != 2:
		_enable_preview_p2_drop_in()
	elif prev == 2 and count != 2:
		if _ghost:
			_ghost.abort(true)
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
		_ai.pick_dash_target_x(_p2_ai),
		MenuActorAIScript.PLAYER_X_MIN,
		MenuActorAIScript.PLAYER_X_MAX
	)
	_set_actor_local_z(false, 0.0)
	_preview_gs.player2_y = randf_range(MenuActorAIScript.RESPAWN_START_Y_MIN, MenuActorAIScript.RESPAWN_START_Y_MAX)
	_preview_gs.player2_vel_y = -randf_range(MenuActorAIScript.RESPAWN_DOWN_SPEED_MIN, MenuActorAIScript.RESPAWN_DOWN_SPEED_MAX)
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
	# 体の塗りはプレビュー用の状態へ写せば、update_from_state が変化したときだけ塗り直す。
	if _preview_gs.p1_skin_code != gm.p1_skin_code:
		_preview_gs.set_player_skin(1, gm.p1_skin)
	if _preview_gs.p2_skin_code != gm.p2_skin_code:
		_preview_gs.set_player_skin(2, gm.p2_skin)
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
	_ai_emotes.fill_pool(_p1_ai, _preview_p1_rig_emote_ids)
	_ai_emotes.fill_pool(_p2_ai, _preview_p2_rig_emote_ids)


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
	_ai_emotes.stop_survivor_taunt(false)
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
	if not wall or not _preview_gs or not _actor_alive(is_p1):
		return
	_clamp_actor_before_wall_front(is_p1, wall.position.z + PREVIEW_DOOR_HALF_DEPTH_Z)
	var hit_key := "preview_hit_p1" if is_p1 else "preview_hit_p2"
	if wall.get_meta(hit_key, false):
		return
	wall.set_meta(hit_key, true)
	_door_learning.record_outcome_for_wall(wall, -1.0, bundle)
	_pause_preview_conveyor()
	bundle.blocking_wall = wall
	_separate_blocking_wall(bundle, is_p1)
	_push_walls_away_from_player(_actor_local_z(is_p1))
	_trigger_preview_death("crash", bundle, is_p1)


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
	# 正解の扉を3回くぐるごとに、設定中のエモートからランダムに1つ選んで踊る（ゴーストに狙われているあいだは踊らない）
	bundle.door_passes_since_emote += 1
	if bundle.door_passes_since_emote >= 3 and bundle.ghost_mode == MenuPreviewActorAIStateScript.GHOST_MODE_NONE:
		bundle.door_passes_since_emote = 0
		_ai_emotes.start_emote(bundle, is_p1)
	_door_learning.record_outcome_for_wall(wall, 1.0, bundle)
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
		# 死んでいる方（ゴーストに乗っているあいだも）はくぐったことにする。でないと壁が砕けずにカメラの前まで流れてくる
		var p1_done: bool = wall.get_meta("preview_hit_p1", false) or not _preview_gs.p1_alive
		var p2_done: bool = wall.get_meta("preview_hit_p2", false) or not _preview_gs.p2_alive
		wall_ready = p1_done and p2_done and (_preview_gs.p1_alive or _preview_gs.p2_alive)
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
	_ai_emotes.apply_legacy_facing(pc.p1_parts, _p1_ai, true)
	if _is_local_2p_active():
		_ai_emotes.apply_legacy_facing(pc.p2_parts, _p2_ai, false)


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


func _reset_preview_ai_state() -> void:
	_ai_time = 0.0
	_conveyor_paused = false
	_ai.reset_actor(_p1_ai, true, 0.55, 1.05)
	_ai_emotes.fill_pool(_p1_ai, _preview_p1_rig_emote_ids)


func _reset_preview_actor2_ai_state() -> void:
	_ai.reset_actor(_p2_ai, false, 1.35, 2.05)
	_ai_emotes.fill_pool(_p2_ai, _preview_p2_rig_emote_ids)


func _update_preview_actor_ai(dt: float) -> void:
	if not _preview_gs:
		return
	_ai_time += dt
	_ai.update_actor(dt, true)


func _update_preview_actor2_ai(dt: float) -> void:
	if not _preview_gs or not _is_local_2p_active():
		return
	_ai.update_actor(dt, false)


func _is_past_belt_edge(is_p1: bool) -> bool:
	if not _preview_gs:
		return false
	return _actor_local_z(is_p1) > PREVIEW_BELT_EDGE_FALL_Z


func _trigger_preview_death(
	reason: String,
	bundle: MenuPreviewActorAIState = null,
	is_p1: bool = true
) -> void:
	if bundle == null:
		bundle = _p1_ai if is_p1 else _p2_ai
	if not _preview_gs:
		return
	if reason == "saw":
		if is_p1:
			_preview_gs.p1_saw_killed = true
		else:
			_preview_gs.p2_saw_killed = true
	if _saw_accident_owner == (1 if is_p1 else 2):
		_saw_accident_owner = 0
	if not _actor_alive(is_p1):
		return
	# 本編と同じ死亡原因フラグを渡し、壁衝突だけを即時ラグドールへ分岐させる。
	# 海落下は従来の死亡演出を維持する。
	_set_actor_wall_impact(is_p1, reason == "crash")
	_push_walls_away_from_player(_actor_local_z(is_p1))
	_separate_blocking_wall(bundle, is_p1)
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
	bundle.ai_state = AI_STATE_DEAD
	bundle.lane_shift_active = false
	bundle.depth_shift_active = false
	bundle.vel_x = 0.0
	bundle.vel_z = 0.0
	bundle.dodge_until = -1.0
	bundle.ghost_mode = MenuPreviewActorAIStateScript.GHOST_MODE_NONE
	bundle.blocking_wall = null
	_clear_pending_accident(bundle)
	bundle.dead_end_t = _ai_time + _ai.death_duration(reason)
	_ai_emotes.begin_survivor_taunt(is_p1)
	if _ghost:
		_ghost.on_actor_died(is_p1, reason)


## 激突した壁を相手から離して砕く（倒れたランナーの上に壁が重ならないように）。
func _separate_blocking_wall(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	var wall := bundle.blocking_wall
	if not wall or not is_instance_valid(wall) or not _preview_gs:
		return
	wall.position.z = _actor_local_z(is_p1) - PREVIEW_WALL_PUSH_BACK_Z
	wall.set_meta("preview_door_broken", true)
	wall.set_meta("preview_collision_processed", true)
	if wall.visible and wall.has_method("shatter_wall"):
		wall.shatter_wall(PREVIEW_WALL_SHATTER_DIR_Z)
	wall.visible = false


func _push_walls_away_from_player(player_local_z: float) -> void:
	var back_z := player_local_z - PREVIEW_WALL_PUSH_BACK_Z
	var ahead_z := player_local_z + PREVIEW_WALL_PLAYER_CLEAR_Z
	for wall in _preview_walls:
		if not is_instance_valid(wall):
			continue
		if _accidents.wall_reserved_for_crash(wall):
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
	if _ghost:
		_ghost.on_player_controller_rebuilt(_preview_player as PlayerController)

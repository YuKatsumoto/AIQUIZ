extends Node3D

## カメラ制御
## Python版 renderer.py の _camera() メソッドに相当
## 1P: 固定三人称追従視点
## 2P: 俯瞰視点
## ゲームオーバー: ズームアウト + シェイク
## フライオーバー: 10問モード開始時の壁全体俯瞰

@onready var camera: Camera3D = $Camera3D

var _time: float = 0.0
var _go_timer: float = 0.0
var _prev_state: String = ""
var _entry_start_eye: Vector3 = Vector3.ZERO
var _entry_start_look: Vector3 = Vector3.ZERO
var _entry_start_quat: Quaternion = Quaternion.IDENTITY
var _entry_start_fov: float = 44.0
var _entry_start_h_offset: float = 0.0
var _entry_blend_active: bool = false
var _entry_blend_t: float = 0.0
var _ocean_attack_focus: Vector3 = Vector3.ZERO
var _has_ocean_attack_focus: bool = false
var _ocean_attack_camera_active: bool = false
var _ocean_attack_player_index: int = 1
var _ocean_attack_intensity: float = 0.0
var _ocean_attack_impact_timer: float = 0.0
var _tutorial_override_active: bool = false
var _tutorial_override_eye: Vector3 = Vector3.ZERO
var _tutorial_override_target: Vector3 = Vector3.ZERO
var _tutorial_override_fov: float = 50.0
var _result_camera_active: bool = false
var _result_camera_phase: int = QuizGameState.ResultCeremonyPhase.NONE
var _result_winner_start_eye := Vector3.ZERO
var _result_winner_start_rotation := Quaternion.IDENTITY
var _result_winner_start_fov := 44.0
var _result_shake_time := 0.0
var _rear_back_ready: bool = false
var _smoothed_rear_back: float = 9.0
var _question_framing_points := PackedVector3Array()
var _question_pitch: float = 0.0
var _question_back: float = 0.0
var _saw_back: float = 0.0
var saw_dock_framing: float = 0.0
var _final_death_player: int = 0
var _final_death_focus := Vector3.ZERO
var _final_death_exploded: bool = false

const QUESTION_SCREEN_MARGIN := 0.08
const QUESTION_FRAMING_FOLLOW := 8.0
const SAW_FRAMING_FOLLOW := 2.5
const SAW_FRAMING_MAX_SPEED := 10.0
const SAW_FRAMING_START_DISTANCE := 8.0
const SAW_FRAMING_FULL_DISTANCE := 4.0
const SAW_SCREEN_SIDE_MARGIN := 0.01

const ENTRY_BLEND_DURATION := 0.95
const PRELOAD_CAMERA_FOV := 66.0
const THIRD_PERSON_FOV := 50.0
const THIRD_PERSON_DISTANCE := 5.6
const THIRD_PERSON_FOCUS_HEIGHT := 1.0
const THIRD_PERSON_BASE_HEIGHT := 2.0
const SOLO_TUTORIAL_CAMERA_HEIGHT_OFFSET := -1.0
const SOLO_TUTORIAL_CAMERA_TARGET_HEIGHT_OFFSET := -2.7
const TUTORIAL_HAZARD_SPLIT_FOV_START_DISTANCE := 7.0
const TUTORIAL_HAZARD_SPLIT_FOV_FULL_DISTANCE := 18.0
const TUTORIAL_HAZARD_SPLIT_MAX_FOV := 68.0
const TUTORIAL_HAZARD_SPLIT_CAMERA_BACK_DISTANCE := 12.5
const TUTORIAL_HAZARD_SPLIT_CAMERA_LOOK_AHEAD := 5.0
const TWO_PLAYER_FOV := 50.0
const TWO_PLAYER_EYE_Y := 4.5
const TWO_PLAYER_LOOK_Y := 1.0
const TWO_PLAYER_LOOK_AHEAD := 8.0
const TWO_PLAYER_CAMERA_BACK := 9.0
const TWO_PLAYER_REAR_PULL_START_DISTANCE := 3.5
const TWO_PLAYER_REAR_PULL_FULL_DISTANCE := 0.5
const TWO_PLAYER_REAR_MAX_BACK := 13.0
const TWO_PLAYER_REAR_BLEND_SPEED := 1.2

func _ready() -> void:
	if not camera:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.current = true
	camera.fov = 44.0
	camera.near = 0.1
	# Include the Blender-authored harbor islands across the open water.
	camera.far = 5000.0
	_consume_transition_camera_pose()

func set_ocean_attack_focus(
	shark_position: Vector3,
	attack_intensity: float = 0.0,
	player_index: int = 1
) -> void:
	_ocean_attack_focus = shark_position
	_ocean_attack_intensity = clampf(attack_intensity, 0.0, 1.0)
	_ocean_attack_player_index = clampi(player_index, 1, 2)
	_has_ocean_attack_focus = true


func clear_ocean_attack_focus(keep_focus: bool = false) -> void:
	if keep_focus:
		return
	_has_ocean_attack_focus = false
	_ocean_attack_intensity = 0.0


func trigger_ocean_attack_impact() -> void:
	_ocean_attack_impact_timer = 0.35


func set_tutorial_override_pose(eye: Vector3, target: Vector3, fov: float) -> void:
	_tutorial_override_eye = eye
	_tutorial_override_target = target
	_tutorial_override_fov = clampf(fov, 38.0, 72.0)
	_tutorial_override_active = true


func clear_tutorial_override() -> void:
	_tutorial_override_active = false


## Track the physical body until it bursts, then hold the explosion location.
func set_final_death_focus(player_index: int, focus: Vector3, exploded: bool) -> void:
	if player_index == 0:
		_final_death_player = 0
		_final_death_exploded = false
		return
	if player_index != _final_death_player or not _final_death_exploded:
		_final_death_focus = focus
	_final_death_player = player_index
	_final_death_exploded = exploded


func _third_person_camera_height(gs: QuizGameState) -> float:
	return THIRD_PERSON_BASE_HEIGHT + (
		SOLO_TUTORIAL_CAMERA_HEIGHT_OFFSET if gs.is_solo_tutorial() else 0.0
	)


func _third_person_camera_target(gs: QuizGameState, focus: Vector3) -> Vector3:
	var height_offset: float = (
		SOLO_TUTORIAL_CAMERA_TARGET_HEIGHT_OFFSET if gs.is_solo_tutorial() else 0.0
	)
	return focus + Vector3.BACK * 8.0 + Vector3.UP * height_offset


func get_gameplay_pose(gs: QuizGameState) -> Dictionary:
	if gs.num_players >= 2:
		var z_focus: float = gs.player_local_z
		if gs.p1_alive and gs.p2_alive:
			z_focus = (gs.player_local_z + gs.player2_local_z) * 0.5
		elif gs.p2_alive:
			z_focus = gs.player2_local_z
		var back := _two_player_rear_back_distance(gs)
		return {
			"eye": Vector3(0.0, TWO_PLAYER_EYE_Y, z_focus - back),
			"target": Vector3(
				0.0,
				TWO_PLAYER_LOOK_Y,
				z_focus + TWO_PLAYER_LOOK_AHEAD
			),
			"fov": TWO_PLAYER_FOV,
		}
	var focus := Vector3(
		gs.player_x,
		gs.player_y + THIRD_PERSON_FOCUS_HEIGHT,
		gs.player_local_z
	)
	return {
		"eye": focus - Vector3.BACK * THIRD_PERSON_DISTANCE + Vector3.UP * _third_person_camera_height(gs),
		"target": _third_person_camera_target(gs, focus),
		"fov": THIRD_PERSON_FOV,
	}


## 2Pでうしろのコンベアローラー端へ近づくほどカメラを後ろへ離し、落下が読めるようにする。
func _two_player_rear_pull_ratio(gs: QuizGameState) -> float:
	var clearance := _two_player_rear_clearance(gs)
	var span := TWO_PLAYER_REAR_PULL_START_DISTANCE - TWO_PLAYER_REAR_PULL_FULL_DISTANCE
	var ratio := 0.0
	if span > 0.0001:
		ratio = clampf(
			(TWO_PLAYER_REAR_PULL_START_DISTANCE - clearance) / span,
			0.0,
			1.0
		)
	return ratio


func _two_player_rear_back_distance(gs: QuizGameState) -> float:
	return lerpf(TWO_PLAYER_CAMERA_BACK, TWO_PLAYER_REAR_MAX_BACK, _two_player_rear_pull_ratio(gs))


func _update_smoothed_rear_back(gs: QuizGameState, dt: float) -> float:
	var target_back := _two_player_rear_back_distance(gs)
	if not _rear_back_ready:
		_smoothed_rear_back = target_back
		_rear_back_ready = true
		return _smoothed_rear_back
	if dt > 0.0:
		var follow := 1.0 - exp(-TWO_PLAYER_REAR_BLEND_SPEED * dt)
		_smoothed_rear_back = lerpf(_smoothed_rear_back, target_back, follow)
	return _smoothed_rear_back


func _two_player_gameplay_fov(gs: QuizGameState) -> float:
	if not (
		gs.tutorial_splits_camera()
		and gs.p1_alive
		and gs.p2_alive
	):
		return TWO_PLAYER_FOV
	var player_separation := absf(gs.player_local_z - gs.player2_local_z)
	var separation_span := (
		TUTORIAL_HAZARD_SPLIT_FOV_FULL_DISTANCE
		- TUTORIAL_HAZARD_SPLIT_FOV_START_DISTANCE
	)
	var separation_ratio := 0.0
	if separation_span > 0.0001:
		separation_ratio = clampf(
			(player_separation - TUTORIAL_HAZARD_SPLIT_FOV_START_DISTANCE) / separation_span,
			0.0,
			1.0
		)
	return lerpf(TWO_PLAYER_FOV, TUTORIAL_HAZARD_SPLIT_MAX_FOV, separation_ratio)


func _two_player_rear_clearance(gs: QuizGameState) -> float:
	var clearance := INF
	if gs.p1_alive and not gs.p1_waiting_for_shark:
		clearance = minf(clearance, gs.player_local_z - StageConstants.FLOOR_BACK_Z)
	if gs.p2_alive and not gs.p2_waiting_for_shark:
		clearance = minf(clearance, gs.player2_local_z - StageConstants.FLOOR_BACK_Z)
	if not is_finite(clearance):
		return TWO_PLAYER_REAR_PULL_START_DISTANCE
	return clearance


func wait_for_entry_blend() -> void:
	if not _entry_blend_active:
		return
	while _entry_blend_active and is_inside_tree():
		await get_tree().process_frame

func update_camera(gs: QuizGameState, dt: float) -> void:
	if gs.game_state not in [Constants.STATE_PLAYING, Constants.STATE_CORRECT] or _tutorial_override_active or _ocean_attack_camera_active:
		_question_pitch = 0.0
		_question_back = 0.0
		_saw_back = 0.0
	# フライオーバー→カウントダウン遷移時にbobタイマーをリセット
	# (bobが途中の位相だとカメラのY座標がジャンプするため)
	if _prev_state == Constants.STATE_FLYOVER and gs.game_state != Constants.STATE_FLYOVER:
		_time = 0.0
	_prev_state = gs.game_state

	_time += dt
	_ocean_attack_impact_timer = maxf(0.0, _ocean_attack_impact_timer - dt)
	var bob: float = sin(_time * 1.2) * 0.04

	var eye: Vector3
	var target: Vector3
	var fov: float = 44.0
	if _tutorial_override_active:
		camera.h_offset = 0.0
		camera.fov = _tutorial_override_fov
		camera.global_position = _tutorial_override_eye
		camera.look_at(_tutorial_override_target, Vector3.UP)
		return

	# Clear the ceremony latch before any early-return camera mode (especially
	# PRELOADING on retry) so the next round never inherits the fixed result shot.
	if not (
		gs.result_presentation_active
		and gs.game_state in [Constants.STATE_RESULT_CEREMONY, Constants.STATE_CLEAR]
	):
		_result_camera_active = false
		_result_camera_phase = QuizGameState.ResultCeremonyPhase.NONE

	# === PRELOADING / WAITING_START: 俯瞰オービットカメラ ===
	if gs.game_state in [
		Constants.STATE_PRELOADING,
		Constants.STATE_WAITING_START,
	]:
		_update_preload_camera(gs, dt)
		return

	# === FLYOVER: 10問モードの壁全体俯瞰演出 ===
	if gs.game_state == Constants.STATE_FLYOVER:
		_update_flyover_camera(gs, dt)
		return

	if (
		gs.result_presentation_active
		and gs.game_state in [Constants.STATE_RESULT_CEREMONY, Constants.STATE_CLEAR]
	):
		_update_result_ceremony_camera(gs, dt)
		return
	_result_camera_active = false
	_result_camera_phase = QuizGameState.ResultCeremonyPhase.NONE

	# 1Pではサメの到達後も、ゲームオーバー中はサメ追従カメラを維持する。
	# 2Pは生存者がいる間だけ DeathWipe を使い、最後の1人が落ちたらメインカメラへ切り替える。
	var final_coop_ocean_wait: bool = false
	if gs.num_players >= 2:
		if gs.p1_waiting_for_shark and not gs.p2_alive:
			final_coop_ocean_wait = true
			_ocean_attack_player_index = 1
		elif gs.p2_waiting_for_shark and not gs.p1_alive:
			final_coop_ocean_wait = true
			_ocean_attack_player_index = 2
	var final_coop_ocean_game_over: bool = (
		gs.num_players >= 2
		and _final_death_player == 0
		and not gs.p1_alive
		and not gs.p2_alive
		and gs.game_state == Constants.STATE_GAME_OVER
		and (gs.p1_shark_killed or gs.p2_shark_killed)
		and _ocean_attack_camera_active
	)
	var ocean_attack_active: bool = final_coop_ocean_wait or final_coop_ocean_game_over or (
		gs.num_players < 2
		and (
			gs.p1_waiting_for_shark
			or (
				gs.p1_shark_killed
				and not gs.p1_alive
				and gs.game_state == Constants.STATE_GAME_OVER
			)
		)
	)
	if ocean_attack_active:
		_update_ocean_attack_camera(gs, dt)
		return
	_ocean_attack_camera_active = false

	if gs.num_players >= 2:
		# === 2-PLAYER: top-down view ===
		fov = TWO_PLAYER_FOV
		# 海やゴーストの練習ステップでは片方が待機し、2人が意図的に離れる。
		# 離れるほど画角を広げ、待機側が画面外へ切れないようにする。
		var tutorial_hazard_split: bool = (
			gs.tutorial_splits_camera()
			and gs.p1_alive
			and gs.p2_alive
		)
		var all_dead: bool = not gs.p1_alive and not gs.p2_alive
		var z_focus: float = gs.player_local_z
		if gs.p1_alive and gs.p2_alive:
			z_focus = (gs.player_local_z + gs.player2_local_z) / 2.0
		elif gs.p2_alive:
			z_focus = gs.player2_local_z

		if all_dead and gs.game_state == Constants.STATE_GAME_OVER:
			_go_timer += dt
			var t_val: float = minf(1.0, _go_timer * 0.5)
			var ease_t: float = 1.0 - pow(1.0 - t_val, 3)
			var dist: float = ease_t * 8.0

			var decay_shake: float = maxf(0.0, 1.0 - _go_timer * 0.8) * 1.5
			var sx: float = (randf() - 0.5) * decay_shake
			var sy: float = (randf() - 0.5) * decay_shake

			# Find the last player who died (the one with the smaller death timer)
			var target_px: float = gs.player_x
			var target_py: float = gs.player_y
			var target_pz: float = gs.player_local_z
			if gs.player2_game_over_timer < gs.game_over_timer:
				target_px = gs.player2_x
				target_py = gs.player2_y
				target_pz = gs.player2_local_z
			if _final_death_player != 0:
				target_px = _final_death_focus.x
				target_py = _final_death_focus.y - 0.5
				target_pz = _final_death_focus.z
				# Leave room for the whole tumbling body even on the first frame.
				dist = maxf(dist, THIRD_PERSON_DISTANCE)

			eye = Vector3(
				target_px + sx,
				target_py + 1.2 + bob + ease_t * 4.0 + sy,
				target_pz - dist)
			target = Vector3(
				target_px + sx * 0.5,
				target_py + 0.5 + sy * 0.5,
				target_pz)
		else:
			_go_timer = 0.0
			fov = _two_player_gameplay_fov(gs)
			if tutorial_hazard_split:
				# Pull back and aim nearer the midpoint; the normal camera looks farther
				# ahead and would push the stationary player below the bottom edge.
				eye = Vector3(
					0.0,
					4.5 + bob,
					z_focus - TUTORIAL_HAZARD_SPLIT_CAMERA_BACK_DISTANCE
				)
				target = Vector3(
					0.0,
					1.0,
					z_focus + TUTORIAL_HAZARD_SPLIT_CAMERA_LOOK_AHEAD
				)
			else:
				var back := _update_smoothed_rear_back(gs, dt)
				eye = Vector3(0.0, TWO_PLAYER_EYE_Y + bob, z_focus - back)
				target = Vector3(
					0.0,
					TWO_PLAYER_LOOK_Y,
					z_focus + TWO_PLAYER_LOOK_AHEAD
				)
	else:
		# === 1-PLAYER: fixed third-person follow view ===
		fov = THIRD_PERSON_FOV
		var all_dead: bool = not gs.p1_alive

		if all_dead and gs.game_state == Constants.STATE_GAME_OVER:
			_go_timer += dt
			var t_val: float = minf(1.0, _go_timer * 0.5)
			var ease_t: float = 1.0 - pow(1.0 - t_val, 3)
			var dist: float = ease_t * 8.0

			var decay_shake: float = maxf(0.0, 1.0 - _go_timer * 0.8) * 1.5
			var sx: float = (randf() - 0.5) * decay_shake
			var sy: float = (randf() - 0.5) * decay_shake

			eye = Vector3(
				gs.player_x + sx,
				gs.player_y + 1.2 + bob + ease_t * 4.0 + sy,
				gs.player_local_z - dist)
			target = Vector3(
				gs.player_x + sx * 0.5,
				gs.player_y + 0.5 + sy * 0.5,
				gs.player_local_z)
		else:
			_go_timer = 0.0
			var focus: Vector3 = Vector3(
				gs.player_x,
				gs.player_y + THIRD_PERSON_FOCUS_HEIGHT + bob,
				gs.player_local_z
			)
			eye = focus - Vector3.BACK * THIRD_PERSON_DISTANCE
			eye += Vector3.UP * _third_person_camera_height(gs)
			target = _third_person_camera_target(gs, focus)

	var question_pose := _frame_question(gs, eye, target, fov, dt)
	eye = question_pose[0]
	target = question_pose[1]
	var saw_pose := _frame_saw(gs, eye, target, fov, dt)
	eye = saw_pose[0]
	target = saw_pose[1]

	# Apply camera shake
	if gs.camera_shake > 0.0:
		var shake_ox: float = (randf() - 0.5) * gs.camera_shake
		var shake_oy: float = (randf() - 0.5) * gs.camera_shake
		var shake_oz: float = (randf() - 0.5) * gs.camera_shake
		eye.x += shake_ox
		eye.y += shake_oy
		eye.z += shake_oz
		target.x += shake_ox * 0.5
		target.y += shake_oy * 0.5

	camera.fov = fov
	camera.global_position = eye
	camera.look_at(target, Vector3.UP)


func set_question_framing_points(points: PackedVector3Array) -> void:
	_question_framing_points = points


## Preserve the normal FOV and yaw. Tilt only by the overflow angle, then
## retreat along the view direction until glyphs and living players fit.
func _frame_question(gs: QuizGameState, eye: Vector3, target: Vector3, fov: float, dt: float) -> PackedVector3Array:
	if _question_framing_points.is_empty() and is_zero_approx(_question_pitch) and is_zero_approx(_question_back):
		return PackedVector3Array([eye, target])
	var follow := 1.0 - exp(-QUESTION_FRAMING_FOLLOW * maxf(dt, 0.0))
	var points := _question_framing_points.duplicate()
	if gs.game_state != Constants.STATE_PLAYING:
		points.clear()
	if not points.is_empty():
		if gs.p1_alive:
			_append_player_framing_points(points, Vector3(gs.player_x, gs.player_y, gs.player_local_z))
		if gs.num_players >= 2 and gs.p2_alive:
			_append_player_framing_points(points, Vector3(gs.player2_x, gs.player2_y, gs.player2_local_z))
	var direction := (target - eye).normalized()
	var distance := eye.distance_to(target)
	var view_basis := Basis.looking_at(direction, Vector3.UP)
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var tan_y := tan(deg_to_rad(fov) * 0.5)
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		tan_y /= aspect
	var safe_y := tan_y * (1.0 - QUESTION_SCREEN_MARGIN * 2.0)
	var safe_x := safe_y * aspect
	var angle_limit := atan(safe_y)
	var min_angle := INF
	var max_angle := -INF
	for point: Vector3 in points:
		var relative := point - eye
		var angle := atan2(relative.dot(view_basis.y), relative.dot(direction))
		min_angle = minf(min_angle, angle)
		max_angle = maxf(max_angle, angle)
	var desired_pitch := 0.0
	if not points.is_empty():
		var lower := max_angle - angle_limit
		var upper := min_angle + angle_limit
		desired_pitch = clampf(0.0, lower, upper) if lower <= upper else (lower + upper) * 0.5
	_question_pitch = lerpf(_question_pitch, desired_pitch, follow)
	direction = direction.rotated(view_basis.x, _question_pitch)
	view_basis = Basis.looking_at(direction, Vector3.UP)
	var required_back := 0.0
	for point: Vector3 in points:
		var relative := point - eye
		var depth := relative.dot(direction)
		required_back = maxf(required_back, absf(relative.dot(view_basis.x)) / safe_x - depth)
		required_back = maxf(required_back, absf(relative.dot(view_basis.y)) / safe_y - depth)
		required_back = maxf(required_back, camera.near + 0.1 - depth)
	# A small lead-in buffer permits smooth following without crossing the 8%
	# safety inset. Release the correction gradually when the next wall is far.
	var desired_back := required_back + (0.35 if required_back > 0.0 else 0.0)
	_question_back = maxf(required_back, lerpf(_question_back, desired_back, follow))
	return PackedVector3Array([eye - direction * _question_back, eye + direction * distance])


## Keep the question camera's height. Begin easing out before the warning
## threshold, then fit the whole carriage by retreating horizontally only.
func _frame_saw(gs: QuizGameState, eye: Vector3, target: Vector3, fov: float, dt: float) -> PackedVector3Array:
	if gs.num_players != 2 or gs.game_state not in [Constants.STATE_PLAYING, Constants.STATE_CORRECT]:
		_saw_back = 0.0
		return PackedVector3Array([eye, target])
	var desired_back := 0.0
	var retreat := (target - eye) * Vector3(1.0, 0.0, 1.0)
	retreat = retreat.normalized()
	var clearance := minf(gs.get_saw_clearance(1), gs.get_saw_clearance(2))
	var weight := 1.0 - smoothstep(SAW_FRAMING_FULL_DISTANCE, SAW_FRAMING_START_DISTANCE, clearance)
	if gs.is_saw_visible() and weight > 0.0:
		var points := _question_framing_points.duplicate() if gs.game_state == Constants.STATE_PLAYING else PackedVector3Array()
		var saw_points_start := points.size()
		var bounds := AABB(Vector3(-12.25, StageConstants.FLOOR_TOP_Y, gs.saw.local_z - 1.7), Vector3(24.5, 0.65, 3.4))
		for corner: int in range(8):
			points.append(bounds.get_endpoint(corner))
		if gs.p1_alive:
			_append_player_framing_points(points, Vector3(gs.player_x, gs.player_y, gs.player_local_z))
		if gs.p2_alive:
			_append_player_framing_points(points, Vector3(gs.player2_x, gs.player2_y, gs.player2_local_z))
		var viewport_size := camera.get_viewport().get_visible_rect().size
		var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
		var safe_y := tan(deg_to_rad(fov) * 0.5) * (1.0 - QUESTION_SCREEN_MARGIN * 2.0)
		if camera.keep_aspect == Camera3D.KEEP_WIDTH:
			safe_y /= aspect
		var safe_x := safe_y * aspect
		# The wide carriage should nearly touch the sides; keep the larger
		# question/player inset only for their own framing points.
		var saw_safe_x := safe_x * (1.0 - SAW_SCREEN_SIDE_MARGIN * 2.0) / (1.0 - QUESTION_SCREEN_MARGIN * 2.0)
		# Looking at the existing target flattens the view as we retreat.
		# Solve the smallest horizontal distance that fits the measured points.
		var lower := 0.0
		var upper := 80.0
		for iteration: int in range(14):
			var back := (lower + upper) * 0.5
			var candidate := eye - retreat * back
			var view := Basis.looking_at(target - candidate, Vector3.UP)
			var fits := true
			for point_index: int in range(points.size()):
				var relative := points[point_index] - candidate
				var depth := -relative.dot(view.z)
				var horizontal_limit := saw_safe_x if point_index >= saw_points_start and point_index < saw_points_start + 8 else safe_x
				if depth < camera.near + 0.1 or absf(relative.dot(view.x)) > depth * horizontal_limit or absf(relative.dot(view.y)) > depth * safe_y:
					fits = false
					break
			if fits:
				upper = back
			else:
				lower = back
		desired_back = (upper + 0.05) * weight
	var follow := 1.0 - exp(-SAW_FRAMING_FOLLOW * maxf(dt, 0.0))
	_saw_back = move_toward(_saw_back, lerpf(_saw_back, desired_back, follow), SAW_FRAMING_MAX_SPEED * maxf(dt, 0.0))
	return PackedVector3Array([eye - retreat * _saw_back, target])


func _append_player_framing_points(points: PackedVector3Array, feet: Vector3) -> void:
	var bounds := AABB(feet + Vector3(-0.65, -0.1, -0.4), Vector3(1.3, 2.9, 0.8))
	for corner: int in range(8):
		points.append(bounds.get_endpoint(corner))


func _update_result_ceremony_camera(gs: QuizGameState, dt: float) -> void:
	var phase := gs.result_ceremony_phase
	# The Blender camera that composed the Score Tower Finale owns the whole shot.
	# It is symmetric until the verdict, then favours the winner; a P2 win mirrors
	# stage and camera together. After the last key it holds the final frame.
	var draw := gs.result_winner == 0
	var sample := ResultFinaleMotion.sample_camera(draw, minf(gs.result_ceremony_elapsed, ResultFinaleMotion.end_time()))
	var local_pose: Transform3D = sample.transform
	var mirror := Vector3(-1, 1, 1) if gs.result_winner == 2 else Vector3.ONE
	var stage_basis := Basis(Vector3.UP, PI).scaled(mirror)
	var stage_origin := ResultCeremonyDirector.stage_origin(gs)
	var target_eye := stage_origin + stage_basis * local_pose.origin
	var forward := -(stage_basis * local_pose.basis.z).normalized()
	var up := (stage_basis * local_pose.basis.y).normalized()
	var target_rotation := Basis.looking_at(forward, up).get_rotation_quaternion()
	var target_fov: float = sample.fov
	# The verdict slam shakes the lens briefly (decays in QuizGameState).
	if gs.camera_shake > 0.001:
		_result_shake_time += maxf(dt, 0.0)
		var amount := gs.camera_shake * 0.06
		target_eye += Vector3(sin(_result_shake_time * 57.0), cos(_result_shake_time * 43.0), 0.0) * amount
	# Preserve horizontal composition on 4:3 screens, including tall hats.
	var aspect := get_viewport().get_visible_rect().size.aspect()
	target_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(target_fov) * 0.5) * maxf(1.0, (16.0 / 9.0) / aspect)))
	if not _result_camera_active:
		_result_winner_start_eye = camera.global_position
		_result_winner_start_rotation = camera.global_basis.get_rotation_quaternion()
		_result_winner_start_fov = camera.fov
		_result_camera_active = true
	_result_camera_phase = phase
	var entry := smoothstep(0.0, QuizGameState.RESULT_ASSEMBLE_DURATION, gs.result_ceremony_elapsed)
	var eye := _result_winner_start_eye.lerp(target_eye, entry)
	var rotation := _result_winner_start_rotation.slerp(target_rotation, entry)
	camera.global_transform = Transform3D(Basis(rotation), eye)
	camera.fov = lerpf(_result_winner_start_fov, target_fov, entry)
	camera.h_offset = 0.0


## フライオーバーカメラ演出 (2フェーズ)
## Phase 1 (0.0–0.55): 最後の壁から後方まで一気に止まらず飛行（+Z方向を向いたまま）
## Phase 2 (0.55–1.0): 後方から三人称追従視点へゆっくり復帰
func get_ocean_attack_camera_pose(
	player_position: Vector3,
	shark_position: Vector3,
	has_shark_focus: bool,
	_attack_intensity: float = 0.0
) -> Dictionary:
	var resolved_shark_position: Vector3 = shark_position
	if not has_shark_focus:
		var outward_sign: float = signf(player_position.x)
		if is_zero_approx(outward_sign):
			outward_sign = 1.0
		resolved_shark_position = player_position + Vector3(outward_sign * 15.0, -1.0, -8.0)

	var separation: float = clampf(
		player_position.distance_to(resolved_shark_position),
		4.0,
		34.0
	)
	var same_side_of_stage: bool = (
		absf(player_position.x) >= StageConstants.FLOOR_HALF_WIDTH
		and absf(resolved_shark_position.x) >= StageConstants.FLOOR_HALF_WIDTH
		and signf(player_position.x) == signf(resolved_shark_position.x)
	)
	var framing_anchor: Vector3 = player_position
	if has_shark_focus and same_side_of_stage:
		framing_anchor = player_position.lerp(resolved_shark_position, 0.5)

	var orbit_distance: float = 9.0 + separation * 0.14
	var vertical_lift: float = 7.0 + separation * 0.11
	var desired_eye: Vector3 = framing_anchor + Vector3(0.0, vertical_lift, -7.0)
	var floor_half_length: float = StageConstants.GAME_FLOOR_LENGTH * 0.5
	var floor_min_z: float = StageConstants.GAME_FLOOR_CENTER_Z - floor_half_length
	var floor_max_z: float = StageConstants.GAME_FLOOR_CENTER_Z + floor_half_length
	if absf(player_position.x) >= StageConstants.FLOOR_HALF_WIDTH:
		desired_eye.x += signf(player_position.x) * orbit_distance
	elif player_position.z >= floor_max_z or player_position.z <= floor_min_z:
		var outward_z: float = signf(player_position.z - StageConstants.GAME_FLOOR_CENTER_Z)
		desired_eye.z += outward_z * orbit_distance
	else:
		var approach: Vector3 = resolved_shark_position - player_position
		var horizontal: Vector3 = Vector3(approach.x, 0.0, approach.z)
		if horizontal.length_squared() < 0.01:
			horizontal = Vector3.FORWARD
		horizontal = horizontal.normalized()
		var camera_side: Vector3 = Vector3(-horizontal.z, 0.0, horizontal.x)
		desired_eye += camera_side * orbit_distance

	return {
		"eye": desired_eye,
		"target": framing_anchor + Vector3(0.0, -0.45, 0.0),
	}


func _update_ocean_attack_camera(gs: QuizGameState, dt: float) -> void:
	var player_position: Vector3
	if gs.num_players < 2 or _ocean_attack_player_index == 1:
		player_position = Vector3(gs.player_x, gs.player_y + 0.65, gs.player_local_z)
	else:
		player_position = Vector3(gs.player2_x, gs.player2_y + 0.65, gs.player2_local_z)

	var pose: Dictionary = get_ocean_attack_camera_pose(
		player_position,
		_ocean_attack_focus,
		_has_ocean_attack_focus,
		_ocean_attack_intensity
	)
	var desired_eye: Vector3 = pose.get("eye", camera.global_position)
	var desired_target: Vector3 = pose.get("target", player_position)
	var impact_strength: float = clampf(_ocean_attack_impact_timer / 0.35, 0.0, 1.0)
	var shake_strength: float = 0.10 * pow(_ocean_attack_intensity, 2.0) + 0.38 * impact_strength
	var shake_offset: Vector3 = Vector3(
		sin(_time * 31.0),
		cos(_time * 43.0),
		sin(_time * 37.0 + 0.8)
	) * shake_strength
	desired_eye += shake_offset
	desired_target += shake_offset * 0.24
	var blend: float = clampf(dt * 4.5, 0.0, 1.0)
	camera.h_offset = 0.0
	if not _ocean_attack_camera_active:
		camera.global_position = desired_eye
		_ocean_attack_camera_active = true
	else:
		camera.global_position = camera.global_position.lerp(desired_eye, blend)
	camera.look_at(desired_target, Vector3.UP)


func _update_flyover_camera(gs: QuizGameState, _dt: float) -> void:
	var t := gs.tuning
	var progress: float = clampf(gs.flyover_timer / gs.flyover_duration, 0.0, 1.0)

	# カメラ開始位置の基準壁数（10問モードと同じ位置から開始）
	var camera_walls: int = mini(gs.flyover_total_walls, 10)
	var camera_start_z: float = t.wall_start_z + (camera_walls - 1) * t.wall_spacing
	# --- 終着点: 1P=三人称追従 / 2P=俯瞰 ---
	var end_pos: Vector3
	var end_look: Vector3
	var end_fov: float
	if gs.num_players >= 2:
		# 2P: 標準の三人称俯瞰カメラ（通常カメラと同一のz_focus計算を使用）
		var z_focus: float = gs.player_local_z
		if gs.p1_alive and gs.p2_alive:
			z_focus = (gs.player_local_z + gs.player2_local_z) / 2.0
		elif gs.p2_alive:
			z_focus = gs.player2_local_z
		end_pos = Vector3(0.0, 4.5, z_focus - 9.0)
		end_look = Vector3(0.0, 1.0, z_focus + 8.0)
		end_fov = TWO_PLAYER_FOV
	else:
		# 1P: 通常プレイと同じ三人称追従視点
		var focus: Vector3 = Vector3(
			gs.player_x,
			gs.player_y + THIRD_PERSON_FOCUS_HEIGHT,
			gs.player_local_z
		)
		end_pos = focus - Vector3.BACK * THIRD_PERSON_DISTANCE
		end_pos += Vector3.UP * _third_person_camera_height(gs)
		end_look = _third_person_camera_target(gs, focus)
		end_fov = THIRD_PERSON_FOV

	# --- キーポイント ---
	# 1P/2P共通: 最後の壁から開始
	var flyover_start_z: float = camera_start_z + 8.0
	var start_pos := Vector3(0.0, 6.0, flyover_start_z)
	
	# オフセット距離。最終視点からカメラが真っ直ぐ引く距離
	var pullback_distance := 14.0
	
	# 最終視点の方向ベクトル（カメラがどちらを向くか）
	var view_dir := (end_look - end_pos).normalized()
	
	# オーバーシュート（一番後ろに下がる点）は、最終位置から視線ベクトルの逆方向へ真っ直ぐ引いた位置とする。
	# これにより、Phase 2 は純粋なドリー・イン（真っ直ぐな接近）となり、視点のズレが一切発生しなくなる。
	var overshoot_pos := end_pos - view_dir * pullback_distance
	var overshoot_look := end_look - view_dir * pullback_distance

	# 開始時の視線(ふんわり前を向く)
	var start_look := start_pos + Vector3(0.0, -0.6, 20.0)

	var eye: Vector3
	var look_target: Vector3
	var fov: float

	if progress < 1.0:
		var eased: float = _ease_smooth(progress)
		eye = overshoot_pos.lerp(end_pos, eased)
		look_target = overshoot_look.lerp(end_look, eased)
		fov = lerpf(66.0, end_fov, eased)
	else:
		eye = end_pos
		look_target = end_look
		fov = end_fov

	camera.fov = fov
	camera.global_position = eye
	camera.look_at(look_target, Vector3.UP)


func _update_preload_camera(gs: QuizGameState, _dt: float) -> void:
	var end_pos: Vector3
	var end_look: Vector3
	
	if gs.num_players >= 2:
		var z_focus: float = gs.player_local_z
		if gs.p1_alive and gs.p2_alive:
			z_focus = (gs.player_local_z + gs.player2_local_z) / 2.0
		elif gs.p2_alive:
			z_focus = gs.player2_local_z
		end_pos = Vector3(0.0, 4.5, z_focus - 9.0)
		end_look = Vector3(0.0, 1.0, z_focus + 8.0)
	else:
		var focus: Vector3 = Vector3(
			gs.player_x,
			gs.player_y + THIRD_PERSON_FOCUS_HEIGHT,
			gs.player_local_z
		)
		end_pos = focus - Vector3.BACK * THIRD_PERSON_DISTANCE
		end_pos += Vector3.UP * _third_person_camera_height(gs)
		end_look = _third_person_camera_target(gs, focus)

	# Keep the original preparation shot. A small lift/backward offset gives
	# the rail handoff room without a separate wide shot of the vessel.
	var vessel_weight := clampf(saw_dock_framing, 0.0, 1.0)
	var view_dir := (end_look - end_pos).normalized()
	var target_eye := end_pos - view_dir * (14.0 + 1.5 * vessel_weight) + Vector3.UP * (0.5 * vessel_weight)
	var target_look := end_look - view_dir * 14.0
	var target_quat := _quat_look_at(target_eye, target_look)
	var eye := target_eye
	var look_at_pos := target_look
	var fov := PRELOAD_CAMERA_FOV
	var h_offset := 0.0

	if _entry_blend_active:
		_entry_blend_t += _dt
		var progress: float = clampf(_entry_blend_t / ENTRY_BLEND_DURATION, 0.0, 1.0)
		var eased: float = _ease_smooth(progress)
		eye = _entry_start_eye.lerp(target_eye, eased)
		camera.quaternion = _entry_start_quat.slerp(target_quat, eased)
		fov = lerpf(_entry_start_fov, PRELOAD_CAMERA_FOV, eased)
		h_offset = lerpf(_entry_start_h_offset, 0.0, eased)
		if progress >= 1.0:
			_entry_blend_active = false
			look_at_pos = target_look
	else:
		camera.quaternion = target_quat

	if gs.camera_shake > 0.0:
		var shake_ox: float = (randf() - 0.5) * gs.camera_shake
		var shake_oy: float = (randf() - 0.5) * gs.camera_shake
		var shake_oz: float = (randf() - 0.5) * gs.camera_shake
		eye.x += shake_ox
		eye.y += shake_oy
		eye.z += shake_oz
		look_at_pos.x += shake_ox * 0.5
		look_at_pos.y += shake_oy * 0.5

	camera.fov = fov
	camera.h_offset = h_offset
	camera.global_position = eye
	if not _entry_blend_active:
		camera.look_at(look_at_pos, Vector3.UP)

func _consume_transition_camera_pose() -> void:
	var pose: Dictionary = SceneTransition.consume_start_camera_pose()
	if pose.is_empty():
		return
	var eye: Variant = pose.get("eye", Vector3.ZERO)
	var look: Variant = pose.get("look", Vector3.ZERO)
	if not (eye is Vector3 and look is Vector3):
		return
	_entry_start_eye = eye
	_entry_start_look = look
	_entry_start_quat = _quat_look_at(_entry_start_eye, _entry_start_look)
	_entry_start_fov = float(pose.get("fov", camera.fov))
	_entry_start_h_offset = float(pose.get("h_offset", camera.h_offset))
	_entry_blend_active = true
	_entry_blend_t = 0.0
	camera.global_position = _entry_start_eye
	camera.quaternion = _entry_start_quat
	camera.fov = _entry_start_fov
	camera.h_offset = _entry_start_h_offset


func _quat_look_at(origin: Vector3, look_target: Vector3) -> Quaternion:
	var dir: Vector3 = origin.direction_to(look_target)
	if dir.length_squared() < 1e-8:
		return Quaternion.IDENTITY
	var up: Vector3 = Vector3.UP
	if absf(dir.dot(up)) > 0.998:
		up = Vector3.RIGHT
	var z_axis: Vector3 = -dir
	var x_axis: Vector3 = up.cross(z_axis)
	if x_axis.length_squared() < 1e-8:
		x_axis = Vector3.FORWARD.cross(z_axis)
	x_axis = x_axis.normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).get_rotation_quaternion()


## Quintic ease-in-out (滑らかな加速/減速)
func _ease_smooth(x: float) -> float:
	if x < 0.5:
		return 16.0 * x * x * x * x * x
	var f: float = (2.0 * x - 2.0)
	return 0.5 * f * f * f * f * f + 1.0

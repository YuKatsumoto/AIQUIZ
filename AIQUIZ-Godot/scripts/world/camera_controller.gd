extends Node3D

## カメラ制御
## Python版 renderer.py の _camera() メソッドに相当
## 1P: FPS視点 (マウスルック)
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
var _ocean_attack_intensity: float = 0.0
var _ocean_attack_impact_timer: float = 0.0

const ENTRY_BLEND_DURATION := 0.95
const PRELOAD_CAMERA_FOV := 66.0

func _ready() -> void:
	if not camera:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.current = true
	camera.fov = 44.0
	camera.near = 0.1
	camera.far = 500.0
	_consume_transition_camera_pose()

func set_ocean_attack_focus(shark_position: Vector3, attack_intensity: float = 0.0) -> void:
	_ocean_attack_focus = shark_position
	_ocean_attack_intensity = clampf(attack_intensity, 0.0, 1.0)
	_has_ocean_attack_focus = true


func clear_ocean_attack_focus() -> void:
	_has_ocean_attack_focus = false
	_ocean_attack_intensity = 0.0


func trigger_ocean_attack_impact() -> void:
	_ocean_attack_impact_timer = 0.35


func wait_for_entry_blend() -> void:
	if not _entry_blend_active:
		return
	while _entry_blend_active and is_inside_tree():
		await get_tree().process_frame

func update_camera(gs: QuizGameState, dt: float) -> void:
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

	# === PRELOADING / WAITING_START: 俯瞰オービットカメラ ===
	if gs.game_state in [Constants.STATE_PRELOADING, Constants.STATE_WAITING_START]:
		_update_preload_camera(gs, dt)
		return

	# === FLYOVER: 10問モードの壁全体俯瞰演出 ===
	if gs.game_state == Constants.STATE_FLYOVER:
		_update_flyover_camera(gs, dt)
		return

	# 2P中のサメ演出は DeathWipe の専用カメラだけで表示する。
	# 生存中のプレイヤーのメイン画面を、落下側の演出で奪わない。
	var ocean_attack_active: bool = (
		gs.num_players < 2
		and gs.p1_waiting_for_shark
	)
	if ocean_attack_active:
		_update_ocean_attack_camera(gs, dt)
		return
	_ocean_attack_camera_active = false

	if gs.num_players >= 2:
		# === 2-PLAYER: top-down view ===
		fov = 50.0
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
			eye = Vector3(0.0, 4.5 + bob, z_focus - 9.0)
			target = Vector3(0.0, 1.0, z_focus + 8.0)
	else:
		# === 1-PLAYER: FPS view ===
		fov = 44.0
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
			var yaw: float = gs.camera_yaw
			var pitch: float = gs.camera_pitch
			var dx: float = sin(yaw) * cos(pitch)
			var dy: float = sin(pitch)
			var dz: float = cos(yaw) * cos(pitch)
			eye = Vector3(gs.player_x, gs.player_y + 1.2 + bob, gs.player_local_z)
			target = eye + Vector3(dx, dy, dz) * 10.0

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


## フライオーバーカメラ演出 (2フェーズ)
## Phase 1 (0.0–0.55): 最後の壁から後方まで一気に止まらず飛行（+Z方向を向いたまま）
## Phase 2 (0.55–1.0): 後方からFPS一人称視点へゆっくり復帰
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
	if gs.p1_waiting_for_shark:
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
	var player_y: float = 1.2  # FPS eye height

	# --- 終着点: 1P=FPS / 2P=三人称 ---
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
		end_fov = 50.0
	else:
		# 1P: FPS一人称視点
		end_pos = Vector3(gs.player_x, player_y, gs.player_local_z)
		end_look = end_pos + Vector3(0.0, 0.0, 10.0)
		end_fov = 44.0

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
		var player_y: float = 1.2
		end_pos = Vector3(gs.player_x, player_y, gs.player_local_z)
		end_look = end_pos + Vector3(0.0, 0.0, 10.0)

	var pullback_distance := 14.0
	var view_dir := (end_look - end_pos).normalized()
	var target_eye := end_pos - view_dir * pullback_distance
	var target_look := end_look - view_dir * pullback_distance
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

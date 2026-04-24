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

func _ready() -> void:
	if not camera:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.current = true
	camera.fov = 44.0
	camera.near = 0.1
	camera.far = 500.0

func update_camera(gs: QuizGameState, dt: float) -> void:
	# フライオーバー→カウントダウン遷移時にbobタイマーをリセット
	# (bobが途中の位相だとカメラのY座標がジャンプするため)
	if _prev_state == Constants.STATE_FLYOVER and gs.game_state != Constants.STATE_FLYOVER:
		_time = 0.0
	_prev_state = gs.game_state

	_time += dt
	var bob: float = sin(_time * 1.2) * 0.04

	var eye: Vector3
	var target: Vector3
	var fov: float = 44.0

	# === FLYOVER: 10問モードの壁全体俯瞰演出 ===
	if gs.game_state == Constants.STATE_FLYOVER:
		_update_flyover_camera(gs, dt)
		return

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
	var start_pos := Vector3(0.0, 6.0, camera_start_z + 8.0)   # 10壁目の位置から開始
	
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

	if progress < 0.55:
		# === Phase 1: 最後の壁から後方まで一気に飛行 ===
		var p: float = progress / 0.55
		var eased: float = _ease_smooth(p)
		eye = start_pos.lerp(overshoot_pos, eased)
		# 視線: スタート時の視点から、オーバーシュート時のドリー軌道の視線へと100%滑らかに繋ぐ
		look_target = start_look.lerp(overshoot_look, eased)
		# FOV: 飛行中に徐々にワイドに
		fov = lerpf(52.0, 66.0, eased)

	else:
		# === Phase 2: 後方 → 終着点へ ゆっくり 復帰 ===
		var p: float = (progress - 0.55) / 0.45
		var eased: float = _ease_smooth(p)
		eye = overshoot_pos.lerp(end_pos, eased)
		# 視線: カメラ座標と一緒に全く同じベクトルで引かれるため、ピッチとヨーは一切変化しない心地よいドリー・イン
		look_target = overshoot_look.lerp(end_look, eased)
		fov = lerpf(66.0, end_fov, eased)

	camera.fov = fov
	camera.global_position = eye
	camera.look_at(look_target, Vector3.UP)


## Quintic ease-in-out (滑らかな加速/減速)
func _ease_smooth(x: float) -> float:
	if x < 0.5:
		return 16.0 * x * x * x * x * x
	var f: float = (2.0 * x - 2.0)
	return 0.5 * f * f * f * f * f + 1.0

extends Node3D

## カメラ制御
## Python版 renderer.py の _camera() メソッドに相当
## 1P: FPS視点 (マウスルック)
## 2P: 俯瞰視点
## ゲームオーバー: ズームアウト + シェイク

@onready var camera: Camera3D = $Camera3D

var _time: float = 0.0
var _go_timer: float = 0.0

func _ready() -> void:
	if not camera:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.current = true
	camera.fov = 44.0
	camera.near = 0.1
	camera.far = 160.0

func update_camera(gs: QuizGameState, dt: float) -> void:
	_time += dt
	var bob: float = sin(_time * 1.2) * 0.04

	var eye: Vector3
	var target: Vector3
	var fov: float = 44.0

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

			var decay_shake: float = maxf(0.0, 1.0 - _go_timer * 0.8) * 1.5
			var sx: float = (randf() - 0.5) * decay_shake
			var sy: float = (randf() - 0.5) * decay_shake

			eye = Vector3(
				sx,
				4.5 + bob + ease_t * 5.0 + sy,
				z_focus + (-9.0 - ease_t * 8.0))
			target = Vector3(
				sx * 0.5,
				1.0 + sy * 0.5,
				z_focus)
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

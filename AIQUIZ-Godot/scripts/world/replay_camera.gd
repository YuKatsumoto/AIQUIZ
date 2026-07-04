extends Node3D
class_name ReplayCamera

## リプレイ用自由視点カメラ
## モード: FREE（フリーカム）/ FOLLOW_P1 / FOLLOW_P2 / OVERHEAD（俯瞰）

enum Mode { FREE, FOLLOW_P1, FOLLOW_P2, OVERHEAD }

signal mode_changed(mode: Mode)

@onready var camera: Camera3D

var current_mode: Mode = Mode.FREE

# フリーカメラ状態
var _yaw: float = 0.0
var _pitch: float = -0.3
var _position: Vector3 = Vector3(0, 5, -10)
var _move_speed: float = 12.0
var _look_sensitivity: float = 0.003
var _zoom_speed: float = 2.0
var _is_dragging: bool = false

# 追従カメラ状態
var _follow_distance: float = 8.0
var _follow_height: float = 4.0
var _follow_yaw: float = 0.0
var _follow_pitch: float = -0.4

# ターゲット位置（ReplayPlayerから更新される）
var _p1_pos: Vector3 = Vector3.ZERO
var _p2_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "ReplayCamera3D"
	camera.fov = 55.0
	camera.near = 0.1
	camera.far = 500.0
	camera.current = true
	add_child(camera)

func set_mode(mode: Mode) -> void:
	current_mode = mode
	mode_changed.emit(mode)
	# モード切替時にカメラ位置を調整
	match mode:
		Mode.FOLLOW_P1:
			_follow_yaw = 0.0
			_follow_pitch = -0.4
		Mode.FOLLOW_P2:
			_follow_yaw = 0.0
			_follow_pitch = -0.4
		Mode.OVERHEAD:
			pass
		Mode.FREE:
			# 現在のカメラ位置をフリーカメラに引き継ぐ
			_position = camera.global_position
			_yaw = camera.rotation.y
			_pitch = camera.rotation.x

func cycle_mode() -> void:
	var next := (current_mode + 1) % 4
	set_mode(next as Mode)

func get_mode_label() -> String:
	match current_mode:
		Mode.FREE: return "フリーカメラ"
		Mode.FOLLOW_P1: return "P1追従"
		Mode.FOLLOW_P2: return "P2追従"
		Mode.OVERHEAD: return "俯瞰"
	return ""

func update_targets(p1: Vector3, p2: Vector3) -> void:
	_p1_pos = p1
	_p2_pos = p2

func update_camera(dt: float) -> void:
	match current_mode:
		Mode.FREE:
			_update_free(dt)
		Mode.FOLLOW_P1:
			_update_follow(dt, _p1_pos)
		Mode.FOLLOW_P2:
			_update_follow(dt, _p2_pos)
		Mode.OVERHEAD:
			_update_overhead(dt)

func _update_free(dt: float) -> void:
	# 回転の適用
	camera.rotation.y = _yaw
	camera.rotation.x = _pitch
	camera.rotation.z = 0.0

	# WASD 移動
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_key_pressed(KEY_S): move.z += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): move.y += 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_SHIFT): move.y -= 1.0

	# Shift で加速
	var speed := _move_speed * (2.5 if Input.is_key_pressed(KEY_CTRL) else 1.0)

	# カメラの向きに基づいて移動
	_position += (camera.global_basis * move) * speed * dt

	# カメラ適用
	camera.global_position = _position

func _update_follow(_dt: float, target: Vector3) -> void:
	var offset := Vector3(
		sin(_follow_yaw) * cos(_follow_pitch) * _follow_distance,
		-sin(_follow_pitch) * _follow_distance,
		cos(_follow_yaw) * cos(_follow_pitch) * _follow_distance
	)
	var eye := target + offset + Vector3(0, 1.0, 0)  # ターゲットの少し上を見る
	camera.global_position = eye
	camera.look_at(target + Vector3(0, 1.0, 0), Vector3.UP)

func _update_overhead(_dt: float) -> void:
	var mid := (_p1_pos + _p2_pos) / 2.0
	var eye := Vector3(mid.x, 20.0, mid.z - 2.0)
	camera.global_position = eye
	camera.look_at(mid + Vector3(0, 0, 5.0), Vector3(0, 0, 1))

func handle_input(event: InputEvent) -> void:
	# マウスドラッグで回転
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if current_mode == Mode.FREE:
				_move_speed = minf(_move_speed * 1.1, 50.0)
			else:
				_follow_distance = maxf(_follow_distance - _zoom_speed, 2.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if current_mode == Mode.FREE:
				_move_speed = maxf(_move_speed * 0.9, 2.0)
			else:
				_follow_distance = minf(_follow_distance + _zoom_speed, 30.0)

	if event is InputEventMouseMotion and _is_dragging:
		var motion := event as InputEventMouseMotion
		if current_mode == Mode.FREE:
			_yaw -= motion.relative.x * _look_sensitivity
			_pitch -= motion.relative.y * _look_sensitivity
			_pitch = clampf(_pitch, -PI / 2.2, PI / 2.2)
		elif current_mode in [Mode.FOLLOW_P1, Mode.FOLLOW_P2]:
			_follow_yaw -= motion.relative.x * _look_sensitivity
			_follow_pitch -= motion.relative.y * _look_sensitivity
			_follow_pitch = clampf(_follow_pitch, -PI / 2.2, -0.05)

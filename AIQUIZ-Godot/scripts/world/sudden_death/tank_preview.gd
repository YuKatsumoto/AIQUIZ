extends Node3D

## 地下ステージ（首都圏外郭放水路の調圧水槽の再現、docs/surge_tank_reproduction.md）を歩いて見るためのプレビュー。
## scenes/sudden_death/tank_preview.tscn をエディターで開いて F6 で起動する。
## 操作：WASD で移動、Q / E で下降・上昇、マウスの右ボタンを押しながら動かして見回す、Shift で速く、
## 1〜9・0 で参考写真と同じ構図の視点へ、L で照明を全部消す / 点ける、F で画質（low → balanced → high → ultra）。
## 舞台は本番と同じ SuddenDeathLoader で読み込む（部分シーンを足し、材質と環境を整えてから表示）。

const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const FLOOR_Y := SuddenDeathLayout.FLOOR_Y
const VIEWS: Array = [
	[Vector3(0.0, 1.6, -27.0), Vector3(0.0, 7.0, 30.0), 62.0],
	[Vector3(7.0, 1.6, 7.0), Vector3(7.0, 2.6, 60.0), 75.0],
	[Vector3(0.0, 1.7, -20.0), Vector3(0.0, 6.0, -60.0), 58.0],
	[Vector3(0.0, 1.7, 105.0), Vector3(0.0, 6.5, 135.0), 68.0],
	[Vector3(-6.0, 1.7, -4.0), Vector3(-30.0, 4.0, -19.0), 62.0],
	[Vector3(-30.0, 6.7, -8.0), Vector3(-31.0, 9.0, 60.0), 70.0],
	[Vector3(3.5, 1.6, -24.0), Vector3(3.5, 3.5, 40.0), 68.0],
	[Vector3(10.0, 1.6, 20.0), Vector3(10.0, 16.0, 34.0), 80.0],
	[Vector3(-34.9, 13.6, 50.0), Vector3(0.0, 4.0, 60.0), 80.0],
	[Vector3(3.0, 1.6, 35.0), Vector3(-24.0, 3.5, 50.0), 64.0],
]
const SPEED := 6.0
const FAST := 4.0
const LOOK_SENSITIVITY := 0.003

var _loader: SuddenDeathLoader
var _stage: CisternStage
var _camera: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _lit := true
var _quality := GraphicsQualityRules.HIGH
var _label: Label


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.near = 0.05
	_camera.far = 400.0
	add_child(_camera)
	_camera.current = true
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	layer.add_child(_label)
	_go_to(0)
	_load(_quality)


func _load(quality: String) -> void:
	if is_instance_valid(_loader):
		_loader.cancel()
		_loader.queue_free()
	if is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null
	_quality = quality
	GameManager.graphics_quality = quality
	GraphicsQualityRules.apply_rendering_server(quality)
	_loader = SuddenDeathLoader.new()
	add_child(_loader)
	_loader.set_heavy_work_allowed(true)
	_loader.set_presentable(true)
	_loader.begin(self, _game_state())
	_label.text = "読み込み中…"


func _game_state() -> QuizGameState:
	var state := QuizGameState.new()
	var quizzes: Array[QuizItem] = []
	for index in range(SuddenDeathTuning.QUESTION_COUNT):
		quizzes.append(QuizItem.create("プレビュー %d" % (index + 1), PackedStringArray(["A", "B", "C", "D"]), 0, "テスト", "OFFLINE"))
	state.sudden_death = SuddenDeathState.new()
	state.sudden_death.setup(quizzes, true)
	return state


func _process(delta: float) -> void:
	if _stage == null and is_instance_valid(_loader) and _loader.is_ready():
		_stage = _loader.cistern()
		_camera.environment = _loader.environment()
		_stage.set_all_rows(1.0 if _lit else 0.0)
		_stage.refresh_reflections()
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_key_pressed(KEY_E):
		move.y += 1.0
	if Input.is_key_pressed(KEY_Q):
		move.y -= 1.0
	var speed := SPEED * (FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_camera.position += _camera.global_transform.basis * move.normalized() * speed * delta if move != Vector3.ZERO else Vector3.ZERO
	var p := _camera.position
	_label.text = "x %.1f  y %.1f  z %.1f   画質 %s   %s\nWASD/QE 移動・右ドラッグ 見回す・1〜0 参考写真の視点・L 照明・F 画質" % [
		p.x, p.y - FLOOR_Y, p.z, _quality, "照明 ON" if _lit else "照明 OFF"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * LOOK_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * LOOK_SENSITIVITY, -1.5, 1.5)
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_9:
			_go_to(key - KEY_1)
		elif key == KEY_0:
			_go_to(9)
		elif key == KEY_L and _stage != null:
			_lit = not _lit
			_stage.set_all_rows(1.0 if _lit else 0.0)
		elif key == KEY_F:
			var tiers := [GraphicsQualityRules.LOW, GraphicsQualityRules.BALANCED, GraphicsQualityRules.HIGH, GraphicsQualityRules.ULTRA]
			_load(tiers[(tiers.find(_quality) + 1) % tiers.size()])


func _go_to(index: int) -> void:
	var view: Array = VIEWS[clampi(index, 0, VIEWS.size() - 1)]
	# the views are in plan metres; the stage is the plan scaled about the landing point
	var eye: Vector3 = view[0] * SuddenDeathLayout.TANK_SCALE + Vector3(0.0, FLOOR_Y, 0.0)
	var target: Vector3 = view[1] * SuddenDeathLayout.TANK_SCALE + Vector3(0.0, FLOOR_Y, 0.0)
	_camera.fov = float(view[2])
	_camera.look_at_from_position(eye, target, Vector3.UP)
	_yaw = _camera.rotation.y
	_pitch = _camera.rotation.x

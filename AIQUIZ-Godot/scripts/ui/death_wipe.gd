extends SubViewportContainer

## 2Pモード死亡ワイプカメラ
## 片方のプレイヤーが画面外で死んだとき、右下にワイプ画面を表示して
## 海に落ちて溺れて沈む様を晒す

@onready var sub_viewport: SubViewport = $SubViewport
@onready var wipe_camera: Camera3D = $SubViewport/WipeCamera
@onready var label: Label = $PlayerLabel
@onready var border_rect: ColorRect = $BorderRect
@onready var skull_label: Label = $SkullLabel

var game_state: QuizGameState
var _active: bool = false
var _dead_player: int = 0  # 1 or 2
var _timer: float = 0.0
var _fade_in: float = 0.0
var _fade_out: float = 0.0
var _is_hiding: bool = false
var _world_set: bool = false

const WIPE_W := 320
const WIPE_H := 240
const BORDER := 4
const WIPE_MARGIN_X := 24
const WIPE_MARGIN_Y := 80  # bottom margin above progress-bar area
const FADE_DURATION := 0.5

func _ready() -> void:
	game_state = QuizManager.game_state
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Containerのstretchにサイズを委ね、非表示中は描画を停止する。
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	sub_viewport.transparent_bg = false
	GraphicsQuality.apply_character_preview(sub_viewport, GameManager.graphics_quality)

	# Camera defaults
	wipe_camera.current = false
	wipe_camera.fov = 50.0
	wipe_camera.near = 0.1
	wipe_camera.far = 160.0

	# Container size (viewport + border)
	custom_minimum_size = Vector2(WIPE_W + BORDER * 2, WIPE_H + BORDER * 2)
	size = custom_minimum_size
	stretch = true

	_setup_labels()

func _setup_labels() -> void:
	# Player label (top overlay)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)

	# Skull label (bottom overlay)
	skull_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skull_label.add_theme_font_size_override("font_size", 32)
	skull_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2, 1))
	skull_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	skull_label.add_theme_constant_override("outline_size", 4)

func _process(dt: float) -> void:
	if not game_state:
		return

	# Only in 2P mode during gameplay-related states
	var should_show := false
	var target_player := 0

	if game_state.num_players >= 2:
		var playing_states := [Constants.STATE_PLAYING, Constants.STATE_CORRECT,
			Constants.STATE_GAME_OVER, Constants.STATE_GOAL_RACE]
		
		if game_state.game_state in playing_states:
			var p1_dead := not game_state.p1_alive
			var p2_dead := not game_state.p2_alive

			if p1_dead and not p2_dead and game_state.game_over_timer > 0 and game_state.game_over_timer < 4.0:
				should_show = true
				target_player = 1
			elif p2_dead and not p1_dead and game_state.player2_game_over_timer > 0 and game_state.player2_game_over_timer < 4.0:
				should_show = true
				target_player = 2
			# Keep showing briefly after both die (game over state)
			elif p1_dead and p2_dead and _active:
				var current_timer := game_state.game_over_timer if _dead_player == 1 else game_state.player2_game_over_timer
				if current_timer < 4.0:
					should_show = true
					target_player = _dead_player

	if should_show:
		if not _active or _is_hiding:
			_start_wipe(target_player)
	else:
		_hide_wipe()

	# If active (including while sliding out), continue updating animation
	if _active:
		_update_wipe(dt)

func _start_wipe(player: int) -> void:
	_active = true
	_dead_player = player
	_timer = 0.0
	_fade_in = 0.0
	_fade_out = 0.0
	_is_hiding = false
	visible = true

	# Share main viewport's World3D so the wipe camera sees the same scene
	if not _world_set:
		var root_vp: Viewport = get_tree().get_root()
		if root_vp and root_vp.world_3d:
			sub_viewport.world_3d = root_vp.world_3d
			_world_set = true
			
			# Find WorldEnvironment to share the sky and lighting
			var current_scene = get_tree().current_scene
			if current_scene:
				var world_env = current_scene.find_child("WorldEnvironment", true, false)
				if world_env and world_env is WorldEnvironment:
					wipe_camera.environment = world_env.environment

	# Label styling per player
	if player == 1:
		label.text = "P1"
		label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
	else:
		label.text = "P2"
		label.add_theme_color_override("font_color", Color(0.35, 0.75, 1.0))
	skull_label.text = ""

func _hide_wipe() -> void:
	if _active and not _is_hiding:
		_is_hiding = true
		_fade_out = 0.0
		# DO NOT reset world_3d to avoid Godot renderer crash during scene/state transitions
		# sub_viewport.world_3d = null

func _update_wipe(dt: float) -> void:
	_timer += dt
	
	var slide_offset := Vector2(size.x + WIPE_MARGIN_X + 50.0, 0.0) # 右側に完全に隠れるオフセット
	var current_offset := slide_offset

	if _is_hiding:
		_fade_out = clampf(_fade_out + dt / FADE_DURATION, 0.0, 1.0)
		var eased := pow(_fade_out, 3.0) # easeInCubic
		current_offset = slide_offset * eased
		
		# スライドアウト完了時に非表示化
		if _fade_out >= 1.0:
			_active = false
			_is_hiding = false
			visible = false
			return
	else:
		_fade_in = clampf(_fade_in + dt / FADE_DURATION, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - _fade_in, 3.0) # easeOutCubic
		current_offset = slide_offset * (1.0 - eased)

	# Position at bottom-right + slide offset
	var screen_size := get_viewport_rect().size
	position = screen_size - size - Vector2(WIPE_MARGIN_X, WIPE_MARGIN_Y) + current_offset

	# Animate border color (danger pulse)
	var pulse := 0.5 + 0.5 * sin(_timer * 5.0)
	border_rect.color = Color(
		0.9 + pulse * 0.1,
		0.1 + pulse * 0.15,
		0.05,
		1.0
	)

	# Skull label subtle shake
	skull_label.position.x = (size.x - 40) / 2.0 + sin(_timer * 12.0) * 3.0

	# Update wipe camera to track dead player
	_update_wipe_camera()

func _update_wipe_camera() -> void:
	var px: float
	var py: float
	var local_z: float
	var death_timer: float

	if _dead_player == 1:
		px = game_state.player_x
		py = game_state.player_y
		local_z = game_state.player_local_z
		death_timer = game_state.game_over_timer
	else:
		px = game_state.player2_x
		py = game_state.player2_y
		local_z = game_state.player2_local_z
		death_timer = game_state.player2_game_over_timer

	var cam_eye: Vector3
	var cam_target: Vector3

	if death_timer < 2.0:
		# Phase 1: Watch the player tumble and fall into ocean
		# Camera positioned slightly to the side and above, looking down
		var fall_progress := clampf(death_timer / 2.0, 0.0, 1.0)
		var cam_y := py + 2.5 + fall_progress * 3.0  # Rise as player falls
		cam_eye = Vector3(px + 3.0, cam_y, local_z - 3.5)
		cam_target = Vector3(px, py, local_z)
	else:
		# Phase 2: Drift above the impact point after the player sinks out of view
		var sink_t: float = death_timer - 2.0
		var orbit_angle: float = sink_t * 0.35
		var radius: float = 4.0
		var target_y: float = StageConstants.OCEAN_SURFACE_Y
		cam_eye = Vector3(
			px + sin(orbit_angle) * radius,
			target_y + 3.8 + sin(sink_t * 1.2) * 0.25,
			local_z - cos(orbit_angle) * radius
		)
		cam_target = Vector3(px, target_y, local_z)

	wipe_camera.global_position = cam_eye
	wipe_camera.look_at(cam_target, Vector3.UP)

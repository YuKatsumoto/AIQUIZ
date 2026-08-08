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
var _shark_impact_flash: float = 0.0
var _impact_overlay: ColorRect = null
var _ghost_follow_direction: Vector3 = Vector3.FORWARD
var _explosion_hold_elapsed: float = 0.0

const WIPE_W := 320
const WIPE_H := 240
const BORDER := 4
const WIPE_MARGIN_X := 24
const WIPE_MARGIN_Y := 80  # bottom margin above progress-bar area
const FADE_DURATION := 0.5
const EXPLOSION_HOLD_DURATION := 1.25
const SOUL_PRESENTATION_RENDER_LAYER := 20

func _ready() -> void:
	game_state = QuizManager.game_state
	if (
		game_state
		and not game_state.player_entered_ocean.is_connected(_on_player_entered_ocean)
	):
		game_state.player_entered_ocean.connect(_on_player_entered_ocean)
	if (
		game_state
		and not game_state.player_scrolled_out.is_connected(_on_player_scrolled_out)
	):
		game_state.player_scrolled_out.connect(_on_player_scrolled_out)
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
	wipe_camera.set_cull_mask_value(SOUL_PRESENTATION_RENDER_LAYER, true)

	# Container size (viewport + border)
	custom_minimum_size = Vector2(WIPE_W + BORDER * 2, WIPE_H + BORDER * 2)
	size = custom_minimum_size
	stretch = true

	_setup_labels()
	_setup_impact_overlay()

func _setup_impact_overlay() -> void:
	_impact_overlay = ColorRect.new()
	_impact_overlay.name = "SharkImpactFlash"
	_impact_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_impact_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_impact_overlay.color = Color(0.72, 0.94, 1.0, 0.0)
	add_child(_impact_overlay)
	move_child(_impact_overlay, get_child_count() - 1)


func play_shark_impact_flash(player_index: int) -> void:
	if not _active or _dead_player != player_index:
		return
	_shark_impact_flash = 1.0


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

func _on_player_entered_ocean(player_index: int, _local_position: Vector3) -> void:
	if not game_state or game_state.num_players < 2:
		return
	var other_player_alive: bool = (
		game_state.p2_alive if player_index == 1 else game_state.p1_alive
	)
	if not other_player_alive:
		return
	# 海面へ入った瞬間に開始する。表示中にもう一人が落ちた場合も、
	# 後から落ちたプレイヤーへ即座に切り替える。
	_start_wipe(player_index)


func _on_player_scrolled_out(player_index: int) -> void:
	if not game_state or game_state.num_players < 2:
		return
	var other_player_alive: bool = (
		game_state.p2_alive if player_index == 1 else game_state.p1_alive
	)
	if not other_player_alive:
		return
	_start_wipe(player_index)


func _process(dt: float) -> void:
	if not game_state:
		return

	var should_show: bool = false
	var target_player: int = _dead_player
	var current_scene: Node = get_tree().current_scene
	var active_player_exploded := _has_player_death_exploded(
		current_scene,
		_dead_player
	)
	if _active and active_player_exploded:
		_explosion_hold_elapsed += dt
	elif not active_player_exploded:
		_explosion_hold_elapsed = 0.0
	if game_state.num_players >= 2:
		var playing_states := [
			Constants.STATE_PLAYING,
			Constants.STATE_CORRECT,
			Constants.STATE_GAME_OVER,
			Constants.STATE_GOAL_RACE,
		]
		if game_state.game_state in playing_states:
			# 落下直後は alive のままサメ待機へ入るため、死亡フラグより
			# waiting_for_shark を優先して表示を維持する。
			if _active and _dead_player in [1, 2]:
				var other_player_alive: bool = (
					game_state.p2_alive if _dead_player == 1 else game_state.p1_alive
				)
				var death_exploded := _has_player_death_exploded(
					current_scene,
					_dead_player
				)
				var waiting_for_shark: bool = game_state.is_player_waiting_for_shark(
					_dead_player
				)
				var current_timer: float = (
					game_state.game_over_timer
					if _dead_player == 1
					else game_state.player2_game_over_timer
				)
				var holding_explosion := (
					death_exploded
					and _explosion_hold_elapsed < EXPLOSION_HOLD_DURATION
				)
				should_show = other_player_alive and (
					holding_explosion
					or (
						not death_exploded
						and (
							waiting_for_shark
							or (current_timer > 0.0 and current_timer < 4.0)
						)
					)
				)
	if current_scene != null and current_scene.has_method("get_ghost_shark_presentation"):
		for player_index: int in [1, 2]:
			var presentation: Dictionary = current_scene.get_ghost_shark_presentation(
				player_index
			)
			var player_exploded := _has_player_death_exploded(
				current_scene,
				player_index
			)
			var holding_explosion := (
				player_exploded
				and player_index == _dead_player
				and _explosion_hold_elapsed < EXPLOSION_HOLD_DURATION
			)
			if (
				bool(presentation.get("active", false))
				and bool(presentation.get("show_wipe", true))
				and (not player_exploded or holding_explosion)
			):
				var other_alive := (
					game_state.p2_alive if player_index == 1 else game_state.p1_alive
				)
				if other_alive:
					should_show = true
					target_player = player_index
					break


	if should_show:
		if not _active or _is_hiding or _dead_player != target_player:
			_start_wipe(target_player)
	else:
		_hide_wipe()

	if _active:
		_update_wipe(dt)

func _start_wipe(player: int) -> void:
	_active = true
	_dead_player = player
	_timer = 0.0
	_shark_impact_flash = 0.0
	_fade_in = 0.0
	_fade_out = 0.0
	_is_hiding = false
	_explosion_hold_elapsed = 0.0
	_ghost_follow_direction = Vector3.FORWARD
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

func _has_player_death_exploded(current_scene: Node, player_index: int) -> bool:
	if (
		player_index not in [1, 2]
		or current_scene == null
		or not current_scene.has_method("has_player_death_exploded")
	):
		return false
	return bool(current_scene.call("has_player_death_exploded", player_index))


func _hide_wipe() -> void:
	if _active and not _is_hiding:
		_is_hiding = true
		_fade_out = 0.0
		# DO NOT reset world_3d to avoid Godot renderer crash during scene/state transitions
		# sub_viewport.world_3d = null

func _update_wipe(dt: float) -> void:
	_timer += dt
	_shark_impact_flash = maxf(0.0, _shark_impact_flash - dt * 12.5)
	if _impact_overlay != null:
		_impact_overlay.color = Color(0.72, 0.94, 1.0, _shark_impact_flash * 0.76)
	
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

	if _dead_player == 1:
		px = game_state.player_x
		py = game_state.player_y
		local_z = game_state.player_local_z
	else:
		px = game_state.player2_x
		py = game_state.player2_y
		local_z = game_state.player2_local_z

	var player_position: Vector3 = Vector3(px, py + 0.65, local_z)
	var shark_position: Vector3 = Vector3.ZERO
	var has_shark: bool = false
	var shark_intensity: float = 0.0
	var current_scene: Node = get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_ghost_shark_presentation"):
		var ghost_presentation: Dictionary = current_scene.get_ghost_shark_presentation(
			_dead_player
		)
		if bool(ghost_presentation.get("active", false)):
			_update_ghost_presentation_camera(player_position, ghost_presentation)
			return
	if current_scene != null and current_scene.has_method("get_ocean_attack_shark_position"):
		var shark_position_variant: Variant = current_scene.get_ocean_attack_shark_position(_dead_player)
		if shark_position_variant is Vector3:
			shark_position = shark_position_variant
			has_shark = true
	if current_scene != null and current_scene.has_method("get_ocean_attack_shark_intensity"):
		shark_intensity = float(current_scene.get_ocean_attack_shark_intensity(_dead_player))

	var cam_eye: Vector3 = player_position + Vector3(3.0, 2.5, -3.5)
	var cam_target: Vector3 = player_position
	var camera_controller: Node = null
	if current_scene != null:
		camera_controller = current_scene.get_node_or_null("CameraController")
	if (
		camera_controller != null
		and camera_controller.has_method("get_ocean_attack_camera_pose")
	):
		# 1Pのサメ接近カメラと同じ位置・注視点・FOVをそのまま使用する。
		var pose: Dictionary = camera_controller.get_ocean_attack_camera_pose(
			player_position,
			shark_position,
			has_shark,
			shark_intensity
		)
		cam_eye = pose.get("eye", cam_eye)
		cam_target = pose.get("target", cam_target)

	wipe_camera.global_position = cam_eye
	wipe_camera.look_at(cam_target, Vector3.UP)


func _update_ghost_presentation_camera(
	death_position: Vector3,
	presentation: Dictionary
) -> void:
	var duration := maxf(float(presentation.get("duration", 7.5)), 0.001)
	var elapsed := clampf(float(presentation.get("elapsed", 0.0)), 0.0, duration)
	var rider_position: Vector3 = presentation.get("rider_position", death_position)
	var shark_position: Vector3 = presentation.get("shark_position", rider_position)
	var travel_direction := shark_position - rider_position
	travel_direction.y = 0.0
	if travel_direction.length_squared() >= 0.001:
		_ghost_follow_direction = travel_direction.normalized()
	travel_direction = _ghost_follow_direction
	var camera_side := Vector3(-travel_direction.z, 0.0, travel_direction.x)
	var side_sign := signf(death_position.x)
	if is_zero_approx(side_sign):
		side_sign = 1.0 if _dead_player == 1 else -1.0
	if camera_side.x * side_sign < 0.0:
		camera_side = -camera_side

	# Every shot is rooted at the live ghost rider. The offsets and FOV may change,
	# but neither the camera position nor its look target drifts toward the shark.
	var follow_target := rider_position + Vector3.UP * 0.45
	var close_eye := rider_position + camera_side * 3.0 - travel_direction * 3.6 + Vector3.UP * 2.55
	var reveal_eye := rider_position + camera_side * 5.4 - travel_direction * 1.2 + Vector3.UP * 2.85
	var chase_eye := rider_position + camera_side * 5.8 - travel_direction * 1.4 + Vector3.UP * 3.30
	var mount_eye := rider_position + camera_side * 5.8 - travel_direction * 0.8 + Vector3.UP * 3.15
	var hero_eye := rider_position + camera_side * 5.0 + travel_direction * 1.7 + Vector3.UP * 2.75

	var cam_eye: Vector3
	var cam_target: Vector3
	var fov: float
	if elapsed < 0.8:
		cam_eye = close_eye
		cam_target = follow_target
		fov = 44.0
	elif elapsed < 1.8:
		var blend_to_reveal := smoothstep(0.0, 1.0, (elapsed - 0.8) / 1.0)
		cam_eye = close_eye.lerp(reveal_eye, blend_to_reveal)
		cam_target = follow_target
		fov = lerpf(44.0, 58.0, blend_to_reveal)
	elif elapsed < 3.2:
		var blend_to_chase := smoothstep(0.0, 1.0, (elapsed - 1.8) / 1.4)
		cam_eye = reveal_eye.lerp(chase_eye, blend_to_chase)
		cam_target = follow_target
		fov = lerpf(58.0, 55.0, blend_to_chase)
	elif elapsed < 4.2:
		var blend_to_mount := smoothstep(0.0, 1.0, elapsed - 3.2)
		cam_eye = chase_eye.lerp(mount_eye, blend_to_mount)
		cam_target = follow_target
		fov = lerpf(55.0, 50.0, blend_to_mount)
	else:
		var blend_to_hero := smoothstep(
			0.0,
			1.0,
			(elapsed - 4.2) / maxf(0.001, duration - 4.2)
		)
		cam_eye = mount_eye.lerp(hero_eye, blend_to_hero)
		cam_target = follow_target
		fov = lerpf(50.0, 48.0, blend_to_hero)
	wipe_camera.fov = fov
	wipe_camera.global_position = cam_eye
	wipe_camera.look_at(cam_target, Vector3.UP)

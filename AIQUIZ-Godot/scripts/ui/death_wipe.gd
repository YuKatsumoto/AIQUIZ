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
## GOSTRIDER の演出中のカメラ（なめらかに追う目・注視点・画角）と、揺れ・閃光・寄り。
var _ghost_presenting: bool = false
var _ghost_camera_ready: bool = false
var _ghost_camera_eye: Vector3 = Vector3.ZERO
var _ghost_camera_target: Vector3 = Vector3.ZERO
var _ghost_camera_fov: float = 50.0
var _ghost_shot_name: String = ""
var _ghost_ascent_ready: bool = false
var _ghost_ascent_anchor: Vector3 = Vector3.ZERO
var _ghost_ascent_back: Vector3 = Vector3.BACK
var _ghost_ascent_side: Vector3 = Vector3.RIGHT
var _ghost_shake: float = 0.0
var _ghost_shake_time: float = 0.0
var _ghost_flash: float = 0.0
var _ghost_flash_color: Color = Color.WHITE
var _ghost_punch: float = 0.0

const WIPE_W := 320
const WIPE_H := 240
const BORDER := 4
const WIPE_MARGIN_X := 24
const WIPE_MARGIN_Y := 80  # bottom margin above progress-bar area
const FADE_DURATION := 0.5
const EXPLOSION_HOLD_DURATION := 1.25
const SOUL_PRESENTATION_RENDER_LAYER := 20
const GHOST_MOUNT_BEAM_RENDER_LAYER := 19
const GHOST_CAMERA_FOLLOW_RATE := 14.0
const GHOST_CAMERA_AIM_RATE := 20.0
const GHOST_CAMERA_MIN_SIDE_X := StageConstants.FLOOR_HALF_WIDTH + 0.45
const GHOST_CAMERA_MIN_WATER_CLEARANCE := 0.28
const GHOST_CAMERA_DECK_CLEARANCE := 0.35
const GHOST_SHAKE_DECAY := 2.6
const GHOST_SHAKE_DISTANCE := 0.16
const GHOST_FLASH_DECAY := 3.4
const GHOST_PUNCH_DECAY := 3.0
const GHOST_PUNCH_SCALE := 0.07
const P1_COLOR := Color(1.0, 0.6, 0.25)
const P2_COLOR := Color(0.35, 0.75, 1.0)

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
	if game_state and not game_state.player_caught_by_saw.is_connected(_on_player_scrolled_out):
		game_state.player_caught_by_saw.connect(_on_player_scrolled_out)
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
	# The survivor camera owns the beacon reveal. Keep it out of the wipe feed
	# even after the wipe has reached its settled corner position.
	# （小窓のカメラは柱のすぐ外に寄るので、映すと画面が柱の色で埋まり乗り手が隠れる）
	wipe_camera.set_cull_mask_value(GHOST_MOUNT_BEAM_RENDER_LAYER, false)

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


func is_settled_for_player(player_index: int) -> bool:
	return (
		_active
		and visible
		and not _is_hiding
		and _dead_player == player_index
		and _fade_in >= 1.0
	)


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
	if not _active and game_state.net_online and not game_state.net_authority:
		_start_online_guest_wipe(current_scene)
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
			# 幽霊の演出（魂が抜ける → サメに乗る → ビーム）は、体が爆散したあとが本番なので、
			# 爆散の保持（EXPLOSION_HOLD_DURATION）で閉じない。演出が小窓を要る間ずっと映す。
			if (
				bool(presentation.get("active", false))
				and bool(presentation.get("show_wipe", true))
			):
				var other_alive := (
					game_state.p2_alive if player_index == 1 else game_state.p1_alive
				)
				if other_alive:
					should_show = true
					target_player = player_index
					break

	# The dead player is already leaping to the result podium as a ghost.
	if game_state.result_ghost_mask != 0 or game_state.result_presentation_active:
		should_show = false

	if should_show:
		if not _active or _is_hiding or _dead_player != target_player:
			_start_wipe(target_player)
	else:
		_hide_wipe()

	if _active:
		_update_wipe(dt)

## オンラインのゲストは game_state.update() を回さないので、海に落ちた・置いていかれた・のこぎりの
## 合図（signal）が来ない。スナップショットで届く状態から、同じところで始める：サメ待ちに入ったとき、
## またはゴーストシャークの演出が始まったとき（爆散した脱落も、ホストと同じく爆散の保持のあいだ映す）。
func _start_online_guest_wipe(current_scene: Node) -> void:
	if game_state.num_players < 2:
		return
	for player_index: int in [1, 2]:
		var other_alive: bool = game_state.p2_alive if player_index == 1 else game_state.p1_alive
		if not other_alive:
			continue
		var ghost_starting := false
		if current_scene != null and current_scene.has_method("get_ghost_shark_presentation"):
			var presentation: Dictionary = current_scene.get_ghost_shark_presentation(player_index)
			ghost_starting = bool(presentation.get("active", false)) and str(presentation.get("phase", "")) == "DEATH_HOLD"
		if game_state.is_player_waiting_for_shark(player_index) or ghost_starting:
			_start_wipe(player_index)
			return


## Initialize the real render target while covered, without starting a death.
func begin_render_prewarm(world: World3D, source_camera: Camera3D) -> void:
	sub_viewport.world_3d = world
	_world_set = true
	wipe_camera.environment = source_camera.environment
	wipe_camera.global_transform = source_camera.global_transform
	wipe_camera.current = true
	visible = true
	label.text = "P1 / P2"
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func end_render_prewarm() -> void:
	visible = false
	# Keep the camera selected; the hidden parent already stops viewport draws.
	# Clearing current here would leave the first real death feed blank.
	label.text = ""
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	# Keep world_3d attached; clearing it during rendering can invalidate RIDs.


func _start_wipe(player: int) -> void:
	wipe_camera.make_current()
	_active = true
	_dead_player = player
	_timer = 0.0
	_shark_impact_flash = 0.0
	_fade_in = 0.0
	_fade_out = 0.0
	_is_hiding = false
	_explosion_hold_elapsed = 0.0
	_ghost_follow_direction = Vector3.FORWARD
	_ghost_presenting = false
	_ghost_camera_ready = false
	_ghost_shot_name = ""
	_ghost_ascent_ready = false
	_ghost_shake = 0.0
	_ghost_flash = 0.0
	_ghost_punch = 0.0
	scale = Vector2.ONE
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
	var gs: QuizGameState = QuizManager.game_state
	var online := gs != null and gs.net_online
	if player == 1:
		label.text = gs.slot_label(1) if online else "P1"
		label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
	else:
		label.text = gs.slot_label(2) if online else "P2"
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
	_ghost_flash = maxf(0.0, _ghost_flash - dt * GHOST_FLASH_DECAY)
	_ghost_punch = maxf(0.0, _ghost_punch - dt * GHOST_PUNCH_DECAY)
	if _impact_overlay != null:
		if _ghost_flash > _shark_impact_flash:
			var flash_color := _ghost_flash_color
			flash_color.a = _ghost_flash * _ghost_flash * 0.72
			_impact_overlay.color = flash_color
		else:
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
	# 着座・目覚めの閃光で一瞬だけ大きくする（右下の角を固定して寄る）。
	var punch := 1.0 + GHOST_PUNCH_SCALE * _ghost_punch * _ghost_punch
	pivot_offset = size
	scale = Vector2.ONE * punch

	var pulse := 0.5 + 0.5 * sin(_timer * 5.0)
	if _ghost_presenting:
		# 幽霊の演出中は、危険の赤ではなくプレイヤー色の光る枠にする。
		var ghost_color := P1_COLOR if _dead_player == 1 else P2_COLOR
		var glow := 0.75 + 0.25 * sin(_timer * 3.2)
		border_rect.color = ghost_color.lerp(Color.WHITE, _ghost_flash * 0.7) * Color(glow, glow, glow, 1.0)
		border_rect.color.a = 1.0
	else:
		# Animate border color (danger pulse)
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
			if not _ghost_presenting:
				_ghost_presenting = true
				var player_name := label.text if not label.text.is_empty() else "P%d" % _dead_player
				label.text = "%s  GHOST RIDER" % player_name
			_update_ghost_presentation_camera(player_position, ghost_presentation)
			return
	_ghost_presenting = false
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


## GOSTRIDER の演出（脱落〜発進）の小窓のカメラ。演技の時刻（performance_time）でショットを選ぶ。
## 魂とサメは甲板より 8 m 下の水路で動くので、カメラはステージの側壁の外・水面の上に置き、
## 背景が壁だけにならない向き（水路の奥・空・観客席）を選ぶ。ショットの間はなめらかにつなぎ、着座の瞬間だけカットで寄る。
func _update_ghost_presentation_camera(
	death_position: Vector3,
	presentation: Dictionary
) -> void:
	var dt := get_process_delta_time()
	var shot := _ghost_shot(death_position, presentation)
	var eye: Vector3 = shot.eye
	var target: Vector3 = shot.target
	var fov: float = shot.fov
	var cut := bool(shot.get("cut", false)) and str(shot.get("name", "")) != _ghost_shot_name
	_ghost_shot_name = str(shot.get("name", ""))
	if not _ghost_camera_ready or cut:
		_ghost_camera_eye = eye
		_ghost_camera_target = target
		_ghost_camera_fov = fov
		_ghost_camera_ready = true
	else:
		var follow := 1.0 - exp(-GHOST_CAMERA_FOLLOW_RATE * dt)
		_ghost_camera_eye = _ghost_camera_eye.lerp(eye, follow)
		_ghost_camera_target = _ghost_camera_target.lerp(target, 1.0 - exp(-GHOST_CAMERA_AIM_RATE * dt))
		_ghost_camera_fov = lerpf(_ghost_camera_fov, fov, follow)
	var shaken_eye := _ghost_camera_eye
	var shaken_target := _ghost_camera_target
	if _ghost_shake > 0.0:
		_ghost_shake = maxf(0.0, _ghost_shake - dt * GHOST_SHAKE_DECAY)
		_ghost_shake_time += dt
		var amount := _ghost_shake * _ghost_shake * GHOST_SHAKE_DISTANCE * float(presentation.get("world_scale", 0.6)) / 0.6
		var wobble := Vector3(
			sin(_ghost_shake_time * 61.0) + sin(_ghost_shake_time * 23.0) * 0.5,
			sin(_ghost_shake_time * 53.0 + 1.3) + sin(_ghost_shake_time * 31.0) * 0.5,
			sin(_ghost_shake_time * 47.0 + 2.1)
		) * amount
		shaken_target += wobble
		shaken_eye += wobble * 0.35
	wipe_camera.fov = _ghost_camera_fov
	wipe_camera.global_position = shaken_eye
	if shaken_eye.distance_squared_to(shaken_target) > 0.0001:
		wipe_camera.look_at(shaken_target, Vector3.UP)


func _ghost_shot(death_position: Vector3, p: Dictionary) -> Dictionary:
	var t := float(p.get("performance_time", 0.0))
	var k := float(p.get("world_scale", 0.6)) / 0.6
	var out := Vector3(float(p.get("out_sign", 1.0)), 0.0, 0.0)
	var forward := Vector3.BACK  # 水路の前（ゲームの進む向き +Z）
	var chest: Vector3 = p.get("rider_chest", p.get("rider_position", death_position))
	var mount: Vector3 = p.get("mount_position", chest)
	var basis: Basis = p.get("mount_basis", Basis.IDENTITY)
	var shark_forward := basis.z.normalized()
	var shark_up := basis.y.normalized()
	var shark_side := basis.x.normalized()
	# サメの横のうち、ステージ側（out の逆）を正にする。
	if shark_side.dot(out) > 0.0:
		shark_side = -shark_side
	var source: Vector3 = p.get("death_position", death_position)
	var result: Dictionary
	if t < 1.40:
		# 出現：水面すれすれ・水路の前から、昇る魂を正面に見上げる。目覚め（1.27 秒）へゆっくり寄る。
		# 甲板の上で脱落したとき（壁への激突など）は前に問題の壁があるので、外側の斜め後ろから見る。
		var on_deck := source.y > StageConstants.FLOOR_TOP_Y - 1.0
		var eye := source + forward * 3.1 * k - out * 0.5 * k + Vector3.UP * 0.05 * k
		if on_deck:
			eye = source + out * 2.4 * k - forward * 1.6 * k + Vector3.UP * 0.35 * k
		result = {
			"name": "emerge",
			"eye": eye,
			"target": chest + Vector3.UP * 0.12 * k,
			"fov": lerpf(48.0, 39.0, smoothstep(0.55, 1.3, t)),
		}
	elif t < 4.05:
		# 飛ぶ：肩越しに前で待つサメを見せてから、ステージ側から並んで追う。
		var shoulder := {
			"eye": chest - forward * 3.6 * k - out * 0.9 * k + Vector3.UP * 1.25 * k,
			"target": chest.lerp(mount, 0.5),
			"fov": 54.0,
		}
		var track := {
			"eye": chest - out * 3.7 * k + Vector3.UP * 0.75 * k - forward * 0.9 * k,
			"target": chest.lerp(mount, lerpf(0.28, 0.55, smoothstep(2.6, 4.0, t))),
			"fov": lerpf(50.0, 45.0, smoothstep(3.0, 4.05, t)),
		}
		result = _blend_shots(shoulder, track, smoothstep(2.25, 2.85, t))
		result["name"] = "flight"
		result["cut"] = true
	elif t < 4.90:
		# 着座：サメの斜め前に切り替えて寄り、ゆるめていく。
		var local := t - 4.05
		var eye := mount + shark_forward * 2.3 * k + shark_side * 1.45 * k + shark_up * 0.85 * k
		result = {
			"name": "impact",
			"cut": true,
			"eye": eye,
			"target": mount + shark_up * 0.42 * k,
			"fov": lerpf(38.0, 47.0, smoothstep(0.0, 0.6, local)),
		}
	elif t < 7.05:
		# 力み：下からあおり、ゆっくり横へ回り込む。突き上げた拳と空・観客席を入れる。
		var local := t - 4.90
		var angle := deg_to_rad(lerpf(28.0, 62.0, smoothstep(0.0, 2.15, local)))
		var around := shark_forward.rotated(shark_up, angle * signf(shark_side.dot(shark_up.cross(shark_forward)) + 0.0001))
		var eye := mount + around * 2.9 * k - shark_up * 0.25 * k
		result = {
			"name": "power",
			"eye": eye,
			"target": mount + shark_up * 0.8 * k,
			"fov": 52.0,
		}
	elif t < 8.49:
		# 縦に立って昇る：背中（乗り手）の側の下から見上げる。昇り始めの位置に据えて、首を振って追う。
		if not _ghost_ascent_ready:
			_ghost_ascent_ready = true
			_ghost_ascent_anchor = mount
			_ghost_ascent_back = -shark_forward
			_ghost_ascent_side = shark_side
		var eye := _ghost_ascent_anchor + _ghost_ascent_back * 4.6 * k + _ghost_ascent_side * 2.6 * k + Vector3.UP * 0.35 * k
		result = {
			"name": "ascent",
			"eye": eye,
			"target": chest,
			"fov": lerpf(54.0, 62.0, smoothstep(7.1, 8.4, t)),
		}
	else:
		# 発進：後ろ上から追い、行く先を見る（サメの前後は水平にならして、腹の下に回り込まない）。
		var flat_forward := Vector3(shark_forward.x, 0.0, shark_forward.z)
		flat_forward = flat_forward.normalized() if flat_forward.length_squared() > 0.0001 else -out
		var eye := mount - flat_forward * 4.4 * k + Vector3.UP * 1.9 * k - out * 0.6 * k
		result = {
			"name": "chase",
			"eye": eye,
			"target": mount + flat_forward * 2.0 * k + Vector3.UP * 0.35 * k,
			"fov": 58.0,
		}
	if t < 7.0:
		_ghost_ascent_ready = false
	result["eye"] = _keep_ghost_camera_outside(result.eye, out)
	return result


func _blend_shots(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	return {
		"eye": (a.eye as Vector3).lerp(b.eye, weight),
		"target": (a.target as Vector3).lerp(b.target, weight),
		"fov": lerpf(float(a.fov), float(b.fov), weight),
	}


## ステージの体（甲板より下の側壁の内側）と水の中にカメラを入れない。甲板より上なら甲板の上でよい。
func _keep_ghost_camera_outside(eye: Vector3, out: Vector3) -> Vector3:
	var side := signf(out.x) if not is_zero_approx(out.x) else 1.0
	var below_deck := eye.y < StageConstants.FLOOR_TOP_Y + GHOST_CAMERA_DECK_CLEARANCE
	if below_deck and (absf(eye.x) < GHOST_CAMERA_MIN_SIDE_X or signf(eye.x) != side):
		eye.x = side * GHOST_CAMERA_MIN_SIDE_X
	eye.y = maxf(eye.y, StageConstants.OCEAN_SURFACE_Y + GHOST_CAMERA_MIN_WATER_CLEARANCE)
	return eye


## 着座・目覚め・柱の閃光（小窓に重ねる色）。
func play_ghost_flash(player_index: int, strength: float, color: Color) -> void:
	if not _active or _dead_player != player_index:
		return
	_ghost_flash = maxf(_ghost_flash, clampf(strength, 0.0, 1.0))
	_ghost_flash_color = color.lerp(Color.WHITE, 0.45)
	_ghost_punch = maxf(_ghost_punch, clampf(strength, 0.0, 1.0))


## 衝撃の揺れ（0〜1）。
func add_ghost_shake(player_index: int, strength: float) -> void:
	if not _active or _dead_player != player_index:
		return
	_ghost_shake = maxf(_ghost_shake, clampf(strength, 0.0, 1.0))

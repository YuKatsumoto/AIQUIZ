extends Control

## 壁速度設定画面
## 3D SubViewport で実際のプレイ画面に近いプレビューを表示し、
## スライダーで壁の速度を調整できる。

# --- Preview 3D nodes ---
var _sub_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_floor: MeshInstance3D
var _preview_walls: Array[Node3D] = []
var _preview_scroll_z: float = 0.0
var _preview_floor_material: ShaderMaterial
var _conveyor_roller_front_material: ShaderMaterial
var _conveyor_return_material: ShaderMaterial

# --- UI nodes ---
var _speed_slider: HSlider
var _speed_label: Label
var _speed_value_label: Label
var _back_btn: Button
var _reset_btn: Button
var _mode_label: Label

# --- State ---
var _wall_scene: PackedScene
var _preview_speed: float = 5.0
const WALL_SPACING := 30.0
const WALL_START_Z := 22.0
const CONVEYOR_FLOOR_SHADER: Shader = preload("res://shaders/conveyor_belt_floor.gdshader")

# --- Preview Player ---
const PLAYER_CONTROLLER_SCRIPT: Script = preload("res://scripts/world/player_controller.gd")
const PREVIEW_PLAYER_X: float = -3.5
## 2扉時のドア奥行き BoxMesh size.z=0.60 の半分（世界+Zへ伸びる側が先にキャラに届く）
const PREVIEW_DOOR_HALF_DEPTH_Z: float = 0.30
const PREVIEW_RED_DOOR_INDEX: int = 1
var _preview_player: Node3D
var _preview_gs: QuizGameState

# --- Conveyor Constants ---
const FLOOR_HALF_WIDTH: float = 12.0
const FLOOR_TOP_Y: float = -1.2
const FLOOR_RAIL_HEIGHT: float = 0.26 
const FLOOR_RAIL_WIDTH: float = 0.16
const FLOOR_RAIL_INSET: float = 0.06
const CONVEYOR_BELT_BASE_COLOR := Color(0.40, 0.41, 0.42, 1.0)
const CONVEYOR_BELT_STRIPE_COLOR := Color(0.34, 0.345, 0.35, 1.0)
const CONVEYOR_BELT_SIDE_COLOR := Color(0.33, 0.34, 0.35, 1.0)
const CONVEYOR_ROLLER_RADIUS: float = 0.48
const CONVEYOR_ROLLER_LENGTH: float = 23.4
const CONVEYOR_RETURN_BELT_THICKNESS: float = 0.10
const CONVEYOR_SIDE_FRAME_WIDTH: float = 0.24
const CONVEYOR_SIDE_FRAME_HEIGHT: float = 1.05

func _ready() -> void:
	_wall_scene = preload("res://scenes/quiz_wall.tscn")
	
	var game_state := QuizManager.game_state
	# 現在の速度設定を読み取り
	if game_state.tuning.wall_speed_override > 0:
		_preview_speed = game_state.tuning.wall_speed_override
	else:
		# 「自動」モードの場合、デフォルト速度を使用
		_preview_speed = 28.0 / (4.0 + 5.0)  # ≈ 3.11（MOVE_BUFFER=5.0に合わせた自動モード基準速度）
	
	_build_ui()
	_build_3d_preview()
	_update_speed_display()

func _process(dt: float) -> void:
	# 3Dプレビューのアニメーション（壁がカメラに向かって移動）
	var move_dist := _preview_speed * dt
	_preview_scroll_z += move_dist
	
	if _preview_floor_material:
		_preview_floor_material.set_shader_parameter("scroll_z", _preview_scroll_z)
	if _conveyor_roller_front_material:
		_conveyor_roller_front_material.set_shader_parameter("scroll_z", _preview_scroll_z)
	if _conveyor_return_material:
		_conveyor_return_material.set_shader_parameter("scroll_z", _preview_scroll_z)
	
	# 壁の位置を更新（前方に進ませ、崖で落下させる）
	for i in range(_preview_walls.size() - 1, -1, -1):
		var wall = _preview_walls[i]
		if not is_instance_valid(wall):
			_preview_walls.remove_at(i)
			continue
			
		# 壁を+Z方向（カメラ手前方向）へ移動
		wall.position.z += move_dist

		# 壁が +Z に進み、赤扉の手前側面がプレイヤーZに届いた瞬間に崩す（中心一致ではなく接触基準）
		var player_z: float = 0.0
		if _preview_gs:
			player_z = _preview_gs.player_local_z
		var door_leading_z: float = wall.position.z + PREVIEW_DOOR_HALF_DEPTH_Z
		if (
			MenuWallBackgroundPreview.wall_front_touches_player(door_leading_z, player_z)
			and not wall.get_meta("preview_door_broken", false)
		):
			if wall.has_method("break_door"):
				wall.break_door(PREVIEW_RED_DOOR_INDEX)
			wall.set_meta("preview_door_broken", true)
		
		# 崖 (Z=8.0) に到達したら、壁を物理パーツ化してマグマへ落とす
		if wall.position.z >= 8.0:
			_drop_wall_into_magma(wall)
			wall.queue_free()
			_preview_walls.remove_at(i)
			
	# 新しい壁を生成するための距離計算
	var furthest_z := 8.0
	for wall in _preview_walls:
		if is_instance_valid(wall) and wall.position.z < furthest_z:
			furthest_z = wall.position.z
			
	# カメラの奥（見えない位置）で壁が足りなくなったら生成
	if furthest_z > 8.0 - WALL_SPACING * 2.5:
		_spawn_preview_wall(furthest_z - WALL_SPACING)
	
	# プレビュープレイヤーのアニメーション更新（速度連動）
	if _preview_player and _preview_gs:
		_poll_preview_emote_inputs()
		_preview_gs._active_wall_speed = _preview_speed
		_preview_player.update_from_state(_preview_gs)
		# update_from_state は num_players==1 + STATE_PLAYING で visible=false に上書きするため強制表示
		_preview_player.visible = true
		_force_preview_player_facing_away()
	
	# カメラ付近の破片は縮小して消す（視界を塞がないため）
	_update_preview_debris_near_camera()

func _drop_wall_into_magma(wall: Node3D) -> void:
	if not wall or not is_instance_valid(wall):
		return
	
	for child in wall.get_children():
		if not (child is MeshInstance3D):
			continue
		var src_mesh := child as MeshInstance3D
		if not src_mesh.visible:
			continue
		var box_mesh := src_mesh.mesh as BoxMesh
		if not box_mesh:
			continue
		
		var piece := RigidBody3D.new()
		piece.mass = 3.2
		piece.gravity_scale = 2.4
		piece.linear_damp = 0.28
		piece.angular_damp = 0.38
		piece.collision_layer = 0
		piece.collision_mask = 1
		
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box_mesh.size
		col.shape = shape
		piece.add_child(col)
		
		var mesh_inst := MeshInstance3D.new()
		var mesh_copy := BoxMesh.new()
		mesh_copy.size = box_mesh.size
		mesh_inst.mesh = mesh_copy
		if src_mesh.material_override:
			mesh_inst.material_override = src_mesh.material_override.duplicate()
		piece.add_child(mesh_inst)
		
		_sub_viewport.add_child(piece)
		piece.global_transform = src_mesh.global_transform
		
		# 統合設定プレビューのソフト落下と同程度のわずかな吹き飛び
		piece.apply_central_impulse(Vector3(
			randf_range(-0.36, 0.36),
			randf_range(0.0, 0.48),
			randf_range(1.85, 3.85)
		))
		piece.apply_torque_impulse(Vector3(
			randf_range(-0.52, 0.52),
			randf_range(-0.32, 0.32),
			randf_range(-0.52, 0.52)
		))

func _force_preview_player_facing_away() -> void:
	var pc := _preview_player as PlayerController
	if not pc:
		return
	if not pc.p1_parts.has("pelvis"):
		return
	var pelvis := pc.p1_parts["pelvis"] as Node3D
	if not pelvis:
		return
	# update_from_state 内で毎フレーム姿勢が再適用されるため、最後に向きを固定する。
	pelvis.rotation.y = PI


func _read_emote_keys_pressed(slots_p1: Array) -> int:
	if Input.is_key_pressed(KEY_1) and slots_p1.size() > 0:
		return int(slots_p1[0])
	if Input.is_key_pressed(KEY_2) and slots_p1.size() > 1:
		return int(slots_p1[1])
	if Input.is_key_pressed(KEY_3) and slots_p1.size() > 2:
		return int(slots_p1[2])
	return 0


func _stop_preview_emotes() -> void:
	if not _preview_gs:
		return
	_preview_gs.p1_emote = 0
	var pc := _preview_player as PlayerController
	if pc:
		pc._p1_rig.stop_all()
	if _preview_player and _preview_player.has_method("update_from_state"):
		_preview_player.update_from_state(_preview_gs)


func _poll_preview_emote_inputs() -> void:
	if not _preview_gs:
		return
	var gm := QuizManager.game_state
	if Input.is_key_pressed(KEY_SPACE):
		_stop_preview_emotes()
		return
	var emote_p1 := _read_emote_keys_pressed(gm.p1_emote_slots)
	if emote_p1 > 0 and _preview_gs.p1_alive and _preview_gs.player_vel_y == 0.0:
		_preview_gs.p1_emote = emote_p1


func _update_preview_debris_near_camera() -> void:
	if not _sub_viewport or not _preview_camera:
		return
	
	const FADE_START_DIST: float = 7.5
	const KILL_DIST: float = 2.0
	const SCALE_FLOOR: float = 0.02
	
	for child in _sub_viewport.get_children():
		if child is RigidBody3D:
			var body := child as RigidBody3D
			if body.get_meta("preview_door_shard", false):
				var d_far_w := body.global_position.distance_to(_preview_camera.global_position)
				if d_far_w > 48.0 or body.global_position.y < -14.0:
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

func _build_ui() -> void:
	# ── 3Dプレビュー背景（全画面） ──
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	add_child(svc)
	
	_sub_viewport = SubViewport.new()
	_sub_viewport.size = Vector2i(1280, 720)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.transparent_bg = false
	_sub_viewport.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_sub_viewport)
	
	# ── UIオーバーレイ（フロートパネル） ──
	var margin_container := MarginContainer.new()
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_right", 40)
	margin_container.add_theme_constant_override("margin_top", 40)
	margin_container.add_theme_constant_override("margin_bottom", 40)
	margin_container.add_theme_constant_override("margin_left", 40)
	add_child(margin_container)
	
	var h_split := HBoxContainer.new()
	margin_container.add_child(h_split)
	
	# 左側の空きスペース（プレビューを見せるため）
	var spacer_left := Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_left.size_flags_stretch_ratio = 1.2
	h_split.add_child(spacer_left)
	
	# 右側の設定パネル
	var settings_panel := PanelContainer.new()
	settings_panel.custom_minimum_size = Vector2(480, 0)
	settings_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var settings_style := StyleBoxFlat.new()
	settings_style.bg_color = Color(0.05, 0.08, 0.12, 0.85)
	settings_style.set_border_width_all(2)
	settings_style.border_color = Color(0.3, 0.4, 0.6, 0.5)
	settings_style.set_corner_radius_all(24)
	settings_style.content_margin_left = 32.0
	settings_style.content_margin_right = 32.0
	settings_style.content_margin_top = 24.0
	settings_style.content_margin_bottom = 24.0
	settings_panel.add_theme_stylebox_override("panel", settings_style)
	h_split.add_child(settings_panel)
	
	var settings_vbox := VBoxContainer.new()
	settings_vbox.add_theme_constant_override("separation", 16)
	settings_panel.add_child(settings_vbox)
	
	# タイトル
	var title := Label.new()
	title.text = "⚡ 壁速度設定"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_vbox.add_child(title)
	
	# 説明
	var desc := Label.new()
	desc.text = "壁が手前に向かって移動する速度を調整します。\n速度が速いほど解答時間が短くなります。"
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_vbox.add_child(desc)
	
	# 現在のモード表示
	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 16)
	_mode_label.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_mode_label()
	
	var mode_panel := PanelContainer.new()
	var mode_style := StyleBoxFlat.new()
	mode_style.bg_color = Color(0.1, 0.15, 0.25, 0.6)
	mode_style.set_corner_radius_all(12)
	mode_style.content_margin_top = 8
	mode_style.content_margin_bottom = 8
	mode_panel.add_theme_stylebox_override("panel", mode_style)
	mode_panel.add_child(_mode_label)
	settings_vbox.add_child(mode_panel)
	
	# セパレータ
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(1, 1, 1, 0.1)
	sep.add_theme_stylebox_override("separator", sep_style)
	settings_vbox.add_child(sep)
	
	# 速度ラベル
	_speed_label = Label.new()
	_speed_label.text = "現在の速度"
	_speed_label.add_theme_font_size_override("font_size", 18)
	_speed_label.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_vbox.add_child(_speed_label)
	
	# 速度値表示（大きいフォント）
	_speed_value_label = Label.new()
	_speed_value_label.add_theme_font_size_override("font_size", 48)
	_speed_value_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	_speed_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_vbox.add_child(_speed_value_label)
	
	# スライダー
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 1.0
	_speed_slider.max_value = 10.0
	_speed_slider.step = 0.1
	_speed_slider.value = _preview_speed
	_speed_slider.custom_minimum_size = Vector2(0, 36)
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.value_changed.connect(_on_speed_changed)
	
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	slider_bg.set_corner_radius_all(10)
	slider_bg.expand_margin_top = 4
	slider_bg.expand_margin_bottom = 4
	
	_speed_slider.add_theme_stylebox_override("slider", slider_bg)
	_speed_slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	_speed_slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	
	settings_vbox.add_child(_speed_slider)
	
	# スライダーの範囲ラベル
	var range_hbox := HBoxContainer.new()
	settings_vbox.add_child(range_hbox)
	
	var slow_label := Label.new()
	slow_label.text = "🐢 遅い"
	slow_label.add_theme_font_size_override("font_size", 14)
	slow_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	slow_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_hbox.add_child(slow_label)
	
	var fast_label := Label.new()
	fast_label.text = "🐇 速い"
	fast_label.add_theme_font_size_override("font_size", 14)
	fast_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	fast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_hbox.add_child(fast_label)
	
	# スペーサー
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	settings_vbox.add_child(spacer)
	
	# ボタン行
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 12)
	settings_vbox.add_child(btn_vbox)
	
	# リセット（自動モード）ボタン
	_reset_btn = Button.new()
	_reset_btn.text = "🔄 自動モードに戻す"
	_reset_btn.custom_minimum_size = Vector2(0, 44)
	_reset_btn.add_theme_font_size_override("font_size", 16)
	_reset_btn.pressed.connect(_on_reset_pressed)
	btn_vbox.add_child(_reset_btn)

	var emote_hint := Label.new()
	emote_hint.text = "左プレビュー: キー 1・2・3 でエモート  Spaceで停止"
	emote_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emote_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	emote_hint.add_theme_font_size_override("font_size", 11)
	emote_hint.add_theme_color_override("font_color", Color(0.55, 0.60, 0.72))
	btn_vbox.add_child(emote_hint)
	
	# 戻るボタン
	_back_btn = Button.new()
	_back_btn.text = "✓ 決定して戻る"
	_back_btn.custom_minimum_size = Vector2(0, 52)
	_back_btn.add_theme_font_size_override("font_size", 18)
	_back_btn.pressed.connect(_on_back_pressed)
	btn_vbox.add_child(_back_btn)
	
	# ボタンスタイル適用
	_style_buttons()

func _style_buttons() -> void:
	# 通常ボタン
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.14, 0.16, 0.22, 0.8)
	normal_style.border_color = Color(0.28, 0.32, 0.42, 0.8)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(12)
	normal_style.content_margin_left = 16.0
	normal_style.content_margin_right = 16.0
	normal_style.content_margin_top = 8.0
	normal_style.content_margin_bottom = 8.0
	
	var hover_style := normal_style.duplicate()
	hover_style.bg_color = Color(0.18, 0.20, 0.28, 0.9)
	hover_style.border_color = Color(0.4, 0.5, 0.7, 0.9)
	
	for btn: Button in [_reset_btn]:
		btn.add_theme_stylebox_override("normal", normal_style.duplicate())
		btn.add_theme_stylebox_override("hover", hover_style.duplicate())
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
		btn.add_theme_color_override("font_hover_color", Color(0.95, 0.97, 1.0))
	
	# 決定ボタン（アクセントカラー）
	var accent_style := StyleBoxFlat.new()
	accent_style.bg_color = Color(0.15, 0.35, 0.65, 0.85)
	accent_style.border_color = Color(0.3, 0.55, 0.9, 0.8)
	accent_style.set_border_width_all(2)
	accent_style.set_corner_radius_all(14)
	accent_style.content_margin_left = 20.0
	accent_style.content_margin_right = 20.0
	accent_style.content_margin_top = 10.0
	accent_style.content_margin_bottom = 10.0
	
	var accent_hover := accent_style.duplicate()
	accent_hover.bg_color = Color(0.2, 0.42, 0.75, 0.95)
	accent_hover.border_color = Color(0.4, 0.65, 1.0, 0.9)
	
	_back_btn.add_theme_stylebox_override("normal", accent_style)
	_back_btn.add_theme_stylebox_override("hover", accent_hover)
	_back_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_back_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

func _build_3d_preview() -> void:
	# ── 3Dシーンを SubViewport 内に構築 ──
	
	# 環境設定 (本番環境に合わせる)
	var bg_color := Color(0.82, 0.85, 0.90)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg_color
	env.ambient_light_color = Color(0.30, 0.32, 0.35)
	env.ambient_light_energy = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	
	# Fog
	env.fog_enabled = true
	env.fog_light_color = bg_color
	env.fog_density = 0.002
	env.fog_aerial_perspective = 0.5

	# Tonemap
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0

	# Glow
	env.glow_intensity = 0.5
	env.glow_strength = 0.8
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.8
	env.set_glow_level(0, true)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, false)
	
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_sub_viewport.add_child(world_env)
	
	# ライト
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -20, 0)
	light.light_energy = 0.8
	light.shadow_enabled = true
	_sub_viewport.add_child(light)
	
	# カメラ（プレイヤー視点に近い角度）
	_preview_camera = Camera3D.new()
	# カメラを崖（Z=8）の外側まで下げ、壁と衝突しない位置に配置
	_preview_camera.position = Vector3(4.5, 4.5, 16.0) 
	_preview_camera.rotation_degrees = Vector3(-14, 15, 0)
	_preview_camera.fov = 65.0
	_sub_viewport.add_child(_preview_camera)
	
	# 床 (本番環境と一致するBoxMesh)
	_preview_floor = MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(24.0, 16.0, 144.0)
	_preview_floor.mesh = floor_mesh
	_preview_floor_material = ShaderMaterial.new()
	_preview_floor_material.shader = CONVEYOR_FLOOR_SHADER
	_preview_floor_material.set_shader_parameter("scroll_z", 0.0)
	_preview_floor_material.set_shader_parameter("scroll_sign", -1.0)
	_preview_floor.material_override = _preview_floor_material
	# 床の端（崖）がちょうどZ=8になるように位置を調整（size.z=144なので、-64 + 72 = 8）
	_preview_floor.position = Vector3(0, -9.2, -64.0)
	_sub_viewport.add_child(_preview_floor)
	
	# マグマの追加
	var magma_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(800.0, 800.0)
	plane.subdivide_width = 200
	plane.subdivide_depth = 200
	magma_mesh.mesh = plane
	magma_mesh.position = Vector3(0, -10.0, 150.0)
	magma_mesh.custom_aabb = AABB(Vector3(-400, -10, -400), Vector3(800, 20, 800))
	
	var mmat := ShaderMaterial.new()
	mmat.shader = StageConstants.MAGMA_SHADER
	
	# Procedural noise texture 1 (Perlin-like)
	var noise1 := NoiseTexture2D.new()
	var fnl1 := FastNoiseLite.new()
	fnl1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl1.frequency = 0.01
	fnl1.fractal_octaves = 4
	fnl1.fractal_lacunarity = 2.0
	fnl1.fractal_gain = 0.5
	noise1.noise = fnl1
	noise1.seamless = true
	noise1.width = 512
	noise1.height = 512
	mmat.set_shader_parameter("noise_tex", noise1)
	
	# Procedural noise texture 2 (Cellular for cracks)
	var noise2 := NoiseTexture2D.new()
	var fnl2 := FastNoiseLite.new()
	fnl2.noise_type = FastNoiseLite.TYPE_CELLULAR
	fnl2.frequency = 0.015
	fnl2.fractal_octaves = 3
	fnl2.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	fnl2.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	noise2.noise = fnl2
	noise2.seamless = true
	noise2.width = 512
	noise2.height = 512
	mmat.set_shader_parameter("noise_tex2", noise2)
	
	magma_mesh.material_override = mmat
	_sub_viewport.add_child(magma_mesh)
	
	# コンベアのレールやローラーを追加
	_setup_conveyor_extras()
	
	# プレビュー用の壁を初期配置（3枚）
	var start_z := 8.0 - WALL_SPACING * 2
	for i in range(3):
		_spawn_preview_wall(start_z + i * WALL_SPACING)
	
	# プレビュー専用 GameState（QuizManager.game_state には触れず独立）
	_preview_gs = QuizGameState.new()
	_preview_gs.game_state = Constants.STATE_PLAYING
	_preview_gs.num_players = 1
	_preview_gs.p1_alive = true
	_preview_gs.player_x = PREVIEW_PLAYER_X
	_preview_gs.player_y = 0.0
	_preview_gs.player_z = 0.0
	_preview_gs.world_scroll_z = 0.0
	_preview_gs.p1_emote = 0
	_preview_gs.p1_jump_trigger = false
	_preview_gs.p1_moving_back = false
	_preview_gs.player_vel_y = 0.0
	_preview_gs._active_wall_speed = _preview_speed
	
	# ゲーム内 (game_world.tscn) の Player と同一条件: 無回転で SubViewport 直下に追加
	_preview_player = Node3D.new()
	_preview_player.set_script(PLAYER_CONTROLLER_SCRIPT)
	_sub_viewport.add_child(_preview_player)
	
	# 帽子をメインメニューで選択されているものに合わせる
	var gm := QuizManager.game_state
	if _preview_player.has_method("set_hat"):
		_preview_player.set_hat(1, gm.p1_hat)


func _spawn_preview_wall(z_pos: float) -> void:
	var dummy_quiz := QuizItem.new()
	dummy_quiz.q = "プレビュー"
	dummy_quiz.c = ["A", "B"]
	
	var wall = _wall_scene.instantiate()
	wall.position.z = z_pos
	_sub_viewport.add_child(wall)
	if wall.has_method("set_quiz"):
		wall.set_quiz(dummy_quiz, 2)
	_preview_walls.append(wall)

func _setup_conveyor_extras() -> void:
	var floor_length := 144.0
	var floor_center_z := -64.0
	var half_len := floor_length * 0.5
	var front_z := floor_center_z + half_len # ベルト端に完全一致（隙間をなくす）
	var top_front_contact_z := floor_center_z + half_len # 8.0
	var roller_center_y := FLOOR_TOP_Y - CONVEYOR_ROLLER_RADIUS # 上端=ベルト面、半分を床に埋め込む
	
	# 0. 物理衝突用の床（壁がめり込まないようにする）
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(24.0, 0.5, floor_length)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	# 床上面がFLOOR_TOP_Yにぴったり合うように配置
	floor_body.position = Vector3(0, FLOOR_TOP_Y - 0.25, floor_center_z)
	_sub_viewport.add_child(floor_body)
	
	# 1. ローラー (Front)
	var roller_mesh := CylinderMesh.new()
	roller_mesh.top_radius = CONVEYOR_ROLLER_RADIUS
	roller_mesh.bottom_radius = CONVEYOR_ROLLER_RADIUS
	roller_mesh.height = CONVEYOR_ROLLER_LENGTH
	roller_mesh.radial_segments = 64
	roller_mesh.rings = 4
	
	_conveyor_roller_front_material = ShaderMaterial.new()
	_conveyor_roller_front_material.shader = CONVEYOR_FLOOR_SHADER
	_conveyor_roller_front_material.set_shader_parameter("scroll_z", 0.0)
	_conveyor_roller_front_material.set_shader_parameter("scroll_sign", -1.0) # プレビュー用の進行方向合わせ
	_conveyor_roller_front_material.set_shader_parameter("roller_mode", 1.0)
	_conveyor_roller_front_material.set_shader_parameter("roller_radius", CONVEYOR_ROLLER_RADIUS)
	_conveyor_roller_front_material.set_shader_parameter("roller_contact_z", top_front_contact_z)
	_conveyor_roller_front_material.set_shader_parameter("roller_arc_sign", 1.0)
	_conveyor_roller_front_material.set_shader_parameter("base_color", CONVEYOR_BELT_BASE_COLOR)
	_conveyor_roller_front_material.set_shader_parameter("stripe_color", CONVEYOR_BELT_STRIPE_COLOR)
	_conveyor_roller_front_material.set_shader_parameter("side_color", CONVEYOR_BELT_SIDE_COLOR)
	_conveyor_roller_front_material.set_shader_parameter("stripe_scale", 12.0)
	_conveyor_roller_front_material.set_shader_parameter("stripe_softness", 0.08)
	_conveyor_roller_front_material.set_shader_parameter("groove_strength", 0.12)
	_conveyor_roller_front_material.set_shader_parameter("roughness_val", 0.72)
	_conveyor_roller_front_material.set_shader_parameter("metallic_val", 0.16)
	
	var roller_front := MeshInstance3D.new()
	roller_front.mesh = roller_mesh
	roller_front.material_override = _conveyor_roller_front_material
	roller_front.rotation = Vector3(0.0, 0.0, PI * 0.5)
	roller_front.position = Vector3(0.0, roller_center_y, front_z)
	var body_f := StaticBody3D.new()
	body_f.collision_layer = 1
	body_f.collision_mask = 0
	var col_f := CollisionShape3D.new()
	var shape_f := CylinderShape3D.new()
	shape_f.radius = CONVEYOR_ROLLER_RADIUS
	shape_f.height = CONVEYOR_ROLLER_LENGTH
	col_f.shape = shape_f
	body_f.add_child(col_f)
	roller_front.add_child(body_f)
	_sub_viewport.add_child(roller_front)
	
	# 2. リターンベルト (ローラーの下を通る折り返し)
	var return_mesh := BoxMesh.new()
	return_mesh.size = Vector3(CONVEYOR_ROLLER_LENGTH, CONVEYOR_RETURN_BELT_THICKNESS, 8.0)
	var return_belt := MeshInstance3D.new()
	return_belt.mesh = return_mesh
	_conveyor_return_material = ShaderMaterial.new()
	_conveyor_return_material.shader = CONVEYOR_FLOOR_SHADER
	_conveyor_return_material.set_shader_parameter("scroll_z", 0.0)
	_conveyor_return_material.set_shader_parameter("scroll_sign", 1.0) # 逆方向
	_conveyor_return_material.set_shader_parameter("base_color", CONVEYOR_BELT_BASE_COLOR)
	_conveyor_return_material.set_shader_parameter("stripe_color", CONVEYOR_BELT_STRIPE_COLOR)
	_conveyor_return_material.set_shader_parameter("side_color", CONVEYOR_BELT_SIDE_COLOR)
	return_belt.material_override = _conveyor_return_material
	return_belt.position = Vector3(0.0, roller_center_y - CONVEYOR_ROLLER_RADIUS, front_z - 4.0)
	_sub_viewport.add_child(return_belt)
	
	# 3. レールとサイドフレーム
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(FLOOR_RAIL_WIDTH, FLOOR_RAIL_HEIGHT, floor_length)
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.27, 0.275, 0.28)
	rail_mat.roughness = 0.66
	
	var rail_y := FLOOR_TOP_Y + FLOOR_RAIL_HEIGHT * 0.5
	var rail_x := FLOOR_HALF_WIDTH - FLOOR_RAIL_WIDTH * 0.5 - FLOOR_RAIL_INSET
	
	var rail_l := MeshInstance3D.new()
	rail_l.mesh = rail_mesh
	rail_l.material_override = rail_mat
	rail_l.position = Vector3(-rail_x, rail_y, floor_center_z)
	_sub_viewport.add_child(rail_l)
	
	var rail_r := MeshInstance3D.new()
	rail_r.mesh = rail_mesh
	rail_r.material_override = rail_mat
	rail_r.position = Vector3(rail_x, rail_y, floor_center_z)
	_sub_viewport.add_child(rail_r)
	
	var side_frame_mesh := BoxMesh.new()
	side_frame_mesh.size = Vector3(CONVEYOR_SIDE_FRAME_WIDTH, CONVEYOR_SIDE_FRAME_HEIGHT, floor_length)
	var side_frame_mat := StandardMaterial3D.new()
	side_frame_mat.albedo_color = Color(0.30, 0.31, 0.33)
	side_frame_mat.roughness = 0.62
	
	var frame_y := FLOOR_TOP_Y + CONVEYOR_SIDE_FRAME_HEIGHT * 0.5 - 0.26
	var frame_x := FLOOR_HALF_WIDTH - CONVEYOR_SIDE_FRAME_WIDTH * 0.5
	
	var frame_l := MeshInstance3D.new()
	frame_l.mesh = side_frame_mesh
	frame_l.material_override = side_frame_mat
	frame_l.position = Vector3(-frame_x, frame_y, floor_center_z)
	_sub_viewport.add_child(frame_l)
	
	var frame_r := MeshInstance3D.new()
	frame_r.mesh = side_frame_mesh
	frame_r.material_override = side_frame_mat
	frame_r.position = Vector3(frame_x, frame_y, floor_center_z)
	_sub_viewport.add_child(frame_r)

func _update_mode_label() -> void:
	var game_state := QuizManager.game_state
	if game_state.tuning.wall_speed_override > 0:
		_mode_label.text = "📌 手動モード（固定速度）"
		_mode_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	else:
		_mode_label.text = "🤖 自動モード（AI解答時間から算出）"
		_mode_label.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))

func _update_speed_display() -> void:
	_speed_value_label.text = "%.1f" % _preview_speed
	
	# 速度に応じて色を変える
	var t: float = (_preview_speed - 2.0) / 8.0  # 0.0 ~ 1.0
	var col := Color(0.3, 1.0, 0.5).lerp(Color(1.0, 0.3, 0.2), t)
	_speed_value_label.add_theme_color_override("font_color", col)

func _on_speed_changed(value: float) -> void:
	_preview_speed = value
	_update_speed_display()
	
	# tuningに即反映（手動モード）
	var game_state := QuizManager.game_state
	game_state.tuning.wall_speed_override = value
	_update_mode_label()

func _on_reset_pressed() -> void:
	# 自動モードに戻す
	var game_state := QuizManager.game_state
	game_state.tuning.wall_speed_override = 0.0
	
	# デフォルト速度を再計算
	_preview_speed = 28.0 / (4.0 + 5.0)  # MOVE_BUFFER=5.0に合わせた自動モード基準速度
	_speed_slider.value = _preview_speed
	_update_speed_display()
	_update_mode_label()

func _on_back_pressed() -> void:
	_stop_preview_emotes()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

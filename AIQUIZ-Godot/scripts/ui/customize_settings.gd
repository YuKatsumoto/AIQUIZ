extends Control

enum Section {
	WALL_SPEED,
	SKIN,
	EMOTE,
}

const WALL_SCENE: PackedScene = preload("res://scenes/quiz_wall.tscn")
const CONVEYOR_FLOOR_SHADER: Shader = preload("res://shaders/conveyor_belt_floor.gdshader")
const PLAYER_CONTROLLER_SCRIPT: Script = preload("res://scripts/world/player_controller.gd")

const WALL_SPACING := 30.0
## 左レーンP1（壁速度プレビューと同じオフセット）／右レーンP2は対称配置
const PREVIEW_PLAYER_P1_X: float = -3.5
const PREVIEW_PLAYER_P2_X: float = 3.5
## スキンプレビュー：runner の反対側（-Z）から正面を見る
const SKIN_PREVIEW_CAM_DIST_Z: float = 2.95
const SKIN_PREVIEW_CAM_Y: float = 1.35
const SKIN_PREVIEW_CAM_LOOK_Y: float = 1.08
const SKIN_PREVIEW_FOV: float = 38.0
## セクション間カメラ切替のスムーズさ（大きいほど早く目的値に追従）
const CAM_PREVIEW_SMOOTH_RATE: float = 9.0
const PREVIEW_DOOR_HALF_DEPTH_Z: float = 0.30
const PREVIEW_BLUE_DOOR_INDEX: int = 0
const PREVIEW_RED_DOOR_INDEX: int = 1
const AUTO_WALL_SPEED: float = 28.0 / (4.0 + 5.0)
## エモートタブ時にベルト表示速度が 0 に近づく時間感（大きいほどゆっくり停止）
const BELT_VISUAL_RAMP_TAU_SEC: float = 2.8
## game_world の「次の問題を準備中」壁合体プレビューに合わせたパラメータ
const PREVIEW_MERGE_SLIDE_START_X: float = 150.0
const PREVIEW_MERGE_INTERVAL_SEC: float = 0.15
const PREVIEW_MERGE_SLIDE_DURATION: float = 0.125
const PREVIEW_MERGE_FLASH_DURATION: float = 0.175
const PREVIEW_DEBRIS_LIFETIME_SEC: float = 5.0
## 壁速度プレビュー：崖端〜マグマで割れた壁本体の「ボトッと落ちる」破片（wall_speed と質量・減衰・インパルスを同期）
const PREVIEW_SOFT_FALL_DEBRIS_MASS: float = 3.2
const PREVIEW_SOFT_FALL_DEBRIS_GRAVITY_SCALE: float = 2.4
const PREVIEW_SOFT_FALL_DEBRIS_LINEAR_DAMP: float = 0.28
const PREVIEW_SOFT_FALL_DEBRIS_ANGULAR_DAMP: float = 0.38
## ソフト落下のわずかな吹き飛び（以前よりやや強め・壁本体と扉破片で揃える）
const PREVIEW_SOFT_FALL_IMP_X: float = 0.36
const PREVIEW_SOFT_FALL_IMP_Y: float = 0.48
const PREVIEW_SOFT_FALL_IMP_Z_MIN: float = 1.85
const PREVIEW_SOFT_FALL_IMP_Z_MAX: float = 3.85
const PREVIEW_SOFT_FALL_TORQUE: float = 0.52
## プレビュー破片：カメラに近づいたら縮小し、十分小さくなったら削除（wall_speed_settings と同系）
const PREVIEW_DEBRIS_FADE_START_DIST: float = 7.5
const PREVIEW_DEBRIS_KILL_DIST: float = 2.0
const PREVIEW_DEBRIS_SCALE_FLOOR: float = 0.02
const PREVIEW_DEBRIS_Y_KILL: float = -14.0

const FLOOR_HALF_WIDTH: float = 12.0
const FLOOR_TOP_Y: float = -1.2
## エモートカメラ（emote_select と同じオービット）、床より下にレンズが入らないよう Y をクランプ
const EMOTE_CAM_MIN_WORLD_Y: float = FLOOR_TOP_Y + 0.72
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

var _sub_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_floor_material: ShaderMaterial
var _conveyor_roller_front_material: ShaderMaterial
var _conveyor_return_material: ShaderMaterial
var _preview_walls: Array[Node3D] = []
var _merge_left_sils: Array[MeshInstance3D] = []
var _merge_right_sils: Array[MeshInstance3D] = []
var _merge_anims: Array[Dictionary] = []
var _merge_started: Array[bool] = []
var _merge_timer: float = 0.0
var _preview_scroll_z: float = 0.0

var _preview_player: Node3D
var _preview_gs: QuizGameState
var _preview_speed: float = AUTO_WALL_SPEED
## プレビュー上のコンベア／壁の実際の移動速度（エモートタブではゆっくり 0 に落とす）
var _belt_visual_speed: float = AUTO_WALL_SPEED
var _active_section: Section = Section.WALL_SPEED
var _editing_player: int = 1

var _emote_preview_holder: Node3D
## P1／P2 レーンごとの FBX＋ブロック人形プレビュー
var _emote_lane_previews: Array[Dictionary] = []
var _emote_preview_time: float = 0.0
var _current_preview_emote_id: int = EmoteData.EMOTE_NONE

const SLOT_KEYS_P1 := ["1", "2", "3"]
const SLOT_KEYS_P2 := ["8", "9", "0"]

var _section_buttons: Dictionary = {}
var _section_title: Label
var _wall_panel: VBoxContainer
var _skin_panel: VBoxContainer
var _emote_panel: VBoxContainer

var _mode_label: Label
var _speed_value_label: Label
var _speed_slider: HSlider

var _skin_player_label: Label
var _skin_player_btn_p1: Button
var _skin_player_btn_p2: Button
var _hat_name_label: Label

var _emote_player_toggle_btn: Button
var _slot_labels: Array[Label] = []
var _emote_grid: GridContainer
var _selected_grid_btn: Button = null
var _grid_card_by_id: Dictionary = {}
var _browsing_emote_id: int = 0

var _preview_svc: SubViewportContainer
## 左プレビュー上でエモート操作を取る（全面 UI の背後にある SubViewport には届かないため）
var _preview_input_catcher: Control
## エモートタブ用オービット（emote_select.gd と同じ操作・係数）
var _emote_cam_yaw: float = 0.0
var _emote_cam_pitch: float = -8.0
var _emote_cam_distance: float = 4.0
var _emote_cam_target: Vector3 = Vector3(PREVIEW_PLAYER_P1_X, 0.2, 0.0)
var _emote_cam_dragging: bool = false
var _emote_cam_panning: bool = false

func _ready() -> void:
	var game_state := QuizManager.game_state
	if game_state.tuning.wall_speed_override > 0.0:
		_preview_speed = game_state.tuning.wall_speed_override
	_belt_visual_speed = _preview_speed

	_build_ui()
	_build_3d_preview()
	_browsing_emote_id = game_state.p1_emote_slots[0] if game_state.p1_emote_slots.size() > 0 else EmoteData.EMOTE_NONE
	_refresh_all_labels()
	_set_section(Section.WALL_SPEED)
	_snap_preview_camera_to_current_section()

func _process(dt: float) -> void:
	var belt_target := 0.0 if _active_section == Section.EMOTE else _preview_speed
	var alpha := 1.0 - exp(-dt / BELT_VISUAL_RAMP_TAU_SEC)
	_belt_visual_speed = lerpf(_belt_visual_speed, belt_target, alpha)
	if absf(_belt_visual_speed - belt_target) < 0.003:
		_belt_visual_speed = belt_target

	var move_dist := _belt_visual_speed * dt
	_preview_scroll_z += move_dist

	if _preview_floor_material:
		_preview_floor_material.set_shader_parameter("scroll_z", _preview_scroll_z)
	if _conveyor_roller_front_material:
		_conveyor_roller_front_material.set_shader_parameter("scroll_z", _preview_scroll_z)
	if _conveyor_return_material:
		_conveyor_return_material.set_shader_parameter("scroll_z", _preview_scroll_z)

	for i in range(_preview_walls.size() - 1, -1, -1):
		var wall := _preview_walls[i]
		if not is_instance_valid(wall):
			_remove_preview_merge_slots_at(i)
			_preview_walls.remove_at(i)
			continue

		wall.position.z += move_dist

		var door_leading_z: float = wall.position.z + PREVIEW_DOOR_HALF_DEPTH_Z
		var p1_z: float = _preview_gs.player_local_z if _preview_gs else 0.0
		var p2_z: float = _preview_gs.player2_local_z if _preview_gs else p1_z
		var crossed_row := door_leading_z >= p1_z or door_leading_z >= p2_z
		if (
			wall.visible
			and crossed_row
			and not wall.get_meta("preview_doors_broken", false)
		):
			if wall.has_method("break_door"):
				wall.break_door(PREVIEW_BLUE_DOOR_INDEX)
				wall.break_door(PREVIEW_RED_DOOR_INDEX)
			wall.set_meta("preview_doors_broken", true)

		if wall.position.z >= 8.0:
			_drop_wall_into_magma(wall)
			wall.queue_free()
			_remove_preview_merge_slots_at(i)
			_preview_walls.remove_at(i)

	_process_preview_wall_merge(dt)

	var furthest_z := 8.0
	for wall in _preview_walls:
		if is_instance_valid(wall) and wall.position.z < furthest_z:
			furthest_z = wall.position.z
	if _active_section == Section.WALL_SPEED and furthest_z > 8.0 - WALL_SPACING * 2.5:
		_spawn_preview_wall(furthest_z - WALL_SPACING)

	if _preview_player and _preview_gs:
		_preview_gs._active_wall_speed = _belt_visual_speed
		_preview_player.update_from_state(_preview_gs)
		_preview_player.visible = _active_section != Section.EMOTE
		_force_preview_player_facing_away()

	_update_preview_debris_near_camera()

	if _active_section == Section.EMOTE:
		_emote_preview_time += dt
		var cam_move := Vector2.ZERO
		if Input.is_key_pressed(KEY_W):
			cam_move.y -= 1
		if Input.is_key_pressed(KEY_S):
			cam_move.y += 1
		if Input.is_key_pressed(KEY_A):
			cam_move.x -= 1
		if Input.is_key_pressed(KEY_D):
			cam_move.x += 1
		if cam_move != Vector2.ZERO:
			var yaw_rad_move := deg_to_rad(_emote_cam_yaw)
			var right_mv := Vector3(cos(yaw_rad_move), 0, -sin(yaw_rad_move))
			var forward_mv := Vector3(sin(yaw_rad_move), 0, cos(yaw_rad_move))
			_emote_cam_target += (right_mv * cam_move.x + forward_mv * cam_move.y) * dt * 2.0
		for entry in _emote_lane_previews:
			var br: Node3D = entry.get("block_root", null)
			if br == null or not is_instance_valid(br):
				continue
			if _current_preview_emote_id == EmoteData.EMOTE_NONE:
				br.rotation.y = sin(_emote_preview_time * 0.6) * 0.5
			else:
				br.rotation.y = 0.0
				var ap: AnimationPlayer = entry.get("ap", null)
				var skel: Skeleton3D = entry.get("skel", null)
				var parts: Dictionary = entry.get("parts", {})
				var bones: Dictionary = entry.get("bones", {})
				var rm: Dictionary = entry.get("rm", {})
				var lx_lane: float = float(entry.get("lane_x", 0.0))
				if (
					ap
					and ap.is_playing()
					and skel
					and not parts.is_empty()
				):
					EmoteBlockmanPreview.apply_skeleton_pose(
						parts,
						skel,
						bones,
						true,
						br,
						rm,
						lx_lane,
					)

	if _preview_camera:
		_apply_preview_camera_smoothing(dt)

func _build_ui() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	add_child(svc)
	_preview_svc = svc

	_sub_viewport = SubViewport.new()
	_sub_viewport.size = Vector2i(1280, 720)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.transparent_bg = false
	_sub_viewport.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_sub_viewport)

	var margin_container := MarginContainer.new()
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_right", 40)
	margin_container.add_theme_constant_override("margin_top", 40)
	margin_container.add_theme_constant_override("margin_bottom", 40)
	margin_container.add_theme_constant_override("margin_left", 40)
	add_child(margin_container)

	var h_split := HBoxContainer.new()
	h_split.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin_container.add_child(h_split)

	var spacer_left := Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_left.size_flags_stretch_ratio = 1.15
	spacer_left.mouse_filter = Control.MOUSE_FILTER_STOP
	spacer_left.gui_input.connect(_on_emote_preview_gui_input)
	_preview_input_catcher = spacer_left
	h_split.add_child(spacer_left)

	var settings_panel := PanelContainer.new()
	settings_panel.custom_minimum_size = Vector2(520, 0)
	settings_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var settings_style := StyleBoxFlat.new()
	settings_style.bg_color = Color(0.05, 0.08, 0.12, 0.86)
	settings_style.set_border_width_all(2)
	settings_style.border_color = Color(0.3, 0.4, 0.6, 0.5)
	settings_style.set_corner_radius_all(24)
	settings_style.content_margin_left = 28.0
	settings_style.content_margin_right = 28.0
	settings_style.content_margin_top = 24.0
	settings_style.content_margin_bottom = 24.0
	settings_panel.add_theme_stylebox_override("panel", settings_style)
	h_split.add_child(settings_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	settings_panel.add_child(vbox)

	_section_title = Label.new()
	_section_title.text = "統合設定"
	_section_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_section_title.add_theme_font_size_override("font_size", 30)
	_section_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	vbox.add_child(_section_title)

	var section_row := HBoxContainer.new()
	section_row.add_theme_constant_override("separation", 10)
	vbox.add_child(section_row)

	_section_buttons[Section.WALL_SPEED] = _make_section_button("⚡ 壁速度", section_row, Section.WALL_SPEED)
	_section_buttons[Section.SKIN] = _make_section_button("🧢 スキン", section_row, Section.SKIN)
	_section_buttons[Section.EMOTE] = _make_section_button("💃 エモート", section_row, Section.EMOTE)

	vbox.add_child(HSeparator.new())

	_wall_panel = VBoxContainer.new()
	_wall_panel.add_theme_constant_override("separation", 10)
	vbox.add_child(_wall_panel)
	_build_wall_panel()

	_skin_panel = VBoxContainer.new()
	_skin_panel.add_theme_constant_override("separation", 10)
	vbox.add_child(_skin_panel)
	_build_skin_panel()

	_emote_panel = VBoxContainer.new()
	_emote_panel.add_theme_constant_override("separation", 10)
	vbox.add_child(_emote_panel)
	_build_emote_panel()

	vbox.add_child(HSeparator.new())
	var back_btn := Button.new()
	back_btn.text = "✓ 決定して戻る"
	back_btn.custom_minimum_size = Vector2(0, 52)
	back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(back_btn)

	_style_all_buttons()
	_refresh_skin_player_button_styles()

func _make_section_button(label: String, parent: Node, section: Section) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 42)
	btn.pressed.connect(func() -> void: _set_section(section))
	parent.add_child(btn)
	return btn

func _build_wall_panel() -> void:
	_mode_label = Label.new()
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.add_theme_font_size_override("font_size", 16)
	_wall_panel.add_child(_mode_label)

	_speed_value_label = Label.new()
	_speed_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_value_label.add_theme_font_size_override("font_size", 42)
	_wall_panel.add_child(_speed_value_label)

	_speed_slider = HSlider.new()
	_speed_slider.min_value = 1.0
	_speed_slider.max_value = 10.0
	_speed_slider.step = 0.1
	_speed_slider.value_changed.connect(_on_speed_changed)
	_wall_panel.add_child(_speed_slider)

	var reset_btn := Button.new()
	reset_btn.text = "🔄 自動モードに戻す"
	reset_btn.pressed.connect(_on_reset_pressed)
	_wall_panel.add_child(reset_btn)

func _build_skin_panel() -> void:
	_skin_player_label = Label.new()
	_skin_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skin_player_label.add_theme_font_size_override("font_size", 20)
	_skin_panel.add_child(_skin_player_label)

	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 8)
	_skin_panel.add_child(player_row)

	_skin_player_btn_p1 = Button.new()
	_skin_player_btn_p1.text = "プレイヤー１"
	_skin_player_btn_p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_player_btn_p1.custom_minimum_size = Vector2(0, 44)
	_skin_player_btn_p1.pressed.connect(func() -> void: _set_skin_editing_player(1))
	player_row.add_child(_skin_player_btn_p1)

	_skin_player_btn_p2 = Button.new()
	_skin_player_btn_p2.text = "プレイヤー２"
	_skin_player_btn_p2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_player_btn_p2.custom_minimum_size = Vector2(0, 44)
	_skin_player_btn_p2.pressed.connect(func() -> void: _set_skin_editing_player(2))
	player_row.add_child(_skin_player_btn_p2)

	var hat_row := HBoxContainer.new()
	hat_row.add_theme_constant_override("separation", 8)
	_skin_panel.add_child(hat_row)

	var hat_prev := Button.new()
	hat_prev.text = "◀"
	hat_prev.pressed.connect(_on_hat_prev)
	hat_row.add_child(hat_prev)

	_hat_name_label = Label.new()
	_hat_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hat_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hat_name_label.add_theme_font_size_override("font_size", 18)
	hat_row.add_child(_hat_name_label)

	var hat_next := Button.new()
	hat_next.text = "▶"
	hat_next.pressed.connect(_on_hat_next)
	hat_row.add_child(hat_next)

func _build_emote_panel() -> void:
	_emote_player_toggle_btn = Button.new()
	_emote_player_toggle_btn.custom_minimum_size = Vector2(0, 44)
	_emote_player_toggle_btn.add_theme_font_size_override("font_size", 18)
	_emote_player_toggle_btn.pressed.connect(_on_emote_player_toggle)
	_emote_panel.add_child(_emote_player_toggle_btn)

	var emote_cam_hint := Label.new()
	emote_cam_hint.text = "左プレビュー: 右ドラッグ＝回転  中ドラッグ／WASD＝移動  ホイール＝ズーム"
	emote_cam_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emote_cam_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	emote_cam_hint.add_theme_font_size_override("font_size", 11)
	emote_cam_hint.add_theme_color_override("font_color", Color(0.55, 0.60, 0.72))
	_emote_panel.add_child(emote_cam_hint)

	_emote_panel.add_child(HSeparator.new())

	for i in range(3):
		var slot_hbox := HBoxContainer.new()
		slot_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_hbox.add_theme_constant_override("separation", 8)
		_emote_panel.add_child(slot_hbox)

		var key_label := Label.new()
		key_label.custom_minimum_size = Vector2(60, 0)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 16)
		key_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		slot_hbox.add_child(key_label)

		var left_btn := Button.new()
		left_btn.text = "◀"
		left_btn.custom_minimum_size = Vector2(40, 36)
		left_btn.add_theme_font_size_override("font_size", 18)
		var slot_idx := i
		left_btn.pressed.connect(func() -> void: _on_slot_change(slot_idx, -1))
		slot_hbox.add_child(left_btn)

		var emote_label := Label.new()
		emote_label.custom_minimum_size = Vector2(180, 0)
		emote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emote_label.add_theme_font_size_override("font_size", 16)
		emote_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
		slot_hbox.add_child(emote_label)
		_slot_labels.append(emote_label)

		var right_btn := Button.new()
		right_btn.text = "▶"
		right_btn.custom_minimum_size = Vector2(40, 36)
		right_btn.add_theme_font_size_override("font_size", 18)
		right_btn.pressed.connect(func() -> void: _on_slot_change(slot_idx, +1))
		slot_hbox.add_child(right_btn)

	_emote_panel.add_child(HSeparator.new())

	var grid_title := Label.new()
	grid_title.text = "🔍 エモート一覧"
	grid_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid_title.add_theme_font_size_override("font_size", 16)
	grid_title.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_emote_panel.add_child(grid_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_emote_panel.add_child(scroll)

	_emote_grid = GridContainer.new()
	_emote_grid.columns = 3
	_emote_grid.add_theme_constant_override("h_separation", 6)
	_emote_grid.add_theme_constant_override("v_separation", 6)
	_emote_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_emote_grid)

	_grid_card_by_id.clear()
	var emote_list := EmoteData.get_emote_list()
	for entry in emote_list:
		var eid: int = entry["id"]
		var ename: String = entry["name"]
		var eicon: String = entry["icon"]

		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 56)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_font_size_override("font_size", 13)
		card.text = "%s\n%s" % [eicon, ename]
		card.clip_text = true

		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.12, 0.13, 0.19)
		card_style.border_color = Color(0.25, 0.28, 0.38)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(8)
		card_style.content_margin_left = 4.0
		card_style.content_margin_right = 4.0
		card_style.content_margin_top = 4.0
		card_style.content_margin_bottom = 4.0
		card.add_theme_stylebox_override("normal", card_style)

		var hover_style := card_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(0.18, 0.20, 0.30)
		hover_style.border_color = Color(0.4, 0.5, 0.7)
		card.add_theme_stylebox_override("hover", hover_style)
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		card.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
		card.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

		card.pressed.connect(_on_grid_emote_selected.bind(eid, card))
		_emote_grid.add_child(card)
		_grid_card_by_id[eid] = card

func _build_3d_preview() -> void:
	var bg_color := Color(0.82, 0.85, 0.90)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg_color
	env.ambient_light_color = Color(0.30, 0.32, 0.35)
	env.ambient_light_energy = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_light_color = bg_color
	env.fog_density = 0.002
	env.fog_aerial_perspective = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_sub_viewport.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -20, 0)
	light.light_energy = 0.8
	light.shadow_enabled = true
	_sub_viewport.add_child(light)

	_preview_camera = Camera3D.new()
	_sub_viewport.add_child(_preview_camera)

	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(24.0, 16.0, 144.0)
	floor.mesh = floor_mesh
	_preview_floor_material = ShaderMaterial.new()
	_preview_floor_material.shader = CONVEYOR_FLOOR_SHADER
	_preview_floor_material.set_shader_parameter("scroll_z", 0.0)
	_preview_floor_material.set_shader_parameter("scroll_sign", -1.0)
	floor.material_override = _preview_floor_material
	floor.position = Vector3(0, -9.2, -64.0)
	_sub_viewport.add_child(floor)

	var game_world_script := preload("res://scripts/world/game_world.gd")
	var magma_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(800.0, 800.0)
	plane.subdivide_width = 200
	plane.subdivide_depth = 200
	magma_mesh.mesh = plane
	magma_mesh.position = Vector3(0, -10.0, 150.0)
	var magma_mat := ShaderMaterial.new()
	magma_mat.shader = Shader.new()
	magma_mat.shader.code = game_world_script.MAGMA_SHADER
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
	magma_mat.set_shader_parameter("noise_tex", noise1)
	magma_mesh.material_override = magma_mat
	_sub_viewport.add_child(magma_mesh)

	_setup_conveyor_extras()

	var start_z := 8.0 - WALL_SPACING * 2
	for i in range(3):
		_spawn_preview_wall(start_z + i * WALL_SPACING)

	_preview_gs = QuizGameState.new()
	_preview_gs.game_state = Constants.STATE_PLAYING
	_preview_gs.num_players = 2
	_preview_gs.p1_alive = true
	_preview_gs.p2_alive = true
	_preview_gs.player_x = PREVIEW_PLAYER_P1_X
	_preview_gs.player_y = 0.0
	_preview_gs.player_z = 0.0
	_preview_gs.player2_x = PREVIEW_PLAYER_P2_X
	_preview_gs.player2_y = 0.0
	_preview_gs.player2_z = 0.0
	_preview_gs.world_scroll_z = 0.0
	_preview_gs._active_wall_speed = _belt_visual_speed

	_preview_player = Node3D.new()
	_preview_player.set_script(PLAYER_CONTROLLER_SCRIPT)
	_sub_viewport.add_child(_preview_player)

	var gm := QuizManager.game_state
	if _preview_player.has_method("set_hat"):
		_preview_player.set_hat(1, gm.p1_hat)
		_preview_player.set_hat(2, gm.p2_hat)

	_emote_preview_holder = Node3D.new()
	_emote_preview_holder.name = "EmotePreviewHolder"
	_emote_preview_holder.visible = false
	_sub_viewport.add_child(_emote_preview_holder)

func _set_section(section: Section) -> void:
	_active_section = section
	_wall_panel.visible = section == Section.WALL_SPEED
	_skin_panel.visible = section == Section.SKIN
	_emote_panel.visible = section == Section.EMOTE

	for key in _section_buttons.keys():
		var btn: Button = _section_buttons[key]
		btn.disabled = key == section

	if _preview_input_catcher:
		_preview_input_catcher.mouse_filter = (
			Control.MOUSE_FILTER_STOP if section == Section.EMOTE else Control.MOUSE_FILTER_IGNORE
		)

	match section:
		Section.WALL_SPEED:
			_section_title.visible = true
			_section_title.text = "⚡ 壁速度設定"
			_cleanup_emote_preview()
			_preview_player.visible = true
			if _preview_walls.is_empty():
				_replenish_preview_walls_after_emote()
		Section.SKIN:
			_section_title.visible = true
			_section_title.text = "🧢 スキン設定"
			_explode_preview_walls_for_emote()
			_cleanup_emote_preview()
			_preview_player.visible = true
			_sync_preview_hat()
		Section.EMOTE:
			_explode_preview_walls_for_emote()
			_section_title.visible = false
			if _emote_preview_holder:
				_emote_preview_holder.visible = true
			_reset_emote_orbit_default()
			_preview_player.visible = false
			var gs_emote := QuizManager.game_state
			var slots_emote: Array[int] = gs_emote.p1_emote_slots if _editing_player == 1 else gs_emote.p2_emote_slots
			if slots_emote.size() > 0:
				_browsing_emote_id = slots_emote[0]
			_update_emote_panel_ui()
			_highlight_grid_card_for_emote(_browsing_emote_id)
			_play_emote_preview(_browsing_emote_id)

func _preview_editing_lane_x() -> float:
	return PREVIEW_PLAYER_P1_X if _editing_player == 1 else PREVIEW_PLAYER_P2_X


func _snap_preview_camera_to_current_section() -> void:
	if not _preview_camera:
		return
	var d := _get_desired_preview_camera()
	_preview_camera.position = d.pos
	_preview_camera.quaternion = d.quat
	_preview_camera.fov = d.fov


func _get_desired_preview_camera() -> Dictionary:
	match _active_section:
		Section.WALL_SPEED:
			var qw := Quaternion.from_euler(
				Vector3(deg_to_rad(-14.0), deg_to_rad(15.0), 0.0),
			)
			return {"pos": Vector3(4.5, 4.5, 16.0), "quat": qw, "fov": 65.0}
		Section.SKIN:
			var tx_skin := _preview_editing_lane_x()
			var look_tgt := Vector3(tx_skin, SKIN_PREVIEW_CAM_LOOK_Y, 0.0)
			var cam_pos_skin := Vector3(tx_skin, SKIN_PREVIEW_CAM_Y, -SKIN_PREVIEW_CAM_DIST_Z)
			var qs := _camera_quat_look_at(cam_pos_skin, look_tgt)
			return {"pos": cam_pos_skin, "quat": qs, "fov": SKIN_PREVIEW_FOV}
		Section.EMOTE:
			var yaw_rad := deg_to_rad(_emote_cam_yaw)
			var pitch_rad := deg_to_rad(clampf(_emote_cam_pitch, -80.0, 80.0))
			var offset := Vector3(
				_emote_cam_distance * cos(pitch_rad) * sin(yaw_rad),
				_emote_cam_distance * sin(pitch_rad),
				_emote_cam_distance * cos(pitch_rad) * cos(yaw_rad)
			)
			var cam_pos := _emote_cam_target + offset
			cam_pos.y = maxf(cam_pos.y, EMOTE_CAM_MIN_WORLD_Y)
			var qe := _camera_quat_look_at(cam_pos, _emote_cam_target)
			return {"pos": cam_pos, "quat": qe, "fov": 40.0}
	return {"pos": Vector3.ZERO, "quat": Quaternion.IDENTITY, "fov": 60.0}


func _camera_quat_look_at(origin: Vector3, look_target: Vector3) -> Quaternion:
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
	var b := Basis(x_axis, y_axis, z_axis)
	return b.get_rotation_quaternion()


func _apply_preview_camera_smoothing(dt: float) -> void:
	if not _preview_camera:
		return
	var d := _get_desired_preview_camera()
	var k: float = 1.0 - exp(-CAM_PREVIEW_SMOOTH_RATE * dt)
	_preview_camera.position = _preview_camera.position.lerp(d.pos, k)
	_preview_camera.quaternion = _preview_camera.quaternion.slerp(d.quat, k)
	_preview_camera.fov = lerpf(_preview_camera.fov, d.fov, k)


func _reset_emote_orbit_default() -> void:
	_emote_cam_yaw = 0.0
	_emote_cam_pitch = -8.0
	_emote_cam_distance = 4.0
	var tx_em := _preview_editing_lane_x()
	_emote_cam_target = Vector3(tx_em, 0.2, 0.0)
	_emote_cam_dragging = false
	_emote_cam_panning = false


func _sync_emote_orbit_lane_x() -> void:
	_emote_cam_target.x = _preview_editing_lane_x()


func _on_emote_preview_gui_input(event: InputEvent) -> void:
	if _active_section != Section.EMOTE:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_emote_cam_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_emote_cam_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_emote_cam_distance = maxf(1.5, _emote_cam_distance - 0.3)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_emote_cam_distance = minf(12.0, _emote_cam_distance + 0.3)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _emote_cam_dragging:
			_emote_cam_yaw -= mm.relative.x * 0.3
			_emote_cam_pitch -= mm.relative.y * 0.3
			_emote_cam_pitch = clampf(_emote_cam_pitch, -80.0, 80.0)
		elif _emote_cam_panning:
			var yaw_rad_pan := deg_to_rad(_emote_cam_yaw)
			var right_pan := Vector3(cos(yaw_rad_pan), 0, -sin(yaw_rad_pan))
			_emote_cam_target += right_pan * mm.relative.x * -0.005
			_emote_cam_target.y += mm.relative.y * 0.005


func _refresh_all_labels() -> void:
	var gs := QuizManager.game_state
	_speed_slider.value = _preview_speed
	_update_mode_label()
	_update_speed_value()
	_skin_player_label.text = "対象プレイヤー: P%d" % _editing_player
	_hat_name_label.text = HatData.get_hat_name(_get_current_hat())
	_update_emote_panel_ui()
	_refresh_skin_player_button_styles()

	if gs and _preview_player and _preview_player.has_method("set_hat"):
		_sync_preview_hat()

func _update_mode_label() -> void:
	var gs := QuizManager.game_state
	if gs.tuning.wall_speed_override > 0:
		_mode_label.text = "📌 手動モード"
		_mode_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	else:
		_mode_label.text = "🤖 自動モード"
		_mode_label.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))

func _update_speed_value() -> void:
	_speed_value_label.text = "%.1f" % _preview_speed
	var t: float = (_preview_speed - 2.0) / 8.0
	var col := Color(0.3, 1.0, 0.5).lerp(Color(1.0, 0.3, 0.2), t)
	_speed_value_label.add_theme_color_override("font_color", col)

func _on_speed_changed(value: float) -> void:
	_preview_speed = value
	if _active_section != Section.EMOTE:
		_belt_visual_speed = value
	QuizManager.game_state.tuning.wall_speed_override = value
	_update_mode_label()
	_update_speed_value()

func _on_reset_pressed() -> void:
	QuizManager.game_state.tuning.wall_speed_override = 0.0
	_preview_speed = AUTO_WALL_SPEED
	if _active_section != Section.EMOTE:
		_belt_visual_speed = _preview_speed
	_speed_slider.value = _preview_speed
	_update_mode_label()
	_update_speed_value()

func _set_skin_editing_player(which: int) -> void:
	if which != 1 and which != 2:
		return
	if _editing_player == which:
		return
	_editing_player = which
	_refresh_all_labels()

func _skin_player_btn_theme(btn: Button, accent: Color, selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent.darkened(0.52 if selected else 0.62)
	normal.bg_color.a = 0.94
	normal.border_color = accent.lightened(0.28 if selected else 0.08)
	normal.border_color.a = 1.0 if selected else 0.82
	normal.set_border_width_all(2 if selected else 1)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 12.0
	normal.content_margin_right = 12.0
	normal.content_margin_top = 8.0
	normal.content_margin_bottom = 8.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent.darkened(0.44 if selected else 0.54)
	hover.bg_color.a = 0.97
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.96))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

func _refresh_skin_player_button_styles() -> void:
	if not _skin_player_btn_p1 or not _skin_player_btn_p2:
		return
	_skin_player_btn_theme(_skin_player_btn_p1, PlayerController.P1_BODY, _editing_player == 1)
	_skin_player_btn_theme(_skin_player_btn_p2, PlayerController.P2_BODY, _editing_player == 2)

func _on_hat_prev() -> void:
	var next_hat := (_get_current_hat() - 1 + HatData.HAT_COUNT) % HatData.HAT_COUNT
	_set_current_hat(next_hat)
	_refresh_all_labels()

func _on_hat_next() -> void:
	var next_hat := (_get_current_hat() + 1) % HatData.HAT_COUNT
	_set_current_hat(next_hat)
	_refresh_all_labels()

func _update_emote_panel_ui() -> void:
	if not _emote_player_toggle_btn:
		return
	var gs := QuizManager.game_state
	if _editing_player == 1:
		_emote_player_toggle_btn.text = "👤 P1 設定中 (➡ P2に切替)"
		_emote_player_toggle_btn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.20))
	else:
		_emote_player_toggle_btn.text = "👤 P2 設定中 (➡ P1に切替)"
		_emote_player_toggle_btn.add_theme_color_override("font_color", Color(0.20, 0.65, 0.90))

	var slots: Array[int] = gs.p1_emote_slots if _editing_player == 1 else gs.p2_emote_slots
	var keys := SLOT_KEYS_P1 if _editing_player == 1 else SLOT_KEYS_P2
	for i in range(_slot_labels.size()):
		var emote_id := slots[i] if i < slots.size() else EmoteData.EMOTE_NONE
		_slot_labels[i].text = EmoteData.get_emote_name(emote_id)
		var slot_hbox := _slot_labels[i].get_parent()
		if slot_hbox and slot_hbox.get_child_count() > 0:
			var key_label := slot_hbox.get_child(0) as Label
			if key_label:
				key_label.text = "[ %s ]" % keys[i]

func _on_emote_player_toggle() -> void:
	_editing_player = 2 if _editing_player == 1 else 1
	var gs := QuizManager.game_state
	var slots: Array[int] = gs.p1_emote_slots if _editing_player == 1 else gs.p2_emote_slots
	if slots.size() > 0:
		_browsing_emote_id = slots[0]
	_refresh_all_labels()
	if _active_section != Section.EMOTE:
		return
	_sync_emote_orbit_lane_x()
	_highlight_grid_card_for_emote(_browsing_emote_id)
	_play_emote_preview(_browsing_emote_id)

func _on_slot_change(slot_idx: int, direction: int) -> void:
	var gs := QuizManager.game_state
	var slots: Array[int]
	if _editing_player == 1:
		slots = gs.p1_emote_slots.duplicate()
	else:
		slots = gs.p2_emote_slots.duplicate()
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var current := slots[slot_idx]
	var next_id := (current + direction + EmoteData.EMOTE_COUNT) % EmoteData.EMOTE_COUNT
	slots[slot_idx] = next_id
	if _editing_player == 1:
		gs.p1_emote_slots = slots
	else:
		gs.p2_emote_slots = slots
	if _active_section == Section.EMOTE:
		_browsing_emote_id = next_id
	_refresh_all_labels()
	if _active_section == Section.EMOTE:
		_highlight_grid_card_for_emote(_browsing_emote_id)
		_play_emote_preview(next_id)

func _grid_card_normal_style() -> StyleBoxFlat:
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.13, 0.19)
	card_style.border_color = Color(0.25, 0.28, 0.38)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(8)
	card_style.content_margin_left = 4.0
	card_style.content_margin_right = 4.0
	card_style.content_margin_top = 4.0
	card_style.content_margin_bottom = 4.0
	return card_style

func _grid_card_hover_style() -> StyleBoxFlat:
	var hover_style := _grid_card_normal_style()
	hover_style.bg_color = Color(0.18, 0.20, 0.30)
	hover_style.border_color = Color(0.4, 0.5, 0.7)
	return hover_style

func _grid_card_selected_style() -> StyleBoxFlat:
	var sel_style := StyleBoxFlat.new()
	sel_style.bg_color = Color(0.15, 0.25, 0.45)
	sel_style.border_color = Color(0.4, 0.65, 1.0)
	sel_style.set_border_width_all(2)
	sel_style.set_corner_radius_all(8)
	sel_style.content_margin_left = 4.0
	sel_style.content_margin_right = 4.0
	sel_style.content_margin_top = 4.0
	sel_style.content_margin_bottom = 4.0
	return sel_style

func _highlight_grid_card_for_emote(emote_id: int) -> void:
	if _selected_grid_btn and is_instance_valid(_selected_grid_btn):
		_selected_grid_btn.add_theme_stylebox_override("normal", _grid_card_normal_style())
		_selected_grid_btn.add_theme_stylebox_override("hover", _grid_card_hover_style())
	if _grid_card_by_id.has(emote_id):
		var card: Button = _grid_card_by_id[emote_id]
		if card and is_instance_valid(card):
			card.add_theme_stylebox_override("normal", _grid_card_selected_style())
			_selected_grid_btn = card

func _on_grid_emote_selected(emote_id: int, card: Button) -> void:
	if _selected_grid_btn and is_instance_valid(_selected_grid_btn):
		_selected_grid_btn.add_theme_stylebox_override("normal", _grid_card_normal_style())
		_selected_grid_btn.add_theme_stylebox_override("hover", _grid_card_hover_style())
	_selected_grid_btn = card
	card.add_theme_stylebox_override("normal", _grid_card_selected_style())
	_browsing_emote_id = emote_id
	_update_emote_panel_ui()
	if _active_section == Section.EMOTE:
		_play_emote_preview(emote_id)

func _pick_best_emote_animation(ap: AnimationPlayer) -> String:
	var best_name := ""
	var best_tracks := -1
	for lib_name in ap.get_animation_library_list():
		var lib: AnimationLibrary = ap.get_animation_library(lib_name)
		for a_name in lib.get_animation_list():
			var full: String = str(lib_name) + "/" + str(a_name) if str(lib_name) != "" else str(a_name)
			var anim: Animation = lib.get_animation(a_name)
			if "mixamo_com" in a_name:
				best_name = full
				best_tracks = 9999
			elif anim.get_track_count() > best_tracks:
				best_tracks = anim.get_track_count()
				if not ("mixamo_com" in best_name):
					best_name = full
	return best_name


func _spawn_lane_emote_preview(emote_id: int, lane_x: float, is_p1: bool, hat_id: int) -> Dictionary:
	var entry: Dictionary = {}
	entry.rm = {"ready": false, "origin": Vector3.ZERO}
	entry.lane_x = lane_x
	entry.fbx = null
	entry.ap = null
	entry.skel = null
	entry.bones = {}

	var block_root := Node3D.new()
	entry.block_root = block_root
	block_root.position = Vector3(lane_x, 0.0, 0.0)
	_emote_preview_holder.add_child(block_root)
	entry.parts = EmoteBlockmanPreview.build_player_skeleton(is_p1, block_root, hat_id)

	if emote_id == EmoteData.EMOTE_NONE:
		return entry

	var fbx_path := EmoteData.get_emote_fbx(emote_id)
	if fbx_path.is_empty() or not ResourceLoader.exists(fbx_path):
		return entry
	var scene := load(fbx_path) as PackedScene
	if not scene:
		return entry

	var node := scene.instantiate() as Node3D
	entry.fbx = node
	node.position = Vector3(lane_x, 0.0, 0.0)
	_sub_viewport.add_child(node)

	for child in node.find_children("*", "MeshInstance3D", true, false):
		child.hide()

	entry.skel = null
	for child in node.find_children("*", "Skeleton3D", true, false):
		entry.skel = child as Skeleton3D
		break

	if entry.skel:
		entry.bones = EmoteBlockmanPreview.map_mixamo_bones(entry.skel)

	entry.ap = null
	for child in node.find_children("*", "AnimationPlayer", true, false):
		entry.ap = child as AnimationPlayer
		break

	if entry.ap:
		var best_name := _pick_best_emote_animation(entry.ap)
		if best_name != "":
			var best_anim: Animation = entry.ap.get_animation(best_name)
			if best_anim:
				best_anim.loop_mode = Animation.LOOP_LINEAR
			entry.ap.play(best_name)

	block_root.rotation.y = 0.0
	return entry


func _cleanup_emote_lane_previews() -> void:
	for entry in _emote_lane_previews:
		var fbx: Node3D = entry.get("fbx", null)
		if fbx != null and is_instance_valid(fbx):
			fbx.queue_free()
		var br: Node3D = entry.get("block_root", null)
		if br != null and is_instance_valid(br):
			br.queue_free()
	_emote_lane_previews.clear()


func _play_emote_preview(emote_id: int) -> void:
	if _active_section != Section.EMOTE:
		return
	if not _emote_preview_holder:
		return

	_cleanup_emote_lane_previews()
	_current_preview_emote_id = emote_id

	var gm := QuizManager.game_state
	var lane_infos: Array[Dictionary] = [
		{"lane_x": PREVIEW_PLAYER_P1_X, "is_p1": true, "hat": gm.p1_hat},
		{"lane_x": PREVIEW_PLAYER_P2_X, "is_p1": false, "hat": gm.p2_hat},
	]

	for lane_info in lane_infos:
		var lx: float = float(lane_info["lane_x"])
		var lane_p1: bool = bool(lane_info["is_p1"])
		var hid: int = int(lane_info["hat"])
		var e := _spawn_lane_emote_preview(emote_id, lx, lane_p1, hid)
		_emote_lane_previews.append(e)


func _cleanup_emote_preview() -> void:
	_cleanup_emote_lane_previews()
	if _emote_preview_holder:
		_emote_preview_holder.visible = false

func _sync_preview_hat() -> void:
	if not _preview_player or not _preview_player.has_method("set_hat"):
		return
	var gs := QuizManager.game_state
	_preview_player.set_hat(1, gs.p1_hat)
	_preview_player.set_hat(2, gs.p2_hat)

func _get_current_hat() -> int:
	var gs := QuizManager.game_state
	return gs.p1_hat if _editing_player == 1 else gs.p2_hat

func _set_current_hat(hat_id: int) -> void:
	var gs := QuizManager.game_state
	if _editing_player == 1:
		gs.p1_hat = hat_id
	else:
		gs.p2_hat = hat_id

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _force_preview_player_facing_away() -> void:
	var pc := _preview_player as PlayerController
	if not pc:
		return
	if pc.p1_parts.has("pelvis"):
		var pelvis := pc.p1_parts["pelvis"] as Node3D
		if pelvis:
			pelvis.rotation.y = PI
	if pc.p2_parts.has("pelvis"):
		var p2_pelvis := pc.p2_parts["pelvis"] as Node3D
		if p2_pelvis:
			p2_pelvis.rotation.y = PI

func _update_preview_debris_near_camera() -> void:
	if not _sub_viewport or not _preview_camera:
		return
	for child in _sub_viewport.get_children():
		if child is RigidBody3D:
			var body := child as RigidBody3D
			if body.get_meta("preview_door_shard", false):
				var d_far := body.global_position.distance_to(_preview_camera.global_position)
				if d_far > 48.0 or body.global_position.y < PREVIEW_DEBRIS_Y_KILL:
					body.queue_free()
				continue
			if body.global_position.y < PREVIEW_DEBRIS_Y_KILL:
				body.queue_free()
				continue
			var dist := body.global_position.distance_to(_preview_camera.global_position)
			if dist <= PREVIEW_DEBRIS_FADE_START_DIST:
				var t := clampf(
					(dist - PREVIEW_DEBRIS_KILL_DIST) / maxf(0.001, PREVIEW_DEBRIS_FADE_START_DIST - PREVIEW_DEBRIS_KILL_DIST),
					0.0,
					1.0,
				)
				var visual_scale: float = maxf(PREVIEW_DEBRIS_SCALE_FLOOR, t)
				for mesh_child in body.get_children():
					if mesh_child is MeshInstance3D:
						(mesh_child as MeshInstance3D).scale = Vector3.ONE * visual_scale
			if dist <= PREVIEW_DEBRIS_KILL_DIST:
				body.queue_free()


func _schedule_preview_debris_free(body: RigidBody3D, lifetime_sec: float) -> void:
	if not body:
		return
	get_tree().create_timer(lifetime_sec).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body.queue_free()
	)


func _create_preview_merge_silhouette() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.0, 5.5, 0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.5, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	mi.mesh = box
	mi.visible = false
	return mi


func _remove_preview_merge_slots_at(idx: int) -> void:
	if idx < _merge_anims.size():
		_merge_anims.remove_at(idx)
	if idx < _merge_started.size():
		_merge_started.remove_at(idx)
	if idx < _merge_left_sils.size():
		_merge_left_sils.remove_at(idx)
	if idx < _merge_right_sils.size():
		_merge_right_sils.remove_at(idx)


func _process_preview_wall_merge(dt: float) -> void:
	if _active_section == Section.EMOTE or _active_section == Section.SKIN:
		return
	var total: int = _preview_walls.size()
	if total == 0:
		return

	var all_started := true
	for ms in _merge_started:
		if not ms:
			all_started = false
			break
	if not all_started:
		_merge_timer += dt
		while _merge_timer >= PREVIEW_MERGE_INTERVAL_SEC:
			var found_next := false
			for search_i in range(total):
				if search_i >= _merge_started.size():
					break
				if not _merge_started[search_i]:
					_merge_started[search_i] = true
					if search_i < _merge_anims.size():
						_merge_anims[search_i]["phase"] = 1
						_merge_anims[search_i]["started"] = true
						_merge_anims[search_i]["timer"] = 0.0
					if search_i < _merge_left_sils.size():
						_merge_left_sils[search_i].visible = true
						_merge_right_sils[search_i].visible = true
					found_next = true
					break
			if not found_next:
				break
			_merge_timer -= PREVIEW_MERGE_INTERVAL_SEC

	for i in range(_merge_anims.size()):
		if i >= _preview_walls.size():
			continue
		var wall: Node3D = _preview_walls[i]
		if not is_instance_valid(wall):
			continue
		var anim: Dictionary = _merge_anims[i]
		if not anim.get("started", false):
			continue

		var phase: int = int(anim.get("phase", 0))
		var t_val: float = float(anim.get("timer", 0.0))
		t_val += dt
		anim["timer"] = t_val

		if phase == 1:
			var prog: float = clampf(t_val / PREVIEW_MERGE_SLIDE_DURATION, 0.0, 1.0)
			var eased: float = 1.0 - pow(1.0 - prog, 5.0)
			var x_offset: float = PREVIEW_MERGE_SLIDE_START_X * (1.0 - eased)
			if i < _merge_left_sils.size():
				_merge_left_sils[i].position.x = -x_offset
				_merge_right_sils[i].position.x = x_offset

			if prog >= 1.0:
				anim["phase"] = 2
				anim["timer"] = 0.0
				if i < _merge_left_sils.size():
					_merge_left_sils[i].visible = false
					_merge_right_sils[i].visible = false
				wall.visible = true
				wall.scale = Vector3(1.15, 1.15, 1.15)
				_spawn_preview_merge_sparks_on_wall(wall)

		elif phase == 2:
			var prog2: float = clampf(t_val / PREVIEW_MERGE_FLASH_DURATION, 0.0, 1.0)
			var eased2: float = 1.0 - pow(1.0 - prog2, 2.0)
			var sc: float = lerpf(1.15, 1.0, eased2)
			wall.scale = Vector3(sc, sc, sc)
			if prog2 >= 1.0:
				anim["phase"] = 3
				wall.scale = Vector3.ONE


## 合体火花・フラッシュを壁ノードに親付けする（SubViewport 内で global_position がずれるのを避ける）
func _spawn_preview_merge_sparks_on_wall(wall: Node3D) -> void:
	if not wall or not is_instance_valid(wall):
		return
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))

	var sparks := CPUParticles3D.new()
	sparks.amount = 55
	sparks.lifetime = 0.75
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.randomness = 1.0
	sparks.local_coords = false
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.5, 2.0, 0.5)
	sparks.direction = Vector3(0.0, 1.0, 0.0)
	sparks.spread = 180.0
	sparks.initial_velocity_min = 7.0
	sparks.initial_velocity_max = 18.0
	sparks.gravity = Vector3(0, -25.0, 0)
	sparks.damping_min = 5.0
	sparks.damping_max = 10.0
	sparks.scale_amount_min = 1.0
	sparks.scale_amount_max = 2.2
	sparks.scale_amount_curve = curve

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = Color(1.5, 1.0, 0.6, 1.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	var mesh := QuadMesh.new()
	mesh.material = mat
	sparks.mesh = mesh
	wall.add_child(sparks)
	sparks.position = Vector3(0.0, 2.5, 0.0)
	sparks.emitting = true

	var flash := CPUParticles3D.new()
	flash.amount = 1
	flash.lifetime = 0.22
	flash.one_shot = true
	flash.gravity = Vector3.ZERO
	flash.local_coords = false
	flash.scale_amount_min = 7.0
	flash.scale_amount_max = 7.0
	flash.scale_amount_curve = curve
	var mat_flash := StandardMaterial3D.new()
	mat_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_flash.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat_flash.albedo_color = Color(1.2, 1.0, 0.8, 0.75)
	mat_flash.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var mesh_flash := QuadMesh.new()
	mesh_flash.material = mat_flash
	flash.mesh = mesh_flash
	wall.add_child(flash)
	flash.position = Vector3(0.0, 2.5, 0.0)
	flash.emitting = true

	var tw_s := create_tween()
	tw_s.tween_callback(func() -> void:
		if is_instance_valid(sparks):
			sparks.queue_free()
	).set_delay(2.4)
	var tw_f := create_tween()
	tw_f.tween_callback(func() -> void:
		if is_instance_valid(flash):
			flash.queue_free()
	).set_delay(1.9)


func _replenish_preview_walls_after_emote() -> void:
	_merge_timer = 0.0
	var start_z := 8.0 - WALL_SPACING * 2
	for idx in range(3):
		_spawn_preview_wall(start_z + float(idx) * WALL_SPACING)


func _explode_preview_walls_for_emote() -> void:
	for i in range(_preview_walls.size() - 1, -1, -1):
		var w: Node3D = _preview_walls[i]
		if is_instance_valid(w):
			_preview_spawn_wall_debris_pieces(w, true)
			w.queue_free()
	_preview_walls.clear()
	_merge_left_sils.clear()
	_merge_right_sils.clear()
	_merge_anims.clear()
	_merge_started.clear()
	_merge_timer = 0.0


## burst==true: スキン／エモートタブへ入ったときの強い散り方。
## burst==false: 壁速度プレビューでマグマへ落ちるとき（wall_speed 単独画面と同じ「ボトッと落下」）
func _preview_spawn_wall_debris_pieces(wall: Node3D, burst: bool) -> void:
	if not wall or not is_instance_valid(wall):
		return
	var mesh_nodes: Array[MeshInstance3D] = []
	if burst:
		for n in wall.find_children("*", "MeshInstance3D", true, false):
			mesh_nodes.append(n as MeshInstance3D)
	else:
		for child in wall.get_children():
			if child is MeshInstance3D:
				mesh_nodes.append(child as MeshInstance3D)

	for src_mesh in mesh_nodes:
		if not src_mesh.visible:
			continue
		var box_mesh := src_mesh.mesh as BoxMesh
		if not box_mesh:
			continue
		var piece := RigidBody3D.new()
		if burst:
			piece.mass = 1.55
			piece.gravity_scale = 0.76
			piece.linear_damp = 0.018
			piece.angular_damp = 0.045
		else:
			piece.mass = PREVIEW_SOFT_FALL_DEBRIS_MASS
			piece.gravity_scale = PREVIEW_SOFT_FALL_DEBRIS_GRAVITY_SCALE
			piece.linear_damp = PREVIEW_SOFT_FALL_DEBRIS_LINEAR_DAMP
			piece.angular_damp = PREVIEW_SOFT_FALL_DEBRIS_ANGULAR_DAMP
		piece.collision_layer = 0
		if burst:
			piece.collision_mask = 0
		else:
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
		elif burst and box_mesh.material:
			mesh_inst.material_override = box_mesh.material.duplicate()
		piece.add_child(mesh_inst)
		_sub_viewport.add_child(piece)
		piece.global_transform = src_mesh.global_transform
		if burst:
			piece.apply_central_impulse(
				Vector3(randf_range(-92.0, 92.0), randf_range(62.0, 158.0), randf_range(-62.0, 188.0))
			)
			piece.apply_torque_impulse(
				Vector3(randf_range(-138.0, 138.0), randf_range(-138.0, 138.0), randf_range(-138.0, 138.0))
			)
		else:
			## customize_settings の PREVIEW_SOFT_FALL_IMP_* と揃える（quiz_wall.gd 扉破片）
			piece.apply_central_impulse(
				Vector3(
					randf_range(-PREVIEW_SOFT_FALL_IMP_X, PREVIEW_SOFT_FALL_IMP_X),
					randf_range(0.0, PREVIEW_SOFT_FALL_IMP_Y),
					randf_range(PREVIEW_SOFT_FALL_IMP_Z_MIN, PREVIEW_SOFT_FALL_IMP_Z_MAX),
				)
			)
			piece.apply_torque_impulse(
				Vector3(
					randf_range(-PREVIEW_SOFT_FALL_TORQUE, PREVIEW_SOFT_FALL_TORQUE),
					randf_range(-PREVIEW_SOFT_FALL_TORQUE * 0.62, PREVIEW_SOFT_FALL_TORQUE * 0.62),
					randf_range(-PREVIEW_SOFT_FALL_TORQUE, PREVIEW_SOFT_FALL_TORQUE),
				)
			)
		_schedule_preview_debris_free(piece, PREVIEW_DEBRIS_LIFETIME_SEC)


func _spawn_preview_wall(z_pos: float) -> void:
	var dummy_quiz := QuizItem.new()
	dummy_quiz.q = "プレビュー"
	dummy_quiz.c = ["A", "B"]
	var wall: Node3D = WALL_SCENE.instantiate()
	wall.position.z = z_pos
	wall.visible = false
	wall.scale = Vector3.ONE
	_sub_viewport.add_child(wall)
	if wall.has_method("set_quiz"):
		wall.set_quiz(dummy_quiz, 2)

	var sil_l := _create_preview_merge_silhouette()
	wall.add_child(sil_l)
	sil_l.position = Vector3(-PREVIEW_MERGE_SLIDE_START_X, 2.75, 0)
	sil_l.visible = false

	var sil_r := _create_preview_merge_silhouette()
	wall.add_child(sil_r)
	sil_r.position = Vector3(PREVIEW_MERGE_SLIDE_START_X, 2.75, 0)
	sil_r.visible = false

	_preview_walls.append(wall)
	_merge_left_sils.append(sil_l)
	_merge_right_sils.append(sil_r)
	_merge_anims.append({"phase": 0, "timer": 0.0, "started": false})
	_merge_started.append(false)

func _drop_wall_into_magma(wall: Node3D) -> void:
	if not wall or not is_instance_valid(wall):
		return
	_preview_spawn_wall_debris_pieces(wall, false)

func _setup_conveyor_extras() -> void:
	var floor_length := 144.0
	var floor_center_z := -64.0
	var half_len := floor_length * 0.5
	var front_z := floor_center_z + half_len
	var top_front_contact_z := floor_center_z + half_len
	var roller_center_y := FLOOR_TOP_Y - CONVEYOR_ROLLER_RADIUS

	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(24.0, 0.5, floor_length)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(0, FLOOR_TOP_Y - 0.25, floor_center_z)
	_sub_viewport.add_child(floor_body)

	var roller_mesh := CylinderMesh.new()
	roller_mesh.top_radius = CONVEYOR_ROLLER_RADIUS
	roller_mesh.bottom_radius = CONVEYOR_ROLLER_RADIUS
	roller_mesh.height = CONVEYOR_ROLLER_LENGTH
	roller_mesh.radial_segments = 64
	_conveyor_roller_front_material = ShaderMaterial.new()
	_conveyor_roller_front_material.shader = CONVEYOR_FLOOR_SHADER
	_conveyor_roller_front_material.set_shader_parameter("scroll_z", 0.0)
	_conveyor_roller_front_material.set_shader_parameter("scroll_sign", -1.0)
	_conveyor_roller_front_material.set_shader_parameter("roller_mode", 1.0)
	_conveyor_roller_front_material.set_shader_parameter("roller_radius", CONVEYOR_ROLLER_RADIUS)
	_conveyor_roller_front_material.set_shader_parameter("roller_contact_z", top_front_contact_z)
	_conveyor_roller_front_material.set_shader_parameter("roller_arc_sign", 1.0)
	_conveyor_roller_front_material.set_shader_parameter("base_color", CONVEYOR_BELT_BASE_COLOR)
	_conveyor_roller_front_material.set_shader_parameter("stripe_color", CONVEYOR_BELT_STRIPE_COLOR)
	_conveyor_roller_front_material.set_shader_parameter("side_color", CONVEYOR_BELT_SIDE_COLOR)
	var roller_front := MeshInstance3D.new()
	roller_front.mesh = roller_mesh
	roller_front.material_override = _conveyor_roller_front_material
	roller_front.rotation = Vector3(0.0, 0.0, PI * 0.5)
	roller_front.position = Vector3(0.0, roller_center_y, front_z)
	_sub_viewport.add_child(roller_front)

	var return_mesh := BoxMesh.new()
	return_mesh.size = Vector3(CONVEYOR_ROLLER_LENGTH, CONVEYOR_RETURN_BELT_THICKNESS, 8.0)
	var return_belt := MeshInstance3D.new()
	return_belt.mesh = return_mesh
	_conveyor_return_material = ShaderMaterial.new()
	_conveyor_return_material.shader = CONVEYOR_FLOOR_SHADER
	_conveyor_return_material.set_shader_parameter("scroll_z", 0.0)
	_conveyor_return_material.set_shader_parameter("scroll_sign", 1.0)
	_conveyor_return_material.set_shader_parameter("base_color", CONVEYOR_BELT_BASE_COLOR)
	_conveyor_return_material.set_shader_parameter("stripe_color", CONVEYOR_BELT_STRIPE_COLOR)
	_conveyor_return_material.set_shader_parameter("side_color", CONVEYOR_BELT_SIDE_COLOR)
	return_belt.material_override = _conveyor_return_material
	return_belt.position = Vector3(0.0, roller_center_y - CONVEYOR_ROLLER_RADIUS, front_z - 4.0)
	_sub_viewport.add_child(return_belt)

	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(FLOOR_RAIL_WIDTH, FLOOR_RAIL_HEIGHT, floor_length)
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.27, 0.275, 0.28)
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

func _style_all_buttons() -> void:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.14, 0.16, 0.22, 0.8)
	normal_style.border_color = Color(0.28, 0.32, 0.42, 0.8)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(10)
	normal_style.content_margin_left = 14.0
	normal_style.content_margin_right = 14.0
	normal_style.content_margin_top = 8.0
	normal_style.content_margin_bottom = 8.0
	var hover_style := normal_style.duplicate()
	hover_style.bg_color = Color(0.18, 0.20, 0.28, 0.9)
	hover_style.border_color = Color(0.4, 0.5, 0.7, 0.9)
	for btn: Button in _get_all_buttons(self):
		if _emote_grid and btn.get_parent() == _emote_grid:
			continue
		if btn == _skin_player_btn_p1 or btn == _skin_player_btn_p2:
			continue
		btn.add_theme_stylebox_override("normal", normal_style.duplicate())
		btn.add_theme_stylebox_override("hover", hover_style.duplicate())
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
		btn.add_theme_color_override("font_hover_color", Color(0.95, 0.97, 1.0))

func _get_all_buttons(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		buttons.append_array(_get_all_buttons(child))
	return buttons

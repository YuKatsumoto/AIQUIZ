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
const SKIN_PREVIEW_CAM_DIST_Z: float = 2.78
const SKIN_PREVIEW_CAM_Y: float = 1.35
const SKIN_PREVIEW_CAM_LOOK_Y: float = 1.08
## 右上UIと帽子の重なりを避ける: 正面の向きは維持したままカメラ位置だけ X 方向に平行移動
const SKIN_PREVIEW_CAM_OFFSET_X: float = -0.60
## エモートタブ: look_at のまま画面内フレームだけ左寄せ（ビューポート幅に対する比率）
const EMOTE_PREVIEW_CAM_H_OFFSET: float = 0.70
const SKIN_PREVIEW_FOV: float = 38.0
## 通常時のプレビューカメラ追従（エモート操作の反応）
const CAM_PREVIEW_SMOOTH_RATE: float = 9.0
## タブ切替直後のみ。大きいほど素早く目的姿勢へ収束（通常 CAM_PREVIEW_SMOOTH_RATE より低めで差を残す）
const CAM_TAB_TRANSITION_SMOOTH_RATE: float = 4.6
const PREVIEW_DOOR_HALF_DEPTH_Z: float = 0.30
const PREVIEW_BLUE_DOOR_INDEX: int = 0
const PREVIEW_RED_DOOR_INDEX: int = 1
const AUTO_WALL_SPEED: float = 28.0 / (4.0 + 5.0)
## エモートタブ時にベルト表示速度が 0 に近づく時間感（小さいほど早く減速）
const BELT_VISUAL_RAMP_TAU_SEC: float = 1.25
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
## エモートタブ初期オービット距離（大きいほど引いた画角）
const EMOTE_CAM_DEFAULT_DISTANCE: float = 5.2
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
## スキンタブ：帽子切替（頭ローカル X）。画面外まで離し、入り／出りで重ならない
const HAT_SLIDE_OFFSCREEN_X: float = 2.85
const HAT_SLIDE_DURATION: float = 0.24
const HAT_SLIDE_ENTER_EASE_POW: float = 2.25
const HAT_SLIDE_EXIT_EASE_POW: float = 0.72
const HAT_SLIDE_ENTER_DELAY_FRAC: float = 0.12
const HAT_SLIDE_INCOMING_Z: float = 0.035
## 帽子メッシュ幅の余白（マウント原点から画面端までの距離に加算）
const HAT_SLIDE_MESH_MARGIN: float = 0.50
## ビューポート端を越えてからさらに押し出す距離（完全に画面外へ消す）
const HAT_SLIDE_EXIT_OVERSHOOT: float = 0.35
const HAT_SLIDE_SCREEN_EDGE_X_FRAC: float = 0.985
const HAT_SLIDE_SCREEN_PAD_PX: float = 10.0

var _sub_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_world_env: WorldEnvironment
var _skin_front_spot: SpotLight3D
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

const SLOT_KEYS_P1 := ["1", "2", "3"]
const SLOT_KEYS_P2 := ["8", "9", "0"]

var _section_buttons: Dictionary = {}
var _settings_panel: PanelContainer
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
var _hat_slide_active: bool = false
var _hat_slide_t: float = 0.0
var _hat_slide_dir: int = 0
var _hat_slide_player_id: int = 1
var _hat_slide_target_id: int = 0
var _hat_slide_old: Node3D = null
var _hat_slide_new: Node3D = null
var _hat_slide_offscreen_dist: float = HAT_SLIDE_OFFSCREEN_X

var _emote_player_btn_p1: Button
var _emote_player_btn_p2: Button
var _emote_browse_icon_label: Label
var _emote_browse_name_label: Label
var _emote_browse_desc_label: Label
var _emote_slot_btns: Array[Button] = []
var _active_assign_slot_idx: int = 0
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
var _emote_cam_distance: float = EMOTE_CAM_DEFAULT_DISTANCE
var _emote_cam_target: Vector3 = Vector3(PREVIEW_PLAYER_P1_X, 0.2, 0.0)
var _emote_cam_dragging: bool = false
var _emote_cam_panning: bool = false
## タブ切替直後は CAM_TAB_TRANSITION_SMOOTH_RATE で寄せ、収束したら通常レートに戻す
var _preview_cam_tab_transition_active: bool = false

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
		if _active_section == Section.WALL_SPEED:
			_poll_preview_emote_inputs()
		_preview_gs._active_wall_speed = _belt_visual_speed
		_preview_player.update_from_state(_preview_gs)
		_preview_player.visible = _active_section != Section.EMOTE
		_force_preview_player_facing_away()

	_update_preview_debris_near_camera()

	if _active_section == Section.EMOTE:
		_emote_preview_time += dt
		for entry in _emote_lane_previews:
			var br: Node3D = entry.get("block_root", null)
			if br == null or not is_instance_valid(br):
				continue
			if int(entry.get("preview_emote_id", EmoteData.EMOTE_NONE)) == EmoteData.EMOTE_NONE:
				var sway_ph: float = float(entry.get("idle_sway_phase", 0.0))
				br.rotation.y = sin(_emote_preview_time * 0.6 + sway_ph) * 0.5
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

	if _active_section == Section.SKIN:
		_update_skin_preview_lighting()

	_process_hat_slide(dt)

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
	h_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.add_child(h_split)

	var spacer_left := Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_left.size_flags_stretch_ratio = 1.15
	spacer_left.mouse_filter = Control.MOUSE_FILTER_STOP
	spacer_left.gui_input.connect(_on_emote_preview_gui_input)
	_preview_input_catcher = spacer_left
	h_split.add_child(spacer_left)

	_settings_panel = PanelContainer.new()
	_settings_panel.custom_minimum_size = Vector2(520, 480)
	_settings_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_settings_panel.clip_contents = true
	var settings_style := StyleBoxFlat.new()
	settings_style.bg_color = Color(0.05, 0.08, 0.12, 0.86)
	settings_style.set_border_width_all(2)
	settings_style.border_color = Color(0.3, 0.4, 0.6, 0.5)
	settings_style.set_corner_radius_all(24)
	settings_style.content_margin_left = 28.0
	settings_style.content_margin_right = 28.0
	settings_style.content_margin_top = 24.0
	settings_style.content_margin_bottom = 24.0
	_settings_panel.add_theme_stylebox_override("panel", settings_style)
	h_split.add_child(_settings_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_panel.add_child(outer_vbox)

	_section_title = Label.new()
	_section_title.text = "統合設定"
	_section_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_section_title.add_theme_font_size_override("font_size", 30)
	_section_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	outer_vbox.add_child(_section_title)

	var section_row := HBoxContainer.new()
	section_row.add_theme_constant_override("separation", 10)
	outer_vbox.add_child(section_row)

	_section_buttons[Section.WALL_SPEED] = _make_section_button("⚡ 壁速度", section_row, Section.WALL_SPEED)
	_section_buttons[Section.SKIN] = _make_section_button("🧢 スキン", section_row, Section.SKIN)
	_section_buttons[Section.EMOTE] = _make_section_button("💃 エモート", section_row, Section.EMOTE)

	outer_vbox.add_child(HSeparator.new())

	var body_scroll := ScrollContainer.new()
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(body_scroll)

	var body_vbox := VBoxContainer.new()
	body_vbox.add_theme_constant_override("separation", 12)
	body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body_vbox)

	_wall_panel = VBoxContainer.new()
	_wall_panel.add_theme_constant_override("separation", 10)
	body_vbox.add_child(_wall_panel)
	_build_wall_panel()

	_skin_panel = VBoxContainer.new()
	_skin_panel.add_theme_constant_override("separation", 10)
	body_vbox.add_child(_skin_panel)
	_build_skin_panel()

	_emote_panel = VBoxContainer.new()
	_emote_panel.add_theme_constant_override("separation", 8)
	body_vbox.add_child(_emote_panel)
	_build_emote_panel()

	outer_vbox.add_child(HSeparator.new())
	var back_btn := Button.new()
	back_btn.text = "✓ 決定して戻る"
	back_btn.custom_minimum_size = Vector2(0, 52)
	back_btn.pressed.connect(_on_back_pressed)
	outer_vbox.add_child(back_btn)

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

	var emote_hint := Label.new()
	emote_hint.text = "左プレビュー: キー 1・2・3（P1）  8・9・0（P2）でエモート  Spaceで停止"
	emote_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emote_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	emote_hint.add_theme_font_size_override("font_size", 11)
	emote_hint.add_theme_color_override("font_color", Color(0.55, 0.60, 0.72))
	_wall_panel.add_child(emote_hint)

func _build_skin_panel() -> void:
	_skin_player_label = Label.new()
	_skin_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skin_player_label.add_theme_font_size_override("font_size", 20)
	_skin_panel.add_child(_skin_player_label)

	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 8)
	_skin_panel.add_child(player_row)

	_skin_player_btn_p2 = Button.new()
	_skin_player_btn_p2.text = "プレイヤー２"
	_skin_player_btn_p2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_player_btn_p2.custom_minimum_size = Vector2(0, 44)
	_skin_player_btn_p2.pressed.connect(func() -> void: _set_skin_editing_player(2))
	player_row.add_child(_skin_player_btn_p2)

	_skin_player_btn_p1 = Button.new()
	_skin_player_btn_p1.text = "プレイヤー１"
	_skin_player_btn_p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_player_btn_p1.custom_minimum_size = Vector2(0, 44)
	_skin_player_btn_p1.pressed.connect(func() -> void: _set_skin_editing_player(1))
	player_row.add_child(_skin_player_btn_p1)

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
	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 8)
	_emote_panel.add_child(player_row)

	_emote_player_btn_p1 = Button.new()
	_emote_player_btn_p1.text = "プレイヤー１"
	_emote_player_btn_p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emote_player_btn_p1.custom_minimum_size = Vector2(0, 44)
	_emote_player_btn_p1.pressed.connect(func() -> void: _set_emote_editing_player(1))
	player_row.add_child(_emote_player_btn_p1)

	_emote_player_btn_p2 = Button.new()
	_emote_player_btn_p2.text = "プレイヤー２"
	_emote_player_btn_p2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emote_player_btn_p2.custom_minimum_size = Vector2(0, 44)
	_emote_player_btn_p2.pressed.connect(func() -> void: _set_emote_editing_player(2))
	player_row.add_child(_emote_player_btn_p2)

	var slot_detail_hbox := HBoxContainer.new()
	slot_detail_hbox.add_theme_constant_override("separation", 10)
	_emote_panel.add_child(slot_detail_hbox)

	var slot_vbox_left := VBoxContainer.new()
	slot_vbox_left.add_theme_constant_override("separation", 6)
	slot_vbox_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_vbox_left.size_flags_stretch_ratio = 1.0
	slot_detail_hbox.add_child(slot_vbox_left)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_stretch_ratio = 1.3
	detail_panel.size_flags_vertical = Control.SIZE_FILL
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = Color(0.08, 0.10, 0.16, 0.92)
	detail_style.border_color = Color(0.28, 0.38, 0.55, 0.65)
	detail_style.set_border_width_all(1)
	detail_style.set_corner_radius_all(12)
	detail_style.content_margin_left = 12.0
	detail_style.content_margin_right = 12.0
	detail_style.content_margin_top = 10.0
	detail_style.content_margin_bottom = 10.0
	detail_panel.add_theme_stylebox_override("panel", detail_style)
	slot_detail_hbox.add_child(detail_panel)

	var detail_vbox := VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 4)
	detail_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	detail_panel.add_child(detail_vbox)

	_emote_browse_icon_label = Label.new()
	_emote_browse_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emote_browse_icon_label.add_theme_font_size_override("font_size", 28)
	detail_vbox.add_child(_emote_browse_icon_label)

	_emote_browse_name_label = Label.new()
	_emote_browse_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emote_browse_name_label.add_theme_font_size_override("font_size", 16)
	_emote_browse_name_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	detail_vbox.add_child(_emote_browse_name_label)

	_emote_browse_desc_label = Label.new()
	_emote_browse_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emote_browse_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_emote_browse_desc_label.add_theme_font_size_override("font_size", 11)
	_emote_browse_desc_label.add_theme_color_override("font_color", Color(0.58, 0.62, 0.72))
	detail_vbox.add_child(_emote_browse_desc_label)

	_emote_slot_btns.clear()
	for i in range(3):
		var slot_btn := Button.new()
		slot_btn.custom_minimum_size = Vector2(180, 46)
		slot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		slot_btn.set_meta("slot_idx", i)
		var slot_idx := i
		slot_btn.pressed.connect(func() -> void: _set_active_assign_slot(slot_idx))

		var slot_hbox := HBoxContainer.new()
		slot_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot_hbox.anchor_right = 1.0
		slot_hbox.anchor_bottom = 1.0
		slot_hbox.offset_left = 6.0
		slot_hbox.offset_right = -6.0
		slot_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		slot_hbox.add_theme_constant_override("separation", 6)
		slot_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_btn.add_child(slot_hbox)

		var key_lbl := Label.new()
		key_lbl.name = "KeyLabel"
		key_lbl.custom_minimum_size = Vector2(28, 0)
		key_lbl.add_theme_font_size_override("font_size", 11)
		key_lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.72))
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_hbox.add_child(key_lbl)

		var icon_lbl := Label.new()
		icon_lbl.name = "IconLabel"
		icon_lbl.custom_minimum_size = Vector2(24, 0)
		icon_lbl.add_theme_font_size_override("font_size", 18)
		icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_hbox.add_child(icon_lbl)

		var name_lbl := Label.new()
		name_lbl.name = "NameLabel"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_lbl.clip_text = true
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(0.88, 0.90, 0.96))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_hbox.add_child(name_lbl)

		slot_vbox_left.add_child(slot_btn)
		_emote_slot_btns.append(slot_btn)

	var emote_cam_hint := Label.new()
	emote_cam_hint.text = "左プレビュー: 右ドラッグ＝回転  ホイール＝ズーム"
	emote_cam_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emote_cam_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	emote_cam_hint.add_theme_font_size_override("font_size", 11)
	emote_cam_hint.add_theme_color_override("font_color", Color(0.55, 0.60, 0.72))
	_emote_panel.add_child(emote_cam_hint)

	_emote_panel.add_child(HSeparator.new())

	var grid_title := Label.new()
	grid_title.text = "エモート一覧"
	grid_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid_title.add_theme_font_size_override("font_size", 15)
	grid_title.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_emote_panel.add_child(grid_title)

	_emote_grid = GridContainer.new()
	_emote_grid.columns = 3
	_emote_grid.add_theme_constant_override("h_separation", 8)
	_emote_grid.add_theme_constant_override("v_separation", 8)
	_emote_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emote_panel.add_child(_emote_grid)

	_grid_card_by_id.clear()
	var emote_list := EmoteData.get_emote_list()
	for entry in emote_list:
		var eid: int = entry["id"]
		var ename: String = entry["name"]
		var eicon: String = entry["icon"]

		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 68)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("normal", _grid_card_normal_style())
		card.add_theme_stylebox_override("hover", _grid_card_hover_style())
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		var card_vbox := VBoxContainer.new()
		card_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		card_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		card_vbox.add_theme_constant_override("separation", 2)
		card_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(card_vbox)

		var card_icon := Label.new()
		card_icon.text = eicon
		card_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_icon.add_theme_font_size_override("font_size", 24)
		card_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_vbox.add_child(card_icon)

		var card_name := Label.new()
		card_name.text = ename
		card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_name.add_theme_font_size_override("font_size", 11)
		card_name.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
		card_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_vbox.add_child(card_name)

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
	_preview_world_env = WorldEnvironment.new()
	_preview_world_env.environment = env
	_sub_viewport.add_child(_preview_world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -20, 0)
	light.light_energy = 0.8
	light.shadow_enabled = true
	_sub_viewport.add_child(light)

	_skin_front_spot = SpotLight3D.new()
	_skin_front_spot.name = "SkinFrontSpot"
	_skin_front_spot.visible = false
	_skin_front_spot.light_color = Color(1.0, 0.98, 0.94)
	_skin_front_spot.light_energy = 1.05
	_skin_front_spot.shadow_enabled = false
	_skin_front_spot.spot_range = 14.0
	_skin_front_spot.spot_angle = 58.0
	_skin_front_spot.spot_angle_attenuation = 0.55
	_sub_viewport.add_child(_skin_front_spot)

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
	var prev_section := _active_section
	if prev_section == Section.SKIN and section != Section.SKIN:
		_finish_hat_slide_immediate()
	if prev_section == Section.WALL_SPEED and section != Section.WALL_SPEED:
		_stop_preview_wall_speed_emotes()
	_active_section = section
	if prev_section != section:
		_preview_cam_tab_transition_active = true
	_wall_panel.visible = section == Section.WALL_SPEED
	_skin_panel.visible = section == Section.SKIN
	_emote_panel.visible = section == Section.EMOTE

	var target_height := 640.0
	match section:
		Section.WALL_SPEED:
			target_height = 480.0
		Section.SKIN:
			target_height = 440.0
		Section.EMOTE:
			target_height = 640.0

	if is_inside_tree():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(_settings_panel, "custom_minimum_size:y", target_height, 0.22)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_settings_panel.custom_minimum_size.y = target_height

	for key in _section_buttons.keys():
		var btn: Button = _section_buttons[key]
		btn.disabled = key == section

	if _preview_input_catcher:
		_preview_input_catcher.mouse_filter = (
			Control.MOUSE_FILTER_STOP if section == Section.EMOTE else Control.MOUSE_FILTER_IGNORE
		)

	match section:
		Section.WALL_SPEED:
			_set_skin_preview_lighting_active(false)
			_section_title.visible = true
			_section_title.text = "⚡ 壁速度設定"
			_cleanup_emote_preview()
			_preview_player.visible = true
			if _preview_walls.is_empty():
				_replenish_preview_walls_after_emote()
		Section.SKIN:
			_set_skin_preview_lighting_active(true)
			_update_skin_preview_lighting()
			_section_title.visible = true
			_section_title.text = "🧢 スキン設定"
			_explode_preview_walls_for_emote()
			_cleanup_emote_preview()
			_preview_player.visible = true
			_sync_preview_hat()
		Section.EMOTE:
			_set_skin_preview_lighting_active(false)
			_explode_preview_walls_for_emote()
			_section_title.visible = true
			_section_title.text = "💃 エモート設定"
			if _emote_preview_holder:
				_emote_preview_holder.visible = true
			_reset_emote_orbit_default()
			_preview_player.visible = false
			_active_assign_slot_idx = 0
			var gs_emote := QuizManager.game_state
			var slots_emote: Array[int] = gs_emote.p1_emote_slots if _editing_player == 1 else gs_emote.p2_emote_slots
			if slots_emote.size() > 0:
				_browsing_emote_id = slots_emote[0]
			_update_emote_panel_ui()
			_highlight_grid_card_for_emote(_browsing_emote_id)
			_refresh_emote_lane_previews()

func _preview_editing_lane_x() -> float:
	return PREVIEW_PLAYER_P1_X if _editing_player == 1 else PREVIEW_PLAYER_P2_X


func _update_skin_preview_lighting() -> void:
	if not _skin_front_spot:
		return
	_skin_front_spot.visible = true
	var tx := _preview_editing_lane_x()
	var look_tgt := Vector3(tx, SKIN_PREVIEW_CAM_LOOK_Y, 0.0)
	var cam_pos := Vector3(
		tx + SKIN_PREVIEW_CAM_OFFSET_X,
		SKIN_PREVIEW_CAM_Y,
		-SKIN_PREVIEW_CAM_DIST_Z * 0.75,
	)
	_skin_front_spot.global_position = cam_pos
	_skin_front_spot.look_at(look_tgt, Vector3.UP)
	if _preview_world_env and _preview_world_env.environment:
		_preview_world_env.environment.ambient_light_energy = 1.18
		_preview_world_env.environment.ambient_light_color = Color(0.38, 0.40, 0.44)


func _set_skin_preview_lighting_active(active: bool) -> void:
	if _skin_front_spot:
		_skin_front_spot.visible = active
	if _preview_world_env and _preview_world_env.environment:
		_preview_world_env.environment.ambient_light_energy = 1.18 if active else 1.0
		_preview_world_env.environment.ambient_light_color = (
			Color(0.38, 0.40, 0.44) if active else Color(0.30, 0.32, 0.35)
		)


func _snap_preview_camera_to_current_section() -> void:
	if not _preview_camera:
		return
	var d := _get_desired_preview_camera()
	_preview_camera.position = d.pos
	_preview_camera.quaternion = d.quat
	_preview_camera.fov = d.fov
	_preview_camera.h_offset = d.get("h_offset", 0.0)
	_preview_camera.v_offset = d.get("v_offset", 0.0)


func _get_desired_preview_camera() -> Dictionary:
	match _active_section:
		Section.WALL_SPEED:
			var qw := Quaternion.from_euler(
				Vector3(deg_to_rad(-14.0), deg_to_rad(-18.0), 0.0),
			)
			return {
				"pos": Vector3(-5.2, 4.5, 16.0),
				"quat": qw,
				"fov": 65.0,
				"h_offset": 0.65,
				"v_offset": 0.0,
			}
		Section.SKIN:
			var tx_skin := _preview_editing_lane_x()
			var look_tgt := Vector3(tx_skin, SKIN_PREVIEW_CAM_LOOK_Y, 0.0)
			var cam_base := Vector3(tx_skin, SKIN_PREVIEW_CAM_Y, -SKIN_PREVIEW_CAM_DIST_Z)
			var qs := _camera_quat_look_at(cam_base, look_tgt)
			var cam_pos_skin := cam_base + Vector3(SKIN_PREVIEW_CAM_OFFSET_X, 0.0, 0.0)
			return {
				"pos": cam_pos_skin,
				"quat": qs,
				"fov": SKIN_PREVIEW_FOV,
				"h_offset": 0.0,
				"v_offset": 0.0,
			}
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
			return {
				"pos": cam_pos,
				"quat": qe,
				"fov": 40.0,
				"h_offset": EMOTE_PREVIEW_CAM_H_OFFSET,
				"v_offset": 0.0,
			}
	return {
		"pos": Vector3.ZERO,
		"quat": Quaternion.IDENTITY,
		"fov": 60.0,
		"h_offset": 0.0,
		"v_offset": 0.0,
	}


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
	var rate := (
		CAM_TAB_TRANSITION_SMOOTH_RATE
		if _preview_cam_tab_transition_active
		else CAM_PREVIEW_SMOOTH_RATE
	)
	var k: float = 1.0 - exp(-rate * dt)
	_preview_camera.position = _preview_camera.position.lerp(d.pos, k)
	_preview_camera.quaternion = _preview_camera.quaternion.slerp(d.quat, k)
	_preview_camera.fov = lerpf(_preview_camera.fov, d.fov, k)
	var h_tgt: float = d.get("h_offset", 0.0)
	var v_tgt: float = d.get("v_offset", 0.0)
	_preview_camera.h_offset = lerpf(_preview_camera.h_offset, h_tgt, k)
	_preview_camera.v_offset = lerpf(_preview_camera.v_offset, v_tgt, k)
	if _preview_cam_tab_transition_active and _preview_camera_close_to_desired(d):
		_preview_cam_tab_transition_active = false

func _preview_camera_close_to_desired(d: Dictionary) -> bool:
	var pos: Vector3 = d.pos
	var quat: Quaternion = d.quat
	var fov: float = d.fov
	var h_tgt: float = d.get("h_offset", 0.0)
	var v_tgt: float = d.get("v_offset", 0.0)
	if _preview_camera.position.distance_to(pos) > 0.06:
		return false
	if absf(_preview_camera.fov - fov) > 0.25:
		return false
	if absf(_preview_camera.h_offset - h_tgt) > 0.02:
		return false
	if absf(_preview_camera.v_offset - v_tgt) > 0.02:
		return false
	return _preview_camera.quaternion.angle_to(quat) < 0.02


func _reset_emote_orbit_default() -> void:
	_emote_cam_yaw = 0.0
	_emote_cam_pitch = -8.0
	_emote_cam_distance = EMOTE_CAM_DEFAULT_DISTANCE
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
	_refresh_emote_player_button_styles()

	if gs and _preview_player and _preview_player.has_method("set_hat") and not _hat_slide_active:
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
	_finish_hat_slide_immediate()
	_editing_player = which
	_refresh_all_labels()
	if _active_section == Section.SKIN:
		_update_skin_preview_lighting()

func _player_accent_btn_theme(btn: Button, accent: Color, selected: bool) -> void:
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
	_player_accent_btn_theme(_skin_player_btn_p1, PlayerController.P1_BODY, _editing_player == 1)
	_player_accent_btn_theme(_skin_player_btn_p2, PlayerController.P2_BODY, _editing_player == 2)


func _refresh_emote_player_button_styles() -> void:
	if not _emote_player_btn_p1 or not _emote_player_btn_p2:
		return
	_player_accent_btn_theme(_emote_player_btn_p1, PlayerController.P1_BODY, _editing_player == 1)
	_player_accent_btn_theme(_emote_player_btn_p2, PlayerController.P2_BODY, _editing_player == 2)

func _on_hat_prev() -> void:
	if _hat_slide_active:
		return
	var next_hat := (_get_current_hat() - 1 + HatData.HAT_COUNT) % HatData.HAT_COUNT
	_apply_hat_change_animated(next_hat, -1)

func _on_hat_next() -> void:
	if _hat_slide_active:
		return
	var next_hat := (_get_current_hat() + 1) % HatData.HAT_COUNT
	_apply_hat_change_animated(next_hat, 1)

func _emote_catalog_entry(emote_id: int) -> Dictionary:
	var id := EmoteData.normalize_emote_id(emote_id)
	for entry in EmoteData.get_emote_list():
		if int(entry["id"]) == id:
			return entry
	return {"id": EmoteData.EMOTE_NONE, "name": "なし", "icon": "—", "desc": ""}


func _editing_player_emote_slots() -> Array[int]:
	var gs := QuizManager.game_state
	return gs.p1_emote_slots if _editing_player == 1 else gs.p2_emote_slots


func _set_emote_editing_player(which: int) -> void:
	if which != 1 and which != 2:
		return
	if _editing_player == which:
		return
	_editing_player = which
	var slots := _editing_player_emote_slots()
	if slots.size() > 0:
		_browsing_emote_id = slots[0]
	_active_assign_slot_idx = 0
	_refresh_all_labels()
	if _active_section != Section.EMOTE:
		return
	_sync_emote_orbit_lane_x()
	_highlight_grid_card_for_emote(_browsing_emote_id)
	_refresh_emote_lane_previews()


func _set_active_assign_slot(idx: int) -> void:
	if idx < 0 or idx > 2:
		return
	_active_assign_slot_idx = idx
	_update_emote_panel_ui()


func _update_emote_browse_detail() -> void:
	if not _emote_browse_name_label:
		return
	var entry := _emote_catalog_entry(_browsing_emote_id)
	if _emote_browse_icon_label:
		_emote_browse_icon_label.text = str(entry.get("icon", "—"))
	_emote_browse_name_label.text = str(entry.get("name", "なし"))
	if _emote_browse_desc_label:
		_emote_browse_desc_label.text = EmoteData.get_emote_desc(_browsing_emote_id)


func _slot_card_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.17, 0.26, 0.95) if selected else Color(0.10, 0.11, 0.17, 0.92)
	style.border_color = Color(0.45, 0.65, 1.0, 0.95) if selected else Color(0.22, 0.26, 0.36, 0.85)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _update_emote_panel_ui() -> void:
	if not _emote_player_btn_p1:
		return
	_refresh_emote_player_button_styles()
	_update_emote_browse_detail()

	var slots := _editing_player_emote_slots()
	var keys := SLOT_KEYS_P1 if _editing_player == 1 else SLOT_KEYS_P2
	for i in range(_emote_slot_btns.size()):
		var slot_btn: Button = _emote_slot_btns[i]
		var selected := i == _active_assign_slot_idx
		var slot_style := _slot_card_style(selected)
		slot_btn.add_theme_stylebox_override("normal", slot_style)
		slot_btn.add_theme_stylebox_override("hover", slot_style)
		slot_btn.add_theme_stylebox_override("pressed", slot_style)

		var emote_id := EmoteData.normalize_emote_id(
			slots[i] if i < slots.size() else EmoteData.EMOTE_NONE
		)
		var entry := _emote_catalog_entry(emote_id)
		var slot_hbox := slot_btn.get_child(0) as HBoxContainer
		if slot_hbox:
			var key_lbl := slot_hbox.get_node_or_null("KeyLabel") as Label
			var icon_lbl := slot_hbox.get_node_or_null("IconLabel") as Label
			var name_lbl := slot_hbox.get_node_or_null("NameLabel") as Label
			if key_lbl:
				key_lbl.text = "[ %s ]" % keys[i]
			if icon_lbl:
				icon_lbl.text = str(entry.get("icon", "—"))
			if name_lbl:
				name_lbl.text = str(entry.get("name", "なし"))

func _grid_card_normal_style() -> StyleBoxFlat:
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.13, 0.19)
	card_style.border_color = Color(0.25, 0.28, 0.38)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(10)
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
	sel_style.set_corner_radius_all(10)
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
	_browsing_emote_id = EmoteData.normalize_emote_id(emote_id)
	
	var gs := QuizManager.game_state
	var slots := _editing_player_emote_slots().duplicate()
	if _active_assign_slot_idx >= 0 and _active_assign_slot_idx < slots.size():
		slots[_active_assign_slot_idx] = _browsing_emote_id
		if _editing_player == 1:
			gs.p1_emote_slots = slots
		else:
			gs.p2_emote_slots = slots

	_update_emote_browse_detail()
	_update_emote_panel_ui()
	if _active_section == Section.EMOTE:
		_refresh_emote_lane_previews()

func _lane_preview_emote_id_for_player(is_p1_lane: bool, gs: QuizGameState) -> int:
	## 編集中レーンのみグリッドの閲覧中 ID。もう一方はそのプレイヤーのスロット0をそのまま表示。
	if is_p1_lane:
		if _editing_player == 1:
			return EmoteData.normalize_emote_id(_browsing_emote_id)
		var sid := gs.p1_emote_slots[0] if gs.p1_emote_slots.size() > 0 else EmoteData.EMOTE_NONE
		return EmoteData.normalize_emote_id(sid)
	if _editing_player == 2:
		return EmoteData.normalize_emote_id(_browsing_emote_id)
	var sid2 := gs.p2_emote_slots[0] if gs.p2_emote_slots.size() > 0 else EmoteData.EMOTE_NONE
	return EmoteData.normalize_emote_id(sid2)

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

	emote_id = EmoteData.normalize_emote_id(emote_id)
	entry.preview_emote_id = emote_id
	entry.idle_sway_phase = 0.0 if is_p1 else PI

	if emote_id == EmoteData.EMOTE_NONE:
		block_root.rotation.y = 0.0
		return entry

	if EmoteData.is_thriller_emote(emote_id):
		EmoteBlockmanPreview.setup_thriller_sequence_preview(
			entry,
			_sub_viewport,
			lane_x,
			Callable(self, "_pick_best_emote_animation"),
		)
		block_root.rotation.y = 0.0
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
			var anim_played: Animation = entry.ap.get_animation(best_name)
			if anim_played and anim_played.length > 0.05:
				entry.ap.advance(randf() * anim_played.length)

	block_root.rotation.y = 0.0
	return entry


func _cleanup_emote_lane_previews() -> void:
	for entry in _emote_lane_previews:
		if entry.get("is_thriller_sequence", false):
			EmoteBlockmanPreview.free_thriller_sequence(entry)
		var fbx: Node3D = entry.get("fbx", null)
		if fbx != null and is_instance_valid(fbx):
			fbx.queue_free()
		var br: Node3D = entry.get("block_root", null)
		if br != null and is_instance_valid(br):
			br.queue_free()
	_emote_lane_previews.clear()


func _refresh_emote_lane_previews() -> void:
	if _active_section != Section.EMOTE:
		return
	if not _emote_preview_holder:
		return

	_cleanup_emote_lane_previews()
	var gm := QuizManager.game_state
	var lane_infos: Array[Dictionary] = [
		{"lane_x": PREVIEW_PLAYER_P1_X, "is_p1": true, "hat": gm.p1_hat},
		{"lane_x": PREVIEW_PLAYER_P2_X, "is_p1": false, "hat": gm.p2_hat},
	]

	for lane_info in lane_infos:
		var lx: float = float(lane_info["lane_x"])
		var lane_p1: bool = bool(lane_info["is_p1"])
		var hid: int = int(lane_info["hat"])
		var eid := _lane_preview_emote_id_for_player(lane_p1, gm)
		var e := _spawn_lane_emote_preview(eid, lx, lane_p1, hid)
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


func _sync_preview_hat_for_player(player_id: int) -> void:
	if not _preview_player or not _preview_player.has_method("set_hat"):
		return
	var gs := QuizManager.game_state
	var hat_id := gs.p1_hat if player_id == 1 else gs.p2_hat
	_preview_player.set_hat(player_id, hat_id)


func _apply_hat_change_animated(new_hat_id: int, direction: int) -> void:
	_set_current_hat(new_hat_id)
	_hat_name_label.text = HatData.get_hat_name(new_hat_id)
	if _active_section != Section.SKIN:
		_sync_preview_hat_for_player(_editing_player)
		return
	_start_hat_slide_preview(_editing_player, new_hat_id, direction)


func _start_hat_slide_preview(player_id: int, new_hat_id: int, direction: int) -> void:
	_finish_hat_slide_immediate()
	var pc := _preview_player as PlayerController
	if pc == null:
		_sync_preview_hat_for_player(player_id)
		return

	var is_p1 := player_id == 1
	var parts: Dictionary = pc.p1_parts if is_p1 else pc.p2_parts
	if not parts.has("hat_mount"):
		_sync_preview_hat_for_player(player_id)
		return
	var mount: Node3D = parts["hat_mount"]
	_update_hat_slide_screen_bounds(mount)

	var old_node: Node3D = pc._p1_hat_node if is_p1 else pc._p2_hat_node
	if is_p1:
		pc._p1_hat_node = null
	else:
		pc._p2_hat_node = null
	parts["hat_meshes"] = []

	var new_node: Node3D = null
	if new_hat_id != HatData.HAT_NONE:
		new_node = HatFactory.create_hat(new_hat_id)
		if new_node:
			mount.add_child(new_node)
			new_node.position = Vector3(
				float(direction) * _hat_slide_offscreen_dist,
				0.0,
				HAT_SLIDE_INCOMING_Z,
			)

	if old_node and is_instance_valid(old_node):
		old_node.position = Vector3.ZERO
		_set_hat_slide_node_visible(old_node, true)

	if new_node and is_instance_valid(new_node):
		_set_hat_slide_node_visible(new_node, true)

	if old_node == null and new_node == null:
		_sync_preview_hat_for_player(player_id)
		return

	_hat_slide_active = true
	_hat_slide_t = 0.0
	_hat_slide_dir = direction
	_hat_slide_player_id = player_id
	_hat_slide_target_id = new_hat_id
	_hat_slide_old = old_node
	_hat_slide_new = new_node


func _hat_slide_enter_weight(u: float) -> float:
	# 画面外から勢いよく飛び込み、装着位置で減速
	return 1.0 - pow(1.0 - u, HAT_SLIDE_ENTER_EASE_POW)


func _hat_slide_exit_weight(u: float) -> float:
	# 前半で素早く画面外へ（入りより先に抜ける）
	return pow(u, HAT_SLIDE_EXIT_EASE_POW)


func _update_hat_slide_screen_bounds(mount: Node3D) -> void:
	_hat_slide_offscreen_dist = _compute_hat_slide_offscreen_x(mount)


func _compute_hat_slide_offscreen_x(mount: Node3D) -> float:
	if mount == null or not _preview_camera or not _sub_viewport:
		return HAT_SLIDE_OFFSCREEN_X
	var vp_size := _sub_viewport.size
	if vp_size.x < 16 or vp_size.y < 16:
		return HAT_SLIDE_OFFSCREEN_X
	var screen_y := float(vp_size.y) * 0.32
	var pad := HAT_SLIDE_SCREEN_PAD_PX
	var left_x := _hat_slide_local_x_at_screen(mount, pad, screen_y)
	var right_x := _hat_slide_local_x_at_screen(
		mount,
		float(vp_size.x) * HAT_SLIDE_SCREEN_EDGE_X_FRAC,
		screen_y,
	)
	var edge := maxf(left_x, right_x)
	if edge < 0.01:
		return HAT_SLIDE_OFFSCREEN_X
	return edge + HAT_SLIDE_MESH_MARGIN + HAT_SLIDE_EXIT_OVERSHOOT


func _hat_slide_local_x_at_screen(mount: Node3D, screen_x: float, screen_y: float) -> float:
	var cam := _preview_camera
	var ray_o := cam.project_ray_origin(Vector2(screen_x, screen_y))
	var ray_d := cam.project_ray_normal(Vector2(screen_x, screen_y))
	var plane_n := -cam.global_transform.basis.z.normalized()
	var denom := plane_n.dot(ray_d)
	if absf(denom) < 1e-6:
		return 0.0
	var t := plane_n.dot(mount.global_position - ray_o) / denom
	if t <= 0.0:
		return 0.0
	var hit := ray_o + ray_d * t
	return absf(mount.to_local(hit).x)


func _set_hat_slide_node_visible(node: Node3D, visible: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.visible = visible


func _process_hat_slide(dt: float) -> void:
	if not _hat_slide_active:
		return
	_hat_slide_t += dt
	var u := clampf(_hat_slide_t / HAT_SLIDE_DURATION, 0.0, 1.0)
	var enter_u := clampf(
		(u - HAT_SLIDE_ENTER_DELAY_FRAC) / (1.0 - HAT_SLIDE_ENTER_DELAY_FRAC),
		0.0,
		1.0,
	)
	var enter_w := _hat_slide_enter_weight(enter_u)
	var exit_w := _hat_slide_exit_weight(u)
	var off := _hat_slide_offscreen_dist
	var dir_f := float(_hat_slide_dir)
	var enter_x := lerpf(dir_f * off, 0.0, enter_w)
	var exit_x := lerpf(0.0, -dir_f * off, exit_w)
	if _hat_slide_old and is_instance_valid(_hat_slide_old):
		_hat_slide_old.position.x = exit_x
	if _hat_slide_new and is_instance_valid(_hat_slide_new):
		_hat_slide_new.position.x = enter_x
		_hat_slide_new.position.z = lerpf(HAT_SLIDE_INCOMING_Z, 0.0, enter_w)
	if u >= 1.0:
		_finish_hat_slide()


func _finish_hat_slide() -> void:
	if not _hat_slide_active:
		return
	if _hat_slide_old and is_instance_valid(_hat_slide_old):
		_hat_slide_old.queue_free()
	if _hat_slide_new and is_instance_valid(_hat_slide_new):
		_hat_slide_new.queue_free()
	var player_id := _hat_slide_player_id
	var hat_id := _hat_slide_target_id
	_hat_slide_active = false
	_hat_slide_old = null
	_hat_slide_new = null
	_hat_slide_t = 0.0
	if _preview_player and _preview_player.has_method("set_hat"):
		_preview_player.set_hat(player_id, hat_id)


func _finish_hat_slide_immediate() -> void:
	if not _hat_slide_active:
		return
	if _hat_slide_old and is_instance_valid(_hat_slide_old):
		_hat_slide_old.queue_free()
	if _hat_slide_new and is_instance_valid(_hat_slide_new):
		_hat_slide_new.queue_free()
	var player_id := _hat_slide_player_id
	_hat_slide_active = false
	_hat_slide_old = null
	_hat_slide_new = null
	_hat_slide_t = 0.0
	_sync_preview_hat_for_player(player_id)

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
	_stop_preview_wall_speed_emotes()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _read_emote_keys_pressed(slots_p1: Array, slots_p2: Array, num_players: int) -> Vector2i:
	var emote_p1 := 0
	var emote_p2 := 0
	if Input.is_key_pressed(KEY_1) and slots_p1.size() > 0:
		emote_p1 = int(slots_p1[0])
	elif Input.is_key_pressed(KEY_2) and slots_p1.size() > 1:
		emote_p1 = int(slots_p1[1])
	elif Input.is_key_pressed(KEY_3) and slots_p1.size() > 2:
		emote_p1 = int(slots_p1[2])
	if num_players >= 2:
		if (Input.is_key_pressed(KEY_8) or Input.is_key_pressed(KEY_KP_7)) and slots_p2.size() > 0:
			emote_p2 = int(slots_p2[0])
		elif (Input.is_key_pressed(KEY_9) or Input.is_key_pressed(KEY_KP_8)) and slots_p2.size() > 1:
			emote_p2 = int(slots_p2[1])
		elif (Input.is_key_pressed(KEY_0) or Input.is_key_pressed(KEY_KP_9)) and slots_p2.size() > 2:
			emote_p2 = int(slots_p2[2])
	return Vector2i(emote_p1, emote_p2)


func _stop_preview_wall_speed_emotes() -> void:
	if not _preview_gs:
		return
	_preview_gs.p1_emote = 0
	_preview_gs.p2_emote = 0
	var pc := _preview_player as PlayerController
	if pc:
		pc._p1_rig.stop_all()
		pc._p2_rig.stop_all()
	if _preview_player and _preview_player.has_method("update_from_state"):
		_preview_player.update_from_state(_preview_gs)


func _poll_preview_emote_inputs() -> void:
	if not _preview_gs:
		return
	var gm := QuizManager.game_state
	var pressed := _read_emote_keys_pressed(
		gm.p1_emote_slots,
		gm.p2_emote_slots,
		_preview_gs.num_players,
	)
	if Input.is_key_pressed(KEY_SPACE):
		_stop_preview_wall_speed_emotes()
		return
	if pressed.x > 0 and _preview_gs.p1_alive and _preview_gs.player_vel_y == 0.0:
		_preview_gs.p1_emote = pressed.x
	if pressed.y > 0 and _preview_gs.p2_alive and _preview_gs.player2_vel_y == 0.0:
		_preview_gs.p2_emote = pressed.y


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
		if btn == _emote_player_btn_p1 or btn == _emote_player_btn_p2:
			continue
		if btn in _emote_slot_btns:
			continue
		if btn in _grid_card_by_id.values():
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

extends Control

## 繧ｨ繝｢繝ｼ繝磯∈謚樒判髱｢
## 蟾ｦ蛛ｴ縺ｫ蠎・＞3D繝励Ξ繝薙Η繝ｼ・育判蜒上・繧医≧縺ｫ繧ｭ繝｣繝ｩ縺瑚ｸ翫ｋ・峨∝承蛛ｴ縺ｧ繧ｹ繝ｭ繝・ヨ險ｭ螳壹・## P1縺ｯ繧ｭ繝ｼ1,2,3 / P2縺ｯ繧ｭ繝ｼ8,9,0 縺ｫ繧ｨ繝｢繝ｼ繝医ｒ蜑ｲ繧雁ｽ薙※繧九・
# --- Preview nodes ---
var _sub_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_player: Node3D  # ブロックマン
var _preview_emote_node: Node3D  # FBX rig
var _preview_emote_ap: AnimationPlayer
var _preview_time: float = 0.0
var _current_preview_id: int = 0  # 陦ｨ遉ｺ荳ｭ縺ｮ繧ｨ繝｢繝ｼ繝・D

var _preview_skeleton: Skeleton3D = null
var _preview_bone_indices: Dictionary = {}
var _preview_player_parts: Dictionary = {}
var _preview_root_motion_ready: bool = false
var _preview_root_motion_origin: Vector3 = Vector3.ZERO
var _last_preview_size: Vector2i = Vector2i.ZERO

const BASE_Y: float = -1.2
const PREVIEW_SIZE := Vector2i(1920, 1440)
const PREVIEW_SUPERSAMPLE := 2.0
const MAX_PREVIEW_EDGE := 4096

# --- Camera orbit ---
var _cam_yaw: float = 0.0
var _cam_pitch: float = -3.0
var _cam_distance: float = 4.0
var _cam_target: Vector3 = Vector3(0.0, 0.0, 0.0)
var _cam_dragging: bool = false
var _cam_panning: bool = false
var _cam_last_mouse: Vector2 = Vector2.ZERO
var _svc_node: Control  # 繝槭え繧ｹ繧､繝吶Φ繝育畑蜿ら・
var _preview_texture_rect: TextureRect
var _touch_points: Dictionary = {}
var _last_pinch_dist: float = 0.0

# --- UI nodes ---
var _slot_labels: Array[Label] = []  # 繧ｹ繝ｭ繝・ヨ陦ｨ遉ｺ繝ｩ繝吶Ν [3縺､]
var _emote_name_label: Label
var _emote_desc_label: Label
var _preview_help_label: Label
var _player_toggle_btn: Button
var _back_btn: Button
var _emote_grid: GridContainer  # 繧ｨ繝｢繝ｼ繝医げ繝ｪ繝・ラ
var _selected_grid_btn: Button = null  # 驕ｸ謚樔ｸｭ縺ｮ繧ｰ繝ｪ繝・ラ繝懊ち繝ｳ

# --- State ---
var _editing_player: int = 1  # 1 or 2
var _editing_slot: int = 0    # 0,1,2
var _browsing_emote_id: int = 0  # 繧ｨ繝｢繝ｼ繝医Μ繧ｹ繝亥・縺ｧ驕ｸ謚樔ｸｭ縺ｮID
var game_state: QuizGameState

const SLOT_KEYS_P1 := ["1", "2", "3"]
const SLOT_KEYS_P2 := ["8", "9", "0"]

func _ready() -> void:
	game_state = QuizManager.game_state
	_build_ui()
	_build_3d_preview()
	get_viewport().size_changed.connect(_update_preview_viewport_size)
	_update_all()
	# 譛蛻昴・繧ｹ繝ｭ繝・ヨ縺ｮ繧ｨ繝｢繝ｼ繝医ｒ繝励Ξ繝薙Η繝ｼ
	_preview_emote(game_state.p1_emote_slots[0])
	call_deferred("_update_preview_viewport_size")

func _process(dt: float) -> void:
	_preview_time += dt
	# WASD 繧ｫ繝｡繝ｩ遘ｻ蜍・
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): move.y -= 1
	if Input.is_key_pressed(KEY_S): move.y += 1
	if Input.is_key_pressed(KEY_A): move.x -= 1
	if Input.is_key_pressed(KEY_D): move.x += 1
	if move != Vector2.ZERO:
		var yaw_rad := deg_to_rad(_cam_yaw)
		var right := Vector3(cos(yaw_rad), 0, -sin(yaw_rad))
		var forward := Vector3(sin(yaw_rad), 0, cos(yaw_rad))
		_cam_target += (right * move.x + forward * move.y) * dt * 2.0
	# 繧ｹ繧ｱ繝ｫ繝医Φ繧｢繝九Γ驕ｩ逕ｨ
	if _current_preview_id == 0:
		if _preview_player:
			_preview_player.rotation.y = sin(_preview_time * 0.6) * 0.5
	else:
		if _preview_player:
			_preview_player.rotation.y = 0.0
		if _preview_emote_ap and _preview_emote_ap.is_playing() and _preview_skeleton:
			_apply_skeleton_pose(_preview_player_parts, _preview_skeleton, _preview_bone_indices, true)
	# 繧ｫ繝｡繝ｩ霆碁％譖ｴ譁ｰ
	_update_orbit_camera()

func _update_orbit_camera() -> void:
	if not _preview_camera:
		return
	var yaw_rad := deg_to_rad(_cam_yaw)
	var pitch_rad := deg_to_rad(clampf(_cam_pitch, -80.0, 80.0))
	var offset := Vector3(
		_cam_distance * cos(pitch_rad) * sin(yaw_rad),
		_cam_distance * sin(pitch_rad),
		_cam_distance * cos(pitch_rad) * cos(yaw_rad)
	)
	_preview_camera.position = _cam_target + offset
	_preview_camera.look_at(_cam_target, Vector3.UP)

func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_cam_dragging = mb.pressed
			_cam_last_mouse = mb.position
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_cam_panning = mb.pressed
			_cam_last_mouse = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_distance = maxf(1.5, _cam_distance - 0.3)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_distance = minf(12.0, _cam_distance + 0.3)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _cam_dragging:
			_cam_yaw -= mm.relative.x * 0.3
			_cam_pitch -= mm.relative.y * 0.3
			_cam_pitch = clampf(_cam_pitch, -80.0, 80.0)
		elif _cam_panning:
			var yaw_rad := deg_to_rad(_cam_yaw)
			var right := Vector3(cos(yaw_rad), 0, -sin(yaw_rad))
			_cam_target += right * mm.relative.x * -0.005
			_cam_target.y += mm.relative.y * 0.005
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_points[st.index] = st.position
		else:
			_touch_points.erase(st.index)
			if _touch_points.is_empty():
				_last_pinch_dist = 0.0
				_cam_dragging = false
		
		if _touch_points.size() == 1:
			_cam_dragging = true
			_cam_last_mouse = st.position
		else:
			_cam_dragging = false
			if _touch_points.size() == 2:
				var keys = _touch_points.keys()
				_last_pinch_dist = _touch_points[keys[0]].distance_to(_touch_points[keys[1]])
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touch_points[sd.index] = sd.position
		
		if _touch_points.size() == 1:
			_cam_yaw -= sd.relative.x * 0.25
			_cam_pitch -= sd.relative.y * 0.25
			_cam_pitch = clampf(_cam_pitch, -80.0, 80.0)
		elif _touch_points.size() == 2:
			var keys = _touch_points.keys()
			var current_dist: float = _touch_points[keys[0]].distance_to(_touch_points[keys[1]])
			if _last_pinch_dist > 0.0:
				var diff := current_dist - _last_pinch_dist
				_cam_distance = clampf(_cam_distance - diff * 0.015, 1.5, 12.0)
			_last_pinch_dist = current_dist

func _build_ui() -> void:
	# 笏笏 閭梧勹 笏笏
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 笏笏 繝｡繧､繝ｳ繝ｬ繧､繧｢繧ｦ繝茨ｼ域ｰｴ蟷ｳ: 繝励Ξ繝薙Η繝ｼ蟾ｦ + 險ｭ螳壼承・俄楳笏
	var main_hbox := HBoxContainer.new()
	main_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 0)
	add_child(main_hbox)

	# === 蟾ｦ蛛ｴ: 3D繝励Ξ繝薙Η繝ｼ鬆伜沺 ===
	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_stretch_ratio = 1.5
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.05, 0.06, 0.09)
	preview_style.set_border_width_all(2)
	preview_style.border_color = Color(0.2, 0.25, 0.35)
	preview_style.set_corner_radius_all(12)
	preview_style.content_margin_left = 8.0
	preview_style.content_margin_right = 8.0
	preview_style.content_margin_top = 8.0
	preview_style.content_margin_bottom = 8.0
	preview_panel.add_theme_stylebox_override("panel", preview_style)
	main_hbox.add_child(preview_panel)

	var preview_vbox := VBoxContainer.new()
	preview_vbox.add_theme_constant_override("separation", 8)
	preview_panel.add_child(preview_vbox)

	var preview_title := Label.new()
	preview_title.text = "💃 ダンスプレビュー"
	preview_title.add_theme_font_size_override("font_size", 20)
	preview_title.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_vbox.add_child(preview_title)

	# エモート名表示
	_emote_name_label = Label.new()
	_emote_name_label.add_theme_font_size_override("font_size", 22)
	_emote_name_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	_emote_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_vbox.add_child(_emote_name_label)

	# SubViewportContainer + small operation hint overlay
	var preview_stage := Control.new()
	preview_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_vbox.add_child(preview_stage)

	_preview_texture_rect = TextureRect.new()
	_preview_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_preview_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview_texture_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_texture_rect.gui_input.connect(_on_preview_gui_input)
	_preview_texture_rect.resized.connect(_update_preview_viewport_size)
	_svc_node = _preview_texture_rect
	preview_stage.add_child(_preview_texture_rect)

	_sub_viewport = SubViewport.new()
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.transparent_bg = false
	_apply_ultra_preview_quality(_sub_viewport, PREVIEW_SIZE)
	preview_stage.add_child(_sub_viewport)
	_preview_texture_rect.texture = _sub_viewport.get_texture()

	_preview_help_label = Label.new()
	_preview_help_label.text = "右ドラッグ: 回転  中ドラッグ/WASD: 移動  ホイール: ズーム"
	_preview_help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_help_label.add_theme_font_size_override("font_size", 11)
	_preview_help_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.95, 0.78))
	_preview_help_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.70))
	_preview_help_label.add_theme_constant_override("shadow_offset_x", 1)
	_preview_help_label.add_theme_constant_override("shadow_offset_y", 1)
	_preview_help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_preview_help_label.offset_left = 12.0
	_preview_help_label.offset_top = -26.0
	_preview_help_label.offset_right = 520.0
	_preview_help_label.offset_bottom = -8.0
	preview_stage.add_child(_preview_help_label)

	# エモート説明
	_emote_desc_label = Label.new()
	_emote_desc_label.add_theme_font_size_override("font_size", 14)
	_emote_desc_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	_emote_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_vbox.add_child(_emote_desc_label)

	# === 右側: 設定パネル ===
	var settings_panel := PanelContainer.new()
	settings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_panel.size_flags_stretch_ratio = 1.0
	var settings_style := StyleBoxFlat.new()
	settings_style.bg_color = Color(0.10, 0.11, 0.16)
	settings_style.content_margin_left = 28.0
	settings_style.content_margin_right = 28.0
	settings_style.content_margin_top = 20.0
	settings_style.content_margin_bottom = 20.0
	settings_panel.add_theme_stylebox_override("panel", settings_style)
	main_hbox.add_child(settings_panel)

	var settings_vbox := VBoxContainer.new()
	settings_vbox.add_theme_constant_override("separation", 14)
	settings_panel.add_child(settings_vbox)

	# タイトル
	var title := Label.new()
	title.text = "💃 エモート設定"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_vbox.add_child(title)

	# プレイヤー切替ボタン
	_player_toggle_btn = Button.new()
	_player_toggle_btn.custom_minimum_size = Vector2(0, 44)
	_player_toggle_btn.add_theme_font_size_override("font_size", 18)
	_player_toggle_btn.pressed.connect(_on_player_toggle)
	settings_vbox.add_child(_player_toggle_btn)

	# 説明
	var desc := Label.new()
	desc.text = "各スロットに好きなダンスを割り当てて、\nゲーム中にキーを押してエモート発動！"
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.55, 0.58, 0.68))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_vbox.add_child(desc)

	settings_vbox.add_child(HSeparator.new())

	# --- スロット設定エリア ---
	for i in range(3):
		var slot_hbox := HBoxContainer.new()
		slot_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_hbox.add_theme_constant_override("separation", 8)
		settings_vbox.add_child(slot_hbox)

		# キー表示
		var key_label := Label.new()
		key_label.add_theme_font_size_override("font_size", 16)
		key_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		key_label.custom_minimum_size = Vector2(60, 0)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_hbox.add_child(key_label)

		# ◀ ボタン
		var left_btn := Button.new()
		left_btn.text = "◀"
		left_btn.custom_minimum_size = Vector2(40, 36)
		left_btn.add_theme_font_size_override("font_size", 18)
		var slot_idx := i
		left_btn.pressed.connect(func(): _on_slot_change(slot_idx, -1))
		slot_hbox.add_child(left_btn)

		# エモート名ラベル
		var emote_label := Label.new()
		emote_label.custom_minimum_size = Vector2(180, 0)
		emote_label.add_theme_font_size_override("font_size", 16)
		emote_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
		emote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_hbox.add_child(emote_label)
		_slot_labels.append(emote_label)

		# ▶ ボタン
		var right_btn := Button.new()
		right_btn.text = "▶"
		right_btn.custom_minimum_size = Vector2(40, 36)
		right_btn.add_theme_font_size_override("font_size", 18)
		right_btn.pressed.connect(func(): _on_slot_change(slot_idx, +1))
		slot_hbox.add_child(right_btn)

	settings_vbox.add_child(HSeparator.new())

	# エモートグリッド（Mixamo風カタログ）
	var grid_title := Label.new()
	grid_title.text = "🔍 エモート一覧"
	grid_title.add_theme_font_size_override("font_size", 16)
	grid_title.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	grid_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_vbox.add_child(grid_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_vbox.add_child(scroll)

	_emote_grid = GridContainer.new()
	_emote_grid.columns = 3
	_emote_grid.add_theme_constant_override("h_separation", 6)
	_emote_grid.add_theme_constant_override("v_separation", 6)
	_emote_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_emote_grid)

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
		card.mouse_filter = Control.MOUSE_FILTER_PASS

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

	# 戻るボタン
	_back_btn = Button.new()
	_back_btn.text = "❌ 決定して戻る"
	_back_btn.custom_minimum_size = Vector2(0, 52)
	_back_btn.add_theme_font_size_override("font_size", 18)
	_back_btn.pressed.connect(_on_back_pressed)
	settings_vbox.add_child(_back_btn)

	_style_buttons()

func _build_3d_preview() -> void:
	# 迺ｰ蠅・
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.75, 0.78, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.42, 0.48)
	env.ambient_light_energy = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = false
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_sub_viewport.add_child(world_env)

	# 繧ｫ繝｡繝ｩ 窶・霆碁％繧ｫ繝｡繝ｩ・・update_orbit_camera 縺ｧ豈弱ヵ繝ｬ繝ｼ繝譖ｴ譁ｰ・・
	_preview_camera = Camera3D.new()
	_preview_camera.fov = 40.0
	_sub_viewport.add_child(_preview_camera)
	# 蛻晄悄霆碁％繝代Λ繝｡繝ｼ繧ｿ
	_cam_yaw = 0.0
	_cam_pitch = -8.0
	_cam_distance = 4.0
	_cam_target = Vector3(0.0, 0.2, 0.0)
	_update_orbit_camera()

	# 繝ｩ繧､繝・
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-40, -30, 0)
	key_light.light_color = Color(0.95, 0.93, 0.90)
	key_light.light_energy = 1.8
	key_light.shadow_enabled = true
	_sub_viewport.add_child(key_light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 120, 0)
	fill.light_color = Color(0.6, 0.65, 0.8)
	fill.light_energy = 0.5
	_sub_viewport.add_child(fill)

	# 蠎・＞蠎奇ｼ医げ繝ｪ繝・ラ鬚ｨ・・
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	plane.subdivide_width = 20
	plane.subdivide_depth = 20
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.55, 0.58, 0.62)
	floor_mat.roughness = 0.85
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, -1.2, 0)
	_sub_viewport.add_child(floor_mesh)

	# グリッド線
	for ix in range(-10, 11):
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.02, 0.005, 20.0)
		line.mesh = box
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.45, 0.47, 0.50)
		line.material_override = lm
		line.position = Vector3(ix * 1.0, -1.195, 0)
		_sub_viewport.add_child(line)
	for iz in range(-10, 11):
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(20.0, 0.005, 0.02)
		line.mesh = box
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.45, 0.47, 0.50)
		line.material_override = lm
		line.position = Vector3(0, -1.195, iz * 1.0)
		_sub_viewport.add_child(line)

	# プレビュー用のブロックマン
	_preview_player = Node3D.new()
	_preview_player.name = "PreviewPlayer"
	_sub_viewport.add_child(_preview_player)
	
	var is_p1 := true
	_preview_player_parts = _build_player_skeleton(is_p1, _preview_player)

func _apply_ultra_preview_quality(viewport: SubViewport, viewport_size: Vector2i) -> void:
	viewport.size = viewport_size
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.msaa_2d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.use_taa = true
	viewport.use_debanding = true

func _update_preview_viewport_size() -> void:
	if not _sub_viewport or not _svc_node:
		return
	var target_size := _preview_viewport_size_for(_svc_node, PREVIEW_SIZE)
	if target_size == _last_preview_size:
		return
	_sub_viewport.size = target_size
	_last_preview_size = target_size

func _preview_viewport_size_for(control: Control, minimum_size: Vector2i) -> Vector2i:
	if not control:
		return minimum_size
	var display_size := control.size
	if display_size.x <= 1.0 or display_size.y <= 1.0:
		return minimum_size
	var scale := _window_pixel_scale()
	var target_x := ceili(display_size.x * scale * PREVIEW_SUPERSAMPLE)
	var target_y := ceili(display_size.y * scale * PREVIEW_SUPERSAMPLE)
	return Vector2i(
		clampi(target_x, minimum_size.x, MAX_PREVIEW_EDGE),
		clampi(target_y, minimum_size.y, MAX_PREVIEW_EDGE)
	)

func _window_pixel_scale() -> float:
	var logical_size := get_viewport().get_visible_rect().size
	if logical_size.x <= 0.0 or logical_size.y <= 0.0:
		return 1.0
	var window_size := Vector2(DisplayServer.window_get_size())
	return maxf(1.0, maxf(window_size.x / logical_size.x, window_size.y / logical_size.y))

func _preview_emote(emote_id: int) -> void:
	_current_preview_id = emote_id
	_preview_root_motion_ready = false
	_preview_root_motion_origin = Vector3.ZERO
	if _preview_player:
		_preview_player.position = Vector3.ZERO

	# 譌｢蟄倥・FBX繝弱・繝峨ｒ蜑企勁
	if _preview_emote_node and is_instance_valid(_preview_emote_node):
		_preview_emote_node.queue_free()
		_preview_emote_node = null
		_preview_emote_ap = null

	_emote_name_label.text = EmoteData.get_emote_name(emote_id)
	_emote_desc_label.text = ""

	if emote_id == EmoteData.EMOTE_NONE:
		if _preview_player:
			_preview_player.rotation.y = 0.0
		return

	var fbx_path := EmoteData.get_emote_fbx(emote_id)
	if fbx_path.is_empty() or not ResourceLoader.exists(fbx_path):
		return

	var scene := load(fbx_path) as PackedScene
	if not scene:
		return

	var node := scene.instantiate()
	node.name = "EmotePreview"
	_sub_viewport.add_child(node)

	# FBX meshes
	for child in node.find_children("*", "MeshInstance3D", true, false):
		child.hide()

	# Skeleton
	_preview_skeleton = null
	_preview_bone_indices.clear()
	for child in node.find_children("*", "Skeleton3D", true, false):
		_preview_skeleton = child as Skeleton3D
		break
	
	if _preview_skeleton:
		var candidates: Dictionary = {
			"hips": ["Hips", "mixamorig:Hips"],
			"spine": ["Spine1", "mixamorig:Spine1", "Spine", "mixamorig:Spine"],
			"neck": ["Neck", "mixamorig:Neck"],
			"head": ["Head", "mixamorig:Head"],
			"l_upper_arm": ["LeftUpperArm", "mixamorig:LeftArm"],
			"l_lower_arm": ["LeftLowerArm", "mixamorig:LeftForeArm"],
			"l_hand": ["LeftHand", "mixamorig:LeftHand"],
			"r_upper_arm": ["RightUpperArm", "mixamorig:RightArm"],
			"r_lower_arm": ["RightLowerArm", "mixamorig:RightForeArm"],
			"r_hand": ["RightHand", "mixamorig:RightHand"],
			"l_upper_leg": ["LeftUpperLeg", "mixamorig:LeftUpLeg"],
			"l_lower_leg": ["LeftLowerLeg", "mixamorig:LeftLeg"],
			"l_foot": ["LeftFoot", "mixamorig:LeftFoot"],
			"l_toe": ["LeftToeBase", "mixamorig:LeftToeBase"],
			"r_upper_leg": ["RightUpperLeg", "mixamorig:RightUpLeg"],
			"r_lower_leg": ["RightLowerLeg", "mixamorig:RightLeg"],
			"r_foot": ["RightFoot", "mixamorig:RightFoot"],
			"r_toe": ["RightToeBase", "mixamorig:RightToeBase"],
			
			# Left hand fingers
			"l_thumb_prox": ["LeftThumbMetacarpal", "mixamorig:LeftHandThumb1", "mixamorig_LeftHandThumb1", "LeftHandThumb1"],
			"l_thumb_dist": ["LeftThumbProximal", "mixamorig:LeftHandThumb2", "mixamorig_LeftHandThumb2", "LeftHandThumb2"],
			"l_index_prox": ["LeftIndexProximal", "mixamorig:LeftHandIndex1", "mixamorig_LeftHandIndex1", "LeftHandIndex1"],
			"l_index_mid": ["LeftIndexIntermediate", "mixamorig:LeftHandIndex2", "mixamorig_LeftHandIndex2", "LeftHandIndex2"],
			"l_index_dist": ["LeftIndexDistal", "mixamorig:LeftHandIndex3", "mixamorig_LeftHandIndex3", "LeftHandIndex3"],
			"l_middle_prox": ["LeftMiddleProximal", "mixamorig:LeftHandMiddle1", "mixamorig_LeftHandMiddle1", "LeftHandMiddle1"],
			"l_middle_mid": ["LeftMiddleIntermediate", "mixamorig:LeftHandMiddle2", "mixamorig_LeftHandMiddle2", "LeftHandMiddle2"],
			"l_middle_dist": ["LeftMiddleDistal", "mixamorig:LeftHandMiddle3", "mixamorig_LeftHandMiddle3", "LeftHandMiddle3"],
			"l_ring_prox": ["LeftRingProximal", "mixamorig:LeftHandRing1", "mixamorig_LeftHandRing1", "LeftHandRing1"],
			"l_ring_mid": ["LeftRingIntermediate", "mixamorig:LeftHandRing2", "mixamorig_LeftHandRing2", "LeftHandRing2"],
			"l_ring_dist": ["LeftRingDistal", "mixamorig:LeftHandRing3", "mixamorig_LeftHandRing3", "LeftHandRing3"],
			"l_pinky_prox": ["LeftLittleProximal", "mixamorig:LeftHandPinky1", "mixamorig_LeftHandPinky1", "LeftHandPinky1"],
			"l_pinky_mid": ["LeftLittleIntermediate", "mixamorig:LeftHandPinky2", "mixamorig_LeftHandPinky2", "LeftHandPinky2"],
			"l_pinky_dist": ["LeftLittleDistal", "mixamorig:LeftHandPinky3", "mixamorig_LeftHandPinky3", "LeftHandPinky3"],
			
			# Right hand fingers
			"r_thumb_prox": ["RightThumbMetacarpal", "mixamorig:RightHandThumb1", "mixamorig_RightHandThumb1", "RightHandThumb1"],
			"r_thumb_dist": ["RightThumbProximal", "mixamorig:RightHandThumb2", "mixamorig_RightHandThumb2", "RightHandThumb2"],
			"r_index_prox": ["RightIndexProximal", "mixamorig:RightHandIndex1", "mixamorig_RightHandIndex1", "RightHandIndex1"],
			"r_index_mid": ["RightIndexIntermediate", "mixamorig:RightHandIndex2", "mixamorig_RightHandIndex2", "RightHandIndex2"],
			"r_index_dist": ["RightIndexDistal", "mixamorig:RightHandIndex3", "mixamorig_RightHandIndex3", "RightHandIndex3"],
			"r_middle_prox": ["RightMiddleProximal", "mixamorig:RightHandMiddle1", "mixamorig_RightHandMiddle1", "RightHandMiddle1"],
			"r_middle_mid": ["RightMiddleIntermediate", "mixamorig:RightHandMiddle2", "mixamorig_RightHandMiddle2", "RightHandMiddle2"],
			"r_middle_dist": ["RightMiddleDistal", "mixamorig:RightHandMiddle3", "mixamorig_RightHandMiddle3", "RightHandMiddle3"],
			"r_ring_prox": ["RightRingProximal", "mixamorig:RightHandRing1", "mixamorig_RightHandRing1", "RightHandRing1"],
			"r_ring_mid": ["RightRingIntermediate", "mixamorig:RightHandRing2", "mixamorig_RightHandRing2", "RightHandRing2"],
			"r_ring_dist": ["RightRingDistal", "mixamorig:RightHandRing3", "mixamorig_RightHandRing3", "RightHandRing3"],
			"r_pinky_prox": ["RightLittleProximal", "mixamorig:RightHandPinky1", "mixamorig_RightHandPinky1", "RightHandPinky1"],
			"r_pinky_mid": ["RightLittleIntermediate", "mixamorig:RightHandPinky2", "mixamorig_RightHandPinky2", "RightHandPinky2"],
			"r_pinky_dist": ["RightLittleDistal", "mixamorig:RightHandPinky3", "mixamorig_RightHandPinky3", "RightHandPinky3"]
		}
		for key in candidates.keys():
			for cand in candidates[key]:
				var idx = _preview_skeleton.find_bone(cand)
				if idx != -1:
					_preview_bone_indices[key] = idx
					break
		print("[EmotePreview] Mapped ", _preview_bone_indices.keys())

	# AnimationPlayer繧呈爾縺励※繝吶せ繝医い繝九Γ繝ｼ繧ｷ繝ｧ繝ｳ繧貞・逕・
	for child in node.find_children("*", "AnimationPlayer", true, false):
		_preview_emote_ap = child as AnimationPlayer
		break

	if _preview_emote_ap:
		var best_name := ""
		var best_tracks := -1
		for lib_name in _preview_emote_ap.get_animation_library_list():
			var lib: AnimationLibrary = _preview_emote_ap.get_animation_library(lib_name)
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
		if best_name != "":
			var best_anim: Animation = _preview_emote_ap.get_animation(best_name)
			if best_anim:
				var duplicated_anim = best_anim.duplicate()
				duplicated_anim.loop_mode = Animation.LOOP_LINEAR
				
				var split_idx = best_name.find("/")
				var lib_name = ""
				var real_anim_name = best_name
				if split_idx != -1:
					lib_name = best_name.substr(0, split_idx)
					real_anim_name = best_name.substr(split_idx + 1)
				
				var lib = _preview_emote_ap.get_animation_library(lib_name)
				if lib:
					lib.add_animation(real_anim_name, duplicated_anim)
					print("[EmotePreview] Duplicated preview animation and set loop_mode: ", best_name)
			_preview_emote_ap.play(best_name)

	_preview_emote_node = node
	if _preview_player:
		_preview_player.rotation.y = 0.0

func _on_slot_change(slot_idx: int, direction: int) -> void:
	var slots: Array[int]
	if _editing_player == 1:
		slots = game_state.p1_emote_slots
	else:
		slots = game_state.p2_emote_slots

	var current := slots[slot_idx]
	var next_id := (current + direction + EmoteData.EMOTE_COUNT) % EmoteData.EMOTE_COUNT
	slots[slot_idx] = next_id

	if _editing_player == 1:
		game_state.p1_emote_slots = slots
		GameManager.p1_emote_slots = slots.duplicate()
	else:
		game_state.p2_emote_slots = slots
		GameManager.p2_emote_slots = slots.duplicate()
	GameManager._save_user_settings()

	_update_all()
	_preview_emote(next_id)

func _on_grid_emote_selected(emote_id: int, card: Button) -> void:
	# 蜑阪・驕ｸ謚槭ｒ繝ｪ繧ｻ繝・ヨ
	if _selected_grid_btn and is_instance_valid(_selected_grid_btn):
		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = Color(0.12, 0.13, 0.19)
		normal_style.border_color = Color(0.25, 0.28, 0.38)
		normal_style.set_border_width_all(1)
		normal_style.set_corner_radius_all(8)
		normal_style.content_margin_left = 4.0
		normal_style.content_margin_right = 4.0
		normal_style.content_margin_top = 4.0
		normal_style.content_margin_bottom = 4.0
		_selected_grid_btn.add_theme_stylebox_override("normal", normal_style)
	# 譁ｰ縺励＞驕ｸ謚槭ｒ繝上う繝ｩ繧､繝・
	_selected_grid_btn = card
	var sel_style := StyleBoxFlat.new()
	sel_style.bg_color = Color(0.15, 0.25, 0.45)
	sel_style.border_color = Color(0.4, 0.65, 1.0)
	sel_style.set_border_width_all(2)
	sel_style.set_corner_radius_all(8)
	sel_style.content_margin_left = 4.0
	sel_style.content_margin_right = 4.0
	sel_style.content_margin_top = 4.0
	sel_style.content_margin_bottom = 4.0
	card.add_theme_stylebox_override("normal", sel_style)
	# 繝励Ξ繝薙Η繝ｼ蜀咲函
	_browsing_emote_id = emote_id
	_preview_emote(emote_id)

func _on_player_toggle() -> void:
	_editing_player = 2 if _editing_player == 1 else 1
	_update_all()
	
	if _preview_player and is_instance_valid(_preview_player):
		_preview_player.queue_free()
	
	_preview_player = Node3D.new()
	_preview_player.name = "PreviewPlayer"
	_sub_viewport.add_child(_preview_player)
	_preview_player_parts = _build_player_skeleton(_editing_player == 1, _preview_player)
	
	var slots := game_state.p1_emote_slots if _editing_player == 1 else game_state.p2_emote_slots
	if slots.size() > 0:
		_preview_emote(slots[0])

func _update_all() -> void:
	# 繝励Ξ繧､繝､繝ｼ蛻・崛繝懊ち繝ｳ
	var p_col: Color
	if _editing_player == 1:
		_player_toggle_btn.text = "👤 P1 設定中 (➡ P2に切替)"
		p_col = Color(0.95, 0.55, 0.20)
	else:
		_player_toggle_btn.text = "👤 P2 設定中 (➡ P1に切替)"
		p_col = Color(0.20, 0.65, 0.90)
	_player_toggle_btn.add_theme_color_override("font_color", p_col)

	var slots := game_state.p1_emote_slots if _editing_player == 1 else game_state.p2_emote_slots
	var keys := SLOT_KEYS_P1 if _editing_player == 1 else SLOT_KEYS_P2

	for i in range(3):
		if i < _slot_labels.size():
			var emote_id := slots[i] if i < slots.size() else 0
			_slot_labels[i].text = EmoteData.get_emote_name(emote_id)
		# キーラベルを更新
		var slot_hbox := _slot_labels[i].get_parent()
		if slot_hbox and slot_hbox.get_child_count() > 0:
			var key_label := slot_hbox.get_child(0) as Label
			if key_label:
				key_label.text = "[ %s ]" % keys[i]

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

# ============================================================
# Skeleton & Animation Utilities (Copied from PlayerController for preview)
# ============================================================

func _build_player_skeleton(is_p1: bool, parent_node: Node3D) -> Dictionary:
	var body_col: Color = PlayerController.P1_BODY if is_p1 else PlayerController.P2_BODY
	var head_col: Color = PlayerController.P1_HEAD if is_p1 else PlayerController.P2_HEAD
	var limb_col: Color = PlayerController.P1_LIMB if is_p1 else PlayerController.P2_LIMB

	var parts := {}

	# Pelvis (Root for all animations)
	var pelvis = Node3D.new()
	pelvis.name = "Pelvis"
	pelvis.position = Vector3(0, BASE_Y + 0.9, 0)
	parent_node.add_child(pelvis)
	parts["pelvis"] = pelvis

	# Lower Torso (hip/belly area)
	var lower_torso = _create_box(Vector3(0.38, 0.22, 0.22), body_col)
	lower_torso.position = Vector3(0, 0.15, 0)
	pelvis.add_child(lower_torso)
	parts["lower_torso"] = lower_torso

	# Spine pivot
	var spine = Node3D.new()
	spine.name = "Spine"
	spine.position = Vector3(0, 0.30, 0)
	pelvis.add_child(spine)
	parts["spine"] = spine

	# Upper Torso
	var upper_torso = _create_box(Vector3(0.38, 0.26, 0.22), body_col)
	upper_torso.position = Vector3(0, 0.18, 0)
	spine.add_child(upper_torso)
	parts["upper_torso"] = upper_torso

	# Neck pivot
	var neck = Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, 0.42, 0)
	spine.add_child(neck)
	parts["neck"] = neck

	# Head pivot
	var head_pivot = Node3D.new()
	head_pivot.position = Vector3(0, 0.03, 0)
	neck.add_child(head_pivot)
	parts["head_pivot"] = head_pivot

	var head = _create_box(Vector3(0.22, 0.22, 0.22), head_col)
	head.position = Vector3(0, 0.22, 0)
	head_pivot.add_child(head)
	parts["head"] = head

	# Hat mount point
	var hat_mount = Node3D.new()
	hat_mount.name = "HatMount"
	hat_mount.position = Vector3(0, 0.44, 0)
	head_pivot.add_child(hat_mount)
	parts["hat_mount"] = hat_mount

	var hat_id: int = game_state.p1_hat if is_p1 else game_state.p2_hat
	if hat_id != HatData.HAT_NONE:
		var hat_node := HatFactory.create_hat(hat_id)
		if hat_node:
			hat_mount.add_child(hat_node)

	# Left Arm
	var l_shoulder = Node3D.new()
	l_shoulder.position = Vector3(-0.52, 0.35, 0)
	spine.add_child(l_shoulder)
	parts["l_shoulder"] = l_shoulder

	var l_upp_arm = _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	l_upp_arm.position = Vector3(0, -0.20, 0)
	l_shoulder.add_child(l_upp_arm)
	parts["l_upp_arm"] = l_upp_arm

	var l_elbow = Node3D.new()
	l_elbow.position = Vector3(0, -0.40, 0)
	l_shoulder.add_child(l_elbow)
	parts["l_elbow"] = l_elbow

	var l_low_arm = _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	l_low_arm.position = Vector3(0, -0.20, 0)
	l_elbow.add_child(l_low_arm)
	parts["l_low_arm"] = l_low_arm

	var l_wrist = Node3D.new()
	l_wrist.position = Vector3(0, -0.40, 0)
	l_elbow.add_child(l_wrist)
	parts["l_wrist"] = l_wrist

	var l_hand_data = _create_detailed_hand(limb_col, true, parts, "l_")
	var l_hand = l_hand_data["root"]
	l_wrist.add_child(l_hand)
	parts["l_hand"] = l_hand

	# Right Arm
	var r_shoulder = Node3D.new()
	r_shoulder.position = Vector3(0.52, 0.35, 0)
	spine.add_child(r_shoulder)
	parts["r_shoulder"] = r_shoulder

	var r_upp_arm = _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	r_upp_arm.position = Vector3(0, -0.20, 0)
	r_shoulder.add_child(r_upp_arm)
	parts["r_upp_arm"] = r_upp_arm

	var r_elbow = Node3D.new()
	r_elbow.position = Vector3(0, -0.40, 0)
	r_shoulder.add_child(r_elbow)
	parts["r_elbow"] = r_elbow

	var r_low_arm = _create_box(Vector3(0.12, 0.26, 0.12), limb_col)
	r_low_arm.position = Vector3(0, -0.20, 0)
	r_elbow.add_child(r_low_arm)
	parts["r_low_arm"] = r_low_arm

	var r_wrist = Node3D.new()
	r_wrist.position = Vector3(0, -0.40, 0)
	r_elbow.add_child(r_wrist)
	parts["r_wrist"] = r_wrist

	var r_hand_data = _create_detailed_hand(limb_col, false, parts, "r_")
	var r_hand = r_hand_data["root"]
	r_wrist.add_child(r_hand)
	parts["r_hand"] = r_hand

	# Left Leg
	var l_hip = Node3D.new()
	l_hip.position = Vector3(-0.22, 0.0, 0)
	pelvis.add_child(l_hip)
	parts["l_hip"] = l_hip

	var l_thigh = _create_box(Vector3(0.18, 0.285, 0.18), limb_col)
	l_thigh.position = Vector3(0, -0.225, 0)
	l_hip.add_child(l_thigh)
	parts["l_thigh"] = l_thigh

	var l_knee = Node3D.new()
	l_knee.position = Vector3(0, -0.45, 0)
	l_hip.add_child(l_knee)
	parts["l_knee"] = l_knee

	var l_calf = _create_box(Vector3(0.16, 0.285, 0.16), limb_col)
	l_calf.position = Vector3(0, -0.225, 0)
	l_knee.add_child(l_calf)
	parts["l_calf"] = l_calf

	var l_ankle = Node3D.new()
	l_ankle.position = Vector3(0, -0.45, 0)
	l_knee.add_child(l_ankle)
	parts["l_ankle"] = l_ankle

	var l_foot = _create_box(Vector3(0.14, 0.06, 0.22), limb_col)
	l_foot.position = Vector3(0, -0.06, 0.05)
	l_ankle.add_child(l_foot)
	parts["l_foot"] = l_foot

	var l_toe = Node3D.new()
	l_toe.position = Vector3(0, -0.06, 0.22)
	l_ankle.add_child(l_toe)
	parts["l_toe"] = l_toe

	var l_toe_mesh = _create_box(Vector3(0.12, 0.04, 0.08), limb_col)
	l_toe_mesh.position = Vector3(0, -0.02, 0.04)
	l_toe.add_child(l_toe_mesh)
	parts["l_toe_mesh"] = l_toe_mesh

	# Right Leg
	var r_hip = Node3D.new()
	r_hip.position = Vector3(0.22, 0.0, 0)
	pelvis.add_child(r_hip)
	parts["r_hip"] = r_hip

	var r_thigh = _create_box(Vector3(0.18, 0.285, 0.18), limb_col)
	r_thigh.position = Vector3(0, -0.225, 0)
	r_hip.add_child(r_thigh)
	parts["r_thigh"] = r_thigh

	var r_knee = Node3D.new()
	r_knee.position = Vector3(0, -0.45, 0)
	r_hip.add_child(r_knee)
	parts["r_knee"] = r_knee

	var r_calf = _create_box(Vector3(0.16, 0.285, 0.16), limb_col)
	r_calf.position = Vector3(0, -0.225, 0)
	r_knee.add_child(r_calf)
	parts["r_calf"] = r_calf

	var r_ankle = Node3D.new()
	r_ankle.position = Vector3(0, -0.45, 0)
	r_knee.add_child(r_ankle)
	parts["r_ankle"] = r_ankle

	var r_foot = _create_box(Vector3(0.14, 0.06, 0.22), limb_col)
	r_foot.position = Vector3(0, -0.06, 0.05)
	r_ankle.add_child(r_foot)
	parts["r_foot"] = r_foot

	var r_toe = Node3D.new()
	r_toe.position = Vector3(0, -0.06, 0.22)
	r_ankle.add_child(r_toe)
	parts["r_toe"] = r_toe

	var r_toe_mesh = _create_box(Vector3(0.12, 0.04, 0.08), limb_col)
	r_toe_mesh.position = Vector3(0, -0.02, 0.04)
	r_toe.add_child(r_toe_mesh)
	parts["r_toe_mesh"] = r_toe_mesh

	return parts

func _create_box(half_extents: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = half_extents * 2.0
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mat.metallic = 0.1
	mesh_inst.material_override = mat
	return mesh_inst

func _create_detailed_hand(color: Color, is_left: bool, parts: Dictionary, prefix: String) -> Dictionary:
	var hand_root = Node3D.new()
	var meshes: Array = []
	
	# 謇九・縺ｲ繧・(Palm)
	var palm = _create_box(Vector3(0.09, 0.10, 0.05), color)
	palm.position = Vector3(0, -0.10, 0)
	hand_root.add_child(palm)
	meshes.append(palm)
	
	# 隕ｪ謖・(Thumb) - 2 segments
	var thumb_root = Node3D.new()
	var thumb_x = 0.10 if is_left else -0.10
	thumb_root.position = Vector3(thumb_x, -0.05, 0.04)
	thumb_root.rotation = Vector3(deg_to_rad(-20), deg_to_rad(45 if is_left else -45), deg_to_rad(30 if is_left else -30))
	hand_root.add_child(thumb_root)
	parts[prefix + "thumb_prox"] = thumb_root

	
	var thumb_prox = _create_box(Vector3(0.025, 0.04, 0.03), color)
	thumb_prox.position = Vector3(0, -0.04, 0)
	thumb_root.add_child(thumb_prox)
	meshes.append(thumb_prox)
	
	var thumb_joint = Node3D.new()
	thumb_joint.position = Vector3(0, -0.08, 0)
	thumb_joint.rotation = Vector3(deg_to_rad(-15), 0, 0)
	thumb_root.add_child(thumb_joint)
	parts[prefix + "thumb_dist"] = thumb_joint

	
	var thumb_dist = _create_box(Vector3(0.025, 0.035, 0.03), color)
	thumb_dist.position = Vector3(0, -0.035, 0)
	thumb_joint.add_child(thumb_dist)
	meshes.append(thumb_dist)
	
	# 謖・譛ｬ (Fingers) - 3 segments
	var finger_lengths = [0.08, 0.09, 0.085, 0.065]
	var finger_widths = 0.022
	var finger_depths = 0.025
	
	var finger_names = ["index", "middle", "ring", "pinky"]
	
	for i in range(4):
		var fname = finger_names[i]
		var base_length = finger_lengths[i]
		
		var finger_root = Node3D.new()
		var offset_x = (0.066 - (i * 0.044)) if is_left else (-0.066 + (i * 0.044))
		finger_root.position = Vector3(offset_x, -0.20, 0.0)
		
		var spread_angle = deg_to_rad((1.5 - i) * 5)
		if not is_left:
			spread_angle = -spread_angle
		finger_root.rotation = Vector3(deg_to_rad(-5), 0, spread_angle)
		hand_root.add_child(finger_root)
		parts[prefix + fname + "_prox"] = finger_root

		
		# Proximal
		var prox_len = base_length * 0.4
		var prox = _create_box(Vector3(finger_widths, prox_len, finger_depths), color)
		prox.position = Vector3(0, -prox_len, 0)
		finger_root.add_child(prox)
		meshes.append(prox)
		
		var joint1 = Node3D.new()
		joint1.position = Vector3(0, -prox_len * 2, 0)
		joint1.rotation = Vector3(deg_to_rad(-10), 0, 0)
		finger_root.add_child(joint1)
		parts[prefix + fname + "_mid"] = joint1

		
		# Middle
		var mid_len = base_length * 0.35
		var mid = _create_box(Vector3(finger_widths, mid_len, finger_depths), color)
		mid.position = Vector3(0, -mid_len, 0)
		joint1.add_child(mid)
		meshes.append(mid)
		
		var joint2 = Node3D.new()
		joint2.position = Vector3(0, -mid_len * 2, 0)
		joint2.rotation = Vector3(deg_to_rad(-10), 0, 0)
		joint1.add_child(joint2)
		parts[prefix + fname + "_dist"] = joint2

		
		# Distal
		var dist_len = base_length * 0.25
		var dist = _create_box(Vector3(finger_widths, dist_len, finger_depths), color)
		dist.position = Vector3(0, -dist_len, 0)
		joint2.add_child(dist)
		meshes.append(dist)
		
	return {"root": hand_root, "meshes": meshes}

func _apply_skeleton_pose(parts: Dictionary, skeleton: Skeleton3D, bone_indices: Dictionary, mirror_x: bool = false) -> void:
	if not skeleton or bone_indices.is_empty():
		return
	
	var pelvis: Node3D = parts.get("pelvis")
	if not pelvis:
		return
		
	var mirror_matrix = Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	
	if bone_indices.has("hips"):
		var bone_xform = skeleton.get_bone_global_pose(bone_indices["hips"])
		if not _preview_root_motion_ready:
			_preview_root_motion_origin = bone_xform.origin
			_preview_root_motion_ready = true
		var root_motion: Vector3 = bone_xform.origin - _preview_root_motion_origin
		if mirror_x:
			root_motion.x = -root_motion.x
		if _preview_player:
			_preview_player.position = Vector3(root_motion.x, 0.0, root_motion.z)
		pelvis.position = Vector3(
			0.0,
			BASE_Y + bone_xform.origin.y,
			0.0
		)
		var new_pelvis_basis = bone_xform.basis.orthonormalized()
		if mirror_x:
			new_pelvis_basis = mirror_matrix * new_pelvis_basis * mirror_matrix
		pelvis.quaternion = Quaternion(new_pelvis_basis)
	
	var apply_bone = func(part_name: String, bone_key: String, flip: bool = false):
		var node: Node3D = parts.get(part_name)
		if node and bone_indices.has(bone_key):
			var gl_pose = skeleton.get_bone_global_pose(bone_indices[bone_key])
			var new_basis = gl_pose.basis.orthonormalized()
			
			if mirror_x:
				new_basis = mirror_matrix * new_basis * mirror_matrix
				
			if flip:
				new_basis = new_basis * Basis(Vector3.RIGHT, PI)
			node.global_basis = new_basis
	
	apply_bone.call("spine", "spine", false)
	apply_bone.call("neck", "neck", false)
	apply_bone.call("head_pivot", "head", false)
	
	apply_bone.call("l_shoulder", "l_upper_arm", true)
	apply_bone.call("l_elbow", "l_lower_arm", true)
	apply_bone.call("l_wrist", "l_hand", true)
	
	apply_bone.call("r_shoulder", "r_upper_arm", true)
	apply_bone.call("r_elbow", "r_lower_arm", true)
	apply_bone.call("r_wrist", "r_hand", true)
	
	apply_bone.call("l_hip", "l_upper_leg", true)
	apply_bone.call("l_knee", "l_lower_leg", true)
	apply_bone.call("l_ankle", "l_foot", true)
	apply_bone.call("l_toe", "l_toe", true)
	
	apply_bone.call("r_hip", "r_upper_leg", true)
	apply_bone.call("r_knee", "r_lower_leg", true)
	apply_bone.call("r_ankle", "r_foot", true)
	apply_bone.call("r_toe", "r_toe", true)
	
	# Fingers (left)
	apply_bone.call("l_thumb_prox", "l_thumb_prox", true)
	apply_bone.call("l_thumb_dist", "l_thumb_dist", true)
	apply_bone.call("l_index_prox", "l_index_prox", true)
	apply_bone.call("l_index_mid", "l_index_mid", true)
	apply_bone.call("l_index_dist", "l_index_dist", true)
	apply_bone.call("l_middle_prox", "l_middle_prox", true)
	apply_bone.call("l_middle_mid", "l_middle_mid", true)
	apply_bone.call("l_middle_dist", "l_middle_dist", true)
	apply_bone.call("l_ring_prox", "l_ring_prox", true)
	apply_bone.call("l_ring_mid", "l_ring_mid", true)
	apply_bone.call("l_ring_dist", "l_ring_dist", true)
	apply_bone.call("l_pinky_prox", "l_pinky_prox", true)
	apply_bone.call("l_pinky_mid", "l_pinky_mid", true)
	apply_bone.call("l_pinky_dist", "l_pinky_dist", true)
	
	# Fingers (right)
	apply_bone.call("r_thumb_prox", "r_thumb_prox", true)
	apply_bone.call("r_thumb_dist", "r_thumb_dist", true)
	apply_bone.call("r_index_prox", "r_index_prox", true)
	apply_bone.call("r_index_mid", "r_index_mid", true)
	apply_bone.call("r_index_dist", "r_index_dist", true)
	apply_bone.call("r_middle_prox", "r_middle_prox", true)
	apply_bone.call("r_middle_mid", "r_middle_mid", true)
	apply_bone.call("r_middle_dist", "r_middle_dist", true)
	apply_bone.call("r_ring_prox", "r_ring_prox", true)
	apply_bone.call("r_ring_mid", "r_ring_mid", true)
	apply_bone.call("r_ring_dist", "r_ring_dist", true)
	apply_bone.call("r_pinky_prox", "r_pinky_prox", true)
	apply_bone.call("r_pinky_mid", "r_pinky_mid", true)
	apply_bone.call("r_pinky_dist", "r_pinky_dist", true)


func _style_buttons() -> void:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.14, 0.16, 0.22)
	normal_style.border_color = Color(0.28, 0.32, 0.42)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(10)
	normal_style.content_margin_left = 12.0
	normal_style.content_margin_right = 12.0
	normal_style.content_margin_top = 6.0
	normal_style.content_margin_bottom = 6.0

	var hover_style := normal_style.duplicate()
	hover_style.bg_color = Color(0.18, 0.20, 0.28)
	hover_style.border_color = Color(0.4, 0.5, 0.7)

	for btn: Button in _get_all_buttons(self):
		if btn == _back_btn:
			continue
		# 繧ｰ繝ｪ繝・ラ繧ｫ繝ｼ繝峨・迢ｬ閾ｪ繧ｹ繧ｿ繧､繝ｫ繧呈戟縺､縺ｮ縺ｧ繧ｹ繧ｭ繝・・
		if _emote_grid and btn.get_parent() == _emote_grid:
			continue
		btn.add_theme_stylebox_override("normal", normal_style.duplicate())
		btn.add_theme_stylebox_override("hover", hover_style.duplicate())
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
		btn.add_theme_color_override("font_hover_color", Color(0.95, 0.97, 1.0))

	# 豎ｺ螳壹・繧ｿ繝ｳ
	var accent := StyleBoxFlat.new()
	accent.bg_color = Color(0.15, 0.35, 0.65)
	accent.border_color = Color(0.3, 0.55, 0.9)
	accent.set_border_width_all(2)
	accent.set_corner_radius_all(12)
	accent.content_margin_left = 20.0
	accent.content_margin_right = 20.0
	accent.content_margin_top = 10.0
	accent.content_margin_bottom = 10.0

	var accent_hover := accent.duplicate()
	accent_hover.bg_color = Color(0.2, 0.42, 0.75)

	_back_btn.add_theme_stylebox_override("normal", accent)
	_back_btn.add_theme_stylebox_override("hover", accent_hover)
	_back_btn.add_theme_color_override("font_color", Color(1, 1, 1))

func _get_all_buttons(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		buttons.append_array(_get_all_buttons(child))
	return buttons

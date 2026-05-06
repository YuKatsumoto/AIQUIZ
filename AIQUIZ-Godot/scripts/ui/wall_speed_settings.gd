extends Control

## 壁速度設定画面
## 3D SubViewport で実際のプレイ画面に近いプレビューを表示し、
## スライダーで壁の速度を調整できる。

# --- Preview 3D nodes ---
var _sub_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_floor: MeshInstance3D
var _preview_wall: Node3D
var _preview_scroll_z: float = 0.0

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

func _ready() -> void:
	_wall_scene = preload("res://scenes/quiz_wall.tscn")
	
	var game_state := QuizManager.game_state
	# 現在の速度設定を読み取り
	if game_state.tuning.wall_speed_override > 0:
		_preview_speed = game_state.tuning.wall_speed_override
	else:
		# 「自動」モードの場合、デフォルト速度を使用
		_preview_speed = 28.0 / (4.0 + 1.5)  # ≈ 5.09
	
	_build_ui()
	_build_3d_preview()
	_update_speed_display()

func _process(dt: float) -> void:
	# 3Dプレビューのアニメーション（壁がプレイヤーに向かって移動）
	_preview_scroll_z += _preview_speed * dt
	
	# 壁の位置を更新
	if _preview_wall and is_instance_valid(_preview_wall):
		var wall_z: float = WALL_START_Z - fmod(_preview_scroll_z, WALL_SPACING)
		_preview_wall.position.z = -wall_z

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
	_speed_slider.min_value = 2.0
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
	_preview_camera.position = Vector3(2.5, 3.5, 2.0) # UIが右にあるので、カメラを右にずらして被写体を左に寄せる
	_preview_camera.rotation_degrees = Vector3(-12, 10, 0) # 少しだけ斜めから見るように角度もつける
	_preview_camera.fov = 65.0
	_sub_viewport.add_child(_preview_camera)
	
	# 床 (本番環境と一致するBoxMesh)
	_preview_floor = MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(24.0, 16.0, 144.0)
	_preview_floor.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.35, 0.35, 0.35)
	floor_mat.roughness = 0.8
	_preview_floor.material_override = floor_mat
	_preview_floor.position = Vector3(0, -9.2, -50)
	_sub_viewport.add_child(_preview_floor)
	
	# マグマの追加
	var GameWorldScript := preload("res://scripts/world/game_world.gd")
	var magma_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(800.0, 800.0)
	plane.subdivide_width = 200
	plane.subdivide_depth = 200
	magma_mesh.mesh = plane
	magma_mesh.position = Vector3(0, -10.0, 150.0)
	magma_mesh.custom_aabb = AABB(Vector3(-400, -10, -400), Vector3(800, 20, 800))
	
	var mmat := ShaderMaterial.new()
	mmat.shader = Shader.new()
	mmat.shader.code = GameWorldScript.MAGMA_SHADER
	
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
	
	# プレビュー用の壁を配置
	_preview_wall = _wall_scene.instantiate()
	_preview_wall.position.z = -WALL_START_Z
	_sub_viewport.add_child(_preview_wall)
	
	# 本番同様に壁の色やドアを生成させるため、ダミーのクイズデータを渡す
	var dummy_quiz := QuizItem.new()
	dummy_quiz.q = "プレビュー"
	dummy_quiz.c = ["A", "B"]
	if _preview_wall.has_method("set_quiz"):
		_preview_wall.set_quiz(dummy_quiz, 2)
	
	# プレイヤー代わりのダミーボックス（位置参照用）
	var player_dummy := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.6, 1.8, 0.6)
	player_dummy.mesh = box_mesh
	var player_mat := StandardMaterial3D.new()
	player_mat.albedo_color = Color(0.3, 0.7, 1.0)
	player_dummy.material_override = player_mat
	player_dummy.position = Vector3(0, 0.0, 0)
	_sub_viewport.add_child(player_dummy)

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
	_preview_speed = 28.0 / (4.0 + 1.5)
	_speed_slider.value = _preview_speed
	_update_speed_display()
	_update_mode_label()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

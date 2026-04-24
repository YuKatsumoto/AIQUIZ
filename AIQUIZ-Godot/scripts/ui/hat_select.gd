extends Control

## 帽子選択画面 — 3Dプレビュー付き
## SubViewport内にプレイヤーモデルと帽子を表示し、リアルタイムで切り替え

@onready var p1_hat_label: Label = $MainContainer/SelectionContainer/P1Section/P1HatRow/P1HatLabel
@onready var p2_hat_label: Label = $MainContainer/SelectionContainer/P2Section/P2HatRow/P2HatLabel
@onready var back_btn: Button = $MainContainer/BackBtn
@onready var p1_viewport: SubViewport = $MainContainer/PreviewContainer/P1PreviewPanel/P1SubViewport
@onready var p2_viewport: SubViewport = $MainContainer/PreviewContainer/P2PreviewPanel/P2SubViewport
@onready var p1_viewport_tex: TextureRect = $MainContainer/PreviewContainer/P1PreviewPanel/P1ViewportTexture
@onready var p2_viewport_tex: TextureRect = $MainContainer/PreviewContainer/P2PreviewPanel/P2ViewportTexture

var game_state: QuizGameState

var _p1_hat_id: int = 0
var _p2_hat_id: int = 0

# Preview scene nodes
var _p1_preview_player: Node3D = null
var _p2_preview_player: Node3D = null
var _p1_preview_hat: Node3D = null
var _p2_preview_hat: Node3D = null
var _p1_hat_mount: Node3D = null
var _p2_hat_mount: Node3D = null

var _preview_time: float = 0.0

func _ready() -> void:
	game_state = QuizManager.game_state
	_p1_hat_id = game_state.p1_hat
	_p2_hat_id = game_state.p2_hat
	
	_setup_preview(p1_viewport, true)
	_setup_preview(p2_viewport, false)
	
	# Set viewport textures from code (cannot be set in .tscn)
	p1_viewport_tex.texture = p1_viewport.get_texture()
	p2_viewport_tex.texture = p2_viewport.get_texture()
	
	_update_hat_labels()
	_update_preview_hats()
	_style_all_buttons()

func _process(dt: float) -> void:
	_preview_time += dt
	# Slowly rotate preview models
	if _p1_preview_player:
		_p1_preview_player.rotation.y = sin(_preview_time * 0.8) * 0.4
	if _p2_preview_player:
		_p2_preview_player.rotation.y = sin(_preview_time * 0.8 + PI) * 0.4

func _setup_preview(viewport: SubViewport, is_p1: bool) -> void:
	viewport.transparent_bg = false
	viewport.size = Vector2i(320, 400)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	# World3D
	var world := World3D.new()
	viewport.world_3d = world
	
	# Root node for the preview scene
	var scene_root := Node3D.new()
	scene_root.name = "PreviewRoot"
	viewport.add_child(scene_root)
	
	# Environment
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.37, 0.42)
	env.ambient_light_energy = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env_node.environment = env
	scene_root.add_child(env_node)
	
	# Camera — 帽子が中心に来るように上半身にフォーカス
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 2.4)
	cam.rotation.x = -0.08
	cam.fov = 35.0
	scene_root.add_child(cam)
	
	# Key Light
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-40, -30, 0)
	key_light.light_color = Color(0.95, 0.93, 0.90)
	key_light.light_energy = 1.5
	scene_root.add_child(key_light)
	
	# Fill Light
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20, 120, 0)
	fill_light.light_color = Color(0.6, 0.65, 0.8)
	fill_light.light_energy = 0.6
	scene_root.add_child(fill_light)
	
	# Floor hint (subtle disc)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.8
	disc.bottom_radius = 0.8
	disc.height = 0.01
	disc.radial_segments = 24
	floor_mesh.mesh = disc
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.15, 0.16, 0.20)
	floor_mat.roughness = 0.9
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, -1.2, 0)
	scene_root.add_child(floor_mesh)
	
	# Build a player model for the preview
	var player_root := Node3D.new()
	player_root.name = "PreviewPlayer"
	scene_root.add_child(player_root)
	
	var body_col: Color = PlayerController.P1_BODY if is_p1 else PlayerController.P2_BODY
	var head_col: Color = PlayerController.P1_HEAD if is_p1 else PlayerController.P2_HEAD
	var limb_col: Color = PlayerController.P1_LIMB if is_p1 else PlayerController.P2_LIMB
	
	# Simplified standing player for preview
	var pelvis := Node3D.new()
	pelvis.position = Vector3(0, -0.3, 0)
	player_root.add_child(pelvis)
	
	# Torso
	var torso := _preview_box(Vector3(0.38, 0.45, 0.22), body_col)
	torso.position = Vector3(0, 0.3, 0)
	pelvis.add_child(torso)
	
	# Head
	var head_pivot := Node3D.new()
	head_pivot.position = Vector3(0, 0.75, 0)
	pelvis.add_child(head_pivot)
	
	var head := _preview_box(Vector3(0.22, 0.22, 0.22), head_col)
	head.position = Vector3(0, 0.22, 0)
	head_pivot.add_child(head)
	
	# Hat mount
	var hat_mount := Node3D.new()
	hat_mount.name = "HatMount"
	hat_mount.position = Vector3(0, 0.44, 0)
	head_pivot.add_child(hat_mount)
	
	# Arms
	var l_arm := _preview_box(Vector3(0.12, 0.40, 0.14), limb_col)
	l_arm.position = Vector3(-0.52, 0.45, 0)
	pelvis.add_child(l_arm)
	
	var r_arm := _preview_box(Vector3(0.12, 0.40, 0.14), limb_col)
	r_arm.position = Vector3(0.52, 0.45, 0)
	pelvis.add_child(r_arm)
	
	# Legs
	var l_leg := _preview_box(Vector3(0.18, 0.45, 0.18), limb_col)
	l_leg.position = Vector3(-0.22, -0.225, 0)
	pelvis.add_child(l_leg)
	
	var r_leg := _preview_box(Vector3(0.18, 0.45, 0.18), limb_col)
	r_leg.position = Vector3(0.22, -0.225, 0)
	pelvis.add_child(r_leg)
	
	if is_p1:
		_p1_preview_player = player_root
		_p1_hat_mount = hat_mount
	else:
		_p2_preview_player = player_root
		_p2_hat_mount = hat_mount

func _preview_box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size * 2.0
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mat.metallic = 0.1
	mi.material_override = mat
	return mi

func _update_hat_labels() -> void:
	p1_hat_label.text = HatData.get_hat_name(_p1_hat_id)
	p2_hat_label.text = HatData.get_hat_name(_p2_hat_id)

func _update_preview_hats() -> void:
	# P1 hat
	if _p1_preview_hat and is_instance_valid(_p1_preview_hat):
		_p1_preview_hat.queue_free()
		_p1_preview_hat = null
	if _p1_hat_id != HatData.HAT_NONE and _p1_hat_mount:
		_p1_preview_hat = HatFactory.create_hat(_p1_hat_id)
		if _p1_preview_hat:
			_p1_hat_mount.add_child(_p1_preview_hat)
	
	# P2 hat
	if _p2_preview_hat and is_instance_valid(_p2_preview_hat):
		_p2_preview_hat.queue_free()
		_p2_preview_hat = null
	if _p2_hat_id != HatData.HAT_NONE and _p2_hat_mount:
		_p2_preview_hat = HatFactory.create_hat(_p2_hat_id)
		if _p2_preview_hat:
			_p2_hat_mount.add_child(_p2_preview_hat)

# --- Button handlers ---

func _on_p1_hat_left_pressed() -> void:
	_p1_hat_id = (_p1_hat_id - 1 + HatData.HAT_COUNT) % HatData.HAT_COUNT
	game_state.p1_hat = _p1_hat_id
	_update_hat_labels()
	_update_preview_hats()

func _on_p1_hat_right_pressed() -> void:
	_p1_hat_id = (_p1_hat_id + 1) % HatData.HAT_COUNT
	game_state.p1_hat = _p1_hat_id
	_update_hat_labels()
	_update_preview_hats()

func _on_p2_hat_left_pressed() -> void:
	_p2_hat_id = (_p2_hat_id - 1 + HatData.HAT_COUNT) % HatData.HAT_COUNT
	game_state.p2_hat = _p2_hat_id
	_update_hat_labels()
	_update_preview_hats()

func _on_p2_hat_right_pressed() -> void:
	_p2_hat_id = (_p2_hat_id + 1) % HatData.HAT_COUNT
	game_state.p2_hat = _p2_hat_id
	_update_hat_labels()
	_update_preview_hats()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


# --- Styling ---

func _style_all_buttons() -> void:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.14, 0.16, 0.22)
	normal_style.border_color = Color(0.28, 0.32, 0.42)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(10)
	normal_style.content_margin_left = 16.0
	normal_style.content_margin_right = 16.0
	normal_style.content_margin_top = 8.0
	normal_style.content_margin_bottom = 8.0
	
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.18, 0.20, 0.28)
	hover_style.border_color = Color(0.4, 0.5, 0.7)
	hover_style.set_border_width_all(1)
	hover_style.set_corner_radius_all(10)
	hover_style.content_margin_left = 16.0
	hover_style.content_margin_right = 16.0
	hover_style.content_margin_top = 8.0
	hover_style.content_margin_bottom = 8.0
	
	var all_buttons := _get_all_buttons(self)
	for btn: Button in all_buttons:
		btn.add_theme_stylebox_override("normal", normal_style.duplicate())
		btn.add_theme_stylebox_override("hover", hover_style.duplicate())
		btn.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
		btn.add_theme_color_override("font_hover_color", Color(0.95, 0.97, 1.0))

func _get_all_buttons(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		buttons.append_array(_get_all_buttons(child))
	return buttons

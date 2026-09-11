extends Control

## スキン＆エモート選択画面 — 3Dプレビュー付き
## 帽子選択 + エモート（ダンス）プレビュー選択を統合

@onready var p1_hat_label: Label = $MainContainer/SelectionContainer/P1Section/P1HatRow/P1HatLabel
@onready var p2_hat_label: Label = $MainContainer/SelectionContainer/P2Section/P2HatRow/P2HatLabel
@onready var p1_emote_label: Label = $MainContainer/SelectionContainer/P1Section/P1EmoteRow/P1EmoteLabel
@onready var p2_emote_label: Label = $MainContainer/SelectionContainer/P2Section/P2EmoteRow/P2EmoteLabel
@onready var p1_emote_desc: Label = $MainContainer/SelectionContainer/P1Section/P1EmoteDesc
@onready var p2_emote_desc: Label = $MainContainer/SelectionContainer/P2Section/P2EmoteDesc
@onready var back_btn: Button = $MainContainer/BackBtn
@onready var p1_viewport: SubViewport = $MainContainer/PreviewContainer/P1PreviewPanel/P1SubViewport
@onready var p2_viewport: SubViewport = $MainContainer/PreviewContainer/P2PreviewPanel/P2SubViewport
@onready var p1_viewport_tex: TextureRect = $MainContainer/PreviewContainer/P1PreviewPanel/P1ViewportTexture
@onready var p2_viewport_tex: TextureRect = $MainContainer/PreviewContainer/P2PreviewPanel/P2ViewportTexture

var game_state: QuizGameState
var _p1_hat_id: int = 0
var _p2_hat_id: int = 0
var _p1_emote_id: int = 0
var _p2_emote_id: int = 0

# Preview scene nodes
var _p1_preview_player: Node3D = null
var _p2_preview_player: Node3D = null
var _p1_preview_hat: Node3D = null
var _p2_preview_hat: Node3D = null
var _p1_hat_mount: Node3D = null
var _p2_hat_mount: Node3D = null

# Emote preview FBX rigs
var _p1_emote_rig: Dictionary = {}
var _p2_emote_rig: Dictionary = {}
var _p1_scene_root: Node3D = null
var _p2_scene_root: Node3D = null

var _preview_time: float = 0.0
var _last_p1_preview_size: Vector2i = Vector2i.ZERO
var _last_p2_preview_size: Vector2i = Vector2i.ZERO

const PREVIEW_SIZE := Vector2i(960, 1080)
const PREVIEW_SUPERSAMPLE := 2.0
const MAX_PREVIEW_EDGE := 4096

func _ready() -> void:
	game_state = QuizManager.game_state
	_p1_hat_id = game_state.p1_hat
	_p2_hat_id = game_state.p2_hat
	_p1_emote_id = game_state.p1_emote_selected
	_p2_emote_id = game_state.p2_emote_selected
	
	_setup_preview(p1_viewport, true)
	_setup_preview(p2_viewport, false)
	
	p1_viewport_tex.texture = p1_viewport.get_texture()
	p2_viewport_tex.texture = p2_viewport.get_texture()
	p1_viewport_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	p2_viewport_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	p1_viewport_tex.resized.connect(_update_preview_viewport_sizes)
	p2_viewport_tex.resized.connect(_update_preview_viewport_sizes)
	get_viewport().size_changed.connect(_update_preview_viewport_sizes)
	
	_update_labels()
	_update_preview_hats()
	
	# エモート選択UIを非表示化（帽子選択のみにする）
	p1_emote_label.get_parent().hide()
	p2_emote_label.get_parent().hide()
	p1_emote_desc.hide()
	p2_emote_desc.hide()
	
	_style_all_buttons()
	call_deferred("_update_preview_viewport_sizes")

func _process(dt: float) -> void:
	_preview_time += dt
	# Slowly rotate when no emote is playing
	if _p1_emote_id == EmoteData.EMOTE_NONE and _p1_preview_player:
		_p1_preview_player.rotation.y = sin(_preview_time * 0.8) * 0.4
	if _p2_emote_id == EmoteData.EMOTE_NONE and _p2_preview_player:
		_p2_preview_player.rotation.y = sin(_preview_time * 0.8 + PI) * 0.4

func _setup_preview(viewport: SubViewport, is_p1: bool) -> void:
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_apply_ultra_preview_quality(viewport, PREVIEW_SIZE)
	
	var world := World3D.new()
	viewport.world_3d = world
	
	var scene_root := Node3D.new()
	scene_root.name = "PreviewRoot"
	viewport.add_child(scene_root)
	if is_p1:
		_p1_scene_root = scene_root
	else:
		_p2_scene_root = scene_root
	
	# Environment
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.37, 0.42)
	env.ambient_light_energy = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	GraphicsQuality.apply_environment(env, GameManager.graphics_quality)
	env_node.environment = env
	scene_root.add_child(env_node)
	
	# Camera — upper body view (hat visible)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.35, 2.6)
	cam.rotation.x = -0.1
	cam.fov = 35.0
	scene_root.add_child(cam)
	
	# Key Light
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-40, -30, 0)
	key_light.light_color = Color(0.95, 0.93, 0.90)
	key_light.light_energy = 1.5
	key_light.shadow_enabled = GraphicsQuality.preview_shadow_enabled(GameManager.graphics_quality)
	scene_root.add_child(key_light)
	
	# Fill Light
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20, 120, 0)
	fill_light.light_color = Color(0.6, 0.65, 0.8)
	fill_light.light_energy = 0.6
	scene_root.add_child(fill_light)
	
	# Floor disc
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.2
	disc.bottom_radius = 1.2
	disc.height = 0.01
	disc.radial_segments = 32
	floor_mesh.mesh = disc
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.15, 0.16, 0.20)
	floor_mat.roughness = 0.9
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, -1.2, 0)
	scene_root.add_child(floor_mesh)
	
	# Player model
	var player_root := Node3D.new()
	player_root.name = "PreviewPlayer"
	scene_root.add_child(player_root)
	
	var body_col: Color = PlayerController.P1_BODY if is_p1 else PlayerController.P2_BODY
	var head_col: Color = PlayerController.P1_HEAD if is_p1 else PlayerController.P2_HEAD
	var limb_col: Color = PlayerController.P1_LIMB if is_p1 else PlayerController.P2_LIMB
	
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

func _apply_ultra_preview_quality(viewport: SubViewport, viewport_size: Vector2i) -> void:
	viewport.size = viewport_size
	GraphicsQuality.apply_character_preview(viewport, GameManager.graphics_quality)

func _update_preview_viewport_sizes() -> void:
	if not p1_viewport or not p2_viewport:
		return
	var p1_size := _preview_viewport_size_for(p1_viewport_tex, PREVIEW_SIZE)
	var p2_size := _preview_viewport_size_for(p2_viewport_tex, PREVIEW_SIZE)
	if p1_size != _last_p1_preview_size:
		p1_viewport.size = p1_size
		_last_p1_preview_size = p1_size
	if p2_size != _last_p2_preview_size:
		p2_viewport.size = p2_size
		_last_p2_preview_size = p2_size

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

func _update_labels() -> void:
	p1_hat_label.text = HatData.get_hat_name(_p1_hat_id)
	p2_hat_label.text = HatData.get_hat_name(_p2_hat_id)
	p1_emote_label.text = EmoteData.get_emote_name(_p1_emote_id)
	p2_emote_label.text = EmoteData.get_emote_name(_p2_emote_id)
	p1_emote_desc.text = EmoteData.get_emote_desc(_p1_emote_id)
	p2_emote_desc.text = EmoteData.get_emote_desc(_p2_emote_id)

func _update_preview_hats() -> void:
	if _p1_preview_hat and is_instance_valid(_p1_preview_hat):
		_p1_preview_hat.queue_free()
		_p1_preview_hat = null
	if _p1_hat_id != HatData.HAT_NONE and _p1_hat_mount:
		_p1_preview_hat = HatFactory.create_hat(_p1_hat_id)
		if _p1_preview_hat:
			_p1_hat_mount.add_child(_p1_preview_hat)
	
	if _p2_preview_hat and is_instance_valid(_p2_preview_hat):
		_p2_preview_hat.queue_free()
		_p2_preview_hat = null
	if _p2_hat_id != HatData.HAT_NONE and _p2_hat_mount:
		_p2_preview_hat = HatFactory.create_hat(_p2_hat_id)
		if _p2_preview_hat:
			_p2_hat_mount.add_child(_p2_preview_hat)

func _update_emote_preview(is_p1: bool) -> void:
	var emote_id: int = _p1_emote_id if is_p1 else _p2_emote_id
	var scene_root: Node3D = _p1_scene_root if is_p1 else _p2_scene_root
	var player_root: Node3D = _p1_preview_player if is_p1 else _p2_preview_player
	var old_rig: Dictionary = _p1_emote_rig if is_p1 else _p2_emote_rig
	
	# Cleanup old emote rig
	if old_rig.has("node") and is_instance_valid(old_rig["node"]):
		old_rig["node"].queue_free()
	if is_p1:
		_p1_emote_rig = {}
	else:
		_p2_emote_rig = {}
	
	if emote_id == EmoteData.EMOTE_NONE or not scene_root:
		if player_root:
			player_root.rotation.y = 0.0
		return
	
	# Load emote FBX for preview
	var fbx_path: String = EmoteData.get_emote_fbx(emote_id)
	if fbx_path.is_empty() or not ResourceLoader.exists(fbx_path):
		return
	
	var scene = load(fbx_path) as PackedScene
	if not scene:
		return
	
	var rig_name := "EmotePreview_P%d" % (1 if is_p1 else 2)
	var node = scene.instantiate()
	node.name = rig_name
	# Hide the FBX meshes — we only use bones for reference
	scene_root.add_child(node)
	
	for child in node.find_children("*", "MeshInstance3D", true, false):
		child.hide()
	
	# Find AnimationPlayer and play
	var ap: AnimationPlayer = null
	for child in node.find_children("*", "AnimationPlayer", true, false):
		ap = child as AnimationPlayer
		break
	
	if ap:
		# Find best animation (prefer mixamo_com)
		var anim_name := ""
		var max_tracks := -1
		for lib_name in ap.get_animation_library_list():
			var lib = ap.get_animation_library(lib_name)
			for a_name in lib.get_animation_list():
				var full: String = ("%s/%s" % [lib_name, a_name]) if not String(lib_name).is_empty() else String(a_name)
				var anim = lib.get_animation(a_name)
				var tc = anim.get_track_count()
				if "mixamo_com" in a_name:
					anim_name = full
					max_tracks = 9999
				elif tc > max_tracks:
					max_tracks = tc
					if anim_name == "" or not ("mixamo_com" in anim_name):
						anim_name = full
		if anim_name != "":
			ap.play(anim_name)
	
	var rig_data := {"node": node, "anim_player": ap}
	if is_p1:
		_p1_emote_rig = rig_data
		# Face the character toward camera
		if _p1_preview_player:
			_p1_preview_player.rotation.y = 0.0
	else:
		_p2_emote_rig = rig_data
		if _p2_preview_player:
			_p2_preview_player.rotation.y = 0.0

# --- Hat button handlers ---
func _on_p1_hat_left_pressed() -> void:
	_p1_hat_id = (_p1_hat_id - 1 + HatData.HAT_COUNT) % HatData.HAT_COUNT
	game_state.p1_hat = _p1_hat_id
	_update_labels()
	_update_preview_hats()

func _on_p1_hat_right_pressed() -> void:
	_p1_hat_id = (_p1_hat_id + 1) % HatData.HAT_COUNT
	game_state.p1_hat = _p1_hat_id
	_update_labels()
	_update_preview_hats()

func _on_p2_hat_left_pressed() -> void:
	_p2_hat_id = (_p2_hat_id - 1 + HatData.HAT_COUNT) % HatData.HAT_COUNT
	game_state.p2_hat = _p2_hat_id
	_update_labels()
	_update_preview_hats()

func _on_p2_hat_right_pressed() -> void:
	_p2_hat_id = (_p2_hat_id + 1) % HatData.HAT_COUNT
	game_state.p2_hat = _p2_hat_id
	_update_labels()
	_update_preview_hats()

# --- Emote button handlers ---
func _on_p1_emote_left_pressed() -> void:
	_p1_emote_id = (_p1_emote_id - 1 + EmoteData.EMOTE_COUNT) % EmoteData.EMOTE_COUNT
	game_state.p1_emote_selected = _p1_emote_id
	_update_labels()
	_update_emote_preview(true)

func _on_p1_emote_right_pressed() -> void:
	_p1_emote_id = (_p1_emote_id + 1) % EmoteData.EMOTE_COUNT
	game_state.p1_emote_selected = _p1_emote_id
	_update_labels()
	_update_emote_preview(true)

func _on_p2_emote_left_pressed() -> void:
	_p2_emote_id = (_p2_emote_id - 1 + EmoteData.EMOTE_COUNT) % EmoteData.EMOTE_COUNT
	game_state.p2_emote_selected = _p2_emote_id
	_update_labels()
	_update_emote_preview(false)

func _on_p2_emote_right_pressed() -> void:
	_p2_emote_id = (_p2_emote_id + 1) % EmoteData.EMOTE_COUNT
	game_state.p2_emote_selected = _p2_emote_id
	_update_labels()
	_update_emote_preview(false)

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

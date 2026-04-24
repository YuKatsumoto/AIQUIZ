extends Node3D

## 3Dゲームワールド管理
## Python版 renderer.py の _draw_world + main_3d.py の入力処理に相当

@onready var camera_controller: Node3D = $CameraController
@onready var floor_mesh: MeshInstance3D = $Floor
@onready var player_node: Node3D = $Player
@onready var wall_container: Node3D = $WallContainer
@onready var particle_spawner: Node3D = $ParticleSpawner
@onready var environment_node: WorldEnvironment = $WorldEnvironment
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D

var game_state: QuizGameState
var quiz_wall_scene: PackedScene

# Track previous flash values for particle spawning
var _prev_correct_flash: float = 0.0
var _prev_wrong_flash: float = 0.0
var _prev_go_timer: float = 0.0
var _prev_p2_go_timer: float = 0.0
var _active_walls: Array[Node3D] = []
var _flyover_walls: Array[Node3D] = []
var _flyover_active: bool = false
var _hats_applied: bool = false
const MAX_VISIBLE_WALLS := 4
const BG_COLOR := Color(0.82, 0.85, 0.90)
const FLOOR_COLOR := Color(0.35, 0.35, 0.35)

func _ready() -> void:
	game_state = QuizManager.game_state
	quiz_wall_scene = preload("res://scenes/quiz_wall.tscn")

	# Listen for game state signals
	game_state.state_changed.connect(_on_state_changed)
	game_state.quiz_loaded.connect(_on_quiz_loaded)
	game_state.correct_answer.connect(_on_correct)
	game_state.wrong_answer.connect(_on_wrong)

	# Setup environment
	_setup_environment()
	_setup_lighting()
	_setup_magma()

const MAGMA_SHADER = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert;

// --- Uniforms ---
uniform vec3 deep_color : source_color = vec3(0.15, 0.02, 0.0);
uniform vec3 mid_color : source_color = vec3(0.85, 0.18, 0.0);
uniform vec3 hot_color : source_color = vec3(1.0, 0.65, 0.0);
uniform vec3 white_hot : source_color = vec3(1.0, 0.95, 0.6);
uniform float flow_speed : hint_range(0.0, 2.0) = 0.35;
uniform float voronoi_scale : hint_range(1.0, 40.0) = 8.0;
uniform float emission_intensity : hint_range(0.0, 8.0) = 1.5;
uniform float wave_height : hint_range(0.0, 3.0) = 1.2;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D noise_tex;
uniform sampler2D noise_tex2;

varying float v_height;
varying float v_flow;

// --- Voronoi ---
vec2 random2D(vec2 p) {
	return fract(sin(vec2(
		dot(p, vec2(127.1, 311.7)),
		dot(p, vec2(269.5, 183.3))
	)) * 43758.5453);
}

float voronoi(vec2 pos, float t) {
	vec2 p = floor(pos);
	vec2 f = fract(pos);
	float res = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 b = vec2(float(i), float(j));
			vec2 pnt = random2D(p + b);
			pnt = 0.5 + 0.5 * sin(t + 6.2831 * pnt);
			vec2 r = vec2(b) - f + pnt;
			float d = dot(r, r);
			res += exp(-18.0 * d);
		}
	}
	return clamp(-(1.0 / 18.0) * log(max(res, 1e-6)), 0.0, 1.0);
}

void vertex() {
	float t = TIME * flow_speed;

	// Sample noise for organic waves
	vec2 uv1 = VERTEX.xz * 0.008 + vec2(t * 0.3, t * 0.2);
	vec2 uv2 = VERTEX.xz * 0.015 + vec2(-t * 0.15, t * 0.25);
	float n1 = texture(noise_tex, uv1).r;
	float n2 = texture(noise_tex2, uv2).r;

	// Large slow waves
	float wave1 = sin(VERTEX.x * 0.25 + TIME * 0.8) * cos(VERTEX.z * 0.2 + TIME * 0.6) * 0.6;
	float wave2 = sin(VERTEX.x * 0.08 - TIME * 0.5) * sin(VERTEX.z * 0.12 + TIME * 0.3) * 0.8;

	// Noise-driven displacement
	float noise_disp = (n1 * 0.7 + n2 * 0.3) * wave_height;

	// Bubbling hotspots
	float bx = sin(VERTEX.x * 1.2 + TIME * 2.5);
	float bz = cos(VERTEX.z * 1.2 - TIME * 2.0);
	float bubbles = pow(abs(bx * bz), 8.0) * 0.6;

	float total = wave1 + wave2 + noise_disp + bubbles;
	VERTEX.y += total;
	v_height = total;
	v_flow = n1 * 0.6 + n2 * 0.4;
}

void fragment() {
	float t = TIME * flow_speed;

	// Voronoi for crack patterns
	vec2 uv_v = UV * voronoi_scale + vec2(t * 0.4, -t * 0.3);
	float v1 = voronoi(uv_v, TIME * 2.0);
	float v2 = voronoi(uv_v * 0.5 + vec2(5.0, 3.0), TIME * 1.5);
	float cracks = v1 * 0.7 + v2 * 0.3;

	// Flow noise for organic movement
	vec2 fuv1 = UV * 3.0 + vec2(t * 0.6, t * 0.4);
	vec2 fuv2 = UV * 5.0 + vec2(-t * 0.3, t * 0.5);
	float fn1 = texture(noise_tex, fuv1).r;
	float fn2 = texture(noise_tex2, fuv2).r;
	float flow = fn1 * 0.6 + fn2 * 0.4;

	// Combine: cracks reveal hot interior, surface is cooler crust
	float heat = clamp(cracks * 1.2 + flow * 0.3 + v_height * 0.15, 0.0, 1.0);

	// 4-stop color gradient: deep -> mid -> hot -> white-hot
	vec3 col;
	if (heat < 0.3) {
		col = mix(deep_color, mid_color, heat / 0.3);
	} else if (heat < 0.6) {
		col = mix(mid_color, hot_color, (heat - 0.3) / 0.3);
	} else {
		col = mix(hot_color, white_hot, clamp((heat - 0.6) / 0.4, 0.0, 1.0));
	}

	// Pulsing glow on hotspots
	float pulse = 1.0 + sin(TIME * 3.0) * 0.08;

	ALBEDO = col;
	EMISSION = col * emission_intensity * heat * pulse;
	ROUGHNESS = roughness_val + (1.0 - heat) * 0.4;
	METALLIC = 0.0;
}
"""

func _setup_magma() -> void:
	var magma_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(800.0, 800.0)
	plane.subdivide_width = 200
	plane.subdivide_depth = 200
	magma_mesh.mesh = plane
	magma_mesh.position = Vector3(0, -10.0, 150.0)
	magma_mesh.custom_aabb = AABB(Vector3(-400, -10, -400), Vector3(800, 20, 800))

	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = MAGMA_SHADER

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
	mat.set_shader_parameter("noise_tex", noise1)

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
	mat.set_shader_parameter("noise_tex2", noise2)

	magma_mesh.material_override = mat
	add_child(magma_mesh)

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG_COLOR
	env.ambient_light_color = Color(0.30, 0.32, 0.35)
	env.ambient_light_energy = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

	# Fog
	env.fog_enabled = true
	env.fog_light_color = BG_COLOR
	env.fog_density = 0.012
	env.fog_aerial_perspective = 0.5

	# Tonemap
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0

	# Glow (for magma emission bloom)
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.8
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.8
	env.set_glow_level(0, true)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, false)

	environment_node.environment = env

func _setup_lighting() -> void:
	directional_light.rotation_degrees = Vector3(-50, -20, 0)
	directional_light.light_color = Color(0.90, 0.92, 0.95)
	directional_light.light_energy = 1.2
	directional_light.shadow_enabled = true

func _process(dt: float) -> void:
	if not game_state:
		return

	# Gather input
	var axis_p1 := Vector2.ZERO
	var axis_p2 := Vector2.ZERO
	var jump_p1 := false
	var jump_p2 := false
	var emote_p1 := 0
	var emote_p2 := 0

	if game_state.game_state == Constants.STATE_PLAYING:
		if Input.is_key_pressed(KEY_1): emote_p1 = 1
		elif Input.is_key_pressed(KEY_2): emote_p1 = 2
		elif Input.is_key_pressed(KEY_3): emote_p1 = 3
		
		# Player 1: W/A/S/D
		if Input.is_key_pressed(KEY_D): axis_p1.x -= 1.0
		if Input.is_key_pressed(KEY_A): axis_p1.x += 1.0
		if Input.is_key_pressed(KEY_W): axis_p1.y += 1.0
		if Input.is_key_pressed(KEY_S): axis_p1.y -= 1.0
		jump_p1 = Input.is_key_pressed(KEY_SPACE)

		if game_state.num_players >= 2:
			if Input.is_key_pressed(KEY_8) or Input.is_key_pressed(KEY_KP_7): emote_p2 = 1
			elif Input.is_key_pressed(KEY_9) or Input.is_key_pressed(KEY_KP_8): emote_p2 = 2
			elif Input.is_key_pressed(KEY_0) or Input.is_key_pressed(KEY_KP_9): emote_p2 = 3
			
			# 2P: Arrow keys for P2
			if Input.is_key_pressed(KEY_RIGHT): axis_p2.x -= 1.0
			if Input.is_key_pressed(KEY_LEFT): axis_p2.x += 1.0
			if Input.is_key_pressed(KEY_UP): axis_p2.y += 1.0
			if Input.is_key_pressed(KEY_DOWN): axis_p2.y -= 1.0
			jump_p2 = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_KP_0)
		else:
			# 1P: Arrow keys also work for P1
			if Input.is_key_pressed(KEY_RIGHT): axis_p1.x -= 1.0
			if Input.is_key_pressed(KEY_LEFT): axis_p1.x += 1.0
			if Input.is_key_pressed(KEY_UP): axis_p1.y += 1.0
			if Input.is_key_pressed(KEY_DOWN): axis_p1.y -= 1.0

		axis_p1 = axis_p1.normalized()
		if game_state.num_players >= 2:
			axis_p2 = axis_p2.normalized()

	# Mouse look (1P only)
	if game_state.game_state == Constants.STATE_PLAYING and game_state.num_players == 1:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Update game state
	game_state.update(dt, axis_p1, axis_p2, jump_p1, jump_p2, emote_p1, emote_p2)

	# Update visuals
	_update_floor()
	_update_flyover()
	_update_player()
	_update_walls()
	_update_camera(dt)
	_check_particles()

	# Handle ESC / R key
	if game_state.game_state == Constants.STATE_PLAYING:
		if Input.is_key_pressed(KEY_ESCAPE) :
			game_state.reset_to_menu()
			get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	if game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
		if Input.is_key_pressed(KEY_R) :
			game_state.reset_to_menu()
			get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if game_state and game_state.game_state == Constants.STATE_PLAYING \
				and game_state.num_players == 1:
			game_state.camera_yaw -= event.relative.x * 0.002
			game_state.camera_pitch -= event.relative.y * 0.002
			game_state.camera_pitch = clampf(game_state.camera_pitch,
				-PI / 2.5, PI / 2.5)
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		if event.is_pressed() and not event.is_echo():
			if game_state and game_state.game_state == Constants.STATE_WAITING_START:
				if game_state.has_method("trigger_start"):
					game_state.trigger_start()

func _update_floor() -> void:
	if game_state.game_state == Constants.STATE_FLYOVER:
		# フライオーバー中: 最後の壁まで床を延長
		# 後端を通常時と同じ -4.5 に揃えて、遷移時に崖の位置がずれないようにする
		var t := game_state.tuning
		var last_wall_z: float = t.wall_start_z + (game_state.flyover_total_walls - 1) * t.wall_spacing
		var floor_front: float = last_wall_z + 30.0  # 最後の壁の少し先まで
		var floor_back: float = -4.5  # 通常時の床の後端と一致
		var floor_length: float = floor_front - floor_back
		var floor_center_z: float = (floor_front + floor_back) / 2.0
		var box_mesh: BoxMesh = floor_mesh.mesh as BoxMesh
		if box_mesh:
			box_mesh.size = Vector3(24.0, 16.0, floor_length)
		floor_mesh.position = Vector3(0, -9.2, floor_center_z)
	else:
		# 通常時: 固定サイズ 144 units
		var box_mesh: BoxMesh = floor_mesh.mesh as BoxMesh
		if box_mesh:
			box_mesh.size = Vector3(24.0, 16.0, 144.0)
		floor_mesh.position = Vector3(0, -9.2, 67.5)

func _update_player() -> void:
	if game_state.game_state == Constants.STATE_MENU:
		player_node.visible = false
		_hats_applied = false
		return

	player_node.visible = true
	var pc: PlayerController = player_node as PlayerController
	if pc:
		pc.update_from_state(game_state)
		
		# Apply hats when game starts (2P mode)
		if not _hats_applied and game_state.num_players >= 2:
			if pc.p2_container != null:
				pc.set_hat(1, game_state.p1_hat)
				pc.set_hat(2, game_state.p2_hat)
				_hats_applied = true

func _update_flyover() -> void:
	if game_state.game_state == Constants.STATE_FLYOVER:
		if not _flyover_active:
			# フライオーバー開始: 全壁を生成
			_flyover_active = true
			_clear_flyover_walls()
			var t := game_state.tuning
			for i: int in range(game_state.flyover_total_walls):
				var wz: float = t.wall_start_z + i * t.wall_spacing
				var wall_node: Node3D = quiz_wall_scene.instantiate()
				wall_node.set_meta("wall_index", i)
				wall_node.position = Vector3(0, 0, wz)
				wall_container.add_child(wall_node)
				_flyover_walls.append(wall_node)
				# クイズ内容を壁に設定
				if i < game_state.quiz_list.size() and wall_node.has_method("set_quiz"):
					wall_node.set_quiz(game_state.quiz_list[i], game_state.num_choices)
	elif _flyover_active:
		# フライオーバー終了: 壁をクリーンアップ
		_flyover_active = false
		_clear_flyover_walls()

func _clear_flyover_walls() -> void:
	for wall: Node3D in _flyover_walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_flyover_walls.clear()

func _update_walls() -> void:
	if game_state.game_state in [Constants.STATE_MENU, Constants.STATE_FLYOVER]:
		for wall: Node3D in _active_walls:
			wall.queue_free()
		_active_walls.clear()
		return

	var t := game_state.tuning
	var needed_indices: Array[int] = []
	for i: int in range(MAX_VISIBLE_WALLS):
		var idx: int = game_state.current_wall_index + i
		var wz: float = t.wall_start_z + idx * t.wall_spacing
		if wz > game_state.player_z - 2.0:
			needed_indices.append(idx)

	# Remove walls no longer needed
	var to_remove: Array[Node3D] = []
	for wall: Node3D in _active_walls:
		if not wall.has_meta("wall_index") or wall.get_meta("wall_index") not in needed_indices:
			to_remove.append(wall)
	for wall: Node3D in to_remove:
		_active_walls.erase(wall)
		wall.queue_free()

	# Add walls that are missing
	var existing_indices: Array[int] = []
	for wall: Node3D in _active_walls:
		if wall.has_meta("wall_index"):
			existing_indices.append(wall.get_meta("wall_index") as int)

	for idx: int in needed_indices:
		if idx not in existing_indices:
			var wz: float = t.wall_start_z + idx * t.wall_spacing
			var wall_node: Node3D = quiz_wall_scene.instantiate()
			wall_node.set_meta("wall_index", idx)
			wall_node.position = Vector3(0, 0, wz - game_state.world_scroll_z)
			wall_container.add_child(wall_node)
			_active_walls.append(wall_node)
			
		# Also MUST update positions of existing walls because they slide!
	for wall: Node3D in _active_walls:
		if wall.has_meta("wall_index"):
			var idx: int = wall.get_meta("wall_index") as int
			var wz: float = t.wall_start_z + idx * t.wall_spacing
			wall.position.z = wz - game_state.world_scroll_z

			# Setup door labels if this is the current wall
			if idx == game_state.current_wall_index and game_state.current_quiz:
				_update_wall_labels(wall)

func _update_wall_labels(wall_node: Node3D) -> void:
	if wall_node.has_method("set_quiz"):
		wall_node.set_quiz(game_state.current_quiz, game_state.num_choices)

func _update_camera(dt: float) -> void:
	if camera_controller.has_method("update_camera"):
		camera_controller.update_camera(game_state, dt)

func _check_particles() -> void:
	# Correct particle spawn
	if game_state.correct_flash > 0.8 and _prev_correct_flash <= 0.8:
		if particle_spawner.has_method("spawn_correct"):
			particle_spawner.spawn_correct(
				Vector3(game_state.player_x, game_state.player_y, game_state.player_local_z))
	_prev_correct_flash = game_state.correct_flash

	# Explosion particle spawn (P1)
	if game_state.game_over_timer >= 2.0 and _prev_go_timer < 2.0:
		if particle_spawner.has_method("spawn_explosion"):
			particle_spawner.spawn_explosion(
				Vector3(game_state.player_x, game_state.player_y, game_state.player_local_z))
	_prev_go_timer = game_state.game_over_timer
	
	# Explosion particle spawn (P2)
	if game_state.player2_game_over_timer >= 2.0 and _prev_p2_go_timer < 2.0:
		if particle_spawner.has_method("spawn_explosion"):
			particle_spawner.spawn_explosion(
				Vector3(game_state.player2_x, game_state.player2_y, game_state.player2_local_z))
	_prev_p2_go_timer = game_state.player2_game_over_timer

func _on_state_changed(new_state: String) -> void:
	pass

func _on_quiz_loaded(quiz: QuizItem) -> void:
	# Update labels on the current wall
	for wall: Node3D in _active_walls:
		if wall.has_meta("wall_index") and wall.get_meta("wall_index") == game_state.current_wall_index:
			_update_wall_labels(wall)

func _on_correct() -> void:
	if game_state.current_quiz:
		var answer_idx: int = game_state.current_quiz.a
		for wall: Node3D in _active_walls:
			if wall.has_meta("wall_index") and wall.get_meta("wall_index") == game_state.current_wall_index:
				if wall.has_method("break_door"):
					wall.break_door(answer_idx)
	# Audio handled by AudioManager

func _on_wrong(_msg: String) -> void:
	pass  # Audio handled by AudioManager

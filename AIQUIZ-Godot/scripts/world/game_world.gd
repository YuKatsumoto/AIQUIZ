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
var _net_state: NetGameState = null
var quiz_wall_scene: PackedScene

# Track previous flash values for particle spawning
var _prev_correct_flash: float = 0.0
var _prev_wrong_flash: float = 0.0
var _prev_go_timer: float = 0.0
var _fireworks_launched: bool = false
var _prev_p2_go_timer: float = 0.0
var _active_walls: Array[Node3D] = []
var _flyover_walls: Array[Node3D] = []
var _flyover_active: bool = false
var _hats_applied: bool = false
# ── プリロード中の3D構築アニメーション ──
var _pw_walls: Array[Node3D] = []        # 完成壁
var _pw_left: Array[Node3D] = []          # 左半分スライド壁
var _pw_right: Array[Node3D] = []         # 右半分スライド壁
var _pw_anims: Array[Dictionary] = []     # アニメ状態
var _pw_count: int = 0                    # 生成済み壁数
var _pw_merge_started: Array[bool] = []   # 各壁のマージ開始フラグ
var _pw_merge_timer: float = 0.0          # 壁間のディレイタイマー
var _goal_line_node: Node3D = null
const MAX_VISIBLE_WALLS := 4
const BG_COLOR := Color(0.82, 0.85, 0.90)
const FLOOR_COLOR := Color(0.35, 0.35, 0.35)

var pause_menu: CanvasLayer = null

func _ready() -> void:
	game_state = QuizManager.game_state
	quiz_wall_scene = preload("res://scenes/quiz_wall.tscn")

	# Listen for game state signals
	game_state.state_changed.connect(_on_state_changed)
	game_state.quiz_loaded.connect(_on_quiz_loaded)
	game_state.correct_answer.connect(_on_correct)
	game_state.wrong_answer.connect(_on_wrong)

	# Setup network sync layer
	_net_state = NetGameState.new()
	add_child(_net_state)
	_net_state.setup(game_state)

	# Setup environment
	_setup_environment()
	_setup_lighting()
	_setup_magma()

	# Pause menu setup
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_menu()

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
	if not game_state or get_tree().paused:
		return

	# --- Online mode: client skips game logic, only sends input ---
	var _is_online: bool = _net_state and _net_state.is_online
	var _is_client: bool = _is_online and not NetworkManager.is_host

	# Gather input
	var axis_p1 := Vector2.ZERO
	var axis_p2 := Vector2.ZERO
	var jump_p1 := false
	var jump_p2 := false
	var emote_p1 := 0
	var emote_p2 := 0

	if game_state.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE, Constants.STATE_WAITING_START, Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN]:
		# --- ローカル入力収集 (P1 or クライアントの自分) ---
		# P1 エモート: キー1,2,3 → スロットからエモートIDを取得
		if Input.is_key_pressed(KEY_1) and game_state.p1_emote_slots.size() > 0: emote_p1 = game_state.p1_emote_slots[0]
		elif Input.is_key_pressed(KEY_2) and game_state.p1_emote_slots.size() > 1: emote_p1 = game_state.p1_emote_slots[1]
		elif Input.is_key_pressed(KEY_3) and game_state.p1_emote_slots.size() > 2: emote_p1 = game_state.p1_emote_slots[2]
		
		# Player 1: W/A/S/D
		if Input.is_key_pressed(KEY_D): axis_p1.x -= 1.0
		if Input.is_key_pressed(KEY_A): axis_p1.x += 1.0
		if Input.is_key_pressed(KEY_W): axis_p1.y += 1.0
		if Input.is_key_pressed(KEY_S): axis_p1.y -= 1.0
		jump_p1 = Input.is_key_pressed(KEY_SPACE)

		# --- Online client: 自分の入力をホストに送信 ---
		if _is_client:
			axis_p1 = axis_p1.normalized()
			_net_state.send_local_input(axis_p1, jump_p1, emote_p1)
		# --- Online host: P2の入力はネットワーク経由 ---
		elif _is_online and NetworkManager.is_host:
			axis_p2 = _net_state.get_remote_axis()
			jump_p2 = _net_state.get_remote_jump()
			emote_p2 = _net_state.get_remote_emote()
		# --- ローカル2P ---
		elif game_state.num_players >= 2:
			# P2 エモート: キー8,9,0 → スロットからエモートIDを取得
			if (Input.is_key_pressed(KEY_8) or Input.is_key_pressed(KEY_KP_7)) and game_state.p2_emote_slots.size() > 0: emote_p2 = game_state.p2_emote_slots[0]
			elif (Input.is_key_pressed(KEY_9) or Input.is_key_pressed(KEY_KP_8)) and game_state.p2_emote_slots.size() > 1: emote_p2 = game_state.p2_emote_slots[1]
			elif (Input.is_key_pressed(KEY_0) or Input.is_key_pressed(KEY_KP_9)) and game_state.p2_emote_slots.size() > 2: emote_p2 = game_state.p2_emote_slots[2]
			
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

	# Mouse look (1P only, not online)
	if game_state.game_state == Constants.STATE_PLAYING and game_state.num_players == 1 and not _is_online:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Update game state (host or offline only — client receives snapshots)
	if not _is_client:
		game_state.update(dt, axis_p1, axis_p2, jump_p1, jump_p2, emote_p1, emote_p2)

	# Network sync (snapshot send for host)
	if _net_state:
		_net_state.process_network(dt)

	# Update visuals
	_update_floor()
	_update_flyover()
	_update_player()
	_update_walls()
	_update_goal_line()
	_update_preview_walls(dt)
	_update_camera(dt)
	_check_particles()

	# Handle R key for restart (ESC is handled in _unhandled_input)
	if game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
		if Input.is_key_pressed(KEY_R) :
			game_state.reset_to_menu()
			get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed() and not event.is_echo():
		if game_state and game_state.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]:
			_toggle_pause()
			
	if event is InputEventMouseMotion:
		if game_state and game_state.game_state == Constants.STATE_PLAYING \
				and game_state.num_players == 1 and not get_tree().paused:
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
	if game_state.game_state in [Constants.STATE_FLYOVER, Constants.STATE_PRELOADING, Constants.STATE_WAITING_START]:
		# フライオーバー / プリロード中: 最後の壁(orゴールライン)まで床を延長
		var t := game_state.tuning
		var wall_count: int = game_state.target_count if game_state.target_count > 0 else 10
		if game_state.game_state == Constants.STATE_FLYOVER:
			wall_count = game_state.flyover_total_walls
		var last_wall_z: float = t.wall_start_z + (wall_count - 1) * t.wall_spacing
		var floor_front: float = last_wall_z + 30.0
		# 2P×10Qモード: ゴールラインまで延長
		if game_state.num_players >= 2 and game_state.mode == Constants.MODE_TEN:
			var goal_line_z: float = t.wall_start_z + game_state.target_count * t.wall_spacing + 15.0
			floor_front = maxf(floor_front, goal_line_z + 20.0)
		var floor_back: float = -4.5
		var floor_length: float = floor_front - floor_back
		var floor_center_z: float = (floor_front + floor_back) / 2.0
		var box_mesh: BoxMesh = floor_mesh.mesh as BoxMesh
		if box_mesh:
			box_mesh.size = Vector3(24.0, 16.0, floor_length)
		floor_mesh.position = Vector3(0, -9.2, floor_center_z)
	elif game_state.game_state == Constants.STATE_GOAL_RACE:
		# ゴールレース中: ゴールラインの先まで床を延長
		var floor_front: float = game_state.goal_z + 20.0 - game_state.world_scroll_z
		var floor_back: float = -4.5
		var floor_length: float = maxf(144.0, floor_front - floor_back)
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
	if game_state.game_state in [Constants.STATE_MENU, Constants.STATE_PRELOADING]:
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
			# フライオーバー開始: プレビュー壁をクリーンアップして正位置で新規生成
			_flyover_active = true
			_clear_preview_walls()
			if _flyover_walls.is_empty():
				var t := game_state.tuning
				for i: int in range(game_state.flyover_total_walls):
					var wz: float = t.wall_start_z + i * t.wall_spacing
					var wall_node: Node3D = quiz_wall_scene.instantiate()
					wall_node.set_meta("wall_index", i)
					wall_node.position = Vector3(0, 0, wz)
					wall_container.add_child(wall_node)
					_flyover_walls.append(wall_node)
					if i < game_state.quiz_list.size() and wall_node.has_method("set_quiz"):
						wall_node.set_quiz(game_state.quiz_list[i], game_state.num_choices)
			# 全壁を可視化
			for w: Node3D in _flyover_walls:
				w.visible = true
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
	# プリロード中・ゴールレース中・クリア後・メニュー・フライオーバー中は通常壁を全て非表示
	if game_state.game_state in [Constants.STATE_MENU, Constants.STATE_FLYOVER, Constants.STATE_GOAL_RACE, Constants.STATE_CLEAR, Constants.STATE_PRELOADING, Constants.STATE_WAITING_START]:
		for wall: Node3D in _active_walls:
			wall.queue_free()
		_active_walls.clear()
		return

	var t := game_state.tuning
	var needed_indices: Array[int] = []
	# Keep 1 wall behind (the one just passed through) so its wall mesh stays visible
	var start_idx := maxi(0, game_state.current_wall_index - 1)
	# 固定問数モードでは target_count 以降の壁を生成しない
	var max_wall_idx: int = -1
	if game_state.mode == Constants.MODE_TEN or game_state.mode == Constants.MODE_TUTORIAL:
		max_wall_idx = game_state.target_count - 1  # 0-indexed: 壁0〜9まで
	for i: int in range(MAX_VISIBLE_WALLS + 1):
		var idx: int = start_idx + i
		# 固定問数モードでは target_count 以降の壁をスキップ
		if max_wall_idx >= 0 and idx > max_wall_idx:
			continue
		var wz: float = t.wall_start_z + idx * t.wall_spacing
		if wz > game_state.player_z - 5.0:
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

			if wall_node.has_method("set_is_boss"):
				var is_boss: bool = (idx == game_state.target_count - 1 and game_state.mode == Constants.MODE_TEN)
				wall_node.set_is_boss(is_boss)

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

func _update_goal_line() -> void:
	# Only show goal line in 2P × 10Q mode during relevant states
	var should_show := (
		game_state.num_players >= 2
		and game_state.mode == Constants.MODE_TEN
		and game_state.game_state in [
			Constants.STATE_GOAL_RACE,
			Constants.STATE_FLYOVER,
			Constants.STATE_PLAYING,
			Constants.STATE_CLEAR,
			Constants.STATE_WAITING_START,
		]
	)

	if not should_show:
		if _goal_line_node and is_instance_valid(_goal_line_node):
			_goal_line_node.queue_free()
			_goal_line_node = null
		return

	# Calculate goal Z position
	var t := game_state.tuning
	var g_z: float
	if game_state.goal_z > 0.0:
		g_z = game_state.goal_z
	else:
		g_z = t.wall_start_z + game_state.target_count * t.wall_spacing + 15.0

	# Create goal line if not exists
	if not _goal_line_node or not is_instance_valid(_goal_line_node):
		_goal_line_node = Node3D.new()
		_goal_line_node.name = "GoalLine"
		add_child(_goal_line_node)

		# --- Goal gate: two pillars + crossbar ---
		# 床のトップ面は Y = -9.2 + 8.0 = -1.2 なので、それに合わせて配置
		const FLOOR_TOP_Y: float = -1.2
		var pillar_color := Color(1.0, 0.85, 0.1)  # Gold
		var bar_color := Color(1.0, 0.85, 0.1)

		# Left pillar (高さ5.0、中心をFLOOR_TOP_Y + 2.5に配置)
		var left_pillar := _create_goal_box(Vector3(0.4, 5.0, 0.4), pillar_color)
		left_pillar.position = Vector3(-7.0, FLOOR_TOP_Y + 2.5, 0)
		_goal_line_node.add_child(left_pillar)

		# Right pillar
		var right_pillar := _create_goal_box(Vector3(0.4, 5.0, 0.4), pillar_color)
		right_pillar.position = Vector3(7.0, FLOOR_TOP_Y + 2.5, 0)
		_goal_line_node.add_child(right_pillar)

		# Crossbar (柱の上端に配置)
		var crossbar := _create_goal_box(Vector3(14.4, 0.4, 0.4), bar_color)
		crossbar.position = Vector3(0, FLOOR_TOP_Y + 5.0, 0)
		_goal_line_node.add_child(crossbar)

		# Ground line (checkerboard-style stripe — 床面に接着)
		for i: int in range(28):
			var stripe := _create_goal_box(Vector3(0.5, 0.05, 1.0),
				Color.WHITE if i % 2 == 0 else Color(0.15, 0.15, 0.15))
			stripe.position = Vector3(-6.75 + i * 0.5, FLOOR_TOP_Y + 0.03, 0)
			_goal_line_node.add_child(stripe)

		# "GOAL" label (クロスバーのやや下に配置)
		var goal_label := Label3D.new()
		goal_label.text = "🏁 GOAL 🏁"
		goal_label.font_size = 72
		goal_label.pixel_size = 0.012
		goal_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		goal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		goal_label.modulate = Color(1.0, 0.95, 0.3)
		goal_label.outline_modulate = Color(0.1, 0.05, 0.0, 1.0)
		goal_label.outline_size = 10
		goal_label.position = Vector3(0, FLOOR_TOP_Y + 3.8, -0.3)
		goal_label.rotation.y = PI
		var font := load("res://resources/fonts/NotoSansJP-Regular.otf")
		if font:
			goal_label.font = font
		_goal_line_node.add_child(goal_label)

	# Update position relative to world scroll
	if game_state.game_state == Constants.STATE_FLYOVER:
		_goal_line_node.position = Vector3(0, 0, g_z)
	else:
		_goal_line_node.position = Vector3(0, 0, g_z - game_state.world_scroll_z)

func _create_goal_box(box_size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	mat.metallic = 0.3
	mat.emission_enabled = true
	mat.emission = color * 0.3
	mat.emission_energy_multiplier = 0.5
	mesh_inst.material_override = mat
	return mesh_inst

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

	# Fireworks on CLEAR state (花火演出)
	if game_state.game_state == Constants.STATE_CLEAR and not _fireworks_launched:
		_fireworks_launched = true
		if particle_spawner.has_method("spawn_fireworks"):
			# ゴールライン位置から花火を打ち上げ
			var fw_z: float = game_state.goal_z - game_state.world_scroll_z if game_state.goal_z > 0 else 50.0
			particle_spawner.spawn_fireworks(Vector3(0, 0, fw_z))

func _on_state_changed(new_state: String) -> void:
	if new_state == Constants.STATE_CLEAR:
		_fireworks_launched = false
	elif new_state in [Constants.STATE_MENU, Constants.STATE_PLAYING]:
		_fireworks_launched = false
		_clear_preview_walls()
	elif new_state == Constants.STATE_WAITING_START:
		# プレビュー壁＋マージアニメーションはそのまま続行させる
		# フライオーバー壁の重複を防ぐため、ここでは何もしない
		# （FLYOVER開始時にプレビュー壁をフライオーバー壁へ移管する）
		_clear_flyover_walls()

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

func _build_pause_menu() -> void:
	pause_menu = CanvasLayer.new()
	pause_menu.layer = 100
	pause_menu.visible = false
	add_child(pause_menu)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)
	
	var title = Label.new()
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	vbox.add_child(title)
	
	# --- BGM Volume ---
	var bgm_label = Label.new()
	bgm_label.text = "BGM Volume"
	bgm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(bgm_label)
	
	var bgm_slider = HSlider.new()
	bgm_slider.min_value = 0.0
	bgm_slider.max_value = 1.0
	bgm_slider.step = 0.05
	bgm_slider.value = game_state.bgm_volume
	bgm_slider.custom_minimum_size = Vector2(400, 40)
	bgm_slider.value_changed.connect(func(val: float):
		game_state.set_bgm_volume(val)
		var bus_idx = AudioServer.get_bus_index("BGM")
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(val) if val > 0 else -80.0)
		else:
			# Fallback if no BGM bus exists
			pass
	)
	vbox.add_child(bgm_slider)
	
	# --- SFX Volume ---
	var sfx_label = Label.new()
	sfx_label.text = "SFX Volume"
	sfx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sfx_label)
	
	var sfx_slider = HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = game_state.sfx_volume
	sfx_slider.custom_minimum_size = Vector2(400, 40)
	sfx_slider.value_changed.connect(func(val: float):
		game_state.set_sfx_volume(val)
		var bus_idx = AudioServer.get_bus_index("SFX")
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(val) if val > 0 else -80.0)
		else:
			# Fallback for SFX if using AudioManager
			if AudioManager.has_method("set_volume"):
				AudioManager.set_volume(val)
	)
	vbox.add_child(sfx_slider)
	
	# --- Buttons ---
	var btn_resume = Button.new()
	btn_resume.text = "ゲームに戻る"
	btn_resume.add_theme_font_size_override("font_size", 28)
	btn_resume.custom_minimum_size = Vector2(0, 60)
	btn_resume.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn_resume.pressed.connect(func(): _toggle_pause())
	vbox.add_child(btn_resume)
	
	var btn_title = Button.new()
	btn_title.text = "タイトルに戻る"
	btn_title.add_theme_font_size_override("font_size", 28)
	btn_title.custom_minimum_size = Vector2(0, 60)
	btn_title.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn_title.pressed.connect(func():
		get_tree().paused = false
		game_state.reset_to_menu()
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	)
	vbox.add_child(btn_title)

func _toggle_pause() -> void:
	if not pause_menu:
		return
	var new_paused = !get_tree().paused
	get_tree().paused = new_paused
	pause_menu.visible = new_paused
	if new_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if game_state.num_players == 1:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ============================================================
# プリロード中の3D構築アニメーション
# 軽量シルエットが左右から爆速スライドイン → 合体＋火花エフェクト
# ============================================================

## 左右スライド用の軽量シルエットメッシュを生成
func _create_slide_silhouette(wz: float, x_pos: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.0, 5.5, 0.4)  # 壁とほぼ同サイズ
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.5, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	mi.mesh = box
	mi.position = Vector3(x_pos, 2.75, wz)
	mi.visible = false
	return mi

func _update_preview_walls(dt: float) -> void:
	if game_state.game_state not in [Constants.STATE_PRELOADING, Constants.STATE_WAITING_START]:
		return

	var t := game_state.tuning
	var quiz_count: int = game_state.quiz_list.size()

	# ── 壁+シルエットの生成（クイズ到着に同期、奥から手前へ配置）──
	# 到着N番目のクイズ → 位置 (total - 1 - N) に壁を生成
	# これにより最初のクイズが最奥、最後のクイズが最手前に出現
	var total_expected: int = maxi(game_state.target_count, quiz_count)
	while _pw_count < quiz_count:
		# 逆マッピング: 到着順 → 奥から手前の位置
		var visual_idx: int = total_expected - 1 - _pw_count
		var wz: float = t.wall_start_z + visual_idx * t.wall_spacing

		# 完成壁（合体後に表示）
		var wall_final: Node3D = quiz_wall_scene.instantiate()
		wall_final.set_meta("wall_index", visual_idx)
		wall_final.position = Vector3(0, 0, wz)
		wall_final.visible = false
		wall_container.add_child(wall_final)
		_pw_walls.append(wall_final)

		if _pw_count < game_state.quiz_list.size() and wall_final.has_method("set_quiz"):
			wall_final.set_quiz(game_state.quiz_list[_pw_count], game_state.num_choices)

		# 左右は軽量シルエット（BoxMesh）
		var sil_l := _create_slide_silhouette(wz, -25.0)
		sil_l.visible = false
		wall_container.add_child(sil_l)
		_pw_left.append(sil_l)

		var sil_r := _create_slide_silhouette(wz, 25.0)
		sil_r.visible = false
		wall_container.add_child(sil_r)
		_pw_right.append(sil_r)

		# 新しい壁のアニメーション情報 — まだ開始しない（タイマーで順次開始）
		_pw_anims.append({
			"phase": 0,
			"timer": 0.0,
			"started": false,
		})
		_pw_merge_started.append(false)

		_pw_count += 1

	# ── マージアニメーション順次開始（0.3秒間隔）──
	# 配列順 = 奥→手前（逆マッピング済み）なので、index 0 から順に開始
	const MERGE_INTERVAL: float = 0.3
	var total_walls: int = _pw_anims.size()
	if total_walls > 0:
		var all_started: bool = true
		for ms: bool in _pw_merge_started:
			if not ms:
				all_started = false
				break
		if not all_started:
			_pw_merge_timer += dt
			while _pw_merge_timer >= MERGE_INTERVAL:
				# 配列順（0=最奥）でまだ開始していない壁を探す
				var found_next: bool = false
				for search_i: int in range(total_walls):
					if not _pw_merge_started[search_i]:
						_pw_merge_started[search_i] = true
						_pw_anims[search_i]["phase"] = 1
						_pw_anims[search_i]["started"] = true
						if search_i < _pw_left.size():
							_pw_left[search_i].visible = true
							_pw_right[search_i].visible = true
						found_next = true
						break
				if not found_next:
					break
				_pw_merge_timer -= MERGE_INTERVAL

	# アニメーション更新
	const SLIDE_DURATION: float = 0.25
	const FLASH_DURATION: float = 0.35
	# 画面外（遠く）から飛んでくるように開始位置を拡張
	const SLIDE_START_X: float = 150.0

	for i: int in range(_pw_anims.size()):
		var anim: Dictionary = _pw_anims[i]
		if not anim["started"] or i >= _pw_walls.size():
			continue

		var phase: int = anim["phase"]
		var t_val: float = anim["timer"]
		t_val += dt
		anim["timer"] = t_val

		if phase == 1:
			var p: float = clampf(t_val / SLIDE_DURATION, 0.0, 1.0)
			# キレのあるイージング (EaseOutExpo風) に変更して超高速で飛んできて急ブレーキ
			var eased: float = 1.0 - pow(1.0 - p, 5.0)
			var x_offset: float = SLIDE_START_X * (1.0 - eased)
			_pw_left[i].position.x = -x_offset
			_pw_right[i].position.x = x_offset

			if p >= 1.0:
				anim["phase"] = 2
				anim["timer"] = 0.0
				_pw_left[i].visible = false
				_pw_right[i].visible = false
				_pw_walls[i].visible = true
				_pw_walls[i].scale = Vector3(1.15, 1.15, 1.15)
				_spawn_merge_sparks(_pw_walls[i].global_position)

		elif phase == 2:
			var p: float = clampf(t_val / FLASH_DURATION, 0.0, 1.0)
			var eased: float = 1.0 - pow(1.0 - p, 2.0)
			var s: float = lerpf(1.15, 1.0, eased)
			_pw_walls[i].scale = Vector3(s, s, s)
			if p >= 1.0:
				anim["phase"] = 3
				_pw_walls[i].scale = Vector3.ONE


## 合体時の火花パーティクルを生成
func _spawn_merge_sparks(pos: Vector3) -> void:
	# サイズを時間経過で縮小するカーブ
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))

	# 1. 飛び散る火花 (Spark)
	var sparks := CPUParticles3D.new()
	sparks.amount = 150
	sparks.lifetime = 1.0
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.randomness = 1.0

	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.5, 2.0, 0.5)

	sparks.direction = Vector3(0.0, 1.0, 0.0)
	sparks.spread = 180.0
	sparks.initial_velocity_min = 15.0
	sparks.initial_velocity_max = 35.0
	sparks.gravity = Vector3(0, -10.0, 0)
	sparks.damping_min = 5.0
	sparks.damping_max = 10.0

	sparks.scale_amount_min = 2.0
	sparks.scale_amount_max = 4.0
	sparks.scale_amount_curve = curve

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = preload("res://kenney_particle-pack/PNG (Transparent)/spark_05.png")
	mat.albedo_color = Color(3.0, 1.5, 0.5, 1.0) # HDR風の強い発光
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true

	var mesh := QuadMesh.new()
	mesh.material = mat
	sparks.mesh = mesh

	sparks.global_position = pos + Vector3(0, 2.5, 0)
	wall_container.add_child(sparks)
	sparks.emitting = true

	# 2. 中央の閃光 (Flash)
	var flash := CPUParticles3D.new()
	flash.amount = 1
	flash.lifetime = 0.3
	flash.one_shot = true
	flash.gravity = Vector3.ZERO
	flash.scale_amount_min = 15.0
	flash.scale_amount_max = 15.0
	flash.scale_amount_curve = curve
	
	var mat_flash := StandardMaterial3D.new()
	mat_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_flash.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat_flash.albedo_texture = preload("res://kenney_particle-pack/PNG (Transparent)/flare_01.png")
	mat_flash.albedo_color = Color(2.5, 2.0, 1.0, 1.0)
	mat_flash.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	
	var mesh_flash := QuadMesh.new()
	mesh_flash.material = mat_flash
	flash.mesh = mesh_flash
	flash.global_position = pos + Vector3(0, 2.5, 0)
	wall_container.add_child(flash)
	flash.emitting = true

	# クリーンアップ
	var tw := create_tween()
	tw.tween_callback(sparks.queue_free).set_delay(2.5)
	tw.tween_callback(flash.queue_free).set_delay(2.0)


func _clear_preview_walls() -> void:
	for wall: Node3D in _pw_walls:
		if is_instance_valid(wall): wall.queue_free()
	for wall: Node3D in _pw_left:
		if is_instance_valid(wall): wall.queue_free()
	for wall: Node3D in _pw_right:
		if is_instance_valid(wall): wall.queue_free()
	_pw_walls.clear()
	_pw_left.clear()
	_pw_right.clear()
	_pw_anims.clear()
	_pw_count = 0
	_pw_merge_started.clear()
	_pw_merge_timer = 0.0

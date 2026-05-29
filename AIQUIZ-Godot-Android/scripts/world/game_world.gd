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
const CONVEYOR_FLOOR_SHADER: Shader = preload("res://shaders/conveyor_belt_floor.gdshader")

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
# ── スタートバリア壁（カウントダウン終了まで問題を隠す） ──
var _start_barrier: Node3D = null
var _barrier_exploded: bool = false
var _barrier_dropping: bool = false
var _barrier_drop_timer: float = 0.0
var _barrier_spawned_for_session: bool = false  # 1ゲームに1回だけ
const MAX_VISIBLE_WALLS := 4
const BG_COLOR := Color(0.82, 0.85, 0.90)
const FLOOR_COLOR := Color(0.35, 0.35, 0.35)
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
const CONVEYOR_RETURN_BELT_GAP: float = 0.03
const CONVEYOR_SIDE_FRAME_WIDTH: float = 0.24
const CONVEYOR_SIDE_FRAME_HEIGHT: float = 1.05
const CONVEYOR_SIDE_FRAME_OVERHANG: float = 1.2
const CONVEYOR_SIDE_FRAME_TOP_CLEARANCE: float = 0.26

var pause_menu: CanvasLayer = null
@onready var gameplay_hud: CanvasLayer = $GameplayHUD
var _mobile_emote_p1: int = 0
var _floor_belt_material: ShaderMaterial = null
var _floor_rail_left: MeshInstance3D = null
var _floor_rail_right: MeshInstance3D = null
var _conveyor_roller_front: MeshInstance3D = null
var _conveyor_roller_back: MeshInstance3D = null
var _conveyor_return_belt: MeshInstance3D = null
var _conveyor_return_material: ShaderMaterial = null
var _conveyor_roller_front_material: ShaderMaterial = null
var _conveyor_roller_back_material: ShaderMaterial = null
var _conveyor_side_frame_left: MeshInstance3D = null
var _conveyor_side_frame_right: MeshInstance3D = null
var _floor_collision_body: StaticBody3D = null

# ── リプレイ記録 ──
var _recorder: ReplayRecorder = null
var _replay_mode: bool = false

func _ready() -> void:
	game_state = QuizManager.game_state
	quiz_wall_scene = preload("res://scenes/quiz_wall.tscn")

	# リプレイモードチェック
	_replay_mode = get_meta("replay_mode", false)

	# Listen for game state signals
	game_state.state_changed.connect(_on_state_changed)
	game_state.quiz_loaded.connect(_on_quiz_loaded)
	game_state.correct_answer.connect(_on_correct)
	game_state.wrong_answer.connect(_on_wrong)

	# リプレイ記録を開始（通常モードのみ）
	# TODO: 一旦リプレイ機能を封印するため無効化
	if not _replay_mode:
		pass
		#_recorder = ReplayRecorder.new()
		#_recorder.start_recording(game_state)

	# Setup network sync layer
	_net_state = NetGameState.new()
	add_child(_net_state)
	_net_state.setup(game_state)

	# Setup environment
	_setup_environment()
	_setup_lighting()
	_setup_floor_conveyor()
	_setup_magma()

	# Pause menu setup
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_menu()

	# バーチャルコントローラーのシグナル接続
	if gameplay_hud and gameplay_hud.has_node("VirtualController"):
		var vc = gameplay_hud.get_node("VirtualController")
		if vc:
			vc.pause_triggered.connect(_toggle_pause)
			vc.emote_triggered.connect(func(emote_id: int):
				print("[WORLD] Received mobile emote: %d" % emote_id)
				_mobile_emote_p1 = emote_id
			)
			vc.swipe_left.connect(func():
				game_state.handle_mobile_swipe(true)
			)
			vc.swipe_right.connect(func():
				game_state.handle_mobile_swipe(false)
			)


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

		# バーチャルコントローラー（タッチUI）の入力をマージ
		var vc = null
		if gameplay_hud and gameplay_hud.has_node("VirtualController"):
			vc = gameplay_hud.get_node("VirtualController")
		if vc and vc.visible:
			var vc_axis = vc.get_joystick_axis()
			if vc_axis.length_squared() > 0.01:
				axis_p1 = vc_axis
			if vc.is_jump_pressed():
				jump_p1 = true
			if _mobile_emote_p1 > 0:
				emote_p1 = _mobile_emote_p1
				_mobile_emote_p1 = 0

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
			var arrow_axis := Vector2.ZERO
			if Input.is_key_pressed(KEY_RIGHT): arrow_axis.x -= 1.0
			if Input.is_key_pressed(KEY_LEFT): arrow_axis.x += 1.0
			if Input.is_key_pressed(KEY_UP): arrow_axis.y += 1.0
			if Input.is_key_pressed(KEY_DOWN): arrow_axis.y -= 1.0
			if arrow_axis.length_squared() > 0.01:
				axis_p1 = arrow_axis

		axis_p1 = axis_p1.normalized()
		if game_state.num_players >= 2:
			axis_p2 = axis_p2.normalized()

	# Mouse look (1P only, not online and not replay, and not mobile)
	var is_mobile := OS.has_feature("mobile")
	if not is_mobile and not _replay_mode and game_state.game_state == Constants.STATE_PLAYING and game_state.num_players == 1 and not _is_online:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Update game state (host or offline only — client receives snapshots)
	if not _is_client and not _replay_mode:
		game_state.update(dt, axis_p1, axis_p2, jump_p1, jump_p2, emote_p1, emote_p2)

	# リプレイ記録
	if _recorder and _recorder.is_recording:
		_recorder.capture(game_state)

		# 記録の終了判定（ゲームオーバーやクリア演出が終わるまで記録を続ける）
		if game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
			# 1Pと2P両方のタイマーを確認
			var go_timer: float = game_state.game_over_timer
			if game_state.num_players >= 2:
				go_timer = maxf(game_state.game_over_timer, game_state.player2_game_over_timer)
			if go_timer >= 4.0:
				_recorder.stop_recording(game_state)
				QuizManager.set_meta("last_replay", _recorder)
				print("[ReplayRecorder] Recording stopped: %d frames, %.1fs" % [_recorder.frame_count, _recorder.get_duration()])

	# Network sync (snapshot send for host)
	if _net_state:
		_net_state.process_network(dt)

	# Update visuals
	_update_floor_conveyor()
	_update_floor()
	_update_flyover()
	_update_player()
	_update_walls()
	_update_goal_line()
	_update_preview_walls(dt)
	_update_camera(dt)
	_check_particles()
	_update_start_barrier()

	# Handle R key for restart (ESC is handled in _unhandled_input)
	if game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
		if Input.is_key_pressed(KEY_R) :
			game_state.reset_to_menu()
			get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _setup_floor_conveyor() -> void:
	if not floor_mesh:
		return
	_floor_belt_material = ShaderMaterial.new()
	_floor_belt_material.shader = CONVEYOR_FLOOR_SHADER
	_floor_belt_material.set_shader_parameter("scroll_z", 0.0)
	_floor_belt_material.set_shader_parameter("scroll_sign", 1.0)
	_floor_belt_material.set_shader_parameter("base_color", CONVEYOR_BELT_BASE_COLOR)
	_floor_belt_material.set_shader_parameter("stripe_color", CONVEYOR_BELT_STRIPE_COLOR)
	_floor_belt_material.set_shader_parameter("side_color", CONVEYOR_BELT_SIDE_COLOR)
	floor_mesh.material_override = _floor_belt_material
	_setup_floor_rails()
	_setup_conveyor_loop_geometry()
	_setup_floor_collision()

func _setup_floor_collision() -> void:
	if not floor_mesh:
		return
	var floor_box: BoxMesh = floor_mesh.mesh as BoxMesh
	if not floor_box:
		return
	_floor_collision_body = StaticBody3D.new()
	_floor_collision_body.collision_layer = 1
	_floor_collision_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(floor_box.size.x, 0.5, floor_box.size.z)
	col.shape = shape
	_floor_collision_body.add_child(col)
	# 床上面がFLOOR_TOP_Yに一致するように配置（floor_meshの子として相対座標）
	_floor_collision_body.position = Vector3(0, -0.25, 0)
	floor_mesh.add_child(_floor_collision_body)

func _update_floor_conveyor() -> void:
	if not _floor_belt_material:
		return
	_floor_belt_material.set_shader_parameter("scroll_z", game_state.world_scroll_z)
	if _conveyor_roller_front_material:
		_conveyor_roller_front_material.set_shader_parameter("scroll_z", game_state.world_scroll_z)
	if _conveyor_roller_back_material:
		_conveyor_roller_back_material.set_shader_parameter("scroll_z", game_state.world_scroll_z)
	if _conveyor_return_material:
		_conveyor_return_material.set_shader_parameter("scroll_z", game_state.world_scroll_z)

func _setup_floor_rails() -> void:
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(FLOOR_RAIL_WIDTH, FLOOR_RAIL_HEIGHT, 144.0)
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.27, 0.275, 0.28)
	rail_mat.roughness = 0.66
	rail_mat.metallic = 0.22

	_floor_rail_left = MeshInstance3D.new()
	_floor_rail_left.mesh = rail_mesh
	_floor_rail_left.material_override = rail_mat
	add_child(_floor_rail_left)

	_floor_rail_right = MeshInstance3D.new()
	_floor_rail_right.mesh = rail_mesh
	_floor_rail_right.material_override = rail_mat
	add_child(_floor_rail_right)

	_update_floor_rails()

func _update_floor_rails() -> void:
	if not _floor_rail_left or not _floor_rail_right or not floor_mesh:
		return
	var box_mesh: BoxMesh = floor_mesh.mesh as BoxMesh
	if not box_mesh:
		return
	var floor_length: float = box_mesh.size.z
	var rail_mesh_l := _floor_rail_left.mesh as BoxMesh
	var rail_mesh_r := _floor_rail_right.mesh as BoxMesh
	if rail_mesh_l:
		rail_mesh_l.size = Vector3(FLOOR_RAIL_WIDTH, FLOOR_RAIL_HEIGHT, floor_length)
	if rail_mesh_r:
		rail_mesh_r.size = Vector3(FLOOR_RAIL_WIDTH, FLOOR_RAIL_HEIGHT, floor_length)

	var rail_y: float = FLOOR_TOP_Y + FLOOR_RAIL_HEIGHT * 0.5
	var rail_x: float = FLOOR_HALF_WIDTH - FLOOR_RAIL_WIDTH * 0.5 - FLOOR_RAIL_INSET
	var floor_center_z: float = floor_mesh.position.z
	_floor_rail_left.position = Vector3(-rail_x, rail_y, floor_center_z)
	_floor_rail_right.position = Vector3(rail_x, rail_y, floor_center_z)

func _setup_conveyor_loop_geometry() -> void:
	var roller_mesh := CylinderMesh.new()
	roller_mesh.top_radius = CONVEYOR_ROLLER_RADIUS
	roller_mesh.bottom_radius = CONVEYOR_ROLLER_RADIUS
	roller_mesh.height = CONVEYOR_ROLLER_LENGTH
	roller_mesh.radial_segments = 64
	roller_mesh.rings = 4

	_conveyor_roller_front_material = ShaderMaterial.new()
	_conveyor_roller_front_material.shader = CONVEYOR_FLOOR_SHADER
	_conveyor_roller_front_material.set_shader_parameter("scroll_z", 0.0)
	_conveyor_roller_front_material.set_shader_parameter("scroll_sign", 1.0)
	_conveyor_roller_front_material.set_shader_parameter("roller_mode", 1.0)
	_conveyor_roller_front_material.set_shader_parameter("roller_radius", CONVEYOR_ROLLER_RADIUS)
	_conveyor_roller_front_material.set_shader_parameter("roller_contact_z", 0.0)
	_conveyor_roller_front_material.set_shader_parameter("roller_arc_sign", -1.0)
	_conveyor_roller_front_material.set_shader_parameter("base_color", CONVEYOR_BELT_BASE_COLOR)
	_conveyor_roller_front_material.set_shader_parameter("stripe_color", CONVEYOR_BELT_STRIPE_COLOR)
	_conveyor_roller_front_material.set_shader_parameter("side_color", CONVEYOR_BELT_SIDE_COLOR)
	_conveyor_roller_front_material.set_shader_parameter("stripe_scale", 12.0)
	_conveyor_roller_front_material.set_shader_parameter("stripe_softness", 0.08)
	_conveyor_roller_front_material.set_shader_parameter("groove_strength", 0.12)
	_conveyor_roller_front_material.set_shader_parameter("roller_depth", 0.0)
	_conveyor_roller_front_material.set_shader_parameter("roughness_val", 0.72)
	_conveyor_roller_front_material.set_shader_parameter("metallic_val", 0.16)

	_conveyor_roller_back_material = ShaderMaterial.new()
	_conveyor_roller_back_material.shader = CONVEYOR_FLOOR_SHADER
	_conveyor_roller_back_material.set_shader_parameter("scroll_z", 0.0)
	_conveyor_roller_back_material.set_shader_parameter("scroll_sign", 1.0)
	_conveyor_roller_back_material.set_shader_parameter("roller_mode", 1.0)
	_conveyor_roller_back_material.set_shader_parameter("roller_radius", CONVEYOR_ROLLER_RADIUS)
	_conveyor_roller_back_material.set_shader_parameter("roller_contact_z", 0.0)
	_conveyor_roller_back_material.set_shader_parameter("roller_arc_sign", 1.0)
	_conveyor_roller_back_material.set_shader_parameter("base_color", CONVEYOR_BELT_BASE_COLOR)
	_conveyor_roller_back_material.set_shader_parameter("stripe_color", CONVEYOR_BELT_STRIPE_COLOR)
	_conveyor_roller_back_material.set_shader_parameter("side_color", CONVEYOR_BELT_SIDE_COLOR)
	_conveyor_roller_back_material.set_shader_parameter("stripe_scale", 12.0)
	_conveyor_roller_back_material.set_shader_parameter("stripe_softness", 0.08)
	_conveyor_roller_back_material.set_shader_parameter("groove_strength", 0.12)
	_conveyor_roller_back_material.set_shader_parameter("roller_depth", 0.0)
	_conveyor_roller_back_material.set_shader_parameter("roughness_val", 0.72)
	_conveyor_roller_back_material.set_shader_parameter("metallic_val", 0.16)

	_conveyor_roller_front = MeshInstance3D.new()
	_conveyor_roller_front.mesh = roller_mesh
	_conveyor_roller_front.material_override = _conveyor_roller_front_material
	_conveyor_roller_front.rotation = Vector3(0.0, 0.0, PI * 0.5)
	var body_f := StaticBody3D.new()
	body_f.collision_layer = 1
	body_f.collision_mask = 0
	var col_f := CollisionShape3D.new()
	var shape_f := CylinderShape3D.new()
	shape_f.radius = CONVEYOR_ROLLER_RADIUS
	shape_f.height = CONVEYOR_ROLLER_LENGTH
	col_f.shape = shape_f
	body_f.add_child(col_f)
	_conveyor_roller_front.add_child(body_f)
	add_child(_conveyor_roller_front)

	_conveyor_roller_back = MeshInstance3D.new()
	_conveyor_roller_back.mesh = roller_mesh
	_conveyor_roller_back.material_override = _conveyor_roller_back_material
	_conveyor_roller_back.rotation = Vector3(0.0, 0.0, PI * 0.5)
	var body_b := StaticBody3D.new()
	body_b.collision_layer = 1
	body_b.collision_mask = 0
	var col_b := CollisionShape3D.new()
	var shape_b := CylinderShape3D.new()
	shape_b.radius = CONVEYOR_ROLLER_RADIUS
	shape_b.height = CONVEYOR_ROLLER_LENGTH
	col_b.shape = shape_b
	body_b.add_child(col_b)
	_conveyor_roller_back.add_child(body_b)
	add_child(_conveyor_roller_back)

	var return_mesh := BoxMesh.new()
	return_mesh.size = Vector3(CONVEYOR_ROLLER_LENGTH, CONVEYOR_RETURN_BELT_THICKNESS, 8.0)
	_conveyor_return_belt = MeshInstance3D.new()
	_conveyor_return_belt.mesh = return_mesh
	_conveyor_return_material = ShaderMaterial.new()
	_conveyor_return_material.shader = CONVEYOR_FLOOR_SHADER
	_conveyor_return_material.set_shader_parameter("scroll_z", 0.0)
	_conveyor_return_material.set_shader_parameter("scroll_sign", -1.0)
	_conveyor_return_material.set_shader_parameter("base_color", CONVEYOR_BELT_BASE_COLOR)
	_conveyor_return_material.set_shader_parameter("stripe_color", CONVEYOR_BELT_STRIPE_COLOR)
	_conveyor_return_material.set_shader_parameter("side_color", CONVEYOR_BELT_SIDE_COLOR)
	_conveyor_return_material.set_shader_parameter("rim_inner_x", 12.0)
	_conveyor_return_material.set_shader_parameter("rim_softness", 0.02)
	_conveyor_return_belt.material_override = _conveyor_return_material
	add_child(_conveyor_return_belt)

	var side_frame_mesh := BoxMesh.new()
	side_frame_mesh.size = Vector3(CONVEYOR_SIDE_FRAME_WIDTH, CONVEYOR_SIDE_FRAME_HEIGHT, 12.0)
	var side_frame_mat := StandardMaterial3D.new()
	side_frame_mat.albedo_color = Color(0.30, 0.31, 0.33)
	side_frame_mat.roughness = 0.62
	side_frame_mat.metallic = 0.16

	_conveyor_side_frame_left = MeshInstance3D.new()
	_conveyor_side_frame_left.mesh = side_frame_mesh
	_conveyor_side_frame_left.material_override = side_frame_mat
	add_child(_conveyor_side_frame_left)

	_conveyor_side_frame_right = MeshInstance3D.new()
	_conveyor_side_frame_right.mesh = side_frame_mesh
	_conveyor_side_frame_right.material_override = side_frame_mat
	add_child(_conveyor_side_frame_right)

	_update_conveyor_loop_geometry()

func _update_conveyor_loop_geometry() -> void:
	if not floor_mesh:
		return
	var floor_box: BoxMesh = floor_mesh.mesh as BoxMesh
	if not floor_box:
		return

	var floor_length: float = floor_box.size.z
	var floor_center_z: float = floor_mesh.position.z
	var half_len: float = floor_length * 0.5
	var top_front_contact_z: float = floor_center_z + half_len
	var top_back_contact_z: float = floor_center_z - half_len
	# 実機風: ローラー中心は上面より下に置いて、ベルトが端で巻き取られる接線を作る
	var roller_center_y: float = FLOOR_TOP_Y - CONVEYOR_ROLLER_RADIUS # 上端=ベルト面、半分を床に埋め込む
	var front_z: float = floor_center_z + half_len
	var back_z: float = floor_center_z - half_len

	if _conveyor_roller_front:
		_conveyor_roller_front.position = Vector3(0.0, roller_center_y, front_z)
		if _conveyor_roller_front_material:
			_conveyor_roller_front_material.set_shader_parameter("roller_contact_z", top_front_contact_z)
	if _conveyor_roller_back:
		_conveyor_roller_back.position = Vector3(0.0, roller_center_y, back_z)
		if _conveyor_roller_back_material:
			_conveyor_roller_back_material.set_shader_parameter("roller_contact_z", top_back_contact_z)

	if _conveyor_return_belt:
		var return_len: float = maxf(0.2, floor_length - 0.12)
		var return_mesh: BoxMesh = _conveyor_return_belt.mesh as BoxMesh
		if return_mesh:
			return_mesh.size = Vector3(CONVEYOR_ROLLER_LENGTH, CONVEYOR_RETURN_BELT_THICKNESS, return_len)
		var return_y: float = roller_center_y - CONVEYOR_ROLLER_RADIUS - CONVEYOR_RETURN_BELT_GAP - CONVEYOR_RETURN_BELT_THICKNESS * 0.5
		_conveyor_return_belt.position = Vector3(0.0, return_y, floor_center_z)

	var frame_len: float = floor_length + CONVEYOR_SIDE_FRAME_OVERHANG * 2.0
	var frame_center_y: float = FLOOR_TOP_Y + CONVEYOR_SIDE_FRAME_TOP_CLEARANCE - CONVEYOR_SIDE_FRAME_HEIGHT * 0.5
	var frame_x: float = FLOOR_HALF_WIDTH - CONVEYOR_SIDE_FRAME_WIDTH * 0.5
	if _conveyor_side_frame_left:
		var frame_mesh_l := _conveyor_side_frame_left.mesh as BoxMesh
		if frame_mesh_l:
			frame_mesh_l.size = Vector3(CONVEYOR_SIDE_FRAME_WIDTH, CONVEYOR_SIDE_FRAME_HEIGHT, frame_len)
		_conveyor_side_frame_left.position = Vector3(-frame_x, frame_center_y, floor_center_z)
	if _conveyor_side_frame_right:
		var frame_mesh_r := _conveyor_side_frame_right.mesh as BoxMesh
		if frame_mesh_r:
			frame_mesh_r.size = Vector3(CONVEYOR_SIDE_FRAME_WIDTH, CONVEYOR_SIDE_FRAME_HEIGHT, frame_len)
		_conveyor_side_frame_right.position = Vector3(frame_x, frame_center_y, floor_center_z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed() and not event.is_echo():
		if game_state and game_state.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]:
			_toggle_pause()
			
	if event is InputEventMouseMotion:
		if not _replay_mode and game_state and game_state.game_state == Constants.STATE_PLAYING \
				and game_state.num_players == 1 and not get_tree().paused:
			game_state.camera_yaw -= event.relative.x * 0.002
			game_state.camera_pitch -= event.relative.y * 0.002
			game_state.camera_pitch = clampf(game_state.camera_pitch,
				-PI / 2.5, PI / 2.5)
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		if event.is_pressed() and not event.is_echo():
			if game_state and game_state.game_state == Constants.STATE_WAITING_START:
				# カウントダウン壁が出現し終わるまで開始トリガーをブロック
				if not _barrier_spawned_for_session or _barrier_dropping:
					return
				if game_state.has_method("trigger_start"):
					game_state.trigger_start()

func _update_floor() -> void:
	if game_state.game_state in [Constants.STATE_FLYOVER, Constants.STATE_PRELOADING, Constants.STATE_WAITING_START]:
		# フライオーバー / プリロード中: 最後の壁(orゴールライン)まで床を延長
		var t := game_state.tuning
		var wall_count: int
		if not game_state._is_fixed_count_mode():
			wall_count = 30
		else:
			wall_count = game_state.target_count if game_state.target_count > 0 else 10
		if game_state.game_state == Constants.STATE_FLYOVER:
			wall_count = game_state.flyover_total_walls
		var last_wall_z: float = t.wall_start_z + (wall_count - 1) * t.wall_spacing
		var floor_front: float = last_wall_z + 30.0
		# 2P×10Qモード: ゴールラインまで延長
		if game_state.num_players >= 2 and game_state.mode == Constants.MODE_TEN:
			var goal_line_z: float = t.wall_start_z + game_state.target_count * t.wall_spacing + 15.0
			floor_front = maxf(floor_front, goal_line_z + 20.0)
		var floor_back: float = game_state.FLOOR_BACK_Z
		var floor_length: float = floor_front - floor_back
		var floor_center_z: float = (floor_front + floor_back) / 2.0
		var box_mesh: BoxMesh = floor_mesh.mesh as BoxMesh
		if box_mesh:
			box_mesh.size = Vector3(24.0, 16.0, floor_length)
		floor_mesh.position = Vector3(0, -9.2, floor_center_z)
	elif game_state.game_state == Constants.STATE_GOAL_RACE:
		# ゴールレース中: ゴールラインの先まで床を延長
		var floor_front: float = game_state.goal_z + 20.0 - game_state.world_scroll_z
		var floor_back: float = game_state.FLOOR_BACK_Z
		var floor_length: float = maxf(144.0, floor_front - floor_back)
		var floor_center_z: float = (floor_front + floor_back) / 2.0
		var box_mesh: BoxMesh = floor_mesh.mesh as BoxMesh
		if box_mesh:
			box_mesh.size = Vector3(24.0, 16.0, floor_length)
		floor_mesh.position = Vector3(0, -9.2, floor_center_z)
	else:
		# 通常時: 最奥の壁、またはプレイヤーの位置に合わせて床を動的に延長
		var t := game_state.tuning
		var max_wall_idx: int = game_state.current_wall_index + MAX_VISIBLE_WALLS
		if game_state.mode == Constants.MODE_TEN or game_state.mode == Constants.MODE_TUTORIAL:
			max_wall_idx = mini(max_wall_idx, game_state.target_count)
		var furthest_wall_z: float = t.wall_start_z + max_wall_idx * t.wall_spacing
		var player_ahead_z: float = game_state.player_z + 40.0
		if game_state.num_players >= 2:
			player_ahead_z = maxf(player_ahead_z, game_state.player2_z + 40.0)

		var max_z_needed: float = maxf(furthest_wall_z, player_ahead_z)
		var floor_front: float = max_z_needed + 40.0 - game_state.world_scroll_z
		floor_front = maxf(floor_front, 139.5) # 最低限の長さを保証

		var floor_back: float = game_state.FLOOR_BACK_Z
		var floor_length: float = floor_front - floor_back
		var floor_center_z: float = (floor_front + floor_back) / 2.0
		var box_mesh: BoxMesh = floor_mesh.mesh as BoxMesh
		if box_mesh:
			box_mesh.size = Vector3(24.0, 16.0, floor_length)
		floor_mesh.position = Vector3(0, -9.2, floor_center_z)
	_update_floor_rails()
	_update_conveyor_loop_geometry()

func _update_player() -> void:
	if game_state.game_state in [Constants.STATE_MENU, Constants.STATE_PRELOADING]:
		player_node.visible = false
		_hats_applied = false
		return

	player_node.visible = true
	var pc: PlayerController = player_node as PlayerController
	if pc:
		pc.update_from_state(game_state)
		
		# Apply hats when game starts
		if not _hats_applied:
			pc.set_hat(1, game_state.p1_hat)
			if game_state.num_players >= 2 and pc.p2_container != null:
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
	# Keep walls behind that haven't reached the cliff yet
	var start_idx := maxi(0, game_state.current_wall_index - 3)
	# 固定問数モードでは target_count 以降の壁を生成しない
	var max_wall_idx: int = -1
	if game_state.mode == Constants.MODE_TEN or game_state.mode == Constants.MODE_TUTORIAL:
		max_wall_idx = game_state.target_count - 1  # 0-indexed: 壁0〜9まで
	for i: int in range(MAX_VISIBLE_WALLS + 3):
		var idx: int = start_idx + i
		# 固定問数モードでは target_count 以降の壁をスキップ
		if max_wall_idx >= 0 and idx > max_wall_idx:
			continue
		var wz: float = t.wall_start_z + idx * t.wall_spacing
		var local_z: float = wz - game_state.world_scroll_z
		if local_z > game_state.FLOOR_BACK_Z:
			needed_indices.append(idx)

	# Remove walls no longer needed
	var to_remove: Array[Node3D] = []
	for wall: Node3D in _active_walls:
		if not wall.has_meta("wall_index") or wall.get_meta("wall_index") not in needed_indices:
			to_remove.append(wall)
	for wall: Node3D in to_remove:
		_active_walls.erase(wall)
		var idx: int = wall.get_meta("wall_index") as int
		var wz: float = t.wall_start_z + idx * t.wall_spacing
		var local_z: float = wz - game_state.world_scroll_z
		if local_z <= game_state.FLOOR_BACK_Z + 0.1:
			if wall.has_method("shatter_wall"):
				wall.shatter_wall()
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
	elif new_state == Constants.STATE_PLAYING:
		_fireworks_launched = false
		_clear_preview_walls()
		# カウントダウン終了 → バリア壁を爆散！
		if not _barrier_exploded:
			_explode_start_barrier()
	elif new_state == Constants.STATE_MENU:
		_fireworks_launched = false
		_clear_preview_walls()
		_remove_start_barrier()
		_barrier_spawned_for_session = false
	elif new_state == Constants.STATE_WAITING_START:
		_clear_flyover_walls()
		# バリアはプレビュー壁完了後に自動スポーンするので、ここでは何もしない
	elif new_state == Constants.STATE_COUNTDOWN:
		# チュートリアル等でプレビュー壁がない場合のフォールバック
		if not _barrier_spawned_for_session:
			_begin_barrier_drop()

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
		if game_state.num_players == 1 and not OS.has_feature("mobile"):
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
	var is_endless: bool = not game_state._is_fixed_count_mode()
	var total_expected: int = maxi(30 if is_endless else game_state.target_count, quiz_count)
	var target_pw_count: int = total_expected if is_endless else quiz_count

	# ── 壁+シルエットの生成（クイズ到着に同期、奥から手前へ配置）──
	while _pw_count < target_pw_count:
		# エンドレスは手前から奥へ、固定モードは逆マッピング（奥から手前へ）
		var visual_idx: int = _pw_count if is_endless else (total_expected - 1 - _pw_count)
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
		elif wall_final.has_method("set_quiz"):
			wall_final.set_quiz(null, game_state.num_choices)

		# 左右は軽量シルエット（BoxMesh）
		var sil_l := _create_slide_silhouette(wz, -25.0)
		sil_l.visible = false
		wall_container.add_child(sil_l)
		_pw_left.append(sil_l)

		var sil_r := _create_slide_silhouette(wz, 25.0)
		sil_r.visible = false
		wall_container.add_child(sil_r)
		_pw_right.append(sil_r)

		# 新しい壁のアニメーション情報 — エンドレスモードなら即座に完了状態(phase 3)とする
		_pw_anims.append({
			"phase": 3 if is_endless else 0,
			"timer": 0.0,
			"started": is_endless,
		})
		_pw_merge_started.append(is_endless)
		
		if is_endless:
			wall_final.visible = true
			wall_final.scale = Vector3.ONE

		_pw_count += 1

	# ── マージアニメーション順次開始（0.15秒間隔）──
	# 配列順 = 奥→手前（逆マッピング済み）なので、index 0 から順に開始
	var is_offline: bool = QuizManager.provider.llm_mode == "OFFLINE"
	var merge_interval: float = 0.15 # オンライン・オフライン問わず爆速で開始
	var total_walls: int = _pw_anims.size()
	if total_walls > 0:
		var all_started: bool = true
		for ms: bool in _pw_merge_started:
			if not ms:
				all_started = false
				break
		if not all_started:
			_pw_merge_timer += dt
			while _pw_merge_timer >= merge_interval:
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
				_pw_merge_timer -= merge_interval

	# アニメーション更新
	var slide_duration: float = 0.125 # 常に最速
	var flash_duration: float = 0.175
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
			var p: float = clampf(t_val / slide_duration, 0.0, 1.0)
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
				
				# カメラに近づくほど強い振動を発生させる (全体的に振動を強化)
				var dist_z = absf(_pw_walls[i].global_position.z - camera_controller.global_position.z)
				var shake_power = clampf(40.0 / maxf(1.0, dist_z), 0.2, 1.6)
				game_state.camera_shake = maxf(game_state.camera_shake, shake_power)

		elif phase == 2:
			var p: float = clampf(t_val / flash_duration, 0.0, 1.0)
			var eased: float = 1.0 - pow(1.0 - p, 2.0)
			var s: float = lerpf(1.15, 1.0, eased)
			_pw_walls[i].scale = Vector3(s, s, s)
			if p >= 1.0:
				anim["phase"] = 3
				_pw_walls[i].scale = Vector3.ONE

	# ── 全壁のアニメ完了を検出 → バリア壁を落下開始 ──
	var required_walls: int = 1 if is_endless else game_state.target_count

	if _pw_anims.size() >= required_walls and not _barrier_spawned_for_session:
		var all_done := true
		for anim: Dictionary in _pw_anims:
			if anim.get("phase", 0) < 3:
				all_done = false
				break
		if all_done:
			_begin_barrier_drop()


## 合体時の火花パーティクルを生成
func _spawn_merge_sparks(pos: Vector3) -> void:
	# サイズを時間経過で縮小するカーブ
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))

	# 1. 飛び散る火花 (Spark) - 抑えめに調整
	var sparks := CPUParticles3D.new()
	sparks.amount = 60
	sparks.lifetime = 0.8
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.randomness = 1.0

	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.5, 2.0, 0.5)

	sparks.direction = Vector3(0.0, 1.0, 0.0)
	sparks.spread = 180.0
	sparks.initial_velocity_min = 8.0
	sparks.initial_velocity_max = 20.0
	sparks.gravity = Vector3(0, -25.0, 0)
	sparks.damping_min = 5.0
	sparks.damping_max = 10.0

	sparks.scale_amount_min = 1.0
	sparks.scale_amount_max = 2.5
	sparks.scale_amount_curve = curve

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = Color(1.5, 1.0, 0.6, 1.0) # 抑えめの発光
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true

	var mesh := QuadMesh.new()
	mesh.material = mat
	sparks.mesh = mesh

	sparks.global_position = pos + Vector3(0, 2.5, 0)
	wall_container.add_child(sparks)
	sparks.emitting = true

	# 2. 中央の閃光 (Flash) - 抑えめに調整
	var flash := CPUParticles3D.new()
	flash.amount = 1
	flash.lifetime = 0.25
	flash.one_shot = true
	flash.gravity = Vector3.ZERO
	flash.scale_amount_min = 8.0
	flash.scale_amount_max = 8.0
	flash.scale_amount_curve = curve
	
	var mat_flash := StandardMaterial3D.new()
	mat_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_flash.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat_flash.albedo_color = Color(1.2, 1.0, 0.8, 0.8)
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

# ============================================================
# スタートバリア壁（プレビュー壁完了後に上からズドンと落下）
# ============================================================

const BARRIER_SIZE := Vector3(32.0, 24.0, 1.8)
const BARRIER_COLOR := Color(0.12, 0.16, 0.28)
const BARRIER_DROP_HEIGHT := 40.0
const BARRIER_DROP_DURATION := 0.45

func _begin_barrier_drop() -> void:
	if _barrier_spawned_for_session:
		return
	_barrier_spawned_for_session = true
	_remove_start_barrier()
	_barrier_exploded = false
	var barrier_z: float = game_state.tuning.wall_start_z - 7.0
	_start_barrier = Node3D.new()
	_start_barrier.name = "StartBarrier"
	_start_barrier.position = Vector3(0, BARRIER_DROP_HEIGHT, barrier_z)
	# 壁メッシュ
	var mi := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = BARRIER_SIZE
	mi.mesh = bx
	var mt := StandardMaterial3D.new()
	mt.albedo_color = BARRIER_COLOR
	mt.roughness = 0.45
	mt.metallic = 0.25
	mt.emission_enabled = true
	mt.emission = Color(0.08, 0.12, 0.25)
	mt.emission_energy_multiplier = 0.4
	mi.material_override = mt
	_start_barrier.add_child(mi)
	# カウントダウン用ラベル
	var ql := Label3D.new()
	ql.name = "QuestionLabel"
	ql.text = ""
	ql.font_size = 450 if game_state.num_players == 1 else 800
	ql.pixel_size = 0.012
	ql.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ql.modulate = Color(1.0, 0.9, 0.3, 0.9)
	ql.outline_modulate = Color(0.02, 0.02, 0.08, 1.0)
	ql.outline_size = 40
	var label_y: float = 2.5 if game_state.num_players == 1 else 5.0
	ql.position = Vector3(0, label_y, -1.0)
	ql.rotation.y = PI
	var font := load("res://resources/fonts/NotoSansJP-Regular.otf")
	if font: ql.font = font
	_start_barrier.add_child(ql)
	# 待機パーティクル
	var sp := CPUParticles3D.new()
	sp.amount = 50
	sp.lifetime = 1.2
	sp.randomness = 1.0
	sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(16.0, 12.0, 0.3)
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 70.0
	sp.initial_velocity_min = 1.5
	sp.initial_velocity_max = 4.0
	sp.gravity = Vector3(0, -3.0, 0)
	sp.scale_amount_min = 0.06
	sp.scale_amount_max = 0.18
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.35, 0.55, 1.0)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.billboard_keep_scale = true
	var sq := QuadMesh.new()
	sq.material = sm
	sp.mesh = sq
	_start_barrier.add_child(sp)

	# スチーム用マテリアル
	var steam_mat := StandardMaterial3D.new()
	steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam_mat.albedo_color = Color(0.9, 0.9, 0.95, 0.25)
	steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	steam_mat.billboard_keep_scale = true
	var steam_quad := QuadMesh.new()
	steam_quad.material = steam_mat

	# 左から右へ噴き出す蒸気
	var steam_l := CPUParticles3D.new()
	steam_l.name = "SteamL"
	steam_l.emitting = false
	steam_l.amount = 120
	steam_l.lifetime = 1.5
	steam_l.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	steam_l.emission_box_extents = Vector3(0.5, 10.0, 1.0)
	steam_l.direction = Vector3(1, 0, 0)
	steam_l.spread = 15.0
	steam_l.gravity = Vector3(0, -1.0, 0)
	steam_l.initial_velocity_min = 5.0
	steam_l.initial_velocity_max = 8.0
	steam_l.scale_amount_min = 2.0
	steam_l.scale_amount_max = 4.5
	steam_l.mesh = steam_quad
	steam_l.position = Vector3(-16.0, 10.0, 0)
	_start_barrier.add_child(steam_l)

	# 右から左へ噴き出す蒸気
	var steam_r := CPUParticles3D.new()
	steam_r.name = "SteamR"
	steam_r.emitting = false
	steam_r.amount = 120
	steam_r.lifetime = 1.5
	steam_r.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	steam_r.emission_box_extents = Vector3(0.5, 10.0, 1.0)
	steam_r.direction = Vector3(-1, 0, 0)
	steam_r.spread = 15.0
	steam_r.gravity = Vector3(0, -1.0, 0)
	steam_r.initial_velocity_min = 5.0
	steam_r.initial_velocity_max = 8.0
	steam_r.scale_amount_min = 2.0
	steam_r.scale_amount_max = 4.5
	steam_r.mesh = steam_quad
	steam_r.position = Vector3(16.0, 10.0, 0)
	_start_barrier.add_child(steam_r)
	wall_container.add_child(_start_barrier)
	_barrier_dropping = true
	_barrier_drop_timer = 0.0

func _update_start_barrier() -> void:
	if _barrier_dropping and _start_barrier and is_instance_valid(_start_barrier):
		_barrier_drop_timer += get_process_delta_time()
		var p: float = clampf(_barrier_drop_timer / BARRIER_DROP_DURATION, 0.0, 1.0)
		var eased: float = p * p  # 加速落下
		_start_barrier.position.y = lerpf(BARRIER_DROP_HEIGHT, 0.0, eased)
		if p >= 1.0:
			_barrier_dropping = false
			_start_barrier.position.y = 0.0
			game_state.camera_shake = 1.2
			_spawn_landing_impact(_start_barrier.global_position)
		return
		
	if _start_barrier and is_instance_valid(_start_barrier):
		var ql := _start_barrier.get_node_or_null("QuestionLabel") as Label3D
		if ql:
			if game_state.game_state == Constants.STATE_COUNTDOWN:
				var remain := int(ceil(game_state.countdown_timer))
				ql.text = str(remain) if remain > 0 else ""
				
				var progress := 1.0 - clampf(game_state.countdown_timer / 3.99, 0.0, 1.0)
				
				# 1. 壁の振動演出
				# base position is x=0, y=0. apply non-linear random offset based on progress.
				var shake_intensity = lerpf(0.0, 0.6, pow(progress, 4.0))
				_start_barrier.position.x = randf_range(-shake_intensity, shake_intensity)
				_start_barrier.position.y = randf_range(-shake_intensity, shake_intensity)
				
				# 2. 横から噴き出す蒸気演出
				var steam_l := _start_barrier.get_node_or_null("SteamL") as CPUParticles3D
				if steam_l:
					steam_l.emitting = true
					steam_l.initial_velocity_max = lerpf(8.0, 35.0, progress)
					steam_l.scale_amount_max = lerpf(2.0, 6.0, progress)
					
				var steam_r := _start_barrier.get_node_or_null("SteamR") as CPUParticles3D
				if steam_r:
					steam_r.emitting = true
					steam_r.initial_velocity_max = lerpf(8.0, 35.0, progress)
					steam_r.scale_amount_max = lerpf(2.0, 6.0, progress)
					
			else:
				ql.text = ""
				if game_state.game_state != Constants.STATE_WAITING_START:
					_start_barrier.position.x = 0
					_start_barrier.position.y = 0
				
		if game_state.game_state not in [Constants.STATE_COUNTDOWN, Constants.STATE_FLYOVER, Constants.STATE_WAITING_START, Constants.STATE_PRELOADING]:
			if _barrier_exploded:
				_remove_start_barrier()

func _spawn_landing_impact(pos: Vector3) -> void:
	var dust := CPUParticles3D.new()
	dust.amount = 80
	dust.lifetime = 1.0
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.randomness = 1.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(16.0, 0.5, 1.0)
	dust.spread = 180.0
	dust.initial_velocity_min = 5.0
	dust.initial_velocity_max = 15.0
	dust.gravity = Vector3(0, -3.0, 0)
	dust.scale_amount_min = 0.3
	dust.scale_amount_max = 1.0
	dust.color = Color(0.5, 0.5, 0.6, 0.5)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(0.6, 0.6, 0.7, 0.4)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.billboard_keep_scale = true
	var dq := QuadMesh.new()
	dq.material = dm
	dust.mesh = dq
	dust.position = pos + Vector3(0, -BARRIER_SIZE.y * 0.5, 0)
	dust.emitting = true
	get_tree().current_scene.add_child(dust)
	var ct := Timer.new()
	ct.wait_time = 3.0
	ct.one_shot = true
	ct.autostart = true
	dust.add_child(ct)
	ct.timeout.connect(dust.queue_free)

func _explode_start_barrier() -> void:
	_barrier_exploded = true
	if not _start_barrier or not is_instance_valid(_start_barrier):
		return
	var bpos: Vector3 = _start_barrier.global_position
	_start_barrier.visible = false
	game_state.camera_shake = 0.7
	var cx_n := 12
	var cy_n := 10
	var cs := Vector3(BARRIER_SIZE.x / cx_n, BARRIER_SIZE.y / cy_n, BARRIER_SIZE.z)
	var shared_box := BoxMesh.new()
	shared_box.size = cs * 0.8
	for cx: int in range(cx_n):
		for cy: int in range(cy_n):
			var chunk := RigidBody3D.new()
			chunk.mass = 0.4
			chunk.gravity_scale = 2.5
			chunk.collision_layer = 0
			chunk.collision_mask = 0
			var cmi := MeshInstance3D.new()
			cmi.mesh = shared_box
			var m := StandardMaterial3D.new()
			m.albedo_color = BARRIER_COLOR.lerp(Color(0.4, 0.5, 0.9), randf() * 0.4)
			m.roughness = 0.5
			m.metallic = 0.1
			if randf() > 0.5:
				m.emission_enabled = true
				m.emission = Color(0.2, 0.35, 0.8) * 0.6
				m.emission_energy_multiplier = 0.5
			cmi.material_override = m
			chunk.add_child(cmi)
			var ox: float = (cx - (cx_n - 1) * 0.5) * cs.x + randf_range(-0.5, 0.5)
			var oy: float = (cy - (cy_n - 1) * 0.5) * cs.y + randf_range(-0.5, 0.5)
			chunk.global_position = bpos + Vector3(ox, oy, 0)
			get_tree().current_scene.add_child(chunk)
			# キャラの爆散と同じような散り方（左右に分かれて上に跳ねる）
			var sx := 1.0 if ox >= 0 else -1.0
			var vel := Vector3(
				sx * randf_range(3.0, 10.0),
				randf_range(6.0, 15.0),
				randf_range(-5.0, 5.0)
			)
			chunk.linear_velocity = vel
			chunk.angular_velocity = Vector3(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
			var t := Timer.new()
			t.wait_time = randf_range(2.5, 4.0)
			t.one_shot = true
			t.autostart = true
			chunk.add_child(t)
			t.timeout.connect(chunk.queue_free)
	
	game_state.camera_shake = 1.5
	_spawn_mega_explosion(bpos)
	
	var ct := Timer.new()
	ct.wait_time = 0.3
	ct.one_shot = true
	ct.autostart = true
	add_child(ct)
	ct.timeout.connect(_remove_start_barrier)

func _spawn_mega_explosion(pos: Vector3) -> void:
	var sr := get_tree().current_scene
	var flash := CPUParticles3D.new()
	flash.amount = 200
	flash.lifetime = 0.6
	flash.one_shot = true
	flash.explosiveness = 1.0
	flash.randomness = 1.0
	flash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flash.emission_sphere_radius = 5.0
	flash.spread = 180.0
	flash.initial_velocity_min = 15.0
	flash.initial_velocity_max = 45.0
	flash.gravity = Vector3(0, -5.0, 0)
	flash.scale_amount_min = 0.3
	flash.scale_amount_max = 1.2
	flash.color = Color(0.8, 0.85, 1.0)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.9, 0.92, 1.0)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.billboard_keep_scale = true
	var fq := QuadMesh.new()
	fq.material = fm
	flash.mesh = fq
	flash.position = pos
	flash.emitting = true
	sr.add_child(flash)
	var sparks := CPUParticles3D.new()
	sparks.amount = 250
	sparks.lifetime = 1.5
	sparks.one_shot = true
	sparks.explosiveness = 0.98
	sparks.randomness = 1.0
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 4.0
	sparks.spread = 180.0
	sparks.initial_velocity_min = 10.0
	sparks.initial_velocity_max = 35.0
	sparks.gravity = Vector3(0, -15.0, 0)
	sparks.scale_amount_min = 0.04
	sparks.scale_amount_max = 0.2
	sparks.color = Color(1.0, 0.75, 0.15)
	var spm := StandardMaterial3D.new()
	spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spm.albedo_color = Color(1.0, 0.85, 0.2)
	spm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spm.billboard_keep_scale = true
	var spq := QuadMesh.new()
	spq.material = spm
	sparks.mesh = spq
	sparks.position = pos
	sparks.emitting = true
	sr.add_child(sparks)
	var smoke := CPUParticles3D.new()
	smoke.amount = 60
	smoke.lifetime = 2.0
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	smoke.randomness = 1.0
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 6.0
	smoke.spread = 180.0
	smoke.initial_velocity_min = 3.0
	smoke.initial_velocity_max = 12.0
	smoke.gravity = Vector3(0, 2.0, 0)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.5
	smoke.color = Color(0.4, 0.42, 0.5, 0.6)
	var smm := StandardMaterial3D.new()
	smm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smm.albedo_color = Color(0.5, 0.52, 0.6, 0.5)
	smm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smm.billboard_keep_scale = true
	var smq := QuadMesh.new()
	smq.material = smm
	smoke.mesh = smq
	smoke.position = pos
	smoke.emitting = true
	sr.add_child(smoke)
	var cleanup := Timer.new()
	cleanup.wait_time = 4.0
	cleanup.one_shot = true
	cleanup.autostart = true
	flash.add_child(cleanup)
	cleanup.timeout.connect(func():
		if is_instance_valid(flash): flash.queue_free()
		if is_instance_valid(sparks): sparks.queue_free()
		if is_instance_valid(smoke): smoke.queue_free()
	)

func _remove_start_barrier() -> void:
	if _start_barrier and is_instance_valid(_start_barrier):
		_start_barrier.queue_free()
		_start_barrier = null

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
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

varying float v_height;

void vertex() {
	// Large slow waves
	float wave1 = sin(VERTEX.x * 0.3 + TIME * 1.0) * cos(VERTEX.z * 0.3 + TIME * 0.8) * 0.8;
	float wave2 = sin(VERTEX.x * 0.1 - TIME * 0.6) * sin(VERTEX.z * 0.15 + TIME * 0.4) * 1.0;

	// Bubbling peaks
	float bx = sin(VERTEX.x * 1.5 + TIME * 3.0);
	float bz = cos(VERTEX.z * 1.5 - TIME * 2.5);
	float bubbles = pow(abs(bx * bz), 6.0) * 0.8;

	VERTEX.y += wave1 + wave2 + bubbles;
	v_height = wave1 + wave2 + bubbles;
}

void fragment() {
	vec3 base_color = vec3(0.9, 0.3, 0.0); // Simple magma orange
	vec3 highlight = vec3(1.0, 0.9, 0.3) * clamp(v_height * 0.6, 0.0, 1.0);
	
	ALBEDO = base_color + highlight;
}
"""

func _setup_magma() -> void:
	var magma_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	plane.subdivide_width = 128
	plane.subdivide_depth = 128
	magma_mesh.mesh = plane
	magma_mesh.position = Vector3(0, -10.0, 0)
	magma_mesh.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 20, 400))

	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = MAGMA_SHADER

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

	if game_state.game_state == Constants.STATE_PLAYING:
		# Player 1: W/A/S/D
		if Input.is_key_pressed(KEY_D): axis_p1.x -= 1.0
		if Input.is_key_pressed(KEY_A): axis_p1.x += 1.0
		if Input.is_key_pressed(KEY_W): axis_p1.y += 1.0
		if Input.is_key_pressed(KEY_S): axis_p1.y -= 1.0
		jump_p1 = Input.is_key_pressed(KEY_SPACE)

		if game_state.num_players >= 2:
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
	game_state.update(dt, axis_p1, axis_p2, jump_p1, jump_p2)

	# Update visuals
	_update_floor()
	_update_player()
	_update_walls()
	_update_camera(dt)
	_check_particles()

	# Handle ESC / R key
	if game_state.game_state == Constants.STATE_PLAYING:
		if Input.is_key_pressed(KEY_ESCAPE):
			game_state.reset_to_menu()
			get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	if game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
		if Input.is_key_pressed(KEY_R):
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
	# Floor is 144 units long. Keep it centered around the player's local area.
	# The floor mesh is in local (camera-relative) space, so we just keep it
	# positioned so the player is always on it.
	floor_mesh.position = Vector3(0, -9.2, 67.5)

func _update_player() -> void:
	if game_state.game_state == Constants.STATE_MENU:
		player_node.visible = false
		return

	player_node.visible = true
	var pc: PlayerController = player_node as PlayerController
	if pc:
		pc.update_from_state(game_state)

func _update_walls() -> void:
	if game_state.game_state == Constants.STATE_MENU:
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

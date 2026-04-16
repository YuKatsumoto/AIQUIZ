extends Node3D
class_name PlayerController

## ブロック人間プレイヤー (関節付き階層モデル)
## Python版 renderer.py の _draw_player_alive / _draw_player_exploding に相当

# Player colors
const P1_BODY := Color(0.95, 0.55, 0.20)
const P1_HEAD := Color(0.95, 0.65, 0.35)
const P1_LIMB := Color(0.85, 0.48, 0.18)

const P2_BODY := Color(0.20, 0.65, 0.90)
const P2_HEAD := Color(0.30, 0.75, 0.95)
const P2_LIMB := Color(0.15, 0.55, 0.80)

var p1_parts := {}
var p2_parts := {}
var p2_container: Node3D

var _p1_exploding: bool = false
var _p2_exploding: bool = false
var _p1_explosion_data: Array[Dictionary] = []
var _p2_explosion_data: Array[Dictionary] = []

var _time: float = 0.0
const BASE_Y: float = -1.2

func _ready() -> void:
	p1_parts = _build_player_skeleton(true, self)

# 階層構造の構築
func _build_player_skeleton(is_p1: bool, parent_node: Node3D) -> Dictionary:
	var body_col: Color = P1_BODY if is_p1 else P2_BODY
	var head_col: Color = P1_HEAD if is_p1 else P2_HEAD
	var limb_col: Color = P1_LIMB if is_p1 else P2_LIMB

	var parts := {}

	# Pelvis (Root for all animations)
	var pelvis = Node3D.new()
	pelvis.name = "Pelvis"
	pelvis.position = Vector3(0, BASE_Y + 0.9, 0)
	parent_node.add_child(pelvis)
	parts["pelvis"] = pelvis

	# Torso
	var torso = _create_box(Vector3(0.38, 0.45, 0.22), body_col)
	torso.position = Vector3(0, 0.3, 0) # Center of torso relative to pelvis
	pelvis.add_child(torso)
	parts["torso"] = torso

	# Head
	var head_pivot = Node3D.new()
	head_pivot.position = Vector3(0, 0.75, 0) # Neck
	pelvis.add_child(head_pivot)
	parts["head_pivot"] = head_pivot

	var head = _create_box(Vector3(0.22, 0.22, 0.22), head_col)
	head.position = Vector3(0, 0.22, 0)
	head_pivot.add_child(head)
	parts["head"] = head

	# --- Left Arm ---
	var l_shoulder = Node3D.new()
	l_shoulder.position = Vector3(-0.52, 0.65, 0)
	pelvis.add_child(l_shoulder)
	parts["l_shoulder"] = l_shoulder

	var l_upp_arm = _create_box(Vector3(0.12, 0.20, 0.14), limb_col)
	l_upp_arm.position = Vector3(0, -0.20, 0)
	l_shoulder.add_child(l_upp_arm)
	parts["l_upp_arm"] = l_upp_arm

	var l_elbow = Node3D.new()
	l_elbow.position = Vector3(0, -0.40, 0)
	l_shoulder.add_child(l_elbow)
	parts["l_elbow"] = l_elbow

	var l_low_arm = _create_box(Vector3(0.10, 0.20, 0.12), limb_col)
	l_low_arm.position = Vector3(0, -0.20, 0)
	l_elbow.add_child(l_low_arm)
	parts["l_low_arm"] = l_low_arm

	# --- Right Arm ---
	var r_shoulder = Node3D.new()
	r_shoulder.position = Vector3(0.52, 0.65, 0)
	pelvis.add_child(r_shoulder)
	parts["r_shoulder"] = r_shoulder

	var r_upp_arm = _create_box(Vector3(0.12, 0.20, 0.14), limb_col)
	r_upp_arm.position = Vector3(0, -0.20, 0)
	r_shoulder.add_child(r_upp_arm)
	parts["r_upp_arm"] = r_upp_arm

	var r_elbow = Node3D.new()
	r_elbow.position = Vector3(0, -0.40, 0)
	r_shoulder.add_child(r_elbow)
	parts["r_elbow"] = r_elbow

	var r_low_arm = _create_box(Vector3(0.10, 0.20, 0.12), limb_col)
	r_low_arm.position = Vector3(0, -0.20, 0)
	r_elbow.add_child(r_low_arm)
	parts["r_low_arm"] = r_low_arm

	# --- Left Leg ---
	var l_hip = Node3D.new()
	l_hip.position = Vector3(-0.22, 0.0, 0)
	pelvis.add_child(l_hip)
	parts["l_hip"] = l_hip

	var l_thigh = _create_box(Vector3(0.18, 0.225, 0.18), limb_col)
	l_thigh.position = Vector3(0, -0.225, 0)
	l_hip.add_child(l_thigh)
	parts["l_thigh"] = l_thigh

	var l_knee = Node3D.new()
	l_knee.position = Vector3(0, -0.45, 0)
	l_hip.add_child(l_knee)
	parts["l_knee"] = l_knee

	var l_calf = _create_box(Vector3(0.16, 0.225, 0.16), limb_col)
	l_calf.position = Vector3(0, -0.225, 0)
	l_knee.add_child(l_calf)
	parts["l_calf"] = l_calf

	# --- Right Leg ---
	var r_hip = Node3D.new()
	r_hip.position = Vector3(0.22, 0.0, 0)
	pelvis.add_child(r_hip)
	parts["r_hip"] = r_hip

	var r_thigh = _create_box(Vector3(0.18, 0.225, 0.18), limb_col)
	r_thigh.position = Vector3(0, -0.225, 0)
	r_hip.add_child(r_thigh)
	parts["r_thigh"] = r_thigh

	var r_knee = Node3D.new()
	r_knee.position = Vector3(0, -0.45, 0)
	r_hip.add_child(r_knee)
	parts["r_knee"] = r_knee

	var r_calf = _create_box(Vector3(0.16, 0.225, 0.16), limb_col)
	r_calf.position = Vector3(0, -0.225, 0)
	r_knee.add_child(r_calf)
	parts["r_calf"] = r_calf

	# Add all meshes to a list for easy vis clipping
	parts["meshes"] = [torso, head, l_upp_arm, l_low_arm, r_upp_arm, r_low_arm, l_thigh, l_calf, r_thigh, r_calf]

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

func _process(dt: float) -> void:
	_time += dt

func update_from_state(gs: QuizGameState) -> void:
	var pz: float = gs.player_z
	var walk_phase: float = _time * 8.0

	# Ensure P2 is created if needed
	if gs.num_players >= 2 and p2_container == null:
		p2_container = Node3D.new()
		p2_container.name = "Player2"
		add_child(p2_container)
		p2_parts = _build_player_skeleton(false, p2_container)
	if gs.num_players < 2 and p2_container != null:
		p2_container.queue_free()
		p2_container = null
		p2_parts.clear()

	# --- Player 1 ---
	position = Vector3(gs.player_x, gs.player_y, gs.player_local_z)
	
	if gs.p1_alive:
		_p1_exploding = false
		_set_parts_visible(p1_parts, true)
		_animate_skeleton(p1_parts, gs.player_y, gs.player_vel_y, gs.game_state == Constants.STATE_PLAYING, walk_phase, false)
	elif gs.game_over_timer > 0:
		if gs.game_over_timer < 2.0:
			_set_parts_visible(p1_parts, true)
			_animate_struggle(p1_parts, gs.game_over_timer)
		else:
			if not _p1_exploding:
				_p1_exploding = true
				_init_explosion(p1_parts, true)
			_set_parts_visible(p1_parts, false)
			_update_explosion(true, gs.game_over_timer - 2.0)
	else:
		_set_parts_visible(p1_parts, false)

	# --- Player 2 ---
	if gs.num_players >= 2 and p2_container:
		p2_container.position = Vector3(gs.player2_x - gs.player_x, gs.player2_y - gs.player_y, gs.player2_local_z - gs.player_local_z)
		
		if gs.p2_alive:
			_p2_exploding = false
			_set_parts_visible(p2_parts, true)
			_animate_skeleton(p2_parts, gs.player2_y, gs.player2_vel_y, gs.game_state == Constants.STATE_PLAYING, walk_phase * 1.1, true)
		elif gs.player2_game_over_timer > 0:
			if gs.player2_game_over_timer < 2.0:
				_set_parts_visible(p2_parts, true)
				_animate_struggle(p2_parts, gs.player2_game_over_timer)
			else:
				if not _p2_exploding:
					_p2_exploding = true
					_init_explosion(p2_parts, false)
				_set_parts_visible(p2_parts, false)
				_update_explosion(false, gs.player2_game_over_timer - 2.0)
		else:
			_set_parts_visible(p2_parts, false)

	# 1P: only show player body during game over explosion, or 2P mode
	if gs.num_players == 1:
		if gs.game_state == Constants.STATE_GAME_OVER and gs.game_over_timer > 0:
			visible = true
		elif gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_CORRECT, Constants.STATE_PRELOADING]:
			visible = false
		else:
			visible = false

func _set_parts_visible(parts: Dictionary, vis: bool) -> void:
	if not parts or not parts.has("meshes"): return
	for mesh: MeshInstance3D in parts["meshes"]:
		if mesh: mesh.visible = vis

func _animate_skeleton(parts: Dictionary, py: float, vy: float, is_playing: bool, phase: float, is_p2: bool) -> void:
	var pelvis: Node3D = parts["pelvis"]
	var head: Node3D = parts["head_pivot"]
	var l_shoulder: Node3D = parts["l_shoulder"]
	var r_shoulder: Node3D = parts["r_shoulder"]
	var l_elbow: Node3D = parts["l_elbow"]
	var r_elbow: Node3D = parts["r_elbow"]
	var l_hip: Node3D = parts["l_hip"]
	var r_hip: Node3D = parts["r_hip"]
	var l_knee: Node3D = parts["l_knee"]
	var r_knee: Node3D = parts["r_knee"]

	# Base resets
	pelvis.position = Vector3(0, BASE_Y + 0.9, 0)
	pelvis.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	l_shoulder.rotation = Vector3.ZERO
	r_shoulder.rotation = Vector3.ZERO
	l_elbow.rotation = Vector3.ZERO
	r_elbow.rotation = Vector3.ZERO
	l_hip.rotation = Vector3.ZERO
	r_hip.rotation = Vector3.ZERO
	l_knee.rotation = Vector3.ZERO
	r_knee.rotation = Vector3.ZERO
	
	if py < -1.0:
		# Flail
		var flail := sin(_time * 25.0) * PI * 0.4
		l_hip.rotation.x = flail
		r_hip.rotation.x = -flail
		l_shoulder.rotation.x = PI + flail
		r_shoulder.rotation.x = PI - flail
		var ang_speed = 5.0 if not is_p2 else 6.0
		pelvis.rotation.y = _time * ang_speed
	elif py > 0.01:
		# Jump
		if vy > 0.0:
			l_hip.rotation.x = -PI / 4.0
			l_knee.rotation.x = PI / 4.0
			r_hip.rotation.x = 0.0
			r_knee.rotation.x = PI / 8.0
			l_shoulder.rotation.x = PI / 1.5
			r_shoulder.rotation.x = PI / 1.5
			l_elbow.rotation.x = -PI / 4.0
			r_elbow.rotation.x = -PI / 4.0
		else:
			l_hip.rotation.x = 0.0
			l_knee.rotation.x = 0.0
			r_hip.rotation.x = 0.0
			r_knee.rotation.x = 0.0
			l_shoulder.rotation.x = PI / 3.0
			r_shoulder.rotation.x = PI / 3.0
			l_elbow.rotation.x = -PI / 6.0
			r_elbow.rotation.x = -PI / 6.0
	else:
		# Run/Stand
		var swing: float = 0.0
		if is_playing:
			swing = sin(phase)
			var bob: float = abs(cos(phase)) * 0.15 # Bobbing
			pelvis.position.y = BASE_Y + 0.9 + bob
			pelvis.rotation.x = 0.15 # Forward lean
			head.rotation.x = -0.1 # Keep head looking up
			
			# Hips
			l_hip.rotation.x = swing * 0.6
			r_hip.rotation.x = -swing * 0.6
			
			# Knees (bend when leg is going backward -> positive swing)
			l_knee.rotation.x = clampf(-swing * 0.8, 0.0, PI/2.0)
			r_knee.rotation.x = clampf(swing * 0.8, 0.0, PI/2.0)
			
			# Shoulders
			l_shoulder.rotation.x = -swing * 0.7
			r_shoulder.rotation.x = swing * 0.7
			
			# Elbows
			l_elbow.rotation.x = -PI/4.0 + clampf(-swing * 0.2, -PI/8.0, 0.0)
			r_elbow.rotation.x = -PI/4.0 + clampf(swing * 0.2, -PI/8.0, 0.0)

func _animate_struggle(parts: Dictionary, timer: float) -> void:
	var pelvis: Node3D = parts["pelvis"]
	var l_shoulder: Node3D = parts["l_shoulder"]
	var r_shoulder: Node3D = parts["r_shoulder"]
	var l_elbow: Node3D = parts["l_elbow"]
	var r_elbow: Node3D = parts["r_elbow"]
	var l_hip: Node3D = parts["l_hip"]
	var r_hip: Node3D = parts["r_hip"]
	var l_knee: Node3D = parts["l_knee"]
	var r_knee: Node3D = parts["r_knee"]

	var decay: float = 1.0 - (timer / 2.0)
	var fast: float = sin(_time * 18.0) * decay
	var slow: float = sin(_time * 7.0) * decay
	
	pelvis.position = Vector3(0, BASE_Y + 0.9, 0)
	pelvis.rotation = Vector3(0, sin(_time * 4.0) * decay * 0.3, slow * 0.25)
	
	l_shoulder.rotation.x = -PI * 0.8 + fast * PI * 0.5
	r_shoulder.rotation.x = -PI * 0.8 - fast * PI * 0.5
	l_shoulder.rotation.z = slow * 0.4
	r_shoulder.rotation.z = -slow * 0.4
	
	l_elbow.rotation.x = -0.2
	r_elbow.rotation.x = -0.2
	
	l_hip.rotation.x = fast * 0.6
	r_hip.rotation.x = -fast * 0.6
	l_knee.rotation.x = 0.5
	r_knee.rotation.x = 0.5

func _init_explosion(parts: Dictionary, is_p1: bool) -> void:
	if not parts or not parts.has("meshes"): return
	
	var exp_data: Array[Dictionary] = []
	for mesh: MeshInstance3D in parts["meshes"]:
		var gt = mesh.global_transform
		var old_parent = mesh.get_parent()
		if old_parent != self:
			old_parent.remove_child(mesh)
			self.add_child(mesh)
			mesh.global_transform = gt
			
		var gx = mesh.global_position.x - self.global_position.x
		var sx = 1.0 if gx >= 0 else -1.0
		
		var vel = Vector3(sx * randf_range(2.0, 6.0), randf_range(4.0, 9.0), randf_range(-3.0, 3.0))
		var rot_vel = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
		
		exp_data.append({
			"node": mesh,
			"base_pos": mesh.position,
			"base_rot": mesh.rotation,
			"velocity": vel,
			"rot_velocity": rot_vel
		})
		
	if is_p1:
		_p1_explosion_data = exp_data
	else:
		_p2_explosion_data = exp_data

func _update_explosion(is_p1: bool, timer: float) -> void:
	var data = _p1_explosion_data if is_p1 else _p2_explosion_data
	var gravity = 15.0
	
	for d: Dictionary in data:
		var node: MeshInstance3D = d["node"]
		var base: Vector3 = d["base_pos"]
		var brot: Vector3 = d["base_rot"]
		var vel: Vector3 = d["velocity"]
		var rot_vel: Vector3 = d["rot_velocity"]
		
		var ey = base.y + vel.y * timer - 0.5 * gravity * timer * timer
		ey = maxf(BASE_Y + 0.1, ey)
		var ex = base.x + vel.x * timer
		var ez = base.z + vel.z * timer
		
		node.position = Vector3(ex, ey, ez)
		node.rotation = brot + rot_vel * timer
		node.visible = true

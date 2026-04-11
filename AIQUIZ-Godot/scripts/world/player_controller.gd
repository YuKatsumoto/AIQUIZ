extends Node3D
class_name PlayerController

## ブロック人間プレイヤー (6パーツ)
## Python版 renderer.py の _draw_player_alive / _draw_player_exploding に相当

# Player colors
const P1_BODY := Color(0.95, 0.55, 0.20)
const P1_HEAD := Color(0.95, 0.65, 0.35)
const P1_LIMB := Color(0.85, 0.48, 0.18)

const P2_BODY := Color(0.20, 0.65, 0.90)
const P2_HEAD := Color(0.30, 0.75, 0.95)
const P2_LIMB := Color(0.15, 0.55, 0.80)

# Node references (set in _ready)
var head: MeshInstance3D
var torso: MeshInstance3D
var left_arm: MeshInstance3D
var right_arm: MeshInstance3D
var left_leg: MeshInstance3D
var right_leg: MeshInstance3D

# Player 2 parts (created dynamically for 2P)
var p2_head: MeshInstance3D
var p2_torso: MeshInstance3D
var p2_left_arm: MeshInstance3D
var p2_right_arm: MeshInstance3D
var p2_left_leg: MeshInstance3D
var p2_right_leg: MeshInstance3D
var p2_container: Node3D

# Explosion state
var _p1_exploding: bool = false
var _p2_exploding: bool = false
var _p1_explosion_parts: Array[Dictionary] = []
var _p2_explosion_parts: Array[Dictionary] = []

var _time: float = 0.0
const BASE_Y: float = -1.2

func _ready() -> void:
	_build_player_body(true)

func _build_player_body(is_p1: bool) -> void:
	var body_col: Color = P1_BODY if is_p1 else P2_BODY
	var head_col: Color = P1_HEAD if is_p1 else P2_HEAD
	var limb_col: Color = P1_LIMB if is_p1 else P2_LIMB

	if is_p1:
		# Left Leg
		left_leg = _create_box(Vector3(0.18, 0.45, 0.18), limb_col)
		left_leg.position = Vector3(-0.22, BASE_Y + 0.45, 0)
		add_child(left_leg)
		# Right Leg
		right_leg = _create_box(Vector3(0.18, 0.45, 0.18), limb_col)
		right_leg.position = Vector3(0.22, BASE_Y + 0.45, 0)
		add_child(right_leg)
		# Torso
		torso = _create_box(Vector3(0.38, 0.45, 0.22), body_col)
		torso.position = Vector3(0, BASE_Y + 1.20, 0)
		add_child(torso)
		# Left Arm
		left_arm = _create_box(Vector3(0.12, 0.40, 0.14), limb_col)
		left_arm.position = Vector3(-0.52, BASE_Y + 1.15, 0)
		add_child(left_arm)
		# Right Arm
		right_arm = _create_box(Vector3(0.12, 0.40, 0.14), limb_col)
		right_arm.position = Vector3(0.52, BASE_Y + 1.15, 0)
		add_child(right_arm)
		# Head
		head = _create_box(Vector3(0.22, 0.22, 0.22), head_col)
		head.position = Vector3(0, BASE_Y + 1.87, 0)
		add_child(head)
	else:
		p2_container = Node3D.new()
		p2_container.name = "Player2"
		add_child(p2_container)
		p2_left_leg = _create_box(Vector3(0.18, 0.45, 0.18), limb_col)
		p2_left_leg.position = Vector3(-0.22, BASE_Y + 0.45, 0)
		p2_container.add_child(p2_left_leg)
		p2_right_leg = _create_box(Vector3(0.18, 0.45, 0.18), limb_col)
		p2_right_leg.position = Vector3(0.22, BASE_Y + 0.45, 0)
		p2_container.add_child(p2_right_leg)
		p2_torso = _create_box(Vector3(0.38, 0.45, 0.22), body_col)
		p2_torso.position = Vector3(0, BASE_Y + 1.20, 0)
		p2_container.add_child(p2_torso)
		p2_left_arm = _create_box(Vector3(0.12, 0.40, 0.14), limb_col)
		p2_left_arm.position = Vector3(-0.52, BASE_Y + 1.15, 0)
		p2_container.add_child(p2_left_arm)
		p2_right_arm = _create_box(Vector3(0.12, 0.40, 0.14), limb_col)
		p2_right_arm.position = Vector3(0.52, BASE_Y + 1.15, 0)
		p2_container.add_child(p2_right_arm)
		p2_head = _create_box(Vector3(0.22, 0.22, 0.22), head_col)
		p2_head.position = Vector3(0, BASE_Y + 1.87, 0)
		p2_container.add_child(p2_head)

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
		_build_player_body(false)
	if gs.num_players < 2 and p2_container != null:
		p2_container.queue_free()
		p2_container = null

	# --- Player 1 ---
	position = Vector3(gs.player_x, gs.player_y, gs.player_local_z)
	
	if gs.p1_alive:
		_p1_exploding = false
		_set_parts_visible(true, true)

		# Walking / Jumping animation
		if gs.player_y < -1.0:
			var flail := sin(_time * 25.0) * PI * 0.4
			left_leg.rotation.x = flail
			right_leg.rotation.x = -flail
			left_arm.rotation.x = PI + flail
			right_arm.rotation.x = PI - flail
			rotation.y = _time * 5.0
		elif gs.player_y > 0.01:
			rotation.y = 0.0
			if gs.player_vel_y > 0.0:
				# Jump UP
				left_leg.rotation.x = -PI / 4.0
				right_leg.rotation.x = 0.0
				left_arm.rotation.x = PI / 1.5
				right_arm.rotation.x = PI / 1.5
			else:
				# Fall down
				left_leg.rotation.x = 0.0
				right_leg.rotation.x = 0.0
				left_arm.rotation.x = PI / 3.0
				right_arm.rotation.x = PI / 3.0
		else:
			rotation.y = 0.0
			var swing: float = 0.0
			if gs.game_state == Constants.STATE_PLAYING:
				swing = sin(walk_phase) * 0.35
			left_leg.rotation.x = swing
			right_leg.rotation.x = -swing
			left_arm.rotation.x = -swing * 0.7
			right_arm.rotation.x = swing * 0.7
	elif gs.game_over_timer > 0:
		if gs.game_over_timer < 2.0:
			# Freeze on wall during camera drop
			_set_parts_visible(true, true)
		else:
			if not _p1_exploding:
				_p1_exploding = true
				_init_explosion_parts(true, gs.player_x, pz)
			_set_parts_visible(false, true)
			_update_explosion(true, gs.game_over_timer - 2.0)
	else:
		_set_parts_visible(false, true)

	# --- Player 2 ---
	if gs.num_players >= 2 and p2_container:
		p2_container.position = Vector3(gs.player2_x - gs.player_x, gs.player2_y - gs.player_y, gs.player2_local_z - gs.player_local_z)
		
		if gs.p2_alive:
			_p2_exploding = false
			_set_parts_visible(true, false)
			if gs.player2_y < -1.0:
				var flail := sin(_time * 25.0) * PI * 0.4
				p2_left_leg.rotation.x = flail
				p2_right_leg.rotation.x = -flail
				p2_left_arm.rotation.x = PI + flail
				p2_right_arm.rotation.x = PI - flail
				p2_container.rotation.y = _time * 5.0
			elif gs.player2_y > 0.01:
				p2_container.rotation.y = 0.0
				if gs.player2_vel_y > 0.0:
					p2_left_leg.rotation.x = -PI / 4.0
					p2_right_leg.rotation.x = 0.0
					p2_left_arm.rotation.x = PI / 1.5
					p2_right_arm.rotation.x = PI / 1.5
				else:
					p2_left_leg.rotation.x = 0.0
					p2_right_leg.rotation.x = 0.0
					p2_left_arm.rotation.x = PI / 3.0
					p2_right_arm.rotation.x = PI / 3.0
			else:
				p2_container.rotation.y = 0.0
				var swing2: float = 0.0
				if gs.game_state == Constants.STATE_PLAYING:
					swing2 = sin(walk_phase * 1.1) * 0.35
				p2_left_leg.rotation.x = swing2
				p2_right_leg.rotation.x = -swing2
				p2_left_arm.rotation.x = -swing2 * 0.7
				p2_right_arm.rotation.x = swing2 * 0.7
		elif gs.player2_game_over_timer > 0:
			if gs.player2_game_over_timer < 2.0:
				_set_parts_visible(true, false)
			else:
				if not _p2_exploding:
					_p2_exploding = true
					_init_explosion_parts(false, gs.player2_x, pz)
				_set_parts_visible(false, false)
				_update_explosion(false, gs.player2_game_over_timer - 2.0)
		else:
			_set_parts_visible(false, false)



	# 1P: only show player body during game over explosion, or 2P mode
	if gs.num_players == 1:
		if gs.game_state == Constants.STATE_GAME_OVER and gs.game_over_timer > 0:
			visible = true
		elif gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_CORRECT, Constants.STATE_PRELOADING]:
			visible = (gs.num_players >= 2)  # hide in 1P FPS
		else:
			visible = false

func _set_parts_visible(vis: bool, is_p1: bool) -> void:
	if is_p1:
		if head: head.visible = vis
		if torso: torso.visible = vis
		if left_arm: left_arm.visible = vis
		if right_arm: right_arm.visible = vis
		if left_leg: left_leg.visible = vis
		if right_leg: right_leg.visible = vis
	else:
		if p2_container:
			p2_container.visible = vis

# --- Explosion ---

func _init_explosion_parts(is_p1: bool, px: float, pz: float) -> void:
	# Each part: { node, base_pos, velocity, rot_velocity }
	var parts: Array[Dictionary] = []
	var part_data: Array[Array]

	if is_p1:
		part_data = [
			[left_leg, Vector3(-0.22, BASE_Y + 0.45, 0), Vector3(-3, 8, -2), Vector3(3, 1, -2)],
			[right_leg, Vector3(0.22, BASE_Y + 0.45, 0), Vector3(3, 7.5, 2), Vector3(-2.5, 2, 1.5)],
			[torso, Vector3(0, BASE_Y + 1.20, 0), Vector3(0.5, 6, 4), Vector3(1, -1.5, 0.5)],
			[left_arm, Vector3(-0.52, BASE_Y + 1.15, 0), Vector3(-6, 9, 1), Vector3(-4, -2, 3)],
			[right_arm, Vector3(0.52, BASE_Y + 1.15, 0), Vector3(5, 10, -1.5), Vector3(2, 4, -1)],
			[head, Vector3(0, BASE_Y + 1.87, 0), Vector3(-1, 12, 3), Vector3(5, 3, 2)],
		]
	else:
		if not p2_container:
			return
		part_data = [
			[p2_left_leg, Vector3(-0.22, BASE_Y + 0.45, 0), Vector3(-3, 8, -2), Vector3(3, 1, -2)],
			[p2_right_leg, Vector3(0.22, BASE_Y + 0.45, 0), Vector3(3, 7.5, 2), Vector3(-2.5, 2, 1.5)],
			[p2_torso, Vector3(0, BASE_Y + 1.20, 0), Vector3(0.5, 6, 4), Vector3(1, -1.5, 0.5)],
			[p2_left_arm, Vector3(-0.52, BASE_Y + 1.15, 0), Vector3(-6, 9, 1), Vector3(-4, -2, 3)],
			[p2_right_arm, Vector3(0.52, BASE_Y + 1.15, 0), Vector3(5, 10, -1.5), Vector3(2, 4, -1)],
			[p2_head, Vector3(0, BASE_Y + 1.87, 0), Vector3(-1, 12, 3), Vector3(5, 3, 2)],
		]

	for pd: Array in part_data:
		parts.append({
			"node": pd[0],
			"base_pos": pd[1],
			"velocity": pd[2],
			"rot_velocity": pd[3],
		})

	if is_p1:
		_p1_explosion_parts = parts
	else:
		_p2_explosion_parts = parts

func _update_explosion(is_p1: bool, timer: float) -> void:
	var parts: Array[Dictionary] = _p1_explosion_parts if is_p1 else _p2_explosion_parts
	const GRAVITY: float = 15.0

	for part: Dictionary in parts:
		var node: MeshInstance3D = part["node"]
		var base: Vector3 = part["base_pos"]
		var vel: Vector3 = part["velocity"]
		var rot_vel: Vector3 = part["rot_velocity"]

		var ey: float = base.y + vel.y * timer - 0.5 * GRAVITY * timer * timer
		ey = maxf(BASE_Y + 0.1, ey)
		var ex: float = base.x + vel.x * timer
		var ez: float = base.z + vel.z * timer

		node.position = Vector3(ex, ey, ez)
		node.rotation = rot_vel * timer
		node.visible = true

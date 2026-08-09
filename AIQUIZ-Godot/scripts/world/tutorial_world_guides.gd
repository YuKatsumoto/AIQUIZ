extends Node3D
class_name TutorialWorldGuides

const P1_COLOR := Color(1.0, 0.48, 0.12, 1.0)
const P2_COLOR := Color(0.18, 0.88, 1.0, 1.0)
const GUIDE_COLOR := Color(1.0, 0.86, 0.18, 1.0)
const DANGER_COLOR := Color(1.0, 0.18, 0.20, 1.0)

var game_state: QuizGameState = null
var _time: float = 0.0
var _p1_ring: MeshInstance3D = null
var _p2_ring: MeshInstance3D = null
var _p1_arrow: MeshInstance3D = null
var _p2_arrow: MeshInstance3D = null
var _screen_arrow_layer: CanvasLayer = null
var _p1_screen_arrow: Label = null
var _p2_screen_arrow: Label = null
var _p1_label: Label3D = null
var _p2_label: Label3D = null
var _door_frame: Node3D = null
var _danger_stripe: MeshInstance3D = null
var _goal_beacon: MeshInstance3D = null
var _guide_label: Label3D = null
var _route_path: Node3D = null
var _materials: Array[StandardMaterial3D] = []

const ROUTE_DASH_COUNT := 14


func setup(state: QuizGameState) -> void:
	game_state = state
	_build_guides()


func update(delta: float) -> void:
	_time += delta
	if game_state == null or game_state.mode != Constants.MODE_TUTORIAL:
		visible = false
		_hide_screen_arrows()
		_set_route_path_visible(false)
		return
	visible = game_state.game_state not in [
		Constants.STATE_CLEAR,
		Constants.STATE_GAME_OVER,
		Constants.STATE_PRELOADING,
		Constants.STATE_WAITING_START,
		Constants.STATE_FLYOVER,
		Constants.STATE_COUNTDOWN,
	]
	if not visible:
		_hide_screen_arrows()
		_set_route_path_visible(false)
		return
	var model := game_state.get_tutorial_overlay_model()
	var guide := str(model.get("world_guide", ""))
	var pulse := 0.72 + 0.28 * sin(_time * 4.5)
	for material: StandardMaterial3D in _materials:
		material.emission_energy_multiplier = 1.3 + pulse * 1.8

	_update_player_guide(1, _p1_ring, _p1_arrow, model, guide)
	_update_player_guide(2, _p2_ring, _p2_arrow, model, guide)
	_update_screen_arrow(1, _p1_screen_arrow, model, guide)
	_update_screen_arrow(2, _p2_screen_arrow, model, guide)
	_update_player_labels(guide)
	_update_door_guide(model, guide, pulse)
	_update_danger_guide(guide, pulse)
	_update_goal_guide(guide, pulse)


func _build_guides() -> void:
	_p1_ring = _create_ring(P1_COLOR)
	_p1_ring.name = "P1SelectionRing"
	add_child(_p1_ring)
	_p2_ring = _create_ring(P2_COLOR)
	_p2_ring.name = "P2SelectionRing"
	add_child(_p2_ring)
	_p1_arrow = _create_arrow(P1_COLOR)
	_p1_arrow.name = "P1DirectionArrow"
	add_child(_p1_arrow)
	_p2_arrow = _create_arrow(P2_COLOR)
	_p2_arrow.name = "P2DirectionArrow"
	add_child(_p2_arrow)
	_screen_arrow_layer = CanvasLayer.new()
	_screen_arrow_layer.name = "TutorialScreenArrows"
	_screen_arrow_layer.layer = 4
	add_child(_screen_arrow_layer)
	_p1_screen_arrow = _create_screen_arrow(P1_COLOR)
	_p1_screen_arrow.name = "P1ScreenDirectionArrow"
	_screen_arrow_layer.add_child(_p1_screen_arrow)
	_p2_screen_arrow = _create_screen_arrow(P2_COLOR)
	_p2_screen_arrow.name = "P2ScreenDirectionArrow"
	_screen_arrow_layer.add_child(_p2_screen_arrow)
	_p1_label = _create_player_label("P1", P1_COLOR)
	_p1_label.name = "P1TutorialLabel"
	add_child(_p1_label)
	_p2_label = _create_player_label("P2", P2_COLOR)
	_p2_label.name = "P2TutorialLabel"
	add_child(_p2_label)

	_door_frame = Node3D.new()
	_door_frame.name = "DoorHighlightFrame"
	add_child(_door_frame)
	var frame_material := _create_material(GUIDE_COLOR)
	for frame_part: Dictionary in [
		{"size": Vector3(0.16, 3.8, 0.16), "position": Vector3(-1.8, 1.9, 0.0)},
		{"size": Vector3(0.16, 3.8, 0.16), "position": Vector3(1.8, 1.9, 0.0)},
		{"size": Vector3(3.76, 0.16, 0.16), "position": Vector3(0.0, 3.72, 0.0)},
	]:
		var part := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = frame_part["size"]
		part.mesh = box
		part.position = frame_part["position"]
		part.material_override = frame_material
		_door_frame.add_child(part)

	_danger_stripe = MeshInstance3D.new()
	_danger_stripe.name = "DangerStripe"
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(5.2, 0.05, 1.15)
	_danger_stripe.mesh = stripe_mesh
	_danger_stripe.material_override = _create_material(DANGER_COLOR)
	add_child(_danger_stripe)

	_route_path = Node3D.new()
	_route_path.name = "HazardRoutePath"
	_route_path.visible = false
	add_child(_route_path)
	var route_material := _create_material(GUIDE_COLOR)
	for _i in ROUTE_DASH_COUNT:
		var dash := MeshInstance3D.new()
		var dash_mesh := BoxMesh.new()
		dash_mesh.size = Vector3(0.16, 0.05, 0.42)
		dash.mesh = dash_mesh
		dash.material_override = route_material
		_route_path.add_child(dash)

	_goal_beacon = MeshInstance3D.new()
	_goal_beacon.name = "GoalBeacon"
	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.12
	beacon_mesh.bottom_radius = 0.55
	beacon_mesh.height = 7.0
	_goal_beacon.mesh = beacon_mesh
	_goal_beacon.material_override = _create_material(GUIDE_COLOR)
	add_child(_goal_beacon)

	_guide_label = Label3D.new()
	_guide_label.name = "TutorialGuideLabel"
	_guide_label.font_size = 48
	_guide_label.pixel_size = 0.008
	_guide_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_guide_label.modulate = GUIDE_COLOR
	_guide_label.outline_modulate = Color(0.02, 0.03, 0.08, 0.95)
	_guide_label.outline_size = 10
	add_child(_guide_label)


func _update_player_guide(
		player_index: int,
		ring: MeshInstance3D,
		arrow: MeshInstance3D,
		model: Dictionary,
		guide: String) -> void:
	var enabled := player_index == 1 or game_state.num_players >= 2
	var player_position := _player_position(player_index)
	ring.visible = enabled and guide in ["player", "players", "controls"]
	ring.position = Vector3(player_position.x, StageConstants.FLOOR_TOP_Y + 0.05, player_position.z)
	arrow.visible = enabled and guide == "controls" and game_state.num_players < 2
	arrow.position = Vector3(player_position.x, StageConstants.FLOOR_TOP_Y + 0.07, player_position.z + 1.8)
	arrow.scale = Vector3.ONE
	if not arrow.visible:
		return
	var task_id := _first_pending_task(model, player_index)
	match task_id:
		"left":
			arrow.rotation.y = PI * 0.5
		"right":
			arrow.rotation.y = -PI * 0.5
		"back":
			arrow.rotation.y = PI
		_:
			arrow.rotation.y = 0.0


func _update_screen_arrow(
		player_index: int,
		arrow: Label,
		model: Dictionary,
		guide: String) -> void:
	arrow.visible = false
	if game_state.num_players < 2 or guide != "controls":
		return
	var arrow_text := _screen_arrow_text(_first_pending_task(model, player_index))
	if arrow_text.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var head_position := _player_position(player_index) + Vector3(0.0, 2.2, 0.0)
	if camera.is_position_behind(head_position):
		return
	var screen_position := camera.unproject_position(head_position)
	var safe_rect := get_viewport().get_visible_rect().grow(-24.0)
	if not safe_rect.has_point(screen_position):
		return
	arrow.text = arrow_text
	arrow.position = screen_position - arrow.size * 0.5
	arrow.visible = true


func _screen_arrow_text(task_id: String) -> String:
	match task_id:
		"left":
			return "←"
		"right":
			return "→"
		"forward":
			return "↑"
		"back":
			return "↓"
	return ""


func _hide_screen_arrows() -> void:
	if _p1_screen_arrow != null:
		_p1_screen_arrow.visible = false
	if _p2_screen_arrow != null:
		_p2_screen_arrow.visible = false


func _update_door_guide(model: Dictionary, guide: String, pulse: float) -> void:
	var answer := int(model.get("highlight_answer", -1))
	_door_frame.visible = guide == "guided_door" and answer in [0, 1]
	if not _door_frame.visible:
		return
	var door_x := game_state.tuning.left_door_x if answer == 0 else game_state.tuning.right_door_x
	_door_frame.position = Vector3(door_x, StageConstants.FLOOR_TOP_Y, game_state.wall_z - game_state.world_scroll_z - 0.5)
	_door_frame.scale = Vector3.ONE * (1.0 + pulse * 0.035)
	_guide_label.visible = true
	_guide_label.text = "正解ドア"
	_guide_label.position = _door_frame.position + Vector3(0.0, 4.5, 0.0)


func _update_player_labels(guide: String) -> void:
	var show_labels := game_state.num_players >= 2 and guide in ["players", "controls"]
	_p1_label.visible = show_labels
	_p2_label.visible = show_labels
	if not show_labels:
		return
	_p1_label.position = _player_position(1) + Vector3(0.0, 2.75, 0.0)
	_p2_label.position = _player_position(2) + Vector3(0.0, 2.75, 0.0)


func _update_danger_guide(guide: String, pulse: float) -> void:
	_danger_stripe.visible = guide in ["wall_hazard", "ocean_hazard"]
	if not _danger_stripe.visible:
		if guide not in ["guided_door", "goal"]:
			_guide_label.visible = false
		_set_route_path_visible(false)
		return
	var hazard_player := maxi(1, game_state.tutorial_flow.designated_hazard_player())
	var player_pos := _player_position(hazard_player)
	if guide == "wall_hazard":
		var wall_local_z := game_state.wall_z - game_state.world_scroll_z - 1.0
		_danger_stripe.position = Vector3(0.0, StageConstants.FLOOR_TOP_Y + 0.05, wall_local_z)
		_danger_stripe.rotation.y = 0.0
		_guide_label.text = "ここにぶつかる"
		_guide_label.position = _danger_stripe.position + Vector3(0.0, 3.0, 0.0)
		_update_wall_route_path(player_pos, wall_local_z)
	else:
		var side := 1.0 if hazard_player == 1 else -1.0
		_danger_stripe.position = Vector3(side * StageConstants.FLOOR_HALF_WIDTH, StageConstants.FLOOR_TOP_Y + 0.05, player_pos.z + 2.0)
		_danger_stripe.rotation.y = PI * 0.5
		_guide_label.text = "海へ"
		_guide_label.position = _danger_stripe.position + Vector3(side * 1.6, 2.2, 0.0)
		_set_route_path_visible(false)
	_guide_label.visible = true
	_danger_stripe.scale = Vector3.ONE * (1.0 + pulse * 0.07)


func _set_route_path_visible(enabled: bool) -> void:
	if _route_path:
		_route_path.visible = enabled


func _update_wall_route_path(player_pos: Vector3, wall_local_z: float) -> void:
	if _route_path == null:
		return
	var start := Vector3(player_pos.x, StageConstants.FLOOR_TOP_Y + 0.08, player_pos.z + 0.55)
	# 中央の壁へ向かうルート（ドアではなく中央へ誘導）
	var end := Vector3(0.0, StageConstants.FLOOR_TOP_Y + 0.08, wall_local_z + 0.35)
	var delta := end - start
	var distance := delta.length()
	if distance < 0.35:
		_set_route_path_visible(false)
		return
	_set_route_path_visible(true)
	var direction := delta / distance
	var yaw := atan2(direction.x, direction.z)
	var dashes := _route_path.get_children()
	var count := dashes.size()
	for i in count:
		var dash := dashes[i] as MeshInstance3D
		if dash == null:
			continue
		# 点線: ダッシュと隙間を交互に配置
		var t := (float(i) + 0.5) / float(count)
		dash.position = start.lerp(end, t)
		dash.rotation = Vector3(0.0, yaw, 0.0)
		dash.visible = true


func _update_goal_guide(guide: String, pulse: float) -> void:
	_goal_beacon.visible = guide in ["goal", "complete"]
	if not _goal_beacon.visible:
		return
	var goal_z := game_state.goal_z - game_state.world_scroll_z
	_goal_beacon.position = Vector3(0.0, 2.3 + pulse * 0.35, goal_z)
	_goal_beacon.scale = Vector3(1.0 + pulse * 0.08, 1.0, 1.0 + pulse * 0.08)
	_guide_label.visible = true
	_guide_label.text = "GOAL"
	_guide_label.position = Vector3(0.0, 5.8, goal_z)


func _first_pending_task(model: Dictionary, player_index: int) -> String:
	for player_variant: Variant in model.get("players", []):
		var player: Dictionary = player_variant
		if int(player.get("player", 0)) != player_index:
			continue
		for task_variant: Variant in player.get("tasks", []):
			var task: Dictionary = task_variant
			if not bool(task.get("done", false)):
				return str(task.get("id", ""))
	return ""


func _player_position(player_index: int) -> Vector3:
	if player_index == 2:
		return Vector3(game_state.player2_x, game_state.player2_y, game_state.player2_local_z)
	return Vector3(game_state.player_x, game_state.player_y, game_state.player_local_z)


func _create_ring(color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 0.92
	torus.rings = 24
	torus.ring_segments = 8
	instance.mesh = torus
	instance.material_override = _create_material(color)
	return instance


func _create_player_label(label_text: String, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = label_text
	label.font_size = 52
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.outline_modulate = Color(0.02, 0.03, 0.08, 0.98)
	label.outline_size = 12
	label.no_depth_test = true
	return label


func _create_screen_arrow(color: Color) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(38.0, 38.0)
	label.size = Vector2(38.0, 38.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.98))
	label.add_theme_constant_override("outline_size", 6)
	label.visible = false
	return label


func _create_arrow(color: Color) -> MeshInstance3D:
	var immediate := ImmediateMesh.new()
	var material := _create_material(color)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for vertex: Vector3 in [
		Vector3(0.0, 0.0, 1.45), Vector3(-0.72, 0.0, 0.25), Vector3(-0.24, 0.0, 0.25),
		Vector3(0.0, 0.0, 1.45), Vector3(-0.24, 0.0, 0.25), Vector3(0.24, 0.0, 0.25),
		Vector3(0.0, 0.0, 1.45), Vector3(0.24, 0.0, 0.25), Vector3(0.72, 0.0, 0.25),
		Vector3(-0.24, 0.0, 0.25), Vector3(-0.24, 0.0, -1.0), Vector3(0.24, 0.0, -1.0),
		Vector3(-0.24, 0.0, 0.25), Vector3(0.24, 0.0, -1.0), Vector3(0.24, 0.0, 0.25),
	]:
		immediate.surface_set_normal(Vector3.UP)
		immediate.surface_add_vertex(vertex)
	immediate.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = immediate
	return instance


func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.no_depth_test = false
	_materials.append(material)
	return material

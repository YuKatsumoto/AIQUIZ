@tool
class_name MenuHelicopterSequenceProfile
extends Node3D

## Editor-authored extraction shot. Open this scene, drag Pickup Path3D points,
## then scrub start_pickup. intro_arrival remains available for the menu drop.

const INTRO_ANIMATION: StringName = &"intro_arrival"
const PICKUP_ANIMATION: StringName = &"start_pickup"
const PhysicalRopeLadderScript := preload("res://scripts/world/physical_rope_ladder.gd")

@export_category("Fixed ground pickup positions")
@export var pickup_single_ground := Vector3(-1.5, -1.2, -4.0)
@export var pickup_left_ground := Vector3(-8.0, -1.2, -4.0)
@export var pickup_right_ground := Vector3(4.0, -1.2, -4.0)

@export_category("Animation-driven values")
@export_range(0.0, 1.0, 0.001) var p1_hatch: float = 0.0:
	set(value):
		p1_hatch = clampf(value, 0.0, 1.0)
		_apply_preview_hatch(1, p1_hatch)
@export_range(0.0, 1.0, 0.001) var p2_hatch: float = 0.0:
	set(value):
		p2_hatch = clampf(value, 0.0, 1.0)
		_apply_preview_hatch(2, p2_hatch)
@export_range(0.0, 1.0, 0.001) var p1_action_progress: float = 0.0:
	set(value):
		p1_action_progress = clampf(value, 0.0, 1.0)
@export_range(0.0, 1.0, 0.001) var p2_action_progress: float = 0.0:
	set(value):
		p2_action_progress = clampf(value, 0.0, 1.0)
@export_range(0.0, 1.0, 0.001) var p1_ladder_deploy: float = 0.0:
	set(value):
		p1_ladder_deploy = clampf(value, 0.0, 1.0)
@export_range(0.0, 1.0, 0.001) var p2_ladder_deploy: float = 0.0:
	set(value):
		p2_ladder_deploy = clampf(value, 0.0, 1.0)
@export_range(-45.0, 45.0, 0.1, "suffix:°") var p1_bank_deg: float = 0.0
@export_range(-45.0, 45.0, 0.1, "suffix:°") var p2_bank_deg: float = 0.0
@export_range(-30.0, 30.0, 0.1, "suffix:°") var p1_pitch_deg: float = 0.0
@export_range(-30.0, 30.0, 0.1, "suffix:°") var p2_pitch_deg: float = 0.0
@export_range(0.0, 30.0, 0.1, "suffix:°") var camera_fov_delta: float = 0.0
@export_range(-30.0, 30.0, 0.1, "suffix:°") var camera_tilt_deg: float = 0.0
@export var show_intro_preview := false:
	set(value):
		show_intro_preview = value
		_apply_preview_visibility()
@export var show_pickup_preview := true:
	set(value):
		show_pickup_preview = value
		_apply_preview_visibility()

var _runtime_animation: StringName = PICKUP_ANIMATION
var _runtime_time := 0.0
var _runtime_mode := false
var _hatch_bases: Dictionary = {}
var _preview_ladders: Dictionary = {}
var _preview_actors: Dictionary = {}


func _ready() -> void:
	_cache_preview_hatch_bases()
	_apply_preview_hatch(1, p1_hatch)
	_apply_preview_hatch(2, p2_hatch)
	_apply_preview_visibility()
	_ensure_preview_extraction()
	call_deferred("_start_standalone_preview")


func _process(_delta: float) -> void:
	if _runtime_mode or not is_inside_tree():
		return
	_refresh_preview_extraction()


func _start_standalone_preview() -> void:
	if _runtime_mode or not is_inside_tree():
		return
	var preview_camera := get_node_or_null("PreviewCamera") as Camera3D
	if preview_camera != null:
		preview_camera.current = true
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null and player.has_animation(PICKUP_ANIMATION):
		player.play(PICKUP_ANIMATION)
	set_process(true)


func prepare_runtime() -> void:
	_runtime_mode = true
	set_process(false)
	_clear_preview_extraction()
	var preview_camera := get_node_or_null("PreviewCamera") as Camera3D
	if preview_camera != null:
		preview_camera.current = false
	var editor_reference := get_node_or_null("EditorReference") as Node3D
	if editor_reference != null:
		editor_reference.visible = false
	_apply_preview_visibility()
	var preview_light := get_node_or_null("PreviewLight") as DirectionalLight3D
	if preview_light != null:
		preview_light.visible = false
	var preview_environment := get_node_or_null("PreviewEnvironment") as WorldEnvironment
	if preview_environment != null:
		preview_environment.environment = null


func set_player_ground(player_index: int, ground: Vector3) -> void:
	var prefix := "P1" if player_index == 1 else "P2"
	for sequence: String in ["Intro", "Pickup"]:
		var path := get_node_or_null("%s%sPath" % [sequence, prefix]) as Path3D
		if path != null:
			path.position = ground


func set_fixed_pickup_ground(player_index: int, player_count: int, left_slot: bool) -> void:
	var path := get_node_or_null("PickupP%dPath" % player_index) as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		return
	var target := pickup_single_ground if player_count == 1 else (
		pickup_left_ground if left_slot else pickup_right_ground
	)
	var outward_side := -1.0 if left_slot else 1.0
	var authored_side := -1.0 if player_index == 1 else 1.0
	path.scale.x = outward_side / authored_side
	var hover_point := path.curve.get_point_position(1)
	path.position = target - Vector3(hover_point.x * path.scale.x, 0.0, hover_point.z)


func get_pickup_clearance_z() -> float:
	return minf(pickup_single_ground.z, minf(pickup_left_ground.z, pickup_right_ground.z)) - 4.0


func get_pickup_ground_target(player_index: int) -> Vector3:
	var path := get_node_or_null("PickupP%dPath" % player_index) as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		return Vector3.ZERO
	var target := path.to_global(path.curve.get_point_position(1))
	target.y = path.global_position.y
	return target


func select_runtime_animation(animation_name: StringName) -> bool:
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null or not player.has_animation(animation_name):
		return false
	_runtime_animation = animation_name
	_runtime_time = 0.0
	player.assigned_animation = animation_name
	player.pause()
	player.seek(0.0, true, true)
	return true


func seek_runtime(time_seconds: float) -> void:
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null or not player.has_animation(_runtime_animation):
		return
	_runtime_time = clampf(time_seconds, 0.0, get_runtime_duration())
	if player.assigned_animation != _runtime_animation:
		player.assigned_animation = _runtime_animation
		player.pause()
	player.seek(_runtime_time, true, true)


func get_runtime_duration() -> float:
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null or not player.has_animation(_runtime_animation):
		return 0.0
	var animation := player.get_animation(_runtime_animation)
	return animation.length if animation != null else 0.0


func is_runtime_finished() -> bool:
	var duration := get_runtime_duration()
	return duration > 0.0 and _runtime_time >= duration - 0.0001


func get_player_state(player_index: int) -> Dictionary:
	var prefix := "P1" if player_index == 1 else "P2"
	var sequence := "Pickup" if _runtime_animation == PICKUP_ANIMATION else "Intro"
	var path := get_node_or_null("%s%sPath" % [sequence, prefix]) as Path3D
	var follow := get_node_or_null("%s%sPath/Follow" % [sequence, prefix]) as PathFollow3D
	if path == null or follow == null or path.curve == null:
		return {}
	var length := path.curve.get_baked_length()
	var offset := clampf(follow.progress, 0.0, length)
	var sample_step := minf(0.15, length * 0.01)
	var before := path.curve.sample_baked(maxf(0.0, offset - sample_step), true)
	var after := path.curve.sample_baked(minf(length, offset + sample_step), true)
	var local_direction := (after - before).normalized()
	if local_direction.length_squared() <= 0.0001:
		local_direction = Vector3.FORWARD
	var world_direction := (path.global_basis * local_direction).normalized()
	return {
		"position": follow.global_position,
		"direction": world_direction,
		"hatch": p1_hatch if player_index == 1 else p2_hatch,
		"action_progress": p1_action_progress if player_index == 1 else p2_action_progress,
		"ladder_deploy": p1_ladder_deploy if player_index == 1 else p2_ladder_deploy,
		"bank": deg_to_rad(p1_bank_deg if player_index == 1 else p2_bank_deg),
		"pitch": deg_to_rad(p1_pitch_deg if player_index == 1 else p2_pitch_deg),
	}


func _apply_preview_visibility() -> void:
	if not is_inside_tree():
		return
	for sequence: String in ["Intro", "Pickup"]:
		var should_show := (
			show_intro_preview if sequence == "Intro" else show_pickup_preview
		)
		if _runtime_mode:
			should_show = false
		for player_prefix: String in ["P1", "P2"]:
			var model := get_node_or_null(
				"%s%sPath/Follow/PreviewModel" % [sequence, player_prefix]
			) as Node3D
			if model != null:
				model.visible = should_show


func _cache_preview_hatch_bases() -> void:
	if not _hatch_bases.is_empty():
		return
	for player_index: int in [1, 2]:
		var prefix := "P1" if player_index == 1 else "P2"
		for sequence: String in ["Intro", "Pickup"]:
			var model := get_node_or_null("%s%sPath/Follow/PreviewModel" % [sequence, prefix])
			if model == null:
				continue
			var left := model.find_child("DropHatchLeft", true, false) as Node3D
			var right := model.find_child("DropHatchRight", true, false) as Node3D
			if left != null and right != null:
				_hatch_bases[left.get_path()] = left.rotation
				_hatch_bases[right.get_path()] = right.rotation


func _apply_preview_hatch(player_index: int, openness: float) -> void:
	if not is_inside_tree():
		return
	if _hatch_bases.is_empty():
		_cache_preview_hatch_bases()
	var prefix := "P1" if player_index == 1 else "P2"
	var angle := deg_to_rad(78.0) * smoothstep(0.0, 1.0, clampf(openness, 0.0, 1.0))
	for sequence: String in ["Intro", "Pickup"]:
		var model := get_node_or_null("%s%sPath/Follow/PreviewModel" % [sequence, prefix])
		if model == null:
			continue
		var left := model.find_child("DropHatchLeft", true, false) as Node3D
		var right := model.find_child("DropHatchRight", true, false) as Node3D
		if left == null or right == null:
			continue
		var left_base: Vector3 = _hatch_bases.get(left.get_path(), left.rotation)
		var right_base: Vector3 = _hatch_bases.get(right.get_path(), right.rotation)
		left.rotation = left_base + Vector3(0.0, 0.0, -angle)
		right.rotation = right_base + Vector3(0.0, 0.0, angle)


func _ensure_preview_extraction() -> void:
	if _runtime_mode or not is_inside_tree():
		return
	for player_index: int in [1, 2]:
		_ensure_preview_actor(player_index)
		_ensure_preview_ladder(player_index)


func _ensure_preview_actor(player_index: int) -> void:
	if _preview_actors.has(player_index):
		return
	var editor_reference := get_node_or_null("EditorReference") as Node3D
	if editor_reference == null:
		return
	var actor_name := "P%dActor" % player_index
	var actor := editor_reference.get_node_or_null(actor_name) as Node3D
	if actor == null:
		actor = Node3D.new()
		actor.name = actor_name
		editor_reference.add_child(actor)
		var body := MeshInstance3D.new()
		body.name = "Body"
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.28
		mesh.height = 1.15
		body.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = (
			Color(0.96, 0.45, 0.16, 1.0)
			if player_index == 1
			else Color(0.35, 0.62, 0.95, 1.0)
		)
		body.material_override = material
		body.position.y = 0.58
		actor.add_child(body)
	_preview_actors[player_index] = actor


func _ensure_preview_ladder(player_index: int) -> void:
	if _preview_ladders.has(player_index):
		return
	var mount := _ensure_preview_ladder_mount(player_index)
	if mount == null:
		return
	var ladder := PhysicalRopeLadderScript.new() as PhysicalRopeLadder
	ladder.name = "P%dPreviewRopeLadder" % player_index
	add_child(ladder)
	ladder.configure(mount, player_index)
	_preview_ladders[player_index] = ladder


func _ensure_preview_ladder_mount(player_index: int) -> Node3D:
	var prefix := "P1" if player_index == 1 else "P2"
	var model := get_node_or_null("Pickup%sPath/Follow/PreviewModel" % prefix) as Node3D
	if model == null:
		return null
	var mount := model.get_node_or_null("PreviewLadderMount") as Node3D
	if mount != null:
		return mount
	mount = Node3D.new()
	mount.name = "PreviewLadderMount"
	model.add_child(mount)
	_place_preview_mount(mount, model)
	return mount


func _place_preview_mount(mount: Node3D, model: Node3D) -> void:
	var left := model.find_child("DropHatchLeft", true, false) as Node3D
	var right := model.find_child("DropHatchRight", true, false) as Node3D
	if left == null or right == null:
		mount.position = Vector3(0.0, 0.08, 0.0)
		return
	var center := (left.global_position + right.global_position) * 0.5
	var down := -model.global_basis.y.normalized()
	mount.global_position = center - down * 0.08


func _refresh_preview_extraction() -> void:
	if _runtime_mode or not is_inside_tree():
		return
	_ensure_preview_extraction()
	for player_index: int in [1, 2]:
		var prefix := "P1" if player_index == 1 else "P2"
		var model := get_node_or_null("Pickup%sPath/Follow/PreviewModel" % prefix) as Node3D
		var mount := _ensure_preview_ladder_mount(player_index)
		if model != null and mount != null:
			_place_preview_mount(mount, model)
		var ladder := _preview_ladders.get(player_index) as PhysicalRopeLadder
		var deploy := p1_ladder_deploy if player_index == 1 else p2_ladder_deploy
		if ladder != null and is_instance_valid(ladder):
			if Engine.is_editor_hint():
				ladder.apply_editor_preview(deploy)
			else:
				ladder.set_deploy_progress(deploy)
			ladder.set_winch_progress(0.0)
		var actor := _preview_actors.get(player_index) as Node3D
		if actor == null or not is_instance_valid(actor):
			continue
		var path := get_node_or_null("Pickup%sPath" % prefix) as Path3D
		var ground := path.position if path != null else Vector3(-3.5 if player_index == 1 else 3.5, -1.2, 0.0)
		var grab := p1_action_progress if player_index == 1 else p2_action_progress
		var hang := ground + Vector3.UP * 1.15
		if ladder != null and is_instance_valid(ladder):
			var grip := ladder.get_grip_data()
			if bool(grip.get("valid", false)):
				hang = grip.get("center", hang) + Vector3.DOWN * 1.18
			elif mount != null:
				hang = mount.global_position + Vector3.DOWN * 7.2
		elif mount != null:
			hang = mount.global_position + Vector3.DOWN * 7.2
		var stand := ground + Vector3.UP * 0.02
		actor.visible = show_pickup_preview
		actor.global_position = stand.lerp(hang, smoothstep(0.0, 1.0, grab))


func _clear_preview_extraction() -> void:
	for player_index: Variant in _preview_ladders.keys():
		var ladder: PhysicalRopeLadder = _preview_ladders[player_index]
		if ladder != null and is_instance_valid(ladder):
			ladder.queue_free()
	_preview_ladders.clear()
	for player_index: Variant in _preview_actors.keys():
		var actor: Node3D = _preview_actors[player_index]
		if actor != null and is_instance_valid(actor):
			actor.visible = false

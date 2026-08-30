@tool
class_name MenuHelicopterSequenceProfile
extends Node3D

## Editor-authored flight paths and timelines used by the main-menu helicopters.
## Open res://scenes/menu_helicopter_sequence.tscn, drag Path3D points/handles,
## then scrub intro_arrival or start_pickup in AnimationPlayer.

const INTRO_ANIMATION: StringName = &"intro_arrival"
const PICKUP_ANIMATION: StringName = &"start_pickup"

@export_category("Animation-driven values")
@export_range(0.0, 1.0, 0.001) var p1_hatch: float = 0.0:
	set(value):
		p1_hatch = clampf(value, 0.0, 1.0)
		_apply_preview_hatch(1, p1_hatch)
@export_range(0.0, 1.0, 0.001) var p2_hatch: float = 0.0:
	set(value):
		p2_hatch = clampf(value, 0.0, 1.0)
		_apply_preview_hatch(2, p2_hatch)
@export_range(0.0, 1.0, 0.001) var p1_action_progress: float = 0.0
@export_range(0.0, 1.0, 0.001) var p2_action_progress: float = 0.0
@export_range(-45.0, 45.0, 0.1, "suffix:°") var p1_bank_deg: float = 0.0
@export_range(-45.0, 45.0, 0.1, "suffix:°") var p2_bank_deg: float = 0.0
@export_range(-30.0, 30.0, 0.1, "suffix:°") var p1_pitch_deg: float = 0.0
@export_range(-30.0, 30.0, 0.1, "suffix:°") var p2_pitch_deg: float = 0.0
@export_range(0.0, 30.0, 0.1, "suffix:°") var camera_fov_delta: float = 0.0
@export_range(-30.0, 30.0, 0.1, "suffix:°") var camera_tilt_deg: float = 0.0
@export var show_intro_preview := true:
	set(value):
		show_intro_preview = value
		_apply_preview_visibility()
@export var show_pickup_preview := false:
	set(value):
		show_pickup_preview = value
		_apply_preview_visibility()

var _runtime_animation: StringName = INTRO_ANIMATION
var _runtime_time := 0.0
var _runtime_mode := false
var _hatch_bases: Dictionary = {}


func _ready() -> void:
	_cache_preview_hatch_bases()
	_apply_preview_hatch(1, p1_hatch)
	_apply_preview_hatch(2, p2_hatch)
	_apply_preview_visibility()
	call_deferred("_start_standalone_preview")


func _start_standalone_preview() -> void:
	if _runtime_mode or not is_inside_tree():
		return
	var preview_camera := get_node_or_null("PreviewCamera") as Camera3D
	if preview_camera != null:
		preview_camera.current = true
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null and player.has_animation(INTRO_ANIMATION):
		player.play(INTRO_ANIMATION)


func prepare_runtime() -> void:
	_runtime_mode = true
	# Disable the editor preview camera before this instance can enter a live
	# viewport. current=true would steal the menu camera, then clearing it
	# hands the view to LiveCamera at the origin.
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

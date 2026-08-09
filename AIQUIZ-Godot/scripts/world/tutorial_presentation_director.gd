extends Node
class_name TutorialPresentationDirector

var game_state: QuizGameState = null
var camera_controller: Node3D = null

var _active: bool = false
var _elapsed: float = 0.0
var _duration: float = 1.5
var _presentation_id: String = ""
var _step_id: String = ""
var _revision: int = -1
var _poses: Array[Dictionary] = []


func setup(state: QuizGameState, controller: Node3D) -> void:
	game_state = state
	camera_controller = controller


func update(delta: float) -> void:
	if game_state == null or camera_controller == null:
		return
	if game_state.mode != Constants.MODE_TUTORIAL:
		_cancel(false)
		return
	var model := game_state.get_tutorial_overlay_model()
	if not bool(model.get("presentation_locked", false)):
		if _active:
			_cancel(false)
		return
	var model_step := str(model.get("step_id", ""))
	var model_revision := int(model.get("revision", -1))
	if not _active or model_step != _step_id:
		_begin_presentation(model_step, model_revision)
	if not _active:
		return
	_elapsed = minf(_duration, _elapsed + delta)
	_apply_pose(_elapsed / maxf(0.001, _duration))
	if _elapsed >= _duration:
		_finish()


func skip() -> void:
	if _active:
		_finish()


func is_active() -> bool:
	return _active


func _begin_presentation(step_id: String, model_revision: int) -> void:
	var flow: RefCounted = game_state.tutorial_flow
	if flow == null:
		return
	_presentation_id = flow.presentation_id()
	if _presentation_id.is_empty():
		game_state.complete_tutorial_presentation()
		return
	_step_id = step_id
	_revision = model_revision
	_elapsed = 0.0
	_duration = flow.presentation_duration()
	_poses = _build_poses(_presentation_id)
	_active = not _poses.is_empty()
	if not _active:
		game_state.complete_tutorial_presentation(_presentation_id)
		return
	AudioManager.set_tutorial_ducked(true)
	AudioManager.play_tutorial_step()
	_apply_pose(0.0)


func _finish() -> void:
	if not _active:
		return
	_apply_pose(1.0)
	var finished_id := _presentation_id
	_cancel(true)
	AudioManager.play_tutorial_settle()
	game_state.complete_tutorial_presentation(finished_id)
	if game_state.is_tutorial_presentation_locked():
		var model := game_state.get_tutorial_overlay_model()
		_begin_presentation(str(model.get("step_id", "")), int(model.get("revision", -1)))


func _cancel(restore_audio: bool) -> void:
	if camera_controller != null and camera_controller.has_method("clear_tutorial_override"):
		camera_controller.clear_tutorial_override()
	if restore_audio or _active:
		AudioManager.set_tutorial_ducked(false)
	_active = false
	_elapsed = 0.0
	_poses.clear()


func _apply_pose(progress: float) -> void:
	if _poses.is_empty():
		return
	if _poses.size() == 1:
		_set_camera_pose(_poses[0])
		return
	var scaled := clampf(progress, 0.0, 1.0) * float(_poses.size() - 1)
	var index := mini(_poses.size() - 2, int(floor(scaled)))
	var local_t := _ease_smooth(scaled - float(index))
	var from_pose: Dictionary = _poses[index]
	var to_pose: Dictionary = _poses[index + 1]
	var pose := {
		"eye": (from_pose.get("eye", Vector3.ZERO) as Vector3).lerp(
			to_pose.get("eye", Vector3.ZERO) as Vector3, local_t
		),
		"target": (from_pose.get("target", Vector3.ZERO) as Vector3).lerp(
			to_pose.get("target", Vector3.ZERO) as Vector3, local_t
		),
		"fov": lerpf(float(from_pose.get("fov", 50.0)), float(to_pose.get("fov", 50.0)), local_t),
	}
	_set_camera_pose(pose)


func _set_camera_pose(pose: Dictionary) -> void:
	if not camera_controller.has_method("set_tutorial_override_pose"):
		return
	var eye: Vector3 = pose.get("eye", Vector3.ZERO)
	var target: Vector3 = pose.get("target", Vector3.ZERO)
	eye.x = clampf(eye.x, -24.0, 24.0)
	eye.y = clampf(eye.y, 2.4, 14.0)
	camera_controller.set_tutorial_override_pose(eye, target, float(pose.get("fov", 50.0)))


func _build_poses(presentation_id: String) -> Array[Dictionary]:
	var camera := camera_controller.get_node_or_null("Camera3D") as Camera3D
	var normal: Dictionary = camera_controller.get_gameplay_pose(game_state)
	var start := normal.duplicate(true)
	if camera != null:
		start = {
			"eye": camera.global_position,
			"target": camera.global_position - camera.global_basis.z * 12.0,
			"fov": camera.fov,
		}
	if presentation_id == "completion_hero":
		var completion_hold: Array[Dictionary] = [start]
		return completion_hold
	var p1 := _player_position(1)
	var p2 := _player_position(2)
	var center := p1 if game_state.num_players < 2 else (p1 + p2) * 0.5
	var wall_z := game_state.wall_z - game_state.world_scroll_z
	var goal_local_z := game_state.goal_z - game_state.world_scroll_z
	if game_state.goal_z <= 0.0:
		goal_local_z = wall_z + 30.0
	var result: Array[Dictionary] = [start]
	match presentation_id:
		"goal_sweep":
			result.append(_pose(center + Vector3(0.0, 5.0, -8.0), Vector3(0.0, 1.2, goal_local_z), 55.0))
		_:
			result.append(normal)
	result.append(normal)
	return result


func _player_position(player_index: int) -> Vector3:
	if player_index == 2:
		return Vector3(game_state.player2_x, game_state.player2_y, game_state.player2_local_z)
	return Vector3(game_state.player_x, game_state.player_y, game_state.player_local_z)


func _pose(eye: Vector3, target: Vector3, fov: float) -> Dictionary:
	return {"eye": eye, "target": target, "fov": fov}


func _ease_smooth(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)

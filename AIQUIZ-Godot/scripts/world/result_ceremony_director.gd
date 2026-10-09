class_name ResultCeremonyDirector
extends Node3D

## Score Tower Finale — local 2P, ten questions. Every round ends here: living
## finalists walk in from the goal, eliminated ones join as ghosts (leaping off
## the ghost shark, or appearing on the podium after the elimination wipe).
## Owns the 3D stage (towers, cast, props, referee), the result ghosts, the
## celebration effects, the stage lights and the verdict camera shake. The HUD
## (ResultFinaleHud) and the camera (CameraController) read the same
## Blender/After Effects clock.

const Motion = preload("res://scripts/world/result_finale/result_finale_motion.gd")
const KEY_LIGHT_COLOR := Color(1.0, 0.91, 0.76)
const RIM_ENERGY := 0.9
const GHOST_ARC_HEIGHT := 2.4

## Sudden death (SuddenDeathDirector): how far the elevator deck under the podium has
## sunk below the floor. The whole stage rides it down the shaft mouth and back up.
static var stage_drop := 0.0
## Sudden death: the ceremony key and rim lights (0..1) fade as the deck sinks into the mouth.
static var stage_light := 1.0

var game_state: QuizGameState = null
## Sudden death return: the crowd waits for the loser to land before throwing.
var allow_egg_target := true
var player_controller: PlayerController = null
var camera_controller: Node3D = null

var _stage: ResultFinaleStage
var _effects: ResultFinaleEffects
var _lights: Node3D
var _key_light: SpotLight3D
var _rims: Array[OmniLight3D] = []
var _interactive_elapsed := 0.0
var _cues: Dictionary = {}
var _render_prewarm_active := false
var _ghost_ride: GhostSharkRideController = null
var _ghost_root: Node3D
## Player index -> released ghost, its transform at release and its riding scale.
var _ghosts: Dictionary = {}
var _ghost_from: Dictionary = {}
var _ghost_scale: Dictionary = {}
var _ghost_clock := 0.0


func setup(
		state: QuizGameState,
		players: PlayerController,
		camera_rig: Node3D,
		ghost_ride: Node = null) -> void:
	game_state = state
	player_controller = players
	camera_controller = camera_rig
	_ghost_ride = ghost_ride as GhostSharkRideController
	_ghost_root = Node3D.new()
	_ghost_root.name = "ResultGhosts"
	add_child(_ghost_root)
	_effects = ResultFinaleEffects.new()
	_effects.name = "ResultFinaleEffects"
	add_child(_effects)
	_stage = ResultFinaleStage.new()
	add_child(_stage)
	var camera := camera_rig.get_node_or_null("Camera3D") as Camera3D if camera_rig != null else null
	_stage.setup(state, players, camera, _effects)


## Stage origin: centred between both finishing marks on the conveyor surface.
static func stage_origin(state: QuizGameState) -> Vector3:
	return Vector3(0.0, Motion.FLOOR_TOP_Y - stage_drop,
		state.get_local_result_goal_z() + QuizGameState.RESULT_WALK_FINISH_OFFSET - state.world_scroll_z)


## Where the podium (and the sudden death shaft mouth) sits on the floor, without the drop.
static func podium_center(state: QuizGameState) -> Vector3:
	return Vector3(0.0, Motion.FLOOR_TOP_Y,
		state.get_local_result_goal_z() + QuizGameState.RESULT_WALK_FINISH_OFFSET - state.world_scroll_z)


func stage() -> ResultFinaleStage:
	return _stage


## Ceremony clock including the time the result controls have been waiting.
func result_elapsed() -> float:
	return game_state.result_ceremony_elapsed + _interactive_elapsed


## Egg target for the goal stand crowd once the verdict is out (null otherwise).
func crowd_egg_target() -> Node3D:
	if _stage == null or _render_prewarm_active or game_state == null or not game_state.result_presentation_active:
		return null
	if not allow_egg_target:
		return null
	if result_elapsed() < Motion.VERDICT:
		return null
	return _stage.egg_target()


func update_result_ceremony(delta: float) -> void:
	if game_state == null:
		return
	_update_result_ghosts(delta)
	if not game_state.result_presentation_active:
		if _stage.is_built() and not _render_prewarm_active:
			_reset_presentation()
		return
	if game_state.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.INTERACTIVE:
		_interactive_elapsed += maxf(0.0, delta)
	else:
		_interactive_elapsed = 0.0
	if not _stage.is_built() or _stage.built_winner() != game_state.result_winner:
		_effects.clear()
		_cues.clear()
		_stage.build(game_state.result_winner)
		if game_state.sudden_death_aborted:
			# The descent came back up: the draw already had its verdict and every burst.
			_cues["verdict"] = game_state.result_ceremony_elapsed
			_stage.skip_effects_before(game_state.result_ceremony_elapsed)
	var elapsed := result_elapsed()
	_effects.setup(GameManager.graphics_quality)
	_stage.set_ghost_sources(_ghosts)
	_stage.update_stage(elapsed, stage_origin(game_state))
	_ensure_lights()
	_update_lights(delta, elapsed)
	# Holding at the verdict after the sudden death: the verdict beat waits for the release.
	if not game_state.result_return_hold:
		_update_beats(elapsed)


# ------------------------------------------------------------------ result ghosts

## Ghost finalists: released from the ghost ride (or raised from the body), then
## a leap onto their own lane, then the same walk as the living onto the pads.
## ResultFinaleStage takes the pose over at CAST_START and hides them.
func _update_result_ghosts(delta: float) -> void:
	if game_state.result_ghost_mask == 0:
		if not _ghosts.is_empty():
			_clear_ghosts()
		return
	_ghost_clock += maxf(delta, 0.0)
	for player_index in [1, 2]:
		if not game_state.is_result_ghost(player_index):
			continue
		var ghost := _ghosts.get(player_index) as Node3D
		if ghost == null or not is_instance_valid(ghost):
			ghost = _release_ghost(player_index)
			if ghost == null:
				continue
		if game_state.result_presentation_active:
			_pose_walking_ghost(ghost, player_index)
		else:
			_pose_leaping_ghost(ghost, player_index)


func _release_ghost(player_index: int) -> Node3D:
	var ghost: Node3D = null
	if _ghost_ride != null and is_instance_valid(_ghost_ride):
		ghost = _ghost_ride.release_result_ghost(player_index, _ghost_root)
	elif player_controller != null:
		ghost = player_controller.create_ghost_rider_visual(player_index)
		if ghost != null:
			_ghost_root.add_child(ghost)
			ghost.global_position = player_controller.get_death_presentation_position(player_index == 1)
			player_controller.make_ghost_rider_translucent(ghost)
	if ghost == null:
		return null
	ghost.name = "ResultGhostP%d" % player_index
	_ghosts[player_index] = ghost
	_ghost_from[player_index] = ghost.global_transform.orthonormalized()
	_ghost_scale[player_index] = clampf(float(ghost.get_meta("result_release_scale", 1.0)), 0.2, 1.0)
	return ghost


func _pose_leaping_ghost(ghost: Node3D, player_index: int) -> void:
	var progress := game_state.get_result_ghost_arrival_progress(player_index)
	var from: Transform3D = _ghost_from[player_index]
	var landing := _world_point(game_state.get_result_ghost_landing_local_position(player_index))
	var ground := from.origin.lerp(landing, smoothstep(0.0, 1.0, progress))
	var lift := GHOST_ARC_HEIGHT * 4.0 * progress * (1.0 - progress)
	var turn := smoothstep(0.0, 0.6, progress)
	var rotation_value := from.basis.get_rotation_quaternion().slerp(_ghost_facing(), turn)
	var size := lerpf(float(_ghost_scale[player_index]), 1.0, smoothstep(0.0, 0.35, progress))
	ghost.global_transform = Transform3D(Basis(rotation_value).scaled(Vector3.ONE * size), ground + Vector3.UP * lift)
	var rise_speed := GHOST_ARC_HEIGHT * 4.0 * (1.0 - 2.0 * progress) / QuizGameState.RESULT_GHOST_ARRIVAL_DURATION
	var airborne := progress < 1.0
	player_controller.apply_ghost_rider_result_pose(
		ghost, player_index, false, _ghost_clock,
		lift if airborne else 0.0, rise_speed if airborne else 0.0
	)


func _pose_walking_ghost(ghost: Node3D, player_index: int) -> void:
	var local := game_state.get_result_player_local_position(player_index)
	ghost.global_transform = Transform3D(Basis(_ghost_facing()), _world_point(local))
	var walking := game_state.result_ceremony_phase in [
		QuizGameState.ResultCeremonyPhase.ASSEMBLE,
		QuizGameState.ResultCeremonyPhase.WALK,
	]
	player_controller.apply_ghost_rider_result_pose(ghost, player_index, walking, _ghost_clock)


## Result positions are GameWorld-local, like the live players.
func _world_point(local: Vector3) -> Vector3:
	var world_root := get_parent() as Node3D
	return world_root.to_global(local) if world_root != null else local


func _ghost_facing() -> Quaternion:
	var world_root := get_parent() as Node3D
	return world_root.global_basis.get_rotation_quaternion() if world_root != null else Quaternion.IDENTITY


func _clear_ghosts() -> void:
	for ghost: Variant in _ghosts.values():
		if ghost is Node3D and is_instance_valid(ghost):
			(ghost as Node3D).queue_free()
	_ghosts.clear()
	_ghost_from.clear()
	_ghost_scale.clear()
	_ghost_clock = 0.0


func get_result_ghost(player_index: int) -> Node3D:
	var ghost := _ghosts.get(player_index) as Node3D
	return ghost if ghost != null and is_instance_valid(ghost) else null


func _cue(name_value: String, due: bool) -> bool:
	if due and not _cues.has(name_value):
		_cues[name_value] = result_elapsed()
		return true
	return false


func _update_beats(elapsed: float) -> void:
	if _cue("verdict", elapsed >= Motion.VERDICT):
		game_state.camera_shake = maxf(game_state.camera_shake, 0.45)


## Prepare the finale meshes and materials under the loading cover so the first
## ceremony frame does not compile them.
func begin_render_prewarm() -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if game_state == null or not game_state.uses_local_result_ceremony():
		return {"ready": true, "skipped": true, "elapsed_msec": 0.0}
	_render_prewarm_active = true
	_ensure_lights()
	_stage.build(1)
	_stage.update_stage(Motion.VERDICT + 1.0, Vector3(0.0, Motion.FLOOR_TOP_Y, 0.0))
	return {
		"ready": _stage.is_built(),
		"skipped": false,
		"elapsed_msec": float(Time.get_ticks_usec() - started_usec) / 1000.0,
	}


func end_render_prewarm() -> void:
	_render_prewarm_active = false
	_reset_presentation()


func _ensure_lights() -> void:
	if is_instance_valid(_lights):
		return
	_lights = Node3D.new()
	_lights.name = "ResultPresentationLights"
	add_child(_lights)
	_key_light = SpotLight3D.new()
	_key_light.name = "CeremonyKey"
	_key_light.light_color = KEY_LIGHT_COLOR
	_key_light.light_energy = 0.0
	_key_light.light_specular = 0.46
	_key_light.shadow_enabled = false
	_key_light.spot_range = 16.0
	_key_light.spot_angle = 50.0
	_key_light.spot_attenuation = 0.72
	_lights.add_child(_key_light)
	for index in range(2):
		var rim := OmniLight3D.new()
		rim.name = "P%dRim" % (index + 1)
		rim.light_color = ResultFinaleStage.P1_COLOR if index == 0 else ResultFinaleStage.P2_COLOR
		rim.light_energy = 0.0
		rim.light_specular = 0.3
		rim.shadow_enabled = false
		rim.omni_range = 5.5
		rim.omni_attenuation = 1.3
		_lights.add_child(rim)
		_rims.append(rim)


func _update_lights(delta: float, elapsed: float) -> void:
	var origin := stage_origin(game_state)
	var snapshot := _stage.get_debug_snapshot()
	var heights: Dictionary = snapshot.get("heights", {})
	var focus := origin + Vector3(0.0, 2.2, 0.0)
	_key_light.global_position = origin + Vector3(4.8, 7.2, -5.0)
	_key_light.look_at(focus, Vector3.UP)
	var p1_height := float(heights.get(1, 0.0))
	var p2_height := float(heights.get(2, 0.0))
	# Rims sit behind each tower top (stage +Z is away from the camera).
	_rims[0].global_position = origin + Vector3(Motion.TOWER_X, p1_height + 2.2, 1.6)
	_rims[1].global_position = origin + Vector3(-Motion.TOWER_X, p2_height + 2.2, 1.6)
	var amount := smoothstep(0.0, 0.8, elapsed) * stage_light
	var quality := GraphicsQuality.normalize(GameManager.graphics_quality)
	var factor := 0.72 if quality == GraphicsQuality.LOW else (1.0 if GraphicsQuality.is_at_least(quality, GraphicsQuality.HIGH) else 0.86)
	var night := _night_amount()
	var blend := 1.0 - exp(-maxf(delta, 0.0) * 5.8)
	_key_light.light_energy = lerpf(_key_light.light_energy, amount * factor * lerpf(0.9, 1.6, night), blend)
	for index in range(2):
		var dim := 1.0
		if game_state.result_winner != 0 and index + 1 != game_state.result_winner and elapsed >= Motion.VERDICT:
			dim = 0.25
		_rims[index].light_energy = lerpf(_rims[index].light_energy, amount * factor * RIM_ENERGY * dim * lerpf(0.6, 1.1, night), blend)


func _night_amount() -> float:
	var world_root := get_parent()
	var stage := world_root.get_node_or_null("StageEnvironment") if world_root != null else null
	if stage == null:
		return 0.0
	var weather: Variant = stage.get("weather_cycle")
	if weather is Node:
		return clampf(float((weather as Node).get("night_amount")), 0.0, 1.0)
	return 0.0


func _reset_presentation() -> void:
	_stage.clear()
	_effects.clear()
	_cues.clear()
	_interactive_elapsed = 0.0
	if is_instance_valid(_lights):
		_lights.queue_free()
	_lights = null
	_key_light = null
	_rims.clear()


func get_debug_snapshot() -> Dictionary:
	var snapshot := _stage.get_debug_snapshot() if _stage != null else {}
	snapshot["phase"] = game_state.result_ceremony_phase if game_state != null else -1
	snapshot["cues"] = _cues.duplicate()
	snapshot["light_count"] = _lights.get_child_count() if is_instance_valid(_lights) else 0
	snapshot["result_elapsed"] = result_elapsed() if game_state != null else 0.0
	return snapshot


func force_cleanup() -> void:
	_render_prewarm_active = false
	_reset_presentation()
	_clear_ghosts()
	if player_controller != null:
		player_controller.reset_result_presentation()

class_name ResultCeremonyDirector
extends Node3D

## Score Tower Finale — local 2P, ten questions, both players finished alive.
## Owns the 3D stage (towers, cast, props, referee), the celebration effects, the
## stage lights and the sound beats. The HUD (ResultFinaleHud) and the camera
## (CameraController) read the same Blender/After Effects clock.

const Motion = preload("res://scripts/world/result_finale/result_finale_motion.gd")
const KEY_LIGHT_COLOR := Color(1.0, 0.91, 0.76)
const RIM_ENERGY := 0.9

var game_state: QuizGameState = null
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


func _exit_tree() -> void:
	if is_instance_valid(AudioManager):
		AudioManager.stop_result_sounds()


func setup(
		state: QuizGameState,
		players: PlayerController,
		camera_rig: Node3D,
		_ghost_ride: Node = null) -> void:
	game_state = state
	player_controller = players
	camera_controller = camera_rig
	_effects = ResultFinaleEffects.new()
	_effects.name = "ResultFinaleEffects"
	add_child(_effects)
	_stage = ResultFinaleStage.new()
	add_child(_stage)
	var camera := camera_rig.get_node_or_null("Camera3D") as Camera3D if camera_rig != null else null
	_stage.setup(state, players, camera, _effects)


## Stage origin: centred between both finishing marks on the conveyor surface.
static func stage_origin(state: QuizGameState) -> Vector3:
	return Vector3(0.0, Motion.FLOOR_TOP_Y,
		state.get_local_result_goal_z() + QuizGameState.RESULT_WALK_FINISH_OFFSET - state.world_scroll_z)


## Ceremony clock including the time the result controls have been waiting.
func result_elapsed() -> float:
	return game_state.result_ceremony_elapsed + _interactive_elapsed


## Egg target for the goal stand crowd once the verdict is out (null otherwise).
func crowd_egg_target() -> Node3D:
	if _stage == null or _render_prewarm_active or game_state == null or not game_state.result_presentation_active:
		return null
	if result_elapsed() < Motion.VERDICT:
		return null
	return _stage.egg_target()


func update_result_ceremony(delta: float) -> void:
	if game_state == null:
		return
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
	var elapsed := result_elapsed()
	_effects.setup(GameManager.graphics_quality)
	_stage.update_stage(elapsed, stage_origin(game_state))
	_ensure_lights()
	_update_lights(delta, elapsed)
	_update_sounds(elapsed)


func _cue(name_value: String, due: bool) -> bool:
	if due and not _cues.has(name_value):
		_cues[name_value] = result_elapsed()
		return true
	return false


func _update_sounds(elapsed: float) -> void:
	var draw := game_state.result_winner == 0
	var totals := Vector2i(game_state.result_p1_score, game_state.result_p2_score)
	var max_total := maxi(totals.x, totals.y)
	if _cue("pad_pop", elapsed >= Motion.beat("pad_pop")):
		AudioManager.play_result_cue(&"pad_pop")
	if _cue("correct", elapsed >= Motion.beat("correct")):
		AudioManager.play_result_lock()
	if _cue("hp", elapsed >= Motion.beat("hp")):
		AudioManager.play_result_lock()
	if _cue("climb", elapsed >= Motion.beat("climb")):
		AudioManager.play_result_cue(&"climb")
	for player_index in [1, 2]:
		var total := totals.x if player_index == 1 else totals.y
		if _cue("lock_%d" % player_index, elapsed >= Motion.lock_time(total, max_total)):
			AudioManager.play_result_lock()
	if _cue("verdict", elapsed >= Motion.VERDICT):
		AudioManager.play_result_accent(&"verdict")
		AudioManager.play_result_cue(&"cymbal", 1.0, -3.0)
		AudioManager.play_result_victory(draw)
		game_state.camera_shake = maxf(game_state.camera_shake, 0.45)
	if _cue("confetti", elapsed >= Motion.VERDICT + 0.03):
		AudioManager.play_result_cue(&"confetti")
	if _cue("swish", elapsed >= Motion.VERDICT + 0.12):
		AudioManager.play_result_cue(&"swish", 1.0, -6.0)
	if not draw:
		if _cue("sad", elapsed >= Motion.beat("sink_start") + 0.05):
			AudioManager.play_result_cue(&"sad", 1.0, -2.0)
		if _cue("crown", elapsed >= Motion.beat("crown_land")):
			AudioManager.play_result_cue(&"crown")
		if _cue("rain", elapsed >= Motion.beat("rain")):
			AudioManager.start_result_rain()
	for index in range(4):
		if _cue("firework_%d" % index, elapsed >= [7.05, 7.55, 8.25, 9.3][index] + 0.08):
			AudioManager.play_result_cue(&"confetti", 0.62, -9.0)


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
	var amount := smoothstep(0.0, 0.8, elapsed)
	var quality := GraphicsQuality.normalize(GameManager.graphics_quality)
	var factor := 0.72 if quality == GraphicsQuality.LOW else (1.0 if quality == GraphicsQuality.HIGH else 0.86)
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
	AudioManager.stop_result_sounds()


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
	if player_controller != null:
		player_controller.reset_result_presentation()

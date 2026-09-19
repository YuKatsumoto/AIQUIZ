extends Node3D
class_name SawChaseController

## Presentation only. State/replay owns position, animation time and wheel travel.
const MODEL_PATH := "res://assets/hazards/linked_saw_carriage.glb"
var model: Node3D
var animation: AnimationPlayer
var skeleton: Skeleton3D
var spin_clip: StringName
var wheel_bones: Array[int] = []
var spin_bones: Array[int] = []
var lift_posts: Array[MeshInstance3D] = []
var _preview_elapsed := 0.0
var _caught_lifts: Dictionary = {}
var _landing_spin_elapsed := 0.0
var _last_saw_elapsed := 0.0
var dock: SawDockPresentation

func configure_entrance(preview: bool, animate: bool) -> void:
	if dock != null: return
	dock = SawDockPresentation.new()
	dock.name = "SawServiceDock"
	add_child(dock)
	dock.setup(preview, animate)
	position = dock.carriage_position()

func finish_entrance() -> void:
	if dock != null and not dock.is_deployed():
		dock.restore_deployed()

func _load_model() -> void:
	model = (load(MODEL_PATH) as PackedScene).instantiate()
	model.rotation.y = PI # Blender +Y exports toward Godot -Z.
	add_child(model)
	for node: Node in model.find_children("*", "AnimationPlayer", true, false):
		animation = node as AnimationPlayer
		animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		animation.stop()
		for clip: StringName in animation.get_animation_list():
			if str(clip) in ["Spin_Loop", "Spin"]:
				spin_clip = clip
		animation.play(spin_clip)
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		for i: int in skeleton.get_bone_count():
			if skeleton.get_bone_name(i).begins_with("Roll_"):
				wheel_bones.append(i)
			elif skeleton.get_bone_name(i).begins_with("Spin_"):
				spin_bones.append(i)
				var post := MeshInstance3D.new()
				post.name = "TelescopicSpindle_%02d" % spin_bones.size()
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = 0.075
				cylinder.bottom_radius = 0.11
				cylinder.height = 1.0
				post.mesh = cylinder
				var steel := StandardMaterial3D.new()
				steel.albedo_color = Color(0.32, 0.36, 0.40)
				steel.metallic = 0.85
				steel.roughness = 0.28
				post.material_override = steel
				add_child(post)
				lift_posts.append(post)

static func accelerated_spin_time(elapsed: float) -> float:
	var duration := SawChaseState.SPINUP_SECONDS
	var u := clampf(elapsed / duration, 0.0, 1.0)
	# Integral of smoothstep, followed by constant full-speed rotation.
	return duration * (u * u * u - 0.5 * u * u * u * u) + maxf(0.0, elapsed - duration)

func advance_landing_spin(gs: QuizGameState, dt: float, players_landed: bool) -> void:
	if gs.saw.elapsed < _last_saw_elapsed:
		_landing_spin_elapsed = 0.0
	_last_saw_elapsed = gs.saw.elapsed
	if not gs.is_replay and players_landed and gs.saw.elapsed == 0.0 and gs.game_state in [Constants.STATE_PRELOADING, Constants.STATE_WAITING_START, Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN]:
		_landing_spin_elapsed += maxf(dt, 0.0)

func spin_time(gs: QuizGameState) -> float:
	# Existing replays have no arrival clock; retain their recorded play clock.
	if gs.is_replay:
		return SawChaseState.SPINUP_SECONDS * 0.5 + gs.saw.elapsed
	return accelerated_spin_time(_landing_spin_elapsed + gs.saw.elapsed)

func update_preview(dt: float) -> void:
	visible = true
	if model == null:
		_load_model()
	if dock != null:
		dock.advance(dt)
		if dock.is_deployed():
			_preview_elapsed += minf(maxf(dt, 0.0), maxf(0.0, dock.elapsed - dock.READY_TIME)) if dock.animated else maxf(dt, 0.0)
		position = dock.carriage_position()
		basis = dock.carriage_basis()
		_apply_spin(accelerated_spin_time(_preview_elapsed), -dock.wheel_distance())
		dock.update_audio(dt > 0.0, smoothstep(0.0, SawChaseState.SPINUP_SECONDS, _preview_elapsed), global_position)
	else:
		_preview_elapsed += dt
		position = Vector3(0.0, StageConstants.FLOOR_TOP_Y, SawDockPresentation.MENU_Z)
		_apply_spin(accelerated_spin_time(_preview_elapsed), 0.0)

func _apply_spin(seconds: float, wheel_distance: float) -> void:
	if animation != null and not spin_clip.is_empty():
		var duration := animation.get_animation(spin_clip).length
		animation.seek(fposmod(seconds * SawChaseState.BLADE_RPM / 18.0, duration), true)
	if skeleton != null:
		for bone: int in wheel_bones:
			var rest_rotation := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(bone, rest_rotation * Quaternion(Vector3.UP, -wheel_distance / SawChaseState.WHEEL_RADIUS))
		for i: int in spin_bones.size():
			_set_lift(i, 0.0)
		skeleton.force_update_all_bone_transforms()

func _set_lift(index: int, height: float) -> void:
	var bone := spin_bones[index]
	var rest := skeleton.get_bone_rest(bone).origin
	skeleton.set_bone_pose_position(bone, rest + Vector3.UP * height)
	var post := lift_posts[index]
	post.visible = height > 0.01
	post.position = Vector3(-rest.x, rest.y + height * 0.5, -rest.z)
	post.scale.y = maxf(height, 0.001)

func blade_center(index: int) -> Vector3:
	if skeleton == null or index < 0 or index >= spin_bones.size(): return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(spin_bones[index]).origin

func nearest_blade(point: Vector3) -> int:
	var nearest := -1
	var distance := INF
	for i: int in spin_bones.size():
		var d := point.distance_squared_to(blade_center(i))
		if d < distance:
			distance = d
			nearest = i
	return nearest

func _update_lifts(gs: QuizGameState) -> void:
	var new_catches: Dictionary = {}
	for player_index: int in [1, 2]:
		var killed := gs.p1_saw_killed if player_index == 1 else gs.p2_saw_killed
		if not killed:
			_caught_lifts.erase(player_index)
		elif not _caught_lifts.has(player_index):
			new_catches[player_index] = {}
	for i: int in spin_bones.size():
		var blade_x := -skeleton.get_bone_rest(spin_bones[i]).origin.x
		var lift := 0.0
		for player_index: int in [1, 2]:
			var killed := gs.p1_saw_killed if player_index == 1 else gs.p2_saw_killed
			var death_time := gs.game_over_timer if player_index == 1 else gs.player2_game_over_timer
			if killed and _caught_lifts.has(player_index):
				var held: Dictionary = _caught_lifts[player_index]
				lift = maxf(lift, float(held.get(i, 0.0)) * (1.0 - smoothstep(SawChaseState.CUT_SCATTER_DELAY, SawChaseState.CUT_SCATTER_DELAY + 0.60, death_time)))
				continue
			if not killed and not gs._saw_player_eligible(player_index):
				continue
			var x := gs.player_x if player_index == 1 else gs.player2_x
			var z := gs.player_local_z if player_index == 1 else gs.player2_local_z
			var y := gs.player_y if player_index == 1 else gs.player2_y
			var radius := SawChaseState.BLADE_RADIUS + QuizGameState.PLAYER_BODY_RADIUS
			if absf(x - blade_x) > radius or y <= 0.05:
				continue
			var clearance := Vector2(x - blade_x, z - gs.saw.local_z).length() - radius
			var reach := (y + 0.9) * (1.0 - smoothstep(0.0, 4.0, clearance))
			lift = maxf(lift, reach)
			if new_catches.has(player_index):
				new_catches[player_index][i] = reach
		_set_lift(i, lift)
	# Keep each victim's impact pose separate when two players approach together.
	_caught_lifts.merge(new_catches)
	skeleton.force_update_all_bone_transforms()

func update_visual(gs: QuizGameState, dt: float = 0.0, players_landed: bool = false, entrance_running: bool = true) -> void:
	visible = gs.is_saw_visible()
	if not visible:
		if dock != null: dock.stop_audio()
		return
	if model == null:
		_load_model()
	var spin_dt := dt
	if dock != null and not gs.is_replay:
		if entrance_running: dock.advance(dt)
		players_landed = players_landed and dock.is_deployed()
		if dock.animated:
			spin_dt = minf(maxf(dt, 0.0), maxf(0.0, dock.elapsed - dock.READY_TIME))
	advance_landing_spin(gs, spin_dt, players_landed)
	position = Vector3(0.0, StageConstants.FLOOR_TOP_Y, gs.saw.local_z)
	if dock != null and not dock.is_deployed(): position = dock.carriage_position()
	basis = dock.carriage_basis() if dock != null else Basis.IDENTITY
	var entry_distance := dock.wheel_distance() if dock != null else 0.0
	_apply_spin(spin_time(gs), gs.saw.wheel_distance + entry_distance)
	if skeleton != null:
		if dock == null or dock.is_deployed(): _update_lifts(gs)
	if dock != null:
		var active := entrance_running and dt > 0.0 and gs.game_state in [Constants.STATE_PRELOADING, Constants.STATE_WAITING_START, Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN, Constants.STATE_PLAYING]
		dock.update_audio(active, smoothstep(0.0, SawChaseState.SPINUP_SECONDS, _landing_spin_elapsed + gs.saw.elapsed), global_position)

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
var operator_seat: SawOperatorPresentation
var _operator_distance := 0.0
var _operator_elapsed := 0.0
var _operator_lifts: Array[float] = []
var _menu_chase: MenuSawChaseState

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
	if operator_arriving(): operator_seat.seat_transfer.finish_arrival()

func prepare_operator_arrival() -> void:
	if model == null: _load_model()
	operator_seat.seat_transfer.begin_arrival()

func operator_arriving() -> bool:
	return operator_seat != null and operator_seat.seat_transfer.is_arriving()

func _load_model() -> void:
	model = (load(MODEL_PATH) as PackedScene).instantiate()
	model.rotation.y = PI # Blender +Y exports toward Godot -Z.
	add_child(model)
	operator_seat = preload("res://scripts/world/saw_operator_presentation.gd").new()
	operator_seat.name = "SawOperator"
	add_child(operator_seat)
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
	if dt<=0.0 and _menu_chase!=null:return
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
	if _menu_chase!=null and (dock==null or dock.is_deployed()):
		position.z=_menu_chase.local_z
		_apply_spin(accelerated_spin_time(_preview_elapsed),_menu_chase.travel-(dock.wheel_distance() if dock else 0.0))
	else:
		_update_operator(null, dt)

func apply_menu_chase(gs: QuizGameState, state: MenuSawChaseState, dt: float) -> void:
	_menu_chase=state
	if dock!=null and not dock.is_deployed():return
	position.z=state.local_z
	_apply_spin(accelerated_spin_time(_preview_elapsed),state.travel-(dock.wheel_distance() if dock else 0.0))
	_update_lifts(gs)
	_update_operator(gs,dt,true,-state.velocity/MenuSawChaseState.RETURN_SPEED)

func _update_operator(gs: QuizGameState, dt: float, menu: bool=false, drive_override: float=NAN) -> void:
	if operator_seat == null: return
	menu=menu or gs==null
	# Menu transfer travels toward -Z; retain the physical left side of travel.
	operator_seat.position = SawOperatorPresentation.MOUNT * Vector3(-1,1,-1) if menu else SawOperatorPresentation.MOUNT
	operator_seat.rotation.y = SawOperatorPresentation.FACING_YAW + (PI if menu else 0.0)
	var entry := dock.elapsed if dock != null else SawDockPresentation.READY_TIME
	var deployed := dock == null or dock.is_deployed()
	var spin: float = _preview_elapsed if menu else _landing_spin_elapsed + gs.saw.elapsed
	var drive := 0.0
	if gs != null and not menu:
		if gs.is_replay: spin = SawChaseState.SPINUP_SECONDS + gs.saw.elapsed
		if gs.saw.elapsed < _operator_elapsed:
			operator_seat.reset_pose()
			_operator_lifts.clear()
			_operator_distance = gs.saw.wheel_distance
		var time_step: float = gs.saw.elapsed - _operator_elapsed
		if time_step > .000001:
			drive = clampf((gs.saw.wheel_distance-_operator_distance) / time_step / maxf(gs.tuning.saw_max_speed,.01),0.0,1.0)
		elif dt <= 0.0 and not operator_seat.last_sample.is_empty():
			drive = float(operator_seat.last_sample.drive)
		if gs.is_replay:
			drive = clampf(float(gs.get_meta("saw_operator_speed",0.0)) / maxf(gs.tuning.saw_max_speed,.01),0.0,1.0)
		_operator_distance = gs.saw.wheel_distance
		_operator_elapsed = gs.saw.elapsed
		if gs.saw.stopping and not gs.is_replay:
			drive = clampf(gs.saw.velocity / maxf(gs.tuning.saw_max_speed, .01), 0.0, 1.0)
		# Result/pause keeps contact and lever positions exactly as the machine stops.
		if not gs.is_replay and not gs.saw.stopping and gs.game_state in [Constants.STATE_GAME_OVER,Constants.STATE_CORRECT,"ONLINE_QUIZ_ERROR"] and not operator_seat.last_sample.is_empty(): return
		if not gs.is_replay and dt<=0.0 and is_equal_approx(float(operator_seat.last_sample.get("spin",-1.0)),spin):return
	var lift := 0.0
	var rate := 0.0
	var strongest := -1.0
	var heights: Array[float]=[]
	var best_x := INF
	if skeleton != null:
		for i in spin_bones.size():
			var bone: int=spin_bones[i]
			var height := skeleton.get_bone_pose_position(bone).y-skeleton.get_bone_rest(bone).origin.y
			heights.append(height)
			var speed := (height-_operator_lifts[i])/dt if dt>0.0 and i<_operator_lifts.size() else 0.0
			var blade_x := -skeleton.get_bone_rest(bone).origin.x
			var priority_x := blade_x if menu else -blade_x
			if absf(speed)>strongest+.0001 or (is_equal_approx(absf(speed),strongest) and priority_x<best_x):
				strongest=absf(speed);rate=speed;lift=height;best_x=priority_x
	if strongest<.001 and not heights.is_empty():lift=heights.max()
	if gs!=null and gs.is_replay:
		var values: Dictionary=gs.get_meta("saw_operator_lift",{})
		lift=float(values.get("height",lift));rate=float(values.get("speed",0.0))
	elif dt>0.0 and not operator_seat.last_sample.is_empty():
		# A different blade can demand the opposite direction. Traverse the gate
		# continuously; hands and pedal still use this same displayed input.
		rate=move_toward(float(operator_seat.last_sample.lift_motion)*6.0,clampf(rate,-6.0,6.0),50.0*dt)
	_operator_lifts=heights
	if is_finite(drive_override):drive=drive_override
	operator_seat.apply_sample(SawOperatorPresentation.sample(entry,spin,drive,lift,deployed,rate))

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
	if gs.is_replay and gs.has_meta("saw_replay_lifts"):
		var heights: PackedFloat32Array=gs.get_meta("saw_replay_lifts")
		for i in spin_bones.size():
			var x := -skeleton.get_bone_rest(spin_bones[i]).origin.x
			_set_lift(i,heights[clampi(roundi(x/SawChaseState.BLADE_PITCH+3.5),0,7)])
		return
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
			if player_index>gs.num_players:continue
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
	advance_landing_spin(gs, spin_dt, players_landed and not operator_arriving())
	position = Vector3(0.0, StageConstants.FLOOR_TOP_Y, gs.saw.local_z)
	if dock != null and not dock.is_deployed(): position = dock.carriage_position()
	basis = dock.carriage_basis() if dock != null else Basis.IDENTITY
	var entry_distance := dock.wheel_distance() if dock != null else 0.0
	_apply_spin(spin_time(gs), gs.saw.wheel_distance + entry_distance)
	if skeleton != null:
		if dock == null or dock.is_deployed(): _update_lifts(gs)
	_update_operator(gs, dt)
	if operator_arriving():
		operator_seat.seat_transfer.advance_arrival(
			dt, entrance_running and (dock == null or dock.is_deployed()),
			gs.game_state in [Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN, Constants.STATE_PLAYING])
	if dock != null:
		var coasting: bool = not gs.is_replay and gs.saw.stopping and gs.saw.stop_speed_ratio() > 0.0
		var active := entrance_running and dt > 0.0 and (coasting or gs.game_state in [Constants.STATE_PRELOADING, Constants.STATE_WAITING_START, Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN, Constants.STATE_PLAYING])
		var speed := smoothstep(0.0, SawChaseState.SPINUP_SECONDS, _landing_spin_elapsed + gs.saw.elapsed)
		if not gs.is_replay: speed *= gs.saw.stop_speed_ratio()
		dock.update_audio(active, speed, global_position)

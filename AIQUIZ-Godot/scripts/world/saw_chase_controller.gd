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
var _operator_idle := 0.0 # Waiting clock for the pre-start look-around; frozen once the start begins.
var _menu_chase: MenuSawChaseState
## Menu-only stow (wall speed tab): the blades brake to a stop, rams lift and tilt them, the
## drive modules rack them at both ends, and four corner davit towers clamp each rack, carry it
## over the bogie and the operator deck and hang it below the belt beside the conveyor.
## Blender bakes two clips on one progress clock p in [0, length]: Stow is sampled at p and
## Deploy at length - p. Deploy has its own forward-time sway, so a reversal slows the machine
## to a stop, then cross-fades onto the other clip (source: linked_saw_carriage_source/README.md).
## The clips play STOW_SPEED times faster than their Blender timing. At deployed rest the davit towers
## hang down beside the conveyor; they stand up before the clip moves them and hang down again once the deploy ends.
const STOW_CLIP := &"Stow"
const DEPLOY_CLIP := &"Deploy"
const STOW_DATA_PATH := "res://assets/hazards/linked_saw_carriage_stow.json"
const STOW_STEP := 1.0 / 240.0 # fixed step: 30/60/120 fps reach the same p(t)
const STOW_SPEED := 1.3 # clip seconds per second
const STOW_REVERSE_ACCEL := 4.5 # m/s^2 the moving machine may decelerate by when reversed
const TOWER_LAY_SECONDS := 0.7 # davit towers swing between upright and hanging
const TOWER_HANG_TILT := PI / 60.0 # 3 deg: hanging towers lean this far outboard of plumb
const STOW_CROSSFADE := 0.35
const STOW_LIFT_SETTLE := 1.5 # m/s a chase catch lift sinks back while the blades brake
const STOW_RETREAT_SPEED := 2.5 # m/s the stowed carriage backs away to the end of the belt (and returns before deploying)
const STOW_RETREAT_ACCEL := 1.5 # m/s^2
const BEACON_MATERIAL := "MAT_BeaconLens"
var stow_target := false
var _stow_p := 0.0 # 0 = deployed rest, stow_length() = parked beside the conveyor
var _stow_rate := 0.0 # dp/dt in [-1, 1]
var _stow_acc := 0.0 # unstepped remainder, in steps (< 1)
var _stow_clip := 0 # 0 = Stow (p rising), 1 = Deploy (p falling); switches when dp/dt changes sign
var _stow_data: Dictionary = {}
var _stow_anims: Array[Animation] = []
var _stow_maps: Array[Dictionary] = [] # per clip: bone -> Vector3i(position, rotation, scale track), -1 = rest
var _stow_bones: Array[int] = [] # every bone either clip moves (Carriage/Roll stay with the chase)
var _stow_pose: Dictionary = {} # bone -> [position, rotation, scale] sampled once per frame
var _stow_from: Dictionary = {} # cross-fade source
var _stow_fade := 1.0
var _spin_extra := 0.0 # Coasting spin accumulated while the preview clock is frozen.
var _last_wheel_distance := 0.0
var _beacons: Array[Array] = [] # [MeshInstance3D, surface, lit material]
var _beacon_time := 0.0
var _lifts := PackedFloat32Array() # last chase lift per blade
var _stow_lifts := PackedFloat32Array() # chase lifts held when the stow starts, sinking to zero
var _stow_drive := 0.0 # operator's DRIVE input when the stow began; eases to zero on the stow clock
var _stow_idle := -1.0 # seconds resting fully stowed (operator vignettes); -1 = not at rest
var _retreat := 0.0 # metres the fully stowed carriage has backed (+Z) away from where it stowed; deploy waits for 0
var _retreat_speed := 0.0 # signed m/s along +Z
var _retreat_origin_z := 0.0 # carriage Z when this stow began
var _tower_lay := 1.0 # 1 = davit towers hanging (deployed rest), 0 = upright as both clips start/end
var _tower_hold_p := 0.0 # p below which neither clip moves a tower
var _tower_bones: Array[int] = [] # Davit_* luff roots
var _tower_turns: Array[Quaternion] = [] # per tower: local rotation that hangs it down

func configure_entrance(preview: bool, animate: bool) -> void:
	if dock != null: return
	dock = SawDockPresentation.new()
	dock.name = "SawServiceDock"
	add_child(dock)
	dock.setup(preview, animate)
	position = dock.carriage_position()
	# The towers stay upright between the vessel's lift-bay posts and lie down once the carriage is on the belt.
	_tower_lay = 1.0 if dock.is_deployed() else 0.0

func finish_entrance() -> void:
	if dock != null and not dock.is_deployed():
		dock.restore_deployed()
	_tower_lay = 1.0
	if operator_arriving(): operator_seat.seat_transfer.finish_arrival()

func prepare_operator_arrival() -> void:
	if model == null: _load_model()
	operator_seat.seat_transfer.begin_arrival()

func operator_arriving() -> bool:
	return operator_seat != null and operator_seat.seat_transfer.is_arriving()

## Load the carriage ahead of a mid-round appearance (the 2P tutorial's saw lesson)
## so the first visible frame does not stall on the GLB.
func preload_model() -> void:
	if model == null:
		_load_model()

func _load_model() -> void:
	model = (load(MODEL_PATH) as PackedScene).instantiate()
	model.rotation.y = PI # Blender +Y exports toward Godot -Z.
	add_child(model)
	GraphicsQuality.drop_tiny_shadow_casters(model)
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
				# Polished steel with the stage's steel relief; one material shared by every spindle.
				post.material_override = preload("res://scripts/world/wall_materials.gd").spindle_steel(
					Color(0.32, 0.36, 0.40), 0.85, 0.28)
				add_child(post)
				lift_posts.append(post)
	_setup_stow()

func _setup_stow() -> void:
	if animation == null or skeleton == null: return
	var anims: Array[Animation] = []
	var maps: Array[Dictionary] = []
	for clip: StringName in [STOW_CLIP, DEPLOY_CLIP]:
		if not animation.has_animation(clip): return
		var anim := animation.get_animation(clip)
		var map: Dictionary = {}
		for track: int in anim.get_track_count():
			var slot := [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D].find(anim.track_get_type(track))
			var bone := skeleton.find_bone(str(anim.track_get_path(track).get_concatenated_subnames()))
			# Carriage/Roll stay with the chase; everything else (Spin + stow rig) follows the clip.
			if slot < 0 or bone < 0 or skeleton.get_bone_name(bone).get_slice("_", 0) in ["Carriage", "Roll"]: continue
			var entry: Vector3i = map.get(bone, Vector3i(-1, -1, -1))
			entry[slot] = track
			map[bone] = entry
			if not _stow_bones.has(bone): _stow_bones.append(bone)
		anims.append(anim)
		maps.append(map)
	_stow_anims = anims
	_stow_maps = maps
	_stow_data = load_stow_data(STOW_DATA_PATH, anims[0].length)
	for bone: int in skeleton.get_bone_count():
		if not skeleton.get_bone_name(bone).begins_with("Davit_"): continue
		# Swung outboard over the belt edge until it hangs down beside the conveyor. The luff hinge and its
		# outboard sense come from the Stow clip's parked pose; TOWER_HANG_TILT keeps the mast's inner face
		# off the conveyor side frame (|x| 12.0, top 0.08 m above the belt).
		var rest_rotation := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var luff: int = (maps[0].get(bone, Vector3i(-1, -1, -1)) as Vector3i).y
		var parked := anims[0].rotation_track_interpolate(luff, anims[0].length) if luff >= 0 else rest_rotation
		_tower_bones.append(bone)
		_tower_turns.append(Quaternion((rest_rotation.inverse() * parked).normalized().get_axis(), PI - TOWER_HANG_TILT))
	_tower_hold_p = _tower_rest_span()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null: continue
		for surface: int in mesh_instance.mesh.get_surface_count():
			var lens := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if lens == null or lens.resource_name != BEACON_MATERIAL: continue
			# Per-instance copy: the lens stays dark at rest and flashes only while the machine works.
			var lit := lens.duplicate() as BaseMaterial3D
			lit.emission_enabled = true
			lit.emission_energy_multiplier = 0.0
			mesh_instance.set_surface_override_material(surface, lit)
			_beacons.append([mesh_instance, surface, lit])

## Sidecar written by tools/saw_stow/build_stow.py (stage "sidecar"): wall/chair intervals and the
## 30 Hz speed curve on the stow clock p. Without it the stow still plays, conservatively: walls break
## for the whole move and the operator chair never launches while the rack is off its rest.
static func load_stow_data(path: String, clip_length: float) -> Dictionary:
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary: data = parsed
	var length := float(data.get("length", clip_length))
	return {
		"length": length,
		"brake_seconds": float(data.get("brake_seconds", 1.3)),
		"curve_rate": float(data.get("curve_rate", 30.0)),
		"wall_block": data.get("wall_block", [{"from": 0.0, "to": length, "reach_y": 2.0}]),
		"station_airspace": data.get("station_airspace", [0.0, length]),
		"chair_column": data.get("chair_column", [0.0, length]),
		"speed_env": PackedFloat32Array(data.get("speed_env", [4.5])),
		"fallback": data.is_empty(),
	}

func is_stow_clear() -> bool:
	return _stow_p <= 0.0 and _stow_rate == 0.0

func is_fully_stowed() -> bool:
	return not _stow_anims.is_empty() and _stow_p >= stow_length()

## Stow clock p: 0 = deployed rest, stow_length() = parked beside the conveyor. Deploy runs it backwards.
func stow_time() -> float:
	return _stow_p

func stow_length() -> float:
	return float(_stow_data.get("length", 0.0))

func stow_brake_seconds() -> float:
	return float(_stow_data.get("brake_seconds", 1.3))

## True while any part of the machine stands over the belt: walls must break before reaching it.
func stow_blocks_walls() -> bool:
	return wall_reach_y() > 0.0

## Half depth (carriage Z) of the machine over the belt at the current p; 0 when nothing is there.
func wall_reach_y() -> float:
	var reach := 0.0
	for block: Dictionary in _stow_data.get("wall_block", []):
		if _stow_p > float(block.from) and _stow_p < float(block.to): reach = maxf(reach, float(block.reach_y))
	return reach

func rack_over_station() -> bool:
	return _in_span(_stow_data.get("station_airspace", []), _stow_p, _stow_p)

## Whether the operator chair may launch now: no blade crosses the chair column within `lookahead`
## seconds of stow motion (|dp/dt| <= STOW_SPEED, so p moves at most that far the way it is heading).
func chair_launch_clear(lookahead: float) -> bool:
	if _stow_anims.is_empty(): return true
	var span := maxf(lookahead, 0.0) * STOW_SPEED
	var low := _stow_p - (span if not stow_target or _stow_rate < 0.0 else 0.0)
	var high := _stow_p + (span if stow_target or _stow_rate > 0.0 else 0.0)
	return not _in_span(_stow_data.get("chair_column", []), low, high)

## Clip time p below which neither clip moves any tower bone (Stow sampled at p, Deploy at length - p).
func _tower_rest_span() -> float:
	var hold := _stow_anims[0].length
	for clip: int in 2:
		var anim := _stow_anims[clip]
		for track: int in anim.get_track_count():
			var bone := skeleton.find_bone(str(anim.track_get_path(track).get_concatenated_subnames()))
			if bone < 0 or skeleton.get_bone_name(bone).get_slice("_", 0) not in ["Davit", "DavitS2", "DavitS3", "DavitS4", "DavitS5", "DavitS6", "Knuckle", "BeamFlyP", "BeamFlyN", "Jaw"]: continue
			var rest := skeleton.get_bone_rest(bone)
			var p := 0.0
			while p < hold:
				var t := p if clip == 0 else anim.length - p
				var moved := false
				match anim.track_get_type(track):
					Animation.TYPE_POSITION_3D: moved = anim.position_track_interpolate(track, t).distance_to(rest.origin) > 0.002
					Animation.TYPE_ROTATION_3D: moved = anim.rotation_track_interpolate(track, t).angle_to(rest.basis.get_rotation_quaternion()) > 0.002
				if moved:
					hold = maxf(p - 1.0 / 48.0, 0.0)
					break
				p += 1.0 / 48.0
	return hold

func _tower_lay_target() -> float:
	if dock != null and not dock.is_deployed(): return 0.0
	return 0.0 if stow_target or _stow_p > _tower_hold_p else 1.0

func _step_tower_lay(dt: float) -> bool:
	var before := _tower_lay
	_tower_lay = move_toward(_tower_lay, _tower_lay_target(), maxf(dt, 0.0) / TOWER_LAY_SECONDS)
	return _tower_lay != before

func _apply_tower_lay() -> void:
	var lay := smoothstep(0.0, 1.0, _tower_lay)
	for i: int in _tower_bones.size():
		var bone := _tower_bones[i]
		var base: Quaternion = _stow_pose[bone][1] if _stow_pose.has(bone) else skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(bone, base * Quaternion.IDENTITY.slerp(_tower_turns[i], lay))

static func _in_span(span: Array, low: float, high: float) -> bool:
	return span.size() >= 2 and high > float(span[0]) and low < float(span[1])

## Machine speed (m/s of its fastest tracked point) per unit of dp/dt at p.
func stow_speed(p: float) -> float:
	return _stow_curve("speed_env", p)

func _stow_curve(key: String, p: float) -> float:
	var values: PackedFloat32Array = _stow_data.get(key, PackedFloat32Array())
	if values.is_empty(): return 0.0
	var x := clampf(p * float(_stow_data.curve_rate), 0.0, values.size() - 1.0)
	var i := int(x)
	return lerpf(values[i], values[mini(i + 1, values.size() - 1)], x - i)

## Advances the stow toward stow_target in fixed 1/240 s steps, so p(t) does not depend on the frame
## rate. A reversal decelerates the machine at STOW_REVERSE_ACCEL before the other clip takes over.
## The menu freezes the preview clock whenever the saw is not clear, so the coasting spin is integrated
## here to keep the angle continuous.
func advance_stow(dt: float) -> void:
	if model == null: _load_model()
	if _stow_anims.is_empty(): return
	if is_stow_clear() and not stow_target:
		_stow_acc = 0.0
		if _step_tower_lay(dt):
			_apply_tower_lay()
			skeleton.force_update_all_bone_transforms()
		return
	var step := maxf(dt, 0.0)
	_stow_acc += step / STOW_STEP
	var steps := int(_stow_acc + 0.000001)
	_stow_acc -= steps
	# A blade the menu chase had lifted (catching a runner) sinks back instead of dropping.
	if is_stow_clear() and steps > 0:
		_retreat_origin_z = position.z
		_retreat = 0.0
		_retreat_speed = 0.0
		_stow_lifts = _lifts.duplicate()
		# The carriage coasts to a stop under the operator's hand as the stow begins.
		if operator_seat != null and not operator_seat.last_sample.is_empty(): _stow_drive = float(operator_seat.last_sample.drive)
	for i: int in steps:
		_stow_tick()
	if steps > 0: _sample_stow()
	_step_retreat(step)
	_update_beacons(step)
	_apply_spin(_preview_spin_seconds(), _last_wheel_distance)
	if is_stow_clear():
		for bone: int in _stow_bones:
			if not spin_bones.has(bone): skeleton.reset_bone_pose(bone)
		_apply_tower_lay()
		skeleton.force_update_all_bone_transforms()
	_update_operator_stow(step)

## The menu chase and preview clocks stop while the blades are racked, so the stow clock p drives
## the operator: STOW on the BLADE stick, watch the rack, duck while it passes overhead, look back as
## it parks, and the waiting vignettes while stowed. Deploy plays the same p backwards.
func _update_operator_stow(dt: float) -> void:
	if operator_seat == null or operator_seat.seat_transfer.owns_pose() or operator_seat.last_sample.is_empty(): return
	var length := stow_length()
	if _stow_p >= length:
		_stow_idle = maxf(_stow_idle, 0.0) + dt
	elif _stow_p <= length - SawOperatorPresentation.STOW_REST_FADE:
		_stow_idle = -1.0 # The stowed vignettes have faded out; the next rest starts fresh.
	operator_seat.apply_sample(SawOperatorPresentation.sample(
		dock.elapsed if dock != null else SawDockPresentation.FINISH_TIME, _preview_elapsed,
		_stow_drive * (1.0 - smoothstep(0.0, .6, _stow_p)), 0.0, true, 0.0, 0.0,
		{"rpm": _preview_spin_rate(), "stow": _stow_p, "stow_length": length, "stow_rate": _stow_rate, "stow_idle": _stow_idle}))

func _stow_tick() -> void:
	var length := stow_length()
	var want := 1.0 if stow_target else -1.0
	if (want > 0.0 and _stow_p >= length) or (want < 0.0 and _stow_p <= 0.0): want = 0.0
	if want < 0.0 and _retreat > 0.0: want = 0.0 # the carriage rolls back to where it stowed before the deploy starts
	var rate := move_toward(_stow_rate, want, STOW_REVERSE_ACCEL / maxf(stow_speed(_stow_p) * STOW_SPEED, 0.05) * STOW_STEP)
	var clip := _stow_clip if rate == 0.0 else (0 if rate > 0.0 else 1)
	if clip != _stow_clip:
		# Reversal: hold what is on screen and blend onto the other clip (it has its own sway).
		# At either end both clips share the exact pose, so nothing needs blending there.
		_stow_clip = clip
		if _stow_p > 0.0 and _stow_p < length:
			_stow_from = _stow_pose.duplicate()
			_stow_fade = 0.0
	_spin_extra += _preview_spin_rate() * STOW_STEP
	for i: int in _stow_lifts.size(): _stow_lifts[i] = move_toward(_stow_lifts[i], 0.0, STOW_LIFT_SETTLE * STOW_STEP)
	_tower_lay = move_toward(_tower_lay, _tower_lay_target(), STOW_STEP / TOWER_LAY_SECONDS)
	_stow_rate = rate
	_stow_p = clampf(_stow_p + rate * STOW_SPEED * STOW_STEP, 0.0, length)
	if (_stow_p >= length and rate > 0.0) or (_stow_p <= 0.0 and rate < 0.0): _stow_rate = 0.0
	if _tower_lay > 0.0 and _stow_p > _tower_hold_p:
		# The towers finish standing up before the clip moves them.
		_stow_p = _tower_hold_p
		_stow_rate = 0.0
	_stow_fade = minf(1.0, _stow_fade + STOW_STEP / STOW_CROSSFADE)

## Once the blades are fully racked the carriage backs away to the end of the belt (the menu chase's
## home Z), clear of the playfield; before a deploy it rolls forward to where it stowed. Wheels roll with it.
func _retreat_goal() -> float:
	if not stow_target or _stow_p < stow_length(): return 0.0
	return maxf(SawDockPresentation.MENU_Z - _retreat_origin_z, 0.0)

func _step_retreat(dt: float) -> void:
	var remaining := _retreat_goal() - _retreat
	var before := _retreat
	if absf(remaining) < 0.005:
		_retreat += remaining
		_retreat_speed = 0.0
	else:
		var want := signf(remaining) * minf(STOW_RETREAT_SPEED, sqrt(2.0 * STOW_RETREAT_ACCEL * absf(remaining)))
		_retreat_speed = move_toward(_retreat_speed, want, STOW_RETREAT_ACCEL * maxf(dt, 0.0))
		_retreat += _retreat_speed * maxf(dt, 0.0)
		if (_retreat - _retreat_goal()) * signf(remaining) > 0.0: # never overshoot the goal
			_retreat = _retreat_goal()
			_retreat_speed = 0.0
	if _retreat != before:
		position.z = _retreat_origin_z + _retreat
		_last_wheel_distance += _retreat - before

func _stow_clip_time() -> float:
	return _stow_p if _stow_clip == 0 else stow_length() - _stow_p

## Blade spin (fraction of full speed): coasts down with the brake at the start of the stow clock.
func _preview_spin_rate() -> float:
	return smoothstep(0.0, SawChaseState.SPINUP_SECONDS, _preview_elapsed) * (1.0 - smoothstep(0.0, stow_brake_seconds(), _stow_p))

## One sample of the active clip per advance, shared by _apply_stow and _blade_base.
func _sample_stow() -> void:
	_stow_pose.clear()
	if is_stow_clear(): return
	var anim := _stow_anims[_stow_clip]
	var map := _stow_maps[_stow_clip]
	var time := clampf(_stow_clip_time(), 0.0, anim.length)
	var blend := smoothstep(0.0, 1.0, _stow_fade)
	for bone: int in _stow_bones:
		var tracks: Vector3i = map.get(bone, Vector3i(-1, -1, -1))
		var rest := skeleton.get_bone_rest(bone)
		# Import drops tracks that never leave the rest pose.
		var pose := [
			anim.position_track_interpolate(tracks.x, time) if tracks.x >= 0 else rest.origin,
			anim.rotation_track_interpolate(tracks.y, time) if tracks.y >= 0 else rest.basis.get_rotation_quaternion(),
			anim.scale_track_interpolate(tracks.z, time) if tracks.z >= 0 else rest.basis.get_scale()]
		if blend < 1.0 and _stow_from.has(bone):
			var from: Array = _stow_from[bone]
			pose = [(from[0] as Vector3).lerp(pose[0], blend), (from[1] as Quaternion).slerp(pose[1], blend), (from[2] as Vector3).lerp(pose[2], blend)]
		_stow_pose[bone] = pose

## Rotating-mirror beacons: a sharp flash about 1.5 times a second while the machine works, dark at rest.
func _update_beacons(step: float) -> void:
	var working := _stow_rate != 0.0 or (_stow_p > 0.0 and _stow_p < stow_length())
	_beacon_time = _beacon_time + step if working else 0.0
	var energy := 7.0 * pow(maxf(0.0, cos(TAU * 1.5 * _beacon_time)), 8.0) if working else 0.0
	for beacon: Array in _beacons:
		(beacon[2] as BaseMaterial3D).emission_energy_multiplier = energy

func beacons_lit() -> bool:
	for beacon: Array in _beacons:
		if (beacon[2] as BaseMaterial3D).emission_energy_multiplier > 0.0: return true
	return false

func _preview_spin_seconds() -> float:
	return accelerated_spin_time(_preview_elapsed) + _spin_extra

func _apply_stow() -> void:
	for bone: int in _stow_pose:
		var pose: Array = _stow_pose[bone]
		var rotation: Quaternion = pose[1]
		if spin_bones.has(bone):
			# Tilt in the parent space, keeping the blade's own spin about its axis. Its position
			# comes through _blade_base, under the chase lift.
			var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			rotation = rotation * rest.inverse() * skeleton.get_bone_pose_rotation(bone)
		else:
			skeleton.set_bone_pose_position(bone, pose[0])
		skeleton.set_bone_pose_rotation(bone, rotation)
		skeleton.set_bone_pose_scale(bone, pose[2])
	_apply_tower_lay()

func _blade_base(bone: int) -> Vector3:
	if _stow_pose.has(bone): return _stow_pose[bone][0]
	return skeleton.get_bone_rest(bone).origin

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
		_apply_spin(_preview_spin_seconds(), -dock.wheel_distance())
	else:
		_preview_elapsed += dt
		position = Vector3(0.0, StageConstants.FLOOR_TOP_Y, SawDockPresentation.MENU_Z)
		_apply_spin(_preview_spin_seconds(), 0.0)
	if _menu_chase!=null and (dock==null or dock.is_deployed()):
		position.z=_menu_chase.local_z
		_apply_spin(_preview_spin_seconds(),_menu_chase.travel-(dock.wheel_distance() if dock else 0.0))
	else:
		_update_operator(null, dt)

func apply_menu_chase(gs: QuizGameState, state: MenuSawChaseState, dt: float) -> void:
	_menu_chase=state
	if dock!=null and not dock.is_deployed():return
	position.z=state.local_z
	_apply_spin(_preview_spin_seconds(),state.travel-(dock.wheel_distance() if dock else 0.0))
	_update_lifts(gs)
	# The operator celebrates a menu catch on the same clock as the blade's catch lift.
	var catch_age := -1.0
	if state.phase == MenuSawChaseState.Phase.CATCHING: catch_age = state.clock
	elif state.phase == MenuSawChaseState.Phase.RETURNING: catch_age = MenuSawChaseState.CATCH_SECONDS + state.clock
	_update_operator(gs,dt,true,-state.velocity/MenuSawChaseState.RETURN_SPEED,catch_age)

## Seconds since the most recent blade catch (from recorded death timers), or -1.
static func operator_catch_age(gs: QuizGameState) -> float:
	var age := INF
	if gs.p1_saw_killed: age = minf(age, gs.game_over_timer)
	if gs.num_players >= 2 and gs.p2_saw_killed: age = minf(age, gs.player2_game_over_timer)
	return age if age < SawOperatorPresentation.CATCH_SECONDS else -1.0

func _update_operator(gs: QuizGameState, dt: float, menu: bool=false, drive_override: float=NAN, menu_catch: float=-1.0) -> void:
	if operator_seat == null: return
	menu=menu or gs==null
	# Menu transfer travels toward -Z; retain the physical left side of travel.
	operator_seat.position = SawOperatorPresentation.MOUNT * Vector3(-1,1,-1) if menu else SawOperatorPresentation.MOUNT
	operator_seat.rotation.y = SawOperatorPresentation.FACING_YAW + (PI if menu else 0.0)
	# Without a transport the deck is long settled; the dock clock only shapes the arrival.
	var entry := dock.elapsed if dock != null else SawDockPresentation.FINISH_TIME
	var deployed := dock == null or dock.is_deployed()
	var spin: float = _preview_elapsed if menu else _landing_spin_elapsed + gs.saw.elapsed
	var extra := {"catch": menu_catch} if menu else {}
	if menu and _stow_p > 0.0: extra.rpm = _preview_spin_rate()
	var drive := 0.0
	if gs != null and not menu:
		if gs.is_replay: spin = SawChaseState.SPINUP_SECONDS + gs.saw.elapsed
		if gs.saw.elapsed < _operator_elapsed:
			operator_seat.reset_pose()
			_operator_lifts.clear()
			_operator_idle = 0.0
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
			# Shutdown routine on the stop clock; the needles follow the braking blades.
			extra.stop = gs.saw.stop_elapsed
			extra.rpm = smoothstep(0.0, SawChaseState.SPINUP_SECONDS, spin) * gs.saw.stop_speed_ratio()
		extra.catch = operator_catch_age(gs)
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
	# The waiting clock starts once the deck is down, so the first vignette never pops in.
	if spin<=0.0 and dt>0.0 and deployed:_operator_idle+=dt
	operator_seat.apply_sample(SawOperatorPresentation.sample(entry,spin,drive,lift,deployed,rate,_operator_idle,extra))

func _apply_spin(seconds: float, wheel_distance: float) -> void:
	_last_wheel_distance = wheel_distance
	if animation != null and not spin_clip.is_empty():
		var duration := animation.get_animation(spin_clip).length
		animation.seek(fposmod(seconds * SawChaseState.BLADE_RPM / 18.0, duration), true)
	if skeleton != null:
		for bone: int in wheel_bones:
			var rest_rotation := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(bone, rest_rotation * Quaternion(Vector3.UP, -wheel_distance / SawChaseState.WHEEL_RADIUS))
		for i: int in spin_bones.size():
			_set_lift(i, _stow_lifts[i] if i < _stow_lifts.size() and not is_stow_clear() else 0.0)
		_apply_stow()
		skeleton.force_update_all_bone_transforms()

func _set_lift(index: int, height: float) -> void:
	if _lifts.size() != spin_bones.size(): _lifts.resize(spin_bones.size())
	_lifts[index] = height
	var bone := spin_bones[index]
	var base := _blade_base(bone)
	skeleton.set_bone_pose_position(bone, base + Vector3.UP * height)
	var post := lift_posts[index]
	post.visible = height > 0.01
	post.position = Vector3(-base.x, base.y + height * 0.5, -base.z)
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
	_step_tower_lay(dt)
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

@tool
class_name SeatedSpectatorKit
extends RefCounted

## Goal-stand spectators (assets/goal_stand/goal_stand_spectator.glb) prepared for
## a seated, instanced crowd. The rig skins every box 100% to one bone, so the
## crowd is drawn with MultiMesh and skinned in the vertex shader:
##
## - mesh: the seven hairstyle bodies merged into one surface; prop_mesh adds the
##   seated hand props for the spectators that hold one. UV keeps the palette
##   role, UV2.x is the bone, UV2.y a bit mask: bits 0..6 the hairstyles that use
##   the triangle, bit 6 + prop for a prop triangle (the shader collapses
##   everything a spectator does not wear or hold).
## - bone texture: one row per baked frame, three texels (a 3x4 matrix) per bone.
##   The legs are posed seated on top of each clip, the hips stay on the seat
##   and only the upper body plays the goal stand's own animation. The stadium
##   wave (SPEC_StandWave) is the exception: the hips rise off the seat and the
##   legs straighten over the same feet.
## - sync textures: the winner's dance for each side, baked a few frames at a time
##   once the match knows the emotes (prepare_sync / step_sync), so the side
##   stands can dance in step with the winner (docs/crowd_extras.md).
##
## Model space: the seat contact under the hips is the origin and the spectator
## faces +Z, the same way as the goal stand rig.

const SPECTATOR_SCENE_PATH := "res://assets/goal_stand/goal_stand_spectator.glb"
const CLIPS_PATH := "res://assets/goal_stand/goal_stand_clips.json"
const SHADER: Shader = preload("res://shaders/seated_spectator.gdshader")
const HAIRS: Array[String] = ["Short", "Long", "Cap", "Afro", "Bald", "Bun", "Headband"]
const BAKE_FPS := 20.0
const MAX_CLIPS := 40
## Thighs point forward and slightly down, so the feet reach the terrace floor.
const THIGH_PITCH := deg_to_rad(-78.0)
const KNEE_SPREAD := 0.09
## Seat contact is this far below the hip joints (half the thigh block).
const SEAT_BELOW_HIP := 0.09
## Seat bounce and hip sway kept from each clip (full values would lift the
## spectator out of the chair).
const HIP_BOUNCE := 0.25
const HIP_SWAY := 0.5
## Standing up for the wave: hips this high above the ankles (rest 0.813, knees
## slightly bent) and this far behind them.
const STAND_HIP_OVER_ANKLE := 0.78
const STAND_HIP_BEHIND := 0.05

## Every baked clip, in the order seated_spectator.gdshader indexes them (C_*).
const CLIPS: Array[StringName] = [
	&"SPEC_Idle", &"SPEC_FoldArms", &"SPEC_Talk", &"SPEC_Phone", &"SPEC_Nod",          # 0..4 idle, calm bursts 2..4
	&"SPEC_Clap", &"SPEC_Cheer", &"SPEC_Wave", &"SPEC_Shout", &"SPEC_Anticipate",      # 5..9 fan bursts
	&"SPEC_Dance_YMCA", &"SPEC_Dance_Gangnam", &"SPEC_DanceBounce", &"SPEC_Dance_Silly",  # 10..13 party bursts
	&"SPEC_Despair", &"SPEC_ShakeHead", &"SPEC_PointLaugh", &"SPEC_Gasp",              # 14..17
	&"SPEC_Doze", &"SPEC_WakeUp", &"SPEC_Eat", &"SPEC_Selfie", &"SPEC_Binoculars",     # 18..22
	&"SPEC_Megaphone", &"SPEC_Drum", &"SPEC_ChantClap", &"SPEC_StandWave",             # 23..26
	&"SPEC_TowelSpin", &"SPEC_HighFiveL", &"SPEC_HighFiveR", &"SPEC_ShoulderL", &"SPEC_ShoulderR",  # 27..31
]
const IDLE_CLIP_COUNT := 2       # SPEC_Idle / SPEC_FoldArms are resting poses
## Hand props merged into the seated mesh. A spectator's prop is 1 + its index
## here (0 = empty hands); the towel fan carries both towels and the shader shows
## the one that fits the current clip.
const PROPS: Array[String] = ["GSP_Popcorn", "GSP_HotDog", "GSP_Phone", "GSP_Binoculars", "GSP_Megaphone",
	"GSP_Drum", "GSP_Towel", "GSP_TowelNeck"]
const PROP_POPCORN := 1
const PROP_HOTDOG := 2
const PROP_PHONE := 3
const PROP_BINOCULARS := 4
const PROP_MEGAPHONE := 5
const PROP_DRUM := 6
const PROP_TOWEL := 7
const PROP_BIT_BASE := 6         # prop p uses mask bit PROP_BIT_BASE + p

static var _mesh: ArrayMesh = null
## The same bodies plus the hand props, for the few spectators that hold one (the
## props would otherwise cost every seat their collapsed vertices).
static var _prop_mesh: ArrayMesh = null
static var _material: ShaderMaterial = null
static var _bone_texture: ImageTexture = null
static var _clip_table: PackedVector4Array = PackedVector4Array()
static var _bone_count := 0
static var _frame_rows := 0
static var _clip_meta := {}
## Source rig kept for the sync bakes: {root, skeleton, player, binds, bind_bones, seat}.
static var _source := {}
## Per sync slot (1, 2): {clip, frames, rows, done}.
static var _sync := {}


static func is_built() -> bool:
	return _mesh != null


static func mesh() -> ArrayMesh:
	_ensure()
	return _mesh


static func prop_mesh() -> ArrayMesh:
	_ensure()
	return _prop_mesh


static func material() -> ShaderMaterial:
	_ensure()
	return _material


static func bone_count() -> int:
	_ensure()
	return _bone_count


static func frame_rows() -> int:
	_ensure()
	return _frame_rows


static func clip_index(clip: StringName) -> int:
	return CLIPS.find(clip)


static func all_clips() -> Array[StringName]:
	return CLIPS.duplicate()


## Seconds of a baked clip (0 when unknown).
static func clip_seconds(clip: StringName) -> float:
	var index := clip_index(clip)
	if index < 0 or index >= _clip_table.size():
		return 0.0
	return _clip_table[index].w


static func _ensure() -> void:
	if _mesh != null:
		return
	var scene := load(SPECTATOR_SCENE_PATH) as PackedScene
	var root := scene.instantiate() as Node3D
	var skeleton := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CLIPS_PATH))
	_clip_meta = (parsed as Dictionary).get("clips", {}) if parsed is Dictionary else {}
	var bodies: Array[MeshInstance3D] = []
	for hair: String in HAIRS:
		bodies.append(root.find_child("SPEC_Body_" + hair, true, false) as MeshInstance3D)
	var props: Array[MeshInstance3D] = []
	for prop: String in PROPS:
		props.append(root.find_child(prop, true, false) as MeshInstance3D)
	var skin: Skin = bodies[0].skin
	_bone_count = skin.get_bind_count()
	var bind_bones := PackedInt32Array()
	var binds: Array[Transform3D] = []
	for bind: int in range(_bone_count):
		bind_bones.append(skeleton.find_bone(skin.get_bind_name(bind)))
		binds.append(skin.get_bind_pose(bind))
	_mesh = _merge(bodies, [], skin)
	_prop_mesh = _merge(bodies, props, skin)
	var rows := PackedFloat32Array()
	_clip_table = PackedVector4Array()
	_frame_rows = 0
	var seat_offset := _seat_offset(skeleton)
	_source = {"root": root, "skeleton": skeleton, "player": player, "binds": binds, "bind_bones": bind_bones, "seat": seat_offset}
	for clip: StringName in CLIPS:
		var animation := player.get_animation(clip) if player.has_animation(clip) else null
		if animation == null:
			# An older GLB without the crowd extras: hold the first idle instead.
			animation = player.get_animation(CLIPS[0])
		var frames := maxi(1, int(round(animation.length * BAKE_FPS)))
		_clip_table.append(Vector4(float(_frame_rows), float(frames), BAKE_FPS, animation.length))
		var rise := _rise_curve(clip)
		for frame: int in range(frames):
			var time := float(frame) / BAKE_FPS
			rows.append_array(_bake_frame(animation, time, _rise_at(rise, time)))
			_frame_rows += 1
	var image := Image.create_from_data(_bone_count * 3, _frame_rows, false, Image.FORMAT_RGBAF, rows.to_byte_array())
	_bone_texture = ImageTexture.create_from_image(image)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("bone_texture", _bone_texture)
	var table: Array[Vector4] = []
	for entry: Vector4 in _clip_table:
		table.append(entry)
	while table.size() < MAX_CLIPS:
		table.append(Vector4.ZERO)
	_material.set_shader_parameter("clips", table)
	_material.set_shader_parameter("skins", _colors(GoalStand.SKINS))
	_material.set_shader_parameter("hair_colors", _colors(GoalStand.HAIR_COLORS))
	_material.set_shader_parameter("pants_colors", _colors(GoalStand.PANTS))
	_material.set_shader_parameter("shoe_colors", _colors(GoalStand.SHOES))
	_material.set_shader_parameter("team_colors", [GoalStand.NEUTRAL_SHIRTS[4], GoalStand.P1_COLOR, GoalStand.P2_COLOR])
	_sync = {}


static func _colors(source: Array) -> Array[Color]:
	var out: Array[Color] = []
	for color: Color in source:
		out.append(color)
	while out.size() < 8:
		out.append(out[out.size() - 1])
	return out


## One baked frame: three texels (rows of the 3x4 skinning matrix) per bind.
static func _bake_frame(animation: Animation, time: float, rise: float) -> PackedFloat32Array:
	var skeleton := _source.skeleton as Skeleton3D
	var binds: Array[Transform3D] = _source.binds
	var bind_bones: PackedInt32Array = _source.bind_bones
	var locals := _sample_locals(skeleton, animation, time)
	var poses := _seated_globals(skeleton, locals, _source.seat, rise)
	var rows := PackedFloat32Array()
	for bind: int in range(binds.size()):
		var matrix: Transform3D = poses[bind_bones[bind]] * binds[bind]
		for axis: int in range(3):
			rows.append(matrix.basis.x[axis])
			rows.append(matrix.basis.y[axis])
			rows.append(matrix.basis.z[axis])
			rows.append(matrix.origin[axis])
	return rows


## [up from, up to, down from, down to] in seconds, or empty for a seated clip.
static func _rise_curve(clip: StringName) -> PackedFloat32Array:
	var info: Dictionary = _clip_meta.get(String(clip), {})
	var rise: Array = info.get("rise", [])
	return PackedFloat32Array(rise) if rise.size() == 4 else PackedFloat32Array()


static func _rise_at(rise: PackedFloat32Array, time: float) -> float:
	if rise.is_empty():
		return 0.0
	return smoothstep(rise[0], rise[1], time) * (1.0 - smoothstep(rise[2], rise[3], time))


## Translation that puts the seat contact under the hips at the origin.
static func _seat_offset(skeleton: Skeleton3D) -> Vector3:
	var hip := skeleton.get_bone_global_rest(skeleton.find_bone("thigh_l")).origin
	return Vector3(0.0, -(hip.y - SEAT_BELOW_HIP), -hip.z)


## Global bone transforms for the current animation frame with the lower body
## seated: hips pinned to the chair, thighs forward, calves down, feet flat.
static func _sample_locals(skeleton: Skeleton3D, animation: Animation, time: float) -> Array[Transform3D]:
	var positions := {}
	var rotations := {}
	var scales := {}
	for track: int in range(animation.get_track_count()):
		var bone := skeleton.find_bone(String(animation.track_get_path(track).get_concatenated_subnames()))
		if bone < 0:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				positions[bone] = animation.position_track_interpolate(track, time)
			Animation.TYPE_ROTATION_3D:
				rotations[bone] = animation.rotation_track_interpolate(track, time)
			Animation.TYPE_SCALE_3D:
				scales[bone] = animation.scale_track_interpolate(track, time)
	var locals: Array[Transform3D] = []
	for bone: int in range(skeleton.get_bone_count()):
		var rest := skeleton.get_bone_rest(bone)
		var rotation: Quaternion = rotations.get(bone, rest.basis.get_rotation_quaternion())
		var scale: Vector3 = scales.get(bone, rest.basis.get_scale())
		var origin: Vector3 = positions.get(bone, rest.origin)
		locals.append(Transform3D(Basis(rotation) * Basis.from_scale(scale), origin))
	return locals


## `rise` 0 keeps the spectator seated; towards 1 the hips leave the seat and the
## legs straighten over the seated feet (the stadium wave).
static func _seated_globals(skeleton: Skeleton3D, locals: Array[Transform3D], seat_offset: Vector3,
		rise: float = 0.0) -> Array[Transform3D]:
	var count := skeleton.get_bone_count()
	var poses: Array[Transform3D] = []
	poses.resize(count)
	var pelvis := skeleton.find_bone("pelvis")
	var legs := {}
	for side: String in ["l", "r"]:
		var spread := KNEE_SPREAD if side == "l" else -KNEE_SPREAD
		legs[skeleton.find_bone("thigh_" + side)] = spread
		legs[skeleton.find_bone("calf_" + side)] = spread
		legs[skeleton.find_bone("foot_" + side)] = spread
		legs[skeleton.find_bone("ball_" + side)] = spread
	var shift := Transform3D(Basis.IDENTITY, seat_offset)
	var standing := {}
	if rise > 0.0:
		standing = _standing_legs(skeleton, rise)
	for bone: int in range(count):
		var parent := skeleton.get_bone_parent(bone)
		var local := locals[bone]
		var global: Transform3D = local if parent < 0 else poses[parent] * local
		var rest := skeleton.get_bone_global_rest(bone)
		if bone == pelvis:
			var lift := clampf((global.origin.y - rest.origin.y) * HIP_BOUNCE, -0.03, 0.06)
			var turn := rest.basis.get_rotation_quaternion().slerp(global.basis.get_rotation_quaternion(), HIP_SWAY)
			var origin := rest.origin + Vector3(0.0, lift, 0.0)
			if standing.has("pelvis"):
				origin = origin.lerp(standing.pelvis, rise)
			global = Transform3D(Basis(turn), origin)
		elif standing.has(bone):
			global = _ik_leg_bone(skeleton, bone, parent, poses, rest, standing)
		elif legs.has(bone):
			var spread: float = legs[bone]
			var name := skeleton.get_bone_name(bone)
			var turn := Basis(Vector3.UP, spread)
			if name.begins_with("thigh"):
				turn = turn * Basis(Vector3.RIGHT, THIGH_PITCH)
				# Hip joint follows the (pinned) pelvis; the chain below is rigid.
				var hip: Vector3 = poses[parent] * (skeleton.get_bone_global_rest(parent).affine_inverse() * rest.origin)
				global = Transform3D(turn * rest.basis, hip)
			else:
				var parent_rest := skeleton.get_bone_global_rest(parent)
				var parent_turn := poses[parent].basis * parent_rest.basis.inverse()
				var joint: Vector3 = poses[parent].origin + parent_turn * (rest.origin - parent_rest.origin)
				global = Transform3D(turn * rest.basis, joint)
		poses[bone] = global
	for bone: int in range(count):
		poses[bone] = shift * poses[bone]
	return poses


## Where the seated legs put the ankles, and the standing hip target over them.
## Keys: "pelvis", plus thigh/calf bone ids -> side ("l"/"r") and "ankle_<side>".
static func _standing_legs(skeleton: Skeleton3D, rise: float) -> Dictionary:
	var seated: Array[Transform3D] = []
	var locals: Array[Transform3D] = []
	for bone: int in range(skeleton.get_bone_count()):
		locals.append(skeleton.get_bone_rest(bone))
	seated = _seated_globals(skeleton, locals, Vector3.ZERO, 0.0)
	var out := {}
	var ankles := Vector3.ZERO
	for side: String in ["l", "r"]:
		var foot := skeleton.find_bone("foot_" + side)
		out["ankle_" + side] = seated[foot].origin
		out["foot_basis_" + side] = seated[foot].basis
		ankles += seated[foot].origin * 0.5
		out[skeleton.find_bone("thigh_" + side)] = side
		out[skeleton.find_bone("calf_" + side)] = side
		out[foot] = side
		out[skeleton.find_bone("ball_" + side)] = side
	out["pelvis"] = ankles + Vector3(0.0, STAND_HIP_OVER_ANKLE, -STAND_HIP_BEHIND)
	return out


## Two-bone leg from the (rising) hip to the seated ankle, knee forward (+Z).
static func _ik_leg_bone(skeleton: Skeleton3D, bone: int, parent: int, poses: Array[Transform3D],
		rest: Transform3D, standing: Dictionary) -> Transform3D:
	var side: String = standing[bone]
	var name := skeleton.get_bone_name(bone)
	if name.begins_with("foot") or name.begins_with("ball"):
		var parent_rest := skeleton.get_bone_global_rest(parent)
		var parent_turn := poses[parent].basis * parent_rest.basis.inverse()
		var joint: Vector3 = poses[parent].origin + parent_turn * (rest.origin - parent_rest.origin)
		if name.begins_with("foot"):
			joint = standing["ankle_" + side]
			return Transform3D(standing["foot_basis_" + side], joint)
		return Transform3D(poses[parent].basis * skeleton.get_bone_rest(bone).basis, joint)
	var thigh := skeleton.find_bone("thigh_" + side)
	var calf := skeleton.find_bone("calf_" + side)
	var foot := skeleton.find_bone("foot_" + side)
	var hip_rest := skeleton.get_bone_global_rest(thigh)
	var knee_rest := skeleton.get_bone_global_rest(calf)
	var ankle_rest := skeleton.get_bone_global_rest(foot)
	var l1 := hip_rest.origin.distance_to(knee_rest.origin)
	var l2 := knee_rest.origin.distance_to(ankle_rest.origin)
	var pelvis := skeleton.find_bone("pelvis")
	var hip: Vector3 = poses[pelvis] * (skeleton.get_bone_global_rest(pelvis).affine_inverse() * hip_rest.origin)
	var ankle: Vector3 = standing["ankle_" + side]
	var to := ankle - hip
	var d := clampf(to.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var axis := to.normalized()
	var cos_a := (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var pole := Vector3(0.0, 0.0, 1.0)
	var perp := (pole - axis * pole.dot(axis)).normalized()
	var knee := hip + axis * (l1 * cos_a) + perp * (l1 * sin_a)
	if bone == thigh:
		return Transform3D(_aim(hip_rest.basis, knee_rest.origin - hip_rest.origin, knee - hip), hip)
	return Transform3D(_aim(knee_rest.basis, ankle_rest.origin - knee_rest.origin, ankle - knee), knee)


static func _aim(rest_basis: Basis, rest_dir: Vector3, dir: Vector3) -> Basis:
	return Basis(Quaternion(rest_dir.normalized(), dir.normalized())) * rest_basis


# ------------------------------------------------------------------ the winner's dance

## Starts baking `clip` (a SPEC_Dance_*) for sync slot 1 or 2; step_sync() does
## the work a few frames at a time. A slot already holding that clip is kept.
static func prepare_sync(slot: int, clip: StringName) -> void:
	_ensure()
	var current: Dictionary = _sync.get(slot, {})
	if StringName(current.get("clip", &"")) == clip:
		return
	var player := _source.player as AnimationPlayer
	if not player.has_animation(clip):
		_sync.erase(slot)
		_material.set_shader_parameter("sync_clip_%d" % slot, Vector4.ZERO)
		return
	var animation := player.get_animation(clip)
	var frames := maxi(1, int(round(animation.length * BAKE_FPS)))
	_sync[slot] = {"clip": clip, "frames": frames, "next": 0, "rows": PackedFloat32Array(), "seconds": animation.length,
		"done": false}
	_material.set_shader_parameter("sync_clip_%d" % slot, Vector4.ZERO)


## Bakes pending sync frames within `budget_usec`; true once nothing is pending.
static func step_sync(budget_usec: int = 1500) -> bool:
	if _sync.is_empty():
		return true
	var start := Time.get_ticks_usec()
	var player := _source.player as AnimationPlayer
	var pending := false
	for slot: int in _sync:
		var job: Dictionary = _sync[slot]
		if job.done:
			continue
		var animation := player.get_animation(job.clip)
		var rows: PackedFloat32Array = job.rows
		while int(job.next) < int(job.frames):
			rows.append_array(_bake_frame(animation, float(job.next) / BAKE_FPS, 0.0))
			job.next = int(job.next) + 1
			if Time.get_ticks_usec() - start > budget_usec:
				break
		job.rows = rows
		if int(job.next) >= int(job.frames):
			var image := Image.create_from_data(_bone_count * 3, int(job.frames), false, Image.FORMAT_RGBAF, rows.to_byte_array())
			_material.set_shader_parameter("sync_bones_%d" % slot, ImageTexture.create_from_image(image))
			_material.set_shader_parameter("sync_clip_%d" % slot, Vector4(0.0, float(job.frames), BAKE_FPS, float(job.seconds)))
			job.done = true
			job.rows = PackedFloat32Array()
		else:
			pending = true
		if Time.get_ticks_usec() - start > budget_usec:
			return false
	return not pending


static func sync_ready(slot: int) -> bool:
	return bool((_sync.get(slot, {}) as Dictionary).get("done", false))


static func sync_clip(slot: int) -> StringName:
	return StringName((_sync.get(slot, {}) as Dictionary).get("clip", &""))


# ------------------------------------------------------------------ mesh

## The pants block (pelvis) and the lowest shirt block (spine_01) of the goal
## stand bodies share their front face, which z-fights along the waist. Pull the
## pants' front just behind the shirt so the shirt always covers the seam.
const WAIST_GAP := 0.006
static var _fixed_bodies := {}


static func fix_waist(arrays: Array, skin: Skin) -> Array:
	var pelvis := -1
	var spine := -1
	for bind: int in range(skin.get_bind_count()):
		match String(skin.get_bind_name(bind)):
			"pelvis": pelvis = bind
			"spine_01": spine = bind
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var influences := bones.size() / vertices.size()
	var owner := PackedInt32Array()
	var shirt_front := -INF
	for v: int in range(vertices.size()):
		var best := 0
		for extra: int in range(1, influences):
			if weights[v * influences + extra] > weights[v * influences + best]:
				best = extra
		owner.append(bones[v * influences + best])
		if owner[v] == spine:
			shirt_front = maxf(shirt_front, vertices[v].z)   # the rig faces +Z
	if pelvis < 0 or shirt_front == -INF:
		return arrays
	for v: int in range(vertices.size()):
		if owner[v] == pelvis and vertices[v].z > shirt_front - WAIST_GAP:
			vertices[v].z = shirt_front - WAIST_GAP
	arrays[Mesh.ARRAY_VERTEX] = vertices
	return arrays


## Skinned body mesh with the waist fix, cached per source mesh (goal stand).
static func fixed_body(source: Mesh, skin: Skin) -> Mesh:
	var key := source.get_instance_id()
	if not _fixed_bodies.has(key):
		var fixed := ArrayMesh.new()
		var flags: int = source.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		fixed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fix_waist(source.surface_get_arrays(0), skin), [], {}, flags)
		fixed.surface_set_material(0, source.surface_get_material(0))
		_fixed_bodies[key] = fixed
	return _fixed_bodies[key]


## Union of the hairstyle bodies plus the props. Identical body triangles are
## shared and tagged with every hairstyle that owns them; a prop triangle carries
## its prop bit. Bones are rewritten to the body skin's bind order.
static func _merge(bodies: Array[MeshInstance3D], props: Array[MeshInstance3D], body_skin: Skin) -> ArrayMesh:
	var owners := {}
	var order: Array[String] = []
	var data := {}
	var sources: Array = []
	for style: int in range(bodies.size()):
		sources.append([bodies[style], 1 << style, true])
	for index: int in range(props.size()):
		if props[index] != null:
			sources.append([props[index], 1 << (PROP_BIT_BASE + index + 1), false])
	var bind_of := {}
	for bind: int in range(body_skin.get_bind_count()):
		bind_of[body_skin.get_bind_name(bind)] = bind
	for source: Array in sources:
		var node := source[0] as MeshInstance3D
		var bit: int = source[1]
		var arrays := node.mesh.surface_get_arrays(0)
		if source[2]:
			arrays = fix_waist(arrays, node.skin)
		var remap := PackedInt32Array()
		for bind: int in range(node.skin.get_bind_count()):
			remap.append(int(bind_of.get(node.skin.get_bind_name(bind), 0)))
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var influences := bones.size() / vertices.size()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices = PackedInt32Array(range(vertices.size()))
		for tri: int in range(0, indices.size(), 3):
			var corners := []
			var key := "" if source[2] else "p%d:" % bit
			for corner: int in range(3):
				var v := indices[tri + corner]
				var bone := bones[v * influences]
				var best := weights[v * influences]
				for extra: int in range(1, influences):
					if weights[v * influences + extra] > best:
						best = weights[v * influences + extra]
						bone = bones[v * influences + extra]
				bone = remap[bone]
				corners.append([vertices[v], normals[v], uvs[v], bone])
				key += "%.4f,%.4f,%.4f|%.3f|%d;" % [vertices[v].x, vertices[v].y, vertices[v].z, uvs[v].x, bone]
			if not owners.has(key):
				owners[key] = 0
				order.append(key)
				data[key] = corners
			owners[key] = int(owners[key]) | bit
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for key: String in order:
		var mask := float(owners[key])
		for corner: Array in data[key]:
			surface.set_color(Color.WHITE)
			surface.set_normal(corner[1])
			surface.set_uv(corner[2])
			surface.set_uv2(Vector2(float(corner[3]), mask))
			surface.add_vertex(corner[0])
	surface.index()
	return surface.commit()

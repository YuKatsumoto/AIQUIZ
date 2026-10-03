@tool
class_name SeatedSpectatorKit
extends RefCounted

## Goal-stand spectators (assets/goal_stand/goal_stand_spectator.glb) prepared for
## a seated, instanced crowd. The rig skins every box 100% to one bone, so the
## crowd is drawn with MultiMesh and skinned in the vertex shader:
##
## - mesh: the seven hairstyle bodies merged into one surface. UV keeps the
##   palette role, UV2.x is the bone, UV2.y a bit mask of the hairstyles that
##   use the triangle (the shader collapses the others).
## - bone texture: one row per baked frame, three texels (a 3x4 matrix) per bone.
##   The legs are posed seated on top of each clip, the hips stay on the seat
##   and only the upper body plays the goal stand's own animation.
##
## Model space: the seat contact under the hips is the origin and the spectator
## faces +Z, the same way as the goal stand rig.

const SPECTATOR_SCENE_PATH := "res://assets/goal_stand/goal_stand_spectator.glb"
const SHADER: Shader = preload("res://shaders/seated_spectator.gdshader")
const HAIRS: Array[String] = ["Short", "Long", "Cap", "Afro", "Bald", "Bun", "Headband"]
const BAKE_FPS := 20.0
const MAX_CLIPS := 16
## Thighs point forward and slightly down, so the feet reach the terrace floor.
const THIGH_PITCH := deg_to_rad(-78.0)
const KNEE_SPREAD := 0.09
## Seat contact is this far below the hip joints (half the thigh block).
const SEAT_BELOW_HIP := 0.09
## Seat bounce and hip sway kept from each clip (full values would lift the
## spectator out of the chair).
const HIP_BOUNCE := 0.25
const HIP_SWAY := 0.5

## Clip ids used by the shader. Idle clips play most of the time, active ones in
## short bursts, dances only for party people.
const IDLE_CLIPS: Array[StringName] = [&"SPEC_Idle", &"SPEC_Talk", &"SPEC_Phone", &"SPEC_Nod", &"SPEC_FoldArms"]
const ACTIVE_CLIPS: Array[StringName] = [&"SPEC_Clap", &"SPEC_Cheer", &"SPEC_Wave", &"SPEC_Shout", &"SPEC_Anticipate"]
const DANCE_CLIPS: Array[StringName] = [&"SPEC_Dance_YMCA", &"SPEC_Dance_Gangnam", &"SPEC_DanceBounce", &"SPEC_Dance_Silly"]
## Played only on a verdict, by fans of the losing player.
const DESPAIR_CLIP := &"SPEC_Despair"

static var _mesh: ArrayMesh = null
static var _material: ShaderMaterial = null
static var _bone_texture: ImageTexture = null
static var _clip_table: PackedVector4Array = PackedVector4Array()
static var _bone_count := 0
static var _frame_rows := 0


static func is_built() -> bool:
	return _mesh != null


static func mesh() -> ArrayMesh:
	_ensure()
	return _mesh


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
	var all := all_clips()
	return all.find(clip)


static func all_clips() -> Array[StringName]:
	var clips: Array[StringName] = []
	clips.append_array(IDLE_CLIPS)
	clips.append_array(ACTIVE_CLIPS)
	clips.append_array(DANCE_CLIPS)
	clips.append(DESPAIR_CLIP)
	return clips


static func _ensure() -> void:
	if _mesh != null:
		return
	var scene := load(SPECTATOR_SCENE_PATH) as PackedScene
	var root := scene.instantiate() as Node3D
	var skeleton := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var bodies: Array[MeshInstance3D] = []
	for hair: String in HAIRS:
		bodies.append(root.find_child("SPEC_Body_" + hair, true, false) as MeshInstance3D)
	var skin: Skin = bodies[0].skin
	_bone_count = skin.get_bind_count()
	var bind_bones := PackedInt32Array()
	var binds: Array[Transform3D] = []
	for bind: int in range(_bone_count):
		bind_bones.append(skeleton.find_bone(skin.get_bind_name(bind)))
		binds.append(skin.get_bind_pose(bind))
	_mesh = _merge_bodies(bodies)
	var rows := PackedFloat32Array()
	var clips := all_clips()
	_clip_table = PackedVector4Array()
	_frame_rows = 0
	var seat_offset := _seat_offset(skeleton)
	for clip: StringName in clips:
		# Tracks are sampled directly, so no scene tree or mixer is needed.
		var animation := player.get_animation(clip)
		var frames := maxi(1, int(round(animation.length * BAKE_FPS)))
		_clip_table.append(Vector4(float(_frame_rows), float(frames), BAKE_FPS, animation.length))
		for frame: int in range(frames):
			var locals := _sample_locals(skeleton, animation, float(frame) / BAKE_FPS)
			var poses := _seated_globals(skeleton, locals, seat_offset)
			for bind: int in range(_bone_count):
				var matrix: Transform3D = poses[bind_bones[bind]] * binds[bind]
				for axis: int in range(3):
					rows.append(matrix.basis.x[axis])
					rows.append(matrix.basis.y[axis])
					rows.append(matrix.basis.z[axis])
					rows.append(matrix.origin[axis])
			_frame_rows += 1
	root.free()
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
	_material.set_shader_parameter("idle_clip_count", IDLE_CLIPS.size())
	_material.set_shader_parameter("active_clip_count", ACTIVE_CLIPS.size())
	_material.set_shader_parameter("dance_clip_count", DANCE_CLIPS.size())
	_material.set_shader_parameter("skins", _colors(GoalStand.SKINS))
	_material.set_shader_parameter("hair_colors", _colors(GoalStand.HAIR_COLORS))
	_material.set_shader_parameter("pants_colors", _colors(GoalStand.PANTS))
	_material.set_shader_parameter("shoe_colors", _colors(GoalStand.SHOES))
	_material.set_shader_parameter("team_colors", [GoalStand.NEUTRAL_SHIRTS[4], GoalStand.P1_COLOR, GoalStand.P2_COLOR])


static func _colors(source: Array) -> Array[Color]:
	var out: Array[Color] = []
	for color: Color in source:
		out.append(color)
	while out.size() < 8:
		out.append(out[out.size() - 1])
	return out


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


static func _seated_globals(skeleton: Skeleton3D, locals: Array[Transform3D], seat_offset: Vector3) -> Array[Transform3D]:
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
	for bone: int in range(count):
		var parent := skeleton.get_bone_parent(bone)
		var local := locals[bone]
		var global: Transform3D = local if parent < 0 else poses[parent] * local
		var rest := skeleton.get_bone_global_rest(bone)
		if bone == pelvis:
			var lift := clampf((global.origin.y - rest.origin.y) * HIP_BOUNCE, -0.03, 0.06)
			var turn := rest.basis.get_rotation_quaternion().slerp(global.basis.get_rotation_quaternion(), HIP_SWAY)
			global = Transform3D(Basis(turn), rest.origin + Vector3(0.0, lift, 0.0))
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


## Union of the hairstyle bodies. Identical triangles are shared and tagged with
## every hairstyle that owns them.
static func _merge_bodies(bodies: Array[MeshInstance3D]) -> ArrayMesh:
	var owners := {}
	var order: Array[String] = []
	var data := {}
	for style: int in range(bodies.size()):
		var arrays := fix_waist(bodies[style].mesh.surface_get_arrays(0), bodies[style].skin)
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
			var key := ""
			for corner: int in range(3):
				var v := indices[tri + corner]
				var bone := bones[v * influences]
				var best := weights[v * influences]
				for extra: int in range(1, influences):
					if weights[v * influences + extra] > best:
						best = weights[v * influences + extra]
						bone = bones[v * influences + extra]
				corners.append([vertices[v], normals[v], uvs[v], bone])
				key += "%.4f,%.4f,%.4f|%.3f|%d;" % [vertices[v].x, vertices[v].y, vertices[v].z, uvs[v].x, bone]
			if not owners.has(key):
				owners[key] = 0
				order.append(key)
				data[key] = corners
			owners[key] = int(owners[key]) | (1 << style)
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

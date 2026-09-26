class_name ResultWinnerDance
extends RefCounted

## Sample the equipped FBX, independently of gameplay's animation clock.
## Only the result duplicate is posed: the Score Tower Finale winner, blending
## out of the Blender victory landing on top of the tower (both players on a draw).
const START := 7.6
const BLEND_END := 8.0
var emote_id := 0
var clips: Array[Dictionary] = []
var duration := 0.0
var sample_time := 0.0

func setup(parent: Node3D, selected: int) -> void:
	clear()
	emote_id = EmoteData.normalize_emote_id(selected)
	var paths: Array = EmoteData.THRILLER_PART_PATHS.duplicate() if EmoteData.is_thriller_emote(emote_id) else [EmoteData.get_emote_fbx(emote_id)]
	for path in paths:
		if path.is_empty() or not ResourceLoader.exists(path): continue
		var source := (load(path) as PackedScene).instantiate() as Node3D
		parent.add_child(source)
		source.visible = false
		source.process_mode = Node.PROCESS_MODE_DISABLED
		var skeleton := source.find_child("*Skeleton*", true, false) as Skeleton3D
		if skeleton == null:
			var skeletons := source.find_children("*", "Skeleton3D", true, false)
			if not skeletons.is_empty(): skeleton = skeletons[0] as Skeleton3D
		var ap := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var animation := EmoteBlockmanPreview.pick_best_emote_animation(ap)
		if skeleton == null or animation.is_empty():
			source.queue_free()
			continue
		ap.play(animation)
		ap.pause()
		ap.seek(0.0, true)
		skeleton.force_update_all_bone_transforms()
		var bones := EmoteBlockmanPreview.map_mixamo_bones(skeleton)
		var clip_duration := ap.get_animation(animation).length
		if clip_duration <= 0.0 or not bones.has("hips"):
			source.queue_free()
			continue
		clips.append({"source": source, "ap": ap, "skeleton": skeleton, "bones": bones,
			"duration": clip_duration, "origin": skeleton.get_bone_global_pose(bones.hips).origin})
		duration += clip_duration

func apply(root: Node3D, parts: Dictionary, camera: Camera3D, elapsed: float, floor_y: float) -> void:
	if clips.is_empty() or elapsed <= START: return
	sample_time = fposmod(dance_clock(elapsed), duration)
	var local_time := sample_time
	var clip: Dictionary = clips.back()
	for candidate in clips:
		clip = candidate
		if local_time < float(candidate.duration): break
		local_time -= float(candidate.duration)
	var skeleton: Skeleton3D = clip.skeleton
	(clip.ap as AnimationPlayer).seek(local_time, true)
	skeleton.force_update_all_bone_transforms()
	var weight := smoothstep(START, BLEND_END, elapsed)
	var carrier := root.global_transform
	var before := {}
	for key: Variant in parts:
		if parts[key] is Node3D: before[key] = (parts[key] as Node3D).transform
	# The existing retargeter writes global orientations. Pose in an identity
	# frame, using the same FBX axis correction as customization and gameplay.
	root.global_transform = Transform3D.IDENTITY
	EmoteBlockmanPreview.apply_skeleton_pose(parts, skeleton, clip.bones, true, null, {})
	var hip_pose := skeleton.get_bone_global_pose(clip.bones.hips)
	var mirror := Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3.BACK)
	var hip_yaw := (mirror * hip_pose.basis * mirror).get_euler().y
	for key: Variant in before:
		var node := parts[key] as Node3D
		node.transform = (before[key] as Transform3D).interpolate_with(node.transform, weight)
	# P2 mirrors the stage layout, but must keep the dancer's handedness.
	# Remove that reflection before applying world-space camera facing.
	if carrier.basis.determinant() < 0.0: carrier.basis = carrier.basis * mirror
	root.global_transform = carrier
	var to_camera := camera.global_position - root.global_position
	var facing := atan2(to_camera.x, to_camera.z) - hip_yaw
	root.global_basis = Basis(carrier.basis.get_rotation_quaternion().slerp(Quaternion(Vector3.UP, facing), weight))
	var drift: Vector3 = hip_pose.origin - (clip.origin as Vector3)
	root.global_position += root.global_basis * Vector3(clampf(-drift.x, -0.16, 0.16), 0.0, clampf(drift.z, -0.12, 0.12)) * weight
	# Keep contact poses on the belt, but retain jumps present in the source.
	var source_height := INF
	for key in ["l_foot", "r_foot", "l_toe", "r_toe", "l_hand", "r_hand", "head"]:
		if clip.bones.has(key): source_height = minf(source_height, skeleton.get_bone_global_pose(clip.bones[key]).origin.y)
	var lift := clampf(source_height - 0.12, 0.0, 0.55) if emote_id != EmoteData.EMOTE_HEAD_SPINNING else 0.0
	var lowest := INF
	for mesh: MeshInstance3D in parts.meshes:
		for corner in range(8): lowest = minf(lowest, (mesh.global_transform * mesh.get_aabb().get_endpoint(corner)).y)
	root.global_position.y += (floor_y + 0.012 + lift - lowest) * weight
	var head: Node3D = parts.head_pivot
	var gaze := Basis.looking_at(camera.global_position - head.global_position, Vector3.UP, true)
	# Correct the gaze after the complete parent pose, including P2 reflection.
	var desired_local := (head.get_parent() as Node3D).global_basis.inverse() * gaze
	if desired_local.determinant() < 0.0:
		desired_local = desired_local * Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3.BACK)
	head.quaternion = head.quaternion.slerp(desired_local.orthonormalized().get_rotation_quaternion(), weight)

## The winner keeps dancing on the tower while the result controls wait.
static func dance_clock(elapsed: float) -> float:
	return maxf(0.0, elapsed - START)

func clear() -> void:
	for clip in clips:
		if is_instance_valid(clip.source): (clip.source as Node).queue_free()
	clips.clear()
	duration = 0.0
	sample_time = 0.0

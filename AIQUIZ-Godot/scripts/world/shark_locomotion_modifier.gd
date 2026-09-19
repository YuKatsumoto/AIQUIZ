extends SkeletonModifier3D
## Steering is applied after the swim clip, and restored by Skeleton3D each
## frame. Never accumulate offsets into the next AnimationPlayer sample.
## All angles below are relative joint angles, in radians.

var turn: float = 0.0
var stroke_gain: float = 1.0
var swim_active: bool = false
var _bones: Dictionary = {}
var _axes: Dictionary = {}
var _rest_rotations: Dictionary = {}

const BEND_DEGREES := {
	"body_01": 0.0, "head": 4.0, "body_02": -5.0,
	"tail_01": -6.0, "tail_02": -4.0, "tail_03": -2.0,
}

func _ready() -> void:
	var skeleton := get_skeleton()
	for bone_name in ["body_01", "body_02", "tail_01", "tail_02", "tail_03", "head", "pectoral.L", "pectoral.R"]:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			continue
		_bones[bone_name] = index
		_rest_rotations[bone_name] = skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		# Imported bone axes differ between the trunk, head and fins. Express
		# the same anatomical axes in each bone's rest coordinate system.
		_axes[bone_name] = skeleton.get_bone_global_rest(index).basis.inverse()


func _process_modification_with_delta(_delta: float) -> void:
	if not swim_active:
		return
	var skeleton := get_skeleton()
	for bone_name: String in BEND_DEGREES:
		if not _bones.has(bone_name):
			continue
		var index: int = _bones[bone_name]
		var pose := skeleton.get_bone_pose_rotation(index)
		var rest: Quaternion = _rest_rotations[bone_name]
		pose = rest.slerp(pose, stroke_gain)
		var axis: Vector3 = (_axes[bone_name] * Vector3.UP).normalized()
		pose = pose * Quaternion(axis, deg_to_rad(BEND_DEGREES[bone_name]) * turn)
		skeleton.set_bone_pose_rotation(index, pose.normalized())
	# +Y yaw turns the +X-facing imported shark toward -Z (its left side).
	# The inside fin depresses/protracts; the outside fin stays nearly level.
	for bone_name: String in ["pectoral.L", "pectoral.R"]:
		if not _bones.has(bone_name):
			continue
		var side := 1.0 if bone_name == "pectoral.L" else -1.0
		var inside := maxf(0.0, turn * side)
		var index: int = _bones[bone_name]
		var axes: Basis = _axes[bone_name]
		var pose := skeleton.get_bone_pose_rotation(index)
		pose *= Quaternion((axes * Vector3.RIGHT).normalized(), -side * deg_to_rad(7.0) * inside)
		pose *= Quaternion((axes * Vector3.UP).normalized(), -side * deg_to_rad(4.0) * inside)
		skeleton.set_bone_pose_rotation(index, pose.normalized())

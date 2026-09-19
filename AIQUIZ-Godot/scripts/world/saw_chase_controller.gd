extends Node3D
class_name SawChaseController

## Presentation only. State/replay owns position, animation time and wheel travel.
const MODEL_PATH := "res://assets/hazards/linked_saw_carriage.glb"
var model: Node3D
var animation: AnimationPlayer
var skeleton: Skeleton3D
var spin_clip: StringName
var wheel_bones: Array[int] = []

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

func update_visual(gs: QuizGameState) -> void:
	visible = gs.is_saw_visible()
	if not visible:
		return
	if model == null:
		_load_model()
	position = Vector3(0.0, StageConstants.FLOOR_TOP_Y, gs.saw.local_z)
	if animation != null and not spin_clip.is_empty():
		var duration := animation.get_animation(spin_clip).length
		animation.seek(fposmod(gs.saw.elapsed, duration), true)
	if skeleton != null:
		for bone: int in wheel_bones:
			var rest_rotation := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(bone, rest_rotation * Quaternion(Vector3.UP, -gs.saw.wheel_distance / SawChaseState.WHEEL_RADIUS))
		skeleton.force_update_all_bone_transforms()

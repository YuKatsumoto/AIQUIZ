@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node = ctx.instantiate_imported_scene()
	if root == null:
		ctx.error("Could not instantiate shark asset")
		return
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	var player: AnimationPlayer = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or player == null:
		ctx.error("Expected rig nodes were not imported")
		return
	var names: PackedStringArray = PackedStringArray()
	for index: int in range(skeleton.get_bone_count()):
		names.append(skeleton.get_bone_name(index))
	ctx.log("bones=%d names=%s jaw_index=%d" % [skeleton.get_bone_count(), str(names), skeleton.find_bone("jaw")])
	ctx.log("animations=%s" % str(player.get_animation_list()))
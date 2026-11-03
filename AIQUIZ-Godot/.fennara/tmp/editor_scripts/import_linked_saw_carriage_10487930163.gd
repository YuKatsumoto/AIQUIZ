@tool
extends RefCounted
func run(ctx) -> void:
	ctx.log(ctx.get_import_info())
	var root: Node = ctx.instantiate_imported_scene()
	for node: Node in root.find_children("*", "AnimationPlayer", true, false):
		ctx.log({"animations": node.get_animation_list()})
	for node: Node in root.find_children("*", "Skeleton3D", true, false):
		var bones: Array = []
		for i: int in node.get_bone_count():
			bones.append({"name":node.get_bone_name(i),"rest":str(node.get_bone_rest(i))})
		ctx.log({"bones":bones})
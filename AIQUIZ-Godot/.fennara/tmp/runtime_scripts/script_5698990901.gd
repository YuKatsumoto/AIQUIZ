extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	ctx.log("root=%s class=%s children=%d" % [root.name, root.get_class(), root.get_child_count()])
	for child: Node in root.get_children():
		ctx.log("child=%s class=%s visible=%s" % [child.name, child.get_class(), str(child.get("visible"))])

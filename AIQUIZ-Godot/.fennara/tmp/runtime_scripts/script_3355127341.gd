extends RefCounted

func run(ctx: Variant) -> void:
	var world: Node = ctx.get_scene_root()
	var spawner: Node = world.get_node("ParticleSpawner")
	var children: Array[String] = []
	for child: Node in spawner.get_children():
		children.append("%s:%s" % [child.name, child.get_class()])
	ctx.log("spawner_children=%s count=%d" % [str(children), children.size()])

@tool
extends RefCounted

func run(ctx) -> void:
	ctx.log(ctx.list_import_options("gltf/"))

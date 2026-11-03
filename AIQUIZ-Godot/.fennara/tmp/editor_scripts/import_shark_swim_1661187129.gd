@tool
extends RefCounted

func run(ctx) -> void:
	var info: Dictionary = ctx.get_import_info()
	ctx.log("import_valid=%s options=%d" % [info.get("import_valid", false), info.get("option_count", 0)])
	ctx.log("nodes_options=%s" % str(ctx.list_import_options("nodes/")))
	ctx.log("animation_options=%s" % str(ctx.list_import_options("animation/")))
@tool
extends RefCounted

func run(ctx) -> void:
	var option_name: String = "animation/fps"
	var before: Variant = ctx.get_import_option(option_name)
	if not (before is int):
		ctx.error("Expected integer animation/fps")
		return
	if not ctx.set_import_option(option_name, before):
		return
	ctx.log("Requested canonical reimport with animation/fps=%d" % int(before))
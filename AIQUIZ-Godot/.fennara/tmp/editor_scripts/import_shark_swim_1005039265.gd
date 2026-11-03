@tool
extends RefCounted

func run(ctx) -> void:
	var info: Dictionary = ctx.get_import_info()
	ctx.log("importer=%s class=%s valid=%s" % [info.get("importer", ""), info.get("resource_class", ""), info.get("import_valid", false)])
	var root: Node = ctx.instantiate_imported_scene()
	if root == null:
		ctx.error("Could not instantiate shark asset")
		return
	var player: AnimationPlayer = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		ctx.log("animation_player=none")
		return
	var names: PackedStringArray = player.get_animation_list()
	ctx.log("animations=%s" % str(names))
	for name: StringName in names:
		var animation: Animation = player.get_animation(name)
		if animation != null:
			ctx.log("animation=%s length=%.3f tracks=%d loop=%d" % [String(name), animation.length, animation.get_track_count(), animation.loop_mode])
extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.restart_scene()
	await ctx.wait(0.35)
	var root: Node = ctx.get_scene_root()
	var director: Node = root.find_child("MenuHelicopterArrivalDirector", true, false)
	if director == null:
		ctx.error("arrival director not found")
		return
	for info_var: Variant in director.get("_helicopters"):
		var info: Dictionary = info_var
		ctx.log("P%d start=%s c1=%s c2=%s hover=%s exit_c1=%s exit_c2=%s exit=%s ground=%s" % [int(info.get("player_index", 0)), str(info.get("start")), str(info.get("approach_c1")), str(info.get("approach_c2")), str(info.get("hover")), str(info.get("exit_c1")), str(info.get("exit_c2")), str(info.get("exit")), str(info.get("ground"))])

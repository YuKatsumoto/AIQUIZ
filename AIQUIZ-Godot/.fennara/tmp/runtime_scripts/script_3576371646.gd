extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var preview: Node = null
	for node: Node in root.find_children("*", "Node", true, false):
		if node.has_method("begin_game_start_departure"):
			preview = node
			break
	if preview == null:
		ctx.error("menu preview controller not found")
		return
	preview.call("begin_game_start_departure", 2)
	await ctx.wait(0.2)
	var director: Node = root.find_child("MenuHelicopterStartDepartureDirector", true, false)
	if director == null:
		ctx.error("pickup director not found")
		return
	for info_var: Variant in director.get("_helicopters"):
		var info: Dictionary = info_var
		ctx.log("P%d pickup start=%s c1=%s c2=%s hover=%s exit_c1=%s exit_c2=%s exit=%s ground=%s" % [int(info.get("player_index", 0)), str(info.get("start")), str(info.get("approach_c1")), str(info.get("approach_c2")), str(info.get("hover")), str(info.get("exit_c1")), str(info.get("exit_c2")), str(info.get("exit")), str(info.get("ground"))])

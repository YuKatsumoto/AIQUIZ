extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var director: Node = root.find_child("MenuHelicopterArrivalDirector", true, false)
	if director == null:
		ctx.log("director missing")
		return
	ctx.log("phase=%s elapsed=%.2f" % [str(director.get("_phase")), float(director.get("_phase_elapsed"))])
	for info_var: Variant in director.get("_helicopters"):
		var info: Dictionary = info_var
		ctx.log("P%d pos=%s bounds=%s visible=%s" % [
			int(info.get("player_index", 0)),
			str((info.get("holder") as Node3D).global_position),
			str(info.get("last_screen_bounds", {})),
			str(info.get("ever_visible_in_frame", false)),
		])

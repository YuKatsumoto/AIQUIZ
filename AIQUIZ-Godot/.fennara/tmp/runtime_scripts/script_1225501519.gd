extends RefCounted

func run(ctx: Variant) -> void:
	var shared_phase: float = WeatherCycle.shared_day_phase()
	var bright: bool = WeatherCycle.is_bright_sky()
	var day_amount: float = WeatherCycle.shared_day_amount()
	ctx.log("shared phase=%.4f day_amount=%.4f bright=%s lock=%s" % [shared_phase, day_amount, str(bright), str(WeatherCycle.LOCK_DAYTIME)])
	var cycles: Array[Node] = []
	_collect_weather(ctx.get_scene_root(), cycles)
	ctx.log("weather nodes=%d" % cycles.size())
	for cycle in cycles:
		ctx.log("%s phase=%.4f night=%.4f forced=%s energy=%.3f" % [
			str(cycle.get_path()),
			float(cycle.get("day_phase")),
			float(cycle.get("night_amount")),
			str(cycle.get("_forced")),
			_sun_energy(cycle),
		])
	await ctx.capture("daytime_lock_t0")
	await ctx.wait(3.0)
	var phase_later: float = WeatherCycle.shared_day_phase()
	ctx.log("phase after wait=%.4f delta=%.6f" % [phase_later, absf(phase_later - shared_phase)])
	for cycle in cycles:
		if not is_instance_valid(cycle):
			continue
		ctx.log("later %s phase=%.4f night=%.4f" % [
			str(cycle.get_path()),
			float(cycle.get("day_phase")),
			float(cycle.get("night_amount")),
		])
	await ctx.capture("daytime_lock_t1")

func _collect_weather(node: Node, out: Array[Node]) -> void:
	if node is WeatherCycle:
		out.append(node)
	for child in node.get_children():
		_collect_weather(child, out)

func _sun_energy(cycle: Node) -> float:
	var light: Variant = cycle.get("directional_light")
	if light is DirectionalLight3D:
		return (light as DirectionalLight3D).light_energy
	return -1.0

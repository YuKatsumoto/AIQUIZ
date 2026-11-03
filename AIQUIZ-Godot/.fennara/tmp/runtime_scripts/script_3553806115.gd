extends RefCounted

func run(ctx: Variant) -> void:
	var shark: SharkSwimmer = ctx.get_scene_root() as SharkSwimmer
	shark.set_process(false)
	shark.position = Vector3(20.0, -0.22, -20.0)
	shark.set("_center", shark.position)
	shark.set("_velocity", Vector3.ZERO)
	shark.begin_attack(1, Vector3(20.0, -0.22, 20.0), 4.0, 160.0)
	var steps: int = 0
	while shark.get_attack_phase() < SharkSwimmer.AttackPhase.CHARGE and steps < 180:
		shark.call("_update_attack", 1.0 / 60.0)
		shark.call("_update_arcade_attack_effects", 1.0 / 60.0)
		steps += 1
	shark.call("_update_arcade_attack_effects", 1.0 / 60.0)
	var before: String = "phase=%d intensity=%.2f jaw=%.2f wake=%s spray=%s audio=%s" % [
		shark.get_attack_phase(),
		shark.get_attack_intensity(),
		float(shark.get("_jaw_open_amount")),
		str((shark.get_node("ArcadeWake") as GPUParticles3D).emitting),
		str((shark.get_node("ChargeSurfaceSpray") as GPUParticles3D).emitting),
		str((shark.get_node("SharkRushSFX") as AudioStreamPlayer3D).playing),
	]
	shark.cancel_attack()
	var after: String = "phase=%d intensity=%.2f jaw=%.2f wake=%s spray=%s audio=%s model_pos=%s" % [
		shark.get_attack_phase(),
		shark.get_attack_intensity(),
		float(shark.get("_jaw_open_amount")),
		str((shark.get_node("ArcadeWake") as GPUParticles3D).emitting),
		str((shark.get_node("ChargeSurfaceSpray") as GPUParticles3D).emitting),
		str((shark.get_node("SharkRushSFX") as AudioStreamPlayer3D).playing),
		str((shark.get_node("Model") as Node3D).position),
	]
	ctx.log("cancel_reset before={%s} after={%s}" % [before, after])

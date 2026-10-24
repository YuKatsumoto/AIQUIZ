extends Node

## ゴーストシャークの鞍・ハンドルと乗り手の座標の関係を書き出す（Blender の作業用の実測）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 60 --script res://tests/ghost_mount_probe_bootstrap.gd
var gs: QuizGameState
var world: Node3D
var ghost: GhostSharkRideController
var helper: Node


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, Constants.MODE_ENDLESS)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs._active_wall_speed = 0.15
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.get_node("Player").prepare_for_loading(gs)
	world.get_node("Player").reveal_without_intro_arrival()
	ghost = world.get("_ghost_shark_ride_controller")
	for i in range(60):
		await get_tree().process_frame
	gs._set_player_hp(1, 1)
	gs.player_x = helper.door(gs, false)
	gs.player2_x = helper.door(gs, true)
	gs.resolve_collision(true, true)
	var guard := 0
	while ghost.phase != ghost.Phase.BEAM_REVEAL and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await get_tree().process_frame
	var shark: Node3D = ghost.get("_shark")
	var rider: Node3D = ghost.get("_rider")
	var model: Node3D = shark.get_node("Model")
	var mount: Node3D = rider.get_parent() as Node3D
	var out := {}
	out["shark_scale"] = str(shark.scale)
	out["model_transform"] = str(model.transform)
	out["mount_local"] = str(mount.transform)
	out["rider_local"] = str(rider.transform)
	out["rider_global_scale"] = str(rider.global_basis.get_scale())
	var rider_inv := rider.global_transform.affine_inverse()
	var model_inv := model.global_transform.affine_inverse()
	out["rider_in_model"] = str(model_inv * rider.global_transform)
	var socket := model.find_child("GhostMountSocket", true, false) as Node3D
	if socket:
		out["socket_in_model"] = str(model_inv * socket.global_transform)
	var meshes := {}
	for node: Node in model.find_children("SharkSaddle_*", "", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var center := mi.global_transform * mi.get_aabb().get_center()
		meshes[str(mi.name)] = {"rider": str(rider_inv * center), "model": str(model_inv * center)}
	out["saddle"] = meshes
	var parts: Dictionary = rider.get_meta("ghost_mount_parts", {})
	var joints := {}
	for name in ["pelvis", "spine", "l_shoulder", "r_shoulder", "l_wrist", "r_wrist", "l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"]:
		var p := parts.get(name) as Node3D
		if p:
			joints[name] = str(rider_inv * p.global_position)
	out["joints_rider_space"] = joints
	var overlays := {}
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null and not String(mi.name).begins_with("SharkSaddle"):
			var overlay := mi.material_overlay as ShaderMaterial
			overlays[str(mi.name)] = {
				"overlay": str(mi.material_overlay),
				"sweep": overlay.get_shader_parameter("sweep") if overlay else null,
				"intensity": overlay.get_shader_parameter("intensity") if overlay else null,
				"aabb": str(mi.get_aabb()),
				"transform_in_model": str(model.global_transform.affine_inverse() * mi.global_transform),
			}
	out["possession"] = overlays
	out["shark_debug"] = shark.call("get_ghost_ride_debug_state")
	var ap := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		out["anim"] = str(ap.current_animation)
	print("GHOST_MOUNT_PROBE " + JSON.stringify(out, "  "))
	get_tree().quit(0)

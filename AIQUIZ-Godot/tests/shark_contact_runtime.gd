extends Node

## Rendered regression probe: run with --path . --script this file --fixed-fps 60.
## Uses the real game world, ocean fall, shark assignment and player explosion.
const OUT := "res://artifacts/shark_rig_rebuild/"
var world: Node3D
var gs: QuizGameState
var shark: SharkSwimmer
var rows: Array[Dictionary] = []
var hits: Array[Dictionary] = []
var tag := "before"
var target_player := 1
var camera: Camera3D
var frame := 0
var scenario := "edge"

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("tag="): tag = arg.trim_prefix("tag=")
		if arg.begins_with("player="): target_player = int(arg.trim_prefix("player="))
		if arg.begins_with("case="): scenario = arg.trim_prefix("case=")
	get_tree().root.size = Vector2i(960, 540)
	gs = get_tree().root.get_node("QuizManager").game_state
	get_tree().root.get_node("QuizManager").provider.set("llm_mode", "OFFLINE")
	gs.llm_mode = "OFFLINE"
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.game_state = Constants.STATE_PLAYING
	gs.skip_start_helicopter_arrival = true
	gs.current_quiz = QuizItem.create("Shark contact verification", PackedStringArray(["left", "right"]), 0)
	gs._active_wall_speed = 0.0
	gs.world_scroll_z = 0.0
	gs.current_wall_index = 0
	gs.player_x = 2.0
	gs.player2_x = -2.0
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_z = -12.0
	gs.player2_z = -12.0
	gs.p1_alive = true
	gs.p2_alive = true
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.get_node("Player").prepare_for_loading(gs)
	await get_tree().create_timer(0.3).timeout
	if target_player == 1:
		gs.player_x = StageConstants.FLOOR_HALF_WIDTH + 0.6
		gs.player_y = -1.0
		gs.player_z = gs.wall_z - 0.2
		gs.player_vel_y = -1.0
	else:
		gs.player2_x = -StageConstants.FLOOR_HALF_WIDTH - 0.6
		gs.player2_y = -1.0
		gs.player2_z = gs.wall_z - 0.2
		gs.player2_vel_y = -1.0
	if scenario.begins_with("back") or scenario.begins_with("front"):
		var edge_z: float = QuizGameState.FLOOR_BACK_Z - 0.02
		if scenario.begins_with("front"):
			edge_z = world.stage_env.get_floor_center_z() + world.stage_env.get_floor_length() * 0.5 + 0.6
		if target_player == 1:
			gs.player_x = 0.28
			gs.player_z = gs.world_scroll_z + edge_z
		else:
			gs.player2_x = -0.28
			gs.player2_z = gs.world_scroll_z + edge_z
		if scenario.begins_with("front"):
			# Isolate the render-stage front boundary without advancing an entire race.
			gs._begin_ocean_shark_wait(target_player)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.fov = 48.0
	var after_hit := 0
	for i in 900:
		frame = i
		await get_tree().process_frame
		if shark == null:
			shark = world.get("_ocean_attack_sharks").get(target_player) as SharkSwimmer
			if shark != null:
				shark.attack_reached.connect(on_hit)
				if scenario == "portal" or scenario.ends_with("_portal"):
					shark.call("_start_attack_portal_rescue", shark.get("_attack_target"))
				elif scenario == "close":
					var point := gs.get_ocean_player_local_position(target_player)
					shark.position = point + Vector3(8 if target_player == 1 else -8, 0, -9)
					shark.call("_build_attack_route", shark.position, shark.get("_attack_target"))
		if shark == null: continue
		var row := sample()
		rows.append(row)
		var target := gs.get_ocean_player_local_position(target_player)
		camera.position = target + Vector3(14 * (1 if target_player == 1 else -1), 7, 17)
		if scenario.begins_with("back"):
			camera.position = target + Vector3(12, 9, -18)
		camera.look_at(target + Vector3(0, 0, 0))
		camera.make_current()
		var boundary_probe := scenario.begins_with("back") or scenario.begins_with("front")
		var capture_bite: bool = row.phase == "BITE" and (not boundary_probe or i % 30 == 0)
		if capture_bite or not hits.is_empty():
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png(OUT + "%s_%04d.png" % [tag, frame])
		if not hits.is_empty():
			after_hit += 1
			if after_hit >= 15: break
	var max_jaw := 0.0
	for row in rows: max_jaw = maxf(max_jaw, absf(row.jaw))
	var data := {"renderer": RenderingServer.get_current_rendering_method(), "player": target_player,
		"scenario": scenario, "max_jaw_radians": max_jaw, "hits": hits, "frames": rows,
		"exploded": world.has_player_death_exploded(target_player)}
	var file := FileAccess.open(OUT + tag + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	var passed: bool = hits.size() == 1 and data.exploded and max_jaw < 0.0001 and hits[0].exploded
	print("SHARK_CONTACT_RESULT ", JSON.stringify({"passed": passed, "hits": hits, "max_jaw": max_jaw, "frames": rows.size()}))
	get_tree().quit(0 if passed else 1)

func sample() -> Dictionary:
	var target := gs.get_ocean_player_local_position(target_player)
	var head := shark.get_ocean_attack_head_position()
	var local_target := shark.model.to_local(target)
	return {"frame": frame, "phase": SharkSwimmer.AttackPhase.keys()[shark.get_attack_phase()],
		"contact": shark.get_ocean_attack_debug_state().get("last_contact", {}),
		"root": vec(shark.position), "target": vec(target), "head": vec(head),
		"target_in_model": vec(local_target), "head_distance": head.distance_to(target),
		"timer": shark.get("_bite_timer"), "animation": str(shark.animation_player.current_animation),
		"jaw": shark.get("_jaw_skeleton").get_bone_pose_rotation(shark.get("_jaw_bone_index")).get_angle(),
		"exploded": world.has_player_death_exploded(target_player)}

func on_hit(_index: int) -> void:
	hits.append(sample())

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

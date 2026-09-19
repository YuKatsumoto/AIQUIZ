extends Node

const OUT := "res://artifacts/contact_speed_fix/wall_recoil/"
var gs: QuizGameState
var world: Node3D
var pc: PlayerController
var helper: Node
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var checks := 0
var video_frame := 0

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	helper = load("res://tests/hp_unit.gd").new()
	QuizManager.player_analytics = null
	await scenario("p1_wrong", 2, false, true)
	await scenario("p2_wrong", 2, true, false)
	await scenario("both_wrong", 2, false, false)
	await scenario("solid_wall", 1, false, true, true)
	await scenario("solo_wrong", 1, false, true)
	# The overlay must reconstruct from existing synchronized damage state.
	world.set("_replay_mode", true)
	gs.p1_damage_time = 0.46
	gs.is_replay = true
	await frames(3)
	check(pc.p1_parts.pelvis.position.z < -1.18, "replay damage state reconstructs recoil")
	gs.hp_state_available = false
	await frames(2)
	check(pc.get("_health_pose_restore").is_empty() and is_zero_approx(pc.p1_parts.pelvis.position.z), "legacy replay clears recoil")
	gs.hp_state_available = true
	gs.is_replay = false
	gs.p1_damage_time = 0.46
	await frames(2)
	gs._reset_health()
	await frames(2)
	check(pc.get("_health_pose_restore").is_empty() and is_zero_approx(pc.p1_parts.pelvis.position.z), "retry reset clears recoil")
	gs.p1_hp = 1
	helper.answer(gs, false)
	await frames(2)
	check(not gs.p1_alive and gs.p1_wall_impact and pc.get("_health_pose_restore").is_empty(), "fatal wall hit keeps the existing death path")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "frames": video_frame, "samples": rows}
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WALL_RECOIL_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "frames": video_frame}))
	for provider in helper.providers:
		provider.free()
	helper.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func scenario(tag: String, players: int, correct1: bool, correct2: bool, solid := false) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	gs = helper.fixture(players)
	gs.skip_start_helicopter_arrival = true
	QuizManager.game_state = gs
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true)
	pc = world.get_node("Player") as PlayerController
	pc.prepare_for_loading(gs)
	await frames(50)
	var events: Array = []
	gs.health_changed.connect(func(p, old, hp): events.append({"p":p,"old":old,"hp":hp}))
	for player in range(1, players + 1):
		var rig: AnimationRig = pc.get("_p1_rig" if player == 1 else "_p2_rig")
		check(not rig.resolve_ual_clip("Hit_Chest", AnimationRig.SLOT_UAL).is_empty(), tag + " authored recoil available P%d" % player)
	gs.player_x = 0.0 if solid else helper.door(gs, correct1) + (0.4 if players == 2 and correct1 == correct2 else 0.0)
	gs.player2_x = helper.door(gs, correct2) - (0.4 if correct1 == correct2 else 0.0)
	gs.world_scroll_z = gs.wall_z - 1.1
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z
	await frames(3)
	await capture(tag + "_before")
	world.set("_replay_mode", false)
	var crossed := false
	for i in range(120):
		await frames(1)
		if i % 2 == 0: await sample(tag)
		if not events.is_empty():
			crossed = true
			break
	check(crossed, tag + " actual wall collision")
	check(gs.camera_shake > 0.25, tag + " impact starts stronger brief camera shake")
	var peak := [0.0, 0.0]
	var authored := [false, false]
	var max_spine_angle := [0.0, 0.0]
	for i in range(48):
		await frames(1)
		for player in range(1, players + 1):
			var parts: Dictionary = pc.p1_parts if player == 1 else pc.p2_parts
			peak[player - 1] = minf(peak[player - 1], parts.pelvis.position.z)
			if gs.get_damage_time(player) > 0.05:
				var rig: AnimationRig = pc.get("_p1_rig" if player == 1 else "_p2_rig")
				authored[player - 1] = authored[player - 1] or rig.active_skeleton == rig.skeletons[AnimationRig.SLOT_UAL]
			for saved: Dictionary in pc.get("_health_pose_restore"):
				if saved.node == parts.spine:
					var baseline: Transform3D = saved.transform
					max_spine_angle[player - 1] = maxf(max_spine_angle[player - 1], rad_to_deg(baseline.basis.get_rotation_quaternion().angle_to(parts.spine.quaternion)))
		if i % 2 == 0: await sample(tag)
		if i == 7: await capture(tag + "_peak")
	await capture(tag + "_returned")
	for player in range(1, players + 1):
		var correct := correct1 if player == 1 else correct2
		var parts: Dictionary = pc.p1_parts if player == 1 else pc.p2_parts
		check(gs.get_player_hp(player) == (3 if correct else 2), tag + " one HP only on wrong contact P%d" % player)
		check(is_zero_approx(parts.pelvis.position.z), tag + " returns to normal position P%d" % player)
		if not correct:
			check(peak[player - 1] < -1.18 and peak[player - 1] >= -1.201, tag + " stronger backward travel P%d: %f" % [player, peak[player - 1]])
			check(authored[player - 1] and max_spine_angle[player - 1] > 5.0, tag + " authored recoil pose P%d: %f" % [player, max_spine_angle[player - 1]])
		else:
			check(is_zero_approx(peak[player - 1]) and not authored[player - 1], tag + " correct player unaffected P%d" % player)
	check(gs.current_wall_index == 1, tag + " advances once")
	check(events.size() == (int(not correct1) + (int(not correct2) if players == 2 else 0)), tag + " no repeated damage")
	check(pc.get("_health_pose_restore").is_empty(), tag + " animation fully released")
	check(is_zero_approx(gs.camera_shake), tag + " camera shake fully settles")

func sample(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "frames/%04d.png" % video_frame)
	video_frame += 1
	rows.append({"tag":tag,"time":gs.play_time,"hurt1":gs.p1_damage_time,"hurt2":gs.p2_damage_time,"offset1":pc.p1_parts.pelvis.position.z,"offset2":pc.p2_parts.pelvis.position.z if gs.num_players == 2 else 0.0,"hp1":gs.p1_hp,"hp2":gs.p2_hp,"wall":gs.current_wall_index,"shake":gs.camera_shake,"camera_x":get_viewport().get_camera_3d().global_position.x})

func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

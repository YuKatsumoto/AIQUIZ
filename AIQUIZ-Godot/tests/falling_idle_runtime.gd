extends Node

## Observe the real menu Start -> helicopter -> physical touchdown route.
const OUT := "res://artifacts/falling_idle/"
var players := 2
var fps := 60
var baseline := false
var label := ""
var failures: Array[String] = []
var checks: Dictionary = {}
var observed: Dictionary = {}
var samples: Array[Dictionary] = []
var pictures: Dictionary = {}
var closeups: Dictionary = {}

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, key: String) -> void:
	checks[key] = bool(checks.get(key, true)) and ok
	if not ok and not failures.has(key):
		failures.append(key)
		push_error(key)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--players="): players = arg.get_slice("=", 1).to_int()
		if arg.begins_with("--fps="): fps = arg.get_slice("=", 1).to_int()
		if arg == "--baseline": baseline = true
	label = "p%d_%dfps%s" % [players, fps, "_baseline" if baseline else ""]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + label))
	Engine.max_fps = fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_tree().root.size = Vector2i(1280, 720)
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.llm_mode = "OFFLINE"
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	gs.menu_step = Constants.MENU_STEP_CONFIG
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	while get_tree().current_scene == null:
		await get_tree().process_frame
	var menu := get_tree().current_scene
	menu.call("_update_ui")
	var preview: Node = menu.get("_menu_wall_preview")
	preview.sync_menu_player_count(players)
	await get_tree().create_timer(1.5).timeout
	while menu.config_conveyor != null and menu.config_conveyor.is_moving():
		await get_tree().process_frame
	menu.call("_on_start_pressed")
	var deadline := Time.get_ticks_msec() + 65000
	var world: Node = null
	var completed := false
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var scene := get_tree().current_scene
		if scene == null or scene.scene_file_path != "res://scenes/game_world.tscn":
			continue
		world = scene
		var director := world.get_node_or_null("HelicopterArrivalDirector") as HelicopterArrivalDirector
		if director == null: continue
		var pc: PlayerController = director._player_controller
		if closeups.is_empty() and not baseline:
			for n in range(1, players + 1):
				var viewport := SubViewport.new()
				viewport.size = Vector2i(640, 640)
				viewport.world_3d = world.get_world_3d()
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var camera := Camera3D.new()
				camera.fov = 36.0
				viewport.add_child(camera)
				camera.make_current()
				closeups[n] = {"viewport":viewport,"camera":camera}
		for n in range(1, players + 1):
			var rig: AnimationRig = pc._p1_rig if n == 1 else pc._p2_rig
			if baseline:
				# The fallback is the unmodified physical flight and its original visual.
				rig.aps[AnimationRig.SLOT_FALLING_IDLE] = null
			var jump := pc.get_intro_jump_state(n)
			if not jump.get("active", false): continue
			if not observed.has(n):
				observed[n] = {"air_frames":0, "motion":0.0, "land":false, "idle":false}
			var m: Dictionary = observed[n]
			var parts: Dictionary = pc.p1_parts if n == 1 else pc.p2_parts
			if closeups.has(n):
				var focus: Vector3 = parts.pelvis.global_position + Vector3.UP * .3
				var camera: Camera3D = closeups[n].camera
				camera.global_position = focus + Vector3(2.8, 1.0, -4.4)
				camera.look_at(focus)
			var elapsed: float = pc._intro_jumps.get(n, {}).get("elapsed", 0.0)
			var airborne: bool = not jump.get("floor_contacted", false)
			if airborne:
				m.air_frames += 1
				var drop := pc.get_intro_drop_state(n)
				var pos: Vector3 = drop.position
				samples.append({"player":n,"elapsed":elapsed,"position":[pos.x,pos.y,pos.z]})
				if not baseline:
					check(jump.clip == "Falling Idle" and jump.animated_fall, "P%d falling clip is active in flight" % n)
					check(parts.pelvis.global_position.distance_to(pos) < .001, "P%d animated root follows physical torso" % n)
					check(not pc._intro_ragdolls[n].container.visible, "P%d physical duplicate hidden" % n)
					check(parts.head.is_visible_in_tree() and parts.l_hand.is_visible_in_tree() and parts.r_hand.is_visible_in_tree(), "P%d head and both hands visible" % n)
					check(not pc._intro_hat_restore.has(n), "P%d hat restored to animated head" % n)
					var q: Quaternion = parts.l_elbow.quaternion
					if elapsed > .2 and m.has("last_q"):
						m.motion += q.angle_to(m.last_q)
					m.last_q = q
					for body: RigidBody3D in pc._intro_ragdolls[n].rag.bodies.values():
						if body == pc._intro_ragdolls[n].rag.bodies.get("anchor"): continue
						check(not body.freeze and body.gravity_scale == 1.0 and body.continuous_cd, "P%d collision and gravity remain active" % n)
				if elapsed > .18: picture("p%d_air_early" % n)
				if elapsed > .38: picture("p%d_air_mid" % n)
				if elapsed > .58: picture("p%d_air_late" % n)
			elif jump.land_phase == "jump_land":
				m.land = true
				check(jump.clip == AnimationRig.UAL_JUMP_LAND, "P%d original landing clip restored" % n)
				picture("p%d_touchdown" % n)
			elif jump.land_phase == "idle":
				m.idle = true
				var target: Vector3 = jump.stand_landing
				var pos: Vector3 = parts.pelvis.global_position
				check(Vector2(pos.x-target.x,pos.z-target.z).length() < .02, "P%d lands at its starting mark" % n)
				picture("p%d_standing" % n)
		if not director.is_start_locked() and observed.size() == players:
			completed = true
			break
	check(completed, "real Start route finishes with controls unlocked")
	for n in range(1, players + 1):
		var m: Dictionary = observed.get(n, {})
		check(int(m.get("air_frames", 0)) >= 5, "P%d airborne phase observed" % n)
		check(m.get("land", false) and m.get("idle", false), "P%d touchdown and idle observed" % n)
		if not baseline: check(float(m.get("motion", 0.0)) > .001, "P%d clip moves across multiple air frames" % n)
		m.erase("last_q")
	if completed and not baseline:
		await verify_retry(world)
	var report := {"passed":failures.is_empty(),"failures":failures,"checks":checks,"players":players,"fps":fps,"baseline":baseline,"observed":observed,"samples":samples,"pictures":pictures}
	FileAccess.open(OUT+label+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FALLING_IDLE_ACCEPTANCE ", JSON.stringify({"passed":failures.is_empty(),"label":label,"checks":checks.size(),"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func picture(key: String) -> void:
	if pictures.has(key): return
	var path := OUT + label + "/" + key + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	pictures[key] = path
	var n := key.substr(1, 1).to_int()
	if closeups.has(n):
		var detail := OUT + label + "/" + key + "_detail.png"
		closeups[n].viewport.get_texture().get_image().save_png(detail)
		pictures[key + "_detail"] = detail

func verify_retry(world: Node) -> void:
	var world_id := world.get_instance_id()
	world.get_node("GameplayHUD").call("_retry_game")
	var deadline := Time.get_ticks_msec() + 20000
	var retried := false
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene == null or scene.get_instance_id() == world_id or SceneTransition.is_transitioning(): continue
		retried = true
		check(scene.get_node_or_null("HelicopterArrivalDirector") == null, "retry still skips helicopter")
		var pc := scene.get("player_node") as PlayerController
		check(pc != null and not pc.has_intro_arrival(), "retry has no retained falling pose")
		if pc != null: await verify_cancel_and_loop(pc)
		break
	check(retried, "retry completes")

func verify_cancel_and_loop(pc: PlayerController) -> void:
	var rig := pc._p1_rig
	var ap: AnimationPlayer = rig.aps[AnimationRig.SLOT_FALLING_IDLE]
	var animation := ap.get_animation(rig.anim_names[AnimationRig.SLOT_FALLING_IDLE])
	rig.seek_falling_idle(.2)
	var bone: int = rig.active_bone_indices.l_lower_arm
	var original := rig.active_skeleton.get_bone_pose_rotation(bone)
	rig.seek_falling_idle(.2 + animation.length * 3.0)
	check(original.angle_to(rig.active_skeleton.get_bone_pose_rotation(bone)) < .001, "falling loop repeats after three cycles")
	var pelvis: Node3D = pc.p1_parts.pelvis
	var ground := Vector3(pelvis.global_position.x, StageConstants.FLOOR_TOP_Y, pelvis.global_position.z)
	pelvis.global_position = ground + Vector3.UP * 5.0
	check(pc.begin_intro_ladder_jump(1, Vector3(0, -1, 0), ground, .8), "interrupted flight begins")
	await get_tree().process_frame
	pc.update_intro_ladder_jump(1, .1)
	pc.cancel_intro_drops()
	pc.update_from_state(QuizManager.game_state)
	check(not pc.has_intro_arrival() and pc._intro_ragdolls.is_empty() and pc._intro_hat_restore.is_empty(), "cancellation clears falling and physical state")
	check(pc.p1_parts.head.is_visible_in_tree() and pc.p1_parts.l_hand.is_visible_in_tree(), "cancellation restores ordinary avatar")

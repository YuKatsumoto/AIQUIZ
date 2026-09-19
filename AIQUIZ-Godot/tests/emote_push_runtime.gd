extends "res://tests/local_push_runtime.gd"
const EMOTE_OUTPUT := "res://artifacts/emote_push/"
var observations: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var clip := ""
var capture_phases := {}
var expected_emotes := [0, 0]

func run() -> void:
	name = "EmotePushRuntime"
	gs = QuizManager.game_state
	old_source = QuizManager.provider.llm_mode
	QuizManager.provider.llm_mode = "OFFLINE"
	previous_fps = Engine.max_fps
	Engine.max_fps = 60
	if await _start(Constants.MODE_ENDLESS):
		await _wait(2.0)
		RenderingServer.frame_post_draw.connect(_observe)
		for slot in range(3):
			for mirror in [1, -1]:
				await _case(slot, mirror)
		RenderingServer.frame_post_draw.disconnect(_observe)
	_release_all()
	Engine.max_fps = previous_fps
	QuizManager.provider.llm_mode = old_source
	for capture: Dictionary in captures:
		capture.image.save_png(capture.path)
	captures.clear()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"renderer": RenderingServer.get_current_rendering_method(), "observations": observations, "events": events}
	FileAccess.open(EMOTE_OUTPUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	finished = true
	print("EMOTE_PUSH_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "failures": failures}))

func _case(slot: int, mirror: int) -> void:
	clip = "slot%d_mirror%d" % [slot + 1, mirror]
	phase = clip
	_release_all()
	gs.local_push.reset()
	gs.player_x = 0.62 * mirror
	gs.player2_x = -0.62 * mirror
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z
	gs.wall_z = gs.world_scroll_z + 100.0
	gs._active_wall_speed = 0.0
	gs.p1_emote = 0
	gs.p2_emote = 0
	expected_emotes = [gs.p1_emote_slots[slot], gs.p2_emote_slots[slot]]
	_key([KEY_1, KEY_2, KEY_3][slot], true)
	_key([KEY_8, KEY_9, KEY_0][slot], true)
	await _wait(0.10)
	_key([KEY_1, KEY_2, KEY_3][slot], false)
	_key([KEY_8, KEY_9, KEY_0][slot], false)
	var start := observations.size()
	_inward()
	await _wait(0.3)
	gs.local_push_event.connect(_on_event)
	for attacker in [1, 2]:
		var target_x := gs.player2_x if attacker == 1 else gs.player_x
		var since := events.size()
		_repress(attacker)
		await _wait(0.21)
		_check(_count("hit", since, attacker) == 1, clip + " P%d hits during emote" % attacker)
		var moved := (gs.player2_x if attacker == 1 else gs.player_x) - target_x
		_check(absf(moved) > 0.20, clip + " target displaced by P%d" % attacker)
		await _wait(0.3)
	gs.local_push_event.disconnect(_on_event)
	_release_all()
	await _wait(0.25)
	var segment := observations.slice(start)
	for player in [1, 2]:
		var rows: Array = segment.filter(func(row: Dictionary): return row.player == player)
		_check(rows.all(func(row: Dictionary): return row.emote_playing and row.emote == expected_emotes[player - 1]), clip + " P%d emote keeps playing throughout push" % player)
		var recoil: Array = rows.filter(func(row: Dictionary): return row.phase == "recoil" and absf(row.lean) > 5.0)
		_check(recoil.size() >= 2, clip + " P%d recoil visible across frames" % player)
		_check(not recoil.is_empty() and recoil.all(func(row: Dictionary): return row.overlay_error < 0.1 and row.applied_angle > 5.0), clip + " P%d rendered spine tilts with recoil" % player)
		_check(rows.any(func(row: Dictionary): return row.phase == "brace" and row.applied_angle > 3.0), clip + " P%d leans while bracing" % player)
		var times: Array = rows.map(func(row: Dictionary): return row.animation_time)
		_check(times.max() - times.min() > 0.5, clip + " P%d dance timeline advances" % player)
	clip = ""

func _observe() -> void:
	if clip.is_empty():
		return
	var controller = world.player_node
	for player in [1, 2]:
		var rig = controller._p1_rig if player == 1 else controller._p2_rig
		var parts: Dictionary = controller.p1_parts if player == 1 else controller.p2_parts
		var pose := gs.get_local_push_pose(player)
		var spine: Node3D = parts.spine
		var error := 0.0
		var angle := 0.0
		for saved: Dictionary in controller._push_pose_restore:
			if saved.node == spine:
				var base: Basis = spine.get_parent_node_3d().global_basis * saved.transform.basis
				var expected := Basis(Vector3.FORWARD, deg_to_rad(float(pose.lean))) * base
				error = rad_to_deg(spine.global_basis.get_rotation_quaternion().angle_to(expected.get_rotation_quaternion()))
				angle = rad_to_deg(spine.global_basis.get_rotation_quaternion().angle_to(base.get_rotation_quaternion()))
		var anim_time := 0.0
		for anim_slot in AnimationRig.EMOTE_RIG_SLOTS:
			var ap: AnimationPlayer = rig.aps[anim_slot]
			if ap != null and ap.is_playing():
				anim_time = ap.current_animation_position
		var row := {"case": clip, "time": gs.local_push.time, "player": player,
			"phase": pose.get("phase", "run"), "lean": pose.get("lean", 0.0), "applied_angle": angle, "overlay_error": error,
			"emote": gs.p1_emote if player == 1 else gs.p2_emote, "emote_playing": rig.is_emote_playing(), "animation_time": anim_time}
		observations.append(row)
		var key := "%s_p%d_%s" % [clip, player, row.phase]
		if row.phase in ["brace", "strike", "recoil"] and not capture_phases.has(key) and absf(row.lean) > 5.0:
			capture_phases[key] = true
			captures.append({"path": EMOTE_OUTPUT + key + ".png", "image": get_viewport().get_texture().get_image()})

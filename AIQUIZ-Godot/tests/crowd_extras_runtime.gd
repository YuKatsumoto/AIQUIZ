extends Node

## Crowd extras (docs/crowd_extras.md) on the real stands: the side stands with
## their seated crowd and mascots, the goal stand with its personalities, all
## driven by CrowdCues through the cues the game sends (countdown, start, a miss,
## a shock, the stadium wave, the chant and the winner's dance).
##   Godot --path . --script tests/crowd_extras_bootstrap.gd --fixed-fps 60
## Saves screenshots to artifacts/crowd_extras/runtime/ (needs a window); under
## --headless only the structural and timing checks run.

const StageScript = preload("res://scripts/world/stage_environment.gd")
const CrowdScript = preload("res://scripts/world/grandstand_crowd.gd")
const Kit = preload("res://scripts/world/seated_spectator_kit.gd")
const OUT := "res://artifacts/crowd_extras/runtime/"
const DT := 1.0 / 60.0


class DirectorStub:
	extends Node
	var elapsed := 0.0

	func result_elapsed() -> float:
		return elapsed

	func crowd_egg_target() -> Node3D:
		return null


var errors: Array[String] = []
var report := {}
var stage: Node3D
var stand: GoalStand
var state: QuizGameState
var cues: CrowdCues
var director: DirectorStub
var camera: Camera3D
var shots := DisplayServer.get_name() != "headless"


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and not errors.has(message):
		errors.append(message)
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_build()
	await _frames(30)
	_check_cast()
	await _countdown_and_start()
	await _miss_and_shock()
	await _wave()
	await _chant()
	await _personalities()
	await _winner_dance()
	print("CROWD_EXTRAS ", "PASS" if errors.is_empty() else "FAIL", " ", JSON.stringify({"errors": errors, "report": report}))
	get_tree().quit(0 if errors.is_empty() else 1)


func _build() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.58, 0.72, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(25.0), 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	stage = StageScript.new()
	add_child(stage)
	var config: Dictionary = stage.gameplay_build_config()
	config.floor_center_z = 60.0
	config.floor_length = 150.0
	stage.build(config)
	stand = GoalStand.new()
	add_child(stand)
	stand.setup("high")
	stand.position = Vector3(0.0, StageConstants.FLOOR_TOP_Y, 135.0 + GoalStand.GOAL_OFFSET)
	state = QuizGameState.new()
	state.num_players = 2
	state.mode = Constants.MODE_TEN
	state.game_state = Constants.STATE_WAITING_START
	state.p1_emote_slots = [EmoteData.EMOTE_YMCA]
	state.p2_emote_slots = [EmoteData.EMOTE_GANGNAM]
	director = DirectorStub.new()
	add_child(director)
	cues = CrowdCues.new()
	camera = Camera3D.new()
	camera.far = 3000.0
	add_child(camera)
	camera.make_current()
	CrowdScript.prepare_dances(EmoteData.EMOTE_YMCA, EmoteData.EMOTE_GANGNAM)


## One game frame of the crowd, as game_world._update_crowd() runs it.
func _step() -> void:
	var stands := stage.get_node("Grandstands") as Node3D
	cues.course_z = stands.global_position.z
	cues.goal_course = stand.global_position.z - cues.course_z
	var use_director: Node = director if state.result_presentation_active else null
	cues.update(DT, state, stand.side_crowd_reaction(), use_director)
	stand.update_stand(DT, state, use_director, camera, true, cues)
	CrowdScript.follow_cues(cues)
	CrowdScript.update_mascots(cues, DT, camera)


func _frames(count: int) -> void:
	for _i in range(count):
		_step()
		await get_tree().process_frame


func _shot(name: String, eye: Vector3, target: Vector3, fov := 45.0) -> void:
	if not shots:
		return
	camera.global_position = eye
	camera.look_at(target)
	camera.fov = fov
	for _i in range(3):
		_step()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")


func _goal_clips() -> Dictionary:
	return stand.get_debug_snapshot().clips


func _check_cast() -> void:
	var shot := stand.get_debug_snapshot()
	report["goal_kinds"] = shot.kinds
	for kind: String in ["SLEEPER", "EATER", "SELFIE", "BINOCULARS", "LEADER", "TOWEL", "PAIR", "CARRIER", "VENDOR"]:
		check(int(shot.kinds.get(kind, 0)) > 0, "goal stand has %s" % kind)
	check(int(shot.kids) == int(shot.kinds.get("CARRIER", 0)), "every carrier has a child on the shoulders")
	check(stand.mascot != null and stand.mascot.player != null, "goal stand mascot animated")
	var mascots := 0
	var roles := {}
	for side: Node3D in stage.get_node("Grandstands").get_children():
		var crowd := side.get_node("Spectators")
		mascots += 1 if crowd.mascot != null and crowd.mascot.player != null else 0
		for role: int in crowd.role_counts:
			roles[role] = int(roles.get(role, 0)) + int(crowd.role_counts[role])
	report["side_roles"] = roles
	check(mascots == 2, "a mascot on each side stand (%d)" % mascots)
	for role: int in [CrowdScript.ROLE_SLEEPER, CrowdScript.ROLE_EATER, CrowdScript.ROLE_SELFIE, CrowdScript.ROLE_BINOCULARS,
			CrowdScript.ROLE_LEADER, CrowdScript.ROLE_TOWEL, CrowdScript.ROLE_PAIR_L, CrowdScript.ROLE_PAIR_R]:
		check(int(roles.get(role, 0)) > 0, "side stands have role %d" % role)
	check(int(roles.get(CrowdScript.ROLE_PAIR_L, 0)) == int(roles.get(CrowdScript.ROLE_PAIR_R, 0)), "side pairs come in twos")
	# Kids sit on the carrier's shoulders.
	for s: GoalStand.Spectator in stand.spectators:
		if s.kind == GoalStand.Kind.CARRIER and s.kid != null:
			var lift := s.kid.root.global_position.y - s.root.global_position.y
			check(lift > 1.3 and lift < 1.65, "child sits on the shoulders (%.2f m up)" % lift)


func _countdown_and_start() -> void:
	state.game_state = Constants.STATE_COUNTDOWN
	await _frames(40)
	check(cues.cue == CrowdCues.Cue.COUNTDOWN, "countdown cue")
	check(String(stand.get_debug_snapshot().mood) == "countdown", "goal stand leans in for the countdown")
	check(int(_goal_clips().get("SPEC_Anticipate", 0)) > 10, "goal crowd anticipates (%s)" % [_goal_clips()])
	await _shot("countdown_side", Vector3(18.0, 4.0, 40.0), Vector3(31.0, 2.0, 46.0))
	state.game_state = Constants.STATE_PLAYING
	await _frames(30)
	check(cues.cue == CrowdCues.Cue.START, "start cue")
	check(int(_goal_clips().get("SPEC_Cheer", 0)) > 10, "goal crowd cheers the start")
	await _shot("start_goal", Vector3(0.0, 4.5, 146.0), Vector3(0.0, 2.2, 161.0), 55.0)
	await _shot("start_side", Vector3(18.0, 4.0, 40.0), Vector3(31.0, 2.0, 46.0))
	await _frames(150)


func _miss_and_shock() -> void:
	cues.on_miss(1)
	await _frames(40)
	check(String(stand.get_debug_snapshot().mood) == "miss1", "goal stand reacts to P1's miss")
	var clips := _goal_clips()
	check(int(clips.get("SPEC_PointLaugh", 0)) > 3 and int(clips.get("SPEC_Despair", 0)) + int(clips.get("SPEC_ShakeHead", 0)) > 3,
		"P1 fans groan, P2 fans laugh (%s)" % [clips])
	await _shot("miss_p1_right", Vector3(18.0, 4.0, 40.0), Vector3(31.0, 2.0, 46.0))
	await _shot("miss_p1_left", Vector3(-18.0, 4.0, 40.0), Vector3(-31.0, 2.0, 46.0))
	await _frames(200)
	cues.on_shock(48.0)
	await _frames(25)
	await _shot("shock", Vector3(18.0, 4.0, 40.0), Vector3(31.0, 2.0, 48.0))
	await _frames(200)
	cues.on_hurt(2)
	await _frames(30)
	check(String(stand.get_debug_snapshot().mood) == "hurt2", "goal stand groans at P2's lost HP")
	await _frames(150)


func _wave() -> void:
	cues.wave_started = cues.clock
	await _frames(2)
	var right_mascot: Node3D = (stage.get_node("Grandstands/GrandstandRight") as Node3D).get_node("Spectators").mascot
	check(right_mascot != null and String(right_mascot.action) == "wave_lead", "the right stand's mascot starts the wave")
	await _shot("wave_start_mascot", right_mascot.global_position + Vector3(-7.0, 2.2, -5.0),
		right_mascot.global_position + Vector3(0.0, 1.2, 1.0), 40.0)
	# The wave reaches course z 70 (world 55) after 50 / 16 s.
	await _frames(int((70.0 - cues.wave_origin) / CrowdCues.WAVE_SPEED / DT) - 6)
	await _shot("wave_right", Vector3(16.0, 5.0, 38.0), Vector3(31.0, 2.5, 58.0), 55.0)
	var to_goal := cues.wave_arrival_goal_stand(4.0)
	while cues.wave_time() < to_goal:
		await _frames(1)
	var overlays := int(stand.get_debug_snapshot().overlays)
	report["wave_goal_overlays"] = overlays
	check(overlays > 3 and int(_goal_clips().get("SPEC_StandWave", 0)) > 3, "the wave crosses the goal stand")
	await _shot("wave_goal", Vector3(0.0, 4.5, 146.0), Vector3(0.0, 2.2, 161.0), 55.0)
	var to_left := cues.wave_arrival_side(false, 70.0)
	while cues.wave_time() < to_left and cues.wave_time() >= 0.0:
		await _frames(1)
	await _shot("wave_left", Vector3(-16.0, 5.0, 75.0), Vector3(-31.0, 2.5, 55.0), 55.0)
	while cues.wave_time() >= 0.0:
		await _frames(1)


func _chant() -> void:
	cues.chant_started = cues.clock
	cues.chant_until = cues.clock + 6.0
	cues.chant_team = 1
	await _frames(40)
	var clips := _goal_clips()
	report["chant_clips"] = clips
	check(int(clips.get("SPEC_ChantClap", 0)) > 5, "P1 fans clap on the leaders' beat")
	check(String(stand.mascot.action) == "clap", "the mascot claps with the chant")
	await _shot("chant_right", Vector3(18.0, 4.0, 40.0), Vector3(31.0, 2.0, 46.0))
	await _shot("chant_goal", Vector3(-3.0, 4.0, 147.0), Vector3(-6.0, 2.0, 161.0), 50.0)
	await _frames(400)


func _personalities() -> void:
	# Close-ups of the goal stand's characters in the lull.
	var vendor_y := {}
	for s: GoalStand.Spectator in stand.spectators:
		if s.kind == GoalStand.Kind.VENDOR:
			vendor_y[s] = s.walk_y
	await _frames(120)
	for s: GoalStand.Spectator in vendor_y:
		check(not is_equal_approx(s.walk_y, vendor_y[s]) or s.clip == &"SPEC_VendorCall", "vendor walks the aisle or calls out")
		check(s.root.position.y >= 0.3 and s.root.position.y <= 1.5, "vendor stays on the aisle steps")
	report["vendors"] = stand.get_debug_snapshot().vendors
	var looks := {GoalStand.Kind.SLEEPER: "sleeper", GoalStand.Kind.EATER: "eater", GoalStand.Kind.SELFIE: "selfie",
		GoalStand.Kind.BINOCULARS: "binoculars", GoalStand.Kind.LEADER: "leader", GoalStand.Kind.CARRIER: "carrier",
		GoalStand.Kind.VENDOR: "vendor", GoalStand.Kind.PAIR: "pair", GoalStand.Kind.TOWEL: "towel"}
	var seen := {}
	for s: GoalStand.Spectator in stand.spectators:
		if not looks.has(s.kind) or seen.has(s.kind):
			continue
		seen[s.kind] = true
		var at := s.root.global_position + Vector3(0.0, 1.2, 0.0)
		var eye := at + (stand.global_basis * Vector3(0.0, 0.6, 4.2))
		await _shot("closeup_" + looks[s.kind], eye, at, 40.0)
	await _shot("closeup_mascot", stand.mascot.global_position + stand.global_basis * Vector3(0.0, 1.6, 5.0),
		stand.mascot.global_position + Vector3(0.0, 1.0, 0.0), 45.0)
	await _shot("side_personalities", Vector3(22.0, 3.5, 22.0), Vector3(30.5, 1.8, 25.0), 40.0)


func _winner_dance() -> void:
	# The finale's verdict: P1 wins with YMCA; the crowd joins at ResultWinnerDance.START.
	state.game_state = Constants.STATE_RESULT_CEREMONY
	state.result_presentation_active = true
	state.result_winner = 1
	director.elapsed = ResultWinnerDance.START + 1.5
	var waited := 0
	while not (Kit.sync_ready(1) and Kit.sync_ready(2)) and waited < 900:
		director.elapsed += DT
		await _frames(1)
		waited += 1
	check(Kit.sync_ready(1), "the winner's dance is baked for the side stands")
	await _frames(30)
	director.elapsed += 0.5
	var clips := _goal_clips()
	report["dance_clips"] = clips
	check(int(clips.get("SPEC_Dance_YMCA", 0)) > 5, "the goal crowd dances the winner's YMCA (%s)" % [clips])
	check(String(stand.mascot.action) == "dance", "the mascot dances")
	# Every synced dancer is on the same beat.
	var times := []
	for s: GoalStand.Spectator in stand.spectators:
		if s.clip == &"SPEC_Dance_YMCA":
			times.append(snappedf(s.ap.current_animation_position, 0.01))
	var spread := 0.0
	for t: float in times:
		spread = maxf(spread, absf(t - float(times[0])))
	report["dance_spread"] = spread
	check(spread < 0.2 or spread > 4.3, "goal crowd dances in step (spread %.2f s)" % spread)
	await _shot("dance_goal", Vector3(0.0, 4.5, 146.0), Vector3(0.0, 2.2, 161.0), 55.0)
	await _shot("dance_right", Vector3(18.0, 4.0, 120.0), Vector3(31.0, 2.0, 126.0))
	state.result_presentation_active = false

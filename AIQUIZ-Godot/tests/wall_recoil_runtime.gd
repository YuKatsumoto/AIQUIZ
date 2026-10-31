extends Node

## HP のある不正解の衝突を実ゲームで確かめる：扉の表面で当たり、後ろへ弾かれ、のけぞりと後ずさりの
## 姿になり、問題のあいだは迫る壁の表面で止まる。体のメッシュが扉・壁の面を越えて埋まらないことを測る。
const OUT := "res://artifacts/contact_speed_fix/wall_recoil/"
## 体のメッシュが壁の面を越えてよい量（m）。描画の箱どうしが触れる程度。
const CLIP_TOLERANCE := 0.03
## 足が扉の面へ触れてよい量（m）。走りの歩幅で前へ出たつま先が当たる直前に、
## ぶつかった足のすねが衝突の1フレームだけ、この程度まで触れる。
const LEG_CLIP_TOLERANCE := 0.18
var gs: QuizGameState
var world: Node3D
var pc: PlayerController
var helper: Node
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var checks := 0
var video_frame := 0
var side_view: SubViewport
var side_camera: Camera3D
var clip_details: Array[Dictionary] = []
## 場面ごとの、部位ごとの最大のはみ出し（判定の材料として runtime.json に残す）。
var clip_summary: Dictionary = {}

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "side"))
	helper = load("res://tests/hp_unit.gd").new()
	QuizManager.player_analytics = null
	await scenario("p1_wrong", 2, false, true)
	await scenario("p2_wrong", 2, true, false)
	await scenario("both_wrong", 2, false, false)
	await scenario("solid_wall", 1, false, true, true)
	await scenario("solo_wrong", 1, false, true)
	await stagger_hold()
	await border_lane()
	# The overlay must reconstruct from existing synchronized damage state.
	world.set("_replay_mode", true)
	gs.p1_damage_time = 0.46
	gs.is_replay = true
	await frames(3)
	check(not pc.get("_health_pose_restore").is_empty() and is_zero_approx(pc.p1_parts.pelvis.position.z), "replay damage state reconstructs recoil")
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
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "frames": video_frame, "clip_summary": clip_summary, "clip_details": clip_details, "samples": rows}
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WALL_RECOIL_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "frames": video_frame}))
	for provider in helper.providers:
		provider.free()
	helper.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func setup_world(players: int) -> void:
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
	if side_view == null:
		side_view = SubViewport.new()
		side_view.size = Vector2i(640, 360)
		side_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		side_camera = Camera3D.new()
		side_camera.fov = 40.0
		side_view.add_child(side_camera)
		add_child(side_view)
	side_view.world_3d = get_viewport().find_world_3d()
	side_camera.current = true
	await frames(50)

func scenario(tag: String, players: int, correct1: bool, correct2: bool, solid := false) -> void:
	await setup_world(players)
	var events: Array = []
	gs.health_changed.connect(func(p, old, hp): events.append({"p":p,"old":old,"hp":hp}))
	for player in range(1, players + 1):
		var rig: AnimationRig = pc.get("_p1_rig" if player == 1 else "_p2_rig")
		check(not rig.resolve_ual_clip("Hit_Chest", AnimationRig.SLOT_UAL).is_empty(), tag + " authored recoil available P%d" % player)
		check(not rig.resolve_ual_clip("Jog_Fwd_Loop", AnimationRig.SLOT_UAL).is_empty(), tag + " backpedal clip available P%d" % player)
	gs.player_x = 0.0 if solid else helper.door(gs, correct1) + (0.4 if players == 2 and correct1 == correct2 else 0.0)
	gs.player2_x = helper.door(gs, correct2) - (0.4 if correct1 == correct2 else 0.0)
	gs.world_scroll_z = gs.wall_z - 2.4
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z
	await frames(3)
	await capture(tag + "_before")
	world.set("_replay_mode", false)
	var clip := [{}, {}]
	var crossed := false
	for i in range(120):
		await frames(1)
		_track_clip(clip, 0)
		if i % 2 == 0: await sample(tag)
		if gs.current_wall_index > 0:
			crossed = true
			break
	check(crossed, tag + " actual wall collision")
	check(gs.camera_shake > 0.25, tag + " impact starts stronger brief camera shake")
	var z0 := [gs.player_z - gs.world_scroll_z, gs.player2_z - gs.world_scroll_z]
	var retreat := [0.0, 0.0]
	var authored := [false, false]
	var max_spine_angle := [0.0, 0.0]
	var max_leg_angle := [0.0, 0.0]
	var pelvis_offset := 0.0
	for i in range(48):
		await frames(1)
		_track_clip(clip, 0)
		for player in range(1, players + 1):
			var parts: Dictionary = pc.p1_parts if player == 1 else pc.p2_parts
			var local_z := (gs.player_z if player == 1 else gs.player2_z) - gs.world_scroll_z
			retreat[player - 1] = maxf(retreat[player - 1], z0[player - 1] - local_z)
			pelvis_offset = maxf(pelvis_offset, absf(parts.pelvis.position.z))
			if gs.get_damage_time(player) > 0.05:
				var rig: AnimationRig = pc.get("_p1_rig" if player == 1 else "_p2_rig")
				authored[player - 1] = authored[player - 1] or rig.active_skeleton == rig.skeletons[AnimationRig.SLOT_UAL]
			for saved: Dictionary in pc.get("_health_pose_restore"):
				var baseline: Transform3D = saved.transform
				var angle := rad_to_deg(baseline.basis.get_rotation_quaternion().angle_to((saved.node as Node3D).quaternion))
				if saved.node == parts.spine:
					max_spine_angle[player - 1] = maxf(max_spine_angle[player - 1], angle)
				elif saved.node == parts.l_hip or saved.node == parts.r_hip:
					max_leg_angle[player - 1] = maxf(max_leg_angle[player - 1], angle)
		if i % 2 == 0: await sample(tag)
		if i == 2: await capture(tag + "_impact")
		if i == 12: await capture(tag + "_peak")
	await capture(tag + "_returned")
	check(pelvis_offset < 0.001, tag + " no visual-only offset: %f" % pelvis_offset)
	for player in range(1, players + 1):
		var correct := correct1 if player == 1 else correct2
		check(gs.get_player_hp(player) == (3 if correct else 2), tag + " one HP only on wrong contact P%d" % player)
		_check_clip(tag, player, clip[player - 1])
		if not correct:
			check(retreat[player - 1] > 1.9 and retreat[player - 1] < 2.3, tag + " knocked back from the door face P%d: %f" % [player, retreat[player - 1]])
			check(authored[player - 1] and max_spine_angle[player - 1] > 5.0, tag + " authored recoil pose P%d: %f" % [player, max_spine_angle[player - 1]])
			check(max_leg_angle[player - 1] > 15.0, tag + " legs step back P%d: %f" % [player, max_leg_angle[player - 1]])
		else:
			check(retreat[player - 1] < 0.01 and not authored[player - 1], tag + " correct player unaffected P%d" % player)
	check(gs.current_wall_index == 1, tag + " advances once")
	check(events.size() == (int(not correct1) + (int(not correct2) if players == 2 else 0)), tag + " no repeated damage")
	check(pc.get("_health_pose_restore").is_empty(), tag + " animation fully released")
	check(is_zero_approx(gs.camera_shake), tag + " camera shake fully settles")

## 2P：P1 だけ先に不正解で弾かれ、P2 が来るまで迫ってくる壁の表面で止まる。
func stagger_hold() -> void:
	var tag := "stagger_hold"
	await setup_world(2)
	gs.player_x = helper.door(gs, false)
	gs.player2_x = helper.door(gs, true)
	gs.world_scroll_z = gs.wall_z - 2.4
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z - 4.0
	await frames(3)
	world.set("_replay_mode", false)
	var clip := [{}, {}]
	var held_frames := 0
	var beyond := 0.0
	for i in range(300):
		await frames(1)
		_track_clip(clip, 0)
		if gs.is_held_by_wall(1):
			held_frames += 1
			beyond = maxf(beyond, gs.player_z - (gs.wall_z - QuizGameState.WALL_FACE_CONTACT_DISTANCE))
		if i % 3 == 0: await sample(tag)
		if i == 70: await capture(tag + "_held")
		if gs.current_wall_index > 0:
			break
	check(gs.p1_hp == 2 and gs.p2_hp == 3 and gs.current_wall_index == 1, tag + " P1 hurt once, P2 completes the question")
	check(held_frames > 20, tag + " P1 was held by the wall while waiting: %d" % held_frames)
	check(beyond <= 0.0001, tag + " held body stays at the door face: %f" % beyond)
	for player in [1, 2]:
		_check_clip(tag, player, clip[player - 1])

func _check_clip(tag: String, player: int, clip: Dictionary) -> void:
	clip_summary["%s P%d" % [tag, player]] = clip
	check(float(clip.get("trunk", 0.0)) <= CLIP_TOLERANCE, tag + " torso and head never sink into the wall P%d: %s" % [player, str(clip)])
	check(float(clip.get("legs", 0.0)) <= LEG_CLIP_TOLERANCE, tag + " legs only touch the wall P%d: %s" % [player, str(clip)])

## 壁端より外のボーダーの列は、判定の線を越えても被弾しない。
func border_lane() -> void:
	var tag := "border_lane"
	await setup_world(1)
	gs.player_x = StageConstants.QUIZ_WALL_HALF_WIDTH + 0.25
	gs.world_scroll_z = gs.wall_z - 2.4
	gs.player_z = gs.world_scroll_z
	await frames(3)
	world.set("_replay_mode", false)
	for i in range(60):
		await frames(1)
	check(gs.p1_hp == 3 and gs.current_wall_index == 0 and gs.p1_alive, tag + " border never damages")
	check(gs.player_z <= gs.wall_z - QuizGameState.WALL_WORLD_BORDER_STOP_DISTANCE + 0.0001, tag + " border still stops the body")

## 体の各メッシュが、まだ見えている壁・扉の箱の手前の面をどれだけ越えたか（x と y が重なるものだけ）。
## clip は [P1, P2] の {"trunk", "legs", "arms"}。胴と頭は埋めない。足は歩幅のつま先が触れる程度まで、
## 腕と手は記録だけ（腕の長さぶん体を壁から離すと、胴が宙で止まって見える）。
func _track_clip(clip: Array, wall_index: int) -> void:
	var wall: Node3D = null
	for candidate: Node3D in world.get("_active_walls"):
		if is_instance_valid(candidate) and int(candidate.get_meta("wall_index", -1)) == wall_index:
			wall = candidate
	if wall == null:
		return
	var solids: Array[AABB] = []
	var solid_names: Array[String] = []
	for part: MeshInstance3D in wall.get("wall_parts") + wall.get("doors"):
		if not is_instance_valid(part) or not part.is_visible_in_tree():
			continue
		var material := part.material_override as StandardMaterial3D
		if material != null and material.albedo_color.a < 0.5:
			continue
		solids.append(part.global_transform * part.get_aabb())
		solid_names.append(str(part.name))
	for player in range(1, gs.num_players + 1):
		var parts: Dictionary = pc.p1_parts if player == 1 else pc.p2_parts
		for mesh: MeshInstance3D in parts.get("meshes", []):
			if not is_instance_valid(mesh) or not mesh.is_visible_in_tree():
				continue
			var key := _part_key(parts, mesh)
			var group := "trunk"
			for limb: String in ["arm", "hand", "wrist", "elbow", "thumb", "index", "middle", "ring", "pinky"]:
				if key.contains(limb):
					group = "arms"
			for limb: String in ["thigh", "calf", "toe", "foot", "ankle", "knee", "hip_", "leg"]:
				if key.contains(limb):
					group = "legs"
			var box := mesh.global_transform * mesh.get_aabb()
			var slot: Dictionary = clip[player - 1]
			for s in range(solids.size()):
				var solid := solids[s]
				var overlap_x := box.position.x < solid.end.x and box.end.x > solid.position.x
				var overlap_y := box.position.y < solid.end.y and box.end.y > solid.position.y
				var depth := box.end.z - solid.position.z
				if overlap_x and overlap_y and box.position.z < solid.end.z and depth > float(slot.get(group, 0.0)):
					slot[group] = depth
					clip_details.append({"player": player, "depth": depth, "mesh": key, "group": group,
						"solid": solid_names[s], "solid_box": str(solid), "box": str(box), "time": gs.play_time,
						"z": (gs.player_z if player == 1 else gs.player2_z) - gs.world_scroll_z, "wall_local": gs.wall_z - gs.world_scroll_z,
						"hurt": gs.get_damage_time(player), "wall": gs.current_wall_index})

## メッシュが属する体の部位の名前（parts の鍵。指などの小部品は親をたどる）。
func _part_key(parts: Dictionary, mesh: Node) -> String:
	var node := mesh
	while node != null:
		for key: String in parts:
			if parts[key] is Node and parts[key] == node:
				return key
		node = node.get_parent()
	return str(mesh.name)

func sample(tag: String) -> void:
	var target := pc.global_position
	# Profile view along -X: the door face is a vertical edge on the right of the frame.
	side_camera.global_position = target + Vector3(6.0, 1.1, 0.4)
	side_camera.look_at(target + Vector3(0.0, 1.0, 0.4))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "frames/%04d.png" % video_frame)
	side_view.get_texture().get_image().save_png(OUT + "side/%04d.png" % video_frame)
	video_frame += 1
	rows.append({"tag":tag,"time":gs.play_time,"hurt1":gs.p1_damage_time,"hurt2":gs.p2_damage_time,"z1":gs.player_z - gs.world_scroll_z,"z2":gs.player2_z - gs.world_scroll_z if gs.num_players == 2 else 0.0,"wall_local":gs.wall_z - gs.world_scroll_z,"ext1":gs.p1_external_velocity.y,"hp1":gs.p1_hp,"hp2":gs.p2_hp,"wall":gs.current_wall_index,"shake":gs.camera_shake,"camera_x":get_viewport().get_camera_3d().global_position.x})

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

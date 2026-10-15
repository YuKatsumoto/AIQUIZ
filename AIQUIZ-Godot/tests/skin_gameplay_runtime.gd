extends Node

## 体の色はオンライン対戦だけ。実際のオフライン試合（2人・ヘリ到着あり）では、
## 体の色を変えてあっても各スロットの標準色で出るかを確かめる。
## ヘリ到着（降下ラグドール）・走行中・壁での死亡（破片）を撮り、マテリアルの色も検査する。
## 写真は artifacts/skin_gameplay/。保存ファイルには書かない（--fresh-profile）。
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/skin_gameplay_bootstrap.gd -- --fresh-profile

const OUT := "res://artifacts/skin_gameplay/"
const P1_CHEST := Color8(250, 210, 60)
const P1_REST := Color8(120, 64, 200)
const P2_CHEST := Color8(30, 30, 34)
const P2_REST := Color8(245, 245, 240)

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func _check(ok: bool, label: String) -> void:
	if not ok and not _failures.has(label):
		_failures.append(label)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.max_fps = 60
	get_tree().root.size = Vector2i(1280, 720)
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.set_player_skin(1, PlayerSkin.set_color(PlayerSkin.set_color(PlayerSkin.default_skin(1), PlayerSkin.ALL, P1_REST), &"chest", P1_CHEST))
	gs.set_player_skin(2, PlayerSkin.set_color(PlayerSkin.set_color(PlayerSkin.default_skin(2), PlayerSkin.ALL, P2_REST), &"chest", P2_CHEST))
	gs.p1_hat = HatData.HAT_PROPELLER
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	gs.start_game()
	gs.skip_start_helicopter_arrival = false
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	while get_tree().current_scene == null:
		await get_tree().process_frame
	var world := get_tree().current_scene
	var pc: PlayerController = world.player_node

	# ヘリ到着（読み込み後の数秒）を 0.8 秒ごとに撮り、降下中のラグドールがあれば色を確かめる。
	var deadline := Time.get_ticks_msec() + 60000
	while SceneTransition.is_transitioning() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ragdoll_checked := false
	var watch_until := Time.get_ticks_msec() + 14000
	var next_shot := 0
	var shot := 0
	while Time.get_ticks_msec() < watch_until:
		await get_tree().process_frame
		if not ragdoll_checked:
			ragdoll_checked = _check_ragdoll_colors(world)
		if Time.get_ticks_msec() >= next_shot and shot < 16:
			await _capture("arrival_%02d" % shot)
			shot += 1
			next_shot = Time.get_ticks_msec() + 800
	while world.is_start_presentation_locked() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(Time.get_ticks_msec() < deadline, "startup completes")
	print("SKIN_GAMEPLAY ragdoll seen: ", ragdoll_checked)

	# 走行中
	await _frames(90)
	await _capture("playing")
	_check(_albedo(pc.p1_parts.upper_torso) == _standard(1, &"chest"), "P1 chest is the standard color offline")
	_check(_albedo(pc.p1_parts.head) == _standard(1, &"head"), "P1 head is the standard color offline")
	_check(_albedo(pc.p1_parts.l_upp_arm) == _standard(1, &"l_arm"), "P1 arm is the standard color offline")
	_check(not pc.p2_parts.is_empty() and _albedo(pc.p2_parts.head) == _standard(2, &"head"), "P2 head is the standard color offline")
	_check(not pc.p2_parts.is_empty() and _albedo(pc.p2_parts.upper_torso) == _standard(2, &"chest"), "P2 chest is the standard color offline")
	_check(not pc.p2_parts.is_empty() and _albedo(pc.p2_parts.l_thigh) == _standard(2, &"l_leg"), "P2 leg is the standard color offline")

	# ヘリ降下・のこぎり・壁衝突のラグドールはすべて _setup_ragdoll で作られる。ゲーム中の骨格から作って色を見る。
	for player_index: int in [1, 2]:
		var rag: Dictionary = pc._setup_ragdoll(pc.p1_parts if player_index == 1 else pc.p2_parts, player_index == 1)
		await _frames(2)
		await _capture("ragdoll_p%d" % player_index)
		var rag_colors := {}
		for node: Node in (rag.container as Node).find_children("*", "MeshInstance3D", true, false):
			var color := _albedo(node)
			if color.a > 0.0:
				rag_colors[color.to_html(false)] = true
		print("SKIN_GAMEPLAY ragdoll p%d colors: " % player_index, rag_colors.keys())
		_check(rag_colors.has(_standard(player_index, &"chest").to_html(false)) and not _has_custom(rag_colors), "P%d ragdoll uses the standard colors offline" % player_index)
		pc._teardown_ragdoll(rag)
		pc.call("_set_parts_visible", pc.p1_parts if player_index == 1 else pc.p2_parts, true)
	await _frames(2)

	# 壁での死亡（P1）。破片が同じ色か。
	world.set_process(false)
	gs.game_state = Constants.STATE_PLAYING
	gs.world_scroll_z = gs.wall_z - 10.0
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z
	world._update_walls()
	world._update_player(0.0)
	world._update_camera(0.0)
	gs._set_player_hp(1, 1)
	gs._apply_hp_wall_damage(1)
	var colors_seen := {}
	for frame: int in range(120):
		await get_tree().physics_frame
		gs.game_over_timer += 1.0 / 60.0
		world._update_player(1.0 / 60.0)
		world._update_camera(1.0 / 60.0)
		if frame == 20 or frame == 60:
			await _capture("p1_wall_death_%d" % frame)
		if frame == 20:
			colors_seen = _collect_debris_colors(pc)
			if colors_seen.is_empty():
				# 物理ラグドールで倒れる演出のときは、ラグドールの体の色を見る
				colors_seen = _collect_ragdoll_colors(world)
	print("SKIN_GAMEPLAY death colors: ", colors_seen.keys())
	_check(not colors_seen.is_empty() and not _has_custom(colors_seen), "P1 death pieces use the standard colors offline")
	print("SKIN_GAMEPLAY ", JSON.stringify({"passed": _failures.is_empty(), "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _albedo(node: Variant) -> Color:
	var mesh := node as MeshInstance3D
	if mesh == null or not mesh.material_override is StandardMaterial3D:
		return Color.TRANSPARENT
	return PlayerSkin.quantize((mesh.material_override as StandardMaterial3D).albedo_color)


func _check_ragdoll_colors(world: Node) -> bool:
	var colors := _collect_ragdoll_colors(world)
	if colors.is_empty():
		return false
	_check(not _has_custom(colors), "arrival ragdoll uses the standard colors offline %s" % [colors.keys()])
	return true


func _standard(slot: int, part_id: StringName) -> Color:
	return PlayerSkin.quantize(PlayerSkin.part_color(PlayerSkin.default_skin(slot), part_id))


## 試合前に入れておいたカスタムの色が1つでも見えたら true。
func _has_custom(colors: Dictionary) -> bool:
	for color: Color in [P1_CHEST, P1_REST, P2_CHEST, P2_REST]:
		if colors.has(color.to_html(false)):
			return true
	return false


func _collect_ragdoll_colors(world: Node) -> Dictionary:
	var colors := {}
	for container_name: String in ["RagdollLimbsP1", "RagdollLimbsP2"]:
		var container := world.find_child(container_name, true, false)
		if container == null:
			continue
		for node: Node in container.find_children("*", "MeshInstance3D", true, false):
			var color := _albedo(node)
			if color.a > 0.0:
				colors[color.to_html(false)] = true
	return colors


func _collect_debris_colors(pc: PlayerController) -> Dictionary:
	var colors := {}
	for body: RigidBody3D in pc._p1_explosion_bodies:
		if not is_instance_valid(body):
			continue
		for node: Node in body.get_children():
			var color := _albedo(node)
			if color.a > 0.0:
				colors[color.to_html(false)] = true
	return colors


func _frames(count: int) -> void:
	for index: int in range(count):
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + file_name + ".png"))

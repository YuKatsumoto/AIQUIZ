extends Node

## サドンデスへ行くときの幽霊の復活（docs/sudden_death_v2/ghost_revive.md）。実際の GameWorld で、脱落した人が幽霊のまま
## 引き分けにし（GameWorld._debug_force_draw_finish の ghost_mask）、分岐 → 復活 → 種目発表 → 乗り込みの頭までを 1 フレームずつ進める。
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/sudden_death_v2/ghost_revive_runtime_bootstrap.gd -- case=p1
## case：p1（P1 が幽霊）/ p2（P2 が幽霊）/ both（2 人とも幽霊）/ none（2 人とも生きている。復活の場面がないこと）
## every=N：復活の間は N フレームごとに画を撮る（既定 6）。0 で撮らない。
## 出力：artifacts/sudden_death_v2/ghost_revive/<case>/（画と report.json）。

const OUT_ROOT := "res://artifacts/sudden_death_v2/ghost_revive/"
const FRAME_LIMIT := 60 * 40

var case_name := "p1"
var every := 6
var out := OUT_ROOT
var gs: QuizGameState
var world: Node
var director: HeliSuddenDeathDirector
var players: PlayerController
var report := {"failures": [], "acts": [], "shots": [], "checks": {}, "samples": []}
var _frame := 0
var _last_act := ""
var _pending_shots: Array = []
var _board_at := -1
var _starts_seen := {}
var _lens_from := {}
var _lens_drift := 0.0
var _lens_turn := 0.0
var _lens_fov := 0.0
var _captions := 0


func _ready() -> void:
	call_deferred("run")


func fail(label: String) -> void:
	(report.failures as Array).append(label)
	push_error(label)


func ghost_mask() -> int:
	match case_name:
		"p1":
			return 1
		"p2":
			return 2
		"both":
			return 3
	return 0


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("case="):
			case_name = arg.trim_prefix("case=")
		elif arg.begins_with("every="):
			every = int(arg.trim_prefix("every="))
	out = OUT_ROOT + case_name + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	report["case"] = case_name
	GameManager.graphics_quality = "balanced"
	get_tree().root.size = Vector2i(1280, 720)
	var helper: Node = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture()
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	players = world.get_node("Player") as PlayerController
	players.prepare_for_loading(gs)
	director = world.get("_sudden_death_director") as HeliSuddenDeathDirector
	director.use_real_time = false
	await _frames(60)
	world.call("_clear_preview_walls")
	gs.current_index = 10
	gs.current_wall_index = 10
	gs.load_current_quiz()
	gs.world_scroll_z = gs.goal_z - 24.0
	gs.player_z = gs.goal_z - 10.0
	gs.player2_z = gs.goal_z - 10.0
	await _frames(15)
	world.call("_debug_force_draw_finish", ghost_mask())
	var guard := 0
	while not gs.result_presentation_active and guard < 600:
		guard += 1
		await get_tree().process_frame
	report.checks["ghost_mask"] = gs.result_ghost_mask
	report.checks["pending"] = gs.sudden_death_pending
	if gs.result_ghost_mask != ghost_mask():
		fail("the draw has ghosts %d, expected %d" % [gs.result_ghost_mask, ghost_mask()])
	if not gs.sudden_death_pending:
		fail("the draw did not branch into the sudden death")
		_finish()
		return
	while _frame < FRAME_LIMIT:
		_frame += 1
		await get_tree().process_frame
		_watch()
		await _flush_shots()
		if _board_at > 0 and _frame - _board_at > 150:
			break
	_check_end()
	_finish()


func _watch() -> void:
	var act := director.act_name()
	if act != _last_act:
		(report.acts as Array).append([act, _frame, snappedf(gs.result_ceremony_elapsed, 0.01)])
		_on_act(act)
		_last_act = act
	var elapsed := gs.result_ceremony_elapsed
	var revive: Object = director.call("revival") if director.has_method("revival") else null
	var showing := act == "REVIVE" or (act == "BRANCH" and elapsed >= 7.5) or (act == "BOARD" and director.act_time() < 2.0)
	if every > 0 and showing and _frame % every == 0:
		_pending_shots.append([_frame, "%05d_%s_%05.2f" % [_frame, act.to_lower(), director.act_time()]])
	if act == "REVIVE" and _frame % 3 == 0:
		var row := {"frame": _frame, "t": snappedf(director.act_time(), 0.01), "shot": director.shot_name()}
		if revive != null:
			row["revival"] = revive.call("get_debug_snapshot")
			for name: Variant in (row.revival as Dictionary).get("starts_on_screen", []):
				_starts_seen[str(name)] = true
		(report.samples as Array).append(row)
	if act == "REVIVE":
		_watch_lens()


## The lens holds the finale shot through the revival (user's request: no push in) and no caption shows.
func _watch_lens() -> void:
	var camera := director.main_camera()
	if camera == null:
		return
	if _lens_from.is_empty():
		_lens_from = {"xf": camera.global_transform, "fov": camera.fov}
	var xf: Transform3D = _lens_from.xf
	_lens_drift = maxf(_lens_drift, camera.global_position.distance_to(xf.origin))
	_lens_turn = maxf(_lens_turn, rad_to_deg(camera.global_basis.get_rotation_quaternion().angle_to(xf.basis.get_rotation_quaternion())))
	_lens_fov = maxf(_lens_fov, absf(camera.fov - float(_lens_from.fov)))
	var hud := director.hud()
	var callouts: Variant = hud.get("_callouts") if hud != null else []
	if callouts is Array and not (callouts as Array).is_empty():
		_captions = maxi(_captions, (callouts as Array).size())


func _on_act(act: String) -> void:
	var looks := {}
	for player: int in [1, 2]:
		looks[player] = {"avatar_ghost": _ghost_parts(players.p1_parts if player == 1 else players.p2_parts),
			"cast_ghost": _cast_ghost(player)}
	report.checks["looks_at_%s" % act.to_lower()] = looks
	if act == "BOARD":
		_board_at = _frame
		_pending_shots.append([_frame + 30, "board_after_0.5s"])
		for player: int in [1, 2]:
			var puppet := director.puppet(player)
			if puppet != null and not puppet.is_visible():
				fail("P%d is not shown when the boarding starts" % player)
			if int(looks[player].avatar_ghost) > 0:
				fail("P%d still looks like a ghost when the boarding starts (%d ghost parts)" % [player, int(looks[player].avatar_ghost)])


## How many meshes under the parts still wear the ghost soul shader.
func _ghost_parts(parts: Dictionary) -> int:
	var count := 0
	var seen := {}
	for key: Variant in parts:
		if not (parts[key] is Node3D):
			continue
		var node := parts[key] as Node3D
		for mesh: Node in [node] + node.find_children("*", "MeshInstance3D", true, false):
			if mesh is MeshInstance3D and not seen.has(mesh) and (mesh as MeshInstance3D).is_visible_in_tree():
				seen[mesh] = true
				if PlayerController.is_ghost_soul_look(mesh as MeshInstance3D):
					count += 1
	return count


func _cast_ghost(player: int) -> int:
	var ceremony := world.get("_result_ceremony_director") as ResultCeremonyDirector
	var stage := ceremony.stage() if ceremony != null else null
	if stage == null or not stage.is_built():
		return -1
	return _ghost_parts(stage.actor_parts(player))


func _check_end() -> void:
	var names: Array[String] = []
	for row: Array in report.acts:
		names.append(String(row[0]))
	report.checks["acts"] = names
	if _board_at < 0:
		fail("the boarding did not start (acts %s)" % str(names))
	var revived := names.has("REVIVE")
	if ghost_mask() != 0 and not revived:
		fail("no revival for the ghost (acts %s)" % str(names))
	if ghost_mask() == 0 and revived:
		fail("a revival ran without a ghost")
	if not revived:
		return
	report.checks["lens"] = {"drift_m": snappedf(_lens_drift, 0.001), "turn_deg": snappedf(_lens_turn, 0.01), "fov_deg": snappedf(_lens_fov, 0.01)}
	report.checks["captions"] = _captions
	report.checks["starts_on_screen"] = _starts_seen.keys()
	# The shake on the burst and the landing moves the lens a few centimetres; it never pushes in or turns.
	if _lens_drift > 0.12 or _lens_turn > 0.05 or _lens_fov > 0.01:
		fail("the lens moved during the revival (%.3f m, %.2f deg, fov %.2f)" % [_lens_drift, _lens_turn, _lens_fov])
	if _captions > 0:
		fail("a caption showed during the revival")
	if not _starts_seen.is_empty():
		fail("parts started inside the picture: %s" % str(_starts_seen.keys()))
	for player: int in [1, 2]:
		if (ghost_mask() & (1 if player == 1 else 2)) != 0 and not gs.is_sudden_death_revived(player):
			fail("P%d was not marked revived" % player)


func _flush_shots() -> void:
	var keep: Array = []
	for row: Array in _pending_shots:
		if _frame >= int(row[0]):
			await RenderingServer.frame_post_draw
			var path := out + String(row[1]) + ".jpg"
			get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path(path), 0.88)
			(report.shots as Array).append(path)
		else:
			keep.append(row)
	_pending_shots = keep


func _finish() -> void:
	report["frames"] = _frame
	report["director"] = director.get_debug_snapshot() if director != null else {}
	var f := FileAccess.open(out + "report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("GHOST_REVIVE_RUNTIME ", JSON.stringify({"case": case_name, "failures": report.failures, "acts": report.checks.get("acts", []),
		"frames": _frame}))
	get_tree().quit(0 if (report.failures as Array).is_empty() else 1)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

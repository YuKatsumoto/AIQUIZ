extends Node

## スカイゲートのボード（SkyGateBoard / SkyGateEffects）の確認。Godot の実画面で撮り、描く回数・粒の数・計算の時間を測る。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://assets/sudden_death/sky_gate/check/gate_board_check_bootstrap.gd -- low
## 引数は画質（low / balanced / high / ultra。既定 low）。画は source/previews/godot_*_<画質>.png、
## 数は source/godot_check_<画質>.json に書く。

const OUT_DIR := "res://assets/sudden_death/sky_gate/source/previews/"
const REPORT := "res://assets/sudden_death/sky_gate/source/godot_check_%s.json"
const STEP := 1.0 / 60.0

var quality := "low"
var board: SkyGateBoard
var camera: Camera3D
var sun: DirectionalLight3D
var dolls: Array[Dictionary] = []
var doll_roots: Array[Node3D] = []
var report := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		quality = args[0]
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	world.name = "CheckWorld"
	add_child(world)
	_make_environment(world)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 2000.0
	world.add_child(camera)
	camera.make_current()
	board = SkyGateBoard.new()
	board.name = "Gate_1"
	world.add_child(board)
	var ok := board.build(quality)
	report["quality"] = quality
	report["build_ok"] = ok
	board.set_question("8 + 7 = ?", ["13", "15", "16", "14"])
	for player in [1, 2]:
		var r := Node3D.new()
		r.name = "Doll_%d" % player
		world.add_child(r)
		var parts := EmoteBlockmanPreview.build_player_skeleton(player == 1, r, HatData.HAT_NONE, 0, {})
		_skydive_pose(parts)
		dolls.append(parts)
		doll_roots.append(r)
	_place_dolls()
	await _frames(20)

	# 描く回数：ボードなし → ボードだけ
	board.visible = false
	for r in doll_roots:
		r.visible = false
	await _frames(4)
	board.visible = true
	_look(Vector3(0.0, 15.5, 13.0), Vector3(0.0, 0.0, -0.4))
	await _settle(0.5)
	report["draw_calls_board_idle"] = await _board_draws()
	report["primitives_board_idle"] = await _board_prims()

	# 1. ボード（見下ろし）
	for r in doll_roots:
		r.visible = true
	_look(Vector3(0.0, 15.5, 13.0), Vector3(0.0, 0.0, -0.4))
	await _settle(0.4)
	await _shot("godot_01_board")

	# 2. 光る枠：P1 は 15、P2 は 14。もう 1 枚は 2 人とも 13
	board.set_highlight(1, 1, true)
	board.set_highlight(3, 2, true)
	await _settle(0.3)
	report["draw_calls_highlight_2"] = await _board_draws()
	await _shot("godot_02_highlight")
	board.set_highlight(1, 1, false)
	board.set_highlight(3, 2, false)
	board.set_highlight(0, 1, true)
	board.set_highlight(0, 2, true)
	await _settle(0.3)
	_look(Vector3(-3.3, 7.5, 4.6), Vector3(-3.3, 0.0, -0.6))
	await _settle(0.05)
	await _shot("godot_03_highlight_both")
	board.reset()

	# 3. 正解：15（パネル 1）をつき破る。P1 の人形が通る
	_look(Vector3(4.6, 8.0, 6.2), Vector3(3.3, -0.6, -0.6))
	doll_roots[1].visible = false
	board.burst(1, board.panel_center(1) + Vector3(0.6, 0.0, 0.2))
	var t := 0.0
	for target: float in [0.08, 0.3, 0.75]:
		t = await _advance_to(t, target)
		_drop_doll(0, t, 1)
		await _shot("godot_04_burst_%03d" % int(target * 100.0))
	await _settle(1.6)
	_look(Vector3(1.0, -9.5, 7.0), Vector3(1.5, 0.0, -0.8))
	await _settle(0.05)
	await _shot("godot_05_burst_below")
	board.reset()
	_place_dolls()

	# 4. まちがい：13（パネル 0）がドカン。P2 の人形がブロックにばらける
	doll_roots[1].visible = true
	_look(Vector3(-1.5, 10.5, 8.5), Vector3(-3.0, 0.0, -0.8))
	var at := board.panel_center(0) + Vector3(0.0, 0.8, 0.0)
	doll_roots[1].global_position = at
	doll_roots[0].visible = false
	board.boom(0)
	board.effects.player_burst(dolls[1], at)
	t = 0.0
	for target: float in [0.06, 0.22, 0.5, 1.0]:
		t = await _advance_to(t, target)
		await _shot("godot_06_boom_%03d" % int(target * 100.0))
		if is_equal_approx(target, 0.22):
			report["draw_calls_boom_and_blocks"] = await _board_draws()
	board.reset()
	(dolls[1]["pelvis"] as Node3D).visible = true

	# 5. ブロックにばらける（近く）
	_place_dolls()
	doll_roots[0].visible = true
	var p1_at := doll_roots[0].global_position
	_look(p1_at + Vector3(2.4, 4.2, 4.0), p1_at + Vector3(0.0, -0.2, 0.0))
	await _settle(0.1)
	await _shot("godot_07_doll_before")
	board.effects.player_burst(dolls[0], p1_at)
	t = 0.0
	for target: float in [0.12, 0.45, 0.9]:
		t = await _advance_to(t, target)
		await _shot("godot_08_blocks_%03d" % int(target * 100.0))
	report["blocks_from_doll"] = board.effects.live_counts()
	board.reset()
	(dolls[0]["pelvis"] as Node3D).visible = true

	# 6. ドローン（近く）
	var drone := board.find_child("Drone_1", true, false) as Node3D
	var dp := drone.global_position
	_look(dp + Vector3(-2.6, 1.6, 3.4), dp + Vector3(-0.2, -0.5, 0.0))
	await _settle(0.2)
	await _shot("godot_09_drone")

	# 7. 遠く（はるか下のボード、文字と小さい部品の描く距離）
	_place_dolls()
	_look(Vector3(0.0, 70.0, 30.0), Vector3(0.0, 0.0, 0.0))
	await _settle(0.1)
	await _shot("godot_10_far")
	report["draw_calls_far_70m"] = await _board_draws()

	# 8. 穴の位置：パネル 3 の手前の左に開ける（人形の真下に穴が来ること）
	board.reset()
	var off_at := board.panel_center(3) + Vector3(-2.0, 0.0, 0.9)
	doll_roots[1].visible = false
	var lie := Basis(Vector3.BACK, PI) * Basis(Vector3.RIGHT, -PI / 2.0)
	doll_roots[0].global_transform = Transform3D(lie, off_at + Vector3(0.0, 2.0, 0.0) - lie * Vector3(0.0, 1.0, 0.0))
	board.burst(3, off_at)
	_look(off_at + Vector3(0.0, 9.0, 0.01), off_at)
	t = 0.0
	t = await _advance_to(t, 0.6)
	await _shot("godot_11_hole_offset")
	var hole_uv: Vector2 = board._paper[3].get_shader_parameter("hole_center")
	report["hole_offset_uv"] = [hole_uv.x, hole_uv.y]

	# 一番重いとき：2 人とも同じゲートで、正解とまちがいと人形が同時
	_look(Vector3(0.0, 15.5, 13.0), Vector3(0.0, 0.0, -0.4))
	board.reset()
	board.set_highlight(1, 1, true)
	board.set_highlight(0, 2, true)
	_place_dolls()
	board.burst(1)
	board.boom(0)
	board.effects.player_burst(dolls[1], board.panel_center(0) + Vector3(0.0, 0.8, 0.0))
	var usec := 0
	var frames := 0
	var max_counts := {}
	var max_total := 0
	t = 0.0
	while t < 2.2:
		var t0 := Time.get_ticks_usec()
		board.advance(STEP)
		usec += Time.get_ticks_usec() - t0
		frames += 1
		t += STEP
		await get_tree().process_frame
		if frames == 9:
			report["peak_draw_calls_board"] = await _board_draws()
		var counts := board.effects.live_counts()
		var total := 0
		for k: String in counts:
			total += int(counts[k])
		if total > max_total:
			max_total = total
			max_counts = counts
	report["peak_particles"] = max_total
	report["peak_particles_by_kind"] = max_counts
	report["advance_usec_avg"] = float(usec) / float(frames)
	report["particle_amounts"] = {
		"burst_confetti": board.effects.amount(SkyGateEffects.BURST_CONFETTI),
		"boom_puffs": board.effects.amount(SkyGateEffects.BOOM_PUFFS),
		"boom_stars": board.effects.amount(SkyGateEffects.BOOM_STARS),
		"boom_shreds": board.effects.amount(SkyGateEffects.BOOM_SHREDS),
		"player_puffs": board.effects.amount(SkyGateEffects.PLAYER_PUFFS),
		"player_stars": board.effects.amount(SkyGateEffects.PLAYER_STARS),
	}
	report["fps_independence_max_diff"] = _fps_check()
	report["fps"] = Engine.get_frames_per_second()
	var f := FileAccess.open(REPORT % quality, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[GateBoardCheck] ", JSON.stringify(report))
	get_tree().quit()


## 30／60／120fps で同じ時刻まで進めて、粒の位置の差の最大（m）を見る。
func _fps_check() -> float:
	var results: Array[PackedFloat32Array] = []
	for fps: float in [30.0, 60.0, 120.0]:
		var fx := SkyGateEffects.new()
		add_child(fx)
		fx.build(quality)
		fx.burst_fx(Vector3.ZERO, Color("#8CCDF5"))
		fx.boom_fx(Vector3(3.0, 0.0, 0.0), Color("#8FE3B5"))
		var steps := int(round(0.9 * fps))
		for i in range(steps):
			fx.advance(1.0 / fps)
		var live := PackedFloat32Array()
		for kind in range(SkyGateEffects.KIND_COUNT):
			var o: int = fx._offsets[kind]
			live.append(float(fx._counts[kind]))
			live.append_array(fx._buf.slice(o, o + fx._counts[kind] * SkyGateEffects.STRIDE))
		results.append(live)
		fx.queue_free()
	if results[0].size() != results[1].size() or results[2].size() != results[1].size():
		return INF
	var worst := 0.0
	for i in range(results[0].size()):
		worst = maxf(worst, maxf(absf(results[0][i] - results[1][i]), absf(results[2][i] - results[1][i])))
	return worst


func _advance_to(t: float, target: float) -> float:
	while t < target - 0.0001:
		board.advance(STEP)
		t += STEP
	await _frames(2)
	return t


func _settle(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		board.advance(STEP)
		t += STEP
		await get_tree().process_frame
	await _frames(2)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + shot_name + "_" + quality + ".png")


## ボード（と子の効果）だけの描く回数：見せたときと隠したときの差。
func _board_draws() -> int:
	await _frames(2)
	var with_board := _draws()
	board.visible = false
	await _frames(2)
	var without := _draws()
	board.visible = true
	await _frames(1)
	return with_board - without


func _board_prims() -> int:
	await _frames(2)
	var with_board := _prims()
	board.visible = false
	await _frames(2)
	var without := _prims()
	board.visible = true
	await _frames(1)
	return with_board - without


func _draws() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


func _prims() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)


func _look(eye: Vector3, target: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(target, Vector3.UP if absf((target - eye).normalized().y) < 0.99 else Vector3.FORWARD)


func _make_environment(world: Node3D) -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.42, 0.86)
	sky_mat.sky_horizon_color = Color(0.62, 0.8, 0.98)
	sky_mat.ground_horizon_color = Color(0.5, 0.7, 0.92)
	sky_mat.ground_bottom_color = Color(0.1, 0.32, 0.62)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = quality != "low"
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = quality != "low"
	world.add_child(sun)
	# 本物の空のセット（海は 70m 下、雲は 30m 下と 25m 上）
	var sky_set := SuddenDeathSkySet.new()
	world.add_child(sky_set)
	sky_set.build(quality, sun.global_transform.basis.z)


## 腹ばいで手足を広げる（頭を奥へ、背中を上へ）。
func _skydive_pose(parts: Dictionary) -> void:
	(parts["l_shoulder"] as Node3D).rotation = Vector3(0.0, 0.0, deg_to_rad(-100.0))
	(parts["r_shoulder"] as Node3D).rotation = Vector3(0.0, 0.0, deg_to_rad(100.0))
	(parts["l_elbow"] as Node3D).rotation = Vector3(0.0, 0.0, deg_to_rad(35.0))
	(parts["r_elbow"] as Node3D).rotation = Vector3(0.0, 0.0, deg_to_rad(-35.0))
	(parts["l_hip"] as Node3D).rotation = Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(-18.0))
	(parts["r_hip"] as Node3D).rotation = Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(18.0))
	(parts["l_knee"] as Node3D).rotation = Vector3(deg_to_rad(40.0), 0.0, 0.0)
	(parts["r_knee"] as Node3D).rotation = Vector3(deg_to_rad(40.0), 0.0, 0.0)


func _place_dolls() -> void:
	var lie := Basis(Vector3.BACK, PI) * Basis(Vector3.RIGHT, -PI / 2.0)
	var spots: Array[Vector3] = [board.panel_center(1) + Vector3(0.0, 3.2, 0.6), board.panel_center(3) + Vector3(-0.4, 4.0, 0.4)]
	for i in range(doll_roots.size()):
		doll_roots[i].global_transform = Transform3D(lie, spots[i] - lie * Vector3(0.0, 1.0, 0.0))
		doll_roots[i].visible = true
		(dolls[i]["pelvis"] as Node3D).visible = true


## 正解のパネルを通りぬける人形（t 秒で上から下へ）。
func _drop_doll(index: int, t: float, panel: int) -> void:
	var lie := Basis(Vector3.BACK, PI) * Basis(Vector3.RIGHT, -PI / 2.0)
	var c := board.panel_center(panel) + Vector3(0.6, 0.0, 0.2)
	var y := lerpf(1.2, -3.5, clampf(t / 0.75, 0.0, 1.0))
	doll_roots[index].global_transform = Transform3D(lie, c + Vector3(0.0, y, 0.0) - lie * Vector3(0.0, 1.0, 0.0))
	doll_roots[index].visible = true

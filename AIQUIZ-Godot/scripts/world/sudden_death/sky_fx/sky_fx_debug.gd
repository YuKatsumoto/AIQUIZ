extends Node3D

## スカイゲートの空の演出（SkyFallScenery・SkyFallScarf）のデバッグの入口。監督なしで、本戦の見下ろしの画を出す。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://scripts/world/sudden_death/sky_fx/sky_fx_debug_bootstrap.gd -- low
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://scripts/world/sudden_death/sky_fx/sky_fx_debug_bootstrap.gd -- low shots
## 引数：画質（low / balanced / high / ultra。既定 low）、shots（決まった高さの画を撮って数を測り、終わる）。
## 操作（shots なし）：←→ 進み（押し続けで動く）・下のつまみ・Space 自動で落ちる／止める・1〜4 高さへ飛ぶ・
##   W 風の強さ（自動→0→0.5→1.0→1.4）・O 延長戦・C カメラ（見下ろし／マフラーの寄り／高い所／着地台の高さの横）・H 文字を消す。
## 中身：空のセット（SuddenDeathSkySet の海）・着地台（LandingFloat）・問題のボード（SkyGateBoard、W5）・
##   人形 2 人（腹ばい、DropMotion があればその姿）にマフラーと風の筋。海の深さは SkyFallScenery.sea_depth(p)。
## ボードはゲート 8 秒（ROUND 1）で 320 m 下から上がってくる（進み 1 で 4 枚目を通る）。風はゲートの後半 0.5、通過で 1.4。

const StageAtmosphereScript = preload("res://scripts/world/stage_atmosphere.gd")
const OUT_DIR := "res://assets/sudden_death/sky_fx/source/previews/"
const REPORT := "res://assets/sudden_death/sky_fx/source/godot_check_%s.json"
const SKY_ORIGIN := Vector3(0.0, 140.0, -1800.0)
const FALL := SKY_ORIGIN + Vector3(0.0, -26.0, 0.0)
const SIDE_X := 1.7
const ROUND_TIME := 32.0
const FALL_SPEED := 40.0
const GATE_TIME := 8.0
const GATE_DEPTH := 320.0
const STEP := 1.0 / 60.0
const WIND_MODES := [-1.0, 0.0, 0.5, 1.0, 1.4]

var quality := "low"
var shots := false
var camera: Camera3D
var sun: DirectionalLight3D
var weather: WeatherCycle
var venue_env: Environment
var sky_set: SuddenDeathSkySet
var scenery: SkyFallScenery
var landing: LandingFloat
var board: SkyGateBoard
var dolls: Array[Dictionary] = []
var scarves: Array[SkyFallScarf] = []
var progress := 0.0
var auto_fall := false
var wind_mode := 0
var cam_mode := 0
var report := {}
var _gate := -1
var _pass_at := -INF
var _clock := 0.0
var _hud: CanvasLayer
var _label: Label
var _slider: HSlider
var _hold := 0.0
var _move := Vector2.ZERO


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "shots":
			shots = true
		elif a in GraphicsQuality.VALID_QUALITIES:
			quality = a
	_build()
	if shots:
		_run_shots.call_deferred()
	else:
		_build_hud()
		auto_fall = true


# ------------------------------------------------------------------ 組み立て

func _build() -> void:
	_make_environment()
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.1
	camera.far = 5000.0
	add_child(camera)
	camera.make_current()
	camera.environment = venue_env
	sky_set = SuddenDeathSkySet.new()
	add_child(sky_set)
	sky_set.position = SKY_ORIGIN
	sky_set.build(quality, sun.global_basis.z)
	# 空のセットの巡航の雲（StagingClouds）は本戦では使わない（雲は SkyFallScenery の体積雲）
	if sky_set.clouds != null:
		sky_set.clouds.visible = false
	# 海はステージの太陽で光る（天気の周期が海の材質へ太陽を渡す。ステージの _link_ocean_to_weather と同じ）
	weather.ocean_material = sky_set.ocean.material_override as ShaderMaterial
	weather.refresh_ocean_sun()
	landing = LandingFloat.new()
	add_child(landing)
	landing.build()
	scenery = SkyFallScenery.new()
	scenery.name = "SkyFallScenery"
	add_child(scenery)
	scenery.global_position = FALL
	scenery.build(quality, _landing_point(0.0), Vector3.FORWARD)
	scenery.set_camera(camera)
	scenery.configure_sea(sky_set.ocean, sun)
	scenery.set_sun(sun)
	board = SkyGateBoard.new()
	board.name = "Gate"
	add_child(board)
	board.build(quality)
	board.set_question("8 + 7 = ?", ["13", "15", "16", "14"])
	for player in [1, 2]:
		var root := Node3D.new()
		root.name = "P%dDoll" % player
		add_child(root)
		var parts := EmoteBlockmanPreview.build_player_skeleton(player == 1, root, HatData.HAT_NONE, 0, {})
		parts["root"] = root
		dolls.append(parts)
		var scarf := SkyFallScarf.new()
		scarf.name = "P%dScarf" % player
		add_child(scarf)
		scarf.auto_advance = false
		scarves.append(scarf)
	_pose_dolls(0.0)
	for i in range(2):
		scarves[i].attach_doll(dolls[i], i + 1)
		scenery.track_body(i + 1, dolls[i])
	_apply(0.0, 0.0)


## ステージと同じ空・光・トーンマップ（StageEnvironment._setup_environment と _setup_lighting と同じ設定）。
## 太陽はステージの天気の周期（WeatherCycle、昼で止めてある）が向ける。海と雲にも同じ太陽を渡す。
func _make_environment() -> void:
	var env := Environment.new()
	StageEnvironment.configure_stage_environment(env)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.8
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.8
	env.set_glow_level(0, true)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, false)
	GraphicsQuality.apply_environment(env, quality)
	StageAtmosphereScript.apply_environment_quality(env, quality)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation_degrees = Vector3(-50, -20, 0)
	sun.light_color = Color(0.90, 0.92, 0.95)
	sun.light_energy = 1.2
	GraphicsQuality.configure_directional_shadow(sun, quality)
	sun.shadow_enabled = GraphicsQuality.gameplay_shadow_enabled(quality)
	add_child(sun)
	weather = StageEnvironment.attach_weather_cycle(self, env, sun)
	# 本戦の画はカメラに見せ方の環境を当てる（監督と同じ。ステージの WorldEnvironment は天気の周期が動かすまま）
	venue_env = SkyFallScenery.venue_environment(quality)


func _landing_point(p: float) -> Vector3:
	return Vector3(FALL.x, FALL.y - SkyFallScenery.sea_depth(p, scenery != null and scenery.overtime), FALL.z)


## 人形を腹ばいに（頭を画面の上＝−Z、背中を上）。P1 は画面の左（−X）。
func _pose_dolls(t: float) -> void:
	for i in range(dolls.size()):
		var parts := dolls[i]
		var center := FALL + Vector3(SIDE_X * (-1.0 if i == 0 else 1.0), sin(t * 1.3 + i) * 0.12, cos(t * 0.9 + i * 2.0) * 0.1)
		var pelvis := parts.pelvis as Node3D
		var move := _move if i == 0 else Vector2(sin(t * 0.5) * 0.4, 0.0)
		if DropMotion.has_assets() and DropMotion.pose_box(parts, move, t + i * 0.37):
			pelvis.global_transform = Transform3D(Basis(Vector3.UP, PI) * pelvis.basis, center)
		else:
			_fallback_box(parts)
			var lie := Basis(Vector3.RIGHT, -PI * 0.5)
			pelvis.global_transform = Transform3D(lie, center)


func _fallback_box(parts: Dictionary) -> void:
	var table := {"l_shoulder": Vector3(0, 0, -82), "r_shoulder": Vector3(0, 0, 82), "l_elbow": Vector3(0, 0, -78), "r_elbow": Vector3(0, 0, 78),
		"l_hip": Vector3(10, 0, -16), "r_hip": Vector3(10, 0, 16), "l_knee": Vector3(58, 0, 0), "r_knee": Vector3(58, 0, 0),
		"head_pivot": Vector3(-64, 0, 0), "spine": Vector3(-16, 0, 0)}
	for key: String in table:
		var node := parts.get(key) as Node3D
		if node != null:
			var d: Vector3 = table[key]
			node.rotation = Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z))


# ------------------------------------------------------------------ 1 フレーム

## 進み p へ。落ちた分 fall（m）だけ流し、delta だけ時計を進める。
func _apply(fall: float, delta: float) -> void:
	_clock += delta
	scenery.set_progress(progress)
	var overtime := scenery.overtime
	var lp := _landing_point(progress)
	scenery.set_landing_point(lp)
	if sky_set.ocean != null:
		sky_set.ocean.position.y = lp.y - sky_set.global_position.y
	landing.float_at(lp, lp.y, delta)
	# ボード：ゲートの頭で 320 m 下、通過で 2 人の高さ
	var gates := progress * 4.0 if not overtime else fposmod(_clock / GATE_TIME, 1.0)
	var index := mini(int(floorf(gates)), 3) if not overtime else int(floorf(_clock / GATE_TIME))
	var u := gates - floorf(gates) if progress < 1.0 or overtime else 1.0
	if index != _gate:
		if _gate >= 0:
			_pass_at = _clock
		_gate = index
		board.reset()
		board.global_position = FALL + Vector3(0.0, -GATE_DEPTH, 0.0)
		scenery.gate_emerge(board)
	board.global_position = FALL + Vector3(0.0, -GATE_DEPTH * (1.0 - u) - 2.5, 0.0)
	board.visible = u < 0.995
	board.advance(delta)
	# 風：ゲートの後半は弱く、通過の瞬間に一度強く（ゆっくり戻る）
	var w := 1.0 if u < 0.5 else 0.5
	var since := _clock - _pass_at
	if since >= 0.0 and since < 0.6:
		w = lerpf(1.4, w, smoothstep(0.0, 0.6, since))
	if WIND_MODES[wind_mode] >= 0.0:
		w = WIND_MODES[wind_mode]
	scenery.set_wind(w)
	_pose_dolls(_clock)
	for s: SkyFallScarf in scarves:
		s.wind = w
		s.advance(delta)
	scenery.advance(fall, delta)
	_place_camera()


func _place_camera() -> void:
	var mid := FALL
	match cam_mode:
		0:  # G2_TopDown：2 人の上 6.5 m・少し後ろから 75° で見下ろす
			_look(mid + Vector3(0.0, 6.5, 1.75), mid + Vector3(0.0, 0.0, 0.0) + Vector3(0.0, -0.966, -0.259) * 4.0, Vector3.FORWARD)
		1:  # マフラーと風の筋の寄り（P1）
			var p := (dolls[0].spine as Node3D).global_position
			_look(p + Vector3(1.4, 2.3, 1.6), p + Vector3(0.0, 0.1, -0.2), Vector3.UP)
		2:  # 高い所から（島の並び）
			_look(mid + Vector3(0.0, 40.0, 14.0), mid + Vector3(0.0, -200.0, -40.0), Vector3.FORWARD)
		3:  # 着地台の高さの横から（海面近くの低い視点。W4 の着地の画と同じ見え方）
			var lp := _landing_point(progress)
			_look(lp + Vector3(22.0, 3.0, 26.0), lp + Vector3(-90.0, -2.0, -30.0), Vector3.UP)


func _look(eye: Vector3, target: Vector3, up: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(target, up)


func _process(delta: float) -> void:
	if shots:
		return
	var step := 0.0
	if Input.is_key_pressed(KEY_RIGHT):
		step += delta * 0.12
	if Input.is_key_pressed(KEY_LEFT):
		step -= delta * 0.12
	_move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), 0.0)
	if auto_fall and step == 0.0:
		step = delta / ROUND_TIME
	var before := progress
	progress = clampf(progress + step, 0.0, 1.0) if not scenery.overtime else fposmod(progress + step, 1.0)
	if not scenery.overtime and progress >= 1.0 and auto_fall:
		progress = 0.0
		_gate = -1
	var fall := maxf(progress - before, 0.0) * ROUND_TIME * FALL_SPEED if not scenery.overtime else FALL_SPEED * delta
	_apply(fall, delta)
	if _slider != null and not _slider.has_focus():
		_slider.set_value_no_signal(progress)
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if shots or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			auto_fall = not auto_fall
		KEY_W:
			wind_mode = (wind_mode + 1) % WIND_MODES.size()
		KEY_O:
			scenery.set_overtime(not scenery.overtime)
		KEY_C:
			cam_mode = (cam_mode + 1) % 4
		KEY_H:
			_hud.visible = not _hud.visible
		KEY_1:
			_jump(0.05)
		KEY_2:
			_jump(0.4)
		KEY_3:
			_jump(0.7)
		KEY_4:
			_jump(0.93)


func _jump(p: float) -> void:
	progress = p
	auto_fall = false


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.001
	_slider.anchor_left = 0.1
	_slider.anchor_right = 0.9
	_slider.anchor_top = 1.0
	_slider.anchor_bottom = 1.0
	_slider.offset_top = -48
	_slider.offset_bottom = -20
	_slider.value_changed.connect(func(v: float) -> void:
		progress = v
		auto_fall = false)
	_hud.add_child(_slider)


func _update_label() -> void:
	if _label == null:
		return
	var st := scenery.stats()
	var wm: float = WIND_MODES[wind_mode]
	_label.text = "進み %.3f  帯 %s%s  風 %.2f（%s）  海まで %.0f m\n描く回数 %d（全体）  fps %d  advance %.2f ms\n←→ 進み  Space 自動%s  1〜4 高さ  W 風  O 延長戦  C カメラ  H 文字" % [
		progress, st.band, "（延長戦）" if scenery.overtime else "", scenery.wind, "自動" if wm < 0.0 else "手動",
		SkyFallScenery.sea_depth(progress, scenery.overtime),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		Engine.get_frames_per_second(), float(st.advance_ms), "（動いている）" if auto_fall else "（止まっている）"]


# ------------------------------------------------------------------ 撮る

func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	report = {"quality": quality, "drop_motion": DropMotion.has_assets(), "shots": {}}
	await _frames(10)
	var plan := [
		# 名前, 進み, 風（-1 は自動）, カメラ, 撮る前に進める秒, 延長戦
		["01_C_cloud_sea", 0.04, -1.0, 0, 1.6, false],
		["02_F_enter", 0.165, -1.0, 0, 0.8, false],
		["03_F_inside", 0.19, -1.0, 0, 0.5, false],
		["04_F_exit", 0.235, -1.0, 0, 0.8, false],
		["05_A_islands", 0.4, 1.0, 0, 1.0, false],
		["06_A_gate_near", 0.68, 0.5, 0, 1.0, false],
		["07_E_near_island", 0.9, -1.0, 0, 1.0, false],
		["08_E_landing", 0.985, -1.0, 0, 0.8, false],
		["09_overtime", 0.5, 1.0, 0, 1.0, true],
		["10_scarf_close", 0.45, 1.0, 1, 1.2, false],
		["11_clouds_high", 0.32, 1.0, 2, 0.6, false],
		["12_cloud_sea_high", 0.05, 1.0, 2, 1.2, false],
		["13_birds", 0.93, -1.0, 0, 0.8, false],
		["14_contrail", 0.03, -1.0, 0, 0.8, false],
		["15_landing_low", 1.0, -1.0, 3, 0.6, false],
	]
	for item: Array in plan:
		var name: String = item[0]
		scenery.set_overtime(bool(item[5]))
		wind_mode = WIND_MODES.find(float(item[2])) if float(item[2]) >= 0.0 else 0
		cam_mode = int(item[3])
		await _goto(float(item[1]), float(item[4]))
		if name == "13_birds":
			scenery.flyers.debug_place(-10.0, 0.5)
			await _run(0.5)
		if name == "14_contrail":
			scenery.flyers.debug_place(0.0, 0.45)
			await _run(0.3)
		await _shot(name)
		report.shots[name] = {"progress": progress, "band": scenery.band_name(), "wind": scenery.wind, "stats": scenery.stats(),
			"draws_total": _draws()}
	scenery.set_overtime(false)
	wind_mode = 0
	cam_mode = 0
	# 描く回数（空の演出だけ）：見せたときと隠したときの差。帯ごと
	var draws := {}
	var gpu := {}
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for pair: Array in [["C", 0.05], ["F", 0.19], ["A", 0.45], ["E", 0.93]]:
		await _goto(float(pair[1]), 0.5)
		draws[pair[0]] = await _scenery_draws()
		gpu[pair[0]] = await _gpu_ms()
	report["draw_calls_sky_fx"] = draws
	report["gpu_ms"] = gpu
	report["draw_calls_scarves"] = await _scarf_draws()
	report["advance_ms_avg"] = await _advance_cost()
	report["counts"] = scenery.stats()
	report["sun_to_sun"] = [snappedf(sun.global_basis.z.x, 0.001), snappedf(sun.global_basis.z.y, 0.001), snappedf(sun.global_basis.z.z, 0.001)]
	report["sun_energy"] = sun.light_energy
	report["fps"] = Engine.get_frames_per_second()
	var f := FileAccess.open(REPORT % quality, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	_contact_sheet(plan)
	print("[SkyFxDebug] ", JSON.stringify({"draws": report.draw_calls_sky_fx, "gpu_ms": report.gpu_ms, "scarves": report.draw_calls_scarves, "advance_ms": report.advance_ms_avg}))
	get_tree().quit()


## 進み p の少し前から seconds 秒かけて p まで落ちる（雲・粒・マフラーが落ち着く）。
func _goto(p: float, seconds: float) -> void:
	var frames := maxi(1, int(seconds / STEP))
	var start := maxf(p - seconds / ROUND_TIME, 0.0)
	if scenery.overtime:
		start = p
	progress = start
	_gate = -1
	_apply(0.0, STEP)
	for i in range(frames):
		var before := progress
		progress = lerpf(start, p, float(i + 1) / frames)
		var fall := (progress - before) * ROUND_TIME * FALL_SPEED if not scenery.overtime else FALL_SPEED * STEP
		_apply(fall, STEP)
		await get_tree().process_frame
	await _frames(2)


func _run(seconds: float) -> void:
	for i in range(int(seconds / STEP)):
		_apply(0.0, STEP)
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "godot_" + shot_name + "_" + quality + ".png")


func _draws() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


func _scenery_draws() -> int:
	await _frames(3)
	var with_fx := _draws()
	scenery.visible = false
	var screen := camera.get_node_or_null("SkyFxScreen") as Node3D
	if screen != null:
		screen.visible = false
	await _frames(3)
	var without := _draws()
	scenery.visible = true
	if screen != null:
		screen.visible = true
	await _frames(2)
	return with_fx - without


## 1 フレームの GPU の時間（ms、30 フレームの平均）：全体と、空の演出を隠したとき。
func _gpu_ms() -> Dictionary:
	var rid := get_viewport().get_viewport_rid()
	var total := 0.0
	for i in range(30):
		await RenderingServer.frame_post_draw
		total += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	scenery.visible = false
	var screen := camera.get_node_or_null("SkyFxScreen") as Node3D
	if screen != null:
		screen.visible = false
	await _frames(3)
	var without := 0.0
	for i in range(30):
		await RenderingServer.frame_post_draw
		without += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	scenery.visible = true
	if screen != null:
		screen.visible = true
	await _frames(2)
	return {"with": snappedf(total / 30.0, 0.01), "without": snappedf(without / 30.0, 0.01)}


func _scarf_draws() -> int:
	await _frames(3)
	var with_fx := _draws()
	for s: SkyFallScarf in scarves:
		s.visible = false
		for child: Node in (dolls[scarves.find(s)].neck as Node3D).get_children():
			if child is MeshInstance3D and String(child.name).begins_with("ScarfRing"):
				(child as MeshInstance3D).visible = false
	await _frames(3)
	var without := _draws()
	for s: SkyFallScarf in scarves:
		s.visible = true
		for child: Node in (dolls[scarves.find(s)].neck as Node3D).get_children():
			if child is MeshInstance3D and String(child.name).begins_with("ScarfRing"):
				(child as MeshInstance3D).visible = true
	await _frames(2)
	return with_fx - without


## advance（空の演出の 1 フレームの計算）の平均（ms）。帯ごとに 60 フレーム。
func _advance_cost() -> Dictionary:
	var out := {}
	for pair: Array in [["C", 0.05], ["F", 0.19], ["A", 0.45], ["E", 0.93]]:
		progress = float(pair[1])
		var total := 0
		for i in range(60):
			var t0 := Time.get_ticks_usec()
			scenery.set_progress(progress)
			scenery.advance(FALL_SPEED * STEP, STEP)
			total += Time.get_ticks_usec() - t0
			await get_tree().process_frame
		out[pair[0]] = snappedf(total / 60.0 / 1000.0, 0.001)
	var t1 := 0
	for i in range(60):
		var t0 := Time.get_ticks_usec()
		for s: SkyFallScarf in scarves:
			s.advance(STEP)
		t1 += Time.get_ticks_usec() - t0
		await get_tree().process_frame
	out["scarves_2"] = snappedf(t1 / 60.0 / 1000.0, 0.001)
	return out


func _contact_sheet(plan: Array) -> void:
	var cols := 4
	var w := 480
	var h := 270
	var rows := int(ceilf(plan.size() / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	for i in range(plan.size()):
		var path := OUT_DIR + "godot_" + String(plan[i][0]) + "_" + quality + ".png"
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			continue
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_jpg(ProjectSettings.globalize_path(OUT_DIR + "godot_contact_%s.jpg" % quality), 0.86)

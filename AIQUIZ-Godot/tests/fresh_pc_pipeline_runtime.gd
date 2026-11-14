extends Node

## 新しい PC で試合中に固まらないことの確認（画面ありで動かす。描画の部品の数は画面がないと増えない）。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/fresh_pc_pipeline_runtime_bootstrap.gd
## 新しい PC では、試合中に初めて描くもの（材質・描き方）ごとに描画の部品（パイプライン）を作り、
## 作り終えるまで画面が止まる（間違えたときの点滅で約 1 秒、サメにかまれたときに約 2 秒）。
## 部品を作った数はこの PC でも数えられるので、本物の試合を準備させたあと、試合中に起きる演出を出して
## 「止まりの元になる部品（canvas・mesh・surface・draw）を 1 つも作らない」ことを確かめる。
##   1. 1P エンドレスを、本物と同じ覆いつきの切り替えで始める（GameWorld._prepare_world_visuals_under_cover）
##   2. 間違えたときの点滅（体が半透明になる）
##   3. 正解の光・水しぶき・爆発の粒子
##   4. サメにかまれる（爆散・爆発の演出・水柱・広がる輪）と、その片付け
## 結果は artifacts/fresh_pc_pipeline/result.json。

const PipelineWatch = preload("res://scripts/core/pipeline_watch.gd")
const OUT := "res://artifacts/fresh_pc_pipeline/"

var _failures: Array[String] = []
var _checks := 0
var _report := {}


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("FRESH_PC_TEST " + message)


func _ready() -> void:
	run.call_deferred()


func _frames(count: int) -> void:
	for _i: int in range(count):
		await PipelineWatch.draw_frame(self)


func _seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## step を動かし、そのあいだに止まりの元になる部品を作ったら失敗にする。
func _expect_no_compile(label: String, step: Callable, settle_seconds: float) -> void:
	var before := PipelineWatch.counts()
	var worst_ms := 0.0
	step.call()
	var until := Time.get_ticks_msec() + int(settle_seconds * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < until:
		await PipelineWatch.draw_frame(self)
		var now := Time.get_ticks_usec()
		worst_ms = maxf(worst_ms, float(now - last) / 1000.0)
		last = now
	var compiled := PipelineWatch.delta(before, PipelineWatch.counts(), true)
	_report[label] = {"compiled": compiled, "worst_frame_ms": snappedf(worst_ms, 0.1)}
	check(compiled.is_empty(), "%s: 試合中に描画の部品を作った %s" % [label, JSON.stringify(compiled)])


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if DisplayServer.get_name() == "headless":
		push_error("FRESH_PC_TEST needs a window (pipelines are not counted headless)")
		get_tree().quit(2)
		return
	GameManager.tutorial_prompt_seen_version = GameManager.CURRENT_TUTORIAL_VERSION
	GameManager.practice_intro_seen = true
	var gs := QuizManager.game_state
	gs.num_players = 1
	gs.mode = Constants.MODE_ENDLESS
	gs.llm_mode = "OFFLINE"
	QuizManager.provider.llm_mode = "OFFLINE"
	gs.start_game()
	gs.skip_start_helicopter_arrival = true
	await SceneTransition.fade_to_color_and_wait(Color.BLACK, true)
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	await get_tree().scene_changed
	var started := Time.get_ticks_msec()
	var world: Node = null
	while Time.get_ticks_msec() - started < 120000:
		await get_tree().process_frame
		world = get_tree().current_scene
		if world != null and world.get("_world_visual_prepared") and not SceneTransition.is_transitioning() \
				and gs.game_state == Constants.STATE_WAITING_START and bool(world.call("_can_trigger_start")):
			break
	check(world != null and world.scene_file_path == "res://scenes/game_world.tscn", "試合の画面に入る")
	if not _failures.is_empty():
		_finish()
		return
	var prep: Dictionary = world.get("_world_visual_prep_report")
	_report["prep"] = {
		"pipelines_settled": prep.get("pipelines_settled"), "render_frames": prep.get("render_frames"),
		"particle_prewarm": prep.get("particle_prewarm"), "elapsed_msec": prep.get("elapsed_msec"),
	}
	check(bool(prep.get("pipelines_settled", false)), "試合の準備で描画の部品作りが落ち着いてから覆いを外す")
	check(int(prep.get("particle_prewarm", 0)) >= 6, "試合の準備で粒子の演出を描く")
	gs.trigger_start()
	started = Time.get_ticks_msec()
	while gs.game_state != Constants.STATE_PLAYING and Time.get_ticks_msec() - started < 30000:
		await get_tree().process_frame
	check(gs.game_state == Constants.STATE_PLAYING, "PLAYING になる")
	await _frames(10)
	var pc := world.get_node("Player") as PlayerController
	var spawner: Node = world.get("particle_spawner")
	var recorder: Node = GameManager.get_node_or_null("HitchRecorder")
	check(recorder != null, "固まり記録が動いている")
	var recorded_before := int(recorder.get("match_stall_compiles")) if recorder != null else 0

	# 2. 間違えたときの点滅（_apply_health_pose が体を半透明にする）
	await _expect_no_compile("damage_flash", func() -> void:
		gs.p1_damage_time = QuizGameState.DAMAGE_FLASH_DURATION, 0.6)
	# 3. 粒子
	var at := Vector3(gs.player_x, gs.player_y, gs.player_local_z)
	await _expect_no_compile("particles", func() -> void:
		spawner.call("spawn_correct", at)
		spawner.call("spawn_ocean_splash", at + Vector3(2.0, 0.0, 0.0))
		spawner.call("spawn_explosion", at + Vector3(-2.0, 1.0, 0.0)), 0.8)
	# 4. サメにかまれる（GameWorld._play_shark_impact と同じ組み合わせ）。片付け（水柱 2.4 秒・爆発 4.5 秒）まで見る。
	await _expect_no_compile("shark_bite", func() -> void:
		spawner.call("spawn_shark_impact", at, Vector3.FORWARD)
		pc.begin_ocean_shark_explosion(1, gs), 5.2)
	# 2 回目（使い回し）も作らない
	await _expect_no_compile("shark_impact_again", func() -> void:
		spawner.call("spawn_shark_impact", at + Vector3(1.0, 0.0, 0.0), Vector3.LEFT), 3.0)
	if recorder != null:
		_report["recorder_match_stall_compiles"] = int(recorder.get("match_stall_compiles")) - recorded_before
		_report["recorder_events"] = recorder.get("match_compile_events")
	_finish()


func _finish() -> void:
	var result := {"checks": _checks, "failures": _failures, "report": _report}
	var file := FileAccess.open(OUT + "result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
	print("FRESH_PC_TEST " + JSON.stringify(result))
	get_tree().quit(0 if _failures.is_empty() else 1)

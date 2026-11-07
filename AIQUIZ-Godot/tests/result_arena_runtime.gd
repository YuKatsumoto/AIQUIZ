extends Node

## エンドレスの2人の両者脱落の結果発表を、海上の結果発表アリーナ（ResultArena）で行うことを本物の GameWorld で
## 確かめて撮る（tests/result_arena_bootstrap.gd から起動）。2 人を問題の壁で脱落させ（elimination_lasso_runtime と
## 同じ作り方）、暗転 → アリーナでの結果発表 → 次の試合の始まりまでを流す。
## （10問の両者脱落はハテナの投げ縄でコースのゴールへ運ぶ。tests/elimination_lasso_runtime.gd・result_ceremony_runtime の elimination）
## 確かめること：投げ縄の演出がない／暗転してからアリーナが出る／アリーナのあいだコース（床・左右の客席）が隠れる／
## 観客とモニター（GoalStand）はアリーナの正面スタンドで、暗転が明ける前に並び終わっている／左右のスタンドに座った観客がいる／
## 結果発表が最後まで進む／次の試合の始まりでアリーナが片付き、コースが戻る。
## 引数（"--" の後ろ）：quality=low|balanced|high|ultra、every=<秒>（撮る間隔、既定 1.0）、
## draw（同点にしてサドンデスへ進め、アリーナを出て決着してアリーナで結果発表に戻るまでを撮る）

var OUT := "res://artifacts/result_arena/runtime/"
var helper: Node
var gs: QuizGameState
var world: Node
var fps := 60
var quality := "high"
var every := 1.0
## 結果発表アリーナはエンドレスの2人だけ
var mode := Constants.MODE_ENDLESS
var draw := false
var checks := 0
var failures: Array[String] = []
var report := {}


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("quality="): quality = arg.trim_prefix("quality=")
		if arg.begins_with("every="): every = float(arg.trim_prefix("every="))
		if arg == "draw": draw = true
	OUT += "endless" + ("_draw" if draw else "") + "/"
	GameManager.graphics_quality = quality
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, mode)
	gs.sudden_death_enabled = draw
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	if draw:
		# サドンデスの問題を作る代役（sudden_death_runtime の GeneratingProvider）
		(load("res://scripts/core/game_state.gd") as GDScript).set("sudden_death_available", true)
		var generator: Node = load("res://tests/sudden_death_runtime.gd").GeneratingProvider.new()
		get_tree().root.add_child(generator)
		gs.provider = generator
	await frames(fps)
	world.call("_clear_preview_walls")
	world.call("_remove_start_barrier")
	gs.score = 5
	gs.player2_score = 5 if draw else 3
	await eliminate_both_mid_quiz()
	if draw:
		await observe_sudden_death()
		finish()
		return
	save_frame("00_eliminated")
	var stage: StageEnvironment = world.get("stage_env")
	var arena_seen_at := -1.0
	var populated_on_reveal := false
	var revealed := false
	var next_shot := 0.0
	var start_ms := Time.get_ticks_msec()
	for _frame in range(fps * 26):
		await RenderingServer.frame_post_draw
		var arena: ResultArena = world.get("_result_arena")
		var t := float(Time.get_ticks_msec() - start_ms) / 1000.0
		var lasso: EliminationLassoDirector = world.get("_elimination_lasso")
		if lasso != null and lasso.is_active():
			report["lasso_seen"] = true
		if arena == null:
			check(not gs.result_presentation_active or SceneTransition.is_fully_covered(), "the ceremony never shows the course")
		if arena != null and arena_seen_at < 0.0:
			arena_seen_at = t
			check(SceneTransition.is_fully_covered(), "the arena appears under the screen cover")
			check(not stage.is_course_visible(), "the course is hidden in the arena")
			check(world.get("_goal_stand") == arena.stand, "the ceremony's crowd and board are the arena's front stand")
			check(world.get("_goal_line_node") == null, "no goal gate in the arena")
			var center := ResultCeremonyDirector.podium_center(gs)
			check(arena.global_position.is_equal_approx(center), "the arena sits at the podium %s / %s" % [arena.global_position, center])
		if arena != null and not revealed and not SceneTransition.is_fully_covered():
			revealed = true
			populated_on_reveal = arena.stand.is_populated()
			check(populated_on_reveal, "the front stand's crowd is seated before the reveal")
			var seated := 0
			for crowd: Node in arena.wing_crowds:
				seated += int(crowd.get("spectator_count"))
			report["wing_spectators"] = seated
			report["front_spectators"] = arena.stand.spectators.size()
			check(seated > 100, "both wings hold a seated crowd (%d)" % seated)
			check(arena.stand.spectators.size() > 40, "the front stand holds its crowd (%d)" % arena.stand.spectators.size())
			check(arena.stand.scoreboard_installed(), "the arena's monitor shows the scoreboard")
		if revealed and gs.result_presentation_active:
			var elapsed := gs.result_ceremony_elapsed
			if elapsed >= next_shot:
				next_shot += every
				save_frame("ceremony_%05.2f" % elapsed)
		if gs.game_state == Constants.STATE_CLEAR and revealed and gs.result_ceremony_elapsed > QuizGameState.RESULT_TOTAL_DURATION + 1.5:
			break
	save_frame("zz_result_screen")
	report["arena_seen_at"] = arena_seen_at
	check(arena_seen_at >= 0.0, "the result arena appeared")
	check(not report.get("lasso_seen", false), "no elimination lasso in endless")
	check(gs.game_state == Constants.STATE_CLEAR, "the ceremony reached the result screen (state %s)" % gs.game_state)
	# 次の試合の始まり：アリーナを片付けてコースへ戻る
	gs.game_state = Constants.STATE_WAITING_START
	gs.result_presentation_active = false
	gs.result_from_elimination = false
	gs.state_changed.emit(gs.game_state)
	await frames(5)
	check(world.get("_result_arena") == null, "the arena is cleared at the next match")
	check(stage.is_course_visible(), "the course is back at the next match")
	finish()


## 2 人とも問題の壁で脱落させる（elimination_lasso_runtime の eliminate_both_mid_quiz と同じ）。
func eliminate_both_mid_quiz() -> void:
	gs.current_index = 3
	gs.current_wall_index = 3
	gs.game_state = Constants.STATE_PLAYING
	gs.load_current_quiz()
	var wall_z := gs.tuning.wall_start_z + 3 * gs.tuning.wall_spacing
	gs.world_scroll_z = wall_z - 7.0
	gs.player_z = gs.world_scroll_z + 0.5
	gs.player2_z = gs.world_scroll_z + 0.5
	await frames(3)
	gs._set_player_hp(1, 1)
	gs._set_player_hp(2, 1)
	var wrong := (gs.current_quiz.a + 1) % gs.num_choices
	gs.player_x = gs.tuning.door4_xs[wrong] if gs.num_choices == 4 else (gs.tuning.left_door_x if wrong == 0 else gs.tuning.right_door_x)
	gs.player2_x = gs.player_x
	gs.resolve_collision(true, true)
	check(gs.game_state == Constants.STATE_GAME_OVER and gs.is_elimination_result_pending(), "both out mid-quiz hold for the finale")


## 同点：結果発表の DRAW からサドンデス（HeliSuddenDeathDirector：種目発表 → 水上機で出発 → 空のセットの種目）へ進む。
## アリーナの大型モニターで種目を出し、舞台の縁から水上機に乗って出て行くまでを 2 秒ごとに撮り、演出の幕（act）を記録する。
## 種目は誰も答えないので決着まではたどらない（答えの流れは tests/sudden_death_runtime.gd）。
func observe_sudden_death() -> void:
	var director: Node = world.get("_sudden_death_director")
	var stage: StageEnvironment = world.get("stage_env")
	var acts: Array[String] = []
	var entered := false
	var next_shot := 0
	for frame in range(fps * 110):
		await RenderingServer.frame_post_draw
		var act := String(director.get("Act").keys()[int(director.get("_act"))])
		if acts.is_empty() or acts[-1] != act:
			acts.append(act)
		if gs.game_state == Constants.STATE_SUDDEN_DEATH:
			entered = true
		if frame >= next_shot:
			next_shot += fps * 2
			save_frame("sd_%03d_%s" % [frame / fps, act.to_lower()])
		if "DROP" in acts:
			break
	report["sudden_death_acts"] = acts
	check(entered, "the draw goes on to the sudden death")
	check("REVEAL" in acts and "BOARD" in acts and "SKY" in acts, "game reveal, floatplane boarding and the sky set play out (%s)" % [acts])
	var arena: ResultArena = world.get("_result_arena")
	check(arena != null and not stage.is_course_visible(), "the arena stays for the verdict after the sudden death")
	var floatplane: Node = world.find_child("StandGate", true, false)
	check(floatplane == null, "no course stand gate rises in the arena")


func save_frame(tag: String) -> void:
	get_viewport().get_texture().get_image().save_jpg(OUT + tag + ".jpg", 0.88)


func finish() -> void:
	report["passed"] = failures.is_empty()
	report["checks"] = checks
	report["failures"] = failures
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("RESULT_ARENA_RUNTIME " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

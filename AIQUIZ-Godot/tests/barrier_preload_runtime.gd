extends Node

## カウントダウンの壁（スタートバリア）は、問題の読み込み（STATE_PRELOADING）が終わるまで落ちないことを、本物の GameWorld で
## 確かめる（tests/barrier_preload_bootstrap.gd から起動）。エンドレスの2人と10問の2人で、問題が届かないあいだ数秒待ち、
## 問題を渡して読み込みが終わったら（STATE_WAITING_START）すぐ落ちることを見る。

## 問題をまだ作れていない供給元（読み込み中のまま待たせる）。
class StalledProvider extends QuizProvider:
	func _load_bank() -> Dictionary:
		return {}

	func get_quizzes(_subject: String, _grade: int, _difficulty: String, _mode: String, _count: int,
			_exclude_texts: Array[String] = []) -> Array[QuizItem]:
		return []


const OUT := "res://artifacts/barrier_preload/"
const WAIT_SECONDS := 4.0
var fps := 60
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
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT + ".gdignore", FileAccess.WRITE)
	QuizManager.player_analytics = null
	for mode: String in [Constants.MODE_ENDLESS, Constants.MODE_TEN]:
		await run_mode(mode)
	report["passed"] = failures.is_empty()
	report["checks"] = checks
	report["failures"] = failures
	print("BARRIER_PRELOAD_RUNTIME " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)


func run_mode(mode: String) -> void:
	var helper: Node = load("res://tests/hp_unit.gd").new()
	var gs: QuizGameState = helper.fixture(2, mode)
	var quizzes: Array[QuizItem] = gs.quiz_list.duplicate()
	# 問題がまだ届いていない読み込み中から始める（問題の供給元は何も返さない）
	var stalled := StalledProvider.new()
	add_child(stalled)
	gs.provider = stalled
	gs.quiz_list.clear()
	gs.current_index = 0
	gs.current_wall_index = 0
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_PRELOADING
	QuizManager.game_state = gs
	var world: Node = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	var dropped_while_loading := false
	var shown_while_loading := false
	for _frame in range(roundi(WAIT_SECONDS * fps)):
		await get_tree().process_frame
		if bool(world.get("_barrier_spawned_for_session")):
			dropped_while_loading = true
		# 描画の予熱（本番では暗転の下）で一時的に置くぶんは数えない：コースの壁の入れ物にあるものだけ
		var barrier: Node3D = world.get("_start_barrier")
		if barrier != null and barrier.is_visible_in_tree() and barrier.get_parent() == world.get("wall_container"):
			shown_while_loading = true
	var tag := mode.to_lower()
	get_viewport().get_texture().get_image().save_jpg(OUT + tag + "_loading.jpg", 0.85)
	check(gs.game_state == Constants.STATE_PRELOADING, "%s: still loading without questions (%s)" % [mode, gs.game_state])
	check(not dropped_while_loading, "%s: the countdown wall stays up while the questions load" % mode)
	check(not shown_while_loading, "%s: the countdown wall is not on the course while the questions load" % mode)
	# 問題が届く → 読み込みが終わる → カウントダウンの壁が落ちる
	gs.quiz_list.append_array(quizzes)
	var loaded_frame := -1
	var drop_frame := -1
	for frame in range(fps * 15):
		await get_tree().process_frame
		if loaded_frame < 0 and gs.game_state != Constants.STATE_PRELOADING:
			loaded_frame = frame
		if bool(world.get("_barrier_spawned_for_session")):
			drop_frame = frame
			check(loaded_frame >= 0 and loaded_frame <= frame, "%s: the wall drops only after loading completes" % mode)
			break
	await frames(fps)
	get_viewport().get_texture().get_image().save_jpg(OUT + tag + "_dropped.jpg", 0.85)
	check(drop_frame >= 0, "%s: the countdown wall drops once the questions are ready" % mode)
	report[tag] = {"loaded_frame": loaded_frame, "drop_frame": drop_frame, "state": gs.game_state}
	get_tree().current_scene = null
	world.queue_free()
	await frames(5)
	stalled.queue_free()
	for provider: Node in helper.get("providers"):
		if is_instance_valid(provider):
			provider.free()
	helper.free()

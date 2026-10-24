extends Node

## 実際のゲーム画面で、自動モードの壁が「見積もった秒数」ちょうどに届くかを確かめる。
## 1人・10問モード。プレイヤーは正解のドアの前に立つだけで、ベルトに運ばれて壁に当たる。
## godot --path . --resolution 1280x720 --script res://tests/wall_speed_bootstrap.gd -- runtime

class TestProvider extends QuizProvider:
	func _load_bank() -> Dictionary:
		return {}
	func submit_result(_quiz: QuizItem, _correct: bool) -> void:
		pass

const OUT := "res://artifacts/wall_speed/"
## 問題が出てからこの秒数で画面を撮り、壁の近さを比べる。
const SNAPSHOT_AFTER := 5.0
const ARRIVAL_TOLERANCE := 0.15

var gs: QuizGameState
var world: Node3D
var provider: TestProvider
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var _loaded_at := 0.0
var _plan := {}


func _ready() -> void:
	call_deferred("run")


func quiz(q: String, choices: Array) -> QuizItem:
	# AI の予測解答時間は実データで一番多い 4.0 にそろえる（旧ロジックでは全部同じ速さになる）。
	return QuizItem.create(q, PackedStringArray(choices), 0, "", "GEMINI_POOL", "", PackedStringArray(), 4.0)


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	provider = TestProvider.new()
	gs = QuizGameState.new(provider)
	gs.num_players = 1
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	gs.subject = "算数"
	gs.grade = 4
	gs.difficulty = "普通"
	gs.target_count = 10
	gs.tuning.wall_speed_override = 0.0
	gs.game_state = Constants.STATE_PLAYING
	gs.skip_start_helicopter_arrival = true
	gs._reset_health()
	gs.player_z = -8.0
	var questions := [
		quiz("正方形の辺の数は？", ["4", "3"]),
		quiz("たて12cm横5cm高さ4cmの箱と、1辺6cmの立方体の体積の差は何cm³？", ["24cm³", "36cm³"]),
		quiz("三角形の角の数は？", ["3", "4"]),
		quiz("1本85円のえんぴつを3本買って500円出すと、おつりは何円？", ["245円", "255円"]),
	]
	for i in range(10):
		gs.quiz_list.append(questions[i % questions.size()] if i < 9 else quiz("12×3+8 はいくつ？", ["44", "42", "46", "40"]))
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.quiz_loaded.connect(_on_quiz_loaded)
	gs.question_completed.connect(_on_question_completed)
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	gs.load_current_quiz()
	for index in range(questions.size()):
		var wall := gs.current_wall_index
		while gs.play_time - _loaded_at < SNAPSHOT_AFTER:
			await get_tree().process_frame
		await capture("q%d_after_%ds" % [index, int(SNAPSHOT_AFTER)])
		var waited := 0.0
		while gs.current_wall_index == wall and waited < 30.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		check(gs.current_wall_index == wall + 1, "wall %d reached" % index)
	var easy: Dictionary = rows[0]
	var hard: Dictionary = rows[1]
	check(hard.budget > easy.budget + 3.0, "the hard question gets clearly more time")
	check(rows[3].budget > rows[2].budget + 3.0, "the change-making problem gets clearly more time")
	var report := {"passed": failures.is_empty(), "failures": failures, "rows": rows,
		"renderer": RenderingServer.get_current_rendering_method()}
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WALL_SPEED_RUNTIME " + JSON.stringify(report))
	provider.free()
	get_tree().quit(0 if failures.is_empty() else 1)


func _on_quiz_loaded(_quiz: QuizItem) -> void:
	_loaded_at = gs.play_time
	_plan = {
		"q": gs.current_quiz.q,
		"speed": gs._active_wall_speed,
		"budget": gs.wall_speed_planner.last_budget_seconds,
		"answer": gs.wall_speed_planner.last_answer_seconds,
		"distance": gs._distance_to_current_wall(),
	}
	# 正解のドアの前に立つ。前後には動かず、ベルトに運ばれるのを待つ。
	gs.player_x = gs.tuning.left_door_x if gs.current_quiz.a == 0 else gs.tuning.right_door_x


func _on_question_completed(_wall: int, correct: bool) -> void:
	var row := _plan.duplicate()
	row["arrival"] = gs.play_time - _loaded_at
	row["correct"] = correct
	rows.append(row)
	check(correct, "answered at the correct door: " + str(row.q))
	check(absf(row.arrival - row.budget) <= ARRIVAL_TOLERANCE,
		"wall arrives on schedule (%.2fs planned, %.2fs actual): %s" % [row.budget, row.arrival, row.q])


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")

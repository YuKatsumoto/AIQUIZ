class_name PracticeSession
extends RefCounted

## メニューとゲーム画面の間で、遊ぶコースを渡す（docs/new_tutorial/foundation_design.md 6章）。
## シーンを切り替えても残るよう、値は static に持つ。ゲーム画面の PracticeDirector が course_id のコースを読む。

const GAME_WORLD_SCENE := "res://scenes/game_world.tscn"

## 遊ぶコース（例 "c1"）
static var course_id := ""
## ③で、P2 を CPU にする
static var with_cpu := false
## 初回の案内（PracticeIntroPrompt）の［する］から始めた
static var from_first_run := false
## メニューに戻ったら、コース選択を開く（コースを最後まで遊んだとき）。メニューが開いたら消す。
static var return_to_select := false
## メニューに戻ったら、そのコースの続き（メニューの上のレッスン）を始める（docs/new_tutorial/phase5_design.md 2章）。
## 例：②の 2-6 は {"course": "c2", "step": "2-6", "star": true, "skipped": 0, "first_run": false}。メニューが始めたら消す。
static var resume_in_menu := {}
## メニューに戻ったら、このコースをすぐ始める（クリアカードの［つぎの コースへ］）。メニューが始めたら消す。
static var launch_next := ""


## コース id を始める：game_state を練習のモードと人数にし、メニューの退場の演出でゲーム画面へ移る。
## menu はメインメニュー（scripts/ui/main_menu.gd）。遊べないコースなら何もしない。
## コースの始めの画面（PracticeCatalog の scene）があるコース（④）は、その画面へ移る。画面は resume_in_menu
## （{"course": "c4", "step": "4-1", "first_run": …}）を見て、その画面の上のレッスンを始める（docs/new_tutorial/phase7_design.md 1.1）。
## その画面がいまのメニュー（⑤はメインメニュー）なら、画面を移らずに menu.practice_start_here で始める（phase8_design.md 1.1）。
static func launch(menu: Node, id: String, cpu := false, first_run := false) -> void:
	var course := PracticeCatalog.find(id)
	if course.is_empty() or not bool(course.get("available", false)):
		push_warning("PracticeSession: course %s is not available" % id)
		return
	course_id = id
	with_cpu = cpu
	from_first_run = first_run
	return_to_select = false
	var scene := str(course.get("scene", ""))
	if not scene.is_empty() and scene == menu.scene_file_path and menu.has_method(&"practice_start_here"):
		resume_in_menu = {}
		menu.call(&"practice_start_here", id, first_run)
		return
	if not scene.is_empty():
		# モードと人数は、その画面からゲーム画面へ移るときに決める（途中でメニューへ戻ってもモードを残さない）
		resume_in_menu = {"course": id, "step": "", "first_run": first_run}
		menu.call("_play_exit_and_change_scene", scene, false)
		return
	var game_state: QuizGameState = QuizManager.game_state
	game_state.mode = Constants.MODE_PRACTICE
	game_state.num_players = int(course.players)
	menu.call("_play_exit_and_change_scene", GAME_WORLD_SCENE, false)

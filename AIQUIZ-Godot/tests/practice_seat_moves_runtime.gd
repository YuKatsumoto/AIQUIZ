extends Node

## 案内のハテナの、席へ戻る・席を離れる動き（docs/new_tutorial/phase9_design.md 5章、PracticeSeatMoves）の見た目の確かめ。
##   1. メニュー（②の 2-6 の続き）：のこぎりの操縦席のハテナが立ち上がり、呼んだ雲に跳び乗って画面の右側へ（saw_leave）
##      → Esc でとばしてクリア →［あとで］で、雲で席の横へ飛び、座面へ跳び降りて座る（saw_return）
##   2. オンラインの画面（④のクリアの続き）：操縦士のハテナが立ち上がり、ドアを押し上げて降り、ドアを閉めて雲で飛ぶ（heli_leave）
##      →［あとで］で、雲でヘリの横へ降り、歩いてドアを開け、ステップを上がって乗り、ドアを閉めて座る（heli_board）
## 動いている間、0.35 秒ごとに遊ぶ画面（カメラはそのまま）と、近くのカメラで撮る。席のハテナが隠れる・出る、ドアが開いて閉まる、
## ベルト、ハテナの親（席の台の子 → 元へ）を確かめる。最後に {"passed", "checks", "failures"} を出す。

const OUT := "res://artifacts/practice_seat_moves/"
const SETTINGS := "user://practice_seat_moves_settings.json"
const MAIN_MENU := "res://ui/main_menu.tscn"
const ONLINE_MENU := "res://ui/online_menu.tscn"
const SHOT_EVERY := 0.2

var failures: Array[String] = []
var checks := 0
var _saved := {}
var _shooting := false
var _close_camera: Camera3D = null


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var gs := QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "stamps": GameManager.practice_stamps.duplicate(true),
		"intro": GameManager.practice_intro_seen, "llm": QuizManager.provider.llm_mode, "players": gs.num_players}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	GameManager.practice_stamps = {}
	GameManager.practice_intro_seen = true
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode("OFFLINE")
	gs.num_players = 1
	await _menu_saw()
	await _online_heli()
	_finish()


# ---------- 1. メニューの操縦席 ----------

func _menu_saw() -> void:
	PracticeSession.resume_in_menu = {"course": "c2", "step": "2-6", "star": false, "skipped": 0, "first_run": false}
	get_tree().change_scene_to_file(MAIN_MENU)
	var opened := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and scene.find_child("PracticeMenuGuide", true, false) != null, 30000)
	check(opened, "the menu starts the 2-6 guide")
	if not opened:
		return
	var menu := get_tree().current_scene
	var guide := menu.find_child("PracticeMenuGuide", true, false) as PracticeMenuGuide
	var saw := menu.call("practice_menu_saw") as SawChaseController
	check(saw != null and saw.operator_seat != null, "the menu has the saw and its seat")
	if saw == null or saw.operator_seat == null:
		return
	var leaving := await _wait(func() -> bool: return guide.get("_seat_moves") != null, 15000)
	check(leaving, "the guide starts the seat moves (leaving the seat)")
	var hatena := guide.hatena
	await _frames(2)
	check(hatena.get_parent() == saw.operator_seat, "while leaving, the guide Hatena is a child of the seat")
	check(saw.is_operator_hidden() and hatena.visible and hatena.is_seated(), "the seat Hatena hides and the guide Hatena sits in its place")
	_watch_menu(menu, saw, "menu_leave")
	var done := await _wait(func() -> bool: return guide.get("_seat_moves") == null, 15000)
	_shooting = false
	check(done, "the leaving moves end")
	check(hatena.get_parent() == menu.call("practice_menu_world") and hatena.visible and hatena.has_cloud(),
		"after leaving, the guide Hatena rides its cloud in the menu world")
	check(saw.is_operator_hidden(), "the seat stays empty while the guide is out")
	# Esc で 2-6 をとばしてクリア →［あとで］
	await _seconds(0.5)
	guide.call("_on_exit_requested")
	var card := await _wait(func() -> bool: return str(guide.phase) == "card", 20000)
	check(card, "skipping brings the clear card")
	if not card:
		return
	await _seconds(2.5)
	guide.call("_on_card_button", 1)
	var returning := await _wait(func() -> bool: return guide.get("_seat_moves") != null, 5000)
	check(returning, "あとで starts the seat moves (going back)")
	_watch_menu(menu, saw, "menu_return")
	var guide_ref: WeakRef = weakref(guide)
	guide = null
	var back := await _wait(func() -> bool:
		var live := guide_ref.get_ref() as Node
		return live == null or live.get("_seat_moves") == null, 15000)
	_shooting = false
	await _frames(2)
	check(back, "the going-back moves end")
	check(not saw.is_operator_hidden(), "the seat Hatena is back")
	check(not is_instance_valid(hatena) or not hatena.visible, "the guide Hatena is gone after sitting down")
	await _seconds(0.5)


## 動いている間、遊ぶ画面と近くのカメラ（操縦席に寄る）で撮る。
func _watch_menu(menu: Node, saw: SawChaseController, tag: String) -> void:
	var world := menu.call("practice_menu_world") as Node
	var camera := menu.call("practice_menu_camera") as Camera3D
	_shooting = true
	var index := 0
	while _shooting and is_inside_tree() and is_instance_valid(saw):
		await _shot("%s_%02d" % [tag, index])
		var seat := saw.operator_seat.skeleton.global_position + Vector3.UP * 0.9
		var toward := (camera.global_position - seat).normalized()
		await _close_shot(world, seat + toward * 5.0 + Vector3.UP * 0.4, seat, camera, "%s_%02d_close" % [tag, index])
		index += 1
		await _seconds(SHOT_EVERY)


# ---------- 2. オンラインの画面のヘリ ----------

func _online_heli() -> void:
	PracticeSession.resume_in_menu = {"course": "c4", "step": "clear", "first_run": false}
	get_tree().change_scene_to_file(ONLINE_MENU)
	var opened := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene is OnlineMenu and (scene as OnlineMenu).practice_guide() != null, 30000)
	check(opened, "the online menu starts the c4 clear guide")
	if not opened:
		return
	var menu := get_tree().current_scene as OnlineMenu
	var guide := menu.practice_guide()
	var stage := menu.practice_stage()
	var heli := stage.my_heli if stage != null else null
	check(heli != null and heli.pilot != null, "the stage has my helicopter with its pilot")
	if heli == null or heli.pilot == null:
		return
	var leaving := await _wait(func() -> bool: return guide.get("_seat_moves") != null, 20000)
	check(leaving, "the clear starts the seat moves (getting off the helicopter)")
	var hatena := guide.hatena
	await _frames(2)
	check(hatena.get_parent() == heli and hatena.is_seated() and not heli.pilot.visible,
		"the guide Hatena sits in the pilot's place (the pilot hides)")
	var opened_door := [0.0]
	_watch_heli(menu, heli, opened_door, "heli_leave")
	var done := await _wait(func() -> bool: return guide.get("_seat_moves") == null, 25000)
	_shooting = false
	check(done, "the getting-off moves end")
	check(opened_door[0] > 0.9, "the door opened while getting off (%.2f)" % opened_door[0])
	check(heli.door_openness(PracticeSeatMoves.HELI_DOOR) < 0.05, "the door is closed again (%.2f)" % heli.door_openness(PracticeSeatMoves.HELI_DOOR))
	check(hatena.get_parent() == stage and hatena.visible and hatena.has_cloud(), "after getting off, the guide Hatena rides its cloud on the stage")
	var card := await _wait(func() -> bool: return str(guide.phase) == "card", 15000)
	check(card, "the clear card shows")
	if not card:
		return
	await _seconds(2.5)
	guide.call("_on_card_button", 1)
	var boarding := await _wait(func() -> bool: return guide.get("_seat_moves") != null, 5000)
	check(boarding, "あとで starts the seat moves (boarding)")
	opened_door[0] = 0.0
	_watch_heli(menu, heli, opened_door, "heli_board")
	var guide_ref: WeakRef = weakref(guide)
	guide = null
	var back := await _wait(func() -> bool:
		var live := guide_ref.get_ref() as Node
		return live == null or live.get("_seat_moves") == null, 25000)
	_shooting = false
	await _frames(2)
	check(back, "the boarding moves end")
	check(opened_door[0] > 0.9, "the door opened while boarding (%.2f)" % opened_door[0])
	check(heli.door_openness(PracticeSeatMoves.HELI_DOOR) < 0.05, "the door is closed after boarding")
	check(heli.pilot.visible, "the pilot Hatena is back in the seat")
	check(not is_instance_valid(hatena) or not hatena.visible, "the guide Hatena is gone after sitting down")
	await _seconds(0.5)


func _watch_heli(menu: OnlineMenu, heli: OnlineHeliportHelicopter, opened_door: Array, tag: String) -> void:
	var stage := menu.practice_stage()
	var camera := menu.practice_camera()
	_shooting = true
	var index := 0
	var follow := func() -> void:
		while _shooting and is_instance_valid(heli):
			opened_door[0] = maxf(float(opened_door[0]), heli.door_openness(PracticeSeatMoves.HELI_DOOR))
			await get_tree().process_frame
	follow.call()
	while _shooting and is_inside_tree() and is_instance_valid(heli):
		await _shot("%s_%02d" % [tag, index])
		# ドアが画面の右寄り（オンラインの画面の左の板に隠れない所）に来るよう、ドアより機首のほうを見る
		var look := heli.to_global(heli.marker_position("MK_Step") + Vector3(0.0, 1.3, -1.6))
		var eye := heli.to_global(heli.marker_position("MK_BoardStand") + Vector3(-4.6, 2.0, -3.4))
		await _close_shot(stage, eye, look, camera, "%s_%02d_close" % [tag, index])
		index += 1
		await _seconds(SHOT_EVERY)


# ---------- 道具 ----------

## 近くのカメラ（world の中）で撮って、元のカメラに戻す。
func _close_shot(world: Node, eye: Vector3, look: Vector3, back_to: Camera3D, tag: String) -> void:
	if world == null:
		return
	if _close_camera == null or not is_instance_valid(_close_camera) or _close_camera.get_parent() != world:
		_close_camera = Camera3D.new()
		_close_camera.name = "SeatMovesCloseCamera"
		_close_camera.fov = 42.0
		world.add_child(_close_camera)
	_close_camera.global_position = eye
	_close_camera.look_at(look, Vector3.UP)
	_close_camera.make_current()
	await _frames(1)
	await _shot(tag)
	if back_to != null and is_instance_valid(back_to):
		back_to.make_current()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration, true).timeout


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")


func _finish() -> void:
	_shooting = false
	GameManager.settings_path = _saved.path
	GameManager.practice_stamps = _saved.stamps
	GameManager.practice_intro_seen = _saved.intro
	QuizManager.provider.set_llm_mode(_saved.llm)
	QuizManager.game_state.num_players = _saved.players
	PracticeSession.resume_in_menu = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	print("PRACTICE_SEAT_MOVES " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

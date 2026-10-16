extends Node

## Online menu flow (no relay needed): main menu button placement, the dedicated online
## menu's pages and back navigation, and the way back to the main menu.
##   Godot --path . --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_menu_runtime.gd [shots=DIR]
## A closed port stands in for the relay, so "find" must fall back to the home page.

const DEAD_RELAY := "ws://127.0.0.1:9"

var gs: QuizGameState
var failures: Array[String] = []
var checks := 0
var shots_dir := ""
var _saved := {}


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			shots_dir = arg.trim_prefix("shots=")
	gs = QuizManager.game_state
	_saved = {"subject": gs.subject, "grade": gs.grade, "difficulty": gs.difficulty, "name": GameManager.online_name}
	NetworkManager.relay_url = DEAD_RELAY

	await _main_menu_button()
	var menu := await _open_online_menu()
	if menu != null:
		await _home_page(menu)
		await _stage_phases(menu)
		await _friend_page(menu)
		await _find_without_relay(menu)
		await _back_to_main_menu(menu)
	_finish()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _main_menu_button() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await _frames(30)
	var main_menu := get_tree().current_scene
	var online := main_menu.find_child("OnlineVersusBtn", true, false) as Button
	check(online != null, "main menu has the online button")
	if online == null:
		return
	var row := online.get_parent()
	check(row.name == "TutorialRow", "online button sits in the tutorial row")
	check(row.get_child(0).name == "TutorialMainBtn" and row.get_child(1) == online, "online button is right of the tutorial button")
	check(online.text == "オンライン対戦", "online button label")
	var endless := main_menu.find_child("EndlessBtn", true, false) as Control
	await _frames(20)  # entrance slide
	check(absf(online.global_position.x - endless.global_position.x) < 2.0,
		"online button lines up under エンドレス (%.1f vs %.1f)" % [online.global_position.x, endless.global_position.x])
	await _shot("main_menu_mode")
	# 「2人プレイ」の切り替えにオンラインはもう出てこない。
	var seen := {}
	gs.num_players = 1
	for i in range(4):
		main_menu.call("_on_players_toggle_pressed")
		seen[gs.num_players] = true
	check(seen.keys().all(func(n: int) -> bool: return n in [1, 2]), "player toggle stays 1/2 (saw %s)" % [seen.keys()])
	gs.num_players = 2


func _open_online_menu() -> OnlineMenu:
	var main_menu := get_tree().current_scene
	var online := main_menu.find_child("OnlineVersusBtn", true, false) as Button
	if online == null:
		return null
	online.pressed.emit()
	var opened := await _wait(func() -> bool: return get_tree().current_scene is OnlineMenu, 8000)
	check(opened, "online button opens the online menu scene")
	if not opened:
		return null
	var menu := get_tree().current_scene as OnlineMenu
	check(menu.scene_file_path == OnlineMenu.SCENE_PATH, "online menu scene path")
	check(menu.current_id() == OnlineMenu.HOME, "online menu starts on home")
	# 遷移のワイプが開ききるまでは、もどる操作を受け付けない（二重の遷移を防ぐ）。
	check(await _wait(func() -> bool: return not SceneTransition.is_transitioning(), 5000),
		"online menu reveals the transition cover")
	await _frames(5)
	await _shot("online_home")
	return menu


func _home_page(menu: OnlineMenu) -> void:
	var home := menu.page(OnlineMenu.HOME) as OnlineHomePage
	var subject := gs.subject
	home.call("_shift", &"subject", 1)
	check(gs.subject != subject, "subject stepper changes the subject")
	check((home.get("_values")[&"subject"] as Label).text == gs.subject, "subject label follows")
	var difficulty := gs.difficulty
	home.call("_shift", &"difficulty", -1)
	check(gs.difficulty != difficulty, "difficulty stepper changes the difficulty")
	home.call("_shift", &"grade", 1)
	check((home.get("_values")[&"grade"] as Label).text == "%d年生" % gs.grade, "grade label follows")

	var input := home.get("_name_input") as LineEdit
	var find := home.get("_find_button") as Button
	input.text = "しね"
	home.call("_on_name_changed", input.text)
	check(find.disabled, "NG name disables matching")
	home.roll_name()
	check(not find.disabled, "dice name re-enables matching")
	check(GameManager.online_name == input.text, "dice name is saved")
	# 見た目の確認用：なまえの入力欄を選んだとき（ふちが光る）と、スキン設定のページ
	input.grab_focus()
	await _frames(3)
	await _shot("online_home_name_focus")
	menu.call("_on_page_action", &"skin", {})
	check(menu.current_id() == OnlineMenu.SKIN, "the skin sign action opens the skin page")
	await _seconds(0.8)
	await _shot("online_skin")
	menu.back()
	check(menu.current_id() == OnlineMenu.HOME, "back from the skin page returns home")
	await _seconds(0.8)


## 3D の背景（海上ヘリポート v2）と演出の監督。演出の中身は tests/net/online_staging_runtime.gd が確かめる。
func _stage_phases(menu: OnlineMenu) -> void:
	var stage := menu.stage
	check(stage != null, "the online menu builds the 3D heliport")
	if stage == null:
		return
	check(stage.camera != null and stage.camera.current, "the heliport camera is current")
	check(menu.director != null and menu.director.state_name() == "IDLE", "home shows the idle heliport")
	check(stage.my_heli.global_position.distance_to(stage.pad_ground.origin) < 0.01, "my helicopter rests on the single pad")
	check(not stage.their_heli.visible, "their helicopter is hidden at home")
	await _seconds(0.3)


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _friend_page(menu: OnlineMenu) -> void:
	menu.call("_on_page_action", &"friend", {})
	check(menu.current_id() == OnlineMenu.FRIEND, "friend button opens the friend page")
	var friend := menu.page(OnlineMenu.FRIEND) as OnlineFriendPage
	await _frames(5)
	await _shot("online_friend")
	friend.call("_set_mode", OnlineFriendPage.Mode.JOIN)
	menu.join_friend_room("AB")
	check((menu.get("_status") as Label).text.contains("5もじ"), "short code is refused with a reason")
	menu.back()
	check(menu.current_id() == OnlineMenu.FRIEND and friend.get("_mode") == OnlineFriendPage.Mode.CHOOSE, "back from code entry returns to the friend choices")
	menu.back()
	check(menu.current_id() == OnlineMenu.HOME, "back from the friend page returns home")


func _find_without_relay(menu: OnlineMenu) -> void:
	menu.find_match()
	check(menu.director == null or menu.director.state_name() == "BOARDING", "find starts the boarding")
	check(menu.director == null or menu.chrome() == OnlineMenu.CHROME_STAGING, "boarding hides the home column")
	var back_home := await _wait(func() -> bool:
		return menu.current_id() == OnlineMenu.HOME and (menu.director == null or menu.director.state_name() == "IDLE") 			and not menu.get("_cancelling"), 15000)
	check(back_home, "a dead relay falls back to home")
	check(not (menu.get("_status") as Label).text.is_empty(), "the failure reason is shown")
	await _frames(5)
	await _shot("online_home_failed")


func _back_to_main_menu(menu: OnlineMenu) -> void:
	menu.back()
	var returned := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == "res://ui/main_menu.tscn", 20000)
	check(returned, "back from home returns to the main menu")
	check(gs.menu_step == Constants.MENU_STEP_MODE, "main menu opens on the mode step")


func _shot(label: String) -> void:
	if shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, label])


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _finish() -> void:
	gs.subject = _saved.subject
	gs.grade = _saved.grade
	gs.difficulty = _saved.difficulty
	if NetNameFilter.is_ok(str(_saved.name)):
		GameManager.set_online_name(str(_saved.name))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	print("ONLINE_MENU " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

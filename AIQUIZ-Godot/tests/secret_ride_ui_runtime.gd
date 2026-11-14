extends Node

## カスタマイズ画面「スキン」のシークレット枠（ママチャリ）と、解放の知らせを本物の画面で確かめる。
##   解放前：「？？？」→ 押すと条件が出る ／ 解放後：「ママチャリ NEW!」→ 押すと乗る・もう一度で降りる
## 解放の記録とスキンの保存先はテスト用に差し替え、終わったら元に戻す。ウィンドウありで流す：
##   Godot --path . --resolution 1280x720 --script tests/secret_ride_ui_bootstrap.gd
## 撮った画像は artifacts/secret_ride_ui/。

const OUT := "res://artifacts/secret_ride_ui/"
const SETTINGS := "user://secret_ride_ui_settings.json"
const SKINS := "user://secret_ride_ui_skins.json"
const UNLOCKS := "user://secret_ride_ui_unlocks.json"
const MAIN_MENU := "res://ui/main_menu.tscn"
const SIZE := Vector2i(1280, 720)
const ToastScript := preload("res://scripts/ui/secret_unlock_toast.gd")

var gs: QuizGameState
var _saved := {}
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "skin_path": PlayerSkinStore.path, "unlock_path": UnlockStore.path,
		"llm": QuizManager.provider.llm_mode}
	GameManager.settings_path = SETTINGS
	PlayerSkinStore.flush()
	PlayerSkinStore.path = SKINS
	UnlockStore.path = UNLOCKS
	for user_path: String in [SETTINGS, SKINS, UNLOCKS]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(user_path))
	UnlockStore.reset_memory()
	PlayerSkinStore.reset_memory()
	PlayerSkinStore.apply_to_state(gs)
	GameManager.practice_intro_seen = true
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode("OFFLINE")
	gs.num_players = 1
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""

	get_tree().change_scene_to_file(MAIN_MENU)
	var ready := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and scene.has_method(&"practice_customize") \
			and scene.is_node_ready() and not SceneTransition.is_transitioning(), 25000)
	if not ready:
		_failures.append("the main menu did not open")
		_finish()
		return
	await _seconds(4.0)
	var menu := get_tree().current_scene as Control
	menu.call(&"practice_menu_show_config")
	await _seconds(1.2)
	menu.call(&"practice_open_customize")
	await _wait(func() -> bool: return bool(menu.call(&"practice_customize_ready")), 6000)
	await _seconds(1.5)
	var customize := menu.call(&"practice_customize") as Control
	var tab := customize.call(&"practice_coach_target", &"tab_skin") as BaseButton
	if tab != null:
		tab.pressed.emit()
	await _seconds(1.6)

	var button := customize.find_child("SecretRideButton", true, false) as Button
	var hint := customize.find_child("SecretRideHint", true, false) as Label
	if button == null or hint == null:
		_failures.append("the secret ride button is missing from the skin tab")
		_finish()
		return
	_check(button.is_visible_in_tree(), "secret button is visible on the skin tab")
	_check(_inside_panel(button) and _inside_panel(hint), "secret button and hint fit inside the settings panel")

	# 解放前
	_check(button.text.contains("？？？") and not button.text.contains("ママチャリ"), "locked: the name is hidden")
	_check(not hint.text.contains("50問"), "locked: the condition is hidden until pressed")
	await _shot("1_locked")
	button.pressed.emit()
	await _seconds(0.3)
	_check(hint.text.contains("エンドレス") and hint.text.contains("50問") and hint.text.contains("普通"), "locked: pressing shows the condition")
	_check(gs.p1_ride == RideData.RIDE_NONE, "locked: pressing does not equip the ride")
	_check(_inside_panel(hint), "the condition text fits inside the settings panel")
	await _shot("2_locked_hint")

	# 解放した直後
	_check(UnlockStore.unlock(UnlockStore.MAMACHARI), "unlock succeeds")
	customize.call(&"_refresh_all_labels")
	await _seconds(0.3)
	_check(button.text.contains("ママチャリ") and button.text.contains("NEW"), "unlocked: shows the name with NEW")
	await _shot("3_unlocked_new")

	# 乗る・降りる
	button.pressed.emit()
	await _seconds(0.3)
	_check(gs.p1_ride == RideData.RIDE_MAMACHARI, "pressing equips the ride")
	_check(PlayerSkinStore.get_ride(1) == RideData.RIDE_MAMACHARI, "the ride is stored")
	_check(not button.text.contains("NEW"), "NEW disappears after the first press")
	_check(bool(button.get(&"chosen")), "the button lamp is on while riding")
	# プレビューのキャラも自転車に乗り、カメラが引いて全体が見える
	await _seconds(2.2)
	_check(_visible_bikes() == 1, "the preview character rides the bike")
	await _shot("4_riding")
	button.pressed.emit()
	await _seconds(0.3)
	_check(gs.p1_ride == RideData.RIDE_NONE and PlayerSkinStore.get_ride(1) == RideData.RIDE_NONE, "pressing again gets off")
	_check(_visible_bikes() == 0, "the preview character gets off the bike")

	# プレイヤー2 は別に選べる
	var p2 := customize.call(&"practice_coach_target", &"skin_players") as Control
	customize.call(&"_set_skin_editing_player", 2)
	button.pressed.emit()
	await _seconds(0.3)
	_check(gs.p2_ride == RideData.RIDE_MAMACHARI and gs.p1_ride == RideData.RIDE_NONE, "player 2 chooses independently")
	_check(p2 != null, "skin player buttons exist")

	# 解放の知らせ（試合中に出るもの）
	var layer := CanvasLayer.new()
	layer.layer = 50
	get_tree().root.add_child(layer)
	var toast := ToastScript.new()
	layer.add_child(toast)
	toast.present(UnlockStore.MAMACHARI)
	await _seconds(1.0)
	var rect := toast.get_global_rect()
	var view := get_viewport().get_visible_rect()
	_check(view.encloses(rect), "the toast is fully on screen")
	_check(absf(rect.get_center().x - view.get_center().x) < 2.0, "the toast is centred")
	await _shot("5_toast")
	await _wait(func() -> bool: return layer.get_child_count() == 0, 8000)
	_check(layer.get_child_count() == 0, "the toast removes itself")
	layer.queue_free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## 画面に出ているママチャリの数（カスタマイズのプレビューのキャラが乗っているもの）。
func _visible_bikes() -> int:
	var count := 0
	for node: Node in get_tree().root.find_children("MamachariRig*", "Node3D", true, false):
		if (node as Node3D).is_visible_in_tree():
			count += 1
	return count


## 設定パネル（角の丸い板）の内側に収まっているか。
func _inside_panel(control: Control) -> bool:
	var node: Node = control
	while node != null and not node is PanelContainer:
		node = node.get_parent()
	return node != null and (node as Control).get_global_rect().encloses(control.get_global_rect())


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != SIZE:
		image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	image.save_png(ProjectSettings.globalize_path(OUT + label + ".png"))


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration, true).timeout


func _finish() -> void:
	GameManager.settings_path = str(_saved.path)
	PlayerSkinStore.path = str(_saved.skin_path)
	UnlockStore.path = str(_saved.unlock_path)
	UnlockStore.load_from_disk()
	PlayerSkinStore.load_into(gs)
	QuizManager.provider.set_llm_mode(str(_saved.llm))
	for user_path: String in [SETTINGS, SKINS, UNLOCKS]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(user_path))
	print("SECRET_RIDE_UI " + JSON.stringify({"passed": _failures.is_empty(), "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)

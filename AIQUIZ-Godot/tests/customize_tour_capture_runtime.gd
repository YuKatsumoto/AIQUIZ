extends Node

## カスタマイズ紹介（チュートリアルの最後）で見せる画面写真を、今のカスタマイズ画面から撮り直す。
## 設定は変えず、写真は artifacts/tutorial_v5/customize/ に保存する（差し替えは人が確認してから行う）。
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/customize_tour_capture_bootstrap.gd --fixed-fps 60
const OUT := "res://artifacts/tutorial_v5/customize/"
const NAMES := ["customize_wall_speed", "customize_skin_hat", "customize_emote"]

var _menu: Node = null


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	GameManager.settings_path = "user://customize_tour_capture_settings.json"
	var settings_hash := FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH)
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	var ready := await _wait_until(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.name == "MainMenu" and scene.get("_embedded_customize") != null, 40.0)
	if not ready:
		print("CUSTOMIZE_CAPTURE failed: menu not ready")
		get_tree().quit(1)
		return
	_menu = get_tree().current_scene
	await _wait(2.5)
	# コース選択（V5の説明・所要時間・「内容を更新しました」バッジ）も同じ実行で残しておく。
	var selector: Node = _menu.get("_tutorial_selector")
	if selector != null:
		selector.call("show_selector")
		await _wait(0.6)
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "course_selector.png"))
		selector.call("hide_selector")
		await _wait(0.3)
	_menu.call("_open_embedded_customize")
	await _wait(1.6)
	var host: Node = _menu.get("_embedded_customize")
	for index: int in range(3):
		host.call("_set_section", index)
		await _wait(1.2)
		if index == 1:
			# 帽子が見えないと紹介にならないので、効果のあるプロペラ帽を選んだ姿を撮る（保存はされない）。
			host.call("_apply_hat_change_animated", HatData.HAT_PROPELLER, 1)
			await _wait(1.4)
		await _wait(0.6)
		await RenderingServer.frame_post_draw
		var image := get_tree().root.get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path(OUT + NAMES[index] + ".png"))
	var untouched := FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH) == settings_hash
	print("CUSTOMIZE_CAPTURE " + JSON.stringify({"saved": NAMES, "settings_untouched": untouched}))
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _wait_until(condition: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if condition.call():
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return bool(condition.call())

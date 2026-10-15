extends Node

## カスタマイズ画面のスキンタブの実行時チェック。体の色はオンライン対戦専用なので、
## ここは色カスタマイズを入れる前の画面（プレイヤー1/2 と帽子だけ）であることを確かめる。
## 体の色を変えてあっても、プレビューのキャラはスロットの標準色で出る。
## 写真を artifacts/skin_editor/ に残す。保存ファイルには書かない（--fresh-profile）。
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/skin_editor_bootstrap.gd -- --fresh-profile
## 解像度を変えるとき: -- --fresh-profile size=1680x720

const OUT := "res://artifacts/skin_editor/"
const CUSTOM_CHEST := Color8(250, 210, 60)

var _failures: Array[String] = []
var _host: Node = null
var _size := Vector2i(1280, 720)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("size="):
			var parts := arg.trim_prefix("size=").split("x")
			if parts.size() == 2:
				_size = Vector2i(int(parts[0]), int(parts[1]))
	get_tree().root.size = _size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	GameManager.settings_path = "user://skin_editor_runtime_settings.json"
	PlayerSkinStore.path = "user://skin_editor_runtime_skins.json"
	var real_skins_hash := FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH)
	# オンライン用に体の色を変えてある状態（保存はしない）
	var gs := QuizManager.game_state
	for slot: int in [1, 2]:
		gs.set_player_skin(slot, PlayerSkin.set_color(PlayerSkin.default_skin(slot), &"chest", CUSTOM_CHEST))
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	var ready := await _wait_until(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.name == "MainMenu" and scene.get("_embedded_customize") != null, 40.0)
	if not ready:
		_finish(["menu not ready"])
		return
	var menu := get_tree().current_scene
	await _wait(2.0)
	menu.call("_open_embedded_customize")
	await _wait(1.4)
	_host = menu.get("_embedded_customize")
	_host.call("_set_section", 1)
	await _wait(1.6)
	var tag := "%dx%d" % [_size.x, _size.y]
	await _capture("skin_tab_" + tag)

	_check(_host.find_children("*", "SkinEditor", true, false).is_empty(), "customize has no color editor")
	_check(_host.find_child("SkinLeftPanel", true, false) == null, "no color part panel")
	var right := _host.get("_settings_panel") as Control
	_check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(0.5).encloses(right.get_global_rect()), "right panel inside the screen")
	for name: String in ["_skin_player_label", "_skin_player_btn_p1", "_skin_player_btn_p2", "_hat_prev_button", "_hat_next_button"]:
		var control := _host.get(name) as Control
		_check(control != null and control.is_visible_in_tree(), "%s is visible" % name)
	var player: PlayerController = _host.get("_preview_player")
	for slot: int in [1, 2]:
		var parts: Dictionary = player.p1_parts if slot == 1 else player.p2_parts
		if parts.is_empty():
			continue
		var chest := PlayerSkin.quantize(((parts.upper_torso as MeshInstance3D).material_override as StandardMaterial3D).albedo_color)
		var expected := PlayerSkin.quantize(PlayerSkin.part_color(PlayerSkin.default_skin(slot), &"chest"))
		_check(chest == expected, "P%d preview chest is the standard color (%s)" % [slot, chest.to_html(false)])
	# 帽子は今までどおり変えられる
	var hat_before := gs.p1_hat
	_host.call("_on_hat_next")
	await _wait(0.8)
	_check(gs.p1_hat != hat_before, "hat still changes")
	_check(PlayerSkinStore.get_hat(1) == gs.p1_hat, "hat change is kept for the next launch")
	await _capture("skin_tab_hat_" + tag)
	_host.call("_set_skin_editing_player", 2)
	await _wait(0.8)
	await _capture("skin_tab_p2_" + tag)
	_check(FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH) == real_skins_hash, "real skin file untouched")
	_finish(_failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + file_name + ".png"))


func _finish(failures: Array) -> void:
	print("SKIN_EDITOR_RUNTIME ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


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

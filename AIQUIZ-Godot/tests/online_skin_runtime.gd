extends Node

## オンライン画面の「スキン設定」の実行時チェック（リレーには つながない）。
## トップで自分のキャラの横に「スキン設定」の看板（3D）が立つか・看板をクリックするとスキン設定のページになるか・
## 色と帽子を変えると立っているキャラにすぐ映るか・けってい でトップへ戻るかを確かめ、
## 写真を artifacts/online_skin/ に残す。保存ファイルには書かない（一時パスに差し替える）。
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/online_skin_bootstrap.gd -- --fresh-profile

const OUT := "res://artifacts/online_skin/"
const DEAD_RELAY := "ws://127.0.0.1:9"

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	NetworkManager.relay_url = DEAD_RELAY
	PlayerSkinStore.path = "user://online_skin_runtime_skins.json"
	var real_skins_hash := FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH)
	var gs := QuizManager.game_state
	var saved_hat := gs.p1_hat
	get_tree().change_scene_to_file(OnlineMenu.SCENE_PATH)
	var ready := await _wait_until(func() -> bool:
		var scene := get_tree().current_scene
		return scene is OnlineMenu and (scene as OnlineMenu).current_id() == OnlineMenu.HOME, 40.0)
	if not ready:
		_finish(["online menu not ready"])
		return
	var menu := get_tree().current_scene as OnlineMenu
	await _wait(2.5)
	await _capture("home")

	var board := menu.stage.skin_sign if menu.stage != null else null
	_check(board != null and board.is_shown() and board.is_visible_in_tree(), "skin sign stands on the home page")
	if board == null:
		_finish(_failures)
		return
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var stage_scale: Vector2 = (menu.get("_stage_view") as Control).scale
	var camera := menu.stage.camera
	var chest_px: Vector2 = camera.unproject_position(menu.stage.me().center()) * stage_scale
	var sign_px: Vector2 = camera.unproject_position(board.board_center()) * stage_scale
	print("ONLINE_SKIN_SIGN ", JSON.stringify({"chest": [chest_px.x, chest_px.y], "sign": [sign_px.x, sign_px.y]}))
	_check(screen.has_point(sign_px), "skin sign inside the screen %s" % sign_px)
	_check(sign_px.x > chest_px.x + 200.0 and sign_px.x - chest_px.x < 480.0, "sign stands to the right of the character (%.0f px)" % (sign_px.x - chest_px.x))
	var right := camera.global_basis.x
	var edge_px: Vector2 = camera.unproject_position(board.board_center() + right * (OnlineSkinSign.BOARD_SIZE.x * 0.5 + OnlineSkinSign.FRAME_MARGIN)) * stage_scale
	_check(edge_px.x < screen.size.x - 8.0, "whole sign inside the screen (right edge %.0f)" % edge_px.x)
	_check(board.find_child("Sub", true, false) == null and (board.find_child("Title", true, false) as Label3D).text == "スキン設定", "sign says only スキン設定")
	_check(sign_px.x > OnlineMenu.PAGE_WIDTH + 64.0, "sign is clear of the page column")
	_check(absf(board.global_position.y - menu.stage.pad_ground.origin.y) < 0.01, "sign stands on the deck")
	# 看板を指すと光り、クリックでスキン設定が開く（本物のマウスの入力を送る）
	var motion := InputEventMouseMotion.new()
	motion.position = sign_px
	motion.global_position = sign_px
	Input.parse_input_event(motion)
	await _wait(0.3)
	_check(board.hovered, "sign lights up under the cursor")
	await _capture("home_sign_hover")
	# 看板の外（キャラの足元）を押しても開かない
	_click(Vector2(chest_px.x, chest_px.y + 40.0))
	await _wait(0.4)
	_check(menu.current_id() == OnlineMenu.HOME, "clicking beside the sign does nothing")
	var placed_at := board.global_position
	_click(sign_px)
	await _wait(0.6)
	_check(menu.current_id() == OnlineMenu.SKIN, "clicking the sign opens the skin page")
	await _wait(0.4)
	_check(board.is_shown() and board.is_visible_in_tree(), "sign stays after it is pressed")
	_check(board.global_position.distance_to(placed_at) < 0.001, "sign stays in place")
	var skin_page := menu.page(OnlineMenu.SKIN) as OnlineSkinPage
	var page_rect := skin_page.get_global_rect()
	_check(screen.encloses(page_rect), "skin page fits the screen %s" % page_rect)
	await _wait(0.6)
	await _capture("skin_page")
	if menu.stage != null:
		# カメラがキャラへ寄り、キャラはカメラの方を向く。キャラは画面の右寄り（ページにかからない）
		var closeup := menu.get("_skin_closeup") as OnlineSkinCloseup
		_check(closeup != null and closeup.weight() >= 0.999, "camera moved in for the skin page")
		var chest := menu.stage.me().center()
		_check(camera.global_position.distance_to(chest) < 6.5, "camera is close to the character (%.2f)" % camera.global_position.distance_to(chest))
		var pelvis := menu.stage.me().parts().pelvis as Node3D
		var to_camera := camera.global_position - pelvis.global_position
		to_camera.y = 0.0
		var facing := pelvis.global_basis.z
		facing.y = 0.0
		_check(facing.normalized().dot(to_camera.normalized()) > 0.97, "character faces the camera")
		var on_screen: Vector2 = camera.unproject_position(chest) * stage_scale
		_check(on_screen.x > page_rect.end.x + 40.0, "character stays right of the page (%.0f)" % on_screen.x)
		# 帽子の上から足先まで画面に入る
		var parts := menu.stage.me().parts()
		var top: Vector2 = camera.unproject_position((parts.head as Node3D).global_position + Vector3.UP * 0.6) * stage_scale
		var foot: Vector2 = camera.unproject_position((parts.l_foot as Node3D).global_position) * stage_scale
		_check(top.y > 0.0 and foot.y < screen.size.y, "whole character in view (%.0f..%.0f)" % [top.y, foot.y])
		var chest_material := ((menu.stage.me().parts().upper_torso as MeshInstance3D).material_override as StandardMaterial3D)
		_check(chest_material.next_pass != null, "whole body outline glows on the skin page")

	# 色を変えると、立っているキャラにすぐ映る
	var editor := skin_page.editor
	editor.select_part(&"chest")
	editor.call("_set_color", Color8(250, 210, 60), "")
	editor.select_part(&"l_leg")
	editor.call("_set_color", Color8(40, 200, 120), "")
	skin_page.call("_step_hat", 1)
	await _wait(0.8)
	await _capture("skin_changed")
	if menu.stage != null:
		var parts := menu.stage.me().parts()
		var chest_color := ((parts.upper_torso as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
		_check(PlayerSkin.quantize(chest_color) == Color8(250, 210, 60), "standing character chest follows the editor")
		var leg_color := ((parts.r_thigh as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
		_check(PlayerSkin.quantize(leg_color) == Color8(40, 200, 120), "standing character left leg follows the editor")
	_check(gs.p1_hat != saved_hat and PlayerSkinStore.get_hat(1) == gs.p1_hat, "hat changed and stored")
	_check(menu.call("_local_profile").skin == PlayerSkinStore.get_skin_code(1) and PlayerSkinStore.get_skin_code(1) != "", "profile sends the new skin")

	# けってい でトップへ
	(skin_page.get("_done_button") as Button).pressed.emit()
	await _wait(0.6)
	_check(menu.current_id() == OnlineMenu.HOME, "done returns home")
	await _wait(0.8)
	if menu.stage != null:
		_check((menu.get("_skin_closeup") as OnlineSkinCloseup).weight() <= 0.001, "camera goes back after editing")
		var torso := ((menu.stage.me().parts().upper_torso as MeshInstance3D).material_override as StandardMaterial3D)
		_check(torso.next_pass == null, "outline cleared after editing")
	await _capture("home_after")
	_check(board.is_shown() and board.is_visible_in_tree(), "sign comes back on the home page")
	_check(FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH) == real_skins_hash, "real skin file untouched")
	var temp := ProjectSettings.globalize_path(PlayerSkinStore.path)
	if FileAccess.file_exists(PlayerSkinStore.path):
		DirAccess.remove_absolute(temp)
	_finish(_failures)


func _finish(failures: Array) -> void:
	print("ONLINE_SKIN_RUNTIME ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _click(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = pressed
		press.position = at
		press.global_position = at
		Input.parse_input_event(press)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + file_name + ".png"))


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

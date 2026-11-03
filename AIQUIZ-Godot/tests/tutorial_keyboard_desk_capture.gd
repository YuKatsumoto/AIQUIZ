extends SceneTree

## ローカル2Pのキーボード説明（3Dの机）の構図と、キーを押したときの手の動きの確かめ。
## ウィンドウありで流して画面を撮る。
##   Godot --path . --script res://tests/tutorial_keyboard_desk_capture.gd
## 撮った画面と数値（desk_report.json）は artifacts/tutorial_keyboard_desk/。

const IntroScript = preload("res://scripts/ui/tutorial_keyboard_intro.gd")
const OUTPUT := "res://artifacts/tutorial_keyboard_desk"
## 16:9（大・小）、21:9、32:9、4:3、16:10。
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1680, 720), Vector2i(1920, 540),
	Vector2i(1024, 768), Vector2i(1280, 800)]
## 押す場面。キーは [keycode, location]。
const PRESSES := {
	"press_p1_w_d": [[KEY_W, KEY_LOCATION_UNSPECIFIED], [KEY_D, KEY_LOCATION_UNSPECIFIED]],
	"press_p1_space": [[KEY_SPACE, KEY_LOCATION_UNSPECIFIED]],
	"press_p1_emote_2": [[KEY_2, KEY_LOCATION_UNSPECIFIED]],
	"press_p2_up_right": [[KEY_UP, KEY_LOCATION_UNSPECIFIED], [KEY_RIGHT, KEY_LOCATION_UNSPECIFIED]],
	"press_p2_right_ctrl": [[KEY_CTRL, KEY_LOCATION_RIGHT]],
	"press_p2_right_ctrl_and_right": [[KEY_CTRL, KEY_LOCATION_RIGHT], [KEY_RIGHT, KEY_LOCATION_UNSPECIFIED]],
	"press_p2_emote_9": [[KEY_9, KEY_LOCATION_UNSPECIFIED]],
	"press_p2_numpad_8": [[KEY_KP_8, KEY_LOCATION_UNSPECIFIED]],
}

var _intro: Control
var _report := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.content_scale_size = Vector2i.ZERO
	root.size = SIZES[0]
	_intro = IntroScript.new()
	_intro.name = "TutorialKeyboardIntro"
	root.add_child(_intro)
	await process_frame
	_intro.show_intro("LOCAL_2P")
	_intro.set_process(false)
	for size: Vector2i in SIZES:
		root.size = size
		await _settle()
		var label := "desk_%dx%d" % [size.x, size.y]
		await _shot(label)
		_report[label] = _intro.get_evidence()
	root.size = SIZES[0]
	await _settle()
	for label: String in PRESSES:
		for key: Array in PRESSES[label]:
			_send_key(key[0], true, key[1])
		await _settle()
		await _shot(label)
		_report[label] = {"actual_keys": _intro.get_evidence().keyboard.actual_keys,
			"hands": _intro.get_evidence().desk.hands, "demo_focus": _intro.get_evidence().demo_focus}
		for key: Array in PRESSES[label]:
			_send_key(key[0], false, key[1])
		await _settle()
	_report["released"] = _intro.get_evidence().desk.hands
	# 右手が数字の列へ滑っていく途中（瞬間移動ではないことの確かめ）。
	_send_key(KEY_9, true)
	await process_frame
	_intro._process(0.06)
	await _shot("press_p2_emote_9_moving")
	_send_key(KEY_9, false)
	await _settle()
	# チュートリアル開始：カメラがモニターへ寄っていく途中と、画面いっぱいになる直前。
	_intro._next.pressed.emit()
	_intro._process(0.5)
	await _shot("enter_monitor_mid")
	_intro._process(0.8)
	await _shot("enter_monitor_near_end")
	_intro._process(0.3)
	_report["entered"] = not _intro.visible
	var file := FileAccess.open(ProjectSettings.globalize_path(OUTPUT).path_join("desk_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_intro.queue_free()
	await process_frame
	quit(0)


func _settle() -> void:
	for _frame: int in range(4):
		await process_frame
		_intro._process(0.1)


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUTPUT).path_join(label + ".png"))


func _send_key(code: int, pressed: bool, location := KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.location = location
	Input.parse_input_event(event)

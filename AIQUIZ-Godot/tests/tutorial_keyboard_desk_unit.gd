extends SceneTree

## ローカル2Pのキーボード説明（3Dの机）の手の動きの契約。ヘッドレスで流せる。
##   Godot --headless --path . --script res://tests/tutorial_keyboard_desk_unit.gd
## 見た目の確かめは tutorial_keyboard_desk_capture.gd（ウィンドウあり）。

const IntroScript = preload("res://scripts/ui/tutorial_keyboard_intro.gd")
const OUTPUT := "res://artifacts/tutorial_keyboard_desk"
## 指先がキーに届いたとみなす距離（キー1個分 = 1.0）。休めている親指は Space の上に少し浮く。
const FINGER_REACH := 0.25
const RESTING_THUMB_REACH := 0.45
## 16:9（大・小）、21:9、32:9、4:3、16:10、5:4。
const LAYOUT_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1680, 720), Vector2i(1920, 540),
	Vector2i(1024, 768), Vector2i(1280, 800), Vector2i(1280, 1024)]

var _intro: Control
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	_intro = IntroScript.new()
	_intro.name = "TutorialKeyboardIntro"
	root.add_child(_intro)
	await process_frame
	_intro.show_intro("LOCAL_2P")
	_intro.set_process(false)
	_settle()
	var evidence: Dictionary = _intro.get_evidence()
	_check(evidence.presentation == "desk_3d" and evidence.desk.key_count == 64, "Local 2P shows the 3D desk with the full keyboard")
	_check(_pose("P1") == "home" and _pose("P2") == "home", "Both hands start on their home keys")
	_check(_rests("P1", {"ring": "A", "middle": "S", "index": "D", "pinky": "ShiftL"}), "P1 rests ring, middle and index on A, S, D")
	_check(_rests("P2", {"index": "←", "middle": "↓", "ring": "→"}), "P2 rests index, middle and ring on the arrows")
	_check(_digit("P1", "thumb").key == "Space" and _digit("P1", "thumb").tip_error < RESTING_THUMB_REACH, "P1 thumb rests over Space")
	_check(_pose("P2_left") == "home" and not _hand("P2_left").in_view and _hand("P1").in_view and _hand("P2").in_view,
		"P2's left hand waits below the screen while both resting hands are in view")

	_intro._process(10.0)
	_check(_pressing("P1").is_empty() and _pressing("P2").is_empty() and _pose("P1") == "home" and _pose("P2") == "home",
		"Without input nothing presses or moves by itself")

	await _press([KEY_W, KEY_D])
	_check(_pressing("P1") == {"middle": "W", "index": "D"}, "W reaches with the middle finger while the index presses D")
	_check(_digit("P1", "middle").tip_error < FINGER_REACH and _digit("P1", "index").tip_error < FINGER_REACH, "The pressing fingertips reach W and D")
	_check("W" in _sunk() and "D" in _sunk(), "W and D sink under the fingers")
	_check(_intro.get_evidence().demo_focus in ["P1:forward_back", "P1:left_right"], "The pressed action card lights up")
	await _release([KEY_W, KEY_D])
	_check(_pressing("P1").is_empty() and _digit("P1", "middle").key == "S", "Releasing returns the middle finger to S")

	await _press([KEY_SPACE])
	_check(_pressing("P1") == {"thumb": "Space"} and _digit("P1", "thumb").tip_error < FINGER_REACH, "The P1 thumb presses Space")
	await _release([KEY_SPACE])

	await _press([KEY_2])
	_check(_pose("P1") == "numbers" and _pressing("P1") == {"middle": "2"}, "Pressing 2 moves the left hand to the number row")
	_check(_digit("P1", "middle").tip_error < FINGER_REACH, "The middle finger reaches 2")
	await _release([KEY_2])
	_check(_pose("P1") == "home", "The left hand returns home after the emote key")

	await _press([KEY_UP])
	_check(_pose("P2") == "home" and _pressing("P2") == {"middle": "↑"}, "↑ reaches with the P2 middle finger without moving the hand")
	await _release([KEY_UP])

	await _press([KEY_CTRL], KEY_LOCATION_RIGHT)
	_check(_pose("P2") == "jump" and _pressing("P2") == {"thumb": "CtrlR"}, "Right Ctrl moves the right hand so its thumb presses it")
	_check(_digit("P2", "thumb").tip_error < FINGER_REACH and _digit("P2", "index").tip_error < FINGER_REACH, "The thumb reaches right Ctrl while the index stays on ←")
	await _press([KEY_RIGHT])
	_check(_pressing("P2") == {"thumb": "CtrlR", "ring": "→"}, "Jumping while holding → keeps the ring finger on →")
	await _release([KEY_RIGHT])
	await _release([KEY_CTRL], KEY_LOCATION_RIGHT)
	_check(_pose("P2") == "home", "The right hand returns home after right Ctrl")

	await _press([KEY_CTRL], KEY_LOCATION_LEFT)
	_check(_pose("P2") == "home" and _pressing("P2").is_empty() and _pressing("P1").is_empty(), "Left Ctrl moves neither hand")
	await _release([KEY_CTRL], KEY_LOCATION_LEFT)

	await _press([KEY_RIGHT, KEY_9])
	_check(_pose("P2_left") == "numbers" and _pressing("P2_left") == {"middle": "9"} and _hand("P2_left").in_view,
		"P2 brings the left hand up to press 9")
	_check(_digit("P2_left", "middle").tip_error < FINGER_REACH, "The left middle finger reaches 9")
	_check(_pose("P2") == "home" and _pressing("P2") == {"ring": "→"}, "The right hand keeps holding → while the left hand emotes")
	await _release([KEY_RIGHT, KEY_9])
	_check(_pose("P2_left") == "home" and not _hand("P2_left").in_view, "The left hand goes back below the screen")

	await _press([KEY_KP_7])
	_check(_pose("P2_left") == "numbers" and _pressing("P2_left") == {"ring": "8"}, "Keypad 7 is shown as P2's emote key 8")
	await _release([KEY_KP_7])
	_check(_pose("P2_left") == "home", "The left hand goes back after the keypad emote")

	var desk: Dictionary = _intro.get_evidence().desk
	_check(desk.monitor_source == "placeholder" and desk.mascot, "Without the menu the monitor shows the placeholder, and Hatena stands on the desk")
	var wide_picture := ImageTexture.create_from_image(Image.create(1680, 720, false, Image.FORMAT_RGB8))
	_intro.set_monitor_texture(wide_picture)
	_intro._process(0.0)
	desk = _intro.get_evidence().desk
	_check(desk.monitor_source == "live" and absf(desk.monitor_crop.x - (16.0 / 9.0) / (1680.0 / 720.0)) < 0.01 and is_equal_approx(desk.monitor_crop.y, 1.0),
		"A 21:9 live picture is cropped to the 16:9 monitor")
	_intro.set_monitor_texture(ImageTexture.create_from_image(Image.create(1024, 768, false, Image.FORMAT_RGB8)))
	_intro._process(0.0)
	desk = _intro.get_evidence().desk
	_check(is_equal_approx(desk.monitor_crop.x, 1.0) and absf(desk.monitor_crop.y - 0.75) < 0.01, "A 4:3 live picture is cropped top and bottom")
	_intro.set_monitor_texture(null)
	_intro._process(0.0)
	desk = _intro.get_evidence().desk
	_check(desk.monitor_source == "placeholder" and is_equal_approx(desk.monitor_crop.x, 1.0), "Clearing the picture returns to the placeholder")

	for size: Vector2i in LAYOUT_SIZES:
		root.size = size
		await process_frame
		_intro._process(0.0)
		_check(_layout_fits(), "At %dx%d the 3D keyboard stays on screen and clear of the cards and buttons" % [size.x, size.y])
		var wide := float(size.x) / size.y >= 16.0 / 9.0 - 0.001
		_check(_intro.get_evidence().desk.keep_aspect == ("height" if wide else "width"),
			"At %dx%d the camera keeps the 16:9 framing inside the screen" % [size.x, size.y])
	root.size = LAYOUT_SIZES[0]
	await process_frame
	_intro._process(0.0)

	_intro._keyboard.set_reduced_motion(true)
	await _press([KEY_W, KEY_2])
	_check(_pose("P1") == "home" and _pressing("P1").is_empty(), "Reduced motion keeps the hand still")
	_check("W" in _sunk() and "2" in _sunk(), "Reduced motion still sinks the pressed keys")
	await _release([KEY_W, KEY_2])
	_intro._keyboard.set_reduced_motion(false)

	_intro._next.pressed.emit()
	_intro.show_intro("SOLO")
	_intro.set_process(false)
	_check(_intro.get_evidence().presentation == "flat" and not _intro._desk_3d.visible, "Solo keeps the flat keyboard")

	var report := {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(ProjectSettings.globalize_path(OUTPUT).path_join("desk_unit_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TUTORIAL_KEYBOARD_DESK_UNIT " + JSON.stringify(report))
	_intro.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


## 手が新しい置き方に落ち着くまで進める（HAND_SPEED で 0.5 秒 × 3 なら十分）。
func _settle() -> void:
	for _step: int in range(3):
		_intro._process(0.5)


func _press(codes: Array, location := KEY_LOCATION_UNSPECIFIED) -> void:
	for code: int in codes:
		_send_key(code, true, location)
	await process_frame
	_settle()


func _release(codes: Array, location := KEY_LOCATION_UNSPECIFIED) -> void:
	for code: int in codes:
		_send_key(code, false, location)
	await process_frame
	_settle()


## label は "P1"（左手）、"P2"（右手）、"P2_left"（P2のエモート用の左手）。
func _hand(label: String) -> Dictionary:
	return _intro.get_evidence().desk.hands[label]


func _pose(label: String) -> String:
	return str(_hand(label).pose)


func _pressing(label: String) -> Dictionary:
	return _hand(label).pressing


func _digit(label: String, digit_name: String) -> Dictionary:
	return _hand(label).digits.get(digit_name, {"key": "", "tip_error": INF})


func _sunk() -> Array:
	return _intro.get_evidence().desk.sunk_keys


## 3Dのキーボードが画面に収まり、説明カード・開始ボタン・Esc ボタンのどれとも重ならない。
func _layout_fits() -> bool:
	var view := Rect2(Vector2.ZERO, Vector2(root.size))
	var evidence: Dictionary = _intro.get_evidence()
	var keyboard: Rect2 = evidence.keyboard_rect
	if not view.encloses(keyboard):
		return false
	var others: Array[Rect2] = [_intro._next.get_global_rect(), _intro._close.get_global_rect()]
	for label: Dictionary in evidence.action_labels:
		others.append(label.rect)
	for rect: Rect2 in others:
		if not view.encloses(rect) or rect.intersects(keyboard):
			return false
	return true


func _rests(label: String, expected: Dictionary) -> bool:
	for digit_name: String in expected:
		var digit := _digit(label, digit_name)
		if digit.key != expected[digit_name] or digit.tip_error >= FINGER_REACH:
			return false
	return true


func _send_key(code: int, pressed: bool, location := KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.location = location
	Input.parse_input_event(event)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error(description)

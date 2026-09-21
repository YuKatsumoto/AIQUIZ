extends SceneTree

const IntroScript = preload("res://scripts/ui/tutorial_keyboard_intro.gd")
var _intro: Control
var _checks := 0
var _failures: Array[String] = []
var _completed: Array[String] = []
var _cancel_count := 0
var _capture := false
var _captures: Array[String] = []


func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	_intro = IntroScript.new()
	_intro.name = "TutorialKeyboardIntro"
	root.add_child(_intro)
	_intro.completed.connect(func(course: String) -> void: _completed.append(course))
	_intro.cancelled.connect(func() -> void: _cancel_count += 1)
	await process_frame
	_check(not _intro.is_active(), "Intro begins hidden")
	_intro.show_intro("SOLO")
	_intro.set_process(false)
	_check(_intro.is_active() and _intro.get_evidence().page_count == 1, "Solo explains all controls on one screen")
	_check(_intro.get_evidence().players == ["P1"], "Solo shows only P1")
	_check(_intro.get_evidence().shown_actions == ["P1:left_right", "P1:forward_back", "P1:jump", "P1:emote"], "All four solo action labels remain available together")
	_check(_all_labels_visible(), "Every solo operation is simultaneously visible")
	_check(_has_keys(["A", "D", "W", "S", "Space", "1", "2", "3", "←", "→", "↑", "↓"]), "Solo highlights every real action key including arrow alternatives")
	_check(_intro.get_start_button() == _intro._next and _intro._next.text == "チュートリアル開始", "The explicit start button is available on the same screen")
	_intro._process(1.2)
	await _shot("solo_overview")
	_intro._process(3.6)
	_check(_intro.get_evidence().keyboard.demo_key == "D" and _all_labels_visible(), "Only the finger demo changes focus while every label stays visible")
	_send_key(KEY_RIGHT, true)
	await process_frame
	_intro._process(0.05)
	_check("→" in _intro.get_evidence().keyboard.actual_keys and _completed.is_empty(), "Arrow practice highlights live input without navigation or starting gameplay")
	await _shot("solo_actual_arrow")
	_send_key(KEY_RIGHT, false)
	await process_frame
	_send_key(KEY_SPACE, true)
	await process_frame
	_intro._process(0.05)
	_check(_intro.is_active() and _completed.is_empty() and _intro.get_evidence().demo_focus == "P1:jump", "Space practice highlights jump and cannot activate the focused start button")
	_send_key(KEY_SPACE, false)
	await process_frame
	_intro._pause.button_pressed = true
	_intro._toggle_pause()
	_intro._process(4.0)
	_check(_intro.get_evidence().paused and not _intro.get_evidence().keyboard.state.pressed, "Static mode stops simulated key presses")
	_send_key(KEY_W, true)
	await process_frame
	_intro._process(0.05)
	_check(_intro.get_evidence().keyboard.state.live and _intro.get_evidence().demo_focus == "P1:forward_back", "Real input remains visible while the demonstration is stopped")
	_send_key(KEY_W, false)
	await process_frame
	_intro._replay_demo()
	_intro._process(1.2)
	_check(not _intro.get_evidence().paused and _intro.get_evidence().keyboard.demo_key == "A", "Replay resumes from the first action without hiding any operations")
	_intro._process(1.5)
	_check(not _intro.get_evidence().keyboard.state.pressed and _intro.get_evidence().keyboard.header == "操作例：離す", "The demonstration includes a distinct release phase")
	await _shot("solo_release")
	_intro._process(120.0)
	_check(_intro.is_active() and _completed.is_empty() and _all_labels_visible(), "Demonstration time never navigates, hides labels, or starts practice")
	_send_key(KEY_ENTER, true)
	await process_frame
	_send_key(KEY_ENTER, false)
	await process_frame
	_check(not _intro.is_active() and _completed == ["SOLO"], "Explicit Enter on the focused start button emits the solo course")
	_intro.show_intro("LOCAL_2P")
	_intro.set_process(false)
	_check(_intro.get_evidence().page_count == 1 and _intro.get_evidence().players == ["P1", "P2"], "Duo shows both players on the same single screen")
	_check(_intro.get_evidence().shown_actions == ["P1:left_right", "P1:forward_back", "P1:jump", "P1:emote", "P2:left_right", "P2:forward_back", "P2:jump", "P2:emote"], "All eight duo operations appear together")
	_check(_all_labels_visible() and _has_keys(["A", "D", "W", "S", "Space", "1", "2", "3", "←", "→", "↑", "↓", "CtrlL", "CtrlR", "8", "9", "0"]), "Duo highlights the complete P1 and P2 physical key sets")
	_intro._process(1.2)
	await _shot("duo_overview")
	_send_key(KEY_CTRL, true, KEY_LOCATION_RIGHT)
	await process_frame
	_intro._process(0.05)
	_check("CtrlR" in _intro.get_evidence().keyboard.actual_keys and _intro.get_evidence().demo_focus == "P2:jump", "P2 live Ctrl immediately highlights P2 jump during the P1 demonstration")
	await _shot("duo_actual_ctrl")
	_send_key(KEY_CTRL, false, KEY_LOCATION_RIGHT)
	await process_frame
	_send_key(KEY_CTRL, true, KEY_LOCATION_LEFT)
	await process_frame
	_intro._process(0.05)
	_check("CtrlL" in _intro.get_evidence().keyboard.actual_keys and "CtrlR" not in _intro.get_evidence().keyboard.actual_keys, "Left Ctrl keeps its correct physical location")
	_send_key(KEY_CTRL, false, KEY_LOCATION_LEFT)
	await process_frame
	_send_key(KEY_KP_7, true)
	await process_frame
	_intro._process(0.05)
	_check(_intro.get_evidence().keyboard.state.key == "8" and _intro.get_evidence().demo_focus == "P2:emote", "P2 keypad aliases still match their actual actions")
	_send_key(KEY_KP_7, false)
	await process_frame
	_intro._replay_demo()
	_intro._process(12.0 * 3.6 + 1.2)
	_check(_intro.get_evidence().keyboard.demo_key == "CtrlR" and _all_labels_visible(), "The automatic demonstration reaches P2 while all eight labels stay visible")
	await _shot("duo_ctrl_demo")
	root.size = Vector2i(960, 540)
	await process_frame
	_intro._process(0.0)
	_check(_all_content_fits(), "The keyboard and all eight cards fit at 960 by 540")
	await _shot("duo_960")
	_intro._next.pressed.emit()
	_check(not _intro.is_active() and _completed == ["SOLO", "LOCAL_2P"], "The explicit start button emits the selected duo course")
	_intro.show_intro("SOLO")
	_intro.set_process(false)
	_intro._process(1.2)
	_check(_all_content_fits() and _all_labels_visible(), "The solo keyboard and all four cards fit at 960 by 540")
	await _shot("solo_960")
	_send_key(KEY_ESCAPE, true)
	await process_frame
	_check(not _intro.is_active() and _cancel_count == 1, "Esc returns to course selection without beginning practice")
	_send_key(KEY_ESCAPE, false)
	await process_frame
	_intro.show_intro("LOCAL_2P")
	_intro.set_process(false)
	_intro._close.pressed.emit()
	_check(not _intro.is_active() and _cancel_count == 2, "The visible course-selection button cancels without starting practice")
	_check(_find_character_demo(_intro) == null and not _intro.get_evidence().uses_character_demo, "The overview contains no character action demo")
	_check(not _intro.has_method("_go_next") and not _intro.has_method("_go_back"), "The former page navigation has been removed")
	var report := {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "captures": _captures, "presentation": "single_screen_all_controls"}
	var output := ProjectSettings.globalize_path("res://artifacts/tutorial_keyboard_intro")
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join("intro_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TUTORIAL_KEYBOARD_INTRO " + JSON.stringify(report))
	_intro.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _has_keys(keys: Array) -> bool:
	var highlighted: Array = _intro.get_evidence().keyboard.highlighted_keys
	for key: String in keys:
		if key not in highlighted:
			return false
	return true


func _all_labels_visible() -> bool:
	for label: Dictionary in _intro.get_evidence().action_labels:
		if not label.visible:
			return false
	return true


func _all_content_fits() -> bool:
	var view := Rect2(Vector2.ZERO, Vector2(root.size))
	var evidence: Dictionary = _intro.get_evidence()
	if not view.encloses(evidence.deck_rect) or not view.encloses(evidence.keyboard_rect):
		return false
	for label: Dictionary in evidence.action_labels:
		if not view.encloses(label.rect) or label.rect.intersects(evidence.keyboard_rect):
			return false
	return true


func _shot(label: String) -> void:
	if not _capture:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var directory := ProjectSettings.globalize_path("res://artifacts/tutorial_keyboard_intro")
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(label + ".png")
	image.save_png(path)
	_captures.append(path)


func _find_character_demo(node: Node) -> Node:
	var script := node.get_script() as Script
	if (script and script.resource_path.ends_with("tutorial_action_demo.gd")) or node.name == "SynchronizedAction":
		return node
	for child: Node in node.get_children():
		var found := _find_character_demo(child)
		if found:
			return found
	return null


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

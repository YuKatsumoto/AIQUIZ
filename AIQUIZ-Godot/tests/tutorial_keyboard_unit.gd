extends SceneTree

## Focused keyboard contracts. Run as an independent headless process:
## godot --headless --path . --script res://tests/tutorial_keyboard_unit.gd
const KeyboardScript = preload("res://scripts/ui/tutorial_keyboard.gd")
var _keyboard: Control
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_keyboard = KeyboardScript.new()
	_keyboard.size = Vector2(620, 218)
	root.add_child(_keyboard)
	await process_frame
	_test_physical_layout()
	_test_dynamic_push_and_completion()
	await _test_shared_push_key_order()
	_test_ghost_retry_until_hit()
	await _test_real_input_priority()
	await _test_ctrl_sides_and_numpad_alias()
	_test_reduced_motion()
	await _test_charge_meter_synchronization()
	print("TUTORIAL_KEYBOARD_UNIT " + JSON.stringify({"passed": _failures.is_empty(), "checks": _checks, "failures": _failures}))
	_keyboard.queue_free()
	quit(0 if _failures.is_empty() else 1)


func _test_physical_layout() -> void:
	var a: Rect2 = _keyboard.get_key_rect("A")
	var w: Rect2 = _keyboard.get_key_rect("W")
	var s: Rect2 = _keyboard.get_key_rect("S")
	var d: Rect2 = _keyboard.get_key_rect("D")
	var space: Rect2 = _keyboard.get_key_rect("Space")
	var left: Rect2 = _keyboard.get_key_rect("←")
	var up: Rect2 = _keyboard.get_key_rect("↑")
	var down: Rect2 = _keyboard.get_key_rect("↓")
	var right: Rect2 = _keyboard.get_key_rect("→")
	_check(a.position.x < s.position.x and s.position.x < d.position.x, "A S D read from left to right")
	_check(w.position.y < s.position.y and w.position.x < s.position.x, "W lies above S with real QWERTY row staggering")
	_check(space.size.x >= a.size.x * 5.0 and space.position.y > s.position.y, "Space is a long bottom-row key")
	_check(up.position.x == down.position.x and up.position.y < down.position.y, "Up and down form the vertical stem of an inverted T")
	_check(left.position.y == down.position.y and down.position.y == right.position.y, "Left down right share the bottom row")
	_check(left.position.x < down.position.x and down.position.x < right.position.x, "Arrow directions match their actual horizontal positions")
	_check(left.position.x > _keyboard.get_key_rect("CtrlR").end.x, "Arrow cluster is separate from the main typing block")
	_check(_keyboard.get_key_rect("CtrlL").position.x < space.position.x and _keyboard.get_key_rect("CtrlR").position.x > space.end.x, "Both Ctrl keys flank the bottom row")
	_check(_keyboard.get_key_rect("1").position.y < w.position.y and _keyboard.get_key_rect("0").position.x > _keyboard.get_key_rect("9").position.x, "Number row is above letters with zero after nine")
	_keyboard.size = Vector2(930, 327)
	_check(_keyboard.get_key_rect("Space").size.is_equal_approx(space.size * 1.5), "Key geometry scales uniformly with the visual keyboard")
	_keyboard.size = Vector2(620, 218)


func _test_dynamic_push_and_completion() -> void:
	var original := {
		"step_id": "duo_push",
		"focus_task": {"id": "push", "key": "離す→押す", "player": 2},
		"players": [{"player": 2, "tasks": [{"id": "push", "key": "←", "caption": "一度離して、左を押す"}]}],
	}
	_keyboard.configure(original, true)
	_check(_keyboard.get_evidence().demo_key == "←", "Runtime push direction overrides an older flow focus copy")
	original.players[0].tasks[0].key = "→"
	_keyboard.configure(original, true)
	_check(_keyboard.get_evidence().demo_key == "→", "Same task immediately follows a changed push direction")
	_check("←" not in _keyboard.get_evidence().highlighted_keys, "Changed push direction no longer highlights the old key")
	original.players[0].tasks[0].done = true
	original.focus_task = {}
	_keyboard.configure(original, true)
	_check(_keyboard.get_evidence().demo_key.is_empty(), "Completed tasks stop the demonstration")
	_check("P2:push" in _keyboard.get_evidence().completed_tasks, "Completion remains attributed to the correct player")
	_keyboard.configure({"step_id": "duo_ghost", "tasks": [{"id": "hit", "key": "HIT", "caption": "相手に命中"}]}, true)
	_check(_keyboard.get_evidence().demo_key.is_empty(), "A result such as HIT is never drawn as an imaginary key")


func _test_real_input_priority() -> void:
	_keyboard.configure({"step_id": "move", "tasks": [
		{"id": "left", "key": "A / ←", "caption": "左へ動く"},
		{"id": "right", "key": "D / →", "caption": "右へ動く"},
	]}, false)
	_keyboard.replay_demo()
	_keyboard.advance(1.2)
	_check(_keyboard.get_action_state().key == "A" and _keyboard.get_action_state().pressed, "Visual demo presses A without injecting game input")
	_check(not Input.is_key_pressed(KEY_A), "Demonstrations never move the real player")
	_send_key(KEY_D, true)
	await process_frame
	_keyboard.advance(0.05)
	var state: Dictionary = _keyboard.get_action_state()
	_check(state.live and state.key == "D" and state.id == "right" and state.pressed, "Actual D overrides the A demonstration and selects its real action")
	_send_key(KEY_D, false)
	await process_frame
	_keyboard.advance(0.05)
	_check(_keyboard.get_action_state().live and not _keyboard.get_action_state().pressed, "Releasing a real key is visible before the demo resumes")
	_send_key(KEY_K, true)
	await process_frame
	_keyboard.advance(0.05)
	_check(_keyboard.get_action_state().live and not _keyboard.get_action_state().pressed and _keyboard.get_action_state().id.is_empty(), "An unrelated key cannot animate a stale demonstrated action")
	_send_key(KEY_K, false)
	await process_frame
	_keyboard.advance(0.7)
	_check(not _keyboard.get_action_state().live, "Demonstration resumes after real input settles")


func _test_shared_push_key_order() -> void:
	var model := {"step_id": "duo_push", "focus_task": {"id": "brace", "player": 1}, "players": [
		{"player": 1, "tasks": [{"id": "brace", "key": "D", "caption": "踏ん張る"}, {"id": "push", "key": "D", "caption": "一押し"}]},
		{"player": 2, "tasks": [{"id": "brace", "key": "←", "caption": "踏ん張る"}, {"id": "push", "key": "←", "caption": "一押し"}]},
	]}
	_keyboard.configure(model, true)
	_send_key(KEY_D, true)
	_send_key(KEY_LEFT, true)
	await process_frame
	_keyboard.advance(0.05)
	_check(_keyboard.get_action_state().id == "brace", "Shared push keys show brace while the hold task is unfinished")
	_check(_keyboard.get_action_state().player == 1, "Simultaneous input preserves the current focused player's instruction")
	_send_key(KEY_D, false)
	await process_frame
	_keyboard.advance(0.05)
	_check(_keyboard.get_action_state().player == 2 and _keyboard.get_action_state().id == "brace", "P2's shared key also retains brace before push")
	_send_key(KEY_LEFT, false)
	await process_frame
	model.players[0].tasks[0].done = true
	model.players[1].tasks[0].done = true
	model.focus_task = {"id": "push", "player": 1}
	_keyboard.configure(model, true)
	_send_key(KEY_D, true)
	await process_frame
	_keyboard.advance(0.05)
	_check(_keyboard.get_action_state().id == "push", "After brace completes the same physical key correctly becomes push")
	_send_key(KEY_D, false)
	await process_frame
	_keyboard.advance(0.7)


func _test_ghost_retry_until_hit() -> void:
	var model := {"step_id": "duo_ghost", "lesson_kind": "ghost", "focus_task": {"id": "hit", "player": 2}, "players": [{"player": 2, "tasks": [
		{"id": "aim", "key": "矢印", "caption": "ねらう", "done": true},
		{"id": "charge", "key": "Ctrl", "caption": "長押し→離す", "done": true},
		{"id": "hit", "key": "HIT", "caption": "当てる", "done": false},
	]}]}
	_keyboard.configure(model, true)
	_keyboard.replay_demo()
	_keyboard.advance(1.2)
	var evidence: Dictionary = _keyboard.get_evidence()
	_check(not evidence.all_tasks_complete and evidence.header != "操作完了", "A missed ghost charge cannot report lesson completion")
	_check(evidence.demo_key in ["←", "↑", "↓", "→"] and evidence.state.id == "aim", "Pending HIT demonstrates a real aiming key again")
	_check("P2:aim" in evidence.completed_tasks and "P2:charge" in evidence.completed_tasks, "Retry guidance preserves the flow's already completed aim and charge")
	_keyboard.advance(3.6)
	_keyboard.configure(model, true)
	evidence = _keyboard.get_evidence()
	_check(evidence.demo_key == "CtrlR" and evidence.state.id == "charge" and evidence.state.pressed, "Retry alternates into a charge hold without configure resetting its clock")
	_keyboard.advance(1.6)
	_check(not _keyboard.get_action_state().pressed and _keyboard.get_evidence().header == "操作例：離す", "The retry charge visibly releases before aiming again")
	model.players[0].tasks[2].done = true
	model.focus_task = {}
	_keyboard.configure(model, true)
	_check(_keyboard.get_evidence().all_tasks_complete and _keyboard.get_evidence().header == "操作完了", "Only a confirmed HIT completes the ghost lesson")
	_check(_keyboard.get_evidence().demo_key.is_empty(), "Confirmed HIT stops the retry demonstration")
	_keyboard.configure({"step_id": "result_only", "tasks": [{"id": "hit", "key": "HIT", "done": false}]}, true)
	_check(_keyboard.get_evidence().header != "操作完了", "A non-key result task never implies success merely because focus is empty")


func _test_charge_meter_synchronization() -> void:
	_keyboard.configure({"step_id": "ghost_popup", "tasks": [{"id": "charge", "player": 2, "key": "Ctrl", "caption": "長押し→離す"}]}, true)
	_keyboard.replay_demo()
	_keyboard.set_demonstration_override({"pressed": true, "phase": 0.5})
	_keyboard.advance(0.05)
	_check(_keyboard.get_action_state().pressed and is_equal_approx(_keyboard.get_action_state().phase, 0.5), "External meter hold synchronizes the demonstrated key and phase")
	_keyboard.set_demonstration_override({"pressed": false, "phase": 0.8})
	_keyboard.advance(0.05)
	_check(not _keyboard.get_action_state().pressed and _keyboard.get_evidence().header == "操作例：離す", "External meter release synchronizes the key and release instruction")
	_send_key(KEY_CTRL, true, KEY_LOCATION_RIGHT)
	await process_frame
	_keyboard.advance(0.05)
	_check(_keyboard.get_action_state().live and _keyboard.get_action_state().pressed, "Real Ctrl overrides an external visual release")
	_send_key(KEY_CTRL, false, KEY_LOCATION_RIGHT)
	await process_frame
	_keyboard.advance(0.7)
	_keyboard.set_reduced_motion(true)
	_keyboard.set_demonstration_override({"pressed": true, "phase": 0.5})
	_check(not _keyboard.get_action_state().pressed, "Reduced motion also suppresses externally synchronized repeated presses")
	_keyboard.set_reduced_motion(false)
	_keyboard.set_demonstration_override({})
	_keyboard.replay_demo()
	_keyboard.advance(1.2)
	_check(_keyboard.get_action_state().pressed, "Clearing synchronization restores the normal demonstration clock")


func _test_ctrl_sides_and_numpad_alias() -> void:
	_keyboard.configure({"step_id": "duo_jump", "players": [{"player": 2, "tasks": [{"id": "jump", "key": "Ctrl", "caption": "ジャンプ"}]}]}, true)
	_send_key(KEY_CTRL, true, KEY_LOCATION_LEFT)
	await process_frame
	_keyboard.advance(0.05)
	_check("CtrlL" in _keyboard.get_evidence().actual_keys and "CtrlR" not in _keyboard.get_evidence().actual_keys, "Physical left Ctrl appears on the left while retaining the shared jump action")
	_send_key(KEY_CTRL, false, KEY_LOCATION_LEFT)
	await process_frame
	_keyboard.advance(0.05)
	_send_key(KEY_CTRL, true, KEY_LOCATION_RIGHT)
	await process_frame
	_keyboard.advance(0.05)
	_check("CtrlR" in _keyboard.get_evidence().actual_keys and _keyboard.get_action_state().player == 2, "Right Ctrl belongs to P2 as well")
	_send_key(KEY_CTRL, false, KEY_LOCATION_RIGHT)
	await process_frame
	_keyboard.advance(0.05)
	_keyboard.configure({"step_id": "emote", "players": [{"player": 2, "tasks": [{"id": "emote", "key": "8 / 9 / 0", "caption": "踊る"}]}]}, true)
	_send_key(KEY_KP_7, true)
	await process_frame
	_keyboard.advance(0.05)
	_check(_keyboard.get_action_state().live and _keyboard.get_action_state().key == "8" and _keyboard.get_action_state().id == "emote", "P2 keypad seven reports the same action as eight, matching gameplay")
	_send_key(KEY_KP_7, false)
	await process_frame
	_keyboard.advance(0.7)


func _test_reduced_motion() -> void:
	_keyboard.configure({"step_id": "jump", "tasks": [{"id": "jump", "key": "Space", "caption": "ジャンプ"}]}, false)
	_keyboard.set_reduced_motion(true)
	_keyboard.replay_demo()
	_keyboard.advance(1.3)
	_check(_keyboard.get_evidence().reduced_motion and not _keyboard.get_action_state().pressed, "Reduced motion removes repeated automatic key pressing")
	_check("Space" in _keyboard.get_evidence().highlighted_keys and _keyboard.get_evidence().demo_key == "Space", "Reduced motion preserves the key-location explanation")
	_keyboard.set_reduced_motion(false)
	_keyboard.replay_demo()
	_keyboard.advance(1.3)
	_check(_keyboard.get_action_state().pressed, "Re-enabling motion restores the visual press sequence")


func _send_key(code: int, pressed: bool, location: int = KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.location = location
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error(description)

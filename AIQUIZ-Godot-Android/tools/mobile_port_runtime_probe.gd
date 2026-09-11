extends Node

## Android port acceptance probe.
## Runs the real gameplay scene with the Mobile renderer, proves that the
## touch controller is present and that local P2 is driven by the CPU, then
## saves the rendered viewport for visual inspection.

const OUTPUT_PATH := "res://build/mobile-port-runtime.png"
const GAME_SCENE := "res://scenes/game_world.tscn"


func _ready() -> void:
	# Keep the runner outside current_scene so changing to the real gameplay
	# scene does not free the coroutine that gathers the evidence.
	get_tree().current_scene = null
	reparent(get_tree().root)
	call_deferred("_run")


func _run() -> void:
	for _frame: int in range(4):
		await get_tree().process_frame

	if QuizManager == null:
		_fail("autoload_ready", "QuizManager=null")
		return
	var state: QuizGameState = QuizManager.game_state
	state.reset_to_menu()
	state.mode = Constants.MODE_TEN
	QuizManager.provider.set_llm_mode("OFFLINE")
	state.llm_mode = "OFFLINE"
	state.num_players = 2
	state.start_game()

	var change_error := get_tree().change_scene_to_file(GAME_SCENE)
	if change_error != OK:
		_fail("scene_change", "code=%d" % change_error)
		return
	await get_tree().scene_changed
	var world := get_tree().current_scene
	if world == null:
		_fail("scene_ready", "current_scene=null")
		return

	# Allow the authored world, HUD, controller, characters, and transition to
	# finish their normal startup before collecting evidence.
	for _frame: int in range(360):
		await get_tree().process_frame

	if state.current_quiz == null:
		_fail("quiz_ready", "current_quiz=null state=%s" % state.game_state)
		return

	# Enter active play without removing any runtime systems. The probe keeps
	# the normal question/wall produced by the offline game boot.
	state.game_state = Constants.STATE_PLAYING
	state.player_x = 0.0
	state.player_z = 0.0
	state.player2_x = -1.5
	state.player2_z = 0.0
	state.player_y = 0.0
	state.player2_y = 0.0
	state.p1_alive = true
	state.p2_alive = true
	state.choice_locked = false
	state.state_changed.emit(state.game_state)
	await get_tree().process_frame
	var touch_checks: Dictionary = await _exercise_multitouch(world)

	var before := Vector2(state.player2_x, state.player2_z)
	for _frame: int in range(120):
		await get_tree().process_frame
	var after := Vector2(state.player2_x, state.player2_z)
	var report: Dictionary = world.call("get_mobile_port_report")
	var controller_report: Dictionary = report.get("controller", {})
	var cpu_report: Dictionary = report.get("cpu", {})
	var last_input: Dictionary = report.get("last_cpu_input", {})

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var capture := get_viewport().get_texture().get_image()
	var image_error := capture.save_png(OUTPUT_PATH)

	var cpu_motion := before.distance_to(after)
	var controller_available := bool(controller_report.get("available", false))
	var cpu_enabled := bool(report.get("cpu_enabled", false))
	var cpu_available := bool(cpu_report.get("available", false))
	var cpu_axis: Vector2 = last_input.get("axis", Vector2.ZERO) as Vector2
	var checks := {
		"mobile_profile": bool(report.get("mobile_profile", false)),
		"controller_available": controller_available,
		"controller_visible": bool(controller_report.get("visible", false)),
		"cpu_enabled": cpu_enabled,
		"cpu_available": cpu_available,
		"cpu_axis_nonzero": cpu_axis.length_squared() > 0.001,
		"cpu_motion": cpu_motion > 0.05,
		"capture_saved": image_error == OK,
		"touch_drag": bool(touch_checks.get("touch_drag", false)),
		"touch_jump": bool(touch_checks.get("touch_jump", false)),
		"multitouch_independent": bool(touch_checks.get("multitouch_independent", false)),
		"touch_release_reset": bool(touch_checks.get("touch_release_reset", false)),
	}
	var passed := true
	for key: String in checks:
		if not bool(checks[key]):
			passed = false

	print("[MobilePortProbe] checks=%s" % JSON.stringify(checks))
	print(
		"[MobilePortProbe] P2 before=%s after=%s motion=%.3f axis=%s state=%s answer=%d"
		% [before, after, cpu_motion, cpu_axis, state.game_state, state.current_quiz.a]
	)
	print("[MobilePortProbe] report=%s" % JSON.stringify(report))
	print("[MobilePortProbe] touch=%s" % JSON.stringify(touch_checks))
	print("[MobilePortProbe] capture=%s size=%s" % [OUTPUT_PATH, capture.get_size()])
	get_tree().quit(0 if passed else 2)


func _fail(check: String, detail: String) -> void:
	push_error("[MobilePortProbe] FAIL %s: %s" % [check, detail])
	get_tree().quit(2)


func _exercise_multitouch(world: Node) -> Dictionary:
	var controller: VirtualController = world.get("_mobile_controller") as VirtualController
	if controller == null:
		return {}
	var stick_center := (
		controller.joystick_base.global_position + controller.joystick_base.size * 0.5
	)
	var jump_center := (
		controller.jump_button.global_position + controller.jump_button.size * 0.5
	)

	var stick_down := InputEventScreenTouch.new()
	stick_down.index = 0
	stick_down.position = stick_center
	stick_down.pressed = true
	Input.parse_input_event(stick_down)
	var stick_drag := InputEventScreenDrag.new()
	stick_drag.index = 0
	stick_drag.position = stick_center + Vector2(56.0, 0.0)
	stick_drag.relative = Vector2(56.0, 0.0)
	Input.parse_input_event(stick_drag)
	await get_tree().process_frame
	var drag_axis := controller.get_joystick_axis()

	var jump_down := InputEventScreenTouch.new()
	jump_down.index = 1
	jump_down.position = jump_center
	jump_down.pressed = true
	Input.parse_input_event(jump_down)
	await get_tree().process_frame
	var jump_during := controller.is_jump_pressed()
	var jump_up := InputEventScreenTouch.new()
	jump_up.index = 1
	jump_up.position = jump_center
	jump_up.pressed = false
	Input.parse_input_event(jump_up)
	await get_tree().process_frame
	var axis_after_jump_release := controller.get_joystick_axis()

	var stick_up := InputEventScreenTouch.new()
	stick_up.index = 0
	stick_up.position = stick_center + Vector2(56.0, 0.0)
	stick_up.pressed = false
	Input.parse_input_event(stick_up)
	await get_tree().process_frame
	var reset_axis := controller.get_joystick_axis()
	return {
		"touch_drag": drag_axis.length_squared() > 0.01,
		"touch_jump": jump_during,
		"multitouch_independent": axis_after_jump_release.length_squared() > 0.01,
		"touch_release_reset": reset_axis.length_squared() < 0.001,
		"drag_axis": drag_axis,
		"axis_after_jump_release": axis_after_jump_release,
	}

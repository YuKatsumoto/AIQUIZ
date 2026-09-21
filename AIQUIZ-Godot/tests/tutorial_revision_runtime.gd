extends Node
## Run in the real main menu. Does not mark a course complete or alter settings.
const OUT := "res://artifacts/customize_rollback/"
var finished := false
var phase := "idle"
var checks: Array[Dictionary] = []
var failures: Array[String] = []

func run() -> void:
	name = "TutorialRevisionAcceptance"
	var menu = get_tree().current_scene
	var gs = QuizManager.game_state
	if gs.has_pending_solo_customize_tour():
		_check(false, "requires idle menu without pending user course")
		_finish()
		return
	var saved_hash := FileAccess.get_sha256("user://settings.json")
	var settings_before := _settings_snapshot(gs)
	phase = "keyboard"
	menu._tutorial_selector.hide()
	menu._start_tutorial_game("LOCAL_2P")
	await _wait(0.3)
	var intro = menu._tutorial_keyboard_intro
	_check(intro.is_active() and intro.get_evidence().page_count == 1, "single-screen keyboard retained")
	_check(intro.get_evidence().shown_actions.size() == 8, "both players still explained together")
	await _capture("keyboard_retained")
	intro._close.pressed.emit()
	menu._tutorial_selector.hide()
	phase = "restored_customize"
	menu._open_embedded_customize()
	await _wait(0.8)
	var host = menu._embedded_customize
	host.begin_tutorial_tour()
	await _wait(0.4)
	_check(not host.has_method("tutorial_live_action"), "live practice API removed")
	_check(host._tutorial_tour_active, "old introduction opens")
	var titles := ["壁速度設定", "スキン設定", "エモート設定"]
	var images := ["customize_wall_speed.png", "customize_skin_hat.png", "customize_emote.png"]
	for i: int in 3:
		_check(host._tutorial_tour_title.text == titles[i], "original page title %d" % i)
		_check(host._tutorial_tour_image.texture.resource_path.ends_with(images[i]), "original screenshot %d" % i)
		_check(not host._tutorial_tour_image.texture is ViewportTexture, "static introduction image %d" % i)
		_check(not host._tutorial_tour_next_button.disabled, "can proceed without practice %d" % i)
		await _capture("customize_%d" % i)
		if i < 2:
			await _tap(KEY_RIGHT)
	_check(host._tutorial_tour_key_legend.visible, "original P1/P2 key legend retained")
	await _tap(KEY_LEFT)
	_check(host._tutorial_tour_index == 1, "left key returns to previous page")
	await _tap(KEY_SPACE)
	_check(host._tutorial_tour_index == 2, "space advances as before")
	await _tap(KEY_ENTER)
	_check(not host._tutorial_tour_active and menu._customize_tutorial_completion_showing, "old introduction completes")
	await _capture("completion_restored")
	await _wait(4.0)
	_check(not menu._customize_tutorial_completion_showing, "completion returns normally")
	host.begin_tutorial_tour()
	await _tap(KEY_ESCAPE)
	await _wait(0.8)
	_check(not host._tutorial_tour_active and not menu._embedded_customize_open, "escape closes introduction")
	_check(_settings_snapshot(gs) == settings_before, "introduction does not change customization")
	_check(FileAccess.get_sha256("user://settings.json") == saved_hash, "saved settings and badges preserved")
	# Leave the restored introduction visible for inspection.
	menu._open_embedded_customize()
	await _wait(0.8)
	host.begin_tutorial_tour()
	await _wait(0.2)
	_finish()

func _settings_snapshot(gs: QuizGameState) -> String:
	return JSON.stringify([gs.tuning.wall_speed_override, gs.p1_hat, gs.p2_hat, gs.p1_emote_slots, gs.p2_emote_slots])

func _tap(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _wait(0.08)
	event.pressed = false
	Input.parse_input_event(event)
	await _wait(0.2)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + label + ".png")

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _check(ok: bool, label: String) -> void:
	checks.append({"passed":ok, "name":label})
	if not ok: failures.append(label)

func _finish() -> void:
	finished = true
	phase = "finished"
	FileAccess.open(OUT + "runtime_report.json", FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(), "checks":checks, "failures":failures}, "\t"))

func status() -> Dictionary:
	return {"phase":phase, "finished":finished, "checks":checks.size(), "failures":failures}

extends Node

## 画面のコーチ（PracticeCoach）だけの小さな確かめ（docs/new_tutorial/phase5_design.md 5.1・5.3）。
## ボタン・スライダーを並べた画面の上で、光っている所だけ押せる（マウスもキーボードも）、見せるだけは押せない、
## 吹き出し（早送り・残す・光っている所を避ける）、Esc、ポーズ中も動く、close で全部押せる、を確かめる。
##   Godot --path . --script tests/practice_menu_coach_bootstrap.gd -- runtime=res://tests/practice_menu_coach_unit.gd
## 撮った画面は artifacts/practice_menu/。

const OUT := "res://artifacts/practice_menu/"

var failures: Array[String] = []
var notes: Array[String] = []
var checks := 0
var presses := {}
var exits := 0
var unhandled_escapes := 0

var _screen: Control = null
var _buttons: Array[Button] = []
var _slider: HSlider = null
var _pause_layer: CanvasLayer = null
var _pause_button: Button = null


## Esc が下の画面まで届いたかを数える（コーチより先に作るので、_unhandled_input はコーチの _input のあと）
class EscapeListener extends Node:
	var owner_test: Node = null

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
			owner_test.set("unhandled_escapes", int(owner_test.get("unhandled_escapes")) + 1)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build_screen()
	await _frames(5)
	var coach := PracticeCoach.new()
	coach.name = "UnitCoach"
	add_child(coach)
	coach.exit_requested.connect(func() -> void: exits += 1)
	await _frames(3)

	await _blocks_everything_at_start(coach)
	await _clickable_target(coach)
	await _show_only_target(coach)
	await _slider_target(coach)
	await _bubbles(coach)
	await _escape(coach)
	await _paused(coach)
	await _closed(coach)
	_portrait(coach)
	_finish()


func _build_screen() -> void:
	_screen = Control.new()
	_screen.name = "UnitScreen"
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	var listener := EscapeListener.new()
	listener.owner_test = self
	add_child(listener)
	var background := ColorRect.new()
	background.color = Color(0.18, 0.32, 0.46)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(background)
	for i in range(3):
		var button := Button.new()
		button.name = "Button%d" % i
		button.text = ["A", "B", "C"][i]
		button.position = Vector2(140 + i * 300, 260)
		button.size = Vector2(220, 80)
		button.add_theme_font_size_override("font_size", 32)
		button.pressed.connect(func() -> void: presses[i] = int(presses.get(i, 0)) + 1)
		_screen.add_child(button)
		_buttons.append(button)
	for i in range(3):
		var left := _buttons[wrapi(i - 1, 0, 3)]
		var right := _buttons[wrapi(i + 1, 0, 3)]
		_buttons[i].focus_neighbor_left = _buttons[i].get_path_to(left)
		_buttons[i].focus_neighbor_right = _buttons[i].get_path_to(right)
	_slider = HSlider.new()
	_slider.name = "Slider"
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.05
	_slider.value = 0.5
	_slider.position = Vector2(340, 470)
	_slider.size = Vector2(600, 40)
	_screen.add_child(_slider)
	# ポーズ画面の代わり（layer 100、ポーズ中も動く）
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 100
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.visible = false
	add_child(_pause_layer)
	_pause_button = Button.new()
	_pause_button.name = "ResumeButton"
	_pause_button.text = "ゲームに戻る"
	_pause_button.position = Vector2(500, 580)
	_pause_button.size = Vector2(280, 70)
	_pause_button.add_theme_font_size_override("font_size", 28)
	_pause_button.pressed.connect(func() -> void: presses[&"resume"] = int(presses.get(&"resume", 0)) + 1)
	_pause_layer.add_child(_pause_button)


## 作った時から、どこも押せない（光がない）。
func _blocks_everything_at_start(coach: PracticeCoach) -> void:
	check(coach.is_active(), "the coach starts active")
	await _click(_center(_buttons[0]))
	check(_count(0) == 0, "a fresh coach blocks clicks (A pressed %d)" % _count(0))
	_buttons[0].grab_focus()
	await _frames(3)
	check(get_viewport().gui_get_focus_owner() == null, "a fresh coach keeps the focus off unlit buttons")
	_buttons[0].grab_focus.call_deferred()
	await _frames(1)
	await _tap(KEY_ENTER)
	check(_count(0) == 0, "Enter does not press an unlit button")


## 光っている所（押せる）だけ押せる：マウスもキーボードも。
func _clickable_target(coach: PracticeCoach) -> void:
	coach.focus([_buttons[1]], true)
	await _frames(4)
	check(coach.targets() == [_buttons[1]] and coach.is_clickable(), "B is lit and clickable")
	check(get_viewport().gui_get_focus_owner() == _buttons[1], "the lit button gets the keyboard focus")
	var hole := coach.hole_rects()[0] if not coach.hole_rects().is_empty() else Rect2()
	check(hole.encloses(_buttons[1].get_global_rect()), "the light frame surrounds B (%s)" % hole)
	check(not coach.blocks_point(_center(_buttons[1])) and coach.blocks_point(_center(_buttons[0])),
		"the coach lets clicks through only on the lit button")
	await _seconds(0.4)
	await _shot("unit_01_focus_b")
	await _click(_center(_buttons[0]))
	await _click(_center(_buttons[2]))
	check(_count(0) == 0 and _count(2) == 0, "A and C are not pressed (%d, %d)" % [_count(0), _count(2)])
	await _click(_center(_buttons[1]))
	check(_count(1) == 1, "the lit B is pressed by the mouse (%d)" % _count(1))
	await _tap(KEY_ENTER)
	check(_count(1) == 2, "the lit B is pressed by Enter (%d)" % _count(1))
	await _tap(KEY_RIGHT)
	check(get_viewport().gui_get_focus_owner() == _buttons[1], "arrow keys do not move the focus to an unlit button")
	await _tap(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == _buttons[1], "Tab does not move the focus to an unlit button")
	# 光っている2つの間は矢印で移れる
	coach.focus([_buttons[1], _buttons[2]], true)
	await _frames(3)
	await _tap(KEY_RIGHT)
	check(get_viewport().gui_get_focus_owner() == _buttons[2], "arrows move between two lit buttons")
	await _tap(KEY_RIGHT)
	check(get_viewport().gui_get_focus_owner() == _buttons[2], "arrows stop at the last lit button (A is unlit)")
	# grab_focus = false：押せるがフォーカスは取らない（Enter は早送り）
	get_viewport().gui_release_focus()
	coach.focus([_buttons[2]], true, false)
	await _frames(3)
	check(get_viewport().gui_get_focus_owner() == null, "grab_focus = false leaves the focus alone")
	await _click(_center(_buttons[2]))
	check(_count(2) == 1, "C is still clickable without the focus (%d)" % _count(2))


## 見せるだけ（clickable = false）：光っていても押せない。
func _show_only_target(coach: PracticeCoach) -> void:
	coach.focus([_buttons[1]], false)
	await _frames(4)
	var before := _count(1)
	check(get_viewport().gui_get_focus_owner() == null, "a show-only light takes the focus away")
	await _click(_center(_buttons[1]))
	await _tap(KEY_ENTER)
	check(_count(1) == before, "a show-only lit button cannot be pressed (%d)" % _count(1))
	check(coach.blocks_point(_center(_buttons[1])), "a show-only light blocks clicks")


## スライダー：光っている間は動かせる（マウスでも矢印キーでも）。
func _slider_target(coach: PracticeCoach) -> void:
	coach.focus([_slider], true)
	await _frames(4)
	check(get_viewport().gui_get_focus_owner() == _slider, "the lit slider gets the focus")
	var rect := _slider.get_global_rect()
	await _drag(rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.5), rect.position + Vector2(rect.size.x * 0.9, rect.size.y * 0.5))
	check(_slider.value > 0.75, "the lit slider can be dragged (%.2f)" % _slider.value)
	var value := _slider.value
	await _tap(KEY_LEFT)
	check(_slider.value < value, "arrow keys move the lit slider (%.2f -> %.2f)" % [value, _slider.value])
	await _shot("unit_02_focus_slider")


## 吹き出し：時間で消える・Enter で早送り・hold は残る・光っている所を避ける。
func _bubbles(coach: PracticeCoach) -> void:
	coach.focus([_buttons[1]], false)
	# ハテナが光っている B のすぐ下にいる：頭の真上に出すと B にかかるので、横へずらす
	var anchor := _center(_buttons[1]) + Vector2(0.0, _buttons[1].size.y * 0.5 + 60.0)
	coach.set_anchor(func() -> Vector2: return anchor)
	var done := [false]
	coach.say("c2.menu.1").connect(func() -> void: done[0] = true, CONNECT_ONE_SHOT)
	await _seconds(0.3)
	check(coach.bubble_text() == PracticeTexts.get_text("c2.menu.1"), "say takes a PracticeTexts id (%s)" % coach.bubble_text())
	var bubble := coach.find_child("CoachBubble", true, false) as Control
	var lit := coach.hole_rects()[0] if not coach.hole_rects().is_empty() else Rect2()
	check(bubble != null and not bubble.get_global_rect().intersects(lit), "the bubble stays off the lit button (%s vs %s)" % [bubble.get_global_rect() if bubble else Rect2(), lit])
	await _shot("unit_03_bubble")
	await _tap(KEY_ENTER)
	await _frames(2)
	check(done[0] and coach.bubble_text().is_empty(), "Enter fast-forwards an explanation bubble")
	# 時間で消える（台本①の 1.2：「ここが メニュー！」は 1.8 秒）
	var timed := [false]
	coach.say("ここが メニュー！").connect(func() -> void: timed[0] = true, CONNECT_ONE_SHOT)
	await _seconds(1.0)
	check(not timed[0] and not coach.bubble_text().is_empty(), "the bubble stays for its time")
	await _seconds(1.1)
	check(timed[0] and coach.bubble_text().is_empty(), "the bubble goes away after its time")
	# hold：時間が過ぎても残り、早送りもしない
	var held := [false]
	coach.say("c2.menu.7", 0.3, true).connect(func() -> void: held[0] = true, CONNECT_ONE_SHOT)
	await _tap(KEY_ENTER)
	await _seconds(0.5)
	check(held[0] and coach.bubble_text() == PracticeTexts.get_text("c2.menu.7"), "a held bubble stays after its time")
	coach.hide_bubble()
	check(coach.bubble_text().is_empty(), "hide_bubble removes the held bubble")
	# 画面の端で止める
	coach.set_anchor(func() -> Vector2: return Vector2(1270.0, 30.0))
	coach.say("c2.menu.11")
	await _frames(3)
	var view := get_viewport().get_visible_rect()
	check(bubble != null and view.encloses(bubble.get_global_rect()), "the bubble stops at the screen edge (%s)" % [bubble.get_global_rect() if bubble else Rect2()])
	coach.hide_bubble()
	coach.set_anchor(Callable())


## Esc：exit_requested。pass_escape が false なら下の画面には渡さない。
func _escape(coach: PracticeCoach) -> void:
	var exits_before := exits
	var unhandled_before := unhandled_escapes
	await _tap(KEY_ESCAPE)
	check(exits == exits_before + 1, "Esc asks to leave the coach")
	check(unhandled_escapes == unhandled_before, "Esc does not reach the screen below by default")
	coach.pass_escape = true
	await _tap(KEY_ESCAPE)
	check(exits == exits_before + 2 and unhandled_escapes == unhandled_before + 1, "pass_escape hands Esc to the screen below too")
	coach.pass_escape = false


## ポーズ中も動く：ポーズ画面（layer 100）の光っているボタンを押せて、吹き出しの時間も進む。
func _paused(coach: PracticeCoach) -> void:
	_pause_layer.visible = true
	get_tree().paused = true
	coach.focus([_pause_button], true)
	await _frames(4)
	check(get_viewport().gui_get_focus_owner() == _pause_button, "the lit pause button gets the focus while paused")
	await _click(_center(_buttons[0]))
	check(_count(0) == 0, "unlit buttons stay blocked while paused")
	await _click(_center(_pause_button))
	check(int(presses.get(&"resume", 0)) == 1, "the lit pause button is pressed while paused")
	var done := [false]
	coach.say("c2.pause.2", 0.4).connect(func() -> void: done[0] = true, CONNECT_ONE_SHOT)
	await _seconds_always(0.7)
	check(done[0], "the bubble time runs while paused")
	await _shot("unit_04_paused")
	get_tree().paused = false
	_pause_layer.visible = false


## close：光も暗い幕も消え、全部押せる。
func _closed(coach: PracticeCoach) -> void:
	coach.close()
	await _seconds(0.35)
	check(not coach.is_active() and coach.targets().is_empty(), "close ends the coach")
	await _click(_center(_buttons[0]))
	check(_count(0) == 1, "after close, A is clickable again (%d)" % _count(0))
	_buttons[0].grab_focus()
	await _frames(2)
	await _tap(KEY_ENTER)
	check(_count(0) == 2, "after close, Enter presses the focused button (%d)" % _count(0))
	var exits_before := exits
	await _tap(KEY_ESCAPE)
	check(exits == exits_before, "a closed coach ignores Esc")
	var shade := coach.find_child("CoachShade", true, false) as CanvasItem
	check(shade != null and not shade.visible, "the shade is hidden after close")
	# また光らせると始まる
	coach.focus([_buttons[2]], true)
	await _frames(3)
	check(coach.is_active() and coach.blocks_point(_center(_buttons[0])), "focus after close restarts the coach")
	coach.close()


func _portrait(coach: PracticeCoach) -> void:
	coach.show_portrait(true)
	if not ResourceLoader.exists(PracticeCoach.PORTRAIT_PATH):
		check(coach.portrait() == null, "without C's portrait script the coach shows no portrait")
		notes.append("C の HatenaPortrait（%s）がまだないので、小窓なしで確かめた" % PracticeCoach.PORTRAIT_PATH)
	else:
		check(coach.portrait() != null, "the coach makes C's portrait")
	coach.show_portrait(false)
	coach.close()


# ---------- 道具 ----------

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _count(index: Variant) -> int:
	return int(presses.get(index, 0))


func _center(control: Control) -> Vector2:
	var xform := control.get_global_transform_with_canvas()
	return xform * (control.size * 0.5)


func _to_window(point: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * point


func _mouse_motion(point: Vector2, mask: int) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = _to_window(point)
	motion.global_position = motion.position
	motion.button_mask = mask
	Input.parse_input_event(motion)


func _mouse_button(point: Vector2, pressed: bool) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = _to_window(point)
	button.global_position = button.position
	button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(button)


func _click(point: Vector2) -> void:
	_mouse_motion(point, 0)
	await _frames(2)
	_mouse_button(point, true)
	await _frames(2)
	_mouse_button(point, false)
	await _frames(3)


func _drag(from: Vector2, to: Vector2) -> void:
	_mouse_motion(from, 0)
	await _frames(2)
	_mouse_button(from, true)
	await _frames(2)
	for i in range(1, 6):
		_mouse_motion(from.lerp(to, i / 5.0), MOUSE_BUTTON_MASK_LEFT)
		await _frames(1)
	_mouse_button(to, false)
	await _frames(3)


func _tap(keycode: Key) -> void:
	_key(keycode, true)
	await _frames(2)
	_key(keycode, false)
	await _frames(2)


func _key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _seconds_always(duration: float) -> void:
	await get_tree().create_timer(duration, true).timeout


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + ".png"))


func _finish() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes}
	print("PRACTICE_COACH_UNIT " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

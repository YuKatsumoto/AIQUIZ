extends SceneTree

## チュートリアルの開始画面（V7: コース選択と操作キーの説明を1画面にまとめたもの）の契約。
## - コースを選ぶと右のキーボードと操作の説明がそのコースのキーに切り替わる。
## - 操作の説明のキーは、実際の配列どおりの並び（W の下に A S D、横長の Space、1 2 3 の横並び）。
## - 練習用のキーでは開始しない。Enter（はじめる）で開始、Esc で閉じる。
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/tutorial_course_selector_unit.gd
## 画面も撮るとき（描画が要るので --headless を外す）:
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_course_selector_unit.gd -- --capture

## autoload（GameManager）を使うので、preload ではなく起動後に load する。
const SELECTOR_PATH := "res://scripts/ui/tutorial_course_selector.gd"
const OUT := "res://artifacts/tutorial_v7/course_select"

var _selector: Control
var _checks := 0
var _failures: Array[String] = []
var _selected: Array[String] = []
var _dismissed := 0
var _capture := false
var _captures: Array[String] = []


func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	_selector = (load(SELECTOR_PATH) as Script).new()
	_selector.name = "TutorialCourseSelector"
	root.add_child(_selector)
	_selector.course_selected.connect(func(course: String) -> void: _selected.append(course))
	_selector.dismissed.connect(func() -> void: _dismissed += 1)
	await process_frame
	_check(not _selector.is_active(), "Selector begins hidden")

	_selector.show_selector()
	_selector.set_process(false)
	_selector._process(0.3)
	await process_frame
	var evidence: Dictionary = _selector.get_evidence()
	_check(evidence.active and evidence.course == "SOLO", "Selector opens on the 1P course")
	_check(_legend_ids() == ["P1:move", "P1:jump", "P1:emote"], "1P explains move, jump and emote together (%s)" % str(_legend_ids()))
	_check(_legend_caption("P1:emote") == "相手を煽ろう!!", "Emote caption invites taunting (%s)" % _legend_caption("P1:emote"))
	_check(_legend_caption("P1:move") == "矢印キーでも動ける", "1P move caption mentions the arrow keys")
	_check(_has_keys(["A", "D", "W", "S", "Space", "1", "2", "3", "←", "→", "↑", "↓"]), "1P keyboard lights every real key including the arrows")
	_check(_selector.get_start_button().text == "はじめる" and _selector.get_start_button().has_focus(), "Start button is focused")
	_check_cluster_layout("P1:move", ["W", "A", "S", "D"])
	_check_wide_space("P1:jump")
	_check_single_row("P1:emote", ["1", "2", "3"])
	await _shot("solo")

	_send_key(KEY_W, true)
	await process_frame
	_selector._process(0.05)
	_check(_selector.get_evidence().active_legend == "P1:move" and _selected.is_empty(), "W lights the move explanation without starting")
	await _shot("solo_press_w")
	_send_key(KEY_W, false)
	await process_frame
	_send_key(KEY_SPACE, true)
	await process_frame
	_selector._process(0.05)
	_check(_selector.get_evidence().active_legend == "P1:jump" and _selected.is_empty(), "Space lights jump and cannot press the focused start button")
	_send_key(KEY_SPACE, false)
	await process_frame
	_selector._process(1.0)

	var duo_card: Button = _selector._cards["LOCAL_2P"]
	duo_card.pressed.emit()
	_selector._process(0.3)
	await process_frame
	evidence = _selector.get_evidence()
	_check(evidence.course == "LOCAL_2P" and _selected.is_empty(), "Choosing the 2P card switches the keys without starting")
	_check(_legend_ids() == ["P1:move", "P1:jump", "P1:emote", "P2:move", "P2:jump", "P2:emote"], "2P explains both players (%s)" % str(_legend_ids()))
	_check(_legend_caption("P2:jump") == "左のCtrlは使えない", "P2 jump warns about the left Ctrl")
	_check(_legend_caption("P2:emote") == "相手を煽ろう!!", "P2 emote caption invites taunting")
	_check(_has_keys(["A", "D", "W", "S", "Space", "1", "2", "3", "←", "→", "↑", "↓", "CtrlR", "8", "9", "0"]), "2P keyboard lights both players' keys")
	_check("CtrlL" not in evidence.keyboard.highlighted_keys, "Left Ctrl is never lit")
	_check_cluster_layout("P2:move", ["↑", "←", "↓", "→"])
	_check_single_row("P2:emote", ["8", "9", "0"])
	await _shot("duo")
	_send_key(KEY_CTRL, true, KEY_LOCATION_RIGHT)
	await process_frame
	_selector._process(0.05)
	_check(_selector.get_evidence().active_legend == "P2:jump", "Right Ctrl lights the P2 jump explanation")
	_send_key(KEY_CTRL, false, KEY_LOCATION_RIGHT)
	await process_frame
	_selector._process(1.0)

	root.size = Vector2i(960, 540)
	await process_frame
	_selector._process(0.0)
	await process_frame
	_check(_all_content_fits(), "Everything fits at 960 by 540")
	await _shot("duo_960")
	root.size = Vector2i(1280, 720)
	await process_frame

	_selector.get_start_button().grab_focus()
	_send_key(KEY_ENTER, true)
	await process_frame
	_send_key(KEY_ENTER, false)
	await process_frame
	_check(not _selector.is_active() and _selected == ["LOCAL_2P"], "Enter on the start button starts the chosen course")

	_selector.show_selector()
	_selector.set_process(false)
	await process_frame
	_send_key(KEY_ESCAPE, true)
	await process_frame
	_send_key(KEY_ESCAPE, false)
	await process_frame
	_check(not _selector.is_active() and _dismissed == 1 and _selected.size() == 1, "Esc closes without starting")
	_selector.show_selector()
	_selector.set_process(false)
	await process_frame
	_selector._close.pressed.emit()
	_check(not _selector.is_active() and _dismissed == 2, "The close button also closes")

	var report := {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "captures": _captures}
	print("TUTORIAL_COURSE_SELECTOR " + JSON.stringify(report))
	_selector.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


# ---------- 説明のキーの並び ----------

func _legend_card(id: String) -> Control:
	for entry: Dictionary in _selector._legend_cards:
		if "P%d:%s" % [int(entry["player"]), str(entry["id"])] == id:
			return entry["card"]
	return null


func _chips(id: String) -> Dictionary:
	var found := {}
	var card := _legend_card(id)
	if card != null:
		_collect_chips(card, found)
	return found


func _collect_chips(node: Node, found: Dictionary) -> void:
	if node is TutorialKeyChip:
		var chip := node as TutorialKeyChip
		if not found.has(chip.label_text):
			found[chip.label_text] = chip
	for child: Node in node.get_children():
		_collect_chips(child, found)


## 逆T字: 上の段のキーは下の段の真ん中のキーの真上。下の段は左から順に同じ高さ。
func _check_cluster_layout(id: String, keys: Array) -> void:
	var chips := _chips(id)
	if keys.any(func(key: String) -> bool: return not chips.has(key)):
		_check(false, "%s has keys %s (got %s)" % [id, str(keys), str(chips.keys())])
		return
	var top: Rect2 = (chips[keys[0]] as Control).get_global_rect()
	var left: Rect2 = (chips[keys[1]] as Control).get_global_rect()
	var middle: Rect2 = (chips[keys[2]] as Control).get_global_rect()
	var right: Rect2 = (chips[keys[3]] as Control).get_global_rect()
	_check(absf(top.get_center().x - middle.get_center().x) < 1.5 and top.end.y <= middle.position.y + 0.5,
		"%s: %s sits right above %s" % [id, keys[0], keys[2]])
	_check(is_equal_approx(left.position.y, middle.position.y) and is_equal_approx(middle.position.y, right.position.y)
		and left.end.x <= middle.position.x and middle.end.x <= right.position.x,
		"%s: %s %s %s line up in one row" % [id, keys[1], keys[2], keys[3]])
	_check(is_equal_approx(top.size.x, middle.size.x) and is_equal_approx(left.size.x, right.size.x),
		"%s: letter keys keep one key size (not stretched)" % id)


func _check_wide_space(id: String) -> void:
	var chips := _chips(id)
	var move_chips := _chips("P1:move")
	if not chips.has("Space") or not move_chips.has("W"):
		_check(false, "%s has a Space key" % id)
		return
	var space: Rect2 = (chips["Space"] as Control).get_global_rect()
	var letter: Rect2 = (move_chips["W"] as Control).get_global_rect()
	_check(space.size.x > letter.size.x * 4.0 and is_equal_approx(space.size.y, letter.size.y), "%s: Space is wide like the real bar, with the same height" % id)


func _check_single_row(id: String, keys: Array) -> void:
	var chips := _chips(id)
	var rects: Array[Rect2] = []
	for key: String in keys:
		if not chips.has(key):
			_check(false, "%s has key %s" % [id, key])
			return
		rects.append((chips[key] as Control).get_global_rect())
	var ok := true
	for i: int in range(1, rects.size()):
		ok = ok and is_equal_approx(rects[i].position.y, rects[0].position.y) and rects[i - 1].end.x <= rects[i].position.x
		ok = ok and is_equal_approx(rects[i].size.x, rects[0].size.x)
	_check(ok, "%s: %s sit side by side at one key size" % [id, str(keys)])


# ---------- 補助 ----------

func _legend_ids() -> Array:
	var ids: Array = []
	for entry: Dictionary in _selector.get_evidence().legend:
		ids.append(entry.id)
	return ids


func _legend_caption(id: String) -> String:
	for entry: Dictionary in _selector.get_evidence().legend:
		if entry.id == id:
			return str(entry.caption)
	return ""


func _has_keys(keys: Array) -> bool:
	var highlighted: Array = _selector.get_evidence().keyboard.highlighted_keys
	for key: String in keys:
		if key not in highlighted:
			return false
	return true


func _all_content_fits() -> bool:
	var view := Rect2(Vector2.ZERO, Vector2(root.size))
	var evidence: Dictionary = _selector.get_evidence()
	if not view.grow(0.5).encloses(evidence.deck_rect) or not view.encloses(evidence.keyboard_rect):
		return false
	for entry: Dictionary in evidence.legend:
		if not entry.visible or not view.encloses(entry.rect):
			return false
	return view.encloses(_selector.get_start_button().get_global_rect())


func _shot(label: String) -> void:
	if not _capture:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(label + ".png")
	root.get_texture().get_image().save_png(path)
	_captures.append(path)


func _send_key(code: int, pressed: bool, location := KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.location = location
	Input.parse_input_event(event)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error(description)

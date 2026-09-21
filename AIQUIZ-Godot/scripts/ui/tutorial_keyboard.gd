class_name TutorialKeyboard
extends Control

## A complete, stable keyboard map: only the current lesson's keys light up.
## The demonstration is visual only; it never injects input into the game.
const DESIGN_SIZE := Vector2(620.0, 218.0)
const P1_COLOR := Color("ffa440")
const P2_COLOR := Color("51d8ec")
const INK := Color("14243b")
const TEXT := Color("eef3fa")
const MUTED := Color("a9b9cd")
const CYCLE_SECONDS := 3.6

var show_footnote := true
var _keys: Array[Dictionary] = []
var _key_by_id: Dictionary = {}
var _highlights: Dictionary = {}
var _tasks: Array[Dictionary] = []
var _focus: Dictionary = {}
var _model: Dictionary = {}
var _styles: Dictionary = {}
var _key_depth: Dictionary = {}
var _actual_keys: Array[String] = []
var _duo := false
var _reduced_motion := false
var _elapsed := 0.0
var _input_grace := 0.0
var _ctrl_left_down := false
var _ctrl_right_down := false
var _last_actual_task: Dictionary = {}
var _last_actual_key := ""
var _demonstration_override: Dictionary = {}
var _draw_fit := 1.0
var _draw_origin := Vector2.ZERO
var _text_raster_scale := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DESIGN_SIZE
	_build_layout()
	_build_styles()


func configure(model: Dictionary, duo: bool = false) -> void:
	var old_focus := "%s:%s:%s" % [str(_model.get("step_id", "")), str(_focus.get("player", 1)), str(_focus.get("id", ""))]
	_model = model.duplicate(true)
	_duo = duo
	_tasks.clear()
	_highlights.clear()
	var players: Array = model.get("players", [])
	if not players.is_empty():
		for player_variant: Variant in players:
			var player: Dictionary = player_variant
			for task_variant: Variant in player.get("tasks", []):
				var task: Dictionary = task_variant.duplicate(true)
				task["player"] = int(player.get("player", 1))
				_tasks.append(task)
	else:
		for task_variant: Variant in model.get("tasks", []):
			var task: Dictionary = task_variant.duplicate(true)
			task["player"] = int(task.get("player", 1))
			_tasks.append(task)
	_focus = {}
	for task: Dictionary in _tasks:
		for key_id: String in _task_key_ids(task):
			# Keep the first unfinished action when stages share one key.
			# In push practice, holding/brace precedes release-and-push.
			var previous: Dictionary = _highlights.get(key_id, {})
			if previous.is_empty() or (bool(previous.get("done", false)) and not bool(task.get("done", false))):
				_highlights[key_id] = task
		if _focus.is_empty() and not bool(task.get("done", false)) and not _task_key_ids(task).is_empty():
			_focus = task
	var supplied_focus: Dictionary = model.get("focus_task", {})
	if not supplied_focus.is_empty():
		# game_state can refresh a push direction in players.tasks after the flow
		# produced focus_task. Resolve identity against the current tasks so the
		# illustrated key always follows the current runtime direction.
		for task: Dictionary in _tasks:
			if str(task.get("id", "")) != str(supplied_focus.get("id", "")):
				continue
			if int(task.get("player", 1)) != int(supplied_focus.get("player", 1)):
				continue
			if not bool(task.get("done", false)) and not _task_key_ids(task).is_empty():
				_focus = task
			break
	if _focus.is_empty():
		_configure_hit_retry()
	else:
		for key_id: String in _task_key_ids(_focus):
			_highlights[key_id] = _focus
	var new_focus := "%s:%s:%s" % [str(_model.get("step_id", "")), str(_focus.get("player", 1)), str(_focus.get("id", ""))]
	if new_focus != old_focus:
		_elapsed = 0.0
		_last_actual_task = {}
		_last_actual_key = ""
		_input_grace = 0.0
	queue_redraw()


func _configure_hit_retry() -> void:
	if str(_model.get("lesson_kind", "")) != "ghost":
		return
	for task: Dictionary in _tasks:
		if str(task.get("id", "")) != "hit" or bool(task.get("done", false)):
			continue
		var player := int(task.get("player", 1))
		var retry_keys: Array[String] = []
		for action: Dictionary in _tasks:
			if int(action.get("player", 1)) != player or str(action.get("id", "")) not in ["aim", "charge"]:
				continue
			var retry := action.duplicate(true)
			retry["done"] = false
			retry["caption"] = "照準を調整" if str(action.get("id", "")) == "aim" else "長押し→離して突進"
			for key_id: String in _task_key_ids(retry):
				_highlights[key_id] = retry
				if key_id not in retry_keys:
					retry_keys.append(key_id)
		if not retry_keys.is_empty():
			# Instructional retry only; the flow's completed tasks stay untouched.
			_focus = {"id": "hit_retry", "player": player, "caption": "照準を調整 → 長押し → 離す", "retry_keys": retry_keys}
		return


func _all_tasks_complete() -> bool:
	if _tasks.is_empty():
		return false
	for task: Dictionary in _tasks:
		if not bool(task.get("done", false)):
			return false
	return true


func advance(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	_actual_keys.clear()
	var matching_task: Dictionary = {}
	var matching_key := ""
	if not Input.is_key_pressed(KEY_CTRL):
		_ctrl_left_down = false
		_ctrl_right_down = false
	for key: Dictionary in _keys:
		var key_id: String = key["id"]
		if _is_actual_key_down(key):
			_actual_keys.append(key_id)
			if _highlights.has(key_id):
				var candidate: Dictionary = _highlights[key_id]
				var is_focus := str(candidate.get("id", "")) == str(_focus.get("id", "")) and int(candidate.get("player", 1)) == int(_focus.get("player", 1))
				if matching_task.is_empty() or is_focus:
					matching_task = candidate
					matching_key = key_id
	if not _actual_keys.is_empty():
		_input_grace = 0.55
		_last_actual_task = matching_task
		_last_actual_key = matching_key if not matching_key.is_empty() else _actual_keys[0]
	else:
		_input_grace = maxf(0.0, _input_grace - maxf(delta, 0.0))
	var demo_key := _demo_key_id()
	for key: Dictionary in _keys:
		var key_id: String = key["id"]
		var pressed: bool = key_id in _actual_keys
		if _input_grace <= 0.0 and key_id == demo_key:
			pressed = _demo_is_pressed()
		var target := 1.0 if pressed else 0.0
		_key_depth[key_id] = target if _reduced_motion else move_toward(float(_key_depth.get(key_id, 0.0)), target, maxf(delta, 0.0) * 11.0)
	queue_redraw()


func replay_demo() -> void:
	_elapsed = 0.0
	_input_grace = 0.0
	_last_actual_task = {}
	_last_actual_key = ""
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	queue_redraw()


## External charge meters can share their existing press/release timeline.
## This only drives the visual example; live input always retains priority.
func set_demonstration_override(state: Dictionary) -> void:
	_demonstration_override = state.duplicate(true)
	queue_redraw()


func get_action_state() -> Dictionary:
	var live := _input_grace > 0.0
	var task: Dictionary = _last_actual_task if live else _focus
	var key := _last_actual_key if live else _demo_key_id()
	var task_id := str(task.get("id", ""))
	var caption := str(task.get("caption", ""))
	if task_id == "hit_retry":
		task_id = "charge" if key in ["CtrlR", "CtrlL", "Space"] else "aim"
		caption = "長押し→離して突進" if task_id == "charge" else "照準を調整"
	return {
		"id": task_id,
		"caption": caption,
		"player": int(task.get("player", 1)),
		"key": key,
		"pressed": (_last_actual_key in _actual_keys and not task.is_empty()) if live else _demo_is_pressed(),
		"live": live,
		"elapsed": _elapsed,
		"phase": _demo_phase(),
		"reduced_motion": _reduced_motion,
		"lesson_kind": str(_model.get("lesson_kind", "")),
	}


func get_evidence() -> Dictionary:
	var completed: Array[String] = []
	for task: Dictionary in _tasks:
		if bool(task.get("done", false)):
			completed.append("P%d:%s" % [int(task.get("player", 1)), str(task.get("id", ""))])
	return {
		"layout": "QWERTY_5_ROWS_WITH_INVERTED_T",
		"key_count": _keys.size(),
		"highlighted_keys": _highlights.keys(),
		"actual_keys": _actual_keys.duplicate(),
		"completed_tasks": completed,
		"all_tasks_complete": _all_tasks_complete(),
		"header": _header_text(),
		"focus_task": _focus.duplicate(true),
		"demo_key": _demo_key_id(),
		"input_priority": _input_grace > 0.0,
		"reduced_motion": _reduced_motion,
		"state": get_action_state(),
	}


## Local on-screen bounds, useful to locate a demonstrated key in captures.
func get_key_rect(key_id: String) -> Rect2:
	if not _key_by_id.has(key_id) or size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	var fit := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var rect: Rect2 = _key_by_id[key_id]["rect"]
	return Rect2((size - DESIGN_SIZE * fit) * 0.5 + rect.position * fit, rect.size * fit)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_CTRL or key_event.physical_keycode == KEY_CTRL:
			if key_event.location == KEY_LOCATION_LEFT:
				_ctrl_left_down = key_event.pressed
			elif key_event.location == KEY_LOCATION_RIGHT:
				_ctrl_right_down = key_event.pressed


func _is_actual_key_down(key: Dictionary) -> bool:
	var key_id: String = key["id"]
	if key_id == "CtrlL":
		return _ctrl_left_down and Input.is_key_pressed(KEY_CTRL)
	if key_id == "CtrlR":
		return Input.is_key_pressed(KEY_CTRL) and (_ctrl_right_down or not _ctrl_left_down)
	var code: int = int(key.get("code", 0))
	if code == 0:
		return false
	# Match game_world.gd, which reads logical keycodes for both players.
	if Input.is_key_pressed(code):
		return true
	if _duo and int((_highlights.get(key_id, {}) as Dictionary).get("player", 1)) == 2:
		match key_id:
			"8": return Input.is_key_pressed(KEY_KP_7)
			"9": return Input.is_key_pressed(KEY_KP_8)
			"0": return Input.is_key_pressed(KEY_KP_9)
	return false


func _task_key_ids(task: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if task.has("retry_keys"):
		for key_id: String in task["retry_keys"]:
			out.append(key_id)
		return out
	var spec := str(task.get("key", "")).strip_edges()
	spec = spec.replace(" / ", "/").replace("・", "/")
	if spec in ["矢印", "矢印キー", "←↑↓→"]:
		return ["←", "↑", "↓", "→"]
	if spec.to_upper() == "WASD":
		return ["W", "A", "S", "D"]
	for raw: String in spec.split("/", false):
		var token := raw.strip_edges()
		match token.to_lower():
			"space", "スペース", "spc": token = "Space"
			"ctrl", "control":
				out.append("CtrlR")
				out.append("CtrlL")
				continue
			"left": token = "←"
			"right": token = "→"
			"up": token = "↑"
			"down": token = "↓"
			_: token = token.to_upper() if token.length() == 1 else token
		if _key_by_id.has(token) and token not in out:
			out.append(token)
	return out


func _demo_key_id() -> String:
	var key_ids := _task_key_ids(_focus)
	if key_ids.is_empty():
		return ""
	if str(_focus.get("id", "")) == "hit_retry":
		# Alternate a real aim key with charge/release until the hit succeeds.
		var cycle := int(floor(_elapsed / CYCLE_SECONDS))
		var charge_key := "CtrlR" if "CtrlR" in key_ids else "Space"
		if cycle % 2 == 1 and charge_key in key_ids:
			return charge_key
		var aim_keys: Array[String] = []
		for key_id: String in key_ids:
			if key_id not in ["CtrlR", "CtrlL", "Space"]:
				aim_keys.append(key_id)
		return aim_keys[int(cycle / 2) % aim_keys.size()] if not aim_keys.is_empty() else key_ids[0]
	# A / left-arrow in solo mode describes alternatives, not a chord.
	if not _duo or "CtrlR" in key_ids:
		return key_ids[0]
	return key_ids[int(floor(_elapsed / CYCLE_SECONDS)) % key_ids.size()]


func _demo_phase() -> float:
	if _demonstration_override.has("phase"):
		return clampf(float(_demonstration_override["phase"]), 0.0, 1.0)
	return fmod(_elapsed, CYCLE_SECONDS) / CYCLE_SECONDS


func _demo_is_pressed() -> bool:
	if _focus.is_empty() or _reduced_motion:
		return false
	if _demonstration_override.has("pressed"):
		return bool(_demonstration_override["pressed"])
	var phase := _demo_phase()
	return phase >= 0.24 and phase < 0.68


func _build_layout() -> void:
	_add_row(44.0, 14.0, ["Esc:27", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Back:43"])
	_add_row(73.0, 14.0, ["Tab:42", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\:28"])
	_add_row(102.0, 14.0, ["Caps:49", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Enter:52"])
	_add_row(131.0, 14.0, ["ShiftL:65", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "ShiftR:67"])
	_add_row(160.0, 14.0, ["CtrlL:43", "Win:32", "AltL:34", "Space:213", "AltR:34", "Fn:30", "CtrlR:44"])
	_add_key("↑", "↑", Rect2(553, 131, 28, 23), KEY_UP)
	_add_key("←", "←", Rect2(522, 160, 28, 23), KEY_LEFT)
	_add_key("↓", "↓", Rect2(553, 160, 28, 23), KEY_DOWN)
	_add_key("→", "→", Rect2(584, 160, 28, 23), KEY_RIGHT)


func _add_row(y: float, start_x: float, specs: Array) -> void:
	var x := start_x
	for spec_variant: Variant in specs:
		var parts := str(spec_variant).split(":")
		var key_id := parts[0]
		var width := float(parts[1]) if parts.size() > 1 else 28.0
		var label := key_id
		if key_id in ["CtrlL", "CtrlR"]: label = "Ctrl"
		elif key_id in ["ShiftL", "ShiftR"]: label = "Shift"
		elif key_id in ["AltL", "AltR"]: label = "Alt"
		elif key_id == "Back": label = "⌫"
		var code := int(OS.find_keycode_from_string(label))
		if key_id in ["Fn", "Win", "Caps"]: code = 0
		_add_key(key_id, label, Rect2(x, y, width, 23.0), code)
		x += width + 3.0


func _add_key(key_id: String, label: String, rect: Rect2, code: int) -> void:
	var key := {"id": key_id, "label": label, "rect": rect, "code": code}
	_keys.append(key)
	_key_by_id[key_id] = key


func _build_styles() -> void:
	_styles["board_shadow"] = _style(Color("07101e"), Color("07101e"), 12, 0)
	_styles["board"] = _style(Color("182a43"), Color("4c627c"), 12, 1)
	_styles["bed"] = _style(Color("0c182a"), Color("233b55"), 7, 1)
	_styles["key_base"] = _style(Color("938f88"), Color("070d17"), 5, 1)
	_styles["normal"] = _style(Color("dedbd4"), Color("fbf7ed"), 4, 1)
	_styles["p1"] = _style(P1_COLOR, Color("ffe1a9"), 4, 1)
	_styles["p2"] = _style(P2_COLOR, Color("c4f8ff"), 4, 1)
	_styles["done1"] = _style(Color("96ceba"), P1_COLOR, 4, 2)
	_styles["done2"] = _style(Color("96ceba"), P2_COLOR, 4, 2)
	_styles["input"] = _style(Color("faffed"), Color("c1ff98"), 4, 2)
	_styles["focus1"] = _style(Color(1.0, 0.64, 0.25, 0.12), P1_COLOR, 7, 2)
	_styles["focus2"] = _style(Color(0.31, 0.85, 0.93, 0.12), P2_COLOR, 7, 2)


func _style(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_corner_radius_all(radius)
	result.set_border_width_all(border_width)
	return result


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_fit = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_draw_origin = (size - DESIGN_SIZE * _draw_fit) * 0.5
	_text_raster_scale = _draw_fit * maxf(get_global_transform_with_canvas().get_scale().x, 0.1)
	draw_set_transform(_draw_origin, 0.0, Vector2.ONE * _draw_fit)
	var font := get_theme_default_font()
	_draw_header(font)
	draw_style_box(_styles["board_shadow"], Rect2(1, 33, 618, 165))
	draw_style_box(_styles["board"], Rect2(1, 28, 618, 166))
	draw_style_box(_styles["bed"], Rect2(10, 40, 483, 149))
	draw_style_box(_styles["bed"], Rect2(518, 155, 98, 34))
	var demo_key := _demo_key_id()
	for key: Dictionary in _keys:
		_draw_key(font, key, demo_key)
	# The arrow cluster's empty upper-left corner deliberately stays empty.
	_draw_text(font, Vector2(516, 84), "矢印キー", 96, 12, MUTED)
	draw_line(Vector2(566, 94), Vector2(566, 119), Color("405976"), 1.0, true)
	if not demo_key.is_empty() and _input_grace <= 0.0 and not _reduced_motion:
		_draw_demo_hand(demo_key)
	var footnote := "表示されたキーを押して操作を確認できます。"
	if _highlights.has("CtrlR"):
		footnote = "Ctrl は左右どちらでも使えます。"
	elif _duo and (_highlights.has("8") or _highlights.has("9")):
		footnote = "数字キーで再生します。P2はテンキー7・8・9にも対応。"
	elif not _duo and (_highlights.has("←") or _highlights.has("↑")):
		footnote = "移動には文字キーと矢印キーのどちらも使用できます。"
	if show_footnote:
		_draw_text(font, Vector2(8, 214), footnote, 609, 12, MUTED)
	draw_set_transform(Vector2.ZERO)


func _draw_text(font: Font, at: Vector2, text: String, width: float, font_size: int, color: Color) -> void:
	# Rasterize glyphs at their final pixel size instead of enlarging a tiny
	# cached font atlas together with the keyboard's vector geometry.
	var raster_size := maxi(1, roundi(font_size * _text_raster_scale))
	draw_set_transform(_draw_origin, 0.0, Vector2.ONE * (_draw_fit / _text_raster_scale))
	draw_string(font, at * _text_raster_scale, text, HORIZONTAL_ALIGNMENT_LEFT, width * _text_raster_scale, raster_size, color)
	draw_set_transform(_draw_origin, 0.0, Vector2.ONE * _draw_fit)


func _header_text() -> String:
	var live := _input_grace > 0.0
	if live:
		return "入力中" if not _actual_keys.is_empty() else "入力解除"
	if _all_tasks_complete():
		return "操作完了"
	if _focus.is_empty():
		return "操作を継続"
	if _reduced_motion:
		return "表示されたキーを入力"
	if _demo_is_pressed():
		return "操作例：押す"
	if _demo_phase() >= 0.68:
		return "操作例：離す"
	return "操作例"


func _draw_header(font: Font) -> void:
	var headline := _header_text()
	var badge_color := Color("a2edba") if _all_tasks_complete() or _input_grace > 0.0 else P1_COLOR
	draw_circle(Vector2(9, 13), 4.0, badge_color)
	_draw_text(font, Vector2(21, 18), headline, 182, 14, TEXT)
	var state := get_action_state()
	var caption := str(state.get("caption", ""))
	var player := int(state.get("player", 1))
	if not caption.is_empty():
		caption = "P%d  %s" % [player, caption] if _duo else caption
		_draw_text(font, Vector2(192, 18), caption, 320, 14, P2_COLOR if player == 2 else P1_COLOR)
	if _duo:
		_draw_text(font, Vector2(524, 18), "P1", 28, 12, P1_COLOR)
		_draw_text(font, Vector2(576, 18), "P2", 28, 12, P2_COLOR)
	else:
		_draw_text(font, Vector2(546, 18), "キーボード", 72, 11, MUTED)


func _draw_key(font: Font, key: Dictionary, demo_key: String) -> void:
	var key_id: String = key["id"]
	var rect: Rect2 = key["rect"]
	var task: Dictionary = _highlights.get(key_id, {})
	var player := int(task.get("player", 1))
	var active := not task.is_empty()
	var depth := float(_key_depth.get(key_id, 0.0))
	var is_real := key_id in _actual_keys
	var focus_key := key_id == demo_key and _input_grace <= 0.0
	if focus_key:
		var focus_rect := rect.grow(3.0)
		focus_rect.size.y += 4.0
		draw_style_box(_styles["focus%d" % player], focus_rect)
	var base_rect := rect
	base_rect.size.y += 4.0
	draw_style_box(_styles["key_base"], base_rect)
	var top := rect
	top.position.y += depth * 3.5
	var style_name := "normal"
	if active:
		style_name = "done%d" % player if bool(task.get("done", false)) else "p%d" % player
	if is_real:
		style_name = "input"
	draw_style_box(_styles[style_name], top)
	var label: String = key["label"]
	var font_size := 13 if label.length() == 1 else 10
	if key_id == "Space":
		font_size = 12
	var raster_size := maxi(1, roundi(font_size * _text_raster_scale))
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, raster_size).x / _text_raster_scale
	var label_pos := top.position + Vector2((top.size.x - label_width) * 0.5, 16.0)
	_draw_text(font, label_pos, label, top.size.x, font_size, INK if active or is_real else Color("596171"))
	if key_id in ["F", "J"]:
		draw_line(top.position + Vector2(10, 20), top.position + Vector2(18, 20), Color("8e938f"), 1.2, true)
	if active and bool(task.get("done", false)):
		var p := top.position + Vector2(top.size.x - 8.0, 5.0)
		draw_polyline(PackedVector2Array([p + Vector2(-3, 0), p + Vector2(-1, 2), p + Vector2(3, -3)]), Color("226c4f"), 1.6, true)


func _draw_demo_hand(key_id: String) -> void:
	if not _key_by_id.has(key_id):
		return
	var rect: Rect2 = _key_by_id[key_id]["rect"]
	var phase := _demo_phase()
	var approach := smoothstep(0.0, 0.24, phase)
	var withdraw := smoothstep(0.70, 0.92, phase)
	var depth := float(_key_depth.get(key_id, 0.0))
	var tip := rect.get_center() + Vector2(3.0, 7.0 + depth * 3.5)
	tip += Vector2(6.0, 11.0) * (1.0 - approach + withdraw)
	var alpha := clampf(minf(phase / 0.12, (1.0 - phase) / 0.12), 0.0, 1.0)
	var skin := Color(1.0, 0.94, 0.81, alpha)
	var outline := Color(0.08, 0.12, 0.20, alpha)
	if _demo_is_pressed():
		draw_arc(tip, 11.0 + sin(phase * PI) * 2.0, PI, TAU, 24, Color(1.0, 1.0, 1.0, 0.75), 1.6, true)
	var points := PackedVector2Array([
		tip, tip + Vector2(4, -2), tip + Vector2(7, 0), tip + Vector2(7, 10),
		tip + Vector2(10, 8), tip + Vector2(13, 10), tip + Vector2(16, 10),
		tip + Vector2(19, 13), tip + Vector2(18, 23), tip + Vector2(14, 28),
		tip + Vector2(6, 28), tip + Vector2(1, 21), tip + Vector2(-3, 16),
		tip + Vector2(-2, 12), tip + Vector2(1, 12), tip + Vector2(3, 15),
		tip + Vector2(3, 2),
	])
	draw_colored_polygon(points, skin)
	points.append(points[0])
	draw_polyline(points, outline, 1.4, true)

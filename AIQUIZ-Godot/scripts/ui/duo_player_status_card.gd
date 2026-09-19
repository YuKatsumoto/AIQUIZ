extends Control
## Editable live HUD. Motion tracks are sampled from the supplied native AE project.

const CARD_SIZE := Vector2(188, 80)
const GHOST_CARD_SIZE := Vector2(320, 120)
const HEART_RADIUS := 10.5
const INK := Color(0.027, 0.047, 0.082, 0.96)
const TEXT := Color(0.96, 0.975, 1.0)
const MUTED := Color(0.63, 0.70, 0.80)
const WARNING := Color(1.0, 0.49, 0.37)
const MOTION_PATH := "res://assets/ui/duo_hud/motion.json"

var game_state: QuizGameState
var player_index := 1
var accent := Color.WHITE
var _motion: Dictionary
var _surface: Control
var _score_label: Label
var _score_unit: Label
var _hp_label: Label
var _delta_label: Label
var _status_label: Label
var _heart_points := PackedVector2Array()
var _panel: StyleBoxFlat
var _badge: StyleBoxFlat
var _shown_hp := 3
var _last_score := 0
var _health_events: Array[Dictionary] = []
var _entrance_time := 0.0
var _score_time := 10.0
var _flash_time := 0.0
var _clock := 0.0
var _was_visible := false
var _bursts: Array[Dictionary] = []
var _shine_time := 10.0
var _impact_time := 10.0
var _ghost_slot: Control
var _ghost_hud_active := false

func setup(gs: QuizGameState, index: int, color: Color) -> void:
	game_state = gs
	player_index = index
	accent = color
	_shown_hp = gs.get_player_hp(index)
	_last_score = _current_score()
	gs.health_changed.connect(_on_health_changed)
	var data = JSON.parse_string(FileAccess.get_file_as_string(MOTION_PATH))
	if data is Dictionary:
		_motion = data.tracks

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = CARD_SIZE
	_surface = Control.new()
	_surface.name = "AnimatedSurface"
	_surface.size = CARD_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.draw.connect(_draw_surface)
	add_child(_surface)
	_ghost_slot = Control.new()
	_ghost_slot.name = "GhostRideSlot"
	_ghost_slot.position = Vector2(0, 40)
	_ghost_slot.size = Vector2(GHOST_CARD_SIZE.x, 76)
	_ghost_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_slot.visible = false
	_surface.add_child(_ghost_slot)
	_panel = StyleBoxFlat.new()
	_panel.bg_color = INK
	_panel.set_corner_radius_all(12)
	_panel.set_border_width_all(1)
	_panel.border_color = Color(accent, 0.55)
	_panel.shadow_color = Color(0.0, 0.01, 0.025, 0.28)
	_panel.shadow_size = 3
	_panel.shadow_offset = Vector2(0, 2)
	_badge = StyleBoxFlat.new()
	_badge.bg_color = accent
	_badge.set_corner_radius_all(6)
	_score_label = _label("Score", str(_last_score), Vector2(50, 2), Vector2(98, 30), 25, TEXT)
	_score_label.pivot_offset = Vector2(0, 18)
	_score_unit = _label("ScoreUnit", "correct" if game_state.use_english_ui else "正解", Vector2(77, 19), Vector2(44, 15), 10, MUTED)
	_label("Player", "P%d" % player_index, Vector2(10, 10), Vector2(30, 22), 13, INK, true)
	_label("HPHeading", "HP", Vector2(10, 45), Vector2(27, 23), 11, MUTED)
	_hp_label = _label("HP", "3 / 3", Vector2(127, 45), Vector2(49, 23), 12, TEXT, true)
	_delta_label = _label("ScoreDelta", "+1", Vector2(48, -27), Vector2(68, 25), 21, accent, true)
	_delta_label.add_theme_color_override("font_outline_color", INK)
	_delta_label.add_theme_constant_override("outline_size", 3)
	_delta_label.visible = false
	_status_label = _label("Status", "", Vector2(121, 61), Vector2(60, 14), 10, WARNING, true)
	for i in range(64):
		var t := TAU * float(i) / 64.0
		_heart_points.append(Vector2(16.0 * pow(sin(t), 3), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) / 16.0)
	_update_text()

func set_ghost_hud_active(active: bool) -> void:
	if _ghost_hud_active == active:
		return
	_ghost_hud_active = active
	size = GHOST_CARD_SIZE if active else CARD_SIZE
	_surface.size = size
	_ghost_slot.visible = active
	_surface.get_node("HPHeading").visible = not active
	_hp_label.visible = not active
	_status_label.visible = not active
	_hp_label.position.x = size.x - 61.0
	_status_label.position.x = size.x - 67.0
	_surface.queue_redraw()

func _label(node_name: String, value: String, pos: Vector2, bounds: Vector2, font_size: int, color: Color, centered := false) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.position = pos
	label.size = bounds
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_surface.add_child(label)
	# Reapply after the font override; Label otherwise keeps its larger default-font minimum.
	label.size = bounds
	return label

func _current_score() -> int:
	return game_state.score if player_index == 1 else game_state.player2_score

func _on_health_changed(index: int, previous: int, hp: int) -> void:
	if index != player_index:
		return
	if not is_visible_in_tree() or not _was_visible:
		_shown_hp = hp
		_health_events.clear()
		return
	_health_events.append({"from": previous, "to": hp, "time": 0.0})

func _process(dt: float) -> void:
	if game_state == null:
		return
	if not is_visible_in_tree():
		_was_visible = false
		_health_events.clear()
		_bursts.clear()
		_shown_hp = game_state.get_player_hp(player_index)
		_last_score = _current_score()
		return
	if not _was_visible:
		_entrance_time = -0.067 * float(player_index - 1)
		_score_time = 10.0
		_flash_time = 0.0
		_shine_time = 0.0
		_impact_time = 10.0
		_was_visible = true
		_update_text()
	_entrance_time += dt
	_score_time += dt
	_shine_time += dt
	_impact_time += dt
	_clock += dt
	for i in range(_bursts.size() - 1, -1, -1):
		_bursts[i].time = float(_bursts[i].time) + dt
		if float(_bursts[i].time) >= 0.68:
			_bursts.remove_at(i)
	_flash_time = maxf(0.0, _flash_time - dt)
	var score := _current_score()
	if score != _last_score:
		if score > _last_score:
			_delta_label.text = "+%d" % (score - _last_score)
			_score_time = 0.0
			_shine_time = 0.0
			_spawn_burst("score", Vector2(76, 15))
		else:
			_score_time = 10.0
		_last_score = score
		_update_text()
	if not _health_events.is_empty():
		var event: Dictionary = _health_events[0]
		if float(event.time) == 0.0:
			_flash_time = 0.32
			var losing := int(event.to) < int(event.from)
			if losing:
				_impact_time = 0.0
			else:
				_shine_time = 0.0
			for slot in range(mini(int(event.from), int(event.to)), maxi(int(event.from), int(event.to))):
				_spawn_burst("damage" if losing else "recover", Vector2(52 + slot * 26, 58))
		event.time = float(event.time) + dt
		var duration := 0.30 if int(event.to) < int(event.from) else 0.40
		if float(event.time) >= duration:
			_shown_hp = int(event.to)
			_health_events.pop_front()
	else:
		_shown_hp = game_state.get_player_hp(player_index)
	var scale_value := _sample("score_scale", _score_time)
	_score_label.scale = Vector2.ONE * scale_value
	_place_score_unit(scale_value)
	_delta_label.visible = _score_time < 0.65
	_delta_label.position.y = -19.0 - 22.0 * _sample("burst_progress", _score_time)
	_delta_label.scale = Vector2.ONE * lerpf(0.8, 1.0, _sample("entrance_alpha", _score_time))
	_delta_label.modulate.a = 1.0 - smoothstep(0.25, 0.65, _score_time)
	_surface.position.x = _sample("impact_shake", _impact_time)
	_surface.position.y = _sample("entrance_y", maxf(0.0, _entrance_time))
	_surface.modulate.a = 0.0 if _entrance_time < 0.0 else _sample("entrance_alpha", _entrance_time)
	var hp := game_state.get_player_hp(player_index)
	_hp_label.text = "%d / %d" % [hp, QuizGameState.MAX_HP]
	_hp_label.position.y = 40.0 if hp <= 1 else 45.0
	if game_state.use_english_ui:
		_status_label.text = "OUT" if hp == 0 else ("LOW HP" if hp == 1 else "")
	else:
		_status_label.text = "脱落" if hp == 0 else ("あと1回" if hp == 1 else "")
	_status_label.position.y = CARD_SIZE.y - _status_label.size.y - 3.0
	_hp_label.add_theme_color_override("font_color", WARNING if hp <= 1 else TEXT)
	_surface.queue_redraw()

func _update_text() -> void:
	_score_label.text = str(_last_score)
	var digits := _score_label.text.length()
	var font_size := 25 if digits <= 3 else (22 if digits <= 5 else 17)
	_score_label.add_theme_font_size_override("font_size", font_size)
	_score_label.size = Vector2(98, 30)
	_place_score_unit(1.0)
	_delta_label.visible = false

func _place_score_unit(score_scale: float) -> void:
	var font_size := _score_label.get_theme_font_size("font_size")
	var font: Font = _score_label.get_theme_font("font")
	var width := font.get_string_size(_score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_score_unit.position.x = minf(140.0, 57.0 + width * score_scale)

func _sample(track_name: String, time: float) -> float:
	var track: Dictionary = _motion[track_name]
	var values: Array = track.values
	var at := clampf(time / float(track.duration), 0.0, 1.0) * float(values.size() - 1)
	var start := int(floor(at))
	return lerpf(float(values[start]), float(values[mini(start + 1, values.size() - 1)]), at - float(start))

func _draw_surface() -> void:
	var hp := game_state.get_player_hp(player_index)
	var low_pulse := (0.35 + 0.12 * sin(_clock * TAU * 0.8)) if hp == 1 and not _ghost_hud_active else 0.0
	_panel.border_color = accent.lerp(WARNING, low_pulse)
	_panel.border_color.a = 0.62
	_surface.draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	_draw_shine()
	_surface.draw_line(Vector2(10, 39), Vector2(size.x - 10, 39), Color(0.22, 0.30, 0.39, 0.72), 1.0, true)
	var accent_x := 2.0 if player_index == 1 else size.x - 2.0
	_surface.draw_line(Vector2(accent_x, 14), Vector2(accent_x, size.y - 14), accent, 2.0, true)
	_surface.draw_style_box(_badge, Rect2(10, 10, 30, 22))
	if _ghost_hud_active:
		_draw_bursts()
		return
	for slot in range(QuizGameState.MAX_HP):
		var center := Vector2(52 + slot * 26, 58)
		_draw_heart(center, HEART_RADIUS, Color(0.14, 0.19, 0.26), true)
		var filled := slot < _shown_hp
		var heart_scale := 1.0
		var alpha := 1.0
		if not _health_events.is_empty():
			var event: Dictionary = _health_events[0]
			if slot >= mini(int(event.from), int(event.to)) and slot < maxi(int(event.from), int(event.to)):
				filled = true
				var losing := int(event.to) < int(event.from)
				heart_scale = _sample("damage_scale" if losing else "recover_scale", float(event.time))
				alpha = _sample("damage_alpha", float(event.time)) if losing else 1.0
		if filled and heart_scale > 0.005:
			var color := accent.lerp(Color.WHITE, _flash_time * 0.65)
			color.a = alpha
			_draw_heart(center, HEART_RADIUS * heart_scale, color, false)
	_draw_bursts()

func _spawn_burst(kind: String, center: Vector2) -> void:
	# A bounded pool of small vector effects, all driven by short event envelopes.
	if _bursts.size() >= 8:
		_bursts.pop_front()
	_bursts.append({"kind": kind, "center": center, "time": 0.0})

func _draw_shine() -> void:
	if _shine_time >= 0.55:
		return
	var progress := _sample("shine_progress", _shine_time)
	var alpha := sin(PI * progress) * 0.18
	var x := lerpf(-38.0, CARD_SIZE.x + 38.0, progress)
	var bounds := PackedVector2Array([Vector2(10, 3), Vector2(178, 3), Vector2(178, 76), Vector2(10, 76)])
	# Two gradient halves give the travelling highlight soft, continuous edges.
	for half in range(2):
		var left := x - 16.0 + float(half) * 14.0
		var ribbon := PackedVector2Array([Vector2(left, 3), Vector2(left + 14, 3), Vector2(left - 13, 76), Vector2(left - 27, 76)])
		for clipped in Geometry2D.intersect_polygons(ribbon, bounds):
			var colors := PackedColorArray()
			for point in clipped:
				var center_x := x - 2.0 - 27.0 * (point.y - 3.0) / 73.0
				colors.append(Color(0.8, 0.94, 1.0, alpha * clampf(1.0 - absf(point.x - center_x) / 14.0, 0.0, 1.0)))
			_surface.draw_polygon(clipped, colors)
	_surface.draw_line(Vector2(12, 1.5), Vector2(12 + 164 * progress, 1.5), Color(accent, sin(PI * progress) * 0.85), 2.0, true)

func _draw_bursts() -> void:
	for burst in _bursts:
		if _ghost_hud_active and str(burst.kind) != "score":
			continue
		var elapsed := float(burst.time)
		var progress := _sample("burst_progress", elapsed)
		var alpha := _sample("burst_alpha", elapsed)
		var center: Vector2 = burst.center
		var damaged := str(burst.kind) == "damage"
		var recovered := str(burst.kind) == "recover"
		var scored := str(burst.kind) == "score"
		var tint := accent.lerp(WARNING, 0.60) if damaged else accent
		var radius := lerpf(4.0, 32.0 if scored else 24.0, progress)
		_surface.draw_circle(center, radius, Color(tint, alpha * 0.10), true, -1.0, true)
		_surface.draw_arc(center, radius, 0, TAU, 40, Color(tint, alpha * 0.75), 1.3, true)
		if recovered:
			_surface.draw_arc(center, radius * 0.68, 0, TAU, 32, Color(0.88, 1.0, 0.94, alpha * 0.65), 1.0, true)
		var spark_count := 12 if scored else 8
		for i in range(spark_count):
			var angle := -PI + float(i) * PI / float(spark_count - 1)
			var direction := Vector2(cos(angle), sin(angle))
			var distance := (16.0 + float(i % 3) * 8.0) * progress
			var point := center + direction * distance + Vector2(0, -10.0 * progress)
			var sparkle := Color(tint.lerp(Color.WHITE, 0.65), alpha)
			if damaged:
				point.y += 16.0 * progress * progress
				var length := lerpf(3.5, 0.5, progress)
				var side := direction.orthogonal() * length * 0.45
				_surface.draw_colored_polygon(PackedVector2Array([point - direction * length, point + side, point + direction * length, point - side]), sparkle)
			elif recovered:
				var length := lerpf(3.0, 1.0, progress)
				_surface.draw_line(point - Vector2(length, 0), point + Vector2(length, 0), sparkle, 1.2, true)
				_surface.draw_line(point - Vector2(0, length), point + Vector2(0, length), sparkle, 1.2, true)
			else:
				_surface.draw_line(point, point - direction * (6.0 * (1.0 - progress)), Color(tint, alpha * 0.65), 2.0, true)
				_surface.draw_circle(point, 3.6, Color(tint, alpha * 0.16), true, -1.0, true)
				_surface.draw_circle(point, 1.4, sparkle, true, -1.0, true)

func _draw_heart(center: Vector2, radius: float, color: Color, outline: bool) -> void:
	var points := PackedVector2Array()
	for point in _heart_points:
		points.append(center + point * radius)
	_surface.draw_colored_polygon(points, color)
	if outline:
		points.append(points[0])
		_surface.draw_polyline(points, Color(0.33, 0.41, 0.50, 0.7), 1.0, true)

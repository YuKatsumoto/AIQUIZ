extends Control

## Self-authored vector hearts: no font glyph or external asset dependency.
const PLAYER_COLORS := [Color(0.95, 0.55, 0.20), Color(0.20, 0.65, 0.90)]
const GROUP_WIDTH := 174.0
const DUO_CARD := preload("res://scripts/ui/duo_player_status_card.gd")
var game_state: QuizGameState
var _shown_hp := [3, 3]
var _queues: Array = [[], []]
var _heart_points := PackedVector2Array()
var _duo_cards: Array[Control] = []

func setup(gs: QuizGameState) -> void:
	game_state = gs
	_shown_hp = [gs.p1_hp, gs.p2_hp]
	gs.health_changed.connect(_on_health_changed)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if game_state.num_players == 2:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for player in range(2):
			var card := DUO_CARD.new()
			card.name = "P%dStatusCard" % (player + 1)
			card.setup(game_state, player + 1, PLAYER_COLORS[player])
			add_child(card)
			_duo_cards.append(card)
			card.resized.connect(_layout_duo_cards)
		_layout_duo_cards()
		return
	position = Vector2(16, 14)
	size = Vector2(GROUP_WIDTH * 2, 48)
	for i in range(64):
		var t := TAU * float(i) / 64.0
		_heart_points.append(Vector2(16.0 * pow(sin(t), 3), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) / 16.0)

func _on_health_changed(player_index: int, previous: int, hp: int) -> void:
	if game_state.num_players == 2:
		return # Each player card consumes the same authoritative health signal.
	if game_state == null or not visible:
		_shown_hp[player_index - 1] = hp
		_queues[player_index - 1].clear()
		return
	_queues[player_index - 1].append({"from": previous, "to": hp, "time": 0.0})

func _process(dt: float) -> void:
	if game_state == null:
		return
	if game_state.num_players == 2:
		visible = game_state.uses_hp() and game_state.game_state in [Constants.STATE_COUNTDOWN, Constants.STATE_PLAYING, Constants.STATE_CORRECT, Constants.STATE_GOAL_RACE]
		_layout_duo_cards()
		return
	visible = game_state.uses_hp() and game_state.game_state in [Constants.STATE_COUNTDOWN, Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
	if not visible:
		_shown_hp = [game_state.p1_hp, game_state.p2_hp]
		_queues[0].clear()
		_queues[1].clear()
		return
	for player in range(2):
		var queue: Array = _queues[player]
		if queue.is_empty():
			_shown_hp[player] = game_state.get_player_hp(player + 1)
			continue
		queue[0].time += dt
		var duration := 0.24 if int(queue[0].to) < int(queue[0].from) else 0.34
		if float(queue[0].time) >= duration:
			_shown_hp[player] = int(queue[0].to)
			queue.pop_front()
	queue_redraw()

func _draw() -> void:
	if game_state == null:
		return
	if game_state.num_players == 2:
		return
	for player in range(game_state.num_players):
		var origin := Vector2(float(player) * GROUP_WIDTH, 0)
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(0.025, 0.045, 0.075, 0.84)
		panel.set_corner_radius_all(12)
		panel.border_color = Color(PLAYER_COLORS[player], 0.55)
		panel.set_border_width_all(1)
		draw_style_box(panel, Rect2(origin, Vector2(GROUP_WIDTH - 10, 46)))
		draw_string(ThemeDB.fallback_font, origin + Vector2(12, 30), "P%d" % (player + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PLAYER_COLORS[player])
		for slot in range(3):
			var center := origin + Vector2(62 + slot * 34, 23)
			_draw_heart(center, 11.0, Color(0.18, 0.22, 0.28, 1.0), true)
			var filled: bool = slot < int(_shown_hp[player])
			var heart_scale := 1.0
			if not _queues[player].is_empty():
				var event: Dictionary = _queues[player][0]
				var losing := int(event.to) < int(event.from)
				if slot >= mini(int(event.from), int(event.to)) and slot < maxi(int(event.from), int(event.to)):
					filled = true
					if losing:
						heart_scale = 1.0 - smoothstep(0.0, 0.24, float(event.time))
					else:
						heart_scale = 1.0 + 0.26 * sin(PI * clampf(float(event.time) / 0.34, 0.0, 1.0))
			if filled and heart_scale > 0.01:
				_draw_heart(center, 11.0 * heart_scale, PLAYER_COLORS[player], false)

func _layout_duo_cards() -> void:
	var viewport_size := get_viewport_rect().size
	var card_scale := minf(1.0, viewport_size.x / 720.0)
	var margin := 16.0 * card_scale
	# The existing question progress bar occupies the bottom 24 pixels.
	for player in range(_duo_cards.size()):
		var card_size := _duo_cards[player].size * card_scale
		var bottom := viewport_size.y - 36.0 * card_scale - card_size.y
		_duo_cards[player].scale = Vector2.ONE * card_scale
		_duo_cards[player].position = Vector2(margin if player == 0 else viewport_size.x - margin - card_size.x, bottom)

func get_ghost_hud_card(player_index: int) -> Control:
	if game_state == null or not game_state.uses_hp() or game_state.num_players != 2:
		return null
	if player_index < 1 or player_index > _duo_cards.size():
		return null
	return _duo_cards[player_index - 1]

func reserve_marker_center(center: Vector2, radius: float) -> Vector2:
	if not visible or game_state.num_players != 2:
		return center
	for card in _duo_cards:
		var bounds := card.get_global_rect().grow(radius + 8.0)
		if bounds.has_point(center):
			center.y = bounds.position.y
	return center

func _draw_heart(center: Vector2, radius: float, color: Color, outline: bool) -> void:
	var points := PackedVector2Array()
	for point in _heart_points:
		points.append(center + point * radius)
	draw_colored_polygon(points, color)
	if outline:
		points.append(points[0])
		draw_polyline(points, Color(0.45, 0.50, 0.57, 0.65), 1.1, true)

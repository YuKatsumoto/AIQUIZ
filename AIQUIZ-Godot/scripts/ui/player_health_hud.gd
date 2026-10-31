extends Control

## Self-authored vector hearts: no font glyph or external asset dependency.
const PLAYER_COLORS := [Color(0.95, 0.55, 0.20), Color(0.20, 0.65, 0.90)]
const GROUP_WIDTH := 174.0
const DUO_CARD := preload("res://scripts/ui/duo_player_status_card.gd")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const TouchHud = preload("res://scripts/ui/touch_hud/touch_hud.gd")
## スマホ：1人のハートの札を少し大きく描く（6.9インチで読める大きさ）。
const TOUCH_SOLO_SCALE := 1.25
## スマホ：2人のカードは中の配置（AE の寸法）を崩さず、カードごと拡大して文字を読める大きさにする。
const TOUCH_DUO_SCALE := 1.4
## スマホ：画面の下は TouchControls のスティック・ジャンプ・答えのボタンが使うので、2人のカードは上の隅に置く。
## 左上は TouchControls のポーズボタン（SafeArea の左上、80px）があるので、その右から（1人のハートも同じ。TouchHud.pause_clearance）。
const TOUCH_CARD_TOP := 12.0
const TOUCH_CARD_SIDE := 16.0
## スマホのオンライン：右上に ping の札（NetOverlay）が出るので、右のカードはその下へ。
const TOUCH_ONLINE_PING_CLEARANCE := 48.0
## 練習（docs/new_tutorial/phase4_design.md 2.5）だけの見せ方。本編のハートの動きは変えない。1人の表示だけ。
## 登場：ポンと出て光り（INTRO_POP_SECONDS）、そのあと1つずつ順に光る（合わせて INTRO_SECONDS）。
const INTRO_POP_SECONDS := 0.45
const INTRO_GLOW_START := 0.6
const INTRO_GLOW_STEP := 0.42
const INTRO_GLOW_SECONDS := 0.55
const INTRO_SECONDS := 2.0
## 減ったハートの枠が赤く点滅する長さと速さ（回/秒）、増えたハートがキラッと光る長さ。
const LOST_FLASH_SECONDS := 1.5
const LOST_FLASH_RATE := 3.0
const SPARKLE_SECONDS := 0.55
var game_state: QuizGameState
var _shown_hp := [3, 3]
var _queues: Array = [[], []]
var _heart_points := PackedVector2Array()
var _duo_cards: Array[Control] = []
## 練習：登場の経過秒（-1 は登場していない）、枠の点滅とキラッの残り秒（プレイヤー × ハート）。
var _intro_time := [-1.0, -1.0]
var _lost_flash := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
var _sparkle := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]

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
	if MobileUi.is_touch_ui():
		scale = Vector2.ONE * TOUCH_SOLO_SCALE
		_layout_solo_group()
		TouchHud.on_safe_area_changed(_layout_solo_group)
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
	if game_state.practice_rules != null:
		_queue_practice_health(player_index - 1, previous, hp)
		return
	_queues[player_index - 1].append({"from": previous, "to": hp, "time": 0.0})


## 練習：減ったハートの枠を赤く点滅させ、一度に増えたときは1つずつ順に増やしてキラッと光らせる。
func _queue_practice_health(player: int, previous: int, hp: int) -> void:
	if hp < previous:
		for slot: int in range(maxi(hp, 0), mini(previous, 3)):
			_lost_flash[player][slot] = LOST_FLASH_SECONDS
		_queues[player].append({"from": previous, "to": hp, "time": 0.0})
		return
	for step: int in range(previous, hp):
		_queues[player].append({"from": step, "to": step + 1, "time": 0.0, "practice_gain": true})


## 練習（1-5）：ハートがポンと出て光り、そのあと1つずつ順に光る。ハートが出ているとき（uses_hp）だけ受ける。
func play_practice_intro(player_index: int) -> void:
	if player_index < 1 or player_index > 2 or game_state == null:
		return
	if not game_state.uses_hp():
		push_warning("play_practice_intro: hearts are not shown (hp_enabled is off)")
		return
	_intro_time[player_index - 1] = 0.0

func _process(dt: float) -> void:
	if game_state == null:
		return
	if game_state.num_players == 2:
		# 練習の2人は、ハートを使わないレッスンでもカードを出す（game_state.shows_duo_cards）。
		visible = game_state.shows_duo_cards() and game_state.game_state in [Constants.STATE_COUNTDOWN, Constants.STATE_PLAYING, Constants.STATE_CORRECT, Constants.STATE_GOAL_RACE]
		_layout_duo_cards()
		return
	visible = game_state.uses_hp() and game_state.game_state in [Constants.STATE_COUNTDOWN, Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
	if visible and MobileUi.is_touch_ui():
		# ポーズボタンの大きさは設定（touch_controls_scale）で変わるので、出ている間は毎フレーム合わせる。
		_layout_solo_group()
	if not visible:
		_shown_hp = [game_state.p1_hp, game_state.p2_hp]
		_queues[0].clear()
		_queues[1].clear()
		_clear_practice_effects()
		return
	for player in range(2):
		_advance_practice_effects(player, dt)
		var queue: Array = _queues[player]
		if queue.is_empty():
			_shown_hp[player] = game_state.get_player_hp(player + 1)
			continue
		if bool(queue[0].get("practice_gain", false)) and not bool(queue[0].get("started", false)):
			queue[0]["started"] = true
			var gained := int(queue[0].to) - 1
			if gained >= 0 and gained < 3:
				_sparkle[player][gained] = SPARKLE_SECONDS
				_lost_flash[player][gained] = 0.0
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
		# 練習の登場：ポンと出る（ふだんは等倍のまま）。
		var intro := float(_intro_time[player])
		var group_scale := 1.0
		var group_glow := 0.0
		if intro >= 0.0:
			group_scale = _ease_out_back(clampf(intro / INTRO_POP_SECONDS, 0.0, 1.0))
			group_glow = 1.0 - clampf(intro / (INTRO_POP_SECONDS + 0.3), 0.0, 1.0)
			if group_scale <= 0.01:
				continue
		var pivot := origin + Vector2((GROUP_WIDTH - 10) * 0.5, 23)
		draw_set_transform(pivot * (1.0 - group_scale), 0.0, Vector2.ONE * group_scale)
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(0.025, 0.045, 0.075, 0.84)
		panel.set_corner_radius_all(12)
		panel.border_color = Color(PLAYER_COLORS[player], 0.55).lerp(Color.WHITE, group_glow)
		panel.set_border_width_all(1)
		draw_style_box(panel, Rect2(origin, Vector2(GROUP_WIDTH - 10, 46)))
		if group_glow > 0.0:
			var shine := StyleBoxFlat.new()
			shine.bg_color = Color(1.0, 0.97, 0.85, 0.38 * group_glow)
			shine.set_corner_radius_all(12)
			draw_style_box(shine, Rect2(origin, Vector2(GROUP_WIDTH - 10, 46)))
		draw_string(ThemeDB.fallback_font, origin + Vector2(12, 30), "P%d" % (player + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PLAYER_COLORS[player])
		for slot in range(3):
			var center := origin + Vector2(62 + slot * 34, 23)
			# 練習で減ったハートの枠は、赤く点滅する。
			var lost := float(_lost_flash[player][slot])
			if lost > 0.0 and fmod((LOST_FLASH_SECONDS - lost) * LOST_FLASH_RATE, 1.0) < 0.55:
				_draw_heart(center, 11.0, Color(0.42, 0.06, 0.08, 1.0), true, Color(1.0, 0.24, 0.18, 1.0), 2.4)
			else:
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
			# 練習：登場で順に光る・増えたときにキラッと光る（ふだんは 0）。
			var sparkle := float(_sparkle[player][slot]) / SPARKLE_SECONDS
			var glow := maxf(_intro_slot_glow(intro, slot), sin(PI * sparkle) if sparkle > 0.0 else 0.0)
			if filled and glow > 0.0:
				draw_circle(center, 11.0 * (1.5 + 0.5 * glow), Color(1.0, 0.95, 0.7, 0.32 * glow))
			if filled and heart_scale > 0.01:
				var heart_color: Color = PLAYER_COLORS[player]
				_draw_heart(center, 11.0 * heart_scale * (1.0 + 0.22 * glow), heart_color.lerp(Color(1.0, 1.0, 0.92), 0.55 * glow), false)
			if sparkle > 0.0:
				_draw_sparkle(center + Vector2(9.0, -10.0), 9.0 * sin(PI * sparkle), Color(1.0, 1.0, 1.0, sin(PI * sparkle)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _layout_duo_cards() -> void:
	var viewport_size := get_viewport_rect().size
	var card_scale := minf(1.0, viewport_size.x / 720.0)
	var margin := 16.0 * card_scale
	if MobileUi.is_touch_ui():
		_layout_duo_cards_touch(viewport_size, card_scale * TOUCH_DUO_SCALE)
		return
	# The existing question progress bar occupies the bottom 24 pixels.
	for player in range(_duo_cards.size()):
		var card_size := _duo_cards[player].size * card_scale
		var bottom := viewport_size.y - 36.0 * card_scale - card_size.y
		_duo_cards[player].scale = Vector2.ONE * card_scale
		_duo_cards[player].position = Vector2(margin if player == 0 else viewport_size.x - margin - card_size.x, bottom)


## スマホ：P1 は左上（ポーズボタンの右）、P2 は右上。どちらも SafeArea（カメラの穴と角丸）の内側。
## ゴーストの間に大きくなるカードは下へ伸びる（位置は毎フレームここで決め直す）。
func _layout_duo_cards_touch(viewport_size: Vector2, card_scale: float) -> void:
	var top := TouchHud.safe_top() + TOUCH_CARD_TOP
	for player in range(_duo_cards.size()):
		var card := _duo_cards[player]
		var card_size := card.size * card_scale
		var y := top
		if player == 1 and game_state != null and game_state.net_online:
			y += TOUCH_ONLINE_PING_CLEARANCE
		card.scale = Vector2.ONE * card_scale
		card.position = Vector2(
			TouchHud.safe_left() + TouchHud.pause_clearance() if player == 0 else viewport_size.x - TOUCH_CARD_SIDE - TouchHud.safe_right() - card_size.x,
			y
		)
		card.set("top_anchored", true)


## スマホ：上の隅に出ている2人のカードの、画面の上の範囲（チュートリアルのバーなどがよける）。出ていなければ空。
func touch_card_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if not visible or not MobileUi.is_touch_ui():
		return rects
	for card: Control in _duo_cards:
		if card.is_visible_in_tree():
			rects.append(card.get_global_rect())
	return rects


## スマホ：1人のハートの札を左上の SafeArea の内側へ（左上のポーズボタンの右）。
func _layout_solo_group() -> void:
	position = Vector2(TouchHud.pause_clearance() + TouchHud.safe_left(), 14.0 + TouchHud.safe_top())

func get_ghost_hud_card(player_index: int) -> Control:
	if game_state == null or not game_state.shows_duo_cards():
		return null
	if player_index < 1 or player_index > _duo_cards.size():
		return null
	return _duo_cards[player_index - 1]

## 練習（docs/new_tutorial/phase6_design.md）：2人のカードを一度光らせる（例：P2 が参加した）。
func practice_card_shine(player_index: int) -> void:
	if player_index < 1 or player_index > _duo_cards.size():
		return
	var card := _duo_cards[player_index - 1]
	if card.has_method("practice_shine"):
		card.practice_shine()


func reserve_marker_center(center: Vector2, radius: float) -> Vector2:
	if not visible or game_state.num_players != 2:
		return center
	for card in _duo_cards:
		var bounds := card.get_global_rect().grow(radius + 8.0)
		if bounds.has_point(center):
			# スマホのカードは上の隅にあるので、マーカーはカードの下へよける。
			center.y = bounds.end.y if MobileUi.is_touch_ui() else bounds.position.y
	return center

func _draw_heart(center: Vector2, radius: float, color: Color, outline: bool,
		outline_color := Color(0.45, 0.50, 0.57, 0.65), outline_width := 1.1) -> void:
	var points := PackedVector2Array()
	for point in _heart_points:
		points.append(center + point * radius)
	draw_colored_polygon(points, color)
	if outline:
		points.append(points[0])
		draw_polyline(points, outline_color, outline_width, true)


## 練習のキラッ：4つの角の星。
func _draw_sparkle(center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.5:
		return
	var points := PackedVector2Array()
	for i in range(8):
		var angle := TAU * float(i) / 8.0 - PI * 0.5
		var r := radius if i % 2 == 0 else radius * 0.26
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)


## 練習の登場で、slot 番目のハートが光る強さ（0〜1）。登場していなければ 0。
func _intro_slot_glow(intro: float, slot: int) -> float:
	if intro < 0.0:
		return 0.0
	var x := (intro - (INTRO_GLOW_START + float(slot) * INTRO_GLOW_STEP)) / INTRO_GLOW_SECONDS
	return sin(PI * x) if x > 0.0 and x < 1.0 else 0.0


## 行き過ぎて戻る（ポンと出る）。
static func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


func _advance_practice_effects(player: int, dt: float) -> void:
	if float(_intro_time[player]) >= 0.0:
		_intro_time[player] = float(_intro_time[player]) + dt
		if float(_intro_time[player]) >= INTRO_SECONDS:
			_intro_time[player] = -1.0
	for slot in range(3):
		_lost_flash[player][slot] = maxf(0.0, float(_lost_flash[player][slot]) - dt)
		_sparkle[player][slot] = maxf(0.0, float(_sparkle[player][slot]) - dt)


## ハートが隠れている間は点滅とキラッを捨てる。登場は、ハートを出すルールのままなら出るまで待つ。
func _clear_practice_effects() -> void:
	for player in range(2):
		for slot in range(3):
			_lost_flash[player][slot] = 0.0
			_sparkle[player][slot] = 0.0
		if not game_state.uses_hp():
			_intro_time[player] = -1.0

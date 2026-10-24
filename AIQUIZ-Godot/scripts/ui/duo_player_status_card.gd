extends Control
## Editable live HUD. Motion tracks are sampled from the supplied native AE project.
## 見た目はメニューの金属の押しボタン（MenuMetalButton）の板：下だけ厚い縁、四隅のボルト、ランプ、色の下線。
## 正解数と連続正解は、地下神殿の水門の問題板と同じ琥珀色の LED 窓（shaders/duo_hud_led.gdshader）に灯す。

const CARD_SIZE := Vector2(188, 80)
const GHOST_CARD_SIZE := Vector2(320, 120)
const HEART_RADIUS := 9.5
const HEART_PITCH := 27.0
const TEXT := Color(0.96, 0.975, 1.0)
const MUTED := Color(0.545, 0.588, 0.62)
const WARNING := Color(1.0, 0.49, 0.37)
const WARNING_SOFT := Color(1.0, 0.616, 0.518)
const OUTLINE := Color(0.027, 0.047, 0.082, 0.96)
const BADGE_INK := Color("#182129")
const PLATE_RIM := Color("#72838b")
const DEAD_RIM := Color("#5c676e")
const DEAD_FACE := Color("#2a343c")
const DEAD_LAMP := Color("#2c3a44")
const DEAD_LINE := Color("#3a4650")
const EMPTY_HEART := Color("#26313a")
const EMPTY_HEART_LINE := Color("#3a4650")
const STAMP_INK := Color("#4a1508")
const STAMP_LINE := Color("#5a1d10")
const LED_CORE := Color("#ffd79a")
const LED_GLOW := Color("#ff8a1e")
const LED_STREAK := Color("#ffc46a")
const LED_STREAK_UNIT := Color("#ffb24d")
const LED_SHADER := preload("res://shaders/duo_hud_led.gdshader")
## LED の粒の間隔（画面の画素）。カードの拡大率で割ってカードの座標にする。
const LED_DOT_PIXELS := 2.4
## LED の文字のにじみ：縁取りの太さと濃さを重ねる。
const LED_GLOW_LAYERS := [[9, 0.07], [5, 0.11], [2, 0.16]]
## LED 窓の文字の並ぶ線（窓の上端から）。
const LED_BASELINE := 20.5
const MOTION_PATH := "res://assets/ui/duo_hud/motion.json"
const STREAK_BADGE := preload("res://scripts/ui/streak_flame_badge.gd")

var game_state: QuizGameState
var player_index := 1
var accent := Color.WHITE
var _motion: Dictionary
var _surface: Control
var _led_window: ColorRect
var _led_glow: Control
var _fx: Control
var _score_label: Label
var _score_unit: Label
var _hp_label: Label
var _delta_label: Label
var _status_label: Label
var _heart_points := PackedVector2Array()
var _frame: StyleBoxFlat
var _face: StyleBoxFlat
var _badge: StyleBoxFlat
var _bezel: StyleBoxFlat
var _socket: StyleBoxFlat
var _meter: StyleBoxFlat
var _stamp: StyleBoxFlat
var _led_material: ShaderMaterial
var _led_panel_material: ShaderMaterial
var _row_state := -1
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
var _streak_badge: Control

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
	_frame = _plate(PLATE_RIM, 7)
	_frame.shadow_color = Color(0.0, 0.01, 0.025, 0.32)
	_frame.shadow_size = 3
	_frame.shadow_offset = Vector2(0, 2)
	_face = _plate(MenuMetalButton.FACE, 5)
	_badge = _plate(accent, 5)
	_bezel = _plate(MenuMetalButton.FRAME_LIGHT, 3)
	_socket = _plate(MenuMetalButton.FRAME_DARK, 5)
	_meter = _plate(MenuMetalButton.FRAME_DARK, 5)
	_meter.border_color = WARNING
	_stamp = _plate(WARNING, 5)
	# LED 窓：板（消えた粒）→ 文字のにじみ → 文字（灯った粒）の順に重ねる。
	_led_panel_material = ShaderMaterial.new()
	_led_panel_material.shader = LED_SHADER
	_led_panel_material.set_shader_parameter("panel", true)
	_led_material = ShaderMaterial.new()
	_led_material.shader = LED_SHADER
	_led_window = ColorRect.new()
	_led_window.name = "LedWindow"
	_led_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_led_window.material = _led_panel_material
	_surface.add_child(_led_window)
	_led_glow = Control.new()
	_led_glow.name = "LedGlow"
	_led_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_led_glow.clip_contents = true
	_led_glow.draw.connect(_draw_led_glow)
	_surface.add_child(_led_glow)
	_score_label = _label("Score", str(_last_score), Vector2.ZERO, Vector2(98, 25), 21, LED_CORE)
	_score_label.material = _led_material
	_score_unit = _label("ScoreUnit", "correct" if game_state.use_english_ui else "正解", Vector2.ZERO, Vector2(44, 15), 10, LED_CORE)
	_score_unit.material = _led_material
	var badge := _badge_rect()
	if game_state.net_online:
		# オンラインは自分のカードと相手のカードを言葉で分ける。
		var tag := "じぶん" if game_state.is_local_slot(player_index) else "あいて"
		_label("Player", tag, badge.position, badge.size, 10, BADGE_INK, true)
	else:
		_label("Player", "P%d" % player_index, badge.position, badge.size, 13, BADGE_INK, true)
	_label("HPHeading", "HP", Vector2(9, 46), Vector2(20, 22), 9, MUTED)
	_hp_label = _label("HP", "3 / 3", Vector2(126, 46), Vector2(51, 23), 12, TEXT, true)
	_delta_label = _label("ScoreDelta", "+1", Vector2(48, -27), Vector2(68, 25), 21, accent, true)
	_delta_label.add_theme_color_override("font_outline_color", OUTLINE)
	_delta_label.add_theme_constant_override("outline_size", 3)
	_delta_label.visible = false
	_status_label = _label("Status", "", Vector2(126, 58), Vector2(51, 10), 9, WARNING, true)
	# 連続正解は正解数の右に、炎（AE 製ループ）と回数で出す。LED 窓の粒で描く。
	_streak_badge = STREAK_BADGE.new()
	_streak_badge.name = "StreakBadge"
	_streak_badge.setup(game_state.use_english_ui)
	_surface.add_child(_streak_badge)
	_streak_badge.set_led_style(_led_material, MenuMetalButton.FONT, LED_STREAK, LED_STREAK_UNIT)
	_streak_badge.snap(game_state.get_player_streak(player_index))
	# 得点・被弾・回復の光は文字の上に出す。
	_fx = Control.new()
	_fx.name = "Effects"
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_bursts)
	_surface.add_child(_fx)
	for i in range(64):
		var t := TAU * float(i) / 64.0
		_heart_points.append(Vector2(16.0 * pow(sin(t), 3), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) / 16.0)
	_layout_window()
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
	_row_state = -1
	_layout_window()
	_surface.queue_redraw()

func _plate(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style

func _label(node_name: String, value: String, pos: Vector2, bounds: Vector2, font_size: int, color: Color, centered := false) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.position = pos
	label.size = bounds
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", MenuMetalButton.FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_surface.add_child(label)
	# Reapply after the font override; Label otherwise keeps its larger default-font minimum.
	label.size = bounds
	return label

## P1/P2 のバッジ（メニューの featured ボタンと同じ、色ベタの小さな板）。
func _badge_rect() -> Rect2:
	return Rect2(18, 11, 42, 21) if game_state.net_online else Rect2(20, 11, 33, 21)

## LED 窓の縁。バッジの右から、カードの右の縁まで。
func _window_rect() -> Rect2:
	var left := _badge_rect().end.x + 7.0
	return Rect2(left, 9, size.x - 7.0 - left, 27)

## LED の粒が並ぶ面（縁の内側）。
func _led_rect() -> Rect2:
	return _window_rect().grow(-1.0)

## HP の数字のメーター窓（右下）。
func _meter_rect() -> Rect2:
	return Rect2(size.x - 62.0, 46, 51, 23)

func _heart_center(slot: int) -> Vector2:
	return Vector2(43.0 + float(slot) * HEART_PITCH, 56.5)

func _layout_window() -> void:
	var led := _led_rect()
	_led_window.position = led.position
	_led_window.size = led.size
	_led_glow.position = led.position
	_led_glow.size = led.size
	_fx.size = size
	_score_label.position.x = led.position.x + 3.0
	_set_baseline(_score_label, led.position.y + LED_BASELINE)
	_set_baseline(_score_unit, led.position.y + LED_BASELINE)
	_streak_badge.position.y = led.position.y - 8.5
	var window := Vector4(led.position.x, led.position.y, led.size.x, led.size.y)
	_led_material.set_shader_parameter("window", window)
	_led_panel_material.set_shader_parameter("window", window)

## ラベルの文字の並ぶ線を y に合わせる（ラベルの高さはフォントで決まるので、上端から逆算する）。
func _set_baseline(label: Label, y: float) -> void:
	label.position.y = y - _baseline_offset(label)

func _baseline_offset(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	return (label.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)

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
		_streak_badge.snap(game_state.get_player_streak(player_index))
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
			_spawn_burst("score", Vector2(_score_label.position.x + 9.0, _led_rect().get_center().y))
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
				_spawn_burst("damage" if losing else "recover", _heart_center(slot))
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
	_streak_badge.advance(dt, game_state.get_player_streak(player_index))
	_place_streak_badge()
	_delta_label.visible = _score_time < 0.65
	_delta_label.position.y = -19.0 - 22.0 * _sample("burst_progress", _score_time)
	_delta_label.scale = Vector2.ONE * lerpf(0.8, 1.0, _sample("entrance_alpha", _score_time))
	_delta_label.modulate.a = 1.0 - smoothstep(0.25, 0.65, _score_time)
	_surface.position.x = _sample("impact_shake", _impact_time)
	_surface.position.y = _sample("entrance_y", maxf(0.0, _entrance_time))
	_surface.modulate.a = 0.0 if _entrance_time < 0.0 else _sample("entrance_alpha", _entrance_time)
	var hp := game_state.get_player_hp(player_index)
	_update_hp_row(hp)
	_update_led(hp)
	_surface.queue_redraw()
	_led_glow.queue_redraw()
	_fx.queue_redraw()

## HP の数字と状態。メーター窓に「3 / 3」、残り 1 は数字と「あと1回」を縦に、0 は「OUT」のスタンプ。
func _update_hp_row(hp: int) -> void:
	_hp_label.text = "%d / %d" % [hp, QuizGameState.MAX_HP]
	_hp_label.modulate.a = 0.0 if hp == 0 else 1.0
	if hp == 0:
		_status_label.text = "OUT"
	elif hp == 1:
		_status_label.text = "LOW HP" if game_state.use_english_ui else "あと1回"
	else:
		_status_label.text = ""
	var state := clampi(hp, 0, 2)
	if state == _row_state:
		return
	_row_state = state
	var meter := _meter_rect()
	_hp_label.add_theme_color_override("font_color", WARNING if hp <= 1 else TEXT)
	_hp_label.add_theme_font_size_override("font_size", 10 if state == 1 else 12)
	_hp_label.position = meter.position + (Vector2(0, -1.5) if state == 1 else Vector2.ZERO)
	_hp_label.size = Vector2(meter.size.x, 12) if state == 1 else meter.size
	if state == 0:
		_status_label.add_theme_font_size_override("font_size", 13)
		_status_label.add_theme_color_override("font_color", STAMP_INK)
		_status_label.size = Vector2(55, 24)
		_status_label.position = meter.get_center() - _status_label.size * 0.5
		_status_label.pivot_offset = _status_label.size * 0.5
		_status_label.rotation = deg_to_rad(-6.0)
	else:
		_status_label.add_theme_font_size_override("font_size", 9)
		_status_label.add_theme_color_override("font_color", WARNING_SOFT)
		_status_label.size = Vector2(meter.size.x, 10)
		_status_label.position = meter.position + Vector2(0, 9.5)
		_status_label.rotation = 0.0

## LED の粒の格子をカードの今の位置と大きさに合わせる（入場の動きや揺れの間も粒が窓に留まるように）。
func _update_led(hp: int) -> void:
	var to_card := _surface.get_global_transform().affine_inverse()
	var screen := get_viewport().get_final_transform() * _surface.get_global_transform_with_canvas()
	var pitch := clampf(LED_DOT_PIXELS / maxf(screen.get_scale().x, 0.01), 1.1, 2.4)
	for led_material: ShaderMaterial in [_led_material, _led_panel_material]:
		led_material.set_shader_parameter("card_x", to_card.x)
		led_material.set_shader_parameter("card_y", to_card.y)
		led_material.set_shader_parameter("card_origin", to_card.origin)
		led_material.set_shader_parameter("pitch", pitch)
	_led_material.set_shader_parameter("level", 0.6 if _is_out(hp) else 1.0)

func _is_out(hp: int) -> bool:
	return hp == 0 and not _ghost_hud_active

func _update_text() -> void:
	_score_label.text = str(_last_score)
	var digits := _score_label.text.length()
	var font_size := 21 if digits <= 3 else (18 if digits <= 5 else 15)
	_score_label.add_theme_font_size_override("font_size", font_size)
	_score_label.size = Vector2(98, 0)
	_set_baseline(_score_label, _led_rect().position.y + LED_BASELINE)
	# 弾むときは数字の真ん中を軸にする。
	_score_label.pivot_offset = Vector2(0, _baseline_offset(_score_label) - font_size * 0.36)
	_place_score_unit(1.0)
	_delta_label.visible = false

func _place_score_unit(score_scale: float) -> void:
	var width := _text_width(_score_label)
	var limit := _led_rect().end.x - _text_width(_score_unit) - 3.0
	_score_unit.position.x = minf(limit, _score_label.position.x + 2.0 + width * score_scale)

## 正解の単位の直後に置く。幅が足りなければ「連続」を省き、それでも足りなければ「正解」を隠して
## 正解数の直後に詰める。
func _place_streak_badge() -> void:
	var limit := _led_rect().end.x - 3.0
	var unit_end := _score_unit.position.x + _text_width(_score_unit)
	_streak_badge.set_compact(false)
	if unit_end + 4.0 + float(_streak_badge.content_width()) > limit:
		_streak_badge.set_compact(true)
	var width: float = _streak_badge.content_width()
	var x := unit_end + 4.0
	var show_unit := x + width <= limit
	if not show_unit:
		x = _score_label.position.x + _text_width(_score_label) * _score_label.scale.x + 4.0
	_score_unit.visible = show_unit or not _streak_badge.visible
	_streak_badge.position.x = minf(x, limit - width)

func _text_width(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x

func _sample(track_name: String, time: float) -> float:
	var track: Dictionary = _motion[track_name]
	var values: Array = track.values
	var at := clampf(time / float(track.duration), 0.0, 1.0) * float(values.size() - 1)
	var start := int(floor(at))
	return lerpf(float(values[start]), float(values[mini(start + 1, values.size() - 1)]), at - float(start))

## 正解・回復の直後にボルトと下線が一瞬明るくなる（メニューの矢印ボタンを押したときと同じ）。
func _press_amount() -> float:
	return 1.0 - clampf(_shine_time / 0.24, 0.0, 1.0)

func _draw_surface() -> void:
	var s := _surface
	var hp := game_state.get_player_hp(player_index)
	var out := _is_out(hp)
	var low := hp == 1 and not _ghost_hud_active
	var low_pulse := (0.45 + 0.2 * sin(_clock * TAU * 0.8)) if low else 0.0
	var blink := 0.5 + 0.5 * sin(_clock * TAU * 1.6)
	var press := _press_amount()
	# 板：縁（下だけ厚い）と面。
	_frame.bg_color = DEAD_RIM if out else PLATE_RIM.lerp(WARNING, low_pulse)
	s.draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	_face.bg_color = DEAD_FACE if out else MenuMetalButton.FACE
	s.draw_style_box(_face, Rect2(3, 3, size.x - 6, size.y - 8))
	_draw_shine()
	for bolt in [Vector2(7, 7), Vector2(size.x - 7, 7), Vector2(7, size.y - 9), Vector2(size.x - 7, size.y - 9)]:
		s.draw_circle(bolt, 2.5, MenuMetalButton.FRAME_DARK, true, -1.0, true)
		s.draw_circle(bolt, 1.15, MenuMetalButton.FRAME_LIGHT.lightened(press * 0.35), true, -1.0, true)
	# ランプ：生きている間は点灯、残り 1 は赤く点滅、脱落で消える。
	var badge := _badge_rect()
	var lamp_center := Vector2(badge.position.x - 7.0, badge.get_center().y)
	var lamp := accent.lerp(Color.WHITE, press * 0.5)
	if out:
		lamp = DEAD_LAMP
	elif low:
		lamp = WARNING.lerp(MenuMetalButton.FRAME_DARK, 0.55 * (1.0 - blink))
	s.draw_circle(lamp_center, 3.6, MenuMetalButton.FRAME_DARK, true, -1.0, true)
	s.draw_circle(lamp_center, 2.2, lamp, true, -1.0, true)
	if low:
		s.draw_arc(lamp_center, 5.2, 0, TAU, 24, Color(WARNING, 0.5 * blink), 0.8, true)
	_badge.bg_color = accent.darkened(0.45) if out else accent
	s.draw_style_box(_badge, badge)
	s.draw_style_box(_bezel, _window_rect())
	# 板に彫った溝。
	s.draw_line(Vector2(12, 39.5), Vector2(size.x - 12, 39.5), MenuMetalButton.FRAME_DARK, 1.2, true)
	s.draw_line(Vector2(12, 40.8), Vector2(size.x - 12, 40.8), Color(MenuMetalButton.FRAME_LIGHT, 0.6), 0.8, true)
	if not _ghost_hud_active:
		_draw_hearts()
		var meter := _meter_rect()
		_meter.set_border_width_all(1 if low else 0)
		s.draw_style_box(_meter, meter)
		if out:
			s.draw_set_transform(meter.get_center(), deg_to_rad(-6.0))
			s.draw_style_box(_stamp, Rect2(-27.5, -12, 55, 24))
			s.draw_rect(Rect2(-25, -9.5, 50, 19), STAMP_LINE, false, 0.9, true)
			s.draw_set_transform_matrix(Transform2D.IDENTITY)
	# プレイヤーの色の下線（メニューの矢印ボタンが選ばれたときの線）。
	var line := accent.lerp(Color.WHITE, press * 0.4)
	if out:
		line = DEAD_LINE
	elif low:
		line = WARNING
	s.draw_line(Vector2(12, size.y - 7.5), Vector2(size.x - 12, size.y - 7.5), line, 2.0 + press, true)

func _draw_hearts() -> void:
	for slot in range(QuizGameState.MAX_HP):
		var center := _heart_center(slot)
		# ハートはボタンのランプ穴と同じ暗い穴に収める。
		_surface.draw_style_box(_socket, Rect2(center.x - 12.0, 46, 24, 23))
		_draw_heart(center, HEART_RADIUS, EMPTY_HEART, true)
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
	var top := 3.0
	var bottom := size.y - 5.0
	var slant := 27.0 * (bottom - top) / 73.0
	var x := lerpf(-38.0, size.x + 38.0, progress)
	var bounds := PackedVector2Array([Vector2(3, top), Vector2(size.x - 3, top), Vector2(size.x - 3, bottom), Vector2(3, bottom)])
	# Two gradient halves give the travelling highlight soft, continuous edges.
	for half in range(2):
		var left := x - 16.0 + float(half) * 14.0
		var ribbon := PackedVector2Array([Vector2(left, top), Vector2(left + 14, top), Vector2(left + 14 - slant, bottom), Vector2(left - slant, bottom)])
		for clipped in Geometry2D.intersect_polygons(ribbon, bounds):
			var colors := PackedColorArray()
			for point in clipped:
				var center_x := x - 2.0 - slant * (point.y - top) / (bottom - top)
				colors.append(Color(0.8, 0.94, 1.0, alpha * clampf(1.0 - absf(point.x - center_x) / 14.0, 0.0, 1.0)))
			_surface.draw_polygon(clipped, colors)
	_surface.draw_line(Vector2(12, 1.5), Vector2(12 + (size.x - 24.0) * progress, 1.5), Color(accent, sin(PI * progress) * 0.85), 2.0, true)

## LED の文字と炎のまわりの橙のにじみ（窓の中だけ）。
func _draw_led_glow() -> void:
	var dim := 0.45 if _is_out(game_state.get_player_hp(player_index)) else 1.0
	var to_glow := _led_glow.get_global_transform().affine_inverse()
	var labels: Array[Label] = [_score_label]
	if _score_unit.visible:
		labels.append(_score_unit)
	if _streak_badge.visible:
		labels.append_array(_streak_badge.glow_labels())
	for label in labels:
		var strength := dim * label.modulate.a
		if strength <= 0.01:
			continue
		var font: Font = label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		_led_glow.draw_set_transform_matrix(to_glow * label.get_global_transform())
		for layer in LED_GLOW_LAYERS:
			_led_glow.draw_string_outline(font, Vector2(0, _baseline_offset(label)), label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(layer[0]), Color(LED_GLOW, float(layer[1]) * strength))
	_led_glow.draw_set_transform_matrix(Transform2D.IDENTITY)
	var flame: float = _streak_badge.flame_strength() * dim
	if _streak_badge.visible and flame > 0.01:
		var center: Vector2 = to_glow * _streak_badge.get_global_transform() * _streak_badge.flame_center()
		for i in range(4):
			_led_glow.draw_circle(center, 13.0 - float(i) * 3.0, Color(LED_GLOW, 0.06 * flame), true, -1.0, true)

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
		_fx.draw_circle(center, radius, Color(tint, alpha * 0.10), true, -1.0, true)
		_fx.draw_arc(center, radius, 0, TAU, 40, Color(tint, alpha * 0.75), 1.3, true)
		if recovered:
			_fx.draw_arc(center, radius * 0.68, 0, TAU, 32, Color(0.88, 1.0, 0.94, alpha * 0.65), 1.0, true)
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
				_fx.draw_colored_polygon(PackedVector2Array([point - direction * length, point + side, point + direction * length, point - side]), sparkle)
			elif recovered:
				var length := lerpf(3.0, 1.0, progress)
				_fx.draw_line(point - Vector2(length, 0), point + Vector2(length, 0), sparkle, 1.2, true)
				_fx.draw_line(point - Vector2(0, length), point + Vector2(0, length), sparkle, 1.2, true)
			else:
				_fx.draw_line(point, point - direction * (6.0 * (1.0 - progress)), Color(tint, alpha * 0.65), 2.0, true)
				_fx.draw_circle(point, 3.6, Color(tint, alpha * 0.16), true, -1.0, true)
				_fx.draw_circle(point, 1.4, sparkle, true, -1.0, true)

## 満タンのハートは点灯したランプのように、左上に小さな光を載せる。空のハートは暗い影だけ。
func _draw_heart(center: Vector2, radius: float, color: Color, empty: bool) -> void:
	var points := PackedVector2Array()
	for point in _heart_points:
		points.append(center + point * radius)
	_surface.draw_colored_polygon(points, color)
	if empty:
		points.append(points[0])
		_surface.draw_polyline(points, EMPTY_HEART_LINE, 0.8, true)
	else:
		_surface.draw_circle(center + Vector2(-0.38, -0.3) * radius, radius * 0.2, Color(1, 1, 1, 0.5 * color.a), true, -1.0, true)

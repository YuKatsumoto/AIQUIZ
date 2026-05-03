extends Control
class_name MinigameCatch

## ブロックマンキャッチ ミニゲーム
## プリロード中にマウスで遊べるキャッチゲーム

signal game_ended(score: int)

# ── 設定 ──
const PLAYER_WIDTH := 40.0
const PLAYER_HEIGHT := 40.0
const ITEM_SIZE := 28.0
const SPAWN_INTERVAL_MIN := 0.4
const SPAWN_INTERVAL_MAX := 0.85
const FALL_SPEED_MIN := 120.0
const FALL_SPEED_MAX := 220.0
const PLAY_AREA_MARGIN := 16.0

# アイテム定義: {emoji, points, color, weight}
const ITEM_DEFS := [
	{"emoji": "⭐", "points": 1, "color": Color(1.0, 0.9, 0.2), "weight": 40},
	{"emoji": "💎", "points": 3, "color": Color(0.3, 0.7, 1.0), "weight": 12},
	{"emoji": "🍎", "points": 1, "color": Color(1.0, 0.3, 0.3), "weight": 22},
	{"emoji": "🍬", "points": 2, "color": Color(1.0, 0.5, 0.8), "weight": 16},
	{"emoji": "💣", "points": -2, "color": Color(0.4, 0.4, 0.4), "weight": 10},
]

# ── 状態 ──
var _score: int = 0
var _combo: int = 0
var _best_combo: int = 0
var _spawn_timer: float = 0.0
var _next_spawn: float = 0.5
var _player_x: float = 0.0
var _player_target_x: float = 0.0
var _items: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _bg_stars: Array[Dictionary] = []
var _elapsed: float = 0.0
var _active: bool = false
var _fade_alpha: float = 0.0
var _shake_timer: float = 0.0
var _shake_intensity: float = 0.0
var _total_weight: int = 0

# ── UIノード ──
var _score_label: Label = null
var _combo_label: Label = null
var _instruction_label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	for def in ITEM_DEFS:
		_total_weight += def["weight"]

	var font := _load_font()

	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 18)
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	_score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_score_label.add_theme_constant_override("outline_size", 4)
	if font:
		_score_label.add_theme_font_override("font", font)
	add_child(_score_label)

	_combo_label = Label.new()
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.add_theme_font_size_override("font_size", 14)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	_combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_combo_label.add_theme_constant_override("outline_size", 3)
	_combo_label.visible = false
	if font:
		_combo_label.add_theme_font_override("font", font)
	add_child(_combo_label)

	_instruction_label = Label.new()
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction_label.add_theme_font_size_override("font_size", 12)
	_instruction_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.7))
	_instruction_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_instruction_label.add_theme_constant_override("outline_size", 3)
	_instruction_label.text = "🖱️ マウスを動かしてアイテムをキャッチ！"
	if font:
		_instruction_label.add_theme_font_override("font", font)
	add_child(_instruction_label)


func _load_font() -> Font:
	if ResourceLoader.exists("res://resources/fonts/NotoSansJP-Regular.otf"):
		return load("res://resources/fonts/NotoSansJP-Regular.otf") as Font
	return null


func start() -> void:
	_active = true
	_score = 0
	_combo = 0
	_best_combo = 0
	_elapsed = 0.0
	_spawn_timer = 0.0
	_next_spawn = 0.8
	_shake_timer = 0.0
	_items.clear()
	_particles.clear()
	_fade_alpha = 0.0
	_player_x = size.x * 0.5
	_player_target_x = _player_x
	visible = true
	_init_bg_stars()
	queue_redraw()


func stop() -> void:
	_active = false
	game_ended.emit(_score)


func get_score() -> int:
	return _score


func _init_bg_stars() -> void:
	_bg_stars.clear()
	for idx: int in range(30):
		_bg_stars.append({
			"x": randf() * 400.0,
			"y": randf() * 660.0,
			"speed": randf_range(15.0, 50.0),
			"size": randf_range(1.0, 2.5),
			"alpha": randf_range(0.15, 0.4),
			"idx": idx,
		})


func _process(dt: float) -> void:
	if not _active:
		return

	_elapsed += dt
	_fade_alpha = clampf(_fade_alpha + dt * 3.0, 0.0, 1.0)

	# シェイク減衰
	if _shake_timer > 0.0:
		_shake_timer -= dt

	# マウス位置でプレイヤーを移動（スムーズ追従）
	var mouse_pos := get_local_mouse_position()
	var margin := PLAY_AREA_MARGIN + PLAYER_WIDTH * 0.5
	_player_target_x = clampf(mouse_pos.x, margin, size.x - margin)
	_player_x = lerpf(_player_x, _player_target_x, dt * 18.0)

	# アイテムスポーン
	_spawn_timer += dt
	if _spawn_timer >= _next_spawn:
		_spawn_timer = 0.0
		_spawn_item()
		var diff := clampf(_elapsed / 30.0, 0.0, 0.6)
		_next_spawn = randf_range(
			SPAWN_INTERVAL_MIN - diff * 0.15,
			SPAWN_INTERVAL_MAX - diff * 0.3
		)

	# アイテム更新＆判定
	var play_h := size.y - 30.0
	var player_rect := Rect2(
		_player_x - PLAYER_WIDTH * 0.6,
		play_h - PLAYER_HEIGHT - 8.0,
		PLAYER_WIDTH * 1.2,
		PLAYER_HEIGHT
	)

	var i := _items.size() - 1
	while i >= 0:
		var item := _items[i]
		item["y"] += item["speed"] * dt

		var item_rect := Rect2(
			item["x"] - ITEM_SIZE * 0.5,
			item["y"] - ITEM_SIZE * 0.5,
			ITEM_SIZE, ITEM_SIZE
		)

		if not item["caught"] and item_rect.intersects(player_rect):
			item["caught"] = true
			var def: Dictionary = ITEM_DEFS[item["def_idx"]]

			if def["points"] > 0:
				_combo += 1
				_best_combo = maxi(_best_combo, _combo)
				var bonus := 1 if _combo < 5 else 2
				_score += def["points"] * bonus
			else:
				_combo = 0
				_score += def["points"]
				_shake_timer = 0.3
				_shake_intensity = 6.0
			_score = maxi(0, _score)

			var pts_text: String
			if def["points"] > 0 and _combo >= 5:
				pts_text = "+%d x2!" % def["points"]
			elif def["points"] > 0:
				pts_text = "+%d" % def["points"]
			else:
				pts_text = "%d" % def["points"]
			_spawn_particle(item["x"], item["y"], pts_text, def["color"])

			if def["points"] < 0:
				_spawn_particle(item["x"], item["y"] - 20.0, "💥", Color(1.0, 0.3, 0.1))

			_items.remove_at(i)
			i -= 1
			continue

		if item["y"] > play_h + ITEM_SIZE:
			# 良いアイテムを取り逃した → コンボリセット
			var def2: Dictionary = ITEM_DEFS[item["def_idx"]]
			if def2["points"] > 0:
				_combo = 0
			_items.remove_at(i)
		i -= 1

	# パーティクル更新
	var pi := _particles.size() - 1
	while pi >= 0:
		var p := _particles[pi]
		p["y"] += p["vy"] * dt
		p["alpha"] -= dt * 1.5
		p["scale"] = clampf(p.get("scale", 1.0) + dt * 0.5, 1.0, 1.5)
		if p["alpha"] <= 0.0:
			_particles.remove_at(pi)
		pi -= 1

	# 背景星更新
	for star: Dictionary in _bg_stars:
		star["y"] += star["speed"] * dt
		if star["y"] > size.y:
			star["y"] = -5.0
			star["x"] = randf() * size.x

	# ラベル更新
	_score_label.text = "⭐ %d" % _score
	_score_label.position = Vector2(size.x * 0.5 - 50.0, 4.0)
	_score_label.size = Vector2(100.0, 24.0)

	if _combo >= 3:
		_combo_label.visible = true
		_combo_label.text = "🔥 %d COMBO" % _combo
		_combo_label.position = Vector2(size.x * 0.5 - 60.0, 26.0)
		_combo_label.size = Vector2(120.0, 20.0)
		var pulse := 1.0 + sin(_elapsed * 8.0) * 0.08
		_combo_label.scale = Vector2(pulse, pulse)
	else:
		_combo_label.visible = false

	_instruction_label.position = Vector2(size.x * 0.5 - 150.0, size.y - 28.0)
	_instruction_label.size = Vector2(300.0, 20.0)
	_instruction_label.modulate.a = clampf(1.0 - _elapsed * 0.2, 0.0, 0.8)

	queue_redraw()


func _spawn_item() -> void:
	var roll := randi() % _total_weight
	var cumulative := 0
	var chosen_idx := 0
	for idx in range(ITEM_DEFS.size()):
		cumulative += ITEM_DEFS[idx]["weight"]
		if roll < cumulative:
			chosen_idx = idx
			break

	var item_margin := PLAY_AREA_MARGIN + ITEM_SIZE
	var x := randf_range(item_margin, size.x - item_margin)
	var speed_bonus := clampf(_elapsed / 25.0, 0.0, 0.5) * 80.0
	var speed := randf_range(FALL_SPEED_MIN + speed_bonus, FALL_SPEED_MAX + speed_bonus)

	_items.append({
		"x": x, "y": -ITEM_SIZE,
		"def_idx": chosen_idx, "speed": speed,
		"alpha": 1.0, "caught": false,
	})


func _spawn_particle(px: float, py: float, text: String, color: Color) -> void:
	_particles.append({
		"x": px, "y": py,
		"text": text, "color": color,
		"alpha": 1.3, "vy": -90.0, "scale": 1.0,
	})


func _draw() -> void:
	if not _active:
		return

	var play_h := size.y - 100.0
	var alpha := _fade_alpha

	# シェイクオフセット
	var shake_off := Vector2.ZERO
	if _shake_timer > 0.0:
		var intensity := _shake_intensity * (_shake_timer / 0.3)
		shake_off = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))

	# ── 背景星 ──
	for star: Dictionary in _bg_stars:
		var sa: float = star["alpha"] * alpha
		draw_circle(Vector2(star["x"], star["y"]) + shake_off, star["size"], Color(0.7, 0.8, 1.0, sa))

	# ── 地面ライン ──
	var ground_y := play_h - 4.0
	draw_line(
		Vector2(PLAY_AREA_MARGIN, ground_y) + shake_off,
		Vector2(size.x - PLAY_AREA_MARGIN, ground_y) + shake_off,
		Color(0.3, 0.45, 0.8, 0.4 * alpha), 2.0
	)
	# 地面グロー
	for gy: int in range(3):
		var ga := 0.08 * (3 - gy) * alpha
		draw_line(
			Vector2(PLAY_AREA_MARGIN, ground_y + gy + 1) + shake_off,
			Vector2(size.x - PLAY_AREA_MARGIN, ground_y + gy + 1) + shake_off,
			Color(0.3, 0.45, 0.8, ga), 1.0
		)

	# ── プレイヤー ──
	var player_y := play_h - PLAYER_HEIGHT - 8.0
	_draw_blockman(_player_x + shake_off.x, player_y + shake_off.y, alpha)

	# ── アイテム ──
	for item: Dictionary in _items:
		var def: Dictionary = ITEM_DEFS[item["def_idx"]]
		var ia := alpha
		if item["y"] < 20.0:
			ia *= clampf(item["y"] / 20.0, 0.0, 1.0)
		var pos := Vector2(item["x"], item["y"]) + shake_off
		# グロー
		draw_circle(pos, ITEM_SIZE * 0.7, Color(def["color"].r, def["color"].g, def["color"].b, 0.12 * ia))
		# 絵文字
		_draw_emoji(pos.x, pos.y, def["emoji"], ITEM_SIZE, ia)

	# ── パーティクル ──
	var font_obj := _get_font()
	for p: Dictionary in _particles:
		if p["alpha"] <= 0.0:
			continue
		var pa := clampf(p["alpha"], 0.0, 1.0)
		var pc := Color(p["color"].r, p["color"].g, p["color"].b, pa)
		var po := Color(0, 0, 0, pa * 0.8)
		var ps := int(20.0 * p.get("scale", 1.0))
		var pp := Vector2(p["x"] - 20.0, p["y"]) + shake_off
		draw_string_outline(font_obj, pp, p["text"], HORIZONTAL_ALIGNMENT_CENTER, 60, ps, 3, po)
		draw_string(font_obj, pp, p["text"], HORIZONTAL_ALIGNMENT_CENTER, 60, ps, pc)


func _get_font() -> Font:
	var f := _score_label.get_theme_font("font")
	if f == null:
		f = ThemeDB.fallback_font
	return f


func _draw_blockman(cx: float, cy: float, alpha: float) -> void:
	var w := PLAYER_WIDTH
	var h := PLAYER_HEIGHT

	# 影（足元）
	draw_rect(Rect2(cx - w * 0.4, cy + h - 2, w * 0.8, 8.0), Color(0, 0, 0, 0.15 * alpha))

	# 体
	draw_rect(Rect2(cx - w * 0.5, cy, w, h), Color(0.25, 0.55, 1.0, alpha))
	# ハイライト
	draw_rect(Rect2(cx - w * 0.5 + 2, cy + 2, w - 4, h * 0.25), Color(0.45, 0.75, 1.0, 0.35 * alpha))
	# 影
	draw_rect(Rect2(cx - w * 0.5, cy + h * 0.75, w, h * 0.25), Color(0.15, 0.35, 0.7, 0.25 * alpha))

	# 目
	var eye_sz := 9.0
	var eye_y := cy + h * 0.22
	var eye_sp := w * 0.22
	draw_rect(Rect2(cx - eye_sp - eye_sz * 0.5, eye_y, eye_sz, eye_sz), Color(1, 1, 1, alpha))
	draw_rect(Rect2(cx + eye_sp - eye_sz * 0.5, eye_y, eye_sz, eye_sz), Color(1, 1, 1, alpha))
	# 瞳
	var pup := 4.0
	draw_rect(Rect2(cx - eye_sp - pup * 0.5, eye_y + 2, pup, pup), Color(0.1, 0.1, 0.2, alpha))
	draw_rect(Rect2(cx + eye_sp - pup * 0.5, eye_y + 2, pup, pup), Color(0.1, 0.1, 0.2, alpha))

	# 口
	var my := cy + h * 0.58
	var mw := w * 0.3
	draw_line(Vector2(cx - mw, my), Vector2(cx, my + 5), Color(1, 1, 1, 0.7 * alpha), 2.0)
	draw_line(Vector2(cx, my + 5), Vector2(cx + mw, my), Color(1, 1, 1, 0.7 * alpha), 2.0)

	# 腕
	var arm_w := 7.0
	var arm_h := 22.0
	var arm_y := cy + h * 0.28
	draw_rect(Rect2(cx - w * 0.5 - arm_w, arm_y, arm_w, arm_h), Color(0.2, 0.45, 0.9, alpha))
	draw_rect(Rect2(cx + w * 0.5, arm_y, arm_w, arm_h), Color(0.2, 0.45, 0.9, alpha))

	# トレイ（キャッチ皿）
	var tray_y := arm_y - 3.0
	draw_line(
		Vector2(cx - w * 0.5 - arm_w, tray_y),
		Vector2(cx + w * 0.5 + arm_w, tray_y),
		Color(0.5, 0.75, 1.0, 0.7 * alpha), 3.0
	)

	# コンボ時のオーラ
	if _combo >= 5:
		var aura_a := (0.1 + sin(_elapsed * 6.0) * 0.05) * alpha
		draw_circle(Vector2(cx, cy + h * 0.5), w * 0.8, Color(1.0, 0.7, 0.2, aura_a))


func _draw_emoji(cx: float, cy: float, emoji: String, sz: float, alpha: float) -> void:
	var font_obj := _get_font()
	var fs := int(sz * 0.85)
	draw_string(font_obj, Vector2(cx - sz * 0.4, cy + sz * 0.3),
		emoji, HORIZONTAL_ALIGNMENT_CENTER, int(sz * 0.8), fs, Color(1, 1, 1, alpha))

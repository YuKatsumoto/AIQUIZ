class_name PracticeSignWall
extends Node3D

## 看板の壁（docs/new_tutorial/phase4_design.md 3.1、台本①の 1.4）。本番のクイズ壁（quiz_wall.gd）と同じ灰色の鋼板の壁と、
## 上の紺色の問題パネル。ドアの代わりに大きなパネルを2枚持ち、キーの絵（矢印キーを大きく、A D・W S を小さく）・✓・点滅・
## 「？」・波・サメの絵を出す。空から落ちてきて（drop_in）、用が済むと空へ戻る（fly_away）。
## 監督が world の子にして置く。このノードの位置は壁の足もとの真ん中（ゲーム画面の座標。クイズ壁と同じく y = 0 で床に立つ。
## 床の面はこのノードの空間の y = StageConstants.FLOOR_TOP_Y）。前（プレイヤーのほう）は −z。
## パネルは2枚：0 番が画面の左（x = +3.5。2択の青いドアの所）、1 番が画面の右（x = −3.5。赤いドアの所）。
## 段階5（コース②。phase5_design.md 4.1）で、横長の「スペース」キー、1枚に小さなキーを並べるパネル（"keys" と tick_panel_key）、
## 「II」（一時停止）・雲に乗ったハテナ・おどるハテナの絵、1枚だけの点滅（blink_panel）を足した。
## 段階6（コース③。phase6_design.md 3.3）で、キーの組とその下の横長のキー（"keys" と "sub"）、パネルの左上の「P1」「P2」の札
## （"player"）、押し合う2人（push）・「離す → 押す」（push_again）の絵を足した。
##
##   setup(quality) / set_title(lines) / set_panels(panels) / tick_panel(key) / is_panel_done(key)
##   tick_panel_key(key, index) / is_panel_key_done(key, index) / blink_panels() / blink_panel(key)
##   drop_in(seconds) -> Signal / fly_away(seconds) -> Signal

## 着地した（drop_in の返り値の signal と同じ時）・空へ消えた（fly_away と同じ時）
signal landed
signal flew_away

const QuizWallScript = preload("res://scripts/world/quiz_wall.gd")
const WallMaterials = preload("res://scripts/world/wall_materials.gd")
const Shapes = preload("res://scripts/world/practice/practice_shapes.gd")

const FLOOR_Y := StageConstants.FLOOR_TOP_Y
const HALF_WIDTH := StageConstants.QUIZ_WALL_HALF_WIDTH
## 壁の厚さと、床に埋まっている下端（クイズ壁と同じ）
const THICKNESS := 1.1
const BOTTOM_Y := -3.15
const FRONT_Z := -THICKNESS * 0.5
## パネル：中心の x（0 番が画面の左）、大きさ（2択のドアは幅 3.6 m・床から 3.58 m）、床からの下端、厚み、縁の太さ
const PANEL_XS: Array[float] = [3.5, -3.5]
const PANEL_SIZE := Vector2(4.8, 3.7)
const PANEL_FLOOR_GAP := 0.3
const PANEL_DEPTH := 0.14
const PANEL_FRAME := 0.13
## 絵を重ねるときの前後のずれ（m）
const LAYER_STEP := 0.014
## 問題パネル：14m 先から読める大きさ（クイズ壁は 64px × 0.008）。2行まで
const TITLE_FONT_SIZE := 84
const TITLE_PIXEL_SIZE := 0.008
const TITLE_MAX_LINES := 2
const TITLE_GAP := 0.3
const TITLE_PADDING := Vector2(0.42, 0.16)
const TITLE_BORDER := 0.05
const TOP_MARGIN := 0.18
## 空から落ちる高さ（本番の空撮の壁 PREVIEW_WALL_DROP_START_Y と同じ）と、着地のつぶれ・戻り
const DROP_HEIGHT := 46.0
const LAND_SQUASH := Vector3(1.10, 0.84, 1.10)
const SETTLE_SECONDS := 0.35
## 着地の揺れ（小さめ）と音
const LAND_SHAKE := 0.35
const LAND_SFX := &"wall_land"
## 空へ戻る音（台本①の 1.9「看板が空へ戻る音」。tools/audio/make_practice_sfx.py）
const FLY_SFX := &"practice_sign_fly"
const FLY_SFX_DB := 0.0
## 空へ戻るとき、はじめにかがむ割合
const FLY_WINDUP := 0.22
## ✓ の光・点滅
const TICK_FLASH_SECONDS := 0.55
const BADGE_POP_SECONDS := 0.32
const BLINK_SECONDS := 1.0
const BLINK_HZ := 4.0
## パネルの動き（光る・✓・点滅）が1フレームに進む秒の上限
const MAX_STEP := 1.0 / 30.0
## 色
const WALL_COLOR := QuizWallScript.WALL_COLOR
const NAVY := QuizWallScript.QUESTION_PANEL_COLOR
const STEEL := QuizWallScript.QUESTION_BORDER_COLOR
const TICK_COLOR := Color(0.28, 0.90, 0.42)
const BLINK_COLOR := Color(1.0, 0.80, 0.16)
const FLASH_FACE_COLOR := Color(0.55, 0.95, 0.65)
const KEY_TOP_COLOR := Color(0.97, 0.97, 0.99)
const KEY_SIDE_COLOR := Color(0.58, 0.63, 0.72)
const SKY_COLOR := Color(0.84, 0.93, 1.0)
const SEA_COLOR := Color(0.12, 0.46, 0.86)
const WAVE_COLOR := Color(0.10, 0.42, 0.86)
const FIN_COLOR := Color(0.47, 0.52, 0.59)
const FIN_SHADE_COLOR := Color(0.36, 0.40, 0.47)
const FOAM_COLOR := Color(0.96, 0.98, 1.0)
const QUESTION_COLOR := Color(1.0, 0.80, 0.16)
## ✓ が付いた小さなキーの上の面
const KEY_DONE_COLOR := Color(0.80, 0.97, 0.84)
## 「スペース」の絵のまわりの、ほかのキー（暗くして、横長のキーを目立たせる）
const KEY_DIM_TOP_COLOR := Color(0.26, 0.32, 0.50)
const KEY_DIM_SIDE_COLOR := Color(0.13, 0.17, 0.32)
## ハテナの絵（客席のハテナと同じ色：白い玉の体、金色の「？」と手足、紺のくつ）
const HATENA_WHITE := Color(0.98, 0.99, 1.0)
const HATENA_SHADE := Color(0.79, 0.85, 0.96)
const HATENA_GOLD := Color(0.97, 0.70, 0.22)
const HATENA_LINE := Color(0.08, 0.11, 0.27)
const HATENA_EYE := Color(0.04, 0.05, 0.09)
const HATENA_CHEEK := Color(1.0, 0.70, 0.75)
const HATENA_SHOE := Color(0.18, 0.27, 0.62)
## 雲の絵と、雲のハテナの絵の空（白い雲とハテナが目立つよう、波・サメの空より青く）
const CLOUD_SKY_COLOR := Color(0.55, 0.78, 0.97)
const CLOUD_WHITE := Color(1.0, 1.0, 1.0)
const CLOUD_SHADE := Color(0.82, 0.88, 0.98)
const CLOUD_LINE := Color(0.52, 0.62, 0.82)
## おどるハテナの絵の地と、音符
const DANCE_BG_COLOR := Color(1.0, 0.92, 0.76)
const NOTE_COLORS: Array[Color] = [Color(0.92, 0.28, 0.55), Color(0.18, 0.50, 0.95)]
## キーの絵：矢印の向き（絵の座標。0 で右）
const ARROW_ANGLES := {"←": PI, "→": 0.0, "↑": PI * 0.5, "↓": -PI * 0.5}
## キーの文字：大きさ（px）と、キーの幅に対して文字が使ってよい幅（Esc などの長い文字は小さくして収める）
const KEY_GLYPH_FONT := 150
const KEY_GLYPH_PIXEL := 0.009
const KEY_GLYPH_FIT := 0.76
## 1枚に並べる小さなキー（"keys"）：大きさ、すきま、並びの高さ（絵の座標の v）、✓ の札の大きさ
const SMALL_KEY_SIZE := 1.25
const SMALL_KEY_GAP := 0.2
const SMALL_KEY_ROW_V := -0.15
const SMALL_BADGE_RADIUS := 0.27
## キーの組（"keys" と "sub"）：キーの大きさ・すきま、上の段の上端（v）、下の横長のキーの高さ・すきま・幅の範囲
const SET_KEY_SIZE := 0.9
const SET_KEY_GAP := 0.12
const SET_TOP_V := 1.42
const SET_SUB_HEIGHT := 0.62
const SET_SUB_GAP := 0.26
const SET_SUB_WIDTH := Vector2(1.9, 3.1)
## キーの組の4つの所（0 上の段、1〜3 下の段の左から）。移動のキーはこの所へ置く
const KEY_SET_SPOTS := {"W": 0, "↑": 0, "A": 1, "←": 1, "S": 2, "↓": 2, "D": 3, "→": 3}
## 「P1」「P2」の札（"player"）：パネルの左上。色は画面の下の2人のカードと同じ（P1 だいだい・P2 青）
const PLAYER_TAG_CENTER := Vector2(-1.62, 1.3)
const PLAYER_TAG_SIZE := Vector2(0.92, 0.52)
const PLAYER_COLORS: Array[Color] = [Color(0.95, 0.55, 0.20), Color(0.20, 0.65, 0.90)]
## 押し合いの絵（push・push_again）：床、人の紺の縁どり、ぶつかる所の光、「押す」の衝撃の線
const PUSH_FLOOR_COLOR := Color(0.46, 0.50, 0.58)
const PUSH_FLOOR_TOP := Color(0.70, 0.74, 0.81)
const FIGURE_LINE := Color(0.08, 0.11, 0.27)
const FIGURE_EYE := Color(0.06, 0.07, 0.12)
const IMPACT_COLOR := Color(1.0, 0.80, 0.16)
const DUST_COLOR := Color(0.93, 0.94, 0.97)

enum Move { NONE, DROP, SETTLE, LIFT }


## パネル1枚の部品と状態。
class SignPanel extends RefCounted:
	var key := &""
	var root: Node3D = null
	var art: Node3D = null
	var badge: Node3D = null
	var border: StandardMaterial3D = null
	var face: StandardMaterial3D = null
	var done := false
	## 光る残り（1 → 0）と、✓ が出てからの秒（出ていなければ < 0）
	var flash := 0.0
	var badge_time := -1.0
	## 点滅の残りの秒（blink_panels・blink_panel）
	var blink_left := 0.0
	## 1枚に並べた小さなキー（"keys"。なければ空）
	var keys: Array[SignKey] = []


## 1枚のパネルに並べた小さなキー1つの部品と状態（tick_panel_key）。
class SignKey extends RefCounted:
	var top: StandardMaterial3D = null
	var badge: Node3D = null
	var done := false
	var flash := 0.0
	var badge_time := -1.0


## 土ぼこりの粒の shader（看板どうしで共有）
static var _dust_shader: Shader = null

var _built := false
var _quality := ""
var _panels: Array[SignPanel] = []
var _title_root: Node3D = null
var _title_label: Label3D = null
var _title_face: MeshInstance3D = null
var _title_border: MeshInstance3D = null
var _title_bottom := 0.0
var _wall_top := 0.0
var _dust: CPUParticles3D = null
var _move := Move.NONE
var _move_time := 0.0
var _move_duration := 0.0
var _move_serial := 0
## 着地する所（drop_in を呼んだときの位置。空へ戻ったあともここへ戻しておく）
var _home := Vector3.ZERO


func _init() -> void:
	# ゲーム画面は止めている間も動く（PROCESS_MODE_ALWAYS）ので、看板はポーズで止める。
	process_mode = Node.PROCESS_MODE_PAUSABLE


func setup(quality: String) -> void:
	if _built:
		return
	_built = true
	_quality = GraphicsQuality.normalize(quality)
	_title_bottom = FLOOR_Y + PANEL_FLOOR_GAP + PANEL_SIZE.y + TITLE_GAP
	_wall_top = _title_bottom + TITLE_BORDER * 2.0 + TITLE_PADDING.y * 2.0 + _title_line_height() * TITLE_MAX_LINES + TOP_MARGIN
	_build_wall()
	_build_title()
	for i: int in range(PANEL_XS.size()):
		_panels.append(_build_panel(i))
	_build_dust()


func _ensure_built() -> void:
	if not _built:
		setup(WallMaterials.current_quality())


## 壁の上端（このノードの空間の y）。
func wall_top_y() -> float:
	_ensure_built()
	return _wall_top


# ---------- 中身 ----------

## 問題パネルの文字。2行まで（3行目からは捨てる）。空なら問題パネルを隠す。
func set_title(lines: PackedStringArray) -> void:
	_ensure_built()
	var shown := PackedStringArray()
	for line: String in lines:
		if shown.size() >= TITLE_MAX_LINES:
			push_warning("PracticeSignWall: title has more than %d lines" % TITLE_MAX_LINES)
			break
		shown.append(line)
	var text := "\n".join(shown)
	_title_root.visible = not text.strip_edges().is_empty()
	_title_label.text = text
	if not _title_root.visible:
		return
	var font := Shapes.msdf_font()
	var width := 0.0
	for line: String in shown:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE).x * TITLE_PIXEL_SIZE)
	var height := _title_line_height() * shown.size()
	var face_size := Vector2(width, height) + TITLE_PADDING * 2.0
	var center_y := _title_bottom + TITLE_BORDER + face_size.y * 0.5
	_title_face.mesh = Shapes.polygon_mesh(Shapes.rounded_rect(face_size, 0.08))
	_title_border.mesh = Shapes.polygon_mesh(Shapes.rounded_rect(face_size + Vector2.ONE * TITLE_BORDER * 2.0, 0.1))
	_title_face.position.y = center_y
	_title_border.position.y = center_y
	_title_label.position.y = center_y


## パネル2枚の中身。0 番が画面の左。足りないパネルは隠す。✓ は消える（is_panel_done も false に戻る）。各パネルは：
##   {"key": StringName, "glyph": "←", "sub": "A"}：大きなキー（矢印か文字。"Esc" など長い文字はキーに収まる大きさにする）と小さなキー
##   {"key": StringName, "keys": ["1", "2", "3"]}：小さなキーを横に並べる（4つまで）。1つずつ tick_panel_key で ✓
##   {"key": StringName, "keys": ["W", "A", "S", "D"], "sub": "スペース"}：キーの組とその下の横長のキー（段階6）。
##     キーが4つなら、キーボードと同じ並び（上の段の真ん中と下の段の3つ）。W A S D・↑ ← ↓ → は渡した順によらず
##     キーボードと同じ所（W・↑ が上、A・← / S・↓ / D・→ が下の段の左から）、ほかの文字は keys[0] が上・keys[1]〜[3] が下。
##     4つでなければ横に1列。"←" "→" "↑" "↓" は矢印の絵で描く。
##     tick_panel_key の index は keys の順（並べた所によらない）で、"sub" のキーは最後（keys.size()）。
##     例：P1 は ["W", "A", "S", "D"] と "スペース"、P2 は ["↑", "↓", "←", "→"] と "右 Ctrl"
##   {"key": StringName, "picture": 絵の名前}：&"question"（？）・&"wave"（波）・&"shark"（サメ）・&"space"（横長のスペースキー）・
##     &"pause"（II）・&"hatena_cloud"（雲に乗ったハテナ）・&"hatena_dance"（おどるハテナ）・
##     &"push"（2人が押し合う。左がだいだいの P1、右が青の P2）・&"push_again"（離す → 押す：上がったキー → 矢印 → 押したキー）。
##     push_again は "captions": ["離す", "押す"] のように、2つのキーの下に文字を添えられる（なければ絵だけ）
## どのパネルにも "player": 1 か 2 を付けると、左上に「P1」「P2」の札を出す（2人の色）。
func set_panels(panels: Array) -> void:
	_ensure_built()
	for i: int in range(_panels.size()):
		var panel := _panels[i]
		var spec: Dictionary = panels[i] if i < panels.size() and panels[i] is Dictionary else {}
		panel.root.visible = not spec.is_empty()
		panel.key = StringName(spec.get("key", &""))
		panel.done = false
		panel.flash = 0.0
		panel.badge_time = -1.0
		panel.blink_left = 0.0
		panel.badge.visible = false
		panel.keys.clear()
		for child: Node in panel.art.get_children():
			panel.art.remove_child(child)
			child.queue_free()
		if spec.is_empty():
			continue
		if spec.has("picture"):
			_draw_picture(panel.art, StringName(spec.picture), spec)
		elif spec.has("keys"):
			# spec.keys は Dictionary の keys() と取り違えるので、角かっこで取る
			var labels: Variant = spec["keys"]
			var list: Array = Array(labels) if labels is PackedStringArray else labels as Array
			if spec.has("sub"):
				panel.keys = _draw_key_set(panel.art, list, str(spec.get("sub", "")))
			else:
				panel.keys = _draw_small_keys(panel.art, list)
		else:
			_draw_key(panel.art, str(spec.get("glyph", "")), str(spec.get("sub", "")))
		var player := int(spec.get("player", 0))
		if player in [1, 2]:
			_draw_player_tag(panel.art, player)
	_apply_panel_colors()


## そのパネルが光って ✓ が付く（もう付いていれば何もしない）。小さなキーを並べたパネルは、キーにも全部 ✓ が付く。
func tick_panel(key: StringName) -> void:
	var panel := _panel(key)
	if panel == null or panel.done:
		return
	for index: int in range(panel.keys.size()):
		_tick_key(panel.keys[index])
	_tick(panel)


func is_panel_done(key: StringName) -> bool:
	var panel := _panel(key)
	return panel != null and panel.done


## 小さなキーを並べたパネル（"keys"）の index 番目（0 から。画面の左から）のキーだけ光って ✓ が付く。
## 全部に ✓ が付いたら、パネルも光って ✓ が付く（is_panel_done が true）。もう付いているキーには何もしない。
func tick_panel_key(key: StringName, index: int) -> void:
	var panel := _panel(key)
	if panel == null or index < 0 or index >= panel.keys.size() or panel.keys[index].done:
		return
	_tick_key(panel.keys[index])
	for small: SignKey in panel.keys:
		if not small.done:
			return
	_tick(panel)


func is_panel_key_done(key: StringName, index: int) -> bool:
	var panel := _panel(key)
	return panel != null and index >= 0 and index < panel.keys.size() and panel.keys[index].done


func _tick(panel: SignPanel) -> void:
	if panel.done:
		return
	panel.done = true
	panel.flash = 1.0
	panel.badge_time = 0.0
	panel.badge.visible = true
	panel.badge.scale = Vector3.ONE * 0.01


func _tick_key(small: SignKey) -> void:
	if small.done:
		return
	small.done = true
	small.flash = 1.0
	small.badge_time = 0.0
	small.badge.visible = true
	small.badge.scale = Vector3.ONE * 0.01


## パネルを1秒ほど点滅させる（「キーを おして みて」）。
func blink_panels() -> void:
	for panel: SignPanel in _panels:
		panel.blink_left = BLINK_SECONDS


## そのパネルだけ1秒ほど点滅させる（2-1 の「スペース」・2-3 の「Esc」）。
func blink_panel(key: StringName) -> void:
	var panel := _panel(key)
	if panel != null:
		panel.blink_left = BLINK_SECONDS


func _panel(key: StringName) -> SignPanel:
	for panel: SignPanel in _panels:
		if panel.key == key and panel.root.visible:
			return panel
	return null


# ---------- 落ちる・戻る ----------

## 空から落ちて着地する（土ぼこり・wall_land の音・小さな揺れ）。着地の時刻に返り値の signal が来る。
## 着地する所は、呼んだときのこのノードの位置（空へ戻る途中なら、前に着地した所）。
func drop_in(seconds := 0.55) -> Signal:
	_ensure_built()
	if _move == Move.NONE or _move == Move.SETTLE:
		_home = position
	_move_serial += 1
	_move = Move.DROP
	_move_time = 0.0
	_move_duration = maxf(seconds, 0.05)
	position = _home + Vector3.UP * DROP_HEIGHT
	scale = Vector3.ONE
	visible = true
	var timer := _timer(_move_duration)
	timer.timeout.connect(_on_landed.bind(_move_serial))
	return timer.timeout


## 少しかがんでから、空へ戻って見えなくなる。返り値の signal が来たら queue_free してよい
## （しなければ、見えないまま元の所に置いておく。もう一度 drop_in できる）。
func fly_away(seconds := 0.6) -> Signal:
	_ensure_built()
	if _move == Move.NONE or _move == Move.SETTLE:
		_home = position
	position = _home
	scale = Vector3.ONE
	_move_serial += 1
	_move = Move.LIFT
	_move_time = 0.0
	_move_duration = maxf(seconds, 0.1)
	_puff_dust()
	_play_sfx(FLY_SFX, FLY_SFX_DB)
	var timer := _timer(_move_duration)
	timer.timeout.connect(_on_flown.bind(_move_serial))
	return timer.timeout


func is_moving() -> bool:
	return _move == Move.DROP or _move == Move.LIFT


func _on_landed(serial: int) -> void:
	if serial != _move_serial:
		return
	position = _home
	scale = LAND_SQUASH
	_move = Move.SETTLE
	_move_time = 0.0
	_puff_dust()
	_play_sfx(LAND_SFX, -2.0)
	var game_state: Variant = _game_state()
	if game_state != null:
		game_state.camera_shake = maxf(float(game_state.camera_shake), LAND_SHAKE)
	landed.emit()


func _on_flown(serial: int) -> void:
	if serial != _move_serial:
		return
	_move = Move.NONE
	visible = false
	position = _home
	scale = Vector3.ONE
	flew_away.emit()


func _timer(seconds: float) -> SceneTreeTimer:
	# ポーズ中は止まる（process_always = false）。木に入る前でも作れるよう、SceneTree から作る。
	return (Engine.get_main_loop() as SceneTree).create_timer(seconds, false)


func _game_state() -> Variant:
	var manager := get_node_or_null(^"/root/QuizManager")
	if manager == null:
		return null
	var state: Variant = manager.get("game_state")
	return state if state != null and "camera_shake" in state else null


func _play_sfx(cue: StringName, volume_db: float) -> void:
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(cue, volume_db)


func _puff_dust() -> void:
	if _dust != null:
		_dust.restart()
		_dust.emitting = true


# ---------- 毎フレーム ----------

func _process(delta: float) -> void:
	if not _built:
		return
	_update_move(delta)
	_update_panels(delta)


func _update_move(delta: float) -> void:
	match _move:
		Move.DROP:
			_move_time += delta
			var p := clampf(_move_time / _move_duration, 0.0, 1.0)
			# 本番の空撮の壁と同じく、地面の直前でさらに速くなる。
			position = _home + Vector3.UP * DROP_HEIGHT * (1.0 - p * p)
		Move.SETTLE:
			_move_time += delta
			var p := clampf(_move_time / SETTLE_SECONDS, 0.0, 1.0)
			var eased := 1.0 - pow(1.0 - p, 3.0)
			position = _home + Vector3.UP * sin(p * PI) * 0.12 * (1.0 - p)
			scale = LAND_SQUASH.lerp(Vector3.ONE, eased)
			if p >= 1.0:
				_move = Move.NONE
				position = _home
				scale = Vector3.ONE
		Move.LIFT:
			_move_time += delta
			var p := clampf(_move_time / _move_duration, 0.0, 1.0)
			if p < FLY_WINDUP:
				var k := sin(p / FLY_WINDUP * PI * 0.5)
				scale = Vector3(1.0 + 0.04 * k, 1.0 - 0.08 * k, 1.0 + 0.04 * k)
				position = _home
			else:
				var q := (p - FLY_WINDUP) / (1.0 - FLY_WINDUP)
				scale = Vector3(1.0 - 0.05 * q, 1.0 + 0.14 * q, 1.0 - 0.05 * q)
				position = _home + Vector3.UP * DROP_HEIGHT * q * q


func _update_panels(delta: float) -> void:
	# 絵を作り直した直後などの重いフレームで、光る・点滅を飛ばさないよう、1フレームに進める秒に上限をつける
	delta = minf(delta, MAX_STEP)
	for panel: SignPanel in _panels:
		var blinking := panel.blink_left > 0.0
		if blinking:
			panel.blink_left = maxf(panel.blink_left - delta, 0.0)
		# 呼んだすぐあとから光る（光る・消えるをくり返す）
		var blink_on := blinking and fmod((BLINK_SECONDS - panel.blink_left) * BLINK_HZ, 1.0) < 0.5
		if panel.flash > 0.0:
			panel.flash = maxf(panel.flash - delta / TICK_FLASH_SECONDS, 0.0)
		_pop_badge(panel.badge, panel, delta)
		var pulse := 1.0
		if blinking:
			pulse = 1.0 + 0.035 * absf(sin(panel.blink_left * BLINK_HZ * PI))
		panel.root.scale = Vector3.ONE * pulse
		var border := TICK_COLOR if panel.done else STEEL
		if blink_on:
			border = BLINK_COLOR
		panel.border.albedo_color = border.lerp(Color.WHITE, panel.flash * 0.6)
		panel.face.albedo_color = NAVY.lerp(FLASH_FACE_COLOR, panel.flash * 0.75)
		for small: SignKey in panel.keys:
			if small.flash > 0.0:
				small.flash = maxf(small.flash - delta / TICK_FLASH_SECONDS, 0.0)
			_pop_badge(small.badge, small, delta)
			var top := KEY_DONE_COLOR if small.done else KEY_TOP_COLOR
			small.top.albedo_color = top.lerp(TICK_COLOR.lightened(0.35), small.flash * 0.8)


## ✓ の札がポンと大きめに出て、元の大きさに戻る（ease out back）。state は badge_time を持つ SignPanel か SignKey。
func _pop_badge(badge: Node3D, state: RefCounted, delta: float) -> void:
	var time: float = state.get("badge_time")
	if time < 0.0 or time >= BADGE_POP_SECONDS:
		return
	time += delta
	state.set("badge_time", time)
	var p := clampf(time / BADGE_POP_SECONDS, 0.0, 1.0)
	var back := 2.2
	var s := 1.0 + (back + 1.0) * pow(p - 1.0, 3.0) + back * pow(p - 1.0, 2.0)
	badge.scale = Vector3.ONE * maxf(0.01, s)
	if p >= 1.0:
		badge.scale = Vector3.ONE


func _apply_panel_colors() -> void:
	for panel: SignPanel in _panels:
		panel.root.scale = Vector3.ONE
		panel.border.albedo_color = TICK_COLOR if panel.done else STEEL
		panel.face.albedo_color = NAVY
		for small: SignKey in panel.keys:
			small.top.albedo_color = KEY_DONE_COLOR if small.done else KEY_TOP_COLOR


# ---------- 作る ----------

func _title_line_height() -> float:
	return Shapes.msdf_font().get_height(TITLE_FONT_SIZE) * TITLE_PIXEL_SIZE


func _build_wall() -> void:
	var height := _wall_top - BOTTOM_Y
	var wall := MeshInstance3D.new()
	wall.name = "Wall"
	var box := BoxMesh.new()
	box.size = Vector3(HALF_WIDTH * 2.0, height, THICKNESS)
	wall.mesh = box
	wall.position = Vector3(0.0, BOTTOM_Y + height * 0.5, 0.0)
	# クイズ壁と同じ塗装鋼板（上端をパネルの継ぎ目にそろえる）
	wall.material_override = WallMaterials.panel(WALL_COLOR, _quality, 0, 1.0, 0.6, 0.05, height * 0.5)
	add_child(wall)


func _build_title() -> void:
	_title_root = Node3D.new()
	_title_root.name = "Title"
	add_child(_title_root)
	_title_border = Shapes.add_mesh(_title_root, null, Shapes.flat_material(STEEL), Vector3(0.0, 0.0, FRONT_Z - 0.02))
	_title_face = Shapes.add_mesh(_title_root, null, Shapes.flat_material(NAVY), Vector3(0.0, 0.0, FRONT_Z - 0.035))
	_title_label = Shapes.wall_label("", TITLE_FONT_SIZE, TITLE_PIXEL_SIZE, Color.WHITE, Color(0.02, 0.05, 0.10, 0.95), 10)
	_title_label.position.z = FRONT_Z - 0.06
	_title_root.add_child(_title_label)
	_title_root.visible = false


func _build_panel(index: int) -> SignPanel:
	var panel := SignPanel.new()
	panel.root = Node3D.new()
	panel.root.name = "Panel%d" % index
	panel.root.position = Vector3(PANEL_XS[index], FLOOR_Y + PANEL_FLOOR_GAP + PANEL_SIZE.y * 0.5, FRONT_Z)
	add_child(panel.root)
	panel.border = Shapes.flat_material(STEEL, false, false, 0, false, true)
	panel.face = Shapes.flat_material(NAVY, false, false, 0, false, true)
	# 壁から少し出た板（縁の色）と、その前の紺の面
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(PANEL_SIZE.x, PANEL_SIZE.y, PANEL_DEPTH)
	plate.mesh = box
	plate.position.z = -PANEL_DEPTH * 0.5
	plate.material_override = panel.border
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.root.add_child(plate)
	var face_size := PANEL_SIZE - Vector2.ONE * PANEL_FRAME * 2.0
	Shapes.add_mesh(panel.root, Shapes.polygon_mesh(Shapes.rounded_rect(face_size, 0.12)), panel.face,
		Vector3(0.0, 0.0, -PANEL_DEPTH - 0.004))
	panel.art = Node3D.new()
	panel.art.name = "Art"
	panel.art.position.z = -PANEL_DEPTH - 0.004 - LAYER_STEP
	panel.root.add_child(panel.art)
	panel.badge = _build_badge()
	panel.badge.position = Vector3(-(PANEL_SIZE.x * 0.5 - 0.5), PANEL_SIZE.y * 0.5 - 0.5, -PANEL_DEPTH - 0.004 - LAYER_STEP * 8.0)
	panel.root.add_child(panel.badge)
	panel.root.visible = false
	return panel


## ✓ の札：緑の丸に白い縁と白い ✓（radius は白い縁の外の半径）。
func _build_badge(radius: float = 0.6) -> Node3D:
	var badge := Node3D.new()
	badge.name = "Check"
	var k := radius / 0.6
	Shapes.add_mesh(badge, Shapes.polygon_mesh(Shapes.circle(radius, 40)), Shapes.flat_material(Color.WHITE))
	Shapes.add_mesh(badge, Shapes.polygon_mesh(Shapes.circle(radius * 0.867, 40)), Shapes.flat_material(TICK_COLOR.darkened(0.08)),
		Vector3(0.0, 0.0, -LAYER_STEP))
	var mark := Shapes.wall_label("✓", 110, 0.0085 * k, Color.WHITE, Color(0.05, 0.30, 0.12, 1.0), 10)
	mark.position = Vector3(0.0, 0.02 * k, -LAYER_STEP * 2.0)
	badge.add_child(mark)
	badge.visible = false
	return badge


func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "LandingDust"
	_dust.emitting = false
	_dust.amount = GraphicsQuality.particle_amount(70, _quality)
	# 数は particle_amount で画質に合わせ済み：スマホの場面の粒の間引きを重ねない。
	GraphicsQuality.mark_particles_scaled(_dust)
	_dust.lifetime = 1.0
	_dust.one_shot = true
	_dust.explosiveness = 1.0
	_dust.randomness = 1.0
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(HALF_WIDTH, 0.2, 0.6)
	# 床に沿って手前へ広がる（パネルの前までは上がらない）
	_dust.direction = Vector3(0.0, 0.12, -1.0)
	_dust.spread = 38.0
	_dust.initial_velocity_min = 2.0
	_dust.initial_velocity_max = 7.0
	_dust.gravity = Vector3(0.0, -4.0, 0.0)
	_dust.damping_min = 3.0
	_dust.damping_max = 5.0
	_dust.scale_amount_min = 0.6
	_dust.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(0.70, 0.70, 0.76, 0.55))
	fade.set_color(1, Color(0.70, 0.70, 0.76, 0.0))
	_dust.color_ramp = fade
	var quad := QuadMesh.new()
	quad.material = _dust_material()
	_dust.mesh = quad
	_dust.position = Vector3(0.0, FLOOR_Y + 0.25, FRONT_Z - 0.5)
	add_child(_dust)


## 土ぼこりの粒：カメラを向く板に、ふちがぼけた丸を描く（テクスチャなし）。
static func _dust_material() -> ShaderMaterial:
	if _dust_shader == null:
		_dust_shader = Shader.new()
		_dust_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
void vertex() {
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * (1.0 - smoothstep(0.25, 1.0, d));
}
"""
	var material := ShaderMaterial.new()
	material.shader = _dust_shader
	return material


# ---------- パネルの絵（絵の座標：パネルの真ん中が原点、u 右・v 上） ----------

## 重ねの層 layer（小数でもよい。0 が面のすぐ前、1 層で LAYER_STEP 手前）に多角形を描く。
## 絵は 7 層より奥に収める（パネルの ✓ の札が 7〜9 層。小さなキーの ✓ は 5〜7 層）。
func _layer(parent: Node3D, points: PackedVector2Array, color: Color, layer: float) -> void:
	var mesh := Shapes.polygon_mesh(points)
	if mesh != null:
		Shapes.add_mesh(parent, mesh, Shapes.flat_material(color), Vector3(0.0, 0.0, -LAYER_STEP * layer))


func _line(parent: Node3D, points: PackedVector2Array, width: float, color: Color, layer: float) -> void:
	Shapes.add_mesh(parent, Shapes.polyline_mesh(points, width), Shapes.flat_material(color), Vector3(0.0, 0.0, -LAYER_STEP * layer))


func _text(parent: Node3D, text: String, font_size: int, pixel_size: float, at: Vector2, color: Color,
		outline_color: Color = Color(0, 0, 0, 0), outline: int = 0, layer: float = 3.0) -> void:
	var label := Shapes.wall_label(text, font_size, pixel_size, color, outline_color, outline)
	label.position = Vector3(-at.x, at.y, -LAYER_STEP * layer)
	parent.add_child(label)


## 文字の大きさ（pixel_size）：font_size で書いたとき幅が max_width（m）を超えるなら、収まるまで小さくする。
func _fit_pixel_size(text: String, font_size: int, pixel_size: float, max_width: float) -> float:
	var width := Shapes.msdf_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * pixel_size
	return pixel_size * minf(1.0, max_width / width) if width > 0.0 else pixel_size


## キーの絵：大きなキー（矢印か文字）と、その下に小さなキー（sub。なければ大きなキーを真ん中に）。
func _draw_key(art: Node3D, glyph: String, sub: String) -> void:
	var big := 2.1
	var center := Vector2(0.0, 0.48) if not sub.is_empty() else Vector2.ZERO
	_layer(art, Shapes.rounded_rect(Vector2(big, big), 0.3, center + Vector2(0.0, -0.14)), KEY_SIDE_COLOR, 0)
	_layer(art, Shapes.rounded_rect(Vector2(big, big), 0.3, center), KEY_TOP_COLOR, 1)
	if ARROW_ANGLES.has(glyph):
		_layer(art, Shapes.arrow_polygon(1.5, 0.44, 1.16, 0.68, float(ARROW_ANGLES[glyph]), center), NAVY, 2)
	elif not glyph.is_empty():
		# 「Esc」など長い文字は、キーの幅に収まる大きさにする
		var pixel := _fit_pixel_size(glyph, KEY_GLYPH_FONT, KEY_GLYPH_PIXEL, big * KEY_GLYPH_FIT)
		_text(art, glyph, KEY_GLYPH_FONT, pixel, center, NAVY)
	if sub.is_empty():
		return
	var small := 0.86
	var sub_center := Vector2(0.0, -1.22)
	_layer(art, Shapes.rounded_rect(Vector2(small, small), 0.14, sub_center + Vector2(0.0, -0.08)), KEY_SIDE_COLOR, 0)
	_layer(art, Shapes.rounded_rect(Vector2(small, small), 0.14, sub_center), KEY_TOP_COLOR, 1)
	_text(art, sub, 80, 0.0075, sub_center + Vector2(0.0, 0.02), NAVY)


func _draw_picture(art: Node3D, picture: StringName, spec: Dictionary = {}) -> void:
	var inner := PANEL_SIZE - Vector2.ONE * (PANEL_FRAME * 2.0 + 0.32)
	match picture:
		&"question":
			_text(art, "？", 300, 0.0098, Vector2(0.0, 0.05), QUESTION_COLOR, Color(0.02, 0.05, 0.12, 1.0), 24, 1)
		&"wave":
			_layer(art, Shapes.rounded_rect(inner, 0.22), SKY_COLOR, 0)
			for row: int in range(3):
				_line(art, _wave_points(0.82 - row * 0.82, 1.62, 0.2, 1.3), 0.3, WAVE_COLOR, 1)
		&"shark":
			_draw_shark(art, inner)
		&"space":
			_draw_space_key(art, inner)
		&"pause":
			_draw_pause(art)
		&"hatena_cloud":
			_draw_hatena_cloud(art, inner)
		&"hatena_dance":
			_draw_hatena_dance(art, inner)
		&"push":
			_draw_push(art, inner)
		&"push_again":
			var captions: Variant = spec.get("captions", [])
			_draw_push_again(art, inner, Array(captions) if captions is PackedStringArray else captions as Array)
		_:
			push_warning("PracticeSignWall: unknown picture %s" % picture)


## 小さなキーを横に並べる（"keys"。4つまで）。キーの上の面の材質と ✓ の札を返す（tick_panel_key で光らせる）。
func _draw_small_keys(art: Node3D, labels: Array) -> Array[SignKey]:
	var keys: Array[SignKey] = []
	if labels == null or labels.is_empty():
		return keys
	var count := mini(labels.size(), 4)
	if labels.size() > count:
		push_warning("PracticeSignWall: a panel shows up to 4 small keys")
	var inner_width := PANEL_SIZE.x - PANEL_FRAME * 2.0 - 0.4
	var size := minf(SMALL_KEY_SIZE, (inner_width - SMALL_KEY_GAP * (count - 1)) / count)
	var step := size + SMALL_KEY_GAP
	for i: int in range(count):
		var center := Vector2(-step * (count - 1) * 0.5 + step * i, SMALL_KEY_ROW_V)
		keys.append(_draw_small_key(art, center, Vector2(size, size), str(labels[i]), 0.18, 0.11, 0.0068, SMALL_BADGE_RADIUS))
	return keys


## 小さなキー1つ：下にずらした側面、白い上の面（tick_panel_key で光らせる材質）、文字（"←" などは矢印の絵）、
## 右上の角の ✓ の札（パネルの ✓ の札より奥・絵より手前）。radius は角の丸み、drop は側面のずれ、pixel は文字の大きさ。
func _draw_small_key(art: Node3D, center: Vector2, key_size: Vector2, label: String, radius: float, drop: float,
		pixel: float, badge_radius: float) -> SignKey:
	var small := SignKey.new()
	small.top = Shapes.flat_material(KEY_TOP_COLOR, false, false, 0, false, true)
	_layer(art, Shapes.rounded_rect(key_size, radius, center + Vector2(0.0, -drop)), KEY_SIDE_COLOR, 0)
	Shapes.add_mesh(art, Shapes.polygon_mesh(Shapes.rounded_rect(key_size, radius, center)), small.top, Vector3(0.0, 0.0, -LAYER_STEP))
	if ARROW_ANGLES.has(label):
		var side := minf(key_size.x, key_size.y)
		_layer(art, Shapes.arrow_polygon(side * 0.62, side * 0.2, side * 0.56, side * 0.32, float(ARROW_ANGLES[label]), center), NAVY, 2)
	elif not label.is_empty():
		var fit := _fit_pixel_size(label, 120, pixel, key_size.x * KEY_GLYPH_FIT)
		_text(art, label, 120, fit, center + Vector2(0.0, 0.02), NAVY)
	small.badge = _build_badge(badge_radius)
	var corner := center + key_size * 0.5 - Vector2(0.06, 0.06)
	small.badge.position = Vector3(-corner.x, corner.y, -LAYER_STEP * 5.0)
	art.add_child(small.badge)
	return small


## キーの組（段階6。"keys" と "sub"）：4つならキーボードと同じ並び（上の段に keys[0]、下の段に keys[1]〜[3]）、
## ほかの数なら横に1列。その下に横長のキー（sub の文字）。キーの順に、最後に横長のキーの SignKey を返す。
func _draw_key_set(art: Node3D, labels: Array, sub: String) -> Array[SignKey]:
	var keys: Array[SignKey] = []
	var s := SET_KEY_SIZE
	var k := s / SMALL_KEY_SIZE
	var radius := 0.18 * k
	var drop := 0.11 * k
	var badge := SMALL_BADGE_RADIUS * k
	var top_v := SET_TOP_V - s * 0.5
	var bottom_v := top_v - s - SET_KEY_GAP
	var step := s + SET_KEY_GAP
	var centers: Array[Vector2] = []
	if labels.size() == 4:
		var spots: Array[Vector2] = [Vector2(0.0, top_v), Vector2(-step, bottom_v), Vector2(0.0, bottom_v), Vector2(step, bottom_v)]
		# 移動のキー（W A S D・矢印）は、渡した順によらずキーボードと同じ所へ（W・↑ が上、A・← / S・↓ / D・→ が下の段）。
		# tick_panel_key の index は渡した順のまま
		var ranks: Array[int] = []
		for label: Variant in labels:
			ranks.append(int(KEY_SET_SPOTS.get(str(label).to_upper(), -1)))
		var known := not ranks.has(-1)
		for rank: int in range(4):
			known = known and ranks.count(rank) == 1
		for i: int in range(4):
			centers.append(spots[ranks[i]] if known else spots[i])
	else:
		var count := mini(labels.size(), 4)
		if labels.size() > count:
			push_warning("PracticeSignWall: a key set shows up to 4 keys")
		for i: int in range(count):
			centers.append(Vector2(-step * (count - 1) * 0.5 + step * i, (top_v + bottom_v) * 0.5))
	for i: int in range(centers.size()):
		keys.append(_draw_small_key(art, centers[i], Vector2(s, s), str(labels[i]), radius, drop, 0.0068 * k, badge))
	if sub.is_empty():
		return keys
	# 横長のキー：文字の幅に合わせる（スペースのように横長に見える幅から、パネルに収まる幅まで）
	var sub_pixel := 0.0036
	var text_width := Shapes.msdf_font().get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 120).x * sub_pixel
	var sub_size := Vector2(clampf(text_width + 0.9, SET_SUB_WIDTH.x, SET_SUB_WIDTH.y), SET_SUB_HEIGHT)
	var sub_center := Vector2(0.0, bottom_v - s * 0.5 - drop - SET_SUB_GAP - SET_SUB_HEIGHT * 0.5)
	keys.append(_draw_small_key(art, sub_center, sub_size, sub, radius, drop, sub_pixel, badge))
	return keys


## パネルの左上の「P1」「P2」の札（2人の色の縁と、暗くした色の地に白い文字）。絵より手前（6〜6.6 の層）。
func _draw_player_tag(art: Node3D, player: int) -> void:
	var color := PLAYER_COLORS[player - 1]
	_layer(art, Shapes.rounded_rect(PLAYER_TAG_SIZE + Vector2.ONE * 0.1, 0.3, PLAYER_TAG_CENTER), color, 6.0)
	_layer(art, Shapes.rounded_rect(PLAYER_TAG_SIZE, 0.25, PLAYER_TAG_CENTER), color.darkened(0.5), 6.3)
	var text := "P%d" % player
	var pixel := _fit_pixel_size(text, 120, 0.0036, PLAYER_TAG_SIZE.x * 0.78)
	_text(art, text, 120, pixel, PLAYER_TAG_CENTER + Vector2(0.0, 0.01), Color.WHITE, Color(0, 0, 0, 0), 0, 6.6)


## 横長の「スペース」キー：下に大きく白く光るキー（文字「スペース」）、上に暗いキーの列（キーボードのいちばん下の大きなキーだと分かるように）。
func _draw_space_key(art: Node3D, inner: Vector2) -> void:
	var dim_size := 0.5
	var dim_gap := 0.12
	var count := 6
	var row_width := dim_size * count + dim_gap * (count - 1)
	for row: int in range(2):
		var v := 1.02 - row * (dim_size + dim_gap)
		# 2列目は少し右へずらす（キーボードの段のずれ）
		var shift := 0.16 * row
		for i: int in range(count):
			var center := Vector2(-row_width * 0.5 + dim_size * 0.5 + (dim_size + dim_gap) * i + shift - 0.08, v)
			_layer(art, Shapes.rounded_rect(Vector2(dim_size, dim_size), 0.09, center + Vector2(0.0, -0.06)), KEY_DIM_SIDE_COLOR, 0)
			_layer(art, Shapes.rounded_rect(Vector2(dim_size, dim_size), 0.09, center), KEY_DIM_TOP_COLOR, 1)
	var bar := Vector2(minf(inner.x - 0.3, 3.7), 1.08)
	var bar_center := Vector2(0.0, -0.62)
	_layer(art, Shapes.rounded_rect(bar, 0.24, bar_center + Vector2(0.0, -0.13)), KEY_SIDE_COLOR, 0)
	_layer(art, Shapes.rounded_rect(bar, 0.24, bar_center), KEY_TOP_COLOR, 1)
	_text(art, "スペース", 120, _fit_pixel_size("スペース", 120, 0.0064, bar.x * 0.7), bar_center + Vector2(0.0, 0.02), NAVY)


## 「II」（一時停止）：白い丸のボタンに紺の2本の棒。
func _draw_pause(art: Node3D) -> void:
	var radius := 1.22
	_layer(art, Shapes.circle(radius, 56, Vector2(0.0, -0.1)), KEY_SIDE_COLOR, 0)
	_layer(art, Shapes.circle(radius, 56), KEY_TOP_COLOR, 1)
	for side: float in [-1.0, 1.0]:
		_layer(art, Shapes.rounded_rect(Vector2(0.36, 1.12), 0.1, Vector2(side * 0.3, 0.0)), NAVY, 2)


## 雲に乗ったハテナ：空の地、うしろに飛ぶ線、手をふるハテナ、その下半分を隠す雲。
func _draw_hatena_cloud(art: Node3D, inner: Vector2) -> void:
	_layer(art, Shapes.rounded_rect(inner, 0.22), CLOUD_SKY_COLOR, 0)
	# 左に飛ぶ線（右へ飛んでいる）
	var lines: Array[Vector3] = [Vector3(-1.98, 0.38, 0.55), Vector3(-1.9, 0.02, 0.7), Vector3(-1.98, -0.34, 0.5)]
	for line: Vector3 in lines:
		_line(art, PackedVector2Array([Vector2(line.x, line.y), Vector2(line.x + line.z, line.y)]), 0.1, CLOUD_WHITE, 0.3)
	# 画面の左の手（ハテナの右手）をふり、右の手は雲の上に置く
	_draw_hatena(art, Vector2(0.05, 0.18), 0.64, 0.06, [Vector2(-0.5, 0.87), Vector2(0.9, -0.42)], [], 1.0)
	_draw_cloud(art, Vector2(0.02, -0.95), 1.05, 3.4)


## おどるハテナ：あたたかい色の地、床の影、片手を上げて片足をけり上げたハテナ、まわりに音符。
func _draw_hatena_dance(art: Node3D, inner: Vector2) -> void:
	_layer(art, Shapes.rounded_rect(inner, 0.22), DANCE_BG_COLOR, 0)
	_layer(art, Shapes.ellipse(Vector2(0.95, 0.13), 36, Vector2(0.0, -1.02)), DANCE_BG_COLOR.darkened(0.14), 0.3)
	_draw_hatena(art, Vector2(0.05, 0.1), 0.66, -0.2, [Vector2(-0.45, 0.9), Vector2(0.95, 0.3)],
		[Vector2(-0.18, -1.0), Vector2(0.85, -0.45)], 1.0)
	_draw_note(art, Vector2(-1.62, 0.5), 0.9, NOTE_COLORS[0], false, 3.4)
	_draw_note(art, Vector2(1.2, 0.72), 0.85, NOTE_COLORS[1], true, 3.4)


## ハテナの絵（正面。客席のハテナの形）。玉の半径 radius、玉の真ん中 center、体の傾き tilt（+ で左へ倒れる）。
## arms：[画面の左の腕, 右の腕] の向き（肩からの向き。傾ける前の絵の座標）。legs：[左の足, 右の足] の向き（空なら足を描かない）。
## base から base + 2.1 の層を使う（うしろから「？」と手足 → 体 → 顔）。どの部品も紺の縁どり。
func _draw_hatena(art: Node3D, center: Vector2, radius: float, tilt: float, arms: Array, legs: Array, base: float) -> void:
	var xf := Transform2D(tilt, Vector2(radius, radius), 0.0, center)
	var edge := 0.07
	# 「？」：てっぺんから立つ軸と、先が玉で止まるかぎ
	var hook := PackedVector2Array()
	for i: int in range(23):
		var a := deg_to_rad(200.0 - 280.0 * i / 22.0)
		hook.append(Vector2(0.0, 1.55) + Vector2(cos(a), sin(a)) * 0.36)
	hook.append(Vector2(0.0, 1.12))
	hook.append(Vector2(0.0, 0.8))
	var stroke := xf * hook
	_line(art, stroke, (0.17 + edge * 2.0) * radius, HATENA_LINE, base)
	_line(art, stroke, 0.17 * radius, HATENA_GOLD, base + 0.3)
	_layer(art, Shapes.circle((0.12 + edge) * radius, 20, xf * hook[0]), HATENA_LINE, base)
	_layer(art, Shapes.circle(0.12 * radius, 20, xf * hook[0]), HATENA_GOLD, base + 0.3)
	# 腕（肩から）と、先の丸い手
	var shoulders: Array[Vector2] = [Vector2(-0.84, -0.28), Vector2(0.84, -0.28)]
	for i: int in range(mini(arms.size(), 2)):
		var dir := (arms[i] as Vector2).normalized()
		var arm := PackedVector2Array([shoulders[i], shoulders[i] + dir * 0.5])
		var hand := xf * arm[1]
		_line(art, xf * arm, (0.2 + edge * 2.0) * radius, HATENA_LINE, base)
		_line(art, xf * arm, 0.2 * radius, HATENA_GOLD, base + 0.3)
		_layer(art, Shapes.circle((0.17 + edge) * radius, 24, hand), HATENA_LINE, base)
		_layer(art, Shapes.circle(0.17 * radius, 24, hand), HATENA_GOLD, base + 0.3)
	# 足（腰から）と、紺のくつ
	var hips: Array[Vector2] = [Vector2(-0.32, -0.84), Vector2(0.32, -0.84)]
	for i: int in range(mini(legs.size(), 2)):
		var dir := (legs[i] as Vector2).normalized()
		var leg := PackedVector2Array([hips[i], hips[i] + dir * 0.46])
		_line(art, xf * leg, (0.18 + edge * 2.0) * radius, HATENA_LINE, base)
		_line(art, xf * leg, 0.18 * radius, HATENA_GOLD, base + 0.3)
		var toe := Vector2(signf(hips[i].x) * 0.08, -0.04)
		var shoe := xf * (leg[1] + toe)
		var angle := tilt + atan2(dir.y, dir.x) + PI * 0.5
		_layer(art, Shapes.ellipse(Vector2(0.25 + edge, 0.14 + edge) * radius, 24, shoe, angle), HATENA_LINE, base + 0.4)
		_layer(art, Shapes.ellipse(Vector2(0.25, 0.14) * radius, 24, shoe, angle), HATENA_SHOE, base + 0.5)
	# 体の玉：縁、右下の陰、左上へずらした白
	var body := xf * Vector2.ZERO
	_layer(art, Shapes.circle((1.0 + edge) * radius, 56, body), HATENA_LINE, base + 0.6)
	_layer(art, Shapes.circle(radius, 56, body), HATENA_SHADE, base + 0.9)
	_layer(art, Shapes.circle(0.9 * radius, 56, xf * Vector2(-0.08, 0.08)), HATENA_WHITE, base + 1.2)
	# 「？」の根もとの輪
	_layer(art, Shapes.ellipse(Vector2(0.2 + edge, 0.08 + edge) * radius, 24, xf * Vector2(0.0, 0.97), tilt), HATENA_LINE, base + 1.2)
	_layer(art, Shapes.ellipse(Vector2(0.2, 0.08) * radius, 24, xf * Vector2(0.0, 0.97), tilt), HATENA_GOLD, base + 1.5)
	# 顔：目（光る点が2つ）・ほお・口
	for side: float in [-1.0, 1.0]:
		var eye := Vector2(side * 0.3, 0.06)
		_layer(art, Shapes.ellipse(Vector2(0.1, 0.15) * radius, 24, xf * eye, tilt), HATENA_EYE, base + 1.5)
		_layer(art, Shapes.circle(0.045 * radius, 12, xf * (eye + Vector2(-0.03, 0.06))), Color.WHITE, base + 1.8)
		_layer(art, Shapes.circle(0.022 * radius, 10, xf * (eye + Vector2(0.035, -0.05))), Color.WHITE, base + 1.8)
		_layer(art, Shapes.ellipse(Vector2(0.13, 0.075) * radius, 20, xf * Vector2(side * 0.53, -0.14), tilt), HATENA_CHEEK, base + 1.5)
	var mouth := PackedVector2Array([Vector2(-0.12, -0.12), Vector2(-0.06, -0.18), Vector2(0.0, -0.195), Vector2(0.06, -0.18), Vector2(0.12, -0.12)])
	_line(art, xf * mouth, 0.05 * radius, HATENA_EYE, base + 1.5)


## 雲の絵：ふくらみ（丸）と平らな底。うしろに縁の色、手前に白、底に薄い陰。layer から layer + 0.6 の層を使う。
func _draw_cloud(art: Node3D, center: Vector2, size: float, layer: float) -> void:
	var bumps: Array[Vector3] = [Vector3(-1.15, -0.05, 0.42), Vector3(-0.55, 0.22, 0.52), Vector3(0.15, 0.3, 0.55),
		Vector3(0.8, 0.12, 0.46), Vector3(1.3, -0.08, 0.36)]
	var edge := 0.07
	for pass_index: int in range(2):
		var grow := edge if pass_index == 0 else 0.0
		var color := CLOUD_LINE if pass_index == 0 else CLOUD_WHITE
		var z := layer + 0.3 * pass_index
		for bump: Vector3 in bumps:
			_layer(art, Shapes.circle((bump.z + grow) * size, 36, center + Vector2(bump.x, bump.y) * size), color, z)
		_layer(art, Shapes.rounded_rect(Vector2(2.9 + grow * 2.0, 0.5 + grow * 2.0) * size, (0.25 + grow) * size,
			center + Vector2(0.05, -0.25) * size), color, z)
	_layer(art, Shapes.rounded_rect(Vector2(2.6, 0.16) * size, 0.08 * size, center + Vector2(0.05, -0.38) * size), CLOUD_SHADE, layer + 0.6)


## 音符：ふつうの音符（はた付き）か、2つつながった音符。center は（1つ目の）たまの真ん中。layer から layer + 0.3 の層。
func _draw_note(art: Node3D, center: Vector2, size: float, color: Color, beamed: bool, layer: float) -> void:
	var heads: Array[Vector2] = [Vector2.ZERO]
	if beamed:
		heads.append(Vector2(0.62, 0.1))
	for head: Vector2 in heads:
		_layer(art, Shapes.ellipse(Vector2(0.19, 0.13) * size, 24, center + head * size, 0.4), color, layer)
		var stem_bottom := head + Vector2(0.16, 0.05)
		_line(art, PackedVector2Array([center + stem_bottom * size, center + (stem_bottom + Vector2(0.0, 0.78)) * size]), 0.07 * size, color, layer)
	if beamed:
		var a := center + Vector2(0.16, 0.83) * size
		var b := center + Vector2(0.78, 0.93) * size
		var thick := Vector2(0.0, 0.16) * size
		_layer(art, PackedVector2Array([a - thick * 0.5, b - thick * 0.5, b + thick * 0.5, a + thick * 0.5]), color, layer + 0.3)
	else:
		var top := center + Vector2(0.16, 0.83) * size
		var flag := PackedVector2Array([top, top + Vector2(0.14, -0.14) * size, top + Vector2(0.24, -0.3) * size, top + Vector2(0.2, -0.46) * size])
		_line(art, flag, 0.08 * size, color, layer + 0.3)


## 波線の点（v の高さ、u は ±half、amplitude の振れ、wavelength の波長）。
func _wave_points(v: float, half: float, amplitude: float, wavelength: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 48
	for i: int in range(steps + 1):
		var u := -half + half * 2.0 * float(i) / steps
		points.append(Vector2(u, v + sin(u / wavelength * TAU) * amplitude))
	return points


## サメの絵：空、海から出た灰色のひれ（前の辺がふくらみ、うしろの辺がへこむ）、ひれの根もとを隠す海と白い波。
func _draw_shark(art: Node3D, inner: Vector2) -> void:
	_layer(art, Shapes.rounded_rect(inner, 0.22), SKY_COLOR, 0)
	var base_left := Vector2(-0.95, -0.75)
	var tip := Vector2(0.55, 1.18)
	var base_right := Vector2(0.78, -0.75)
	var fin := PackedVector2Array([base_left])
	fin.append_array(Shapes.bezier(base_left, Vector2(-0.55, 0.95), tip, 14))
	fin.append_array(Shapes.bezier(tip, Vector2(0.35, 0.05), base_right, 10))
	_layer(art, fin, FIN_COLOR, 1)
	# ひれのうしろ側の影
	var shade := PackedVector2Array([Vector2(0.18, -0.75)])
	shade.append_array(Shapes.bezier(Vector2(0.18, -0.75), Vector2(0.32, 0.35), tip, 10))
	shade.append_array(Shapes.bezier(tip, Vector2(0.35, 0.05), base_right, 10))
	_layer(art, shade, FIN_SHADE_COLOR, 2)
	# 海：上の辺が波打ち、下の角は面の角に合わせて丸める
	var water := -0.42
	var half := inner * 0.5
	var sea := PackedVector2Array()
	var steps := 40
	for i: int in range(steps + 1):
		var u := half.x - inner.x * float(i) / steps
		sea.append(Vector2(u, water + sin(u / 1.1 * TAU) * 0.09))
	var r := 0.22
	for step: int in range(7):
		var angle := PI + PI * 0.5 * float(step) / 6.0
		sea.append(Vector2(-half.x + r, -half.y + r) + Vector2(cos(angle), sin(angle)) * r)
	for step: int in range(7):
		var angle := PI * 1.5 + PI * 0.5 * float(step) / 6.0
		sea.append(Vector2(half.x - r, -half.y + r) + Vector2(cos(angle), sin(angle)) * r)
	_layer(art, sea, SEA_COLOR, 3)
	# ひれのまわりの白い波
	for side: float in [-1.0, 1.0]:
		var foam := PackedVector2Array()
		for i: int in range(9):
			var t := float(i) / 8.0
			var u := -0.1 + side * (0.95 + t * 0.75)
			foam.append(Vector2(u, water + 0.04 + sin(t * PI) * 0.16))
		_line(art, foam, 0.12, FOAM_COLOR, 4)
	_line(art, _wave_points(-0.95, 1.5, 0.08, 1.0), 0.1, Color(0.55, 0.78, 1.0), 4)


# ---------- 段階6：押し合いの絵（push・push_again） ----------

## 押し合う2人：空の地と床、左にだいだいの P1（右向き）、右に青の P2（左向き）。2人とも前へ傾いて手を突き出し、
## 手の合わさる所に黄色い光、うしろの足もとに土ぼこり（踏ん張っている）。
func _draw_push(art: Node3D, inner: Vector2) -> void:
	_layer(art, Shapes.rounded_rect(inner, 0.22), SKY_COLOR, 0)
	var floor_v := -1.05
	_draw_floor_band(art, inner, floor_v)
	var k := 0.5
	# 手の合わさる所（2人の手は真ん中で会う）のうしろに光
	var hand_v := floor_v + 1.16
	_layer(art, Shapes.star(0.62, 0.3, 8, Vector2(0.0, hand_v)), FIGURE_LINE, 0.6)
	_layer(art, Shapes.star(0.52, 0.24, 8, Vector2(0.0, hand_v)), IMPACT_COLOR, 0.8)
	# うしろの足のかかとに土ぼこり（白い丸を3つ重ねる）
	for side: float in [-1.0, 1.0]:
		var heel := Vector2(side * 1.64, floor_v + 0.12)
		for puff: Vector3 in [Vector3(0.0, 0.0, 0.16), Vector3(0.2, 0.06, 0.12), Vector3(0.36, 0.0, 0.09)]:
			_layer(art, Shapes.circle(puff.z, 20, heel + Vector2(side * puff.x, puff.y)), DUST_COLOR, 0.8)
	_draw_figure(art, Vector2(-1.0, floor_v), k, 1.0, 0.45, PLAYER_COLORS[0], 1.0)
	_draw_figure(art, Vector2(1.0, floor_v), k, -1.0, 0.45, PLAYER_COLORS[1], 3.6)


## 離す → 押す：上がった（離した）キーと上向きの線 → 黄色い矢印 → 押し込んだキーとまわりの衝撃の線。キーは同じ「→」。
## 下に、一押しされて後ろへ下がる青い人と、押しただいだいの人。captions があれば、2つのキーのすぐ下に文字を添える。
func _draw_push_again(art: Node3D, inner: Vector2, captions: Array) -> void:
	_layer(art, Shapes.rounded_rect(inner, 0.22), SKY_COLOR, 0)
	var key_v := 0.72
	var key_size := Vector2(0.95, 0.95)
	var line_color := Color(0.34, 0.44, 0.68)
	# 離したキー：側面が深い（上がっている）。上に上向きの線
	var up := Vector2(-1.3, key_v + 0.06)
	_layer(art, Shapes.rounded_rect(key_size, 0.14, up + Vector2(0.0, -0.22)), KEY_SIDE_COLOR, 0.5)
	_layer(art, Shapes.rounded_rect(key_size, 0.14, up), KEY_TOP_COLOR, 1.0)
	_layer(art, Shapes.arrow_polygon(0.56, 0.18, 0.5, 0.29, 0.0, up), NAVY, 2.0)
	for u: float in [-0.28, 0.0, 0.28]:
		_line(art, PackedVector2Array([up + Vector2(u, 0.6), up + Vector2(u, 0.76)]), 0.09, line_color, 1.0)
	# 押したキー：側面が浅い（沈んでいる）。上と横に衝撃の線（下は文字と人のために空ける）
	var down := Vector2(1.3, key_v - 0.06)
	_layer(art, Shapes.rounded_rect(key_size, 0.14, down + Vector2(0.0, -0.05)), KEY_SIDE_COLOR, 0.5)
	_layer(art, Shapes.rounded_rect(key_size, 0.14, down), KEY_TOP_COLOR.lerp(IMPACT_COLOR, 0.18), 1.0)
	_layer(art, Shapes.arrow_polygon(0.56, 0.18, 0.5, 0.29, 0.0, down), NAVY, 2.0)
	for degrees: float in [-25.0, 15.0, 55.0, 90.0, 125.0]:
		var dir := Vector2.from_angle(deg_to_rad(degrees))
		var ray := PackedVector2Array([down + dir * 0.6, down + dir * 0.78])
		_line(art, ray, 0.15, FIGURE_LINE, 1.0)
		_line(art, ray, 0.09, IMPACT_COLOR, 1.3)
	# 真ん中の矢印（紺の縁どりに黄色）
	var mid := Vector2(0.0, key_v)
	_layer(art, Shapes.arrow_polygon(0.74, 0.26, 0.64, 0.38, 0.0, mid), FIGURE_LINE, 1.0)
	_layer(art, Shapes.arrow_polygon(0.58, 0.14, 0.48, 0.28, 0.0, mid + Vector2(-0.02, 0.0)), IMPACT_COLOR, 1.3)
	if captions.size() >= 2:
		for i: int in range(2):
			var at := Vector2(up.x if i == 0 else down.x, -0.04)
			var text := str(captions[i])
			_text(art, text, 110, _fit_pixel_size(text, 110, 0.0038, 1.4), at, NAVY, Color(0, 0, 0, 0), 0, 2.2)
	# 下：一押しの結果（押しただいだいの人と、後ろへ下がる青い人。うしろに動きの線）
	var floor_v := -1.3
	_draw_floor_band(art, inner, floor_v)
	var k := 0.18
	_draw_figure(art, Vector2(-0.5, floor_v), k, 1.0, 0.5, PLAYER_COLORS[0], 2.5)
	_draw_figure(art, Vector2(0.62, floor_v), k, -1.0, -0.42, PLAYER_COLORS[1], 4.0)
	_layer(art, Shapes.star(0.2, 0.09, 8, Vector2(0.12, floor_v + 0.44)), IMPACT_COLOR, 6.5)
	for v: float in [0.22, 0.4, 0.58]:
		_line(art, PackedVector2Array([Vector2(1.02, floor_v + v), Vector2(1.38, floor_v + v)]), 0.06, line_color, 2.4)


## 床の帯：top_v から下（下の角は面の角に合わせて丸める）と、上の縁の明るい線。
func _draw_floor_band(art: Node3D, inner: Vector2, top_v: float) -> void:
	var half := inner * 0.5
	# 角の丸みは帯の高さに収める（帯の上の辺が丸みにかかると、多角形がねじれる）
	var r := minf(0.22, top_v + half.y - 0.02)
	var band := PackedVector2Array([Vector2(half.x, top_v), Vector2(-half.x, top_v)])
	if r < 0.02:
		band.append_array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y)])
	else:
		for step: int in range(7):
			var angle := PI + PI * 0.5 * float(step) / 6.0
			band.append(Vector2(-half.x + r, -half.y + r) + Vector2(cos(angle), sin(angle)) * r)
		for step: int in range(7):
			var angle := PI * 1.5 + PI * 0.5 * float(step) / 6.0
			band.append(Vector2(half.x - r, -half.y + r) + Vector2(cos(angle), sin(angle)) * r)
	_layer(art, band, PUSH_FLOOR_COLOR, 0.2)
	_line(art, PackedVector2Array([Vector2(-half.x + 0.04, top_v), Vector2(half.x - 0.04, top_v)]), 0.06, PUSH_FLOOR_TOP, 0.3)


## 押す人（横向き。ゲームのキャラクターと同じ四角い体）。feet は足もとの真ん中、k は大きさ（1 単位の m）、facing は向き
## （+1 で絵の右へ向く）、lean は上半身の前への傾き（ラジアン。負なら後ろへのけぞる）。どの部品も紺の縁どり。
## base から base + 2.4 の層を使う（うしろの腕と足 → 前の足 → 体と頭 → 目 → 前の腕）。
func _draw_figure(art: Node3D, feet: Vector2, k: float, facing: float, lean: float, color: Color, base: float) -> void:
	var edge := 0.09
	var body := Transform2D(0.0, Vector2(facing * k, k), 0.0, feet)
	var hip := Vector2(0.0, 1.7)
	# 上半身は腰を中心に前へ傾ける（右向きのとき時計回り）
	var upper := body * Transform2D(-lean, hip)
	var dark := color.darkened(0.3)
	var mid := color.darkened(0.14)
	# うしろの腕・うしろの足
	_limb(art, upper, [Vector2(0.02, 1.42), Vector2(1.32, 1.24)], 0.38, edge, k, dark, base)
	_limb(art, body, [Vector2(-0.15, 1.7), Vector2(-1.0, 0.22)], 0.5, edge, k, dark, base)
	# 前の足（ひざを曲げる）
	_limb(art, body, [Vector2(0.2, 1.7), Vector2(0.62, 0.95), Vector2(0.42, 0.22)], 0.5, edge, k, mid, base + 0.6)
	# 体と頭
	for part: Array in [[Vector2(0.0, 0.85), Vector2(1.15, 1.75), color], [Vector2(0.05, 2.33), Vector2(1.1, 1.05), color.lightened(0.1)]]:
		var center: Vector2 = part[0]
		var size: Vector2 = part[1]
		_layer(art, upper * Shapes.rounded_rect(size + Vector2.ONE * edge * 2.0, 0.16, center), FIGURE_LINE, base + 1.2)
		_layer(art, upper * Shapes.rounded_rect(size, 0.1, center), part[2], base + 1.5)
	# 目（向いている側の顔）
	_layer(art, upper * Shapes.rounded_rect(Vector2(0.16, 0.26), 0.04, Vector2(0.36, 2.4)), FIGURE_EYE, base + 1.8)
	# 前の腕
	_limb(art, upper, [Vector2(0.24, 1.45), Vector2(1.45, 1.38)], 0.4, edge, k, color, base + 2.1)


## 腕・足：xf の空間の点を結ぶ太い線（幅 width）を、紺の縁どり（edge）つきで描く。
func _limb(art: Node3D, xf: Transform2D, points: Array, width: float, edge: float, k: float, color: Color, layer: float) -> void:
	var line := PackedVector2Array()
	for point: Vector2 in points:
		line.append(xf * point)
	_line(art, line, (width + edge * 2.0) * k, FIGURE_LINE, layer)
	_line(art, line, width * k, color, layer + 0.3)

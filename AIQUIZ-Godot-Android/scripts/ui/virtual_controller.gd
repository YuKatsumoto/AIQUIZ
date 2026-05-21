extends Control
class_name VirtualController

# シグナル
signal jump_triggered
signal emote_triggered(emote_id: int)
signal pause_triggered

# ジョイスティック関連
@onready var joystick_base: Panel = $Joystick/Base
@onready var joystick_tip: Panel = $Joystick/Base/Tip
@onready var jump_button: Button = $JumpButton
@onready var pause_button: Button = $PauseButton
@onready var emote_container: HBoxContainer = $EmoteButtons
@onready var emote_1: Button = $EmoteButtons/Emote1
@onready var emote_2: Button = $EmoteButtons/Emote2
@onready var emote_3: Button = $EmoteButtons/Emote3

var joystick_active := false
var joystick_center := Vector2.ZERO
var joystick_vector := Vector2.ZERO
const MAX_DRAG_RADIUS := 64.0

var jump_active := false

func _ready() -> void:
	# デバッグ用にPC上でもエミュレーションできるように表示させておく（実機ビルド時はモバイル判定で表示される）
	# ただし、エディタ上で "Emulate Touch From Mouse" を有効にしていればPC上でもタッチ動作が確認できる。
	visible = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("web")
	
	# UIのデザインスタイルの適用
	_style_ui()

	# シグナル接続
	jump_button.button_down.connect(_on_jump_down)
	jump_button.button_up.connect(_on_jump_up)
	pause_button.pressed.connect(_on_pause_pressed)
	
	emote_1.pressed.connect(func(): _on_emote_pressed(0))
	emote_2.pressed.connect(func(): _on_emote_pressed(1))
	emote_3.pressed.connect(func(): _on_emote_pressed(2))

func _style_ui() -> void:
	# ジョイスティックベースのスタイル (円形、半透明ガラス風)
	var base_style := StyleBoxFlat.new()
	base_style.bg_color = Color(0.1, 0.1, 0.15, 0.4)
	base_style.border_color = Color(0.3, 0.5, 0.8, 0.6)
	base_style.set_border_width_all(2)
	base_style.set_corner_radius_all(64) # 完全な円形 (size 128 の半分)
	joystick_base.add_theme_stylebox_override("panel", base_style)
	
	# ジョイスティック先端 (Tip) のスタイル (円形、明るい青)
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(0.2, 0.6, 1.0, 0.8)
	tip_style.border_color = Color(0.5, 0.8, 1.0, 0.9)
	tip_style.set_border_width_all(1)
	tip_style.set_corner_radius_all(24) # 完全な円形 (size 48 の半分)
	joystick_tip.add_theme_stylebox_override("panel", tip_style)
	
	# ジャンプボタンのスタイル (丸型、ネオンブルー)
	var jump_normal := StyleBoxFlat.new()
	jump_normal.bg_color = Color(0.15, 0.35, 0.7, 0.6)
	jump_normal.border_color = Color(0.3, 0.6, 1.0, 0.8)
	jump_normal.set_border_width_all(3)
	jump_normal.set_corner_radius_all(55) # size 110 の半分
	
	var jump_pressed_style := StyleBoxFlat.new()
	jump_pressed_style.bg_color = Color(0.2, 0.5, 1.0, 0.8)
	jump_pressed_style.border_color = Color(0.6, 0.8, 1.0, 1.0)
	jump_pressed_style.set_border_width_all(3)
	jump_pressed_style.set_corner_radius_all(55)
	
	jump_button.add_theme_stylebox_override("normal", jump_normal)
	jump_button.add_theme_stylebox_override("hover", jump_normal) # モバイルではホバーはノーマルと同じ
	jump_button.add_theme_stylebox_override("pressed", jump_pressed_style)
	jump_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	jump_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	
	# 一時停止ボタンのスタイル (角丸四角形、半透明)
	var pause_normal := StyleBoxFlat.new()
	pause_normal.bg_color = Color(0.15, 0.15, 0.2, 0.5)
	pause_normal.border_color = Color(0.4, 0.4, 0.45, 0.7)
	pause_normal.set_border_width_all(2)
	pause_normal.set_corner_radius_all(12)
	
	var pause_pressed := pause_normal.duplicate()
	pause_pressed.bg_color = Color(0.25, 0.25, 0.3, 0.7)
	
	pause_button.add_theme_stylebox_override("normal", pause_normal)
	pause_button.add_theme_stylebox_override("pressed", pause_pressed)
	pause_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	# エモートボタンのスタイル
	var emote_normal := StyleBoxFlat.new()
	emote_normal.bg_color = Color(0.12, 0.14, 0.2, 0.6)
	emote_normal.border_color = Color(0.28, 0.32, 0.42, 0.7)
	emote_normal.set_border_width_all(1)
	emote_normal.set_corner_radius_all(8)
	
	var emote_pressed_style := emote_normal.duplicate()
	emote_pressed_style.bg_color = Color(0.2, 0.25, 0.35, 0.8)
	emote_pressed_style.border_color = Color(0.4, 0.5, 0.7, 0.9)
	
	for btn in [emote_1, emote_2, emote_3]:
		btn.add_theme_stylebox_override("normal", emote_normal)
		btn.add_theme_stylebox_override("pressed", emote_pressed_style)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))

	_update_emote_labels()

func _update_emote_labels() -> void:
	var gs = QuizManager.game_state
	if gs:
		var labels = [emote_1, emote_2, emote_3]
		for i in range(3):
			if gs.p1_emote_slots.size() > i:
				var emote_id = gs.p1_emote_slots[i]
				labels[i].text = _get_emote_name(emote_id)
				labels[i].visible = true
			else:
				labels[i].visible = false

func _get_emote_name(emote_id: int) -> String:
	match emote_id:
		1: return "🔥 挑発"
		2: return "✨ 勝利"
		3: return "💧 落胆"
		_: return "エモート"

func _input(event: InputEvent) -> void:
	if not visible:
		return
		
	# ジョイスティックのドラッグ処理
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		# joystick_baseの中心位置を算出
		var base_global_center := joystick_base.global_position + joystick_base.size * 0.5
		var dist_to_center := touch.position.distance_to(base_global_center)
		
		if touch.pressed:
			# ジョイスティックの付近(半径100px以内程度)がタッチされたらアクティブに
			if dist_to_center < MAX_DRAG_RADIUS * 1.5:
				joystick_active = true
				joystick_center = base_global_center
				_update_joystick(touch.position)
		else:
			if joystick_active:
				joystick_active = false
				joystick_vector = Vector2.ZERO
				# つまみを中央に戻す
				joystick_tip.position = joystick_base.size * 0.5 - joystick_tip.size * 0.5
				
	elif event is InputEventScreenDrag and joystick_active:
		var drag := event as InputEventScreenDrag
		_update_joystick(drag.position)

func _update_joystick(touch_pos: Vector2) -> void:
	var offset := touch_pos - joystick_center
	# ドラッグ範囲を制限
	if offset.length() > MAX_DRAG_RADIUS:
		offset = offset.normalized() * MAX_DRAG_RADIUS
	
	# つまみの位置更新
	joystick_tip.position = offset + (joystick_base.size * 0.5) - (joystick_tip.size * 0.5)
	
	# ベクトルの出力設定 (PC版の W/A/S/D と挙動を一致させる)
	# Dキー(右) -> axis.x = -1.0
	# Aキー(左) -> axis.x = 1.0
	# Wキー(前) -> axis.y = 1.0
	# Sキー(後ろ) -> axis.y = -1.0
	# ジョイスティックのX+ (右) のとき、出力は - (左)
	# ジョイスティックのY- (上) のとき、出力は + (前)
	joystick_vector.x = - (offset.x / MAX_DRAG_RADIUS)
	joystick_vector.y = - (offset.y / MAX_DRAG_RADIUS)

func _on_jump_down() -> void:
	jump_active = true
	jump_triggered.emit()

func _on_jump_up() -> void:
	jump_active = false

func _on_pause_pressed() -> void:
	pause_triggered.emit()

func _on_emote_pressed(slot_idx: int) -> void:
	var gs = QuizManager.game_state
	if gs and gs.p1_emote_slots.size() > slot_idx:
		emote_triggered.emit(gs.p1_emote_slots[slot_idx])

# 外部からのポーリング用
func get_joystick_axis() -> Vector2:
	return joystick_vector

func is_jump_pressed() -> bool:
	return jump_active

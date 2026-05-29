extends Control
class_name VirtualController

# シグナル
signal jump_triggered
signal emote_triggered(emote_id: int)
signal pause_triggered
signal swipe_left
signal swipe_right

var swipe_start_pos := Vector2.ZERO
var swipe_active := false
const SWIPE_THRESHOLD := 50.0

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
	process_mode = PROCESS_MODE_ALWAYS

	# 画面全体を覆うようにアンカーを設定
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

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
	# ジョイスティックベースのスタイル (円形、非常に薄い半透明グレー)
	var base_style := StyleBoxFlat.new()
	base_style.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	base_style.set_corner_radius_all(64) # 完全な円形 (size 128 の半分)
	joystick_base.add_theme_stylebox_override("panel", base_style)
	
	# ジョイスティック先端 (Tip) のスタイル (円形、半透明白)
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(1.0, 1.0, 1.0, 0.35)
	tip_style.set_corner_radius_all(24) # 完全な円形 (size 48 の半分)
	joystick_tip.add_theme_stylebox_override("panel", tip_style)
	
	# ジャンプボタンのスタイル (丸型、フラットな半透明)
	var jump_normal := StyleBoxFlat.new()
	jump_normal.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	jump_normal.set_corner_radius_all(55) # size 110 の半分
	
	var jump_pressed_style := StyleBoxFlat.new()
	jump_pressed_style.bg_color = Color(1.0, 1.0, 1.0, 0.30)
	jump_pressed_style.set_corner_radius_all(55)
	
	jump_button.add_theme_stylebox_override("normal", jump_normal)
	jump_button.add_theme_stylebox_override("hover", jump_normal)
	jump_button.add_theme_stylebox_override("pressed", jump_pressed_style)
	jump_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	jump_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8))
	
	# 一時停止ボタンのスタイル (角丸四角形、半透明)
	var pause_normal := StyleBoxFlat.new()
	pause_normal.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	pause_normal.set_corner_radius_all(12)
	
	var pause_pressed := pause_normal.duplicate()
	pause_pressed.bg_color = Color(1.0, 1.0, 1.0, 0.25)
	
	pause_button.add_theme_stylebox_override("normal", pause_normal)
	pause_button.add_theme_stylebox_override("pressed", pause_pressed)
	pause_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pause_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8))
	
	# エモートボタンのスタイル (フラットグレー)
	var emote_normal := StyleBoxFlat.new()
	emote_normal.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	emote_normal.set_corner_radius_all(8)
	
	var emote_pressed_style := emote_normal.duplicate()
	emote_pressed_style.bg_color = Color(1.0, 1.0, 1.0, 0.28)
	
	for btn in [emote_1, emote_2, emote_3]:
		btn.add_theme_stylebox_override("normal", emote_normal)
		btn.add_theme_stylebox_override("pressed", emote_pressed_style)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))

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
	return EmoteData.get_emote_name(emote_id)

func _input(event: InputEvent) -> void:
	if not visible:
		return
		
	# ジョイスティックおよびスワイプのドラッグ処理
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
				swipe_active = false
			else:
				# ジョイスティック以外の画面タッチはスワイプの開始とみなす
				swipe_active = true
				swipe_start_pos = touch.position
		else:
			if joystick_active:
				joystick_active = false
				joystick_vector = Vector2.ZERO
				# つまみを中央に戻す
				joystick_tip.position = joystick_base.size * 0.5 - joystick_tip.size * 0.5
			elif swipe_active:
				swipe_active = false
				var diff := touch.position - swipe_start_pos
				if diff.length() > SWIPE_THRESHOLD:
					if abs(diff.x) > abs(diff.y):
						# 横スワイプ
						if diff.x > SWIPE_THRESHOLD:
							swipe_right.emit()
						elif diff.x < -SWIPE_THRESHOLD:
							swipe_left.emit()
					else:
						# 縦スワイプ
						if diff.y < -SWIPE_THRESHOLD:
							# 上スワイプはジャンプ
							jump_triggered.emit()
				
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if joystick_active:
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
	print("[VC] _on_emote_pressed slot: %d" % slot_idx)
	if gs and gs.p1_emote_slots.size() > slot_idx:
		var emote_id = gs.p1_emote_slots[slot_idx]
		print("[VC] Emote triggered ID: %d" % emote_id)
		emote_triggered.emit(emote_id)

# 外部からのポーリング用
func get_joystick_axis() -> Vector2:
	return joystick_vector

func is_jump_pressed() -> bool:
	return jump_active

func _process(_delta: float) -> void:
	var gs = QuizManager.game_state
	if gs:
		var is_playing = gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
		var is_mobile_platform = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("web") or OS.is_debug_build() or OS.has_feature("editor")
		var should_be_visible = is_mobile_platform and is_playing
		if visible != should_be_visible:
			visible = should_be_visible
		
		if visible:
			_update_emote_labels()

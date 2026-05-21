extends CanvasLayer

## リプレイ再生HUD
## タイムライン、再生/停止、速度切替、カメラモードなどのUI

var replay_player: ReplayPlayer
var replay_camera: ReplayCamera

var _timeline: HSlider
var _time_label: Label
var _speed_label: Label
var _play_btn: Button
var _speed_btn: Button
var _camera_btn: Button
var _back_btn: Button
var _share_btn: Button
var _is_seeking: bool = false

func setup(player: ReplayPlayer, cam: ReplayCamera) -> void:
	replay_player = player
	replay_camera = cam
	_build_ui()
	# シグナル接続
	replay_player.playback_paused.connect(_on_pause_changed)
	replay_player.speed_changed.connect(_on_speed_changed)
	if replay_camera:
		replay_camera.mode_changed.connect(_on_camera_mode_changed)

func _process(_dt: float) -> void:
	if not replay_player:
		return
	# タイムラインの値を更新（ドラッグ中でなければ）
	if not _is_seeking:
		_timeline.set_value_no_signal(replay_player.get_progress() * 100.0)
	_time_label.text = replay_player.get_time_label()

func _build_ui() -> void:
	layer = 90

	# 下部バー背景
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -110.0
	bar.offset_left = 20.0
	bar.offset_right = -20.0
	bar.offset_bottom = -16.0
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.03, 0.05, 0.10, 0.88)
	bar_style.border_color = Color(0.25, 0.35, 0.6, 0.45)
	bar_style.set_border_width_all(1)
	bar_style.set_corner_radius_all(16)
	bar_style.content_margin_left = 20.0
	bar_style.content_margin_right = 20.0
	bar_style.content_margin_top = 12.0
	bar_style.content_margin_bottom = 12.0
	bar.add_theme_stylebox_override("panel", bar_style)
	add_child(bar)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	bar.add_child(vbox)

	# ── Row 1: タイムライン ──
	_timeline = HSlider.new()
	_timeline.min_value = 0.0
	_timeline.max_value = 100.0
	_timeline.step = 0.1
	_timeline.custom_minimum_size = Vector2(0, 24)

	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.12, 0.15, 0.22, 0.8)
	slider_bg.set_corner_radius_all(6)
	slider_bg.expand_margin_top = 2
	slider_bg.expand_margin_bottom = 2
	_timeline.add_theme_stylebox_override("slider", slider_bg)
	_timeline.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	_timeline.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())

	_timeline.drag_started.connect(func():
		_is_seeking = true
	)
	_timeline.drag_ended.connect(func(_changed: bool):
		_is_seeking = false
		var t: float = (_timeline.value / 100.0) * replay_player.get_duration()
		replay_player.seek(t)
	)
	_timeline.value_changed.connect(func(val: float):
		if _is_seeking:
			var t: float = (val / 100.0) * replay_player.get_duration()
			replay_player.seek(t)
	)
	vbox.add_child(_timeline)

	# ── Row 2: コントロールボタン ──
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(hbox)

	# 再生/停止ボタン
	_play_btn = _create_btn("⏸", 44, Color(0.2, 0.7, 0.4))
	_play_btn.pressed.connect(func():
		if not replay_player.is_playing:
			replay_player.play()
		else:
			replay_player.pause()
		_update_play_btn()
	)
	hbox.add_child(_play_btn)

	# 速度ボタン
	_speed_btn = _create_btn("1x", 60, Color(0.4, 0.6, 0.9))
	_speed_btn.pressed.connect(func():
		replay_player.cycle_speed(1)
	)
	hbox.add_child(_speed_btn)

	# 時間表示
	_time_label = Label.new()
	_time_label.text = "0:00 / 0:00"
	_time_label.add_theme_font_size_override("font_size", 15)
	_time_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_time_label.custom_minimum_size = Vector2(120, 0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(_time_label)

	# スペーサー
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# カメラモードボタン
	_camera_btn = _create_btn("🎥 フリー", 120, Color(0.5, 0.5, 0.7))
	_camera_btn.pressed.connect(func():
		if replay_camera:
			replay_camera.cycle_mode()
	)
	hbox.add_child(_camera_btn)

	# 共有ボタン
	_share_btn = _create_btn("📤 共有", 80, Color(0.6, 0.5, 0.8))
	_share_btn.pressed.connect(_on_share_pressed)
	hbox.add_child(_share_btn)

	# 戻るボタン
	_back_btn = _create_btn("✕ 閉じる", 90, Color(0.7, 0.35, 0.35))
	_back_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	)
	hbox.add_child(_back_btn)

	# 上部: REPLAY 表示
	var replay_badge := Label.new()
	replay_badge.text = "🎬 REPLAY"
	replay_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	replay_badge.offset_left = 20.0
	replay_badge.offset_top = 16.0
	replay_badge.add_theme_font_size_override("font_size", 24)
	replay_badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	replay_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	replay_badge.add_theme_constant_override("outline_size", 4)
	add_child(replay_badge)

	# スコア表示
	var _score_label := Label.new()
	if replay_player.recorder and replay_player.recorder.meta:
		var m := replay_player.recorder.meta
		var mode_text := ""
		match m.get("mode", ""):
			"TEN_QUESTIONS": mode_text = "10問モード"
			"ENDLESS": mode_text = "エンドレス"
			"COOP": mode_text = "協力"
			"TUTORIAL": mode_text = "チュートリアル"
		_score_label.text = "%s | %s %d年 %s" % [mode_text, m.get("subject", ""), m.get("grade", 0), m.get("difficulty", "")]
	_score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score_label.offset_right = -20.0
	_score_label.offset_top = 16.0
	_score_label.add_theme_font_size_override("font_size", 16)
	_score_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_score_label.add_theme_constant_override("outline_size", 3)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_score_label)

	# 操作ヒント
	var hint := Label.new()
	hint.text = "右ドラッグ: 回転  WASD: 移動  ホイール: ズーム"
	hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hint.offset_left = 20.0
	hint.offset_top = 48.0
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	add_child(hint)

func _create_btn(text: String, width: float, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(width, 36)
	btn.add_theme_font_size_override("font_size", 15)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.85)
	style.border_color = accent.lerp(Color.WHITE, 0.1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0

	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.15, 0.18, 0.25, 0.95)
	hover.border_color = accent.lerp(Color.WHITE, 0.3)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0.88, 0.90, 0.95))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	return btn

func _update_play_btn() -> void:
	if replay_player.is_paused or not replay_player.is_playing:
		_play_btn.text = "⏵"
	else:
		_play_btn.text = "⏸"

func _on_pause_changed(_paused: bool) -> void:
	_update_play_btn()

func _on_speed_changed(_speed: float) -> void:
	_speed_btn.text = replay_player.get_speed_label()

func _on_camera_mode_changed(_mode: ReplayCamera.Mode) -> void:
	_camera_btn.text = replay_camera.get_mode_label()

func _on_share_pressed() -> void:
	if not replay_player or not replay_player.recorder:
		return
	# リプレイデータをファイルに保存し、パスを表示
	var path := replay_player.recorder.save_to_file()
	if not path.is_empty():
		_share_btn.text = "✓ 保存済"
		# 3秒後にテキストを戻す
		var tree := get_tree()
		if tree:
			tree.create_timer(3.0).timeout.connect(func():
				_share_btn.text = "📤 共有"
			)

extends CanvasLayer

@onready var flash_rect: ColorRect = $FlashRect

## ゲーム中HUD (3Dシーン上に重ねて表示)
## Python版 hud.py の _draw_play 部分に相当

@onready var question_label: Label = $QuestionPanel/QuestionLabel
@onready var question_panel: PanelContainer = $QuestionPanel
@onready var score_label: Label = $ScoreLabel
@onready var message_label: Label = $MessageLabel
@onready var progress_bar: ProgressBar = $ProgressBar

@onready var preload_panel: Panel = $PreloadPanel
@onready var preload_bg: ColorRect = $PreloadBackground
@onready var pl_progress: ProgressBar = $PreloadPanel/ProgressBar
@onready var pl_status: Label = $PreloadPanel/Status
@onready var start_prompt_label: Label = $PreloadPanel/StartPromptLabel

@onready var game_over_panel: Panel = $GameOverPanel
@onready var go_title: Label = $GameOverPanel/Title
@onready var go_message: Label = $GameOverPanel/MessageBox/Message
@onready var go_rate_box: VBoxContainer = $GameOverPanel/RateBox
@onready var btn_good: Button = $GameOverPanel/RateBox/HBoxContainer/RateGoodBtn
@onready var btn_bad: Button = $GameOverPanel/RateBox/HBoxContainer/RateBadBtn
@onready var rate_feedback: Label = $GameOverPanel/RateBox/RateFeedback
@onready var btn_menu: Button = $GameOverPanel/MenuBtn
@onready var btn_retry: Button = $GameOverPanel/RetryBtn
@onready var btn_history: Button = $GameOverPanel/HistoryBtn

@onready var history_panel: Panel = $HistoryPanel
@onready var history_back_btn: Button = $HistoryPanel/HeaderBar/BackBtn
@onready var history_list: VBoxContainer = $HistoryPanel/ScrollContainer/HistoryList

var game_state: QuizGameState
var _go_fade_timer: float = 0.0
var _history_built: bool = false
var _stats_panel: PanelContainer = null

var _score_anim_timer: float = 0.0
var _displayed_score: float = 0.0
var _target_score: int = 0
var _streak_label: Label = null
var _confetti_fired: bool = false
var _tutorial_panel: PanelContainer = null
var _tutorial_title: Label = null
var _tutorial_detail: Label = null
var _tutorial_keys_box: HBoxContainer = null
var _tutorial_key_signature: String = ""
var _tutorial_emote_panel: PanelContainer = null
var _tutorial_emote_preview: Control = null
var _tutorial_emote_p1_slots: Label = null
var _tutorial_emote_p2_slots: Label = null
var _tutorial_emote_signature: String = ""



func _ready() -> void:
	game_state = QuizManager.game_state
	message_label.visible = false
	preload_bg.visible = false
	preload_panel.visible = false
	game_over_panel.visible = false
	history_panel.visible = false

	# プリロード用プログレスバーのスタイル設定（ダーク背景で見えるように）
	var pl_bg_style := StyleBoxFlat.new()
	pl_bg_style.bg_color = Color(0.12, 0.14, 0.22, 1.0)
	pl_bg_style.border_color = Color(0.3, 0.4, 0.6, 0.5)
	pl_bg_style.set_border_width_all(1)
	pl_bg_style.set_corner_radius_all(6)
	pl_progress.add_theme_stylebox_override("background", pl_bg_style)

	var pl_fill_style := StyleBoxFlat.new()
	pl_fill_style.bg_color = Color(0.25, 0.55, 1.0, 1.0)
	pl_fill_style.set_corner_radius_all(5)
	pl_progress.add_theme_stylebox_override("fill", pl_fill_style)
	pl_progress.custom_minimum_size.y = 22.0

	# フェードイン（ゲームシーン開始時）


	# Create streak label for in-game display
	_streak_label = Label.new()
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_streak_label.add_theme_font_size_override("font_size", 18)
	_streak_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	_streak_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_streak_label.add_theme_constant_override("outline_size", 3)
	_streak_label.visible = false
	# Position below the score label
	_streak_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_streak_label.offset_left = -200.0
	_streak_label.offset_top = 44.0
	_streak_label.offset_right = -16.0
	_streak_label.offset_bottom = 68.0
	add_child(_streak_label)

	# Build the stats panel for game over (created once, updated per game)
	_create_stats_panel()
	_create_tutorial_overlay()



	btn_good.pressed.connect(func():
		game_state.rate_last_question(true)
		_show_feedback("◯ 良い問題として評価しました")
	)
	btn_bad.pressed.connect(func():
		game_state.rate_last_question(false)
		_show_feedback("× 悪い問題として評価しました")
	)
	btn_menu.pressed.connect(func():

		game_state.reset_to_menu()
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	)
	btn_retry.pressed.connect(func():
		game_state.start_game()
		get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	)
	btn_history.pressed.connect(func():
		_open_history()
	)
	history_back_btn.pressed.connect(func():
		_close_history()
	)

func _show_feedback(txt: String) -> void:
	btn_good.get_parent().visible = false
	rate_feedback.text = txt
	rate_feedback.visible = true

func _process(_dt: float) -> void:
	if not game_state:
		return

	if game_state.game_state == Constants.STATE_PRELOADING:
		_show_preloading(_dt)
		_update_tutorial_overlay(_dt)
		return
	elif game_state.game_state == Constants.STATE_WAITING_START:
		_show_waiting_start(_dt)
		_update_tutorial_overlay(_dt)
		return
	elif game_state.game_state == Constants.STATE_FLYOVER:
		preload_bg.visible = false
		preload_panel.visible = false
		question_panel.visible = false
		score_label.visible = false
		progress_bar.visible = false
		game_over_panel.visible = false
		message_label.visible = false

		_update_tutorial_overlay(_dt)
		return
	else:
		preload_bg.visible = false
		preload_panel.visible = false

	if game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
		_go_fade_timer += _dt
		_show_game_over()
	else:
		_go_fade_timer = 0.0
		_score_anim_timer = 0.0
		_displayed_score = 0.0
		_confetti_fired = false
		game_over_panel.visible = false
		history_panel.visible = false
		_history_built = false

	_update_question()
	_update_score()
	_update_message()
	_update_progress()
	_update_flash()
	_update_streak_label()
	_update_tutorial_overlay(_dt)

func _update_flash() -> void:
	if game_state.correct_flash > 0.0:
		flash_rect.color = Color(0.2, 1.0, 0.4, game_state.correct_flash * 0.4)
		flash_rect.visible = true
	elif game_state.wrong_flash > 0.0:
		flash_rect.color = Color(1.0, 0.2, 0.2, game_state.wrong_flash * 0.6)
		flash_rect.visible = true
	else:
		flash_rect.visible = false

var _displayed_progress: float = 0.0

func _show_preloading(dt: float) -> void:
	preload_bg.visible = false
	preload_panel.visible = true
	question_panel.visible = false
	score_label.visible = false
	message_label.visible = false
	progress_bar.visible = false
	game_over_panel.visible = false
	pl_progress.visible = true
	start_prompt_label.visible = false

	pl_status.text = game_state.status_text

	var target: int = 1 if game_state.mode == Constants.MODE_ENDLESS else game_state.target_count
	target = maxi(1, target)
	var current: int = mini(game_state.quiz_list.size(), target)

	pl_progress.max_value = float(target)
	_displayed_progress = clampf(_displayed_progress, 0.0, float(current))

	# スムーズな進行度アニメーション (実際の取得数にlerpで追いつかせる)
	if current < target:
		_displayed_progress = lerpf(_displayed_progress, float(current), dt * 10.0)
	else:
		# 完了時はキッチリ合わせる
		_displayed_progress = float(target)

	pl_progress.value = _displayed_progress

var _blink_timer: float = 0.0
func _show_waiting_start(dt: float) -> void:
	preload_bg.visible = false
	preload_panel.visible = true
	question_panel.visible = false
	score_label.visible = false
	message_label.visible = false
	progress_bar.visible = false
	game_over_panel.visible = false

	pl_status.text = "読み込み完了"
	pl_progress.visible = false
	start_prompt_label.visible = true
	if game_state.mode == Constants.MODE_TUTORIAL:
		start_prompt_label.text = "[ 任意のキーでチュートリアル開始 ]"
	else:
		start_prompt_label.text = "[ 任意のキーを押してスタート ]"

	_blink_timer += dt
	start_prompt_label.modulate.a = 0.5 + 0.5 * sin(_blink_timer * 6.0)

func _update_flyover_message() -> void:
	message_label.visible = true
	var progress := clampf(game_state.flyover_timer / game_state.flyover_duration, 0.0, 1.0)
	var wall_count := game_state.flyover_total_walls
	var showing := ceili(progress * wall_count)
	if progress < 0.15:
		message_label.text = "全%d問のコースを確認中..." % wall_count
	elif progress < 0.85:
		message_label.text = "Q%d / %d" % [wall_count - showing + 1, wall_count]
	else:
		message_label.text = "スタート準備!"
	message_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	message_label.add_theme_font_size_override("font_size", 42)
	message_label.modulate.a = 1.0


# ============================================================
# Game Over / Clear スコア表示 (強化版)
# ============================================================

func _create_stats_panel() -> void:
	"""ゲームオーバー時の統合メインカードを構築"""
	# tscn側のMessageBoxとRateBoxは非表示にする（カード内に統合）
	go_message.get_parent().visible = false
	go_rate_box.visible = false

	_stats_panel = PanelContainer.new()
	_stats_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.14, 0.92)
	style.border_color = Color(0.25, 0.4, 0.8, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 32.0
	style.content_margin_right = 32.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	_stats_panel.add_theme_stylebox_override("panel", style)
	# 画面中央に配置、タイトルの直下〜ボタンの上まで
	_stats_panel.set_anchors_preset(Control.PRESET_CENTER)
	_stats_panel.offset_left = -340.0
	_stats_panel.offset_top = -195.0
	_stats_panel.offset_right = 340.0
	_stats_panel.offset_bottom = 195.0
	_stats_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	game_over_panel.add_child(_stats_panel)

func _create_tutorial_overlay() -> void:
	_tutorial_panel = PanelContainer.new()
	_tutorial_panel.visible = false
	var style := StyleBoxFlat.new()
	# --- より透過的な背景で3Dキャラクターが見えるように ---
	style.bg_color = Color(0.02, 0.04, 0.10, 0.62)
	style.border_color = Color(0.28, 0.46, 0.88, 0.55)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 10.0
	_tutorial_panel.add_theme_stylebox_override("panel", style)
	_tutorial_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(_tutorial_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	_tutorial_panel.add_child(root)

	_tutorial_title = Label.new()
	_tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_title.add_theme_font_size_override("font_size", 18)
	_tutorial_title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.32))
	# アウトライン追加（半透明背景でも文字が読めるように）
	_tutorial_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_tutorial_title.add_theme_constant_override("outline_size", 4)
	root.add_child(_tutorial_title)

	_tutorial_detail = Label.new()
	_tutorial_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_detail.add_theme_font_size_override("font_size", 14)
	_tutorial_detail.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	_tutorial_detail.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tutorial_detail.add_theme_constant_override("outline_size", 3)
	root.add_child(_tutorial_detail)

	_tutorial_keys_box = HBoxContainer.new()
	_tutorial_keys_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_tutorial_keys_box.add_theme_constant_override("separation", 14)
	root.add_child(_tutorial_keys_box)

func _update_tutorial_overlay(dt: float = 0.0) -> void:
	if not _tutorial_panel or not game_state:
		return
	var tutorial_visible := (
		game_state.mode == Constants.MODE_TUTORIAL
		and game_state.game_state in [
			Constants.STATE_WAITING_START,
			Constants.STATE_COUNTDOWN,
			Constants.STATE_PLAYING,
		]
	)
	if not tutorial_visible:
		_tutorial_panel.visible = false
		_tutorial_key_signature = ""
		return

	_tutorial_panel.visible = true
	_tutorial_title.text = game_state.tutorial_instruction_text()
	_tutorial_detail.text = game_state.tutorial_detail_text()
	var is_2p := game_state.num_players >= 2
	# --- パネルを画面最下部にコンパクト配置（キャラクターと重ならない） ---
	_tutorial_panel.offset_left = 60.0
	_tutorial_panel.offset_right = -60.0
	_tutorial_panel.offset_top = -148.0 if is_2p else -128.0
	_tutorial_panel.offset_bottom = 0.0

	var signature := "%d:%d:%s" % [
		game_state.num_players,
		game_state.current_index,
		game_state.game_state,
	]
	if signature != _tutorial_key_signature:
		_tutorial_key_signature = signature
		_rebuild_tutorial_keys()

func _rebuild_tutorial_keys() -> void:
	if not _tutorial_keys_box:
		return
	for child in _tutorial_keys_box.get_children():
		child.queue_free()

	if game_state.num_players >= 2:
		_add_tutorial_player_keys(
			"P1",
			PackedStringArray(["W", "A", "S", "D", "Space", "1, 2, 3"]),
			PackedStringArray(["前", "左", "後", "右", "ジャンプ", "エモート"]),
			Color(0.40, 0.66, 1.0)
		)
		_add_tutorial_player_keys(
			"P2",
			PackedStringArray(["↑", "←", "↓", "→", "Ctrl / Num0", "8, 9, 0"]),
			PackedStringArray(["前", "左", "後", "右", "ジャンプ", "エモート"]),
			Color(0.35, 0.95, 0.64)
		)
	else:
		_add_tutorial_player_keys(
			"P1",
			PackedStringArray(["W / ↑", "A / ←", "S / ↓", "D / →", "Space", "1, 2, 3"]),
			PackedStringArray(["前", "左", "後", "右", "ジャンプ", "エモート"]),
			Color(0.40, 0.66, 1.0)
		)

func _add_tutorial_player_keys(
		player_label: String,
		keys: PackedStringArray,
		captions: PackedStringArray,
		accent: Color) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 3)
	block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tutorial_keys_box.add_child(block)

	var label := Label.new()
	label.text = player_label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", accent)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 2)
	block.add_child(label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	block.add_child(row)

	for i: int in range(keys.size()):
		var caption := captions[i] if i < captions.size() else ""
		_add_key_chip(row, keys[i], caption, accent, _tutorial_key_highlighted(caption))

func _add_key_chip(
		parent: HBoxContainer,
		key_text: String,
		caption: String,
		accent: Color,
		highlighted: bool) -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 1)
	parent.add_child(stack)

	var key_panel := PanelContainer.new()
	var width := clampf(float(key_text.length()) * 10.0 + 18.0, 36.0, 100.0)
	key_panel.custom_minimum_size = Vector2(width, 28.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.26, 0.39, 0.80) if highlighted else Color(0.08, 0.10, 0.17, 0.72)
	style.border_color = Color(1.0, 0.86, 0.22, 1.0) if highlighted else accent.lerp(Color.WHITE, 0.15)
	style.set_border_width_all(2 if highlighted else 1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	key_panel.add_theme_stylebox_override("panel", style)
	stack.add_child(key_panel)

	var key_label := Label.new()
	key_label.text = key_text
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", 14 if key_text.length() <= 6 else 12)
	key_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45) if highlighted else Color(0.92, 0.95, 1.0))
	key_panel.add_child(key_label)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override("font_size", 10)
	caption_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.32) if highlighted else Color(0.58, 0.64, 0.78))
	stack.add_child(caption_label)

func _tutorial_key_highlighted(caption: String) -> bool:
	if not game_state or game_state.game_state != Constants.STATE_PLAYING:
		return false
	match game_state.current_index:
		0:
			return caption == "左"
		1:
			return caption == "右"
		_:
			return caption == "左"


func _show_game_over() -> void:
	var is_clear := game_state.game_state == Constants.STATE_CLEAR

	if not is_clear and _go_fade_timer < 4.0:
		game_over_panel.visible = false
		return

	game_over_panel.visible = true
	# tscn側のMessageBox/RateBoxは常に非表示（カード内に統合済）
	go_message.get_parent().visible = false

	if not is_clear:
		var alpha := clampf((_go_fade_timer - 4.0) / 1.0, 0.0, 1.0)
		game_over_panel.modulate.a = alpha
	else:
		game_over_panel.modulate.a = 1.0
		if not _confetti_fired:
			_confetti_fired = true
			_fire_confetti()

	go_title.text = "CLEAR!" if is_clear else "GAME OVER"
	go_title.add_theme_color_override("font_color", Color(1, 0.8, 0.2) if is_clear else Color(1, 0.3, 0.3))

	# Parse message: remove redundant GAME OVER/CLEAR text
	var raw_msg: String = game_state.message_text
	if raw_msg.begins_with("GAME OVER\n\n"):
		raw_msg = raw_msg.substr(11)
	elif raw_msg.begins_with("GAME OVER\n"):
		raw_msg = raw_msg.substr(10)
	elif raw_msg.begins_with("CLEAR!"):
		var parts = raw_msg.split("\n")
		var new_parts = []
		for p in parts:
			if not p.begins_with("CLEAR!") and not "questions done" in p and not "問完走" in p and not "Score:" in p and not "正解数:" in p:
				new_parts.append(p)
		raw_msg = "\n".join(new_parts)
	elif raw_msg.begins_with("TUTORIAL CLEAR!"):
		var tutorial_parts = raw_msg.split("\n")
		if tutorial_parts.size() > 1:
			tutorial_parts.remove_at(0)
		raw_msg = "\n".join(tutorial_parts)
	# Strip trailing score lines
	var msg_lines = raw_msg.split("\n\n")
	if msg_lines.size() > 1 and ("Score:" in msg_lines[-1] or "正解数:" in msg_lines[-1]):
		msg_lines.remove_at(msg_lines.size() - 1)
		raw_msg = "\n\n".join(msg_lines)
	raw_msg = raw_msg.strip_edges()

	# Build the unified card content
	_build_result_card(is_clear, raw_msg)

	# NEW RECORD display


	# Bottom buttons
	btn_history.visible = game_state.quiz_history.size() > 0

func _build_result_card(is_clear: bool, explanation: String) -> void:
	"""メインカード内に全リザルト情報を構築"""
	_stats_panel.visible = true
	for child in _stats_panel.get_children():
		child.queue_free()

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	_stats_panel.add_child(root_vbox)

	var current_score: int = game_state.score
	var p2_score: int = game_state.player2_score
	var is_2p: bool = game_state.num_players >= 2
	var is_tutorial: bool = game_state.mode == Constants.MODE_TUTORIAL
	var is_coop: bool = game_state.is_coop_mode()

	# ─── Score animation ───
	_score_anim_timer += 0.016
	var anim_progress := clampf(_score_anim_timer / 1.5, 0.0, 1.0)
	anim_progress = 1.0 - pow(1.0 - anim_progress, 3.0)

	# ─── Row 1: Score display ───
	if is_coop:
		var score_row := HBoxContainer.new()
		score_row.alignment = BoxContainer.ALIGNMENT_CENTER
		score_row.add_theme_constant_override("separation", 12)
		root_vbox.add_child(score_row)

		var score_num := Label.new()
		var displayed := int(anim_progress * current_score)
		score_num.text = "%d" % displayed
		score_num.add_theme_font_size_override("font_size", 48)
		score_num.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if is_clear else Color(0.9, 0.92, 0.95))
		score_row.add_child(score_num)

		var sub := Label.new()
		sub.text = "協力成功 / %d問" % game_state.target_count
		sub.add_theme_font_size_override("font_size", 16)
		sub.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		score_row.add_child(sub)

		var team_label := Label.new()
		team_label.text = "COOP CLEAR" if is_clear else "協力失敗"
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		team_label.add_theme_font_size_override("font_size", 22)
		team_label.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if is_clear else Color(1.0, 0.45, 0.35))
		root_vbox.add_child(team_label)
	elif is_2p:
		var hbox_scores := HBoxContainer.new()
		hbox_scores.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox_scores.add_theme_constant_override("separation", 30)
		root_vbox.add_child(hbox_scores)
		_add_player_score_column(hbox_scores, "P1", current_score, anim_progress,
			current_score > p2_score)
		var vs_label := Label.new()
		vs_label.text = "+" if is_tutorial else "vs"
		vs_label.add_theme_font_size_override("font_size", 20)
		vs_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox_scores.add_child(vs_label)
		_add_player_score_column(hbox_scores, "P2", p2_score, anim_progress,
			p2_score > current_score)

		# Winner
		if is_tutorial:
			var done_label := Label.new()
			done_label.text = "2人で完了 / 3つの壁"
			done_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			done_label.add_theme_font_size_override("font_size", 22)
			done_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			root_vbox.add_child(done_label)
		elif current_score != p2_score:
			var wl := Label.new()
			wl.text = "🏆 %s WIN!" % ("P1" if current_score > p2_score else "P2")
			wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			wl.add_theme_font_size_override("font_size", 22)
			wl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			root_vbox.add_child(wl)
		else:
			var dl := Label.new()
			dl.text = "🤝 DRAW!"
			dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dl.add_theme_font_size_override("font_size", 22)
			dl.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
			root_vbox.add_child(dl)
	else:
		# 1P: score big number + subtitle in an HBox for compactness
		var score_row := HBoxContainer.new()
		score_row.alignment = BoxContainer.ALIGNMENT_CENTER
		score_row.add_theme_constant_override("separation", 12)
		root_vbox.add_child(score_row)

		var score_num := Label.new()
		var displayed := int(anim_progress * current_score)
		score_num.text = "%d" % displayed
		score_num.add_theme_font_size_override("font_size", 48)
		score_num.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if is_clear else Color(0.9, 0.92, 0.95))
		score_row.add_child(score_num)

		if game_state.mode == Constants.MODE_TEN:
			var sub := Label.new()
			sub.text = "正解 / 10問"
			sub.add_theme_font_size_override("font_size", 16)
			sub.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
			sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			score_row.add_child(sub)
		elif is_tutorial:
			var sub := Label.new()
			sub.text = "完了 / 3つの壁"
			sub.add_theme_font_size_override("font_size", 16)
			sub.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
			sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			score_row.add_child(sub)

	# ─── Separator ───
	_add_separator(root_vbox)

	# ─── Row 2: Stats (横並びの4つのミニカード) ───
	var stats_hbox := HBoxContainer.new()
	stats_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_hbox.add_theme_constant_override("separation", 16)
	root_vbox.add_child(stats_hbox)

	var total := game_state.total_answered
	var correct_count := maxi(current_score, p2_score) if is_2p else current_score
	var rate_pct: float = (float(correct_count) / float(total) * 100.0) if total > 0 else 0.0
	var rate_color := Color(0.3, 1.0, 0.5) if rate_pct >= 80.0 else (
		Color(1.0, 0.85, 0.3) if rate_pct >= 50.0 else Color(1.0, 0.4, 0.3))
	_add_mini_stat(stats_hbox, "正答率", "%.0f%%" % rate_pct, rate_color)

	var streak_color := Color(1.0, 0.6, 0.2) if game_state.max_streak >= 3 else Color(0.75, 0.78, 0.85)
	_add_mini_stat(stats_hbox, "連続正解", "%d 🔥" % game_state.max_streak, streak_color)

	var mins := int(game_state.play_time) / 60
	var secs := int(game_state.play_time) % 60
	_add_mini_stat(stats_hbox, "時間", "%d:%02d" % [mins, secs], Color(0.65, 0.7, 0.82))


	# ─── Row 3: Explanation (if any) ───
	if not explanation.is_empty():
		_add_separator(root_vbox)

		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 110)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root_vbox.add_child(scroll)

		var exp_vbox := VBoxContainer.new()
		exp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(exp_vbox)

		var exp_label := Label.new()
		exp_label.text = explanation
		exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		exp_label.add_theme_font_size_override("font_size", 18)
		exp_label.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
		exp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		exp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exp_vbox.add_child(exp_label)

	# ─── Row 4: Rating (if applicable) ───
	if game_state.rating_target_quiz:
		_add_separator(root_vbox)
		if game_state.rating_feedback.is_empty():
			# Show buttons
			go_rate_box.visible = true
			btn_good.get_parent().visible = true
			rate_feedback.visible = false
			# Reparent RateBox into the card
			if go_rate_box.get_parent() != root_vbox:
				go_rate_box.get_parent().remove_child(go_rate_box)
				root_vbox.add_child(go_rate_box)
		else:
			go_rate_box.visible = true
			_show_feedback(game_state.rating_feedback)
			if go_rate_box.get_parent() != root_vbox:
				go_rate_box.get_parent().remove_child(go_rate_box)
				root_vbox.add_child(go_rate_box)
	else:
		go_rate_box.visible = false

func _add_mini_stat(parent: HBoxContainer, title: String, value: String, color: Color) -> void:
	"""統計ミニカード: タイトル + 値の縦並び"""
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)

	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", 20)
	val_lbl.add_theme_color_override("font_color", color)
	col.add_child(val_lbl)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
	col.add_child(title_lbl)

func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.3, 0.35, 0.5, 0.3))
	parent.add_child(sep)

func _add_player_score_column(parent: HBoxContainer, label_text: String, score_val: int,
		anim_progress: float, is_winner: bool) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	parent.add_child(col)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.2) if is_winner else Color(0.6, 0.65, 0.75))
	col.add_child(name_label)

	var val_label := Label.new()
	var displayed := int(anim_progress * score_val)
	val_label.text = "%d" % displayed
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_label.add_theme_font_size_override("font_size", 40)
	val_label.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.2) if is_winner else Color(0.85, 0.88, 0.92))
	col.add_child(val_label)

func _add_stat_row(grid: GridContainer, label_text: String, value_text: String, value_color: Color) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	grid.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", value_color)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(val)


func _update_question() -> void:
	if game_state.current_quiz and game_state.game_state == Constants.STATE_PLAYING:
		question_panel.visible = true
		if game_state.is_coop_mode() and game_state.current_quiz.has_coop_data():
			var q_text := FractionFormatter.to_inline(game_state.current_quiz.q)
			var p1_role := game_state.current_quiz.coop_p1_label
			var p2_role := game_state.current_quiz.coop_p2_label
			question_label.text = "%s\n%s / %s" % [q_text, p1_role, p2_role]
		else:
			question_label.text = FractionFormatter.to_inline(game_state.current_quiz.q)
	else:
		question_panel.visible = false

func _update_score() -> void:
	if game_state.game_state in [Constants.STATE_PLAYING, Constants.STATE_CORRECT, Constants.STATE_GOAL_RACE]:
		score_label.visible = true
		if game_state.num_players >= 2:
			if game_state.mode == Constants.MODE_TUTORIAL:
				score_label.text = "2P練習  P1:%d  P2:%d" % [game_state.score, game_state.player2_score]
			elif game_state.is_coop_mode():
				score_label.text = "協力: %d/%d" % [game_state.score, game_state.target_count]
			else:
				score_label.text = "P1: %d  P2: %d" % [game_state.score, game_state.player2_score]
		else:
			if game_state.mode == Constants.MODE_TUTORIAL:
				score_label.text = "チュートリアル: %d/%d" % [
					mini(game_state.current_index + 1, game_state.target_count),
					game_state.target_count
				]
			elif game_state.mode == Constants.MODE_TEN:
				score_label.text = "正解: %d  問題: %d/10" % [game_state.score, game_state.current_index + 1]
			else:
				score_label.text = "正解: %d" % game_state.score
	else:
		score_label.visible = false

func _update_streak_label() -> void:
	if not _streak_label:
		return
	if game_state.game_state in [Constants.STATE_PLAYING, Constants.STATE_CORRECT]:
		if game_state.current_streak >= 2:
			_streak_label.visible = true
			_streak_label.text = "🔥 %d連続正解!" % game_state.current_streak
			# Color intensifies with streak
			var intensity := clampf(float(game_state.current_streak - 2) / 8.0, 0.0, 1.0)
			_streak_label.add_theme_color_override("font_color", Color(
				1.0,
				0.6 - intensity * 0.3,
				0.2 - intensity * 0.15
			))
			# Slight pulse on the streak label
			var pulse := 0.85 + 0.15 * sin(_go_fade_timer * 6.0)  # reuse timer is 0 during gameplay, use correct_flash
			if game_state.correct_flash > 0.0:
				_streak_label.scale = Vector2(1.15, 1.15)
			else:
				_streak_label.scale = Vector2(1.0, 1.0)
		else:
			_streak_label.visible = false
	else:
		_streak_label.visible = false

func _update_message() -> void:
	if game_state.game_state == Constants.STATE_GOAL_RACE:
		message_label.visible = true
		message_label.text = game_state.message_text
		# Pulsating gold text
		var pulse: float = (sin(Time.get_ticks_msec() * 0.004) + 1.0) * 0.5
		message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.15 + pulse * 0.2))
		message_label.add_theme_font_size_override("font_size", 48)
		message_label.modulate.a = 1.0
	elif game_state.correct_flash > 0.0 and game_state.message_text:
		message_label.visible = true
		message_label.text = game_state.message_text
		message_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		message_label.add_theme_font_size_override("font_size", 36)
		message_label.modulate.a = clampf(game_state.correct_flash * 2.0, 0.0, 1.0)
	else:
		message_label.visible = false

func _update_progress() -> void:
	if game_state.mode == Constants.MODE_TEN and \
			game_state.game_state in [Constants.STATE_PLAYING, Constants.STATE_CORRECT]:
		progress_bar.visible = true
		progress_bar.max_value = 10
		progress_bar.value = game_state.current_index
	else:
		progress_bar.visible = false


# ============================================================
# 問題履歴パネル
# ============================================================

func _open_history() -> void:
	if not _history_built:
		_build_history_items()
		_history_built = true

	game_over_panel.visible = false
	history_panel.visible = true
	history_panel.modulate.a = 1.0
	history_panel.position.x = 0.0

func _close_history() -> void:
	history_panel.visible = false
	game_over_panel.visible = true
	game_over_panel.modulate.a = 1.0

func _build_history_items() -> void:
	# Clear existing items
	for child in history_list.get_children():
		child.queue_free()

	if game_state.quiz_history.is_empty():
		var empty_label := Label.new()
		empty_label.text = "出題された問題はありません"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 20)
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		history_list.add_child(empty_label)
		return

	for i: int in range(game_state.quiz_history.size()):
		var entry: Dictionary = game_state.quiz_history[i]
		var quiz: QuizItem = entry["quiz"]
		var correct: bool = entry["correct"]
		var rated: String = entry.get("rated", "")

		var card := _create_history_card(i, quiz, correct, rated)
		history_list.add_child(card)

func _create_history_card(index: int, quiz: QuizItem, correct: bool, rated: String) -> PanelContainer:
	var card := PanelContainer.new()

	# Card style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.16, 0.9)
	style.border_color = Color(0.3, 0.7, 0.4, 0.8) if correct else Color(0.8, 0.3, 0.2, 0.8)
	style.border_width_left = 4
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# --- Header: Q number + result icon + question text ---
	var header := Label.new()
	var icon: String = "◯" if correct else "✗"
	var icon_color_tag: String
	if correct:
		icon_color_tag = "Q%d  %s" % [index + 1, icon]
	else:
		icon_color_tag = "Q%d  %s" % [index + 1, icon]
	var question_text := quiz.coop_prompt if quiz.has_coop_data() and not quiz.coop_prompt.is_empty() else quiz.q
	header.text = "%s  %s" % [icon_color_tag, FractionFormatter.to_inline(question_text)]
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5) if correct else Color(1.0, 0.4, 0.3))
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(header)

	var entry: Dictionary = game_state.quiz_history[index]

	# --- Choices ---
	var choices_box := VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 2)
	vbox.add_child(choices_box)

	if quiz.has_coop_data():
		_add_coop_history_choices(choices_box, quiz, entry)
	else:
		var labels_4 := ["A", "B", "C", "D"]
		for ci: int in range(quiz.c.size()):
			var choice_label := Label.new()
			var prefix: String
			if quiz.c.size() <= 2:
				prefix = "左" if ci == 0 else "右"
			else:
				prefix = labels_4[ci] if ci < 4 else str(ci)

			var is_correct_choice := (ci == quiz.a)
			choice_label.text = "  %s: %s %s" % [prefix, FractionFormatter.to_inline(quiz.c[ci]), "✓" if is_correct_choice else ""]
			choice_label.add_theme_font_size_override("font_size", 17)
			if is_correct_choice:
				choice_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
			else:
				choice_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
			choice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			choices_box.add_child(choice_label)

	# --- Explanation ---
	if not quiz.e.is_empty():
		var explain_label := Label.new()
		explain_label.text = "📝 %s" % FractionFormatter.to_inline(quiz.e)
		explain_label.add_theme_font_size_override("font_size", 16)
		explain_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.75))
		explain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(explain_label)

	# --- Rating buttons ---
	var rate_container := HBoxContainer.new()
	rate_container.alignment = BoxContainer.ALIGNMENT_END
	rate_container.add_theme_constant_override("separation", 12)
	vbox.add_child(rate_container)

	var player_rated: bool = entry.get("player_rated", false)
	if not player_rated:
		# Show rating buttons, optionally mentioning AI's rating if any
		var rate_label := Label.new()
		if rated == "good":
			rate_label.text = "AI評価:良い | あなたの評価:"
		elif rated == "bad":
			rate_label.text = "AI評価:悪い | あなたの評価:"
		else:
			rate_label.text = "この問題の評価:"
		rate_label.add_theme_font_size_override("font_size", 15)
		rate_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		rate_container.add_child(rate_label)

		var good_btn := Button.new()
		good_btn.text = "◯ 良い"
		good_btn.custom_minimum_size = Vector2(100, 36)
		good_btn.add_theme_font_size_override("font_size", 16)
		good_btn.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		rate_container.add_child(good_btn)

		var bad_btn := Button.new()
		bad_btn.text = "× 悪い"
		bad_btn.custom_minimum_size = Vector2(100, 36)
		bad_btn.add_theme_font_size_override("font_size", 16)
		bad_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		rate_container.add_child(bad_btn)

		# Capture index for closure
		var idx := index
		good_btn.pressed.connect(func():
			game_state.rate_quiz_at(idx, true)
			_replace_rate_buttons(rate_container, true)
		)
		bad_btn.pressed.connect(func():
			game_state.rate_quiz_at(idx, false)
			_replace_rate_buttons(rate_container, false)
		)
	else:
		# Already rated by player manually — show feedback
		var feedback := Label.new()
		if rated == "good":
			feedback.text = "◯ 良い問題として評価しました"
			feedback.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		else:
			feedback.text = "× 悪い問題として評価しました"
			feedback.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		feedback.add_theme_font_size_override("font_size", 15)
		rate_container.add_child(feedback)

	return card

func _add_coop_history_choices(choices_box: VBoxContainer, quiz: QuizItem, entry: Dictionary) -> void:
	var p1_chosen: int = int(entry.get("p1_choice", -99))
	var p2_chosen: int = int(entry.get("p2_choice", -99))
	_add_coop_history_role(choices_box, quiz.coop_p1_label, quiz.coop_p1_choices, quiz.coop_p1_answer, p1_chosen)
	_add_coop_history_role(choices_box, quiz.coop_p2_label, quiz.coop_p2_choices, quiz.coop_p2_answer, p2_chosen)

func _add_coop_history_role(choices_box: VBoxContainer, title: String,
		choices: PackedStringArray, answer: int, chosen: int) -> void:
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.75))
	choices_box.add_child(title_label)

	var names := ["A", "B"]
	for ci: int in range(mini(2, choices.size())):
		var choice_label := Label.new()
		var is_correct_choice := ci == answer
		var picked := " / 選択" if ci == chosen else ""
		choice_label.text = "  %s: %s%s %s" % [
			names[ci],
			FractionFormatter.to_inline(choices[ci]),
			picked,
			"✓" if is_correct_choice else ""
		]
		choice_label.add_theme_font_size_override("font_size", 17)
		choice_label.add_theme_color_override("font_color",
			Color(0.3, 1.0, 0.5) if is_correct_choice else Color(0.65, 0.7, 0.75))
		choice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		choices_box.add_child(choice_label)

func _replace_rate_buttons(container: HBoxContainer, good: bool) -> void:
	# Remove all children
	for child in container.get_children():
		child.queue_free()

	# Add feedback label
	var feedback := Label.new()
	if good:
		feedback.text = "◯ 良い問題として評価しました"
		feedback.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	else:
		feedback.text = "× 悪い問題として評価しました"
		feedback.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	feedback.add_theme_font_size_override("font_size", 15)
	container.add_child(feedback)

func _fire_confetti() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	# Center position (assuming CLEAR! text is somewhat central, slightly top)
	var center_pos = Vector2(viewport_size.x / 2.0, viewport_size.y * 0.3)

	# Create two emitters (left and right) to burst from center outwards
	var angles = [200.0, 340.0]  # Slightly upwards left and right
	var colors = [Color.RED, Color.YELLOW, Color.GREEN, Color.CYAN, Color.MAGENTA, Color.WHITE, Color.ORANGE]

	for i in range(2):
		var emitter = CPUParticles2D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 0.8
		emitter.amount = 60
		emitter.lifetime = 3.0

		# Position relative to go_title or screen center
		emitter.position = go_title.global_position + Vector2(go_title.size.x / 2.0, go_title.size.y / 2.0)

		# Emission shape
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emitter.emission_rect_extents = Vector2(40.0, 20.0)

		# Movement
		emitter.direction = Vector2.UP.rotated(deg_to_rad(angles[i] - 270.0))
		if i == 0:
			emitter.direction = Vector2(-1, -0.5).normalized()
		else:
			emitter.direction = Vector2(1, -0.5).normalized()

		emitter.spread = 35.0
		emitter.gravity = Vector2(0, 900.0)
		emitter.initial_velocity_min = 400.0
		emitter.initial_velocity_max = 750.0
		emitter.angular_velocity_min = -360.0
		emitter.angular_velocity_max = 360.0

		# Size and scale
		emitter.scale_amount_min = 6.0
		emitter.scale_amount_max = 12.0

		# Color curve for fading out
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(1, 1, 1, 1))
		gradient.add_point(0.7, Color(1, 1, 1, 1))
		gradient.add_point(1.0, Color(1, 1, 1, 0))
		emitter.color_ramp = gradient

		# Random colors from preset
		emitter.color_initial_ramp = Gradient.new()
		emitter.color_initial_ramp.set_color(0, colors[randi() % colors.size()])
		emitter.color_initial_ramp.set_color(1, colors[randi() % colors.size()])

		# Actually, CPUParticles2D doesn't support multiple discrete colors easily without a texture.
		# Let's make multiple small emitters to get different colors.
		pass

	# Better approach for discrete colors: multiple small emitters
	for col in colors:
		var emitter = CPUParticles2D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 0.9
		emitter.amount = 15
		emitter.lifetime = 2.5

		if go_title.is_inside_tree():
			emitter.position = go_title.global_position + Vector2(go_title.size.x / 2.0, go_title.size.y / 2.0)
		else:
			emitter.position = center_pos

		emitter.direction = Vector2(0, -1)
		emitter.spread = 75.0
		emitter.gravity = Vector2(0, 800.0)
		emitter.initial_velocity_min = 350.0
		emitter.initial_velocity_max = 850.0
		emitter.angular_velocity_min = -720.0
		emitter.angular_velocity_max = 720.0

		emitter.scale_amount_min = 8.0
		emitter.scale_amount_max = 16.0
		emitter.color = col

		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(1, 1, 1, 1))
		gradient.add_point(0.7, Color(1, 1, 1, 1))
		gradient.add_point(1.0, Color(1, 1, 1, 0))
		emitter.color_ramp = gradient

		add_child(emitter)
		emitter.emitting = true

		# Self destruct timer
		var timer = get_tree().create_timer(3.0)
		timer.timeout.connect(func(): if is_instance_valid(emitter): emitter.queue_free())


# ============================================================
# ローディング演出（プリロード中のアニメーション強化）

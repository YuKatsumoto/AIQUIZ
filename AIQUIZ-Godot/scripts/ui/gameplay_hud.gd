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
@onready var btn_history: Button = $GameOverPanel/HistoryBtn

@onready var history_panel: Panel = $HistoryPanel
@onready var history_back_btn: Button = $HistoryPanel/HeaderBar/BackBtn
@onready var history_list: VBoxContainer = $HistoryPanel/ScrollContainer/HistoryList

var game_state: QuizGameState
var _go_fade_timer: float = 0.0
var _history_built: bool = false

func _ready() -> void:
	game_state = QuizManager.game_state
	message_label.visible = false
	preload_bg.visible = false
	preload_panel.visible = false
	game_over_panel.visible = false
	history_panel.visible = false
	
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
		_show_preloading()
		return
	elif game_state.game_state == Constants.STATE_WAITING_START:
		_show_waiting_start(_dt)
		return
	else:
		preload_bg.visible = false
		preload_panel.visible = false
	if game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
		_go_fade_timer += _dt
		_show_game_over()
	else:
		_go_fade_timer = 0.0
		game_over_panel.visible = false
		history_panel.visible = false
		_history_built = false

	_update_question()
	_update_score()
	_update_message()
	_update_progress()
	_update_flash()

func _update_flash() -> void:
	if game_state.correct_flash > 0.0:
		flash_rect.color = Color(0.2, 1.0, 0.4, game_state.correct_flash * 0.4)
		flash_rect.visible = true
	elif game_state.wrong_flash > 0.0:
		flash_rect.color = Color(1.0, 0.2, 0.2, game_state.wrong_flash * 0.6)
		flash_rect.visible = true
	else:
		flash_rect.visible = false

func _show_preloading() -> void:
	preload_bg.visible = true
	preload_panel.visible = true
	question_panel.visible = false
	score_label.visible = false
	message_label.visible = false
	progress_bar.visible = false
	game_over_panel.visible = false
	pl_progress.visible = true
	start_prompt_label.visible = false
	
	pl_status.text = game_state.status_text
	
	if QuizManager.provider is BufferedQuizProvider:
		var bp = QuizManager.provider as BufferedQuizProvider
		var target: int = bp.target_count if bp.current_mode == Constants.MODE_TEN else 1
		var current: int = bp.buffer.size()
		pl_progress.max_value = target
		pl_progress.value = current

var _blink_timer: float = 0.0
func _show_waiting_start(dt: float) -> void:
	preload_bg.visible = true
	preload_panel.visible = true
	question_panel.visible = false
	score_label.visible = false
	message_label.visible = false
	progress_bar.visible = false
	game_over_panel.visible = false
	
	pl_status.text = "読み込み完了"
	pl_progress.visible = false
	start_prompt_label.visible = true
	
	_blink_timer += dt
	start_prompt_label.modulate.a = 0.5 + 0.5 * sin(_blink_timer * 6.0)

func _show_game_over() -> void:
	var is_clear := game_state.game_state == Constants.STATE_CLEAR
	
	if not is_clear and _go_fade_timer < 2.0:
		game_over_panel.visible = false
		return
		
	game_over_panel.visible = true
	
	if not is_clear:
		var alpha := clampf((_go_fade_timer - 2.0) / 1.0, 0.0, 1.0)
		game_over_panel.modulate.a = alpha
	else:
		game_over_panel.modulate.a = 1.0
	
	go_title.text = "CLEAR!" if is_clear else "GAME OVER"
	go_title.add_theme_color_override("font_color", Color(1, 0.8, 0.2) if is_clear else Color(1, 0.3, 0.3))
	
	go_message.text = game_state.message_text
	
	# Show history button if there's any history
	btn_history.visible = game_state.quiz_history.size() > 0
	
	if game_state.rating_target_quiz and game_state.rating_feedback.is_empty():
		go_rate_box.visible = true
		btn_good.get_parent().visible = true
		rate_feedback.visible = false
	elif not game_state.rating_feedback.is_empty():
		go_rate_box.visible = true
		_show_feedback(game_state.rating_feedback)
	else:
		go_rate_box.visible = false

func _update_question() -> void:
	if game_state.current_quiz and game_state.game_state == Constants.STATE_PLAYING:
		question_panel.visible = true
		question_label.text = game_state.current_quiz.q
	else:
		question_panel.visible = false

func _update_score() -> void:
	if game_state.game_state in [Constants.STATE_PLAYING, Constants.STATE_CORRECT]:
		score_label.visible = true
		if game_state.num_players >= 2:
			score_label.text = "P1: %d  P2: %d" % [game_state.score, game_state.player2_score]
		else:
			if game_state.mode == Constants.MODE_TEN:
				score_label.text = "正解: %d  問題: %d/10" % [game_state.score, game_state.current_index + 1]
			else:
				score_label.text = "正解: %d" % game_state.score
	else:
		score_label.visible = false

func _update_message() -> void:
	if game_state.game_state == Constants.STATE_COUNTDOWN:
		message_label.visible = true
		var t = ceili(game_state.countdown_timer)
		if t > 0:
			message_label.text = str(t)
		else:
			message_label.text = "GO!"
		message_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		message_label.add_theme_font_size_override("font_size", 160)
	elif game_state.message_text and game_state.game_state == Constants.STATE_CORRECT:
		message_label.visible = true
		message_label.text = game_state.message_text
		message_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		message_label.add_theme_font_size_override("font_size", 36)
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
	history_panel.visible = true
	game_over_panel.visible = false
	if not _history_built:
		_build_history_items()
		_history_built = true

func _close_history() -> void:
	history_panel.visible = false
	game_over_panel.visible = true

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
	header.text = "%s  %s" % [icon_color_tag, quiz.q]
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5) if correct else Color(1.0, 0.4, 0.3))
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(header)
	
	# --- Choices ---
	var choices_box := VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 2)
	vbox.add_child(choices_box)
	
	var labels_4 := ["A", "B", "C", "D"]
	for ci: int in range(quiz.c.size()):
		var choice_label := Label.new()
		var prefix: String
		if quiz.c.size() <= 2:
			prefix = "左" if ci == 0 else "右"
		else:
			prefix = labels_4[ci] if ci < 4 else str(ci)
		
		var is_correct_choice := (ci == quiz.a)
		choice_label.text = "  %s: %s %s" % [prefix, quiz.c[ci], "✓" if is_correct_choice else ""]
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
		explain_label.text = "📝 %s" % quiz.e
		explain_label.add_theme_font_size_override("font_size", 16)
		explain_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.75))
		explain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(explain_label)
	
	# --- Rating buttons ---
	var rate_container := HBoxContainer.new()
	rate_container.alignment = BoxContainer.ALIGNMENT_END
	rate_container.add_theme_constant_override("separation", 12)
	vbox.add_child(rate_container)
	
	if rated.is_empty():
		# Show rating buttons
		var rate_label := Label.new()
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
		# Already rated — show feedback
		var feedback := Label.new()
		if rated == "good":
			feedback.text = "◯ 良い問題として評価済み"
			feedback.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		else:
			feedback.text = "× 悪い問題として評価済み"
			feedback.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		feedback.add_theme_font_size_override("font_size", 15)
		rate_container.add_child(feedback)
	
	return card

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

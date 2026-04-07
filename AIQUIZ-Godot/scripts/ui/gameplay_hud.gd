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
@onready var pl_progress: ProgressBar = $PreloadPanel/ProgressBar
@onready var pl_status: Label = $PreloadPanel/Status

@onready var game_over_panel: Panel = $GameOverPanel
@onready var go_title: Label = $GameOverPanel/Title
@onready var go_message: Label = $GameOverPanel/MessageBox/Message
@onready var go_rate_box: VBoxContainer = $GameOverPanel/RateBox
@onready var btn_good: Button = $GameOverPanel/RateBox/HBoxContainer/RateGoodBtn
@onready var btn_bad: Button = $GameOverPanel/RateBox/HBoxContainer/RateBadBtn
@onready var rate_feedback: Label = $GameOverPanel/RateBox/RateFeedback
@onready var btn_menu: Button = $GameOverPanel/MenuBtn
var game_state: QuizGameState
var _go_fade_timer: float = 0.0

func _ready() -> void:
	game_state = QuizManager.game_state
	message_label.visible = false
	preload_panel.visible = false
	game_over_panel.visible = false
	
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
	else:
		preload_panel.visible = false
	if game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
		_go_fade_timer += _dt
		_show_game_over()
	else:
		_go_fade_timer = 0.0
		game_over_panel.visible = false

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
	preload_panel.visible = true
	question_panel.visible = false
	score_label.visible = false
	message_label.visible = false
	progress_bar.visible = false
	game_over_panel.visible = false
	
	pl_status.text = game_state.status_text
	
	if QuizManager.provider is BufferedQuizProvider:
		var bp = QuizManager.provider as BufferedQuizProvider
		var target: int = bp.target_count if bp.current_mode == Constants.MODE_TEN else 1
		var current: int = bp.buffer.size()
		pl_progress.max_value = target
		pl_progress.value = current

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
	if game_state.message_text and game_state.game_state == Constants.STATE_CORRECT:
		message_label.visible = true
		message_label.text = game_state.message_text
		message_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
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

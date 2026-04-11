extends Node

signal game_started
signal game_over(is_cleared: bool)

# ゲーム全体の設定
var is_2p_mode: bool = false
var selected_difficulty: String = "Normal"
var selected_subject: String = "ALL"
var selected_grade: String = "ALL"
var is_endless_mode: bool = false
var questions_to_clear: int = 10

var current_score: int = 0
var current_question_index: int = 0

func _ready() -> void:
	print("GameManager initialized.")
	_load_env()

func _load_env() -> void:
	# .envファイルの簡易パース（拡張機能として）
	var file = FileAccess.open("res://.env", FileAccess.READ)
	if file:
		while not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.is_empty() or line.begins_with("#"):
				continue
			var parts = line.split("=", true, 1)
			if parts.size() == 2:
				OS.set_environment(parts[0].strip_edges(), parts[1].strip_edges())
		file.close()

func start_game() -> void:
	current_score = 0
	current_question_index = 0
	emit_signal("game_started")
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")

# NOTE: Result handling is done via game_state signals, not scene transitions.

func back_to_menu() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

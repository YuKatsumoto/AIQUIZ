extends Node

## クイズデータ管理 (Autoload)
## QuizProvider のインスタンスを保持し、ゲーム全体に提供する

var provider: QuizProvider
var game_state: QuizGameState
var firebase_ratings: FirebaseRatings
var quiz_optimizer: QuizOptimizer

func _ready() -> void:
	# In STAGE B, we use BufferedQuizProvider which acts as a Node
	provider = load("res://scripts/core/buffered_provider.gd").new()
	add_child(provider)
	
	firebase_ratings = FirebaseRatings.new()
	add_child(firebase_ratings)
	
	quiz_optimizer = preload("res://scripts/core/quiz_optimizer.gd").new()
	add_child(quiz_optimizer)
	
	game_state = QuizGameState.new(provider)
	print("[QuizManager] Started with BufferedQuizProvider, FirebaseRatings, and QuizOptimizer.")

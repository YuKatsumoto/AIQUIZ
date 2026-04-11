extends Node

## クイズデータ管理 (Autoload)
## QuizProvider のインスタンスを保持し、ゲーム全体に提供する

var provider: QuizProvider
var game_state: QuizGameState
var firebase_ratings: FirebaseRatings

func _ready() -> void:
	# In STAGE B, we use BufferedQuizProvider which acts as a Node
	provider = load("res://scripts/core/buffered_provider.gd").new()
	add_child(provider)
	
	firebase_ratings = FirebaseRatings.new()
	add_child(firebase_ratings)
	
	game_state = QuizGameState.new(provider)
	print("[QuizManager] Started with BufferedQuizProvider + FirebaseRatings.")

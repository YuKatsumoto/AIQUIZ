extends Node

## クイズデータ管理 (Autoload)
## QuizProvider のインスタンスを保持し、ゲーム全体に提供する

var provider: QuizProvider
var game_state: QuizGameState
var firebase_ratings: FirebaseRatings
var quiz_optimizer: QuizOptimizer
var quiz_validator: QuizValidator
var player_analytics: PlayerAnalytics

func _ready() -> void:
	# In STAGE B, we use BufferedQuizProvider which acts as a Node
	provider = load("res://scripts/core/buffered_provider.gd").new()
	add_child(provider)
	
	firebase_ratings = FirebaseRatings.new()
	add_child(firebase_ratings)
	
	quiz_optimizer = preload("res://scripts/core/quiz_optimizer.gd").new()
	add_child(quiz_optimizer)
	
	# 案2: 2段階バリデーションパイプライン
	quiz_validator = QuizValidator.new()
	add_child(quiz_validator)
	
	# 案3: プレイヤー行動分析
	player_analytics = PlayerAnalytics.new()
	add_child(player_analytics)
	
	game_state = QuizGameState.new(provider)
	print("[QuizManager] Started with BufferedQuizProvider, FirebaseRatings, QuizOptimizer, QuizValidator, and PlayerAnalytics.")

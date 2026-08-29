extends Node

## クイズデータ管理 (Autoload)
## QuizProvider のインスタンスを保持し、ゲーム全体に提供する

const FirebaseQuizCacheScript := preload("res://scripts/core/firebase_quiz_cache.gd")

var provider: QuizProvider
var game_state: QuizGameState
var firebase_quiz_cache: Node
var firebase_ratings: FirebaseRatings
var quiz_optimizer: QuizOptimizer
var quiz_validator: QuizValidator
var player_analytics: PlayerAnalytics

func _ready() -> void:
	# Load the last known Firebase snapshot immediately, then sync in the
	# background. BufferedQuizProvider can consume the cached items synchronously.
	firebase_quiz_cache = FirebaseQuizCacheScript.new()
	add_child(firebase_quiz_cache)

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
	print("[QuizManager] Started with BufferedQuizProvider, FirebaseQuizCache, FirebaseRatings, QuizOptimizer, QuizValidator, and PlayerAnalytics.")

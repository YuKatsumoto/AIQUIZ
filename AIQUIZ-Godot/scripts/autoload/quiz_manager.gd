extends Node

## クイズデータ管理 (Autoload)
## QuizProvider のインスタンスを保持し、ゲーム全体に提供する

const FirebaseQuizCacheScript := preload("res://scripts/core/firebase_quiz_cache.gd")

## シークレット（かくし要素）を今回はじめて解放した。id は UnlockStore の ID。
signal secret_unlocked(id: StringName)

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
	# 保存済みの見た目（体の塗りと帽子）を反映する。
	PlayerSkinStore.load_into(game_state)
	game_state.correct_answer.connect(_check_secret_unlocks)
	print("[QuizManager] Started with BufferedQuizProvider, FirebaseQuizCache, FirebaseRatings, QuizOptimizer, QuizValidator, and PlayerAnalytics.")


## 正解のたびに、シークレットの解放条件に届いたかを調べる。
## 数えるのは自分のPCで遊んだ本番の試合だけ（リプレイ・オンライン対戦は数えない）。
func _check_secret_unlocks() -> void:
	var gs := game_state
	if gs == null or gs.is_replay or gs.net_online:
		return
	var best := gs.score
	if gs.num_players >= 2:
		best = maxi(best, gs.player2_score)
	for id: StringName in UnlockStore.report_endless_progress(gs.mode, gs.difficulty, best):
		secret_unlocked.emit(id)

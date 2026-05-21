extends Node
class_name NetGameState

## ネットワーク同期レイヤー
## ホスト/クライアントの役割に応じて、QuizGameState の更新と
## リレーサーバー経由のスナップショット送受信を管理する。

var game_state: QuizGameState
var is_online: bool = false

# クライアントから受信したリモート入力（ホスト側で使用）
var remote_p2_axis: Vector2 = Vector2.ZERO
var remote_p2_jump: bool = false
var remote_p2_emote: int = 0

# スナップショット送信間隔
const SNAPSHOT_INTERVAL := 0.05  # 20Hz
var _snapshot_timer: float = 0.0


func _ready() -> void:
	# NetworkManagerのシグナルに接続
	if NetworkManager:
		NetworkManager.snapshot_received.connect(_on_snapshot_received)
		NetworkManager.input_received.connect(_on_input_received)
		NetworkManager.quiz_received.connect(_on_quiz_received)
		NetworkManager.event_received.connect(_on_event_received)
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)


func setup(gs: QuizGameState) -> void:
	"""game_worldから呼ばれる初期化"""
	game_state = gs
	is_online = NetworkManager.state == NetworkManager.State.IN_GAME


func process_network(dt: float) -> void:
	"""game_world._process()から呼ばれるネットワーク処理"""
	if not is_online or game_state == null:
		return

	if NetworkManager.is_host:
		_snapshot_timer += dt
		if _snapshot_timer >= SNAPSHOT_INTERVAL:
			_snapshot_timer = 0.0
			_send_snapshot()


# ---------- Host: スナップショット送信 ----------

func _send_snapshot() -> void:
	"""ホスト: ゲーム状態をリレーサーバー経由で両者に送信"""
	var snapshot := game_state.to_snapshot()
	NetworkManager.send_snapshot(snapshot)


# ---------- Host: クイズデータ送信 ----------

func send_quiz_to_client(quiz: QuizItem) -> void:
	"""ホスト: 新しいクイズデータをクライアントに送信"""
	if not is_online or not NetworkManager.is_host:
		return
	var quiz_data := {
		"q": quiz.q,
		"c": Array(quiz.c),
		"a": quiz.a,
		"e": quiz.e,
		"src": quiz.src,
		"est": quiz.estimated_seconds,
	}
	NetworkManager.send_quiz(quiz_data)


# ---------- Host: ゲームイベント送信 ----------

func send_game_event(event_name: String, data: Dictionary = {}) -> void:
	"""ホスト: ゲームイベントをクライアントに送信"""
	if not is_online or not NetworkManager.is_host:
		return
	NetworkManager.send_event(event_name, data)


# ---------- Client: 入力送信 ----------

func send_local_input(axis: Vector2, jump: bool, emote: int) -> void:
	"""クライアント: 自分の入力をホストに送信"""
	if not is_online or NetworkManager.is_host:
		return
	NetworkManager.send_input(axis, jump, emote)


# ---------- Getters for host (remote player input) ----------

func get_remote_axis() -> Vector2:
	return remote_p2_axis


func get_remote_jump() -> bool:
	var j := remote_p2_jump
	remote_p2_jump = false  # 消費
	return j


func get_remote_emote() -> int:
	var e := remote_p2_emote
	remote_p2_emote = 0
	return e


# ---------- Signal handlers ----------

func _on_snapshot_received(data: Dictionary) -> void:
	"""クライアント: ホストからのスナップショットを適用"""
	if game_state and not NetworkManager.is_host:
		game_state.apply_snapshot(data)


func _on_input_received(data: Dictionary) -> void:
	"""ホスト: クライアントからの入力を受信"""
	if NetworkManager.is_host:
		remote_p2_axis = Vector2(
			float(data.get("ax", 0.0)),
			float(data.get("ay", 0.0))
		)
		remote_p2_jump = bool(data.get("j", false))
		remote_p2_emote = int(data.get("e", 0))


func _on_quiz_received(data: Dictionary) -> void:
	"""クライアント: ホストからのクイズデータを受信"""
	if not NetworkManager.is_host and game_state:
		var quiz := QuizItem.create(
			data.get("q", ""),
			PackedStringArray(data.get("c", [])),
			int(data.get("a", 0)),
			data.get("e", ""),
			"ONLINE",
			"",
			PackedStringArray(),
			float(data.get("est", 4.0))
		)
		# クライアントのクイズリストに追加
		game_state.quiz_list.append(quiz)
		game_state.current_quiz = quiz
		game_state.quiz_loaded.emit(quiz)


func _on_event_received(data: Dictionary) -> void:
	"""クライアント: ホストからのゲームイベントを受信"""
	var event_name: String = data.get("event", "")
	match event_name:
		"correct":
			game_state.correct_answer.emit()
		"wrong":
			game_state.wrong_answer.emit(data.get("msg", ""))
		"game_cleared":
			game_state.game_cleared.emit(data.get("msg", ""))
		_:
			pass


func _on_peer_disconnected() -> void:
	"""相手が切断した場合の処理"""
	if game_state:
		game_state.message_text = "相手が切断しました"
		game_state.game_state = Constants.STATE_GAME_OVER
		game_state.state_changed.emit(Constants.STATE_GAME_OVER)

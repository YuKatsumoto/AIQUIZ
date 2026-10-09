extends Control

## オンライン対戦ロビー画面
## ルーム作成/一覧/参加 + 接続状態表示

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var room_code_input: LineEdit = $VBoxContainer/JoinRow/RoomCodeInput
@onready var join_btn: Button = $VBoxContainer/JoinRow/JoinBtn
@onready var create_btn: Button = $VBoxContainer/CreateBtn
@onready var refresh_btn: Button = $VBoxContainer/RefreshBtn
@onready var back_btn: Button = $VBoxContainer/BackBtn
@onready var room_list_container: VBoxContainer = $VBoxContainer/RoomListScroll/RoomListContainer
@onready var waiting_panel: PanelContainer = $WaitingPanel
@onready var waiting_label: Label = $WaitingPanel/VBox/WaitingLabel
@onready var room_code_label: Label = $WaitingPanel/VBox/RoomCodeLabel
@onready var cancel_btn: Button = $WaitingPanel/VBox/CancelBtn

var game_state: QuizGameState


func _ready() -> void:
	game_state = QuizManager.game_state

	# Signals
	create_btn.pressed.connect(_on_create_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.guest_joined.connect(_on_guest_joined)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.room_list_received.connect(_on_room_list_received)
	NetworkManager.game_start_received.connect(_on_game_start_received)

	waiting_panel.visible = false
	status_label.text = "リレーサーバー: %s" % NetworkManager.relay_url

	# 初回ルーム一覧取得
	_on_refresh_pressed()


# ---------- Button handlers ----------

func _on_create_pressed() -> void:
	status_label.text = "ルーム作成中..."
	game_state.num_players = 2
	game_state.select_mode_and_continue(Constants.MODE_TEN)
	NetworkManager.create_room()
	_show_waiting("ルームを作成しました\n相手の参加を待っています...", NetworkManager.room_id)


func _on_join_pressed() -> void:
	var code := room_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "ルームコードを入力してください"
		return
	status_label.text = "接続中..."
	game_state.num_players = 2
	game_state.select_mode_and_continue(Constants.MODE_TEN)
	NetworkManager.join_room(code)
	_show_waiting("ルーム %s に接続中..." % code, code)


func _on_refresh_pressed() -> void:
	status_label.text = "ルーム一覧を取得中..."
	NetworkManager.fetch_room_list()


func _on_back_pressed() -> void:
	NetworkManager.disconnect_from_relay()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_cancel_pressed() -> void:
	NetworkManager.disconnect_from_relay()
	waiting_panel.visible = false
	status_label.text = "接続をキャンセルしました"


# ---------- Network signal handlers ----------

func _on_connection_succeeded(role: String) -> void:
	if role == "host":
		_show_waiting("ルーム作成完了！\n相手の参加を待っています...", NetworkManager.room_id)
	else:
		_show_waiting("接続成功！\nホストの開始を待っています...", NetworkManager.room_id)
		# ゲスト: プレイヤー情報を送信
		NetworkManager.send_player_info(
			"ゲスト",
			game_state.p2_hat,
			Array(game_state.p2_emote_slots),
			game_state.p2_toon_preset,
		)


func _on_connection_failed(reason: String) -> void:
	waiting_panel.visible = false
	status_label.text = "接続失敗: %s" % reason


func _on_guest_joined() -> void:
	# ホスト: 相手が参加 → プレイヤー情報を送信してゲーム開始
	NetworkManager.send_player_info(
		"ホスト",
		game_state.p1_hat,
		Array(game_state.p1_emote_slots),
		game_state.p1_toon_preset,
	)
	waiting_label.text = "相手が参加しました！\nゲームを開始します..."

	# 2秒後にゲーム開始
	await get_tree().create_timer(2.0).timeout
	_start_online_game()


func _on_peer_disconnected() -> void:
	waiting_panel.visible = false
	status_label.text = "相手が切断しました"


func _on_room_list_received(rooms: Array) -> void:
	# ルーム一覧を更新
	for child in room_list_container.get_children():
		child.queue_free()

	if rooms.is_empty():
		status_label.text = "現在利用可能なルームはありません"
		return

	status_label.text = "%d 個のルームが見つかりました" % rooms.size()
	for room_data in rooms:
		var btn := Button.new()
		btn.text = "%s (ルーム: %s)" % [
			room_data.get("host_name", "不明"),
			room_data.get("room_id", "?")
		]
		btn.custom_minimum_size = Vector2(0, 40)
		var rid: String = room_data.get("room_id", "")
		btn.pressed.connect(func(): _join_room(rid))
		room_list_container.add_child(btn)


func _on_game_start_received(data: Dictionary) -> void:
	# ゲスト: ホストからのゲーム開始通知
	if NetworkManager.is_host:
		return
	game_state.subject = str(data.get("subject", game_state.subject))
	game_state.grade = int(data.get("grade", game_state.grade))
	game_state.difficulty = str(data.get("difficulty", game_state.difficulty))
	game_state.mode = str(data.get("mode", game_state.mode))
	game_state.llm_mode = str(data.get("llm_mode", game_state.llm_mode))
	game_state.quiz_list.clear()
	game_state.current_quiz = null
	game_state.game_state = Constants.STATE_PRELOADING
	if game_state.provider is BufferedQuizProvider:
		var buffered_provider := game_state.provider as BufferedQuizProvider
		buffered_provider.current_mode = game_state.mode
		buffered_provider.set_llm_mode(game_state.llm_mode)
	game_state.provider.end_round()
	_transition_to_game()


# ---------- Helpers ----------

func _show_waiting(message: String, code: String) -> void:
	waiting_panel.visible = true
	waiting_label.text = message
	room_code_label.text = "ルームコード: %s" % code


func _join_room(rid: String) -> void:
	room_code_input.text = rid
	_on_join_pressed()


func _start_online_game() -> void:
	# ホスト: ゲーム設定を送信して開始
	game_state.llm_mode = QuizManager.provider.llm_mode
	NetworkManager.send_settings({
		"subject": game_state.subject,
		"grade": game_state.grade,
		"difficulty": game_state.difficulty,
		"mode": game_state.mode,
		"llm_mode": game_state.llm_mode,
	})
	NetworkManager.send_game_start({
		"subject": game_state.subject,
		"grade": game_state.grade,
		"difficulty": game_state.difficulty,
		"mode": game_state.mode,
		"llm_mode": game_state.llm_mode,
	})
	# ホストだけが問題生成を開始し、クライアントは検証済みデータの同期だけを受ける。
	game_state.start_game()
	NetworkManager.state = NetworkManager.State.IN_GAME
	_transition_to_game()


func _transition_to_game() -> void:
	NetworkManager.state = NetworkManager.State.IN_GAME
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")


func _exit_tree() -> void:
	# シグナル切断（シーン切替時のエラー防止）
	if NetworkManager:
		if NetworkManager.connection_succeeded.is_connected(_on_connection_succeeded):
			NetworkManager.connection_succeeded.disconnect(_on_connection_succeeded)
		if NetworkManager.connection_failed.is_connected(_on_connection_failed):
			NetworkManager.connection_failed.disconnect(_on_connection_failed)
		if NetworkManager.guest_joined.is_connected(_on_guest_joined):
			NetworkManager.guest_joined.disconnect(_on_guest_joined)
		if NetworkManager.peer_disconnected.is_connected(_on_peer_disconnected):
			NetworkManager.peer_disconnected.disconnect(_on_peer_disconnected)
		if NetworkManager.room_list_received.is_connected(_on_room_list_received):
			NetworkManager.room_list_received.disconnect(_on_room_list_received)
		if NetworkManager.game_start_received.is_connected(_on_game_start_received):
			NetworkManager.game_start_received.disconnect(_on_game_start_received)

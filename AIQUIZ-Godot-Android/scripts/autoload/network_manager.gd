extends Node

## ネットワーク管理Autoload
## WebSocketリレーサーバーを介したオンライン対戦の接続管理

signal connection_succeeded(role: String)        # "host" or "guest"
signal connection_failed(reason: String)
signal guest_joined                               # ホスト側: 相手が参加
signal peer_disconnected                          # 相手が切断
signal room_list_received(rooms: Array)
signal message_received(msg: Dictionary)
signal player_info_received(info: Dictionary)
signal game_start_received(data: Dictionary)
signal snapshot_received(data: Dictionary)
signal input_received(data: Dictionary)
signal quiz_received(data: Dictionary)
signal event_received(data: Dictionary)

enum State { OFFLINE, CONNECTING, IN_LOBBY, IN_GAME }

var state: State = State.OFFLINE
var is_host: bool = false
var room_id: String = ""
var relay_url: String = ""

var _ws: WebSocketPeer = null
var _poll_timer: float = 0.0
const POLL_INTERVAL := 0.016  # ~60Hz
const PING_INTERVAL := 10.0
var _ping_timer: float = 0.0
var _reconnect_attempts: int = 0
const MAX_RECONNECT := 3

# 相手のプレイヤー情報
var opponent_name: String = ""
var opponent_hat: int = 0
var opponent_emote_slots: Array[int] = [1, 2, 3]


func _ready() -> void:
	relay_url = _get_relay_url()
	if relay_url.is_empty():
		push_warning("[NetworkManager] RELAY_SERVER_URL not set in .env")
	else:
		print("[NetworkManager] Relay URL: %s" % relay_url)


func _get_relay_url() -> String:
	# .env から読み取り（GameManagerが先にロード済み）
	var url := OS.get_environment("RELAY_SERVER_URL")
	if url.is_empty():
		# フォールバック: ローカル開発用
		url = "ws://localhost:8080"
	# https → wss, http → ws 変換
	if url.begins_with("https://"):
		url = "wss://" + url.substr(8)
	elif url.begins_with("http://"):
		url = "ws://" + url.substr(7)
	elif not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://" + url
	return url


# ---------- Public API ----------

func create_room() -> void:
	"""ルームを作成してホストとして待機"""
	room_id = _generate_room_id()
	is_host = true
	_connect_to_relay()


func join_room(target_room_id: String) -> void:
	"""既存ルームにゲストとして参加"""
	room_id = target_room_id
	is_host = false
	_connect_to_relay()


func fetch_room_list() -> void:
	"""利用可能なルーム一覧を取得 (HTTP GET)"""
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 5.0

	var base_url := relay_url.replace("ws://", "http://").replace("wss://", "https://")
	var url := base_url + "/rooms"

	http.request_completed.connect(func(result: int, code: int, _h, body: PackedByteArray):
		var rooms_list: Array = []
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Array:
				rooms_list = json.data
		room_list_received.emit(rooms_list)
		http.queue_free()
	)

	var err := http.request(url)
	if err != OK:
		room_list_received.emit([])
		http.queue_free()


func send_message(msg: Dictionary) -> void:
	"""リレーサーバーにメッセージを送信"""
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func send_input(axis: Vector2, jump: bool, emote: int) -> void:
	"""クライアント→ホスト: 入力データ送信"""
	send_message({
		"type": "input",
		"ax": axis.x,
		"ay": axis.y,
		"j": jump,
		"e": emote,
	})


func send_snapshot(data: Dictionary) -> void:
	"""ホスト→両者: ゲーム状態スナップショット送信"""
	data["type"] = "snapshot"
	send_message(data)


func send_quiz(quiz_data: Dictionary) -> void:
	"""ホスト→両者: クイズデータ送信"""
	send_message({"type": "quiz", "data": quiz_data})


func send_event(event_name: String, data: Dictionary = {}) -> void:
	"""ゲームイベント送信"""
	data["type"] = "event"
	data["event"] = event_name
	send_message(data)


func send_player_info(player_name: String, hat: int, emote_slots: Array[int]) -> void:
	"""プレイヤー情報を相手に送信"""
	send_message({
		"type": "player_info",
		"name": player_name,
		"hat": hat,
		"emote_slots": emote_slots,
	})


func send_game_start(settings: Dictionary) -> void:
	"""ホスト: ゲーム開始を通知"""
	send_message({"type": "start", "data": settings})


func send_settings(settings: Dictionary) -> void:
	"""ホスト: ゲーム設定を共有"""
	send_message({"type": "settings", "data": settings})


func disconnect_from_relay() -> void:
	"""リレーサーバーから切断"""
	if _ws:
		_ws.close()
		_ws = null
	state = State.OFFLINE
	room_id = ""
	is_host = false
	_reconnect_attempts = 0
	opponent_name = ""
	opponent_hat = 0
	opponent_emote_slots = [1, 2, 3]


# ---------- Internal ----------

func _generate_room_id() -> String:
	# 4文字の覚えやすいルームコード
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in range(4):
		code += chars[randi() % chars.length()]
	return code


func _connect_to_relay() -> void:
	state = State.CONNECTING
	_ws = WebSocketPeer.new()
	var url := "%s/ws/%s" % [relay_url, room_id]
	print("[NetworkManager] Connecting to: %s" % url)
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_error("[NetworkManager] Failed to initiate connection: %d" % err)
		state = State.OFFLINE
		connection_failed.emit("接続を開始できませんでした")


func _process(dt: float) -> void:
	if _ws == null:
		return

	_ws.poll()

	var ws_state := _ws.get_ready_state()

	if ws_state == WebSocketPeer.STATE_OPEN:
		if state == State.CONNECTING:
			# 接続成功を待つ（サーバーからのroom_created/room_joinedメッセージで確定）
			pass

		# メッセージ受信
		while _ws.get_available_packet_count() > 0:
			var raw := _ws.get_packet().get_string_from_utf8()
			_handle_message(raw)

		# Ping
		_ping_timer += dt
		if _ping_timer >= PING_INTERVAL:
			_ping_timer = 0.0
			send_message({"type": "ping", "ts": Time.get_ticks_msec()})

	elif ws_state == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		print("[NetworkManager] Connection closed: code=%d" % code)
		_ws = null

		if state == State.CONNECTING:
			connection_failed.emit("サーバーに接続できませんでした")
			state = State.OFFLINE
		elif state in [State.IN_LOBBY, State.IN_GAME]:
			peer_disconnected.emit()
			state = State.OFFLINE


func _handle_message(raw: String) -> void:
	var json := JSON.new()
	if json.parse(raw) != OK:
		return
	var msg: Dictionary = json.data
	if not msg is Dictionary:
		return

	var msg_type: String = msg.get("type", "")

	match msg_type:
		"room_created":
			state = State.IN_LOBBY
			room_id = msg.get("room_id", room_id)
			is_host = true
			print("[NetworkManager] Room created: %s (host)" % room_id)
			connection_succeeded.emit("host")

		"room_joined":
			state = State.IN_LOBBY
			room_id = msg.get("room_id", room_id)
			is_host = false
			print("[NetworkManager] Joined room: %s (guest)" % room_id)
			connection_succeeded.emit("guest")

		"guest_joined":
			print("[NetworkManager] Guest joined the room")
			guest_joined.emit()

		"peer_disconnected":
			print("[NetworkManager] Peer disconnected")
			peer_disconnected.emit()
			if state == State.IN_GAME:
				state = State.OFFLINE

		"error":
			var error_msg: String = msg.get("msg", "Unknown error")
			print("[NetworkManager] Error: %s" % error_msg)
			connection_failed.emit(error_msg)

		"player_info":
			opponent_name = msg.get("name", "")
			opponent_hat = int(msg.get("hat", 0))
			var slots = msg.get("emote_slots", [1, 2, 3])
			opponent_emote_slots.clear()
			for s in slots:
				opponent_emote_slots.append(int(s))
			player_info_received.emit(msg)

		"start":
			state = State.IN_GAME
			game_start_received.emit(msg.get("data", {}))

		"settings":
			message_received.emit(msg)

		"snapshot":
			snapshot_received.emit(msg)

		"input":
			input_received.emit(msg)

		"quiz":
			quiz_received.emit(msg.get("data", {}))

		"event":
			event_received.emit(msg)

		"pong":
			var sent_ts: int = int(msg.get("ts", 0))
			var rtt: int = Time.get_ticks_msec() - sent_ts
			# RTTログ（デバッグ用）
			if rtt > 200:
				print("[NetworkManager] High RTT: %dms" % rtt)

		_:
			message_received.emit(msg)

extends Node

const ToonPresets = preload("res://scripts/cosmetics/character_toon_presets.gd")

## ネットワーク管理Autoload（リレープロトコル v2）
## マッチング（ランダム／ともだちコード）、試合中メッセージの送受信、
## 切断時の自動再接続（リレーの猶予時間内）を受け持つ。
## フレームは {"t": 種類, "d": 中身} の JSON テキスト。

const PROTO_VERSION := 2
const BUILD := "godot-2"

signal state_changed(state: State)
signal connection_failed(reason: String)
signal queued
signal queue_timeout
signal friend_code_received(code: String)
signal matched(info: Dictionary)
signal resumed(info: Dictionary)
signal reconnect_failed(reason: String)
signal peer_paused(who: String, grace_s: float)
signal peer_resumed(who: String)
signal peer_left(who: String)
signal forfeit_received(winner_role: String, reason: String)
signal server_restarting
signal error_received(code: String)
signal profile_received(profile: Dictionary)
## 試合中にリレーされたメッセージ（settings / start / snap / quiz / evt / resync / finish / cmd / ready / req_resync）
signal relay_message(msg_type: String, data: Dictionary)

enum State { OFFLINE, CONNECTING, IDLE, QUEUED, IN_LOBBY, IN_GAME, RECONNECTING }

var state: State = State.OFFLINE
var is_host: bool = false
var relay_url: String = ""

# 試合情報（matched / resumed で確定）
var match_id: String = ""
var match_settings: Dictionary = {}
var my_profile: Dictionary = {}
## リレーが検査したあとの自分のプロフィール（なまえが弾かれたら name が空になる）。
var match_you: Dictionary = {}
var opponent_profile: Dictionary = {}
var friend_code: String = ""
var opponent_present: bool = false

# 回線品質
var rtt_ms: float = -1.0
var server_clock_offset_ms: float = 0.0
var bytes_sent: int = 0
var bytes_received: int = 0

# 相手のプレイヤー情報（旧コード互換。profile から導出）
var opponent_name: String = ""
var opponent_hat: int = 0
var opponent_toon_preset: int = ToonPresets.STANDARD
## 相手の体の塗り（PlayerSkin のコンパクト表記。"" は相手スロットの標準色）。
var opponent_skin_code: String = ""
var opponent_emote_slots: Array[int] = [1, 2, 3]

## RELAY_SERVER_URL（環境変数 / .env）が無いときの接続先＝本番リレー（Cloud Run）。
## ローカルのリレーで試すときは .env に RELAY_SERVER_URL=ws://localhost:8080 を書く。
const DEFAULT_RELAY_URL := "wss://aiquiz-relay-pktyslvfzq-an.a.run.app"

const PING_INTERVAL := 1.0
## これだけ何も届かなければ回線が死んだとみなす（Cloud Run は切断を通知しないことがある）
const SILENCE_TIMEOUT := 5.0
const RECONNECT_BACKOFF: Array[float] = [0.5, 1.0, 2.0, 4.0]

var _ws: WebSocketPeer = null
var _greeted := false
var _hello_sent := false
var _pending: Dictionary = {}  # 接続完了後に送る最初の要求 {t, d}
var _token: String = ""
var _ping_timer := 0.0
var _silence := 0.0
var _resume_state: State = State.IN_GAME
var _reconnect_deadline_ms := 0
var _reconnect_attempt := 0
var _reconnect_wait := 0.0
var _grace_s := 30.0


func _ready() -> void:
	# ポーズ中も通信と生存確認を止めない（止めるとリレーに切断扱いされる）。
	process_mode = Node.PROCESS_MODE_ALWAYS
	relay_url = _get_relay_url()
	print("[NetworkManager] Relay URL: %s" % relay_url)


func _get_relay_url() -> String:
	var url := OS.get_environment("RELAY_SERVER_URL")
	if url.is_empty():
		url = DEFAULT_RELAY_URL
	if url.begins_with("https://"):
		url = "wss://" + url.substr(8)
	elif url.begins_with("http://"):
		url = "ws://" + url.substr(7)
	elif not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://" + url
	return url.trim_suffix("/")


# ---------- Public API ----------

func is_in_match() -> bool:
	return state in [State.IN_LOBBY, State.IN_GAME, State.RECONNECTING]


func is_online_game() -> bool:
	return state in [State.IN_GAME, State.RECONNECTING]


func role() -> String:
	return "host" if is_host else "guest"


## ランダムマッチの待ち行列に入る。settings: subject / grade / difficulty(0-2) / mode
func find_match(settings: Dictionary, profile: Dictionary) -> void:
	_request({"t": "queue", "d": settings}, profile)


func create_friend_room(settings: Dictionary, profile: Dictionary) -> void:
	_request({"t": "friend_create", "d": settings}, profile)


func join_friend_room(code: String, profile: Dictionary) -> void:
	_request({"t": "friend_join", "d": {"code": code.strip_edges().to_upper()}}, profile)


func cancel_search() -> void:
	send("cancel")
	friend_code = ""
	if state in [State.QUEUED, State.CONNECTING]:
		_set_state(State.IDLE if _greeted else State.OFFLINE)


## 試合を自分から抜ける（相手は不戦勝になる）。
func leave_match() -> void:
	if is_in_match():
		send("leave")
	disconnect_from_relay()


func disconnect_from_relay() -> void:
	if _ws:
		_ws.close()
		_ws = null
	_greeted = false
	_pending = {}
	_token = ""
	match_id = ""
	match_settings = {}
	match_you = {}
	friend_code = ""
	opponent_present = false
	is_host = false
	rtt_ms = -1.0
	_set_opponent_profile({})
	_set_state(State.OFFLINE)


## デバッグ用：通信なしで「相手が見つかった」状態にする（マッチング演出の確認。OnlineMenu の L キー）。
## 接続・待ち行列は閉じ、ホスト扱いで相手のプロフィールと試合設定だけを入れる。
func debug_fake_match(profile: Dictionary, settings: Dictionary) -> void:
	disconnect_from_relay()
	is_host = true
	match_settings = settings
	opponent_present = true
	_set_opponent_profile(profile)
	_set_state(State.IN_LOBBY)


## 試合中は IN_GAME に進める（ロビーからゲーム画面へ移るとき）。
func enter_game() -> void:
	if state == State.IN_LOBBY:
		_set_state(State.IN_GAME)


func send(msg_type: String, data: Dictionary = {}) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _greeted and msg_type != "hello":
		return
	var text := JSON.stringify({"t": msg_type, "d": data})
	bytes_sent += text.length()
	_ws.send_text(text)


func send_profile(profile: Dictionary) -> void:
	my_profile = profile
	send("profile", profile)


## サーバー時計の推定（ミリ秒）。早押しの公平判定などに使う。
func server_time_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + server_clock_offset_ms


# ---------- Connection ----------

func _request(first: Dictionary, profile: Dictionary) -> void:
	my_profile = profile
	friend_code = ""
	if _greeted and _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send(first.t, first.d)
		return
	_pending = first
	_open_socket(State.CONNECTING)


func _open_socket(next_state: State) -> void:
	if _ws:
		_ws.close()
	_greeted = false
	_hello_sent = false
	_silence = 0.0
	_ping_timer = 0.0
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	_set_state(next_state)
	var url := relay_url + "/ws"
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_warning("[NetworkManager] connect_to_url failed: %d" % err)
		_on_socket_closed()


func _send_hello() -> void:
	var hello := {"proto": PROTO_VERSION, "build": BUILD, "profile": my_profile}
	if state == State.RECONNECTING and not _token.is_empty():
		hello["resume"] = {"match_id": match_id, "token": _token}
	var text := JSON.stringify({"t": "hello", "d": hello})
	_ws.send_text(text)


func _process(dt: float) -> void:
	if state == State.RECONNECTING and _ws == null:
		_tick_reconnect(dt)
		return
	if _ws == null:
		return
	_ws.poll()
	var ws_state := _ws.get_ready_state()
	if ws_state == WebSocketPeer.STATE_OPEN:
		if not _hello_sent:
			_hello_sent = true
			_send_hello()
		while _ws != null and _ws.get_available_packet_count() > 0:
			var raw := _ws.get_packet().get_string_from_utf8()
			bytes_received += raw.length()
			_silence = 0.0
			_handle_message(raw)
		if _ws == null:
			return
		_silence += dt
		if _silence > SILENCE_TIMEOUT:
			print("[NetworkManager] Relay silent for %.1fs, dropping link" % _silence)
			_ws.close()
			_ws = null
			_on_socket_closed()
			return
		if _greeted:
			_ping_timer += dt
			if _ping_timer >= PING_INTERVAL:
				_ping_timer = 0.0
				send("ping", {"ts": Time.get_ticks_msec()})
	elif ws_state == WebSocketPeer.STATE_CLOSED:
		print("[NetworkManager] Connection closed: code=%d" % _ws.get_close_code())
		_ws = null
		_on_socket_closed()


func _on_socket_closed() -> void:
	_ws = null
	_greeted = false
	if is_in_match() and not _token.is_empty():
		_begin_reconnect()
		return
	var was := state
	_set_state(State.OFFLINE)
	if was in [State.CONNECTING, State.QUEUED, State.IDLE]:
		connection_failed.emit("サーバーにつながりませんでした")


func _begin_reconnect() -> void:
	if state != State.RECONNECTING:
		_resume_state = state
		_reconnect_deadline_ms = Time.get_ticks_msec() + int(_grace_s * 1000.0)
		_reconnect_attempt = 0
		_set_state(State.RECONNECTING)
	_reconnect_wait = RECONNECT_BACKOFF[mini(_reconnect_attempt, RECONNECT_BACKOFF.size() - 1)]
	_reconnect_attempt += 1


func _tick_reconnect(dt: float) -> void:
	if Time.get_ticks_msec() > _reconnect_deadline_ms:
		_fail_reconnect("つながりなおせませんでした")
		return
	_reconnect_wait -= dt
	if _reconnect_wait <= 0.0:
		print("[NetworkManager] Reconnect attempt %d" % _reconnect_attempt)
		_open_socket(State.RECONNECTING)


func _fail_reconnect(reason: String) -> void:
	disconnect_from_relay()
	reconnect_failed.emit(reason)


func reconnect_seconds_left() -> float:
	if state != State.RECONNECTING:
		return 0.0
	return maxf(0.0, float(_reconnect_deadline_ms - Time.get_ticks_msec()) / 1000.0)


# ---------- Messages ----------

func _handle_message(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return
	var msg := parsed as Dictionary
	var msg_type := str(msg.get("t", ""))
	var data: Dictionary = msg.get("d", {}) if msg.get("d", {}) is Dictionary else {}

	match msg_type:
		"welcome":
			_greeted = true
			if state == State.CONNECTING:
				_set_state(State.IDLE)
			if not _pending.is_empty():
				send(_pending.t, _pending.d)
				_pending = {}
		"update_required":
			_pending = {}
			disconnect_from_relay()
			connection_failed.emit("ゲームを最新版にアップデートしてください")
		"queued":
			_set_state(State.QUEUED)
			queued.emit()
		"queue_timeout":
			_set_state(State.IDLE)
			queue_timeout.emit()
		"cancelled":
			pass
		"friend_code":
			friend_code = str(data.get("code", ""))
			_set_state(State.QUEUED)
			friend_code_received.emit(friend_code)
		"matched":
			_apply_match_info(data)
			_set_state(State.IN_LOBBY)
			matched.emit(data)
		"resumed":
			_apply_match_info(data)
			_set_state(_resume_state)
			print("[NetworkManager] Resumed match %s as %s" % [match_id, role()])
			resumed.emit(data)
		"resume_failed":
			_fail_reconnect("試合が終わっていました")
		"peer_paused":
			opponent_present = false
			peer_paused.emit(str(data.get("who", "")), float(data.get("grace_s", 30.0)))
		"peer_resumed":
			opponent_present = true
			peer_resumed.emit(str(data.get("who", "")))
		"peer_left":
			opponent_present = false
			peer_left.emit(str(data.get("who", "")))
		"forfeit":
			opponent_present = false
			forfeit_received.emit(str(data.get("winner", "")), str(data.get("reason", "")))
		"profile":
			_set_opponent_profile(data)
			profile_received.emit(data)
		"server_restart":
			server_restarting.emit()
		"error":
			var code := str(data.get("code", "error"))
			print("[NetworkManager] Relay error: %s" % code)
			error_received.emit(code)
		"pong":
			_on_pong(data)
		_:
			relay_message.emit(msg_type, data)


func _apply_match_info(data: Dictionary) -> void:
	match_id = str(data.get("match_id", ""))
	_token = str(data.get("token", _token))
	is_host = str(data.get("role", "")) == "host"
	match_settings = data.get("settings", {}) if data.get("settings", {}) is Dictionary else {}
	opponent_present = bool(data.get("peer_present", true))
	_grace_s = float(data.get("grace_s", 30.0))
	friend_code = ""
	_set_opponent_profile(data.get("opponent", {}) if data.get("opponent", {}) is Dictionary else {})
	match_you = data.get("you", {}) if data.get("you", {}) is Dictionary else {}


func _set_opponent_profile(profile: Dictionary) -> void:
	opponent_profile = profile
	# 相手が決めた名前（リレーの検査を通ったもの）。無ければプリセットのニックネーム。
	opponent_name = str(profile.get("name", ""))
	if opponent_name.is_empty() and not profile.is_empty():
		opponent_name = NetNicknames.name_for(int(profile.get("nick", 0)))
	opponent_hat = int(profile.get("hat", 0))
	opponent_toon_preset = ToonPresets.normalize(int(profile.get("toon", ToonPresets.STANDARD)))
	var skin_code: Variant = profile.get("skin", "")
	opponent_skin_code = skin_code if skin_code is String and not PlayerSkin.from_code(skin_code).is_empty() else ""
	opponent_emote_slots.clear()
	for slot in profile.get("emotes", [1, 2, 3]):
		opponent_emote_slots.append(int(slot))


func _on_pong(data: Dictionary) -> void:
	var sent := int(data.get("ts", 0))
	var sample := float(Time.get_ticks_msec() - sent)
	if sample < 0.0 or sample > 10000.0:
		return
	rtt_ms = sample if rtt_ms < 0.0 else lerpf(rtt_ms, sample, 0.2)
	var server_ms := float(data.get("server_ms", 0))
	if server_ms > 0.0:
		var local_at_server := Time.get_unix_time_from_system() * 1000.0 - sample * 0.5
		var offset := server_ms - local_at_server
		server_clock_offset_ms = offset if is_zero_approx(server_clock_offset_ms) else lerpf(server_clock_offset_ms, offset, 0.1)


func _set_state(next: State) -> void:
	if state == next:
		return
	state = next
	state_changed.emit(next)

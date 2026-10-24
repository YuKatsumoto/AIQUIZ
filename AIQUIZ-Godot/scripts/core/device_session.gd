extends Node


## 端末ごとの許可証（aiquiz-proxy の device-auth.js と対になる）。
## 初回起動時にランダムな端末 ID を作って保存し、プロキシの /session で許可証をもらう。
##   1. GET  /session/challenge → {challenge, bits}
##   2. sha256("challenge:iid:counter") の先頭 bits ビットが 0 になる counter を探す（計算の課題）
##   3. POST /session {iid, challenge, counter} → {token, expires_at}
## 許可証は 30 日有効。残りが RENEW_BEFORE_SEC を切ったら作り直す。
## 端末 ID は個人を特定しないランダムな値で、利用の上限管理にだけ使う。

const SAVE_PATH := "user://device_session.json"
const RENEW_BEFORE_SEC := 3 * 24 * 3600
const RETRY_SEC := 60.0
## 計算の課題で 1 フレームに使う時間（ミリ秒）。ゲームの動きを止めないため分けて進める
const SOLVE_SLICE_MS := 6
const MAX_COUNTER := 200_000_000

var iid: String = ""
var token: String = ""
var expires_at: int = 0
## プロキシが許可証を使っていない（手元の開発など）
var tokens_disabled: bool = false
var _fetching: bool = false


func _ready() -> void:
	_load()
	if iid.is_empty():
		iid = Crypto.new().generate_random_bytes(16).hex_encode()
		_save()
	ensure_token()


func has_valid_token() -> bool:
	return not token.is_empty() and expires_at > int(Time.get_unix_time_from_system())


## 許可証を取りに行っている最中で、まだ使える許可証が無い
func is_waiting_for_token() -> bool:
	return _fetching and not has_valid_token()


## 許可証が無いか期限が近ければ取り直す（重ねて呼んでも 1 回だけ動く）
func ensure_token() -> void:
	if _fetching or tokens_disabled:
		return
	var now := int(Time.get_unix_time_from_system())
	if not token.is_empty() and expires_at - now > RENEW_BEFORE_SEC:
		return
	var base := ApiStatusAutoload.get_proxy_url().trim_suffix("/")
	if base.is_empty():
		return
	_fetching = true
	var ok := await _fetch_token(base)
	_fetching = false
	if not ok and not tokens_disabled and is_inside_tree():
		get_tree().create_timer(RETRY_SEC).timeout.connect(ensure_token)


## プロキシが許可証を受け付けなかった（期限切れ・鍵の変更など）。捨てて取り直す。
func reject_token() -> void:
	if token.is_empty():
		return
	print("[DeviceSession] Proxy rejected the device token; requesting a new one")
	token = ""
	expires_at = 0
	_save()
	ensure_token()


func _fetch_token(base: String) -> bool:
	var app_headers := ApiStatusAutoload.get_app_headers()
	var challenge_res := await _request(base + "/session/challenge", app_headers, HTTPClient.METHOD_GET, "")
	if int(challenge_res["code"]) == 503 and str(challenge_res["data"].get("error", "")) == "device_tokens_disabled":
		tokens_disabled = true
		print("[DeviceSession] Proxy has device tokens disabled")
		return false
	if int(challenge_res["code"]) != 200:
		print("[DeviceSession] Challenge request failed (code=%d)" % int(challenge_res["code"]))
		return false
	var challenge := str(challenge_res["data"].get("challenge", ""))
	var bits := int(challenge_res["data"].get("bits", 0))
	if challenge.is_empty() or bits < 0 or bits > 32:
		return false
	var started := Time.get_ticks_msec()
	var counter := await _solve(challenge, bits)
	if counter < 0:
		return false
	print("[DeviceSession] Solved the session challenge (%d bits) in %.2fs" % [
		bits, float(Time.get_ticks_msec() - started) / 1000.0])
	var body := JSON.stringify({"iid": iid, "challenge": challenge, "counter": str(counter)})
	var session_res := await _request(base + "/session", app_headers, HTTPClient.METHOD_POST, body)
	if int(session_res["code"]) != 200:
		print("[DeviceSession] Session request failed (code=%d %s)" % [
			int(session_res["code"]), str(session_res["data"].get("error", ""))])
		return false
	token = str(session_res["data"].get("token", ""))
	expires_at = int(session_res["data"].get("expires_at", 0))
	_save()
	return has_valid_token()


## sha256("challenge:iid:counter") の先頭 bits ビットが 0 になる counter を探す
func _solve(challenge: String, bits: int) -> int:
	var prefix := "%s:%s:" % [challenge, iid]
	var counter := 0
	while counter < MAX_COUNTER:
		var slice_end := Time.get_ticks_msec() + SOLVE_SLICE_MS
		while Time.get_ticks_msec() < slice_end:
			for _i in range(256):
				if _leading_zero_bits((prefix + str(counter)).sha256_buffer()) >= bits:
					return counter
				counter += 1
		if not is_inside_tree():
			return -1
		await get_tree().process_frame
	return -1


static func _leading_zero_bits(digest: PackedByteArray) -> int:
	var total := 0
	for byte in digest:
		if byte == 0:
			total += 8
			continue
		var mask := 0x80
		while mask > 0 and (byte & mask) == 0:
			total += 1
			mask >>= 1
		return total
	return total


func _request(url: String, headers: PackedStringArray, method: int, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"code": 0, "data": {}}
	var result: Array = await http.request_completed
	http.queue_free()
	var data: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return {"code": int(result[1]), "data": data if data is Dictionary else {}}


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		return
	var saved_iid := str(data.get("iid", ""))
	if saved_iid.length() == 32 and saved_iid.is_valid_hex_number():
		iid = saved_iid
		token = str(data.get("token", ""))
		expires_at = int(data.get("expires_at", 0))


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[DeviceSession] Could not save %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({"iid": iid, "token": token, "expires_at": expires_at}))
	file.close()

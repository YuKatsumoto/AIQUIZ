extends Node
class_name FirebaseQuizCache

## Firebase shared quiz bank client.
##
## Network access always goes through the authenticated Cloud Run proxy. A fully
## downloaded snapshot is persisted under user:// and remains available when the
## next launch has no network connection. Candidate/evaluation writes use a
## durable, content-keyed outbox so gameplay never waits for Firebase.

signal cache_updated(total_count: int)

const CACHE_VERSION: int = 1
const CACHE_PATH: String = "user://firebase_quiz_cache_v1.json"
const CACHE_TEMP_PATH: String = "user://firebase_quiz_cache_v1.tmp"
const CACHE_BACKUP_PATH: String = "user://firebase_quiz_cache_v1.bak"
const OUTBOX_PATH: String = "user://firebase_quiz_outbox_v1.json"
const OUTBOX_TEMP_PATH: String = "user://firebase_quiz_outbox_v1.tmp"
const OUTBOX_BACKUP_PATH: String = "user://firebase_quiz_outbox_v1.bak"
const PAGE_SIZE: int = 500
const MAX_SYNC_PAGES: int = 100
const MAX_CANDIDATE_BATCH: int = 50
const MAX_EVALUATION_BATCH: int = 25
const INITIAL_RETRY_SECONDS: float = 5.0
const MAX_RETRY_SECONDS: float = 300.0

var _cache_items: Array[Dictionary] = []
var _cache_revision: int = 0
var _candidate_outbox: Dictionary = {}
var _evaluation_outbox: Dictionary = {}
var _syncing: bool = false
var _flushing: bool = false
var _retry_seconds: float = INITIAL_RETRY_SECONDS
var _retry_timer: Timer


func _ready() -> void:
	_load_cache()
	_load_outbox()
	_retry_timer = Timer.new()
	_retry_timer.name = "QuizBankRetryTimer"
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_on_retry_timeout)
	add_child(_retry_timer)
	call_deferred("_start_background_work")


func _start_background_work() -> void:
	sync_now()
	flush_outbox()


func get_all_items() -> Array[Dictionary]:
	return _cache_items.duplicate(true)


func get_cached_count() -> int:
	return _cache_items.size()


func get_cache_revision() -> int:
	return _cache_revision


func queue_candidates(quizzes: Array[QuizItem], subject: String, grade: int,
		difficulty: String) -> void:
	var changed := false
	for quiz: QuizItem in quizzes:
		if quiz == null or not _is_online_source(quiz.src):
			continue
		var payload := _quiz_payload(quiz, subject, grade, difficulty)
		if not _is_valid_payload(payload):
			continue
		_candidate_outbox[_local_question_key(payload)] = payload
		changed = true
	if changed:
		_save_outbox()
		flush_outbox()


func queue_evaluation(quiz: QuizItem, good: bool, subject: String, grade: int,
		difficulty: String, reason: String = "") -> void:
	if quiz == null:
		return
	var payload := _quiz_payload(quiz, subject, grade, difficulty)
	if not _is_valid_payload(payload):
		return
	payload["good"] = good
	payload["reason"] = reason.left(500)
	var event_seed := "%s\u0000%s\u0000%d" % [
		_local_question_key(payload), str(good), int(Time.get_unix_time_from_system())
	]
	var event_id := _sha256_hex(event_seed)
	payload["event_id"] = event_id
	_evaluation_outbox[event_id] = payload
	_save_outbox()
	flush_outbox()


func sync_now() -> void:
	if _syncing or ApiStatusAutoload.get_proxy_url().is_empty():
		return
	_syncing = true
	var snapshot: Dictionary = await _download_snapshot()
	_syncing = false
	if not snapshot.get("ok", false):
		_schedule_retry()
		return

	var items: Array[Dictionary] = []
	for raw: Variant in snapshot.get("items", []):
		if raw is Dictionary and _is_valid_cache_item(raw):
			var item: Dictionary = (raw as Dictionary).duplicate(true)
			item["src"] = "OFFLINE_FIREBASE"
			items.append(item)

	var revision := int(snapshot.get("revision", 0))
	if not _replace_cache_atomically(items, revision):
		push_warning("[FirebaseQuizCache] Snapshot was valid but could not be persisted")
		_schedule_retry()
		return

	_cache_items = items
	_cache_revision = revision
	_retry_seconds = INITIAL_RETRY_SECONDS
	print("[FirebaseQuizCache] Synced %d reusable quizzes (revision=%d)" % [
		_cache_items.size(), _cache_revision
	])
	cache_updated.emit(_cache_items.size())


func flush_outbox() -> void:
	if _flushing or ApiStatusAutoload.get_proxy_url().is_empty():
		return
	if _candidate_outbox.is_empty() and _evaluation_outbox.is_empty():
		return
	_flushing = true
	var all_ok := true

	while not _candidate_outbox.is_empty():
		var keys: Array = _candidate_outbox.keys().slice(0, MAX_CANDIDATE_BATCH)
		var items: Array = []
		for key: Variant in keys:
			items.append(_candidate_outbox[key])
		var response: Dictionary = await _request_json(
			HTTPClient.METHOD_POST,
			ApiStatusAutoload.get_proxy_url().trim_suffix("/") + "/quiz-bank/candidates",
			{"items": items}
		)
		if not response.get("ok", false):
			all_ok = false
			break
		for key: Variant in keys:
			_candidate_outbox.erase(key)
		_save_outbox()

	if all_ok:
		while not _evaluation_outbox.is_empty():
			var keys: Array = _evaluation_outbox.keys().slice(0, MAX_EVALUATION_BATCH)
			var evaluations: Array = []
			for key: Variant in keys:
				evaluations.append(_evaluation_outbox[key])
			var response: Dictionary = await _request_json(
				HTTPClient.METHOD_POST,
				ApiStatusAutoload.get_proxy_url().trim_suffix("/") + "/quiz-bank/evaluations",
				{"evaluations": evaluations}
			)
			if not response.get("ok", false):
				all_ok = false
				break
			for key: Variant in keys:
				_evaluation_outbox.erase(key)
			_save_outbox()

	_flushing = false
	if all_ok:
		_retry_seconds = INITIAL_RETRY_SECONDS
		# A successful evaluation can change the shared reusable set. Refresh without
		# blocking the caller so this device sees the newly approved item as well.
		if not _evaluation_outbox.is_empty():
			_schedule_retry()
		elif not _syncing:
			sync_now()
	else:
		_schedule_retry()


func _download_snapshot() -> Dictionary:
	for _attempt: int in range(2):
		var collected: Array[Dictionary] = []
		var cursor := ""
		var revision := 0
		var restart := false
		for _page: int in range(MAX_SYNC_PAGES):
			var url := ApiStatusAutoload.get_proxy_url().trim_suffix("/") \
				+ "/quiz-bank/snapshot?limit=%d" % PAGE_SIZE
			if not cursor.is_empty():
				url += "&cursor=" + cursor.uri_encode()
			if revision > 0:
				url += "&revision=%d" % revision
			var response: Dictionary = await _request_json(HTTPClient.METHOD_GET, url, {})
			if int(response.get("code", 0)) == 409:
				restart = true
				break
			if not response.get("ok", false):
				return {"ok": false}
			var data: Variant = response.get("data")
			if not data is Dictionary or int(data.get("version", 0)) != CACHE_VERSION:
				return {"ok": false}
			var page_revision := int(data.get("revision", 0))
			if revision == 0:
				revision = page_revision
			elif revision != page_revision:
				restart = true
				break
			var raw_items: Variant = data.get("items", [])
			if not raw_items is Array:
				return {"ok": false}
			for raw: Variant in raw_items:
				if not raw is Dictionary or not _is_valid_cache_item(raw):
					return {"ok": false}
				collected.append((raw as Dictionary).duplicate(true))
			cursor = str(data.get("next_cursor", ""))
			if cursor.is_empty():
				return {"ok": true, "revision": revision, "items": collected}
		if not restart:
			push_warning("[FirebaseQuizCache] Snapshot exceeded %d pages" % MAX_SYNC_PAGES)
			return {"ok": false}
	return {"ok": false}


func _request_json(method: int, url: String, payload: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var body := "" if method == HTTPClient.METHOD_GET else JSON.stringify(payload)
	var err := http.request(url, ApiStatusAutoload.get_proxy_headers(), method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0}
	var completed: Array = await http.request_completed
	http.queue_free()
	var result := int(completed[0])
	var response_code := int(completed[1])
	var response_body: PackedByteArray = completed[3]
	var data: Variant = null
	if not response_body.is_empty():
		data = JSON.parse_string(response_body.get_string_from_utf8())
	return {
		"ok": result == HTTPRequest.RESULT_SUCCESS \
			and response_code >= 200 and response_code < 300 \
			and data is Dictionary,
		"code": response_code,
		"data": data,
	}


func _quiz_payload(quiz: QuizItem, subject: String, grade: int,
		difficulty: String) -> Dictionary:
	return {
		"q": quiz.q,
		"c": Array(quiz.c),
		"a": quiz.a,
		"e": quiz.e.left(600),
		"subject": subject,
		"grade": grade,
		"difficulty": difficulty,
		"src": quiz.src,
		"genre": quiz.genre.left(80),
		"estimated_seconds": quiz.estimated_seconds,
	}


func _is_valid_payload(item: Dictionary) -> bool:
	if not _is_valid_cache_item(item):
		return false
	return not str(item.get("src", "")).strip_edges().is_empty()


func _is_valid_cache_item(item: Dictionary) -> bool:
	var q := str(item.get("q", "")).strip_edges()
	var choices: Variant = item.get("c", [])
	var answer := int(item.get("a", -1))
	var subject := str(item.get("subject", ""))
	var grade := int(item.get("grade", 0))
	var difficulty := str(item.get("difficulty", ""))
	if q.is_empty() or q.length() > 60 or q.contains("�"):
		return false
	if not choices is Array or (choices.size() != 2 and choices.size() != 4):
		return false
	if answer < 0 or answer >= choices.size():
		return false
	if subject not in ["国語", "算数", "理科", "社会"] or grade < 1 or grade > 6:
		return false
	if difficulty not in ["簡単", "普通", "難しい"]:
		return false
	var seen: Dictionary = {}
	for choice: Variant in choices:
		var text := str(choice).strip_edges()
		if text.is_empty() or text.length() > 20 or text.contains("�"):
			return false
		var normalized := _normalize_text(text)
		if seen.has(normalized):
			return false
		seen[normalized] = true
	return true


func _is_online_source(source: String) -> bool:
	return source.strip_edges().to_upper() in ["GEMINI", "GEMINI_STREAM", "OPENAI"]


func _local_question_key(payload: Dictionary) -> String:
	return _sha256_hex("%s\u0000%d\u0000%s" % [
		str(payload.get("subject", "")),
		int(payload.get("grade", 0)),
		_normalize_text(str(payload.get("q", ""))),
	])


func _normalize_text(text: String) -> String:
	var normalized := text.strip_edges().to_lower()
	for whitespace: String in [" ", "　", "\t", "\r", "\n"]:
		normalized = normalized.replace(whitespace, "")
	return normalized


func _sha256_hex(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()


func _load_cache() -> void:
	var data := _read_json_dictionary(CACHE_PATH)
	if data.is_empty():
		data = _read_json_dictionary(CACHE_BACKUP_PATH)
	if data.is_empty() or int(data.get("version", 0)) != CACHE_VERSION:
		return
	var raw_items: Variant = data.get("items", [])
	if not raw_items is Array:
		return
	var loaded: Array[Dictionary] = []
	for raw: Variant in raw_items:
		if raw is Dictionary and _is_valid_cache_item(raw):
			var item: Dictionary = (raw as Dictionary).duplicate(true)
			item["src"] = "OFFLINE_FIREBASE"
			loaded.append(item)
	_cache_items = loaded
	_cache_revision = int(data.get("revision", 0))
	print("[FirebaseQuizCache] Loaded %d cached quizzes (revision=%d)" % [
		_cache_items.size(), _cache_revision
	])


func _load_outbox() -> void:
	var data := _read_json_dictionary(OUTBOX_PATH)
	if data.is_empty():
		data = _read_json_dictionary(OUTBOX_BACKUP_PATH)
	var candidates: Variant = data.get("candidates", {})
	var evaluations: Variant = data.get("evaluations", {})
	if candidates is Dictionary:
		_candidate_outbox = (candidates as Dictionary).duplicate(true)
	if evaluations is Dictionary:
		_evaluation_outbox = (evaluations as Dictionary).duplicate(true)


func _save_outbox() -> void:
	if not _write_json_atomically(
		OUTBOX_PATH, OUTBOX_TEMP_PATH, OUTBOX_BACKUP_PATH,
		{
			"version": CACHE_VERSION,
			"candidates": _candidate_outbox,
			"evaluations": _evaluation_outbox,
		}
	):
		push_warning("[FirebaseQuizCache] Could not persist upload outbox")


func _replace_cache_atomically(items: Array[Dictionary], revision: int) -> bool:
	return _write_json_atomically(
		CACHE_PATH, CACHE_TEMP_PATH, CACHE_BACKUP_PATH,
		{
			"version": CACHE_VERSION,
			"revision": revision,
			"items": items,
		}
	)


func _write_json_atomically(target_path: String, temp_path: String,
		backup_path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()

	var verify := _read_json_dictionary(temp_path)
	if int(verify.get("version", 0)) != CACHE_VERSION:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false

	var target := ProjectSettings.globalize_path(target_path)
	var temp := ProjectSettings.globalize_path(temp_path)
	var backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(target_path):
		if DirAccess.rename_absolute(target, backup) != OK:
			DirAccess.remove_absolute(temp)
			return false
	var rename_err := DirAccess.rename_absolute(temp, target)
	if rename_err != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup, target)
		return false
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup)
	return true


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return data if data is Dictionary else {}


func _schedule_retry() -> void:
	if _retry_timer == null or not _retry_timer.is_stopped():
		return
	_retry_timer.start(_retry_seconds)
	_retry_seconds = minf(MAX_RETRY_SECONDS, _retry_seconds * 2.0)


func _on_retry_timeout() -> void:
	flush_outbox()
	sync_now()

extends RefCounted
class_name ReplayRecorder

const ToonPresets = preload("res://scripts/cosmetics/character_toon_presets.gd")

## リプレイ記録クラス
## ゲーム中にフレームごとの状態スナップショットを記録し、
## ファイルへの保存・読込・共有エクスポートに対応する。

const SAVE_DIR := "user://replays/"
const MAX_REPLAYS := 20  # 保存できる最大リプレイ数

## 1フレームのスナップショット
## PackedFloat32Array にパックして省メモリ化
## [0] t, [1-3] p1_xyz, [4] p1_vel_y, [5] p1_alive, [6] p1_emote,
## [7-9] p2_xyz, [10] p2_vel_y, [11] p2_alive, [12] p2_emote,
## [13] scroll_z, [14] wall_idx, [15] score, [16] p2_score,
## [17] state_id, [18] correct_flash, [19] wrong_flash,
## [20] go_timer, [21] p2_go_timer, [22] p1_jump, [23] p2_jump
const FIELDS_PER_FRAME := 24

var frames: PackedFloat32Array = PackedFloat32Array()
var frame_count: int = 0
var is_recording: bool = false

## メタデータ
var meta: Dictionary = {}

## クイズデータ (壁インデックス → クイズ情報)
var quiz_snapshots: Dictionary = {}  # {wall_idx: {q, c, a, e}}

## 記録済みの壁インデックス
var _recorded_walls: Dictionary = {}

# 状態文字列 → 数値ID マッピング
const STATE_IDS := {
	"MENU": 0, "PRELOADING": 1, "WAITING_START": 2, "FLYOVER": 3,
	"COUNTDOWN": 4, "PLAYING": 5, "CORRECT": 6, "GAME_OVER": 7,
	"CLEAR": 8, "GOAL_RACE": 9, "ONLINE_QUIZ_ERROR": 10
}

const ID_TO_STATE := {
	0: "MENU", 1: "PRELOADING", 2: "WAITING_START", 3: "FLYOVER",
	4: "COUNTDOWN", 5: "PLAYING", 6: "CORRECT", 7: "GAME_OVER",
	8: "CLEAR", 9: "GOAL_RACE", 10: "ONLINE_QUIZ_ERROR"
}

func start_recording(gs: QuizGameState) -> void:
	frames.clear()
	frame_count = 0
	quiz_snapshots.clear()
	_recorded_walls.clear()
	is_recording = true

	# メタデータを記録
	meta = {
		"subject": gs.subject,
		"grade": gs.grade,
		"difficulty": gs.difficulty,
		"mode": gs.mode,
		"num_players": gs.num_players,
		"target_count": gs.target_count,
		"p1_hat": gs.p1_hat,
		"p2_hat": gs.p2_hat,
		"p1_toon_preset": ToonPresets.normalize(gs.p1_toon_preset),
		"p2_toon_preset": ToonPresets.normalize(gs.p2_toon_preset),
		"timestamp": int(Time.get_unix_time_from_system()),
		"version": 2,
	}

func stop_recording(gs: QuizGameState) -> void:
	is_recording = false
	# 最終スコアを更新
	meta["final_score"] = gs.score
	meta["final_p2_score"] = gs.player2_score
	meta["final_state"] = gs.game_state
	meta["play_time"] = gs.play_time
	meta["max_streak"] = gs.max_streak
	meta["total_answered"] = gs.total_answered

func capture(gs: QuizGameState) -> void:
	if not is_recording:
		return

	# クイズデータの記録（壁ごとに1回）
	if gs.current_quiz and not _recorded_walls.has(gs.current_wall_index):
		_recorded_walls[gs.current_wall_index] = true
		quiz_snapshots[gs.current_wall_index] = {
			"q": gs.current_quiz.q,
			"c": Array(gs.current_quiz.c),
			"a": gs.current_quiz.a,
			"e": gs.current_quiz.e,
		}

	# フレームデータをパック
	var state_id: float = float(STATE_IDS.get(gs.game_state, 0))

	var offset := frame_count * FIELDS_PER_FRAME
	frames.resize(offset + FIELDS_PER_FRAME)

	frames[offset + 0] = gs.play_time
	frames[offset + 1] = gs.player_x
	frames[offset + 2] = gs.player_y
	frames[offset + 3] = gs.player_z
	frames[offset + 4] = gs.player_vel_y
	frames[offset + 5] = 1.0 if gs.p1_alive else 0.0
	frames[offset + 6] = float(gs.p1_emote)
	frames[offset + 7] = gs.player2_x
	frames[offset + 8] = gs.player2_y
	frames[offset + 9] = gs.player2_z
	frames[offset + 10] = gs.player2_vel_y
	frames[offset + 11] = 1.0 if gs.p2_alive else 0.0
	frames[offset + 12] = float(gs.p2_emote)
	frames[offset + 13] = gs.world_scroll_z
	frames[offset + 14] = float(gs.current_wall_index)
	frames[offset + 15] = float(gs.score)
	frames[offset + 16] = float(gs.player2_score)
	frames[offset + 17] = state_id
	frames[offset + 18] = gs.correct_flash
	frames[offset + 19] = gs.wrong_flash
	frames[offset + 20] = gs.game_over_timer
	frames[offset + 21] = gs.player2_game_over_timer
	frames[offset + 22] = 1.0 if gs.p1_jump_trigger else 0.0
	frames[offset + 23] = 1.0 if gs.p2_jump_trigger else 0.0

	frame_count += 1


# ── フレームアクセス ──

func get_frame(index: int) -> Dictionary:
	if index < 0 or index >= frame_count:
		return {}
	var o := index * FIELDS_PER_FRAME
	return {
		"t": frames[o + 0],
		"p1_x": frames[o + 1], "p1_y": frames[o + 2], "p1_z": frames[o + 3],
		"p1_vel_y": frames[o + 4],
		"p1_alive": frames[o + 5] > 0.5,
		"p1_emote": int(frames[o + 6]),
		"p2_x": frames[o + 7], "p2_y": frames[o + 8], "p2_z": frames[o + 9],
		"p2_vel_y": frames[o + 10],
		"p2_alive": frames[o + 11] > 0.5,
		"p2_emote": int(frames[o + 12]),
		"scroll_z": frames[o + 13],
		"wall_idx": int(frames[o + 14]),
		"score": int(frames[o + 15]),
		"p2_score": int(frames[o + 16]),
		"state": ID_TO_STATE.get(int(frames[o + 17]), "PLAYING"),
		"correct_flash": frames[o + 18],
		"wrong_flash": frames[o + 19],
		"go_timer": frames[o + 20],
		"p2_go_timer": frames[o + 21],
		"p1_jump": frames[o + 22] > 0.5,
		"p2_jump": frames[o + 23] > 0.5,
	}

func get_frame_time(index: int) -> float:
	if index < 0 or index >= frame_count:
		return 0.0
	return frames[index * FIELDS_PER_FRAME]

func get_duration() -> float:
	if frame_count == 0:
		return 0.0
	return frames[(frame_count - 1) * FIELDS_PER_FRAME]

## 指定時間に最も近いフレームインデックスを二分探索で取得
func find_frame_at_time(t: float) -> int:
	if frame_count == 0:
		return 0
	var lo := 0
	var hi := frame_count - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if get_frame_time(mid) < t:
			lo = mid + 1
		else:
			hi = mid
	return lo

## 2フレーム間を補間したデータを取得
func get_interpolated_frame(t: float) -> Dictionary:
	if frame_count == 0:
		return {}
	var idx := find_frame_at_time(t)
	if idx == 0 or idx >= frame_count:
		return get_frame(clampi(idx, 0, frame_count - 1))

	var f0 := get_frame(idx - 1)
	var f1 := get_frame(idx)
	var t0: float = f0["t"]
	var t1: float = f1["t"]
	if t1 <= t0:
		return f1

	var alpha: float = clampf((t - t0) / (t1 - t0), 0.0, 1.0)

	# float値をlerp、bool/intは最新値を使用
	var result := {}
	for key in f1:
		var v0 = f0[key]
		var v1 = f1[key]
		if v0 is float and v1 is float:
			result[key] = lerpf(v0 as float, v1 as float, alpha)
		else:
			result[key] = v1
	return result


# ── ファイル保存/読込 ──

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func save_to_file(filename: String = "") -> String:
	_ensure_dir()
	if filename.is_empty():
		var ts := int(Time.get_unix_time_from_system())
		var mode_short: String = meta.get("mode", "TEN").substr(0, 3)
		filename = "replay_%s_%d.rep" % [mode_short, ts]

	var path := SAVE_DIR + filename

	var data := {
		"meta": meta,
		"quiz": quiz_snapshots,
		"frame_count": frame_count,
		"fields_per_frame": FIELDS_PER_FRAME,
		"frames_base64": Marshalls.raw_to_base64(frames.to_byte_array()),
	}

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
		_cleanup_old_replays()
		print("[ReplayRecorder] Saved: %s (%d frames, %.1fs)" % [path, frame_count, get_duration()])
		return path
	else:
		push_error("[ReplayRecorder] Failed to save: %s" % path)
		return ""

func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("[ReplayRecorder] File not found: %s" % path)
		return false

	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return false

	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		push_error("[ReplayRecorder] JSON parse error: %s" % path)
		return false

	var data: Dictionary = json.data
	if not data is Dictionary:
		return false

	meta = data.get("meta", {})
	frame_count = data.get("frame_count", 0)

	# quiz_snapshots のキーを int に復元
	quiz_snapshots.clear()
	var raw_quiz: Dictionary = data.get("quiz", {})
	for key in raw_quiz:
		quiz_snapshots[int(key)] = raw_quiz[key]

	var b64: String = data.get("frames_base64", "")
	if not b64.is_empty():
		var raw := Marshalls.base64_to_raw(b64)
		frames = raw.to_float32_array()
	else:
		frames.clear()
		frame_count = 0

	is_recording = false
	print("[ReplayRecorder] Loaded: %s (%d frames, %.1fs)" % [path, frame_count, get_duration()])
	return true

## 共有用エクスポート: リプレイデータをクリップボードにコピー可能な文字列で返す
func export_for_sharing() -> String:
	var data := {
		"meta": meta,
		"quiz": quiz_snapshots,
		"frame_count": frame_count,
		"fields_per_frame": FIELDS_PER_FRAME,
		"frames_base64": Marshalls.raw_to_base64(frames.to_byte_array()),
	}
	return JSON.stringify(data)

## 共有用インポート: エクスポートされた文字列からリプレイを復元
func import_from_string(json_str: String) -> bool:
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return false
	var data: Dictionary = json.data
	if not data is Dictionary:
		return false
	meta = data.get("meta", {})
	frame_count = data.get("frame_count", 0)
	quiz_snapshots.clear()
	var raw_quiz: Dictionary = data.get("quiz", {})
	for key in raw_quiz:
		quiz_snapshots[int(key)] = raw_quiz[key]
	var b64: String = data.get("frames_base64", "")
	if not b64.is_empty():
		frames = Marshalls.base64_to_raw(b64).to_float32_array()
	else:
		frames.clear()
		frame_count = 0
	is_recording = false
	return true

## 保存済みリプレイ一覧を取得
static func list_saved_replays() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return results
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return results
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".rep"):
			var path := SAVE_DIR + fname
			var info := _read_meta_only(path)
			if not info.is_empty():
				info["filename"] = fname
				info["path"] = path
				results.append(info)
		fname = dir.get_next()
	# 新しい順にソート
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("timestamp", 0) > b.get("timestamp", 0)
	)
	return results

static func _read_meta_only(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return {}
	var data: Dictionary = json.data
	if not data is Dictionary:
		return {}
	var m: Dictionary = data.get("meta", {})
	m["frame_count"] = data.get("frame_count", 0)
	return m

func _cleanup_old_replays() -> void:
	var replays := ReplayRecorder.list_saved_replays()
	if replays.size() > MAX_REPLAYS:
		# 古い順に削除
		for i in range(MAX_REPLAYS, replays.size()):
			var path: String = replays[i].get("path", "")
			if not path.is_empty():
				DirAccess.remove_absolute(path)
				print("[ReplayRecorder] Cleaned up old replay: %s" % path)

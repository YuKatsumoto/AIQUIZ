extends RefCounted
class_name ReplayPlayer

## リプレイ再生クラス
## ReplayRecorder のデータを時間ベースで再生し、
## game_state に状態を注入する。

var recorder: ReplayRecorder
var is_playing: bool = false
var is_paused: bool = false
var current_time: float = 0.0
var playback_speed: float = 1.0

## 利用可能な再生速度
const SPEED_OPTIONS := [0.25, 0.5, 1.0, 2.0, 4.0]
var _speed_index: int = 2  # 1.0x

signal playback_started
signal playback_stopped
signal playback_paused(paused: bool)
signal time_changed(t: float)
signal speed_changed(speed: float)

func setup(replay: ReplayRecorder) -> void:
	recorder = replay
	current_time = 0.0
	is_playing = false
	is_paused = false
	_speed_index = 2
	playback_speed = 1.0

func play() -> void:
	if not recorder or recorder.frame_count == 0:
		return
	is_playing = true
	is_paused = false
	playback_started.emit()

func pause() -> void:
	is_paused = not is_paused
	playback_paused.emit(is_paused)

func stop() -> void:
	is_playing = false
	is_paused = false
	current_time = 0.0
	playback_stopped.emit()

func seek(t: float) -> void:
	if not recorder:
		return
	current_time = clampf(t, 0.0, recorder.get_duration())
	time_changed.emit(current_time)

func cycle_speed(delta: int = 1) -> void:
	_speed_index = clampi(_speed_index + delta, 0, SPEED_OPTIONS.size() - 1)
	playback_speed = SPEED_OPTIONS[_speed_index]
	speed_changed.emit(playback_speed)

func get_speed_label() -> String:
	if playback_speed < 1.0:
		return "%.2gx" % playback_speed
	return "%dx" % int(playback_speed)

func get_duration() -> float:
	if recorder:
		return recorder.get_duration()
	return 0.0

func get_progress() -> float:
	var dur := get_duration()
	if dur <= 0.0:
		return 0.0
	return current_time / dur


# ── フレーム更新 ──

func advance(dt: float) -> void:
	if not is_playing or is_paused or not recorder:
		return
	current_time += dt * playback_speed
	if current_time >= recorder.get_duration():
		current_time = recorder.get_duration()
		is_paused = true
		playback_paused.emit(true)
	time_changed.emit(current_time)

func get_current_frame() -> Dictionary:
	if not recorder or recorder.frame_count == 0:
		return {}
	return recorder.get_interpolated_frame(current_time)

## game_state に現在のフレームデータを注入する
func apply_to_game_state(gs: QuizGameState) -> void:
	var frame := get_current_frame()
	if frame.is_empty():
		return

	gs.player_x = frame["p1_x"]
	gs.player_y = frame["p1_y"]
	gs.player_z = frame["p1_z"]
	gs.player_vel_y = frame["p1_vel_y"]
	gs.p1_alive = frame["p1_alive"]
	gs.p1_emote = frame["p1_emote"]

	gs.player2_x = frame["p2_x"]
	gs.player2_y = frame["p2_y"]
	gs.player2_z = frame["p2_z"]
	gs.player2_vel_y = frame["p2_vel_y"]
	gs.p2_alive = frame["p2_alive"]
	gs.p2_emote = frame["p2_emote"]

	gs.world_scroll_z = frame["scroll_z"]
	gs.current_wall_index = frame["wall_idx"]
	gs.score = frame["score"]
	gs.player2_score = frame["p2_score"]
	gs.game_state = frame["state"]
	gs.correct_flash = frame["correct_flash"]
	gs.wrong_flash = frame["wrong_flash"]
	gs.game_over_timer = frame["go_timer"]
	gs.player2_game_over_timer = frame["p2_go_timer"]
	gs.p1_jump_trigger = frame["p1_jump"]
	gs.p2_jump_trigger = frame["p2_jump"]
	gs.play_time = frame["t"]

	# クイズデータの復元
	var wall_idx: int = frame["wall_idx"]
	if recorder.quiz_snapshots.has(wall_idx):
		var qd: Dictionary = recorder.quiz_snapshots[wall_idx]
		if gs.current_quiz == null or gs.current_quiz.q != qd["q"]:
			var choices := PackedStringArray()
			for c in qd["c"]:
				choices.append(str(c))
			gs.current_quiz = QuizItem.create(
				qd["q"], choices, qd["a"], qd["e"], "REPLAY"
			)

func get_time_label() -> String:
	var cur_min := int(current_time) / 60
	var cur_sec := int(current_time) % 60
	var dur := get_duration()
	var dur_min := int(dur) / 60
	var dur_sec := int(dur) % 60
	return "%d:%02d / %d:%02d" % [cur_min, cur_sec, dur_min, dur_sec]

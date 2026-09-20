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

	gs.saw.enabled = bool(frame.get("saw_enabled", false))
	gs.saw.local_z = float(frame.get("saw_z", SawChaseState.INITIAL_Z))
	gs.saw.elapsed = float(frame.get("saw_time", 0.0))
	gs.saw.wheel_distance = float(frame.get("saw_travel", 0.0))
	# Presentation-only velocity from recorded travel: independent of seek order.
	var before_time := maxf(0.0,current_time-0.05)
	var after_time := minf(recorder.get_duration(),current_time+0.05)
	var before := recorder.get_interpolated_frame(before_time)
	var after := recorder.get_interpolated_frame(after_time)
	var saw_interval := float(after.get("saw_time",0.0))-float(before.get("saw_time",0.0))
	var saw_speed := 0.0
	if saw_interval > 0.000001:
		saw_speed = maxf(0.0,(float(after.get("saw_travel",0.0))-float(before.get("saw_travel",0.0)))/saw_interval)
	gs.set_meta("saw_operator_speed",saw_speed)
	var lift_now := _saw_lifts_at(current_time)
	gs.set_meta("saw_operator_lift",_saw_operator_lift_at(current_time))
	gs.set_meta("saw_replay_lifts",lift_now)
	gs.p1_saw_killed = bool(frame.get("saw_killed1", false))
	gs.p2_saw_killed = bool(frame.get("saw_killed2", false))
	gs.hp_state_available = bool(frame.get("hp_available", false))
	if gs.uses_hp() and int(frame["wall_idx"]) == gs.current_wall_index + 1:
		gs.question_completed.emit(gs.current_wall_index, int(frame["score"]) > gs.score or int(frame["p2_score"]) > gs.player2_score)
	gs._set_player_hp(1, int(frame.get("hp1", 3)))
	gs._set_player_hp(2, int(frame.get("hp2", 3)))
	gs.p1_damage_time = float(frame.get("hurt1", 0.0))
	gs.p2_damage_time = float(frame.get("hurt2", 0.0))
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

func _raw_saw_operator_lift(time: float) -> Dictionary:
	var before_time := maxf(0.0,time-.05)
	var after_time := minf(recorder.get_duration(),time+.05)
	var before := _saw_lifts_at(before_time)
	var after := _saw_lifts_at(after_time)
	var now := _saw_lifts_at(time)
	var selected := 7 # Physical left in the gameplay carriage frame.
	var max_change := -1.0
	for i in range(7,-1,-1):
		var change := absf(after[i]-before[i])
		if change>max_change+.00001:
			max_change=change;selected=i
		elif change<.00001 and max_change<.00001 and now[i]>now[selected]:selected=i
	return {"height":now[selected],"speed":(after[selected]-before[selected])/maxf(after_time-before_time,.00001)}

func _saw_operator_lift_at(time: float) -> Dictionary:
	# Reconstruct the short lever transition from history, never the last seek.
	var start := maxf(0.0,time-.24)
	var value := _raw_saw_operator_lift(start)
	var speed := clampf(float(value.speed),-6.0,6.0)
	var step := (time-start)/12.0
	for i in range(1,13):
		value=_raw_saw_operator_lift(start+i*step)
		speed=move_toward(speed,clampf(float(value.speed),-6.0,6.0),50.0*step)
	value.speed=speed
	return value

func _saw_lifts_at(time: float) -> PackedFloat32Array:
	var frame := recorder.get_interpolated_frame(time)
	var heights := PackedFloat32Array();heights.resize(8)
	for index in [1,2]:
		if index>int(recorder.meta.get("num_players",2)):continue
		var prefix := "p1_" if index==1 else "p2_"
		var killed := bool(frame.get("saw_killed%d"%index,false))
		if not killed and not bool(frame.get(prefix+"alive",false)):continue
		var timer := float(frame.get("go_timer" if index==1 else "p2_go_timer",0.0))
		var pose := recorder.get_interpolated_frame(maxf(0.0,time-timer)) if killed else frame
		var x := float(pose.get(prefix+"x",0.0))
		var y := float(pose.get(prefix+"y",0.0))
		var z := float(pose.get(prefix+"z",0.0))-float(pose.get("scroll_z",0.0))
		var saw_z := float(pose.get("saw_z",SawChaseState.INITIAL_Z))
		var fade := 1.0-smoothstep(SawChaseState.CUT_SCATTER_DELAY,SawChaseState.CUT_SCATTER_DELAY+.6,timer) if killed else 1.0
		for i in 8:
			var dx := x-(i-3.5)*SawChaseState.BLADE_PITCH
			var radius := SawChaseState.BLADE_RADIUS+QuizGameState.PLAYER_BODY_RADIUS
			if absf(dx)>radius or y<=.05:continue
			var clearance := Vector2(dx,z-saw_z).length()-radius
			heights[i]=maxf(heights[i],(y+.9)*(1.0-smoothstep(0.0,4.0,clearance))*fade)
	return heights

func get_time_label() -> String:
	var cur_min := int(current_time) / 60
	var cur_sec := int(current_time) % 60
	var dur := get_duration()
	var dur_min := int(dur) / 60
	var dur_sec := int(dur) % 60
	return "%d:%02d / %d:%02d" % [cur_min, cur_sec, dur_min, dur_sec]

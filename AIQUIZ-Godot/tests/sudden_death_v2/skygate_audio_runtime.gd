extends "res://tests/sudden_death_v2/skygate_runtime.gd"

## サドンデスの効果音の通し（docs/sound_effects.md「サドンデス」）。skygate_runtime.gd と同じ実ゲームの通しを画を撮らずに回し、
## 鳴った音（AudioManager.sfx_played）の場面と時刻、水上機のエンジンの音（FloatplaneSound）と落ちる風（SkyGatePresenter）の
## 大きさを記録して確かめる。SFX バスを録音する（Master は絞るのでスピーカーからは鳴らない）。
## 曲の切り替え（docs/bgm_renewal.md「サドンデスの曲」）も確かめる：判定の結果の曲 → 8.6 秒の導入曲 → GO の本戦曲 →
## 勝者の着地の結果の曲（帰還のあとも流れたまま）。打ち切りは 結果の曲 → 導入曲 → 結果の曲。
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/sudden_death_v2/skygate_audio_bootstrap.gd -- case=p1
## case：p1（P2 が ROUND 1 の 2 枚目でまちがえる）/ round2（ROUND 2 まで）/ both（ROUND 1 の 2 枚目で 2 人ともまちがえて復活、3 枚目で P2）
##   / abort（準備の失敗。曲の切り替えだけを確かめる）
## 出力：artifacts/sudden_death_audio/<case>/（report.json・runtime.json（鳴った音と大きさ）・sfx.f32）。
## 録音は python tools/audio/analyze_helicopter_capture.py --folder artifacts/sudden_death_audio/<case> で WAV にしてピークを測る。

const AUDIO_ROOT := "res://artifacts/sudden_death_audio/"
## 場面ごとに、少なくとも 1 回鳴るはずの音
const EXPECT := {
	"BRANCH": ["sd_whistle", "sd_siren", "sd_tower_move"],
	"REVEAL": ["score_drum_roll", "score_drum_finish"],
	"BOARD": ["sd_siren", "sd_stand_lift", "fp_flyby", "fp_touchdown", "sd_tower_move", "sd_stand_lower", "sd_servo", "fp_ramp",
		"fp_ramp_latch", "fp_belt", "sd_cloud_whoosh"],
	"DROP": ["fp_ramp", "fp_ramp_wind", "fp_green_light", "fp_belt", "fp_jump"],
	"VENUE": ["countdown_beep", "countdown_go", "sg_gate_rush", "sg_tear", "door_correct", "sg_safe", "sg_bounce", "barrier_explosion",
		"body_burst", "door_wrong", "score_drum_finish", "sg_chute_open", "jump_land", "sg_float_splash", "sg_winner", "ghost_soul_rise"],
	"EXTRACT": ["sd_servo", "fp_ramp", "fp_belt", "fp_ramp_latch", "sd_cloud_whoosh"],
	"HOME": ["fp_ramp", "fp_ramp_wind", "fp_green_light", "fp_belt", "fp_jump", "jump_land", "crowd_goal_cheer", "ghost_soul_rise", "sd_tower_move"],
}
const EXPECT_ROUND2 := {
	"VENUE": ["sg_round_clear", "sg_round_gong", "sg_notice"],
}
const EXPECT_BOTH := {"VENUE": ["sg_revive"]}
## エンジンの音が聞こえるはずの場面
const ENGINE_ACTS := ["BOARD", "SKY", "DROP", "EXTRACT", "HOME"]

var _events: Array = []
var _levels := {}
var _capture: AudioEffectCapture
var _capture_file: FileAccess
var _sfx_bus := -1
var _capture_index := -1
var _peak := 0.0
var _master_db := 0.0
## 録音から読んだサンプルの数（すべてのチャンネルの組を合わせて）。鳴った音の録音の中の位置を記録する
var _captured := 0
var _capture_started_usec := 0
## 曲が替わった瞬間：曲・場面・段階・決着演出の時計・音量の文脈
var _music: Array = []
var _music_track: StringName = &"?"
## 場面ごとに、実際に鳴っていた曲（AudioManager の曲ごとのプレイヤーが再生中のもの）
var _music_heard := {}


func _ready() -> void:
	out_root = AUDIO_ROOT
	take_shots = false
	_sfx_bus = AudioServer.get_bus_index("SFX")
	_capture_index = AudioServer.get_bus_effect_count(_sfx_bus)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 30.0
	AudioServer.add_bus_effect(_sfx_bus, _capture)
	# スピーカーからは鳴らさない（SFX バスの録音は Master の音量に関係しない）
	_master_db = AudioServer.get_bus_volume_db(0)
	AudioServer.set_bus_volume_db(0, -80.0)
	AudioManager.sfx_played.connect(_on_sfx)
	super()


func _process(_delta: float) -> void:
	if _capture == null:
		return
	if _capture_file == null and not out.is_empty() and out != OUT_ROOT:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
		_capture_file = FileAccess.open(out + "sfx.f32", FileAccess.WRITE)
		_capture.clear_buffer()
		_capture_started_usec = Time.get_ticks_usec()
	if _capture_file != null:
		var buffer := _capture.get_buffer(_capture.get_frames_available())
		if not buffer.is_empty():
			_capture_file.store_buffer(buffer.to_byte_array())
			_captured += buffer.size()
		_peak = maxf(_peak, db_to_linear(maxf(AudioServer.get_bus_peak_volume_left_db(_sfx_bus, 0),
			AudioServer.get_bus_peak_volume_right_db(_sfx_bus, 0))))


func _on_sfx(cue: StringName) -> void:
	var act := director.act_name() if director != null else "-"
	var phase := ""
	var presenter := director.presenter() as SkyGatePresenter if director != null else null
	if presenter != null and act in ["VENUE", "EXTRACT"]:
		phase = presenter.phase_name()
	_events.append({"cue": str(cue), "act": act, "phase": phase, "act_time": snappedf(director.act_time() if director != null else 0.0, 0.01),
		"frame": _frame, "captured": _captured})


## ROUND 1 の 2 枚目で 2 人ともまちがえる（その場で復活）→ 3 枚目で P2 だけまちがえる。
func _mode(game: SkyGateGame, player: int) -> String:
	if case_name == "both":
		if game.current_round == 1 and game.gate_index == 1:
			return "wrong"
		if game.current_round == 1 and game.gate_index >= 2 and player == 2:
			return "wrong"
		return "right"
	return super(game, player)


func _watch() -> void:
	super()
	var act := director.act_name()
	var row: Dictionary = _levels.get(act, {"engine": 0.0, "inside": 0.0, "wind": 0.0, "frames": 0})
	row.frames = int(row.frames) + 1
	var staging := director.floatplane_staging()
	if staging != null and staging.sound != null:
		row.engine = maxf(float(row.engine), staging.sound.mix_gain)
		row.inside = maxf(float(row.inside), staging.sound.inside_amount())
	var presenter := director.presenter() as SkyGatePresenter
	if presenter != null:
		row.wind = maxf(float(row.wind), presenter.wind_audio_gain())
	_levels[act] = row
	var phase := presenter.phase_name() if presenter != null and act in ["VENUE", "EXTRACT"] else ""
	var track := AudioManager.get_music_track()
	if track != _music_track:
		_music_track = track
		_music.append({"track": str(track), "act": act, "phase": phase, "ceremony": snappedf(gs.result_ceremony_elapsed, 0.01),
			"context": str(AudioManager.get_music_context()), "frame": _frame})
	var player := AudioManager._track_players.get(track) as AudioStreamPlayer
	var key := act + (":" + phase if phase != "" else "")
	var heard: Array = _music_heard.get(key, [])
	var playing := str(track) if player != null and player.playing else "-"
	if not heard.has(playing):
		heard.append(playing)
	_music_heard[key] = heard


func _finish() -> void:
	if _capture_file != null:
		_capture_file.close()
		_capture_file = null
	AudioManager.sfx_played.disconnect(_on_sfx)
	AudioServer.remove_bus_effect(_sfx_bus, _capture_index)
	# 終わったあとのフレームで録音を開き直さない（開き直すと空のファイルで上書きされる）
	_capture = null
	AudioServer.set_bus_volume_db(0, _master_db)
	_check_audio()
	# 録音に入っているステレオの組の数：読んだサンプルの数と実時間から数える（7.1 ch の機器でも前の組だけのことがある）
	var rate := AudioServer.get_mix_rate()
	var elapsed := maxf(float(Time.get_ticks_usec() - _capture_started_usec) / 1000000.0, 0.001)
	var pairs := clampi(roundi(float(_captured) / rate / elapsed), 1, maxi(AudioServer.get_bus_channels(_sfx_bus), 1))
	for e: Dictionary in _events:
		e["capture_at"] = snappedf(float(e.captured) / float(pairs) / rate, 0.001)
	var audio := {"events": _events, "levels": _levels, "music": _music, "music_heard": _music_heard,
		"peak_dbfs": snappedf(linear_to_db(maxf(_peak, 0.00001)), 0.1),
		"snapshots": [{"phase": "sfx", "sample_rate": rate, "peak": _peak}], "capture_stereo_pairs": pairs,
		"capture_seconds": snappedf(float(_captured) / float(pairs) / rate, 0.1), "real_seconds": snappedf(elapsed, 0.1)}
	var f := FileAccess.open(out + "runtime.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(audio, "  "))
	f.close()
	print("SKYGATE_AUDIO ", JSON.stringify({"case": case_name, "cues": _events.size(), "peak_dbfs": audio.peak_dbfs}))
	super()


func _check_audio() -> void:
	_check_music()
	if case_name == "abort":
		return
	var expect := EXPECT.duplicate(true)
	var extra: Dictionary = EXPECT_ROUND2 if case_name == "round2" else (EXPECT_BOTH if case_name == "both" else {})
	for act: String in extra:
		var list: Array = (expect.get(act, []) as Array).duplicate()
		list.append_array(extra[act])
		expect[act] = list
	var missing := []
	for act: String in expect:
		for cue: String in expect[act]:
			var found := false
			for e: Dictionary in _events:
				if e.cue == cue and e.act == act:
					found = true
					break
			if not found:
				missing.append("%s@%s" % [cue, act])
	report.checks["audio_missing"] = missing
	if not missing.is_empty():
		fail("sounds that did not play where expected: %s" % str(missing))
	for act: String in ENGINE_ACTS:
		var row: Dictionary = _levels.get(act, {})
		if row.is_empty() or float(row.engine) < 0.05:
			fail("the floatplane engine is not heard in %s (max gain %s)" % [act, str(row.get("engine", "-"))])
	if float((_levels.get("SKY", {}) as Dictionary).get("inside", 0.0)) < 0.99:
		fail("the cruise camera never counted as inside the cabin")
	if float((_levels.get("VENUE", {}) as Dictionary).get("wind", 0.0)) < 0.3:
		fail("the falling wind is not heard in the game (max gain %s)" % str((_levels.get("VENUE", {}) as Dictionary).get("wind", "-")))
	var staging := director.floatplane_staging()
	if staging != null and staging.sound != null and staging.sound.mix_gain > 0.01 and not staging.plane.visible:
		fail("the engine is still heard after the plane left (gain %.3f)" % staging.sound.mix_gain)
	report.checks["audio_levels"] = _levels
	report.checks["audio_peak_dbfs"] = snappedf(linear_to_db(maxf(_peak, 0.00001)), 0.1)


## 曲の順番と、替わった場面。導入曲の間（乗り込み〜降下）と本戦の間に、その曲が実際に鳴っていること。
func _check_music() -> void:
	report.checks["music"] = _music
	report.checks["music_heard"] = _music_heard
	var intro := str(AudioManager.MUSIC_TRACK_SUDDEN_DEATH_INTRO)
	var main := str(AudioManager.MUSIC_TRACK_SUDDEN_DEATH_MAIN)
	var result := str(AudioManager.MUSIC_TRACK_RESULT)
	# 判定（6.9 秒）の結果の曲から数える（その前の「曲なし」は数えない）
	var order: Array[String] = []
	var rows: Array = []
	for row: Dictionary in _music:
		if order.is_empty() and row.track != result:
			continue
		order.append(String(row.track))
		rows.append(row)
	var expected: Array[String] = [result, intro, main, result]
	if case_name == "abort":
		expected = [result, intro, result]
	if order != expected:
		fail("music order %s, expected %s (%s)" % [str(order), str(expected), str(_music)])
		return
	var cut_in: Dictionary = rows[1]
	if cut_in.act != "BRANCH" or absf(float(cut_in.ceremony) - HeliSuddenDeathDirector.CUT_IN_TIME) > 0.1 or cut_in.context != str(AudioManager.MUSIC_CONTEXT_SUDDEN_DEATH):
		fail("the intro music did not start at the 8.6 s cut-in (%s)" % str(cut_in))
	if case_name == "abort":
		if not (rows[2].act in ["ABORT", "DONE"]):
			fail("the result music did not come back with the abort (%s)" % str(rows[2]))
	else:
		if rows[2].act != "VENUE" or rows[2].phase != "main":
			fail("the main-event music did not start on GO (%s)" % str(rows[2]))
		if rows[3].act != "VENUE" or rows[3].phase != "finish":
			fail("the result music did not start on the winner's landing (%s)" % str(rows[3]))
		for act: String in ["BOARD", "SKY", "DROP"]:
			# ROUND 2 の前の短い降下は、本戦の曲が流れたまま
			var want: Array = [intro, main] if act == "DROP" and case_name == "round2" else [intro]
			if _music_heard.get(act, []) != want:
				fail("%s should hear %s, heard %s" % [act, str(want), str(_music_heard.get(act, []))])
		for act: String in ["EXTRACT", "HOME"]:
			for key: String in _music_heard:
				if key.begins_with(act) and _music_heard[key] != [result]:
					fail("%s should hear only the result music, heard %s" % [key, str(_music_heard[key])])
	var end_player := AudioManager._track_players.get(AudioManager.MUSIC_TRACK_RESULT) as AudioStreamPlayer
	if AudioManager.get_music_track() != AudioManager.MUSIC_TRACK_RESULT or end_player == null or not end_player.playing:
		fail("the result music is not playing after the return (track %s)" % str(AudioManager.get_music_track()))
	if AudioManager.get_music_context() != AudioManager.MUSIC_CONTEXT_RESULT:
		fail("the music context after the return is %s, not result" % str(AudioManager.get_music_context()))

extends "res://tests/pv_capture/pv_s09_play_runtime.gd"

## PV S21「決着はスコアタワー」を、S09 で 2 人が遊んだ試合（テイク s09_play）の本当の結果発表で撮る（2026-10-22 夜、ユーザーの指示）。
## 記録 s09_play_rec のキーを同じコマで流し直し（S09 と同じ試合になる）、記録が終わったあとも押したままの W で P1 がゴールまで走る。
## 脱落した P2 は幽霊としてサメからゴールのレーンへ跳び移り、結果発表になる（P1：正解 7 × 1.5、P2：正解 2（脱落））。
## 撮るのは結果発表の G0 秒から 285 フレーム。時間の速さは台本 s21（pv_s21_runtime.gd）と同じ：等速 → 早回し → 5.5 拍目に WIN! → 1.25 倍。
## 撮り終えたら、連番と cues.json を pv_0001〜に詰め直す（report の cut_in_frame = 1。通しは 1:1 で置く）。
## sub=1 だけ（遊んだときと同じ 1 秒 60 コマで流し直す。動きのブレはなし）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s21_play inputs=s09_play_rec quality=ultra tag=s21_play_frames

const S21_BEATS := 10.0
const HANDLE_FRAMES := 4
const G0 := 3.0                 # 撮り始める結果発表の時刻（正解数が出そろい、HP が出る直前）
const FAST_FROM := 1.0          # PV のこの秒まで等速
const RAMP := 0.3               # 速さを変える長さ（PV 秒）
const G_SLOW := 6.55            # ここで等速に戻る（タワーが止まった後の静けさ）
const VERDICT_BEAT := 5.5       # WIN! を 5.5 拍目の頭に
const AFTER_SPEED := 1.25       # WIN! のあとの速さ
const MAX_RESULT_WAIT := 2400   # 記録の終わりから結果発表の G0 までの上限（40 秒）
const FINALE_BEATS: Array[String] = ["correct", "hp", "climb", "climb_end", "hush", "verdict", "crown_start", "crown_land",
	"sink_start", "dance_start", "kneel"]

var _s21_first := -1            # 結果発表を撮り始めるテイクのフレーム
var _s21_from_pv := -1.0        # その直前の PV の秒
var _s21_frames := 0
var g0_actual := 0.0
var speed_v := 1.0
var p2_end := 0.0
var _beats := {}                # 結果発表の見せ場 → 詰め直したあとのフレーム


func _init() -> void:
	super._init()
	take_name = "s21_play"
	play_mode = "replay"


func _setup() -> void:
	await super._setup()
	_s21_frames = bf(S21_BEATS) - 1 + HANDLE_FRAMES
	only_frames.clear()
	only_frames[-1] = true          # 結果発表まで絵は保存しない（撮り始めるときに足す）
	_explicit_frames = true
	frame_count = int(_replay.get("frames", 0)) + MAX_RESULT_WAIT + _s21_frames


func _update(n: int, t: float, dt: float) -> void:
	super._update(n, t, dt)
	if _s21_first < 0:
		if gs.result_presentation_active and gs.result_ceremony_elapsed >= G0 - 0.5 / FPS:
			_s21_first = n + 1
			_s21_from_pv = t
			g0_actual = gs.result_ceremony_elapsed
			_plan_speed()
			for f in range(_s21_first, _s21_first + _s21_frames):
				only_frames[f] = true
			frame_count = _s21_first + _s21_frames - 1
			_event("s21_first", {"g0": snappedf(g0_actual, 0.0001)}, _s21_first)
			var hud := world.get_node_or_null("GameplayHUD") as CanvasLayer
			var keep: Array[CanvasLayer] = []
			if hud != null:
				keep.append(hud)
			hide_overlays(keep)             # 台本 s21 と同じく、ゲームの HUD（得点の式と WIN!）だけ残す
		return
	var elapsed := gs.result_ceremony_elapsed
	for beat: String in FINALE_BEATS:
		if not _beats.has(beat) and elapsed >= ResultFinaleMotion.beat(beat) - 0.00001:
			_beats[beat] = n - _s21_first + 1


## 早回しの速さ V を決める：WIN!（ResultFinaleMotion.VERDICT）が VERDICT_BEAT の頭に来て、G_SLOW で等速に戻る（台本 s21 と同じ）
func _plan_speed() -> void:
	var p_verdict := (bf(VERDICT_BEAT) - 1) / FPS
	p2_end = p_verdict - (ResultFinaleMotion.VERDICT - G_SLOW)
	var distance := G_SLOW - (g0_actual + FAST_FROM)
	var span := p2_end - FAST_FROM
	speed_v = (distance - RAMP) / (span - RAMP)
	if speed_v < 1.0 or span < 2.0 * RAMP:
		failures.append("早回しが決まらない（V = %.3f）" % speed_v)


## PV の秒 → ゲームの秒。結果発表を撮り始めるまでは等速（記録と同じ試合のまま）、そこからは台本 s21 の速さ
func _game_time_at(pv: float) -> float:
	if _s21_from_pv < 0.0 or pv <= _s21_from_pv:
		return pv
	return _s21_from_pv + _planned_game_time_at(pv - _s21_from_pv)


func _planned_game_time_at(pv: float) -> float:
	var a := FAST_FROM
	var b := p2_end
	var k := speed_v - 1.0
	if pv <= a:
		return pv
	if pv <= a + RAMP:
		var u := pv - a
		return pv + k * u * u / (2.0 * RAMP)
	var g1 := a + RAMP + k * RAMP * 0.5
	if pv <= b - RAMP:
		return g1 + speed_v * (pv - a - RAMP)
	var g2 := g1 + speed_v * (b - 2.0 * RAMP - a)
	if pv <= b:
		var u := pv - (b - RAMP)
		return g2 + speed_v * u - k * u * u / (2.0 * RAMP)
	var g3 := g2 + RAMP + k * RAMP * 0.5
	var p_verdict := b + (ResultFinaleMotion.VERDICT - G_SLOW)
	if pv <= p_verdict:
		return g3 + (pv - b)
	return g3 + (p_verdict - b) + AFTER_SPEED * (pv - p_verdict)


func _check() -> void:
	super._check()
	report["cut_in_frame"] = 1
	report["result"] = {"winner": gs.result_winner, "points_half": [gs.result_p1_score, gs.result_p2_score],
		"formula": [gs.get_result_formula_text(1), gs.get_result_formula_text(2)], "ghosts": gs.result_ghost_mask}
	report["s21"] = {"take_first_frame": _s21_first, "frames": _s21_frames, "g0_actual": snappedf(g0_actual, 0.0001),
		"speed": snappedf(speed_v, 0.001), "slow_from_pv": snappedf(p2_end, 0.0001), "beats": _beats}
	if _s21_first < 0:
		failures.append("結果発表の %.1f 秒まで届かなかった（%s）" % [G0, gs.game_state])
		return
	if gs.result_winner != 1:
		failures.append("P1 が勝っていない（winner %d）" % gs.result_winner)
	if not _beats.has("verdict") or absi(int(_beats["verdict"]) - bf(VERDICT_BEAT)) > 1:
		failures.append("WIN! が %s（予定 %d）" % [str(_beats.get("verdict", "なし")), bf(VERDICT_BEAT)])
	report["highlights"] = {"formula_correct": _beats.get("correct", -1), "hp_bonus": _beats.get("hp", -1),
		"climb": _beats.get("climb", -1), "towers_stop": _beats.get("climb_end", -1), "win": _beats.get("verdict", -1),
		"crown_land": _beats.get("crown_land", -1), "loser_sinks": _beats.get("sink_start", -1)}
	# ドラムロールは結果発表の cast_start に鳴り始めるので、撮り始めより前（台本 s21 と同じ置き方）
	report["audio_before_take"] = [{"cue": "score_drum_roll",
		"seconds_into_sound_at_frame_1": snappedf(g0_actual - ResultFinaleMotion.beat("cast_start"), 0.001),
		"cut_at_frame": _beats.get("verdict", -1)}]


## 撮った結果発表の連番と効果音のキューを、テイクのフレーム 1 から詰め直す
func _cleanup() -> void:
	super._cleanup()
	if _s21_first < 0:
		return
	var dir := ProjectSettings.globalize_path(out)
	for f in range(_s21_first, _s21_first + _s21_frames):
		var src := dir + "pv_%04d.jpg" % f
		if FileAccess.file_exists(src):
			DirAccess.rename_absolute(src, dir + "pv_%04d.jpg" % (f - _s21_first + 1))
	var kept: Array = []
	for cue: Dictionary in cues:
		var f := int(cue["frame"])
		if f >= _s21_first and f < _s21_first + _s21_frames:
			var moved := cue.duplicate()
			moved["frame"] = f - _s21_first + 1
			moved["t"] = snappedf(float(cue["t"]) - _s21_from_pv, 0.0001)
			kept.append(moved)
	cues = kept

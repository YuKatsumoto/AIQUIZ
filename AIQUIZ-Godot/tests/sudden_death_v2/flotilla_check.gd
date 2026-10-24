extends Node

## 着地台のまわりの観客船（SkyGateFlotilla）とクラッカー・打ち上げ花火（SkyGateFireworks）を実画面で確かめる
## （docs/sudden_death_v2/sky_gate.md 第9章）。監督なしのデバッグの入口 SkyGateDebug を 1 フレームずつ進める。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --script res://tests/sudden_death_v2/flotilla_check_bootstrap.gd -- [case=finale|round] [quality=high]
## case=finale：1 枚目で P2 がまちがえて P1 の勝ち → 勝者の着地（観客が身を乗り出す → クラッカー → 花火）→ ダンスの間の花火 → 迎え（止まる）。
## case=round：2 人とも 4 枚突破 → 2 人とも着地台へ（クラッカーと 5 発）→ 次のラウンドで片づく。
## 画は artifacts/sudden_death_v2/sky_gate_flotilla/<case>_*.png、結果は標準出力の FLOTILLA_CHECK {...}。

const OUT_DIR := "res://artifacts/sudden_death_v2/sky_gate_flotilla/"
const DT := 1.0 / 60.0

var case_name := "finale"
var quality := "high"
var debug: SkyGateDebug
var checks := 0
var failures: Array[String] = []
var shots: Array[String] = []
var max_counts := {}
var notes := {}
var step_cost := {}


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair[0] == "case" and pair.size() > 1:
			case_name = pair[1]
		elif pair[0] == "quality" and pair.size() > 1:
			quality = pair[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _run() -> void:
	debug = SkyGateDebug.new()
	debug.manual = true
	debug.quality = quality
	debug.autopilot = {1: "right", 2: "wrong" if case_name == "finale" else "right"}
	add_child(debug)
	debug.build()
	await _frames(3)
	var flotilla := debug.presenter.flotilla()
	check(flotilla != null, "the flotilla is built")
	if flotilla == null:
		_finish()
		return
	check(flotilla.boats.size() == SkyGateFlotilla.BOATS.size(), "%d boats" % SkyGateFlotilla.BOATS.size())
	check(flotilla.spectator_count >= 60, "spectators aboard (%d)" % flotilla.spectator_count)
	var clearance := SkyGateFlotilla.corridor_clearance(flotilla.layout())
	notes["corridor_margin"] = snappedf(clearance, 0.01)
	check(clearance >= 0.0, "boats keep clear of the floatplane's path (margin %.1f m)" % clearance)
	var edge := SkyGateFlotilla.nearest_edge(flotilla.layout())
	notes["nearest_edge"] = snappedf(edge, 0.01)
	check(edge >= SkyGateFlotilla.CAMERA_CLEAR, "boats stay outside the camera's circle round the float (%.1f m)" % edge)
	_check_seats(flotilla)
	await _advance_until(func() -> bool: return debug.clock > 1.0, 120)
	debug.presenter.confirm_rules()
	if case_name == "round":
		await _case_round(flotilla)
	else:
		await _case_finale(flotilla)
	_finish()


func _finish() -> void:
	print("FLOTILLA_CHECK ", JSON.stringify({"case": case_name, "quality": quality, "checks": checks, "failures": failures,
		"shots": shots, "max": max_counts, "notes": notes,
		"step_ms": {"show": _avg_ms("show"), "calm": _avg_ms("calm")},
		"flotilla": debug.presenter.flotilla().get_debug_snapshot() if debug != null and debug.presenter.flotilla() != null else {}}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _avg_ms(key: String) -> float:
	var cost: Array = step_cost.get(key, [0, 0])
	return snappedf(float(cost[0]) / maxf(float(cost[1]), 1.0) / 1000.0, 0.01)


# ------------------------------------------------------------------ cases

func _case_finale(flotilla: SkyGateFlotilla) -> void:
	var presenter := debug.presenter
	await _advance_until(func() -> bool: return presenter.phase_name() == "finish", 2400)
	check(presenter.phase_name() == "finish", "P1 wins at the first gate")
	await _advance_until(func() -> bool: return flotilla.cue_state().kind == SkyGateFlotilla.CUE_ANTICIPATE, 1800)
	check(flotilla.cue_state().kind == SkyGateFlotilla.CUE_ANTICIPATE, "the crowd leans in before the touchdown")
	await _advance_frames(50)
	await _shot("finale_01_descend")
	await _advance_until(func() -> bool: return flotilla.is_showing(), 600)
	check(flotilla.is_showing(), "the show starts at the touchdown")
	await _advance_frames(24)
	await _shot("finale_02_poppers")
	_check_boats_in_view(flotilla, 2, "landing orbit")
	await _advance_frames(40)
	var snap := flotilla.get_debug_snapshot()
	check(int(snap.poppers) >= SkyGateFlotilla.BOATS.size() * SkyGateFlotilla.POPPERS_PER_BOAT,
		"every boat pops crackers (%d)" % int(snap.poppers))
	check(int(snap.shells) >= 3, "the first salvo is up (%d)" % int(snap.shells))
	await _advance_frames(50)
	await _shot("finale_03_first_bursts")
	await _advance_until(func() -> bool: return presenter.phase_name() == "dance", 900)
	check(presenter.phase_name() == "dance", "the winner dances")
	# 歓声：ダンスの 2 秒（判定の歓声から勝者のファンの歓声へ替わる 0.6 秒のくぼみを含む）の間、いちばん強い所
	var cheer := 0.0
	for _i in range(130):
		_step()
		var cue := flotilla.cue_state()
		if int(cue.kind) in [SkyGateFlotilla.CUE_VERDICT, SkyGateFlotilla.CUE_GOAL]:
			cheer = maxf(cheer, float(cue.weight))
	await _frames(2)
	await _shot("finale_04_dance")
	check(cheer > 0.9, "the crowd cheers through the dance (%.2f)" % cheer)
	await _advance_until(func() -> bool: return float(flotilla.get_debug_snapshot().show_t) >= SkyGateFlotilla.FINALE_AT + 1.45, 900)
	await _shot("finale_05_finale")
	await _overview("finale_06_overview")
	snap = flotilla.get_debug_snapshot()
	check(int(snap.shells) >= 12, "the show keeps going through the dance (%d shells)" % int(snap.shells))
	var picks := int(snap.in_view) + int(snap.fallback)
	check(picks > 0 and float(snap.in_view) / float(picks) >= 0.8, "bursts are picked inside the camera's view (%d / %d)" % [int(snap.in_view), picks])
	check(int(max_counts.get("Sparks", 0)) >= 100, "fireworks sparks are drawn (max %d)" % int(max_counts.get("Sparks", 0)))
	check(int(max_counts.get("Streamers", 0)) >= 60, "crackers' streamers are drawn (max %d)" % int(max_counts.get("Streamers", 0)))
	check(int(max_counts.get("Smoke", 0)) >= 10, "daylight smoke is drawn (max %d)" % int(max_counts.get("Smoke", 0)))
	# 迎え：新しい花火は止まり、上がっているものが終われば何も残らない
	presenter.release_avatar(presenter.winner())
	check(not flotilla.is_showing(), "the show stops at the pickup")
	var shells := int(flotilla.get_debug_snapshot().shells)
	await _advance_frames(540)
	check(int(flotilla.get_debug_snapshot().shells) == shells, "no new shell after the pickup")
	check(not flotilla.fireworks.is_playing(), "the last fireworks die out")
	check(float(flotilla.cue_state().weight) < 0.05, "the crowd calms down after the pickup")


func _case_round(flotilla: SkyGateFlotilla) -> void:
	var presenter := debug.presenter
	await _advance_until(func() -> bool: return presenter.phase_name() == "round_land", 4800)
	check(presenter.phase_name() == "round_land", "both clear ROUND 1")
	await _advance_until(func() -> bool: return flotilla.is_showing(), 1200)
	check(flotilla.is_showing(), "the round show starts at the touchdown")
	await _advance_frames(24)
	await _shot("round_01_poppers")
	_check_boats_in_view(flotilla, 2, "round landing")
	await _advance_frames(110)
	await _shot("round_02_bursts")
	await _advance_frames(80)
	var snap := flotilla.get_debug_snapshot()
	check(int(snap.shells) == SkyGateFlotilla.ROUND_SHELLS.size(), "the round show is %d shells (%d)" % [SkyGateFlotilla.ROUND_SHELLS.size(), int(snap.shells)])
	check(not flotilla.is_showing(), "the round show ends by itself")
	await _advance_until(func() -> bool: return presenter.phase_name() == "countdown", 900)
	check(presenter.phase_name() == "countdown", "the next round starts")
	check(not flotilla.fireworks.is_playing(), "the next round clears the fireworks")


# ------------------------------------------------------------------ checks

## 座席の観客が船の上（船の箱の中）にいて、着地台の方（+Z）を向いている。
func _check_seats(flotilla: SkyGateFlotilla) -> void:
	var outside := 0
	var facing_bad := 0
	for i in range(flotilla.boats.size()):
		var boat := flotilla.boats[i]
		var box: Array = ((flotilla.layout().boats as Dictionary)[str(flotilla.boat_info[i].type)] as Dictionary).aabb
		var aabb := AABB(Vector3(float(box[0][0]), float(box[0][1]), float(box[0][2])), Vector3.ZERO).expand(
			Vector3(float(box[1][0]), float(box[1][1]), float(box[1][2])))
		for person: Dictionary in flotilla.boat_info[i].people:
			if not aabb.has_point(person.hip):
				outside += 1
		var to_float := (flotilla.global_position - boat.global_position).normalized()
		if (boat.global_basis.z.normalized()).dot(to_float) < 0.95:
			facing_bad += 1
	check(outside == 0, "every spectator sits inside the boat (%d outside)" % outside)
	check(facing_bad == 0, "every boat faces the float with its seats (%d wrong)" % facing_bad)


func _check_boats_in_view(flotilla: SkyGateFlotilla, need: int, label: String) -> void:
	var seen := 0
	for boat: Node3D in flotilla.boats:
		if debug.camera.is_position_in_frustum(boat.global_position + Vector3.UP * 1.5):
			seen += 1
	notes["boats_in_view_" + label] = seen
	check(seen >= need, "%s: at least %d boats in the picture (%d)" % [label, need, seen])


# ------------------------------------------------------------------ stepping and shots

func _step() -> void:
	var flotilla := debug.presenter.flotilla()
	var start := Time.get_ticks_usec()
	debug.step_frame(DT)
	# 1 フレームの CPU の時間（見せ方まるごと）：祝いの間とそれ以外の平均
	var phase := "show" if flotilla != null and (flotilla.is_showing() or flotilla.fireworks.is_playing()) else "calm"
	var cost: Array = step_cost.get(phase, [0, 0])
	step_cost[phase] = [int(cost[0]) + Time.get_ticks_usec() - start, int(cost[1]) + 1]
	if flotilla != null and flotilla.fireworks != null:
		var counts := flotilla.fireworks.live_counts()
		for key: String in counts:
			max_counts[key] = maxi(int(max_counts.get(key, 0)), int(counts[key]))


func _advance_until(cond: Callable, limit: int) -> void:
	var n := 0
	while not cond.call() and n < limit:
		_step()
		n += 1
		if n % 4 == 0:
			await get_tree().process_frame
	await get_tree().process_frame


func _advance_frames(count: int) -> void:
	for i in range(count):
		_step()
		if i % 4 == 0:
			await get_tree().process_frame
	await get_tree().process_frame


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "%s_%s.png" % [quality, shot_name])
	shots.append(shot_name)


## 高い所から着地台と船の並びを見下ろす画（並びの確かめ）。撮ったらカメラは次の step_frame で元に戻る。
func _overview(shot_name: String) -> void:
	var center := debug.presenter.flotilla().global_position
	var eye := center + Vector3(0.0, 62.0, -58.0)
	debug.camera.global_transform = Transform3D(Basis.looking_at(center - eye, Vector3.UP), eye)
	debug.camera.fov = 50.0
	await _shot(shot_name)

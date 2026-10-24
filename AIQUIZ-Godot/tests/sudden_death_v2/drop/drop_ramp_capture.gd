extends Node

## スカイゲートの人の動き（DropMotion、W3）を実際の描画（Forward+）で確かめる画を撮る。空と海の上に仮のスロープ（箱）を置く。
##   Godot --path . --resolution 1280x720 --fixed-fps 30 --script res://tests/sudden_death_v2/drop/drop_ramp_capture_bootstrap.gd -- case=pair seed=3
##   （pair は jumps=SD_Jump_Basic_A,SD_Jump_Superman で 2 人の降り方を決められる。tag=名前 で出力のフォルダを分ける）
## case:
##   pair  本物のアバター（StagingPuppet・SLOT_DROP）2 人が歩く → 駆け出す → 端で飛ぶ（0.4 秒ずらす。降り方は choose_pair）
##   all   人形（build_player_skeleton）で 10 種類の降り方を 1 つずつ（端の前後と腹ばいに落ち着くまで）
##   land  人形で帰還の着地 3 通り（4 m の段から下の床へ）
##   cabin 本物のアバター 2 人がベンチで向かい合う：座る → ベルト → ベルトを外して立つ
## 出力：artifacts/sudden_death_v2/drop_motion/<case>[_<tag>]/（*.png と report.json）。pair は端を離れる位置と腹ばいの向きも確かめる。

const StageScript = preload("res://scripts/world/stage_environment.gd")
const PlayerControllerScript = preload("res://scripts/world/player_controller.gd")
const OUT_ROOT := "res://artifacts/sudden_death_v2/drop_motion/"
## 仮のスロープの上面の高さ（海の上）。端は z = 0、走る向きは +Z。
const H := 60.0
const RAMP_LEN := 3.2
const RAMP_W := 3.1
const STEP := 1.0 / 30.0
const WALK_TIME := 0.6
const FALL_SPEED := 9.0

var scenario := "pair"
var seed_value := 3
var tag := ""
var out := OUT_ROOT
var stage: Node3D
var camera: Camera3D
var props: Node3D
var checks := 0
var failures: Array[String] = []
var report := {}
var shots: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("case="):
			scenario = arg.trim_prefix("case=")
		elif arg.begins_with("seed="):
			seed_value = int(arg.trim_prefix("seed="))
		elif arg.begins_with("tag="):
			tag = arg.trim_prefix("tag=")
	out = OUT_ROOT + scenario + ("_" + tag if not tag.is_empty() else "") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	_build_world()
	await _frames(10)
	match scenario:
		"pair":
			await _case_pair()
		"all":
			await _case_all()
		"land":
			await _case_land()
		"cabin":
			await _case_cabin()
	report["case"] = scenario
	report["shots"] = shots
	report["checks"] = checks
	report["failures"] = failures
	var f := FileAccess.open(out + "report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	print("DROP_RAMP_CAPTURE ", JSON.stringify({"case": scenario, "checks": checks, "failures": failures, "shots": shots.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ world

func _build_world() -> void:
	stage = StageScript.new()
	add_child(stage)
	stage.build(stage.gameplay_build_config())
	# 空・太陽・海だけ残す（空のセットと同じく、本編の舞台は隠す）
	for child: Node in stage.get_children():
		if child is Node3D and not (String(child.name) in ["DirectionalLight3D", "Ocean"]):
			(child as Node3D).visible = false
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 55.0
	add_child(camera)
	camera.make_current()
	props = Node3D.new()
	props.name = "Props"
	add_child(props)


func _box(size: Vector3, center: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = center
	props.add_child(node)
	return node


## 機内の床（後ろ 8 m）とスロープ（3.2 m、端に黄色の線）。上面は y = H。
func _ramp(width := RAMP_W) -> void:
	_box(Vector3(width, 0.25, RAMP_LEN), Vector3(0, H - 0.125, -RAMP_LEN * 0.5), Color(0.42, 0.45, 0.48))
	_box(Vector3(width, 0.252, 0.12), Vector3(0, H - 0.125, -0.06), Color(0.95, 0.78, 0.15))
	_box(Vector3(width + 0.9, 0.25, 8.0), Vector3(0, H - 0.125, -RAMP_LEN - 4.0), Color(0.33, 0.35, 0.37))
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.2, 3.4, 8.0), Vector3(side * (width * 0.5 + 0.55), H + 1.7, -RAMP_LEN - 4.0), Color(0.55, 0.57, 0.6))


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out + name + ".png"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	shots.append(path)


func _look(eye: Vector3, target: Vector3) -> void:
	camera.look_at_from_position(eye, target, Vector3.UP)


func _players() -> PlayerController:
	var gs := QuizGameState.new()
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.game_state = Constants.STATE_MENU
	gs.p1_alive = true
	gs.p2_alive = true
	var holder := Node3D.new()
	holder.set_script(PlayerControllerScript)
	holder.name = "DropPlayers"
	add_child(holder)
	var players := holder as PlayerController
	players.call("_sync_player_model_count", gs)
	if players.p2_container != null:
		players.p2_container.position = Vector3.ZERO
	return players


func _doll(is_p1: bool) -> Dictionary:
	var root := Node3D.new()
	props.add_child(root)
	return EmoteBlockmanPreview.build_player_skeleton(is_p1, root, HatData.HAT_NONE)


func _pelvis(parts: Dictionary) -> Vector3:
	return (parts["pelvis"] as Node3D).global_position


func _front_z(parts: Dictionary) -> float:
	var front := -INF
	for key: String in DropMotion.FOOT_MESH_KEYS:
		var mesh := parts.get(key) as MeshInstance3D
		if mesh == null:
			continue
		var aabb := mesh.get_aabb()
		for c in range(8):
			front = maxf(front, (mesh.global_transform * aabb.get_endpoint(c)).z)
	return front


# ------------------------------------------------------------------ pair（本物のアバター 2 人）

## 1 人ぶんの段取り：歩く → 駆け出す（端の手前で降り方の始まりの位相に合わせる）→ 降り方 → 腹ばいで落ち続ける。
func _plan(jump: String, x: float, start: float) -> Dictionary:
	var info := DropMotion.clip_info(jump)
	var run: Dictionary = DropMotion.clip_info(DropMotion.RAMP_RUN_OUT)
	var run_time := float(run.length) + float(info.get("run_phase", 0.0))
	var jump_origin := Vector3(x, H, -float(info.edge))
	var run_origin := jump_origin - Vector3(0, 0, DropMotion.root_offset(DropMotion.RAMP_RUN_OUT, run_time).z)
	var walk_origin := run_origin - Vector3(0, 0, DropMotion.root_offset(DropMotion.RAMP_WALK, WALK_TIME).z)
	return {
		"jump": jump, "info": info, "start": start, "run_time": run_time,
		"t_run": start + WALK_TIME, "t_jump": start + WALK_TIME + run_time,
		"walk": Transform3D(Basis.IDENTITY, walk_origin), "run": Transform3D(Basis.IDENTITY, run_origin),
		"jump_frame": Transform3D(Basis.IDENTITY, jump_origin), "segment": "",
	}


func _drive_puppet(puppet: StagingPuppet, plan: Dictionary, t: float) -> String:
	var info: Dictionary = plan.info
	var clip := DropMotion.RAMP_WALK
	var local := 0.0
	var frame: Transform3D = plan.walk
	var end := float(plan.t_jump) + float(info.length)
	if t < float(plan.start):
		local = 0.0
	elif t < float(plan.t_run):
		local = t - float(plan.start)
	elif t < float(plan.t_jump):
		clip = DropMotion.RAMP_RUN_OUT
		local = t - float(plan.t_run)
		frame = plan.run
	elif t < end:
		clip = String(plan.jump)
		local = t - float(plan.t_jump)
		frame = plan.jump_frame
	else:
		# 降り方のあとは腹ばいのループ（同じ位相）で落ち続ける
		clip = DropMotion.BOX_LOOP
		var after := t - end
		local = float(info.length) - float(info.settle) + after
		var base: Vector3 = (plan.jump_frame as Transform3D) * DropMotion.root_offset(String(plan.jump), float(info.length))
		frame = Transform3D(Basis.IDENTITY, base + Vector3(0, -FALL_SPEED * after, 0.6 * after))
	if clip != String(plan.segment):
		if not String(plan.segment).is_empty() and clip != DropMotion.BOX_LOOP:
			puppet.begin_blend(0.12)
		plan.segment = clip
	if clip == DropMotion.BOX_LOOP:
		DropMotion.pose_puppet(puppet, clip, local)
		var pelvis := puppet.parts()["pelvis"] as Node3D
		pelvis.global_transform = Transform3D(pelvis.basis, frame.origin + Vector3(0, pelvis.position.y - DropMotion.BASE_Y, 0))
	else:
		DropMotion.place_puppet(puppet, clip, local, frame)
	puppet.apply_blend(STEP)
	return clip


func _case_pair() -> void:
	_ramp()
	var players := _players()
	var puppets: Array[StagingPuppet] = [StagingPuppet.new(players, 1), StagingPuppet.new(players, 2)]
	await _frames(3)
	for p: StagingPuppet in puppets:
		check(p.is_ready(), "puppet %d ready" % p.index)
		p.set_visible(true)
		var length := p.clip_length(DropMotion.BOX_LOOP, AnimationRig.SLOT_DROP)
		check(length > 0.0, "puppet %d plays SD_* clips from AnimationRig.SLOT_DROP (%.2f s)" % [p.index, length])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var last := {}
	var first := 1 + rng.randi_range(0, 1)
	var pair := DropMotion.choose_pair(rng, last, first)
	# 確認の画は毎回同じ組にしたいとき：jumps=SD_Jump_Superman,SD_Jump_Salute
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("jumps="):
			var names := arg.trim_prefix("jumps=").split(",")
			pair = {first: names[0], 3 - first: names[1]}
	report["first"] = first
	report["jumps"] = pair
	var plans := {}
	for p: int in [1, 2]:
		# P1 は画面の左（後ろから見て +X）
		plans[p] = _plan(String(pair[p]), 0.75 if p == 1 else -0.75, 0.0 if p == first else DropMotion.JUMP_STAGGER)
	var second := 3 - first
	var leave1 := float(plans[first].t_jump) + float(plans[first].info.leave)
	var leave2 := float(plans[second].t_jump) + float(plans[second].info.leave)
	var settle2 := float(plans[second].t_jump) + float(plans[second].info.settle)
	var settle1 := float(plans[first].t_jump) + float(plans[first].info.settle)
	var marks := {
		"01_walk": 0.25, "02_run": float(plans[first].t_run) + 0.3, "03_leave_first": leave1, "04_leave_second": leave2,
		"05_air": (leave2 + settle1) * 0.5, "06_settled": maxf(settle1, settle2) + 0.1, "07_topdown": maxf(settle1, settle2) + 0.6,
	}
	report["times"] = {"leave": {first: leave1, second: leave2}, "settle": {first: settle1, second: settle2}}
	var measured := {}
	var t := 0.0
	var done := {}
	var end := float(marks["07_topdown"]) + STEP
	while t <= end:
		for p: int in [1, 2]:
			_drive_puppet(puppets[p - 1], plans[p], t)
		# 端を離れる瞬間：足の先がスロープの端（z = 0）にある
		for p: int in [1, 2]:
			var leave := float(plans[p].t_jump) + float(plans[p].info.leave)
			if absf(t - leave) < STEP * 0.5 and not measured.has("edge_%d" % p):
				var front := _front_z(puppets[p - 1].parts())
				measured["edge_%d" % p] = front
				check(absf(front) < 0.35, "P%d leaves with the toes at the edge (front z %.2f)" % [p, front])
			var settle := float(plans[p].t_jump) + float(plans[p].info.settle)
			if absf(t - settle) < STEP * 0.5 and not measured.has("belly_%d" % p):
				var pelvis := puppets[p - 1].parts()["pelvis"] as Node3D
				var front_y := pelvis.global_basis.z.normalized().y
				var head_z := pelvis.global_basis.y.normalized().z
				measured["belly_%d" % p] = [front_y, head_z]
				check(front_y < -0.85 and head_z > 0.85, "P%d belly down, head forward at settle (%.2f, %.2f)" % [p, front_y, head_z])
		# カメラ：機内から背中を追って機外へ出て、腹ばいになったら見下ろしへ（heli_drop.md 3.1）
		var a := _pelvis(puppets[0].parts())
		var b := _pelvis(puppets[1].parts())
		var mid := (a + b) * 0.5
		var down := clampf((t - leave1) / maxf(settle2 - leave1 + 0.6, 0.1), 0.0, 1.0)
		var k := smoothstep(0.0, 1.0, down)
		# 2 人が離れるほど引く
		var spread := clampf(a.distance_to(b) / 2.2, 1.0, 4.0)
		var eye := mid + Vector3(0.0, 1.5, -4.6).lerp(Vector3(0.0, 7.5, -2.2), k) * spread
		_look(eye, mid + Vector3(0.0, -0.3, 2.5).lerp(Vector3(0.0, -1.0, 0.6), k))
		await get_tree().process_frame
		for name: String in marks:
			if not done.has(name) and t >= float(marks[name]) - STEP * 0.5:
				done[name] = true
				await _capture(name)
		t += STEP
	report["measured"] = measured


# ------------------------------------------------------------------ all（人形で 10 種類）

func _case_all() -> void:
	_ramp(4.0)
	var clips: Array[String] = DropMotion.BASIC_JUMPS + DropMotion.SPECIAL_JUMPS
	var doll := _doll(true)
	await _frames(3)
	var table := {}
	for clip: String in clips:
		var info := DropMotion.clip_info(clip)
		var frame := Transform3D(Basis.IDENTITY, Vector3(0, H, -float(info.edge)))
		var leave := float(info.leave)
		var settle := float(info.settle)
		var times := {"a": maxf(leave - 0.25, 0.0), "b": leave, "c": leave + 0.2, "d": leave + 0.45, "e": leave + 0.75, "f": settle}
		for key: String in times:
			var t := float(times[key])
			DropMotion.place_doll(doll, clip, t, frame)
			var pelvis := _pelvis(doll)
			_look(pelvis + Vector3(3.6, 1.1, 1.6), pelvis + Vector3(0, -0.15, 0.2))
			await _frames(2)
			await _capture("%s_%s" % [clip, key])
		table[clip] = {"leave": leave, "settle": settle, "delay": settle - leave, "edge": float(info.edge)}
		check(settle - leave <= DropMotion.SETTLE_LIMIT + 0.0001, "%s settles %.2f s after leaving" % [clip, settle - leave])
	report["clips"] = table


# ------------------------------------------------------------------ land（人形で着地 3 通り）

func _case_land() -> void:
	_box(Vector3(3.1, 0.25, 3.2), Vector3(0, H - 0.125, -1.6), Color(0.42, 0.45, 0.48))
	_box(Vector3(8.0, 0.3, 12.0), Vector3(0, H - 4.0 - 0.15, 4.0), Color(0.36, 0.55, 0.42))
	var doll := _doll(true)
	await _frames(3)
	var table := {}
	for clip: String in DropMotion.LANDINGS:
		var info := DropMotion.clip_info(clip)
		var frame := Transform3D(Basis.IDENTITY, Vector3(0, H, -float(info.edge)))
		var leave := float(info.leave)
		var land := float(info.land)
		var length := float(info.length)
		var times := {"a": leave, "b": (leave + land) * 0.5, "c": land, "d": land + 0.25, "e": land + 0.7, "f": length - 0.4}
		for key: String in times:
			var t := float(times[key])
			DropMotion.place_doll(doll, clip, t, frame)
			var pelvis := _pelvis(doll)
			_look(pelvis + Vector3(4.2, 0.9, 1.4), pelvis + Vector3(0, -0.3, 0.3))
			await _frames(2)
			await _capture("%s_%s" % [clip, key])
		# 着地のあとは足の裏が下の床（H - 4）にある
		DropMotion.place_doll(doll, clip, land + 0.5, frame)
		var lowest := DropMotion._lowest_along(doll, Vector3.UP)
		check(absf(lowest - (H - float(info.drop))) < 0.08, "%s stands on the floor 4 m below (%.2f)" % [clip, lowest - H])
		table[clip] = {"leave": leave, "land": land, "lowest_after_land": lowest - H}
	report["clips"] = table


# ------------------------------------------------------------------ cabin（本物のアバター 2 人がベンチで向かい合う）

func _case_cabin() -> void:
	_box(Vector3(4.04, 0.25, 8.0), Vector3(0, H - 0.125, 0), Color(0.38, 0.4, 0.42))
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.2, 3.7, 8.0), Vector3(side * 2.12, H + 1.85, 0), Color(0.55, 0.57, 0.6))
	var players := _players()
	var puppets: Array[StagingPuppet] = [StagingPuppet.new(players, 1), StagingPuppet.new(players, 2)]
	await _frames(3)
	# P1 は機体の右の壁（+X）に座って通路（-X）を向く。P2 は向かい（c130_float.md 第5章）
	var frames := {
		1: Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(1.45, H, 0.0)),
		2: Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-1.45, H, 0.0)),
	}
	for p: StagingPuppet in puppets:
		p.set_visible(true)
		DropMotion.place_puppet(p, DropMotion.BENCH_SIT, 0.0, frames[p.index])
	await _frames(1)
	# 座面：ももの下の高さ
	for p: StagingPuppet in puppets:
		var parts := p.parts()
		var low := INF
		for key: String in ["l_thigh", "r_thigh", "lower_torso"]:
			var mesh := parts.get(key) as MeshInstance3D
			if mesh == null:
				continue
			var aabb := mesh.get_aabb()
			for c in range(8):
				low = minf(low, (mesh.global_transform * aabb.get_endpoint(c)).y)
		var seat := (frames[p.index] as Transform3D).origin
		_box(Vector3(0.5, low - H, 6.0), Vector3(seat.x + signf(seat.x) * 0.1, H + (low - H) * 0.5, 0), Color(0.72, 0.16, 0.14))
		report["seat_height_%d" % p.index] = low - H
	var timeline := [
		[0.0, DropMotion.BENCH_SIT], [1.0, DropMotion.BENCH_BELT], [2.3, DropMotion.BENCH_SIT], [3.0, DropMotion.BENCH_UNBUCKLE],
	]
	var marks := {"01_sit": 0.6, "02_belt_reach": 1.35, "03_belt_click": 1.8, "04_unbuckle": 3.3, "05_stand_up": 3.75, "06_standing": 4.5}
	var t := 0.0
	var done := {}
	var segment := ""
	while t <= 4.6:
		var clip := DropMotion.BENCH_SIT
		var start := 0.0
		for row: Array in timeline:
			if t >= float(row[0]):
				clip = String(row[1])
				start = float(row[0])
		for p: StagingPuppet in puppets:
			if clip != segment and not segment.is_empty():
				p.begin_blend(0.15)
			DropMotion.place_puppet(p, clip, t - start, frames[p.index])
			p.apply_blend(STEP)
		segment = clip
		_look(Vector3(0.0, H + 2.4, -4.2), Vector3(0.0, H + 0.6, 1.5))
		await get_tree().process_frame
		for name: String in marks:
			if not done.has(name) and t >= float(marks[name]) - STEP * 0.5:
				done[name] = true
				await _capture(name)
		t += STEP

extends "res://tests/hud_diegetic_mock/lockon3d_runtime.gd"

## 新仕様「照準を体に合わせ続けるとロックオン → 自動追従で発射」のイメージ映像用モック（A 3D ボックスがベース）。
## 箱は 1 つだけで、回り続けたままロックオンまでを次の順に見せる:
##   1. 照準が体に重なっている間だけ溜まる。回りながら縮み、回転がだんだん速くなる。
##   2. ロックの大きさ（TARGET_HALF）まで縮んだら、ゆっくりの回転まで減速する。
##   3. 回りながら、角が足元から 1 つずつカチッと赤くなっていく（チャージ）。
##   4. 8 つそろうとロックオン。箱が弾んで一気に速く回り、「LOCK ON」が点滅して出てすぐ消える。
##   5. ロック中は照準が自動で体に付いていき、ボタンを押すだけで追尾突進。
##      赤は時間とともに薄れて元の色に戻り、戻りきるとロックが切れて元の大きさ・回転に戻る。
## 外れると溜まった分は逆の順に戻っていく（角の赤が消え、速く回り、広がる）。
## 突進の追尾は、サメの進む向きを毎フレーム生存プレイヤーへ曲げて再現する（曲がる速さに上限あり）。
## 実行: Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 60 --write-movie <out.avi> --script res://tests/hud_diegetic_mock/lockon_homing_bootstrap.gd

const LOCK_TIME := 1.6
const LOCK_DECAY_TIME := 1.2
## ロックが続く時間。この間に赤が元の色へ戻っていく。
const LOCK_HOLD := 4.0
## ロックが切れたあと、次に溜まり始めるまでの待ち。
const LOCK_REARM := 1.0
## 溜まり具合の区切り: ここまで縮む → ここまでに減速する → 残りで角が 1 つずつ赤くなる。
const SHRINK_END := 0.4
const SLOW_END := 0.55
const LOCK_COLOR := Color(1.0, 0.26, 0.34)
## ゲームの照準の速さ（AIM_SPEED）と同じ。
const TRACK_SPEED := 9.0
## 追尾突進が 1 秒に曲がれる角度（ラジアン）。避ける余地を残すため上限を付ける。
const HOMING_TURN_RATE := 2.4
const TARGET_HALF := Vector3(0.7, 0.88, 0.7)
## 回転の速さ（度/秒）: ふだん / 縮みきる直前 / チャージ中 / ロック直後。
const IDLE_SPIN := 28.0
const FAST_SPIN := 420.0
const CHARGE_SPIN := 70.0
const LOCKED_SPIN := 330.0
const LABEL_TIME := 0.6
const ARM := 0.3
const THICK := 0.06
## 角が赤くなる順番。足元の 4 つを一周してから頭の上の 4 つ（layout_box の並び: sx*4 + sy*2 + sz）。
const CORNER_ORDER: Array[int] = [0, 4, 5, 1, 2, 6, 7, 3]

var lock_progress := 0.0
var locked := false
var lock_age := 0.0
var rearm := 0.0
var homing := false
var combo_at_fire := 0
var was_overlapping := false
var box_root: Node3D
var bars: Array[MeshInstance3D] = []
var corner_materials: Array[StandardMaterial3D] = []
var corner_xrays: Array[StandardMaterial3D] = []
var corner_on: Array[bool] = []
var corner_pop: Array[float] = []
var lock_label: Label3D
var current_half := Vector3.ONE
var yaw := 0.0
var spin_speed := IDLE_SPIN
var punch := 0.0
var label_age := -1.0
var shatter_age := -1.0
var clock := 0.0

func run() -> void:
	await setup_world()
	if not await enter_ghost_aiming():
		return
	ghost.set("_combo", 0)
	survivor = 1 if gs.p1_alive else 2
	hide_hud = true
	clear_mock()
	camera = get_viewport().get_camera_3d()
	hide_original_aim()
	build_live_hp_ring()
	build_live_lockon()
	frame_root.visible = false
	build_box()
	await frames(2)
	event("RECORD_START")
	await homing_demo()
	event("RECORD_END")
	get_tree().quit(0)

# --- 流れ ---

func homing_demo() -> void:
	# 照準は床の上（体から外れている）。箱はゆっくり回るだけで、ロックは溜まらない。
	await track_aim(func() -> Vector2: return survivor_offset() + Vector2(-3.2, 2.6), 60, 6.0)
	await track_aim(func() -> Vector2: return ghost.get("_aim_offset"), 20, 6.0)
	# 体に重ねると溜まり始める。生存側が中央へ逃げても、ゴーストは追いかけて重ね続ける。
	await track_aim(survivor_offset, 45, TRACK_SPEED)
	await track_aim(survivor_offset, 12, TRACK_SPEED)
	var inward := center_key()
	key(inward, true)
	await track_aim(survivor_offset, 18, TRACK_SPEED)
	key(inward, false)
	# 切り返し: ゴーストが行き過ぎて外れると、溜まった分が戻っていく。
	var outward := KEY_A if inward == KEY_D else KEY_D
	var overshoot := Vector2(-2.4, 0.0) if inward == KEY_D else Vector2(2.4, 0.0)
	key(outward, true)
	await track_aim(func() -> Vector2: return survivor_offset() + overshoot, 14, TRACK_SPEED)
	key(outward, false)
	await track_aim(func() -> Vector2: return ghost.get("_aim_offset"), 8, TRACK_SPEED)
	# 立て直して重ね直し、今度は外さずにロックまで追い続ける。
	await acquire(260, inward)
	# 1 回目: 撃たずに待つ。照準は自動で付いていき、赤が薄れて元の枠に戻るとロックが切れる。
	await frames(30)
	var run_key := center_key()
	key(run_key, true)
	await frames(24)
	key(run_key, false)
	for i in range(int(LOCK_HOLD * 60.0) + 30):
		if not locked:
			break
		await frames(1)
	await frames(10)
	# 2 回目: 待ちが明けたら重ね直してロックし、ボタンだけで追尾突進。
	await acquire(300, inward)
	await frames(50)
	event("FIRE")
	key(KEY_CTRL, true)
	await frames(3)
	key(KEY_CTRL, false)
	await wait_phase(ghost.Phase.CHARGING, 60)
	event("DASH")
	# 生存側は見てから横へ避けるが、サメが曲がって追いかける。
	var dodge_key := center_key()
	key(dodge_key, true)
	await frames(20)
	key(dodge_key, false)
	for i in range(150):
		await frames(1)
		if shatter_age >= 0.0:
			event("HIT combo=%d" % int(ghost.get("_combo")))
			break
	await frames(90)

## ロックするまで照準を体に重ね続ける。途中で生存側が少し動く。
func acquire(limit: int, move_key: int) -> void:
	for i in range(limit):
		if locked:
			break
		if i == 40:
			key(move_key, true)
		if i == 54:
			key(move_key, false)
		await track_aim(survivor_offset, 1, TRACK_SPEED)
	key(move_key, false)

## 照準を target へ動かす（ロック中は自動で付いていくので触らない）。
func track_aim(target: Callable, count: int, speed: float) -> void:
	for i in range(count):
		if ghost.phase == ghost.Phase.AIMING and not locked:
			var offset: Vector2 = ghost.get("_aim_offset")
			ghost.set("_aim_offset", offset.move_toward(target.call(), speed * STEP))
		await frames(1)

## コースの中央へ向かうキー（D は -X、A は +X）。
func center_key() -> int:
	return KEY_D if survivor_pelvis().global_position.x > 0.0 else KEY_A

# --- 組み立て ---

func build_box() -> void:
	box_root = Node3D.new()
	track(box_root, world)
	# 角ごとに色を変えるので、マテリアルは角ごとに持つ。
	for c in range(8):
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		material.roughness = 0.45
		material.metallic = 0.15
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		corner_materials.append(material)
		var xray := live_material(Color(GHOST_COLOR, 0.2), 1.0)
		xray.render_priority = 9
		corner_xrays.append(xray)
		corner_on.append(false)
		corner_pop.append(0.0)
	for k in range(24):
		var part := box(Vector3.ONE, corner_materials[k / 3])
		part.material_overlay = corner_xrays[k / 3]
		box_root.add_child(part)
		bars.append(part)
	lock_label = label("LOCK ON", 64, 0.0065, LOCK_COLOR, 22)
	lock_label.outline_modulate = Color(1.0, 1.0, 1.0, 0.95)
	lock_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lock_label.no_depth_test = true
	lock_label.render_priority = 12
	lock_label.visible = false
	world.add_child(lock_label)
	mock_nodes.append(lock_label)
	current_half = box_half(0.0, UNLOCKED_SPREAD)

# --- 毎フレームの更新 ---

func apply_frame(aim: Vector3, _power: float, spread: float, _color: Color, alpha: float, _show_guide: bool, phase: int) -> void:
	if box_root == null:
		return
	clock += STEP
	var pelvis := survivor_pelvis()
	var body := pelvis.global_position if pelvis != null else aim
	var charging := bool(ghost.get("_charging_input"))
	rearm = maxf(0.0, rearm - STEP)
	var overlapping := phase == ghost.Phase.AIMING and not charging and not locked and rearm <= 0.0 \
		and Vector2(aim.x - body.x, aim.z - body.z).length() < LOCK_DISTANCE
	update_lock(overlapping)
	if locked and phase in [ghost.Phase.AIMING, ghost.Phase.WINDUP]:
		# ロック中は照準が自動で体に付いていく。
		var offset: Vector2 = ghost.get("_aim_offset")
		ghost.set("_aim_offset", offset.lerp(survivor_offset(), 0.5))
		combo_at_fire = int(ghost.get("_combo"))
	if locked and phase == ghost.Phase.CHARGING:
		homing = true
	if homing and phase == ghost.Phase.CHARGING and shatter_age < 0.0:
		steer_shark(body)
	if homing and shatter_age < 0.0 and (int(ghost.get("_combo")) > combo_at_fire or phase == ghost.Phase.COOLDOWN):
		start_shatter()
	if shatter_age >= 0.0:
		update_shatter()
	else:
		update_box(aim, spread, alpha, phase)
	update_label()

func update_lock(overlapping: bool) -> void:
	if locked:
		lock_age += STEP
		# 撃たずに時間切れ: 赤が元の色に戻りきったところでロックを解く。
		if lock_age >= LOCK_HOLD and not homing:
			locked = false
			lock_progress = 0.0
			for c in range(8):
				corner_on[c] = false
			rearm = LOCK_REARM
			event("LOCK_EXPIRED")
		return
	if shatter_age >= 0.0:
		return
	var before := lock_progress
	lock_progress = clampf(lock_progress + (STEP / LOCK_TIME if overlapping else -STEP / LOCK_DECAY_TIME), 0.0, 1.0)
	if before == 0.0 and lock_progress > 0.0:
		event("ACQUIRE")
	if was_overlapping and not overlapping and lock_progress > 0.0:
		event("LOST progress=%.2f" % lock_progress)
	was_overlapping = overlapping
	# チャージ: 角が 1 つずつ赤くなる。8 つ目で溜まりきる（音程が上がっていく）。
	var charge := clampf((lock_progress - SLOW_END) / (1.0 - SLOW_END), 0.0, 1.0)
	for step in range(8):
		var c := CORNER_ORDER[step]
		var on := charge >= float(step + 1) / 8.0 - 0.001
		if on != corner_on[c]:
			corner_on[c] = on
			corner_pop[c] = 1.0 if on else 0.0
			if on and step < 7:
				AudioManager.play_sfx(&"ai_type_tick", 6.0, 0.85 + 0.1 * step)
	if lock_progress >= 1.0:
		locked = true
		lock_age = 0.0
		punch = 1.0
		label_age = 0.0
		AudioManager.play_sfx(&"lasso_cinch", 0.0, 1.15)
		AudioManager.play_sfx(&"ghost_revive_snap", 3.0, 1.1)
		event("LOCKED")

func update_box(aim: Vector3, spread: float, alpha: float, phase: int) -> void:
	var p := lock_progress
	# 大きさ: 溜まるほどロックの大きさへ縮む。ロック中はその大きさのまま。急に変わらないよう追いかける。
	var target := TARGET_HALF if locked else box_half(0.0, spread).lerp(TARGET_HALF, smoothstep(0.0, SHRINK_END, p))
	current_half = current_half.lerp(target, 0.22)
	punch = move_toward(punch, 0.0, STEP / 0.18)
	var half := current_half * (1.0 + 0.16 * punch * punch)
	# 回転: 縮みながら加速 → ロックの大きさでゆっくりまで減速 → その速さでチャージ → ロックで一気に速く。
	# ロック中の速い回転は、赤が元の色に戻るのに合わせて終わりぎわにふだんの速さへ落ちる。
	var desired := IDLE_SPIN
	var fade := clampf(lock_age / LOCK_HOLD, 0.0, 1.0)
	if locked:
		desired = lerpf(LOCKED_SPIN, IDLE_SPIN, smoothstep(0.6, 1.0, fade))
	elif p >= SLOW_END:
		desired = CHARGE_SPIN
	elif p >= SHRINK_END:
		desired = lerpf(FAST_SPIN, CHARGE_SPIN, smoothstep(0.0, 1.0, (p - SHRINK_END) / (SLOW_END - SHRINK_END)))
	elif p > 0.0:
		desired = lerpf(IDLE_SPIN, FAST_SPIN, p / SHRINK_END)
	# ロックした瞬間はすぐ速く、それ以外はなめらかに追いかける。
	spin_speed = desired if locked and lock_age < STEP * 1.5 else lerpf(spin_speed, desired, 0.15)
	if phase in [ghost.Phase.AIMING, ghost.Phase.WINDUP]:
		yaw += deg_to_rad(spin_speed) * STEP
	var pelvis := survivor_pelvis()
	var anchor := aim
	if locked and pelvis != null:
		anchor = Vector3(pelvis.global_position.x, aim.y, pelvis.global_position.z)
	box_root.visible = alpha > 0.01
	box_root.global_transform = Transform3D(Basis(Vector3.UP, yaw), anchor + Vector3(0.0, CENTER_Y, 0.0))
	# 角ごとの大きさ（赤くなった瞬間に弾む）と色。ロック後は赤が時間とともに薄れて元の色へ。
	var base_color := GHOST_COLOR.lerp(Color.WHITE, 0.25 * smoothstep(0.0, SHRINK_END, p))
	var red := LOCK_COLOR.lerp(GHOST_COLOR, smoothstep(0.0, 1.0, fade)) if locked else LOCK_COLOR
	var windup_flash := phase == ghost.Phase.WINDUP and int(clock / 0.05) % 2 == 0
	var k := 0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var c := k / 3
				corner_pop[c] = move_toward(corner_pop[c], 0.0, STEP / 0.22)
				var s := 1.0 + 0.9 * corner_pop[c] * corner_pop[c]
				var corner := Vector3(sx * half.x, sy * half.y, sz * half.z)
				var arm := ARM * s
				var thick := THICK * s
				bars[k].position = corner - Vector3(sx * arm * 0.5, 0.0, 0.0)
				bars[k].scale = Vector3(arm, thick, thick)
				bars[k + 1].position = corner - Vector3(0.0, sy * arm * 0.5, 0.0)
				bars[k + 1].scale = Vector3(thick, arm, thick)
				bars[k + 2].position = corner - Vector3(0.0, 0.0, sz * arm * 0.5)
				bars[k + 2].scale = Vector3(thick, thick, arm)
				var is_red := corner_on[c] or locked
				var color := red if is_red else base_color
				color = color.lerp(Color.WHITE, maxf(corner_pop[c], punch))
				if windup_flash:
					color = Color.WHITE
				var material := corner_materials[c]
				material.albedo_color = Color(color.darkened(0.1), alpha)
				material.emission = color
				material.emission_energy_multiplier = 1.3 if is_red else 0.5
				corner_xrays[c].albedo_color = Color(color, (0.3 if is_red else 0.22) * alpha)
				k += 3

## 「LOCK ON」はロックした瞬間に点滅しながら出て、すぐ消える。
func update_label() -> void:
	if label_age < 0.0:
		lock_label.visible = false
		return
	label_age += STEP
	if label_age >= LABEL_TIME:
		label_age = -1.0
		lock_label.visible = false
		return
	lock_label.visible = int(label_age / 0.075) % 2 == 0
	lock_label.global_position = box_root.global_position + Vector3(0.0, current_half.y + 0.5, 0.0)
	lock_label.scale = Vector3.ONE * (1.0 + 0.5 * pow(clampf(1.0 - label_age / 0.15, 0.0, 1.0), 2.0))

# --- 追尾突進と、当たったあとの砕け散り ---

func steer_shark(body: Vector3) -> void:
	var shark := ghost.get("_shark") as Node3D
	if shark == null or not is_instance_valid(shark):
		return
	var direction: Vector3 = shark.get("_ghost_charge_direction")
	var to_target := body - shark.global_position
	# 体を通り過ぎたら曲げない（U ターンはしない）。
	if to_target.length() < 0.6 or direction.dot(to_target.normalized()) < 0.2:
		return
	var desired := to_target.normalized()
	var angle := direction.angle_to(desired)
	if angle < 0.0001:
		return
	var turned := direction.slerp(desired, minf(1.0, HOMING_TURN_RATE * STEP / angle)).normalized()
	shark.set("_ghost_charge_direction", turned)
	shark.quaternion = shark.call("_quat_look_at", shark.position, shark.position + turned)
	ghost.set("_locked_direction", turned)

func start_shatter() -> void:
	shatter_age = 0.0
	locked = false
	homing = false
	lock_progress = 0.0
	for c in range(8):
		corner_on[c] = false
	AudioManager.play_sfx(&"ghost_revive_burst", -2.0, 1.2)

func update_shatter() -> void:
	shatter_age += STEP
	var t := clampf(shatter_age / 0.5, 0.0, 1.0)
	for bar in bars:
		var outward := bar.position.normalized() if bar.position.length() > 0.001 else Vector3.UP
		bar.position += outward * STEP * lerpf(6.0, 1.0, t)
		bar.rotate_object_local(Vector3(1.0, 0.6, 0.2).normalized(), STEP * 9.0)
	for material in corner_materials:
		material.albedo_color = Color(LOCK_COLOR.lerp(Color.WHITE, 0.4), 1.0 - t)
	if t >= 1.0:
		shatter_age = -1.0
		# 次に備えて元の形・大きさに戻す（照準の位置にまた現れる）。
		for bar in bars:
			bar.rotation = Vector3.ZERO
		current_half = box_half(0.0, UNLOCKED_SPREAD)
		spin_speed = IDLE_SPIN

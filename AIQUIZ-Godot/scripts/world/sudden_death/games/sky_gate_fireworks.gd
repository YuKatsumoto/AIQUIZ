class_name SkyGateFireworks
extends Node3D

## スカイゲートの着地の祝い（docs/sudden_death_v2/sky_gate.md 第9章）：観客船の打ち上げ花火と、観客のクラッカー（紙テープと紙吹雪）。
## SkyGateEffects と同じ作り：種類ごとに MultiMesh を 1 つ持ち、出ている効果を毎フレームまとめて書く（描く回数は出ている種類の数だけ、最大 5）。
## 粒の位置は「出てからの時間」の式（空気の抵抗つきの放物線）で決めるので、advance の刻み方によらず同じ時刻なら同じ形になる。
## 座標はこのノードのローカル（SkyGateFlotilla の子。着地台の中心 × 海面、回さない）。火の粉の筋と煙はカメラへ向ける板なので、
## カメラ（camera）を渡す。音は距離の分だけ遅らせて鳴らす（音の速さ SOUND_SPEED）。

const SPARK_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/firework_spark.gdshader")
const SMOKE_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/firework_smoke.gdshader")
const STREAMER_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/party_streamer.gdshader")
const GLOW_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/gate_glow.gdshader")
const BITS_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/gate_bits.gdshader")

const SPARKS := 0
const GLOWS := 1
const SMOKE := 2
const STREAMERS := 3
const CONFETTI := 4
const KIND_COUNT := 5
const KIND_NAMES: Array[String] = ["Sparks", "Glows", "Smoke", "Streamers", "Confetti"]
## 画質「高」で同時に出せる数（火の粉・煙・紙は GraphicsQuality.particle_amount で画質に合わせて減らす。光の玉は減らさない）
const BASE_CAPS: Array[int] = [2600, 48, 220, 480, 1000]
## 1 つの粒の MultiMesh のデータ（変換 12・色 4・カスタム 4）
const STRIDE := 20

## 花火の色（sRGB）。プレイヤーの色（P1 オレンジ・P2 青）を主に、金・白・桃・緑・紫・赤を混ぜる。
const SHELL_COLORS: Array[Color] = [Color("#FFC94A"), Color("#FFFFFF"), Color("#FF6FB0"), Color("#6BFF9E"), Color("#B48CFF"),
		Color("#FF5A4A")]
const PLAYER_COLORS: Array[Color] = [Color("#FF8A2A"), Color("#3AA8FF")]
const GOLD := Color("#FFC24A")
## 紙テープと紙吹雪の色（sRGB）
const PAPER_COLORS: Array[Color] = [Color("#FF5E5E"), Color("#FFD23F"), Color("#4FC3F7"), Color("#8BE38F"), Color("#FF9AD5"),
		Color("#FFFFFF"), Color("#FF9A3C"), Color("#B9A2F5")]
const SMOKE_COLOR := Color(0.66, 0.66, 0.70)

## 打ち上げの火の玉の尾（頭のうしろの点の数と間隔、秒）。
const TRAIL_STEPS := 9
const TRAIL_DT := 0.032
## 型ごと：火の粉の数・速さ（m/秒）・空気の抵抗・重さ（m/秒²）・寿命（秒）・筋の長さ（秒）・幅（m）。
const PATTERNS := {
	"peony": {"count": 110, "speed": 17.5, "drag": 2.4, "gravity": 3.0, "life": 1.7, "streak": 0.07, "width": 0.3},
	"chrysanthemum": {"count": 90, "speed": 18.5, "drag": 2.0, "gravity": 3.5, "life": 1.9, "streak": 0.2, "width": 0.26},
	"willow": {"count": 70, "speed": 13.5, "drag": 1.3, "gravity": 5.5, "life": 2.5, "streak": 0.3, "width": 0.22},
	"ring": {"count": 64, "speed": 16.0, "drag": 2.4, "gravity": 2.5, "life": 1.6, "streak": 0.08, "width": 0.3},
	"crackle": {"count": 70, "speed": 13.0, "drag": 2.2, "gravity": 3.2, "life": 1.3, "streak": 0.08, "width": 0.26},
	"double": {"count": 120, "speed": 17.5, "drag": 2.4, "gravity": 3.0, "life": 1.8, "streak": 0.08, "width": 0.28},
}
const PATTERN_NAMES: Array[String] = ["peony", "chrysanthemum", "willow", "ring", "crackle", "double"]
## はじける光（ひらめき）の大きさ（m）・長さ（秒）・強さ（強すぎると昼の空でも白い玉に見える）
const BURST_FLASH := 2.4
const BURST_FLASH_TIME := 0.22
const BURST_FLASH_POWER := 0.55
## クラッカー：紙テープと紙吹雪の数（画質「高」）、飛び出す速さ（m/秒）と広がり（度）
const POPPER_STREAMERS := 9
const POPPER_CONFETTI := 18
const POPPER_SPEED := Vector2(8.0, 12.0)
const POPPER_SPREAD := 20.0
## 紙が落ちて止まる高さ（このノードの y＝海面からの高さ）
const SEA_FLOOR := 0.03
const SOUND_SPEED := 340.0

var quality := "balanced"
var camera: Camera3D = null
## 乱数の種（効果を出すたびに 1 つ進む）。同じ順に呼べば同じ形になる
var seed_base := 20261021
## 数（テストと README）
var shells_launched := 0
var poppers_fired := 0
var _built := false
var _time := 0.0
var _seed := 0
var _emitters: Array[Dictionary] = []
var _sounds: Array[Dictionary] = []
var _mms: Array[MultiMesh] = []
var _nodes: Array[MultiMeshInstance3D] = []
var _caps := PackedInt32Array()
var _counts := PackedInt32Array()
var _offsets := PackedInt32Array()
var _buf := PackedFloat32Array()
var _eye := Vector3(0.0, 3.0, -10.0)


func build(quality_name: String = "") -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_emitters.clear()
	_sounds.clear()
	_mms.clear()
	_nodes.clear()
	quality = GraphicsQuality.normalize(quality_name if quality_name != "" else String(GameManager.graphics_quality))
	_caps.resize(KIND_COUNT)
	_counts.resize(KIND_COUNT)
	_offsets.resize(KIND_COUNT)
	var total := 0
	for kind in range(KIND_COUNT):
		var cap: int = BASE_CAPS[kind]
		if kind != GLOWS:
			cap = GraphicsQuality.particle_amount(cap, quality)
		_caps[kind] = cap
		_counts[kind] = 0
		_offsets[kind] = total
		total += cap * STRIDE
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _mesh_for(kind)
		mm.instance_count = cap
		mm.visible_instance_count = 0
		var node := MultiMeshInstance3D.new()
		node.name = "Fx" + KIND_NAMES[kind]
		node.multimesh = mm
		node.material_override = _material_for(kind)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-160.0, -10.0, -160.0), Vector3(320.0, 120.0, 320.0))
		node.visible = false
		add_child(node)
		_mms.append(mm)
		_nodes.append(node)
	_buf.resize(total)
	_built = true


## 時間を進めて、出ている効果を書き、遅らせた音を鳴らす。
func advance(delta: float) -> void:
	if not _built:
		return
	_time += delta
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		_eye = to_local(camera.global_position)
	for kind in range(KIND_COUNT):
		_counts[kind] = 0
	var alive: Array[Dictionary] = []
	for e: Dictionary in _emitters:
		var t: float = _time - float(e["t0"])
		if t > float(e["life"]):
			continue
		alive.append(e)
		if t < 0.0:
			continue
		match str(e["kind"]):
			"shell":
				_pose_shell(e, t)
			"paper":
				_pose_paper(e, t)
			"smoke":
				_pose_smoke(e, t)
			"glow":
				_pose_glow(e, t)
	_emitters = alive
	_flush()
	var waiting: Array[Dictionary] = []
	for s: Dictionary in _sounds:
		if _time >= float(s["at"]):
			AudioManager.play_sfx(StringName(s["cue"]), float(s["db"]), float(s["pitch"]))
		else:
			waiting.append(s)
	_sounds = waiting


## 出ている効果があるか。
func is_playing() -> bool:
	return not _emitters.is_empty()


## すべての効果と、まだ鳴っていない音を消す。
func clear() -> void:
	_emitters.clear()
	_sounds.clear()
	if _built:
		for kind in range(KIND_COUNT):
			_counts[kind] = 0
		_flush()


## いま描いている粒の数（種類ごと）。
func live_counts() -> Dictionary:
	var out := {}
	for kind in range(KIND_COUNT):
		out[KIND_NAMES[kind]] = _counts[kind] if _built else 0
	return out


func amount(base: int) -> int:
	return GraphicsQuality.particle_amount(base, quality)


# ---------------------------------------------------------------- 打ち上げ花火

## from（打ち上げ筒の口）から打ち上げ、rise 秒で to（はじける所）に着いてはじける。pattern は PATTERNS のどれか。
## color_a が主の色、color_b が 2 つ目の色（double の芯・ring のもう 1 色）。delay 秒あとに上がる。
func shell(from: Vector3, to: Vector3, pattern: String, color_a: Color, color_b: Color, rise: float = 1.25, delay: float = 0.0) -> void:
	if not _built:
		build()
	var spec: Dictionary = PATTERNS.get(pattern, PATTERNS["peony"])
	var rng := _rng()
	var n := amount(int(spec["count"]))
	var height := maxf(to.y - from.y, 1.0)
	# 頂上で止まる見かけの重さ：上がる時間で高さに着き、そこで縦の速さが 0 になる
	var lift := 2.0 * height / (rise * rise)
	var v_launch := (to - from) / rise + Vector3.UP * (0.5 * lift * rise)
	var dirs := PackedVector3Array()
	var speed := PackedFloat32Array()
	var life := PackedFloat32Array()
	var cols := PackedColorArray()
	var glitter := PackedFloat32Array()
	var ca := color_a.srgb_to_linear()
	var cb := color_b.srgb_to_linear()
	var ring_u := Vector3.ZERO
	var ring_v := Vector3.ZERO
	if pattern == "ring":
		# 輪はカメラの方を少し向く面に（真横から見て線にならないように）
		var face := (_eye - to).normalized()
		var hinge := face.cross(Vector3.UP)
		hinge = hinge.normalized() if hinge.length() > 0.01 else Vector3.RIGHT
		face = (Basis(hinge, rng.randf_range(-0.6, 0.6)) * face).normalized()
		ring_u = face.cross(Vector3.UP).normalized()
		if ring_u.length() < 0.1:
			ring_u = Vector3.RIGHT
		ring_v = face.cross(ring_u).normalized()
	var golden := PI * (3.0 - sqrt(5.0))
	for i in range(n):
		var d: Vector3
		if pattern == "ring":
			var a := TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / float(n)
			d = (ring_u * cos(a) + ring_v * sin(a) + _rand_dir(rng) * 0.05).normalized()
		else:
			# 球の上にほぼ等しく（黄金角のらせん）＋少しの揺らぎ
			var y := 1.0 - 2.0 * (float(i) + 0.5) / float(n)
			var r := sqrt(maxf(0.0, 1.0 - y * y))
			var a := golden * float(i)
			d = (Vector3(r * cos(a), y, r * sin(a)) + _rand_dir(rng) * 0.08).normalized()
		dirs.append(d)
		var s := float(spec["speed"]) * rng.randf_range(0.88, 1.08)
		var c := ca
		if pattern == "double" and i % 5 < 2:
			s *= 0.55
			c = cb
		elif pattern == "ring" and i % 2 == 1:
			c = cb
		elif pattern == "willow":
			c = GOLD.srgb_to_linear().lerp(ca, 0.25)
		elif pattern == "chrysanthemum" and i % 4 == 0:
			c = GOLD.srgb_to_linear()
		speed.append(s)
		cols.append(c)
		life.append(float(spec["life"]) * rng.randf_range(0.85, 1.12))
		glitter.append(rng.randf() * TAU if pattern == "crackle" or rng.randf() < 0.25 else -1.0)
	var burst_life := 0.0
	for i in range(n):
		burst_life = maxf(burst_life, life[i] + (0.12 if pattern == "crackle" else 0.0))
	_emitters.append({"kind": "shell", "t0": _time + delay, "life": rise + burst_life, "from": from, "to": to, "rise": rise,
			"v": v_launch, "lift": lift, "pattern": pattern, "dirs": dirs, "speed": speed, "plife": life, "cols": cols,
			"glitter": glitter, "drag": float(spec["drag"]), "gravity": float(spec["gravity"]), "streak": float(spec["streak"]),
			"width": float(spec["width"]), "trail_color": GOLD.srgb_to_linear().lerp(Color(1.0, 0.9, 0.75), 0.4)})
	# 筒のひらめきと煙、はじけるひらめきと煙
	_glow(from, 0.8, 0.15, Color(1.0, 0.85, 0.6, 1.0), delay)
	_smoke_puffs(from, 3, 0.35, Vector2(0.5, 0.9), 1.6, 0.42, Vector3(0.2, 0.7, 0.1), delay)
	_glow(to, BURST_FLASH, BURST_FLASH_TIME, Color(ca.lerp(Color.WHITE, 0.3), BURST_FLASH_POWER), delay + rise)
	_smoke_puffs(to, 7, 3.6, Vector2(1.4, 2.4), 4.2, 0.075, Vector3(0.5, 0.25, 0.3), delay + rise + 0.25)
	_sound(&"sg_firework_launch", from, delay, -2.0, rng.randf_range(0.95, 1.12))
	_sound(&"sg_firework_burst", to, delay + rise, 0.0, rng.randf_range(0.82, 1.0))
	shells_launched += 1


func _pose_shell(e: Dictionary, te: float) -> void:
	var rise: float = e["rise"]
	var from: Vector3 = e["from"]
	var v: Vector3 = e["v"]
	var lift: float = e["lift"]
	if te < rise:
		# 上がる火の玉：頭の光と、うしろへ細くなる尾
		var head := _rise_at(from, v, lift, te)
		var tc: Color = e["trail_color"]
		for k in range(TRAIL_STEPS):
			var t1 := maxf(te - float(k) * TRAIL_DT, 0.0)
			var t0 := maxf(te - float(k + 1) * TRAIL_DT, 0.0)
			var a := _rise_at(from, v, lift, t0)
			var b := _rise_at(from, v, lift, t1)
			var fade := 1.0 - float(k) / float(TRAIL_STEPS)
			_streak(a, b, 0.2 * (0.5 + 0.5 * fade), Color(tc, 0.9 * fade * fade))
		_put(GLOWS, Transform3D(Basis.from_scale(Vector3.ONE * 0.35), head), Color(1.0, 0.92, 0.75, 1.0))
		return
	var t := te - rise
	var to: Vector3 = e["to"]
	var dirs: PackedVector3Array = e["dirs"]
	var speed: PackedFloat32Array = e["speed"]
	var life: PackedFloat32Array = e["plife"]
	var cols: PackedColorArray = e["cols"]
	var glitter: PackedFloat32Array = e["glitter"]
	var k: float = e["drag"]
	var g: float = e["gravity"]
	var streak: float = e["streak"]
	var width: float = e["width"]
	var crackle := str(e["pattern"]) == "crackle"
	for i in range(dirs.size()):
		var lf := life[i]
		var v0 := dirs[i] * speed[i]
		if t > lf:
			# パチパチ（寿命の終わりに小さく光ってはじける）
			if crackle and t < lf + 0.12:
				var at := _ballistic(to, v0, k, g, lf) + dirs[i] * 0.35 * sin(float(i) * 3.7)
				var u := (t - lf) / 0.12
				_streak(at, at + Vector3(0.0, 0.01, 0.0), 0.4, Color(1.0, 0.97, 0.88, 1.0 - u))
			continue
		var b := _ballistic(to, v0, k, g, t)
		var a := _ballistic(to, v0, k, g, maxf(t - streak, 0.0))
		var c := cols[i]
		var bright := 1.0
		if t < 0.06:
			# はじけた瞬間は白く熱い
			c = c.lerp(Color.WHITE, 0.5)
			bright = 1.3
		var u := t / lf
		if u > 0.6:
			bright *= pow(1.0 - (u - 0.6) / 0.4, 1.4)
		if glitter[i] >= 0.0 and u > 0.45:
			bright *= 0.45 + 0.55 * absf(sin(t * 41.0 + glitter[i]))
		_streak(a, b, width, Color(c, bright))


static func _rise_at(from: Vector3, v: Vector3, lift: float, t: float) -> Vector3:
	return from + v * t + Vector3.DOWN * (0.5 * lift * t * t)


## 空気の抵抗（drag）つきの放物線：p = p0 + v0·(1−e^{−kt})/k + g·(t − (1−e^{−kt})/k)/k
static func _ballistic(p0: Vector3, v0: Vector3, k: float, g: float, t: float) -> Vector3:
	var f1 := (1.0 - exp(-k * t)) / k
	return p0 + v0 * f1 + Vector3.DOWN * (g * (t - f1) / k)


static func _ballistic_velocity(v0: Vector3, k: float, g: float, t: float) -> Vector3:
	var e := exp(-k * t)
	return v0 * e + Vector3.DOWN * (g * (1.0 - e) / k)


# ---------------------------------------------------------------- クラッカー

## at（手の位置）から dir の向きへクラッカーを鳴らす：紙テープ・紙吹雪・小さなひらめきと煙・音。delay 秒あと。
## 一度にたくさん鳴らすときは、音は数本だけにする（with_sound。効果音の声は 8 本しかない）。
func popper(at: Vector3, dir: Vector3, delay: float = 0.0, with_sound: bool = true) -> void:
	if not _built:
		build()
	var rng := _rng()
	var aim := dir.normalized()
	var p0 := PackedVector3Array()
	var v0 := PackedVector3Array()
	var size := PackedVector3Array()
	var cols := PackedColorArray()
	var life := PackedFloat32Array()
	var spin := PackedVector3Array()
	var extra := PackedColorArray()
	var ribbon := PackedInt32Array()
	for i in range(amount(POPPER_STREAMERS)):
		p0.append(at)
		v0.append(_cone(rng, aim, POPPER_SPREAD) * rng.randf_range(POPPER_SPEED.x, POPPER_SPEED.y))
		# 紙テープ：長さ・幅（size.x・y）、巻きの位相・半径・速さ
		var w := rng.randf_range(0.035, 0.05)
		size.append(Vector3(w, rng.randf_range(0.7, 1.25), 0.0))
		cols.append((PAPER_COLORS[rng.randi_range(0, PAPER_COLORS.size() - 1)] as Color).srgb_to_linear())
		life.append(rng.randf_range(3.6, 4.4))
		spin.append(Vector3(rng.randf_range(-2.5, 2.5), 0.0, 0.0))
		extra.append(Color(rng.randf() * TAU, rng.randf_range(0.05, 0.11), rng.randf_range(5.0, 9.0), w))
		ribbon.append(1)
	for i in range(amount(POPPER_CONFETTI)):
		p0.append(at)
		v0.append(_cone(rng, aim, POPPER_SPREAD * 1.4) * rng.randf_range(POPPER_SPEED.x * 0.7, POPPER_SPEED.y * 0.9))
		size.append(Vector3(rng.randf_range(0.09, 0.13), rng.randf_range(0.06, 0.09), 1.0))
		cols.append((PAPER_COLORS[rng.randi_range(0, PAPER_COLORS.size() - 1)] as Color).srgb_to_linear())
		life.append(rng.randf_range(2.6, 3.4))
		spin.append(_rand_dir(rng) * rng.randf_range(6.0, 14.0))
		extra.append(Color())
		ribbon.append(0)
	var max_life := 0.0
	for i in range(life.size()):
		max_life = maxf(max_life, life[i])
	_emitters.append({"kind": "paper", "t0": _time + delay, "life": max_life, "p0": p0, "v0": v0, "size": size, "cols": cols,
			"plife": life, "spin": spin, "extra": extra, "ribbon": ribbon})
	_glow(at, 0.5, 0.1, Color(1.0, 0.9, 0.7, 0.9), delay)
	_smoke_puffs(at, 2, 0.25, Vector2(0.25, 0.4), 1.2, 0.35, aim * 0.6 + Vector3.UP * 0.3, delay)
	if with_sound:
		_sound(&"sg_popper", at, delay, 0.0, rng.randf_range(2.1, 2.5))
	poppers_fired += 1


func _pose_paper(e: Dictionary, t: float) -> void:
	var p0: PackedVector3Array = e["p0"]
	var v0: PackedVector3Array = e["v0"]
	var size: PackedVector3Array = e["size"]
	var cols: PackedColorArray = e["cols"]
	var life: PackedFloat32Array = e["plife"]
	var spin: PackedVector3Array = e["spin"]
	var extra: PackedColorArray = e["extra"]
	var ribbon: PackedInt32Array = e["ribbon"]
	for i in range(p0.size()):
		if t > life[i]:
			continue
		var shrink := clampf((life[i] - t) / 0.35, 0.0, 1.0)
		if ribbon[i] == 1:
			# 紙テープ：重く速く飛び、すぐ止まってひらひら落ちる
			var head := _ballistic(p0[i], v0[i], 2.6, 4.2, t)
			var vel := _ballistic_velocity(v0[i], 2.6, 4.2, t)
			var on_sea := head.y <= SEA_FLOOR
			head.y = maxf(head.y, SEA_FLOOR)
			var slow := smoothstep(4.0, 0.8, vel.length())
			var sway := Vector3(sin(t * 2.1 + extra[i].r), 0.0, cos(t * 1.7 + extra[i].r)) * 0.35
			var trail := (-vel.normalized()).lerp((Vector3.DOWN + sway).normalized(), slow).normalized()
			if on_sea:
				trail = Vector3(trail.x, 0.0, trail.z)
				trail = trail.normalized() if trail.length() > 0.05 else Vector3.RIGHT
			var view := (_eye - head).normalized()
			var across := trail.cross(view)
			across = across.normalized() if across.length() > 0.01 else trail.cross(Vector3.UP).normalized()
			across = across.rotated(trail, spin[i].x * t)
			var normal := across.cross(trail).normalized()
			var length := size[i].y * shrink
			var xf := Transform3D(Basis(across * size[i].x, trail * length, normal), head)
			_put(STREAMERS, xf, cols[i], extra[i])
		else:
			# 紙吹雪：小さい四角が回りながら落ちる
			var pos := _ballistic(p0[i], v0[i], 2.4, 3.5, t)
			pos.y = maxf(pos.y, SEA_FLOOR)
			var axis := spin[i].normalized()
			var b := Basis(axis, spin[i].length() * t) * Basis.from_scale(Vector3(size[i].x, size[i].y, 1.0) * shrink)
			_put(CONFETTI, Transform3D(b, pos), cols[i])


# ---------------------------------------------------------------- 煙・ひらめき・音

## count 個の薄い煙の玉。radius まで広がり（1.2 秒）、size（最初・最後の半径）で大きくなって life 秒で消える。drift で流れる。
func _smoke_puffs(at: Vector3, count: int, radius: float, size: Vector2, life: float, alpha: float, drift: Vector3, delay: float) -> void:
	var rng := _rng()
	var dirs := PackedVector3Array()
	var dist := PackedFloat32Array()
	var lifes := PackedFloat32Array()
	var seeds := PackedFloat32Array()
	var n := maxi(1, amount(count * 2) / 2) if count > 2 else count
	for i in range(n):
		dirs.append(_rand_dir(rng))
		dist.append(radius * rng.randf_range(0.3, 1.0))
		lifes.append(life * rng.randf_range(0.8, 1.1))
		seeds.append(rng.randf())
	var max_life := 0.0
	for l in lifes:
		max_life = maxf(max_life, l)
	_emitters.append({"kind": "smoke", "t0": _time + delay, "life": max_life, "center": at, "dirs": dirs, "dist": dist, "plife": lifes,
			"seeds": seeds, "size": size, "alpha": alpha, "drift": drift})


func _pose_smoke(e: Dictionary, t: float) -> void:
	var center: Vector3 = e["center"]
	var dirs: PackedVector3Array = e["dirs"]
	var dist: PackedFloat32Array = e["dist"]
	var life: PackedFloat32Array = e["plife"]
	var seeds: PackedFloat32Array = e["seeds"]
	var size: Vector2 = e["size"]
	var alpha: float = e["alpha"]
	var drift: Vector3 = e["drift"]
	for i in range(dirs.size()):
		if t > life[i]:
			continue
		var u := t / life[i]
		var pos := center + dirs[i] * dist[i] * _ease_out(t / 1.2) + drift * t
		var s := lerpf(size.x, size.y, _ease_out(u))
		var a := alpha * smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.35, 1.0, u))
		_put(SMOKE, Transform3D(_facing(pos, s), pos), Color(SMOKE_COLOR, a), Color(seeds[i], 0.0, 0.0, 0.0))


## ひらめき：光る玉がすぐ広がって消える（delay 秒あと）。color は線形、a が強さ。
func _glow(at: Vector3, radius: float, duration: float, color: Color, delay: float = 0.0) -> void:
	_emitters.append({"kind": "glow", "t0": _time + delay, "life": duration, "center": at, "radius": radius, "color": color})


func _pose_glow(e: Dictionary, t: float) -> void:
	var u := clampf(t / float(e["life"]), 0.0, 1.0)
	var s := float(e["radius"]) * _ease_out(minf(u * 3.0, 1.0))
	var c: Color = e["color"]
	c.a *= (1.0 - u) * (1.0 - u)
	_put(GLOWS, Transform3D(Basis.from_scale(Vector3.ONE * maxf(s, 0.01)), e["center"] as Vector3), c)


## 音を、聞こえる所（カメラ）までの距離の分だけ遅らせて鳴らす。遠いほど少し小さく。
func _sound(cue: StringName, at: Vector3, delay: float, db: float, pitch: float) -> void:
	var d := _eye.distance_to(at)
	_sounds.append({"at": _time + delay + d / SOUND_SPEED, "cue": cue, "db": db - clampf((d - 15.0) * 0.12, 0.0, 9.0), "pitch": pitch})


# ---------------------------------------------------------------- 板の置き方

## a から b への火の粉の筋（カメラへ向けた板）。短すぎる筋は点に見えるよう幅の 1.6 倍まで伸ばす。
func _streak(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var seg := b - a
	var length := seg.length()
	var mid := (a + b) * 0.5
	var view := (_eye - mid).normalized()
	var along := seg / length if length > 0.0001 else view.cross(Vector3.RIGHT).normalized()
	var min_len := width * 1.6
	if length < min_len:
		mid = b - along * (min_len * 0.5)
		length = min_len
	var across := view.cross(along)
	across = across.normalized() if across.length() > 0.001 else Vector3.UP
	_put(SPARKS, Transform3D(Basis(along * length, across * width, view), mid), color)


## カメラへ向けた板の向き（半径 r。板は 1×1 なので 2r にする）。
func _facing(at: Vector3, r: float) -> Basis:
	var view := (_eye - at).normalized()
	var right := Vector3.UP.cross(view)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var up := view.cross(right).normalized()
	return Basis(right * (2.0 * r), up * (2.0 * r), view)


func _put(kind: int, xf: Transform3D, c: Color, custom: Color = Color()) -> void:
	var n := _counts[kind]
	if n >= _caps[kind]:
		return
	_counts[kind] = n + 1
	var o := _offsets[kind] + n * STRIDE
	var b := xf.basis
	_buf[o] = b.x.x
	_buf[o + 1] = b.y.x
	_buf[o + 2] = b.z.x
	_buf[o + 3] = xf.origin.x
	_buf[o + 4] = b.x.y
	_buf[o + 5] = b.y.y
	_buf[o + 6] = b.z.y
	_buf[o + 7] = xf.origin.y
	_buf[o + 8] = b.x.z
	_buf[o + 9] = b.y.z
	_buf[o + 10] = b.z.z
	_buf[o + 11] = xf.origin.z
	_buf[o + 12] = c.r
	_buf[o + 13] = c.g
	_buf[o + 14] = c.b
	_buf[o + 15] = c.a
	_buf[o + 16] = custom.r
	_buf[o + 17] = custom.g
	_buf[o + 18] = custom.b
	_buf[o + 19] = custom.a


func _flush() -> void:
	for kind in range(KIND_COUNT):
		var n := _counts[kind]
		var node := _nodes[kind]
		node.visible = n > 0
		if n == 0:
			continue
		var mm := _mms[kind]
		var o := _offsets[kind]
		mm.buffer = _buf.slice(o, o + _caps[kind] * STRIDE)
		mm.visible_instance_count = n


# ---------------------------------------------------------------- 形と材質

func _mesh_for(kind: int) -> Mesh:
	match kind:
		SPARKS, SMOKE, CONFETTI:
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			return quad
		STREAMERS:
			return _streamer_mesh()
		_:
			var ball := SphereMesh.new()
			ball.radius = 1.0
			ball.height = 2.0
			ball.radial_segments = 16
			ball.rings = 8
			return ball


func _material_for(kind: int) -> Material:
	var mat := ShaderMaterial.new()
	match kind:
		SPARKS:
			mat.shader = SPARK_SHADER
		SMOKE:
			mat.shader = SMOKE_SHADER
		STREAMERS:
			mat.shader = STREAMER_SHADER
		CONFETTI:
			mat.shader = BITS_SHADER
		_:
			mat.shader = GLOW_SHADER
			mat.set_shader_parameter("mode", 1)
	return mat


## 紙テープ 1 本：幅 1（X −0.5〜0.5）、長さ 1（Y 0 → 1）を 12 に分けた帯。巻いて揺らすのはシェーダー。
func _streamer_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 12
	for i in range(seg):
		var y0 := float(i) / float(seg)
		var y1 := float(i + 1) / float(seg)
		for v: Array in [[-0.5, y0], [0.5, y0], [0.5, y1], [-0.5, y0], [0.5, y1], [-0.5, y1]]:
			st.set_normal(Vector3.BACK)
			st.set_uv(Vector2(float(v[0]) + 0.5, float(v[1])))
			st.add_vertex(Vector3(float(v[0]), float(v[1]), 0.0))
	return st.commit()


# ---------------------------------------------------------------- 道具

func _rng() -> RandomNumberGenerator:
	_seed += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_base, _seed])
	return rng


## aim のまわり spread 度の円錐の中の向き。
static func _cone(rng: RandomNumberGenerator, aim: Vector3, spread: float) -> Vector3:
	var side := aim.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var up := side.cross(aim).normalized()
	var a := rng.randf() * TAU
	var r := tan(deg_to_rad(spread)) * sqrt(rng.randf())
	return (aim + (side * cos(a) + up * sin(a)) * r).normalized()


static func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var r := sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(r * cos(a), z, r * sin(a))


static func _ease_out(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)

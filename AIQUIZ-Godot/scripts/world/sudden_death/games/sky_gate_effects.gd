class_name SkyGateEffects
extends Node3D

## スカイゲートの効果（docs/sudden_death_v2/skygate_build_plan.md 4.6節、sky_gate.md 第2章）。
## 紙吹雪・破れた紙のかけら・漫画の煙と火の玉・星・光の輪・ひらめき・破れた紙の垂れ（フラップ）・人形のブロック。
## 子ども向けなので血や怖さはない（ブロックが飛び散る漫画の爆発）。
##
## 種類ごとに MultiMesh を 1 つ持ち、出ている効果をまとめて毎フレーム書く。描く回数は出ている種類の数だけ（最大 7）。
## 粒の位置は「効果が出てからの時間」の式で決める（空気の抵抗つきの放物線）。advance の刻み方によらず、同じ時刻なら同じ形になる
## （30／60／120fps で同じ。スローは delta を小さく渡す）。
## 座標はこのノードのローカル。SkyGateBoard の子（board.effects）に置けば、ボードと一緒に動く。

const PUFF_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/gate_puff.gdshader")
const GLOW_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/gate_glow.gdshader")
const BITS_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/gate_bits.gdshader")

const CHIPS := 0
const PUFFS := 1
const STARS := 2
const BLOCKS := 3
const FLAPS := 4
const RINGS := 5
const FLASHES := 6
const KIND_COUNT := 7
const KIND_NAMES: Array[String] = ["Chips", "Puffs", "Stars", "Blocks", "Flaps", "Rings", "Flashes"]
## 画質「高」で同時に出せる数（紙吹雪・煙・星は GraphicsQuality.particle_amount で画質に合わせて減らす）
const BASE_CAPS: Array[int] = [560, 64, 32, 160, 48, 8, 8]
## 1 つの粒の MultiMesh のデータ（変換 12・色 4・カスタム 4）
const STRIDE := 20

## 紙吹雪の色（sRGB）：パネルの 4 色と白・オレンジ・うす紫
const CONFETTI_COLORS: Array[Color] = [Color("#8FE3B5"), Color("#8CCDF5"), Color("#FBE878"), Color("#F9A9C8"),
		Color("#FFFFFF"), Color("#FF9A3C"), Color("#B9A2F5")]
const STAR_COLOR := Color("#FFD23F")
## 煙と火の玉の色（線形。gate_puff.gdshader にそのまま渡す）
const FIRE_HOT := Color(1.0, 0.55, 0.08)
const FIRE_ORANGE := Color(1.0, 0.16, 0.01)
const SMOKE := Color(0.78, 0.79, 0.83)
const SMOKE_DARK := Color(0.52, 0.53, 0.58)

## 正解：紙が破れる（burst_fx）
const BURST_CONFETTI := 160
## まちがい：パネルの爆発（boom_fx）
const BOOM_PUFFS := 26
const BOOM_STARS := 14
const BOOM_SHREDS := 56
## 破れた紙の垂れの長さの上限（m）。外へ少し傾いても枠の幅（0.3 m）を越えない
const FLAP_MAX_LENGTH := 1.4
## 人形がブロックにばらける（player_burst）
const PLAYER_PUFFS := 12
const PLAYER_STARS := 8

var quality := "balanced"
## 乱数の種（効果を出すたびに 1 つ進む）。同じ順に呼べば同じ形になる
var seed_base := 20261018
var _built := false
var _time := 0.0
var _seed := 0
var _emitters: Array[Dictionary] = []
var _mms: Array[MultiMesh] = []
var _nodes: Array[MultiMeshInstance3D] = []
var _caps := PackedInt32Array()
var _counts := PackedInt32Array()
var _offsets := PackedInt32Array()
var _buf := PackedFloat32Array()


func build(quality_name: String = "") -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_emitters.clear()
	_mms.clear()
	_nodes.clear()
	quality = GraphicsQuality.normalize(quality_name if quality_name != "" else String(GameManager.graphics_quality))
	_caps.resize(KIND_COUNT)
	_counts.resize(KIND_COUNT)
	_offsets.resize(KIND_COUNT)
	var total := 0
	for kind in range(KIND_COUNT):
		var cap: int = BASE_CAPS[kind]
		if kind == CHIPS or kind == PUFFS or kind == STARS:
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
		node.custom_aabb = AABB(Vector3(-60.0, -60.0, -60.0), Vector3(120.0, 120.0, 120.0))
		node.visible = false
		add_child(node)
		_mms.append(mm)
		_nodes.append(node)
	_buf.resize(total)
	_built = true


## 時間を進めて、出ている効果を書く。スローのときは小さい delta を渡す。
func advance(delta: float) -> void:
	if not _built:
		return
	_time += delta
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
		match int(e["kind"]):
			CHIPS, STARS, BLOCKS:
				_pose_ballistic(e, t)
			PUFFS:
				_pose_puffs(e, t)
			FLAPS:
				_pose_flaps(e, t)
			RINGS:
				_pose_ring(e, t)
			FLASHES:
				_pose_flash(e, t)
	_emitters = alive
	_flush()


## 出ている効果（垂れたフラップを除く）があるか。
func is_playing() -> bool:
	for e: Dictionary in _emitters:
		if is_finite(float(e["life"])):
			return true
	return false


## すべての効果を消す。
func clear() -> void:
	_emitters.clear()
	if _built:
		for kind in range(KIND_COUNT):
			_counts[kind] = 0
		_flush()


## tag をつけた効果（パネルごとのフラップなど）を消す。
func clear_tag(tag: Variant) -> void:
	var keep: Array[Dictionary] = []
	for e: Dictionary in _emitters:
		if e.get("tag") != tag:
			keep.append(e)
	_emitters = keep


## 粒の数（画質に合わせたあと）。README の数はこれで確かめる。
func amount(base: int) -> int:
	return GraphicsQuality.particle_amount(base, quality)


## いま描いている粒の数（種類ごと）。
func live_counts() -> Dictionary:
	var out := {}
	for kind in range(KIND_COUNT):
		out[KIND_NAMES[kind]] = _counts[kind] if _built else 0
	return out


# ---------------------------------------------------------------- 人形がブロックにばらける

## 人形（EmoteBlockmanPreview.build_player_skeleton の parts）の体を、色ごとのブロックにばらして飛び散らせる。
## at はばらける中心（ワールド）。人形は隠す（parts["pelvis"].visible = false）。元に戻すのは呼んだ側。
## 大きい箱は画質「高」で 4 つ、「標準」で 2 つに割る。白い煙・星・ひらめきも出す（血や怖さはなし）。
func player_burst(parts: Dictionary, at: Vector3) -> void:
	if not _built:
		build()
	var meshes := _doll_meshes(parts)
	var rng := _rng()
	var center := to_local(at)
	var inv := global_transform.affine_inverse()
	var p0 := PackedVector3Array()
	var v0 := PackedVector3Array()
	var axis := PackedVector3Array()
	var spin := PackedFloat32Array()
	var size := PackedVector3Array()
	var col := PackedColorArray()
	var life := PackedFloat32Array()
	var delay := PackedFloat32Array()
	var basis0: Array[Basis] = []
	var split := 2 if quality == GraphicsQuality.HIGH or quality == GraphicsQuality.ULTRA else (1 if quality == GraphicsQuality.BALANCED else 0)
	for mi: MeshInstance3D in meshes:
		var aabb := mi.get_aabb()
		if aabb.size.length() < 0.01:
			continue
		var xf := inv * mi.global_transform
		var scale := xf.basis.get_scale()
		var rot := xf.basis.orthonormalized()
		var full := aabb.size * scale
		var mid := xf * aabb.get_center()
		var color := _mesh_color(mi)
		for piece: Array in _split_box(full, split):
			var pos: Vector3 = mid + rot * (piece[0] as Vector3)
			var away := pos - center
			if away.length() < 0.05:
				away = _rand_dir(rng)
			p0.append(pos)
			v0.append(away.normalized() * rng.randf_range(3.0, 6.5) + _rand_dir(rng) * 1.8 + Vector3.UP * rng.randf_range(1.5, 4.0))
			axis.append(_rand_dir(rng))
			spin.append(rng.randf_range(5.0, 13.0) * (1.0 if rng.randf() < 0.5 else -1.0))
			size.append(piece[1] as Vector3)
			col.append(color.lightened(rng.randf_range(-0.06, 0.08)))
			life.append(rng.randf_range(1.5, 2.1))
			delay.append(rng.randf_range(0.0, 0.04))
			basis0.append(rot)
	_hide_doll(parts, meshes)
	if not p0.is_empty():
		_add_ballistic(BLOCKS, p0, v0, axis, spin, size, col, life, delay, 0.8, 6.0, 0.0, 0.5, basis0)
	puffs(center, 0.75, PLAYER_PUFFS, false, 0.0)
	stars(center, PLAYER_STARS, 0.8)
	flash(center, 1.5, 0.25, Color(1.0, 1.0, 0.95, 0.9))
	ring(center, 0.4, 2.6, 0.4, Color(1.0, 0.95, 0.8, 0.8))


# ---------------------------------------------------------------- ボードが使うまとまり

## 正解：紙が破れたところの紙吹雪・光の輪・ひらめき（フラップと穴は SkyGateBoard.burst が出す）。at はローカル。
func burst_fx(at: Vector3, panel_color: Color) -> void:
	var colors := CONFETTI_COLORS.duplicate()
	colors.append(panel_color)
	colors.append(panel_color)
	confetti(at, BURST_CONFETTI, colors)
	ring(at + Vector3(0.0, 0.04, 0.0), 0.5, 3.6, 0.5, Color(1.0, 0.95, 0.7, 1.0))
	ring(at + Vector3(0.0, 0.03, 0.0), 0.3, 2.2, 0.38, Color(1.0, 1.0, 1.0, 0.7), 0.06)
	flash(at, 1.8, 0.22, Color(1.0, 1.0, 0.9, 0.9))


## まちがい：パネルの漫画の爆発（火の玉から白い煙・星・パネルの色の紙のかけら・オレンジの輪・ひらめき）。at はローカル。
func boom_fx(at: Vector3, panel_color: Color) -> void:
	flash(at, 3.2, 0.32, Color(1.0, 0.75, 0.3, 1.0))
	puffs(at, 2.0, BOOM_PUFFS, true, 0.5)
	stars(at, BOOM_STARS, 1.0)
	shreds(at, panel_color, BOOM_SHREDS)
	ring(at + Vector3(0.0, 0.05, 0.0), 0.8, 5.0, 0.45, Color(1.0, 0.6, 0.2, 1.0))


# ---------------------------------------------------------------- 1 つずつの効果

## 紙吹雪：小さい四角が下と外へ散って、ひらひら落ちる。
func confetti(at: Vector3, base: int, colors: Array = CONFETTI_COLORS) -> void:
	var rng := _rng()
	var n := amount(base)
	var p0 := PackedVector3Array()
	var v0 := PackedVector3Array()
	var axis := PackedVector3Array()
	var spin := PackedFloat32Array()
	var size := PackedVector3Array()
	var col := PackedColorArray()
	var life := PackedFloat32Array()
	var delay := PackedFloat32Array()
	for i in range(n):
		var a := rng.randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a))
		p0.append(at + out * rng.randf_range(0.0, 0.6))
		v0.append(out * rng.randf_range(3.0, 9.5) + Vector3.UP * rng.randf_range(-5.0, 6.5))
		axis.append(_rand_dir(rng))
		spin.append(rng.randf_range(6.0, 16.0))
		size.append(Vector3(rng.randf_range(0.16, 0.26), rng.randf_range(0.09, 0.15), 1.0))
		col.append((colors[rng.randi_range(0, colors.size() - 1)] as Color).srgb_to_linear())
		life.append(rng.randf_range(1.5, 2.4))
		delay.append(rng.randf_range(0.0, 0.05))
	_add_ballistic(CHIPS, p0, v0, axis, spin, size, col, life, delay, 2.0, 4.0, 0.05, 0.4)


## 爆発で飛ぶ紙のかけら（パネルの色と白）。上と外へ。
func shreds(at: Vector3, panel_color: Color, base: int) -> void:
	var rng := _rng()
	var n := amount(base)
	var p0 := PackedVector3Array()
	var v0 := PackedVector3Array()
	var axis := PackedVector3Array()
	var spin := PackedFloat32Array()
	var size := PackedVector3Array()
	var col := PackedColorArray()
	var life := PackedFloat32Array()
	var delay := PackedFloat32Array()
	for i in range(n):
		var a := rng.randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a))
		p0.append(at + out * rng.randf_range(0.2, 1.4))
		v0.append(out * rng.randf_range(3.0, 10.0) + Vector3.UP * rng.randf_range(-4.0, 7.0))
		axis.append(_rand_dir(rng))
		spin.append(rng.randf_range(4.0, 11.0))
		size.append(Vector3(rng.randf_range(0.18, 0.42), rng.randf_range(0.12, 0.30), 1.0))
		var c := panel_color.lightened(rng.randf_range(-0.05, 0.15)) if rng.randf() < 0.8 else Color.WHITE
		col.append(c.srgb_to_linear())
		life.append(rng.randf_range(1.2, 2.0))
		delay.append(rng.randf_range(0.0, 0.04))
	_add_ballistic(CHIPS, p0, v0, axis, spin, size, col, life, delay, 1.4, 6.0, 0.04, 0.35)


## 漫画の煙の玉。fire なら初めは白く光る黄色からオレンジ、そして白い煙へ。radius は広がる大きさ（m）。
func puffs(at: Vector3, radius: float, base: int, fire: bool, rise: float) -> void:
	var rng := _rng()
	var n := amount(base)
	var dir := PackedVector3Array()
	var dist := PackedFloat32Array()
	var size := PackedFloat32Array()
	var life := PackedFloat32Array()
	var delay := PackedFloat32Array()
	var drift := PackedVector3Array()
	var hot := PackedFloat32Array()
	var smoke := PackedColorArray()
	for i in range(n):
		var d := _rand_dir(rng)
		d.y *= 0.6
		dir.append(d.normalized())
		dist.append(radius * rng.randf_range(0.25, 1.0))
		size.append(radius * rng.randf_range(0.32, 0.58))
		var is_hot := fire and i < int(n * 0.55)
		hot.append(1.0 if is_hot else 0.0)
		if not is_hot and fire:
			size[i] *= 1.15
		delay.append(rng.randf_range(0.0, 0.06) + (0.0 if is_hot else 0.07))
		# 火の玉はオレンジのまま小さくなって消え、白い煙が残る
		life.append(rng.randf_range(0.55, 0.85) if is_hot else rng.randf_range(1.0, 1.6))
		drift.append(d * 0.35 + Vector3.UP * rng.randf_range(0.0, 0.6) * (1.0 + rise))
		smoke.append(SMOKE.lerp(SMOKE_DARK, rng.randf_range(0.0, 0.35) if fire else rng.randf_range(0.0, 0.1)))
	var max_life := 0.0
	for i in range(n):
		max_life = maxf(max_life, life[i] + delay[i])
	_emitters.append({"kind": PUFFS, "t0": _time, "life": max_life, "center": at, "dir": dir, "dist": dist, "size": size,
			"plife": life, "delay": delay, "drift": drift, "hot": hot, "smoke": smoke})


## 黄色い星：外へ飛んで回る。
func stars(at: Vector3, base: int, speed: float) -> void:
	var rng := _rng()
	var n := amount(base)
	var p0 := PackedVector3Array()
	var v0 := PackedVector3Array()
	var axis := PackedVector3Array()
	var spin := PackedFloat32Array()
	var size := PackedVector3Array()
	var col := PackedColorArray()
	var life := PackedFloat32Array()
	var delay := PackedFloat32Array()
	for i in range(n):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), rng.randf_range(0.15, 0.9), sin(a)).normalized()
		p0.append(at + d * 0.3)
		v0.append(d * rng.randf_range(4.0, 8.0) * speed)
		axis.append((Vector3.UP + _rand_dir(rng) * 0.35).normalized())
		spin.append(rng.randf_range(5.0, 10.0))
		var s := rng.randf_range(0.3, 0.5)
		size.append(Vector3(s, s, s))
		col.append(STAR_COLOR.lightened(rng.randf_range(0.0, 0.2)))
		life.append(rng.randf_range(0.8, 1.3))
		delay.append(rng.randf_range(0.0, 0.05))
	_add_ballistic(STARS, p0, v0, axis, spin, size, col, life, delay, 1.2, 3.0, 0.1, 0.3)


## 光の輪：ボードの面（ローカルの XZ）に沿って広がって消える。color は線形、a が強さ。
func ring(at: Vector3, from_radius: float, to_radius: float, duration: float, color: Color, delay: float = 0.0) -> void:
	_emitters.append({"kind": RINGS, "t0": _time + delay, "life": duration, "center": at, "r0": from_radius, "r1": to_radius,
			"color": color})


## ひらめき：光る玉がすぐ広がって消える。
func flash(at: Vector3, radius: float, duration: float, color: Color) -> void:
	_emitters.append({"kind": FLASHES, "t0": _time, "life": duration, "center": at, "radius": radius, "color": color})


## 破れた紙の垂れ：穴のふちから内へ向いた紙が、下へ折れて垂れる（tag を clear_tag で消すまで残る）。
## 穴の大きさは hole_radius(radius, open_time, t)、ふちのぎざぎざは jag(角度, seed)（gate_paper.gdshader と同じ式）。
## 角度は穴の中心から見た atan2(z, x)（ローカル）。angles は折れる角度の範囲（rad）。
## bounds（ローカルの XZ の四角）を渡すと、垂れの付け根をその中に収める（パネルより大きい穴でも枠の外へ出ない）。
func flaps(tag: Variant, center: Vector3, radius: float, open_time: float, seed: float, color: Color, angles: Vector2,
		bounds: Rect2 = Rect2()) -> void:
	var rng := _rng()
	var n := 6 if quality == GraphicsQuality.LOW else (8 if quality == GraphicsQuality.BALANCED else 10)
	var target := PackedFloat32Array()
	for i in range(n):
		target.append(rng.randf_range(angles.x, angles.y))
	_emitters.append({"kind": FLAPS, "t0": _time, "life": INF, "tag": tag, "center": center, "radius": radius, "open": open_time,
			"seed": seed, "n": n, "phase": rng.randf() * TAU, "target": target, "color": color.srgb_to_linear(), "bounds": bounds})


## 点 p から向き d へ進んで四角 r のふちに着くまでの長さ。
static func _reach(r: Rect2, p: Vector2, d: Vector2) -> float:
	var best := INF
	if d.x > 0.0001:
		best = minf(best, (r.end.x - p.x) / d.x)
	elif d.x < -0.0001:
		best = minf(best, (r.position.x - p.x) / d.x)
	if d.y > 0.0001:
		best = minf(best, (r.end.y - p.y) / d.y)
	elif d.y < -0.0001:
		best = minf(best, (r.position.y - p.y) / d.y)
	return maxf(best, 0.0)


## 穴の大きさ（m）：open_time で radius まで開く（はじめ速く、あとゆっくり）。
static func hole_radius(radius: float, open_time: float, t: float) -> float:
	if t <= 0.0:
		return 0.0
	return radius * _ease_out(t / maxf(open_time, 0.001))


## 穴のふちのぎざぎざ（gate_paper.gdshader の jag と同じ式）。
static func jag(a: float, seed: float) -> float:
	return 0.16 * sin(a * 7.0 + seed) + 0.10 * sin(a * 13.0 + seed * 2.3) + 0.06 * sin(a * 29.0 + seed * 4.1)


# ---------------------------------------------------------------- 粒の形

func _add_ballistic(kind: int, p0: PackedVector3Array, v0: PackedVector3Array, axis: PackedVector3Array, spin: PackedFloat32Array,
		size: PackedVector3Array, col: PackedColorArray, life: PackedFloat32Array, delay: PackedFloat32Array,
		drag: float, gravity: float, pop: float, shrink: float, basis0: Array[Basis] = []) -> void:
	var max_life := 0.0
	for i in range(life.size()):
		max_life = maxf(max_life, life[i] + delay[i])
	_emitters.append({"kind": kind, "t0": _time, "life": max_life, "p0": p0, "v0": v0, "axis": axis, "spin": spin, "size": size,
			"col": col, "plife": life, "delay": delay, "drag": drag, "gravity": gravity, "pop": pop, "shrink": shrink,
			"basis0": basis0})


## 空気の抵抗（drag）つきの放物線：p = p0 + v0·(1−e^{−kt})/k + g·(t − (1−e^{−kt})/k)/k
func _pose_ballistic(e: Dictionary, te: float) -> void:
	var kind: int = e["kind"]
	var k: float = e["drag"]
	var acc := Vector3(0.0, -float(e["gravity"]), 0.0)
	var pop: float = e["pop"]
	var shrink: float = e["shrink"]
	var p0: PackedVector3Array = e["p0"]
	var v0: PackedVector3Array = e["v0"]
	var axis: PackedVector3Array = e["axis"]
	var spin: PackedFloat32Array = e["spin"]
	var size: PackedVector3Array = e["size"]
	var col: PackedColorArray = e["col"]
	var life: PackedFloat32Array = e["plife"]
	var delay: PackedFloat32Array = e["delay"]
	var basis0: Array[Basis] = e["basis0"]
	var has_basis := not basis0.is_empty()
	for i in range(p0.size()):
		var t := te - delay[i]
		if t < 0.0 or t > life[i]:
			continue
		var s := clampf((life[i] - t) / shrink, 0.0, 1.0)
		if pop > 0.0:
			s *= _ease_out(t / pop)
		if s < 0.001:
			continue
		var f1 := (1.0 - exp(-k * t)) / k
		var pos := p0[i] + v0[i] * f1 + acc * ((t - f1) / k)
		var b := Basis(axis[i], spin[i] * t)
		if has_basis:
			b = b * basis0[i]
		_put(kind, Transform3D(b * Basis.from_scale(size[i] * s), pos), col[i])


func _pose_puffs(e: Dictionary, te: float) -> void:
	var center: Vector3 = e["center"]
	var dir: PackedVector3Array = e["dir"]
	var dist: PackedFloat32Array = e["dist"]
	var size: PackedFloat32Array = e["size"]
	var life: PackedFloat32Array = e["plife"]
	var delay: PackedFloat32Array = e["delay"]
	var drift: PackedVector3Array = e["drift"]
	var hot: PackedFloat32Array = e["hot"]
	var smoke: PackedColorArray = e["smoke"]
	for i in range(dir.size()):
		var t := te - delay[i]
		if t < 0.0 or t > life[i]:
			continue
		var grow := _ease_out(t / 0.2)
		var shrink := 1.0 - smoothstep(life[i] * 0.5, life[i], t)
		var s := size[i] * (0.3 + 0.7 * grow) * shrink
		if s < 0.01:
			continue
		var pos := center + dir[i] * dist[i] * _ease_out(t / 0.45) + drift[i] * t
		var c := smoke[i]
		var emit := 0.0
		if hot[i] > 0.5:
			if t < 0.05:
				c = FIRE_HOT
				emit = 0.7
			elif t < 0.15:
				var u := (t - 0.05) / 0.1
				c = FIRE_HOT.lerp(FIRE_ORANGE, u)
				emit = lerpf(0.7, 0.35, u)
			else:
				c = FIRE_ORANGE
				emit = lerpf(0.35, 0.15, clampf((t - 0.15) / 0.5, 0.0, 1.0))
		_put(PUFFS, Transform3D(Basis.from_scale(Vector3(s, s * 0.92, s)), pos), c, emit)


func _pose_flaps(e: Dictionary, t: float) -> void:
	var r := hole_radius(float(e["radius"]), float(e["open"]), t)
	if r < 0.03:
		return
	var center: Vector3 = e["center"]
	var seed: float = e["seed"]
	var n: int = e["n"]
	var phase: float = e["phase"]
	var target: PackedFloat32Array = e["target"]
	var color: Color = e["color"]
	var bounds: Rect2 = e["bounds"]
	var has_bounds := bounds.has_area()
	for i in range(n):
		var a := phase + TAU * float(i) / float(n)
		var rr := r * (1.0 + jag(a, seed))
		var out := Vector3(cos(a), 0.0, sin(a))
		if has_bounds:
			rr = minf(rr, _reach(bounds, Vector2(center.x, center.z), Vector2(out.x, out.z)) - 0.04)
			if rr < 0.05:
				continue
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		# 下へ折れる（行きすぎない）。少しだけ揺れる
		var th := target[i] * (1.0 - exp(-9.0 * t)) + 0.06 * sin(8.0 * t + float(i)) * exp(-1.5 * t)
		var z_axis := (-out * cos(th) + Vector3.DOWN * sin(th)) * minf(rr * 0.95, FLAP_MAX_LENGTH)
		var x_axis := tangent * (TAU * rr / float(n) * 1.12)
		var y_axis := z_axis.cross(x_axis).normalized()
		_put(FLAPS, Transform3D(Basis(x_axis, y_axis, z_axis), center + out * rr), color.lightened(0.05 * float(i % 3)))


func _pose_ring(e: Dictionary, t: float) -> void:
	var u := clampf(t / float(e["life"]), 0.0, 1.0)
	var r := lerpf(float(e["r0"]), float(e["r1"]), _ease_out(u))
	var c: Color = e["color"]
	c.a *= pow(1.0 - u, 1.5)
	_put(RINGS, Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), e["center"] as Vector3), c)


func _pose_flash(e: Dictionary, t: float) -> void:
	var u := clampf(t / float(e["life"]), 0.0, 1.0)
	var s := float(e["radius"]) * _ease_out(minf(u * 3.0, 1.0))
	var c: Color = e["color"]
	c.a *= (1.0 - u) * (1.0 - u)
	_put(FLASHES, Transform3D(Basis.from_scale(Vector3.ONE * maxf(s, 0.01)), e["center"] as Vector3), c)


func _put(kind: int, xf: Transform3D, c: Color, custom: float = 0.0) -> void:
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
	_buf[o + 16] = custom
	_buf[o + 17] = 0.0
	_buf[o + 18] = 0.0
	_buf[o + 19] = 0.0


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


# ---------------------------------------------------------------- 人形

func _doll_meshes(parts: Dictionary) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var roots: Array[Node] = []
	var pelvis: Variant = parts.get("pelvis")
	if pelvis is Node3D:
		roots.append(pelvis as Node)
	for key: Variant in parts:
		var v: Variant = parts[key]
		if v is MeshInstance3D:
			roots.append(v as Node)
		elif v is Array:
			for item: Variant in v as Array:
				if item is MeshInstance3D:
					roots.append(item as Node)
	for root: Node in roots:
		var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
		if root is MeshInstance3D:
			found.append(root)
		for node: Node in found:
			var mi := node as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree() and not out.has(mi):
				out.append(mi)
	return out


func _hide_doll(parts: Dictionary, meshes: Array[MeshInstance3D]) -> void:
	var pelvis: Variant = parts.get("pelvis")
	if pelvis is Node3D:
		(pelvis as Node3D).visible = false
	for mi: MeshInstance3D in meshes:
		if mi.is_visible_in_tree():
			mi.visible = false


func _mesh_color(mi: MeshInstance3D) -> Color:
	if mi.has_meta(CharacterToonPresets.BASE_COLOR_META):
		return CharacterToonPresets.get_base_color(mi)
	var mat := mi.material_override
	if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		mat = mi.get_active_material(0)
	if mat is BaseMaterial3D:
		var c := (mat as BaseMaterial3D).albedo_color
		return Color(c.r, c.g, c.b, 1.0)
	if mat is ShaderMaterial:
		var v: Variant = (mat as ShaderMaterial).get_shader_parameter(&"albedo_color")
		if v is Color:
			return v
	return Color(0.92, 0.92, 0.92)


## 箱を割る：[中心からのずれ, 大きさ] の列。level 0 は割らない、1 は長い辺を 2 つ、2 は長い 2 辺を 2 つずつ。
func _split_box(full: Vector3, level: int) -> Array:
	var cuts := [1, 1, 1]
	if level >= 1:
		var order := [0, 1, 2]
		order.sort_custom(func(a: int, b: int) -> bool: return full[a] > full[b])
		if full[order[0]] > 0.3:
			cuts[order[0]] = 2
		if level >= 2 and full[order[1]] > 0.25:
			cuts[order[1]] = 2
	var piece := Vector3(full.x / cuts[0], full.y / cuts[1], full.z / cuts[2])
	var out := []
	for ix in range(cuts[0]):
		for iy in range(cuts[1]):
			for iz in range(cuts[2]):
				var off := Vector3((ix + 0.5) * piece.x - full.x * 0.5, (iy + 0.5) * piece.y - full.y * 0.5, (iz + 0.5) * piece.z - full.z * 0.5)
				out.append([off, piece * 0.96])
	return out


# ---------------------------------------------------------------- 形と材質

func _mesh_for(kind: int) -> Mesh:
	match kind:
		CHIPS:
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			return quad
		PUFFS:
			var sphere := SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			sphere.radial_segments = 12
			sphere.rings = 6
			return sphere
		STARS:
			return _star_mesh()
		BLOCKS:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			return box
		FLAPS:
			return _flap_mesh()
		RINGS:
			return _ring_mesh()
		_:
			var ball := SphereMesh.new()
			ball.radius = 1.0
			ball.height = 2.0
			ball.radial_segments = 16
			ball.rings = 8
			return ball


func _material_for(kind: int) -> Material:
	match kind:
		PUFFS:
			var puff := ShaderMaterial.new()
			puff.shader = PUFF_SHADER
			return puff
		CHIPS, FLAPS:
			var bits := ShaderMaterial.new()
			bits.shader = BITS_SHADER
			return bits
		RINGS, FLASHES:
			var glow := ShaderMaterial.new()
			glow.shader = GLOW_SHADER
			glow.set_shader_parameter("mode", 0 if kind == RINGS else 1)
			return glow
		_:
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.roughness = 0.75
			if kind == STARS:
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			return mat


## 5 つの角の星（XZ の面、厚さ 0.25、外の半径 1）。
func _star_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i in range(10):
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		var r := 1.0 if i % 2 == 0 else 0.45
		pts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	var h := 0.125
	for i in range(10):
		var p := pts[i]
		var q := pts[(i + 1) % 10]
		for sign: float in [1.0, -1.0]:
			var c := Vector3(0.0, h * sign, 0.0)
			var a := p + Vector3(0.0, h * 0.4 * sign, 0.0)
			var b := q + Vector3(0.0, h * 0.4 * sign, 0.0)
			if sign > 0.0:
				st.add_vertex(c)
				st.add_vertex(b)
				st.add_vertex(a)
			else:
				st.add_vertex(c)
				st.add_vertex(a)
				st.add_vertex(b)
		var pt := p + Vector3(0.0, h * 0.4, 0.0)
		var pb := p - Vector3(0.0, h * 0.4, 0.0)
		var qt := q + Vector3(0.0, h * 0.4, 0.0)
		var qb := q - Vector3(0.0, h * 0.4, 0.0)
		st.add_vertex(pt)
		st.add_vertex(qt)
		st.add_vertex(qb)
		st.add_vertex(pt)
		st.add_vertex(qb)
		st.add_vertex(pb)
	st.generate_normals()
	return st.commit()


## 破れた紙の垂れ 1 枚：付け根が X（−0.5〜0.5）、先が +Z（1）。ふちは少しぎざぎざ。
func _flap_mesh() -> Mesh:
	var pts: Array[Vector3] = [Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.32, 0.0, 0.42), Vector3(0.12, 0.0, 0.62),
			Vector3(0.05, 0.0, 1.0), Vector3(-0.14, 0.0, 0.66), Vector3(-0.3, 0.0, 0.5)]
	var c := Vector3(0.0, 0.0, 0.4)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in range(pts.size()):
		st.add_vertex(c)
		st.add_vertex(pts[(i + 1) % pts.size()])
		st.add_vertex(pts[i])
	return st.commit()


## 光の輪：XZ の面の輪（内の半径 0.72、外 1）。UV.x が内から外へ 0〜1。
func _ring_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for i in range(seg):
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var i0 := Vector3(cos(a0), 0.0, sin(a0)) * 0.72
		var o0 := Vector3(cos(a0), 0.0, sin(a0))
		var i1 := Vector3(cos(a1), 0.0, sin(a1)) * 0.72
		var o1 := Vector3(cos(a1), 0.0, sin(a1))
		for v: Array in [[i0, 0.0], [o1, 1.0], [o0, 1.0], [i0, 0.0], [i1, 0.0], [o1, 1.0]]:
			st.set_uv(Vector2(float(v[1]), 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0] as Vector3)
	return st.commit()


# ---------------------------------------------------------------- 道具

func _rng() -> RandomNumberGenerator:
	_seed += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_base, _seed])
	return rng


static func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var r := sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(r * cos(a), z, r * sin(a))


static func _ease_out(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)

extends "res://tests/hud_diegetic_mock/lockon_video_runtime.gd"

## ロックオン枠に立体感を持たせる 3 案を、同じ実ゲームの中で順番に切り替えて録画するモック。
##   A 3D ボックス: 体を囲む箱の 8 つの角。ゆっくり回り、溜めると速く回りながら締まる。
##   B 厚みのある枠＋投影光: 四隅の枠に厚みと陰影を付け、床の着地点から光の線で投影する。
##   C 光の柱の檻: 四隅に光の柱を立て、上を細い梁でつないで囲う。回りながら締まる。
## 各案で「照準を外す→ロックオン→溜め続ける→PERFECT で発射→回避」を流す。クールダウンは編集で切る。
## 実行: Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 60 --write-movie <out.avi> --script res://tests/hud_diegetic_mock/lockon3d_bootstrap.gd

const VARIANTS_3D: Array[String] = ["a_box", "b_thick", "c_pillars"]
const CENTER_Y := 1.15
const PILLAR_HEIGHT := 2.3
const PILLAR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.55, 0.95, 1.0, 1.0);
varying float height01;
void vertex() {
	height01 = VERTEX.y + 0.5;
}
void fragment() {
	float fade = pow(1.0 - clamp(height01, 0.0, 1.0), 1.4);
	ALBEDO = tint.rgb * (0.12 + 0.75 * fade) * tint.a;
}
"""

var variant := ""
var variant_root: Node3D
var spin := 0.0
var solid_material: StandardMaterial3D
var xray_material: StandardMaterial3D
var guide_material_3d: StandardMaterial3D
var beam_material: StandardMaterial3D
var pillar_material: ShaderMaterial
var parts_a: Array[MeshInstance3D] = []
var guide_a: Array[MeshInstance3D] = []
var parts_b: Array[MeshInstance3D] = []
var guide_b: Array[MeshInstance3D] = []
var beams: Array[MeshInstance3D] = []
var pillars: Array[MeshInstance3D] = []
var caps: Array[MeshInstance3D] = []
var beams_top: Array[MeshInstance3D] = []
var bases: Array[Node3D] = []
var guide_c: Array[Node3D] = []

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
	# 平面の枠（前回の案）は使わない。
	frame_root.visible = false
	await frames(2)
	event("RECORD_START")
	for name in VARIANTS_3D:
		use_variant(name)
		event("VARIANT_START " + name)
		await attack_demo()
		event("VARIANT_END " + name)
		await wait_phase(ghost.Phase.AIMING, 900)
	event("RECORD_END")
	get_tree().quit(0)

func attack_demo() -> void:
	await glide_aim(func() -> Vector2: return survivor_offset() + Vector2(-3.0, 2.4), 55)
	await hold_aim(20)
	await glide_aim(survivor_offset, 60)
	await hold_aim(30)
	key(KEY_CTRL, true)
	# 溜め続けると 0.5 秒ごとに一周する。締まっては戻る様子を見せてから PERFECT 帯で離す。
	for i in range(75):
		await glide_aim(survivor_offset, 1)
	await charge_band(0.78, 0.86)
	key(KEY_CTRL, false)
	await frames(2)
	event("RELEASE power=%.2f perfect=%s" % [float(ghost.get("_last_charge_power")), str(ghost.get("_perfect_charge"))])
	await frames(1)
	await dodge(26)
	await wait_phase(ghost.Phase.COOLDOWN, 300)
	await frames(30)

func charge_band(low: float, high: float) -> void:
	for i in range(120):
		var charge := float(ghost.get("_charge_amount"))
		if charge >= low and charge <= high:
			return
		await glide_aim(survivor_offset, 1)

# --- 案の切り替え ---

func use_variant(name: String) -> void:
	if variant_root != null and is_instance_valid(variant_root):
		variant_root.queue_free()
	for list in [parts_a, guide_a, parts_b, guide_b, beams, pillars, caps, beams_top]:
		list.clear()
	bases.clear()
	guide_c.clear()
	variant = name
	spin = 0.0
	variant_root = Node3D.new()
	track(variant_root, world)
	solid_material = StandardMaterial3D.new()
	solid_material.emission_enabled = true
	solid_material.roughness = 0.32
	solid_material.metallic = 0.35
	solid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 体に隠れた部分も薄く透けて見えるようにする（X 線表示）。
	xray_material = live_material(Color(GHOST_COLOR, 0.2), 1.0)
	xray_material.render_priority = 9
	guide_material_3d = live_material(Color(PERFECT_COLOR, 0.35), 1.0)
	beam_material = glow_material(Color(GHOST_COLOR, 0.35), 1.6, true)
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	match name:
		"a_box":
			for k in range(24):
				parts_a.append(solid_part(variant_root))
				guide_a.append(guide_part(variant_root))
		"b_thick":
			for k in range(8):
				parts_b.append(solid_part(variant_root))
				guide_b.append(guide_part(variant_root))
			for k in range(4):
				var beam := box(Vector3.ONE, beam_material)
				variant_root.add_child(beam)
				beams.append(beam)
		"c_pillars":
			var shader := Shader.new()
			shader.code = PILLAR_SHADER
			pillar_material = ShaderMaterial.new()
			pillar_material.shader = shader
			for k in range(4):
				var pillar := box(Vector3.ONE, pillar_material)
				variant_root.add_child(pillar)
				pillars.append(pillar)
				caps.append(solid_part(variant_root))
				beams_top.append(solid_part(variant_root))
				var base := Node3D.new()
				variant_root.add_child(base)
				add_arc(base, 0.1, 0.2, 0.0, TAU, solid_material)
				bases.append(base)
				var dot := Node3D.new()
				variant_root.add_child(dot)
				add_arc(dot, 0.08, 0.15, 0.0, TAU, guide_material_3d)
				guide_c.append(dot)

func solid_part(parent: Node3D) -> MeshInstance3D:
	var part := box(Vector3.ONE, solid_material)
	part.material_overlay = xray_material
	parent.add_child(part)
	return part

func guide_part(parent: Node3D) -> MeshInstance3D:
	var part := box(Vector3.ONE, guide_material_3d)
	parent.add_child(part)
	return part

# --- 見た目の更新 ---

func apply_frame(aim: Vector3, power: float, spread: float, color: Color, alpha: float, show_guide: bool, phase: int) -> void:
	if variant_root == null or not is_instance_valid(variant_root):
		return
	# ふだんはゆっくり、溜めている間は速く回り、発射したら止まる（方向ロック）。
	var spin_speed := 0.0
	if phase == ghost.Phase.AIMING:
		spin_speed = deg_to_rad(120.0 if bool(ghost.get("_charging_input")) else 28.0)
	spin += spin_speed * STEP
	# 自己発光を控えめにして、日なたの上面と陰の側面の明るさの差（立体感）を残す。
	solid_material.albedo_color = Color(color.darkened(0.1), alpha)
	solid_material.emission = color
	solid_material.emission_energy_multiplier = 0.45
	xray_material.albedo_color = Color(color, 0.22 * alpha)
	beam_material.albedo_color = Color(color, 0.3 * alpha)
	beam_material.emission = color
	variant_root.visible = alpha > 0.01
	var guide_power := (PERFECT_MIN + PERFECT_MAX) * 0.5
	match variant:
		"a_box":
			variant_root.global_transform = Transform3D(Basis(Vector3.UP, spin), aim + Vector3(0.0, CENTER_Y, 0.0))
			layout_box(parts_a, box_half(power, spread), 0.3, 0.06)
			layout_box(guide_a, box_half(guide_power, 1.0), 0.22, 0.025)
			for part in guide_a:
				part.visible = show_guide
		"b_thick":
			var to_camera := camera.global_position - aim
			to_camera.y = 0.0
			variant_root.global_transform = Transform3D(Basis.looking_at(-to_camera.normalized(), Vector3.UP), aim + Vector3(0.0, CENTER_Y, 0.0))
			var half := frame_half(power, spread)
			layout_thick(parts_b, half, 0.42, 0.085, 0.17)
			layout_thick(guide_b, frame_half(guide_power, 1.0), 0.3, 0.03, 0.03)
			for part in guide_b:
				part.visible = show_guide
			# 床の着地点（投影機）から四隅へ伸びる光の線。
			var origin := Vector3(0.0, 0.05 - CENTER_Y, 0.0)
			var k := 0
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					stretch_between(beams[k], origin, Vector3(sx * half.x, sy * half.y, 0.0), 0.02)
					k += 1
		"c_pillars":
			variant_root.global_transform = Transform3D(Basis(Vector3.UP, spin + PI * 0.25), aim)
			pillar_material.set_shader_parameter("tint", Color(color, alpha))
			var r := lerpf(1.3, 0.95, power) * spread
			var guide_r := lerpf(1.3, 0.95, guide_power)
			var corners: Array[Vector3] = []
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					corners.append(Vector3(sx * r, 0.0, sz * r))
			# 隣り合う柱を梁でつなぐ順番（四角形の周）。
			var ring_order := [0, 1, 3, 2]
			for k in range(4):
				var c := corners[k]
				pillars[k].position = c + Vector3(0.0, PILLAR_HEIGHT * 0.5, 0.0)
				pillars[k].scale = Vector3(0.1, PILLAR_HEIGHT, 0.1)
				caps[k].position = c + Vector3(0.0, PILLAR_HEIGHT, 0.0)
				caps[k].scale = Vector3.ONE * 0.17
				bases[k].position = c + Vector3(0.0, 0.04, 0.0)
				guide_c[k].position = Vector3(signf(c.x) * guide_r, 0.05, signf(c.z) * guide_r)
				guide_c[k].visible = show_guide
				var a: Vector3 = corners[ring_order[k]]
				var b: Vector3 = corners[ring_order[(k + 1) % 4]]
				stretch_between(beams_top[k], a + Vector3.UP * PILLAR_HEIGHT, b + Vector3.UP * PILLAR_HEIGHT, 0.045)

## A の箱: 下は床すれすれ、上は頭の上。溜めると左右・前後・上下ともに締まる。
func box_half(power: float, spread: float) -> Vector3:
	var side := lerpf(1.0, 0.75, power) * spread
	return Vector3(side, minf(lerpf(1.07, 0.86, power) * spread, 1.1), side)

func frame_half(power: float, spread: float) -> Vector2:
	return Vector2(lerpf(1.15, 0.72, power) * spread, minf(lerpf(1.07, 0.86, power) * spread, 1.1))

## 箱の 8 つの角に、各軸へ伸びる 3 本の棒を置く。
func layout_box(bars: Array[MeshInstance3D], half: Vector3, arm: float, thickness: float) -> void:
	var k := 0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner := Vector3(sx * half.x, sy * half.y, sz * half.z)
				bars[k].position = corner - Vector3(sx * arm * 0.5, 0.0, 0.0)
				bars[k].scale = Vector3(arm, thickness, thickness)
				bars[k + 1].position = corner - Vector3(0.0, sy * arm * 0.5, 0.0)
				bars[k + 1].scale = Vector3(thickness, arm, thickness)
				bars[k + 2].position = corner - Vector3(0.0, 0.0, sz * arm * 0.5)
				bars[k + 2].scale = Vector3(thickness, thickness, arm)
				k += 3

## B の四隅のカギ。奥行き depth の厚みを持たせ、上から見下ろすカメラに上面と側面が見えるようにする。
func layout_thick(bars: Array[MeshInstance3D], half: Vector2, arm: float, thickness: float, depth: float) -> void:
	var k := 0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			bars[k].position = Vector3(sx * (half.x - arm * 0.5), sy * half.y, 0.0)
			bars[k].scale = Vector3(arm, thickness, depth)
			bars[k + 1].position = Vector3(sx * half.x, sy * (half.y - arm * 0.5), 0.0)
			bars[k + 1].scale = Vector3(thickness, arm, depth)
			k += 2

## 単位の箱を a から b まで伸ばす（ローカル座標）。
func stretch_between(part: MeshInstance3D, a: Vector3, b: Vector3, width: float) -> void:
	var direction := b - a
	var length := direction.length()
	if length < 0.001:
		return
	var rotation_basis := Basis(Quaternion(Vector3.UP, direction / length))
	part.transform = Transform3D(rotation_basis * Basis.from_scale(Vector3(width, length, width)), (a + b) * 0.5)

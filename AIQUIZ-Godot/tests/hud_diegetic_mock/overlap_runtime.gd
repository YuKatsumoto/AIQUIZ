extends "res://tests/hud_diegetic_mock/mock_runtime.gd"

## 案D（足元の HP リング）に、ゴーストの照準が生存プレイヤーへ重なってごちゃつく問題の改善案モック。
## スコア表示は廃止する前提なので、床の数字は出さない。案ごとに「照準を合わせただけ」と「チャージ 80%」を撮る。
## 実行: Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --script res://tests/hud_diegetic_mock/overlap_bootstrap.gd

const OVERLAP_OUT := "res://artifacts/hud_overlap_mock/"
const VARIANTS: Array[String] = ["baseline", "v1_concentric", "v2_spotlight", "v3_lockon"]
const CHARGES: Array[float] = [0.0, 0.8]
const PERFECT_MIN := 0.72
const PERFECT_MAX := 0.94
const POOL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.55, 0.95, 1.0, 1.0);
uniform float strength = 0.6;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float pool = smoothstep(1.0, 0.82, r) * mix(0.45, 1.0, 1.0 - r);
	ALBEDO = tint.rgb * pool * strength;
}
"""

func run() -> void:
	await setup_world()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OVERLAP_OUT))
	if not await enter_ghost_aiming():
		return
	hide_hud = true
	for variant in VARIANTS:
		for charge in CHARGES:
			clear_mock()
			camera = get_viewport().get_camera_3d()
			call("build_" + variant, charge)
			await frames(6)
			await capture_overlap("%s_c%02d" % [variant, int(round(charge * 100.0))])
	print("HUD_OVERLAP_MOCK done")
	get_tree().quit(0)

# --- 基準: 前回の案D（照準リングと外輪ゲージがそのまま HP リングに重なる） ---

func build_baseline(charge: float) -> void:
	survivor_hp_rings()
	ghost_common(false, charge)

# --- 改善1: 同心円で住み分け。HP は内側の太い実線、照準は外側の細い破線（満ちるとゲージ） ---

func build_v1_concentric(charge: float) -> void:
	survivor_hp_rings()
	hide_original_aim()
	var root := Node3D.new()
	track(root, world)
	follow_aim(root, 0.05)
	var count := 30
	var step := TAU / count
	for k in range(count):
		var a0 := PI + k * step
		var lit := (k + 0.5) / count <= charge
		var idle := Color(GHOST_COLOR, 0.75) if charge <= 0.0 else Color(0.25, 0.45, 0.55, 0.55)
		var material := glow_material(Color(0.92, 1.0, 1.0), 3.0, true) if lit else glow_material(idle, 1.0 if charge <= 0.0 else 0.2, true)
		add_arc(root, 1.1, 1.22, a0, a0 + step * 0.58, material)
	add_arc(root, 1.26, 1.32, PI + TAU * PERFECT_MIN, PI + TAU * PERFECT_MAX, glow_material(PERFECT_COLOR, 2.4, true))
	# プレイヤーに重なっていないときに狙いの中心が分かる小さな十字。
	var cross := glow_material(Color(GHOST_COLOR, 0.85), 1.4, true)
	for angle in [0.0, PI * 0.5]:
		var bar := box(Vector3(0.4, 0.01, 0.06), cross)
		bar.rotation.y = angle
		root.add_child(bar)
	haunt_label(false)

# --- 改善2: 照準を「サメが落とす光だまり」にする。輪郭のない光なので HP リングとぶつからない ---

func build_v2_spotlight(charge: float) -> void:
	survivor_hp_rings()
	hide_original_aim()
	# 溜めるほど光が絞られて明るくなり、PERFECT 帯に入ると金色に変わる。
	var perfect := charge >= PERFECT_MIN and charge <= PERFECT_MAX
	var color := PERFECT_COLOR if perfect else GHOST_COLOR
	var radius := lerpf(1.45, 1.1, charge)
	var height := 7.0
	var spot := SpotLight3D.new()
	track(spot, world)
	spot.light_color = color
	spot.light_energy = lerpf(5.0, 12.0, charge)
	spot.spot_range = height + 2.0
	spot.spot_angle = rad_to_deg(atan(radius / height))
	spot.spot_angle_attenuation = 0.5
	spot.shadow_enabled = true
	spot.rotation.x = -PI * 0.5
	follow_aim(spot, height)
	var pool := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	pool.mesh = plane
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = POOL_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("strength", lerpf(0.45, 0.8, charge))
	pool.material_override = material
	track(pool, world)
	follow_aim(pool, 0.02)
	haunt_label(false)

# --- 改善3: 照準を床から体の高さのロックオン枠に移す。床は HP 専用にする ---

func build_v3_lockon(charge: float) -> void:
	survivor_hp_rings()
	hide_original_aim()
	# 床には突進の着地点だけを小さく残す（プレイヤーに重なると体に隠れる）。
	var dot := Node3D.new()
	track(dot, world)
	follow_aim(dot, 0.05)
	add_arc(dot, 0.1, 0.2, 0.0, TAU, glow_material(Color(GHOST_COLOR, 0.9), 1.6, true))
	# 溜めるほど枠が締まり、PERFECT の大きさ（薄い金の枠）に重なると金色になる。
	var perfect := charge >= PERFECT_MIN and charge <= PERFECT_MAX
	var frame := Node3D.new()
	track(frame, world)
	bracket_frame(frame, lerpf(1.15, 0.68, charge), lerpf(1.3, 0.92, charge), glow_material(PERFECT_COLOR if perfect else GHOST_COLOR, 2.4, true), 0.07)
	var guide := lerpf(1.15, 0.68, (PERFECT_MIN + PERFECT_MAX) * 0.5)
	var guide_h := lerpf(1.3, 0.92, (PERFECT_MIN + PERFECT_MAX) * 0.5)
	if not perfect:
		bracket_frame(frame, guide, guide_h, glow_material(Color(PERFECT_COLOR, 0.45), 1.0, true), 0.035)
	followers.append(func() -> void:
		if is_instance_valid(frame):
			frame.global_transform = Transform3D(camera.global_basis, aim_point() + Vector3(0.0, 1.1, 0.0)))
	haunt_label(false)

func bracket_frame(parent: Node3D, half_w: float, half_h: float, material: StandardMaterial3D, thickness: float) -> void:
	material.no_depth_test = true
	material.render_priority = 10
	var arm := 0.34
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var horizontal := box(Vector3(arm, thickness, 0.01), material)
			horizontal.position = Vector3(sx * (half_w - arm * 0.5), sy * half_h, 0.0)
			parent.add_child(horizontal)
			var vertical := box(Vector3(thickness, arm, 0.01), material)
			vertical.position = Vector3(sx * half_w, sy * (half_h - arm * 0.5), 0.0)
			parent.add_child(vertical)

# --- 共通 ---

func survivor_hp_rings() -> void:
	for i in [1, 2]:
		if alive(i):
			floor_kit(i, false)

func hide_original_aim() -> void:
	var ring := ghost.get("_aim_ring") as Node3D
	var outer := ghost.get("_aim_outer_ring") as Node3D
	followers.append(func() -> void:
		if is_instance_valid(ring):
			ring.visible = false
		if is_instance_valid(outer):
			outer.visible = false)

## ゲーム側が毎フレーム動かしている照準リングの位置を、床の高さで返す。
func aim_point() -> Vector3:
	var ring := ghost.get("_aim_ring") as Node3D
	return Vector3(ring.global_position.x, StageConstants.FLOOR_TOP_Y, ring.global_position.z)

func follow_aim(node: Node3D, lift: float) -> void:
	followers.append(func() -> void:
		if is_instance_valid(node):
			node.global_position = aim_point() + Vector3(0.0, lift, 0.0))

func capture_overlap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OVERLAP_OUT + tag + ".png")
	print("HUD_OVERLAP_MOCK captured " + tag)

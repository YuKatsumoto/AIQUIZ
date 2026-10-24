extends Node

## パラシュート一式と水柱（assets/sudden_death/parachute/chute/）を Godot の本物の空・海で、本物の人形（ブロックマン）に付けて撮る。
## 形の切り替え（Packed・Half・Collapsed・Breath・Grounded）が 3 つのメッシュにあること（Risers は Grounded）、段ごとに重みが変わること、
## プレイヤーの色の塗り替え、ハンカチ、水柱の時間の進み方を確かめる。
##   Godot --path . --resolution 1600x900 --script res://tests/sudden_death_v2/chute_check_bootstrap.gd
## 出力：artifacts/sudden_death_v2/parachute/chute/<名前>.png と report.json。失敗があれば終了コード 1。

const StageScript = preload("res://scripts/world/stage_environment.gd")
const OUT := "res://artifacts/sudden_death_v2/parachute/chute/"
const SITE := Vector3(0.0, 0.0, 150.0)
const POSE_CANOPY := [
	["l_shoulder", "z", -150.0], ["r_shoulder", "z", 150.0], ["l_elbow", "z", 25.0], ["r_elbow", "z", -25.0],
	["l_hip", "x", -18.0], ["r_hip", "x", -12.0], ["l_knee", "x", 22.0], ["r_knee", "x", 14.0],
]
const AXES := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}

var camera: Camera3D
var report := {"failures": []}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var stage := StageScript.new()
	add_child(stage)
	stage.build(stage.gameplay_build_config())
	for child: Node in stage.get_children():
		if child is Node3D and not (String(child.name) in ["DirectionalLight3D", "Ocean"]):
			(child as Node3D).visible = false
	camera = Camera3D.new()
	camera.far = 4000.0
	add_child(camera)
	camera.make_current()

	var y := 60.0
	var shoulders := {}
	var canopies := {}
	for player in [1, 2]:
		var center := SITE + Vector3(-3.5 if player == 1 else 3.5, y, 0.0)
		var parts := _person(player == 1, center)
		var canopy := ParachuteCanopy.new()
		add_child(canopy)
		canopy.build(player == 1)
		var spine := parts.spine as Node3D
		var container := canopy.container_node()
		if container == null:
			_fail("コンテナがない")
		else:
			spine.add_child(container)
			container.position = Vector3(0.0, 0.22, -0.12)
		canopies[player] = canopy
		shoulders[player] = Transform3D(Basis.IDENTITY, spine.global_transform * Vector3(0.0, 0.45, -0.1))
	_check_structure(canopies[1])
	# 段ごと（P1 と P2 を並べる。P2 は 1 段少ない）
	var names := {1: "c1_bag_pilot", 2: "c2_half", 3: "c3_full"}
	for s in [1, 2, 3]:
		(canopies[1] as ParachuteCanopy).set_stage(s)
		(canopies[1] as ParachuteCanopy).snap()
		(canopies[2] as ParachuteCanopy).set_stage(maxi(s - 1, 1))
		(canopies[2] as ParachuteCanopy).snap()
		for p in [1, 2]:
			(canopies[p] as ParachuteCanopy).place(shoulders[p], 0.0)
		var snap: Dictionary = (canopies[1] as ParachuteCanopy).get_debug_snapshot()
		report["weights_stage_%d" % s] = snap.weights
		var want_half := 1.0 if s == 2 else 0.0
		var want_packed := 1.0 if s == 1 else 0.0
		if absf(float(snap.weights.Half) - want_half) > 0.01 or absf(float(snap.weights.Packed) - want_packed) > 0.01:
			_fail("段 %d の重みが違う %s" % [s, str(snap.weights)])
		await _shot(names[s], SITE + Vector3(0.0, y + 3.5, -24.0), SITE + Vector3(0.0, y + 3.2, 0.0), 40.0)
	# 開く動き（2 → 3、スナッチ）：行き過ぎてから決まる
	var c1 := canopies[1] as ParachuteCanopy
	c1.set_stage(2)
	c1.snap()
	c1.set_stage(3)
	var halves: Array[float] = []
	for i in range(30):
		c1.place(shoulders[1], 1.0 / 60.0)
		halves.append(float(c1.get_debug_snapshot().weights.Half))
	report["snatch_half_weights"] = halves
	if halves.min() > -0.01:
		_fail("全開になるとき行き過ぎない（Half の重みが 0 より下へ行かない）")
	if absf(halves.back()) > 0.02:
		_fail("全開で止まらない %f" % halves.back())
	# 下から見上げる
	await _shot("c4_full_below", SITE + Vector3(-3.0, y - 3.0, -4.0), SITE + Vector3(-3.5, y + 6.0, 0.0), 60.0)
	# 着地でつぶれる・ハンカチ
	c1.collapse = 1.0
	c1.place(shoulders[1], 0.0)
	var c2 := canopies[2] as ParachuteCanopy
	c2.set_stage(0)
	c2.show_hanky(true)
	c2.snap()
	c2.place(shoulders[2], 0.0)
	await _shot("c5_collapsed_hanky", SITE + Vector3(0.0, y + 2.0, -12.0), SITE + Vector3(0.0, y + 0.5, 2.0), 45.0)
	# 床に落ちる：drop_to のあと collapse 1 で、置き場所が床の点になり、Grounded の重みが 1
	var floor_at := Transform3D(Basis.IDENTITY, SITE + Vector3(-3.5, y - 1.45, -0.45))
	c1.drop_to(floor_at)
	c1.collapse = 1.0
	c1.place(shoulders[1], 0.0)
	var dropped := c1.get_debug_snapshot()
	report["grounded"] = dropped
	if c1.global_position.distance_to(floor_at.origin) > 0.001:
		_fail("床に落ちたパラシュートの原点が床の点にない %s" % str(c1.global_position))
	if absf(float(dropped.weights.Grounded) - 1.0) > 0.001 or absf(float(dropped.weights.Collapsed)) > 0.001:
		_fail("床に落ちた形の重みが違う %s" % str(dropped.weights))
	await _shot("c6_grounded", SITE + Vector3(-1.0, y + 1.2, 4.5), SITE + Vector3(-3.5, y - 1.3, -1.5), 50.0)
	# 水柱
	var splash := WaterSplash.new()
	add_child(splash)
	splash.build()
	splash.global_position = Vector3(SITE.x + 30.0, StageConstants.OCEAN_SURFACE_Y, SITE.z)
	for t: float in [0.15, 0.5, 1.2, 2.0]:
		splash.pose_at(t)
		await _shot("s_%03d" % int(t * 100), Vector3(SITE.x + 30.0, StageConstants.OCEAN_SURFACE_Y + 3.0, SITE.z - 22.0),
			Vector3(SITE.x + 30.0, StageConstants.OCEAN_SURFACE_Y + 4.5, SITE.z), 45.0)
	var f := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("CHUTE_CHECK ", JSON.stringify({"failures": report.failures, "weights": report.get("weights_stage_2", {})}))
	get_tree().quit(1 if not (report.failures as Array).is_empty() else 0)


func _check_structure(canopy: ParachuteCanopy) -> void:
	var meshes := {}
	for node: Node in canopy.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var shapes: Array[String] = []
		if mi.mesh is ArrayMesh:
			for i in range((mi.mesh as ArrayMesh).get_blend_shape_count()):
				shapes.append(String((mi.mesh as ArrayMesh).get_blend_shape_name(i)))
		var accent := false
		for s in range(mi.mesh.get_surface_count()):
			var o := mi.get_surface_override_material(s) as StandardMaterial3D
			if o != null and o.albedo_color.is_equal_approx(ParachuteCanopy.P1_COLORS[0]):
				accent = true
		meshes[String(mi.name)] = {"shapes": shapes, "accent": accent, "tris": mi.mesh.get_faces().size() / 3}
	report["meshes"] = meshes
	for name: String in ["Canopy", "Lines", "Slider"]:
		var shapes: Array = meshes.get(name, {}).get("shapes", [])
		for shape: String in ["Packed", "Half", "Collapsed", "Breath", "Grounded"]:
			if not shapes.has(shape):
				_fail("%s に形の切り替え %s がない" % [name, shape])
	if not (meshes.get("Risers", {}).get("shapes", []) as Array).has("Grounded"):
		_fail("Risers に形の切り替え Grounded がない（着地のあと床に寝ない）")
	if not bool(meshes.get("Canopy", {}).get("accent", false)):
		_fail("布がプレイヤーの色に塗られていない")
	for name: String in ["PilotChute", "Bridle", "DeployBag", "Hanky", "Risers"]:
		if not meshes.has(name):
			_fail("部品がない：" + name)


func _person(is_p1: bool, center: Vector3) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	root.global_position = center
	var parts: Dictionary = EmoteBlockmanPreview.build_player_skeleton(is_p1, root, HatData.HAT_PROPELLER if is_p1 else HatData.HAT_FOX)
	for row: Array in POSE_CANOPY:
		var node := parts[row[0]] as Node3D
		var a := (root.global_basis * (AXES[row[1]] as Vector3)).normalized()
		node.global_basis = Basis(a, deg_to_rad(float(row[2]))) * node.global_basis
	return parts


func _shot(name: String, eye: Vector3, target: Vector3, fov: float) -> void:
	camera.fov = fov
	camera.look_at_from_position(eye, target)
	for _i in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png"))


func _fail(text: String) -> void:
	(report.failures as Array).append(text)

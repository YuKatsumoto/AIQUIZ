extends Node

## 着地台（assets/sudden_death/parachute/landing_float/）を Godot の本物の海・空に浮かべ、勝者のプレイヤー（ブロックマン）を乗せて撮る。
## あわせて、取り込んだ GLB の部品・材質（テクスチャ・粗さ・発光）とマーカーの位置を確かめる（旗は 2026-10-18 になくした）。
##   Godot --path . --resolution 1600x900 --script res://tests/sudden_death_v2/landing_float_check_bootstrap.gd
## 出力：artifacts/sudden_death_v2/parachute/landing_float/<名前>.png と report.json。失敗があれば終了コード 1。

const StageScript = preload("res://scripts/world/stage_environment.gd")
const GLB := "res://assets/sudden_death/parachute/landing_float/landing_float.glb"
const LAYOUT := "res://assets/sudden_death/parachute/landing_float/landing_float_layout.json"
const OUT := "res://artifacts/sudden_death_v2/parachute/landing_float/"
const SITE := Vector3(0.0, StageConstants.OCEAN_SURFACE_Y, 150.0)
const PLAYER_FOOT := 1.32
const EXPECTED := ["Tube", "Pad", "Rubber", "Metal", "Rope", "Lamps", "Tally", "CameraBody", "Piping"]
const POSE_WIN := [
	["l_shoulder", "z", -160.0], ["r_shoulder", "z", 160.0], ["l_elbow", "z", -12.0], ["r_elbow", "z", 12.0],
	["l_hip", "z", -8.0], ["r_hip", "z", 8.0], ["head_pivot", "x", -10.0],
]
const AXES := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}

var camera: Camera3D
var float_root: Node3D
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

	var scene := load(GLB) as PackedScene
	if scene == null:
		_fail("GLB が読めない")
		_finish()
		return
	float_root = scene.instantiate() as Node3D
	add_child(float_root)
	float_root.position = SITE
	_check_structure()

	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var land: Array = layout.markers.MK_LandCenter
	var land_pos := SITE + Vector3(land[0], land[1], land[2])
	var winner := _player(true, land_pos + Vector3(0.5, PLAYER_FOOT, 0.35), POSE_WIN)
	report["land_center"] = [land_pos.x, land_pos.y, land_pos.z]
	report["winner_feet"] = (winner.root as Node3D).global_position.y - PLAYER_FOOT
	await _frames(20)

	await _shot("lf_godot_hero", SITE + Vector3(3.0, 2.1, 9.0), SITE + Vector3(0.2, 1.3, 0.0), 48.0)
	await _shot("lf_godot_low", SITE + Vector3(-6.5, 0.9, 6.0), SITE + Vector3(0.0, 1.2, 0.0), 52.0)
	await _shot("lf_godot_deck", SITE + Vector3(1.6, 3.4, 4.2), SITE + Vector3(0.0, 0.8, -0.6), 50.0)
	await _shot("lf_godot_back", SITE + Vector3(0.6, 2.0, -8.5), SITE + Vector3(0.0, 1.2, 0.0), 46.0)
	await _shot("lf_godot_top260", SITE + Vector3(0.0, 260.0, 0.01), SITE, 50.0)
	await _shot("lf_godot_top60", SITE + Vector3(0.0, 60.0, 0.01), SITE, 50.0)
	_finish()


func _check_structure() -> void:
	var meshes := {}
	for node: Node in float_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mat := mi.get_active_material(0) as StandardMaterial3D
		var info := {"tris": mi.mesh.get_faces().size() / 3}
		if mat != null:
			info["texture"] = mat.albedo_texture != null
			info["rough_texture"] = mat.roughness_texture != null
			info["emission"] = mat.emission_enabled
			info["cull"] = mat.cull_mode
		meshes[String(mi.name)] = info
	report["meshes"] = meshes
	for name: String in EXPECTED:
		if not meshes.has(name):
			_fail("部品がない：" + name)
	for name: String in ["Tube", "Pad"]:
		if meshes.has(name) and not (meshes[name].get("texture", false) and meshes[name].get("rough_texture", false)):
			_fail(name + " のテクスチャか粗さがない")
	for name: String in ["Lamps", "Tally"]:
		if meshes.has(name) and not meshes[name].get("emission", false):
			_fail(name + " が光らない")
	if meshes.has("Flags"):
		_fail("旗は 2026-10-18 になくした")
	var markers := float_root.find_children("MK_*", "Node3D", true, false)
	report["markers"] = markers.size()
	if markers.size() < 5:
		_fail("マーカーが足りない：%d" % markers.size())


func _player(is_p1: bool, center: Vector3, pose: Array) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(Basis.IDENTITY, center)
	var parts: Dictionary = EmoteBlockmanPreview.build_player_skeleton(is_p1, root, HatData.HAT_PROPELLER)
	parts["root"] = root
	for row: Array in pose:
		var node := parts[row[0]] as Node3D
		var a := (root.global_basis * (AXES[row[1]] as Vector3)).normalized()
		node.global_basis = Basis(a, deg_to_rad(float(row[2]))) * node.global_basis
	return parts


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _shot(name: String, eye: Vector3, target: Vector3, fov: float) -> void:
	camera.fov = fov
	camera.look_at_from_position(eye, target, Vector3.UP if absf((target - eye).normalized().y) < 0.99 else Vector3.FORWARD)
	await _frames(6)
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT + name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	report[name] = path


func _fail(text: String) -> void:
	(report.failures as Array).append(text)


func _finish() -> void:
	var f := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("LANDING_FLOAT_CHECK ", JSON.stringify(report))
	get_tree().quit(1 if not (report.failures as Array).is_empty() else 0)

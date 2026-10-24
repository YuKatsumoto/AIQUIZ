class_name SkyFallIslands
extends Node3D

## スカイゲートの見下ろしの島（docs/sudden_death_v2/sky_fx.md 第3章）。着地台（LandingFloat）のまわりに、
## スタジアムの遠景と同じ作りの島（木・砂浜・浅瀬・礁の白波・ヤシ、assets/sudden_death/sky_fx/sky_fx_islands.glb）を置く。
## 原点＝着地台の中心 × 海面（top_level。SkyFallScenery.set_landing_point で動かす）。並びは sky_fx_layout.json。
## 高い所では軽い作り（*_Lo）、カメラが島に近づくと細かい作り（*_Hi）に替える。帆船と小舟が走り、航跡を引く。
## 着地台は礁の外の深い青の上（いちばん近い島 Main の礁の縁から約 40 m）。

const ISLANDS_GLB := "res://assets/sudden_death/sky_fx/sky_fx_islands.glb"
const BOATS_GLB := "res://assets/sudden_death/sky_fx/sky_fx_boats.glb"
const LAYOUT := "res://assets/sudden_death/sky_fx/sky_fx_layout.json"
const ISLAND_SHADER := preload("res://shaders/sky_fx_island.gdshader")
const SURF_SHADER := preload("res://shaders/sky_fx_surf.gdshader")
const STREAK_SHADER := preload("res://shaders/sky_fx_streak.gdshader")
## 細かい作りに替える距離の余裕（行ったり来たりしないように）。
const LOD_HYSTERESIS := 40.0
const WAKE_LENGTH := 26.0
## 船と航跡はカメラからこれより遠いと描かない（高い所からは数 px で見えないので、描く回数を減らす）。
const BOAT_FAR := 650.0

var quality := ""
var low := false
var camera: Camera3D = null
var layout := {}
## name -> {"hi": MeshInstance3D, "lo": MeshInstance3D, "surf": MeshInstance3D, "center": Vector3, "far": float, "near": bool}
var islands := {}
var _model: Node3D = null
## すべての島の白波（1 つのメッシュ。いつも見える）
var _surf: MeshInstance3D = null
var _island_mat: ShaderMaterial = null
var _surf_mat: ShaderMaterial = null
var _boat_paint: StandardMaterial3D = null
var _boat_sail: StandardMaterial3D = null
var _routes: Array = []
var _boat_nodes: Array[Node3D] = []
var _moored: Array[Node3D] = []
var _wake_mesh: ImmediateMesh = null
var _wake_node: MeshInstance3D = null
var _time := 0.0


func build(p_quality: String) -> void:
	for child: Node in get_children():
		child.queue_free()
	islands.clear()
	_boat_nodes.clear()
	_moored.clear()
	quality = GraphicsQuality.normalize(p_quality)
	low = quality == GraphicsQuality.LOW
	top_level = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	layout = parsed if parsed is Dictionary else {}
	_island_mat = ShaderMaterial.new()
	_island_mat.shader = ISLAND_SHADER
	_surf_mat = ShaderMaterial.new()
	_surf_mat.shader = SURF_SHADER
	_surf_mat.render_priority = -8
	_boat_paint = StandardMaterial3D.new()
	_boat_paint.vertex_color_use_as_albedo = true
	_boat_paint.roughness = 0.8
	_boat_sail = StandardMaterial3D.new()
	_boat_sail.vertex_color_use_as_albedo = true
	_boat_sail.cull_mode = BaseMaterial3D.CULL_DISABLED
	_boat_sail.roughness = 0.9
	var scene := load(ISLANDS_GLB) as PackedScene
	if scene == null:
		push_warning("SkyFallIslands: %s が読めない" % ISLANDS_GLB)
		return
	_model = scene.instantiate() as Node3D
	_model.name = "IslandModel"
	add_child(_model)
	var by_name := {}
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		by_name[String(mi.name)] = mi
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var n := String(mi.name)
		if n.begins_with("SFI_Surf") or n.ends_with("_Surf"):
			mi.material_override = _surf_mat
		elif n.ends_with("_Pier"):
			mi.material_override = _boat_paint
		else:
			mi.material_override = _island_mat
	_surf = by_name.get(String(layout.get("surf", ""))) as MeshInstance3D
	for entry: Dictionary in layout.get("islands", []):
		var c: Array = entry.center
		var rec := {
			"hi": by_name.get(entry.hi), "lo": by_name.get(entry.lo), "surf": by_name.get(entry.get("surf", "")),
			"pier": by_name.get(entry.get("pier", "")),
			"center": Vector3(float(c[0]), float(c[1]), float(c[2])), "far": float(entry.lod_far), "near": false,
		}
		islands[String(entry.name)] = rec
		_set_detail(rec, false)
	_build_boats()


func _build_boats() -> void:
	var scene := load(BOATS_GLB) as PackedScene
	if scene == null:
		return
	var src := scene.instantiate() as Node3D
	var protos := {}
	for node: Node in src.find_children("*", "MeshInstance3D", true, false):
		protos[String(node.name)] = (node as MeshInstance3D).mesh
	src.free()
	var boats_root := Node3D.new()
	boats_root.name = "Boats"
	add_child(boats_root)
	var routes: Array = layout.get("sail_routes", [])
	if low:
		routes = routes.slice(0, 3)
	for r: Dictionary in routes:
		var mesh := protos.get(String(r.boat)) as Mesh
		if mesh == null:
			continue
		var mi := _boat_instance(mesh)
		boats_root.add_child(mi)
		var a: Array = r.from
		var b: Array = r.to
		_routes.append({"from": Vector3(float(a[0]), 0.0, float(a[2])), "to": Vector3(float(b[0]), 0.0, float(b[2])),
			"speed": float(r.speed), "node": mi, "phase": float(_routes.size()) * 0.31})
		_boat_nodes.append(mi)
	var pier: Variant = layout.get("pier")
	if pier is Dictionary and protos.has("SFB_Motor"):
		var yaw := deg_to_rad(float(pier.get("yaw_deg", 0.0)))
		for m: Array in pier.get("moorings", []):
			var mi := _boat_instance(protos.SFB_Motor)
			boats_root.add_child(mi)
			mi.position = Vector3(float(m[0]), 0.05, float(m[2]))
			mi.rotation = Vector3(0.0, yaw + (PI if _moored.size() % 2 == 1 else 0.0), 0.0)
			mi.visible = false
			_moored.append(mi)
	_wake_mesh = ImmediateMesh.new()
	var wake_mat := ShaderMaterial.new()
	wake_mat.shader = STREAK_SHADER
	wake_mat.set_shader_parameter("opacity", 0.8)
	wake_mat.set_shader_parameter("flow_speed", 0.6)
	wake_mat.set_shader_parameter("grain", 10.0)
	wake_mat.set_shader_parameter("edge_soft", 0.9)
	wake_mat.set_shader_parameter("tail_power", 1.6)
	wake_mat.render_priority = -8
	_wake_node = MeshInstance3D.new()
	_wake_node.name = "Wakes"
	_wake_node.mesh = _wake_mesh
	_wake_node.material_override = wake_mat
	_wake_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wake_node.extra_cull_margin = 2048.0
	boats_root.add_child(_wake_node)


func _boat_instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in range(mesh.get_surface_count()):
		var m := mesh.surface_get_material(s)
		var sail := m != null and String(m.resource_name).contains("Sail")
		mi.set_surface_override_material(s, _boat_sail if sail else _boat_paint)
	return mi


func _set_detail(rec: Dictionary, near: bool) -> void:
	rec.near = near
	if rec.hi != null:
		(rec.hi as MeshInstance3D).visible = near
	if rec.lo != null:
		(rec.lo as MeshInstance3D).visible = not near or rec.hi == null
	if rec.pier != null:
		(rec.pier as MeshInstance3D).visible = near
		for boat: Node3D in _moored:
			boat.visible = near


## 着地台の中心（ワールド、海面の高さ）と、画面の上の向き（ゴールの側。水平）。
func place(landing_point: Vector3, forward: Vector3) -> void:
	var f := Vector3(forward.x, 0.0, forward.z)
	f = f.normalized() if f.length() > 1e-4 else Vector3.FORWARD
	global_transform = Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), landing_point)


func advance(delta: float) -> void:
	_time += delta
	var cam := camera if camera != null and is_instance_valid(camera) else get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var eye := cam.global_position
		for key: String in islands:
			var rec: Dictionary = islands[key]
			var d := eye.distance_to(global_transform * (rec.center as Vector3))
			var far := float(rec.far)
			if rec.near and d > far + LOD_HYSTERESIS:
				_set_detail(rec, false)
			elif not rec.near and d < far - LOD_HYSTERESIS:
				_set_detail(rec, true)
	_update_boats(cam)


func _update_boats(cam: Camera3D) -> void:
	if _wake_mesh == null:
		return
	_wake_mesh.clear_surfaces()
	var opened := false
	for r: Dictionary in _routes:
		var from: Vector3 = r.from
		var to: Vector3 = r.to
		var length := from.distance_to(to)
		var t := fposmod(_time * float(r.speed) / length + float(r.phase), 1.0)
		var dir := (to - from).normalized()
		var pos := from.lerp(to, t)
		var node := r.node as Node3D
		node.position = pos + Vector3(0.0, sin(_time * 1.3 + float(r.phase) * 9.0) * 0.08, 0.0)
		node.rotation = Vector3(0.0, atan2(-dir.z, dir.x), sin(_time * 0.9 + float(r.phase) * 5.0) * 0.04)
		var fade := smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.94, 1.0, t))
		node.scale = Vector3.ONE * maxf(fade, 0.001)
		node.visible = cam == null or cam.global_position.distance_to(node.global_position) < BOAT_FAR
		if not node.visible:
			continue
		if not opened:
			_wake_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			opened = true
		_emit_wake(pos, dir, float(r.speed), fade)
	if opened:
		_wake_mesh.surface_end()


## 航跡：船尾から後ろへ広がる V の 2 本と、真ん中の泡の帯。
func _emit_wake(pos: Vector3, dir: Vector3, speed: float, alpha: float) -> void:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var length := WAKE_LENGTH * clampf(speed / 3.0, 0.8, 2.2)
	var stern := pos - dir * 4.0 + Vector3(0.0, 0.15, 0.0)
	for arm: float in [-1.0, 0.0, 1.0]:
		var spread := 0.32 * arm
		var w0 := 0.8 if arm == 0.0 else 0.5
		var segs := 6
		for i in range(segs):
			var t0 := float(i) / segs
			var t1 := float(i + 1) / segs
			var c0 := stern - dir * length * t0 + side * spread * length * t0
			var c1 := stern - dir * length * t1 + side * spread * length * t1
			var hw0 := (w0 + 2.2 * t0) * 0.5
			var hw1 := (w0 + 2.2 * t1) * 0.5
			var col := Color(arm * 0.3 + 0.5, 0.0, 0.0, alpha * (0.9 if arm == 0.0 else 0.75))
			var quad := [[c0 - side * hw0, t0, 0.0], [c0 + side * hw0, t0, 1.0], [c1 + side * hw1, t1, 1.0],
				[c0 - side * hw0, t0, 0.0], [c1 + side * hw1, t1, 1.0], [c1 - side * hw1, t1, 0.0]]
			for v: Array in quad:
				_wake_mesh.surface_set_color(col)
				_wake_mesh.surface_set_uv(Vector2(float(v[1]), float(v[2])))
				_wake_mesh.surface_add_vertex(v[0] as Vector3)


func stats() -> Dictionary:
	var draws := 0
	var tris := 0
	var near := []
	for key: String in islands:
		var rec: Dictionary = islands[key]
		for k: String in ["hi", "lo", "surf", "pier"]:
			var mi := rec.get(k) as MeshInstance3D
			if mi != null and mi.is_visible_in_tree():
				draws += 1
		if rec.near:
			near.append(key)
	if _surf != null and _surf.is_visible_in_tree():
		draws += 1
	for boat: Node3D in _boat_nodes + _moored:
		if boat.is_visible_in_tree():
			draws += (boat as MeshInstance3D).mesh.get_surface_count()
	if _wake_mesh != null and _wake_mesh.get_surface_count() > 0:
		draws += 1
	return {"draws": draws, "near": near, "boats": _boat_nodes.size(), "moored": _moored.size()}

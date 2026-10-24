class_name LandingFloat
extends Node3D

## 着地台（assets/sudden_death/parachute/landing_float/、docs/sudden_death_v2/parachute.md 6.5節）を海に浮かべる。
## 原点＝浮き台の中心 × 喫水線。波に合わせた上下と傾き、着地の沈み込み、標識灯の点滅、中継カメラの赤い灯を受け持つ。
## マーカーは landing_float_layout.json（Godot の座標、原点から）。

const GLB := "res://assets/sudden_death/parachute/landing_float/landing_float.glb"
const LAYOUT := "res://assets/sudden_death/parachute/landing_float/landing_float_layout.json"
const LAMP_PERIOD := 2.0
const DIP_DEPTH := 0.15
const DIP_TIME := 0.7

var model: Node3D = null
var markers := {}
var pad_top := 0.697
## 海面の高さ（ワールド）。毎フレーム float_at() で渡す。
var sea_y := 0.0
var _time := 0.0
var _dip_at := -INF
var _lamp_material: BaseMaterial3D = null
var _tally_material: BaseMaterial3D = null
var _tally_on := false


func build() -> bool:
	var scene := load(GLB) as PackedScene
	if scene == null:
		return false
	model = scene.instantiate() as Node3D
	model.name = "LandingFloatModel"
	add_child(model)
	var text := FileAccess.get_file_as_string(LAYOUT)
	var layout: Variant = JSON.parse_string(text)
	if layout is Dictionary:
		for key: String in (layout as Dictionary).get("markers", {}):
			var p: Array = layout.markers[key]
			markers[key] = Vector3(float(p[0]), float(p[1]), float(p[2]))
		pad_top = float(layout.get("pad_top", pad_top))
	if markers.has("MK_LandCenter"):
		pad_top = (markers.MK_LandCenter as Vector3).y
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name == "Lamps":
			_lamp_material = (mi.get_active_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
			mi.material_override = _lamp_material
		elif mi.name == "Tally":
			_tally_material = (mi.get_active_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
			mi.material_override = _tally_material
	set_tally(false)
	return true


## 海面のこの位置に浮かべる（ワールドの x, z と海面の高さ）。
func float_at(center: Vector3, sea_height: float, delta: float) -> void:
	_time += delta
	sea_y = sea_height
	var bob := sin(_time * 0.9) * 0.05 + sin(_time * 1.7 + 1.3) * 0.025
	var dip := 0.0
	var since := _time - _dip_at
	if since >= 0.0 and since < DIP_TIME:
		dip = -DIP_DEPTH * sin(PI * since / DIP_TIME) * (1.0 - since / DIP_TIME * 0.4)
	var tilt := Basis(Vector3.RIGHT, sin(_time * 0.7) * 0.02) * Basis(Vector3.BACK, sin(_time * 0.55 + 0.8) * 0.025)
	global_transform = Transform3D(tilt, Vector3(center.x, sea_height + bob + dip, center.z))
	if _lamp_material != null:
		var on := fposmod(_time, LAMP_PERIOD) < 0.25
		_lamp_material.emission_energy_multiplier = 4.0 if on else 0.6
	if _tally_material != null:
		_tally_material.emission_energy_multiplier = (5.0 if fposmod(_time, 1.0) < 0.75 else 2.0) if _tally_on else 0.0


## 着地の瞬間：0.15m 沈んで戻る。
func dip() -> void:
	_dip_at = _time


func set_tally(on: bool) -> void:
	_tally_on = on


## マーカーのワールドの位置（なければ原点からの offset）。
func marker(name: String, fallback := Vector3.ZERO) -> Vector3:
	return global_transform * (markers.get(name, fallback) as Vector3)


## 着地点（クッションの上面）のワールドの位置。
func land_point() -> Vector3:
	return global_transform * Vector3(0.0, pad_top, 0.0)

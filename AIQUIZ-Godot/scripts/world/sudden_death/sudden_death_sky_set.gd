class_name SuddenDeathSkySet
extends Node3D

## 空のセット（docs/sudden_death_v2/common.md 第6章）。2機のヘリが並んで飛ぶ間の背景。
## オンライン演出と同じく、ヘリを原点の近くに置いたまま、海の模様（flow_offset）と雲（StagingClouds）を
## 後ろへ流して飛んでいるように見せる。本編の舞台は隠しておく（監督が雲の覆いの中で切り替える）。
## 原点（このノードの位置）＝2機の並びの中心。海は FLY_HEIGHT 下、雲は30m下と25m上。

const OceanDetailScript = preload("res://scripts/world/ocean_detail.gd")
## 海面からの高さ（オンラインの検索中と同じ）。
const FLY_HEIGHT := 70.0
## 流す速さ（m/秒）。
const FLOW_SPEED := 24.0
## 進む向き（ワールド）。
const FORWARD := Vector3(0, 0, -1)

var ocean: MeshInstance3D = null
var clouds: StagingClouds = null
var flow_distance := 0.0
var _flow_offset := Vector2.ZERO
var _quality := ""


func build(quality: String, sun_direction: Vector3) -> void:
	_quality = quality
	for child: Node in get_children():
		child.queue_free()
	ocean = StageEnvironment.create_ocean_surface()
	ocean.name = "SkyOcean"
	add_child(ocean)
	StageEnvironment.configure_ocean_surface(ocean, quality)
	ocean.position = Vector3(0.0, -FLY_HEIGHT, 0.0)
	OceanDetailScript.set_sun(ocean.material_override as ShaderMaterial, sun_direction)
	clouds = StagingClouds.new()
	clouds.name = "SkyClouds"
	add_child(clouds)
	clouds.build(quality, FORWARD)
	flow_distance = 0.0
	_flow_offset = Vector2.ZERO
	_apply_flow()


## 流れた距離（m）だけ海と雲を後ろへずらす。
func advance(distance: float) -> void:
	if distance == 0.0 or clouds == null:
		return
	flow_distance += distance
	_flow_offset += Vector2(FORWARD.x, FORWARD.z) * distance
	_apply_flow()
	clouds.advance(distance)


func _apply_flow() -> void:
	if ocean == null:
		return
	var material := ocean.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("flow_offset", _flow_offset)

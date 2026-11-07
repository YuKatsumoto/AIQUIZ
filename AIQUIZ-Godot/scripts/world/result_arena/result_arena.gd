class_name ResultArena
extends Node3D

## エンドレスの2人の両者脱落の結果発表を行う、海上の専用アリーナ（assets/result_arena。Blender で作った：source/build_result_arena.py）。
## GameWorld が暗転のあいだに結果発表の舞台の中心（ResultCeremonyDirector.podium_center）へ出し、コースを隠す。
## 10問チャレンジでは使わない（両者脱落はハテナの投げ縄でコースのゴールへ運び、ゴール観客席で結果発表する）。
##
## - 円形の舞台（RA_Deck）。中央のフタ（RA_Lid）はサドンデスの縦穴と同じ半径で、縦穴が開いているあいだは外す
## - 正面スタンドと大型モニター：GoalStand をアリーナの建物（result_arena_stand.glb）で組む。観客の応援・卵・ボード・
##   ダンスと LED の番組はゴール観客席と同じで、GameWorld はこれを _goal_stand として動かす
## - 左右の座席スタンド（RA_WingR が P1 の側、RA_WingL が P2 の側）：コースの客席と同じ座った観客（GrandstandCrowd）
## - 照明塔（RA_Masts）。夜の灯はスタジアムと共有の材質（AiquizStadiumMaterials）なので天気に合わせて灯る
##
## 座標：原点は舞台の中心の床の上面。結果発表のカメラは +Z を向き、正面スタンドはその先（layout の stand_offset）に立つ。

const ARENA_SCENE: PackedScene = preload("res://assets/result_arena/result_arena.glb")
const STAND_SCENE: PackedScene = preload("res://assets/result_arena/result_arena_stand.glb")
const LAYOUT_PATH := "res://assets/result_arena/result_arena_layout.json"
const StadiumMaterials = preload("res://scripts/world/aiquiz_stadium/aiquiz_stadium_materials.gd")
const CrowdScript = preload("res://scripts/world/grandstand_crowd.gd")
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
## 左右の座席スタンドの埋まり方（コースの客席の既定と同じ）
const WING_DENSITY := 0.85
const CROWD_SEED := 0x5A7E

var stand: GoalStand = null
## 左右の座席スタンドの観客（GrandstandCrowd）
var wing_crowds: Array[Node3D] = []
var _lid: Node3D = null
var _stage_env: StageEnvironment = null


func setup(graphics_quality: String, stage_env: StageEnvironment = null) -> void:
	name = "ResultArena"
	_stage_env = stage_env
	var quality := QualityRules.normalize(graphics_quality)
	var layout := _read_layout()
	var structure := ARENA_SCENE.instantiate() as Node3D
	structure.name = "Structure"
	add_child(structure)
	StadiumMaterials.apply(structure)
	var shadows := QualityRules.is_at_least(quality, QualityRules.HIGH) and not QualityRules.is_mobile_target()
	for node: Node in structure.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_lid = structure.find_child("RA_Lid", true, false) as Node3D
	stand = GoalStand.new()
	add_child(stand)
	stand.setup(quality, CROWD_SEED, STAND_SCENE)
	stand.position = Vector3(0.0, 0.0, float(layout.get("stand_offset", 22.1)))
	var wings: Dictionary = layout.get("wings", {})
	for wing_name: String in wings:
		var wing := structure.find_child(wing_name, true, false) as Node3D
		if wing == null:
			push_warning("ResultArena: %s is missing from result_arena.glb" % wing_name)
			continue
		var spec: Dictionary = wings[wing_name]
		var team := int(spec.get("team", 1))
		var crowd := CrowdScript.new()
		crowd.name = "Spectators"
		wing.add_child(crowd)
		crowd.setup(WING_DENSITY, CROWD_SEED + team, team)
		crowd.add_block(0, 0.0, spec.get("seats", []))
		wing_crowds.append(crowd)


## 暗転の下で、正面スタンドの観客を一度に並べる（ゴール観客席は数フレームかけて並ぶ）。
func fill_crowd() -> void:
	if stand != null:
		stand.fill_crowd()


func _process(_delta: float) -> void:
	# サドンデスの縦穴が開くと、舞台の中央のフタを外して縦穴の口を見せる。
	if _lid != null and _stage_env != null:
		_lid.visible = not _stage_env.is_shaft_hole_active()


static func _read_layout() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if parsed is Dictionary:
		return parsed
	push_warning("ResultArena: cannot read %s" % LAYOUT_PATH)
	return {}

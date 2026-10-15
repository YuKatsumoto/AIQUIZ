extends RefCounted
class_name PlayerSkinRig

## 箱人形（PlayerController / EmoteBlockmanPreview の骨格）をパーツごとの単色で塗る。
## マテリアルはプレイヤー×パーツごとに1つ（11個）で、色を変えるときは albedo だけ差し替える。

const ToonPresets = preload("res://scripts/cosmetics/character_toon_presets.gd")
const OUTLINE_SHADER: Shader = preload("res://shaders/player_skin_outline.gdshader")

const PART_META: StringName = &"skin_part"
const GROUPS_META: StringName = &"skin_groups"
const MATERIALS_META: StringName = &"skin_materials"
const OUTLINE_META: StringName = &"skin_outline"
## 選んだパーツを光らせる色（emission。0 のときは従来の見た目と同じ）。
const HIGHLIGHT_COLOR := Color(1.0, 0.86, 0.35)

## パーツ → 骨格（parts 辞書）のキー。
## 骨格はつま先が +Z 向きで、"l_*" のキーは -X 側＝キャラ自身から見て右側にある。
## そのため 左うで（l_arm）には "r_*" のキーを当てる（正面から見ると画面の右側）。
const PART_KEYS := {
	&"head": ["head"],
	&"chest": ["upper_torso"],
	&"waist": ["lower_torso"],
	&"l_arm": ["r_upp_arm", "r_low_arm"],
	&"r_arm": ["l_upp_arm", "l_low_arm"],
	&"l_hand": ["r_hand"],
	&"r_hand": ["l_hand"],
	&"l_leg": ["r_thigh", "r_calf"],
	&"r_leg": ["l_thigh", "l_calf"],
	&"l_foot": ["r_foot", "r_toe_mesh"],
	&"r_foot": ["l_foot", "l_toe_mesh"],
}

static var _front_layout_cache: Dictionary = {}


## パーツごとのメッシュ一覧 {part_id: [[MeshInstance3D...]]}（手は l_hand / r_hand 配下の指まで含む）。
static func collect_groups(parts: Dictionary) -> Dictionary:
	var groups := {}
	for part_id: StringName in PART_KEYS:
		var meshes: Array[MeshInstance3D] = []
		for key: String in PART_KEYS[part_id]:
			_collect_meshes(parts.get(key), meshes)
		groups[part_id] = [meshes]
	return groups


static func _collect_meshes(node_value: Variant, out: Array[MeshInstance3D]) -> void:
	var node := node_value as Node
	if node == null or not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
		return
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		out.append(child as MeshInstance3D)


## 骨格を作った直後に呼ぶ。各メッシュにパーツ名を付けて覚えておく。
static func prepare_parts(parts: Dictionary) -> void:
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null:
		return
	var groups := collect_groups(parts)
	for part_id: StringName in groups:
		for side: Array in groups[part_id]:
			for mesh: MeshInstance3D in side:
				mesh.set_meta(PART_META, part_id)
	pelvis.set_meta(GROUPS_META, groups)


static func is_prepared(parts: Dictionary) -> bool:
	var pelvis := parts.get("pelvis") as Node3D
	return pelvis != null and pelvis.has_meta(GROUPS_META)


## skin は PlayerSkin の形式（{} ならスロット既定色）。
static func apply(parts: Dictionary, skin: Dictionary, slot: int) -> void:
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null:
		return
	if not pelvis.has_meta(GROUPS_META):
		prepare_parts(parts)
	var resolved := PlayerSkin.resolve(skin, slot)
	var materials := _materials_for(pelvis)
	var groups: Dictionary = pelvis.get_meta(GROUPS_META)
	for part_id: StringName in PlayerSkin.PART_IDS:
		var color := PlayerSkin.part_color(resolved, part_id)
		var material: StandardMaterial3D = materials[part_id]
		material.albedo_color = color
		for side: Array in groups.get(part_id, []):
			for mesh_value: Variant in side:
				var mesh := mesh_value as MeshInstance3D
				if mesh == null or not is_instance_valid(mesh):
					continue
				if mesh.material_override != material:
					mesh.material_override = material
				ToonPresets.remember_base_color(mesh, color)


static func _materials_for(pelvis: Node3D) -> Dictionary:
	if pelvis.has_meta(MATERIALS_META):
		return pelvis.get_meta(MATERIALS_META)
	var materials := {}
	for part_id: StringName in PlayerSkin.PART_IDS:
		var material := StandardMaterial3D.new()
		material.roughness = 0.7
		material.metallic = 0.1
		# 発光は常に有効にしておき（黒＝見た目は変わらない）、選択時は色だけ変える。
		# 途中で有効にするとシェーダーの作り直しで一瞬止まるため。
		material.emission_enabled = true
		material.emission = Color.BLACK
		materials[part_id] = material
	pelvis.set_meta(MATERIALS_META, materials)
	return materials


## パーツごとの発光量をまとめて設定する（{part_id: amount}、ALL は全身。無いパーツは 0）。
static func set_highlight_map(parts: Dictionary, amounts: Dictionary) -> void:
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null or not pelvis.has_meta(MATERIALS_META):
		return
	var materials: Dictionary = pelvis.get_meta(MATERIALS_META)
	var whole := float(amounts.get(PlayerSkin.ALL, 0.0))
	for id: StringName in materials:
		var value := maxf(whole, float(amounts.get(id, 0.0)))
		(materials[id] as StandardMaterial3D).emission = Color(HIGHLIGHT_COLOR.r * value, HIGHLIGHT_COLOR.g * value, HIGHLIGHT_COLOR.b * value)


## 選んだパーツ（ALL は全身、&"" で消す）の輪郭を光らせる。スキン編集のプレビュー専用。
## パーツのマテリアルの next_pass に、ふちを描くマテリアル（人形ごとに1つ）を付け外しする。
static func set_outline(parts: Dictionary, part_id: StringName) -> void:
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null or not pelvis.has_meta(MATERIALS_META):
		return
	var outline: ShaderMaterial = null
	if pelvis.has_meta(OUTLINE_META):
		outline = pelvis.get_meta(OUTLINE_META)
	else:
		outline = ShaderMaterial.new()
		outline.shader = OUTLINE_SHADER
		outline.set_shader_parameter(&"outline_color", HIGHLIGHT_COLOR)
		pelvis.set_meta(OUTLINE_META, outline)
	var materials: Dictionary = pelvis.get_meta(MATERIALS_META)
	for id: StringName in materials:
		var lit := part_id != &"" and (part_id == PlayerSkin.ALL or id == part_id)
		var material := materials[id] as StandardMaterial3D
		if material.next_pass != (outline if lit else null):
			material.next_pass = outline if lit else null


## 物理用の代わりのメッシュ（ラグドール）を元メッシュと同じ見た目にする。
static func dress_like(dst: MeshInstance3D, src: MeshInstance3D) -> void:
	if dst == null or src == null:
		return
	dst.material_override = src.material_override


# ---------------------------------------------------------------------------
# クリック判定
# ---------------------------------------------------------------------------

## ワールド座標のレイが最初に当たったパーツ ID（なければ &""）。
static func pick(parts: Dictionary, ray_origin: Vector3, ray_dir: Vector3) -> StringName:
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null or not pelvis.has_meta(GROUPS_META) or not pelvis.is_inside_tree():
		return &""
	var best_t := INF
	var best_part: StringName = &""
	var groups: Dictionary = pelvis.get_meta(GROUPS_META)
	for part_id: StringName in groups:
		for side: Array in groups[part_id]:
			for mesh_value: Variant in side:
				var mesh := mesh_value as MeshInstance3D
				if mesh == null or not is_instance_valid(mesh) or not mesh.is_visible_in_tree() or mesh.mesh == null:
					continue
				var inverse := mesh.global_transform.affine_inverse()
				var t := _ray_aabb(inverse * ray_origin, inverse.basis * ray_dir, mesh.mesh.get_aabb())
				if t >= 0.0 and t < best_t:
					best_t = t
					best_part = part_id
	return best_part


## パーツ（ALL は全身）のワールド座標の範囲。見つからなければ大きさ 0 の AABB。
static func part_world_aabb(parts: Dictionary, part_id: StringName) -> AABB:
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null or not pelvis.has_meta(GROUPS_META) or not pelvis.is_inside_tree():
		return AABB()
	var groups: Dictionary = pelvis.get_meta(GROUPS_META)
	var result := AABB()
	var first := true
	for id: StringName in groups:
		if part_id != PlayerSkin.ALL and id != part_id:
			continue
		for side: Array in groups[id]:
			for mesh_value: Variant in side:
				var mesh := mesh_value as MeshInstance3D
				if mesh == null or not is_instance_valid(mesh) or mesh.mesh == null:
					continue
				var box := mesh.global_transform * mesh.mesh.get_aabb()
				result = box if first else result.merge(box)
				first = false
	return result


static func _ray_aabb(origin: Vector3, dir: Vector3, box: AABB) -> float:
	var t_min := -INF
	var t_max := INF
	for axis: int in range(3):
		var o := origin[axis]
		var d := dir[axis]
		var lo := box.position[axis]
		var hi := box.end[axis]
		if absf(d) < 0.000001:
			if o < lo or o > hi:
				return -1.0
			continue
		var t1 := (lo - o) / d
		var t2 := (hi - o) / d
		t_min = maxf(t_min, minf(t1, t2))
		t_max = minf(t_max, maxf(t1, t2))
	if t_max < maxf(t_min, 0.0):
		return -1.0
	return maxf(t_min, 0.0)


# ---------------------------------------------------------------------------
# 2D（正面図）
# ---------------------------------------------------------------------------

## ツリー外でも動くよう、親の .transform を pelvis まで掛け合わせる。
static func rest_transform(node: Node3D, pelvis: Node3D) -> Transform3D:
	var result := node.transform
	var current := node.get_parent()
	while current != null and current != pelvis:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result if current == pelvis else node.transform


## キャラの正面（つま先の向き = pelvis ローカル +Z）から見た人型の矩形一覧。
## {"body": Rect2 (メートル, x右 y下), "regions": [{part, rect}]}
static func front_view_layout() -> Dictionary:
	if not _front_layout_cache.is_empty():
		return _front_layout_cache
	var holder := Node3D.new()
	var parts := EmoteBlockmanPreview.build_player_skeleton(true, holder, HatData.HAT_NONE)
	var pelvis := parts.get("pelvis") as Node3D
	var groups := collect_groups(parts)
	var regions: Array[Dictionary] = []
	var body := Rect2()
	var first := true
	# 3D と同じく、こしの上にむねが重なって見える順に並べる（描く順＝この順）。
	var draw_order: Array[StringName] = [
		&"waist", &"chest", &"head", &"l_arm", &"r_arm", &"l_hand", &"r_hand",
		&"l_leg", &"r_leg", &"l_foot", &"r_foot",
	]
	for part_id: StringName in draw_order:
		for side: Array in groups.get(part_id, []):
			if side.is_empty():
				continue
			var aabb := AABB()
			for index: int in range(side.size()):
				var mesh: MeshInstance3D = side[index]
				var mesh_aabb := rest_transform(mesh, pelvis) * mesh.mesh.get_aabb()
				aabb = mesh_aabb if index == 0 else aabb.merge(mesh_aabb)
			var rect := Rect2(Vector2(aabb.position.x, -aabb.end.y), Vector2(aabb.size.x, aabb.size.y))
			body = rect if first else body.merge(rect)
			first = false
			regions.append({"part": part_id, "rect": rect})
	holder.free()
	_front_layout_cache = {"body": body, "regions": regions}
	return _front_layout_cache

extends RefCounted
class_name HatFactory

## 帽子ファクトリー — Poly Pizza の GLB モデルを読み込み、自動スケーリング
## CC BY 3.0 — 各モデルのアトリビューションは HAT_CREDITS を参照

# プレイヤー頭部サイズ基準値（頭 BoxMesh.size = 0.22）
const HEAD_WIDTH := 0.22

# 帽子が収まるべきターゲット高さ（頭幅の 1.2〜1.8 倍程度）
const DEFAULT_TARGET_HEIGHT := 0.28

# モデルファイルパス（res://assets/hats/ 配下）
const HAT_PATHS := {
	HatData.HAT_TOP_HAT:   "res://assets/hats/top_hat.glb",
	HatData.HAT_CROWN:     "res://assets/hats/crown.glb",
	HatData.HAT_CAP:       "res://assets/hats/cap.glb",
	HatData.HAT_SANTA:     "res://assets/hats/santa_hat.glb",
	HatData.HAT_COWBOY:    "res://assets/hats/cowboy_hat.glb",
	HatData.HAT_HELMET:    "res://assets/hats/helmet.glb",
	HatData.HAT_WIZARD:    "res://assets/hats/wizard_hat.glb",
	HatData.HAT_CONE:      "res://assets/hats/traffic_cone.glb",
	HatData.HAT_SOMBRERO:  "res://assets/hats/sombrero.glb",
	HatData.HAT_FROG:      "res://assets/hats/frog_hat.glb",
	HatData.HAT_PROPELLER: "res://assets/hats/propeller_hat.glb",
	HatData.HAT_FOX:       "res://assets/hats/fox_hat.glb",
	HatData.HAT_CHICKEN:   "res://assets/hats/chicken.glb",
	HatData.HAT_BOUSI:     "res://assets/hats/bousi.fbx",
	HatData.HAT_GRADUATION_CAP: "res://assets/hats/graduation_cap.glb",
	HatData.HAT_PIRATE:    "res://assets/hats/pirate_hat.glb",
}

# 帽子ごとのターゲット高さ（デフォルトより大きくしたい帽子を個別指定）
const HAT_TARGET_HEIGHTS := {
	HatData.HAT_TOP_HAT:   0.42,  # シルクハットは背が高い
	HatData.HAT_CROWN:     0.30,  # 王冠
	HatData.HAT_CAP:       0.28,  # キャップ
	HatData.HAT_SANTA:     0.45,  # サンタ帽
	HatData.HAT_COWBOY:    0.32,  # カウボーイハット
	HatData.HAT_HELMET:    0.32,  # ヘルメット
	HatData.HAT_WIZARD:    0.50,  # ウィザード帽子
	HatData.HAT_CONE:      0.45,  # コーン
	HatData.HAT_SOMBRERO:  0.25,  # ソンブレロ（横に広いので高さは控えめ）
	HatData.HAT_FROG:      0.30,  # カエル帽
	HatData.HAT_PROPELLER: 0.35,  # プロペラ帽
	HatData.HAT_FOX:       0.85,  # キツネ帽（めり込まないようにさらに大きく）
	HatData.HAT_CHICKEN:   0.70,  # ニワトリ（頭の上に乗るサイズ）
	HatData.HAT_BOUSI:     0.70,  # キリン（頭幅に合わせて大きめ）
	HatData.HAT_GRADUATION_CAP: 0.74, # 先細りの被り部下端を約0.58にし、四角い頭の角まで収める
	HatData.HAT_PIRATE:    0.82,  # 赤いバンダナ外周を約0.60にし、内側へ頭全体を収める
}

# 帽子ごとの追加Y軸オフセット（微調整用、正=上、負=下）
const HAT_Y_TWEAKS := {
	HatData.HAT_TOP_HAT:   0.02,
	HatData.HAT_CROWN:     0.06,   # 頭に沈まないよう少し上げる
	HatData.HAT_CAP:       0.02,   # つばを頭にめり込ませない
	HatData.HAT_SANTA:     -0.02,
	HatData.HAT_COWBOY:    -0.02,
	HatData.HAT_HELMET:    -0.12,  # Lowered significantly to stop floating
	HatData.HAT_WIZARD:    0.04,   # つばが頭を貫通しないよう上げる
	HatData.HAT_CONE:      0.0,
	HatData.HAT_SOMBRERO:  0.0,    # 沈み込みと浮きの中間
	HatData.HAT_FROG:      0.0,    # 沈み込みと浮きの中間
	HatData.HAT_PROPELLER: 0.0,
	HatData.HAT_FOX:       -0.42,  # キツネ帽（すっぽり被せる）
	HatData.HAT_CHICKEN:   -0.02,
	HatData.HAT_BOUSI:     -0.02,  # キリンのオレンジ帽体を深く被せ、四角い頭の飛び出しを抑える
	HatData.HAT_GRADUATION_CAP: -0.59, # 被り部が頭上部を約0.10包み、角板は頭上に保つ
	HatData.HAT_PIRATE:    -0.45,  # 赤いバンダナ下端を頭頂へ合わせ、帽体底面を浮かせない
}

# 帽子ごとの追加Y軸回転オフセット（度数法）
# キャラクターのローカル +Z（足先と進行方向）へ、つば・顔をそろえる。
const HAT_Y_ROTATIONS := {
	HatData.HAT_CAP:       90.0,  # つばをキャラ正面へ
	HatData.HAT_FROG:      90.0,  # カエルの顔をキャラ正面へ
	HatData.HAT_PROPELLER: 180.0, # つばをキャラ正面へ
	HatData.HAT_CHICKEN:   90.0,  # ニワトリをキャラ正面へ
	HatData.HAT_BOUSI:     180.0, # つばをキャラ正面へ
	HatData.HAT_GRADUATION_CAP: 45.0, # タッセルを顔正面から前側の角へ逃がす
}

# 帽子ごとの追加X軸オフセット（微調整用）
const HAT_X_TWEAKS := {
	HatData.HAT_HELMET:    -0.08, # AABB偏りで横に寄るのを戻す
	HatData.HAT_PIRATE:    0.13,  # 垂れ布込みAABBではなく赤バンダナ中心を頭へ合わせる
}

# 帽子ごとの追加Z軸オフセット（微調整用、正=+Z＝キャラ正面、負=-Z＝後ろへ）
# つば付き帽子は AABB 中心だとドームが前に出るので、被る部分を頭の中央へ戻す
const HAT_Z_TWEAKS := {
	HatData.HAT_CAP:       -0.08,  # ドームを頭の上へ
	HatData.HAT_PROPELLER: -0.08,  # ドームを頭の上へ
	HatData.HAT_BOUSI:     -0.10,   # ドームを前へ寄せ、四角い頭の前端が帽体を突き抜けないようにする
}

# ボブルヘッド（赤ベコ）エフェクト対象の帽子
# プレイヤーの動きに応じてバネ物理で首がゆらゆら揺れる
const HAT_BOBBLEHEAD := {
	HatData.HAT_BOUSI: true,
}

static func is_bobblehead(hat_id: int) -> bool:
	return HAT_BOBBLEHEAD.get(hat_id, false)

const PROPELLER_BLADE_Y_CUT := 2.0
const PROPELLER_SPINNER_SCRIPT := preload("res://scripts/cosmetics/propeller_spinner.gd")
const GIRAFFE_HEAD_TRACKER_SCRIPT := preload("res://scripts/cosmetics/giraffe_head_tracker.gd")
const GIRAFFE_HEAD_CUT_MODEL_Y := 10.65
const GIRAFFE_HEAD_PIVOT_MODEL := Vector3(-0.005696, 10.65, 1.08)

# Poly Pizza CC BY 3.0 クレジット
const HAT_CREDITS := {
	HatData.HAT_TOP_HAT:   "Top hat by jeremy [CC-BY] via Poly Pizza",
	HatData.HAT_CROWN:     "Crown by Poly by Google [CC-BY] via Poly Pizza",
	HatData.HAT_CAP:       "Cap by J-Toastie [CC-BY] via Poly Pizza",
	HatData.HAT_SANTA:     "Santa Hat by Joe Dorman [CC-BY] via Poly Pizza",
	HatData.HAT_COWBOY:    "Cowboy Hat by J-Toastie [CC-BY] via Poly Pizza",
	HatData.HAT_HELMET:    "Hard hat by Poly by Google [CC-BY] via Poly Pizza",
	HatData.HAT_WIZARD:    "Wizard hat by Poly by Google [CC-BY] via Poly Pizza",
	HatData.HAT_CONE:      "Traffic Cone by Adam Marc Williams [CC-BY] via Poly Pizza",
	HatData.HAT_SOMBRERO:  "Sombrero by Poly by Google [CC-BY] via Poly Pizza",
	HatData.HAT_FROG:      "Frog Hat by J-Toastie [CC-BY] via Poly Pizza",
	HatData.HAT_PROPELLER: "Propeller hat by jeremy [CC-BY] via Poly Pizza",
	HatData.HAT_FOX:       "Fox Hat by J-Toastie [CC-BY] via Poly Pizza",
	HatData.HAT_CHICKEN:   "Chicken by jeremy [CC-BY] via Poly Pizza",
	HatData.HAT_BOUSI:     "Bousi hat model",
	HatData.HAT_GRADUATION_CAP: "Graduation cap by Poly by Google [CC-BY 3.0] via Poly Pizza",
	HatData.HAT_PIRATE:    "Pirate hat by Poly by Google [CC-BY 3.0] via Poly Pizza",
}


static func create_hat(hat_id: int) -> Node3D:
	if hat_id == HatData.HAT_NONE:
		return null
	if not HAT_PATHS.has(hat_id):
		return null
	
	var path: String = HAT_PATHS[hat_id]
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_warning("HatFactory: Failed to load hat model: " + path)
		return null
	
	var root := Node3D.new()
	root.name = "Hat_%d" % hat_id
	
	var model := scene.instantiate()
	root.add_child(model)
	
	# --- 自動フィッティング ---
	# 1. モデルの AABB を計算
	var aabb := _compute_model_aabb(model, Transform3D.IDENTITY)
	
	if aabb.size.length() < 0.001:
		# AABB が取れない場合はフォールバック
		model.scale = Vector3(0.2, 0.2, 0.2)
		return root
	
	# 2. ターゲット高さに合わせてスケール計算
	var target_h: float = HAT_TARGET_HEIGHTS.get(hat_id, DEFAULT_TARGET_HEIGHT)
	var model_height: float = aabb.size.y
	var scale_factor: float = target_h / model_height if model_height > 0.001 else 0.2
	
	model.scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	# 2.5 追加の回転オフセットを適用（AABB再計算前に行うことでセンタリングを完璧にする）
	var y_rot: float = HAT_Y_ROTATIONS.get(hat_id, 0.0)
	if y_rot != 0.0:
		model.rotation_degrees.y += y_rot
	
	# 3. スケール・回転適用後の AABB を再計算
	var scaled_aabb := _compute_model_aabb(model, Transform3D.IDENTITY)
	
	# 4. 帽子の底面が Y=0（HatMount位置）に来るように配置
	#    かつ XZ 中心を原点に揃える
	var bottom_y: float = scaled_aabb.position.y
	var center_x: float = scaled_aabb.position.x + scaled_aabb.size.x * 0.5
	var center_z: float = scaled_aabb.position.z + scaled_aabb.size.z * 0.5
	
	model.position = Vector3(-center_x, -bottom_y, -center_z)
	
	# 5. 追加の微調整オフセット
	var x_tweak: float = HAT_X_TWEAKS.get(hat_id, 0.0)
	var y_tweak: float = HAT_Y_TWEAKS.get(hat_id, 0.0)
	var z_tweak: float = HAT_Z_TWEAKS.get(hat_id, 0.0)
	model.position.x += x_tweak
	model.position.y += y_tweak
	model.position.z += z_tweak
	
	if hat_id == HatData.HAT_PROPELLER:
		_setup_propeller_spin(model)
	elif hat_id == HatData.HAT_BOUSI:
		_setup_giraffe_head_tracking(model)
	
	return root


static func _setup_giraffe_head_tracking(model: Node) -> void:
	var source := model.get_node_or_null("円") as MeshInstance3D
	if source == null or source.mesh == null:
		push_warning("HatFactory: Giraffe source mesh was not found")
		return
	var split := _split_giraffe_mesh(source.mesh, source.transform)
	var body_mesh := split.get("body") as ArrayMesh
	var head_mesh := split.get("head") as ArrayMesh
	if body_mesh == null or head_mesh == null:
		push_warning("HatFactory: Giraffe head split failed")
		return

	var source_parent := source.get_parent() as Node3D
	if source_parent == null:
		return
	var pivot_in_source := source.transform.affine_inverse() * GIRAFFE_HEAD_PIVOT_MODEL

	source.name = "GiraffeBody"
	source.mesh = body_mesh

	var head_pivot := Node3D.new()
	head_pivot.name = "GiraffeHeadPivot"
	head_pivot.transform = Transform3D(
		source.transform.basis,
		source.transform * pivot_in_source,
	)
	source_parent.add_child(head_pivot)

	var head := MeshInstance3D.new()
	head.name = "GiraffeHead"
	head.mesh = head_mesh
	head.transform = Transform3D(Basis.IDENTITY, -pivot_in_source)
	head.cast_shadow = source.cast_shadow
	head.material_override = source.material_override
	head_pivot.add_child(head)
	head_pivot.set_script(GIRAFFE_HEAD_TRACKER_SCRIPT)


static func _split_giraffe_mesh(src: Mesh, source_transform: Transform3D) -> Dictionary:
	var body := ArrayMesh.new()
	var head := ArrayMesh.new()
	for surface_i: int in range(src.get_surface_count()):
		var arrays: Array = src.surface_get_arrays(surface_i)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var body_indices := PackedInt32Array()
		var head_indices := PackedInt32Array()
		var uses_indices := not source_indices.is_empty()
		var triangle_count := (
			int(source_indices.size() / 3.0)
			if uses_indices
			else int(vertices.size() / 3.0)
		)
		for triangle_i: int in range(triangle_count):
			var i0 := source_indices[triangle_i * 3] if uses_indices else triangle_i * 3
			var i1 := source_indices[triangle_i * 3 + 1] if uses_indices else triangle_i * 3 + 1
			var i2 := source_indices[triangle_i * 3 + 2] if uses_indices else triangle_i * 3 + 2
			var centroid_y := (
				(source_transform * vertices[i0]).y
				+ (source_transform * vertices[i1]).y
				+ (source_transform * vertices[i2]).y
			) / 3.0
			if centroid_y >= GIRAFFE_HEAD_CUT_MODEL_Y:
				head_indices.append(i0)
				head_indices.append(i1)
				head_indices.append(i2)
			else:
				body_indices.append(i0)
				body_indices.append(i1)
				body_indices.append(i2)
		var material: Material = src.surface_get_material(surface_i)
		_add_mesh_surface(body, _rebuild_surface_arrays(arrays, body_indices), material)
		_add_mesh_surface(head, _rebuild_surface_arrays(arrays, head_indices), material)
	if body.get_surface_count() == 0 or head.get_surface_count() == 0:
		return {}
	return {"body": body, "head": head}


static func _setup_propeller_spin(model: Node) -> void:
	var mesh_instance := _find_mesh_instance(model)
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var split: Dictionary = _split_propeller_mesh(mesh_instance.mesh)
	var hat_mesh: ArrayMesh = split.get("hat") as ArrayMesh
	var blade_mesh: ArrayMesh = split.get("blades") as ArrayMesh
	if hat_mesh == null or blade_mesh == null:
		return
	mesh_instance.mesh = hat_mesh
	var center: Vector3 = split.get("center", Vector3.ZERO)
	var parent: Node = mesh_instance.get_parent()
	if parent == null:
		return
	var spinner := Node3D.new()
	spinner.name = "PropellerSpinner"
	spinner.set_script(PROPELLER_SPINNER_SCRIPT)
	parent.add_child(spinner)
	spinner.transform = Transform3D(mesh_instance.transform.basis, mesh_instance.transform * center)
	var blades := MeshInstance3D.new()
	blades.name = "PropellerBlades"
	blades.mesh = blade_mesh
	blades.cast_shadow = mesh_instance.cast_shadow
	spinner.add_child(blades)
	blades.position = -center


static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


static func _split_propeller_mesh(src: Mesh) -> Dictionary:
	var hat := ArrayMesh.new()
	var blades := ArrayMesh.new()
	var surface_count := src.get_surface_count()
	var blade_aabb := AABB()
	var has_blades := false
	for surface_i in range(surface_count):
		var arrays: Array = src.surface_get_arrays(surface_i)
		var material: Material = src.surface_get_material(surface_i)
		if surface_i == 1:
			var parts: Dictionary = _partition_surface_by_y(arrays, PROPELLER_BLADE_Y_CUT)
			var low_arrays: Array = parts.get("low", [])
			var high_arrays: Array = parts.get("high", [])
			if int(parts.get("low_count", 0)) > 0:
				_add_mesh_surface(hat, low_arrays, material)
			if int(parts.get("high_count", 0)) > 0:
				_add_mesh_surface(blades, high_arrays, material)
				var high_verts: PackedVector3Array = high_arrays[Mesh.ARRAY_VERTEX]
				for vertex in high_verts:
					if has_blades:
						blade_aabb = blade_aabb.expand(vertex)
					else:
						blade_aabb = AABB(vertex, Vector3.ZERO)
						has_blades = true
		else:
			_add_mesh_surface(hat, arrays, material)
	if not has_blades or hat.get_surface_count() == 0 or blades.get_surface_count() == 0:
		push_warning(
			"HatFactory: propeller split failed has_blades=%s hat_surfaces=%d blade_surfaces=%d"
			% [str(has_blades), hat.get_surface_count(), blades.get_surface_count()]
		)
		return {}
	return {
		"hat": hat,
		"blades": blades,
		"center": blade_aabb.get_center(),
	}


static func _partition_surface_by_y(arrays: Array, y_cut: float) -> Dictionary:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return {"low": [], "high": [], "low_count": 0, "high_count": 0}
	var src_indices: Variant = arrays[Mesh.ARRAY_INDEX]
	var use_index := src_indices is PackedInt32Array and (src_indices as PackedInt32Array).size() >= 3
	var low_indices := PackedInt32Array()
	var high_indices := PackedInt32Array()
	var triangle_count: int
	if use_index:
		triangle_count = int((src_indices as PackedInt32Array).size() / 3.0)
	else:
		triangle_count = int(verts.size() / 3.0)
	for triangle_i in range(triangle_count):
		var i0: int
		var i1: int
		var i2: int
		if use_index:
			var indexed: PackedInt32Array = src_indices
			i0 = indexed[triangle_i * 3]
			i1 = indexed[triangle_i * 3 + 1]
			i2 = indexed[triangle_i * 3 + 2]
		else:
			i0 = triangle_i * 3
			i1 = triangle_i * 3 + 1
			i2 = triangle_i * 3 + 2
		var centroid_y: float = (verts[i0].y + verts[i1].y + verts[i2].y) / 3.0
		if centroid_y > y_cut:
			high_indices.append(i0)
			high_indices.append(i1)
			high_indices.append(i2)
		else:
			low_indices.append(i0)
			low_indices.append(i1)
			low_indices.append(i2)
	return {
		"low": _rebuild_surface_arrays(arrays, low_indices),
		"high": _rebuild_surface_arrays(arrays, high_indices),
		"low_count": int(low_indices.size() / 3.0),
		"high_count": int(high_indices.size() / 3.0),
	}


static func _rebuild_surface_arrays(src: Array, tri_indices: PackedInt32Array) -> Array:
	if tri_indices.is_empty():
		return []
	var src_verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var index_remap := {}
	var old_order := PackedInt32Array()
	var new_indices := PackedInt32Array()
	for i in range(tri_indices.size()):
		var old_i: int = tri_indices[i]
		if not index_remap.has(old_i):
			index_remap[old_i] = old_order.size()
			old_order.append(old_i)
		new_indices.append(int(index_remap[old_i]))
	var dest: Array = []
	dest.resize(Mesh.ARRAY_MAX)
	dest[Mesh.ARRAY_VERTEX] = _remap_vertex_array(src_verts, old_order, src_verts.size())
	dest[Mesh.ARRAY_INDEX] = new_indices
	var copy_slots: Array[int] = [
		Mesh.ARRAY_NORMAL,
		Mesh.ARRAY_TANGENT,
		Mesh.ARRAY_TEX_UV,
		Mesh.ARRAY_COLOR,
	]
	for array_i in copy_slots:
		var src_array: Variant = src[array_i]
		if src_array == null:
			continue
		if src_array is PackedVector3Array and (src_array as PackedVector3Array).is_empty():
			continue
		if src_array is PackedVector2Array and (src_array as PackedVector2Array).is_empty():
			continue
		if src_array is PackedColorArray and (src_array as PackedColorArray).is_empty():
			continue
		dest[array_i] = _remap_vertex_array(src_array, old_order, src_verts.size())
	return dest


static func _remap_vertex_array(src_array: Variant, old_order: PackedInt32Array, src_vert_count: int) -> Variant:
	if src_array is PackedVector3Array:
		var src_v3: PackedVector3Array = src_array
		var dest_v3 := PackedVector3Array()
		dest_v3.resize(old_order.size())
		for i in range(old_order.size()):
			dest_v3[i] = src_v3[old_order[i]]
		return dest_v3
	if src_array is PackedVector2Array:
		var src_v2: PackedVector2Array = src_array
		var dest_v2 := PackedVector2Array()
		dest_v2.resize(old_order.size())
		for i in range(old_order.size()):
			dest_v2[i] = src_v2[old_order[i]]
		return dest_v2
	if src_array is PackedColorArray:
		var src_col: PackedColorArray = src_array
		var dest_col := PackedColorArray()
		dest_col.resize(old_order.size())
		for i in range(old_order.size()):
			dest_col[i] = src_col[old_order[i]]
		return dest_col
	if src_array is PackedFloat32Array:
		var src_f: PackedFloat32Array = src_array
		var stride: int = int(src_f.size() / float(src_vert_count)) if src_vert_count > 0 else 1
		if stride < 1:
			stride = 1
		var dest_f := PackedFloat32Array()
		dest_f.resize(old_order.size() * stride)
		for i in range(old_order.size()):
			var src_base: int = old_order[i] * stride
			var dest_base: int = i * stride
			for k in range(stride):
				dest_f[dest_base + k] = src_f[src_base + k]
		return dest_f
	if src_array is PackedInt32Array:
		var src_i: PackedInt32Array = src_array
		var stride_i: int = int(src_i.size() / float(src_vert_count)) if src_vert_count > 0 else 1
		if stride_i < 1:
			stride_i = 1
		var dest_i := PackedInt32Array()
		dest_i.resize(old_order.size() * stride_i)
		for i in range(old_order.size()):
			var src_base_i: int = old_order[i] * stride_i
			var dest_base_i: int = i * stride_i
			for k in range(stride_i):
				dest_i[dest_base_i + k] = src_i[src_base_i + k]
		return dest_i
	if src_array is PackedByteArray:
		var src_b: PackedByteArray = src_array
		var stride_b: int = int(src_b.size() / float(src_vert_count)) if src_vert_count > 0 else 1
		if stride_b < 1:
			stride_b = 1
		var dest_b := PackedByteArray()
		dest_b.resize(old_order.size() * stride_b)
		for i in range(old_order.size()):
			var src_base_b: int = old_order[i] * stride_b
			var dest_base_b: int = i * stride_b
			for k in range(stride_b):
				dest_b[dest_base_b + k] = src_b[src_base_b + k]
		return dest_b
	return src_array


static func _add_mesh_surface(mesh: ArrayMesh, arrays: Array, material: Material) -> void:
	if arrays.is_empty() or arrays.size() <= Mesh.ARRAY_VERTEX:
		return
	if arrays[Mesh.ARRAY_VERTEX] == null:
		return
	var packed: Array = []
	packed.resize(Mesh.ARRAY_MAX)
	var keep_slots: Array[int] = [
		Mesh.ARRAY_VERTEX,
		Mesh.ARRAY_NORMAL,
		Mesh.ARRAY_TEX_UV,
		Mesh.ARRAY_COLOR,
		Mesh.ARRAY_INDEX,
	]
	for array_i in keep_slots:
		if array_i >= arrays.size():
			continue
		packed[array_i] = arrays[array_i]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, packed)
	var surface_i: int = mesh.get_surface_count() - 1
	if material != null and surface_i >= 0:
		mesh.surface_set_material(surface_i, material)


## 帽子に含まれる全MeshInstance3Dを取得（爆発用）
static func get_hat_meshes(hat_root: Node3D) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if hat_root == null:
		return meshes
	_collect_meshes(hat_root, meshes)
	return meshes

static func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, meshes)


## モデルの結合 AABB を計算（再帰的に全子ノードの Transform を考慮）
static func _compute_model_aabb(node: Node, parent_xform: Transform3D) -> AABB:
	var combined := AABB()
	var has_any := false
	
	var this_xform := parent_xform
	if node is Node3D:
		this_xform = parent_xform * (node as Node3D).transform
	
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var local_aabb: AABB = mi.mesh.get_aabb()
			# ローカル AABB を親からの変換で変換
			var transformed := this_xform * local_aabb
			combined = transformed
			has_any = true
	
	for child in node.get_children():
		var child_aabb := _compute_model_aabb(child, this_xform)
		if child_aabb.size.length() > 0.001:
			if has_any:
				combined = combined.merge(child_aabb)
			else:
				combined = child_aabb
				has_any = true
	
	return combined


## クレジットテキスト取得
static func get_credit(hat_id: int) -> String:
	if HAT_CREDITS.has(hat_id):
		return HAT_CREDITS[hat_id]
	return ""

## 全クレジットテキスト取得
static func get_all_credits() -> String:
	var text := "=== Hat Model Credits ===\n"
	for hat_id: int in HAT_CREDITS:
		text += HAT_CREDITS[hat_id] + "\n"
	return text

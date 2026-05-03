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
}

# 帽子ごとの追加Y軸オフセット（微調整用、正=上、負=下）
const HAT_Y_TWEAKS := {
	HatData.HAT_TOP_HAT:   0.0,
	HatData.HAT_CROWN:     0.0,
	HatData.HAT_CAP:       0.02,   # Raised to avoid sinking
	HatData.HAT_SANTA:     0.0,
	HatData.HAT_COWBOY:    -0.02,
	HatData.HAT_HELMET:    -0.12,  # Lowered significantly to stop floating
	HatData.HAT_WIZARD:    -0.01,
	HatData.HAT_CONE:      0.0,
	HatData.HAT_SOMBRERO:  -0.05,  # ソンブレロは少し下げる
	HatData.HAT_FROG:      -0.02,  # カエル帽
	HatData.HAT_PROPELLER: 0.0,    # プロペラ帽
	HatData.HAT_FOX:       -0.42,  # キツネ帽（すっぽり被せる）
}

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
	
	# 3. スケール適用後の AABB を再計算
	var scaled_aabb := _compute_model_aabb(model, Transform3D.IDENTITY)
	
	# 4. 帽子の底面が Y=0（HatMount位置）に来るように配置
	#    かつ XZ 中心を原点に揃える
	var bottom_y: float = scaled_aabb.position.y
	var center_x: float = scaled_aabb.position.x + scaled_aabb.size.x * 0.5
	var center_z: float = scaled_aabb.position.z + scaled_aabb.size.z * 0.5
	
	model.position = Vector3(-center_x, -bottom_y, -center_z)
	
	# 5. 追加の微調整オフセット
	var y_tweak: float = HAT_Y_TWEAKS.get(hat_id, 0.0)
	model.position.y += y_tweak
	
	return root


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

extends RefCounted

## 描画の部品（パイプライン）を作った数の見張り。
## 新しい PC では、初めて描くもの（材質・描き方）ごとにグラフィックドライバーが部品を作り、作り終えるまで
## 画面が止まる。試合の準備（覆いの下）で作り切ってから覆いを外し、試合中に作ったら知らせるために使う。
## 種類は Godot の RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_* と同じ：
##   canvas（2D）・mesh（読み込み時）・surface（場面に足したとき）・draw（描く瞬間。止まりの元）・
##   specialization（裏で作る最適化版。止まらない）。

const KINDS: Array[String] = ["canvas", "mesh", "surface", "draw", "specialization"]

## keep_materials で持ち続ける材質（材質の id → 材質）。
static var _kept := {}
## ほかの所が試合をまたいで持ち続ける物の入れ物（Dictionary / Array）。ゲームを終えるときに空にする。
static var _caches: Array = []


## いままでに作った数（種類ごと、KINDS の順）。
static func counts() -> Array[int]:
	return [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION),
	]


## before から after までに増えた数を {種類: 数} で返す（増えていない種類は入れない）。
## stalls_only なら、止まりの元になりうる canvas・mesh・surface・draw だけを見る。
static func delta(before: Array[int], after: Array[int], stalls_only: bool = false) -> Dictionary:
	var out := {}
	for index: int in range(mini(before.size(), after.size())):
		if stalls_only and KINDS[index] == "specialization":
			continue
		var grown := after[index] - before[index]
		if grown > 0:
			out[KINDS[index]] = grown
	return out


## root の下で描いている材質を、ゲームを終えるまで持ち続ける。
## コードで作った StandardMaterial3D・ParticleProcessMaterial は、同じ設定の材質がすべて捨てられると
## 描き方（シェーダー）ごと消え、次に使うときに描画の部品を作り直す（新しい PC ではそこで止まる）。
## 試合の準備で描いた物を捨てる前に呼ぶ。返す値は新しく持った数。
static func keep_materials(root: Node) -> int:
	if root == null or not is_instance_valid(root):
		return 0
	var before := _kept.size()
	var nodes: Array[Node] = root.find_children("*", "GeometryInstance3D", true, false)
	nodes.append(root)
	for node: Node in nodes:
		if node is GeometryInstance3D:
			_keep((node as GeometryInstance3D).material_override)
			_keep((node as GeometryInstance3D).material_overlay)
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			for surface: int in range(mesh_instance.get_surface_override_material_count()):
				_keep(mesh_instance.get_surface_override_material(surface))
			_keep_mesh(mesh_instance.mesh)
		elif node is GPUParticles3D:
			var particles := node as GPUParticles3D
			_keep(particles.process_material)
			for pass_index: int in range(particles.draw_passes):
				_keep_mesh(particles.get_draw_pass_mesh(pass_index))
	return _kept.size() - before


## 試合をまたいで持ち続ける物の入れ物を登録する（release_all で空にする）。
static func register_cache(container: Variant) -> void:
	for cache: Variant in _caches:
		if is_same(cache, container):
			return
	_caches.append(container)


## ゲームを終えるときに呼ぶ（GameManager._exit_tree）。持ち続けた材質や見本を、描画の仕組みが止まる前に放す。
static func release_all() -> void:
	_kept.clear()
	for cache: Variant in _caches:
		if cache is Dictionary:
			(cache as Dictionary).clear()
		elif cache is Array:
			(cache as Array).clear()
	_caches.clear()


static func _keep_mesh(mesh: Mesh) -> void:
	if mesh == null:
		return
	for surface: int in range(mesh.get_surface_count()):
		_keep(mesh.surface_get_material(surface))


static func _keep(material: Material) -> void:
	# 材質の中身ごとではなく、描き方（シェーダー）を残すのが目的。コードで作る種類だけでよい。
	if material is BaseMaterial3D or material is ParticleProcessMaterial:
		_kept[material.get_instance_id()] = material


## 1 フレーム描くのを待つ（画面のない実行ではフレームの処理だけ）。
static func draw_frame(node: Node) -> void:
	if DisplayServer.get_name() == "headless":
		await node.get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


## 部品を作る数（canvas・mesh・surface・draw）が stable_frames フレーム続けて増えなくなるまで描き続ける。
## max_frames を超えたら待つのをやめる（止まったままにするより先へ進む）。on_frame は毎フレーム
## 経過秒を渡して呼ぶ（試し描きの物を動かすとき）。min_frames までは落ち着いていても待つ。
## 返す値：{settled: 落ち着いたか, frames: 待ったフレーム数, compiled: 待つ間に作った数}
static func wait_until_settled(node: Node, max_frames: int, stable_frames: int = 3,
		on_frame: Callable = Callable(), min_frames: int = 0) -> Dictionary:
	var first := counts()
	var previous := first
	var stable := 0
	var frames := 0
	var last_usec := Time.get_ticks_usec()
	while frames < max_frames:
		await draw_frame(node)
		if not is_instance_valid(node) or not node.is_inside_tree():
			break
		frames += 1
		if on_frame.is_valid():
			var now := Time.get_ticks_usec()
			on_frame.call(float(now - last_usec) / 1000000.0)
			last_usec = now
		var current := counts()
		if delta(previous, current, true).is_empty():
			stable += 1
		else:
			stable = 0
		previous = current
		if stable >= stable_frames and frames >= min_frames:
			break
	return {"settled": stable >= stable_frames, "frames": frames, "compiled": delta(first, previous)}

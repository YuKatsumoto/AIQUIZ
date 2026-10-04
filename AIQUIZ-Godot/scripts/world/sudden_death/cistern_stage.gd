class_name CisternStage
extends Node3D

## 2Pサドンデスの地下ステージ。首都圏外郭放水路の調圧水槽を実寸で再現した舞台（docs/surge_tank_reproduction.md）。
## Blenderの部品（柱の線0〜10の区画、ポンプ側の端、立坑側の端と第1立坑、見学者の通路と階段）を焼いた光で描く。
## 実ライト（実物の照明と同じ位置の高天井灯・壁の投光器）は人物・リフトのタワー・水を照らし、舞台には
## 鏡面のハイライトだけを足す（舞台のシェーダーの light()）。
## シーンは tools/sudden_death/build_tank_scenes.gd が生成するので、手で編集しない。このシーン
## （床の当たり判定・審判の立ち位置・画面の仕上げ）に、部分シーン（区画 → 両端 → 照明・反射プローブ・霧 →
## 番号札・塵）を add_part_step() で1回に1つずつ足す（5.5節）。部品は追加時に舞台の材質へ差し替え、
## 描画レイヤー11だけに置く（_dress_module）。
## 行の明るさ（行0〜10 = 立坑側の柱の線10 … ポンプ側の線0の照明）は CisternLighting の全体のシェーダー変数で舞台の焼いた光・
## 発光・反射に掛かり、同じ行の実ライトの強さにも掛かる。
## 本戦の2本のリフトのタワー（決着演出のスコアタワーと同じもの）と、水の流体シミュレーション（CisternFlow、
## 判定は持たない）もここに置き、SuddenDeathLoader が build_runtime_step() で1つずつ作る。舞台は動かさず、ワールドの原点に置く。
## visible は演出から直接切り替えてよい（当たり判定と画面の仕上げは表示中だけ有効）。

## The GraphicsQuality autoload instance can be a stale placeholder in an open
## editor; its rules are static, so call them through the script.
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const GRADE_LUT_PATH := "res://scenes/sudden_death/tank_generated/textures/grade_lut.res"

const FLOOR_Y := SuddenDeathLayout.FLOOR_Y
const BAYS_PART := &"CisternBays"
const ENDS_PART := &"CisternEnds"
const LIGHTS_PART := &"CisternLights"
const DRESSING_PART := &"CisternDressing"
## 照明の行のノード名（"Row00" …）。手前（上流）から奥へ並ぶ。
const LIGHT_ROW_PREFIX := "Row"
## 部品のインスタンスに生成ツールが付けるメタデータ（build_cistern_scenes.gd と同じ）。
const MODULE_META := &"cistern_module"
const MATERIALS_META := &"cistern_materials"
## 舞台の静的なメッシュだけの描画レイヤー（11）。実ライトの cull mask はこれを外す。
const HALL_LAYER := 11
const HALL_LAYER_MASK := 1 << (HALL_LAYER - 1)
## 光の行の数（行 r = 柱の線 10 − r）と線の間隔。
const ROW_COUNT := CisternLighting.BAY_COUNT
const BAY_PITCH := CisternLighting.BAY_PITCH
## The lamps of a pillar line hang in its coffers, at the line's own z.
const LAMP_DZ := CisternLighting.LAMP_OFFSET
## 流入トンネルのゲート（部品の CIS_InflowGate）が開くときに上がる量。開ききると上流の壁の裏に隠れる。
const GATE_TRAVEL := 11.4
const GATE_NODE := "CIS_InflowGate"
## 塵の粒の数（標準の画質で 0.6 倍、軽量 0.35 倍。GraphicsQuality.particle_amount）。
const DUST_AMOUNT := 2400
## 軽量はデカールを近くだけに（6.7節）。x = 消え始め、y = 消えるまでの長さ（m）。
const DECAL_FADE_LOW := Vector2(22.0, 8.0)
const DECAL_FADE := Vector2(90.0, 20.0)
## 体積フォグの解像度（全体の設定。6.7節：標準は低解像度、最高画質は高解像度）。
## 1フレームに撮り直す反射プローブの数（1個で舞台を6面描く。8個を一度に撮ると約20ms重くなる）。
const PROBES_PER_FRAME := 2
const FOG_VOLUME_SIZE := {"balanced": Vector2i(48, 48), "high": Vector2i(64, 64), "ultra": Vector2i(96, 96)}

# Runtime: the two lift towers, the water and the key lights on the towers.
## 本戦のキーライト（6.5節）：カメラの側（上流）の高い位置から、それぞれのタワーとその上の走者を照らす。
## 舞台（レイヤー11）は焼いた光なので当てない。位置はタワーの足元から（x はタワーのある側へ反転）。
const FOCUS_COLOR := Color(1.0, 0.94, 0.86)
const FOCUS_ENERGY := 9.0
const FOCUS_RANGE := 26.0
const FOCUS_ANGLE := 30.0
const FOCUS_FROM := Vector3(3.0, 10.5, -11.0)
const FOCUS_AIM := Vector3(0.0, 3.4, 0.0)
## 点く・消える速さ（1/s）。
const FOCUS_FADE := 1.6
## タワーの昇降：油圧の速さの上限（m/s）と、止まる前の減速の長さ（m）。負けて沈むときは速い。
const LIFT_SPEED := 1.4
const LIFT_EASE := 0.45
const PLUNGE_SPEED := 4.5
## 早押しで押した人のタワーの色帯が光る強さ（ResultFinaleStage.ACCENT_ENERGY の倍率）。
const BUZZ_GLOW := 4.0
const HALL_HALF_WIDTH := SuddenDeathLayout.HALL_HALF_WIDTH

## 環境光（apply_hall_light）。舞台は自分の焼いた光で描くので、これは人物・水門列・波だけに効く。
## 暗闇でも人物の輪郭が少し残る程度から、投光器の下で人物の影の側が潰れない程度まで。
const DARK_AMBIENT := 0.05
const LIT_AMBIENT := 0.32
## 部分シーン（区画・両端・照明・飾り）。シーンの外部参照なので、本体と一緒に別スレッドで読み込まれる。
## スクリプトに preload を書くと、型として参照しただけでメインスレッドで読まれてしまう。
@export var part_scenes: Array[PackedScene] = []
## The flood's assets, referenced here so they load on the loader's thread with the scene:
## [front mesh, VAT position, VAT normal, foam, water normal, spray atlas] (CisternFlow uses the last three).
@export var flood_assets: Array[Resource] = []

var game_state: QuizGameState = null

var _parts_added := 0
## 行ごとの明るさ（0〜1）。照明の部分シーンが入る前の指定も保持する。
var _row_brightness: Array[float] = []
## [{"z", "lamps": Array[Light3D], "energy": Array[float], "halos": Array[Light3D], "halo_energy": Array[float]}]
var _light_rows: Array[Dictionary] = []
var _opening_amount := 0.0
var _opening_energy := 0.0
## The light column's ShaderMaterial (own copy; "strength" follows set_opening_light).
var _column_material: ShaderMaterial = null
var _use_light_column := true
var _use_halos := true
var _gate_open := 0.0
var _gate_closed_y := 0.0
var _inflow_gate: Node3D = null
var _quality := GraphicsQualityRules.BALANCED
var _collision_shapes: Array[CollisionShape3D] = []
var _probes: Array[ReflectionProbe] = []
var _probe_nudge := 1.0
## The rows went dark since the last probe capture: re-capture once they are all lit again.
var _probes_stale := false
var _probe_captures := 0
## Probes still to re-capture, PROBES_PER_FRAME a frame (refresh_reflections()).
var _probe_queue: Array[ReflectionProbe] = []
## module -> source scene of the dressed instances (debug).
var _module_sources := {}
static var _grade_lut: ImageTexture3D = null

@onready var _floor_shape := get_node_or_null("Shell/FloorCollision/Shape") as CollisionShape3D
@onready var _shaft_light := get_node_or_null("Opening/ShaftLight") as SpotLight3D
@onready var _light_column := get_node_or_null("Opening/LightColumn") as MeshInstance3D
@onready var _referee_mark := get_node_or_null("Upstream/Balcony/RefereeMark") as Node3D
@onready var _grade := get_node_or_null("Grade") as CanvasLayer

# ------------------------------------------------------------------ runtime state
var _runtime: Node3D = null
## player_index -> ResultFinaleStage.create_tower() dictionary {"root", "lift", "accent", "muzzles"}.
var _towers := {}
## Platform tops (m over the floor) as drawn, where they are heading, and how fast (0 = the hydraulic pace).
var _tower_height := Vector2.ZERO
var _tower_target := Vector2.ZERO
var _tower_speed := Vector2.ZERO
## 0..1 per player: the buzzer glow of the tower's colour band.
var _tower_glow := Vector2.ZERO
var _flow: CisternFlow = null
var _runtime_steps := 0
var _runtime_built := false
var _clock := 0.0
var _prewarm_saved: Dictionary = {}
var _focus_lights: Array[SpotLight3D] = []
var _focus_amount := 0.0
var _focus_on := false
## The floor is wet behind the flood: CisternLighting's wet line follows its front.
var _wet_z := CisternLighting.DRY_Z


func _ready() -> void:
	set_process(false)
	CisternLighting.ensure()
	_ensure_rows()
	for index in range(_row_brightness.size()):
		CisternLighting.set_row(index, _row_brightness[index])
	if _shaft_light != null:
		_opening_energy = _shaft_light.light_energy
	if _light_column != null and _light_column.material_override is ShaderMaterial:
		# Own copy: the scene's material is shared through the resource cache.
		_column_material = (_light_column.material_override as ShaderMaterial).duplicate()
		_light_column.material_override = _column_material
	_collect_collision(self)
	_apply_opening()
	_apply_gate()
	_sync_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_visibility()
	elif what == NOTIFICATION_EXIT_TREE:
		# The globals belong to whichever cistern is shown: leave them dark, and the
		# renderer-wide fog and SSR settings as the project has them.
		CisternLighting.reset()
		_restore_rendering_server()


## The hidden cistern shares the world with the surface stage (same floor height): its floor,
## pillars and walls only collide while it is shown, and the grade overlay only shows with it.
func _sync_visibility() -> void:
	if not is_inside_tree():
		return
	var shown := is_visible_in_tree()
	for shape: CollisionShape3D in _collision_shapes:
		if is_instance_valid(shape):
			shape.set_deferred("disabled", not shown)
	if _grade != null:
		_grade.visible = shown and _quality != GraphicsQualityRules.LOW


func _collect_collision(root: Node) -> void:
	for node: Node in root.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		# The runtime shutters manage their own shapes.
		if is_instance_valid(_runtime) and _runtime.is_ancestor_of(shape):
			continue
		if shape not in _collision_shapes:
			_collision_shapes.append(shape)


## 画質段階に合わせる（SuddenDeathLoader が追加前に呼ぶ。6.7節）。天井開口のライトの影は軽量以外。
## 体積フォグがない段階（軽量）では、光の柱を加算の円錐（LightColumn）で見せ、保安灯のにじみを消し、
## デカールを近くだけにする。体積フォグの解像度と画面空間反射の半解像度は全体の設定なので、ここで
## 決めて、舞台が木から外れたら元に戻す。
func apply_quality(quality: String) -> void:
	_quality = GraphicsQualityRules.normalize(quality)
	var shaft := _shaft_light if _shaft_light != null else get_node_or_null("Opening/ShaftLight") as SpotLight3D
	if shaft != null:
		shaft.shadow_enabled = GraphicsQualityRules.gameplay_shadow_enabled(_quality)
	_use_light_column = not uses_volumetric_fog(_quality)
	_use_halos = uses_volumetric_fog(_quality)
	for index in range(_light_rows.size()):
		_apply_row(index)
	for part: Node in get_children():
		_apply_quality_to(part)
	_apply_opening()
	apply_rendering_server(_quality)
	_sync_visibility()


## Renderer-wide settings of the cistern tiers: volumetric fog resolution, half-size SSR below ultra.
static func apply_rendering_server(quality: String) -> void:
	var tier := GraphicsQualityRules.normalize(quality)
	if FOG_VOLUME_SIZE.has(tier):
		var size: Vector2i = FOG_VOLUME_SIZE[tier]
		RenderingServer.environment_set_volumetric_fog_volume_size(size.x, size.y)
	RenderingServer.environment_set_ssr_half_size(tier != GraphicsQualityRules.ULTRA)


static func _restore_rendering_server() -> void:
	RenderingServer.environment_set_volumetric_fog_volume_size(
		int(ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_size", 64)),
		int(ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_depth", 64)))
	RenderingServer.environment_set_ssr_half_size(
		bool(ProjectSettings.get_setting("rendering/environment/screen_space_reflection/half_size", true)))


# ------------------------------------------------------------------ parts

## 次の部分シーン（区画 → 両端 → 照明 → 飾り）を1つ追加する。全部入ったら true。
func add_part_step() -> bool:
	if _parts_added < part_scenes.size():
		var scene := part_scenes[_parts_added]
		_parts_added += 1
		if scene != null:
			var part := scene.instantiate()
			_dress(part)
			_apply_quality_to(part)
			add_child(part)
			_collect_collision(part)
			_sync_visibility()
			match part.name:
				LIGHTS_PART:
					_collect_light_rows(part)
					_collect_probes(part)
				ENDS_PART:
					_find_gate(part)
	return parts_added()


## Applies the instance transforms the build tool stored as metadata. Returns the instance count.
## (Kept for older generated scenes; the module parts carry no MultiMeshes.)
static func restore_multimeshes(root: Node) -> int:
	var total := 0
	var nodes: Array[Node] = root.find_children("*", "MultiMeshInstance3D", true, false)
	if root is MultiMeshInstance3D:
		nodes.append(root)
	for node: Node in nodes:
		var instance := node as MultiMeshInstance3D
		if instance.multimesh == null or not instance.has_meta(&"instance_transforms"):
			continue
		var transforms: Array = instance.get_meta(&"instance_transforms")
		var multimesh := instance.multimesh
		if multimesh.instance_count != transforms.size():
			multimesh.instance_count = transforms.size()
		for index in range(transforms.size()):
			multimesh.set_instance_transform(index, transforms[index])
		total += transforms.size()
	return total


func parts_added() -> bool:
	return _parts_added >= part_scenes.size()


func part_count() -> int:
	return part_scenes.size()


func parts_added_count() -> int:
	return _parts_added


## Dresses every module instance in `part` (meta cistern_module): hall material per surface by its
## glTF material name, visual layer 11 only (no real light reaches it), no shadows, no GI.
func _dress(part: Node) -> void:
	var modules: Array[Node] = part.find_children("*", "Node3D", true, false).filter(
		func(node: Node) -> bool: return node.has_meta(MODULE_META))
	if part.has_meta(MODULE_META):
		modules.append(part)
	for module: Node in modules:
		_dress_module(module as Node3D)


func _dress_module(module: Node3D) -> void:
	var table := {}
	var fallback: Material = null
	for pair: Variant in module.get_meta(MATERIALS_META, []):
		var entry := pair as Array
		table[str(entry[0])] = entry[1]
		if str(entry[0]) in ["TK_Concrete", "CIS_Concrete"]:
			fallback = entry[1] as Material
	_module_sources[str(module.get_meta(MODULE_META))] = module.scene_file_path
	for node: Node in module.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.layers = HALL_LAYER_MASK
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var key := material_key(mesh.surface_get_material(surface), mesh, surface)
			var material: Material = table.get(key, fallback)
			if material != null:
				mesh_instance.set_surface_override_material(surface, material)


## The hall material a module surface takes: its glTF material name without Blender's ".001" suffix.
static func material_key(material: Material, mesh: Mesh, surface: int) -> String:
	var key := material.resource_name if material != null else ""
	if key.is_empty() and mesh is ArrayMesh:
		key = (mesh as ArrayMesh).surface_get_name(surface).get_slice("#", 0)
	return key.get_slice(".", 0).strip_edges()


## Quality-dependent parts of the decorations: decal reach, dust amount, fog-only halos.
func _apply_quality_to(part: Node) -> void:
	var fade := DECAL_FADE_LOW if _quality == GraphicsQualityRules.LOW else DECAL_FADE
	for node: Node in part.find_children("*", "Decal", true, false):
		(node as Decal).distance_fade_begin = fade.x
		(node as Decal).distance_fade_length = fade.y
	for node: Node in part.find_children("Dust", "GPUParticles3D", true, false):
		var amount := GraphicsQualityRules.particle_amount(DUST_AMOUNT, _quality)
		if (node as GPUParticles3D).amount != amount:
			(node as GPUParticles3D).amount = amount
	# The lamps' highlights on the hall (its light()) are the costliest per-pixel work: off on low.
	if part.name == LIGHTS_PART:
		for node: Node in part.find_children("*", "Light3D", true, false):
			var light := node as Light3D
			if light.light_cull_mask == 0:
				continue
			if _quality == GraphicsQualityRules.LOW:
				light.light_cull_mask &= ~HALL_LAYER_MASK
			else:
				light.light_cull_mask |= HALL_LAYER_MASK


func _collect_light_rows(root: Node) -> void:
	_light_rows.clear()
	for row_node: Node in root.get_children():
		if not row_node is Node3D or not str(row_node.name).begins_with(LIGHT_ROW_PREFIX):
			continue
		var lamps: Array[Light3D] = []
		var energies: Array[float] = []
		var halos: Array[Light3D] = []
		var halo_energies: Array[float] = []
		for child: Node in row_node.get_children():
			if not child is Light3D:
				continue
			var light := child as Light3D
			# Fog-only halos light no surface (cull mask 0); they need volumetric fog.
			if light.light_cull_mask == 0:
				halos.append(light)
				halo_energies.append(light.light_energy)
			else:
				lamps.append(light)
				energies.append(light.light_energy)
		_light_rows.append({"z": (row_node as Node3D).position.z, "lamps": lamps, "energy": energies,
			"halos": halos, "halo_energy": halo_energies})
	_ensure_rows()
	for index in range(_light_rows.size()):
		_apply_row(index)


func _collect_probes(root: Node) -> void:
	_probes.clear()
	for node: Node in root.find_children("*", "ReflectionProbe", true, false):
		_probes.append(node as ReflectionProbe)


func _find_gate(root: Node) -> void:
	_inflow_gate = root.find_child(GATE_NODE, true, false) as Node3D
	if _inflow_gate != null:
		_gate_closed_y = _inflow_gate.position.y
	_apply_gate()


## 下流端の脱出ハッチ（部品の CIS_Hatch_L / CIS_Hatch_R、-X / +X のハシゴの上）。両端が入る前は null。
func hatch_node(right: bool) -> Node3D:
	return find_child("CIS_Hatch_R" if right else "CIS_Hatch_L", true, false) as Node3D


# ------------------------------------------------------------------ lights

## 照明の行の数（行0〜10 = 柱の線10〜0、立坑側 → ポンプ側）。照明の部分シーンが入る前から 11。
func row_count() -> int:
	_ensure_rows()
	return _row_brightness.size()


## 行の z（柱の線の z。その線の照明は同じ z の格天井に吊られている）。
func light_row_z(index: int) -> float:
	if index >= 0 and index < _light_rows.size():
		return float(_light_rows[index].z)
	return CisternLighting.ROW_Z0 + BAY_PITCH * float(clampi(index, 0, ROW_COUNT - 1))


func row_brightness(index: int) -> float:
	_ensure_rows()
	return _row_brightness[index] if index >= 0 and index < _row_brightness.size() else 0.0


## 行ごとの明るさ（0〜1）。舞台の焼いた光・器具の発光・反射（全体のシェーダー変数）と、その行の
## 実ライトの強さに掛ける。0 のライトは描かない。
func set_row_brightness(index: int, amount: float) -> void:
	_ensure_rows()
	if index < 0 or index >= _row_brightness.size():
		return
	var value := clampf(amount, 0.0, 1.0)
	_row_brightness[index] = value
	_apply_row(index)
	_watch_probes()


func set_all_rows(amount: float) -> void:
	for index in range(row_count()):
		set_row_brightness(index, amount)


## 天井開口から落ちる冷たい光の柱（0〜1）。実ライト（人物・デッキ・霧）と、床の光だまり（シェーダー）。
func set_opening_light(amount: float) -> void:
	_opening_amount = clampf(amount, 0.0, 1.0)
	_apply_opening()


func opening_light() -> float:
	return _opening_amount


## 流入トンネルのローラーゲート（CIS_InflowGate）。0＝閉、1＝全開（+Y へ 11.4m 引き上げられ、壁の裏に隠れる）。
func set_inflow_gate(open: float) -> void:
	_gate_open = clampf(open, 0.0, 1.0)
	_apply_gate()


func inflow_gate() -> float:
	return _gate_open


## 審判の立ち位置（操作室のバルコニーの床、手すりの内側）。基底は単位行列で、+Z が下流
## （地下神殿の側）。選手と同じく +Z を正面とするモデルなら、そのまま置けば通路を向く。
func referee_transform() -> Transform3D:
	var mark := _referee_mark if _referee_mark != null else get_node_or_null("Upstream/Balcony/RefereeMark") as Node3D
	if mark != null and mark.is_inside_tree():
		return mark.global_transform
	return transform * (mark.transform if mark != null else Transform3D.IDENTITY)


## 反射プローブを撮り直す（照明が点いた後）。UPDATE_ONCE のプローブは少し動かすと撮り直す。
## 1フレームに PROBES_PER_FRAME 個ずつ（今のフレームから）。
func refresh_reflections() -> void:
	_probes_stale = false
	_probe_captures += 1
	_probe_nudge = -_probe_nudge
	_probe_queue.clear()
	for probe: ReflectionProbe in _probes:
		if is_instance_valid(probe):
			_probe_queue.append(probe)
	_capture_queued_probes()


func _process(_delta: float) -> void:
	_capture_queued_probes()


func _capture_queued_probes() -> void:
	for _index in range(mini(PROBES_PER_FRAME, _probe_queue.size())):
		var probe: ReflectionProbe = _probe_queue.pop_front()
		if is_instance_valid(probe):
			probe.position.x = 0.001 * _probe_nudge
	set_process(not _probe_queue.is_empty())


## Rows dropping well below full make the captured reflections stale; once every row is lit
## again (the landing sequence), capture once more.
func _watch_probes() -> void:
	if _probes.is_empty() or is_prewarming():
		return
	var lowest := 1.0
	for value: float in _row_brightness:
		lowest = minf(lowest, value)
	if lowest < 0.5:
		_probes_stale = true
	elif _probes_stale and lowest >= 0.999:
		refresh_reflections()


func _ensure_rows() -> void:
	var count := maxi(_light_rows.size(), ROW_COUNT)
	while _row_brightness.size() < count:
		_row_brightness.append(0.0)


func _apply_row(index: int) -> void:
	var amount := _row_brightness[index] if index < _row_brightness.size() else 0.0
	CisternLighting.set_row(index, amount)
	if index < 0 or index >= _light_rows.size():
		return
	var row: Dictionary = _light_rows[index]
	var lamps: Array[Light3D] = row.lamps
	var energies: Array[float] = row.energy
	for lamp_index in range(lamps.size()):
		lamps[lamp_index].light_energy = energies[lamp_index] * amount
		lamps[lamp_index].visible = amount > 0.001
	var halos: Array[Light3D] = row.halos
	var halo_energies: Array[float] = row.halo_energy
	for halo_index in range(halos.size()):
		halos[halo_index].light_energy = halo_energies[halo_index] * amount
		halos[halo_index].visible = _use_halos and amount > 0.001


func _apply_opening() -> void:
	CisternLighting.set_opening(_opening_amount)
	if _shaft_light != null:
		_shaft_light.light_energy = _opening_energy * _opening_amount
		_shaft_light.visible = _opening_amount > 0.001
	if _light_column != null:
		_light_column.visible = _use_light_column and _opening_amount > 0.001
		if _column_material != null:
			_column_material.set_shader_parameter("strength", _opening_amount)


func _apply_gate() -> void:
	if _inflow_gate != null:
		var eased := _gate_open * _gate_open * (3.0 - 2.0 * _gate_open)
		_inflow_gate.position.y = _gate_closed_y + GATE_TRAVEL * eased


# ------------------------------------------------------------------ environment

static func uses_volumetric_fog(quality: String) -> bool:
	return not GraphicsQualityRules.is_mobile_target() and GraphicsQualityRules.is_at_least(quality, GraphicsQualityRules.BALANCED)


## 地下用の環境（6.4・6.7節）。深い暗部と、照明の周りのにじみ。トーンマップは AgX、色補正は
## 生成した3D LUT（cistern_generated/textures/grade_lut.res）。体積フォグは標準以上（軽量は距離の霧と
## 光の柱の板）、画面空間反射は高画質（半解像度）と最高画質、SSAO は高画質以上、SSIL は最高画質のみ。
## 舞台の反射は反射プローブ（REFLECTION_SOURCE_DISABLED で空の反射は無し）。
static func make_environment(quality: String) -> Environment:
	var tier := GraphicsQualityRules.normalize(quality)
	var mobile := GraphicsQualityRules.is_mobile_target()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.004, 0.005, 0.006)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.46, 0.52)
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.tonemap_agx_contrast = 1.15
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(0.045, 0.050, 0.056)
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.012
	environment.fog_sky_affect = 0.0
	environment.fog_sun_scatter = 0.0
	# Lamp halos: only the HDR peaks (lenses, the shaft column, wet glints) bloom.
	environment.glow_enabled = not mobile
	environment.glow_normalized = false
	environment.glow_intensity = 0.55 if tier == GraphicsQualityRules.LOW else 0.7
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.15
	environment.glow_hdr_scale = 2.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var levels := PackedFloat32Array([0.0, 0.6, 0.9, 1.0, 0.8, 0.0, 0.0] if tier == GraphicsQualityRules.LOW else [0.0, 0.5, 0.8, 1.0, 1.0, 0.6, 0.0])
	for level in range(levels.size()):
		environment.set_glow_level(level, levels[level])
	if uses_volumetric_fog(tier):
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = 0.006
		environment.volumetric_fog_albedo = Color(0.82, 0.86, 0.90)
		environment.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
		environment.volumetric_fog_anisotropy = 0.55
		environment.volumetric_fog_length = {"balanced": 80.0, "high": 110.0, "ultra": 140.0}.get(tier, 80.0)
		environment.volumetric_fog_detail_spread = 2.0
		environment.volumetric_fog_gi_inject = 0.0
		environment.volumetric_fog_sky_affect = 0.0
		environment.volumetric_fog_temporal_reprojection_enabled = true
		environment.fog_density = 0.005
	var high := not mobile and GraphicsQualityRules.is_at_least(tier, GraphicsQualityRules.HIGH)
	environment.ssr_enabled = high
	if high:
		# Puddles: the lamps, the gates and the shaft column (half resolution below ultra).
		environment.ssr_max_steps = 72 if tier == GraphicsQualityRules.ULTRA else 48
		environment.ssr_fade_in = 0.12
		environment.ssr_fade_out = 2.0
		environment.ssr_depth_tolerance = 0.25
	environment.ssao_enabled = high
	if high:
		environment.ssao_radius = 1.2
		environment.ssao_intensity = 2.2
		environment.ssao_power = 1.6
		environment.ssao_detail = 0.6
		environment.ssao_horizon = 0.06
		environment.ssao_sharpness = 0.98
		environment.ssao_light_affect = 0.0
		environment.ssao_ao_channel_affect = 0.0
	environment.ssil_enabled = not mobile and tier == GraphicsQualityRules.ULTRA
	if environment.ssil_enabled:
		environment.ssil_radius = 6.0
		environment.ssil_intensity = 0.8
		environment.ssil_sharpness = 0.98
		environment.ssil_normal_rejection = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.03
	environment.adjustment_saturation = 0.96
	environment.adjustment_color_correction = grade_lut()
	apply_hall_light(environment, 1.0)
	return environment


## The colour grade as a 3D LUT, built once from the strip the build tool saved (blue slices side by side).
static func grade_lut() -> Texture3D:
	if _grade_lut != null:
		return _grade_lut
	var strip := load(GRADE_LUT_PATH) as Image if ResourceLoader.exists(GRADE_LUT_PATH) else null
	if strip == null or strip.get_height() <= 0:
		return null
	var size := strip.get_height()
	var layers: Array[Image] = []
	for b in range(size):
		layers.append(strip.get_region(Rect2i(b * size, 0, size, size)))
	var lut := ImageTexture3D.new()
	if lut.create(strip.get_format(), size, size, size, false, layers) != OK:
		return null
	_grade_lut = lut
	return _grade_lut


## 地下神殿の環境の明るさ（0＝照明が全て消えた暗闇、1＝点灯）。人物・水門列・波の環境光と霧への
## 光の注入を照明の行と一緒に上げ下げするため、着地の点灯演出で行の平均の明るさを渡す。
## 舞台そのものは焼いた光で描くので、ここでは変わらない。make_environment() の直後は 1。
static func apply_hall_light(environment: Environment, amount: float) -> void:
	if environment == null:
		return
	var lit := clampf(amount, 0.0, 1.0)
	environment.ambient_light_energy = lerpf(DARK_AMBIENT, LIT_AMBIENT, lit)
	environment.volumetric_fog_ambient_inject = lerpf(0.0, 0.04, lit)


# ------------------------------------------------------------------ runtime build

## リフトのタワー・水・キーライトを作り直す準備。作るのは build_runtime_step()。
func setup_runtime(state: QuizGameState) -> void:
	clear_runtime()
	game_state = state
	_runtime = Node3D.new()
	_runtime.name = "Runtime"
	add_child(_runtime)
	_clock = 0.0
	_runtime_steps = 0
	CisternLighting.set_wet_z(CisternLighting.DRY_Z)


## 1回に1つ：P1のタワー → P2のタワー → 水（流体シミュレーション）→ キーライト。全部できたら true。
func build_runtime_step() -> bool:
	if _runtime_built:
		return true
	if not is_instance_valid(_runtime):
		push_warning("CisternStage.build_runtime_step() before setup_runtime()")
		return false
	match _runtime_steps:
		0, 1:
			_build_tower(_runtime_steps + 1)
		2:
			_build_flow()
		_:
			_build_focus_lights()
			_runtime_built = true
	_runtime_steps += 1
	return _runtime_built


func runtime_step_count() -> int:
	return 4


func runtime_steps_done() -> int:
	return mini(_runtime_steps, runtime_step_count())


func is_runtime_built() -> bool:
	return _runtime_built and is_instance_valid(_runtime)


func clear_runtime() -> void:
	if is_instance_valid(_runtime):
		_runtime.queue_free()
	_runtime = null
	_towers.clear()
	_flow = null
	_focus_lights.clear()
	_focus_amount = 0.0
	_focus_on = false
	_tower_height = Vector2.ZERO
	_tower_target = Vector2.ZERO
	_tower_speed = Vector2.ZERO
	_tower_glow = Vector2.ZERO
	_runtime_built = false
	_runtime_steps = 0
	_wet_z = CisternLighting.DRY_Z
	CisternLighting.set_wet_z(CisternLighting.DRY_Z)
	game_state = null


## A player's score tower (the same towers that sank at the draw): retracted into the floor (the
## platform flush with it) until the player steps on, its tier column reaching down out of sight.
func _build_tower(player_index: int) -> void:
	var built := ResultFinaleStage.create_tower(player_index, _runtime)
	var root := built.root as Node3D
	root.name = "LiftTowerP%d" % player_index
	root.position = SuddenDeathLayout.lift_position(player_index)
	_towers[player_index] = built
	if player_index == 1:
		_tower_height.x = 0.0
		_tower_target.x = 0.0
	else:
		_tower_height.y = 0.0
		_tower_target.y = 0.0
	_apply_towers()


func _build_flow() -> void:
	_flow = CisternFlow.new()
	_flow.name = "CisternFlow"
	_runtime.add_child(_flow)
	_flow.setup(_quality, flood_assets)
	var tuning := game_state.sudden_death.tuning if game_state != null and game_state.sudden_death != null else SuddenDeathTuning.new()
	_flow.set_level(tuning.water_level)
	_apply_towers()


func _build_focus_lights() -> void:
	for player_index in [1, 2]:
		var light := SpotLight3D.new()
		light.name = "TowerKeyP%d" % player_index
		light.light_color = FOCUS_COLOR
		light.light_energy = 0.0
		light.light_specular = 0.6
		light.spot_range = FOCUS_RANGE
		light.spot_angle = FOCUS_ANGLE
		light.spot_angle_attenuation = 0.8
		light.light_cull_mask = 0xFFFFF & ~HALL_LAYER_MASK
		light.shadow_enabled = false
		light.visible = false
		light.set_meta(&"player", player_index)
		_runtime.add_child(light)
		_focus_lights.append(light)
	_place_focus()


# ------------------------------------------------------------------ towers

func tower_position(player_index: int) -> Vector3:
	return SuddenDeathLayout.lift_position(player_index)


## The platform top of [param player_index]'s tower as drawn (m over the floor).
func tower_height(player_index: int) -> float:
	return _tower_height.x if player_index == 1 else _tower_height.y


## Sends the tower to [param top] (m over the floor) at the hydraulic pace, or at [param speed] m/s.
## [param snap] puts it there at once.
func set_tower_target(player_index: int, top: float, speed := 0.0, snap := false) -> void:
	if player_index == 1:
		_tower_target.x = top
		_tower_speed.x = speed
		if snap:
			_tower_height.x = top
	else:
		_tower_target.y = top
		_tower_speed.y = speed
		if snap:
			_tower_height.y = top
	if snap:
		_apply_towers()


func tower_target(player_index: int) -> float:
	return _tower_target.x if player_index == 1 else _tower_target.y


func is_tower_moving(player_index: int) -> bool:
	return absf(tower_height(player_index) - tower_target(player_index)) > 0.002


## 0..1: the buzzer light in the tower's colour band.
func set_tower_glow(player_index: int, amount: float) -> void:
	if player_index == 1:
		_tower_glow.x = clampf(amount, 0.0, 1.0)
	else:
		_tower_glow.y = clampf(amount, 0.0, 1.0)


func _step_towers(dt: float) -> void:
	for player_index in [1, 2]:
		var height := tower_height(player_index)
		var target := tower_target(player_index)
		var fast := (_tower_speed.x if player_index == 1 else _tower_speed.y)
		var top_speed := fast if fast > 0.0 else LIFT_SPEED
		# The hydraulics ease out over the last LIFT_EASE metres.
		var speed := top_speed * clampf(absf(target - height) / LIFT_EASE, 0.25, 1.0) if fast <= 0.0 else top_speed
		var moved := move_toward(height, target, speed * dt)
		if _flow != null and height > _flow.level() + 0.05 and moved <= _flow.level() + 0.05:
			# The platform hits the water.
			var at := tower_position(player_index)
			_flow.splash(Vector3(at.x, at.y + _flow.level(), at.z), 1.5, 0.5)
		if player_index == 1:
			_tower_height.x = moved
		else:
			_tower_height.y = moved
	_apply_towers()


func _apply_towers() -> void:
	for player_index: int in _towers:
		var built: Dictionary = _towers[player_index]
		var top := tower_height(player_index)
		(built.lift as Node3D).position.y = top
		var accent := built.accent as StandardMaterial3D
		var glow := _tower_glow.x if player_index == 1 else _tower_glow.y
		accent.emission_energy_multiplier = ResultFinaleStage.ACCENT_ENERGY * (1.0 + BUZZ_GLOW * glow)
		if _flow != null:
			var at := tower_position(player_index)
			_flow.set_tower(player_index - 1, Vector2(at.x, at.z), SuddenDeathLayout.LIFT_RADIUS, top)


# ------------------------------------------------------------------ runtime update

## The water. Hidden and dry until start_flood().
func flow() -> CisternFlow:
	return _flow


## The inflow gate has lifted: the flood bursts out of the tunnel.
func start_flood() -> void:
	if _flow != null:
		_flow.start_flood()


## The key lights on the towers come on (from the countdown) or go off.
func set_focus(on: bool) -> void:
	_focus_on = on


## 毎フレーム：タワーの昇降と光、水、キーライト、濡れた床。
func update_runtime(dt: float, _sd: SuddenDeathState) -> void:
	if not is_runtime_built():
		return
	_clock += dt
	_step_towers(dt)
	if _flow != null:
		_flow.update_flow(dt)
		_flow.set_drips(_flow.is_flooding(), Vector3(0.0, 0.0, SuddenDeathLayout.LIFT_Z - 6.0))
		if _flow.is_flooding():
			# The floor behind the front is wet (the front runs at about 7 m/s).
			var front := SuddenDeathLayout.HALL_START_Z + 7.0 * _flow.flood_time()
			if front - 0.5 > _wet_z:
				_wet_z = minf(front - 0.5, SuddenDeathLayout.HALL_END_Z)
				CisternLighting.set_wet_z(_wet_z)
	_focus_amount = move_toward(_focus_amount, 1.0 if _focus_on else 0.0, FOCUS_FADE * dt)
	_place_focus()


## SuddenDeathState の出来事を水に写す：沈んだタワーの揺れ、落ちた走者のしぶき。
func on_event(event: Dictionary) -> void:
	if not is_runtime_built() or _flow == null:
		return
	match str(event.get("kind", "")):
		"sink":
			var at := tower_position(int(event.get("player", 1)))
			# The tower jolts down a step: a ring of ripples round its column.
			_flow.splash(Vector3(at.x, at.y + _flow.level(), at.z), 1.2, 0.08, false)
		"caught":
			var at := _player_position(int(event.get("player", 0)))
			_flow.splash(Vector3(at.x, SuddenDeathLayout.FLOOR_Y + _flow.level(), at.z + 0.8), 1.1, 0.4)


func _place_focus() -> void:
	var bay := clampi(roundi((SuddenDeathLayout.LIFT_Z - LAMP_DZ - CisternLighting.ROW_Z0) / BAY_PITCH), 0, maxi(_row_brightness.size() - 1, 0))
	var level := _focus_amount * (_row_brightness[bay] if bay < _row_brightness.size() else 1.0)
	for light: SpotLight3D in _focus_lights:
		var player_index := int(light.get_meta(&"player", 1))
		var at := tower_position(player_index)
		var side := signf(at.x)
		var from := at + Vector3(FOCUS_FROM.x * side, FOCUS_FROM.y, FOCUS_FROM.z)
		var aim := at + Vector3(FOCUS_AIM.x * side, tower_height(player_index) + 1.0, FOCUS_AIM.z)
		light.transform = Transform3D(Basis.looking_at(aim - from, Vector3.UP), from)
		light.light_energy = FOCUS_ENERGY * level
		light.visible = level > 0.002


func _player_position(player_index: int) -> Vector3:
	if game_state == null:
		return Vector3(0.0, FLOOR_Y + 1.0, 0.0)
	if player_index == 1:
		return Vector3(game_state.player_x, FLOOR_Y + 1.0 + game_state.player_y, game_state.player_z)
	return Vector3(game_state.player2_x, FLOOR_Y + 1.0 + game_state.player2_y, game_state.player2_z)


## Materials build_runtime_step() creates in code that SuddenDeathLoader should compile beforehand:
## the flow's come from CisternFlow.warm_up_step() (none are left here).
static func runtime_shader_samples() -> Array[Material]:
	var samples: Array[Material] = []
	return samples


# ------------------------------------------------------------------ prewarm

## 描画準備用のカメラ位置（ワールド座標）：本戦（上流から2本のタワーと下流の柱の森）・上流（トンネルと
## 操作室）・天井開口・タワーの足元の水。
func prewarm_views() -> Array[Dictionary]:
	var lift := SuddenDeathLayout.LIFT_Z
	var views: Array[Dictionary] = [
		{"name": "duel", "from": Vector3(0.0, FLOOR_Y + 5.0, lift - 12.5), "to": Vector3(0.0, FLOOR_Y + 3.2, lift + 6.0)},
		{"name": "upstream", "from": Vector3(7.0, FLOOR_Y + 3.2, -12.0), "to": Vector3(-1.0, FLOOR_Y + 1.5, -30.0)},
		{"name": "opening", "from": Vector3(5.0, FLOOR_Y + 1.8, 13.0), "to": Vector3(0.0, FLOOR_Y + 18.0, -1.0)},
		{"name": "water", "from": Vector3(-1.0, FLOOR_Y + 2.2, lift - 8.0), "to": Vector3(-4.0, FLOOR_Y + 1.2, lift + 1.0)},
	]
	return views


## SuddenDeathLoader：パイプラインの準備の間だけ、全ての照明・水・タワーの光を見える状態にする。
func begin_prewarm() -> void:
	if not _prewarm_saved.is_empty():
		return
	_ensure_rows()
	_prewarm_saved = {"rows": _row_brightness.duplicate(), "opening": _opening_amount, "gate": _gate_open}
	set_all_rows(1.0)
	set_opening_light(1.0)
	set_inflow_gate(0.5)
	# The probes render (and compile their passes) while everything is lit.
	refresh_reflections()
	if not is_runtime_built():
		return
	set_tower_target(1, 3.0, 0.0, true)
	set_tower_glow(1, 1.0)
	_focus_on = true
	_focus_amount = 1.0
	_place_focus()


## SuddenDeathLoader, every frame of the pipeline preparation (1, 2, …): the effects come on a few at a
## time so no single frame compiles everything: the water, then its spray.
func prewarm_tick(frame: int) -> void:
	if not is_prewarming() or not is_runtime_built() or _flow == null:
		return
	match frame:
		1:
			_flow.prewarm(true, SuddenDeathLayout.LIFT_Z, 1)
		2:
			_flow.prewarm(true, SuddenDeathLayout.LIFT_Z, 2)


func end_prewarm() -> void:
	if _prewarm_saved.is_empty():
		return
	var rows: Array = _prewarm_saved.rows
	for index in range(mini(rows.size(), _row_brightness.size())):
		set_row_brightness(index, float(rows[index]))
	set_opening_light(float(_prewarm_saved.opening))
	set_inflow_gate(float(_prewarm_saved.gate))
	_prewarm_saved.clear()
	# Some probe faces may still render after the rows went dark: capture again once they are lit.
	_probes_stale = true
	if not is_runtime_built():
		return
	if _flow != null:
		_flow.prewarm(false, 0.0)
	set_tower_target(1, 0.0, 0.0, true)
	set_tower_glow(1, 0.0)
	_focus_on = false
	_focus_amount = 0.0
	_place_focus()
	CisternLighting.set_wet_z(_wet_z)


func is_prewarming() -> bool:
	return not _prewarm_saved.is_empty()


# ------------------------------------------------------------------ debug

func get_debug_snapshot() -> Dictionary:
	var brightness: Array = []
	for amount: float in _row_brightness:
		brightness.append(snappedf(amount, 0.01))
	return {
		"active": is_runtime_built(), "runtime_steps": runtime_steps_done(),
		"towers": {"built": _towers.size(), "height": [snappedf(_tower_height.x, 0.001), snappedf(_tower_height.y, 0.001)],
			"target": [snappedf(_tower_target.x, 0.001), snappedf(_tower_target.y, 0.001)],
			"glow": [snappedf(_tower_glow.x, 0.01), snappedf(_tower_glow.y, 0.01)]},
		"flow": _flow.get_debug_snapshot() if _flow != null else {}, "wet_z": snappedf(_wet_z, 0.01),
		"lights": {"rows": row_count(), "loaded": _light_rows.size(), "brightness": brightness,
			"opening": snappedf(_opening_amount, 0.01), "gate": snappedf(_gate_open, 0.01)},
		"parts": {"added": _parts_added, "total": part_scenes.size()},
		"quality": _quality, "prewarming": is_prewarming(),
		"modules": _module_sources.duplicate(),
		"probes": {"count": _probes.size(), "captures": _probe_captures, "stale": _probes_stale, "queued": _probe_queue.size()},
		"global": CisternLighting.get_debug_snapshot(),
		"focus": {"amount": snappedf(_focus_amount, 0.01),
			"energy": snappedf(_focus_lights[0].light_energy, 0.01) if not _focus_lights.is_empty() else 0.0},
		"gate_node": _inflow_gate != null,
	}

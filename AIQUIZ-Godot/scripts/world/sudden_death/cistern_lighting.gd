class_name CisternLighting
extends RefCounted

## 地下ステージ（調圧水槽、docs/surge_tank_reproduction.md）の全体のシェーダー変数。
## cistern_row_light：32×1、最近傍。R＝照明の行 r（0〜10、立坑側から）の明るさを画素 r に（画素11〜31は未使用）。
## 行 r は柱の線 10 − r（線は z = 112 − 14k、ポンプ側が線0）。
## cistern_row_grid：x＝行0の線の z、y＝線の間隔、z＝行の数（11）、
## w＝天井開口のライトの量（0〜1。実物の調圧水槽には開口がないので舞台のシェーダーは使わない）。
## 線の照明（吊り下げ式の高天井灯）は、その線の格天井の中央（柱のない列 |x| ≤ 21、同じ列の柱と柱の中間）に、線と同じ z で吊られている。
## 舞台の静的なメッシュ（shaders/surge_tank/tank_*.gdshader）はこの値で焼いた光・発光・反射を
## 線ごとに明るくする。テクスチャは全ての CisternStage で共有する（静的）。舞台が木から外れたら
## reset() で真っ暗に戻す。

const ROW_TEXTURE_PARAM := &"cistern_row_light"
const ROW_GRID_PARAM := &"cistern_row_grid"
## The flood has wetted everything upstream of this world z (docs 6.6). -1000 = dry.
const WET_PARAM := &"cistern_wet_z"
const DRY_Z := -1000.0
const TEXTURE_WIDTH := 32
const BAY_FIRST := 0
const BAY_COUNT := 11
## World z (the stage is the plan scaled by SuddenDeathLayout.TANK_SCALE about the landing point).
const BAY_PITCH := SuddenDeathLayout.LINE_PITCH
## z of the pillar line of row 0: line 10, the last line before the shaft-side end wall.
const ROW_Z0 := SuddenDeathLayout.FIRST_LINE_Z
## The lamps of a row hang in the coffers of its pillar line, at the line's own z.
const LAMP_OFFSET := 0.0

static var _image: Image = null
static var _texture: ImageTexture = null
static var _brightness := PackedFloat32Array()
static var _opening := 0.0
static var _wet_z := DRY_Z
static var _dirty := false


## Creates the shared texture and binds both globals (idempotent). Safe without a renderer.
static func ensure() -> void:
	if _texture != null:
		return
	_brightness.resize(BAY_COUNT)
	_brightness.fill(0.0)
	_image = Image.create_empty(TEXTURE_WIDTH, 1, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	_texture = ImageTexture.create_from_image(_image)
	_set_global(ROW_TEXTURE_PARAM, _texture)
	_push_grid()


## Brightness (0〜1) of light row `row` (row r = the lamps of pillar line 10 − r, 0 at the shaft end … 10).
static func set_row(row: int, amount: float) -> void:
	ensure()
	if row < 0 or row >= BAY_COUNT:
		return
	var value := clampf(amount, 0.0, 1.0)
	if is_equal_approx(_brightness[row], value):
		return
	_brightness[row] = value
	_image.set_pixel(row, 0, Color(value, 0.0, 0.0, 1.0))
	_mark_dirty()


static func row(index: int) -> float:
	return _brightness[index] if index >= 0 and index < _brightness.size() else 0.0


## The shaft light through the ceiling opening (0〜1), read by the hall shaders from cistern_row_grid.w.
static func set_opening(amount: float) -> void:
	ensure()
	var value := clampf(amount, 0.0, 1.0)
	if is_equal_approx(_opening, value):
		return
	_opening = value
	_push_grid()


static func opening() -> float:
	return _opening


## The farthest the flood has reached: the hall stays wet behind it (it never dries during a match).
static func set_wet_z(z: float) -> void:
	if is_equal_approx(_wet_z, z):
		return
	_wet_z = z
	_set_global(WET_PARAM, z)


static func wet_z() -> float:
	return _wet_z


## Everything dark (the stage left the tree or was freed).
static func reset() -> void:
	if _texture == null:
		return
	_brightness.fill(0.0)
	_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	_opening = 0.0
	_flush()
	_push_grid()
	set_wet_z(DRY_Z)


static func get_debug_snapshot() -> Dictionary:
	var values: Array = []
	for value: float in _brightness:
		values.append(snappedf(value, 0.01))
	return {"rows": values, "opening": snappedf(_opening, 0.01), "bound": _texture != null, "wet_z": snappedf(_wet_z, 0.01)}


## The texture uploads once per frame however many rows changed in it.
static func _mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_flush_deferred.call_deferred()


static func _flush_deferred() -> void:
	_flush()


static func _flush() -> void:
	_dirty = false
	if _texture != null and _image != null:
		_texture.update(_image)


static func _push_grid() -> void:
	_set_global(ROW_GRID_PARAM, Vector4(ROW_Z0, BAY_PITCH, float(BAY_COUNT), _opening))


static func _set_global(param: StringName, value: Variant) -> void:
	# Declared in project.godot [shader_globals] (listing them is editor-only, so just set).
	RenderingServer.global_shader_parameter_set(param, value)

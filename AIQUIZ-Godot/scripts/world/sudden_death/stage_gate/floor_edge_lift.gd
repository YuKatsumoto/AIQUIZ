class_name FloorEdgeLift
extends Node3D

## 床の端の昇降台（docs/sudden_death_v2/c130_float.md 第4・10章、skygate_build_plan.md 4.3）。
## 床の横の壁に付いた折りたたみのデッキ。しまっているときは、デッキが床の縁から下へぶら下がって壁に沿っている（上面が外を向き、
## 手すりは上面に寝かせてある。壁の縦のレール 2 本と回転灯と一緒に、壁の設備のように見える）。
##   出す（deploy）：付け根の軸で外へ 90° 起きて床と同じ高さの水平になり、手すりが起きる（swing・rails）
##   下ろす（start_lower）：台車ごとレールに沿って、水上機の貨物室の床の高さ（target_y）まで下りる（lower）
##   しまう（start_return）：上がる → 手すりを寝かせる → 下へぶら下がる
## 水上機は、デッキが下りきってから後ろ向きに寄ってくる（床の高さのデッキは尾翼に当たるため。c130_float.md 第10章）。
## 動きは自分で進める（advance）。テストと古い呼び方のために set_extend・set_lower・set_t（すぐその姿にする）も残す。
##
## 座標（side ＝ +1）：壁の面 x ＝ wall_x、床の上面 y ＝ floor_y、台座の z ＝ gap_z。デッキの付け根の軸は壁から HINGE_X、
## 床の上面から DECK_T 下（デッキの下面の壁側の辺）。

## デッキ（stage_gate_layout.json と同じ。build_stage_gate.py）
const DECK_LEN := 4.36
const DECK_HALF_Z := 1.9
const DECK_T := 0.26
const HINGE_X := 0.04
const RAIL_Z := 1.80
## 動きの長さ（秒）：起きる・手すり・下りる・上がる・寝かせる・ぶら下がる
const SWING_TIME := 2.0
const RAILS_TIME := 0.55
const LOWER_TIME := 3.2
const RAISE_TIME := 2.8
const FOLD_TIME := 0.5
const STOW_TIME := 1.7
## 古い約束（set_reach の上限）
const DECK_REACH := DECK_LEN + HINGE_X

var side := 1.0
var wall_x := StageConstants.FLOOR_HALF_WIDTH
var floor_y := StageConstants.FLOOR_TOP_Y
var target_y := StageConstants.OCEAN_SURFACE_Y + 1.9
var gap_z := 0.0
## 0＝ぶら下がっている、1＝水平（床の高さ）
var swing := 0.0
## 0＝寝ている、1＝起きた
var rails := 0.0
## 0＝床の高さ、1＝貨物室の床の高さ
var lower := 0.0
## 古い約束：出ている割合（起きる・手すりをまとめて）
var extend := 0.0

var _deck: MeshInstance3D = null
var _carriage: MeshInstance3D = null
var _frame: MeshInstance3D = null
var _rails: Array[MeshInstance3D] = []
var _beacon: MeshInstance3D = null
var _beacon_material: StandardMaterial3D = null
var _beacon_light: OmniLight3D = null
var _time := 0.0
## 今の動き："" ・"deploy"・"lower"・"return"。_move_t はその動きの経過、_move_from はその動きの初めの値。
var _move := ""
var _move_t := 0.0
var _move_from := 0.0
var _reach_wanted := DECK_REACH
## 1 フレーム前のデッキの上面の高さと、上下の速さ・加速度（乗っている人の体の沈みに使う）
var _last_top := INF
var _vy := 0.0
var _ay := 0.0


func setup(gap_center_z: float, side_sign := 1.0) -> void:
	name = "FloorEdgeLift"
	side = 1.0 if side_sign >= 0.0 else -1.0
	gap_z = gap_center_z
	_frame = _part("SG_LiftFrame")
	_carriage = _part("SG_LiftCarriage")
	_deck = _part("SG_LiftDeck")
	for i in range(2):
		var rail := _part("SG_LiftHandrail")
		if rail != null:
			_rails.append(rail)
	_beacon = _part("SG_Beacon")
	if _beacon != null:
		_beacon_material = StandardMaterial3D.new()
		_beacon_material.albedo_color = Color(1.0, 0.55, 0.12)
		_beacon_material.emission_enabled = true
		_beacon_material.emission = Color(1.0, 0.5, 0.1)
		_beacon_material.emission_energy_multiplier = 0.25
		_beacon.material_override = _beacon_material
		_beacon_light = OmniLight3D.new()
		_beacon_light.name = "BeaconGlow"
		_beacon_light.light_color = Color(1.0, 0.55, 0.15)
		_beacon_light.omni_range = 3.5
		_beacon_light.light_energy = 0.0
		_beacon_light.shadow_enabled = false
		add_child(_beacon_light)
	for part: MeshInstance3D in [_frame, _beacon]:
		if part != null:
			part.global_transform = Transform3D(_side_basis(), Vector3(wall_x * side, floor_y, gap_z))
	if _beacon_light != null:
		_beacon_light.global_position = Vector3((wall_x + 0.3) * side, floor_y - 0.3, gap_z)
	_snap(0.0, 0.0, 0.0)


## 古い約束：デッキの外の端をスロープの端（ワールドの x）に合わせる長さ。デッキの長さは決まっている（4.36 m）ので、
## 届かないときは知らせるだけ。
func set_reach(edge_x: float) -> void:
	_reach_wanted = absf(edge_x) - wall_x + 0.25
	if absf(_reach_wanted - DECK_REACH) > 0.3:
		push_warning("[FloorEdgeLift] the ramp edge is %.2f m from the wall (the deck reaches %.2f m)" % [_reach_wanted - 0.25, DECK_REACH])


## 下ろしたときのデッキの上面の高さ（ワールドの y）。
func set_target_y(y: float) -> void:
	target_y = y
	_place()


# ------------------------------------------------------------------ 動き（advance で進む）

## 起きて水平になり、手すりを起こす。
func deploy() -> void:
	if _move == "deploy" or (swing >= 1.0 and rails >= 1.0):
		return
	_move = "deploy"
	_move_t = SWING_TIME * swing if rails <= 0.0 else SWING_TIME + RAILS_TIME * rails


## 貨物室の床の高さまで下りる（起きていなければ先に起きる）。
func start_lower() -> void:
	if swing < 1.0 or rails < 1.0:
		deploy()
		_move = "deploy_lower"
		return
	_move = "lower"
	_move_t = 0.0
	_move_from = lower


## 上がって、手すりを寝かせ、下へぶら下がる。
func start_return() -> void:
	if _move == "return":
		return
	_move = "return"
	_move_t = 0.0
	_move_from = lower


func is_deployed() -> bool:
	return swing >= 1.0 and rails >= 1.0 and lower <= 0.0


func is_lowered() -> bool:
	return lower >= 1.0


func is_stowed() -> bool:
	return swing <= 0.0 and _move == ""


func busy() -> bool:
	return _move != ""


## 進める（回転灯も）。動いている間と出ている間は回転灯が回る。
func advance(delta: float) -> void:
	_time += delta
	match _move:
		"deploy", "deploy_lower":
			_move_t += delta
			swing = _ease_hydraulic(_move_t / SWING_TIME)
			rails = _ease(clampf((_move_t - SWING_TIME) / RAILS_TIME, 0.0, 1.0))
			if _move_t >= SWING_TIME + RAILS_TIME:
				swing = 1.0
				rails = 1.0
				if _move == "deploy_lower":
					_move = "lower"
					_move_t = 0.0
					_move_from = lower
				else:
					_move = ""
		"lower":
			_move_t += delta
			var u := clampf(_move_t / LOWER_TIME, 0.0, 1.0)
			lower = lerpf(_move_from, 1.0, _ease_elevator(u))
			if u >= 1.0:
				lower = 1.0
				_move = ""
		"return":
			_move_t += delta
			var t := _move_t
			var rise := maxf(RAISE_TIME * _move_from, 0.01)
			if t < rise:
				lower = lerpf(_move_from, 0.0, _ease_elevator(t / rise))
			else:
				lower = 0.0
				rails = 1.0 - _ease(clampf((t - rise) / FOLD_TIME, 0.0, 1.0))
				swing = 1.0 - _ease_hydraulic((t - rise - FOLD_TIME) / STOW_TIME)
				if t >= rise + FOLD_TIME + STOW_TIME:
					swing = 0.0
					rails = 0.0
					_move = ""
	extend = clampf(swing * 0.8 + rails * 0.2, 0.0, 1.0)
	_place()
	# 上面の上下の速さと加速度
	var top := top_point().y
	if is_finite(_last_top) and delta > 0.0:
		var vy := (top - _last_top) / delta
		_ay = lerpf(_ay, (vy - _vy) / delta, 1.0 - exp(-18.0 * delta))
		_vy = vy
	_last_top = top
	_update_beacon()


# ------------------------------------------------------------------ すぐその姿にする（古い約束・テスト）

## 0＝ぶら下がっている、1＝水平で手すりが起きた（0〜0.8 で起き、0.8〜1 で手すり）。
func set_extend(t: float) -> void:
	_move = ""
	var e := clampf(t, 0.0, 1.0)
	_snap(clampf(e / 0.8, 0.0, 1.0), clampf((e - 0.8) / 0.2, 0.0, 1.0), lower)


## 0＝床の高さ、1＝貨物室の床の高さ。
func set_lower(t: float) -> void:
	_move = ""
	_snap(swing, rails, clampf(t, 0.0, 1.0))


func set_t(t: float) -> void:
	set_extend(clampf(t / 0.25, 0.0, 1.0))
	set_lower(clampf((t - 0.25) / 0.75, 0.0, 1.0))


# ------------------------------------------------------------------ 読む

## デッキの上面の点（u＝0 が壁の側、1 が外の端）。ぶら下がっているときは壁に沿った面の上の点。
func deck_point(u: float) -> Vector3:
	return _deck_xf() * Vector3(DECK_LEN * clampf(u, 0.0, 1.0), DECK_T, 0.0)


## デッキの真ん中の上面（乗った人の足の高さ）。
func top_point() -> Vector3:
	return deck_point(0.5)


## デッキの上の点（u：壁から外への割合、z：中心線からの横のずれ）のワールド。
func deck_spot(u: float, z_offset: float) -> Vector3:
	return _deck_xf() * Vector3(DECK_LEN * clampf(u, 0.0, 1.0), DECK_T, z_offset * side)


## デッキの上面の上下の速さ（m/秒、上が正）と加速度（乗っている人の体の沈み）。
func vertical_speed() -> float:
	return _vy


func vertical_accel() -> float:
	return _ay


## デッキの付け根の軸の高さ（ワールドの y）。
func hinge_y() -> float:
	return lerpf(floor_y, target_y, lower) - DECK_T


func restore() -> void:
	queue_free()


# ------------------------------------------------------------------ 中身

func _snap(s: float, r: float, l: float) -> void:
	swing = s
	rails = r
	lower = l
	extend = clampf(swing * 0.8 + rails * 0.2, 0.0, 1.0)
	_place()
	_last_top = INF
	_vy = 0.0
	_ay = 0.0
	_update_beacon()


## デッキの置き場所：付け根の軸（壁から HINGE_X、上面が lower で決まる高さの DECK_T 下）を中心に、ぶら下がる（−90°）〜水平（0°）。
func _deck_xf() -> Transform3D:
	var hinge := Vector3((wall_x + HINGE_X) * side, lerpf(floor_y, target_y, lower) - DECK_T, gap_z)
	var angle := -PI * 0.5 * (1.0 - swing)
	return Transform3D(_side_basis() * Basis(Vector3.BACK, angle), hinge)


func _place() -> void:
	if _deck == null:
		return
	var deck := _deck_xf()
	_deck.global_transform = deck
	if _carriage != null:
		_carriage.global_transform = Transform3D(_side_basis(), deck.origin)
	# 手すり：デッキの上面の左右の端。起きると上へ、寝ると内側へ倒れる。
	for i in range(_rails.size()):
		var s := 1.0 if i == 0 else -1.0
		var fold := (1.0 - rails) * PI * 0.5 * -s
		_rails[i].global_transform = deck * Transform3D(Basis(Vector3.RIGHT, fold), Vector3(0.0, DECK_T, RAIL_Z * s))


func _update_beacon() -> void:
	if _beacon_material == null:
		return
	var active := _move != "" or swing > 0.0
	var on := active and fposmod(_time, 0.8) < 0.4
	# 回る反射板の光らしく、明るさを丸く変える
	var spin := 0.5 + 0.5 * cos(TAU * _time / 0.8)
	_beacon_material.emission_energy_multiplier = (1.0 + 4.0 * spin) if active else 0.25
	if _beacon_light != null:
		_beacon_light.light_energy = (0.35 + 1.1 * spin) if on or active else 0.0


func _side_basis() -> Basis:
	return Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)


func _part(mesh_name: String) -> MeshInstance3D:
	var mesh := StandGate.glb_mesh(mesh_name)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	add_child(mi)
	return mi


static func _ease(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## 油圧の動き：ゆっくり動き出し、一定の速さ、最後にそっと止まる。
static func _ease_hydraulic(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return FloatplaneFlight._ss5(u) * 0.7 + u * 0.3 if u < 1.0 else 1.0


## エレベーター：加速 → 一定 → 減速（加速度もなめらか）。
static func _ease_elevator(t: float) -> float:
	return FloatplaneFlight._ss5(t)

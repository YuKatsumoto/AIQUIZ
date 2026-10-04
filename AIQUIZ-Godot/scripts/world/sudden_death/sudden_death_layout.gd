class_name SuddenDeathLayout
extends RefCounted

## 2Pサドンデスの舞台の寸法（docs/sudden_death_underground.md 第5・6章）。
## 縦穴（ShaftDescent）・地下神殿（CisternStage）・演出（SuddenDeathDirector）が共有する。
## 高さはすべてワールド座標。地下神殿の床は本編の床と同じ高さ（FLOOR_Y）。

const FLOOR_Y := StageConstants.FLOOR_TOP_Y

# ------------------------------------------------------------------ shaft
## 縦穴の内径14m。
const SHAFT_RADIUS := 7.0
## 縦穴の模様（ランプ1段）の高さ。ランプは壁の0°・90°・180°・270°、段ごとに同じ高さ。
const SHAFT_TILE_HEIGHT := 5.0
const SHAFT_TILE_COUNT := 12
## 昇降台の天面より上に残すタイル数（残りは下）。上20m・下40m。
const SHAFT_TILES_ABOVE := 4
## 昇降デッキ（円形、天面が local y = 0）。両者の台座（スコアタワーの根元）を載せる。
const DECK_RADIUS := 5.2
## 台座の位置。P1は+X、P2は−X（本編・決着演出と同じ）。
const PAD_X := 2.2
## スコアタワーが沈みきったときの台座の天面（ResultFinaleStage: PAD_CLEARANCE + collar）。
const PAD_TOP := 0.07
## 審判の立ち位置（台座の間、選手の前方1m。選手は+Zを向く）。
const REFEREE_OFFSET := Vector3(0.0, 0.0, 1.0)
## 巡航中、縦穴をこの高さ（地下神殿の床から）に置く。神殿は霧の向こうで見えない。
const CRUISE_DECK_HEIGHT := 300.0

# ------------------------------------------------------------------ cistern (the real surge tank)
## 首都圏外郭放水路の調圧水槽を国土交通省の平面図・断面図どおりに再現した地下ステージ（docs/surge_tank_reproduction.md）。
## 図面の寸法（m）：内空は幅71m（外形78m）、ポンプ側のゲート面（u = 0）から立坑側の端の壁まで171.4m、その先に第1立坑。
## 59本の柱（幅2m・奥行7m、両端が半円）は線の間隔14m の11本の線に、列の間隔7m の 9列（0, ±7, ±14, ±21, ±28）の
## うち偶数の線は ±7・±21・±28、奇数の線は 0・±14・±28 に立つ（線10 は ±7・±21）。床は中央の掘り下げ（FLOOR_Y、
## 幅54m→40m→30m）と、60°の斜面を上がった両側の棚（+5m）。天井（スラブ下面）は掘り下げの床から17.7m。
## 舞台はこの図面を TANK_SCALE 倍して置く（着地点 (0, FLOOR_Y, 0) が中心）。キャラクターは身長約2.1m・頭0.44m・肩幅0.76m で
## 実際の人（約1.7m・0.23m・0.45m）より大きく、実寸のままでは舞台が小さく見えた。身長の比（1.25）と頭・肩幅の比（1.7〜1.9）の
## 間の 1.5 倍で、写真の見学者のように柱が大きく見える（1.0・1.25・1.5 倍のゲーム画面を見比べて決めた）。
## 2026-10-04 に 2.0 倍へ: 設定画面の講義室（ゴドーくん 1.62m）では 1.5 倍でも柱の間が狭く、教室と実習場が窮屈だった。
## ここから下の定数と関数はすべて拡大後のワールド座標（m）。
const TANK_SCALE := 2.0
## 図面の上の着地点：線8（ゲート面から132.8m）の柱のない列 v = 0。
const PLAN_ORIGIN_U := 132.8
const SLAB_SOFFIT := 17.7 * TANK_SCALE
## いまの降下演出が通り抜ける「天井」の高さ（SuddenDeathDescent が着地の降下に使う）。実物に天井開口はない
## （降下は天井を抜けて着地する。サドンデスを作り直すときに見直す）。
const HALL_HEIGHT := SLAB_SOFFIT
const CEILING_THICKNESS := 1.0
const OPENING_RADIUS := 7.0
## 着地点は線8 の柱のない列（掘り下げの床、見学エリアのポンプ側の端の近く）。
const LANDING := Vector3(0.0, FLOOR_Y, 0.0)
## 側壁の内面（図面 ±35.5m）。立坑側の 15.2m は台形にすぼまる（端の壁で ±20m）。
const HALL_HALF_WIDTH := 35.5 * TANK_SCALE
## 立坑側の端の壁（2つの開口の先が第1立坑）。
const HALL_START_Z := (PLAN_ORIGIN_U - 171.4) * TANK_SCALE
## ポンプ側のゲート面（4つの吸込口）。
const HALL_END_Z := PLAN_ORIGIN_U * TANK_SCALE
const ROW_PITCH := 7.0 * TANK_SCALE
const LINE_PITCH := 14.0 * TANK_SCALE
const LINE_COUNT := 11
const ROW_COUNT := 9
const FIRST_ROW_X := -28.0 * TANK_SCALE
## 立坑側の端に一番近い線（線10）の z。pillar_row_zs() はここから z の増える順。
const FIRST_LINE_Z := (PLAN_ORIGIN_U - 160.8) * TANK_SCALE
## 線 k はゲート面から LINE_U0 + 14k（図面の m）。
const LINE_U0 := 20.8
## Kept for older callers: the x of the rows (a row carries pillars on every other line; ±28 on every line).
const PILLAR_COLUMNS: Array[float] = [-28.0 * TANK_SCALE, -21.0 * TANK_SCALE, -14.0 * TANK_SCALE, -7.0 * TANK_SCALE, 0.0,
	7.0 * TANK_SCALE, 14.0 * TANK_SCALE, 21.0 * TANK_SCALE, 28.0 * TANK_SCALE]
const PILLAR_SIZE := Vector3(2.0, 17.7, 7.0) * TANK_SCALE
const PILLAR_PITCH := 14.0 * TANK_SCALE
## 掘り下げの縁（斜面の上端）の半幅（図面：ポンプ側 27m → 20m → 端の壁で 15m）。
const SHELF_HEIGHT := 5.0 * TANK_SCALE
const SLOPE_RUN := 2.9 * TANK_SCALE
const CREST_PUMP := 27.0 * TANK_SCALE
const CREST_MAIN := 20.0 * TANK_SCALE
const CREST_END := 15.0 * TANK_SCALE
## 縁が絞られ始める・絞り終わる・端の壁へ絞られ始める z（図面の u = 41.7, 69.4, 153.8）。
const TRENCH_Z: Array[float] = [(PLAN_ORIGIN_U - 41.7) * TANK_SCALE, (PLAN_ORIGIN_U - 69.4) * TANK_SCALE, (PLAN_ORIGIN_U - 153.8) * TANK_SCALE]
## 側壁がすぼまり始める z（図面の u = 156.2）と端の壁での半幅。
const CHAMFER_Z := (PLAN_ORIGIN_U - 156.2) * TANK_SCALE
const END_HALF_WIDTH := 20.0 * TANK_SCALE
## 流入トンネル（上流端、直径10m）と操作室のバルコニー（高さ8m）。
const TUNNEL_RADIUS := 5.0
const TUNNEL_CENTER_Y := FLOOR_Y + 5.0
const BALCONY_HEIGHT := 8.0

# ------------------------------------------------------------------ lift towers (早押し水没リフト)
## Both players' score towers stand on the floor downstream of the landing point and lift them over the
## water (docs 6.3). P1 at +X, P2 at −X; the duel camera looks back upstream, so P1 is on the left.
const LIFT_X := 4.0
const LIFT_Z := 9.0
## The flow sees each tower as a disc this wide (the 1.7 m platform over a 1.31 m tier column).
const LIFT_RADIUS := 0.85


static func ceiling_bottom_y() -> float:
	return FLOOR_Y + HALL_HEIGHT


static func ceiling_top_y() -> float:
	return FLOOR_Y + HALL_HEIGHT + CEILING_THICKNESS


## 着地点の上に縦穴を置いたときの、デッキ天面のワールド高さ → 選手の表示の持ち上げ量。
static func lift_for_deck_top(deck_top_world_y: float) -> float:
	return deck_top_world_y + PAD_TOP - FLOOR_Y


## The lift tower of [param player_index] on the hall floor (world).
static func lift_position(player_index: int) -> Vector3:
	return Vector3(LIFT_X if player_index == 1 else -LIFT_X, FLOOR_Y, LIFT_Z)


## 柱の線 k（0 = ポンプ側の最初の線 … 10 = 立坑側の最後の線）の z。
static func line_z(k: int) -> float:
	return (PLAN_ORIGIN_U - (LINE_U0 + 14.0 * float(k))) * TANK_SCALE


## 柱の線の z（11本）を立坑側から z の増える順に（照明の行 r は線 10 − r）。
static func pillar_row_zs() -> Array[float]:
	var zs: Array[float] = []
	for r in range(LINE_COUNT):
		zs.append(line_z(LINE_COUNT - 1 - r))
	return zs


## 線 k の柱の x。
static func pillar_xs(k: int) -> Array[float]:
	var rows: Array[float] = [-28.0, -21.0, -7.0, 7.0, 21.0, 28.0]
	if k % 2 == 1:
		rows = [-28.0, -14.0, 0.0, 14.0, 28.0]
	elif k == LINE_COUNT - 1:
		rows = [-21.0, -7.0, 7.0, 21.0]
	var xs: Array[float] = []
	for v: float in rows:
		xs.append(v * TANK_SCALE)
	return xs


## 59本の柱の中心（x, z）。
static func pillars() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k in range(LINE_COUNT):
		for x: float in pillar_xs(k):
			out.append(Vector2(x, line_z(k)))
	return out


## 掘り下げの縁（斜面の上端）の半幅。
static func trench_crest(z: float) -> float:
	if z >= TRENCH_Z[0]:
		return CREST_PUMP
	if z >= TRENCH_Z[1]:
		return lerpf(CREST_PUMP, CREST_MAIN, (TRENCH_Z[0] - z) / (TRENCH_Z[0] - TRENCH_Z[1]))
	if z >= TRENCH_Z[2]:
		return CREST_MAIN
	return lerpf(CREST_MAIN, CREST_END, clampf((TRENCH_Z[2] - z) / (TRENCH_Z[2] - HALL_START_Z), 0.0, 1.0))


## 側壁の内面の半幅（立坑側の 15.2m（図面）で ±35.5 → ±20 にすぼまる）。
static func wall_half_width(z: float) -> float:
	return lerpf(HALL_HALF_WIDTH, END_HALF_WIDTH, clampf((CHAMFER_Z - z) / (CHAMFER_Z - HALL_START_Z), 0.0, 1.0))


## 床の高さ（FLOOR_Y から）：掘り下げの床 0、60°の斜面、棚 SHELF_HEIGHT。
static func floor_height(x: float, z: float) -> float:
	var toe := trench_crest(z) - SLOPE_RUN
	return clampf((absf(x) - toe) / SLOPE_RUN, 0.0, 1.0) * SHELF_HEIGHT

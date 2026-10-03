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

# ------------------------------------------------------------------ cistern
const HALL_HEIGHT := 18.0
const CEILING_THICKNESS := 1.0
## 天井開口（縦穴の出口）。着地点の真上。
const OPENING_RADIUS := 7.0
const LANDING := Vector3(0.0, FLOOR_Y, 0.0)
const HALL_HALF_WIDTH := 45.0
const HALL_START_Z := -30.0
const HALL_END_Z := 210.0
const PILLAR_COLUMNS: Array[float] = [-38.7, -25.8, -12.9, 12.9, 25.8, 38.7]
const PILLAR_SIZE := Vector3(2.0, 18.0, 7.0)
const PILLAR_PITCH := 15.0
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


## 柱の行（z）。最初の行は上流端から15m、柱の中心は行の z + 奥行の半分。
static func pillar_row_zs() -> Array[float]:
	var zs: Array[float] = []
	var z := HALL_START_Z + 15.0
	while z + PILLAR_SIZE.z < HALL_END_Z - 3.0:
		zs.append(z + PILLAR_SIZE.z * 0.5)
		z += PILLAR_PITCH
	return zs

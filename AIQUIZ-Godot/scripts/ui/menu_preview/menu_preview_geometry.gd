class_name MenuPreviewGeometry
extends RefCounted

## メニュー背景のコンベアと壁の寸法。MenuWallBackgroundPreview と AI の部品の両方が使う
## （部品から持ち主のクラスの定数を読むと、互いに preload し合う形になるため、ここに分ける）。

const PLAYER_X: float = -3.5
const PLAYER2_X: float = 3.5
const DOOR_HALF_DEPTH_Z: float = 0.30
## 本編 game_state の wall_z - 0.4 を扉手前(+Z)基準に換算（0.4 + 扉半奥行0.3）
const WALL_CONTACT_Z: float = 0.70
const RED_DOOR_INDEX: int = 1
## メニューの壁は180°回して置くので、扉0(青)はワールド x=-3.5、扉1(赤)は x=+3.5。
const DOOR_X_LEFT: float = -3.5
const DOOR_X_RIGHT: float = 3.5
const DOOR_HALF_WIDTH: float = 1.8
const DOOR_PASS_MARGIN: float = 0.4
## キャラと壁が重ならないよう確保する Z 方向の最小クリアランス
const WALL_PLAYER_CLEAR_Z: float = 5.5
const WALL_PUSH_BACK_Z: float = 6.5
const FLOOR_Y: float = 0.0
## ランナーが前後に動ける範囲（-z が壁の来る側、+z がカメラ側）
const BELT_Z_MIN: float = -4.8
const BELT_Z_MAX: float = 4.2
## これより +z はコンベアの外（海）
const BELT_EDGE_FALL_Z: float = 4.55
## 海落下待機中だけ通常上限(4.2)を超えて端まで進める
const OCEAN_DEPTH_MAX: float = BELT_EDGE_FALL_Z + 0.85


static func wall_front_touches_player(door_leading_z: float, player_local_z: float) -> bool:
	return door_leading_z >= player_local_z - WALL_CONTACT_Z


## その x がくぐれる扉（0=青・左、1=赤・右）。扉の外なら -1。
static func door_index_at(player_x: float) -> int:
	var half_w := DOOR_HALF_WIDTH + DOOR_PASS_MARGIN
	if player_x >= DOOR_X_RIGHT - half_w and player_x <= DOOR_X_RIGHT + half_w:
		return RED_DOOR_INDEX
	if player_x >= DOOR_X_LEFT - half_w and player_x <= DOOR_X_LEFT + half_w:
		return 0
	return -1


static func door_x(door_index: int) -> float:
	return DOOR_X_RIGHT if door_index == RED_DOOR_INDEX else DOOR_X_LEFT

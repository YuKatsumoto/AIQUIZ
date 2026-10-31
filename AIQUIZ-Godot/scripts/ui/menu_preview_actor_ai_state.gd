class_name MenuPreviewActorAIState
extends RefCounted

## メニュー背景ランナー 1 人ぶんの AI の状態。

const STATE_NORMAL: int = 0
## ゴーストの体当たりで吹き飛んでいる
const STATE_KNOCKBACK: int = 2
## コンベアの後端から海へ落ちている
const STATE_OCEAN_FALL: int = 3
const STATE_DEAD: int = 4
const STATE_RESPAWN: int = 5
const STATE_ACROBATICS: int = 6
const STATE_TAUNT: int = 7

const PENDING_ACCIDENT_NONE: int = 0
const PENDING_ACCIDENT_WALL: int = 1
const PENDING_ACCIDENT_OCEAN: int = 2
const PENDING_ACCIDENT_SAW: int = 3

## 相手がゴーストになったとき：見ているだけ（煽り〜光の柱）／狙われて警戒している（サメの登場から）
const GHOST_MODE_NONE: int = 0
const GHOST_MODE_WATCH: int = 1
const GHOST_MODE_ALERT: int = 2

var ai_state: int = STATE_NORMAL
var next_action_t: float = 0.0
var emote_end_t: float = 0.0
var dead_end_t: float = 0.0
var state_end_t: float = 0.0
var target_x: float = -3.5
## 横移動の巡航速度
var lane_shift_speed: float = 2.2
var lane_shift_active: bool = false
var target_local_z: float = 0.0
## 前後移動の巡航速度
var depth_shift_speed: float = 2.0
var depth_shift_active: bool = false
## いまの移動速度（ローカル座標）。ゴーストが生き残った方の動きを読むのと、吹き飛び・落下の勢いに使う
var vel_x: float = 0.0
var vel_z: float = 0.0
var jump_trigger_ttl: float = 0.0
var is_emoting: bool = false
var blocking_wall: Node3D = null
var last_emote: int = 0
## メニューの壁通過ごとのダンス間引き用カウンター。
var door_passes_since_emote: int = 0
var next_acro_jump_t: float = 0.0
var acro_seed: float = 0.0
var knockback_vel_x: float = 0.0
var knockback_vel_z: float = 0.0
## 吹き飛びのあいだ自分では動けない時刻
var knockback_lock_until: float = 0.0
var door_learner: MenuPreviewDoorLearner
var learn_approach_wall: Node3D = null
var learn_intended_action: int = -1
var learn_target_x: float = -3.5
var learn_episode_reported: bool = false
var available_emotes: Array[int] = []
var taunt_target_x: float = 0.0
var taunt_target_z: float = 0.0
## 潜伏型事故: 0=なし, 1=壁, 2=海, 3=刃／ヒヤリ（AI_STATE は NORMAL のまま）
var pending_accident: int = PENDING_ACCIDENT_NONE
var pending_accident_wall: Node3D = null
## ゴーストの突進をよけている（この時刻まで）
var dodge_until: float = -1.0
var ghost_mode: int = GHOST_MODE_NONE
## ゴーストになって相手を襲っているあいだは復活しない
var respawn_hold: bool = false


func is_dodging(now: float) -> bool:
	return dodge_until >= 0.0 and now < dodge_until

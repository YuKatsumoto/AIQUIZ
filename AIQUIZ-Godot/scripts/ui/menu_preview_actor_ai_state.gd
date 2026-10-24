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
## いまの移動速度（ローカル座標）。加速・減速と、歩様のアニメーションに使う
var vel_x: float = 0.0
var vel_z: float = 0.0
## AI が最後に書いた位置。外から書き換えられたら速度を捨てる
var last_written_x: float = INF
var last_written_z: float = INF
var jump_trigger_ttl: float = 0.0
## ジャンプの溜め：この時刻に jump_prep_speed で踏み切る（< 0 なら溜めていない）
var jump_prep_until: float = -1.0
var jump_prep_speed: float = 0.0
## 最後に着地した時刻（着地直後は少しずつ走り出す）
var landed_at_t: float = -INF
var is_emoting: bool = false
var blocking_wall: Node3D = null
var accident_cooldown_t: float = 0.0
var last_emote: int = 0
## メニューの壁通過ごとのダンス間引き用カウンター。
var door_passes_since_emote: int = 0
var next_acro_jump_t: float = 0.0
var next_acro_retarget_t: float = 0.0
var knockback_vel_x: float = 0.0
var knockback_vel_z: float = 0.0
## 吹き飛びのあいだ自分では動けない時刻
var knockback_lock_until: float = 0.0
## 吹き飛ばされた向き（体を打たれた側へ向ける）
var knockback_from: Vector2 = Vector2.ZERO
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
## ゴーストの突進をよけている（この時刻まで）。dodge_roll なら前転でよける
var dodge_until: float = -1.0
var dodge_roll: bool = false
var ghost_mode: int = GHOST_MODE_NONE
## ゴーストのサメを見る位置（WATCH のとき体をそちらへ向ける）
var ghost_watch_target: Vector3 = Vector3.ZERO
## ゴーストになって相手を襲っているあいだは復活しない
var respawn_hold: bool = false


func is_dodging(now: float) -> bool:
	return dodge_until >= 0.0 and now < dodge_until

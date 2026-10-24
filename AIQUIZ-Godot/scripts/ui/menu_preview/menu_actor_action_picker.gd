class_name MenuActorActionPicker
extends RefCounted

## メニュー背景ランナーの「次の行動」を重み付きで1つ選ぶ。シーンや時間に触らない純粋な抽選。
## 抽選は有効な行動の重みの合計の中で行うので、どの行動も（事故も）重みに比例して必ず選ばれうる。

enum Action { HOLD, LANE_SHIFT, DASH, STEP_FORWARD, STEP_BACK, JUMP, ACROBATICS, ACCIDENT }

const W_HOLD: float = 0.20
const W_LANE_SHIFT: float = 0.22
const W_DASH: float = 0.26
const W_STEP_FORWARD: float = 0.10
const W_STEP_BACK: float = 0.10
const W_JUMP: float = 0.05
const W_ACROBATICS: float = 0.07
## 事故（壁に激突・海へ転落）。上手になるほど減り、2P では少し増やす（2人いると扉を取り合って自然なミスが減るため）。
const W_ACCIDENT: float = 0.035
const ACCIDENT_SKILL_DAMPING: float = 0.65
const ACCIDENT_2P_MULT: float = 1.85
## ゴーストに狙われているあいだは跳ねて避けようとする
const ALERT_JUMP_MULT: float = 1.6
## コンベアが止まっているあいだ（誰かが壁に激突した直後）は落ち着いて立ち止まりがちにする
const PAUSED_MOVE_MULT: float = 0.5
const PAUSED_HOLD_MULT: float = 2.0


class Context:
	extends RefCounted
	## 扉をくぐった成功率（0〜1）
	var skill: float = 0.0
	var is_2p: bool = false
	var grounded: bool = true
	## 事故を起こしてよいか（クールダウン明け・扉へ向かう途中でない・ほかの事故が進行中でない など）
	var accident_allowed: bool = false
	var acro_allowed: bool = true
	## ゴーストに狙われている（エモート・アクロ・事故はしない）
	var ghost_alert: bool = false
	var conveyor_paused: bool = false


static func accident_weight(skill: float, is_2p: bool) -> float:
	var weight := W_ACCIDENT * (1.0 - ACCIDENT_SKILL_DAMPING * clampf(skill, 0.0, 1.0))
	if is_2p:
		weight *= ACCIDENT_2P_MULT
	return weight


## Action の並びと同じ順の重み。0 の行動は選ばれない。
static func weights(ctx: Context) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(Action.size())
	w[Action.HOLD] = W_HOLD
	w[Action.LANE_SHIFT] = W_LANE_SHIFT
	w[Action.DASH] = W_DASH
	w[Action.STEP_FORWARD] = W_STEP_FORWARD
	w[Action.STEP_BACK] = W_STEP_BACK
	w[Action.JUMP] = W_JUMP if ctx.grounded else 0.0
	w[Action.ACROBATICS] = W_ACROBATICS if ctx.grounded and ctx.acro_allowed else 0.0
	w[Action.ACCIDENT] = accident_weight(ctx.skill, ctx.is_2p) if ctx.accident_allowed else 0.0
	if ctx.conveyor_paused:
		w[Action.HOLD] *= PAUSED_HOLD_MULT
		for action: int in [Action.DASH, Action.STEP_FORWARD, Action.STEP_BACK]:
			w[action] *= PAUSED_MOVE_MULT
	if ctx.ghost_alert:
		w[Action.ACROBATICS] = 0.0
		w[Action.ACCIDENT] = 0.0
		w[Action.JUMP] *= ALERT_JUMP_MULT
	return w


static func pick(ctx: Context, rng: RandomNumberGenerator) -> int:
	var w := weights(ctx)
	var total := 0.0
	for value: float in w:
		total += maxf(0.0, value)
	if total <= 0.0:
		return Action.HOLD
	var roll := rng.randf() * total
	var accum := 0.0
	for action: int in range(w.size()):
		accum += maxf(0.0, w[action])
		if roll < accum:
			return action
	# randf() の丸めで合計ちょうどになったときは最後の有効な行動
	for action: int in range(w.size() - 1, -1, -1):
		if w[action] > 0.0:
			return action
	return Action.HOLD

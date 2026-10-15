extends RefCounted
class_name SkinEditHistory

## スキン編集の「もどす／すすむ」。プレイヤーごとに {skin, hat} のスナップショットを持つ。
## 同じ操作（スライダーのドラッグ、キー連打、ホイール）が続く間は1件にまとめる。

const LIMIT := 50
const COALESCE_MSEC := 500

var _undo: Dictionary = {1: [], 2: []}
var _redo: Dictionary = {1: [], 2: []}
var _last_key: Dictionary = {1: "", 2: ""}
var _last_msec: Dictionary = {1: 0, 2: 0}


static func snapshot(skin: Dictionary, hat: int) -> Dictionary:
	return {"skin": skin.duplicate(true), "hat": hat}


## before は変更前の状態。coalesce_key が直前と同じで時間内なら積まない（最初の状態を残す）。
func record(player: int, before: Dictionary, coalesce_key: String = "") -> void:
	var now := Time.get_ticks_msec()
	var same_gesture: bool = (
		not coalesce_key.is_empty()
		and coalesce_key == _last_key[player]
		and now - int(_last_msec[player]) <= COALESCE_MSEC
	)
	_last_key[player] = coalesce_key
	_last_msec[player] = now
	if same_gesture:
		return
	var stack: Array = _undo[player]
	stack.append(before)
	while stack.size() > LIMIT:
		stack.pop_front()
	(_redo[player] as Array).clear()


## 続けて同じ操作が来ても新しい1件として積むようにする（ドラッグ終了時など）。
func break_coalescing(player: int) -> void:
	_last_key[player] = ""


func can_undo(player: int) -> bool:
	return not (_undo[player] as Array).is_empty()


func can_redo(player: int) -> bool:
	return not (_redo[player] as Array).is_empty()


func undo(player: int, current: Dictionary) -> Dictionary:
	if not can_undo(player):
		return {}
	(_redo[player] as Array).append(current)
	break_coalescing(player)
	return (_undo[player] as Array).pop_back()


func redo(player: int, current: Dictionary) -> Dictionary:
	if not can_redo(player):
		return {}
	(_undo[player] as Array).append(current)
	break_coalescing(player)
	return (_redo[player] as Array).pop_back()


func clear() -> void:
	for player: int in [1, 2]:
		(_undo[player] as Array).clear()
		(_redo[player] as Array).clear()
		_last_key[player] = ""

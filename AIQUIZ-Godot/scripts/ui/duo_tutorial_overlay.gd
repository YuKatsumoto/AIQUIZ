extends TutorialCoachBar
class_name DuoTutorialOverlay

## ローカル2Pチュートリアル専用のコーチバー。
## バーの枠組みは res://scripts/ui/tutorial_coach_bar.gd が持ち、
## ここではP1（オレンジ）とP2（シアン）のキーチップを横一列に組み立てる。
## 1Pコースは res://scripts/ui/solo_tutorial_overlay.gd が担当する。

const P1_COLOR := Color(1.0, 0.48, 0.12, 1.0)
const P2_COLOR := Color(0.18, 0.88, 1.0, 1.0)

## 2人分のチップが並ぶので1Pより広く取る。
const DUO_BAR_WIDTH := 1180.0
## 問題出題時以外はキャラクターを隠さないよう上端を基本位置にする。
const DUO_BAR_MARGIN_TOP := 18.0
## P1/P2の操作を横一列にまとめ、画面を隠す高さを抑える。
const DUO_BAR_HEIGHT_FULL := 90.0
const DUO_BAR_HEIGHT_COMPACT := 66.0


func _course_is_active() -> bool:
	return game_state.is_duo_tutorial()


func _bar_width() -> float:
	return DUO_BAR_WIDTH


func _bar_at_top() -> bool:
	return (
		game_state != null
		and game_state.tutorial_flow != null
		and not game_state.tutorial_flow.is_quiz_step()
	)


func _bar_margin_top() -> float:
	return DUO_BAR_MARGIN_TOP


func _bar_height_full() -> float:
	return DUO_BAR_HEIGHT_FULL


func _bar_height_compact() -> float:
	return DUO_BAR_HEIGHT_COMPACT


func _chip_rows_inline() -> bool:
	return true


func _chip_rows(model: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ghost_ready := _is_ghost_control_display_ready()
	for player_variant: Variant in model.get("players", []):
		var player: Dictionary = player_variant
		var player_index := int(player.get("player", 0))
		var tasks: Array = player.get("tasks", [])
		# ゴーストシャークの操作チップは、サメの操作フェーズに入ってから見せる。
		if not ghost_ready and player_index == int(model.get("ghost_player", 0)):
			continue
		if tasks.is_empty():
			continue
		# 脱落した側の回答チップは指示として成立しないので伏せる。
		# 代わりにゴーストシャーク側の操作HUDが下部に出る。
		if not _player_is_alive(player_index):
			continue
		rows.append({
			"label": str(player.get("label", "P%d" % player_index)),
			"color": P1_COLOR if player_index == 1 else P2_COLOR,
			"tasks": tasks,
		})
	return rows


## ゴースト操作チップの表示可否と生存状況はモデルの revision に現れないので、
## 明示的にシグネチャへ混ぜて再描画を促す。
func _extra_signature() -> String:
	return "%s|%s|%s" % [
		_is_ghost_control_display_ready(),
		_player_is_alive(1),
		_player_is_alive(2),
	]


## 脱落中でもゴースト練習ステップでは操作チップを見せたいので、
## そのステップだけは生存扱いにする。
func _player_is_alive(player_index: int) -> bool:
	if game_state == null or game_state.is_tutorial_ghost_practice():
		return true
	return game_state.p1_alive if player_index == 1 else game_state.p2_alive


func _is_ghost_control_display_ready() -> bool:
	if game_state == null or not game_state.is_tutorial_ghost_practice():
		return true
	var ghost_player := game_state.get_tutorial_ghost_player()
	if ghost_player <= 0:
		return true
	var world := _find_game_world()
	if world == null or not world.has_method("is_ghost_shark_control_active"):
		return false
	return bool(world.call("is_ghost_shark_control_active", ghost_player))


func _find_game_world() -> Node:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("is_ghost_shark_control_active"):
			return node
		node = node.get_parent()
	return null

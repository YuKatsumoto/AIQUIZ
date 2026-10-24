extends TutorialCoachBar
class_name DuoTutorialOverlay

## ローカル2Pチュートリアル専用のミッションバー。
## バーの枠組みは res://scripts/ui/tutorial_coach_bar.gd が持ち、
## ここではP1（オレンジ）とP2（水色）のキーを横一列に組み立てる。
## 片方が先に終えたら、その人の段に「OK」を付ける。
## 1Pコースは res://scripts/ui/solo_tutorial_overlay.gd が担当する。


func _course_is_active() -> bool:
	return game_state.is_duo_tutorial()


## クイズ以外ではキャラクターを隠さないよう、バーを画面の上に置く。
## クイズ中は小さなピルにして、下隅のハートのカードの間（画面の下）に収める。
func _bar_at_top() -> bool:
	return (
		game_state != null
		and game_state.tutorial_flow != null
		and not game_state.tutorial_flow.is_quiz_step()
	)


func _key_groups(model: Dictionary) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var ghost_ready := _is_ghost_control_display_ready()
	for player_variant: Variant in model.get("players", []):
		var player: Dictionary = player_variant
		var player_index := int(player.get("player", 0))
		var tasks: Array = player.get("tasks", [])
		# ゴーストシャークの操作キーは、サメの操作フェーズに入ってから見せる。
		if not ghost_ready and player_index == int(model.get("ghost_player", 0)):
			continue
		if tasks.is_empty():
			continue
		# 脱落した側の回答キーは指示として成立しないので伏せる。
		# 代わりにゴーストシャーク側の操作HUDが下部に出る。
		if not _player_is_alive(player_index):
			continue
		groups.append({
			"label": str(player.get("label", "P%d" % player_index)),
			"color": TutorialUiStyle.player_color(player_index),
			"tasks": tasks,
			"player": player_index,
			"complete": bool(player.get("complete", false)),
		})
	return groups


## ゴースト操作キーの表示可否と生存状況はモデルの revision に現れないので、
## 明示的にシグネチャへ混ぜて再描画を促す。
func _extra_signature() -> String:
	return "%s|%s|%s" % [
		_is_ghost_control_display_ready(),
		_player_is_alive(1),
		_player_is_alive(2),
	]


## 脱落中でもゴースト練習ステップでは操作キーを見せたいので、
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

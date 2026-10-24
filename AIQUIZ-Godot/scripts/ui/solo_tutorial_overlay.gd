extends TutorialCoachBar
class_name SoloTutorialOverlay

## 1Pチュートリアル専用のミッションバー。
## バーの枠組みは res://scripts/ui/tutorial_coach_bar.gd が持ち、
## ここでは1P向けのキーの段（P1のオレンジ）を1つだけ組み立てる。
## ローカル2Pコースは res://scripts/ui/duo_tutorial_overlay.gd が担当する。


func _course_is_active() -> bool:
	return game_state.is_solo_tutorial()


func _key_groups(model: Dictionary) -> Array[Dictionary]:
	var tasks: Array = model.get("tasks", [])
	if tasks.is_empty():
		return []
	return [{"label": "", "color": TutorialUiStyle.P1, "tasks": tasks, "player": 1, "complete": false}]

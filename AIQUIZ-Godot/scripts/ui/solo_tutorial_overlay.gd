extends TutorialCoachBar
class_name SoloTutorialOverlay

## 1Pチュートリアル専用のコーチバー。
## バーの枠組みは res://scripts/ui/tutorial_coach_bar.gd が持ち、
## ここでは1P向けのキーチップ1段だけを組み立てる。
## ローカル2Pコースは res://scripts/ui/duo_tutorial_overlay.gd が担当する。


func _course_is_active() -> bool:
	return game_state.is_solo_tutorial()


func _chip_rows(model: Dictionary) -> Array[Dictionary]:
	var tasks: Array = model.get("tasks", [])
	if tasks.is_empty():
		return []
	return [{"label": "", "color": ACCENT, "tasks": tasks}]

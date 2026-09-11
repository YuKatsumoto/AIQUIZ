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
	if bool(ProjectSettings.get_setting("aiquiz/mobile/enabled", false)) \
		or OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		var converted: Array = []
		for task_variant: Variant in tasks:
			var task: Dictionary = (task_variant as Dictionary).duplicate(true)
			match str(task.get("id", "")):
				"left", "right", "forward", "back", "ocean":
					task["key"] = "左スティック"
				"jump":
					task["key"] = "ジャンプ"
				"emote":
					task["key"] = "エモート"
			converted.append(task)
		tasks = converted
	return [{"label": "", "color": ACCENT, "tasks": tasks}]

extends SceneTree

## ゲームのキー配列（TutorialKeyboard.get_key_layout()）を、Blender の机のセットの組み立て用に JSON へ書き出す。
## Blender の build_tutorial_desk.py がこれを読み、同じ並びでキーを作る（キーの id は Godot と同じ）。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/tutorial_desk/export_key_layout.gd
const KeyboardScript = preload("res://scripts/ui/tutorial_keyboard.gd")
const OUTPUT := "res://assets/tutorial_desk/source/key_layout.json"


func _init() -> void:
	var keyboard: TutorialKeyboard = KeyboardScript.new()
	var keys: Array = []
	for spec: Dictionary in keyboard.get_key_layout():
		var rect: Rect2 = spec["rect"]
		keys.append({"id": spec["id"], "label": spec["label"], "x": rect.position.x, "y": rect.position.y,
			"w": rect.size.x, "h": rect.size.y})
	keyboard.free()
	# 2D の配列表の単位：キー幅 28 + すき間 3 が 1 キー分（31）、行は 29 ずつ下がる。
	var data := {"source": "scripts/ui/tutorial_keyboard.gd _build_layout()", "pitch": 31.0, "row_top": 44.0,
		"row_step": 29.0, "left": 14.0, "right": 612.0, "keys": keys}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("EXPORT_KEY_LAYOUT keys=%d -> %s" % [keys.size(), ProjectSettings.globalize_path(OUTPUT)])
	quit()

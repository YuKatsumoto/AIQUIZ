extends SceneTree

## WallAiTextReveal の 1 文字ずつのラベルが、元の Label3D と同じ位置・形になるかを絵で確かめる。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --script res://tests/ai_typing_capture/layout_check.gd
## 出力: artifacts/ai_typing_capture/layout_check/{source,glyphs}.png と clusters.json。2 枚が同じ絵なら、書き終えて元のラベルへ戻しても文字は動かない。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/ai_typing_capture/layout_check_runtime.gd") as Script
	root.add_child(script.new())

extends SceneTree

## 地上（本編）ステージの見た目と GPU 時間のベースライン。ウィンドウあり（Forward+）、1280x720 固定:
##   Godot --path . --script res://tests/ground_look_bootstrap.gd --fixed-fps 60 -- quality=high shots perf frames=300 tag=before
## 引数（"--" の後ろ）: quality=low|balanced|high|ultra  tag=<名前>  shots  perf  frames=<N>
##   compare tagA=<名前> tagB=<名前> quality=<画質>   (同じ構図の撮り直しどうしの画像差分)
## 画像と report.json は artifacts/ground_quality/<tag>/<quality>/。詳細は ground_look_runtime.gd。
## The test node is loaded after the autoloads, so it may use GameManager and the class names.

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/ground_look_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("ground_look_runtime.gd failed to load")
		quit(1)
		return
	root.add_child(script.new())

extends SceneTree

## 「つきやぶれ！スカイゲート」のデバッグの入口（監督なし）。オートロードが要るので、--script で起動してから場面を足す。
##   ./Godot_v4.7.2-stable_win64.exe --path . --script res://scripts/world/sudden_death/games/sky_gate_debug_bootstrap.gd
## 引数は sky_gate_debug.gd を参照（例：-- round=3 p2=right）。


func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var node := SkyGateDebug.new()
	node.name = "SkyGateDebug"
	root.add_child(node)

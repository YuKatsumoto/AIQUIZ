extends SceneTree

## 雲に乗ったハテナ（LassoCloudRider）と投げ縄（LassoRope）だけを空のワールドに置いて、いろいろな角度から撮る。
## 帽子の載せ方・縄を回す姿勢・投げる姿勢の確かめ用（本体は lasso_rig_preview_runtime.gd）。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 960x720 --script res://tests/lasso_rig_preview.gd -- pose=twirl
## pose=idle|twirl|throw|haul、画像は artifacts/elimination_lasso/rig/


func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/lasso_rig_preview_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())

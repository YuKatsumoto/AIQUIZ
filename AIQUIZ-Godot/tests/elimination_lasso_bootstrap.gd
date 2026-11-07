extends SceneTree

## 両者脱落の投げ縄の演出（EliminationLassoDirector）を本物の GameWorld で再生して撮る。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/elimination_lasso_bootstrap.gd -- fps=60 quality=high
## 引数：fps=30|60、quality=low|balanced|high、every=0.1（撮る間隔の秒）、death=wall|ocean、out=<フォルダ>、
## spread=same|near|far|near_swap|far_swap（2 人が倒れる扉）、pre=0.25（脱落の瞬間から撮る間隔の秒）、
## rider=1|2（先に脱落してサメに乗る人）、rider_phase=aiming|charging|cooldown（もう 1 人が脱落するときのサメ）

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/elimination_lasso_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())

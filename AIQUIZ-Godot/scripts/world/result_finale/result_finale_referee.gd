class_name ResultFinaleReferee
extends RefCounted

## The Godot plush referee with his checkered flag (referee_finale.glb).
## Animations "FinaleWin" and "FinaleDraw" are baked in Blender; the rig node
## carries the authored (0, 1 m behind the marks) offset, so place the scene
## root at the stage origin with the stage's rotation.

const SCENE := preload("res://assets/result_finale/referee_finale.glb")
const WIN_ANIMATION := "FinaleWin"
const DRAW_ANIMATION := "FinaleDraw"
const IDLE_LOOP := 1.2  # sway keys at 0 / 0.6 / 1.2 s form a seamless cycle


static func create(parent: Node3D, node_name: String) -> Dictionary:
	var root := SCENE.instantiate() as Node3D
	root.name = node_name
	parent.add_child(root)
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		for animation_name in player.get_animation_list():
			var animation := player.get_animation(animation_name)
			if animation != null:
				animation.loop_mode = Animation.LOOP_NONE
		player.play(WIN_ANIMATION)
		player.pause()
		player.seek(0.0, true)
	for mesh: Node in root.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return {"root": root, "animation": player}


static func pose(player: AnimationPlayer, draw: bool, time: float) -> void:
	if player == null:
		return
	var animation := DRAW_ANIMATION if draw else WIN_ANIMATION
	if player.current_animation != animation or player.assigned_animation != animation:
		player.play(animation)
		player.pause()
	player.seek(clampf(time, 0.0, player.current_animation_length), true)


## Waiting at the finish before the ceremony: loop the authored idle sway.
static func pose_idle(player: AnimationPlayer, clock: float) -> void:
	pose(player, false, fposmod(clock, IDLE_LOOP))

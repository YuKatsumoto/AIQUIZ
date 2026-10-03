class_name ResultFinaleReferee
extends RefCounted

## The Godot plush referee with a checkered flag in each hand (referee_finale.glb).
## Animations "FinaleWin" (winner on his right, P1's lane), "FinaleWinP2" (winner on
## his left) and "FinaleDraw" are baked in Blender and share every key before the
## verdict, so his pose never tells the result early; at the verdict the winner's
## flag goes up. The rig node carries the authored (0, 1 m behind the marks) offset,
## so place the scene root at the stage origin with the stage's rotation.

const SCENE := preload("res://assets/result_finale/referee_finale.glb")
const WIN_ANIMATION := "FinaleWin"
const WIN_P2_ANIMATION := "FinaleWinP2"
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


## The finale mirrors its stage in X when P2 wins. A skinned mesh under a mirrored
## transform is lit inside out on qualities with gameplay shadows (his front turns
## dark blue), and a mirror would also swap which hand raises the flag. So a P2 win
## cancels the mirror on the referee's root (he stands centred, so only the
## handedness changes) and plays FinaleWinP2, authored with the raise and turns on
## the P2 side. Call once per referee, right after create().
static func unmirror(root: Node3D) -> void:
	root.transform = Transform3D(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)), Vector3.ZERO) * root.transform


static func animation_for(winner: int) -> String:
	if winner == 0:
		return DRAW_ANIMATION
	return WIN_P2_ANIMATION if winner == 2 else WIN_ANIMATION


static func pose(player: AnimationPlayer, animation: String, time: float) -> void:
	if player == null:
		return
	if player.current_animation != animation or player.assigned_animation != animation:
		player.play(animation)
		player.pause()
	player.seek(clampf(time, 0.0, player.current_animation_length), true)


## Waiting at the finish before the ceremony: loop the authored idle sway.
static func pose_idle(player: AnimationPlayer, clock: float) -> void:
	pose(player, WIN_ANIMATION, fposmod(clock, IDLE_LOOP))

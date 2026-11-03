@tool
extends RefCounted
func run(ctx) -> void:
	var root: Node = ctx.instantiate_imported_scene()
	var s: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	for i: int in s.get_bone_count():
		ctx.log({"bone":s.get_bone_name(i),"rest":str(s.get_bone_rest(i))})
	var a: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var clip: Animation = a.get_animation("Spin")
	ctx.log({"length":clip.length,"tracks":clip.get_track_count()})
	for i: int in mini(clip.get_track_count(),5):
		ctx.log({"path":str(clip.track_get_path(i)),"type":clip.track_get_type(i),"first":str(clip.track_get_key_value(i,0)),"last":str(clip.track_get_key_value(i,clip.track_get_key_count(i)-1))})
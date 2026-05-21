extends SceneTree

func _init():
	var scene = preload("res://assets/animations/Y Bot@Step Hip Hop Dance.fbx").instantiate()
	var skel = scene.find_child("Skeleton3D", true, false)
	if skel:
		var txt = ""
		for i in range(skel.get_bone_count()):
			txt += skel.get_bone_name(i) + "\n"
		var f = FileAccess.open("res://bones_out.txt", FileAccess.WRITE)
		f.store_string(txt)
		f.close()
	quit()

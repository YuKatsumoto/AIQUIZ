extends SceneTree

func _init():
	var scene = preload("res://assets/animations/Y Bot.fbx").instantiate()
	var skel = scene.find_child("Skeleton3D", true, false)
	if skel:
		var txt = ""
		txt += "LeftIndexProximal index: " + str(skel.find_bone("LeftIndexProximal")) + "\n"
		txt += "mixamorig_LeftHandIndex1 index: " + str(skel.find_bone("mixamorig_LeftHandIndex1")) + "\n"
		var f = FileAccess.open("res://bones_test.txt", FileAccess.WRITE)
		f.store_string(txt)
		f.close()
	quit()

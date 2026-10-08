class_name MascotDresser
extends RefCounted

## Puts the AIQUIZ mascot (ハテナ, assets/characters/aiquiz_mascot/) on the rigs that were
## built around the old plush body: the finale/goal referee and the saw operator. Those GLBs
## share the mascot's 16-bone skeleton (same bone names and rests, checked by
## tests/mascot_rig_check.gd), so the mascot's mesh and skin bind straight onto their
## Skeleton3D and every authored animation and runtime pose keeps working. The old body is
## no longer imported (skip_import in the GLBs' import settings); one still present is removed.

const MODEL := preload("res://assets/characters/aiquiz_mascot/mascot_model.glb")
## Node name the mascot body gets on a dressed rig (and carries in its own GLB).
const BODY_NAME := "HERO_Mascot"
const OLD_BODIES := ["HERO_GodotPlush", "GodotPlushMesh"]

static var _mesh: Mesh
static var _skin: Skin


## Dresses every mascot-rig skeleton under root; returns how many were dressed.
static func dress(root: Node) -> int:
	if not _load():
		return 0
	var dressed := 0
	for node: Node in root.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		if skeleton.find_bone("DEF-head") < 0 or skeleton.find_bone("DEF-hips") < 0:
			continue
		if skeleton.has_node(BODY_NAME):
			continue
		var layers := 1
		var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for child: Node in skeleton.get_children():
			if child is MeshInstance3D and str(child.name) in OLD_BODIES:
				layers = (child as MeshInstance3D).layers
				shadow = (child as MeshInstance3D).cast_shadow
				skeleton.remove_child(child)
				child.free()
		var body := MeshInstance3D.new()
		body.name = BODY_NAME
		body.mesh = _mesh
		body.skin = _skin
		body.layers = layers
		body.cast_shadow = shadow
		skeleton.add_child(body)
		body.skeleton = NodePath("..")
		dressed += 1
	return dressed


static func _load() -> bool:
	if _mesh != null:
		return true
	var model := MODEL.instantiate()
	var source := model.find_child(BODY_NAME, true, false) as MeshInstance3D
	if source != null:
		_mesh = source.mesh
		_skin = source.skin
	model.free()
	return _mesh != null

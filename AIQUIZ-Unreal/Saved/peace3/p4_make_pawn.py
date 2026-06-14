import unreal
import json

PKG = "/Game/AiQuiz/Pawn"
NAME = "BP_AiQuizPawn"
PATH = PKG + "/" + NAME

out = {"ok": False}

if unreal.EditorAssetLibrary.does_asset_exist(PATH):
    unreal.EditorAssetLibrary.delete_asset(PATH)
    out["deleted_existing"] = True

factory = unreal.BlueprintFactory()
factory.set_editor_property("parent_class", unreal.Pawn)
asset_tools = unreal.AssetToolsHelpers.get_asset_tools()
bp = asset_tools.create_asset(NAME, PKG, None, factory)
assert bp is not None, "create_asset failed"

sds = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
handles = sds.k2_gather_subobject_data_for_blueprint(bp)
root = handles[0]

lib = unreal.SubobjectDataBlueprintFunctionLibrary


def add_comp(klass, name):
    params = unreal.AddNewSubobjectParams(
        parent_handle=root, new_class=klass, blueprint_context=bp)
    handle, fail = sds.add_new_subobject(params)
    if not fail.is_empty():
        raise RuntimeError("add_new_subobject failed: %s" % fail)
    sds.rename_subobject(handle, unreal.Text(name))
    data = sds.k2_find_subobject_data_from_handle(handle)
    return lib.get_object(data)


box = add_comp(unreal.StaticMeshComponent, "BodyBox")
cube = unreal.EditorAssetLibrary.load_asset("/Engine/BasicShapes/Cube")
box.set_editor_property("static_mesh", cube)
box.set_editor_property("relative_scale3d", unreal.Vector(0.7, 0.7, 2.4))

cam = add_comp(unreal.CameraComponent, "FpsCamera")
cam.set_editor_property("relative_location", unreal.Vector(0.0, 0.0, 120.0))
cam.set_editor_property("field_of_view", 71.4)

unreal.BlueprintEditorLibrary.compile_blueprint(bp)
saved = unreal.EditorAssetLibrary.save_asset(PATH)

out["ok"] = True
out["saved"] = bool(saved)
out["components"] = [str(box.get_name()), str(cam.get_name())]
print("RESULT " + json.dumps(out))

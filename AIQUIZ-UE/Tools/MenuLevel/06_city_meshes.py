"""街のメッシュの Nanite を切る。何度実行してもよい。

街は全部で 10 万三角形ほどのローポリで、Nanite にすると遠くでヤシ・アーチ窓・旗のような小さな部品が崩れる。
"""
import unreal

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
sms = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
eal = unreal.EditorAssetLibrary

meshes = {}
for a in eas.get_all_level_actors():
    if a.get_folder_path() == "Menu/City" and isinstance(a, unreal.StaticMeshActor) and a.static_mesh_component.static_mesh:
        sm = a.static_mesh_component.static_mesh
        meshes[sm.get_path_name()] = sm

total = 0
for sm in meshes.values():
    ns = sm.get_editor_property("nanite_settings")
    if ns.enabled:
        ns.enabled = False
        sms.set_nanite_settings(sm, ns, True)
        eal.save_loaded_asset(sm)
    total += sm.get_num_triangles(0)
print("meshes:", len(meshes), "triangles:", total)

# -*- coding: utf-8 -*-
"""SK_YBot_Skeleton のボーン名一覧（block-man のソケット参照名を確定するため）。"""
import unreal
import json

sk = unreal.EditorAssetLibrary.load_asset("/Game/AiQuiz/Character/SK_YBot")
names = []
try:
    skel = sk.get_editor_property("skeleton")
    bones = skel.get_editor_property("bone_tree")  # may not be exposed
except Exception:
    bones = None

# Robust path: use the SkeletalMesh ref skeleton via a spawned component's bone names.
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
les.load_level("/Game/AiQuiz/Maps/L_Game")
for a in eas.get_all_level_actors():
    if a.get_actor_label() == "__BoneProbe":
        eas.destroy_actor(a)
actor = eas.spawn_actor_from_class(unreal.SkeletalMeshActor, unreal.Vector(0, 0, 0))
actor.set_actor_label("__BoneProbe")
comp = actor.skeletal_mesh_component
comp.set_skinned_asset_and_update(sk)
names = [str(n) for n in comp.get_all_socket_names()]  # sockets, may be empty
bone_names = []
try:
    n = comp.get_num_bones()
    bone_names = [str(comp.get_bone_name(i)) for i in range(n)]
except Exception as e:
    bone_names = ["ERR:" + str(e)]
eas.destroy_actor(actor)
print("RESULT " + json.dumps({"num": len(bone_names), "bones": bone_names}, ensure_ascii=False))

import unreal
from collections import Counter

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
w = ues.get_editor_world()
print("WORLD", w.get_path_name())

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
acts = eas.get_all_level_actors()
labels = [a.get_actor_label() for a in acts]
classes = Counter([a.get_class().get_name() for a in acts])
print("ACTOR_COUNT", len(acts))
print("CLASS_HIST", dict(classes))
print("LABELS", labels)

# Dirty packages (unsaved)
try:
    dirty = unreal.EditorLoadingAndSavingUtils.get_dirty_content_packages()
    print("DIRTY_CONTENT", [p.get_path_name() for p in dirty])
except Exception as e:
    print("DIRTY_ERR", e)
try:
    dmap = unreal.EditorLoadingAndSavingUtils.get_dirty_map_packages()
    print("DIRTY_MAPS", [p.get_path_name() for p in dmap])
except Exception as e:
    print("DIRTY_MAP_ERR", e)

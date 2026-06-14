import unreal
from collections import Counter

les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
les.load_level("/Game/AiQuiz/Maps/L_Game")

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

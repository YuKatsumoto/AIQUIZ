# -*- coding: utf-8 -*-
"""L_Game の全アクタの位置と垂直バウンドをダンプ。床/マグマの実際の高さを把握する。"""
import unreal
import json

les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
les.load_level("/Game/AiQuiz/Maps/L_Game")
eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

rows = []
for a in eas.get_all_level_actors():
    try:
        loc = a.get_actor_location()
        scale = a.get_actor_scale3d()
        cls = a.get_class().get_name()
        label = a.get_actor_label()
        row = {
            "label": label, "class": cls,
            "loc": [round(loc.x, 1), round(loc.y, 1), round(loc.z, 1)],
            "scale": [round(scale.x, 3), round(scale.y, 3), round(scale.z, 3)],
        }
        try:
            origin, ext = a.get_actor_bounds(False)
            row["z_min"] = round(origin.z - ext.z, 1)
            row["z_max"] = round(origin.z + ext.z, 1)
            row["ext"] = [round(ext.x, 1), round(ext.y, 1), round(ext.z, 1)]
        except Exception as e:
            row["bounds_err"] = str(e)
        rows.append(row)
    except Exception as e:
        rows.append({"err": str(e)})

# Z で並べる（下から上へ）
rows.sort(key=lambda r: r.get("loc", [0, 0, 0])[2])
for r in rows:
    print("STAGEROW " + json.dumps(r, ensure_ascii=False))
print("STAGECOUNT " + str(len(rows)))

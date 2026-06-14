import unreal, json, traceback

# One-shot wrapper: builds magma + fog, sets a presentation camera, saves,
# and takes a screenshot. Run from the UE Python console:
#   py "C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/finish_peace3.py"

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
SUMMARY = BASE + "/result_finish.json"
summary = {"steps": {}}

for step in ("step3_magma.py", "step4_fog.py"):
    path = BASE + "/" + step
    try:
        exec(open(path, encoding="utf-8").read(), {"__name__": "__peace3__"})
        summary["steps"][step] = "ran"
    except Exception as e:
        summary["steps"][step] = "ERROR: %s" % e
        summary["steps"][step + "_tb"] = traceback.format_exc()

# Presentation camera looking down the belt (travel = +X)
try:
    ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    ues.set_level_viewport_camera_info(unreal.Vector(-1400.0, 0.0, 650.0),
                                       unreal.Rotator(0.0, -16.0, 0.0))
    summary["camera"] = "set"
except Exception as e:
    summary["camera"] = "ERROR: %s" % e

# Screenshot for verification (async; file appears a moment later)
try:
    unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, BASE + "/finish_shot.png")
    summary["screenshot"] = "requested -> finish_shot.png"
except Exception as e:
    summary["screenshot"] = "ERROR: %s" % e

with open(SUMMARY, "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2)
unreal.log("PEACE3_FINISH_DONE %s" % json.dumps(summary["steps"]))
print("PEACE3_FINISH_DONE", summary)

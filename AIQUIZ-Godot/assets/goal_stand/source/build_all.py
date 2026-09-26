"""Rebuild the whole Goal Stand in the connected Blender (Higgsfield connector)
and re-export the GLBs. Adds/updates only the AIQUIZ_GoalStand scene; other
scenes in the session are never touched (name collisions raise instead).

    ns = {}; exec(open(r"C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/build_all.py", encoding="utf-8").read(), ns)
    ns["build_all"](export=True)
"""
import bpy

SOURCE = "C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/"
DANCES = [
    ("Ymca Dance.fbx", "SPEC_Dance_YMCA"),
    ("Y Bot@Gangnam Style.fbx", "SPEC_Dance_Gangnam"),
    ("Silly Dancing.fbx", "SPEC_Dance_Silly"),
    ("Hokey Pokey.fbx", "SPEC_Dance_HokeyPokey"),
    ("Dancing Running Man.fbx", "SPEC_Dance_RunningMan"),
    ("Wave Hip Hop Dance.fbx", "SPEC_Dance_WaveHipHop"),
    ("Swing Dancing.fbx", "SPEC_Dance_Swing"),
]


def run(name):
    ns = {}
    exec(open(SOURCE + name, encoding="utf-8").read(), ns)
    return ns


def build_all(export=True):
    if bpy.data.scenes.get("AIQUIZ_GoalStand") is None:
        bpy.data.scenes.new("AIQUIZ_GoalStand")
    bpy.context.window.scene = bpy.data.scenes["AIQUIZ_GoalStand"]
    bpy.context.window.scene.render.fps = 30
    report = {"rig": run("build_rig.py")["result"]}
    report["bodies"] = run("build_bodies.py")["result"]
    report["reactions"] = run("author_actions.py")["result"]
    retarget = run("retarget_dances.py")["retarget"]
    report["dances"] = [retarget(fbx, action) for fbx, action in DANCES]
    report["ual"] = run("bake_ual.py")["result"]
    report["props"] = run("build_props.py")["result"]
    report["stand"] = run("build_stand.py")["result"]
    if export:
        report["export"] = run("export_goal_stand.py")["result"]
    return report

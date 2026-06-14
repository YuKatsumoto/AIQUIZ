# -*- coding: utf-8 -*-
"""起動中の対話型エディタで、実ビューポートから高解像度スクショを撮る。
p3_cam.txt から "x y z roll pitch yaw name" を1行読む。ue_run.py 経由で実行。"""
import unreal

BASE = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
vals = open(BASE + "/p3_cam.txt").read().split()
x, y, z, rr, rp, ry = map(float, vals[:6])
name = vals[6] if len(vals) > 6 else "vp"

les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)

# L_Game がまだなら開く
w = ues.get_editor_world()
if not w or "L_Game" not in w.get_name():
    les.load_level("/Game/AiQuiz/Maps/L_Game")

ues.set_level_viewport_camera_info(unreal.Vector(x, y, z), unreal.Rotator(rr, rp, ry))
unreal.AutomationLibrary.take_high_res_screenshot(1280, 720, BASE + "/" + name + ".png")
print("SHOT_REQUESTED " + name)

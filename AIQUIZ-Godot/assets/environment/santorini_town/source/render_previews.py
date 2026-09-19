"""Render selected source cameras without rebuilding or overwriting the GLB."""
import bpy
from mathutils import Vector
from pathlib import Path
source=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(source/'aiquiz_santorini_town.blend'))
scene=bpy.data.scenes['AIQUIZ | Santorini Caldera Town']
bpy.context.window.scene=scene
cam=scene.camera
cam.data.clip_end=10000
for name,eye,target,lens in [
    ('town_aerial',(790,-770,700),(0,-150,10),32),
    ('rear_church_detail',(185,158,77),(130,306,39),50),
    ('harbor_detail',(24,43,70),(135,111,20),42),
    ('stage_corridor_day',(0,9,13.7),(0,-180,23),24),
    ('windmill_detail',(32,-206,60),(143,-238,19),45),
]:
    cam.location=eye;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens
    bpy.context.view_layer.update()
    scene.render.filepath=str(source/'previews'/(name+'.png'))
    bpy.ops.render.render(write_still=True,scene=scene.name)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(source/'aiquiz_santorini_town.blend'))

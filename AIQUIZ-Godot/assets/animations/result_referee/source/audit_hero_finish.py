"""Blender contact, timing, framing and light-isolation evidence (no main save)."""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector

OUT=Path('C:/AIQUIZ/AIQUIZ-Godot/artifacts/result_ceremony/hero_low_angle_20260924')

def audit(render=True):
    s=bpy.context.scene
    rig=bpy.data.objects['RIG_Referee']
    bat=bpy.data.objects['PRP_Bat']
    report={'scene':s.name,'active_file':bpy.data.filepath,'poses':[],'max_grip_gap':0,'max_ankle_gap':0}
    for frame in range(601):
        s.frame_set(frame)
        dg=bpy.context.evaluated_depsgraph_get()
        r=rig.evaluated_get(dg)
        grip=bpy.data.objects['CTRL_Grip_L'].evaluated_get(dg).matrix_world.translation
        report['max_grip_gap']=max(report['max_grip_gap'],((r.matrix_world@r.pose.bones['DEF-hand.L'].tail)-grip).length)
        for side in ('L','R'):
            ankle=r.matrix_world@r.pose.bones['DEF-shin.'+side].tail
            report['max_ankle_gap']=max(report['max_ankle_gap'],(ankle-bpy.data.objects['CTRL_Foot_'+side].matrix_world.translation).length)
    for t in [3.08,6.23,6.43,6.51,6.58,6.63,6.68,6.76,6.95,7.58,9.1]:
        f=t*60
        s.frame_set(int(f),subframe=f-int(f))
        forward=rig.matrix_world.to_quaternion()@Vector((0,-1,0))
        direction=bpy.data.objects['LOSE_Actor'].location-rig.location
        direction.z=0
        barrel=bpy.data.objects['CONTACT_Barrel'].matrix_world.translation
        report['poses'].append({'time':t,'referee_forward':list(forward),'facing_loser':forward.dot(direction.normalized()),
            'barrel':list(barrel),'bat_direction':list(bat.matrix_world.to_quaternion()@Vector((1,0,0))),
            'referee_position':list(rig.location),'camera_pitch_degrees':math.degrees(math.asin((s.camera.rotation_quaternion@Vector((0,0,-1))).z))})
    report['passed']=report['max_grip_gap']<.002 and report['max_ankle_gap']<.002 and report['poses'][1]['facing_loser']>.98 and report['poses'][-1]['camera_pitch_degrees']>25
    assert report['passed'],report
    (OUT/'blender_final_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    if render:
        old_path=s.render.filepath
        old_percent=s.render.resolution_percentage
        s.render.resolution_percentage=100
        try:
            for name,t in [('retrieve',3.08),('face',6.23),('load',6.43),('contact',6.68),('follow',6.95),('carrier',9.1)]:
                f=t*60;s.frame_set(int(f),subframe=f-int(f))
                s.render.filepath=str(OUT/f'blender_final_{name}.png')
                bpy.ops.render.render(write_still=True)
            lights=[o for o in s.objects if o.type=='LIGHT']
            saved_lights={o.name:o.hide_render for o in lights}
            backgrounds=[n for n in s.world.node_tree.nodes if n.type=='BACKGROUND']
            strengths=[n.inputs['Strength'].default_value for n in backgrounds]
            try:
                for n in backgrounds:n.inputs['Strength'].default_value=0
                for o in lights:o.hide_render=o.name!='LGT_Key'
                s.render.filepath=str(OUT/'blender_key_only.png')
                bpy.ops.render.render(write_still=True)
            finally:
                for o in lights:o.hide_render=saved_lights[o.name]
                for n,v in zip(backgrounds,strengths):n.inputs['Strength'].default_value=v
        finally:
            s.render.filepath=old_path
            s.render.resolution_percentage=old_percent
            s.frame_set(500)
    return {k:v for k,v in report.items() if k!='poses'}

if __name__=='__main__':result=audit()

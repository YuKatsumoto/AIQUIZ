"""Export the evaluated hero choreography; leave the active .blend path alone."""
import bpy
import json
import math
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path('C:/AIQUIZ/AIQUIZ-Godot')
OUT = ROOT / 'assets/animations/result_referee'
EVIDENCE = ROOT / 'artifacts/result_ceremony/hero_low_angle_20260924'


def export():
    s = bpy.context.scene
    assert s.name == 'AIQUIZ_RefereeFinish_v2' and s.get('hero_finish_version') == 3
    C = Matrix.Rotation(math.pi/2, 4, 'X')
    Ci = C.inverted()
    def pose(matrix):
        p,q,scale=matrix.decompose()
        return [*[round(v,6) for v in p],round(q.x,7),round(q.y,7),round(q.z,7),round(q.w,7),*[round(v,6) for v in scale]]
    objects=[o for o in s.objects if o.name.startswith(('WIN_','LOSE_')) and (o.animation_data or o.name.endswith('Actor'))]
    tracks={o.name:[] for o in objects}
    camera=[]
    contacts=[]
    for frame in range(547):
        s.frame_set(frame)
        for o in objects: tracks[o.name].append(pose(Ci@o.matrix_local@C))
        fov=2*math.atan((s.camera.data.sensor_width*9/16)/(2*s.camera.data.lens))*180/math.pi
        camera.append(pose(Ci@s.camera.matrix_world)+[round(fov,6)])
        dg=bpy.context.evaluated_depsgraph_get()
        r=bpy.data.objects['RIG_Referee'].evaluated_get(dg)
        hand=r.matrix_world@r.pose.bones['DEF-hand.L'].tail
        grip=bpy.data.objects['CTRL_Grip_L'].evaluated_get(dg).matrix_world.translation
        if frame % 3 == 0 or frame in [400,401,405,406,455,546]:
            feet={side:{'ankle_gap':round(((r.matrix_world@r.pose.bones['DEF-shin.'+side].tail)-bpy.data.objects['CTRL_Foot_'+side].matrix_world.translation).length,6),
                        'sole_marker_z':round((r.matrix_world@r.pose.bones['DEF-foot.'+side].tail).z,6)} for side in ('L','R')}
            contacts.append({'frame':frame,'hand_gap_m':round((hand-grip).length,6),'feet':feet})
    s.frame_set(400,subframe=.8)
    impact=Ci@bpy.data.objects['CONTACT_Barrel'].matrix_world.translation
    data={'version':3,'source':'Blender 5.1 editable HeroFinish actions: source/build_hero_finish.py',
          'fps':60,'last_frame':546,'hit':6.68,'release':6.76,'burst':7.58,'freeze':9.1,
          'cast_start':2.0,'verdict':6.0,'duration':10.0,'projection':'perspective',
          'impact_position':list(impact),'tracks':tracks,'camera':camera}
    (OUT/'motion.json').write_text(json.dumps(data,separators=(',',':')),encoding='utf-8')
    report={'samples':contacts,'max_hand_gap':max(v['hand_gap_m'] for v in contacts),
            'max_ankle_gap':max(f['ankle_gap'] for v in contacts for f in v['feet'].values()),'impact_position':list(impact)}
    (EVIDENCE/'blender_contacts.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    bpy.ops.object.select_all(action='DESELECT')
    selected=[o for o in s.objects if o.name in ['RIG_Referee','HERO_GodotPlush'] or o.name.startswith(('PRP_','CTRL_','CONTACT_'))]
    for o in selected: o.select_set(True)
    bpy.context.view_layer.objects.active=bpy.data.objects['RIG_Referee']
    s.frame_set(0)
    bpy.ops.export_scene.gltf(filepath=str(OUT/'referee.glb'),export_format='GLB',use_selection=True,use_active_scene=True,
        export_animations=True,export_animation_mode='SCENE',export_frame_range=True,export_frame_step=1,
        export_bake_animation=True,export_skins=True,export_morph=False,export_lights=False,export_cameras=False,
        export_optimize_animation_size=True)
    s.frame_set(500)
    return {'tracks':len(tracks),'frames':547,'referee_glb_bytes':(OUT/'referee.glb').stat().st_size,
            'max_hand_gap':report['max_hand_gap'],'max_ankle_gap':report['max_ankle_gap']}


if __name__ == '__main__':
    result=export()

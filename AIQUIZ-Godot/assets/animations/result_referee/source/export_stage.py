import bpy, json, math
from pathlib import Path
from mathutils import Matrix, Vector
ROOT=Path('C:/AIQUIZ/AIQUIZ-Godot')
OUT=ROOT/'assets/animations/result_referee'
s=bpy.data.scenes['AIQUIZ_RefereeFinish_v2'];bpy.context.window.scene=s
C=Matrix.Rotation(math.pi/2,4,'X');Ci=C.inverted()
def pose(m):
 p,q,scale=m.decompose();return [*[round(v,6) for v in p],round(q.x,7),round(q.y,7),round(q.z,7),round(q.w,7),*[round(v,6) for v in scale]]
tracks={};objects=[]
for o in s.objects:
 if o.name.startswith(('WIN_','LOSE_')) and (o.animation_data or o.name.endswith('Actor')):
  objects.append(o);tracks[o.name]=[]
camera=[];contacts=[]
for frame in range(689):
 s.frame_set(frame)
 for o in objects:tracks[o.name].append(pose(Ci@o.matrix_local@C))
 camera.append(pose(Ci@s.camera.matrix_world)+[round(s.camera.data.ortho_scale*9/16,6)])
 if frame in [0,440,470,493,507,513,550,573,620,688]:
  r=bpy.data.objects['RIG_Referee'];r=r.evaluated_get(bpy.context.evaluated_depsgraph_get())
  hand=r.matrix_world@r.pose.bones['DEF-hand.L'].tail
  grip=bpy.data.objects['CTRL_Grip_L'].matrix_world.translation
  contacts.append({'frame':frame,'hand_gap_m':(hand-grip).length,'barrel':list(bpy.data.objects['CONTACT_Barrel'].matrix_world.translation)})
data={'source':'Blender 5.1 editable actions: source/AIQUIZ_RefereeFinish_v2.blend','fps':60,'last_frame':688,'hit':8.45,'release':8.55,'burst':9.55,'freeze':688/60,'tracks':tracks,'camera':camera}
(OUT/'motion.json').write_text(json.dumps(data,separators=(',',':')),encoding='utf-8')
(ROOT/'artifacts/result_ceremony/referee/blender_contact_audit.json').write_text(json.dumps(contacts,indent=2),encoding='utf-8')
# Export only the authored referee, bat, and their controls. Existing game actors use the sampled node tracks.
bpy.ops.object.select_all(action='DESELECT')
selected=[o for o in s.objects if o.name in ['RIG_Referee','HERO_GodotPlush'] or o.name.startswith(('PRP_','CTRL_','CONTACT_'))]
for o in selected:o.select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['RIG_Referee']
s.frame_set(0)
bpy.ops.export_scene.gltf(filepath=str(OUT/'referee.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_animations=True,export_animation_mode='SCENE',export_frame_range=True,export_frame_step=1,export_bake_animation=True,export_skins=True,export_morph=False,export_lights=False,export_cameras=False,export_optimize_animation_size=True)
s.frame_set(688)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source/AIQUIZ_RefereeFinish_v2.blend'),copy=True)
print({'tracks':len(tracks),'frames':689,'referee_glb_bytes':(OUT/'referee.glb').stat().st_size,'max_hand_gap':max(x['hand_gap_m'] for x in contacts)})

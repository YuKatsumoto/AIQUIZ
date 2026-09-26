"""Sparse editable keys authored in Blender. Game samples are evaluated from these actions."""
import bpy, math, json
from mathutils import Vector, Matrix, Euler
from pathlib import Path
s=bpy.data.scenes['AIQUIZ_RefereeFinish_v2'];bpy.context.window.scene=s
rig=bpy.data.objects['RIG_Referee'];bat=bpy.data.objects['PRP_Bat'];cam=s.camera
C=Matrix.Rotation(math.pi/2,4,'X');Ci=C.inverted()

def curves(ob):
    if not ob.animation_data or not ob.animation_data.action:return []
    slot=ob.animation_data.action_slot.handle
    return [fc for l in ob.animation_data.action.layers for st in l.strips for cb in st.channelbags if cb.slot_handle==slot for fc in cb.fcurves]
def key(ob,prop,points):
    for sec,value in points:
        setattr(ob,prop,value);ob.keyframe_insert(data_path=prop,frame=round(sec*60),group=ob.name)
    for fc in curves(ob):
        for k in fc.keyframe_points:k.interpolation='BEZIER';k.handle_left_type='AUTO_CLAMPED';k.handle_right_type='AUTO_CLAMPED'
def joint(prefix,name,points):
    ob=bpy.data.objects[prefix+name];ob.rotation_mode='XYZ'
    key(ob,'rotation_euler',[(t,(C@Euler(tuple(math.radians(a) for a in v),'YXZ').to_matrix().to_4x4()@Ci).to_euler('XYZ')) for t,v in points])
def bone(name,points):
    b=rig.pose.bones[name];b.rotation_mode='XYZ'
    for sec,degrees in points:
        b.rotation_euler=[math.radians(a) for a in degrees];b.keyframe_insert('rotation_euler',frame=round(sec*60),group=name)

rig.animation_data_clear()
for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
# Keep the independent referee swing source usable for revisions to this scene.
from runpy import run_path
run_path('C:/AIQUIZ/AIQUIZ-Godot/assets/animations/result_referee/source/rebuild_bat_swing.py')['apply_referee_swing']()
for pre,x in [('WIN_',-2.15),('LOSE_',2.05)]:
    ob=bpy.data.objects[pre+'Actor'];ob.animation_data_clear();ob.rotation_mode='XYZ'
    key(ob,'location',[(0,(x,0,1.34)),(7.33,(x,0,1.34))])
    joint(pre,'l_shoulder',[(0,(0,0,-6)),(7.33,(0,0,-6))]);joint(pre,'r_shoulder',[(0,(0,0,6)),(7.33,(0,0,6))])

winner=bpy.data.objects['WIN_Actor']
key(winner,'rotation_euler',[(0,(0,0,-.08)),(7.33,(0,0,-.08)),(8.05,(0,0,-.20)),(8.6,(0,0,-.26)),(9.6,(0,0,-.18)),(11.47,(0,0,-.18))])
joint('WIN_','r_shoulder',[(0,(0,0,6)),(7.33,(0,0,6)),(7.85,(-35,0,55)),(8.55,(-30,0,125)),(9.7,(-25,0,120)),(11.47,(-25,0,120))])
joint('WIN_','r_elbow',[(0,(0,0,0)),(7.33,(0,0,0)),(7.85,(-75,0,0)),(8.6,(-100,0,0)),(11.47,(-100,0,0))])
joint('WIN_','l_shoulder',[(0,(0,0,-6)),(7.33,(0,0,-6)),(8.45,(-18,0,-18)),(9.55,(-15,0,-25)),(11.47,(-15,0,-25))])
joint('WIN_','l_elbow',[(0,(0,0,0)),(7.33,(0,0,0)),(8.6,(-70,0,0)),(11.47,(-70,0,0))])
joint('WIN_','head_pivot',[(0,(0,0,0)),(7.5,(0,15,0)),(9.55,(0,10,-6)),(11.47,(0,10,-6))])

loser=bpy.data.objects['LOSE_Actor']
key(loser,'rotation_euler',[(0,(0,0,.08)),(7.33,(0,0,.08)),(8.10,(0,0,math.pi/2)),(8.45,(0,0,math.pi/2)),(8.55,(0,0,math.pi/2)),(9.10,(.12,-.48,1.32)),(9.55,(.18,-.62,.65)),(11.47,(.22,-.73,.35)),(12.667,(.22,-.73,.35))])
key(loser,'location',[(0,(2.05,0,1.34)),(7.33,(2.05,0,1.34)),(8.45,(2.05,0,1.34)),(8.55,(2.05,0,1.34)),(8.9,(2.9,.12,2.02)),(9.55,(3.32,.2,2.39)),(10.3,(3.46,.24,2.47)),(11.47,(3.50,.25,2.49)),(12.667,(3.50,.25,2.49))])
joint('LOSE_','spine',[(0,(0,0,0)),(7.33,(0,0,0)),(8.1,(22,0,0)),(8.45,(26,0,0)),(8.55,(26,0,0)),(8.95,(-10,0,-7)),(9.55,(-16,0,-12)),(11.47,(-18,0,-13))])
for side,sign in [('l',-1),('r',1)]:
    joint('LOSE_',side+'_shoulder',[(0,(0,0,sign*6)),(7.33,(0,0,sign*6)),(8.10,(-45,0,sign*10)),(8.45,(-55,0,sign*15)),(8.55,(-55,0,sign*15)),(9.10,(-30,0,sign*80)),(9.55,(-15,0,sign*105)),(11.47,(-10,0,sign*115))])
    joint('LOSE_',side+'_elbow',[(0,(0,0,0)),(7.33,(0,0,0)),(8.45,(-65,0,0)),(8.55,(-65,0,0)),(9.55,(-30,0,0)),(11.47,(-25,0,0))])
    joint('LOSE_',side+'_hip',[(0,(0,0,0)),(8.45,(-8*sign,0,0)),(8.55,(-8*sign,0,0)),(9.55,(25*sign,0,sign*15)),(11.47,(30*sign,0,sign*20))])
    joint('LOSE_',side+'_knee',[(0,(0,0,0)),(8.45,(10,0,0)),(8.55,(10,0,0)),(9.55,(38,0,0)),(11.47,(45,0,0))])

# Separate the existing toy parts at the burst; head/hat remain identifiable.
for name,offset in [('head_pivot',(0,0,.18)),('l_shoulder',(-.25,0,.10)),('r_shoulder',(.25,0,.12)),('l_hip',(-.20,0,-.10)),('r_hip',(.20,0,-.10))]:
    ob=bpy.data.objects['LOSE_'+name];rest=ob.location.copy()
    key(ob,'location',[(0,rest),(9.55,rest),(10.05,rest+Vector(offset)*.8),(11.47,rest+Vector(offset)),(12.667,rest+Vector(offset))])

# Camera is authored here; runtime consumes evaluated transforms, not a second approximation.
for t,eye,target,scale in [(0,(2,-13,3.4),(.45,0,.68),9.5),(7.33,(2,-13,3.4),(.45,0,.68),9.5),(8.45,(1.4,-13,3.25),(.55,0,.85),9.8),(9.55,(.8,-13,3.2),(.65,0,1.05),10.7),(11.47,(.55,-13,3.2),(.65,0,1.07),10.9),(12.667,(.55,-13,3.2),(.65,0,1.07),10.9)]:
    cam.location=eye;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
    cam.keyframe_insert('location',frame=round(t*60));cam.keyframe_insert('rotation_euler',frame=round(t*60));cam.data.keyframe_insert('ortho_scale',frame=round(t*60))
for ob in [rig,cam,cam.data]:
    for fc in curves(ob):
        for k in fc.keyframe_points:k.interpolation='BEZIER';k.handle_left_type='AUTO_CLAMPED';k.handle_right_type='AUTO_CLAMPED'
for label,t in [('Line-up',0),('Scores',2),('Verdict',7.3333),('Anticipation',8.22),('Bat contact',8.45),('Release',8.55),('Toy burst',9.55),('Freeze',11.4667),('Interactive',12.6667)]:s.timeline_markers.new(label,frame=round(t*60))
s.frame_set(507)
print({'animated_objects':len([o for o in s.objects if o.animation_data]),'contact_frame':507,'freeze_frame':688})

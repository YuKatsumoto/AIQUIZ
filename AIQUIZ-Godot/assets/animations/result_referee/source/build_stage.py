"""Run in the live Blender scene, after importing the existing actors. No source meshes replaced."""
import bpy, math, json
from mathutils import Vector
from pathlib import Path
ROOT=Path('C:/AIQUIZ/AIQUIZ-Godot')
s=bpy.data.scenes['AIQUIZ_RefereeFinish_v2']
bpy.context.window.scene=s

def material(name,color,rough=.6):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color=(*color,1);m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough
    return m
def empty(name,loc=(0,0,0),parent=None):
    o=bpy.data.objects.new(name,None);s.collection.objects.link(o);o.parent=parent;o.location=loc
    return o
def mesh(name,verts,faces,mat,parent=None):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    o=bpy.data.objects.new(name,data);s.collection.objects.link(o);o.parent=parent;o.data.materials.append(mat)
    return o

# Original plush ships with vertex colors; its separate albedo is the production texture.
plush=bpy.data.objects['GodotPlushMesh.001'];plush.name='HERO_GodotPlush'
m=material('REF_OriginalPlush',(1,1,1),.83)
p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(ROOT/'assets/characters/godot_plush/godot_plush_albedo.png'),check_existing=True)
m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color']);p.inputs['Alpha'].default_value=1
plush.data.materials.clear();plush.data.materials.append(m)
for o in s.objects:
    if o.name.startswith('LOSE_') and o.type=='MESH':
        o.data=o.data.copy()
        o.data.materials.clear();o.data.materials.append(material('REF_P2Preview',(.035,.42,.8)))

floor=mesh('ENV_RefereeFloor',[(-12,-8,0),(12,-8,0),(12,10,0),(-12,10,0)],[(0,1,2,3)],material('REF_NavyFloor',(.018,.033,.055),.8))
for pre,x in [('WIN_',-2.15),('LOSE_',1.6)]:
    bpy.data.objects[pre+'Actor'].location=(x,0,1.34)

# A continuous lathed profile: knob -> slim handle -> shoulder -> rounded barrel.
bat=empty('PRP_Bat',(-.28,-.30,.88))
profile=[(-.10,0),(-.095,.048),(-.07,.060),(-.03,.060),(0,.035),(.42,.035),(.56,.049),(.78,.079),(1.22,.092),(1.40,.09),(1.47,.065),(1.50,0)]
verts=[];faces=[];sides=32
for x,r in profile:
    verts.extend([(x,r*math.cos(i*math.tau/sides),r*math.sin(i*math.tau/sides)) for i in range(sides)])
for j in range(len(profile)-1):
    for i in range(sides):faces.append((j*sides+i,j*sides+(i+1)%sides,(j+1)*sides+(i+1)%sides,(j+1)*sides+i))
wood=material('REF_MapleWood',(.54,.25,.065),.4)
barrel=mesh('PRP_MapleBat',verts,faces,wood,bat)
grip=material('REF_BatGrip',(.035,.025,.028),.82);barrel.data.materials.append(grip)
for poly in barrel.data.polygons:
    poly.use_smooth=True
    if poly.center.x<.39:poly.material_index=1
# Fine ring seams are modeled into the grip silhouette, not a replacement of the player.
for i in range(9):
    x=.025+i*.041
    vs=[(x+dx,.037*math.cos(a*math.tau/24),.037*math.sin(a*math.tau/24)) for dx in [-.003,.003] for a in range(24)]
    fs=[(a,(a+1)%24,24+(a+1)%24,24+a) for a in range(24)]
    mesh('PRP_GripSeam_%02d'%i,vs,fs,material('REF_GripSeam',(.08,.065,.058)),bat)
empty('CONTACT_Barrel',(1.32,0,0),bat)
rig=bpy.data.objects['RIG_Referee']
for side,x in [('R',0.02),('L',.43)]:
    target=empty('CTRL_Grip_'+side,(x,0,0),bat)
    c=rig.pose.bones['DEF-hand.'+side].constraints.new('IK');c.name='Bat grip '+side;c.target=target;c.chain_count=3;c.use_stretch=True
    for bn in ['upper_arm','forearm','hand']:rig.pose.bones['DEF-'+bn+'.'+side].ik_stretch=.15

cam=bpy.data.objects['CAM_Result'];cam.location=(2.0,-13,3.4)
cam.rotation_euler=(Vector((.45,0,.68))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=9.5
s.world.use_nodes=True;next(n for n in s.world.node_tree.nodes if n.type=='BACKGROUND').inputs['Color'].default_value=(.11,.15,.21,1);next(n for n in s.world.node_tree.nodes if n.type=='BACKGROUND').inputs['Strength'].default_value=.25
for name,loc,power,size,color in [('LGT_Key',(-3,-5,6),950,5,(1,.87,.7)),('LGT_Fill',(4,-5,3),220,4,(.45,.64,1)),('LGT_Rim',(1,3,5),1050,3,(1,.65,.3))]:
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=color
    o=bpy.data.objects.new(name,d);s.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
    o['purpose']=name.split('_')[1];o['motivation']='Arena stage lighting'
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective='CAMERA'
        area.spaces.active.shading.type='SOLID';area.spaces.active.shading.color_type='MATERIAL'
s.frame_set(0)
print({'stage':s.name,'objects':len(s.objects),'bat_length':1.6,'camera':cam.name})


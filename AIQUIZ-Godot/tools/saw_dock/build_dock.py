"""Editable, metre-scale conveyor service dock. Run in Blender through Higgsfield.

Native axes: X across belt, +Y toward course, Z up; origin at lift centre,
floor elevation. GLB keeps semantic moving groups for deterministic Godot motion.
Stages: blockout (camera gate), detail (export after inspection).
"""
import bpy, math, os, json
from mathutils import Vector

ROOT = 'C:/AIQUIZ/AIQUIZ-Godot'
OUT = ROOT + '/artifacts/saw_dock'
ASSET = ROOT + '/assets/hazards/saw_service_dock.glb'
STAGE = globals().get('dock_stage', 'blockout')
os.makedirs(OUT, exist_ok=True)

def material(name, color, metal=0.0, rough=.4):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if p is None:
        p=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
        out=m.node_tree.nodes.new('ShaderNodeOutputMaterial')
        m.node_tree.links.new(p.outputs['BSDF'],out.inputs['Surface'])
    p.inputs['Base Color'].default_value = (*color,1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    return m

def empty(name, parent=None):
    o=bpy.data.objects.new(name,None); scene.collection.objects.link(o)
    o.parent=parent
    return o

def box(name, size, at, mat, parent=None, bevel=.015):
    # Actual mesh coordinates; no nonuniform object scale under bevels.
    x,y,z=[v*.5 for v in size]
    vs=[(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)]
    fs=[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vs,[],fs);mesh.update()
    o=bpy.data.objects.new(name,mesh);scene.collection.objects.link(o)
    o.parent=parent;o.location=at;o.data.materials.append(mat)
    if bevel:
        mod=o.modifiers.new('Machined edges','BEVEL');mod.width=bevel;mod.segments=2
        mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return o

def cyl(name, radius, depth, at, mat, parent=None, axis='Z', verts=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=radius,depth=depth,location=(0,0,0))
    o=bpy.context.object;o.name=name;o.parent=parent;o.location=at
    if axis=='X':o.rotation_euler[1]=math.pi/2
    elif axis=='Y':o.rotation_euler[0]=math.pi/2
    o.data.materials.append(mat)
    for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
    b=o.modifiers.new('Turned edge','BEVEL');b.width=.009;b.segments=2
    return o

def rail(name,x,start,end,parent):
    y=(start+end)*.5; length=end-start
    box(name+'_head',(.16,length,.04),(x,y,.24),steel,parent,.006)
    box(name+'_web',(.06,length,.12),(x,y,.16),steel,parent,.004)
    box(name+'_foot',(.24,length,.06),(x,y,.07),dark,parent,.006)

def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()

def sample(t):
    def ease(a,b):
        u=max(0,min(1,(t-a)/(b-a)));return u*u*u*(10+u*(-15+6*u))
    lift=ease(.35,1.55)*(1-ease(3.65,4.7))
    shutter=ease(0,.35)*(1-ease(4.7,5.05))
    locked=ease(1.55,1.75)*(1-ease(3.5,3.65))
    travel=4.8*ease(1.75,3.5)
    return lift,shutter,locked,travel

def shutter_pose(i,amount):
    d=i*.15+amount*4.60
    if d<=4.45:return (0,1.8-d,.02),0
    # Articulated cover coils inwards; layer gap exceeds slat thickness.
    th=(d-4.45)/.44;r=.46-.006*th
    return (0,-2.65-r*math.sin(th),-.44+r*math.cos(th)),th

if STAGE=='blockout':
    scene=bpy.data.scenes.get('SawDock_Workshop')
    if scene and len(scene.objects):raise RuntimeError('Workshop is not empty; inspect before rebuilding.')
    scene=scene or bpy.data.scenes.new('SawDock_Workshop');bpy.context.window.scene=scene
    scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1400;scene.render.resolution_y=800
    scene.render.resolution_percentage=100;scene.render.fps=60;scene.frame_start=1;scene.frame_end=601
    scene.world=bpy.data.worlds.new('Dock_Inspection_World');scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes.new('ShaderNodeBackground')
    wo=scene.world.node_tree.nodes.new('ShaderNodeOutputWorld')
    scene.world.node_tree.links.new(bg.outputs[0],wo.inputs[0])
    bg.inputs[0].default_value=(.22,.26,.32,1)
    bg.inputs[1].default_value=.6
    scene.view_settings.view_transform='AgX'
    dark=material('Dock_Graphite',(.065,.09,.115),.65,.36)
    steel=material('Dock_BrushedSteel',(.43,.51,.57),.85,.3)
    yellow=material('Dock_SafetyOchre',(.9,.47,.045),.35,.38)
    rubber=material('Dock_Rubber',(.018,.023,.029),.05,.65)
    root=empty('DOCK_ROOT');static=empty('DOCK_STATIC',root);lift=empty('DOCK_LIFT',root)
    lift.location.z=-1.4
    # Open lift well; no closed box passes through the moving mechanism.
    box('RearWall',(25.4,.14,2.25),(0,-1.98,-1.1),dark,static)
    box('Sump',(25.4,4.15,.16),(0,-.10,-2.26),dark,static)
    # Front edge is low enough for the carriage underside (+.03) to clear.
    box('FrontSill',(25.4,.16,.2),(0,1.94,-.14),dark,static)
    for s in [-1,1]:
        box('SideCheek_'+str(s),(.25,4.2,2.2),(s*12.65,-.1,-1.06),dark,static)
        box('ShutterGuide_'+str(s),(.10,4.6,.12),(s*12.47,-.455,.015),steel,static)
        box('GuideColumn_'+str(s),(.16,3.5,1.9),(s*12.42,0,-1.15),steel,static)
        # Support links to the conveyor chassis run outside roller end faces.
        box('MountBeam_'+str(s),(.30,2.0,.28),(s*12.55,2.35,-.58),dark,static)
        rail('LiftRail_'+str(s),s*11.86,-1.85,1.85,lift)
        rail('BridgeRail_'+str(s),s*11.86,1.85,3.15,static)
        box('LiftSideBeam_'+str(s),(.44,3.7,.18),(s*11.86,0,-.08),dark,lift)
        cyl('CylinderBarrel_'+str(s),.17,.8,(s*11.86,0,-1.81),dark,static)
        rod=empty('DOCK_ROD_'+('L' if s<0 else 'R'),root)
        rod.location=(s*11.86,0,-1.5)
        cyl('PistonChrome_'+str(s),.09,1,(0,0,.5),steel,rod)
        pin=empty('DOCK_LOCK_'+('L' if s<0 else 'R'),root)
        pin.location=(s*12.44,1.1,-.09)
        cyl('LockPin_'+str(s),.055,.32,(0,0,0),steel,pin,'X')
    for y in [-1.3,0,1.3]:box('LiftCrossmember_'+str(y),(23.6,.18,.16),(0,y,-.14),dark,lift)
    for i in range(24):
        slat=empty('DOCK_SLAT_%02d'%i,root)
        box('Slat_%02d'%i,(24.85,.145,.025),(0,0,0),steel,slat,.006)
    # Coil storage housing is behind the lift envelope.
    box('CoilBack',(25.4,.16,1.16),(0,-3.27,-.46),dark,static)
    box('CoilHood',(25.4,1.05,.12),(0,-2.72,.20),dark,static)
    for s in [-1,1]:box('CoilEnd_'+str(s),(.2,1.1,1.16),(s*12.62,-2.72,-.46),dark,static)
    # Reference only, excluded from game export.
    refs=empty('REF_ROOT')
    bpy.ops.import_scene.gltf(filepath=ROOT+'/assets/hazards/linked_saw_carriage.glb')
    imported=[o for o in bpy.context.selected_objects if o.parent is None]
    carrier=empty('REF_Carriage',refs)
    for o in imported:o.parent=carrier
    for s in [-1,1]:rail('REF_StageRail_'+str(s),s*11.86,3.15,13.0,refs)
    box('REF_Belt',(24,9.85,.4),(0,8.075,-.2),rubber,refs)
    cyl('REF_Roller',.48,23.4,(0,3.15,-.48),rubber,refs,'X',64)
    bpy.ops.object.camera_add(location=(26,-31,21));cam=bpy.context.object;cam.name='CAM_DockInspection';cam.data.type='ORTHO';cam.data.ortho_scale=34;aim(cam,(0,2,0));scene.camera=cam
    bpy.ops.object.light_add(type='AREA',location=(0,-8,18));key=bpy.context.object;key.name='LGT_DockKey';key.data.energy=24000;key.data.shape='DISK';key.data.size=18;aim(key,(0,0,-1))
    # Preview keys use the same analytic choreography as runtime; no physics drift.
    for f in range(1,602,2):
        t=(f-1)/60;up,cover,lock,dist=sample(t)
        lift.location.z=-1.4*(1-up);lift.keyframe_insert('location',frame=f)
        carrier.location=(0,dist,-1.4*(1-up) if t<1.75 else 0);carrier.keyframe_insert('location',frame=f)
        for i in range(24):
            o=bpy.data.objects['DOCK_SLAT_%02d'%i];at,ang=shutter_pose(i,cover)
            o.location=at;o.rotation_euler.x=ang;o.keyframe_insert('location',frame=f);o.keyframe_insert('rotation_euler',frame=f)
        for s,label in [(-1,'L'),(1,'R')]:
            o=bpy.data.objects['DOCK_ROD_'+label];o.scale.z=.08+1.4*up;o.keyframe_insert('scale',frame=f)
            o=bpy.data.objects['DOCK_LOCK_'+label];o.location.x=s*(12.44-.25*lock);o.keyframe_insert('location',frame=f)
    scene.frame_set(121)
    scene.render.filepath=OUT+'/blockout.png';bpy.ops.render.render(write_still=True)
    result={'stage':'blockout','scene':scene.name,'objects':len(scene.objects),'render':scene.render.filepath}
else:
    scene=bpy.data.scenes['SawDock_Workshop'];bpy.context.window.scene=scene
    root=bpy.data.objects['DOCK_ROOT'];static=bpy.data.objects['DOCK_STATIC'];lift=bpy.data.objects['DOCK_LIFT']
    dark=bpy.data.materials['Dock_Graphite'];steel=bpy.data.materials['Dock_BrushedSteel'];yellow=bpy.data.materials['Dock_SafetyOchre'];rubber=bpy.data.materials['Dock_Rubber']
    # Restrained medium-scale service detail, readable at the gameplay distance.
    for s in [-1,1]:
        for y in [-1.55,1.55]:
            box('GuideShoe_%s_%s'%(s,y),(.2,.35,.34),(s*12.24,y,-.14),dark,lift)
            for dz in [-.1,.1]:cyl('ShoeBolt',.035,.045,(s*12.13,y,-.14+dz),steel,lift,'X',6)
        for y in [-1.3,0,1.3]:
            box('ServicePanel',(.018,.86,.7),(s*12.782,y,-.88),steel,static,.01)
            for yy in [-.30,.30]:
                for zz in [-.25,.25]:cyl('ServiceBolt',.032,.03,(s*12.80,y+yy,-.88+zz),dark,static,'X',6)
        for y in [-1.60,1.60]:
            box('WarningEnd',(.32,.36,.035),(s*11.86,y,.015),yellow,lift,.01)
        cyl('LockCollar',.1,.25,(s*12.40,1.1,-.09),dark,static,'X')
        cyl('CylinderGland',.20,.13,(s*11.86,0,-1.4),steel,static)
        cyl('HydraulicLine',.035,1.9,(s*12.1,0,-1.35),rubber,static)
        for z in [-1.9,-1.0]:
            cyl('HoseFitting',.06,.15,(s*12.05,0,z),steel,static,'X',6)
        for y in [-2.55,1.6]:
            box('LampSocket',(.24,.38,.08),(s*12.64,y,.12),rubber,static)
            lampmat=material('Dock_Amber',(.95,.32,.025),.1,.28)
            p=next(n for n in lampmat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Emission Color'].default_value=(1,.19,.008,1);p.inputs['Emission Strength'].default_value=.9
            box('DOCK_LAMP_%s_%s'%(s,y),(.14,.26,.04),(s*12.64,y,.18),lampmat,static,.02)
    for x in [-9,-6,-3,0,3,6,9]:
        box('SumpRib',(.10,3.85,.12),(x,-.1,-2.10),steel,static)
        # Recessed panels and long ribs express the span without a solid slab.
        box('RearServicePanel',(2.6,.035,.65),(x,-2.064,-1.20),steel,static)
        for dx in [-1.18,1.18]:
            cyl('RearPanelBolt',.035,.035,(x+dx,-2.09,-1.20),dark,static,'Y',6)
    # Yellow/black strip is mesh geometry, never baked UI or texture generation.
    for x in range(-12,13):
        box('LipWarning',(0.43,.17,.014),(x,1.94,-.033),yellow,static,.002)
    # Combine static and lift submeshes by material while keeping all motion roots.
    for group in [static,lift]:
        groups={}
        for o in list(group.children):
            if o.type=='MESH':groups.setdefault(o.data.materials[0].name,[]).append(o)
        for mat,objects in groups.items():
            bpy.ops.object.select_all(action='DESELECT')
            for o in objects:
                o.select_set(True);bpy.context.view_layer.objects.active=o
                for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
            bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
            bpy.context.object.name=group.name+'_'+mat
    scene.frame_set(1)
    bpy.ops.object.select_all(action='DESELECT')
    def select_tree(o):
        o.select_set(True)
        for c in o.children:select_tree(c)
    select_tree(root);bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=ASSET,export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
    scene.frame_set(121);scene.render.filepath=OUT+'/detail.png';bpy.ops.render.render(write_still=True)
    for im in bpy.data.images:
        if 'Steel_Concentric_' in im.name:
            suffix='Roughness' if 'Roughness' in im.name else 'BaseColor'
            im.filepath=ROOT+'/assets/hazards/linked_saw_carriage_Steel_Concentric_'+suffix+'_1536.png'
            im.pack()
    # User explicitly requested implementation and editable production assets.
    bpy.ops.wm.save_as_mainfile(filepath=OUT+'/saw_service_dock.blend')
    result={'stage':'detail','asset':ASSET,'blend':bpy.data.filepath,'render':scene.render.filepath}

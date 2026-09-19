"""Staged, editable vessel construction. Execute inside the live Higgsfield Blender host.

vessel_stage: hull -> mechanism -> preview -> detail -> export -> animate.
No existing dock/saw data is edited. Native +Y points toward the conveyor.
"""
import bpy, math, os, json
from mathutils import Vector

ROOT = 'C:/AIQUIZ/AIQUIZ-Godot'
OUT = ROOT + '/artifacts/saw_vessel'
ASSET = ROOT + '/assets/hazards/saw_service_vessel.glb'
STAGE = globals().get('vessel_stage', 'hull')
os.makedirs(OUT, exist_ok=True)

def mat(name, color, metal=.25, rough=.4, emission=0):
    m = bpy.data.materials.get('Vessel_'+name) or bpy.data.materials.new('Vessel_'+name)
    m.diffuse_color = (*color, 1); m.use_nodes = True
    p = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'),None)
    if p is None:
        p=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
        output=m.node_tree.nodes.new('ShaderNodeOutputMaterial');m.node_tree.links.new(p.outputs['BSDF'],output.inputs['Surface'])
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal; p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*color,1)
        p.inputs['Emission Strength'].default_value = emission
    return m

def empty(name, parent=None):
    if name in bpy.data.objects: raise RuntimeError('Already exists: '+name)
    o=bpy.data.objects.new(name,None); scene.collection.objects.link(o); o.parent=parent
    return o

def mesh(name, vertices, faces, material, parent=None, bevel=0):
    if name in bpy.data.objects: raise RuntimeError('Already exists: '+name)
    me=bpy.data.meshes.new(name); me.from_pydata(vertices,[],faces); me.update()
    # Recalculate outward normals for closed generated surfaces.
    import bmesh
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    o=bpy.data.objects.new(name,me);scene.collection.objects.link(o);o.parent=parent
    me.materials.append(material)
    if bevel:
        b=o.modifiers.new('Fabricated edge bevel','BEVEL');b.width=bevel;b.segments=2
        o.modifiers.new('Plate corner normals','WEIGHTED_NORMAL')
    return o

def box(name,size,at,material,parent=None,bevel=.025):
    x,y,z=[v/2 for v in size]
    vs=[(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)]
    fs=[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]
    o=mesh(name,vs,fs,material,parent,bevel);o.location=at;return o

def rod(name,a,b,radius,material,parent=None,n=16):
    a,b=Vector(a),Vector(b);axis=b-a;length=axis.length
    vs=[(radius*math.cos(i*math.tau/n),radius*math.sin(i*math.tau/n),z) for z in (0,length) for i in range(n)]
    fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    o=mesh(name,vs,fs,material,parent,min(radius*.2,.018));o.location=a;o.rotation_euler=axis.to_track_quat('Z','Y').to_euler()
    return o

def rail(name,x,start,end,parent):
    for label,w,h,z,m in [('Head',.16,.04,.24,steel),('Web',.06,.12,.16,steel),('Foot',.24,.06,.07,dark)]:
        box(name+'_'+label,(w,end-start,h),(x,(start+end)/2,z),m,parent,.005)

def aim(o,target): o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()

def loft(name,stations,material,parent):
    # Closed transverse plate rings; chine widths vary along the ship's length.
    vs=[]
    for y,w in stations:
        vs += [(x,y,z) for x,z in [(-w,-4.9),(-w,-5.5),(-w*.93,-8.0),(-w*.75,-9.65),(w*.75,-9.65),(w*.93,-8.0),(w,-5.5),(w,-4.9)]]
    fs=[tuple(reversed(range(8))),tuple(range(len(vs)-8,len(vs)))]
    for j in range(len(stations)-1):
        for i in range(8): fs.append((j*8+i,j*8+(i+1)%8,(j+1)*8+(i+1)%8,(j+1)*8+i))
    return mesh(name,vs,fs,material,parent,.06)

def sample(t):
    def e(a,b):
        u=max(0,min(1,(t-a)/(b-a)));return u*u*u*(10+u*(-15+6*u))
    u=max(0,min(1,t/2.25));approach=2*u-2*u**3+u**4
    return {'offset':-10*(1-approach)-42*e(9,15),
            'lift':e(2.35,4.2)*(1-e(6.55,8.4)),
            'cover':e(1.45,2.3),
            'bridge':e(4.2,4.4)*(1-e(6.3,6.5)),
            'lock':e(4.25,4.42)*(1-e(6.2,6.3)),
            'travel':4.8*e(4.42,6.2)}

def shutter(i,amount):
    d=i*.15+amount*4.6
    if d<=4.45:return (0,1.8-d,.02),0
    a=(d-4.45)/.44;r=.46-.006*a
    return (0,-2.65-r*math.sin(a),-.44+r*math.cos(a)),a

def pose(t, keyframe=None):
    p=sample(t)
    root.location.y=p['offset'];lift.location.z=-4.8*(1-p['lift'])
    nodes=[(root,'location'),(lift,'location')]
    for side in ['L','R']:
        o=bpy.data.objects['VSL_ROD_'+side];o.scale.z=.12+4.8*p['lift'];nodes.append((o,'scale'))
        o=bpy.data.objects['VSL_BRIDGE_'+side];o.scale.y=max(.001,p['bridge']);nodes.append((o,'scale'))
        o=bpy.data.objects['VSL_LOCK_'+side];o.location.x=(-1 if side=='L' else 1)*(12.44-.25*p['lock']);nodes.append((o,'location'))
    for i in range(24):
        o=bpy.data.objects['VSL_SLAT_%02d'%i];at,ang=shutter(i,p['cover']);o.location=at;o.rotation_euler.x=ang
        nodes.extend([(o,'location'),(o,'rotation_euler')])
    carrier=bpy.data.objects.get('VREF_Carriage')
    if carrier:
        carrier.location=(0,4.8 if t>=6.2 else p['offset']+p['travel'],-4.8*(1-p['lift']) if t<4.42 else 0)
        nodes.append((carrier,'location'))
    if keyframe is not None:
        for o,prop in nodes:o.keyframe_insert(prop,frame=keyframe)
    bpy.context.view_layer.update()

def render(label):
    scene.render.filepath=OUT+'/'+label+'.png';bpy.ops.render.render(write_still=True)

if STAGE=='hull':
    scene=bpy.data.scenes.get('SawVessel_Workshop')
    if scene and len(scene.objects):raise RuntimeError('Vessel scene already has objects; inspect first.')
    scene=scene or bpy.data.scenes.new('SawVessel_Workshop');bpy.context.window.scene=scene
    scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1400;scene.render.resolution_y=850
    scene.render.resolution_percentage=100;scene.render.fps=60;scene.frame_start=1;scene.frame_end=661
    scene.view_settings.view_transform='AgX';scene.view_settings.exposure=0
    world=bpy.data.worlds.get('Vessel_InspectionWorld') or bpy.data.worlds.new('Vessel_InspectionWorld');world.use_nodes=True;scene.world=world
    bg=world.node_tree.nodes.get('Background')
    if bg is None:
        bg=world.node_tree.nodes.new('ShaderNodeBackground');wo=world.node_tree.nodes.new('ShaderNodeOutputWorld');world.node_tree.links.new(bg.outputs[0],wo.inputs[0])
    bg.inputs[0].default_value=(.30,.37,.45,1);bg.inputs[1].default_value=.5
else:
    scene=bpy.data.scenes['SawVessel_Workshop'];bpy.context.window.scene=scene

navy=mat('Navy',(.018,.055,.105),.28,.38)
white=mat('Ivory',(.72,.76,.76),.1,.4)
dark=mat('Graphite',(.055,.075,.085),.4,.47)
deck=mat('Deck',(.18,.22,.24),.35,.58)
yellow=mat('SafetyYellow',(.93,.52,.045),.2,.38)
steel=mat('Steel',(.43,.53,.60),.9,.25)
rubber=mat('Rubber',(.012,.017,.020),.0,.82)
glass=mat('Glazing',(.012,.044,.065),.3,.18)

if STAGE=='hull':
    root=empty('VSL_ROOT');body=empty('VSL_BODY',root);lift=empty('VSL_LIFT',root)
    loft('VSL_Hull',[(-15,10.8),(-13,12.8),(-10,13.4),(-3,13.4),(1.7,12.8),(2.15,12.4)],navy,body)
    # Broad aft working deck, open foredeck lift well and chamfered wheelhouse.
    box('VSL_AftDeck',(25.3,9.3,.12),(0,-7.65,-4.84),deck,body,.06)
    box('VSL_Accommodation',(8.6,4.4,1.35),(0,-10.6,-4.10),white,body,.12)
    vs=[(-4,-12.7,-3.425),(4,-12.7,-3.425),(4,-8.55,-3.425),(-4,-8.55,-3.425),(-3.7,-12.4,-.55),(3.7,-12.4,-.55),(3.7,-9,-.55),(-3.7,-9,-.55)]
    mesh('VSL_Wheelhouse',vs,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],white,body,.06)
    box('VSL_Roof',(8.8,5.0,.20),(0,-10.6,-.4),white,body,.06)
    # Main glazing bands follow the sloping walls, framed in the detail phase.
    for sign,label in [(-1,'Port'),(1,'Starboard')]:
        box('VSL_'+label+'Windows',(.07,2.7,1.13),(sign*3.80,-10.55,-1.5),glass,body,.025)
    for y,label in [(-12.5,'Aft'),(-8.85,'Forward')]:
        box('VSL_'+label+'Windows',(7.0,.07,1.13),(0,y,-1.5),glass,body,.025)
    # An explicit inspection camera; original cameras/world remain untouched.
    data=bpy.data.cameras.new('VCAM_Inspection');cam=bpy.data.objects.new('VCAM_Inspection',data);scene.collection.objects.link(cam)
    cam.location=(38,-50,26);data.lens=48;aim(cam,(0,-5,-4));scene.camera=cam
    ld=bpy.data.lights.new('VLGT_StructuralKey','AREA');key=bpy.data.objects.new('VLGT_StructuralKey',ld);scene.collection.objects.link(key)
    key.location=(5,-14,25);ld.energy=36000;ld.shape='DISK';ld.size=20;aim(key,(0,-3,-4))
    key['purpose']='Reveal hull chine and lift connections';key['motivation']='Daylight';key['target']='Vessel';key['camera_relation']='camera left';key['expected_effect']='Broad plate highlights and readable shadow side'
    render('blockout_hull')
    result={'stage':STAGE,'scene':scene.name,'objects':len(scene.objects),'render':scene.render.filepath}
else:
    root=bpy.data.objects['VSL_ROOT'];body=bpy.data.objects['VSL_BODY'];lift=bpy.data.objects['VSL_LIFT']

if STAGE=='mechanism':
    for s,label in [(-1,'L'),(1,'R')]:
        rail('VSL_LiftRail_'+label,s*11.86,-1.85,1.85,lift)
        box('VSL_LiftBeam_'+label,(.44,3.7,.22),(s*11.86,0,-.13),yellow,lift)
        for y in [-1.4,1.4]:
            box('VSL_Guide_'+label+str(y),(.26,.32,5.45),(s*12.6,y,-2.2),yellow,body)
        rod('VSL_Cylinder_'+label,(s*11.86,0,-6.0),(s*11.86,0,-4.8),.25,dark,body)
        piston=empty('VSL_ROD_'+label,root);piston.location=(s*11.86,0,-4.92)
        rod('VSL_Piston_'+label,(0,0,0),(0,0,1),.135,steel,piston)
        bridge=empty('VSL_BRIDGE_'+label,lift);bridge.location=(0,1.85,0)
        rail('VSL_ConnectingRail_'+label,s*11.86,0,1.3,bridge)
        pin=empty('VSL_LOCK_'+label,lift);pin.location=(s*12.44,1.1,-.09)
        rod('VSL_LockPin_'+label,(-.16,0,0),(.16,0,0),.075,steel,pin)
        box('VSL_SideCoaming_'+label,(.20,4.2,.85),(s*12.63,-.1,-4.39),navy,body)
    for i,y in enumerate([-1.4,0,1.4]):box('VSL_LiftCrossmember_'+str(i),(24.8,.25,.22),(0,y,-.13),dark,lift)
    box('VSL_Platform',(24.8,3.7,.08),(0,0,-.065),deck,lift)
    cover=empty('VSL_COVER',root);cover.location.z=-4.0
    for i in range(24):
        slat=empty('VSL_SLAT_%02d'%i,cover)
        box('VSL_ShutterPlate_%02d'%i,(24.85,.145,.025),(0,0,0),steel,slat,.005)
    box('VSL_ShutterCoilHood',(25.4,1.12,.15),(0,-2.75,-3.78),navy,body)
    box('VSL_ShutterCoilRear',(25.4,.16,1.1),(0,-3.27,-4.35),navy,body)
    pose(2.45);render('blockout_mechanism')
    result={'stage':STAGE,'objects':len(scene.objects),'render':scene.render.filepath}

if STAGE=='preview':
    refs=empty('VREF_ROOT');carrier=empty('VREF_Carriage',refs)
    before=set(scene.objects);bpy.ops.import_scene.gltf(filepath=ROOT+'/assets/hazards/linked_saw_carriage.glb')
    imported=set(scene.objects)-before
    for o in imported:
        if o.parent is None:o.parent=carrier
        o.name='VREF_'+o.name
    for s,label in [(-1,'L'),(1,'R')]:rail('VREF_Rail_'+label,s*11.86,3.15,18,refs)
    box('VREF_Conveyor',(24,14.85,.8),(0,10.575,-.4),deck,refs)
    box('VREF_Sea',(100,110,.06),(0,-12,-8.04),mat('Sea',(.035,.23,.29),.35,.32),refs,0)
    pose(2.45);render('blockout_docked')
    result={'stage':STAGE,'render':scene.render.filepath}

if STAGE=='detail':
    if 'VSL_AftFender' in bpy.data.objects:raise RuntimeError('Detail already exists; inspect before editing.')
    ochre=mat('OchreShade',(.37,.20,.035),.15,.6)
    worn=mat('Waterline',(.025,.043,.058),.15,.7)
    warm=mat('WorkLight',(.95,.78,.42),.05,.25,1.7)
    red=mat('PortLight',(.65,.012,.008),.05,.25,1.5)
    green=mat('StarboardLight',(.012,.48,.09),.05,.25,1.5)
    stations=[(-15,10.8),(-13,12.8),(-10,13.4),(-3,13.4),(1.7,12.8),(2.15,12.4)]
    def beam_width(y):
        for (ya,wa),(yb,wb) in zip(stations,stations[1:]):
            if ya<=y<=yb:return wa+(wb-wa)*(y-ya)/(yb-ya)
        return stations[0][1] if y<stations[0][0] else stations[-1][1]
    # Swept rubbing rails follow the actual hull profile instead of floating on it.
    for s,label in [(-1,'Port'),(1,'Starboard')]:
        for j,((ya,wa),(yb,wb)) in enumerate(zip(stations,stations[1:])):
            rod('VSL_'+label+'RubbingRail%02d'%j,(s*(wa+.035),ya,-5.65),(s*(wb+.035),yb,-5.65),.20,rubber,body)
            rod('VSL_'+label+'SheerCap%02d'%j,(s*wa,ya,-4.85),(s*wb,yb,-4.85),.065,white,body)
            # Waterline band follows the chine; restrained dark wet/grime zone.
            vs=[(s*wa*.934,ya,-7.91),(s*wb*.934,yb,-7.91),(s*wb*.94,yb,-7.65),(s*wa*.94,ya,-7.65)]
            mesh('VSL_'+label+'Waterline%02d'%j,vs,[(0,1,2,3)],worn,body)
        for j,y in enumerate([-12,-9,-6,-3,.6]):
            x=s*(beam_width(y)+.11)
            rod('VSL_'+label+'VerticalFender%02d'%j,(x,y,-7.15),(x,y,-5.2),.31,rubber,body,24)
            for z in [-6.95,-5.45]:
                box('VSL_'+label+'FenderStrap'+str(j)+str(z),(.12,.75,.12),(x+s*.22,y,z),steel,body,.018)
        # Guardrail posts and two rails leave clear access to the forward lift.
        ys=[-12.5,-10.5,-8.5,-6.5,-4.5,-3.6]
        for j,y in enumerate(ys):
            x=s*(beam_width(y)-.45)
            rod('VSL_'+label+'Stanchion%02d'%j,(x,y,-4.77),(x,y,-3.65),.047,yellow,body)
        for j,(ya,yb) in enumerate(zip(ys,ys[1:])):
            for z in [-4.2,-3.65]:
                rod('VSL_'+label+'Guardrail'+str(j)+str(z),(s*(beam_width(ya)-.45),ya,z),(s*(beam_width(yb)-.45),yb,z),.04,yellow,body)
        # Real mooring and service details are placed in deliberate clusters.
        for j,y in enumerate([-12.3,-4.5]):
            x=s*10.5
            box('VSL_'+label+'BollardFoot'+str(j),(1.2,.85,.14),(x,y,-4.67),dark,body)
            for dx in [-.34,.34]:
                rod('VSL_'+label+'Bollard'+str(j)+str(dx),(x+dx,y,-4.60),(x+dx,y,-4.03),.16,steel,body)
                rod('VSL_'+label+'BollardCap'+str(j)+str(dx),(x+dx,y-.28,-4.10),(x+dx,y+.28,-4.10),.10,dark,body)
        box('VSL_'+label+'PumpSkid',(1.25,1.8,.16),(s*8.5,-5.3,-4.65),dark,body)
        box('VSL_'+label+'PumpCabinet',(1.1,1.45,.85),(s*8.5,-5.3,-4.17),yellow,body,.06)
        for j in range(5):
            box('VSL_'+label+'PumpVent'+str(j),(.80,.04,.045),(s*8.5,-6.04,-4.0-j*.11),dark,body,.008)
        points=[(s*8.5,-4.5,-4.38),(s*10.5,-4.0,-4.38),(s*12.0,-3.5,-4.38),(s*12.0,-.15,-4.38)]
        for j,(a,b) in enumerate(zip(points,points[1:])):rod('VSL_'+label+'HydraulicPipe'+str(j),a,b,.065,steel,body)
        rod('VSL_'+label+'CylinderCollar',(s*11.86,0,-4.92),(s*11.86,0,-4.71),.30,steel,body,24)
        for y in [-1.4,1.4]:
            box('VSL_'+label+'GuideShoe'+str(y),(.35,.45,.48),(s*12.45,y,-.10),dark,lift)
            rod('VSL_'+label+'GuideWheel'+str(y),(s*12.40,y,-.09),(s*12.67,y,-.09),.17,steel,lift)
        # Dedicated cabin access stair, outside the operating platform envelope.
        for j in range(6):
            box('VSL_'+label+'Stair%02d'%j,(1.0,.42,.10),(s*4.85,-8.65-j*.40,-4.67+j*.225),deck,body,.012)
        rod('VSL_'+label+'StairRail',(s*5.25,-8.5,-3.7),(s*5.25,-10.8,-2.4),.045,yellow,body)
        for j,(y,z) in enumerate([(-8.5,-4.7),(-10.8,-3.4)]):
            rod('VSL_'+label+'StairRailSupport'+str(j),(s*5.25,y,z),(s*5.25,y,z+1),.045,yellow,body)
        # Twin stacks and roof navigation fixtures give a clear workboat silhouette.
        rod('VSL_'+label+'Exhaust',(s*5.3,-11.8,-4.8),(s*5.3,-11.8,.30),.24,navy,body,24)
        rod('VSL_'+label+'ExhaustCap',(s*5.3,-11.8,.26),(s*5.3,-11.8,.48),.29,dark,body,24)
        box('VSL_'+label+'NavigationHousing',(.42,.55,.20),(s*4.20,-9.1,-.34),dark,body)
        box('VSL_'+label+'NavigationLens',(.33,.40,.12),(s*4.20,-9.1,-.19),red if s<0 else green,body,.03)
        for y in [-1.4,1.4]:
            box('VSL_'+label+'WorkLampHousing'+str(y),(.44,.32,.25),(s*12.6,y,.48),dark,body)
            box('VSL_'+label+'WorkLampLens'+str(y),(.32,.04,.15),(s*12.6,y-.18,.48),warm,body,.015)
    rod('VSL_AftFender',(-10.8,-15.15,-5.65),(10.8,-15.15,-5.65),.28,rubber,body,24)
    rod('VSL_BowFender',(-12.4,2.28,-5.65),(12.4,2.28,-5.65),.28,rubber,body,24)
    for j,x in enumerate([-10,-7,0,7,10]):
        if x==0:continue
        box('VSL_DeckHatch%02d'%j,(1.9,1.35,.10),(x,-8,-4.71),dark,body)
        box('VSL_DeckHatchInset%02d'%j,(1.65,1.12,.025),(x,-8,-4.645),deck,body,.012)
        rod('VSL_DeckHatchHandle%02d'%j,(x-.2,-8,-4.59),(x+.2,-8,-4.59),.035,steel,body)
    # Window divisions follow each wall's slope, giving scale without noisy detail.
    for j,x in enumerate([-2.8,-1.4,0,1.4,2.8]):
        rod('VSL_AftMullion%02d'%j,(x,-12.56,-2.07),(x,-12.43,-.94),.045,white,body)
        rod('VSL_FrontMullion%02d'%j,(x,-8.74,-2.07),(x,-8.94,-.94),.045,white,body)
    for s,label in [(-1,'Port'),(1,'Starboard')]:
        for j,y in enumerate([-11.45,-10.55,-9.65]):
            rod('VSL_'+label+'WindowMullion%02d'%j,(s*3.87,y,-2.07),(s*3.75,y,-.94),.045,white,body)
        # Welded ribs and service access remain localized, leaving clean hull plates.
        for j,y in enumerate([-10,-7,-4]):
            x=s*(beam_width(y)-.015)
            box('VSL_'+label+'HullWeld%02d'%j,(.032,.025,1.0),(x,y,-5.43),steel,body,.004)
    rod('VSL_Mast',(0,-10.6,-.29),(0,-10.6,2.2),.095,white,body)
    rod('VSL_RadarBeam',(-1.2,-10.6,1.6),(1.2,-10.6,1.6),.09,white,body)
    for j,x in enumerate([-2.6,2.6]):rod('VSL_Antenna'+str(j),(x,-11.7,-.28),(x,-11.7,1.5),.023,steel,body,12)
    box('VSL_RoofServiceUnit',(1.9,1.3,.45),(0,-11,-.05),deck,body,.08)
    # Warning strips sit on the mechanical lip, not over the whole vessel.
    for i,x in enumerate(range(-12,13)):
        box('VSL_LiftWarning%02d'%i,(.42,.19,.022),(x,1.72,-.013),yellow,lift,.003)
    pose(2.45);render('detail_docked')
    result={'stage':STAGE,'objects':len(scene.objects),'render':scene.render.filepath}

if STAGE=='export':
    # Copy only export branches into a temporary scene and merge meshes per
    # material AND moving parent. Authoring objects and modifiers stay editable.
    pose(4.42)
    export_scene=bpy.data.scenes.new('Vessel_Export_Temporary');mapping={}
    def clone(o,parent=None):
        c=o.copy();c.animation_data_clear()
        if o.data:c.data=o.data.copy()
        export_scene.collection.objects.link(c);c.parent=parent;mapping[o]=c
        for child in o.children:clone(child,c)
    clone(root);bpy.context.window.scene=export_scene
    for original,copy in mapping.items():copy.name='EXP_'+original.name
    for p in [o for o in mapping.values() if o.type=='EMPTY']:
        groups={}
        for o in list(p.children):
            if o.type=='MESH':groups.setdefault(o.data.materials[0].name,[]).append(o)
        for material,objects in groups.items():
            bpy.ops.object.select_all(action='DESELECT')
            for o in objects:
                o.select_set(True);bpy.context.view_layer.objects.active=o
                for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
            bpy.context.view_layer.objects.active=objects[0]
            if len(objects)>1:bpy.ops.object.join()
            bpy.context.object.name=p.name+'_'+material
    # Original semantic names are exported via temporary renames, restored finally.
    names={o:o.name for o in scene.objects if o.name.startswith('VSL_')}
    try:
        for o,n in names.items():o.name='AUTHOR_'+n
        for o in export_scene.objects:o.name=o.name.removeprefix('EXP_')
        bpy.ops.export_scene.gltf(filepath=ASSET,export_format='GLB',use_active_scene=True,export_apply=True,export_animations=False)
        stats={'meshes':sum(o.type=='MESH' for o in export_scene.objects),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in export_scene.objects if o.type=='MESH')}
    finally:
        bpy.context.window.scene=scene
        for o in list(export_scene.objects):bpy.data.objects.remove(o,do_unlink=True)
        bpy.data.scenes.remove(export_scene)
        for o,n in names.items():o.name=n
    result={'stage':STAGE,'asset':ASSET,**stats}

if STAGE=='animate':
    scene.frame_end=1081
    for f in range(1,1082):pose((f-1)/60,f)
    for o in scene.objects:
        ad=o.animation_data
        if not ad or not ad.action:continue
        for layer in ad.action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    if bag.slot_handle!=ad.action_slot.handle:continue
                    for curve in bag.fcurves:
                        for point in curve.keyframe_points:point.interpolation='LINEAR'
    scene.frame_set(266)
    result={'stage':STAGE,'animated_objects':sum(bool(o.animation_data) for o in scene.objects),'frame_range':[1,1081]}

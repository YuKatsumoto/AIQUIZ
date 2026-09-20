"""Staged native Blender construction; run through the live Higgsfield Bridge.

stage: blockout, detail, export. Asset local front is -Y; source scene mounts
it facing carriage +Y. Existing scene and imported carriage remain untouched.
"""
import bpy, math, json, os, uuid
from mathutils import Vector, Matrix
ROOT='C:/AIQUIZ/AIQUIZ-Godot'
OUT=ROOT+'/artifacts/saw_operator'
ASSET=ROOT+'/assets/hazards/saw_operator'
STAGE=globals().get('operator_stage','blockout')
if 'SawOperator_Workbench' not in bpy.data.scenes:
    assert STAGE=='blockout', 'Start with blockout or open the editable source.'
    bpy.context.window.scene=bpy.data.scenes.new('SawOperator_Workbench')
    bpy.ops.import_scene.gltf(filepath=ROOT+'/assets/hazards/linked_saw_carriage.glb')
    bpy.ops.import_scene.gltf(filepath=ROOT+'/assets/characters/godot_plush/godot_plush_model.glb')
scene=bpy.data.scenes['SawOperator_Workbench']
bpy.context.window.scene=scene

def save_workbench():
    # A separate library write keeps other open scenes out of this asset.
    # Atomic replacement also works when Blender's Windows overwrite fails.
    target=ASSET+'/source/saw_operator.blend'
    temporary=ASSET+'/source/workbench_'+uuid.uuid4().hex+'.blend'
    bpy.data.libraries.write(temporary,{scene},path_remap='RELATIVE_ALL',fake_user=True,compress=True)
    os.replace(temporary,target)

def material(name,color,metal=0,rough=.5):
    m=bpy.data.materials.get('OP_'+name) or bpy.data.materials.new('OP_'+name)
    m.diffuse_color=(*color,1);m.use_nodes=True
    p=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if p is None:
        p=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
        output=m.node_tree.nodes.new('ShaderNodeOutputMaterial');m.node_tree.links.new(p.outputs['BSDF'],output.inputs['Surface'])
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m
dark=material('Charcoal',(.045,.062,.072),.25,.36)
steel=material('Machined',(.48,.54,.58),.85,.28)
yellow=material('SafetyYellow',(.96,.49,.025),.15,.38)
rubber=material('Rubber',(.016,.021,.025),0,.72)
seatmat=material('Seat',(.036,.045,.052),0,.65)
red=material('StartRed',(.65,.035,.018),.12,.32)
ivory=material('DialFace',(.83,.88,.83),0,.55)
amber=material('Amber',(.85,.26,.016),.15,.32)

def empty(name,loc=(0,0,0),parent=None):
    assert name not in bpy.data.objects,name
    o=bpy.data.objects.new(name,None);scene.collection.objects.link(o)
    o.parent=parent;o.location=loc;o.empty_display_size=.04
    return o

def mesh(name,verts,faces,mat,parent=None,loc=(0,0,0),bevel=0):
    assert name not in bpy.data.objects,name
    me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(verts,[],faces);me.update()
    o=bpy.data.objects.new(name,me);scene.collection.objects.link(o);o.parent=parent;o.location=loc
    me.materials.append(mat)
    if bevel:
        mod=o.modifiers.new('Machined edge radius','BEVEL');mod.width=bevel;mod.segments=3
        mod=o.modifiers.new('Corner normals','WEIGHTED_NORMAL');mod.keep_sharp=True
    return o

def box(name,loc,size,mat,parent,bevel=.012):
    x,y,z=[v*.5 for v in size]
    return mesh(name,[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat,parent,loc,bevel)

def cylinder(name,loc,radius,depth,mat,parent,vertices=24):
    vs=[(radius*math.cos(a*math.tau/vertices),radius*math.sin(a*math.tau/vertices),z) for z in [-depth/2,depth/2] for a in range(vertices)]
    fs=[tuple(reversed(range(vertices))),tuple(range(vertices,vertices*2))]+[(i,(i+1)%vertices,(i+1)%vertices+vertices,i+vertices) for i in range(vertices)]
    return mesh(name,vs,fs,mat,parent,loc,.003)

def beam(name,a,b,width,mat,parent):
    a,b=Vector(a),Vector(b)
    o=box(name,(a+b)*.5,(width,width,(b-a).length),mat,parent,.008)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def pipe(name,points,radius,mat,parent):
    curve=bpy.data.curves.new(name+'_Curve','CURVE');curve.dimensions='3D';curve.bevel_depth=radius;curve.bevel_resolution=3;curve.resolution_u=16
    spline=curve.splines.new('BEZIER');spline.bezier_points.add(len(points)-1)
    for p,co in zip(spline.bezier_points,points):
        p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,curve);scene.collection.objects.link(o);o.parent=parent;curve.materials.append(mat)
    return o

def loft(name,stations,mat,parent):
    # Eight-corner chamfered cross sections form a continuous manufactured shell.
    vs=[]
    for z,w,d,y in stations:
        c=min(.045,w*.18,d*.18);x=w/2;h=d/2
        vs.extend([(a,b+y,z) for a,b in [(-x+c,-h),(x-c,-h),(x,-h+c),(x,h-c),(x-c,h),(-x+c,h),(-x,h-c),(-x,-h+c)]])
    fs=[tuple(reversed(range(8))),tuple(range(len(vs)-8,len(vs))) ]
    for j in range(len(stations)-1):
        fs.extend([(j*8+i,j*8+(i+1)%8,(j+1)*8+(i+1)%8,(j+1)*8+i) for i in range(8)])
    return mesh(name,vs,fs,mat,parent,bevel=.012)

def aim(o,target):
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()

def render(name):
    scene.render.filepath=OUT+'/'+name+'.png';bpy.ops.render.render(write_still=True)

def descendants(root):
    return [root]+list(root.children_recursive)

if STAGE=='blockout':
    assert 'OperatorStation' not in bpy.data.objects
    root=empty('OperatorStation')
    # Support remains behind the moving blade plane and inside the 25x3.7m lift.
    box('OP_Deck',(0,0,.90),(1.64,1.74,.14),dark,root)
    mount=empty('OP_MountFrame',parent=root)
    for x in [-.32,.32]:
        # Clamp to the existing left outboard spine at X=-12.12, Z=.39..51.
        box('OP_UnderframeTie_'+str(x),(x,1.42,.46),(.20,.10,.10),dark,mount,.008)
        support=empty('OP_LiftSupport_'+('L' if x>0 else 'R'),(x,1.42,.67),mount)
        cylinder('OP_LiftRod_'+str(x),(0,0,0),.055,1.0,steel,support)
        support.scale.z=.42
        box('OP_Mount_'+str(x),(x,1.42,.50),(.30,.10,.09),steel,mount)
    box('OP_SeatPedestal',(0,.30,1.09),(.42,.48,.26),dark,root)
    loft('OP_SeatCushion',[(1.22,.68,.67,.23),(1.25,.76,.71,.23),(1.35,.76,.71,.23),(1.38,.66,.62,.23)],seatmat,root)
    back=loft('OP_SeatBack',[(1.34,.65,.17,.58),(1.55,.76,.18,.62),(1.98,.66,.19,.70),(2.15,.52,.16,.73)],seatmat,root)
    for label,sgn in [('L',1),('R',-1)]:
        c=loft('OP_Console_'+label,[(.98,.24,.61,-.12),(1.28,.24,.61,-.12),(1.37,.34,.70,-.13),(1.44,.34,.70,-.13)],dark,root);c.location.x=sgn*.55
        lever=empty('OP_Lever_'+label,(sgn*.50,-.035,1.44),root)
        cylinder('OP_LeverShaft_'+label,(0,0,.10),.020,.20,steel,lever)
        cylinder('OP_Grip_'+label,(0,0,.19),.044,.12,rubber,lever)
        empty('OP_GripContact_'+label,(0,0,.20),lever)
        pedal=empty('OP_Pedal_'+label,(sgn*.15,-.14,1.11),root)
        pedal.rotation_euler.x=math.radians(22)
        box('OP_PedalPlate_'+label,(0,-.10,0),(.22,.29,.045),steel,pedal)
        empty('OP_FootContact_'+label,(0,-.11,.035),pedal)
    rig=bpy.data.objects['Rig'];rig.animation_data_clear();rig.parent=root;rig.location=(0,.22,.99);rig.scale=(.8,)*3
    for b in rig.pose.bones: b.matrix_basis=Matrix.Identity(4)
    meshpilot=bpy.data.objects['GodotPlushMesh']
    image=bpy.data.images.load(ROOT+'/assets/characters/godot_plush/godot_plush_albedo.png',check_existing=True)
    for slot in meshpilot.material_slots:
        m=slot.material;m.use_nodes=True
        p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color']);p.inputs['Roughness'].default_value=.85
    # Blender IK is an inspection rig; runtime uses the same contact targets.
    for label in ['L','R']:
        sgn=1 if label=='L' else -1
        t=empty('OP_WristTarget_'+label,(sgn*.50,.025,1.64),root)
        ik=rig.pose.bones['DEF-forearm.'+label].constraints.new('IK');ik.name='Control contact';ik.target=t;ik.chain_count=2;ik.use_stretch=False
        hand=rig.pose.bones['DEF-hand.'+label]
        hand.rotation_mode='QUATERNION'
        # Hand orientation is solved after IK evaluation by the pose stage.
        t=empty('OP_AnkleTarget_'+label,(sgn*.149,-.03,1.27),root)
        ik=rig.pose.bones['DEF-shin.'+label].constraints.new('IK');ik.name='Pedal contact';ik.target=t;ik.chain_count=2;ik.use_stretch=False
    root.location=(-10.70,0,0);root.rotation_euler.z=math.pi/2
    # Disable imported demo animation without changing the imported asset on disk.
    for o in scene.objects:
        if o.name=='Carriage_Motion_Rig':
            o.animation_data_clear()
            for pb in o.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    camdata=bpy.data.cameras.new('OP_InspectionCamera');cam=bpy.data.objects.new('OP_InspectionCamera',camdata);scene.collection.objects.link(cam)
    scene.camera=cam;cam.location=(-7.5,-3.8,3.5);aim(cam,(-10.7,0,1.5));camdata.lens=55
    scene.world=bpy.data.worlds.new('OP_StudioWorld');scene.world.use_nodes=True
    bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
    bg.inputs[0].default_value=(.22,.25,.29,1);bg.inputs[1].default_value=.45
    for name,loc,power,size in [('Key',(-13.4,2.0,6),1000,5),('Fill',(-8,0,4),350,4)]:
        d=bpy.data.lights.new('OP_'+name,'AREA');d.energy=power;d.shape='DISK';d.size=size
        o=bpy.data.objects.new('OP_'+name,d);scene.collection.objects.link(o);o.location=loc;aim(o,(-10.9,-.65,1.25))
    scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.fps=60;scene.frame_start=1;scene.frame_end=361
    scene.view_settings.view_transform='AgX'
    bpy.context.view_layer.update()
    render('blockout')
    bpy.ops.wm.save_as_mainfile(filepath=OUT+'/checkpoint_blockout.blend',copy=True)
    result={'stage':STAGE,'objects':len(descendants(root)),'render':OUT+'/blockout.png'}

if STAGE in ['contact','detail','export']:
    root=bpy.data.objects['OperatorStation'];rig=bpy.data.objects['Rig']
    # Orient mittens and soles independently of the two-bone IK chain.
    bpy.context.view_layer.update()
    for side in ['L','R']:
        for part,direction in [('hand',Vector((0,-1,0))),('foot',Vector((0,-.74,-.67)))]:
            b=rig.pose.bones['DEF-'+part+'.'+side]
            rest=b.bone.matrix_local.to_3x3()
            q=(rest@Vector((0,1,0))).rotation_difference(direction)
            desired=(q.to_matrix()@rest).to_4x4();desired.translation=b.head
            b.matrix=desired
    bpy.context.view_layer.update()

if STAGE=='contact':
    # Soles now rest on the pedals rather than inheriting the shin's rotation.
    render('contact')
    result={'stage':STAGE}

if STAGE=='detail':
    for side,sgn in [('L',1),('R',-1)]:
        # Replaceable gasketed top, service hatch and recessed vent louvers.
        box('OP_PanelGasket_'+side,(sgn*.55,-.13,1.447),(.325,.66,.012),rubber,root,.005)
        box('OP_PanelPlate_'+side,(sgn*.55,-.13,1.459),(.300,.63,.013),dark,root,.005)
        fascia=box('OP_InstrumentHousing_'+side,(sgn*.55,-.38,1.60),(.32,.11,.30),dark,root,.015)
        fascia.rotation_euler.x=math.radians(24)
        for j in range(5):
            box('OP_Vent_'+side+str(j),(sgn*.678,.10,1.06+j*.029),(.007,.20,.009),rubber,root,.003)
        for x in [-.126,.126]:
            for y in [-.40,.15]:
                cylinder('OP_PanelScrew_'+side+str(x)+str(y),(sgn*.55+x,y,1.473),.011,.010,steel,root,8)
        lever=bpy.data.objects['OP_Lever_'+side]
        for j in range(4):
            cylinder('OP_LeverBoot_'+side+str(j),(0,0,.018+j*.026),.074-j*.010,.022,rubber,lever)
        for j in range(5):
            cylinder('OP_GripRib_'+side+str(j),(0,0,.15+j*.017),.047,.009,rubber,lever)
        cap=cylinder('OP_GripCap_'+side,(0,0,.258),.037,.014,dark,lever)
        for x in [-.067,.067]:
            pin=cylinder('OP_LeverPin_'+side+str(x),(x,0,.016),.025,.012,steel,lever);pin.rotation_euler.y=math.pi/2
        pedal=bpy.data.objects['OP_Pedal_'+side]
        for i in range(3):
            for j in range(4):
                cylinder('OP_PedalDimple_'+side+str(i)+str(j),((i-1)*.061,-.20+j*.059,.026),.018,.003,rubber,pedal,12)
        axle=cylinder('OP_PedalAxle_'+side,(0,0,0),.032,.30,dark,pedal);axle.rotation_euler.y=math.pi/2
        pipe('OP_ControlCable_'+side,[(sgn*.64,.12,1.4),(sgn*.67,.34,1.24),(sgn*.61,.57,.75),(sgn*.60,.56,.29)],.018,rubber,root)
        for j in range(10):
            cylinder('OP_CableCollar_'+side+str(j),(sgn*.61,.57,.35+j*.035),.022,.01,dark,root,12)
        # Compact analog dial mounted on the forward fascia, facing the driver.
        gauge=empty('OP_GaugeMount_'+side,(sgn*.55,-.319,1.61),root);gauge.rotation_euler.x=math.radians(66)
        cylinder('OP_GaugeBezel_'+side,(0,0,0),.115,.028,steel,gauge,48)
        cylinder('OP_GaugeRubber_'+side,(0,0,.016),.103,.008,rubber,gauge,48)
        cylinder('OP_GaugeFace_'+side,(0,0,.022),.094,.006,ivory,gauge,48)
        for j in range(17):
            a=math.radians(-130+260*j/16)
            tick=box('OP_GaugeTick_'+side+str(j),(.077*math.sin(a),.077*math.cos(a),.027),(.005,.015 if j%4==0 else .008,.002),dark,gauge,0)
            tick.rotation_euler.z=-a
        needle=empty('OP_Needle_'+side,(0,0,.033),gauge)
        box('OP_NeedleBar_'+side,(0,.027,0),(.007,.075,.004),red,needle,.002)
        cylinder('OP_NeedleHub_'+side,(0,0,.004),.012,.007,steel,needle)
    # Controls are next to each grip, within the short original arm's reach.
    cylinder('OP_StartCollar',(.59,.105,1.479),.063,.015,yellow,root)
    start=empty('OP_Start',(.59,.105,1.50),root)
    cylinder('OP_StartStem',(0,0,.016),.026,.035,dark,start)
    cylinder('OP_StartCap',(0,0,.039),.047,.018,red,start)
    empty('OP_StartContact',(0,0,.050),start)
    cylinder('OP_ToggleCollar',(-.59,.105,1.48),.044,.020,steel,root)
    toggle=empty('OP_Toggle',(-.59,.105,1.50),root)
    cylinder('OP_ToggleShaft',(0,0,.034),.012,.068,steel,toggle)
    cylinder('OP_ToggleTip',(0,0,.070),.019,.028,rubber,toggle)
    empty('OP_ToggleContact',(0,0,.080),toggle)
    cover=empty('OP_Cover',(-.59,.045,1.51),root)
    box('OP_CoverTop',(0,.054,.080),(.096,.13,.015),amber,cover,.007)
    for x in [-.046,.046]:box('OP_CoverSide'+str(x),(x,.054,.043),(.008,.13,.074),amber,cover,.003)
    empty('OP_CoverContact',(.045,.05,.080),cover)
    dial=empty('OP_Dial',(-.47,.14,1.485),root)
    cylinder('OP_DialBody',(0,0,.033),.042,.065,dark,dial,32)
    for j in range(20):
        a=math.tau*j/20;cylinder('OP_DialKnurl'+str(j),(.041*math.cos(a),.041*math.sin(a),.031),.003,.050,steel,dial,6)
    box('OP_DialIndicator',(0,.020,.068),(.008,.032,.003),ivory,dial,.001)
    empty('OP_DialContact',(0,0,.072),dial)
    # Stitched cushions, suspension bellows, bolts and non-slip deck pattern.
    pipe('OP_SeatPiping',[(-.31,-.075,1.376),(.31,-.075,1.376),(.33,.47,1.376),(-.33,.47,1.376),(-.31,-.075,1.376)],.006,yellow,root)
    for j in range(4):box('OP_SeatBellows'+str(j),(0,.30,1.0+j*.046),(.49,.55,.028),rubber,root,.01)
    for x in [-.33,.33]:
        pipe('OP_BackSeam'+str(x),[(x,.478,1.45),(x,.514,1.64),(x*.84,.576,1.94),(x*.66,.634,2.10)],.004,yellow,root)
    for x in [-.76,.76]:
        for y in [-.81,.81]:
            box('OP_CornerPlate'+str(x)+str(y),(x,y,.91),(.105,.026,.115),yellow,root,.004)
    for i in range(11):
        for j in range(12):
            if abs((i-5)*.13)<.40 and j>5:continue
            o=box('OP_Tread_%02d_%02d'%(i,j),((i-5)*.13,(j-5.5)*.13,.978),(.062,.012,.006),steel,root,.003);o.rotation_euler.z=math.pi/4*(1 if (i+j)%2 else -1)
    # Non-structural detailing stays off the clean silhouette.
    for x in [-.32,.32]:
        for y in [1.396,1.444]:
            cylinder('OP_MountBolt'+str(x)+str(y),(x,y,.558),.024,.025,steel,bpy.data.objects['OP_MountFrame'],6)
    bpy.context.view_layer.update();render('detail')
    bpy.ops.wm.save_as_mainfile(filepath=OUT+'/checkpoint_detail.blend',copy=True)
    result={'stage':STAGE,'objects':len(descendants(root)),'render':OUT+'/detail.png'}

if STAGE=='export':
    root=bpy.data.objects['OperatorStation'];rig=bpy.data.objects['Rig']
    # Keep the editable source and its inspection rig; optimize copies only.
    save_workbench()
    saved_frame=scene.frame_current
    scene.frame_set(1)
    export_scene=bpy.data.scenes.get('SawOperator_Export')
    if export_scene:
        for o in list(export_scene.objects):bpy.data.objects.remove(o,do_unlink=True)
        bpy.data.scenes.remove(export_scene)
    export_scene=bpy.data.scenes.new('SawOperator_Export')
    copies={}
    for original in descendants(root):
        if 'Target' in original.name or original.get('source_preview_only',False):continue
        copy=original.copy()
        copy.animation_data_clear()
        if original.data:copy.data=original.data.copy()
        export_scene.collection.objects.link(copy);copies[original]=copy
    for original,copy in copies.items():
        copy.parent=copies.get(original.parent)
        for mod in copy.modifiers:
            if mod.type=='ARMATURE':mod.object=copies.get(mod.object,mod.object)
        for constraint in list(copy.constraints):copy.constraints.remove(constraint)
    eroot=copies[root];eroot.location=(0,0,0);eroot.rotation_euler=(0,0,0)
    # Export canonical rest pivots even after baking the source preview action.
    for original,copy in copies.items():
        if original.name in ['OP_MountFrame']:copy.location=(0,0,0)
        if original.name.startswith(('OP_Lever_','OP_Needle_')) or original.name in ['OP_Cover','OP_Toggle','OP_Dial']:
            copy.rotation_euler=(0,0,0)
        if original.name.startswith('OP_Pedal_'):copy.rotation_euler=(math.radians(22),0,0)
    erig=copies[rig];erig.animation_data_clear()
    for pb in erig.pose.bones:
        for c in list(pb.constraints):pb.constraints.remove(c)
        pb.matrix_basis=Matrix.Identity(4)
    bpy.context.window.scene=export_scene
    bpy.context.view_layer.update()
    # glTF retains original semantic names after removing temporary copy suffixes.
    rename={o:o.name for o in copies}
    for original in copies:original.name='SOURCE_'+rename[original]
    for original,copy in copies.items():copy.name=rename[original]
    # Join static objects by material and parent; preserve all moving assemblies.
    groups={}
    for o in list(export_scene.objects):
        if o.type in ['MESH','CURVE','FONT'] and not any(m.type=='ARMATURE' for m in o.modifiers) and not getattr(o.data,'shape_keys',None):
            key=(o.parent,o.data.materials[0] if len(o.data.materials) else None)
            groups.setdefault(key,[]).append(o)
    for (parent,mat),objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in objects:o.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        bpy.ops.object.convert(target='MESH')
        bpy.ops.object.join()
        bpy.context.object.name=(parent.name if parent else 'OP')+'_'+(mat.name if mat else 'Mesh')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=ASSET+'/saw_operator.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_animations=False,export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
    report={'objects':len(export_scene.objects),'meshes':sum(o.type=='MESH' for o in export_scene.objects),'bytes':os.path.getsize(ASSET+'/saw_operator.glb')}
    bpy.context.window.scene=scene
    # Restore source names after removing export-only copies.
    for o in list(export_scene.objects):bpy.data.objects.remove(o,do_unlink=True)
    bpy.data.scenes.remove(export_scene)
    for original,name in rename.items():original.name=name
    scene.frame_set(saved_frame)
    save_workbench()
    open(OUT+'/export.json','w').write(json.dumps(report,indent=2))
    result=report

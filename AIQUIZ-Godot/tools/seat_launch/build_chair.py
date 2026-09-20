"""Run stages via live Higgsfield Bridge. Existing geometry is only reparented.

chair_stage: blockout, detail. Export through tools/saw_operator/build_station.py.
"""
import bpy, math, json
from mathutils import Matrix, Vector
STAGE=globals().get('chair_stage','blockout')
ROOT='C:/AIQUIZ/AIQUIZ-Godot'
scene=bpy.context.scene
assert scene.name=='SawOperator_Workbench'
station=bpy.data.objects['OperatorStation']

def empty(name,parent,loc=(0,0,0)):
    assert name not in bpy.data.objects, name
    o=bpy.data.objects.new(name,None);scene.collection.objects.link(o)
    o.parent=parent;o.location=loc;o.empty_display_size=.04
    return o

def mat(name,color,metal,rough):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes=True;m.diffuse_color=(*color,1)
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m

def mesh(name,vertices,faces,material,parent,loc=(0,0,0),bevel=0):
    me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(vertices,[],faces);me.update()
    o=bpy.data.objects.new(name,me);scene.collection.objects.link(o)
    o.parent=parent;o.location=loc;me.materials.append(material)
    if bevel:
        b=o.modifiers.new('Edge radius','BEVEL');b.width=bevel;b.segments=3
        o.modifiers.new('Corner normals','WEIGHTED_NORMAL')
    return o

def box(name,loc,size,material,parent,bevel=.004):
    x,y,z=[v/2 for v in size]
    return mesh(name,[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],material,parent,loc,bevel)

def lathe(name,profile,loc,material,parent):
    n=32
    vertices=[(r*math.cos(i*math.tau/n),r*math.sin(i*math.tau/n),z) for r,z in profile for i in range(n)]
    faces=[(j*n+i,j*n+(i+1)%n,((j+1)%len(profile))*n+(i+1)%n,((j+1)%len(profile))*n+i) for j in range(len(profile)) for i in range(n)]
    return mesh(name,vertices,faces,material,parent,loc,.0015)

def belt_point(t):
    return Vector((.345-.690*t,.10-.247*math.sin(math.pi*t),1.465))

def ribbon(extension):
    vs=[]
    for i in range(33):
        t=i/32*max(.025,extension);p=belt_point(t)
        tangent=(belt_point(min(1,t+.001))-belt_point(max(0,t-.001))).normalized()
        normal=Vector((-tangent.y,tangent.x,0))*.004
        for width,height in [(-1,-.05),(1,-.05),(1,.05),(-1,.05)]:
            vs.append(tuple(p+normal*width+Vector((0,0,height))))
    return vs

if STAGE=='blockout':
    flight=empty('OP_SeatFlightRoot',station)
    names=['OP_SeatCushion','OP_SeatBack','OP_SeatPiping','OP_BackSeam-0.33','OP_BackSeam0.33','Rig']
    for name in names:
        o=bpy.data.objects[name];assert o.parent==station
        basis=o.matrix_basis.copy();o.parent=flight;o.matrix_parent_inverse=Matrix.Identity(4);o.matrix_basis=basis
    socket=empty('OP_SeatSocket',station)
    kit=empty('SL_Kit',flight)
    webmat=mat('SL_Webbing',(.96,.55,.024),0,.88)
    metal=mat('SL_Metal',(.4,.45,.49),.82,.30)
    dark=mat('SL_Heatshield',(.03,.04,.05),.6,.42)
    red=mat('SL_ReleaseRed',(.70,.025,.015),0,.46)
    faces=[(0,3,2,1),(128,129,130,131)]+[(i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j) for i in range(32) for j in range(4)]
    web=mesh('SL_LapWebbing',ribbon(1),faces,webmat,kit)
    web.shape_key_add(name='Basis')
    for name,extension in [('Retracted',0),('Quarter',.25),('Half',.5),('ThreeQuarter',.75)]:
        key=web.shape_key_add(name=name);key.value=0.0
        for v,co in zip(key.data,ribbon(extension)):v.co=co
    web.data.shape_keys.key_blocks['Retracted'].value=1
    reel=empty('SL_Reel',kit,(.365,.12,1.465))
    box('SL_ReelHousing',(0,0,0),(.095,.13,.16),dark,reel)
    receiver=empty('SL_Receiver',kit,(-.360,.09,1.465))
    box('SL_ReceiverHousing',(0,0,0),(.11,.085,.15),dark,receiver)
    box('SL_ReleaseButton',(0,-.048,.014),(.062,.013,.065),red,receiver)
    tongue=empty('SL_Tongue',kit,belt_point(0))
    box('SL_TonguePlate',(0,-.013,0),(.079,.016,.076),metal,tongue)
    for side,x in [('L',.33),('R',-.33)]:
        nozzle=empty('SL_Nozzle_'+side,kit,(x,.30,1.22))
        profile=[(.064,0),(.064,-.025),(.044,-.060),(.040,-.080),(.055,-.140),(.076,-.198),(.076,-.210),(.065,-.210),(.032,-.080),(.036,-.060),(.053,-.024),(.053,0)]
        lathe('SL_Bell_'+side,profile,(0,0,0),dark,nozzle)
        empty('SL_Exhaust_'+side,nozzle,(0,0,-.210))
    lathe('SL_FixedSocket',[(.072,0),(.072,.018),(.043,.018),(.043,0)],(0,.30,1.218),metal,station)
    kit['reference_image']='references/seat_rebuild/chair_only_reference.png'
    kit['belt_direction']='anatomical left +X to right -X; horizontal lap strap'
    result={'stage':STAGE,'reparented':names,'nozzle_clearance_to_deck':.040,'nozzle_clearance_to_bellows':.009,'objects':len(scene.objects)}

if STAGE=='detail':
    kit=bpy.data.objects['SL_Kit'];metal=bpy.data.materials['SL_Metal'];dark=bpy.data.materials['SL_Heatshield']
    for side in ['L','R']:
        nozzle=bpy.data.objects['SL_Nozzle_'+side]
        lathe('SL_Collar_'+side,[(.070,-.008),(.070,-.022),(.063,-.022),(.063,-.008)],(0,0,0),metal,nozzle)
        for i in range(6):
            a=i*math.tau/6
            lathe('SL_Bolt_'+side+str(i),[(.007,0),(.007,.010),(.001,.010),(.001,0)],(.059*math.cos(a),.059*math.sin(a),.001),metal,nozzle)
        for j,(z,r) in enumerate([(-.15,.060),(-.195,.075)]):
            lathe('SL_Rib_'+side+str(j),[(r+.003,z+.004),(r+.003,z-.004),(r,z-.004),(r,z+.004)],(0,0,0),metal,nozzle)
    box('SL_TongueSlot',(0,-.023,0),(.033,.003,.042),dark,bpy.data.objects['SL_Tongue'],.001)
    result={'stage':STAGE,'kit_objects':len(kit.children_recursive)}
bpy.context.view_layer.update()

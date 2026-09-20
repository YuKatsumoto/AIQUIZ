"""Reference v2: precision gated side consoles; preserves all contact pivots.
Execute via Bridge in SawOperator_Workbench after build_station.py/detail.
"""
import bpy,math
from mathutils import Vector
ROOT='C:/AIQUIZ/AIQUIZ-Godot'
exec(open(ROOT+'/tools/saw_operator/build_station.py',encoding='utf-8').read().split("if STAGE=='blockout':")[0])
root=bpy.data.objects['OperatorStation'];scene.frame_set(1)
for o in list(root.children_recursive):
    if o.name.startswith(('OP_V2_','OP_InputIndex_','OP_LeverBoot_')):
        bpy.data.objects.remove(o,do_unlink=True)

def label(name,body,loc,size,parent,rotation=(0,0,0)):
    c=bpy.data.curves.new(name,'FONT');c.body=body;c.size=size;c.align_x='CENTER';c.extrude=.0004
    o=bpy.data.objects.new(name,c);scene.collection.objects.link(o);o.parent=parent;o.location=loc;o.rotation_euler=rotation;c.materials.append(ivory)
    # Editable text converted only in export copies.
    return o

for side,sgn in [('L',1),('R',-1)]:
    lever=bpy.data.objects['OP_Lever_'+side]
    for j in range(4):
        r=.084-j*.012
        loft('OP_V2_Bellows_'+side+str(j),[(.004+j*.024,r*1.8,r*1.8,0),(.014+j*.024,r*2,r*2,0),(.023+j*.024,r*1.6,r*1.6,0)],rubber,lever)
    for x in [-.090,.090]:
        box('OP_V2_Trunnion_'+side+str(x),(sgn*.50+x,-.035,1.464),(.035,.080,.064),steel,root,.008)
        pin=cylinder('OP_V2_Pin_'+side+str(x),(sgn*.50+x,-.035,1.49),.017,.043,dark,root,24);pin.rotation_euler.y=math.pi/2
        cylinder('OP_V2_LockScrew_'+side+str(x),(sgn*.50+x,-.059,1.501),.008,.008,yellow,root,6)
    # A linked position indicator travels in a narrow protected slot beside each lever.
    gx=sgn*.668
    box('OP_V2_GateRim_'+side,(gx,-.025,1.484),(.037,.215,.012),steel,root,.009)
    box('OP_V2_GateSlot_'+side,(gx,-.025,1.491),(.018,.180,.004),rubber,root,.007)
    index=empty('OP_InputIndex_'+side,(gx,-.025,1.5),root)
    box('OP_V2_IndexTab_'+side,(0,0,0),(.032,.020,.022),yellow,index,.004)
    for i,mark in enumerate(['F','N','R'] if side=='L' else ['UP','HOLD','DN']):
        yy=-.104+i*.08
        box('OP_V2_GateTick_'+side+str(i),(gx-sgn*.034,yy,1.489),(.018,.004,.002),ivory,root,.001)
        label('OP_V2_GateText_'+side+str(i),mark,(gx-sgn*.078,yy-.009,1.49),.018,root)
    gauge=bpy.data.objects['OP_GaugeMount_'+side]
    box('OP_V2_InstrumentFrame_'+side,(0,0,-.006),(.253,.253,.014),dark,gauge,.012)
    for x in [-.107,.107]:
        for y in [-.107,.107]:
            cylinder('OP_V2_GaugeBolt_'+side+str(x)+str(y),(x,y,.008),.012,.008,steel,gauge,6)
    label('OP_V2_GaugeLegend_'+side,'RPM' if side=='L' else 'LIFT',(0,-.047,.029),.018,gauge)
    # Front hatch with recessed rim and captive screws.
    box('OP_V2_HatchRim_'+side,(sgn*.55,-.433,1.175),(.228,.017,.300),steel,root,.010)
    box('OP_V2_Hatch_'+side,(sgn*.55,-.444,1.175),(.209,.017,.281),dark,root,.008)
    for x in [-.081,.081]:
        for z in [1.066,1.284]:
            bolt=cylinder('OP_V2_HatchBolt_'+side+str(x)+str(z),(sgn*.55+x,-.456,z),.009,.010,steel,root,8);bolt.rotation_euler.x=math.pi/2
    for y in [.34,.48]:
        box('OP_V2_CableClamp_'+side+str(y),(sgn*.66,y,1.01),(.08,.04,.025),steel,root,.003)
    pedal=bpy.data.objects['OP_Pedal_'+side]
    box('OP_V2_PedalToeStop_'+side,(0,-.243,.034),(.215,.018,.040),rubber,pedal,.006)
    for x in [-.116,.116]:
        bearing=cylinder('OP_V2_PedalBearing_'+side+str(x),(x,0,0),.041,.022,steel,pedal,24);bearing.rotation_euler.y=math.pi/2

# Fonts remain editable in the source, export converts all font geometry.
bpy.context.view_layer.update()
result={'objects':len(root.children_recursive),'reference':'references/v2/02_controls.png'}

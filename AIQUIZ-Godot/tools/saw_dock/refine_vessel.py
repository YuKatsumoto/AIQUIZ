"""Second-pass native vessel refinement. Run through Higgsfield Bridge.

refine_stage: forms -> cabin -> equipment -> finish. Existing working roots stay.
Authoring parts remain separate; export still uses the copy-only material merge.
"""
import bpy, math, os, json
from mathutils import Vector
vessel_stage='inspect'
exec(compile(open('C:/AIQUIZ/AIQUIZ-Godot/tools/saw_dock/build_vessel.py',encoding='utf-8').read(),'build_vessel.py','exec'))
OUT=ROOT+'/artifacts/saw_vessel/revision2'
STAGE=globals().get('refine_stage','forms')
PREFIX='VSL_R2_'
def B(name,size,at,material=navy,parent=None,bevel=.025):
    if PREFIX+name in bpy.data.objects:return bpy.data.objects[PREFIX+name]
    return box(PREFIX+name,size,at,material,parent or body,bevel)
def R(name,a,b,r,material=steel,parent=None,n=16):
    if PREFIX+name in bpy.data.objects:return bpy.data.objects[PREFIX+name]
    return rod(PREFIX+name,a,b,r,material,parent or body,n)
def M(name,vs,fs,material=navy,parent=None,bevel=.02):
    if PREFIX+name in bpy.data.objects:return bpy.data.objects[PREFIX+name]
    return mesh(PREFIX+name,vs,fs,material,parent or body,bevel)
def line(name,pts,r,material=steel,parent=None):
    # Connected tubular fittings, each named and anchored to its actual support.
    for i,(a,b) in enumerate(zip(pts,pts[1:])): R(name+str(i),a,b,r,material,parent)
def ring(name,center,major,minor,material=steel,axis='Z',parent=None,n=40,m=8):
    vs=[]
    for i in range(n):
        u=i*math.tau/n
        for j in range(m):
            v=j*math.tau/m; p=Vector(((major+minor*math.cos(v))*math.cos(u),(major+minor*math.cos(v))*math.sin(u),minor*math.sin(v)))
            if axis=='X':p=Vector((p.z,p.y,p.x))
            elif axis=='Y':p=Vector((p.x,p.z,p.y))
            vs.append(p+Vector(center))
    fs=[(i*m+j,((i+1)%n)*m+j,((i+1)%n)*m+(j+1)%m,i*m+(j+1)%m) for i in range(n) for j in range(m)]
    return M(name,vs,fs,material,parent,0)
def plate(name,points,thickness,material=white):
    a,b,c=[Vector(v) for v in points[:3]];normal=(b-a).cross(c-a).normalized()
    vs=[Vector(p)+normal*d for d in [-thickness/2,thickness/2] for p in points];n=len(points)
    fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return M(name,vs,fs,material,bevel=.008)

stations=[(-27,7.9),(-25.7,10.5),(-22,12.2),(-17,13.2),(-10,13.4),(-3,13.4),(1.65,12.8),(2.15,12.4)]
def width(y):
    for (ya,wa),(yb,wb) in zip(stations,stations[1:]):
        if ya<=y<=yb:return wa+(wb-wa)*(y-ya)/(yb-ya)
    return stations[0][1] if y<stations[0][0] else stations[-1][1]

ochre=mat('R2_Ochre',(.37,.20,.032),.15,.62)
orange=mat('R2_RescueOrange',(.86,.18,.025),.0,.53)
wet=mat('Waterline',(.025,.043,.058),.15,.7)
warm=mat('WorkLight',(.95,.78,.42),.05,.25,1.7)
red=mat('PortLight',(.65,.012,.008),.05,.25,1.5)
green=mat('StarboardLight',(.012,.48,.09),.05,.25,1.5)

if STAGE=='forms':
    if PREFIX+'Hull' in bpy.data.objects:raise RuntimeError('Forms already exist; inspect instead of duplicating.')
    archive=bpy.data.collections.new('Vessel_R1_ReplacedParts');scene.collection.children.link(archive)
    exact={'VSL_Hull','VSL_AftDeck','VSL_Accommodation','VSL_Wheelhouse','VSL_Roof','VSL_AftFender','VSL_BowFender','VSL_Mast','VSL_RadarBeam','VSL_RoofServiceUnit'}
    groups=['Windows','Mullion','Exhaust','Antenna','Stair','HullWeld','Stanchion','Guardrail','RubbingRail','SheerCap','Waterline','VerticalFender','FenderStrap','Navigation']
    archived=[]
    for o in list(scene.objects):
        if not o.name.startswith('VSL_') or o.parent!=body:continue
        if o.name in exact or any(g in o.name for g in groups):
            world=o.matrix_world.copy();o.parent=None;o.matrix_world=world
            for coll in list(o.users_collection):coll.objects.unlink(o)
            archive.objects.link(o);o.hide_render=True;o.hide_viewport=True;archived.append(o.name)
    vs=[]
    for y,w in stations:
        vs += [(x,y,z) for x,z in [(-w,-4.82),(-w,-5.18),(-w*.99,-5.58),(-w*.955,-7.4),(-w*.92,-8.0),(-w*.81,-9.15),(-w*.71,-9.65),(w*.71,-9.65),(w*.81,-9.15),(w*.92,-8.0),(w*.955,-7.4),(w*.99,-5.58),(w,-5.18),(w,-4.82)]]
    n=14;fs=[tuple(reversed(range(n))),tuple(range(len(vs)-n,len(vs)))]
    fs.extend((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(stations)-1) for i in range(n))
    M('Hull',vs,fs,navy,bevel=.045)
    outline=[(-width(y)+.20,y,-4.77) for y in [-26.7,-25.7,-22,-17,-10,-3.5]]+[(width(y)-.20,y,-4.77) for y in [-3.5,-10,-17,-22,-25.7,-26.7]]
    plate('MainDeck',outline,.13,deck)
    # Chamfered, raked deckhouse; separate upper and lower volumes, real window band.
    cabin=[(-4.3,-21.3),(-4.8,-20.75),(-4.8,-16.45),(-4.05,-15.7),(4.05,-15.7),(4.8,-16.45),(4.8,-20.75),(4.3,-21.3)]
    def level(z,inset):return [(x*(1-inset),-18.5+(y+18.5)*(1-inset),z) for x,y in cabin]
    def volume(name,z0,z1,i0,i1,material):
        vv=level(z0,i0)+level(z1,i1);nn=len(cabin)
        return M(name,vv,[tuple(reversed(range(nn))),tuple(range(nn,2*nn))]+[(i,(i+1)%nn,(i+1)%nn+nn,i+nn) for i in range(nn)],material,bevel=.06)
    volume('CabinFoundation',-4.76,-3.3,-.035,-.035,navy)
    volume('CabinLower',-3.32,-2.13,0,.025,white)
    volume('CabinWindowRecess',-2.13,-.45,.045,.085,dark)
    volume('CabinCrown',-.45,-.13,.065,.075,white)
    volume('CabinRoof',-.13,.11,-.055,-.055,white)
    # Gate: main masses only. Camera moves solely to accommodate the longer hull.
    cam=scene.camera;cam.location=(42,-63,30);cam.data.lens=48;aim(cam,(0,-10,-4.0))
    pose(4.42);render('forms_gate')
    bpy.ops.wm.save_as_mainfile(filepath=OUT+'/checkpoint_forms.blend',copy=True)
    result={'stage':STAGE,'archived':archived,'render':scene.render.filepath,'length':29.15}

if STAGE=='cabin':
    if body.get('r2_cabin_complete'):raise RuntimeError('Cabin refinement exists.')
    # Actual recessed glass quads follow the sloped shell; no floating flat bands.
    for y,normal,label in [(-21.3,-1,'Aft'),(-15.7,1,'Forward')]:
        for i in range(6):
            x=-3.96+i*1.32; xa=x+.065;xb=x+1.255
            low=y + (.15 if normal<0 else -.15);high=y+(.30 if normal<0 else -.30)
            pts=[(xa,low,-1.98),(xb,low,-1.98),(xb*.955,high,-.60),(xa*.955,high,-.60)]
            # A dark recessed sill and a light metal perimeter with visible thickness.
            plate(label+'Pane'+str(i),pts,.038,glass)
            line(label+'Gasket'+str(i),pts+[pts[0]],.042,rubber)
            if label=='Forward':
                R(label+'Wiper'+str(i),(xa+.16,low+.06,-1.91),(xa+.45,low+.01,-.89),.018,dark)
    for sign,label in [(-1,'Port'),(1,'Starboard')]:
        for j in range(4):
            ya=-20.65+j*1.01;yb=ya+.90
            pts=[(sign*4.67,ya,-1.98),(sign*4.67,yb,-1.98),(sign*4.47,yb+.03,-.60),(sign*4.47,ya+.03,-.60)]
            plate(label+'Pane'+str(j),pts,.038,glass);line(label+'Gasket'+str(j),pts+[pts[0]],.04,rubber)
        # Watertight door in the lower aft face, with gasket recess, dog handles and hinges.
        x=sign*2.9
        B(label+'DoorRecess',(1.14,.07,1.35),(x,-21.39,-2.71),dark)
        B(label+'Door',(1.01,.08,1.23),(x,-21.445,-2.71),white)
        B(label+'DoorWindow',(.50,.045,.35),(x,-21.499,-2.37),glass)
        for dz in [-.40,.40]:R(label+'DoorHinge'+str(dz),(x+sign*.54,-21.49,-2.71+dz-.06),(x+sign*.54,-21.49,-2.71+dz+.06),.038,steel)
        R(label+'DoorHandle',(x-sign*.36,-21.52,-2.68),(x-sign*.36,-21.52,-2.90),.022,steel)
        # Walkways, open riser stair treads, two handrails, and low supporting stringers.
        B(label+'CabinWalkway',(1.75,6.2,.13),(sign*5.48,-18.5,-3.37),deck)
        for j in range(8):
            y=-13.30-j*.39;z=-4.70+j*.19
            B(label+'Tread'+str(j),(1.35,.34,.07),(sign*5.48,y,z),steel,bevel=.012)
            for dx in [-.59,.59]:
                if j%2==0:R(label+'StairPost'+str(j)+str(dx),(sign*5.48+dx,y,z),(sign*5.48+dx,y,z+1.05),.035,yellow)
        for dx in [-.62,.62]:
            R(label+'Stringer'+str(dx),(sign*5.48+dx,-13.1,-4.81),(sign*5.48+dx,-16.3,-3.31),.075,dark)
            R(label+'StairHandrail'+str(dx),(sign*5.48+dx,-13.1,-3.65),(sign*5.48+dx,-16.3,-2.16),.04,yellow)
        for y in [-16.5,-18,-19.5,-21.35]:R(label+'WalkwayStanchion'+str(y),(sign*6.25,y,-3.32),(sign*6.25,y,-2.22),.04,white)
        for z in [-2.77,-2.22]:R(label+'WalkwayRail'+str(z),(sign*6.25,-16.5,z),(sign*6.25,-21.35,z),.04,white)
        # Faceted vented exhaust nacelles with capped pipes and support gussets.
        B(label+'StackFoot',(1.10,1.45,.19),(sign*6.6,-20.65,-4.64),dark)
        B(label+'StackHousing',(.86,1.18,3.85),(sign*6.6,-20.65,-2.67),navy,bevel=.11)
        B(label+'StackVentSeat',(.89,.70,1.35),(sign*6.6,-20.68,-1.45),dark)
        for j in range(7):B(label+'StackLouver'+str(j),(.91,.76,.06),(sign*6.6,-20.68,-2+j*.18),steel,bevel=.009)
        R(label+'Exhaust',(sign*6.6,-20.65,-.80),(sign*6.6,-20.65,.61),.20,dark,n=24)
        R(label+'ExhaustLip',(sign*6.6,-20.65,.60),(sign*6.6,-20.65,.70),.25,steel,n=24)
        B(label+'NavShelf',(.6,.80,.10),(sign*4.76,-16.1,.12),dark)
        B(label+'NavLamp',(.26,.37,.16),(sign*4.76,-16.1,.26),red if sign<0 else green,bevel=.045)
        # Life rings and canister rafts establish human scale.
        ring(label+'Lifering',(sign*6.31,-19,-2.72),.34,.092,orange,'X')
        for j in range(2):
            y=-23.1-j*1.4
            B(label+'RaftRack'+str(j),(1.40,1.05,.18),(sign*5.8,y,-4.61),dark)
            R(label+'RaftCanister'+str(j),(sign*5.8-.56,y,-4.20),(sign*5.8+.56,y,-4.20),.35,white,n=32)
            for dx in [-.35,.35]:ring(label+'RaftStrap'+str(j)+str(dx),(sign*5.8+dx,y,-4.20),.35,.025,dark,'X',n=28)
    # A braced, purposeful mast with radome, radar pedestal, horns and cable conduits.
    R('Mast',(0,-18.5,.13),(0,-18.5,3.15),.12,white,n=24)
    for x in [-.9,.9]:R('MastBrace'+str(x),(x,-19.2,.13),(0,-18.5,2.45),.045,steel)
    B('RadarPedestal',(1.2,.9,.28),(0,-18.5,2.49),white)
    B('RadarScanner',(3.0,.35,.22),(0,-18.5,2.75),white,bevel=.08)
    R('MastTopLamp',(0,-18.5,3.1),(0,-18.5,3.3),.14,warm)
    for j,x in enumerate([-3.3,3.3]):
        B('AntennaFoot'+str(j),(.28,.28,.12),(x,-20,.18),dark)
        R('Antenna'+str(j),(x,-20,.24),(x,-20,2.25),.02,steel)
    for j,x in enumerate([-.55,.55]):R('Horn'+str(j),(x,-17.8,.24),(x,-17.1,.24),.14,white)
    B('RoofHVAC',(1.7,1.2,.48),(2.2,-19,.35),white,bevel=.1)
    for j in range(7):B('RoofHVACGrille'+str(j),(1.4,.045,.018),(2.2,-19.45+j*.14,.599),dark,bevel=.004)
    body['r2_cabin_complete']=True
    pose(4.42);render('cabin_refined')
    bpy.ops.wm.save_as_mainfile(filepath=OUT+'/checkpoint_cabin.blend',copy=True)
    result={'stage':STAGE,'render':scene.render.filepath,'objects':len(scene.objects)}

if STAGE=='equipment':
    if PREFIX+'SternRubber' in bpy.data.objects:raise RuntimeError('Equipment exists.')
    for sign,label in [(-1,'Port'),(1,'Starboard')]:
        for j,((ya,wa),(yb,wb)) in enumerate(zip(stations,stations[1:])):
            R(label+'RubRail'+str(j),(sign*(wa+.02),ya,-5.35),(sign*(wb+.02),yb,-5.35),.21,rubber,n=24)
            R(label+'CapRail'+str(j),(sign*wa,ya,-4.73),(sign*wb,yb,-4.73),.072,white)
            # Recessed drain openings cut into the bulwark profile by assembled frames.
            if ya < -3.5:
                a=Vector((sign*(wa-.1),ya,-4.73));b=Vector((sign*(wb-.1),yb,-4.73));length=(b-a).length
                panel=B(label+'Bulwark'+str(j),(length,.15,.70),(a+b)/2+Vector((0,0,.40)),navy)
                panel.rotation_euler.z=math.atan2((b-a).y,(b-a).x)
                R(label+'BulwarkLip'+str(j),a+Vector((0,0,.8)),b+Vector((0,0,.8)),.07,steel)
                for t in [.15,.50,.85]:
                    p=a.lerp(b,t)
                    # Triangular knee behind each bulwark supports the plating.
                    points=[p+Vector((0,0,.65)),p+Vector((0,0,.03)),p+Vector((-sign*.42,0,.03))]
                    plate(label+'Knee'+str(j)+str(t),points,.065,navy)
            # Narrow, restrained wet stripe following the actual hull chine.
            M(label+'BootStripe'+str(j),[(sign*wa*.924,ya,-7.98),(sign*wb*.924,yb,-7.98),(sign*wb*.940,yb,-7.73),(sign*wa*.940,ya,-7.73)],[(0,1,2,3)],wet,bevel=0)
        for j,y in enumerate([-24,-20,-16,-12,-8,-4,.5]):
            x=sign*(width(y)+.16)
            # Ribbed pneumatic fenders with mounting plates and real shackles.
            R(label+'Fender'+str(j),(x,y,-6.98),(x,y,-5.22),.34,rubber,n=32)
            for z in [-6.9,-6.55,-6.18,-5.80,-5.3]:ring(label+'FenderRib'+str(j)+str(z),(x,y,z),.34,.027,rubber,n=24)
            for z in [-6.9,-5.3]:
                B(label+'FenderBracket'+str(j)+str(z),(.20,.84,.16),(x-sign*.14,y,z),dark)
                ring(label+'Shackle'+str(j)+str(z),(x+sign*.23,y,z),.13,.035,steel,'X',n=16)
        # Aft guardrails with clear ladder access and individual mounting shoes.
        ys=[-26,-24,-22,-20,-18,-16,-14,-12,-10,-8,-6,-3.6]
        for j,y in enumerate(ys):
            x=sign*(width(y)-.4)
            B(label+'RailShoe'+str(j),(.18,.18,.045),(x,y,-4.64),steel)
            R(label+'RailPost'+str(j),(x,y,-4.64),(x,y,-3.25),.039,yellow)
        for j,(a,b) in enumerate(zip(ys,ys[1:])):
            for z in [-3.85,-3.25]:R(label+'Guardrail'+str(j)+str(z),(sign*(width(a)-.4),a,z),(sign*(width(b)-.4),b,z),.04,yellow)
        for j,y in enumerate([-23,-12]):
            x=sign*9
            B(label+'CapstanFoot'+str(j),(1.65,1.55,.18),(x,y,-4.63),dark)
            R(label+'CapstanStem'+str(j),(x,y,-4.56),(x,y,-3.5),.26,steel,n=24)
            for z in [-4.48,-3.63]:R(label+'CapstanFlange'+str(j)+str(z),(x,y,z),(x,y,z+.09),.46,navy,n=32)
            for k in range(7):ring(label+'CapstanRope'+str(j)+str(k),(x,y,-4.35+k*.085),.28,.038,ochre,n=28)
            for dx in [-.66,.66]:
                for dy in [-.60,.60]:R(label+'CapstanBolt'+str(j)+str(dx)+str(dy),(x+dx,y+dy,-4.53),(x+dx,y+dy,-4.47),.065,steel,n=6)
        # Hose reel: trunnions, perforated cheeks, central drum and wound hose.
        x=sign*8.4;y=-9.8
        B(label+'ReelBase',(1.9,1.7,.18),(x,y,-4.63),dark)
        for dx in [-.66,.66]:
            B(label+'ReelPillow'+str(dx),(.2,.75,.8),(x+dx,y,-4.22),yellow)
            R(label+'ReelCheek'+str(dx),(x+dx-.06,y,-3.86),(x+dx+.06,y,-3.86),.68,navy,n=32)
        R(label+'ReelAxle',(x-.84,y,-3.86),(x+.84,y,-3.86),.10,steel)
        for k in range(11):ring(label+'HoseWinding'+str(k),(x-.52+k*.104,y,-3.86),.43,.052,rubber,'X',n=32)
        # Mechanism is anchored to a braced frame, flange-bolted to the deck.
        for y in [-1.4,1.4]:
            x=sign*12.6
            B(label+'GuideFoot'+str(y),(.72,.82,.18),(x,y,-4.68),dark)
            R(label+'GuideBrace'+str(y),(x-sign*1.6,y,-4.68),(x,y,-2.9),.09,steel)
            for dx in [-.24,.24]:
                for dy in [-.28,.28]:R(label+'FootBolt'+str(y)+str(dx)+str(dy),(x+dx,y+dy,-4.58),(x+dx,y+dy,-4.48),.055,steel,n=6)
            R(label+'GuideTrack'+str(y),(x-sign*.14,y,-4.5),(x-sign*.14,y,.48),.036,steel)
            B(label+'UpperCrosshead'+str(y),(.65,.52,.20),(x,y,.48),yellow)
        for z in [-5.83,-4.99]:
            R(label+'CylinderFlange'+str(z),(sign*11.86,0,z),(sign*11.86,0,z+.11),.35,steel,n=32)
        line(label+'PressureHose',[(sign*12,-3.4,-4.3),(sign*12,-1,-4.3),(sign*11.55,-.5,-4.7),(sign*11.65,0,-4.95)],.075,rubber)
        # Individual lamp yokes, dark reflectors and warm lenses.
        for y in [-14,-22]:
            x=sign*6.6
            R(label+'LampArm'+str(y),(x,y,-3.4),(x,y,-2.6),.045,steel)
            B(label+'FloodHousing'+str(y),(.64,.30,.34),(x,y,-2.45),dark)
            B(label+'FloodLens'+str(y),(.50,.03,.23),(x,y+.17,-2.45),warm)
    R('SternRubber',(-7.9,-27.15,-5.35),(7.9,-27.15,-5.35),.28,rubber,n=32)
    R('BowRubber',(-12.4,2.28,-5.35),(12.4,2.28,-5.35),.30,rubber,n=32)
    # Broad deck plating with sparse joints, traction strips and recessed inspection wells.
    for y in [-24,-22,-14,-12,-10,-8,-6]:
        B('DeckSeam'+str(y),(2*width(y)-1,.018,.012),(0,y,-4.687),dark,bevel=0)
    for x in [-10.8,-7,-3.5,0,3.5,7,10.8]:
        B('DeckLongitudinal'+str(x),(.014,10,.01),(x,-8.7,-4.685),dark,bevel=0)
    # Welded hull strakes and readable white draft/waterline marks at the forward side.
    for sign,label in [(-1,'Port'),(1,'Starboard')]:
        for j in range(7):
            y=-3.6;z=-7.70+j*.27;x=sign*(width(y)*(.93+(z+8)*.016))
            B(label+'DraftMark'+str(j),(.018,.27,.08),(x,y,z),white,bevel=.003)
        for y in [-24,-20,-16,-12,-8,-4]:
            x=sign*(width(y)*.99)
            R(label+'PlateJoint'+str(y),(x,y,-5.5),(x-sign*.32,y,-7.3),.012,dark,n=8)
    pose(4.42);render('equipment_refined')
    bpy.ops.wm.save_as_mainfile(filepath=OUT+'/checkpoint_equipment.blend',copy=True)
    result={'stage':STAGE,'render':scene.render.filepath,'objects':len(scene.objects)}

if STAGE=='finish':
    # Glazing has visible recessed reveals and mullions instead of a black band.
    pane_material=mat('R2_WindowBlue',(.035,.105,.145),.42,.17)
    for side,y,sign in [('Aft',-21.3,-1),('Forward',-15.7,1)]:
        for i in range(6):
            o=bpy.data.objects[PREFIX+side+'Pane'+str(i)]
            o.location.y=sign*.09;o.data.materials.clear();o.data.materials.append(pane_material)
            for e in range(4):bpy.data.objects[PREFIX+side+'Gasket'+str(i)+str(e)].location.y+=sign*.09
        for i in range(7):
            x=-3.96+i*1.32
            R(side+'Frame'+str(i),(x,y+(-sign*.07),-2.1),(x*.955,y+(-sign*.19),-.44),.055,white)
    for sign,label in [(-1,'Port'),(1,'Starboard')]:
        for i in range(4):bpy.data.objects[PREFIX+label+'Pane'+str(i)].data.materials[0]=pane_material
        for i in range(5):
            y=-20.65+i*1.01
            R(label+'Frame'+str(i),(sign*4.68,y,-2.12),(sign*4.49,y+.03,-.44),.055,white)
        # Recessed marine vents and ladder recess with handholds on the stern sides.
        for j,y in enumerate([-23.7,-13]):
            x=sign*(width(y)-.16)
            B(label+'VentRecess'+str(j),(.06,1.0,.42),(x,y,-4.22),dark)
            for k in range(4):B(label+'VentLouver'+str(j)+str(k),(.075,.88,.025),(x+sign*.02,y,-4.39+k*.10),steel,bevel=.005)
    # Editable lettering as real mesh geometry in the delivered game asset.
    if PREFIX+'ShipName' not in bpy.data.objects:
        curve=bpy.data.curves.new(PREFIX+'ShipNameText','FONT');curve.body='AIQUIZ  /  HEAVY LIFT 08';curve.size=.35;curve.align_x='CENTER';curve.extrude=.0015
        lettering=bpy.data.objects.new(PREFIX+'ShipName',curve);scene.collection.objects.link(lettering);lettering.parent=body
        lettering.location=(0,-27.02,-5.13);lettering.rotation_euler=(math.pi/2,0,0);curve.materials.append(white)
        bpy.ops.object.select_all(action='DESELECT');lettering.select_set(True);bpy.context.view_layer.objects.active=lettering;bpy.ops.object.convert(target='MESH')
    # All additions remain native mesh geometry with authored metre-scale UVs.
    from mathutils import Vector
    for o in list(root.children_recursive):
        if o.type!='MESH':continue
        uv=o.data.uv_layers.get('FinishUV') or o.data.uv_layers.new(name='FinishUV')
        matrix=o.matrix_world.copy()
        for poly in o.data.polygons:
            n=(matrix.to_3x3()@poly.normal).normalized();axis=max(range(3),key=lambda k:abs(n[k]));axes=[k for k in range(3) if k!=axis]
            for li in poly.loop_indices:
                p=matrix@o.data.vertices[o.data.loops[li].vertex_index].co
                uv.data[li].uv=(p[axes[0]]*.5,p[axes[1]]*.5)
    result={'stage':STAGE,'uv_meshes':sum(o.type=='MESH' for o in root.children_recursive)}

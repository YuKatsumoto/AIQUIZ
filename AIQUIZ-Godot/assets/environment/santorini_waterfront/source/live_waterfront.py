"""Run individual phases inside the connected, visible Blender instance.

No factory reset, background process, paid generation, or active-file save.
Checkpoint copies keep the user's original Scene and active filepath intact.
"""
import bpy, bmesh, math, json, ast, hashlib
from pathlib import Path
from mathutils import Vector, Matrix
from collections import defaultdict

ROOT = Path('C:/AIQUIZ/AIQUIZ-Godot')
OUT = ROOT / 'assets/environment/santorini_waterfront'
EVIDENCE = ROOT / 'artifacts/santorini_waterfront'
SEA, BED, DECK, QUAY = -9.2, -17.2, 1.52, -5.16
SCENE = 'Santorini Waterfront Design'
MODULES = 'Santorini Waterfront Modules'

def checkpoint(label):
    p = EVIDENCE / ('20260914_' + label + '.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(p), copy=True)
    return str(p)

def coll(name, scene):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        scene.collection.children.link(c)
    return c

def mat(name, color, rough=.8):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bs = next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Roughness'].default_value = rough
    return m

def setup():
    s = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    assert not s.objects, 'Already imported; inspect before retry'
    mods = bpy.data.scenes.get(MODULES) or bpy.data.scenes.new(MODULES)
    bpy.context.window.scene = s
    s.unit_settings.system = 'METRIC'
    s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x, s.render.resolution_y = 1280,720
    s.render.resolution_percentage = 100
    s.render.fps = 24
    s.frame_start, s.frame_end = 1,144
    s.view_settings.view_transform = 'AgX'
    s.view_settings.exposure = 0
    s.world = bpy.data.worlds.get('ENV_WaterfrontDayWorld') or bpy.data.worlds.new('ENV_WaterfrontDayWorld')
    s.world.use_nodes = True
    bg=next(n for n in s.world.node_tree.nodes if n.type=='BACKGROUND')
    bg.inputs[0].default_value = (.55,.68,.80,1)
    bg.inputs[1].default_value = .45
    with bpy.data.libraries.load(str(ROOT/'assets/environment/santorini_town/source/aiquiz_santorini_town.blend'),link=False) as (a,b):
        b.objects = [n for n in a.objects if '__Terrain' in n or '__Architecture' in n or '__Gardens' in n]
    c=coll('REF_Town_13_Districts',s)
    for o in b.objects:
        c.objects.link(o)
        o.location.z = SEA
        o['waterfront_role']='existing_town'
    with bpy.data.libraries.load(str(ROOT/'assets/environment/santorini_grandstand/source/santorini_open_terrace.blend'),link=False) as (a,b):
        b.collections=['Santorini terrace - editable geometry']
    stand=b.collections[0]
    stand.name='SOURCE_GroundedStand'
    mods.collection.children.link(stand)
    for side in (-1,1):
        c=coll('REF_StandLeft' if side<0 else 'REF_StandRight',s)
        root=bpy.data.objects.new('REF_StandLeftAnchor' if side<0 else 'REF_StandRightAnchor',None)
        c.objects.link(root)
        root.location=(side*28,-4,0)
        root.rotation_euler.z=math.pi if side<0 else 0
        for orig in stand.all_objects:
            if orig.type!='MESH':continue
            o=bpy.data.objects.new(('REF_Left_' if side<0 else 'REF_Right_')+orig.name,orig.data)
            c.objects.link(o);o.parent=root
    rig=coll('REVIEW_CameraLighting',s)
    cam=bpy.data.objects.new('CAM_AccessSurvey',bpy.data.cameras.new('CAM_AccessSurveyData'))
    rig.objects.link(cam);s.camera=cam
    cam.data.lens=42;cam.data.clip_end=6000
    aim_camera((78,105,62),(72,-26,-2))
    ld=bpy.data.lights.new('LGT_DayData','SUN');ld.energy=2.2;ld.angle=.14
    light=bpy.data.objects.new('LGT_Day',ld);rig.objects.link(light)
    light.rotation_euler=(.45,-.4,-.5)
    # Source-only conveyor envelope agrees with StageConstants; never exported.
    g=geometry();g.box((0,-4,-9.2),(24,160,16),5,'conveyor envelope')
    make(g,'REF_ConveyorEnvelope',coll('REF_Conveyor',s))
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.clip_end=6000
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.shading.color_type='MATERIAL'
    bpy.context.view_layer.update()
    return {'scene':s.name,'town_objects':len(bpy.data.collections['REF_Town_13_Districts'].objects),'stand_sections':len([o for o in stand.all_objects if o.type=='MESH']),'protected_scene_objects':[o.name for o in bpy.data.scenes['Scene'].objects]}

def aim_camera(pos,target):
    cam=bpy.data.objects['CAM_AccessSurvey']
    cam.location=pos
    cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()

def palette():
    names=['Cycladic chalk plaster','Limestone coping','Aegean cobalt painted wood','Aegean blue seat highlights','Warm stone paving','Volcanic sea footings','Sunwashed pergola timber','Terracotta pots','Olive and bougainvillea foliage','Bougainvillea flowers','Bougainvillea pale petals','Lantern dark brass','Lantern warm glass']
    return [bpy.data.materials[n] for n in names]

def geometry():
    # Reuse the existing authored beveled stone/beam construction without
    # executing its destructive scene setup or its export/render entrypoint.
    path=ROOT/'assets/environment/santorini_grandstand/source/build_santorini_grandstand.py'
    tree=ast.parse(path.read_text(encoding='utf-8-sig'))
    cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='Geometry')
    ns={'Vector':Vector,'math':math,'defaultdict':defaultdict}
    exec(compile(ast.Module(body=[cls],type_ignores=[]),str(path),'exec'),ns)
    return ns['Geometry']()

def make(g,name,collection,mats=None):
    assert name not in bpy.data.objects,name
    mesh=bpy.data.meshes.new(name+'Mesh')
    mesh.from_pydata(g.v,[],g.f)
    for m in mats or palette():mesh.materials.append(m)
    for p,i in zip(mesh.polygons,g.m):p.material_index=i
    mesh.update()
    o=bpy.data.objects.new(name,mesh);collection.objects.link(o)
    o['waterfront_role']='authored'
    return o

def foundations():
    s=bpy.data.scenes[SCENE]; c=coll('ENV_DistrictFoundations',s)
    report=[]
    for o in bpy.data.collections['REF_Town_13_Districts'].objects:
        if not o.name.endswith('__Terrain'):continue
        m=o.data
        # The original base prism is a closed island. Find its downward base
        # face by its normal and lowest plane, then copy its exact perimeter.
        faces=[p for p in m.polygons if p.normal.z<-.99 and all(abs(m.vertices[i].co.z+5)<.001 for i in p.vertices)]
        assert len(faces)==1,(o.name,len(faces))
        p=faces[0]
        ring=[o.matrix_world@m.vertices[i].co for i in reversed(p.vertices)]
        n=len(ring);v=[(q.x,q.y,z) for z in (BED,SEA-5) for q in ring]
        f=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        g=geometry();g.mesh(v,f,0,'district bed extension')
        obj=make(g,'ENV_'+o.name.replace('__Terrain','_Foundation'),c,[m.materials[p.material_index]])
        report.append({'name':obj.name,'top':SEA-5,'bottom':BED,'vertices':len(v),'old_terrain_unchanged':True})
    sand=mat('Seabed muted limestone sand',(.32,.37,.33),.96)
    g=geometry();g.box((0,-150,BED-2),(4000,4000,4),0,'continuous sea bed')
    make(g,'ENV_Seabed',c,[sand])
    (EVIDENCE/'foundations.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    return {'foundations':len(report),'seabed_top':BED,'conveyor_contact_gap':0.0}

def mesh_islands(mesh):
    parent=list(range(len(mesh.vertices)))
    def root(i):
        while parent[i]!=i:
            parent[i]=parent[parent[i]];i=parent[i]
        return i
    for e in mesh.edges:
        a,b=map(root,e.vertices);parent[b]=a
    groups=defaultdict(list)
    for v in mesh.vertices:groups[root(v.index)].append(v.index)
    return list(groups.values())

def grounded_stand():
    c=bpy.data.collections['SOURCE_GroundedStand'];reports=[]
    for o in c.all_objects:
        if o.type!='MESH':continue
        mesh=o.data; before=len(mesh.vertices);footings=0;columns=0;removed=[]
        # Islands match authored columns/footings and rear rails, never a broad
        # coordinate-box deletion through the entire seating mesh.
        for ids in mesh_islands(mesh):
            vs=[mesh.vertices[i] for i in ids]
            lo=Vector([min(v.co[k] for v in vs) for k in range(3)])
            hi=Vector([max(v.co[k] for v in vs) for k in range(3)])
            size=hi-lo;mid=(hi+lo)*.5
            if abs(size.z-9.8)<.01 and abs(size.x-.70)<.01 and abs(size.y-.72)<.01:
                for v in vs:
                    if v.co.z<mid.z:v.co.z-=7.2
                columns+=1
            elif abs(size.z-2.2)<.01 and abs(size.x-1.15)<.01 and abs(size.y-1.2)<.01:
                for v in vs:v.co.z-=7.2
                footings+=1
            elif abs(mid.x-8.18)<.01 and (abs(size.y-20)<.01 or abs(size.z-.88)<.01):
                # Rear continuous rails are replaced with an opening at every
                # pre-existing aisle; the front rail and seat rails stay intact.
                if abs(size.y-20)<.01 or any(abs(mid.y-a)<1.15 for a in (-60,-40,-20,0,20,40,60)):
                    removed.extend(ids)
        assert columns in (2,4) and footings==columns,(o.name,columns,footings)
        bm=bmesh.new();bm.from_mesh(mesh);bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm,geom=[bm.verts[i] for i in removed],context='VERTS')
        bm.to_mesh(mesh);bm.free();mesh.update()
        reports.append({'section':o.name,'columns_extended':columns,'footings_lowered':footings,'removed_rear_rail_vertices':len(removed),'vertex_count_before':before,'vertex_count_after':len(mesh.vertices)})
    g=geometry()
    cuts=[-80,-61.15,-58.85,-41.15,-38.85,-21.15,-18.85,-1.15,1.15,18.85,21.15,38.85,41.15,58.85,61.15,80]
    for a,b in zip(cuts[::2],cuts[1::2]):
        for h in (1.88,2.40):g.box((8.18,(a+b)*.5,h),(.065,b-a,.07),2,'open entry rear rail')
    for y in (-60,-40,-20,0,20,40,60):
        for sign in (-1,1):g.box((8.18,y+sign*1.17,1.96),(.13,.13,.88),2,'entry gate end post',.02)
    o=make(g,'PRP_StandEntryRails',c)
    for name in ('REF_StandLeft','REF_StandRight'):
        target=bpy.data.collections[name];anchor=next(a for a in target.objects if a.type=='EMPTY')
        dup=bpy.data.objects.new(name+'_EntryRails',o.data);target.objects.link(dup);dup.parent=anchor
    (EVIDENCE/'stand_modifications.json').write_text(json.dumps(reports,indent=2),encoding='utf8')
    return {'sections':len(reports),'columns_extended':sum(r['columns_extended'] for r in reports),'footings_lowered':sum(r['footings_lowered'] for r in reports),'base':BED,'rear_gate_width':2.3}

def supports(g,x,top,half_width=1.45):
    for y in (-half_width,half_width):
        g.box((x,y,(BED+top)/2),(.46,.50,top-BED),0,'white structural pier',.045)
        g.box((x,y,BED+.85),(.86,.94,1.70),5,'volcanic bed footing',.06)
        g.box((x,y,top-.14),(.68,.74,.28),1,'pier capital',.05)

def flight(g,x,z,drop):
    n=18;run=.34
    profile=[(x,z)]
    for i in range(n):
        profile.append((x+i*run,z-(i+1)*drop/n))
        profile.append((x+(i+1)*run,z-(i+1)*drop/n))
    profile.extend([(x+n*run,z-drop-.40),(x,z-.40)])
    v=[(xx,y,zz) for y in (-1.8,1.8) for xx,zz in profile]
    m=len(profile)
    f=[tuple(range(m-1,-1,-1)),tuple(range(m,2*m))]+[(i,(i+1)%m,(i+1)%m+m,i+m) for i in range(m)]
    g.mesh(v,f,0,'continuous stair flight')

def stair_structure():
    c=coll('MODULE_AccessStair',bpy.data.scenes[MODULES]);g=geometry()
    # Flared top landing: narrow at the existing 2.3m gate, broad at the stair.
    poly=[(8.15,-1.12),(9.2,-1.12),(11.35,-1.8),(11.35,1.8),(9.2,1.12),(8.15,1.12)]
    v=[(x,y,z) for z in (DECK-.4,DECK) for x,y in poly];n=len(poly)
    g.mesh(v,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],0,'flared entry landing')
    drop=(DECK-QUAY)/2
    flight(g,11.35,DECK,drop)
    g.box((18.67,0,DECK-drop-.2),(2.4,3.6,.4),0,'middle resting landing',.04)
    flight(g,19.87,DECK-drop,drop)
    g.box((27.49,0,QUAY-.2),(3,3.6,.4),0,'lower resting landing',.04)
    supports(g,10.1,DECK-.4,1.05);supports(g,18.67,DECK-drop-.4);supports(g,27.49,QUAY-.4)
    o=make(g,'PRP_AccessStair_Structure',c)
    o['steps']=36;o['riser']=(DECK-QUAY)/36;o['tread']=.34;o['entry_x']=8.18;o['exit_x']=28.99
    return {'name':o.name,'steps':36,'riser':o['riser'],'entry_height':DECK,'exit_height':QUAY}

def pier_structure():
    c=coll('MODULE_PierBay',bpy.data.scenes[MODULES]);g=geometry()
    g.box((2,0,QUAY-.21),(4,3.6,.42),0,'pier slab',.045)
    supports(g,.25,QUAY-.42)
    o=make(g,'PRP_PierBay_Structure',c)
    return {'name':o.name,'length':4,'width':3.6,'top':QUAY,'bottom':BED}

def gateway_structure():
    c=coll('MODULE_QuayGateway',bpy.data.scenes[MODULES]);g=geometry()
    g.box((-.8,0,QUAY-.2),(3.2,4.5,.4),0,'town arrival landing',.06)
    for y in (-1.85,1.85):g.box((-1.3,y,QUAY+1.12),(.55,.46,2.24),0,'entry arch upright',.07)
    for i in range(20):
        a=i*math.pi/20;b=(i+1)*math.pi/20
        q=[(1.62*math.cos(a),QUAY+2.24+1.62*math.sin(a)),(1.62*math.cos(b),QUAY+2.24+1.62*math.sin(b)),(2.08*math.cos(b),QUAY+2.24+2.08*math.sin(b)),(2.08*math.cos(a),QUAY+2.24+2.08*math.sin(a))]
        v=[(x,y,z) for x in (-1.575,-1.025) for y,z in q]
        g.mesh(v,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],0,'continuous gateway arch')
    o=make(g,'PRP_QuayGateway_Structure',c)
    return {'name':o.name,'opening_width':3.24,'opening_spring_height':2.24,'landing_top':QUAY}

def preview_connections():
    s=bpy.data.scenes[SCENE];c=coll('REF_ConnectedAccess',s)
    layout=json.loads((ROOT/'assets/environment/santorini_town/source/build_report.json').read_text())['layout']
    routes=[]
    def instance(collection,tag,x,z,side,sx=1):
        for src in bpy.data.collections[collection].objects:
            name=tag+'_'+src.name
            if name in bpy.data.objects:continue
            o=bpy.data.objects.new(name,src.data);c.objects.link(o)
            o.location=(side*x,-z,0);o.rotation_euler.z=math.pi if side<0 else 0;o.scale.x=sx
    for side in (-1,1):
        for z in (-56.,64.):
            tag=('West' if side<0 else 'East')+'_'+str(int(z))
            district=min([d for d in layout if d['name'].startswith('West' if side<0 else 'East')],key=lambda d:abs(d['godot_origin'][2]-z))
            end=abs(district['godot_origin'][0])+5.0
            instance('MODULE_AccessStair',tag+'_Stair',28,z,side)
            start=28+28.99;length=end-start
            n=math.ceil(length/4);step=length/n
            for i in range(n):instance('MODULE_PierBay',tag+'_Bay'+str(i),start+i*step,z,side,step/4)
            instance('MODULE_QuayGateway',tag+'_Gateway',end,z,side)
            routes.append({'side':side,'z':z,'district':district['name'],'entry_x':side*36.18,'quay_x':side*end,'bay_count':n,'bay_length':step})
    (EVIDENCE/'blender_preview_routes.json').write_text(json.dumps(routes,indent=2),encoding='utf8')
    aim_camera((38,80,29),(78,-35,-4))
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.region_3d.view_camera_zoom=12
    return routes

def rail_segment(g,a,b,width=.07):
    g.beam(a,b,width,2,'cobalt handrail')

def access_detail():
    c=bpy.data.collections['MODULE_AccessStair'];g=geometry();drop=(DECK-QUAY)/2
    path=[(8.18,1.12,DECK),(9.2,1.12,DECK),(11.35,1.8,DECK),(17.47,1.8,DECK-drop),(19.87,1.8,DECK-drop),(25.99,1.8,QUAY),(28.99,1.8,QUAY)]
    for sign in (-1,1):
        for a,b in zip(path,path[1:]):
            for height in (.52,1.08):rail_segment(g,(a[0],sign*a[1],a[2]+height),(b[0],sign*b[1],b[2]+height))
            count=max(1,math.ceil((b[0]-a[0])/1.8))
            for i in range(count):
                t=i/count;x=a[0]+(b[0]-a[0])*t;y=sign*(a[1]+(b[1]-a[1])*t);z=a[2]+(b[2]-a[2])*t
                g.box((x,y,z+.54),(.10,.10,1.08),2,'stair baluster',.015)
    for x,z in ((11.35,DECK),(19.87,DECK-drop)):
        for i in range(18):
            height=z-(i+1)*drop/18
            g.box((x+i*.34+.045,0,height+.012),(.09,3.55,.024),1,'limestone stair nosing',.012)
    for x,z,length,width in ((10.1,DECK,1.8,2.0),(18.67,DECK-drop,2.2,3.3),(27.49,QUAY,2.8,3.3)):
        g.box((x,0,z+.012),(length,width,.024),4,'landing inset paving',.10)
    o=make(g,'PRP_AccessStair_RailsAndNosing',c)
    return {'name':o.name,'continuous_side_rails':True,'entry_open':True}

def pier_detail():
    c=bpy.data.collections['MODULE_PierBay'];g=geometry()
    for y in (-1.72,1.72):
        for h in (.5,1.08):g.box((2,y,QUAY+h),(4,.065,.07),2,'pier blue handrail')
        for x in (.20,2.0,3.8):g.box((x,y,QUAY+.54),(.09,.09,1.08),2,'pier railing post',.015)
        g.box((2,y,QUAY+.04),(4,.20,.08),1,'pier stone edge',.025)
    for i in range(4):
        for y in (-.78,.78):g.box((i+.5,y,QUAY+.012),(.90,1.40,.024),4 if i%2 else 1,'pier irregular inset paving',.08)
    for y in (-1.45,1.45):
        g.beam((.25,y,QUAY-1.5),(2.2,y,QUAY-.44),.15,1,'under deck diagonal brace')
    return {'name':make(g,'PRP_PierBay_RailsAndPaving',c).name}

def gateway_detail():
    c=bpy.data.collections['MODULE_QuayGateway'];g=geometry()
    for y in (-1.85,1.85):
        g.box((-1.3,y,QUAY+2.24),(.76,.72,.16),1,'entry arch spring coping',.06)
        g.box((-1.3,y,QUAY+.13),(.74,.70,.26),1,'entry jamb foot',.05)
    g.box((-.8,0,QUAY+.012),(3.0,3.2,.024),1,'arrival stone threshold',.1)
    for y in (-2.03,2.03):
        g.box((-.6,y,QUAY+.62),(1.8,.2,1.24),0,'low entry wing wall',.06)
        g.box((-.6,y,QUAY+1.27),(1.94,.32,.12),1,'wing coping',.05)
        # Open blue shutters at the sides express an entrance without a gate
        # across the walkway.
        g.box((-.42,y,QUAY+1.84),(.95,.12,.88),2,'blue open entrance shutter',.035)
    return {'name':make(g,'PRP_QuayGateway_CopingAndBlueShutters',c).name}

def inspection_camera():
    s=bpy.data.scenes[SCENE];cam=s.camera
    cam.data.lens=36
    for frame,pos in [(1,(20,-65,40)),(24,(20,-65,40)),(108,(32,-60,36)),(144,(32,-60,36))]:
        aim_camera(pos,(78,56,-3))
        cam.keyframe_insert(data_path='location',frame=frame)
        cam.keyframe_insert(data_path='rotation_euler',frame=frame)
    s.frame_set(1)
    return {'camera':cam.name,'keyframes':[1,24,108,144],'motion':'inspection dolly, stable opening and rest; excluded from exports'}

def gate_filler():
    c=coll('MODULE_GateFiller',bpy.data.scenes[MODULES]);g=geometry()
    for z in (1.88,2.40):g.box((8.18,0,z),(.065,2.3,.07),2,'unused gate safety rail')
    o=make(g,'PRP_UnusedGate_Railing',c)
    s=bpy.data.scenes[SCENE];dst=coll('REF_UnusedGateRailings',s)
    for side in (-1,1):
        for y in (-40,-20,0,20,40):
            n=bpy.data.objects.new(('West' if side<0 else 'East')+'_UnusedGate_'+str(y),o.data)
            dst.objects.link(n);n.location=(side*28,-4-side*y,0);n.rotation_euler.z=math.pi if side<0 else 0
    return {'module':o.name,'unused_preview_gates_closed':10}

def render_frame(frame,name):
    s=bpy.data.scenes[SCENE];s.frame_set(frame)
    s.render.image_settings.file_format='PNG';s.render.filepath=str(EVIDENCE/(name+'.png'))
    bpy.ops.render.render(write_still=True)
    return {'path':s.render.filepath,'frame':frame,'camera':list(s.camera.location)}

def export_asset(collection_name,filename,merge=True):
    collection=bpy.data.collections[collection_name]
    objects=[o for o in collection.all_objects if o.type=='MESH']
    s=bpy.context.scene
    temp=coll('EXPORT_TEMP_Waterfront',s)
    outputs=[]
    batches=[objects] if merge else [[o] for o in objects]
    for batch in batches:
        g=geometry();mats=[]
        for o in batch:
            mesh=o.data;offset=len(g.v)
            g.v.extend(tuple(o.matrix_world@v.co) for v in mesh.vertices)
            remap={}
            for i,m in enumerate(mesh.materials):
                if m not in mats:mats.append(m)
                remap[i]=mats.index(m)
            g.f.extend(tuple(offset+i for i in p.vertices) for p in mesh.polygons)
            g.m.extend(remap[p.material_index] for p in mesh.polygons)
        name='EXPORT_'+(filename.replace('.glb','') if merge else batch[0].name)
        ob=make(g,name,temp,mats)
        bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
        outputs.append(ob)
    if bpy.context.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
    for o in bpy.context.selected_objects:o.select_set(False)
    for o in outputs:o.select_set(True)
    bpy.context.view_layer.objects.active=outputs[0]
    path=OUT/filename
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False,export_apply=True,export_yup=True,export_extras=True)
    triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in outputs)
    for o in outputs:
        mesh=o.data;bpy.data.objects.remove(o,do_unlink=True);bpy.data.meshes.remove(mesh)
    bpy.data.collections.remove(temp)
    return {'file':str(path),'bytes':path.stat().st_size,'triangles':triangles,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}

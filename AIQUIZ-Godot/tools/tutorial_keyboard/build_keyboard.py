"""Editable tutorial keyboard. Run in Blender; import and call staged functions.

Only TutorialKeyboardStudio and TK_* / *_TK_* datablocks are owned here.
Original scenes and the active .blend path are preserved. Checkpoints use
copy=True; the deliverable writes only the tutorial scene and its dependencies.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/ui/tutorial/keyboard'
EVIDENCE = ROOT / 'docs/tutorial_keyboard'
SCENE = 'TutorialKeyboardStudio'
PITCH = 0.01905
PRESS = 0.0025
REF = 'C:/Users/kykat/.codex/generated_images/01a0c437-5e71-7112-9f55-e02f95844495/exec-61d87f1d-402d-4a79-8fa2-2532862259e9.png'

def scene():
    return bpy.data.scenes[SCENE]

def collection(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        scene().collection.children.link(c)
    return c

def link(name, data=None, group='TK_Keyboard', parent=None):
    o = bpy.data.objects.new(name, data)
    collection(group).objects.link(o)
    o.parent = parent
    if data is None:
        o.empty_display_size=.004
    return o

def material(name, color, roughness=.35, metallic=0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = roughness
    p.inputs['Metallic'].default_value = metallic
    return m

def rounded_ring(w,h,r,z,steps=6):
    verts=[]
    for cx,cy,start in [(w/2-r,h/2-r,0),(-w/2+r,h/2-r,90),(-w/2+r,-h/2+r,180),(w/2-r,-h/2+r,270)]:
        for i in range(steps+1):
            a=math.radians(start+i*90/steps)
            verts.append((cx+r*math.cos(a),cy+r*math.sin(a),z))
    return verts

def loft(name, profiles, loc=(0,0,0), mat=None, parent=None, group='TK_Keyboard'):
    verts=[]
    for w,h,r,z in profiles:
        verts.extend(rounded_ring(w,h,r,z))
    n=len(verts)//len(profiles)
    faces=[tuple(reversed(range(n)))]
    for j in range(len(profiles)-1):
        for i in range(n):
            k=(i+1)%n
            faces.append((j*n+i,j*n+k,(j+1)*n+k,(j+1)*n+i))
    faces.append(tuple((len(profiles)-1)*n+i for i in range(n)))
    mesh=bpy.data.meshes.new(name+'_Mesh')
    mesh.from_pydata(verts,[],faces)
    mesh.update()
    obj=link(name,mesh,group,parent)
    obj.location=loc
    if mat: mesh.materials.append(mat)
    return obj

def box(name,w,h,d,loc,mat,parent=None,bevel=0,group='TK_Keyboard'):
    o=loft(name,[(w,h,max(.0001,bevel),-d/2),(w,h,max(.0001,bevel),d/2)],loc,mat,parent,group)
    return o

def key_layout():
    rows=[
        [('Esc','ESC',1)]+[(v,v,1) for v in '1234567890']+[('-','MINUS',1),('=','EQUAL',1),('Backspace','BACKSPACE',2)],
        [('Tab','TAB',1.5)]+[(v,v,1) for v in 'QWERTYUIOP']+[('[','LBRACKET',1),(']','RBRACKET',1),('\\','BACKSLASH',1.5)],
        [('Caps','CAPS',1.75)]+[(v,v,1) for v in 'ASDFGHJKL']+[(';','SEMICOLON',1),("'",'QUOTE',1),('Enter','ENTER',2.25)],
        [('Shift','LSHIFT',2.25)]+[(v,v,1) for v in 'ZXCVBNM']+[(',','COMMA',1),('.','PERIOD',1),('/','SLASH',1),('Shift','RSHIFT',2.75)],
        [('Ctrl','LCTRL',1.25),('Win','WIN',1.25),('Alt','LALT',1.25),('Space','SPACE',6.25),('Alt','RALT',1.25),('Fn','FN',1.25),('Ctrl','RCTRL',1.5)],
    ]
    keys=[]
    for row,items in enumerate(rows):
        x=0
        for label,key,width in items:
            keys.append(dict(label=label,key=key,width=width,x=(x+width/2-9.25)*PITCH,y=(2-row)*PITCH))
            x+=width
    for key,label,x,y in [('LEFT','←',16,-2),('DOWN','↓',17,-2),('RIGHT','→',18,-2),('UP','↑',17,-1)]:
        keys.append(dict(label=label,key=key,width=1,x=(x-9.25)*PITCH,y=y*PITCH))
    return keys

def checkpoint(label):
    import datetime
    folder=Path(bpy.app.tempdir) / 'tutorial_keyboard_checkpoints'
    folder.mkdir(parents=True,exist_ok=True)
    path=folder/(datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+label+'.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(path),copy=True)
    return str(path)

def dry_run():
    keys=key_layout()
    assert SCENE not in bpy.data.scenes, 'Scene already exists; inspect before rebuilding.'
    assert len({k['key'] for k in keys})==len(keys)
    return dict(scene=SCENE,key_count=len(keys),case_dimensions=[19.4*PITCH,5.8*PITCH,.015],protected=[s.name for s in bpy.data.scenes],create=['TutorialKeyboardStudio','TK_*','HERO_TK_*','RIG_TK_*','CAM_TK_*','LGT_TK_*'],modify=[],delete=[])

def bounds():
    s=bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene=s
    s.unit_settings.system='METRIC'
    s.render.engine='CYCLES'
    s.cycles.samples=48
    s.cycles.use_denoising=True
    s.render.resolution_x=1800
    s.render.resolution_y=600
    s.render.resolution_percentage=100
    s.render.image_settings.file_format='PNG'
    s.render.image_settings.color_mode='RGBA'
    s.render.film_transparent=True
    s.render.fps=30
    s.frame_start=1
    s.frame_end=360
    s.view_settings.view_transform='AgX'
    s.view_settings.look='AgX - Medium High Contrast'
    s.view_settings.exposure=0
    w=bpy.data.worlds.get('TK_StudioWorld') or bpy.data.worlds.new('TK_StudioWorld')
    w.use_nodes=True
    bg=next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value=(.5,.55,.65,1)
    bg.inputs[1].default_value=.15
    s.world=w
    root=link('RIG_TK_Keyboard')
    root['construction_reference']=REF
    root['purpose']='Physical-key literacy: WASD + Space / arrows + right Ctrl'
    navy=material('TK_Navy',(.013,.029,.065),.28,.38)
    dark=material('TK_Socket',(.004,.009,.018),.44)
    box('HERO_TK_Case',19.4*PITCH,5.8*PITCH,.015,(0,0,-.005),navy,root,.008)
    box('HERO_TK_Deck',18.9*PITCH,5.3*PITCH,.002,(0,0,.003),dark,root,.005)
    cd=bpy.data.cameras.new('CAM_TK_Hero_Data')
    cam=link('CAM_TK_Hero',cd)
    cam.location=(0,-.19,.63)
    target=Vector((0,0,.002))
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cd.type='ORTHO'
    cd.ortho_scale=.403
    cd.clip_start=.01
    cd.clip_end=5
    s.camera=cam
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.region_3d.view_camera_zoom=25
            area.spaces.active.overlay.show_relationship_lines=False
            area.spaces.active.overlay.show_extras=False
            area.spaces.active.overlay.show_floor=False
    return {'scene':s.name,'camera':cam.name,'case_dimensions':list(bpy.data.objects['HERO_TK_Case'].dimensions)}

def masses():
    ivory=material('TK_Ivory',(.81,.76,.65),.34)
    orange=material('TK_Player1_Orange',(1,.225,.018),.30)
    cyan=material('TK_Player2_Cyan',(.012,.62,.84),.28)
    root=bpy.data.objects['RIG_TK_Keyboard']
    for k in key_layout():
        mat=orange if k['key'] in ['W','A','S','D','SPACE'] else cyan if k['key'] in ['UP','DOWN','LEFT','RIGHT','RCTRL'] else ivory
        ctrl=link('RIG_TK_Key_'+k['key'],group='TK_Keycaps',parent=root)
        ctrl.location=(k['x'],k['y'],.0065)
        ctrl['physical_key']=k['key']
        ctrl['legend']=k['label']
        w=k['width']*PITCH-.0015
        box('HERO_TK_Key_'+k['key'],w,.0175,.007,(0,0,.0035),mat,ctrl,.0012,'TK_Keycaps')
    return {'key_count':len(key_layout()),'row_count':5,'arrow_cluster':'independent inverted T'}

def detail():
    dark=material('TK_Legend',(.005,.012,.027),.46)
    font=bpy.data.fonts.load('C:/Windows/Fonts/segoeuib.ttf',check_existing=True)
    for k in key_layout():
        old=bpy.data.objects['HERO_TK_Key_'+k['key']]
        mat=old.data.materials[0]
        ctrl=old.parent
        ctrl.location.z=.0065
        w=k['width']*PITCH-.0015
        box('HERO_TK_Switch_'+k['key'],.008,.008,.003,(k['x'],k['y'],.0055),bpy.data.materials['TK_Socket'],bpy.data.objects['RIG_TK_Keyboard'],.0007,'TK_Keycaps')
        # Replace only the owned blockout's mesh with a continuous molded-cap skin.
        refined=loft('TEMP_TK_'+k['key'],[(w,.0175,.0015,0),(w,.0175,.0016,.0012),(w-.0018,.0155,.0017,.0065),(w-.0025,.0149,.0015,.0072)],(0,0,0),mat,ctrl,'TK_Keycaps')
        old_mesh=old.data
        old.data=refined.data
        old.data.name=old.name+'_Mesh'
        old.location=(0,0,0)
        bpy.data.objects.remove(refined,do_unlink=True)
        if old_mesh.users==0: bpy.data.meshes.remove(old_mesh)
        bevel=old.modifiers.new('Molded soft edges','BEVEL')
        bevel.width=.00032
        bevel.segments=3
        bevel.limit_method='ANGLE'
        normals=old.modifiers.new('Weighted cap normals','WEIGHTED_NORMAL')
        normals.keep_sharp=True
        curve=bpy.data.curves.new('HERO_TK_Legend_'+k['key']+'_Text','FONT')
        curve.body=k['label']
        curve.font=font
        curve.align_x='CENTER'
        curve.align_y='CENTER'
        curve.size=.0108 if len(k['label'])==1 else .0072
        if k['key'] in ['UP','DOWN','LEFT','RIGHT']: curve.size=.014
        curve.extrude=0
        curve.resolution_u=6
        text=link('HERO_TK_Legend_'+k['key'],curve,'TK_Legends',ctrl)
        text.location=(0,0,.00728)
        curve.materials.append(dark)
        if k['key'] in ['F','J']:
            box('HERO_TK_Homing_'+k['key'],.0034,.00042,.00022,(0,-.0051,.00735),mat,ctrl,.00017,'TK_Keycaps')
    for name in ['HERO_TK_Case','HERO_TK_Deck']:
        o=bpy.data.objects[name]
        mod=o.modifiers.new('Machined lip radius','BEVEL')
        mod.width=.0007
        mod.segments=3
        mod.limit_method='ANGLE'
        o.modifiers.new('Weighted chassis normals','WEIGHTED_NORMAL')
    # Tidy accent rails set into the front lip, not distracting labels.
    root=bpy.data.objects['RIG_TK_Keyboard']
    for name,x,w,m in [('Player1',-.094,.044,'TK_Player1_Orange'),('Player2',.147,.040,'TK_Player2_Cyan')]:
        box('HERO_TK_Rail_'+name,w,.0008,.0006,(x,-.052,.0032),bpy.data.materials[m],root,.00025)
    return {'detailed_caps':len(key_layout()),'font':font.filepath,'editable_texts':len(key_layout())}

def light(name,location,power,size,color,role):
    group='TK_Lighting_'+role
    data=bpy.data.lights.new(name+'_Data','AREA')
    data.energy=power
    data.shape='DISK'
    data.size=size
    data.color=color
    obj=link(name,data,group)
    obj.location=location
    obj.rotation_euler=(-obj.location).to_track_quat('-Z','Y').to_euler()
    obj['purpose']=role
    obj['motivation']='Studio softbox'
    obj['target']='Keyboard keycaps'
    obj['camera_relation']='Front '+('left' if location[0]<0 else 'right')
    obj['expected_effect']='Readable directional molded keycap form' if role=='key' else 'Recover right-side legends without flattening sockets'
    return obj

def lighting():
    light('LGT_TK_Key',(-.20,-.16,.38),2.2,.25,(1,.89,.78),'key')
    light('LGT_TK_Fill',(.22,.07,.27),.75,.20,(.73,.87,1),'fill')
    return {'lights':['LGT_TK_Key','LGT_TK_Fill']}

def animation():
    names=['A','D','W','S','SPACE','LEFT','RIGHT','UP','DOWN','RCTRL']
    beats=[]
    for i,key in enumerate(names):
        o=bpy.data.objects['RIG_TK_Key_'+key]
        start=12+i*32
        rest=o.location.z
        for frame,z in [(1,rest),(start,rest),(start+5,rest-PRESS),(start+16,rest-PRESS),(start+23,rest),(360,rest)]:
            o.location.z=z
            o.keyframe_insert(data_path='location',index=2,frame=frame)
        if o.animation_data and o.animation_data.action:
            for layer in o.animation_data.action.layers:
                for strip in layer.strips:
                    for bag in strip.channelbags:
                        for fc in bag.fcurves:
                            for kp in fc.keyframe_points:
                                kp.interpolation='BEZIER'
                                kp.handle_left_type='AUTO_CLAMPED'
                                kp.handle_right_type='AUTO_CLAMPED'
        marker=scene().timeline_markers.new('PRESS '+key,frame=start+5)
        beats.append({'key':key,'start':start,'peak':start+5,'release':start+23})
    scene().frame_set(1)
    (EVIDENCE/'animation_beats.json').write_text(json.dumps(beats,indent=2),encoding='utf-8')
    return beats

def press_accents():
    """Thin light rim makes physical travel readable at tutorial display size."""
    root=bpy.data.objects['RIG_TK_Keyboard']
    keys={k['key']:k for k in key_layout()}
    for player,color in [('P1',(1,.23,.015)),('P2',(.005,.62,1))]:
        mat=material('TK_PressGlow_'+player,color,.3)
        shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        shader.inputs['Emission Color'].default_value=(*color,1)
        shader.inputs['Emission Strength'].default_value=2.2
    for i,key in enumerate(['A','D','W','S','SPACE','LEFT','RIGHT','UP','DOWN','RCTRL']):
        k=keys[key]
        w=k['width']*PITCH-.0015
        ow,oh=w+.0015,.019
        iw,ih=w-.0003,.0172
        rings=[rounded_ring(ow,oh,.002,-.0002),rounded_ring(ow,oh,.002,.0002),rounded_ring(iw,ih,.0011,.0002),rounded_ring(iw,ih,.0011,-.0002)]
        n=len(rings[0]); verts=sum(rings,[]); faces=[]
        for r in range(4):
            nex=(r+1)%4
            for j in range(n):
                nj=(j+1)%n
                faces.append((r*n+j,r*n+nj,nex*n+nj,nex*n+j))
        mesh=bpy.data.meshes.new('HERO_TK_PressGlow_'+key+'_Mesh')
        mesh.from_pydata(verts,[],faces); mesh.update()
        obj=link('HERO_TK_PressGlow_'+key,mesh,'TK_Keycaps',root)
        obj.location=(k['x'],k['y'],.00465)
        mesh.materials.append(bpy.data.materials['TK_PressGlow_'+('P1' if i<5 else 'P2')])
        start=12+i*32
        for f,hidden in [(1,True),(start+3,True),(start+4,False),(start+19,False),(start+20,True),(360,True)]:
            obj.hide_render=hidden
            obj.hide_viewport=hidden
            obj.keyframe_insert(data_path='hide_render',frame=f)
            obj.keyframe_insert(data_path='hide_viewport',frame=f)
        obj['purpose']='Brief cue tied to the physical press; color retains player mapping.'
    scene().frame_set(1)
    return {'animated_press_rims':10}

def render(path=None,percent=100,engine='CYCLES',samples=48,frame=1):
    s=scene()
    s.frame_set(frame)
    s.render.engine=engine
    s.render.resolution_percentage=percent
    s.cycles.samples=samples
    s.render.filepath=str(path or OUT/'keyboard_hero.png')
    bpy.ops.render.render(write_still=True,scene=s.name)
    return s.render.filepath

def solid(path,side=False):
    s=scene()
    original=s.render.engine
    cam=s.camera
    loc=cam.location.copy()
    rot=cam.rotation_euler.copy()
    if side:
        cam.location=(0,-.42,.10)
        cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler()
    s.render.engine='BLENDER_WORKBENCH'
    s.display.shading.light='STUDIO'
    s.display.shading.color_type='MATERIAL'
    s.display.shading.show_shadows=True
    s.display.shading.show_cavity=True
    s.render.resolution_percentage=60
    s.render.filepath=str(path)
    bpy.ops.render.render(write_still=True,scene=s.name)
    cam.location=loc
    cam.rotation_euler=rot
    s.render.engine=original
    return str(path)

def audit():
    s=scene()
    expected=key_layout()
    samples=[]
    for i,key in enumerate(['A','D','W','S','SPACE','LEFT','RIGHT','UP','DOWN','RCTRL']):
        o=bpy.data.objects['RIG_TK_Key_'+key]
        measures=[]
        for f in [1,12+i*32,17+i*32,28+i*32,35+i*32,360]:
            s.frame_set(f)
            bpy.context.view_layer.update()
            measures.append({'frame':f,'z':o.matrix_world.translation.z})
        travel=max(x['z'] for x in measures)-min(x['z'] for x in measures)
        samples.append({'key':key,'travel_m':travel,'passed':abs(travel-PRESS)<.000001,'samples':measures})
    s.frame_set(1)
    result={'scene':s.name,'key_count':len(expected),'legend_count':len([o for o in s.objects if o.name.startswith('HERO_TK_Legend_')]),'objects':len(s.objects),'original_scene_objects':[o.name for o in bpy.data.scenes['Scene'].objects] if 'Scene' in bpy.data.scenes else [],'active_filepath':bpy.data.filepath,'camera':s.camera.name,'resolution':[s.render.resolution_x,s.render.resolution_y],'fps':s.render.fps,'frame_range':[s.frame_start,s.frame_end],'motion':samples,'valid':all(a['passed'] for a in samples)}
    (EVIDENCE/'structural_motion_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return result

def save_copy():
    s=scene()
    s.frame_set(1)
    s.render.resolution_percentage=100
    s.render.engine='CYCLES'
    s.cycles.samples=64
    s.render.filepath=str(OUT/'keyboard_hero.png')
    folder=OUT/'source'
    folder.mkdir(parents=True,exist_ok=True)
    (folder/'.gdignore').touch()
    path=folder/'keyboard.blend'
    # Asset-only copy: keep unrelated live scenes out of the delivered source.
    # The live filepath remains unchanged; all dependencies of this scene are written.
    bpy.data.libraries.write(str(path),{s},path_remap='ABSOLUTE',fake_user=True,compress=True)
    return str(path)

if __name__=='__main__':
    # Batch regeneration entry point; intentional original-scene preservation.
    OUT.mkdir(parents=True,exist_ok=True)
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    print(dry_run())
    checkpoint('before_keyboard')
    bounds()
    masses()
    detail()
    lighting()
    animation()
    press_accents()
    render()
    print(audit())
    print(save_copy())

"""Original AIQUIZ Santorini scenery. Blender 5.1 background deterministic builder.

Run Blender --background --factory-startup --python this_file.py.
Coordinates in the design manifest use Godot metres. Geometry is authored Z-up,
then glTF's exporter performs the axis conversion. No external/paid assets.
This file creates its own scene; it never touches a running Blender session.
"""
from __future__ import annotations
import bpy, bmesh, math, json, random, csv, sys, struct
import numpy as np
from pathlib import Path
from mathutils import Vector

SOURCE = Path(__file__).resolve().parent
ASSET = SOURCE.parent
PREVIEWS = SOURCE / 'previews'
PREVIEWS.mkdir(parents=True, exist_ok=True)
R = random.Random(9132026)
# This process is explicitly --factory-startup. Discard its factory cube, camera
# and lamp before making the new source scene, so none can leak into the GLB.
for obj in list(bpy.data.objects):bpy.data.objects.remove(obj,do_unlink=True)
scene = bpy.data.scenes.new('AIQUIZ | Santorini Caldera Town')
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.render.engine = 'BLENDER_EEVEE'
bpy.context.preferences.filepaths.save_version = 0
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.render.engine = 'BLENDER_EEVEE'

def rgba(h):
    def lin(c): return c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4
    return (*[lin(int(h[i:i+2],16)/255) for i in (0,2,4)],1)

def material(name, h, rough=.8, emission=False):
    m=bpy.data.materials.new('Santorini '+name); m.diffuse_color=rgba(h); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=rgba(h)
    p.inputs['Roughness'].default_value=rough
    if emission:
        p.inputs['Emission Color'].default_value=rgba('ffc978')
        p.inputs['Emission Strength'].default_value=.1
    return m

M={
    'white':material('Warm Lime Plaster','f1eee2'),
    'ivory':material('Sunwashed Ivory Plaster','dedccd'),
    'white2':material('Cool White Plaster','e5ece7'),
    'blue':material('Aegean Cobalt','145ea7',.66),
    'blue2':material('Deep Ultramarine','183d78',.62),
    'trim':material('Chalk Edge Trim','faf5e8'),
    'dark':material('Deep Door Recess','253b44'),
    'glass':material('Window Warm Glass','afac89',.34,True),
    'lamp':material('Lantern Warm Bulb','f2cb83',.48,True),
    'stone':material('Warm Volcanic Masonry','a69b86'),
    'stone2':material('Pale Limestone Paving','d5cab1'),
    'rock':material('Caldera Ochre Rock','a18e75'),
    'rock2':material('Caldera Rock Light','ab9981'),
    'rock3':material('Basalt Rock Shade','96826b'),
    'wood':material('Weathered Timber','866445'),
    'leaf':material('Olive Sage Foliage','71875b'),
    'leaf2':material('Cypress Deep Foliage','486c48'),
    'pink':material('Bougainvillea Carmine','d84c91'),
    'pink2':material('Bougainvillea Bright','e48cb9'),
    'pot':material('Terracotta Pots','ba7758'),
    'canvas':material('Ivory Canvas','eaddb5'),
    'metal':material('Aged Brass','897557',.5),
}

def collection(name):
    c=bpy.data.collections.new(name); scene.collection.children.link(c); return c
EXPORT=collection('EXPORT | Town districts and cliff terrain')
REVIEW=collection('REVIEW ONLY | Sea lights cameras')

class Mesh:
    """Direct mesh construction, no operator-heavy object-per-trim workflow."""
    def __init__(self,name,origin=(0,0,0),angle=0):
        self.name=name; self.origin=origin; self.angle=angle
        self.v=[]; self.f=[]; self.ids=[]; self.slots=[]; self.smooth=[]
    def face(self,pts,mat,smooth=False):
        i=len(self.v); ox,oy,oz=self.origin; c=math.cos(self.angle); s=math.sin(self.angle)
        self.v.extend((ox+x*c-y*s,oy+x*s+y*c,oz+z) for x,y,z in pts)
        self.f.append(tuple(range(i,i+len(pts))))
        if mat not in self.slots:self.slots.append(mat)
        self.ids.append(self.slots.index(mat)); self.smooth.append(smooth)
    def prism(self,poly,z,h,mat,top=None):
        self.face([(x,y,z) for x,y in reversed(poly)],mat)
        self.face([(x,y,z+h) for x,y in poly],top or mat)
        for a,b in zip(poly,poly[1:]+poly[:1]):
            self.face([(a[0],a[1],z),(b[0],b[1],z),(b[0],b[1],z+h),(a[0],a[1],z+h)],mat)
    def box(self,x,y,z,w,d,h,mat,bevel=0):
        if not bevel:self.prism([(x-w/2,y-d/2),(x+w/2,y-d/2),(x+w/2,y+d/2),(x-w/2,y+d/2)],z,h,mat); return
        b=min(bevel,w/3,d/3,h/3)
        poly=[(-w/2+b,-d/2),(w/2-b,-d/2),(w/2,-d/2+b),(w/2,d/2-b),(w/2-b,d/2),(-w/2+b,d/2),(-w/2,d/2-b),(-w/2,-d/2+b)]
        lower=[(x+px,y+py,z+b) for px,py in poly]; upper=[(x+px,y+py,z+h-b) for px,py in poly]
        inner=[(x+px*(w-2*b)/w,y+py*(d-2*b)/d) for px,py in poly]
        bottom=[(px,py,z) for px,py in inner]; top=[(px,py,z+h) for px,py in inner]
        self.face(list(reversed(bottom)),mat); self.face(top,mat)
        for a in range(8):
            n=(a+1)%8
            self.face([bottom[a],bottom[n],lower[n],lower[a]],mat)
            self.face([lower[a],lower[n],upper[n],upper[a]],mat)
            self.face([upper[a],upper[n],top[n],top[a]],mat)
    def cylinder(self,x,y,z,r,h,mat,n=12,rt=None):
        rt=r if rt is None else rt
        lo=[(x+r*math.cos(i*math.tau/n),y+r*math.sin(i*math.tau/n),z) for i in range(n)]
        hi=[(x+rt*math.cos(i*math.tau/n),y+rt*math.sin(i*math.tau/n),z+h) for i in range(n)]
        self.face(list(reversed(lo)),mat);self.face(hi,mat)
        for i in range(n):self.face([lo[i],lo[(i+1)%n],hi[(i+1)%n],hi[i]],mat,True)
    def sphere(self,x,y,z,rx,ry,rz,mat,n=10,rings=5,hemisphere=False):
        last=None
        for j in range(rings+1):
            t=(math.pi/2 if hemisphere else math.pi)*j/rings
            if hemisphere:
                rad=math.cos(t); zz=math.sin(t)
            else:rad=math.sin(t);zz=-math.cos(t)
            ring=[(x+rx*rad*math.cos(i*math.tau/n),y+ry*rad*math.sin(i*math.tau/n),z+rz*zz) for i in range(n)]
            if last:
                for i in range(n):self.face([last[i],last[(i+1)%n],ring[(i+1)%n],ring[i]],mat,True)
            last=ring
    def arch(self,x,y,z,w,h,d,mat,fill=False):
        # XZ arch extruded along Y. Rounded top radius is half the opening width.
        r=w/2; spring=h-r
        arc=[(x+r*math.cos(math.pi-i*math.pi/12),z+spring+r*math.sin(math.pi-i*math.pi/12)) for i in range(13)]
        if fill:
            poly=[(x-r,z)]+arc+[(x+r,z)]
            self.face([(px,y-d/2,pz) for px,pz in poly],mat)
            self.face([(px,y+d/2,pz) for px,pz in reversed(poly)],mat)
            for a,b in zip(poly,poly[1:]+poly[:1]):self.face([(a[0],y-d/2,a[1]),(a[0],y+d/2,a[1]),(b[0],y+d/2,b[1]),(b[0],y-d/2,b[1])],mat)
        else:
            t=.24
            self.box(x-r-t/2,y,z,t,d,spring,mat,.055); self.box(x+r+t/2,y,z,t,d,spring,mat,.055)
            for a in range(12):
                t0=math.pi-a*math.pi/12;t1=math.pi-(a+1)*math.pi/12
                p=[(x+r*math.cos(t0),z+spring+r*math.sin(t0)),(x+r*math.cos(t1),z+spring+r*math.sin(t1)),(x+(r+t)*math.cos(t1),z+spring+(r+t)*math.sin(t1)),(x+(r+t)*math.cos(t0),z+spring+(r+t)*math.sin(t0))]
                self.face([(px,y-d/2,pz) for px,pz in p],mat)
                self.face([(px,y+d/2,pz) for px,pz in reversed(p)],mat)
                for c,e in zip(p,p[1:]+p[:1]):self.face([(c[0],y-d/2,c[1]),(c[0],y+d/2,c[1]),(e[0],y+d/2,e[1]),(e[0],y-d/2,e[1])],mat)
    def beam(self,a,b,width,mat):
        a=Vector(a);b=Vector(b);v=(b-a).normalized();u=v.cross(Vector((0,0,1)))
        if u.length<.001:u=v.cross(Vector((0,1,0)))
        u.normalize();u*=width/2;w=v.cross(u)
        p=[a-u-w,a+u-w,a+u+w,a-u+w];q=[v+(b-a) for v in p]
        self.face(list(reversed(p)),mat);self.face(q,mat)
        for i in range(4):self.face([p[i],p[(i+1)%4],q[(i+1)%4],q[i]],mat)
    def finish(self):
        mesh=bpy.data.meshes.new(self.name);mesh.from_pydata(self.v,[],self.f);mesh.update()
        for m in self.slots:mesh.materials.append(M[m])
        for p,i,sm in zip(mesh.polygons,self.ids,self.smooth):p.material_index=i;p.use_smooth=sm
        # Weld seams for smooth domes/foliage, while plaster and stone remain flat.
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.0001)
        bm.to_mesh(mesh);bm.free();mesh.update()
        obj=bpy.data.objects.new(self.name,mesh);EXPORT.objects.link(obj)
        # Per-face duplicated vertices intentionally keep plaster bevels and cut stone crisp.
        return obj

COUNTS={'houses':0,'churches':0,'windmills':0,'stairs':0,'pergolas':0,'trees':0,'boats':0,'terraces':0}

def window(g,x,y,z,w=1.0,h=1.35,arched=False,shutters=True):
    # Applied reveal uses a deep dark surround and projecting plaster jambs.
    g.box(x,y,z,w+.24,.22,h+.23,'trim',.075)
    if arched:g.arch(x,y-.13,z+.09,w,h,.08,'dark',True)
    else:g.box(x,y-.16,z+.1,w,.05,h,'dark')
    g.box(x,y-.20,z+.22,w*.75,.06,h*.72,'glass')
    g.box(x,y-.245,z+.12,.085,.07,h*.84,'blue')
    g.box(x,y-.245,z+h*.54,w*.84,.07,.07,'blue')
    g.box(x,y-.28,z-.06,w+.46,.45,.16,'trim',.055)
    if shutters:
        for side in (-1,1):
            sx=x+side*(w*.71)
            g.box(sx,y-.17,z+.1,w*.31,.12,h,'blue',.05)
            for k in range(4):g.box(sx,y-.24,z+.3+k*h*.19,w*.27,.07,.055,'blue2')

def door(g,x,y,z,w=1.4,h=2.5,arched=True):
    if arched:
        g.arch(x,y-.1,z,w+.3,h+.16,.18,'trim',True)
        g.arch(x,y-.225,z+.07,w,h,.1,'dark',True)
        g.arch(x,y-.30,z+.08,w*.86,h-.11,.08,'blue',True)
    else:
        g.box(x,y-.1,z,w+.35,.18,h+.18,'trim',.08)
        g.box(x,y-.23,z+.03,w,.10,h,'blue',.04)
    for sx in (-.28,.28):g.box(x+sx*w,y-.365,z+.35,w*.31,.065,h*.46,'blue2',.04)
    g.sphere(x+w*.22,y-.42,z+1.15,.08,.06,.08,'metal',6,3)
    g.box(x,y-.5,z-.08,w+.52,1.0,.16,'stone2',.07)

def pot(g,x,y,z,flowers=True,size=1):
    g.cylinder(x,y,z,.32*size,.56*size,'pot',8,.43*size)
    g.cylinder(x,y,z+.49*size,.46*size,.12*size,'pot',8)
    g.sphere(x,y,z+.92*size,.54*size,.44*size,.54*size,'leaf',8,4)
    if flowers:
        for i in range(7):
            a=i*2.4;g.sphere(x+math.cos(a)*.34*size,y+math.sin(a)*.31*size,z+(1.03+(i%3)*.12)*size,.17*size,.16*size,.14*size,'pink' if i%2 else 'pink2',7,3)

def tree(g,x,y,z,cypress=False,scale=1):
    COUNTS['trees']+=1
    g.cylinder(x,y,z,.21*scale,2.8*scale,'wood',7,.14*scale)
    if cypress:
        g.sphere(x,y,z+3.3*scale,.7*scale,.7*scale,2.55*scale,'leaf2',8,5)
    else:
        for i in range(3):
            a=i*2.09;g.sphere(x+math.cos(a)*.72*scale,y+math.sin(a)*.72*scale,z+(2.9+i*.16)*scale,1.45*scale,1.32*scale,1.1*scale,'leaf' if i%2 else 'leaf2',9,4)

def pergola(g,x,y,z,w=5,d=4,flowers=True):
    COUNTS['pergolas']+=1
    for sx in (-1,1):
        for sy in (-1,1):g.box(x+sx*w/2,y+sy*d/2,z,.16,.16,2.7,'wood')
    for sy in (-1,1):g.box(x,y+sy*d/2,z+2.65,w+.5,.22,.23,'wood')
    for i in range(int(w/.65)+1):g.box(x-w/2+i*.65,y,z+2.86,.17,d+.7,.14,'wood')
    if flowers:
        for i in range(9):
            xx=x-w/2+i*w/8
            g.sphere(xx,y+d/2+.12*math.sin(i),z+2.99,.48,.40,.29,'leaf',8,4)
            for j in range(3):
                g.sphere(xx+math.sin(i+j*2.1)*.23,y+d/2-.20+math.cos(i*1.7+j)*.26,z+3.08+math.sin(i+j)*.19,.19,.18,.15,'pink' if (i+j)%2 else 'pink2',7,3)
        # One vine drops along a post rather than forming a uniform colored rail.
        for j in range(5):
            g.sphere(x-w/2+.12,y+d/2,z+.7+j*.48,.25,.27,.37,'leaf',7,3)
            g.sphere(x-w/2+.23,y+d/2-.2,z+.85+j*.48,.19,.17,.19,'pink',7,3)

def terrace(g,x,y,z,w,d,roof=False):
    COUNTS['terraces']+=1
    g.box(x,y,z-.28,w,d,.30,'stone2',.1)
    # Low parapets leave a visible entry in the front edge.
    g.box(x-w/2,y,z,.32,d,1.0,'white',.1);g.box(x+w/2,y,z,.32,d,1.0,'white',.1)
    for sign in (-1,1):g.box(x+sign*w*.33,y-d/2,z,w*.34,.32,.86,'white',.1)
    if roof:g.box(x,y+d/2,z,w,.3,.9,'white',.1)

def stairs(g,x,y,z,width,rise,run,n=12):
    COUNTS['stairs']+=1
    for i in range(n):g.box(x,y+(i+.5)*run/n,z,width,run/n+.02,(i+1)*rise/n,'stone2',.03)
    # Raking plaster stringers, interrupted into short flat caps following risers.
    for side in (-1,1):
        for i in range(0,n,2):g.box(x+side*(width/2+.14),y+(i+1)*run/n,z+i*rise/n,.28,run*2/n+.04,1.0+rise*2/n,'white',.08)

def house(g,x,y,z,w,d,h,kind,seed):
    rr=random.Random(seed);COUNTS['houses']+=1
    wall=('white','white','white2','ivory')[seed%4]
    g.box(x,y,z,w,d,h,wall,.22)
    front=y-d/2
    # Different volumes and actual roof profiles; visible side windows too.
    g.box(x,front,z+.12,w+.14,.13,.22,'ivory',.035)
    door_x=x-w*.23 if seed%2 else x+w*.24
    door(g,door_x,front,z+.10,1.4,2.5,seed%3!=0)
    for xx in [x+w*.24 if seed%2 else x-w*.23]:window(g,xx,front,z+1.08,1.05,1.35,seed%4==0)
    if h>6:
        for xx in (x-w*.26,x+w*.26):window(g,xx,front,z+h-2.65,1.03,1.5,seed%3==0)
        # Shallow balcony with cobalt rail and plaster base.
        if seed%3==0:
            g.box(x,front-.62,z+h-3.0,w*.72,1.5,.22,'trim',.08)
            for i in range(8):g.box(x-w*.34+i*w*.68/7,front-1.27,z+h-2.8,.08,.08,.9,'blue')
            g.box(x,front-1.27,z+h-1.92,w*.75,.09,.09,'blue')
            for sign in (-1,1):
                g.beam((x+sign*w*.32,front-1.29,z+h-2.73),(x,front-1.29,z+h-2.0),.065,'blue')
    # Side details use thin geometry on both side planes; a cobalt shutter color cue.
    for side in (-1,1):
        for yi in (-.20,.22):
            zz=z+1.35 if h<6 else z+h-2.75
            g.box(x+side*(w/2+.06),y+yi*d,zz,.15,1.35,1.6,'trim',.055)
            g.box(x+side*(w/2+.15),y+yi*d,zz+.13,.06,1.10,1.28,'blue',.035)
    if kind in (0,1,4,6):
        g.box(x,y,z+h-.08,w+.28,d+.28,.23,'trim',.09)
        # Roof parapet is capped and substantial enough to read from stage cameras.
        for side in (-1,1):g.box(x+side*(w/2-.03),y,z+h,.27,d,.68,wall,.10)
        g.box(x,y+d/2-.03,z+h,w,.27,.68,wall,.10)
        if kind!=4:g.box(x,front+.03,z+h,w,.27,.60,wall,.10)
        if kind==1:
            g.box(x+w*.18,y+d*.12,z+h,w*.48,d*.48,2.4,wall,.18)
            g.box(x+w*.18,y+d*.12,z+h+2.35,w*.52,d*.52,.20,'trim',.08)
        if kind==4:pergola(g,x,y,z+h+.06,w*.76,d*.7,True)
        if kind==6:
            # Exterior rooftop stair along the flank.
            stairs(g,x+w/2+1.2,y-d/2,z,1.9,h,d,14)
            pot(g,x-w*.25,y-d*.25,z+h+.08,True,1.15)
    elif kind in (2,5):
        # Barrel roof with curved white or blue vault; complete quarter segments.
        r=w*.51; roofmat='white' if kind==2 else 'blue'
        for i in range(16):
            a0=i*math.pi/16;a1=(i+1)*math.pi/16
            q=[(x+r*math.cos(a0),y-d/2-.12,z+h+r*.55*math.sin(a0)),(x+r*math.cos(a1),y-d/2-.12,z+h+r*.55*math.sin(a1)),(x+r*math.cos(a1),y+d/2+.12,z+h+r*.55*math.sin(a1)),(x+r*math.cos(a0),y+d/2+.12,z+h+r*.55*math.sin(a0))]
            g.face(list(reversed(q)),roofmat,True)
        for sy in (-1,1):
            pts=[(x-w/2,y+sy*(d/2+.11),z+h),(x+w/2,y+sy*(d/2+.11),z+h)]+[(x+r*math.cos(i*math.pi/16),y+sy*(d/2+.11),z+h+r*.55*math.sin(i*math.pi/16)) for i in range(17)]
            g.face(pts if sy<0 else list(reversed(pts)),wall)
    else:
        # Traditional small domed dwelling with cubic terrace annex.
        g.cylinder(x,y,z+h,w*.41,.42,'trim',20)
        g.sphere(x,y,z+h+.42,w*.42,w*.42,w*.33,'white',24,8,True)
    if seed%2==0:pot(g,x-w*.38,front-.65,z+.06,True,1.2)
    if seed%5==0:
        # Bougainvillea climbs one wall and spills off the eave.
        for i in range(4):
            zz=z+h*.3+i*h*.23;xx=x+w*.41+math.sin(i)*.35
            g.sphere(xx,front-.2,zz,.47,.34,.64,'leaf',8,4)
            for j in range(4):
                a=j*2.2+i
                g.sphere(xx+math.cos(a)*.35,front-.42+math.sin(a)*.19,zz+j*.16,.23,.19,.22,'pink' if (i+j)%2 else 'pink2',7,3)
    if seed%4==0:
        # Chimney, solar-free traditional roofscape.
        g.box(x-w*.3,y+d*.23,z+h,.6,.65,1.35,wall,.10)
        g.box(x-w*.3,y+d*.23,z+h+1.28,.83,.86,.18,'trim',.055)
    if seed%3==1:
        # Attached lower rooms make clusters of interlocking Cycladic volumes.
        side=-1 if seed%2 else 1;ax=x+side*w*.57;ay=y+d*.15
        aw=w*.52;ad=d*.66;ah=h*.63
        g.box(ax,ay,z,aw,ad,ah,wall,.20)
        g.box(ax,ay,z+ah,aw+.23,ad+.23,.24,'trim',.08)
        g.box(ax,ay-ad/2,z+ah+.17,aw,.26,.6,wall,.09)
        window(g,ax,ay-ad/2,z+1.0,1.0,1.2,False,False)
        pot(g,ax,ay,z+ah+.22,True,1.1)

def church(g,x,y,z,scale=1):
    COUNTS['churches']+=1
    # Monument has a white barrel nave, blue drum dome and free-standing open bell gable.
    w=12*scale;d=18*scale;h=8.7*scale
    g.box(x,y,z,w,d,h,'white',.3)
    g.box(x,y,z+h,w+.5,d+.5,.4,'trim',.1)
    front=y-d/2
    for xx in (x-w*.37,x+w*.37):
        g.box(xx,front-.15,z,.5,.5,h+.2,'trim',.08)
        window(g,xx,front-.18,z+3.9,1.3,2.6,True,False)
    door(g,x,front,z+.1,2.65,4.7,True)
    g.cylinder(x,y+1.9*scale,z+h,4.25*scale,3.2*scale,'white',32)
    for i in range(8):
        a=i*math.tau/8
        xx=x+4.25*scale*math.cos(a);yy=y+1.9*scale+4.25*scale*math.sin(a)
        # Blue vertical drum highlights alternate with the sunlit white reveals.
        g.cylinder(xx,yy,z+h+.65*scale,.30*scale,1.55*scale,'blue2',8)
    g.cylinder(x,y+1.9*scale,z+h+3.1*scale,4.40*scale,.30*scale,'trim',32)
    g.sphere(x,y+1.9*scale,z+h+3.38*scale,4.45*scale,4.45*scale,3.7*scale,'blue',40,12,True)
    top=z+h+7.15*scale
    g.box(x,y+1.9*scale,top,.20*scale,.20*scale,2*scale,'trim',.05)
    g.box(x,y+1.9*scale,top+1.2*scale,1.1*scale,.2*scale,.18*scale,'trim',.04)
    bx=x+w/2+3.4*scale;by=front+1.4*scale
    g.box(bx,by,z,4.7*scale,3*scale,7.5*scale,'white',.2)
    for level,ww in ((0,3.2),(1,2.3)):
        zz=z+(7.5+level*4.6)*scale
        g.arch(bx,by,zz,ww*scale,4.0*scale,1.35*scale,'white')
        g.cylinder(bx,by,zz+2.15*scale,.43*scale,.70*scale,'metal',12,.2*scale)
        g.box(bx,by,zz+3.8*scale,ww*scale+.8*scale,1.6*scale,.3*scale,'trim',.1)
    g.box(bx,by,z+16*scale,.18*scale,.18*scale,1.4*scale,'trim')
    g.box(bx,by,z+16.9*scale,.9*scale,.18*scale,.15*scale,'trim')
    terrace(g,x,front-4*scale,z,19*scale,7*scale)
    for sx in (-1,1):tree(g,x+sx*9.5*scale,y+2*scale,z,True,1.6*scale)

def windmill(g,x,y,z,scale=1):
    COUNTS['windmills']+=1
    g.cylinder(x,y,z,3.2*scale,10*scale,'white',20,2.55*scale)
    g.cylinder(x,y,z+10*scale,3.25*scale,3.3*scale,'wood',20,.12*scale)
    door(g,x,y-3.1*scale,z+.1,1.45,2.7)
    hub=(x,y-2.95*scale,z+9.4*scale)
    g.sphere(*hub,.5*scale,.35*scale,.5*scale,'wood',10,5)
    for i in range(8):
        a=i*math.tau/8+.15
        end=(x+math.cos(a)*7.2*scale,y-3.0*scale,z+9.4*scale+math.sin(a)*7.2*scale)
        g.beam(hub,end,.15*scale,'wood')
        a2=a+.43
        pts=[(x+math.cos(a)*2.6*scale,y-3.07*scale,z+9.4*scale+math.sin(a)*2.6*scale),end,(x+math.cos(a2)*6.7*scale,y-3.07*scale,z+9.4*scale+math.sin(a2)*6.7*scale)]
        g.face(pts,'canvas');g.face(list(reversed(pts)),'canvas')

def boat(g,x,y,z,scale=1):
    COUNTS['boats']+=1
    # Pointed hull, white gunwale, blue seats, mast and furled canvas.
    p=[(-1.1,-3.0),(1.1,-3.0),(1.5,1.9),(0,3.65),(-1.5,1.9)]
    lo=[(x+xx*.75*scale,y+yy*.8*scale,z-.4*scale) for xx,yy in p]
    hi=[(x+xx*scale,y+yy*scale,z+.75*scale) for xx,yy in p]
    for i in range(5):g.face([lo[i],lo[(i+1)%5],hi[(i+1)%5],hi[i]],'blue')
    g.prism([(x+xx*scale,y+yy*scale) for xx,yy in p],z+.68*scale,.16*scale,'trim','wood')
    for yy in (-1.8,.3,1.8):g.box(x,y+yy*scale,z+.85*scale,2.25*scale,.55*scale,.17*scale,'blue')
    g.cylinder(x,y+.1*scale,z+.83*scale,.075*scale,5*scale,'wood',6)

def paving(g,x,y,z,w,d,seed):
    rr=random.Random(seed)
    g.box(x,y,z-.11,w,d,.13,'trim')
    # Original irregular individual flagstones separated by white mortar.
    nx=max(1,int(w/1.5));ny=max(1,int(d/1.35))
    for j in range(ny):
        for i in range(nx):
            ww=w/nx;dd=d/ny;xx=x-w/2+(i+.5)*ww;yy=y-d/2+(j+.5)*dd
            inset=.055
            poly=[(xx-ww/2+inset,yy-dd/2+.08),(xx+ww/2-.08,yy-dd/2+.07),(xx+ww/2-.04,yy+dd/2-.11),(xx+rr.uniform(-.2,.2)*ww,yy+dd/2-.03),(xx-ww/2+.06,yy+dd/2-.07)]
            g.face([(px,py,z+.025) for px,py in poly],'stone' if (i+j)%3 else 'rock3')

def lantern(g,x,y,z):
    g.cylinder(x,y,z,.09,3.5,'metal',7)
    g.box(x,y,z+3.38,.52,.52,.12,'metal')
    g.box(x,y,z+3.50,.32,.32,.55,'lamp')
    g.cylinder(x,y,z+4.05,.39,.35,'metal',4,0)
    for a in (-1,1):
        for b in (-1,1):g.box(x+a*.19,y+b*.19,z+3.48,.05,.05,.63,'metal')

def cafe(g,x,y,z,seed):
    rr=random.Random(seed)
    pergola(g,x,y,z,6,4,True)
    for sx in (-1,1):
        xx=x+sx*1.5
        g.cylinder(xx,y,z,.08,.90,'blue',6)
        g.cylinder(xx,y,z+.90,.70,.13,'wood',12)
        for sy in (-1,1):
            yy=y+sy*.95
            g.box(xx,yy,z+.40,.63,.58,.11,'blue',.06)
            g.box(xx,yy+sy*.26,z+.48,.63,.10,.66,'blue',.05)
            for a in (-1,1):
                for b in (-1,1):g.box(xx+a*.23,yy+b*.2,z,.07,.07,.45,'blue')

def district(name,godot_center,angle,width,seed,theme,levels=4):
    """Local -Y faces water, +Y goes inland; overlapping cliff tiers support lanes."""
    rr=random.Random(seed)
    origin=(godot_center[0],-godot_center[1],0)
    ground=Mesh(name+'__Terrain',origin,angle)
    g=Mesh(name+'__Architecture',origin,angle)
    flora=Mesh(name+'__Gardens',origin,angle)
    heights=[4.0,11.0+(seed%3-1),19.0+(seed%5-2),29.0+(seed%3-1)]
    starts=[0,23,49,77]
    depth=115
    rear_cluster=name.startswith('Rear_')
    def wave(xx,row):
        amplitude=8.0 if rear_cluster else 4.0
        return math.sin(xx/width*math.tau*.9+seed*.09+row*.7)*amplitude+math.sin(xx/width*math.tau*1.8+row)*(3.2 if rear_cluster else 1.7)
    # Uneven contour is consistent across stacked terraces, no floating houses.
    coast=[(-width/2-5,3),(-width*.38,-5),(-width*.21,rr.uniform(-10,-1)),(0,-4),(width*.19,rr.uniform(-10,0)),(width*.38,-2),(width/2+5,5)]
    outer=[(-width/2-7,depth-4),(-width*.3,depth+10),(0,depth+13),(width*.3,depth+6),(width/2+7,depth-2)]
    poly=coast+list(reversed(outer))
    # First quay goes below water. Four geometrical rock layers, irregular facets.
    ground.prism(poly,-5,9,'rock','stone2')
    for tier in range(1,levels):
        start=starts[tier];h0=heights[tier-1];h1=heights[tier]
        front=[]
        for i in range(31):
            xx=-width/2-5+i*(width+10)/30
            yy=start+wave(xx,tier)
            front.append((xx,yy))
        p=front+list(reversed(outer))
        ground.prism(p,h0,h1-h0,'rock2' if tier%2 else 'rock','stone2')
        # Visible cliff geology: horizontal strata with varied triangular faces.
        for i in range(len(front)-1):
            a=front[i];b=front[i+1]
            # Smaller physical rock strata with restrained color variation.
            for band in range(3):
                z0=h0+(h1-h0)*band/3;z1=h0+(h1-h0)*(band+1)/3
                mid=((a[0]+b[0])/2+rr.uniform(-1,1),(a[1]+b[1])/2-rr.uniform(.12,.45),z0+(z1-z0)*rr.uniform(.3,.8))
                tint=rr.choices(['rock','rock2','rock3'],[7,3,1])[0]
                ground.face([(a[0],a[1]-.06,z0),(b[0],b[1]-.06,z0),mid],tint)
                ground.face([(a[0],a[1]-.06,z0),mid,(a[0],a[1]-.06,z1)],'rock')
                ground.face([(b[0],b[1]-.06,z0),(b[0],b[1]-.06,z1),mid],tint)
                ground.face([(a[0],a[1]-.06,z1),mid,(b[0],b[1]-.06,z1)],'rock2' if (band+i)%4==0 else 'rock')
            if i%4==0 and abs(a[0]-6)>9:
                ground.sphere(a[0],a[1]-.25,h0+(h1-h0)*.28,2.7,1.1,(h1-h0)*.29,'rock',8,4)
        # Low limewashed retaining cap creates an authentic layered skyline.
        for i in range(len(front)-1):
            a,b=front[i],front[i+1]
            # Leave gaps aligned with the stairs; skip closest cap segments.
            if abs((a[0]+b[0])/2-width*.04)<8:continue
            ground.beam((a[0],a[1]+.20,h1+.33),(b[0],b[1]+.20,h1+.33),.65,'white')
    # Promenade plus quayside coping and several mooring bollards.
    paving(g,0,5,4.03,width-9,5,seed)
    for i in range(8):
        xx=-width*.42+i*width*.84/7
        g.cylinder(xx,1.2,4.04,.23,.67,'stone2',10)
        if i%2==0:lantern(g,xx,7.5,4.03)
    # Set aside meaningful landmarks rather than intersecting dense random houses.
    sites=[]
    for row in range(levels):
        yy=14+starts[row];zz=heights[row]
        # Continuous curved lanes follow the cliff. Overlapping ends close every join.
        for section in range(12):
            sx=-width/2+7+(section+.5)*(width-14)/12
            paving(g,sx,starts[row]+5+(wave(sx,row) if row else 0),zz+.035,(width-14)/12+.1,3.8,seed+row*18+section)
        cols=9 if width>=166 else 7
        gap=(width-22)/cols
        for col in range(cols):
            xx=-width/2+11+(col+.5)*gap+rr.uniform(-1.6,1.6)
            if rear_cluster:xx+=(1-col%3)*3.25+(row%2-.5)*3.0
            py=yy+(wave(xx,row) if row else 0)+rr.uniform(-.7,1.5)
            # Connecting stairs occupy x=+6 without competing buildings.
            if abs(xx-6)<7:continue
            court_x=-width*.37 if theme!='harbor' else width*.35
            landmark=(theme=='church' and row==2 and abs(xx)<20) or (theme=='windmill' and row==1 and (xx>width*.24 or abs(xx+24)<16)) or (theme=='harbor' and row==0 and abs(xx)<20) or (row in (0,2) and abs(xx-court_x)<10)
            if landmark:continue
            # Human-scale buildings become varied stepped compounds, never skyscrapers.
            ww=rr.uniform(8.4,11.8);dd=rr.uniform(10,13);hh=rr.choice([4.7,5.5,6.0,7.9,8.7])
            current_front=starts[row]+(wave(xx,row) if row else 0)
            next_front=starts[row+1]+wave(xx,row+1) if row<levels-1 else depth-1
            # Fit each building to the real terrace depth, keeping a front lane
            # and avoiding roofs disappearing into the next uphill plateau.
            dd=min(dd,max(5.7,next_front-current_front-8.2))
            min_center=current_front+6.9+dd/2
            max_center=next_front-1.2-dd/2
            py=max(min_center,min(max_center,py))
            if row==0:hh=min(hh,6)
            kind=(col+row*2+seed)%7
            if row==3 and kind==5:kind=2
            old_origin,old_angle=g.origin,g.angle
            c=math.cos(old_angle);s=math.sin(old_angle)
            g.origin=(old_origin[0]+xx*c-py*s,old_origin[1]+xx*s+py*c,0)
            g.angle=old_angle+rr.uniform(-.075,.075)
            hseed=seed+row*43+col*7
            plinth=(1.25+.55*((col+row)%3)) if rear_cluster and (col+row)%3!=0 else 0.0
            if plinth:
                # Split-level compounds create a less regular hilltop outline.
                # Each raised dwelling has a solid footing and a real entry stair.
                g.box(0,0,zz,ww+.38,dd+.38,plinth,'white',.18)
                entry_x=-ww*.23 if hseed%2 else ww*.24
                stairs(g,entry_x,-dd/2-2.6,zz,1.8,plinth,2.6,7)
            house(g,0,0,zz+plinth,ww,dd,hh,kind,hseed)
            g.origin,g.angle=old_origin,old_angle
            sites.append({'local':[round(xx,2),round(py,2),zz+plinth],'foundation_height':plinth,'size':[round(ww,2),round(dd,2),hh],'variant':kind})
            if (col+row)%3==0:tree(flora,xx+ww*.6,py+dd*.3,zz,(row+col)%2==0,.9+rr.random()*.4)
            if row==1 and col==2:
                # Walk-through lane portal with a thick white arch and blue lintel.
                g.arch(xx+ww*.65,py-dd*.30,zz,2.9,4.7,.85,'white')
                g.box(xx+ww*.65,py-dd*.30,zz+4.65,3.4,1.05,.24,'trim',.08)
                pot(flora,xx+ww*.65+1.7,py-dd*.30,zz,True,1.3)
        # Courtyard rhythm changes from civic square to café terraces.
        if row in (0,2):
            tx=-width*.37 if theme!='harbor' else width*.35
            ty=starts[row]+14+(wave(tx,row) if row else 0)
            terrace(g,tx,ty,zz,11,10)
            if row==0:cafe(g,tx,ty,zz+.06,seed)
            else:tree(flora,tx,ty,zz,False,1.4)
        if row<levels-1:
            # A real supported flight links the lane to the next tier.
            rise=heights[row+1]-zz
            y0=starts[row]+5+(wave(6,row) if row else 0)
            y1=starts[row+1]+.30+wave(6,row+1)
            stairs(g,6,y0,zz,3.4,rise,y1-y0,20)
            paving(g,6,y1+2.45,heights[row+1]+.055,7,4.8,seed+row)
        for col in range(4):
            xx=-width*.36+col*width*.24
            pot(flora,xx,starts[row]+7.5+(wave(xx,row) if row else 0),zz,True,1.6)
    if theme=='church':
        church(g,-4,starts[2]+15+wave(-4,2),heights[2],1.05)
        paving(g,-4,starts[2]+2+wave(-4,2),heights[2]+.045,27,10,seed+8)
    elif theme=='windmill':
        windmill(g,width*.35,starts[1]+14+wave(width*.35,1),heights[1],1.2)
        terrace(g,width*.35,starts[1]+14+wave(width*.35,1),heights[1],23,18)
        # A lower waterfront chapel stays inside the forward gameplay camera's
        # horizontal field instead of hiding on the distant upper terrace.
        church(g,-24,starts[1]+14+wave(-24,1),heights[1],.82)
    elif theme=='harbor':
        terrace(g,0,18,4,27,16);cafe(g,-5,18,4.05,seed);cafe(g,5,18,4.05,seed+1)
        # Pier foundation is continuous into the quay and passes below the sea.
        g.box(-width*.28,-13,-3,7,34,7,'rock',.25)
        paving(g,-width*.28,-13,4.05,7.3,34,seed+1)
        g.box(-width*.28,-30,-3,34,7,7,'rock',.25)
        paving(g,-width*.28,-30,4.06,34,7.3,seed+2)
        for i in range(3):boat(g,-width*.28-11+i*10,-37,.35,1.55)
    # Soft natural inland transition: sparse olives, cypress and small outcrop faces.
    for i in range(14):
        xx=rr.uniform(-width*.45,width*.45);yy=rr.uniform(104,114)
        tree(flora,xx,yy,heights[-1],i%3==0,rr.uniform(1.1,1.7))
    for i in range(12):
        xx=-width*.47+i*width*.94/11;yy=-6+math.sin(i)*3
        ground.sphere(xx,yy,-1,rr.uniform(2.5,5),rr.uniform(3,6),rr.uniform(2,4),'rock' if i%2 else 'rock3',7,3)
    objects=[ground.finish(),g.finish(),flora.finish()]
    return {'name':name,'godot_origin':[godot_center[0],0,godot_center[1]],'blender_angle':angle,'theme':theme,'houses':len(sites),'building_sites':sites,'width':width,'inland_depth':depth,'terrace_heights':heights},objects

def setup_review():
    world=bpy.data.worlds.new('Mediterranean clear sky');scene.world=world;world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=rgba('c4dce8')
    world.node_tree.nodes['Background'].inputs[1].default_value=.65
    sun_data=bpy.data.lights.new('Warm Aegean sun','SUN');sun_data.energy=3.2;sun_data.angle=math.radians(7)
    sun=bpy.data.objects.new('Warm Aegean sun',sun_data);REVIEW.objects.link(sun);sun.rotation_euler=(.5,-.45,-.65)
    water=bpy.data.materials.new('REVIEW Sea');water.diffuse_color=rgba('359aa9');water.use_nodes=True
    p=water.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=rgba('359aa9');p.inputs['Roughness'].default_value=.30;p.inputs['Metallic'].default_value=.12
    me=bpy.data.meshes.new('REVIEW Sea');me.from_pydata([(-2500,-2500,-.10),(2500,-2500,-.10),(2500,2500,-.10),(-2500,2500,-.10)],[],[(0,1,2,3)]);me.materials.append(water)
    ob=bpy.data.objects.new('REVIEW ONLY sea plane (not exported)',me);REVIEW.objects.link(ob)
    cam_data=bpy.data.cameras.new('Architecture review');cam_data.clip_end=10000;cam=bpy.data.objects.new('Architecture review',cam_data);REVIEW.objects.link(cam);scene.camera=cam
    return cam

def render(cam,name,eye,target,lens=38,ortho=None):
    cam.location=eye;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO' if ortho else 'PERSP';cam.data.lens=lens
    if ortho:cam.data.ortho_scale=ortho
    scene.render.filepath=str(PREVIEWS/(name+'.png'))
    bpy.ops.render.render(write_still=True)

def export_with_vertex_palette(objects,target):
    """Keep editable source materials; pack static color into glTF COLOR_0.

    One palette material preserves each roughness value group. Window/lantern
    emission remains separately named for WeatherCycle. This replaces hundreds
    of color-only surface submissions without removing authored detail.
    """
    packed=[];palette={};surface_count=0;restore_names=[]
    for original in objects:
        original_name=original.name;mesh_name=original.data.name
        original.name=original_name+'__Editable';original.data.name=mesh_name+'__Editable'
        ob=original.copy();ob.data=original.data.copy();ob.name=original_name;ob.data.name=mesh_name
        restore_names.append((original,original_name,mesh_name))
        EXPORT.objects.link(ob);mesh=ob.data
        attr=mesh.color_attributes.new(name='TownColor',type='FLOAT_COLOR',domain='CORNER')
        oldmats=list(mesh.materials);newmats=[];faceids=[]
        for poly in mesh.polygons:
            old=oldmats[poly.material_index]
            isglow=old.name.startswith('Santorini Window') or old.name.startswith('Santorini Lantern')
            if isglow:
                mat=old;col=(1,1,1,1)
            else:
                p=old.node_tree.nodes.get('Principled BSDF');rough=round(p.inputs['Roughness'].default_value,2)
                if rough not in palette:
                    mat=bpy.data.materials.new('Santorini Vertex Palette Roughness '+str(rough));mat.use_nodes=True
                    mp=mat.node_tree.nodes.get('Principled BSDF');mp.inputs['Base Color'].default_value=(1,1,1,1);mp.inputs['Roughness'].default_value=rough
                    vc=mat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='TownColor';mat.node_tree.links.new(vc.outputs['Color'],mp.inputs['Base Color'])
                    palette[rough]=mat
                mat=palette[rough];col=old.diffuse_color
            if mat not in newmats:newmats.append(mat)
            faceids.append(newmats.index(mat))
            for loop in poly.loop_indices:attr.data[loop].color=col
        mesh.materials.clear()
        for mat in newmats:mesh.materials.append(mat)
        for poly,i in zip(mesh.polygons,faceids):poly.material_index=i
        surface_count+=len(newmats);packed.append(ob)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(False)
    for ob in packed:ob.select_set(True)
    bpy.context.view_layer.objects.active=packed[0]
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_materials='EXPORT',export_extras=True,export_yup=True,export_cameras=False,export_lights=False,export_apply=True)
    pack_color_buffers(target)
    # Re-render original editable objects only and save that source scene.
    for ob in packed:
        mesh=ob.data;bpy.data.objects.remove(ob,do_unlink=True);bpy.data.meshes.remove(mesh)
    for ob,name,mesh_name in restore_names:ob.name=name;ob.data.name=mesh_name
    return len(palette)+2,surface_count

def pack_color_buffers(path):
    """Loss-bounded standard glTF normalized RGBA8, without a codec dependency."""
    raw=path.read_bytes();json_len=struct.unpack_from('<I',raw,12)[0]
    data=json.loads(raw[20:20+json_len]);bin_offset=20+json_len+8;binary=raw[bin_offset:]
    colors={p['attributes']['COLOR_0'] for m in data['meshes'] for p in m['primitives'] if 'COLOR_0' in p['attributes']}
    color_views={data['accessors'][i]['bufferView']:i for i in colors}
    packed=bytearray()
    for i,view in enumerate(data['bufferViews']):
        payload=binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
        if i in color_views:
            accessor=data['accessors'][color_views[i]]
            channels=3 if accessor['type']=='VEC3' else 4
            if accessor['componentType']==5126 and accessor['type'] in ('VEC3','VEC4') and accessor.get('byteOffset',0)==0 and len(payload)==accessor['count']*channels*4:
                values=np.frombuffer(payload,dtype='<f4').reshape(-1,channels)
                if channels==3:values=np.column_stack((values,np.ones(len(values),dtype=np.float32)))
                payload=np.rint(np.clip(values,0,1)*255).astype(np.uint8).tobytes()
                accessor['componentType']=5121;accessor['normalized']=True;accessor['type']='VEC4'
        while len(packed)%4:packed.append(0)
        view['byteOffset']=len(packed);view['byteLength']=len(payload);packed.extend(payload)
    while len(packed)%4:packed.append(0)
    data['buffers'][0]['byteLength']=len(packed)
    encoded=json.dumps(data,separators=(',',':')).encode('utf-8')
    while len(encoded)%4:encoded+=b' '
    total=12+8+len(encoded)+8+len(packed)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,total)+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(packed),b'BIN\0')+packed)

def main():
    layout=[];objects=[]
    # Rear settlement is a unified caldera backdrop with the main blue dome off-axis.
    for i,x in enumerate((-130,0,130)):
        cfg,obs=district('Rear_'+str(i+1),[x,-221],0,136,120+i*27,'church' if i==2 else 'village')
        layout.append(cfg);objects.extend(obs)
    # Both shores remain well outside course/shark/helicopter volumes.
    for side in (-1,1):
        for i,z in enumerate((-108,65,238,411,584)):
            shore=103+5*math.sin(i*1.8+side)
            theme=('harbor' if (side==1 and i in (0,3)) else 'windmill' if (side==1 and i==2) else 'church' if (side==-1 and i==2) else 'village')
            if theme=='harbor':shore=118.0
            cfg,obs=district(('West' if side<0 else 'East')+'_'+str(i+1),[side*shore,z],math.pi/2 if side<0 else -math.pi/2,174,500+(side+1)*137+i*39,theme)
            layout.append(cfg);objects.extend(obs)
    cam=setup_review()
    # Save editable source with one data block per district layer and named materials.
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'aiquiz_santorini_town.blend'))
    target=ASSET/'aiquiz_santorini_town.glb'
    runtime_materials,runtime_surfaces=export_with_vertex_palette(objects,target)
    triangles=sum(sum(len(p.vertices)-2 for p in ob.data.polygons) for ob in objects)
    all_points=[v.co for ob in objects for v in ob.data.vertices]
    corridor_min=min(abs(v.x) for v in all_points if -v.y>-150)
    assert corridor_min>=70.0, f'Unexpected scenery in protected course corridor: {corridor_min}'
    bounds={'min':[min(v.x for v in all_points),min(v.z for v in all_points),min(-v.y for v in all_points)],'max':[max(v.x for v in all_points),max(v.z for v in all_points),max(-v.y for v in all_points)]}
    report={'seed':9132026,'blender':bpy.app.version_string,'units':'metres','local_sea_level':0,'godot_root_y':-9.2,'open_course_direction':'+Z','minimum_scenery_abs_x_where_z_above_minus150':corridor_min,'godot_local_bounds':bounds,'rear_waterfront_godot_z':-212,'districts':len(layout),'export_meshes':len(objects),'triangles':triangles,'materials':runtime_materials,'authoring_materials':len(M),'export_surfaces':runtime_surfaces,'vertex_color_palette':True,'counts':COUNTS,'external_assets':[],'additional_cost':0,'layout':layout,'editable_source':'source/aiquiz_santorini_town.blend','deterministic_builder':'source/build_santorini_town.py'}
    (SOURCE/'build_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('SANTORINI_BUILD_COMPLETE '+json.dumps({k:v for k,v in report.items() if k!='layout'}),flush=True)
    # Preview views approximate the installation's central sea corridor and detailed architecture.
    render(cam,'town_aerial',(790,-770,700),(0,-150,10),32)
    render(cam,'rear_church_detail',(185,158,77),(130,306,39),50)
    render(cam,'harbor_detail',(24,43,70),(135,111,20),42)
    render(cam,'stage_corridor_day',(0,9,13.7),(0,-180,23),24)
    # Persist useful opening camera and the viewport's current hero composition.
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'aiquiz_santorini_town.blend'))

if __name__=='__main__':main()

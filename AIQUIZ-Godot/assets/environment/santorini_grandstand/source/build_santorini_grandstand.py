"""Original Cycladic waterfront terraces for AIQUIZ; no external asset dependency.

Run: blender --background --factory-startup --python this_file.py
The editable Blender scene and game GLB share a 160 m longitudinal datum.
Blender X points away from the course, Y runs along it, Z is up. glTF maps
that to Godot (X, Z, -Y); grandstand_crowd.gd uses the same seating constants.
"""
from __future__ import annotations

import json
import math
import random
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector

SOURCE = Path(__file__).resolve().parent
ASSET = SOURCE.parent
PREVIEW = SOURCE / "previews"
PREVIEW.mkdir(parents=True, exist_ok=True)
RNG = random.Random(9312026)

ROW_COUNT, ROW_FRONT, ROW_PITCH, ROW_RISE = 4, 1.15, 1.25, 0.40
ROW_BASE, SEAT_OFFSET = 0.32, 0.545
SEAT_EDGE, SEAT_PITCH = 77.5, 0.92
AISLES = (-60., -40., -20., 0., 20., 40., 60.)
AISLE_HALF_WIDTH, AISLE_CLEARANCE = 1.10, 1.49
FRONT_X, BACK_X, BASE_LENGTH = -0.8, 8.4, 160.0

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for data in list(bpy.data.materials):
    bpy.data.materials.remove(data)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1600, 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.40, 0.65, 0.86, 1.)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.45

export_collection = bpy.data.collections.new("Santorini terrace - editable geometry")
scene.collection.children.link(export_collection)
preview_collection = bpy.data.collections.new("Presentation only - not exported")
scene.collection.children.link(preview_collection)

def material(name, color, roughness=0.8, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return mat

materials = [
    material("Cycladic chalk plaster", (0.88, 0.86, 0.79)),
    material("Limestone coping", (0.72, 0.69, 0.59)),
    material("Aegean cobalt painted wood", (0.014, 0.12, 0.43), 0.55),
    material("Aegean blue seat highlights", (0.045, 0.29, 0.65), 0.58),
    material("Warm stone paving", (0.46, 0.48, 0.44)),
    material("Volcanic sea footings", (0.23, 0.22, 0.20)),
    material("Sunwashed pergola timber", (0.59, 0.42, 0.23)),
    material("Terracotta pots", (0.54, 0.25, 0.13)),
    material("Olive and bougainvillea foliage", (0.15, 0.30, 0.10)),
    material("Bougainvillea flowers", (0.78, 0.055, 0.27)),
    material("Bougainvillea pale petals", (0.94, 0.21, 0.48)),
    material("Lantern dark brass", (0.22, 0.17, 0.095), 0.5),
    material("Lantern warm glass", (0.98, 0.67, 0.24), 0.5),
]
lamp_shader = materials[-1].node_tree.nodes.get("Principled BSDF")
lamp_shader.inputs["Emission Color"].default_value = (1., 0.48, 0.10, 1.)
lamp_shader.inputs["Emission Strength"].default_value = 0.45

class Geometry:
    def __init__(self):
        self.v, self.f, self.m = [], [], []
        self.elements = defaultdict(int)

    def mesh(self, vertices, faces, mat, tag="part"):
        offset = len(self.v)
        self.v.extend(vertices)
        self.f.extend([tuple(offset+i for i in face) for face in faces])
        self.m.extend([mat]*len(faces))
        self.elements[tag] += 1

    def box(self, center, size, mat, tag="block", bevel=0.):
        x, y, z = center
        sx, sy, sz = [a*.5 for a in size]
        if bevel > 0:
            # Eight-sided horizontal footprint softens exposed Cycladic corners.
            b = min(bevel, sx*.7, sy*.7)
            ring = [(-sx+b,-sy),(sx-b,-sy),(sx,-sy+b),(sx,sy-b),
                    (sx-b,sy),(-sx+b,sy),(-sx,sy-b),(-sx,-sy+b)]
            vertices = [(x+a,y+b_,z+c) for c in (-sz,sz) for a,b_ in ring]
            faces = [tuple(range(7,-1,-1)),tuple(range(8,16))]
            faces += [(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
        else:
            vertices = [(x+a,y+b,z+c) for c in (-sz,sz) for b in (-sy,sy) for a in (-sx,sx)]
            faces = [(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)]
        self.mesh(vertices,faces,mat,tag)

    def beam(self, start, finish, width, mat, tag="beam"):
        a,b = Vector(start),Vector(finish)
        direction = b-a
        basis = direction.to_track_quat("Z","Y").to_matrix()
        center = (a+b)*.5
        half = direction.length*.5
        vertices = [tuple(center+basis@Vector((x,y,z))) for z in (-half,half)
                    for y in (-width*.5,width*.5) for x in (-width*.5,width*.5)]
        self.mesh(vertices,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],mat,tag)

    def cone(self, center, lower_radius, upper_radius, height, mat, sides=10, tag="pot"):
        x,y,z=center
        vertices=[(x+radius*math.cos(math.tau*i/sides),y+radius*math.sin(math.tau*i/sides),z+dz)
                  for radius,dz in ((lower_radius,-height*.5),(upper_radius,height*.5)) for i in range(sides)]
        faces=[tuple(range(sides-1,-1,-1)),tuple(range(sides,sides*2))]
        faces += [(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
        self.mesh(vertices,faces,mat,tag)

    def bush(self, center, radii, mat, tag="foliage"):
        # Broad faceted foliage reads from the game camera without alpha cards.
        x,y,z=center
        rx,ry,rz=radii
        vertices=[(x,y,z-rz)]
        for h in (-.38,.42):
            for i in range(7):
                a=math.tau*i/7
                jitter=RNG.uniform(.82,1.08)
                vertices.append((x+rx*math.cos(a)*jitter,y+ry*math.sin(a)*jitter,z+rz*h))
        vertices.append((x,y,z+rz))
        faces=[(0,1+(i+1)%7,1+i) for i in range(7)]
        faces += [(1+i,1+(i+1)%7,8+(i+1)%7,8+i) for i in range(7)]
        faces += [(15,8+i,8+(i+1)%7) for i in range(7)]
        self.mesh(vertices,faces,mat,tag)

    def create(self, name, parent):
        mesh=bpy.data.meshes.new(name)
        mesh.from_pydata(self.v,[],self.f)
        mesh.materials.clear()
        for mat in materials:
            mesh.materials.append(mat)
        for polygon,mi in zip(mesh.polygons,self.m):
            polygon.material_index=mi
        mesh.update()
        obj=bpy.data.objects.new(name,mesh)
        export_collection.objects.link(obj)
        obj.parent=parent
        obj["element_counts"]=json.dumps(dict(self.elements))
        return obj

root=bpy.data.objects.new("Santorini_Open_Terrace",None)
export_collection.objects.link(root)
root["design"]="Original AIQUIZ Cycladic waterfront terrace, 2026-09-13"
root["nominal_conveyor_length_m"]=BASE_LENGTH
root["seat_rows"]=ROW_COUNT
root["seat_top_m"]=ROW_BASE+SEAT_OFFSET
root["row_rise_m"]=ROW_RISE
root["course_facing_axis"]="-X"
root["max_continuous_silhouette_m"]=2.435

def flower_pot(g,x,y,z,scale=1.):
    g.cone((x,y,z+.31*scale),.22*scale,.34*scale,.62*scale,7,tag="flower pot")
    g.cone((x,y,z+.58*scale),.355*scale,.355*scale,.13*scale,7,tag="pot rim")
    g.bush((x,y,z+.80*scale),(.43*scale,.40*scale,.36*scale),8)
    for i in range(5):
        a=math.tau*i/5
        g.bush((x+math.cos(a)*.24*scale,y+math.sin(a)*.24*scale,z+1.00*scale),
               (.19*scale,.17*scale,.12*scale),9 if i%2 else 10,"flower cluster")

def lantern(g,x,y,z):
    g.box((x,y,z+.13),(.17,.17,.27),12,"warm lantern pane")
    g.box((x,y,z+.29),(.25,.25,.06),11,"lantern cap",.025)
    g.box((x,y,z-.015),(.23,.23,.04),11,"lantern base",.02)
    for dx in (-.09,.09):
        for dy in (-.09,.09):
            g.box((x+dx,y+dy,z+.13),(.025,.025,.29),11,"lantern frame")

def pergola(g,y):
    base=ROW_BASE+(ROW_COUNT-1)*ROW_RISE
    # Three small shade pockets only, all at the rear of the spectator rows.
    for x in (6.05,8.10):
        for yy in (y-2.8,y+2.8):
            g.box((x,yy,base+1.18),(.13,.13,2.36),0,"pergola post",.025)
            g.box((x,yy,base+.16),(.24,.24,.32),0,"post foot",.035)
    for x in (6.00,8.15):
        g.box((x,y,base+2.34),(.18,6.15,.21),6,"pergola lintel",.025)
    for i in range(13):
        yy=y-3.+.5*i
        g.box((7.08,yy,base+2.48),(2.55,.12,.16),6,"open pergola slat",.02)
    for yy in (y-2.7,y+2.7):
        flower_pot(g,8.0,yy,base,.95)
        for j in range(5):
            g.bush((8.08,yy,base+1.00+j*.33),(.25,.24,.36),8,"climbing foliage")
        for j in range(5):
            g.bush((7.8-j*.33,yy,base+2.47),(.30,.31,.19),9 if j%2 else 10,"pergola flowers")
    # Built-in white benches keep the rear promenade visually quiet.
    for yy in (y-1.9,y+1.9):
        g.box((7.2,yy,base+.24),(1.5,.42,.48),0,"pergola stone bench",.09)
        g.box((7.2,yy,base+.51),(1.5,.46,.07),3,"pergola bench blue cushion",.08)

seat_count=0
for section in range(8):
    g=Geometry()
    y0,y1=-80.+section*20.,-60.+section*20.
    yc=(y0+y1)*.5
    g.box((3.8,yc,-.10),(9.2,20.,.64),0,"white waterfront deck",.08)
    g.box((-.63,yc,-.48),(.31,20.,.22),1,"waterfront cornice",.03)
    # Thin rounded coping and a low open blue rail along the promenade.
    g.box((-.60,yc,.42),(.26,20.,.40),0,"front low wall",.045)
    g.box((-.60,yc,.64),(.34,20.,.06),1,"front wall coping",.04)
    for yy in [y0+.45+j*2.4 for j in range(9) if y0+.45+j*2.4<y1-.2]:
        g.box((-.60,yy,.89),(.045,.045,.52),2,"front rail upright")
    g.box((-.60,yc,1.12),(.055,20.,.06),2,"front rail handrail")
    # Deck stone patches: low polygon pale irregular inset paving, white joints.
    for j in range(15):
        yy=y0+.45+j*1.31
        g.box((.02,yy,.229),(.59,1.11,.018),4 if j%3 else 1,"promenade stone",.12)
        g.box((7.10,yy,1.529),(1.70,1.13,.018),4 if j%3 else 1,"rear paving",.14)
    # Narrow ocean piers and open arches under the promenade meet the sea at -9.2.
    for x in (.00,7.65):
        for yy in ((y0+.2,y1-.2) if section==7 else (y0+.2,)):
            g.box((x,yy,-5.1),(.70,.72,9.8),0,"white stone sea pier",.06)
            g.box((x,yy,-8.90),(1.15,1.20,2.2),5,"volcanic pier footing",.09)
            g.box((x,yy,-.65),(1.00,1.16,.52),1,"pier capital",.06)
    # Low stone arches span the piers, below the floor rather than above eye level.
    for x in (.0,7.65):
        for i in range(12):
            a0=math.pi*i/12
            a1=math.pi*(i+1)/12
            aa=(x,y0+.2+9.99*(1-math.cos(a0)),-3.1+2.48*math.sin(a0))
            bb=(x,y0+.2+9.99*(1-math.cos(a1)),-3.1+2.48*math.sin(a1))
            g.beam(aa,bb,.36,0,"open supporting arch")
    # Stepped seating; four rises and no continuous high rear wall.
    for row in range(ROW_COUNT):
        x=ROW_FRONT+row*ROW_PITCH
        top=ROW_BASE+row*ROW_RISE
        front=x-.55
        left=y0+AISLE_HALF_WIDTH if section else y0+.3
        right=y1-AISLE_HALF_WIDTH if section<7 else y1-.3
        g.box(((front+5.72)*.5,(left+right)*.5,(top+.22)*.5),
              (5.72-front,right-left,top-.22),0,"white seating terrace",.045)
        g.box((front+.065,(left+right)*.5,top+.016),(.13,right-left,.032),1,"terrace rounded nosing",.025)
    g.box((7.06,yc,.87),(2.68,20.,1.30),0,"rear promenade foundation",.06)
    # Rear blue rails are transparent in silhouette, white posts remain low.
    for yy in [y0+.3+j*3.2 for j in range(7) if y0+.3+j*3.2<y1]:
        g.box((8.18,yy,1.96),(.10,.10,.88),2,"rear rail upright",.018)
    for height in (1.88,2.40):
        g.box((8.18,yc,height),(.065,20.,.07),2,"rear open rail")
    # Seven half-height stairs align every other tread with a seat row. Their
    # final landing is flush with the rear promenade, avoiding a raised lip.
    if section<7:
        for step in range(7):
            start=.6+step*.625
            top=.32+step*.20
            g.box((start+.3125,y1,(top+.22)*.5),(.625,2.2,top-.22),0,"aisle stair",.035)
            g.box((start+.035,y1,top+.015),(.07,2.2,.03),1,"stair nosing")
        g.box(((4.975+5.72)*.5,y1,.87),(.745,2.2,1.30),0,"flush upper stair landing",.025)
        for sign in (-1.,1.):
            yy=y1+sign*.89
            for x,z in ((.70,1.22),(5.70,2.42)):
                g.box((x,yy,z-.45),(.05,.05,.90),2,"stair rail foot")
            g.beam((.7,yy,1.22),(5.7,yy,2.42),.055,2,"stair blue handrail")
    for row in range(ROW_COUNT):
        for column in range(169):
            yy=-SEAT_EDGE+column*SEAT_PITCH
            if yy<y0 or yy>=y1 or yy>SEAT_EDGE or any(abs(yy-a)<AISLE_CLEARANCE for a in AISLES):
                continue
            x=ROW_FRONT+row*ROW_PITCH
            floor=ROW_BASE+row*ROW_RISE
            seat_mat=3 if (column//4+row)%5==0 else 2
            g.box((x,yy,floor+.50),(.61,.66,.09),seat_mat,"seat cushion",.045)
            g.box((x+.265,yy,floor+.78),(.10,.65,.43),seat_mat,"seat back",.040)
            for dy in (-.235,.235):
                for dx in (-.20,.22):
                    g.box((x+dx,yy+dy,floor+.245),(.055,.055,.49),2,"painted chair leg")
            seat_count+=1
    for yy in (yc-5.0,yc+5.0):
        # Flowers at the rear and at the stair landing keep all audience aisles open.
        flower_pot(g,7.78,yy,1.52,.72)
        lantern(g,8.12,yy,2.40)
    if section in (0,7):
        end=y0+.2 if section==0 else y1-.2
        for row in range(4):
            x=ROW_FRONT+row*ROW_PITCH
            top=ROW_BASE+row*ROW_RISE
            g.box((x,end,top+.30),(1.20,.28,.60),0,"stepped end balustrade",.07)
            g.box((x,end,top+.63),(1.25,.34,.06),1,"end coping",.045)
    for pergola_y in (-50.,10.,65.):
        if y0<=pergola_y<y1:
            pergola(g,pergola_y)
    g.create(f"Terrace_Block_{section+1:02d}",root)

# Keep eight semantic source blocks editable, but batch the exported geometry
# into one mesh with shared material surfaces. This cuts 99 surfaces to 13.
bpy.ops.object.select_all(action="DESELECT")
temporary=[]
source_meshes=[o for o in export_collection.objects if o.type=="MESH"]
for original in source_meshes:
    duplicate=original.copy()
    duplicate.data=original.data.copy()
    export_collection.objects.link(duplicate)
    duplicate.select_set(True)
    temporary.append(duplicate)
bpy.context.view_layer.objects.active=temporary[0]
bpy.ops.object.join()
batched=bpy.context.object
batched.name="Santorini_Terrace_Geometry"
root.select_set(True)
glb=ASSET/"santorini_open_terrace.glb"
bpy.ops.export_scene.gltf(filepath=str(glb),export_format="GLB",use_selection=True,
                          export_apply=True,export_animations=False,export_cameras=False,
                          export_lights=False,export_extras=True)
batched_mesh=batched.data
bpy.data.objects.remove(batched,do_unlink=True)
bpy.data.meshes.remove(batched_mesh)

triangles=0
for obj in export_collection.objects:
    if obj.type=="MESH":
        obj.data.calc_loop_triangles()
        triangles+=len(obj.data.loop_triangles)
coords=[(v.co.x,v.co.z,-v.co.y) for obj in source_meshes for v in obj.data.vertices]
bounds={"min":[round(min(v[i] for v in coords),4) for i in range(3)],
        "max":[round(max(v[i] for v in coords),4) for i in range(3)]}
report={"seat_count":seat_count,"rows":ROW_COUNT,"base_length_m":BASE_LENGTH,
        "triangles":triangles,"export_mesh_objects":1,"editable_source_sections":8,
        "shared_materials":len(materials),"export_surfaces":len(materials),
        "godot_bounds":bounds,
        "seat_grid":{"front_x":ROW_FRONT,"row_pitch":ROW_PITCH,"seat_top":ROW_BASE+SEAT_OFFSET,
                     "row_rise":ROW_RISE,"seat_edge":SEAT_EDGE,"seat_pitch":SEAT_PITCH,
                     "aisles":AISLES,"aisle_clearance":AISLE_CLEARANCE},
        "pergolas":{"count":3,"length_each":6.15,"total_longitudinal_coverage_fraction":3*6.15/160},
        "external_assets":[],"render_note":"Blender asset review only; actual Godot gameplay acceptance is separate."}
(ASSET/"asset_report.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
print("SANTORINI_GRANDSTAND_REPORT "+json.dumps(report),flush=True)

def preview_link(obj):
    for coll in list(obj.users_collection):
        coll.objects.unlink(obj)
    preview_collection.objects.link(obj)

bpy.ops.mesh.primitive_plane_add(size=1200,location=(0,0,-9.21))
sea=bpy.context.object
sea.name="Preview sea - not exported"
sea.data.materials.append(material("Preview turquoise sea",(.025,.26,.34),.22))
preview_link(sea)
bpy.ops.object.light_add(type="SUN",location=(-30,-20,60))
sun=bpy.context.object
sun.data.energy=2.6
sun.data.angle=math.radians(12)
sun.rotation_euler=(math.radians(28),math.radians(-24),math.radians(-25))
preview_link(sun)
bpy.ops.object.camera_add(location=(-38,-46,23))
camera=bpy.context.object
camera.name="Review camera - not exported"
camera.data.type="ORTHO"
camera.data.ortho_scale=59
scene.camera=camera
preview_link(camera)

def render(name,position,target,scale):
    camera.location=position
    camera.rotation_euler=(Vector(target)-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.ortho_scale=scale
    scene.render.filepath=str(PREVIEW/f"{name}.png")
    bpy.ops.render.render(write_still=True)

render("santorini_terrace_detail",(-28,-29,19),(3.,-39.,.6),35.)
render("santorini_terrace_overview",(-105,-100,77),(3.,0.,-1.8),179.)
render("santorini_terrace_course_eye",(-25,-27,4.5),(3.,10.,1.0),48.)
camera.location=(-28,-29,19)
camera.rotation_euler=(Vector((3.,-39.,.6))-camera.location).to_track_quat("-Z","Y").to_euler()
camera.data.ortho_scale=35.
scene.render.filepath=str(PREVIEW/"santorini_terrace_detail.png")
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/"santorini_open_terrace.blend"))
print("SANTORINI_GRANDSTAND_DONE",flush=True)

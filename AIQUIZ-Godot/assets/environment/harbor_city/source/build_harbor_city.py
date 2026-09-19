"""Original AIQUIZ harbor city; Blender 5.1, no downloads or paid dependencies.

Run: blender --background --factory-startup --python build_harbor_city.py
The script creates its own scene and never removes objects from another scene.
One Blender unit is one metre; Z=0 is sea level. glTF converts Z-up to Godot Y-up.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

SOURCE = Path(__file__).resolve().parent
ASSET = SOURCE.parent
TEXTURES = SOURCE / "textures"
PREVIEWS = SOURCE / "previews"
for folder in (TEXTURES, PREVIEWS):
    folder.mkdir(parents=True, exist_ok=True)

scene = bpy.data.scenes.new("AIQUIZ U Harbor City")
bpy.context.window.scene = scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1600
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"


def collection(name):
    obj = bpy.data.collections.new(name)
    scene.collection.children.link(obj)
    return obj


districts = {name: collection(name) for name in (
    "01 Reclaimed island and quay", "02 Waterfront promenade",
    "03 West residential terraces", "04 Civic harbour centre",
    "05 East business district", "06 Park and avenue trees",
)}
review = collection("REVIEW ONLY - sea camera lights")


def linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def color(hex_value):
    value = hex_value.lstrip("#")
    return tuple(linear(int(value[i:i+2], 16) / 255) for i in (0, 2, 4)) + (1,)


def texture(name, pixels):
    h, w, _ = pixels.shape
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    # Blender image pixels are scene-linear; PNG writes sRGB.
    rgb = pixels[:, :, :3]
    pixels[:, :, :3] = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
    img.pixels.foreach_set(pixels.astype(np.float32).ravel())
    img.filepath_raw = str(TEXTURES / (name + ".png"))
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


def facade_images(name, wall_rgb, glass_rgb):
    size, bay = 256, 64
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[:, :, :3] = np.array(wall_rgb) / 255
    glow = np.ones_like(rgba)
    glow[:, :, :3] = 0
    for row in range(4):
        for col in range(4):
            x, y = col * bay, row * bay
            # Broad reveals, deep window sill, a continuous vertical mullion.
            rgba[y+12:y+56, x+8:x+56, :3] = np.array([45, 65, 70]) / 255
            pane = np.array(glass_rgb) / 255 * (1 + .045 * ((row+col) % 3 - 1))
            rgba[y+15:y+54, x+11:x+53, :3] = pane
            rgba[y+15:y+54, x+31:x+33, :3] = np.array(wall_rgb) / 255 * .65
            rgba[y+51:y+54, x+11:x+53, :3] = np.minimum(pane * 1.4, 1)
            rgba[y+9:y+12, x+7:x+57, :3] = np.array(wall_rgb) / 255 * .65
            if (row * 7 + col * 3) % 5 < 2:
                glow[y+16:y+51, x+12:x+52, :3] = [.95, .65, .30]
                glow[y+16:y+51, x+31:x+33, :3] = 0
    return texture(name + "_albedo", rgba), texture(name + "_windows", glow)


def material(name, hex_value, roughness=.8, images=None, metallic=0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = color(hex_value)
    mat.use_backface_culling = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = color(hex_value)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if images:
        for img, socket in zip(images, ("Base Color", "Emission Color")):
            if img is None:
                continue
            tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
            tex.image = img
            tex.interpolation = "Linear"
            tex.extension = "REPEAT"
            mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs[socket])
        bsdf.inputs["Emission Strength"].default_value = .25 if len(images) > 1 else 0
    return mat


M = {
    "chalk": material("Harbor Chalk Limestone", "dfddcd"),
    "sand": material("Harbor Sandstone", "b8a68b"),
    "coral": material("Harbor Muted Terracotta", "b77660"),
    "roof": material("Harbor Standing Seam Copper Roof", "668b88", .6, metallic=.15),
    "glass": material("Harbor Blue Teal Glass", "375d67", .34, metallic=.15),
    "dark": material("Harbor Tide Line Basalt", "46565e"),
    "paving": material("Harbor Warm Promenade Paving", "b0ac96"),
    "road": material("Harbor Asphalt", "526068"),
    "mark": material("Harbor Road Paint", "e3d6ae"),
    "lawn": material("Harbor Park Grass", "688a74"),
    "leaf": material("Harbor Sage Tree Canopy", "72917a"),
    "leaf2": material("Harbor Olive Tree Canopy", "8c9d74"),
    "wood": material("Harbor Tree Trunks", "756352"),
}
for key, wall, glass in (
    ("ivory_facade", (213,211,193), (62,100,114)),
    ("sand_facade", (186,169,144), (59,91,98)),
    ("teal_facade", (83,122,129), (43,80,101)),
):
    M[key] = material("Harbor Windows " + key, "ffffff", .58, facade_images(key, wall, glass))

pixels = np.ones((256, 256, 4), dtype=np.float32)
yy, xx = np.indices((256, 256))
noise = np.random.default_rng(913).uniform(-.018, .018, (256, 256, 1))
pixels[:, :, :3] = np.array([.57, .60, .58]) + noise
joints = (yy % 64 < 3) | ((xx + (yy // 64 % 2) * 64) % 128 < 3)
pixels[joints, :3] *= .65
M["quay"] = material("Harbor Authored Quay Masonry", "ffffff", .93, (texture("quay_blocks_albedo", pixels),))


class Geometry:
    def __init__(self, name, district):
        self.name, self.district = name, district
        self.verts, self.faces, self.uvs, self.slots, self.ids = [], [], [], [], []

    def face(self, points, mat, uv=None):
        start = len(self.verts)
        self.verts.extend(points)
        self.faces.append(tuple(range(start, start + len(points))))
        self.uvs.append(uv or [(0, 0)] * len(points))
        if mat not in self.slots:
            self.slots.append(mat)
        self.ids.append(self.slots.index(mat))

    def prism(self, poly, bottom, top, side, cap=None, uv_scale=None):
        self.face([(x, y, bottom) for x, y in reversed(poly)], cap or side)
        self.face([(x, y, top) for x, y in poly], cap or side)
        for a, b in zip(poly, poly[1:] + poly[:1]):
            width = math.dist(a, b)
            u = width / uv_scale[0] if uv_scale else 1
            v = (top-bottom) / uv_scale[1] if uv_scale else 1
            v0 = bottom / uv_scale[1] if uv_scale else 0
            self.face([(a[0], a[1], bottom), (b[0], b[1], bottom),
                       (b[0], b[1], top), (a[0], a[1], top)], side,
                      [(0, v0), (u, v0), (u, v0+v), (0, v0+v)])

    def box(self, x, y, z, w, d, h, mat, bevel=0):
        self.prism(outline(x, y, w, d, bevel), z, z+h, mat)

    def finish(self):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts, [], self.faces)
        for key in self.slots:
            mesh.materials.append(M[key])
        uv = mesh.uv_layers.new(name="UVMap")
        for poly, mat_id, coords in zip(mesh.polygons, self.ids, self.uvs):
            poly.material_index = mat_id
            for index, coord in zip(poly.loop_indices, coords):
                uv.data[index].uv = coord
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        districts[self.district].objects.link(obj)
        return obj


def outline(x, y, w, d, b=0):
    l, r, f, k = x-w/2, x+w/2, y-d/2, y+d/2
    if not b:
        return [(l,f), (r,f), (r,k), (l,k)]
    return [(l+b,f),(r-b,f),(r,f+b),(r,k-b),(r-b,k),(l+b,k),(l,k-b),(l,f+b)]


def circle(x, y, radius, sides=12, ratio=1):
    return [(x+radius*math.cos(i*math.tau/sides), y+radius*ratio*math.sin(i*math.tau/sides)) for i in range(sides)]


BASE, FRONT, WEST, CIVIC, EAST, TREES = districts.keys()
island = [(-190,-65),(-165,-90),(-43,-90),(-43,-57),(38,-57),(38,-90),
          (164,-90),(190,-64),(190,55),(160,85),(-155,85),(-190,54)]
g = Geometry("Reclaimed island - submerged toe, quay and coping", BASE)
g.prism([(x*1.012,y*1.018) for x,y in island], -6, -.3, "dark")
g.prism(island, -.3, 3.6, "quay", "paving", (12, 4))
g.prism([(x*1.002,y*1.002) for x,y in island], 3.6, 4.15, "chalk", "paving")
for a,b in zip(island, island[1:]+island[:1]):
    # Regular sea-wall buttresses; tops remain below the promenade surface.
    distance = math.dist(a,b)
    for i in range(1, int(distance/16)):
        t = i/int(distance/16)
        g.box(a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t, -.6, 1.6, 1.6, 4.3, "sand")
g.finish()

g = Geometry("Avenues sidewalks and marina fingers", BASE)
for y in (-34, 33):
    g.box(0,y,4.16,348,14,.12,"chalk")
    g.box(0,y,4.29,348,10,.03,"road")
    for x in range(-166,167,12):
        g.box(x,y,4.325,5,.20,.018,"mark")
for x in (-101, 0, 103):
    g.box(x,0,4.17,13,152,.1,"chalk")
    g.box(x,0,4.3,9,152,.03,"road")
    for y in (-34,33):
        for k in range(6):
            g.box(x-4+k*1.5,y-7,4.35,.8,3,.015,"mark")
for x in (-24,0,22):
    g.box(x,-78,1.9,3.5,32,1.0,"paving")
    for y in (-66,-84):
        g.box(x,y,-2,.65,.65,4,"dark")
g.box(0,-59,2,72,4,.9,"paving")
for x in (-152,-62,62,154):
    g.box(x,-66,4.2,25,8,.45,"chalk",1)
    g.box(x,-66,4.66,22,5,.08,"lawn",1)
g.finish()


def parapet(g,x,y,w,d,z,mat="chalk"):
    g.box(x,y-d/2,z,w,.5,1.0,mat)
    g.box(x,y+d/2,z,w,.5,1.0,mat)
    g.box(x-w/2,y,z,.5,d,1.0,mat)
    g.box(x+w/2,y,z,.5,d,1.0,mat)


def block(name, district, x,y,w,d,floors,style="ivory_facade",terrace=False):
    g = Geometry(name,district)
    z = 4.35
    g.box(x,y,z,w+2,d+2,1.0,"chalk",.8)
    g.prism(outline(x,y,w,d,.7),z+1,z+4.8,"glass","roof",(14,14))
    g.box(x,y,z+4.8,w+1.5,d+1.5,.55,"chalk",.7)
    floor_z = z+5.35
    for i in range(floors):
        inset = max(0,i-(floors-3)) * 3 if terrace else 0
        ww,dd = w-inset*2,d-inset
        g.prism(outline(x,y+inset/2,ww,dd,.7),floor_z,floor_z+3.5,style,"roof",(14,14))
        g.box(x,y+inset/2,floor_z+3.5,ww+.9,dd+.9,.3,"chalk",.65)
        floor_z += 3.8
    parapet(g,x,y+inset/2,ww,dd,floor_z)
    g.box(x+3,y+3,floor_z,ww*.35,dd*.42,2.1,"sand",.5)
    g.box(x+3,y+3,floor_z+2.1,ww*.38,dd*.45,.3,"roof",.3)
    if terrace:
        for j in (-1,1):
            g.box(x+j*ww*.34,y-dd*.27+inset/2,floor_z,3.0,3.0,.8,"coral")
            g.box(x+j*ww*.34,y-dd*.27+inset/2,floor_z+.8,2.7,2.7,1.3,"leaf",.4)
    return g.finish()


def gable(name,x,y,w,d,wall="sand_facade"):
    g = Geometry(name,FRONT)
    z, eaves = 4.4, 14
    g.box(x,y,z,w+1,d+1,.7,"chalk",.5)
    g.prism(outline(x,y,w,d),z+.7,eaves,wall,"chalk",(14,14))
    ridge = eaves+6
    g.face([(x-w/2-1,y-d/2-1,eaves),(x,y-d/2-1,ridge),
            (x,y+d/2+1,ridge),(x-w/2-1,y+d/2+1,eaves)],"roof")
    g.face([(x,y-d/2-1,ridge),(x+w/2+1,y-d/2-1,eaves),
            (x+w/2+1,y+d/2+1,eaves),(x,y+d/2+1,ridge)],"roof")
    g.face([(x-w/2,y-d/2,eaves),(x+w/2,y-d/2,eaves),(x,y-d/2,ridge)],"coral")
    g.face([(x+w/2,y+d/2,eaves),(x-w/2,y+d/2,eaves),(x,y+d/2,ridge)],"coral")
    for j in (-1,1):
        g.box(x+j*w*.28,y-d/2-.8,z+5,w*.36,3,.35,"chalk")
    g.finish()


def tower(name,x,y,radius,floors,elliptic=False,district=None):
    g=Geometry(name,district or EAST)
    z=4.4
    poly=circle(x,y,radius,16,.78 if elliptic else 1)
    g.prism(circle(x,y,radius+3,16),z,z+5,"sand","roof")
    for i in range(floors):
        zz=z+5+i*3.7
        g.prism(poly,zz,zz+3.4,"teal_facade","roof",(14,14.8))
        g.prism(circle(x,y,radius+.45,16,.78 if elliptic else 1),zz+3.4,zz+3.7,"chalk","roof")
    crown=z+5+floors*3.7
    g.prism(circle(x,y,radius*.77,16),crown,crown+4.0,"glass","roof")
    g.prism(circle(x,y,radius*.8,16),crown+4,crown+4.6,"chalk","roof")
    g.finish()


# Consistent 3.5 m storeys, several roof silhouettes and readable setbacks.
block("West terraced apartments A",WEST,-144,0,41,38,7,terrace=True)
block("West terraced apartments B",WEST,-58,1,40,39,10,"sand_facade",True)
block("West courtyard rear wing",WEST,-143,60,43,28,5,"sand_facade")
block("West slender residential tower",WEST,-53,62,30,27,12,terrace=True)
block("East office courtyard",EAST,59,0,44,37,8,"ivory_facade",True)
block("East waterfront hotel",EAST,144,0,42,38,6,"sand_facade",True)
block("Garden civic library",CIVIC,9,0,35,31,3,"ivory_facade",True)
block("Harbour west shops",FRONT,-68,-54,39,19,2,"sand_facade")
block("Harbour east shops",FRONT,67,-54,38,19,3,"ivory_facade",True)
gable("Market hall copper roof",-146,-54,40,24)
gable("Ferry warehouse twin roof west",140,-54,20,26)
gable("Ferry warehouse twin roof east",163,-54,20,26)
tower("Rounded harbour landmark",54,59,17,17,True)
tower("East octagonal office tower",141,60,15,12)

g=Geometry("Civic stepped clock and observation tower",CIVIC)
for z,w,d,h in [(4.4,25,22,8),(12.4,17,15,26),(38.4,13,12,11),(49.4,16,15,2),(51.4,10,9,7)]:
    g.prism(outline(1,61,w,d,1),z,z+h,"sand_facade" if h>10 else "chalk","roof",(14,14))
g.prism(circle(1,61,7,4),58.4,59.2,"roof")
for dy in (-1,1):
    # Inset dark clock panel and hands; deliberately broad for the game camera.
    y=61+dy*7.53
    g.box(1,y,40.4,5,.15,5,"glass")
    g.box(1,y+dy*.09,42.7,2.0,.10,.24,"chalk")
    g.box(1,y+dy*.09,42.7,.24,.10,1.7,"chalk")
g.finish()

# Three curved shell roofs over the ferry terminal, avoiding a box-only skyline.
g=Geometry("Marina ferry terminal - triple barrel canopy",FRONT)
g.box(-3,-46,4.4,65,14,5.2,"glass",.5)
for x in (-25,-3,19):
    for k in range(10):
        a,b=k*math.pi/10,(k+1)*math.pi/10
        xa,xb=x-10*math.cos(a),x-10*math.cos(b)
        za,zb=10+4.2*math.sin(a),10+4.2*math.sin(b)
        g.face([(xa,-55,za),(xb,-55,zb),(xb,-37,zb),(xa,-37,za)],"chalk")
        g.face([(xa,-37,za-.35),(xb,-37,zb-.35),(xb,-55,zb-.35),(xa,-55,za-.35)],"sand")
        g.face([(xa,-55,za-.35),(xb,-55,zb-.35),(xb,-55,zb),(xa,-55,za)],"roof")
    for y in (-53,-39):
        for dx in (-9,9):
            g.box(x+dx,y,4.4,.5,.5,5.6,"chalk")
g.finish()

g=Geometry("Harbour entrance beacon towers",FRONT)
for x in (-46,41):
    y=-83
    for rad,z,h,mat in [(3.5,4.3,1,"sand"),(2.1,5.3,6,"chalk"),(2.5,11.3,.5,"coral"),(1.6,11.8,2,"glass")]:
        g.prism(circle(x,y,rad,10),z,z+h,mat)
    g.prism(circle(x,y,2.0,10),13.8,14.5,"roof")
g.finish()

g=Geometry("Promenade trees and park groves",TREES)
tree_positions=[]
for x in range(-171,178,14):
    if abs(x)>48:
        tree_positions.append((x,-78))
for x in range(-171,178,19):
    for y in (-23,23):
        if min(abs(x-k) for k in (-101,0,103))>9:
            tree_positions.append((x,y))
for y in range(-65,73,15):
    tree_positions.extend([(-178,y),(179,y)])
def inside_island(x, y):
    inside = False
    for a,b in zip(island, island[1:]+island[:1]):
        if (a[1]>y) != (b[1]>y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:
            inside = not inside
    return inside


tree_positions = [(x,y) for x,y in tree_positions
                  if all(inside_island(x+dx,y+dy) for dx,dy in ((-3,0),(3,0),(0,-3),(0,3)))]
for i,(x,y) in enumerate(tree_positions):
    height=5.5+(i%4)*.5
    g.prism(circle(x,y,.42,6),4.3,8.1,"wood")
    rings=[(1.0,7.2),(2.7,8.3),(2.9,4.3+height),(1.3,5.3+height)]
    for (r1,z1),(r2,z2) in zip(rings,rings[1:]):
        p,q=circle(x,y,r1,7),circle(x,y,r2,7)
        for j in range(7):
            k=(j+1)%7
            g.face([(p[j][0],p[j][1],z1),(p[k][0],p[k][1],z1),
                    (q[k][0],q[k][1],z2),(q[j][0],q[j][1],z2)],"leaf" if i%3 else "leaf2")
    g.face([(px,py,rings[-1][1]) for px,py in circle(x,y,rings[-1][0],7)],"leaf")
g.finish()

# Expand the authored architecture into a continuous, three-sided city.
# Godot +Z is course-forward and remains completely open. Blender Y = -Godot Z.
templates = list(districts.values())
template_objects = [obj for coll in templates for obj in coll.objects]
districts = {}
terrain_key = "00 Continuous U island - open toward Godot +Z"
districts[terrain_key] = collection(terrain_key)
u_world = [(-1480,-1430),(-1410,-1500),(1410,-1500),(1480,-1430),
           (1480,1980),(1410,2050),(1290,2050),(1220,1980),
           (1220,-1170),(1150,-1240),(-1150,-1240),(-1220,-1170),
           (-1220,1980),(-1290,2050),(-1410,2050),(-1480,1980)]
u_outline = [(x,-z) for x,z in reversed(u_world)]
g = Geometry("Continuous reclamation with submerged seawall",terrain_key)
g.prism(u_outline,-6,.2,"dark","paving")
g.prism(u_outline,.2,3.7,"quay","paving",(12,4))
g.prism(u_outline,3.7,4.15,"chalk","paving")
# Continuous avenues connect the districts. Roads are part of the authored GLB.
for x in (-1386,-1314,1314,1386):
    g.box(x,-290,4.18,13,3400,.08,"chalk")
    g.box(x,-290,4.27,10,3400,.035,"road")
for y in (1334,1406):
    g.box(0,y,4.18,2730,13,.08,"chalk")
    g.box(0,y,4.27,2730,10,.035,"road")
# Broad coping strips along the inner basin make the shoreline legible at distance.
for x in (-1221,1221):
    g.box(x,-410,3.9,2.5,3155,.5,"chalk")
g.box(0,1240,3.9,2300,2.5,.5,"chalk")
g.finish()

placements = []
for i,x in enumerate(range(-1200,1201,400)):
    placements.append(("Rear",i,x,1370,0.0))
for side in (-1,1):
    for i,z in enumerate(range(-950,1851,400)):
        placements.append(("Left" if side<0 else "Right",i,side*1350,-z,math.pi/2 if side<0 else -math.pi/2))

layout_manifest = []
building_count = 0
for tile,(side,index,cx,cy,angle) in enumerate(placements):
    key = "%s district %02d" % (side,index//2+1)
    if key not in districts:
        districts[key] = collection(key)
    before = set(districts[key].objects)
    tag = "%s %02d " % (side,index+1)
    # Storey dimensions stay constant; actual floor counts vary the skyline.
    variant = (tile*7+3)%5
    block(tag+"Terrace residences",key,-144,0,41,38,6+variant,terrace=True)
    block(tag+"Courtyard apartments",key,-58,1,40,39,8+(tile%5),"sand_facade",True)
    block(tag+"Rear garden apartments",key,-143,60,43,28,4+(tile%4),"sand_facade")
    block(tag+"Slender residences",key,-53,62,30,27,9+(tile%6),terrace=True)
    block(tag+"Office terrace",key,59,0,44,37,6+(tile%4),"ivory_facade",True)
    block(tag+"Waterfront hotel",key,144,0,42,38,5+(tile%3),"sand_facade",True)
    block(tag+"Library",key,9,0,35,31,3+(tile%2),"ivory_facade",True)
    block(tag+"West waterfront shops",key,-68,-54,39,19,2+(tile%2),"sand_facade")
    block(tag+"East waterfront shops",key,67,-54,38,19,3,"ivory_facade",True)
    tower(tag+"Rounded landmark",54,59,17,14+(tile*3%12),True,key)
    tower(tag+"Octagonal office",141,60,15,10+(tile*5%10),False,key)
    # Keep the original modeled market roofs, ferry shells, beacons and trees.
    for src in template_objects:
        if not any(s in src.name for s in ("Market hall", "Ferry warehouse", "Marina ferry", "beacon", "clock", "Promenade trees")):
            continue
        dup=src.copy()
        dup.data=src.data.copy()
        dup.name=tag+src.name
        districts[key].objects.link(dup)
    transform = Matrix.Translation((cx,cy,0)) @ Matrix.Rotation(angle,4,"Z")
    for obj in set(districts[key].objects)-before:
        obj.matrix_world = transform @ obj.matrix_world
    building_count += 16
    layout_manifest.append({"side":side,"district":index+1,"godot_centre":[cx,0,-cy]})

for coll in templates:
    coll.name = "TEMPLATE - " + coll.name
    coll.hide_render=True
    coll.hide_viewport=True

# Build compact export objects by district while retaining editable source objects.
export = collection("EXPORT - merged district copies")
for coll in districts.values():
    bpy.ops.object.select_all(action="DESELECT")
    copies=[]
    for obj in coll.objects:
        dup=obj.copy()
        dup.data=obj.data.copy()
        export.objects.link(dup)
        dup.select_set(True)
        copies.append(dup)
    bpy.context.view_layer.objects.active=copies[0]
    if len(copies) > 1:
        bpy.ops.object.join()
    merged=bpy.context.object
    merged.name=coll.name.replace(" ","_")
    # Apply flat triangulation for stable export and predictable Godot LODs.
    modifier=merged.modifiers.new("Game triangulation","TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=modifier.name)

bpy.ops.object.select_all(action="DESELECT")
for obj in export.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active=next(iter(export.objects))
glb_path=ASSET / "aiquiz_harbor_city.glb"
bpy.ops.export_scene.gltf(filepath=str(glb_path),export_format="GLB",use_selection=True,use_active_scene=True,
    export_yup=True,export_apply=True,export_animations=False,export_cameras=False,
    export_lights=False,export_extras=False,export_materials="EXPORT")
stats={"blender":bpy.app.version_string,"units":"metres","sea_level":0,
       "land_top":4.15,"width":2960,"depth":3550,
       "open_direction_godot":"+Z (course forward)",
       "minimum_shore_distance_from_course_axis":1220,
       "districts":len(placements),"buildings":building_count,
       "export_meshes":len(export.objects),
       "triangles":sum(len(o.data.polygons) for o in export.objects),
       "source_meshes":sum(len(c.objects) for c in districts.values()),
       "trees":len(tree_positions)*len(placements),"external_assets":[],"additional_cost":0,
       "layout":layout_manifest}
(SOURCE / "build_report.json").write_text(json.dumps(stats,indent=2),encoding="utf-8")
export.hide_render=True
export.hide_viewport=True

# A local Blender review scene; neither sea nor lighting are exported to the game.
sea_mesh=bpy.data.meshes.new("Review sea plane")
sea_mesh.from_pydata([(-5000,-5000,0),(5000,-5000,0),(5000,5000,0),(-5000,5000,0)],[],[(0,1,2,3)])
sea_obj=bpy.data.objects.new("REVIEW sea",sea_mesh)
review.objects.link(sea_obj)
sea_mesh.materials.append(material("Review Sea - excluded from export","417d96",.35))
world=bpy.data.worlds.new("Harbor review daylight")
world.use_nodes=True
background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
background.inputs[0].default_value=(.5,.65,.8,1)
background.inputs[1].default_value=.7
scene.world=world
sun=bpy.data.lights.new("Review sun","SUN")
sun.energy=3
sun.angle=math.radians(8)
sun_obj=bpy.data.objects.new("Review sun",sun)
review.objects.link(sun_obj)
sun_obj.rotation_euler=(math.radians(25),math.radians(-20),math.radians(-35))
cam_data=bpy.data.cameras.new("Review camera")
cam=bpy.data.objects.new("Review camera",cam_data)
review.objects.link(cam)
cam.location=(3000,-4800,3900)
cam.rotation_euler=(Vector((0,-200,0))-cam.location).to_track_quat("-Z","Y").to_euler()
cam_data.type="ORTHO"
cam_data.ortho_scale=4900
cam_data.clip_end=20000
scene.camera=cam
scene.render.filepath=str(PREVIEWS / "harbor_city_overview.png")
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=="VIEW_3D":
            area.spaces.active.clip_start=5.0
            area.spaces.active.clip_end=20000
            area.spaces.active.shading.type="MATERIAL"
            area.spaces.active.overlay.show_overlays=False
            area.spaces.active.region_3d.view_location=(0,-230,0)
            area.spaces.active.region_3d.view_distance=5000
            area.spaces.active.region_3d.view_rotation=Quaternion((1,0,0,0))
            area.spaces.active.region_3d.view_perspective="ORTHO"
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "aiquiz_harbor_city.blend"))
bpy.ops.render.render(write_still=True)
print("HARBOR_CITY_BUILD_OK " + json.dumps(stats))

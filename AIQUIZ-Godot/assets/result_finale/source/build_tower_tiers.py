"""Score tower tier modules: one tier per point, stacked by Godot under the lift.

Replaces the octagonal column of build_set.py (small navy-framed panels that read as
a busy grid once a tower is 30+ tiers tall). A tier is a smooth, rounded white drum
over a thin recessed accent ring (Godot tints it in the player colour); every 5th
tier swaps that ring for a proud gold band so the stack reads like a ruler.

Run headless from the project root (new file, never touches an open session):
  "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --factory-startup \
      --python assets/result_finale/source/build_tower_tiers.py
Outputs:
  assets/result_finale/tower_tiers.glb            TWR_Tier, TWR_TierMilestone (top at 0, 0.30 tall)
  assets/result_finale/source/AIQUIZ_TowerTiers.blend   editable modules + preview stack
  artifacts/result_finale/tower_tiers_preview.png       low-angle review render
"""
import bpy
import bmesh
import math
from pathlib import Path

ROOT = Path("C:/AIQUIZ/AIQUIZ-Godot")
OUT = ROOT / "assets/result_finale"
TIER = 0.30          # ResultFinaleMotion.TIER_HEIGHT
RADIUS = 0.62        # build_set.py COLUMN_R
SEGMENTS = 40
MILESTONE_EVERY = 5

# Lathe profiles (radius, z), top to bottom, with the material of the span that
# ends at each point. Both start and end at radius 0.600 so stacked tiers meet flush.
BODY, ACCENT, GOLD = 0, 1, 2
TIER_PROFILE = [
    (0.600, 0.000, None),
    (0.611, -0.005, BODY), (0.618, -0.014, BODY), (RADIUS, -0.026, BODY),
    (RADIUS, -0.238, BODY), (0.618, -0.250, BODY), (0.611, -0.259, BODY), (0.600, -0.264, BODY),
    # thin recessed glowing ring between drums
    (0.594, -0.268, ACCENT), (0.594, -0.296, ACCENT), (0.600, -0.300, ACCENT),
]
MILESTONE_PROFILE = [
    (0.600, 0.000, None),
    (0.611, -0.005, BODY), (0.618, -0.014, BODY), (RADIUS, -0.026, BODY),
    (RADIUS, -0.226, BODY), (0.617, -0.236, BODY), (0.608, -0.242, BODY),
    # proud gold band with softened edges
    (0.640, -0.246, GOLD), (0.652, -0.254, GOLD), (0.655, -0.264, GOLD), (0.655, -0.282, GOLD),
    (0.652, -0.291, GOLD), (0.640, -0.298, GOLD), (0.600, -0.300, GOLD),
]


def material(name, color, rough, metal=0.0, emission=None, strength=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = (*color, 1.0)
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1.0)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    p.inputs['Emission Color'].default_value = (*(emission or (0.0, 0.0, 0.0)), 1.0)
    p.inputs['Emission Strength'].default_value = strength if emission else 0.0
    return m


def materials():
    # Names match score_tower.glb so Godot's overrides (player tint, toy gold) apply.
    return [
        material("FIN_TowerBody", (0.90, 0.92, 0.95), 0.42),
        material("FIN_TowerAccent", (1.0, 1.0, 1.0), 0.3, emission=(1.0, 1.0, 1.0), strength=2.0),
        material("FIN_TierGold", (1.0, 0.72, 0.16), 0.3, 0.6),
    ]


def lathe(name, profile, mats, coll):
    bm = bmesh.new()
    loops = []
    for radius, z, _ in profile:
        loops.append([bm.verts.new((radius * math.cos(i * math.tau / SEGMENTS),
                                    radius * math.sin(i * math.tau / SEGMENTS), z)) for i in range(SEGMENTS)])
    for k in range(1, len(loops)):
        upper, lower = loops[k - 1], loops[k]
        for i in range(SEGMENTS):
            j = (i + 1) % SEGMENTS
            f = bm.faces.new((upper[i], lower[i], lower[j], upper[j]))
            f.material_index = profile[k][2]
            f.smooth = True
    bm.normal_update()
    # Keep the ring edges crisp where the material changes; drums stay rounded.
    for k in range(1, len(profile) - 1):
        if profile[k][2] != profile[k + 1][2]:
            for i in range(SEGMENTS):
                edge = bm.edges.get((loops[k][i], loops[k][(i + 1) % SEGMENTS]))
                if edge:
                    edge.smooth = False
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def build():
    scene = bpy.context.scene
    for ob in list(scene.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    modules = bpy.data.collections.new("TWR_TierModules")
    scene.collection.children.link(modules)
    mats = materials()
    tier = lathe("TWR_Tier", TIER_PROFILE, mats, modules)
    milestone = lathe("TWR_TierMilestone", MILESTONE_PROFILE, mats, modules)
    return scene, modules, tier, milestone


def export(tier, milestone):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in (tier, milestone):
        ob.select_set(True)
    path = OUT / "tower_tiers.glb"
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                              export_animations=False, export_apply=True, export_lights=False,
                              export_cameras=False)
    return path


def preview(scene, tier, milestone, count=24):
    """A tower top with its stacked tiers, the way Godot builds it, shot from below."""
    stack = bpy.data.collections.new("PRV_Stack")
    scene.collection.children.link(stack)
    top = 6.0
    for k in range(count):
        src = milestone if (k + 1) % MILESTONE_EVERY == 0 else tier
        ob = bpy.data.objects.new("PRV_Tier%02d" % k, src.data)
        ob.location = (0.0, 0.0, top - 0.30 - k * TIER)
        stack.objects.link(ob)
    deck = bpy.data.meshes.new("PRV_Deck")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=SEGMENTS, radius1=0.85, radius2=0.85, depth=0.2)
    bm.to_mesh(deck)
    bm.free()
    deck.materials.append(bpy.data.materials["FIN_TowerBody"])
    ob = bpy.data.objects.new("PRV_Deck", deck)
    ob.location = (0.0, 0.0, top - 0.1)
    stack.objects.link(ob)
    # Player-orange tint on the accent for the preview only (Godot tints per player).
    accent = bpy.data.materials["FIN_TowerAccent"].copy()
    accent.name = "PRV_AccentOrange"
    p = next(n for n in accent.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (0.95, 0.55, 0.20, 1.0)
    p.inputs['Emission Color'].default_value = (0.95, 0.55, 0.20, 1.0)
    for o in stack.objects:
        if o.type == 'MESH' and o.name.startswith("PRV_Tier"):
            o.material_slots[1].link = 'OBJECT'
            o.material_slots[1].material = accent
    world = bpy.data.worlds.new("PRV_Sky")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.45, 0.65, 0.95, 1.0)
    bg.inputs[1].default_value = 1.0
    scene.world = world
    sun = bpy.data.lights.new("PRV_Sun", 'SUN')
    sun.energy = 3.5
    sun_ob = bpy.data.objects.new("PRV_Sun", sun)
    sun_ob.rotation_euler = (math.radians(50), 0.0, math.radians(35))
    stack.objects.link(sun_ob)
    cam = bpy.data.cameras.new("PRV_Camera")
    cam.lens = 18
    cam_ob = bpy.data.objects.new("PRV_Camera", cam)
    cam_ob.location = (3.2, -4.0, -0.8)
    stack.objects.link(cam_ob)
    target = bpy.data.objects.new("PRV_Target", None)
    target.location = (0.0, 0.0, 2.2)
    stack.objects.link(target)
    track = cam_ob.constraints.new('TRACK_TO')
    track.target = target
    track.track_axis = 'TRACK_NEGATIVE_Z'
    track.up_axis = 'UP_Y'
    scene.camera = cam_ob
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 48
    scene.cycles.device = 'CPU'
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1200
    shot = ROOT / "artifacts/result_finale/tower_tiers_preview.png"
    shot.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(shot)
    bpy.ops.render.render(write_still=True)
    return shot


if __name__ == "__main__":
    scene, modules, tier, milestone = build()
    glb = export(tier, milestone)
    shot = preview(scene, tier, milestone)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "source/AIQUIZ_TowerTiers.blend"))
    print("TOWER_TIERS", glb, glb.stat().st_size, shot)

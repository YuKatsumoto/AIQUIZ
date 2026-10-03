"""Review set-up for the cistern modules in the LIVE Blender (preview only, never exported).

    ns = {"__name__": "cistern_review"}
    exec(open(".../source/review_cistern.py", encoding="utf-8").read(), ns)
    ns["layout"](["U", "A", "B", "O", "C", "A", "B", ...])   # module per bay index k = -1, 0, 1, ...
    ns["cameras"]()
    ns["world"](fog=True)
    ns["render"]("corridor", "C:/.../previews/corridor.png", samples=256)

The layout instances the module collections (CIS_<TAG>) along the corridor exactly as Godot
does: bay k at world z = 15 k, the ends at their own world z.
"""
import math

import bpy
from mathutils import Vector

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/cistern_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)


def layout(seq, first_k=-1, ends=True):
    """seq: module tags for bay k = first_k, first_k + 1, ... ('U'/'D' ends are added when ends)."""
    col = C.collection("CIS_Review")
    for o in list(col.objects):
        if o.instance_type == "COLLECTION" or o.name.startswith("REV_Inst"):
            bpy.data.objects.remove(o, do_unlink=True)
    made = []
    for i, tag in enumerate(seq):
        k = first_k + i
        src = bpy.data.collections.get("CIS_" + tag)
        if src is None:
            continue
        e = bpy.data.objects.new("REV_Inst_%02d_%s" % (i, tag), None)
        e.instance_type = "COLLECTION"
        e.instance_collection = src
        e.location = C.g2b((0.0, 0.0, 15.0 * k))
        col.objects.link(e)
        made.append(e.name)
    if ends:
        for tag in ("U", "D"):
            src = bpy.data.collections.get("CIS_" + tag)
            if src is None or len(src.all_objects) == 0:
                continue
            e = bpy.data.objects.new("REV_Inst_end_%s" % tag, None)
            e.instance_type = "COLLECTION"
            e.instance_collection = src
            col.objects.link(e)
            made.append(e.name)
    # the cold light column through the opening (a real light in Godot, preview only here)
    lo = bpy.data.objects.get("REV_OpeningLight")
    if "O" in seq:
        k = first_k + seq.index("O")
        if lo is None:
            ld = bpy.data.lights.new("REV_OpeningLight", "SPOT")
            lo = bpy.data.objects.new("REV_OpeningLight", ld)
            col.objects.link(lo)
        lo.data.energy = 60000.0
        lo.data.color = (0.78, 0.88, 1.0)
        lo.data.spot_size = math.radians(30.0)
        lo.data.spot_blend = 0.25
        lo.data.shadow_soft_size = 1.5
        lo.location = C.g2b((0.0, 34.0, 15.0 * k))
        lo.rotation_euler = (0.0, 0.0, 0.0)
        lo.hide_render = False
    elif lo is not None:
        lo.hide_render = True
    # the source collections themselves stay out of the view layer (only instances render)
    exclude_sources(True)
    col.hide_render = False
    col.hide_viewport = False
    return made


def exclude_sources(flag):
    for keep in ("CIS_Review",):
        lc = _layer_col(bpy.context.view_layer.layer_collection, keep)
        if lc is not None:
            lc.exclude = False
    for drop in ("CIS_Bake",):
        lc = _layer_col(bpy.context.view_layer.layer_collection, drop)
        if lc is not None:
            lc.exclude = True
    for c in bpy.data.collections:
        if c.name.startswith("CIS_") and c.name not in ("CIS_Review", "CIS_Bake", "CIS_TexBake"):
            lc = _layer_col(bpy.context.view_layer.layer_collection, c.name)
            if lc is not None:
                lc.exclude = flag
            c.hide_render = False
            c.hide_viewport = False


def _layer_col(lc, name):
    if lc.collection.name == name:
        return lc
    for ch in lc.children:
        r = _layer_col(ch, name)
        if r is not None:
            return r
    return None


def _cam(name, pos_g, target_g, fov_v_deg=50.0, lens=None):
    col = C.collection("CIS_Review")
    data = bpy.data.cameras.get(name) or bpy.data.cameras.new(name)
    data.sensor_fit = "VERTICAL"
    data.angle_y = math.radians(fov_v_deg)
    data.clip_start = 0.1
    data.clip_end = 400.0
    obj = bpy.data.objects.get(name) or bpy.data.objects.new(name, data)
    if obj.name not in col.objects:
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        col.objects.link(obj)
    obj.location = C.g2b(pos_g)
    d = (C.g2b(target_g) - C.g2b(pos_g)).normalized()
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return obj


CAMS = {
    # (a) corridor at runner height looking downstream
    "corridor": ((-1.2, 1.75, -6.0), (0.6, 2.6, 40.0), 52.0),
    # (e) the 2P game camera (eye 4.5 m, ~11 m behind the runners at z ~ 8, FOV 50)
    "game": ((0.0, 4.5, -3.0), (0.0, 2.3, 14.0), 50.0),
    # (b) high wide view across the pillar forest
    "forest": ((-8.0, 13.5, -12.0), (22.0, 6.0, 32.0), 60.0),
    # (c) upstream end: tunnel, gate and balcony
    "upstream": ((-3.0, 3.2, -6.0), (4.0, 6.5, -30.0), 58.0),
    # (d) downstream end: ladders, catwalk, hatches
    "downstream": ((2.0, 3.0, 186.0), (0.0, 4.5, 210.0), 55.0),
    # opening from below
    "opening": ((-9.0, 1.7, -12.0), (0.0, 12.0, 0.0), 62.0),
}


def cameras():
    out = {}
    for name, (p, t, fov) in CAMS.items():
        out[name] = _cam("REV_CAM_" + name, p, t, fov).name
    return out


def world(fog=True, density=0.005, exposure=0.0):
    sc = bpy.context.scene
    w = bpy.data.worlds.get("CIS_World") or bpy.data.worlds.new("CIS_World")
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs[0].default_value = (0.0, 0.0, 0.0, 1.0)
    bg.inputs[1].default_value = 0.0
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    sc.world = w
    # fog: a bounded box volume (Cycles/EEVEE), never exported
    col = C.collection("CIS_Review")
    fogo = bpy.data.objects.get("REV_Fog")
    if fog:
        if fogo is None:
            me = bpy.data.meshes.new("REV_Fog")
            import bmesh
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            bm.to_mesh(me)
            bm.free()
            fogo = bpy.data.objects.new("REV_Fog", me)
            col.objects.link(fogo)
        fogo.location = C.g2b((0.0, 9.0, 90.0))
        fogo.scale = (89.8, 240.0, 17.9)
        mat = bpy.data.materials.get("REV_FogMat") or bpy.data.materials.new("REV_FogMat")
        mat.use_nodes = True
        mnt = mat.node_tree
        mnt.nodes.clear()
        mo = mnt.nodes.new("ShaderNodeOutputMaterial")
        vol = mnt.nodes.new("ShaderNodeVolumePrincipled")
        vol.inputs["Density"].default_value = density
        vol.inputs["Anisotropy"].default_value = 0.45
        vol.inputs["Color"].default_value = (0.74, 0.80, 0.86, 1.0)
        mnt.links.new(vol.outputs[0], mo.inputs["Volume"])
        fogo.data.materials.clear()
        fogo.data.materials.append(mat)
        fogo.hide_render = False
        fogo.visible_shadow = False
    elif fogo is not None:
        fogo.hide_render = True
    sc.render.engine = "CYCLES"
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = exposure
    # camera white balance at the flood colour temperature (as in the reference photos)
    try:
        sc.view_settings.use_white_balance = True
        sc.view_settings.white_balance_temperature = 5000.0
        sc.view_settings.white_balance_tint = 0.0
    except Exception:
        pass
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 3
    sc.cycles.volume_bounces = 1
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.volume_step_rate = 4.0
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 900
    sc.render.film_transparent = False
    return {"fog": fog, "density": density}


def lightmap_check(module_file, light_max, albedo=0.32, on=True):
    """View-layer override: emission = albedo x decoded lightmap (UV2) - the Godot formula with a
    flat albedo, to check the bake for seams, noise and orientation."""
    vl = bpy.context.view_layer
    if not on:
        vl.material_override = None
        return None
    mat = bpy.data.materials.get("REV_LMCheck") or bpy.data.materials.new("REV_LMCheck")
    mat.use_nodes = True
    nb = C.NB(mat)
    out = nb.node("ShaderNodeOutputMaterial")
    path = C.TEXTURES + "/" + module_file
    img = bpy.data.images.get(module_file)
    if img is None:
        img = bpy.data.images.load(path)
    else:
        img.reload()
    img.colorspace_settings.name = "Non-Color"
    tex = nb.image(img, uvmap="UVMap_LM")
    dec = nb.node("ShaderNodeVectorMath", operation="POWER")
    nb.link(tex.outputs["Color"], dec.inputs[0])
    dec.inputs[1].default_value = (2.2, 2.2, 2.2)
    sc = nb.node("ShaderNodeVectorMath", operation="SCALE")
    nb.link(dec.outputs[0], sc.inputs[0])
    sc.inputs["Scale"].default_value = light_max * albedo
    em = nb.node("ShaderNodeEmission")
    nb.link(sc.outputs[0], em.inputs["Color"])
    nb.link(em.outputs[0], out.inputs["Surface"])
    vl.material_override = mat
    return mat.name


def shot(cam, path, samples=96, res=(1280, 720), fog=True, lm=None):
    """One review render (used from jobs.py). lm = (lightmap png, light_max) for the bake check."""
    world(fog=fog)
    if lm is not None:
        lightmap_check(lm[0], lm[1])
    try:
        render(cam, path, samples=samples, res=res, fog=fog)
    finally:
        if lm is not None:
            lightmap_check(None, None, on=False)
    return path


def gpu():
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    bpy.context.scene.cycles.device = "GPU"


def render(cam, path, samples=128, res=(1600, 900), fog=None):
    sc = bpy.context.scene
    gpu()
    sc.camera = bpy.data.objects["REV_CAM_" + cam]
    sc.cycles.samples = samples
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = path
    if fog is not None:
        f = bpy.data.objects.get("REV_Fog")
        if f is not None:
            f.hide_render = not fog
    bpy.ops.render.render(write_still=True)
    return path

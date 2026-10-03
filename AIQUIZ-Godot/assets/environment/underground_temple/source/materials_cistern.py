"""Look-dev materials of the cistern modules (LIVE Blender). Exported as named placeholders only:
Godot rebuilds them from textures/ (see README "Godot material recipe").

    ns = {"__name__": "cistern_mats"}
    exec(open(".../source/materials_cistern.py", encoding="utf-8").read(), ns)
    ns["setup_materials"]()

Every CIS_* material = tiling PBR maps on UV0 (the same recipe the README gives Godot) x the
procedural GRIME field (module coordinates). CIS_BakeSwitch (a node group shared by all
materials) turns them into an emission of the grime colour for the grime bake
(bake_cistern.py), so the per-module dirt can be multiplied into the lightmap.

Grime (all multipliers on albedo):
  * waterline 1.5 m above the floor: darker, algae-tinted band below a wavy tide line, two
    fainter older tide lines, a thin mineral band just above, mud splash at the foot
  * runoff streaks on vertical faces (stronger high up), efflorescence crust and runs under
    every cold joint, rust runs under the flood, amber and tray brackets
  * ceiling: damp patches and efflorescence lines; per-pillar tone; very large mottling
  * fields are 15 m-periodic in z near the module ends so any bay order joins seamlessly
"""
import math

import bpy

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/cistern_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)
NB = C.NB
TAU = C.TAU

TEX = C.TEXTURES


def _img(name, colorspace):
    path = TEX + "/" + name
    img = bpy.data.images.get(name)
    if img is None:
        img = bpy.data.images.load(path, check_existing=True)
    else:
        img.filepath = path
        img.reload()
    img.colorspace_settings.name = colorspace
    return img


# ------------------------------------------------------------------ shared node groups
def bake_switch_group():
    g = bpy.data.node_groups.get("CIS_BakeSwitch")
    if g is None:
        g = bpy.data.node_groups.new("CIS_BakeSwitch", "ShaderNodeTree")
        g.interface.new_socket("Mode", in_out="OUTPUT", socket_type="NodeSocketFloat")
        out = g.nodes.new("NodeGroupOutput")
        val = g.nodes.new("ShaderNodeValue")
        val.name = "MODE"
        val.outputs[0].default_value = 0.0
        g.links.new(val.outputs[0], out.inputs[0])
    return g


def set_bake_mode(mode):
    """0 shaded, 1 emit grime colour."""
    bake_switch_group().nodes["MODE"].outputs[0].default_value = float(mode)


def grime_group():
    """Inputs: Kind (0 concrete, 1 floor, 2 metal), Seed. Output: Grime (RGB multiplier)."""
    name = "CIS_Grime"
    g = bpy.data.node_groups.get(name)
    if g is not None:
        bpy.data.node_groups.remove(g)
    g = bpy.data.node_groups.new(name, "ShaderNodeTree")
    g.interface.new_socket("Kind", in_out="INPUT", socket_type="NodeSocketFloat")
    g.interface.new_socket("Seed", in_out="INPUT", socket_type="NodeSocketFloat")
    g.interface.new_socket("Grime", in_out="OUTPUT", socket_type="NodeSocketColor")
    nb = NB(g, clear=False)
    gin = nb.node("NodeGroupInput")
    gout = nb.node("NodeGroupOutput")
    kind, seed = gin.outputs[0], gin.outputs[1]
    tc = nb.node("ShaderNodeTexCoord")
    bx, by, bz = nb.separate(tc.outputs["Object"])
    gx, gy, gz = bx, bz, nb.mul(by, -1.0)
    geo = nb.node("ShaderNodeNewGeometry")
    nbx, nby, nbz = nb.separate(geo.outputs["Normal"])
    ny = nbz
    vert = nb.sub(1.0, nb.math("ABSOLUTE", ny))
    is_ceil = nb.smooth(nb.mul(ny, -1.0), 0.5, 0.8)
    is_floor = nb.math("GREATER_THAN", kind, 0.5)
    is_floor = nb.mul(is_floor, nb.math("LESS_THAN", kind, 1.5))
    is_metal = nb.math("GREATER_THAN", kind, 1.5)
    # boundary weight: within 1.5 m of a bay end use the common (seed 0) field
    bz_mod = nb.sub(nb.math("FLOORED_MODULO", nb.add(gz, 7.5), 15.0), 7.5)
    bw = nb.smooth(nb.math("ABSOLUTE", bz_mod), 6.0, 7.5)
    th = nb.mul(gz, TAU / 15.0)
    cz, sz = nb.math("COSINE", th), nb.math("SINE", th)

    def pn(fx, fy, fz, off, detail=3.0, rough=0.55, distortion=0.0):
        """15 m-periodic-in-z noise mixed toward the common field near the module ends."""
        r = fz * 15.0 / TAU
        outs = []
        for s_off in (nb.mul(seed, 13.7), 0.0):
            vec = nb.combine(nb.mul(gx, fx), nb.add(nb.mul(gy, fy), s_off), nb.add(nb.mul(cz, r), off))
            outs.append(nb.noise4(vec, nb.mul(sz, r), detail, rough, 2.0, distortion))
        return nb.mix(outs[0], outs[1], bw)

    # -------- large tone and per-pillar tone
    big = pn(0.06, 0.06, 0.06, 1.0, 3.0)
    mid = pn(0.35, 0.35, 0.35, 2.0, 4.0, 0.6)
    tone = nb.add(0.76, nb.mul(big, 0.45))
    tone = nb.mul(tone, nb.add(0.90, nb.mul(mid, 0.2)))
    pid = nb.math("FLOOR", nb.mul(nb.add(gx, 51.45), 1.0 / 12.9))
    prand = nb.white(nb.combine(pid, nb.mul(seed, 1.0), 4.4))
    in_pillar_zone = nb.math("GREATER_THAN", nb.math("ABSOLUTE", gx), 11.5)
    tone = nb.mul(tone, nb.add(1.0, nb.mul(nb.mul(nb.sub(prand, 0.5), 0.22), in_pillar_zone)))
    # -------- waterline family (vertical faces and everything metal, not the floor/ceiling)
    wl = nb.add(1.5, nb.mul(nb.sub(pn(0.5, 0.0, 0.5, 3.0, 2.0), 0.5), 0.10))
    below = nb.sub(1.0, nb.smooth(gy, nb.sub(wl, 0.015), nb.add(wl, 0.01)))
    alg = pn(1.2, 4.0, 1.2, 4.0, 4.0, 0.6)
    band_k = nb.mul(below, nb.add(0.55, nb.mul(alg, 0.45)))
    tide = nb.math("EXPONENT", nb.mul(nb.math("POWER", nb.div(nb.sub(gy, wl), 0.018), 2.0), -1.0))
    old1 = nb.math("EXPONENT", nb.mul(nb.math("POWER", nb.div(nb.sub(gy, nb.sub(wl, 0.55)), 0.012), 2.0), -1.0))
    old2 = nb.math("EXPONENT", nb.mul(nb.math("POWER", nb.div(nb.sub(gy, nb.sub(wl, 0.95)), 0.010), 2.0), -1.0))
    mineral = nb.mul(nb.smooth(gy, nb.add(wl, 0.005), nb.add(wl, 0.03)), nb.sub(1.0, nb.smooth(gy, nb.add(wl, 0.06), nb.add(wl, 0.22))))
    foot = nb.sub(1.0, nb.smooth(gy, 0.0, 0.45))
    wl_on = nb.mul(nb.sub(1.0, is_floor), nb.sub(1.0, is_ceil))
    # -------- runoff streaks on vertical faces, stronger high up
    streak_n = pn(2.2, 0.12, 2.2, 5.0, 3.0, 0.55)
    streak = nb.mul(nb.smooth(streak_n, 0.56, 0.74), nb.add(0.35, nb.mul(nb.smooth(gy, 3.0, 17.0), 0.65)))
    streak = nb.mul(streak, nb.mul(vert, nb.sub(1.0, is_metal)))
    # -------- efflorescence under the cold joints (3.75 m pours)
    jabove = nb.mul(nb.math("CEIL", nb.mul(gy, 1.0 / C.LIFT)), C.LIFT)
    dj = nb.sub(jabove, gy)
    leak = nb.smooth(pn(0.45, 0.0, 0.45, 6.0, 2.0), 0.55, 0.66)
    runs_n = nb.smooth(pn(7.0, 0.35, 7.0, 7.0, 2.0), 0.58, 0.72)
    crust = nb.mul(leak, nb.math("EXPONENT", nb.mul(dj, -1.0 / 0.07)))
    runs = nb.mul(nb.mul(leak, runs_n), nb.math("EXPONENT", nb.mul(dj, -1.0 / 0.8)))
    effl = nb.mul(nb.clamp01(nb.add(nb.mul(crust, 0.9), nb.mul(runs, 0.75))), nb.mul(vert, nb.sub(1.0, is_metal)))
    effl = nb.mul(effl, nb.math("GREATER_THAN", gy, 1.7))
    # ceiling: damp blotches + efflorescence lines + white spots
    damp_c = nb.mul(nb.smooth(pn(0.25, 0.0, 0.25, 8.0, 4.0, 0.6, 0.6), 0.55, 0.7), is_ceil)
    cvec = nb.combine(nb.mul(gx, 0.45), nb.mul(seed, 3.1), nb.mul(gz, 0.45))
    vor = nb.node("ShaderNodeTexVoronoi", voronoi_dimensions="3D", feature="DISTANCE_TO_EDGE")
    nb.link(cvec, vor.inputs["Vector"])
    vor.inputs["Scale"].default_value = 1.0
    cline = nb.mul(nb.mul(nb.sub(1.0, nb.smooth(vor.outputs["Distance"], 0.0, 0.02)), is_ceil),
                   nb.smooth(pn(0.3, 0.0, 0.3, 9.0, 2.0), 0.58, 0.68))
    effl = nb.clamp01(nb.add(effl, nb.mul(cline, 0.45)))
    # -------- rust runs under fixtures (flood plates, amber lamps, tray brackets)
    ax = nb.math("ABSOLUTE", gx)

    def run(face_x, y0, z0, half, decay, strength):
        on = nb.mul(nb.math("GREATER_THAN", ax, face_x - 0.08), nb.math("LESS_THAN", ax, face_x + 0.02))
        d = nb.sub(y0, gy)
        lat = nb.math("ABSOLUTE", nb.sub(gz, z0))
        m = nb.mul(nb.sub(1.0, nb.smooth(lat, half * 0.3, nb.add(half, nb.mul(d, 0.05)))), nb.math("EXPONENT", nb.mul(d, -1.0 / decay)))
        m = nb.mul(m, nb.math("GREATER_THAN", d, 0.0))
        return nb.mul(nb.mul(m, on), strength)

    rn = nb.add(0.35, nb.mul(pn(14.0, 0.8, 14.0, 10.0, 2.0), 0.65))
    rust = run(C.CORR_X, C.FLOOD_Y - 0.25, C.FLOOD_Z, 0.20, 2.2, 0.85)
    rust = nb.math("MAXIMUM", rust, run(C.PILLAR_X[1] - C.PILLAR_HW, 2.85, 3.5, 0.08, 1.0, 0.7))
    for zb in (0.75, 3.5, 6.25):
        rust = nb.math("MAXIMUM", rust, run(C.CORR_X, 14.9, zb, 0.04, 1.4, 0.6))
    rust = nb.mul(nb.mul(rust, rn), nb.sub(1.0, is_metal))
    # -------- floor: large stains only (wetness / puddles / silt come from COLOR_0 in the shader)
    fst = nb.smooth(pn(0.22, 0.0, 0.22, 11.0, 4.0, 0.6, 0.8), 0.45, 0.8)
    floor_k = nb.sub(1.0, nb.mul(fst, 0.28))
    # -------- combine (RGB multipliers)
    r = tone
    g_ = tone
    b = tone
    def mulc(cr, cg, cb, k):
        nonlocal r, g_, b
        r = nb.mul(r, nb.mix(1.0, cr, k))
        g_ = nb.mul(g_, nb.mix(1.0, cg, k))
        b = nb.mul(b, nb.mix(1.0, cb, k))

    mulc(0.50, 0.56, 0.47, nb.mul(band_k, wl_on))
    mulc(0.55, 0.53, 0.50, nb.mul(foot, wl_on))
    mulc(0.55, 0.55, 0.52, nb.mul(tide, wl_on))
    mulc(0.75, 0.75, 0.72, nb.mul(nb.add(nb.mul(old1, 0.7), nb.mul(old2, 0.5)), wl_on))
    mulc(1.16, 1.16, 1.12, nb.mul(mineral, nb.mul(wl_on, nb.sub(1.0, is_metal))))
    mulc(0.60, 0.62, 0.61, streak)
    mulc(0.62, 0.64, 0.64, damp_c)
    mulc(1.55, 1.55, 1.48, effl)
    mulc(0.95, 0.55, 0.32, rust)
    mulc(0.86, 0.86, 0.85, nb.mul(is_floor, nb.sub(1.0, floor_k)))
    out = nb.rgb(r, g_, b)
    nb.link(out, gout.inputs[0])
    return g


# ------------------------------------------------------------------ material builder
def _pbr(name, maps, kind, uv_scale_detail=None, tint_vc=False, alpha=None, wet_floor=False, emission=None, seed_node=True):
    """maps: dict albedo/normal/orm image names. kind: grime kind (0 concrete, 1 floor, 2 metal)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nb = NB(mat)
    out = nb.node("ShaderNodeOutputMaterial")
    bsdf = nb.node("ShaderNodeBsdfPrincipled")
    alb = nb.image(_img(maps["albedo"], "sRGB"))
    col = alb.outputs["Color"]
    if tint_vc:
        vc = nb.node("ShaderNodeVertexColor")
        vc.layer_name = "Color"
        tinted = nb.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
        tinted.inputs[0].default_value = 1.0
        nb.link(col, tinted.inputs[6])
        nb.link(vc.outputs["Color"], tinted.inputs[7])
        # albedo A = paint coverage: tint only the paint
        m = nb.node("ShaderNodeMix", data_type="RGBA")
        nb.link(alb.outputs["Alpha"], m.inputs[0])
        nb.link(col, m.inputs[6])
        nb.link(tinted.outputs[2], m.inputs[7])
        col = m.outputs[2]
    orm = nb.image(_img(maps["orm"], "Non-Color")) if maps.get("orm") else None
    rough = None
    metal = None
    if orm is not None:
        orr, org, orb = nb.sep_rgb(orm.outputs["Color"])
        rough = org
        metal = orb
    nrm_img = nb.image(_img(maps["normal"], "Non-Color")) if maps.get("normal") else None
    normal = None
    if nrm_img is not None:
        nm = nb.node("ShaderNodeNormalMap")
        nm.uv_map = "UVMap"
        nm.inputs["Strength"].default_value = 1.0
        nb.link(nrm_img.outputs["Color"], nm.inputs["Color"])
        normal = nm.outputs["Normal"]
    # grime
    gg = nb.node("ShaderNodeGroup")
    gg.node_tree = bpy.data.node_groups["CIS_Grime"]
    gg.inputs["Kind"].default_value = float(kind)
    seed_v = nb.node("ShaderNodeAttribute")
    seed_v.attribute_type = "OBJECT"
    seed_v.attribute_name = "cis_seed"
    nb.link(seed_v.outputs["Fac"], gg.inputs["Seed"])
    grime = gg.outputs["Grime"]
    gm = nb.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    gm.inputs[0].default_value = 1.0
    nb.link(col, gm.inputs[6])
    nb.link(grime, gm.inputs[7])
    col = gm.outputs[2]
    if wet_floor:
        # COLOR_0: R puddle, G damp, B silt; floor_wet: R puddle threshold, G damp, B silt pattern
        vc = nb.node("ShaderNodeVertexColor")
        vc.layer_name = "Color"
        vr, vg, vb = nb.sep_rgb(vc.outputs["Color"])
        wet_img = nb.image(_img("floor_wet.png", "Non-Color"))
        wr, wg, wb = nb.sep_rgb(wet_img.outputs["Color"])
        puddle = nb.smooth(nb.sub(vr, wr), -0.035, 0.035)
        wetm = nb.clamp01(nb.mul(vg, nb.add(0.55, nb.mul(wg, 0.6))))
        silt = nb.clamp01(nb.mul(vb, nb.add(0.3, nb.mul(wb, 0.9))))
        dark = nb.sub(1.0, nb.mul(wetm, 0.45))
        dark = nb.mul(dark, nb.sub(1.0, nb.mul(puddle, 0.25)))
        dm = nb.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
        dm.inputs[0].default_value = 1.0
        nb.link(col, dm.inputs[6])
        nb.link(nb.combine(dark, dark, dark), dm.inputs[7])
        sm = nb.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
        nb.link(silt, sm.inputs[0])
        nb.link(dm.outputs[2], sm.inputs[6])
        nb.link(nb.combine(0.62, 0.55, 0.44), sm.inputs[7])
        col = sm.outputs[2]
        r1 = nb.mix(rough, 0.28, wetm)
        r1 = nb.mix(r1, 0.6, nb.mul(silt, 0.5))
        rough = nb.mix(r1, 0.04, puddle)
        flat = nb.node("ShaderNodeNewGeometry").outputs["Normal"]
        nmix = nb.node("ShaderNodeMix", data_type="VECTOR")
        nb.link(puddle, nmix.inputs[0])
        nb.link(normal, nmix.inputs[4])
        nb.link(flat, nmix.inputs[5])
        normal = nmix.outputs[1]
        bsdf.inputs["Specular IOR Level"].default_value = 0.5
    nb.link(col, bsdf.inputs["Base Color"])
    if rough is not None:
        nb.link(rough, bsdf.inputs["Roughness"])
    if metal is not None:
        nb.link(metal, bsdf.inputs["Metallic"])
    if normal is not None:
        nb.link(normal, bsdf.inputs["Normal"])
    if alpha is not None:
        nb.link(alb.outputs["Alpha"], bsdf.inputs["Alpha"])
    shader = bsdf.outputs[0]
    # bake switch: emit the grime colour
    sw = nb.node("ShaderNodeGroup")
    sw.node_tree = bake_switch_group()
    em = nb.node("ShaderNodeEmission")
    nb.link(grime, em.inputs["Color"])
    mix = nb.node("ShaderNodeMixShader")
    nb.link(sw.outputs[0], mix.inputs[0])
    nb.link(shader, mix.inputs[1])
    nb.link(em.outputs[0], mix.inputs[2])
    nb.link(mix.outputs[0], out.inputs["Surface"])
    # lightmap bake target on UV2 (kept unlinked)
    bt = nb.node("ShaderNodeTexImage")
    bt.name = "BAKE_TARGET"
    bt.label = "BAKE_TARGET"
    uv2 = nb.node("ShaderNodeUVMap")
    uv2.uv_map = "UVMap_LM"
    nb.link(uv2.outputs[0], bt.inputs[0])
    mat.diffuse_color = (0.3, 0.3, 0.3, 1.0)
    return mat


def _emissive(name, color, strength, base=(0.9, 0.9, 0.9)):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nb = NB(mat)
    out = nb.node("ShaderNodeOutputMaterial")
    bsdf = nb.node("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.15
    bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
    st = nb.value(strength, "EMIT_STRENGTH")
    nb.link(st, bsdf.inputs["Emission Strength"])
    sw = nb.node("ShaderNodeGroup")
    sw.node_tree = bake_switch_group()
    em = nb.node("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    mix = nb.node("ShaderNodeMixShader")
    nb.link(sw.outputs[0], mix.inputs[0])
    nb.link(bsdf.outputs[0], mix.inputs[1])
    nb.link(em.outputs[0], mix.inputs[2])
    nb.link(mix.outputs[0], out.inputs["Surface"])
    bt = nb.node("ShaderNodeTexImage")
    bt.name = "BAKE_TARGET"
    uv2 = nb.node("ShaderNodeUVMap")
    uv2.uv_map = "UVMap_LM"
    nb.link(uv2.outputs[0], bt.inputs[0])
    mat.diffuse_color = (*color, 1.0)
    return mat


def _glass(name):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nb = NB(mat)
    out = nb.node("ShaderNodeOutputMaterial")
    bsdf = nb.node("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.6, 0.65, 0.62, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.08
    bsdf.inputs["Transmission Weight"].default_value = 0.85
    bsdf.inputs["Alpha"].default_value = 0.35
    nb.link(bsdf.outputs[0], out.inputs["Surface"])
    bt = nb.node("ShaderNodeTexImage")
    bt.name = "BAKE_TARGET"
    uv2 = nb.node("ShaderNodeUVMap")
    uv2.uv_map = "UVMap_LM"
    nb.link(uv2.outputs[0], bt.inputs[0])
    return mat


def setup_materials():
    bake_switch_group()
    grime_group()
    made = []
    made.append(_pbr("CIS_Concrete", {"albedo": "concrete_albedo.png", "normal": "concrete_normal.png", "orm": "concrete_orm.png"}, 0))
    made.append(_pbr("CIS_Interior", {"albedo": "concrete_albedo.png", "normal": "concrete_normal.png", "orm": "concrete_orm.png"}, 2))
    made.append(_pbr("CIS_Floor", {"albedo": "floor_albedo.png", "normal": "floor_normal.png", "orm": "floor_orm.png"}, 1, wet_floor=True))
    made.append(_pbr("CIS_SteelPaint", {"albedo": "steel_albedo.png", "normal": "steel_normal.png", "orm": "steel_orm.png"}, 2, tint_vc=True))
    made.append(_pbr("CIS_Galvanized", {"albedo": "galv_albedo.png", "normal": "galv_normal.png", "orm": "galv_orm.png"}, 2))
    made.append(_pbr("CIS_Grate", {"albedo": "grate_albedo.png", "normal": "grate_normal.png", "orm": "grate_orm.png"}, 2, alpha=True))
    made.append(_pbr("CIS_Hazard", {"albedo": "hazard_albedo.png", "normal": "steel_normal.png", "orm": "steel_orm.png"}, 2))
    import os as _os
    if _os.path.exists(TEX + "/cistern_sign.png"):
        made.append(_pbr("CIS_Sign", {"albedo": "cistern_sign.png", "normal": "steel_normal.png", "orm": "steel_orm.png"}, 2))
    made.append(_emissive("CIS_LampLens", C.blackbody(C.FLOOD_K), 60.0))
    made.append(_emissive("CIS_LampLensAmber", C.blackbody(C.AMBER_K), 18.0, base=(0.9, 0.55, 0.15)))
    made.append(_glass("CIS_WindowGlass"))
    made.append(_emissive("CIS_Void", (0.0, 0.0, 0.0), 0.0, base=(0.005, 0.005, 0.005)))
    try:
        bpy.data.materials["CIS_Grate"].surface_render_method = "DITHERED"
    except Exception:
        pass
    return [m.name for m in made]

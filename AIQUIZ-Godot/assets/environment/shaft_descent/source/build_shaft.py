"""Build the shaft-descent assets (docs/sudden_death_underground.md ch.5) in the LIVE Blender.

Run through the Higgsfield bl_execute connector, never in a headless Blender:

    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/shaft_descent/source/build_shaft.py",
              encoding="utf-8").read(), {"__name__": "__main__"})

Creates (idempotently, only SHD_* datablocks are touched):
  SHD_Tile      one 5 m ring of the R7.0 concrete shaft with its props (exported)
  SHD_Mouth     flush collar, 8 iris blades with pivots, 4 rotating beacons (exported)
  SHD_Deck      R5.2 elevator deck with grating, hazard band, shoes, wire anchors (exported)
  SHD_Sign      blank depth-sign board (exported)
  SHD_BakeStack 4 linked copies of the tile above/below for the lightmap bake
  SHD_Lights    the sodium lamps of the 5 stacked tiles (bake + review)
  SHD_Review    review camera
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/shaft_descent/source/shaft_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)
Acc, NB = C.Acc, C.NB
frame, T, rot_z = C.frame, C.T, C.rot_z
TAU = C.TAU

SODIUM = (1.0, 0.52, 0.13)


# =============================================================== materials
def _principled(name, color, rough, metal=0.0, emission=None, strength=0.0, alpha=None):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nb = NB(mat)
    out = nb.node("ShaderNodeOutputMaterial")
    bsdf = nb.node("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha is not None:
        bsdf.inputs["Alpha"].default_value = alpha
    nb.nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    mat.diffuse_color = (*color, 1.0)
    return mat


def concrete_material():
    """Procedural cast-in-place shaft concrete. BAKE_SEL picks a bake channel (0 = shaded).

    Every pattern is periodic: 2*pi around the shaft and 5 m vertically (the tile), using
    4D noise on (x, y, rho*cos(2*pi*z/5), rho*sin(2*pi*z/5)).
    """
    mat = bpy.data.materials.get("SHD_Concrete") or bpy.data.materials.new("SHD_Concrete")
    nb = NB(mat)
    tc = nb.node("ShaderNodeTexCoord")
    x, y, z = nb.separate(tc.outputs["Object"])
    theta = nb.math("ARCTAN2", y, x)
    u01 = nb.math("FRACT", nb.mul(theta, 1.0 / TAU))
    zph = nb.mul(z, TAU / C.TILE_H)
    rho = C.TILE_H / TAU
    zc = nb.mul(nb.math("COSINE", zph), rho)
    zs = nb.mul(nb.math("SINE", zph), rho)

    def P(sxy, sz, off=0.0):
        vec = nb.combine(nb.mul(x, sxy), nb.mul(y, sxy), nb.add(nb.mul(zc, sz), off))
        return vec, nb.mul(zs, sz)

    def noiseP(sxy, sz, off, detail=2.0, rough=0.5, distortion=0.0):
        vec, w = P(sxy, sz, off)
        return nb.noise4(vec, w, detail, rough, 2.0, distortion)

    # --- form panels and pours
    pan = nb.mul(u01, C.PANELS)
    pidx = nb.math("FLOOR", pan)
    pu = nb.mul(nb.math("FRACT", pan), C.PANEL_W)
    zl = nb.mul(nb.sub(z, C.JOINT_Z[0]), 1.0 / C.LIFT)
    lidx = nb.math("FLOOR", nb.mul(nb.math("FRACT", nb.mul(zl, 1.0 / 3.0)), 3.0))
    pv = nb.mul(nb.math("FRACT", zl), C.LIFT)            # height above the joint below
    dja = nb.sub(C.LIFT, pv)                               # depth below the joint above
    jn = nb.math("FLOORED_MODULO", nb.add(lidx, 1.0), 3.0)

    # --- form ties (3 x 2 per panel and pour)
    tpu = C.PANEL_W / 3.0
    tpv = C.LIFT / 2.0
    tu = nb.math("FRACT", nb.mul(pu, 1.0 / tpu))
    tv = nb.math("FRACT", nb.mul(pv, 1.0 / tpv))
    du = nb.mul(nb.math("ABSOLUTE", nb.sub(tu, 0.5)), tpu)
    dv = nb.mul(nb.math("ABSOLUTE", nb.sub(tv, 0.5)), tpv)
    dtie = nb.math("SQRT", nb.add(nb.mul(du, du), nb.mul(dv, dv)))
    cell = nb.combine(
        nb.add(nb.mul(pidx, 3.0), nb.math("FLOOR", nb.mul(pu, 1.0 / tpu))),
        nb.add(nb.mul(lidx, 2.0), nb.math("FLOOR", nb.mul(pv, 1.0 / tpv))),
        0.0,
    )
    rnd_tie = nb.white(cell)
    rnd_tie2 = nb.white(nb.combine(
        nb.add(nb.mul(pidx, 3.0), nb.math("FLOOR", nb.mul(pu, 1.0 / tpu))),
        nb.add(nb.mul(lidx, 2.0), nb.math("FLOOR", nb.mul(pv, 1.0 / tpv))),
        7.7,
    ))
    patched = nb.math("GREATER_THAN", rnd_tie, 0.62)
    hole = nb.sub(1.0, nb.smooth(dtie, 0.019, 0.025))
    ring = nb.mul(nb.smooth(dtie, 0.025, 0.028), nb.sub(1.0, nb.smooth(dtie, 0.033, 0.037)))
    h_tie = nb.sub(0.0, nb.add(nb.mul(hole, nb.sub(0.022, nb.mul(patched, 0.0205))), nb.mul(ring, 0.0012)))
    open_hole = nb.mul(hole, nb.sub(1.0, patched))
    tone_tie = nb.add(nb.sub(1.0, nb.mul(open_hole, 0.55)), nb.sub(nb.mul(nb.mul(hole, patched), 0.16), nb.mul(ring, 0.08)))

    # --- fine vertical streak noise shared by rust runs
    streak_fine = nb.smooth(noiseP(26.0, 0.6, 13.0, 2.0), 0.35, 0.6)

    below_tie = nb.math("LESS_THAN", tv, 0.5)
    tie_dz = nb.mul(nb.sub(0.5, tv), tpv)
    rusty = nb.mul(nb.math("GREATER_THAN", rnd_tie2, 0.74), nb.sub(1.0, patched))
    tie_col = nb.sub(1.0, nb.smooth(du, 0.006, nb.add(0.016, nb.mul(tie_dz, 0.05))))
    rust_tie = nb.mul(nb.mul(rusty, below_tie), nb.mul(tie_col, nb.math("EXPONENT", nb.mul(tie_dz, -1.0 / 0.2))))
    rust_tie = nb.add(nb.mul(rust_tie, nb.add(0.35, nb.mul(streak_fine, 0.65))), nb.mul(nb.mul(hole, rusty), 0.6))

    # --- panel joints (vertical) and their mortar fins
    dpj = nb.math("MINIMUM", pu, nb.sub(C.PANEL_W, pu))
    pj_line = nb.sub(1.0, nb.smooth(dpj, 0.0015, 0.0045))
    fin = nb.mul(nb.smooth(dpj, 0.0045, 0.006), nb.sub(1.0, nb.smooth(dpj, 0.008, 0.012)))
    fin = nb.mul(fin, nb.smooth(noiseP(3.0, 3.0, 17.0), 0.45, 0.6))

    # --- bugholes, denser near the top of each pour
    vvec, vw = P(32.0, 32.0, 3.1)
    vdist, vcol = nb.voronoi4(vvec, vw)
    vr = nb.bw(vcol)
    density = nb.add(0.05, nb.mul(nb.smooth(nb.mul(pv, 1.0 / C.LIFT), 0.55, 1.0), 0.16))
    pit = nb.mul(nb.math("GREATER_THAN", vr, nb.sub(1.0, density)), nb.sub(1.0, nb.smooth(vdist, 0.10, 0.24)))

    # --- surface relief
    grain = noiseP(2.5, 70.0, 1.7, 3.0)
    bulge = noiseP(1.1, 1.1, 5.3, 1.0)
    height = nb.add(h_tie, nb.mul(nb.sub(grain, 0.5), 0.0008))
    height = nb.add(height, nb.mul(nb.sub(bulge, 0.5), 0.004))
    height = nb.sub(height, nb.mul(pj_line, 0.0012))
    height = nb.add(height, nb.mul(fin, 0.0009))
    height = nb.sub(height, nb.mul(pit, 0.0045))

    # --- tone (linear albedo before wetness / deposits)
    tone_large = nb.mul(nb.sub(noiseP(0.3, 0.3, 9.1, 4.0), 0.5), 0.42)
    tone_mottle = nb.mul(nb.sub(noiseP(4.0, 4.0, 2.2, 6.0, 0.62, 0.4), 0.5), 0.22)
    tone_panel = nb.mul(nb.sub(nb.white(nb.combine(pidx, lidx, 3.3)), 0.5), 0.16)
    tone_lift = nb.mul(nb.sub(nb.white(nb.combine(lidx, 0.0, 8.8)), 0.5), 0.12)
    tone_grain = nb.mul(nb.sub(grain, 0.5), 0.05)
    tone = nb.add(nb.add(tone_large, tone_mottle), nb.add(tone_panel, nb.add(tone_lift, tone_grain)))
    tone = nb.mul(nb.add(1.0, tone), 0.30)
    tone = nb.mul(tone, tone_tie)
    tone = nb.mul(tone, nb.sub(1.0, nb.mul(pj_line, 0.12)))
    # cement paste bleeding out of the panel joints darkens a ragged band beside them
    paste = nb.mul(nb.sub(1.0, nb.smooth(dpj, 0.004, nb.add(0.02, nb.mul(noiseP(6.0, 6.0, 23.0, 3.0), 0.06)))), 0.18)
    tone = nb.mul(tone, nb.sub(1.0, paste))
    tone = nb.mul(tone, nb.sub(1.0, nb.mul(pit, 0.4)))
    dj_min = nb.math("MINIMUM", pv, dja)
    grime = nb.add(nb.mul(nb.math("EXPONENT", nb.mul(dj_min, -1.0 / 0.04)), 0.30),
        nb.mul(nb.math("EXPONENT", nb.mul(dja, -1.0 / 0.25)), 0.12))
    tone = nb.clamp01(nb.mul(tone, nb.sub(1.0, grime)))

    # --- wetness: seepage below the cold joints, streaks, long runs, blotches
    leak = nb.smooth(nb.noise4(nb.combine(nb.mul(x, 0.55), nb.mul(y, 0.55), nb.mul(jn, 3.7)), 0.0, 3.0, 0.55), 0.55, 0.68)
    seep_len = nb.add(0.05, nb.mul(nb.smooth(noiseP(3.0, 0.0, 27.0, 3.0), 0.3, 0.8), 0.25))
    seep = nb.mul(leak, nb.math("EXPONENT", nb.mul(dja, nb.math("DIVIDE", -1.0, seep_len))))
    sv, sw = (nb.combine(nb.mul(x, 8.0), nb.mul(y, 8.0), nb.add(nb.mul(zc, 0.35), nb.add(nb.mul(jn, 1.3), 11.0))), nb.mul(zs, 0.35))
    streak_n = nb.smooth(nb.noise4(sv, sw, 3.0), 0.52, 0.68)
    streaks = nb.mul(nb.mul(leak, streak_n), nb.math("EXPONENT", nb.mul(dja, -1.0 / 1.1)))
    lv, lw = (nb.combine(nb.mul(x, 6.0), nb.mul(y, 6.0), nb.add(nb.mul(zc, 0.09), 21.0)), nb.mul(zs, 0.09))
    long_runs = nb.mul(nb.smooth(nb.noise4(lv, lw, 2.0), 0.58, 0.72), nb.smooth(noiseP(0.25, 0.25, 31.0), 0.45, 0.7))
    blotch = nb.smooth(noiseP(0.6, 0.6, 41.0, 6.0, 0.6, 0.3), 0.62, 0.70)
    wet = nb.add(nb.add(seep, nb.mul(streaks, 0.95)), nb.add(nb.mul(long_runs, 0.75), nb.mul(blotch, 0.45)))
    wet = nb.clamp01(wet)

    # --- efflorescence: white crust under leaking joints, mineral runs, haze, tie rings
    leak2 = nb.smooth(nb.noise4(nb.combine(nb.mul(x, 0.6), nb.mul(y, 0.6), nb.add(nb.mul(jn, 5.1), 50.0)), 0.0, 2.0), 0.52, 0.68)
    crust = nb.mul(leak2, nb.math("EXPONENT", nb.mul(dja, -1.0 / 0.07)))
    rv, rw = (nb.combine(nb.mul(x, 14.0), nb.mul(y, 14.0), nb.add(nb.mul(zc, 0.5), nb.add(nb.mul(jn, 2.1), 61.0))), nb.mul(zs, 0.5))
    runs = nb.mul(nb.mul(leak2, nb.smooth(nb.noise4(rv, rw, 2.0), 0.6, 0.72)), nb.math("EXPONENT", nb.mul(dja, -1.0 / 0.6)))
    haze = nb.mul(nb.smooth(noiseP(0.9, 0.9, 71.0, 6.0, 0.6, 0.8), 0.63, 0.74), 0.35)
    tie_ring = nb.mul(nb.math("LESS_THAN", rnd_tie2, 0.05), nb.sub(1.0, nb.smooth(dtie, 0.03, 0.07)))
    effl = nb.clamp01(nb.add(nb.add(nb.mul(crust, 0.95), nb.mul(runs, 0.75)), nb.add(haze, nb.mul(tie_ring, 0.5))))

    # --- rust bleed below steel brackets (periodic columns)
    def column(psi_list, offsets, half, zb0, period, decay, strength):
        total = None
        for psi in psi_list:
            b = C.godot_angle(psi)
            d = nb.sub(nb.math("FRACT", nb.add(nb.mul(nb.sub(theta, b), 1.0 / TAU), 0.5)), 0.5)
            arc = nb.mul(d, TAU * C.R)
            for off in offsets:
                lat = nb.math("ABSOLUTE", nb.sub(arc, off))
                dz = nb.mul(nb.math("FRACT", nb.mul(nb.sub(zb0, z), 1.0 / period)), period)
                m = nb.mul(nb.sub(1.0, nb.smooth(lat, half * 0.35, nb.add(half, nb.mul(dz, 0.05)))),
                    nb.math("EXPONENT", nb.mul(dz, -1.0 / decay)))
                m = nb.mul(m, nb.add(0.3, nb.mul(streak_fine, 0.7)))
                total = m if total is None else nb.math("MAXIMUM", total, m)
        return nb.mul(total, strength)

    rust = rust_tie
    rust = nb.math("MAXIMUM", rust, column(C.RAIL_PSI, (-0.16, 0.16), 0.05, C.RAIL_BRACKET_Z[0] - 0.12, 1.25, 0.45, 0.9))
    rust = nb.math("MAXIMUM", rust, column(C.LAMP_PSI, (0.0,), 0.07, 2.80, C.TILE_H, 0.9, 0.75))
    rust = nb.math("MAXIMUM", rust, column([p["psi"] for p in C.PIPES], (0.0,), 0.06, C.PIPE_SUPPORT_Z[0] - 0.08, 2.5, 0.6, 0.7))
    rust = nb.math("MAXIMUM", rust, column((C.LADDER_PSI,), (-0.23, 0.23), 0.03, C.STANDOFF_Z[0] - 0.05, 1.25, 0.35, 0.6))
    rust = nb.math("MAXIMUM", rust, column((C.TRAY_PSI,), (-0.30, 0.30), 0.03, C.STANDOFF_Z[0] - 0.03, 1.25, 0.35, 0.6))
    rust = nb.clamp01(rust)

    # --- shaded preview (the Godot shader repeats this mix)
    base = nb.mul(tone, nb.sub(1.0, nb.mul(wet, 0.45)))
    ef = nb.mul(effl, 0.85)
    base = nb.add(nb.mul(base, nb.sub(1.0, ef)), nb.mul(ef, 0.62))
    rm = nb.mul(rust, 0.8)
    shade = nb.add(0.6, nb.mul(tone, 1.4))
    r_ch = nb.add(nb.mul(nb.mul(base, 0.99), nb.sub(1.0, rm)), nb.mul(rm, nb.mul(shade, 0.30)))
    g_ch = nb.add(nb.mul(nb.mul(base, 0.97), nb.sub(1.0, rm)), nb.mul(rm, nb.mul(shade, 0.13)))
    b_ch = nb.add(nb.mul(nb.mul(base, 0.93), nb.sub(1.0, rm)), nb.mul(rm, nb.mul(shade, 0.05)))
    col = nb.node("ShaderNodeCombineColor")
    nb.nt.links.new(r_ch, col.inputs[0])
    nb.nt.links.new(g_ch, col.inputs[1])
    nb.nt.links.new(b_ch, col.inputs[2])
    rough = nb.clamp01(nb.add(nb.sub(0.9, nb.mul(wet, 0.62)), nb.mul(effl, 0.06)))
    bump = nb.node("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 1.0
    bump.inputs["Distance"].default_value = 1.0
    nb.nt.links.new(height, bump.inputs["Height"])
    bsdf = nb.node("ShaderNodeBsdfPrincipled")
    nb.nt.links.new(col.outputs[0], bsdf.inputs["Base Color"])
    nb.nt.links.new(rough, bsdf.inputs["Roughness"])
    nb.nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    # --- bake selector -> emission
    sel = nb.value(0.0, "BAKE_SEL")
    chans = [nb.add(nb.mul(height, 10.0), 0.5), tone, wet, effl, rust]
    emit_val = None
    for i, ch in enumerate(chans):
        term = nb.mul(nb.math("COMPARE", sel, float(i + 1), 0.1), ch)
        emit_val = term if emit_val is None else nb.add(emit_val, term)
    emit = nb.node("ShaderNodeEmission")
    nb.nt.links.new(emit_val, emit.inputs["Color"])
    emit.inputs["Strength"].default_value = 1.0
    mix = nb.node("ShaderNodeMixShader")
    nb.nt.links.new(nb.math("GREATER_THAN", sel, 0.5), mix.inputs[0])
    nb.nt.links.new(bsdf.outputs[0], mix.inputs[1])
    nb.nt.links.new(emit.outputs[0], mix.inputs[2])
    out = nb.node("ShaderNodeOutputMaterial")
    nb.nt.links.new(mix.outputs[0], out.inputs["Surface"])
    # image node used as the bake target (kept inactive while rendering)
    img_node = nb.node("ShaderNodeTexImage")
    img_node.name = "BAKE_TARGET"
    img_node.label = "BAKE_TARGET"
    mat.diffuse_color = (0.3, 0.3, 0.29, 1.0)
    return mat


def detail_material():
    """Tileable 1 m x 1 m micro relief (pores, sand grains, trowel) for close-up detail normals."""
    mat = bpy.data.materials.get("SHD_ConcreteDetail") or bpy.data.materials.new("SHD_ConcreteDetail")
    nb = NB(mat)
    tc = nb.node("ShaderNodeTexCoord")
    u, v, _ = nb.separate(tc.outputs["UV"])
    rr = 1.0 / TAU
    cu = nb.mul(nb.math("COSINE", nb.mul(u, TAU)), rr)
    su = nb.mul(nb.math("SINE", nb.mul(u, TAU)), rr)
    cv = nb.mul(nb.math("COSINE", nb.mul(v, TAU)), rr)
    sv = nb.mul(nb.math("SINE", nb.mul(v, TAU)), rr)

    def N(scale, off, detail=3.0, rough=0.55):
        vec = nb.combine(nb.mul(cu, scale), nb.mul(su, scale), nb.add(nb.mul(cv, scale), off))
        return nb.noise4(vec, nb.mul(sv, scale), detail, rough)

    sand = nb.mul(nb.sub(N(180.0, 1.0, 2.0), 0.5), 0.0006)
    pores_d, pores_c = nb.voronoi4(
        nb.combine(nb.mul(cu, 90.0), nb.mul(su, 90.0), nb.add(nb.mul(cv, 90.0), 5.0)), nb.mul(sv, 90.0))
    pore = nb.mul(nb.math("GREATER_THAN", nb.bw(pores_c), 0.86), nb.sub(1.0, nb.smooth(pores_d, 0.08, 0.2)))
    soft = nb.mul(nb.sub(N(14.0, 9.0, 4.0), 0.5), 0.0012)
    h = nb.add(nb.add(sand, soft), nb.mul(pore, -0.0016))
    emit = nb.node("ShaderNodeEmission")
    nb.nt.links.new(nb.add(nb.mul(h, 100.0), 0.5), emit.inputs["Color"])
    out = nb.node("ShaderNodeOutputMaterial")
    nb.nt.links.new(emit.outputs[0], out.inputs["Surface"])
    img_node = nb.node("ShaderNodeTexImage")
    img_node.name = "BAKE_TARGET"
    return mat


def hazard_material(name="SHD_Hazard", period=0.32):
    """Diagonal yellow/black stripes by azimuth (preview only; Godot repeats this in a shader)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nb = NB(mat)
    tc = nb.node("ShaderNodeTexCoord")
    x, y, z = nb.separate(tc.outputs["Object"])
    r = nb.math("SQRT", nb.add(nb.mul(x, x), nb.mul(y, y)))
    theta = nb.math("ARCTAN2", y, x)
    s = nb.mul(nb.add(nb.add(nb.mul(theta, 5.0), r), z), 1.0 / period)
    stripe = nb.math("GREATER_THAN", nb.math("FRACT", s), 0.5)
    col = nb.node("ShaderNodeCombineColor")
    nb.nt.links.new(nb.add(nb.mul(stripe, 0.78), 0.02), col.inputs[0])
    nb.nt.links.new(nb.add(nb.mul(stripe, 0.47), 0.018), col.inputs[1])
    nb.nt.links.new(nb.add(nb.mul(stripe, 0.0), 0.015), col.inputs[2])
    bsdf = nb.node("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.55
    nb.nt.links.new(col.outputs[0], bsdf.inputs["Base Color"])
    out = nb.node("ShaderNodeOutputMaterial")
    nb.nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    mat.diffuse_color = (0.8, 0.5, 0.02, 1.0)
    return mat


def grating_material():
    mat = bpy.data.materials.get("SHD_Grating") or bpy.data.materials.new("SHD_Grating")
    nb = NB(mat)
    tc = nb.node("ShaderNodeTexCoord")
    x, y, _ = nb.separate(tc.outputs["Object"])
    bear = nb.math("LESS_THAN", nb.math("FRACT", nb.mul(x, 1.0 / 0.034)), 0.16)
    cross = nb.math("LESS_THAN", nb.math("FRACT", nb.mul(y, 1.0 / 0.10)), 0.07)
    alpha = nb.math("MAXIMUM", bear, cross)
    for sx in (-1.0, 1.0):
        dx = nb.sub(x, sx * C.PAD_X)
        d = nb.math("SQRT", nb.add(nb.mul(dx, dx), nb.mul(y, y)))
        alpha = nb.mul(alpha, nb.math("GREATER_THAN", d, C.PAD_PLATE_R))
    bsdf = nb.node("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.32, 0.33, 0.33, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.8
    bsdf.inputs["Roughness"].default_value = 0.5
    nb.nt.links.new(alpha, bsdf.inputs["Alpha"])
    out = nb.node("ShaderNodeOutputMaterial")
    nb.nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    try:
        mat.surface_render_method = "DITHERED"
    except Exception:
        pass
    mat.diffuse_color = (0.3, 0.3, 0.3, 0.5)
    return mat


def materials():
    m = {}
    m["concrete"] = concrete_material()
    m["detail"] = detail_material()
    m["rail"] = _principled("SHD_RailPaint", (0.105, 0.115, 0.11), 0.55)
    m["galv"] = _principled("SHD_Galvanized", (0.52, 0.53, 0.53), 0.42, 1.0)
    m["cable"] = _principled("SHD_Cable", (0.018, 0.018, 0.02), 0.62)
    m["lamp_body"] = _principled("SHD_LampBody", (0.34, 0.34, 0.32), 0.45, 0.3)
    m["lamp_glass"] = _principled("SHD_LampGlass", (1.0, 0.8, 0.5), 0.1, 0.0, SODIUM, 25.0)
    m["hazard"] = hazard_material()
    m["grating"] = grating_material()
    m["deck_frame"] = _principled("SHD_DeckFrame", (0.06, 0.065, 0.07), 0.5, 0.2)
    m["deck_metal"] = _principled("SHD_DeckMetal", (0.45, 0.46, 0.46), 0.4, 1.0)
    m["pad_plate"] = _principled("SHD_PadPlate", (0.16, 0.165, 0.17), 0.42, 0.75)
    m["blade"] = _principled("SHD_BladeSteel", (0.09, 0.095, 0.10), 0.45, 0.6)
    m["liner"] = _principled("SHD_CollarLiner", (0.12, 0.12, 0.12), 0.5, 0.5)
    m["pocket"] = _principled("SHD_Pocket", (0.03, 0.03, 0.03), 0.7)
    m["beacon_base"] = _principled("SHD_BeaconBase", (0.75, 0.47, 0.02), 0.45)
    m["beacon_lens"] = _principled("SHD_BeaconLens", (1.0, 0.6, 0.05), 0.1, 0.0, (1.0, 0.55, 0.05), 6.0)
    m["beacon_reflector"] = _principled("SHD_BeaconReflector", (0.9, 0.9, 0.9), 0.08, 1.0)
    m["sign_face"] = _principled("SHD_SignFace", (0.72, 0.70, 0.62), 0.28)
    m["sign_frame"] = _principled("SHD_SignFrame", (0.05, 0.05, 0.055), 0.5, 0.3)
    return m


# =============================================================== tile
def wall_object(mats, col):
    prof = [(C.R, 0.0)]
    sharp = []
    for zj in C.JOINT_Z:
        pts = [(C.R, zj - 0.023), (C.R + 0.003, zj - 0.020), (C.R + 0.020, zj - 0.008),
            (C.R + 0.020, zj + 0.008), (C.R + 0.003, zj + 0.020), (C.R, zj + 0.023)]
        for p in pts:
            sharp.append(len(prof))
            prof.append(p)
    prof.append((C.R, C.TILE_H))
    prof.reverse()                      # top -> bottom
    sharp = [len(prof) - 1 - i for i in sharp]
    acc = Acc()
    acc.lathe(prof, C.WALL_SEGMENTS, outward=False, smooth=True, sharp_rows=sharp)
    # UV: u around (ccw in Blender), v = profile length / total so 0 and 1 are the tile ends.
    lengths = [0.0]
    for a, b in zip(prof[:-1], prof[1:]):
        lengths.append(lengths[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    total = lengths[-1]
    for f in acc.bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            a = math.atan2(co.y, co.x) / TAU % 1.0
            uv = loop[acc.uv].uv
            z = co.z
            best = min(range(len(prof)), key=lambda i: abs(prof[i][1] - z) + abs(prof[i][0] - math.hypot(co.x, co.y)))
            uv.y = 1.0 - lengths[best] / total
        # fix the seam: a face spanning u ~ 0.99 -> 0.0 gets 1.0 on the right side
        us = []
        for loop in f.loops:
            co = loop.vert.co
            us.append(math.atan2(co.y, co.x) / TAU % 1.0)
        if max(us) - min(us) > 0.5:
            us = [u + 1.0 if u < 0.5 else u for u in us]
        for loop, u in zip(f.loops, us):
            loop[acc.uv].uv.x = u
    return acc.to_object("SHD_Tile_Wall", [mats["concrete"]], col), total


def lamp(body, glass, psi):
    M = frame(psi)
    ML = M @ T(0.0, C.LAMP_R, 0.0)
    body.box((0.0, C.R - 0.012, 3.05), (0.20, 0.024, 0.50), M)                     # wall plate
    arm0, arm1 = C.R - 0.024, C.LAMP_R + 0.12
    body.box((0.0, (arm0 + arm1) * 0.5, 3.235), (0.06, arm0 - arm1, 0.06), M)      # square-tube arm
    body.cyl((0.0, C.R - 0.03, 2.86), (0.0, C.LAMP_R + 0.12, 3.19), 0.012, 8, M)  # brace
    body.box((0.0, C.R - 0.055, 3.36), (0.13, 0.09, 0.10), M)                     # junction box
    body.cyl((0.0, C.R - 0.055, 3.41), (0.0, C.R - 0.055, 3.44), 0.016, 8, M)      # conduit drop
    for su in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            body.cyl((su * 0.07, C.R - 0.024, 3.05 + sz * 0.2), (su * 0.07, C.R - 0.036, 3.05 + sz * 0.2), 0.012, 6, M)
    housing = [(0.0, 3.365), (0.045, 3.36), (0.09, 3.345), (0.122, 3.31), (0.136, 3.275), (0.139, 3.245),
        (0.139, 3.11), (0.13, 3.093), (0.112, 3.087), (0.100, 3.087)]
    body.lathe(housing, 32, ML, outward=True, sharp_rows=(5, 7))
    for k in range(10):
        a = TAU * k / 10.0
        body.box((0.0, 0.0, 0.0), (0.008, 0.035, 0.12), ML @ rot_z(a) @ T(0.0, 0.152, 3.18))
    gl = [(0.100, 3.09), (0.104, 3.065), (0.105, 2.93), (0.099, 2.88), (0.086, 2.84),
        (0.063, 2.812), (0.034, 2.797), (0.0, 2.792)]
    glass.lathe(gl, 32, ML, outward=True)
    # guard cage: 6 rods + 3 rings
    rod = [(0.129, 3.092), (0.125, 3.0), (0.121, 2.93), (0.112, 2.865), (0.093, 2.815), (0.062, 2.78), (0.036, 2.768)]
    for k in range(6):
        a = TAU * (k + 0.5) / 6.0
        ca, sa = math.cos(a), math.sin(a)
        body.tube([(r * ca, r * sa, zz) for r, zz in rod], 0.0055, 6, ML, caps=False)
    body.ring_tube((0.0, 0.0, 2.93), 0.121, 0.006, 32, 6, ML)
    body.ring_tube((0.0, 0.0, 2.768), 0.036, 0.0065, 16, 6, ML)
    body.ring_tube((0.0, 0.0, 3.092), 0.129, 0.007, 32, 6, ML)


def rail(acc, psi):
    M = frame(psi)
    acc.box((0.0, 6.59, 2.5), (0.25, 0.02, 5.0), M)
    acc.box((0.0, 6.73, 2.5), (0.013, 0.26, 5.0), M)
    acc.box((0.0, 6.87, 2.5), (0.25, 0.02, 5.0), M)
    for su in (-1.0, 1.0):
        acc.box((su * 0.0125, 6.73, 0.0), (0.012, 0.20, 0.38), M)               # fishplates
        for sz in (-0.12, -0.04, 0.04, 0.12):
            acc.cyl((su * 0.019, 6.70, sz), (su * 0.028, 6.70, sz), 0.012, 6, M)
    for zb in C.RAIL_BRACKET_Z:
        acc.box((0.0, 6.99, zb), (0.42, 0.02, 0.24), M)
        for su in (-1.0, 1.0):
            acc.box((su * 0.10, 6.93, zb), (0.012, 0.10, 0.20), M)
            acc.box((su * 0.155, 6.885, zb), (0.07, 0.012, 0.09), M)            # flange clamps
            for sz in (-1.0, 1.0):
                acc.cyl((su * 0.17, 6.98, zb + sz * 0.08), (su * 0.17, 6.962, zb + sz * 0.08), 0.016, 6, M)
                acc.cyl((su * 0.17, 6.962, zb + sz * 0.08), (su * 0.17, 6.945, zb + sz * 0.08), 0.008, 6, M, caps=True)


def pipe(acc, spec):
    M = frame(spec["psi"])
    v = spec["v"]
    r = spec["radius"]
    segs = spec["segs"]
    acc.cyl((0.0, v, 0.0), (0.0, v, C.TILE_H), r, segs, M, caps=False)
    fz = spec["flange_z"]
    fr = r + 0.07
    acc.cyl((0.0, v, fz - 0.03), (0.0, v, fz - 0.002), fr, segs, M)
    acc.cyl((0.0, v, fz + 0.002), (0.0, v, fz + 0.03), fr, segs, M)
    for k in range(8):
        a = TAU * (k + 0.5) / 8.0
        pu, pv = math.cos(a) * (r + 0.045), v + math.sin(a) * (r + 0.045)
        acc.cyl((pu, pv, fz - 0.05), (pu, pv, fz + 0.05), 0.008, 6, M)
        acc.cyl((pu, pv, fz - 0.045), (pu, pv, fz - 0.03), 0.015, 6, M)
        acc.cyl((pu, pv, fz + 0.03), (pu, pv, fz + 0.045), 0.015, 6, M)
    for zs in C.PIPE_SUPPORT_Z:
        back = v + r + 0.012
        acc.box((0.0, (back + 6.98) * 0.5, zs), (0.07, 6.98 - back, 0.07), M)
        acc.box((0.0, 6.99, zs), (0.18, 0.02, 0.18), M)
        acc.box((0.0, back, zs), (2.0 * r + 0.09, 0.024, 0.05), M)
        band = []
        for i in range(17):
            a = math.pi * i / 16.0
            band.append((math.cos(a) * (r + 0.006), v - math.sin(a) * (r + 0.006)))
        acc.sweep_rect(band, zs, 0.004, 0.018, M)
        for su in (-1.0, 1.0):
            acc.cyl((su * (r + 0.03), back - 0.012, zs), (su * (r + 0.03), back - 0.04, zs), 0.013, 6, M)
    return acc


def ladder(acc, psi):
    M = frame(psi)
    sv = C.LADDER_V
    for su in (-1.0, 1.0):
        acc.box((su * 0.23, sv, 2.5), (0.012, 0.065, C.TILE_H), M)
    for z in C.RUNG_Z:
        acc.cyl((-0.23, sv - 0.005, z), (0.23, sv - 0.005, z), 0.0125, 8, M, caps=False)
    for zb in C.STANDOFF_Z:
        for su in (-1.0, 1.0):
            a, b = sv + 0.0325, 6.985
            acc.box((su * 0.23, (a + b) * 0.5, zb), (0.012, b - a, 0.06), M)
            acc.box((su * 0.23, 6.99, zb), (0.09, 0.02, 0.11), M)
    cv, cr = 6.48, 0.37
    a0 = math.asin((sv - cv) / cr)
    a1 = math.pi - a0 - TAU
    arc = []
    steps = 24
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        arc.append((cr * math.cos(a), cv + cr * math.sin(a)))
    path = [(0.236, sv)] + arc + [(-0.236, sv)]
    for zh in C.HOOP_Z:
        acc.sweep_rect(path, zh, 0.004, 0.025, M)
    for k in range(5):
        a = a0 + (a1 - a0) * (0.1 + 0.8 * k / 4.0)
        p = (cr * math.cos(a), cv + cr * math.sin(a))
        acc.box((p[0], p[1], 2.5), (0.04, 0.006, C.TILE_H), M, rot=rot_z(a + math.pi * 0.5))


def tray(acc, cables, psi):
    M = frame(psi)
    for su in (-1.0, 1.0):
        acc.box((su * 0.30, 6.87, 2.5), (0.006, 0.10, C.TILE_H), M)
        acc.box((su * 0.285, 6.823, 2.5), (0.03, 0.006, C.TILE_H), M)
        acc.box((su * 0.285, 6.917, 2.5), (0.03, 0.006, C.TILE_H), M)
    for z in C.RUNG_Z:
        acc.box((0.0, 6.885, z), (0.60, 0.03, 0.025), M)
    for zb in C.STANDOFF_Z:
        for su in (-1.0, 1.0):
            acc.box((su * 0.30, 6.955, zb), (0.03, 0.07, 0.05), M)
            acc.box((su * 0.30, 6.99, zb), (0.09, 0.02, 0.10), M)
    radii = (0.034, 0.028, 0.024, 0.024, 0.020, 0.018, 0.015)
    u = -0.265
    centers = []
    for r in radii:
        u += r
        centers.append((u, r))
        cables.cyl((u, 6.87 - r, 0.0), (u, 6.87 - r, C.TILE_H), r, 10, M, caps=False)
        u += r + 0.012
    for k, z in enumerate(C.RUNG_Z):
        if k % 3 == 1:
            for (cu, r) in centers:
                band = []
                for i in range(9):
                    a = math.pi * i / 8.0
                    band.append((cu + math.cos(a) * (r + 0.003), 6.87 - r - math.sin(a) * (r + 0.003)))
                cables.sweep_rect(band, z + 0.03, 0.002, 0.005, M)


def conduit(acc):
    acc.ring_tube((0.0, 0.0, C.CONDUIT_Z), C.CONDUIT_R, 0.02, 96, 6)
    for k in range(48):
        a = TAU * k / 48.0
        M = rot_z(a)
        acc.box((C.CONDUIT_R, 0.0, C.CONDUIT_Z), (0.05, 0.035, 0.05), M)


def build_tile(mats):
    col = C.collection("SHD_Tile")
    C.clear_collection(col)
    wall, vlen = wall_object(mats, col)
    rails = Acc()
    for psi in C.RAIL_PSI:
        rail(rails, psi)
    rails_obj = rails.to_object("SHD_Tile_Rails", [mats["rail"]], col)
    galv = Acc()
    cables = Acc()
    for spec in C.PIPES:
        pipe(galv, spec)
    ladder(galv, C.LADDER_PSI)
    tray(galv, cables, C.TRAY_PSI)
    conduit(galv)
    galv_obj = galv.to_object("SHD_Tile_Galv", [mats["galv"]], col)
    cable_obj = cables.to_object("SHD_Tile_Cables", [mats["cable"]], col)
    body = Acc()
    glass = Acc()
    for psi in C.LAMP_PSI:
        lamp(body, glass, psi)
    body_obj = body.to_object("SHD_Tile_LampBody", [mats["lamp_body"]], col)
    glass_obj = glass.to_object("SHD_Tile_LampGlass", [mats["lamp_glass"]], col)
    return [wall, rails_obj, galv_obj, cable_obj, body_obj, glass_obj], vlen


def build_stack(tile_objs):
    col = C.collection("SHD_BakeStack")
    C.clear_collection(col)
    for k in (-2, -1, 1, 2):
        for obj in tile_objs:
            dup = bpy.data.objects.new("%s_stack%+d" % (obj.name, k), obj.data)
            dup.location = (0.0, 0.0, k * C.TILE_H)
            col.objects.link(dup)
    return col


def build_lights():
    col = C.collection("SHD_Lights")
    C.clear_collection(col)
    lights = []
    for k in range(-2, 3):
        for psi in C.LAMP_PSI:
            a = C.godot_angle(psi)
            data = bpy.data.lights.new("SHD_Lamp_%+d_%d" % (k, int(psi)), "POINT")
            data.energy = 60.0
            data.color = SODIUM
            data.shadow_soft_size = 0.06
            obj = bpy.data.objects.new(data.name, data)
            obj.location = (C.LAMP_R * math.cos(a), C.LAMP_R * math.sin(a), C.LAMP_Z + k * C.TILE_H)
            col.objects.link(obj)
            lights.append(obj)
    return lights


# =============================================================== deck
def build_deck(mats):
    col = C.collection("SHD_Deck")
    C.clear_collection(col)
    root = bpy.data.objects.new("SHD_Deck_Root", None)
    col.objects.link(root)
    grating = Acc()
    segs = 96
    center = grating.bm.verts.new((0.0, 0.0, 0.0))
    ring = [grating.bm.verts.new((C.GRATING_RADIUS * math.cos(TAU * i / segs), C.GRATING_RADIUS * math.sin(TAU * i / segs), 0.0)) for i in range(segs)]
    for i in range(segs):
        f = grating.bm.faces.new((center, ring[i], ring[(i + 1) % segs]))
        for loop in f.loops:
            loop[grating.uv].uv = (loop.vert.co.x, loop.vert.co.y)
    g_obj = grating.to_object("SHD_Deck_Grating", [mats["grating"]], col)

    band = Acc()
    r0, r1, d = C.GRATING_RADIUS, C.DECK_RADIUS, C.DECK_DEPTH
    prof = [(r0, -0.10), (r0, 0.0), (r1 - 0.01, 0.0), (r1, -0.01), (r1, -d), (r1 - 0.06, -d)]
    band.lathe(prof, 128, outward=True, sharp_rows=(1, 2, 3, 4))
    band_obj = band.to_object("SHD_Deck_Band", [mats["hazard"]], col)

    frame_acc = Acc()
    frame_acc.lathe([(0.55, -0.03), (0.55, -0.40), (0.0, -0.40)], 24, outward=True)        # hub
    frame_acc.lathe([(4.85, -0.10), (4.85, -0.40), (4.95, -0.40)], 128, outward=False)        # ring web (inner)
    frame_acc.lathe([(4.95, -0.40), (5.14, -0.40)], 128, outward=False)                        # ring bottom
    for k in range(8):
        a = TAU * k / 8.0 + TAU / 16.0
        M = rot_z(a)
        frame_acc.box((2.7, 0.0, -0.04), (4.3, 0.16, 0.02), M)      # top flange
        frame_acc.box((2.7, 0.0, -0.21), (4.3, 0.012, 0.32), M)     # web
        frame_acc.box((2.7, 0.0, -0.38), (4.3, 0.16, 0.02), M)      # bottom flange
    for rr in (1.7, 3.4):
        n = 32
        for k in range(n):
            a0, a1 = TAU * k / n, TAU * (k + 1) / n
            p0 = Vector((rr * math.cos(a0), rr * math.sin(a0), -0.09))
            p1 = Vector((rr * math.cos(a1), rr * math.sin(a1), -0.09))
            mid = (p0 + p1) * 0.5
            frame_acc.box(mid, ((p1 - p0).length + 0.01, 0.08, 0.12), rot=rot_z(math.atan2((p1 - p0).y, (p1 - p0).x)))
    for psi in (0.0, 180.0):
        M = frame(psi)
        frame_acc.box((0.0, (5.15 + C.SHOE_V) * 0.5, -0.20), (0.24, C.SHOE_V - 5.15, 0.30), M)  # shoe arm
    frame_obj = frame_acc.to_object("SHD_Deck_Frame", [mats["deck_frame"]], col)

    # Opaque sockets under the two score-tower pads: the towers' tier columns hang
    # below their lifts, so nothing may be seen through the deck there.
    plate = Acc()
    for sx in (-1.0, 1.0):
        M = T(sx * C.PAD_X, 0.0, 0.0)
        plate.lathe([(0.0, 0.0), (C.PAD_PLATE_R, 0.0), (C.PAD_PLATE_R, -C.DECK_DEPTH), (0.0, -C.DECK_DEPTH)], 64, M,
            outward=True, sharp_rows=(1, 2))
        for k in range(12):
            a = TAU * (k + 0.5) / 12.0
            p = (sx * C.PAD_X + (C.PAD_PLATE_R - 0.06) * math.cos(a), (C.PAD_PLATE_R - 0.06) * math.sin(a))
            plate.cyl((p[0], p[1], -0.004), (p[0], p[1], 0.0), 0.02, 6)
    plate_obj = plate.to_object("SHD_Deck_PadPlate", [mats["pad_plate"]], col)

    metal = Acc()
    for psi in (0.0, 180.0):
        M = frame(psi)
        metal.box((0.0, C.SHOE_V + 0.07, -0.24), (0.22, 0.14, 0.36), M)         # shoe head (6.42..6.56), top -0.06
        for su in (-1.0, 1.0):
            metal.box((su * 0.15, 6.575, -0.24), (0.03, 0.09, 0.34), M)          # cheeks around the flange
            for zz in (-0.13, -0.36):
                metal.cyl((su * 0.06, 6.535, zz), (su * 0.06, 6.535, zz + 0.05), 0.04, 12, M)   # face rollers
        for zz in (-0.07, -0.41):
            metal.box((0.0, 6.47, zz), (0.30, 0.10, 0.02), M)
    empties = []
    for k, psi in enumerate(C.ANCHOR_PSI):
        M = frame(psi)
        metal.box((0.0, C.ANCHOR_R, 0.012), (0.26, 0.32, 0.024), M)                # base plate
        metal.box((0.0, C.ANCHOR_R, 0.08), (0.03, 0.20, 0.12), M)                  # padeye plate
        metal.cyl((-0.015, C.ANCHOR_R, 0.12), (0.015, C.ANCHOR_R, 0.12), 0.08, 20, M)  # rounded top
        metal.cyl((-0.05, C.ANCHOR_R, 0.14), (0.05, C.ANCHOR_R, 0.14), 0.02, 10, M)    # pin
        shackle = []
        for i in range(13):
            a = math.pi * i / 12.0
            shackle.append((0.045 * math.cos(a), C.ANCHOR_R, 0.14 + 0.11 * math.sin(a)))
        metal.tube(shackle, 0.011, 8, M, caps=True)
        metal.cyl((0.0, C.ANCHOR_R, 0.24), (0.0, C.ANCHOR_R, C.ANCHOR_TOP), 0.02, 8, M)   # wire socket
        for su in (-1.0, 1.0):
            for sv in (-1.0, 1.0):
                metal.cyl((su * 0.09, C.ANCHOR_R + sv * 0.12, 0.024), (su * 0.09, C.ANCHOR_R + sv * 0.12, 0.04), 0.014, 6, M)
        a = C.godot_angle(psi)
        e = bpy.data.objects.new("SHD_Deck_WireAnchor_%d" % k, None)
        e.empty_display_size = 0.1
        e.location = (C.ANCHOR_R * math.cos(a), C.ANCHOR_R * math.sin(a), C.ANCHOR_TOP)
        col.objects.link(e)
        empties.append(e)
    metal_obj = metal.to_object("SHD_Deck_Metal", [mats["deck_metal"]], col)
    for obj in [g_obj, band_obj, frame_obj, plate_obj, metal_obj] + empties:
        obj.parent = root
    return root


# =============================================================== mouth
def blade_region(i):
    """Pinwheel sector i between spiral boundaries, inner IRIS_IN, outer COLLAR_IN."""
    step = TAU / C.IRIS_BLADES
    return step * i, step * (i + 1)


def _slab(acc, r_in, r_out, ang0, ang1, z_top, z_bot, nr, na, uv_top=True):
    """Closed slab between two boundary curves ang0(r) .. ang1(r) (Blender radians)."""
    grid = []
    for j in range(nr + 1):
        r = r_in + (r_out - r_in) * j / nr
        b0, b1 = ang0(r), ang1(r)
        grid.append([(r * math.cos(b0 + (b1 - b0) * k / na), r * math.sin(b0 + (b1 - b0) * k / na), k / na, j / nr)
            for k in range(na + 1)])
    top = [[acc.bm.verts.new((p[0], p[1], z_top)) for p in row] for row in grid]
    bot = [[acc.bm.verts.new((p[0], p[1], z_bot)) for p in row] for row in grid]
    faces = []
    for j in range(nr):
        for k in range(na):
            f = acc.bm.faces.new((top[j][k], top[j][k + 1], top[j + 1][k + 1], top[j + 1][k]))
            if uv_top:
                for loop, (jj, kk) in zip(f.loops, ((j, k), (j, k + 1), (j + 1, k + 1), (j + 1, k))):
                    loop[acc.uv].uv = (grid[jj][kk][2], grid[jj][kk][3])
            faces.append(f)
            faces.append(acc.bm.faces.new((bot[j][k], bot[j + 1][k], bot[j + 1][k + 1], bot[j][k + 1])))

    def side(a_list, b_list):
        for k in range(len(a_list) - 1):
            faces.append(acc.bm.faces.new((a_list[k], a_list[k + 1], b_list[k + 1], b_list[k])))

    side([r[0] for r in top], [r[0] for r in bot])
    side([r[-1] for r in bot], [r[-1] for r in top])
    side(bot[0], top[0])
    side(top[-1], bot[-1])
    bmesh.ops.recalc_face_normals(acc.bm, faces=faces)
    for f in faces:
        f.smooth = False
    return faces


def build_blade(i, mats, col):
    """Iris blade i: pinwheel sector between spiral seams, top flush at z = 0 when closed.

    The body meets its neighbours exactly; a thin tab tucks under the next blade and an
    outer tab under the collar lip, so the closed iris shows no seam or rim gap. Godot
    opens it by dropping each blade 0.02 m and sliding it out along its pivot's radius.
    """
    acc = Acc()
    a0, a1 = blade_region(i)
    r_in, r_body, r_tab = C.IRIS_IN, C.COLLAR_IN - 0.002, C.COLLAR_IN + 0.05

    def seam(base):
        return lambda r: base + C.IRIS_TWIST * (r - r_in) / (C.COLLAR_IN - r_in)

    _slab(acc, r_in, r_body, seam(a0), seam(a1), 0.0, -0.045, 10, 14)
    _slab(acc, r_body, r_tab, seam(a0), seam(a1), -0.016, -0.045, 1, 14, uv_top=False)
    over = lambda r: seam(a1)(r) + C.IRIS_OVERLAP / r
    _slab(acc, r_in + 0.004, r_tab, seam(a1), over, -0.008, -0.040, 10, 1, uv_top=False)
    # Pivot = the blade's hinge: on the outer-edge mid azimuth, under the collar lip. Godot
    # opens the iris by rotating each blade 90+ deg down about the tangent through it.
    mid = (a0 + a1) * 0.5 + C.IRIS_TWIST
    origin = (C.IRIS_HINGE_R * math.cos(mid), C.IRIS_HINGE_R * math.sin(mid), C.IRIS_HINGE_Y)
    return acc.to_object("SHD_Blade_%d" % i, [mats["blade"]], col, origin=origin)


def build_beacon(k, psi, mats, col, root):
    a = C.godot_angle(psi)
    pos = (C.BEACON_R * math.cos(a), C.BEACON_R * math.sin(a), 0.0)
    base = Acc()
    base.lathe([(0.0, 0.10), (0.085, 0.10), (0.085, 0.055), (0.12, 0.05), (0.12, 0.0)], 24, outward=True, sharp_rows=(1, 2, 3))
    for i in range(4):
        ang = TAU * (i + 0.5) / 4.0
        ca, sa = math.cos(ang), math.sin(ang)
        pts = [(0.112, 0.09), (0.112, 0.30), (0.09, 0.345), (0.05, 0.37)]
        base.tube([(r * ca, r * sa, z) for r, z in pts], 0.007, 6, caps=False)
    base.ring_tube((0.0, 0.0, 0.20), 0.112, 0.007, 24, 6)
    base.lathe([(0.0, 0.385), (0.06, 0.38), (0.06, 0.365), (0.0, 0.365)], 16, outward=True)
    base_obj = base.to_object("SHD_Beacon_%d" % k, [mats["beacon_base"]], col)
    lens = Acc()
    lens.lathe([(0.0, 0.335), (0.045, 0.33), (0.075, 0.315), (0.088, 0.29), (0.090, 0.11), (0.092, 0.10)], 24, outward=True)
    lens_obj = lens.to_object("SHD_Beacon_%d_Lens" % k, [mats["beacon_lens"]], col)
    refl = Acc()
    refl.lathe([(0.06, 0.27), (0.062, 0.20), (0.06, 0.13)], 12, outward=False, phi0=math.pi * 0.5, phi1=math.pi * 1.5)
    refl.lathe([(0.0, 0.21), (0.02, 0.2), (0.02, 0.18), (0.0, 0.17)], 10, outward=True)
    refl.cyl((0.0, 0.0, 0.10), (0.0, 0.0, 0.17), 0.012, 8)
    refl_obj = refl.to_object("SHD_Beacon_%d_Reflector" % k, [mats["beacon_reflector"]], col)
    base_obj.location = pos
    base_obj.rotation_euler = (0.0, 0.0, a)
    base_obj.parent = root
    for child in (lens_obj, refl_obj):
        child.parent = base_obj
    return base_obj


def build_mouth(mats):
    col = C.collection("SHD_Mouth")
    C.clear_collection(col)
    root = bpy.data.objects.new("SHD_Mouth_Root", None)
    col.objects.link(root)
    collar = Acc()
    top = C.COLLAR_PROUD
    collar.lathe([(C.COLLAR_IN, -0.012), (C.COLLAR_IN + 0.012, top), (C.COLLAR_OUT - 0.01, top), (C.COLLAR_OUT, top - 0.01),
        (C.COLLAR_OUT, -0.06)], 192, outward=True, sharp_rows=(1, 2, 3))
    collar_obj = collar.to_object("SHD_Mouth_Collar", [mats["hazard"]], col)
    liner = Acc()
    # blade slot between the collar lip (-0.012) and the liner top (-0.075)
    # 15 mm proud of the concrete (r 7.0) so the two never share a depth plane.
    lr = C.COLLAR_IN - 0.015
    liner.lathe([(C.COLLAR_IN + 0.03, -0.075), (lr, -0.078), (lr, -0.85), (C.COLLAR_IN + 0.02, -0.88)],
        192, outward=False, sharp_rows=(1, 2))
    for k in range(48):
        a = TAU * (k + 0.5) / 48.0
        for rr in (C.COLLAR_IN + 0.06, C.COLLAR_OUT - 0.07):
            p = (rr * math.cos(a), rr * math.sin(a))
            liner.cyl((p[0], p[1], C.COLLAR_PROUD - 0.002), (p[0], p[1], C.COLLAR_PROUD + 0.012), 0.022, 6)
    liner_obj = liner.to_object("SHD_Mouth_Liner", [mats["liner"]], col)
    # Nothing of the mouth reaches past the collar's outer radius: folded blades hide in the
    # wall pocket behind the concrete (r >= 7.05, below the floor).
    stale = bpy.data.objects.get("SHD_Mouth_Pocket")
    if stale is not None:
        bpy.data.objects.remove(stale, do_unlink=True)
    for obj in (collar_obj, liner_obj):
        obj.parent = root
    for i in range(C.IRIS_BLADES):
        b = build_blade(i, mats, col)
        b.parent = root
    for k, psi in enumerate(C.BEACON_PSI):
        build_beacon(k, psi, mats, col, root)
    return root


# =============================================================== sign
def build_sign(mats):
    col = C.collection("SHD_Sign")
    C.clear_collection(col)
    root = bpy.data.objects.new("SHD_Sign_Root", None)
    col.objects.link(root)
    face = Acc()
    w, h, y0, y1 = 1.5, 0.75, 0.104, 0.124
    face.box((0.0, (y0 + y1) * 0.5, 0.0), (w, y1 - y0, h))
    # UVs: front face 0..1
    for f in face.bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[face.uv].uv = ((co.x + w * 0.5) / w, (co.z + h * 0.5) / h)
    face_obj = face.to_object("SHD_Sign_Board", [mats["sign_face"]], col)
    fr = Acc()
    t = 0.04
    for (cx, cz, sx, sz) in ((0.0, h * 0.5 + t * 0.5, w + 2 * t, t), (0.0, -h * 0.5 - t * 0.5, w + 2 * t, t),
            (w * 0.5 + t * 0.5, 0.0, t, h), (-w * 0.5 - t * 0.5, 0.0, t, h)):
        fr.box((cx, 0.115, cz), (sx, 0.035, sz))
    for sx in (-0.55, 0.55):
        for sz in (-0.25, 0.25):
            fr.box((sx, 0.05, sz), (0.04, 0.10, 0.04))
            fr.box((sx, 0.008, sz), (0.10, 0.016, 0.10))
    fr_obj = fr.to_object("SHD_Sign_Frame", [mats["sign_frame"]], col)
    anchor = bpy.data.objects.new("SHD_Sign_TextAnchor", None)
    anchor.location = (0.0, y1 + 0.002, 0.0)
    col.objects.link(anchor)
    for obj in (face_obj, fr_obj, anchor):
        obj.parent = root
    return root


# =============================================================== detail bake plane / review
def build_aux(mats):
    col = C.collection("SHD_Aux")
    C.clear_collection(col)
    acc = Acc()
    v = [acc.bm.verts.new(p) for p in ((0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0))]
    f = acc.bm.faces.new(v)
    for loop in f.loops:
        loop[acc.uv].uv = (loop.vert.co.x, loop.vert.co.y)
    plane = acc.to_object("SHD_DetailBakePlane", [mats["detail"]], col)
    plane.location = (30.0, 0.0, 0.0)
    plane.hide_render = True
    return plane


def build_review():
    col = C.collection("SHD_Review")
    C.clear_collection(col)
    cam_data = bpy.data.cameras.new("SHD_CAM_Review")
    cam_data.lens = 18.0
    cam_data.clip_end = 200.0
    cam = bpy.data.objects.new("SHD_CAM_Review", cam_data)
    col.objects.link(cam)
    cam.location = (0.0, 4.0, 11.5)
    direction = Vector((0.0, -6.0, -6.0))
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def setup_world():
    scene = bpy.context.scene
    world = bpy.data.worlds.get("SHD_World") or bpy.data.worlds.new("SHD_World")
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (0.0, 0.0, 0.0, 1.0)
        bg.inputs[1].default_value = 0.0
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.unit_settings.system = "METRIC"


def main():
    mats = materials()
    tile_objs, vlen = build_tile(mats)
    build_stack(tile_objs)
    build_lights()
    deck = build_deck(mats)
    deck.location = (0.0, 0.0, 6.0)
    mouth = build_mouth(mats)
    mouth.location = (0.0, 0.0, 15.0)
    sign = build_sign(mats)
    a = C.godot_angle(C.SIGN_PSI)
    sign.location = (C.R * math.cos(a), C.R * math.sin(a), 8.5)
    sign.rotation_euler = (0.0, 0.0, a + math.pi * 0.5)
    build_aux(mats)
    build_review()
    setup_world()
    tris = {}
    for col_name in ("SHD_Tile", "SHD_Deck", "SHD_Mouth", "SHD_Sign"):
        total = 0
        for obj in bpy.data.collections[col_name].all_objects:
            if obj.type == "MESH":
                obj.data.calc_loop_triangles()
                total += len(obj.data.loop_triangles)
        tris[col_name] = total
    return {"tris": tris, "wall_profile_length": vlen}


if __name__ == "__main__":
    _result = main()
    result = _result

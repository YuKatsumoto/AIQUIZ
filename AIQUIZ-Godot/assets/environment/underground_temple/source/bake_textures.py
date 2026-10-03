"""Bake the tiling PBR texture sets of the cistern from procedural Cycles materials (LIVE Blender).

No downloaded, purchased or generated images: every map is an emission bake of a node graph
on a unit plane, packed with numpy.

    ns = {"__name__": "cistern_tex"}
    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/bake_textures.py",
              encoding="utf-8").read(), ns)
    ns["bake_set"]("concrete")     # concrete, floor, steel, galv, grate, hazard, detail (one call each)
    ns["pack_set"]("concrete")     # -> textures/concrete_{albedo,normal,orm}.png ...

All patterns are periodic on the tile (4D noise on a torus), so every map tiles seamlessly.

| set      | tile (m per UV) | maps |
| concrete | 3.75 (4 x 2 form panels 0.9375 x 1.875) | albedo RGB, normal, orm (R AO, G rough, B metal) |
| floor    | 3.75 | albedo, normal, orm, wet (R puddle threshold, G damp, B silt) |
| steel    | 1.0  | albedo RGB (untinted) + A paint mask, normal, orm |
| galv     | 1.0  | albedo, normal, orm |
| grate    | 0.5  | albedo RGB + A coverage (alpha scissor), normal, orm |
| hazard   | 1.0  | albedo RGB + A paint mask (uses steel normal / orm) |
| detail   | 1.0  | detail normal (micro relief) |
"""
import json
import math
import os
import tempfile
import time

import bpy
import numpy as np

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/underground_temple/source/cistern_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)
NB = C.NB
TAU = C.TAU

CACHE = os.path.join(tempfile.gettempdir(), "aiquiz_cistern_tex")

SETS = {
    "concrete": {"tile": C.S_CONCRETE, "size": 2048, "passes": 2},
    "floor": {"tile": C.S_FLOOR, "size": 2048, "passes": 3},
    "steel": {"tile": C.S_STEEL, "size": 1024, "passes": 2},
    "galv": {"tile": C.S_GALV, "size": 1024, "passes": 2},
    "grate": {"tile": C.S_GRATE, "size": 512, "passes": 2},
    "hazard": {"tile": C.S_HAZARD, "size": 1024, "passes": 1},
    "detail": {"tile": 1.0, "size": 1024, "passes": 1},
}


# ------------------------------------------------------------------ periodic helpers
class Tile:
    """Node helpers for a periodic tile: u, v in [0, 1) map onto a 4D torus."""

    def __init__(self, nb, tile_m):
        self.nb = nb
        self.tile = tile_m
        tc = nb.node("ShaderNodeTexCoord")
        u, v, _ = nb.separate(tc.outputs["UV"])
        self.u = nb.math("FRACT", u)
        self.v = nb.math("FRACT", v)
        self.U = nb.mul(self.u, tile_m)      # metres
        self.Vm = nb.mul(self.v, tile_m)
        self.cu = nb.math("COSINE", nb.mul(self.u, TAU))
        self.su = nb.math("SINE", nb.mul(self.u, TAU))
        self.cv = nb.math("COSINE", nb.mul(self.v, TAU))
        self.sv = nb.math("SINE", nb.mul(self.v, TAU))

    def vec(self, fu, fv=None, off=0.0):
        """Torus point for fu x fv noise cells per tile."""
        nb = self.nb
        fv = fu if fv is None else fv
        ru, rv = fu / TAU, fv / TAU
        vec = nb.combine(nb.mul(self.cu, ru), nb.mul(self.su, ru), nb.add(nb.mul(self.cv, rv), off))
        return vec, nb.mul(self.sv, rv)

    def noise(self, fu, fv=None, off=0.0, detail=2.0, rough=0.5, distortion=0.0, lac=2.0):
        vec, w = self.vec(fu, fv, off)
        return self.nb.noise4(vec, w, detail, rough, lac, distortion)

    def voronoi(self, fu, fv=None, off=0.0, feature="F1", randomness=1.0):
        vec, w = self.vec(fu, fv, off)
        return self.nb.voronoi4(vec, w, randomness, feature)

    def per_metre(self, f):
        return f * self.tile


def _emit_material(name, passes):
    """Material whose emission shows pass BAKE_SEL (1-based); passes = list of colour sockets."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return mat


def _finish(nb, mat, passes):
    sel = nb.value(1.0, "BAKE_SEL")
    col = None
    for i, p in enumerate(passes):
        w = nb.math("COMPARE", sel, float(i + 1), 0.1)
        mixn = nb.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
        mixn.inputs[0].default_value = 1.0
        nb.link(p, mixn.inputs[6])
        nb.link(nb.combine(w, w, w), mixn.inputs[7])
        term = mixn.outputs[2]
        if col is None:
            col = term
        else:
            addn = nb.node("ShaderNodeMix", data_type="RGBA", blend_type="ADD")
            addn.inputs[0].default_value = 1.0
            nb.link(col, addn.inputs[6])
            nb.link(term, addn.inputs[7])
            col = addn.outputs[2]
    emit = nb.node("ShaderNodeEmission")
    nb.link(col, emit.inputs["Color"])
    emit.inputs["Strength"].default_value = 1.0
    out = nb.node("ShaderNodeOutputMaterial")
    nb.link(emit.outputs[0], out.inputs["Surface"])
    img = nb.node("ShaderNodeTexImage")
    img.name = "BAKE_TARGET"
    return mat


def gray(nb, x):
    return nb.combine(x, x, x)


# ------------------------------------------------------------------ concrete (form-panel finish)
def concrete_graph():
    mat = _emit_material("TEX_Concrete", 2)
    nb = NB(mat)
    T = Tile(nb, C.S_CONCRETE)
    pw, ph = C.S_CONCRETE / 4.0, C.S_CONCRETE / 2.0
    pu_n = nb.mul(T.U, 1.0 / pw)
    pv_n = nb.mul(T.Vm, 1.0 / ph)
    pi = nb.math("FLOOR", pu_n)
    pj = nb.math("FLOOR", pv_n)
    pu = nb.mul(nb.math("FRACT", pu_n), pw)
    pv = nb.mul(nb.math("FRACT", pv_n), ph)
    dju = nb.math("MINIMUM", pu, nb.sub(pw, pu))
    djv = nb.math("MINIMUM", pv, nb.sub(ph, pv))
    dj = nb.math("MINIMUM", dju, djv)
    prand = nb.white(nb.combine(pi, pj, 1.3))
    prand2 = nb.white(nb.combine(pi, pj, 5.9))
    # --- P-cone (form tie) holes: 2 x 3 per panel
    hu = nb.mul(nb.math("FRACT", nb.mul(pu, 2.0 / pw)), 1.0)
    hv = nb.mul(nb.math("FRACT", nb.mul(pv, 3.0 / ph)), 1.0)
    du = nb.mul(nb.math("ABSOLUTE", nb.sub(hu, 0.5)), pw / 2.0)
    dv = nb.mul(nb.math("ABSOLUTE", nb.sub(hv, 0.5)), ph / 3.0)
    dt = nb.math("SQRT", nb.add(nb.mul(du, du), nb.mul(dv, dv)))
    hcell = nb.combine(nb.add(nb.mul(pi, 2.0), nb.math("FLOOR", nb.mul(pu, 2.0 / pw))),
                       nb.add(nb.mul(pj, 3.0), nb.math("FLOOR", nb.mul(pv, 3.0 / ph))), 2.2)
    hr = nb.white(hcell)
    hr2 = nb.white(nb.add(hcell, nb.combine(0.0, 0.0, 4.4)))
    plugged = nb.math("GREATER_THAN", hr, 0.12)
    disc = nb.sub(1.0, nb.smooth(dt, 0.0135, 0.0155))
    ring = nb.mul(nb.smooth(dt, 0.0145, 0.016), nb.sub(1.0, nb.smooth(dt, 0.017, 0.021)))
    open_hole = nb.mul(disc, nb.sub(1.0, plugged))
    plug = nb.mul(disc, plugged)
    # --- surface fields
    grain = T.noise(T.per_metre(28.0), T.per_metre(2.2), 1.0, 3.0, 0.55)          # plywood grain (vertical panels)
    mott = T.noise(T.per_metre(1.6), None, 7.0, 4.0, 0.62, 0.25)
    mott2 = T.noise(T.per_metre(6.0), None, 11.0, 5.0, 0.6)
    bulge = T.noise(T.per_metre(0.9), None, 13.0, 2.0)
    vdist, vcol = T.voronoi(T.per_metre(55.0), None, 17.0)
    vr = nb.bw(vcol)
    top_bias = nb.smooth(T.v, 0.55, 1.0)                    # bugholes collect toward the top of a pour
    density = nb.add(0.06, nb.mul(top_bias, 0.16))
    pit = nb.mul(nb.math("GREATER_THAN", vr, nb.sub(1.0, density)), nb.sub(1.0, nb.smooth(vdist, 0.12, 0.32)))
    # joint line + occasional mortar fin + sand streak beside the joint (paste leakage)
    jline = nb.sub(1.0, nb.smooth(dj, 0.0008, 0.0026))
    fin_mask = nb.smooth(T.noise(T.per_metre(2.5), None, 19.0, 2.0), 0.52, 0.62)
    fin = nb.mul(nb.mul(nb.smooth(dj, 0.0026, 0.0036), nb.sub(1.0, nb.smooth(dj, 0.0045, 0.007))), fin_mask)
    sand_w = nb.add(0.008, nb.mul(T.noise(T.per_metre(7.0), None, 23.0, 3.0), 0.03))
    sand = nb.mul(nb.sub(1.0, nb.smooth(dj, 0.002, sand_w)), nb.smooth(T.noise(T.per_metre(3.0), None, 29.0, 3.0), 0.45, 0.65))
    # height (m)
    h = nb.mul(nb.sub(prand, 0.5), 0.0024)                           # panel steps
    h = nb.add(h, nb.mul(nb.sub(grain, 0.5), 0.00045))
    h = nb.add(h, nb.mul(nb.sub(bulge, 0.5), 0.0030))
    h = nb.add(h, nb.mul(nb.sub(mott2, 0.5), 0.0006))
    h = nb.sub(h, nb.mul(jline, 0.0012))
    h = nb.add(h, nb.mul(fin, 0.0010))
    h = nb.sub(h, nb.mul(plug, 0.0028))
    h = nb.sub(h, nb.mul(ring, 0.0008))
    h = nb.sub(h, nb.mul(open_hole, 0.016))
    h = nb.sub(h, nb.mul(pit, 0.0035))
    h = nb.sub(h, nb.mul(sand, 0.0006))
    # tone: clouds, per-sheet tone and form-oil blotches (pattern jumps at every sheet edge)
    cloud = T.noise(T.per_metre(0.55), None, 61.0, 3.0, 0.55, 1.6)
    oil_vec, oil_w = T.vec(T.per_metre(2.4), None, 67.0)
    oil = nb.noise4(nb.add(oil_vec, nb.combine(nb.mul(prand, 9.0), nb.mul(prand2, 7.0), 0.0)), oil_w, 4.0, 0.6, 2.0, 0.6)
    oil = nb.smooth(oil, 0.52, 0.75)
    speck_d, speck_c = T.voronoi(T.per_metre(260.0), None, 71.0)
    speck = nb.mul(nb.sub(nb.bw(speck_c), 0.5), nb.sub(1.0, nb.smooth(speck_d, 0.2, 0.5)))
    vbleed = nb.mul(nb.sub(1.0, nb.smooth(dju, 0.004, nb.add(0.02, nb.mul(T.noise(T.per_metre(4.0), T.per_metre(0.8), 73.0, 3.0), 0.07)))),
                    nb.smooth(T.noise(T.per_metre(2.0), T.per_metre(0.5), 79.0, 2.0), 0.4, 0.6))
    tone = nb.add(1.0, nb.mul(nb.sub(mott, 0.5), 0.42))
    tone = nb.add(tone, nb.mul(nb.sub(cloud, 0.5), 0.30))
    tone = nb.add(tone, nb.mul(nb.sub(mott2, 0.5), 0.12))
    tone = nb.add(tone, nb.mul(nb.sub(prand2, 0.5), 0.22))
    tone = nb.add(tone, nb.mul(nb.sub(grain, 0.5), 0.07))
    tone = nb.add(tone, nb.mul(speck, 0.16))
    tone = nb.mul(tone, nb.sub(1.0, nb.mul(oil, 0.14)))
    tone = nb.mul(tone, nb.sub(1.0, nb.mul(sand, 0.30)))
    tone = nb.mul(tone, nb.sub(1.0, nb.mul(vbleed, 0.20)))
    tone = nb.mul(tone, nb.sub(1.0, nb.mul(jline, 0.30)))
    tone = nb.mul(tone, nb.sub(1.0, nb.mul(pit, 0.55)))
    # bleed / laitance band just under the next cold joint (top of the tile = top of the pour)
    laitance = nb.mul(nb.math("EXPONENT", nb.mul(nb.sub(1.0, T.v), -C.S_CONCRETE / 0.10)), 0.18)
    tone = nb.mul(tone, nb.sub(1.0, laitance))
    base = nb.mul(tone, 0.30)
    # plugs: lighter, warmer mortar with a dark ring; open holes dark
    base = nb.add(nb.mul(base, nb.sub(1.0, plug)), nb.mul(plug, nb.add(0.235, nb.mul(nb.sub(hr2, 0.5), 0.10))))
    base = nb.mul(base, nb.sub(1.0, nb.mul(ring, 0.45)))
    base = nb.mul(base, nb.sub(1.0, nb.mul(open_hole, 0.75)))
    # rust stain under a few open holes, short water streak under some plugs
    tv = nb.math("FRACT", nb.mul(pv, 3.0 / ph))
    below = nb.math("LESS_THAN", tv, 0.5)
    dz = nb.mul(nb.sub(0.5, tv), ph / 3.0)
    streak_n = nb.smooth(T.noise(T.per_metre(40.0), T.per_metre(1.5), 31.0, 2.0), 0.4, 0.62)
    col_w = nb.sub(1.0, nb.smooth(du, 0.004, nb.add(0.011, nb.mul(dz, 0.04))))
    rusty = nb.mul(nb.math("GREATER_THAN", hr2, 0.70), nb.sub(1.0, plugged))
    rust = nb.mul(nb.mul(nb.mul(rusty, below), col_w), nb.math("EXPONENT", nb.mul(dz, -1.0 / 0.16)))
    rust = nb.mul(rust, nb.add(0.4, nb.mul(streak_n, 0.6)))
    rust = nb.math("MAXIMUM", rust, nb.mul(nb.mul(disc, rusty), 0.8))
    wetty = nb.mul(nb.math("LESS_THAN", hr2, 0.22), plugged)
    wstreak = nb.mul(nb.mul(nb.mul(wetty, below), col_w), nb.math("EXPONENT", nb.mul(dz, -1.0 / 0.22)))
    wstreak = nb.mul(wstreak, nb.add(0.3, nb.mul(streak_n, 0.7)))
    base = nb.mul(base, nb.sub(1.0, nb.mul(wstreak, 0.25)))
    # efflorescence haze (sparse)
    effl = nb.mul(nb.smooth(T.noise(T.per_metre(1.2), None, 37.0, 5.0, 0.62, 0.4), 0.66, 0.78), 0.55)
    base = nb.add(nb.mul(base, nb.sub(1.0, effl)), nb.mul(effl, 0.48))
    r = nb.add(nb.mul(nb.mul(base, 0.965), nb.sub(1.0, rust)), nb.mul(rust, 0.20))
    g = nb.add(nb.mul(nb.mul(base, 0.985), nb.sub(1.0, rust)), nb.mul(rust, 0.085))
    b = nb.add(nb.mul(nb.mul(base, 1.0), nb.sub(1.0, rust)), nb.mul(rust, 0.035))
    albedo = nb.rgb(r, g, b)
    rough = nb.clamp01(nb.add(nb.add(0.80, nb.mul(nb.sub(mott2, 0.5), 0.12)), nb.sub(nb.mul(plug, 0.06), nb.mul(wstreak, 0.25))))
    rough = nb.clamp01(nb.add(rough, nb.mul(effl, 0.08)))
    p2 = nb.combine(nb.add(nb.mul(h, 20.0), 0.5), rough, nb.add(rust, 0.0))
    return _finish(nb, mat, [albedo, p2])


# ------------------------------------------------------------------ floor (troweled, worn, wet)
def floor_graph():
    mat = _emit_material("TEX_Floor", 3)
    nb = NB(mat)
    T = Tile(nb, C.S_FLOOR)
    mott = T.noise(T.per_metre(0.9), None, 3.0, 4.0, 0.6, 0.3)
    mott2 = T.noise(T.per_metre(4.0), None, 5.0, 5.0, 0.6)
    swirl = T.noise(T.per_metre(1.6), None, 7.0, 2.0, 0.5, 2.5)
    trowel = nb.math("SINE", nb.mul(swirl, 60.0))
    wear = nb.smooth(T.noise(T.per_metre(0.45), None, 9.0, 3.0, 0.55), 0.48, 0.66)
    agg_d, agg_c = T.voronoi(T.per_metre(28.0), None, 11.0)
    agg_r = nb.bw(agg_c)
    stone = nb.mul(nb.sub(1.0, nb.smooth(agg_d, 0.25, 0.42)), wear)
    fine_d, fine_c = T.voronoi(T.per_metre(110.0), None, 13.0)
    fine = nb.mul(nb.sub(1.0, nb.smooth(fine_d, 0.15, 0.4)), nb.math("GREATER_THAN", nb.bw(fine_c), 0.6))
    # hairline cracks: thin voronoi borders, masked
    cr_vec, cr_w = T.vec(T.per_metre(0.8), None, 15.0)
    crn = nb.node("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature="DISTANCE_TO_EDGE")
    nb.link(cr_vec, crn.inputs["Vector"])
    nb.link(cr_w, crn.inputs["W"])
    crn.inputs["Scale"].default_value = 1.0
    crack_mask = nb.smooth(T.noise(T.per_metre(0.35), None, 17.0, 2.0), 0.6, 0.7)
    crack = nb.mul(nb.sub(1.0, nb.smooth(crn.outputs["Distance"], 0.0, 0.012)), crack_mask)
    # stains
    stain = nb.smooth(T.noise(T.per_metre(0.6), None, 19.0, 6.0, 0.65, 0.5), 0.62, 0.75)
    rust_st = nb.smooth(T.noise(T.per_metre(1.1), None, 21.0, 5.0, 0.6, 0.6), 0.70, 0.80)
    # height
    h = nb.mul(nb.sub(mott, 0.5), 0.002)
    h = nb.add(h, nb.mul(trowel, 0.00012))
    h = nb.add(h, nb.mul(stone, 0.0012))
    h = nb.sub(h, nb.mul(fine, 0.0012))
    h = nb.sub(h, nb.mul(crack, 0.0025))
    # albedo
    tone = nb.add(1.0, nb.mul(nb.sub(mott, 0.5), 0.30))
    tone = nb.add(tone, nb.mul(nb.sub(mott2, 0.5), 0.12))
    tone = nb.add(tone, nb.mul(wear, 0.12))
    base = nb.mul(tone, 0.17)
    sc = nb.add(0.10, nb.mul(agg_r, 0.26))
    base = nb.add(nb.mul(base, nb.sub(1.0, nb.mul(stone, 0.75))), nb.mul(nb.mul(stone, 0.75), sc))
    base = nb.mul(base, nb.sub(1.0, nb.mul(fine, 0.4)))
    base = nb.mul(base, nb.sub(1.0, nb.mul(crack, 0.55)))
    base = nb.mul(base, nb.sub(1.0, nb.mul(stain, 0.30)))
    r = nb.add(nb.mul(base, nb.sub(1.0, nb.mul(rust_st, 0.4))), nb.mul(rust_st, 0.05))
    g = nb.add(nb.mul(nb.mul(base, 0.985), nb.sub(1.0, nb.mul(rust_st, 0.4))), nb.mul(rust_st, 0.025))
    b = nb.add(nb.mul(nb.mul(base, 0.975), nb.sub(1.0, nb.mul(rust_st, 0.4))), nb.mul(rust_st, 0.01))
    albedo = nb.rgb(r, g, b)
    rough = nb.clamp01(nb.sub(nb.add(0.72, nb.mul(nb.sub(mott2, 0.5), 0.14)), nb.mul(wear, 0.16)))
    rough = nb.clamp01(nb.add(rough, nb.mul(stain, 0.06)))
    p2 = nb.combine(nb.add(nb.mul(h, 20.0), 0.5), rough, 0.0)
    # wet: R puddle threshold (low = fills first), G damp pattern, B silt streaks (along v = flow)
    lvl = T.noise(T.per_metre(0.55), None, 41.0, 3.0, 0.55)
    lvl2 = T.noise(T.per_metre(3.5), None, 43.0, 3.0, 0.5)
    thr = nb.clamp01(nb.add(nb.add(nb.mul(nb.sub(lvl, 0.5), 1.25), 0.5), nb.mul(nb.sub(lvl2, 0.5), 0.22)))
    thr = nb.clamp01(nb.sub(thr, nb.mul(crack, 0.25)))
    damp = T.noise(T.per_metre(1.8), None, 47.0, 5.0, 0.62, 0.8)
    silt = nb.smooth(T.noise(T.per_metre(6.0), T.per_metre(0.7), 53.0, 4.0, 0.6, 0.6), 0.45, 0.75)
    p3 = nb.combine(thr, damp, silt)
    return _finish(nb, mat, [albedo, p2, p3])


# ------------------------------------------------------------------ painted steel (tinted in Godot)
def steel_graph():
    mat = _emit_material("TEX_Steel", 2)
    nb = NB(mat)
    T = Tile(nb, C.S_STEEL)
    chipn = T.noise(T.per_metre(9.0), None, 3.0, 6.0, 0.62, 0.3)
    chip = nb.smooth(chipn, 0.615, 0.635)
    primer = nb.sub(nb.smooth(chipn, 0.585, 0.60), chip)
    pitn = T.noise(T.per_metre(90.0), None, 5.0, 3.0)
    streak = nb.smooth(T.noise(T.per_metre(22.0), T.per_metre(1.2), 7.0, 3.0), 0.55, 0.75)
    rustrun = nb.mul(streak, nb.smooth(T.noise(T.per_metre(1.6), None, 9.0, 2.0), 0.6, 0.75))
    dirt = T.noise(T.per_metre(3.0), None, 11.0, 5.0, 0.6, 0.4)
    peel = T.noise(T.per_metre(160.0), None, 13.0, 2.0)
    paint = nb.clamp01(nb.sub(nb.sub(1.0, chip), primer))
    paint = nb.clamp01(nb.sub(paint, nb.mul(rustrun, 0.7)))
    pv = nb.mul(nb.add(0.74, nb.mul(nb.sub(dirt, 0.5), 0.22)), nb.sub(1.0, nb.mul(nb.smooth(dirt, 0.6, 0.8), 0.25)))
    rust_r = nb.add(0.16, nb.mul(pitn, 0.12))
    r = nb.add(nb.add(nb.mul(pv, paint), nb.mul(primer, 0.30)), nb.mul(nb.clamp01(nb.sub(1.0, nb.add(paint, primer))), rust_r))
    g = nb.add(nb.add(nb.mul(pv, paint), nb.mul(primer, 0.085)), nb.mul(nb.clamp01(nb.sub(1.0, nb.add(paint, primer))), nb.mul(rust_r, 0.42)))
    b = nb.add(nb.add(nb.mul(pv, paint), nb.mul(primer, 0.05)), nb.mul(nb.clamp01(nb.sub(1.0, nb.add(paint, primer))), nb.mul(rust_r, 0.18)))
    albedo = nb.rgb(r, g, b)
    h = nb.add(nb.mul(paint, 0.00025), nb.mul(nb.sub(peel, 0.5), 0.00004))
    h = nb.sub(h, nb.mul(nb.mul(nb.sub(1.0, paint), pitn), 0.0002))
    rough = nb.clamp01(nb.add(nb.add(0.42, nb.mul(dirt, 0.25)), nb.mul(nb.sub(1.0, paint), 0.35)))
    p2 = nb.combine(nb.add(nb.mul(h, 200.0), 0.5), rough, paint)
    return _finish(nb, mat, [albedo, p2])


def galv_graph():
    mat = _emit_material("TEX_Galv", 2)
    nb = NB(mat)
    T = Tile(nb, C.S_GALV)
    sd, sc = T.voronoi(T.per_metre(38.0), None, 3.0)
    spang = nb.bw(sc)
    white = nb.smooth(T.noise(T.per_metre(4.0), None, 5.0, 6.0, 0.62, 0.5), 0.57, 0.68)
    dirt = T.noise(T.per_metre(2.0), None, 7.0, 5.0, 0.6, 0.5)
    streak = nb.smooth(T.noise(T.per_metre(18.0), T.per_metre(1.0), 9.0, 3.0), 0.55, 0.8)
    base = nb.add(0.50, nb.mul(nb.sub(spang, 0.5), 0.06))
    base = nb.mul(base, nb.sub(1.0, nb.mul(nb.smooth(dirt, 0.5, 0.8), 0.35)))
    base = nb.mul(base, nb.sub(1.0, nb.mul(streak, 0.2)))
    base = nb.add(nb.mul(base, nb.sub(1.0, white)), nb.mul(white, 0.68))
    albedo = nb.rgb(base, nb.mul(base, 1.0), nb.mul(base, 1.02))
    rough = nb.clamp01(nb.add(nb.add(0.38, nb.mul(nb.sub(spang, 0.5), 0.16)), nb.add(nb.mul(white, 0.4), nb.mul(dirt, 0.15))))
    h = nb.add(nb.mul(nb.sub(spang, 0.5), 0.00004), nb.mul(white, 0.00008))
    metal = nb.sub(1.0, nb.mul(white, 0.6))
    p2 = nb.combine(nb.add(nb.mul(h, 200.0), 0.5), rough, metal)
    return _finish(nb, mat, [albedo, p2])


def grate_graph():
    mat = _emit_material("TEX_Grate", 2)
    nb = NB(mat)
    T = Tile(nb, C.S_GRATE)
    # bearing bars: constant-v lines (16 per tile = 31.25 mm pitch, 5 mm thick); cross rods every 0.1 m
    bv = nb.mul(nb.math("ABSOLUTE", nb.sub(nb.math("FRACT", nb.mul(T.v, 16.0)), 0.5)), C.S_GRATE / 16.0)
    bar = nb.sub(1.0, nb.smooth(bv, 0.0022, 0.0030))
    cu = nb.mul(nb.math("ABSOLUTE", nb.sub(nb.math("FRACT", nb.mul(T.u, 5.0)), 0.5)), C.S_GRATE / 5.0)
    rod = nb.sub(1.0, nb.smooth(cu, 0.0026, 0.0034))
    clog = nb.smooth(T.noise(T.per_metre(6.0), None, 3.0, 4.0, 0.6), 0.66, 0.70)
    cover = nb.math("MAXIMUM", nb.math("MAXIMUM", bar, rod), clog)
    dirt = T.noise(T.per_metre(5.0), None, 5.0, 4.0)
    metal = nb.mul(nb.add(0.30, nb.mul(dirt, 0.12)), nb.sub(1.0, clog))
    mud = nb.mul(clog, 0.09)
    albedo_r = nb.add(metal, mud)
    albedo = nb.rgb(albedo_r, nb.add(nb.mul(metal, 0.98), nb.mul(mud, 0.85)), nb.add(nb.mul(metal, 0.95), nb.mul(mud, 0.62)))
    # alpha lives in the second pass (B) to keep emission bakes RGB
    h = nb.math("MAXIMUM", nb.mul(bar, nb.sub(1.0, nb.smooth(bv, 0.0, 0.003))), nb.mul(rod, 0.7))
    rough = nb.clamp01(nb.add(0.5, nb.mul(clog, 0.4)))
    p2 = nb.combine(nb.add(nb.mul(h, 0.4), 0.5), rough, cover)
    return _finish(nb, mat, [albedo, p2])


def hazard_graph():
    mat = _emit_material("TEX_Hazard", 1)
    nb = NB(mat)
    T = Tile(nb, C.S_HAZARD)
    s = nb.math("FRACT", nb.mul(nb.add(T.U, T.Vm), 4.0))
    stripe = nb.smooth(s, 0.495, 0.505)
    stripe = nb.sub(stripe, nb.smooth(s, 0.995, 1.0))
    wear = nb.smooth(T.noise(T.per_metre(8.0), None, 3.0, 6.0, 0.6, 0.3), 0.68, 0.71)
    dirt = T.noise(T.per_metre(2.5), None, 5.0, 4.0, 0.6, 0.5)
    yel = nb.combine(0.78, 0.50, 0.03)
    blk = nb.combine(0.03, 0.03, 0.03)
    mixn = nb.node("ShaderNodeMix", data_type="RGBA")
    nb.link(stripe, mixn.inputs[0])
    nb.link(blk, mixn.inputs[6])
    nb.link(yel, mixn.inputs[7])
    col = mixn.outputs[2]
    m2 = nb.node("ShaderNodeMix", data_type="RGBA")
    nb.link(wear, m2.inputs[0])
    nb.link(col, m2.inputs[6])
    nb.link(nb.combine(0.16, 0.08, 0.04), m2.inputs[7])
    d = nb.sub(1.0, nb.mul(nb.smooth(dirt, 0.45, 0.85), 0.45))
    m3 = nb.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    m3.inputs[0].default_value = 1.0
    nb.link(m2.outputs[2], m3.inputs[6])
    nb.link(nb.combine(d, d, d), m3.inputs[7])
    return _finish(nb, mat, [m3.outputs[2]])


def detail_graph():
    mat = _emit_material("TEX_Detail", 1)
    nb = NB(mat)
    T = Tile(nb, 1.0)
    sand = nb.mul(nb.sub(T.noise(180.0, None, 1.0, 2.0), 0.5), 0.0006)
    pd, pc = T.voronoi(90.0, None, 5.0)
    pore = nb.mul(nb.math("GREATER_THAN", nb.bw(pc), 0.86), nb.sub(1.0, nb.smooth(pd, 0.08, 0.2)))
    soft = nb.mul(nb.sub(T.noise(14.0, None, 9.0, 4.0), 0.5), 0.0012)
    h = nb.add(nb.add(sand, soft), nb.mul(pore, -0.0016))
    return _finish(nb, mat, [gray(nb, nb.add(nb.mul(h, 100.0), 0.5))])


GRAPHS = {"concrete": concrete_graph, "floor": floor_graph, "steel": steel_graph, "galv": galv_graph,
          "grate": grate_graph, "hazard": hazard_graph, "detail": detail_graph}
HEIGHT_SCALE = {"concrete": 20.0, "floor": 20.0, "steel": 200.0, "galv": 200.0, "grate": 0.4, "detail": 100.0}


# ------------------------------------------------------------------ bake plumbing
def _gpu():
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    bpy.context.scene.cycles.device = "GPU"


def _plane():
    name = "CIS_TexBakePlane"
    obj = bpy.data.objects.get(name)
    if obj is None:
        me = bpy.data.meshes.new(name)
        me.from_pydata([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], [], [(0, 1, 2, 3)])
        uv = me.uv_layers.new(name="UVMap")
        for i, loop in enumerate(me.loops):
            co = me.vertices[loop.vertex_index].co
            uv.data[i].uv = (co.x, co.y)
        obj = bpy.data.objects.new(name, me)
        col = C.collection("CIS_TexBake")
        col.objects.link(obj)
        obj.location = (0.0, 0.0, -500.0)
    lc = _layer_col(bpy.context.view_layer.layer_collection, "CIS_TexBake")
    if lc is not None:
        lc.exclude = False
    return obj


def _layer_col(lc, name):
    if lc.collection.name == name:
        return lc
    for ch in lc.children:
        r = _layer_col(ch, name)
        if r is not None:
            return r
    return None


def _image(name, w, h):
    img = bpy.data.images.get(name)
    if img is not None and (img.size[0] != w or img.size[1] != h):
        bpy.data.images.remove(img)
        img = None
    if img is None:
        img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    return img


def _select_only(obj):
    for o in bpy.context.view_layer.objects:
        if o.select_get():
            o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _cache(name):
    os.makedirs(CACHE, exist_ok=True)
    return os.path.join(CACHE, name)


def bake_set(name):
    t = time.time()
    info = SETS[name]
    mat = GRAPHS[name]()
    plane = _plane()
    plane.hide_render = False
    plane.data.materials.clear()
    plane.data.materials.append(mat)
    _gpu()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 9
    sc.cycles.use_denoising = False
    sc.render.bake.margin = 0
    size = info["size"]
    img = _image("CIS_TexBake", size, size)
    node = mat.node_tree.nodes["BAKE_TARGET"]
    node.image = img
    mat.node_tree.nodes.active = node
    _select_only(plane)
    stats = {}
    try:
        for p in range(1, info["passes"] + 1):
            mat.node_tree.nodes["BAKE_SEL"].outputs[0].default_value = float(p)
            bpy.ops.object.bake(type="EMIT", margin=0, use_clear=True)
            arr = np.empty(size * size * 4, np.float32)
            img.pixels.foreach_get(arr)
            arr = arr.reshape(size, size, 4)[:, :, :3].copy()
            np.save(_cache("%s_%d.npy" % (name, p)), arr)
            stats[p] = [round(float(arr[:, :, c].mean()), 4) for c in range(3)]
    finally:
        plane.hide_render = True
    return {"set": name, "secs": round(time.time() - t, 1), "means": stats}


# ------------------------------------------------------------------ packing
def _normal(h, px, strength=1.0):
    dhdx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2.0 * px)
    dhdy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / (2.0 * px)
    n = np.stack([-dhdx * strength, -dhdy * strength, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n


def _blur_wrap(a, sigma):
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (math.pi ** 2) * ((fx * sigma) ** 2 + (fy * sigma) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def save_png(name, rgba, path):
    h, w, ch = rgba.shape
    if ch == 3:
        rgba = np.dstack([rgba, np.ones((h, w), np.float32)])
    img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.clip(rgba, 0.0, 1.0).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def _ao(h, px):
    cav = h - _blur_wrap(h, 0.004 / px)
    return np.clip(1.0 + cav * 90.0, 0.35, 1.0)


def pack_set(name):
    t = time.time()
    info = SETS[name]
    size = info["size"]
    px = info["tile"] / size
    T = C.TEXTURES
    out = []
    p1 = np.load(_cache("%s_1.npy" % name))
    if name == "detail":
        h = (p1[:, :, 0] - 0.5) / HEIGHT_SCALE[name]
        n = _normal(h, px)
        save_png("tmp", n * 0.5 + 0.5, T + "/detail_normal.png")
        return {"set": name, "files": ["detail_normal.png"], "secs": round(time.time() - t, 1)}
    if name == "hazard":
        save_png("tmp", np.dstack([srgb(p1), np.ones((size, size), np.float32)]), T + "/hazard_albedo.png")
        return {"set": name, "files": ["hazard_albedo.png"], "secs": round(time.time() - t, 1)}
    p2 = np.load(_cache("%s_2.npy" % name))
    h = (p2[:, :, 0] - 0.5) / HEIGHT_SCALE[name]
    rough = p2[:, :, 1]
    n = _normal(h, px)
    ao = _ao(h, px)
    if name == "concrete":
        albedo = np.dstack([srgb(p1), np.ones((size, size), np.float32)])
        orm = np.dstack([ao, rough, np.zeros_like(ao)])
    elif name == "floor":
        albedo = np.dstack([srgb(p1), np.ones((size, size), np.float32)])
        orm = np.dstack([ao, rough, np.zeros_like(ao)])
        p3 = np.load(_cache("floor_3.npy"))
        save_png("tmp", p3, T + "/floor_wet.png")
        out.append("floor_wet.png")
    elif name == "steel":
        albedo = np.dstack([srgb(p1), p2[:, :, 2]])
        orm = np.dstack([ao, rough, np.zeros_like(ao)])
    elif name == "galv":
        albedo = np.dstack([srgb(p1), np.ones((size, size), np.float32)])
        orm = np.dstack([ao, rough, p2[:, :, 2]])
    elif name == "grate":
        albedo = np.dstack([srgb(p1), p2[:, :, 2]])
        orm = np.dstack([np.ones_like(ao), rough, np.full_like(ao, 0.8)])
    save_png("tmp", albedo, T + "/%s_albedo.png" % name)
    save_png("tmp", n * 0.5 + 0.5, T + "/%s_normal.png" % name)
    save_png("tmp", orm, T + "/%s_orm.png" % name)
    out += ["%s_albedo.png" % name, "%s_normal.png" % name, "%s_orm.png" % name]
    return {"set": name, "files": out, "secs": round(time.time() - t, 1),
            "albedo_mean": [round(float(p1[:, :, c].mean()), 4) for c in range(3)], "rough_mean": round(float(rough.mean()), 3)}


# ------------------------------------------------------------------ fictional facility sign
SIGN_FONT = "C:/Program Files/Blender Foundation/Blender 5.1/5.1/datafiles/fonts/Noto Sans CJK Regular.woff2"
SIGN_SIZE = (2048, 410)        # board 9.2 x 1.84 m


def _text(scene_col, body, size, loc, color, font, offset=0.0, align="CENTER", name="t"):
    cu = bpy.data.curves.new("CIS_SignTxt_" + name, "FONT")
    cu.body = body
    cu.font = font
    cu.size = size
    cu.align_x = align
    cu.align_y = "CENTER"
    cu.offset = offset
    ob = bpy.data.objects.new("CIS_SignTxt_" + name, cu)
    ob.location = (loc[0], loc[1], 0.01)
    mat = bpy.data.materials.new("CIS_SignTxtMat_" + name)
    mat.diffuse_color = (*color, 1.0)
    cu.materials.append(mat)
    scene_col.objects.link(ob)
    return ob


def bake_sign():
    """Render the board artwork (flat, orthographic) in a scratch scene, then weather it in numpy.
    Text: fictional facility name only (no real names, no logos). Font: Noto Sans CJK (OFL)."""
    t = time.time()
    font = bpy.data.fonts.get("NotoSansCJK") or bpy.data.fonts.load(SIGN_FONT)
    font.name = "NotoSansCJK"
    sc = bpy.data.scenes.get("CIS_SignScene") or bpy.data.scenes.new("CIS_SignScene")
    for o in list(sc.collection.objects):
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if isinstance(data, bpy.types.Curve):
            bpy.data.curves.remove(data)
    W, H = 9.2, 1.84
    navy = (0.012, 0.035, 0.11)
    white = (0.86, 0.86, 0.83)
    # board + navy band
    me = bpy.data.meshes.get("CIS_SignBoard") or bpy.data.meshes.new("CIS_SignBoard")
    me.clear_geometry()
    me.from_pydata([(-W / 2, -H / 2, 0), (W / 2, -H / 2, 0), (W / 2, H / 2, 0), (-W / 2, H / 2, 0),
                    (-W / 2, -H / 2, 0.005), (W / 2, -H / 2, 0.005), (W / 2, -H / 2 + 0.46, 0.005), (-W / 2, -H / 2 + 0.46, 0.005)], [],
                   [(0, 1, 2, 3), (4, 5, 6, 7)])
    mb = bpy.data.materials.get("CIS_SignBoardMat") or bpy.data.materials.new("CIS_SignBoardMat")
    mb.diffuse_color = (*white, 1.0)
    mn = bpy.data.materials.get("CIS_SignBandMat") or bpy.data.materials.new("CIS_SignBandMat")
    mn.diffuse_color = (*navy, 1.0)
    me.materials.clear()
    me.materials.append(mb)
    me.materials.append(mn)
    me.polygons[1].material_index = 1
    board = bpy.data.objects.new("CIS_SignBoardObj", me)
    sc.collection.objects.link(board)
    _text(sc.collection, "AIQUIZ 第3調圧水槽", 0.86, (-0.05, 0.40), navy, font, 0.005, name="jp")
    _text(sc.collection, "AIQUIZ No.3 SURGE TANK", 0.30, (0.0, -0.24), navy, font, 0.003, name="en")
    _text(sc.collection, "下流端  排水ポンプ吸込口   DOWNSTREAM END  ·  PUMP INTAKE", 0.22, (0.0, -0.69), white, font, 0.002, name="band")
    cam_data = bpy.data.cameras.get("CIS_SignCam") or bpy.data.cameras.new("CIS_SignCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = W
    cam = bpy.data.objects.new("CIS_SignCam", cam_data)
    cam.location = (0, 0, 5)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.render_aa = "32"
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = SIGN_SIZE
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    path = os.path.join(CACHE, "sign_raw.png")
    os.makedirs(CACHE, exist_ok=True)
    sc.render.filepath = path
    win = bpy.context.window or bpy.context.window_manager.windows[0]
    prev = win.scene
    try:
        win.scene = sc
        with bpy.context.temp_override(window=win, scene=sc):
            bpy.ops.render.render(write_still=True, scene=sc.name)
    finally:
        win.scene = prev
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    rgb = px.reshape(h, w, 4)[:, :, :3]            # display-referred sRGB values
    # weathering: grime toward the bottom, rust bleeding from the six stand-off bolts, soft blotches
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = yy / h                                       # 0 bottom .. 1 top (Blender rows)
    rng = np.random.default_rng(3)
    blot = np.zeros((h, w), np.float32)
    for _ in range(60):
        cx, cy, r = rng.uniform(0, w), rng.uniform(0, h), rng.uniform(20, 140)
        blot += np.exp(-(((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * r * r))) * rng.uniform(0.01, 0.05)
    grime = 1.0 - np.clip(blot, 0, 0.35) - 0.10 * (1.0 - v) ** 2
    rust = np.zeros((h, w), np.float32)
    for bx in (0.6, W / 2, W - 0.6):
        for by in (0.3, H - 0.3):
            cx = bx / W * w
            cy = by / H * h
            dy = np.clip(cy - yy, 0, None)
            lat = np.abs(xx - cx)
            rust += np.exp(-lat / (3.0 + dy * 0.05)) * np.exp(-dy / 55.0) * (yy < cy + 6)
            rust += np.exp(-(((xx - cx) ** 2 + (yy - cy) ** 2) / 60.0)) * 1.5
    rust = np.clip(rust, 0, 1)
    out = rgb * grime[:, :, None]
    rc = np.array([0.42, 0.20, 0.08], np.float32)
    out = out * (1 - 0.7 * rust[:, :, None]) + rc * 0.7 * rust[:, :, None]
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    out *= (0.75 + 0.25 * np.clip(edge / 12.0, 0, 1))[:, :, None]
    save_png("tmp", np.dstack([np.clip(out, 0, 1), np.ones((h, w), np.float32)]), C.TEXTURES + "/cistern_sign.png")
    # clean up the scratch scene
    for o in list(sc.collection.objects):
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if isinstance(data, bpy.types.Curve):
            bpy.data.curves.remove(data)
    return {"file": "cistern_sign.png", "size": [w, h], "secs": round(time.time() - t, 1)}


# ------------------------------------------------------------------ decal atlas
DECAL_SIZE = 2048
DECAL_CELL = 256
# name: (cell x, cell y, cells w, cells h) from the TOP-LEFT of the PNG, physical size (m), surface, note
DECALS = {
    "effl_run_a":    ((0, 0, 2, 4), (1.0, 2.0), "wall", "efflorescence crust under a joint with runs (top edge = joint)"),
    "effl_run_b":    ((2, 0, 2, 4), (1.0, 2.0), "wall", "efflorescence crust, variant"),
    "rust_run_long": ((4, 0, 1, 4), (0.4, 1.6), "wall", "rust bleed from a bolt / tie hole (top = source)"),
    "rust_run_a":    ((5, 0, 1, 2), (0.3, 0.6), "wall", "short rust bleed"),
    "rust_run_b":    ((5, 2, 1, 2), (0.3, 0.6), "wall", "short rust bleed, variant"),
    "leak_trace":    ((6, 0, 2, 4), (0.8, 1.6), "wall", "pipe leak: rust core, mineral edge, wet halo"),
    "water_streaks": ((0, 4, 4, 2), (2.4, 1.2), "wall", "dark water runoff streaks (top edge = source)"),
    "crack_effl":    ((4, 4, 2, 2), (1.2, 1.2), "wall/ceiling", "hairline crack with efflorescence"),
    "floor_ring":    ((6, 4, 2, 2), (1.6, 1.6), "floor", "dried puddle ring with silt"),
    "floor_stain":   ((0, 6, 2, 2), (1.6, 1.6), "floor", "rust / oil stain"),
    "effl_patch":    ((2, 6, 2, 2), (1.0, 1.0), "wall/ceiling", "efflorescence blotch"),
    "tide_marks":    ((4, 6, 4, 1), (4.0, 0.5), "wall", "tide-line band, tiles horizontally"),
    "digits":        ((4, 7, 4, 1), (1.6, 0.4), "pillar", "stencil digits 0-9, each 1/10 of the rect width"),
}


def _vnoise(h, w, cy, cx, rng):
    g = rng.random((cy + 2, cx + 2)).astype(np.float32)
    ys = np.linspace(0, cy, h, dtype=np.float32)
    xs = np.linspace(0, cx, w, dtype=np.float32)
    y0 = np.minimum(np.floor(ys).astype(int), cy)
    x0 = np.minimum(np.floor(xs).astype(int), cx)
    fy = ys - y0
    fx = xs - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]
    b = g[y0][:, x0 + 1]
    c = g[y0 + 1][:, x0]
    d = g[y0 + 1][:, x0 + 1]
    return (a * (1 - fx)[None, :] + b * fx[None, :]) * (1 - fy)[:, None] + (c * (1 - fx)[None, :] + d * fx[None, :]) * fy[:, None]


def _fbm(h, w, cy, cx, rng, octaves=5):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * _vnoise(h, w, max(1, cy * 2 ** o), max(1, cx * 2 ** o), rng)
        tot += amp
        amp *= 0.5
    return out / tot


def _ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def _edge_fade(h, w, m=0.06):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    ex = np.minimum(xx, w - 1 - xx) / (w * m)
    ey = np.minimum(yy, h - 1 - yy) / (h * m)
    return np.clip(np.minimum(ex, ey), 0, 1)


def _runs(h, w, rng, n, top_band, length, width, wander=0.04):
    """Vertical drips hanging from the top row (row 0 = top). Returns a 0..1 mask."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = yy / h
    u = xx / w
    m = np.zeros((h, w), np.float32)
    for _ in range(n):
        x0 = rng.uniform(0.08, 0.92)
        L = rng.uniform(length * 0.35, length)
        wd = rng.uniform(width * 0.5, width)
        drift = (_fbm(h, 1, 5, 1, rng, 3)[:, 0] - 0.5) * wander
        cx = x0 + drift
        taper = np.clip(1.0 - v[:, :1] / L, 0, 1) ** 0.6
        prof = np.exp(-((u - cx[:, None]) / (wd * (0.35 + 0.65 * taper))) ** 2)
        m = np.maximum(m, prof * taper * rng.uniform(0.5, 1.0))
    band = np.exp(-(v / max(1e-3, top_band)) ** 1.5)
    return np.clip(np.maximum(m, band * (0.6 + 0.4 * _fbm(h, w, 2, 6, rng, 4))), 0, 1)


def _blur(a, sigma):
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (math.pi ** 2) * ((fx * sigma) ** 2 + (fy * sigma) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def _digits_alpha(w, h):
    """Render 0-9 (Noto Sans CJK, OFL) as an alpha strip with an orthographic workbench render.
    Returns rows top-first."""
    font = bpy.data.fonts.get("NotoSansCJK") or bpy.data.fonts.load(SIGN_FONT)
    font.name = "NotoSansCJK"
    sc = bpy.data.scenes.get("CIS_SignScene") or bpy.data.scenes.new("CIS_SignScene")
    for o in list(sc.collection.objects):
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if isinstance(data, bpy.types.Curve):
            bpy.data.curves.remove(data)
    W = 10.0
    H = W * h / w
    for k in range(10):
        _text(sc.collection, str(k), H * 0.92, (-W / 2 + 0.5 + k, -H * 0.02), (1.0, 1.0, 1.0), font, 0.03, name="d%d" % k)
    cam_data = bpy.data.cameras.get("CIS_SignCam") or bpy.data.cameras.new("CIS_SignCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = W
    cam = bpy.data.objects.new("CIS_SignCam", cam_data)
    cam.location = (0, 0, 5)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "MATERIAL"
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    path = os.path.join(CACHE, "digits_raw.png")
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.filepath = path
    win = bpy.context.window or bpy.context.window_manager.windows[0]
    prev = win.scene
    try:
        win.scene = sc
        with bpy.context.temp_override(window=win, scene=sc):
            bpy.ops.render.render(write_still=True, scene=sc.name)
    finally:
        win.scene = prev
    img = bpy.data.images.load(path, check_existing=False)
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    for o in list(sc.collection.objects):
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if isinstance(data, bpy.types.Curve):
            bpy.data.curves.remove(data)
    a = px.reshape(h, w, 4)
    return (a[:, :, 3] * a[:, :, 0])[::-1].copy()


def bake_decals():
    """cistern_decals.png (sRGB albedo + alpha) and cistern_decals_normal.png, 2048^2, 8 x 8 cells
    of 256 px; the rects are returned (and written to cistern_layout.json by export_cistern)."""
    t = time.time()
    S = DECAL_SIZE
    rgba = np.zeros((S, S, 4), np.float32)       # rows TOP first; flipped when saved
    hgt = np.zeros((S, S), np.float32)

    def dims(name):
        (cx, cy, cw, ch), _, _, _ = DECALS[name]
        return ch * DECAL_CELL, cw * DECAL_CELL

    def put(name, col, alpha, height):
        (cx, cy, cw, ch), _, _, _ = DECALS[name]
        y0, x0 = cy * DECAL_CELL, cx * DECAL_CELL
        h, w = alpha.shape
        rgba[y0:y0 + h, x0:x0 + w, :3] = np.broadcast_to(col, (h, w, 3))
        rgba[y0:y0 + h, x0:x0 + w, 3] = alpha
        hgt[y0:y0 + h, x0:x0 + w] = height

    for name, seed in (("effl_run_a", 1), ("effl_run_b", 2)):
        h, w = dims(name)
        r = np.random.default_rng(seed)
        m = _runs(h, w, r, 14, 0.06, 0.9, 0.035, 0.05)
        grain = _fbm(h, w, 40, 20, r, 3)
        a = np.clip(m * (0.55 + 0.6 * grain) - 0.05, 0, 1) * _edge_fade(h, w)
        col = np.dstack([0.80 + 0.06 * grain, 0.80 + 0.06 * grain, 0.76 + 0.05 * grain])
        put(name, col, a, a * (0.6 + 0.4 * grain))
    for name, seed, n in (("rust_run_long", 3, 3), ("rust_run_a", 4, 2), ("rust_run_b", 5, 2)):
        h, w = dims(name)
        r = np.random.default_rng(seed)
        m = _runs(h, w, r, n, 0.02, 0.95, 0.10, 0.02)
        v = (np.arange(h, dtype=np.float32) / h)[:, None] * np.ones((1, w), np.float32)
        streak = _fbm(h, w, 30, 3, r, 3)
        a = np.clip(m * (0.6 + 0.6 * streak), 0, 1) * _edge_fade(h, w)
        k = np.clip(1.0 - v * 1.2, 0, 1)
        col = np.dstack([0.20 + 0.20 * k, 0.07 + 0.08 * k, 0.025 + 0.03 * k])
        put(name, col, a, a * 0.2)
    h, w = dims("leak_trace")
    r = np.random.default_rng(6)
    core = _runs(h, w, r, 4, 0.03, 0.9, 0.06, 0.02)
    halo = _runs(h, w, r, 6, 0.08, 1.0, 0.22, 0.03)
    grain = _fbm(h, w, 30, 15, r, 3)
    edge = np.clip(halo - core * 1.2, 0, 1) * _ss(0.4, 0.7, grain)
    a = np.clip(np.maximum(core, halo * 0.55), 0, 1) * _edge_fade(h, w)
    col = np.dstack([0.05 + 0.25 * core + 0.6 * edge, 0.05 + 0.09 * core + 0.6 * edge, 0.045 + 0.03 * core + 0.57 * edge])
    put("leak_trace", col, a, core * 0.3 + edge * 0.6)
    h, w = dims("water_streaks")
    r = np.random.default_rng(7)
    m = _runs(h, w, r, 26, 0.05, 1.0, 0.025, 0.02)
    a = np.clip(m * 0.85 * (0.5 + 0.7 * _fbm(h, w, 8, 30, r, 3)), 0, 1) * _edge_fade(h, w)
    put("water_streaks", np.array([0.06, 0.068, 0.06], np.float32), a, a * 0.05)
    h, w = dims("crack_effl")
    r = np.random.default_rng(8)
    crack = np.zeros((h, w), np.float32)
    for branch in range(3):
        p = np.array([r.uniform(0.2, 0.8) * w, 0.05 * h]) if branch == 0 else np.array([r.uniform(0.3, 0.7) * w, r.uniform(0.3, 0.6) * h])
        ang = math.pi / 2 + r.uniform(-0.3, 0.3)
        for step in range(220 if branch == 0 else 90):
            ang += r.normal(0, 0.18)
            p = p + np.array([math.cos(ang), math.sin(ang)]) * 4.0
            if not (0 <= p[0] < w and 0 <= p[1] < h):
                break
            iy, ix = int(p[1]), int(p[0])
            crack[max(0, iy - 1):iy + 2, max(0, ix - 1):ix + 2] = 1.0
    halo = _blur(crack, 10.0)
    halo /= max(1e-6, float(halo.max()))
    grain = _fbm(h, w, 20, 20, r, 4)
    halo = np.clip(halo * 2.2 * (0.4 + 0.8 * grain), 0, 1)
    a = np.clip(np.maximum(crack, halo * 0.8), 0, 1) * _edge_fade(h, w)
    col = np.dstack([0.78 - 0.7 * crack, 0.78 - 0.7 * crack, 0.74 - 0.68 * crack])
    put("crack_effl", col, a, halo * 0.5 - crack)
    h, w = dims("floor_ring")
    r = np.random.default_rng(9)
    n1 = _fbm(h, w, 6, 6, r, 4)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2)) + (n1 - 0.5) * 0.45
    ring = np.exp(-((d - 0.72) / 0.035) ** 2) + 0.35 * np.exp(-((d - 0.6) / 0.025) ** 2)
    inner = (1.0 - _ss(0.55, 0.75, d)) * 0.35
    a = np.clip(ring * 0.9 + inner, 0, 1) * _edge_fade(h, w)
    put("floor_ring", np.array([0.21, 0.18, 0.13], np.float32), a, ring * 0.1)
    h, w = dims("floor_stain")
    r = np.random.default_rng(10)
    n1 = _fbm(h, w, 5, 5, r, 5)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2)) + (n1 - 0.5) * 0.8
    a = (1.0 - _ss(0.35, 0.85, d)) * (0.5 + 0.5 * _fbm(h, w, 16, 16, r, 3)) * _edge_fade(h, w)
    put("floor_stain", np.dstack([0.16 + 0.10 * n1, 0.075 + 0.04 * n1, 0.03 + 0.01 * n1]), a, a * 0.02)
    h, w = dims("effl_patch")
    r = np.random.default_rng(11)
    n1 = _fbm(h, w, 5, 5, r, 5)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2)) + (n1 - 0.5) * 0.9
    g = _fbm(h, w, 40, 40, r, 3)
    a = np.clip((1.0 - _ss(0.3, 0.9, d)) * (0.4 + 0.9 * g) - 0.1, 0, 1) * _edge_fade(h, w)
    put("effl_patch", np.dstack([0.80 + 0.05 * g, 0.80 + 0.05 * g, 0.77 + 0.05 * g]), a, a * g)
    h, w = dims("tide_marks")
    v = (np.arange(h, dtype=np.float32) / h)[:, None]
    u = (np.arange(w, dtype=np.float32) / w)[None, :]
    wav = 0.04 * np.sin(TAU * (u * 3 + 0.2)) + 0.02 * np.sin(TAU * (u * 11 + 0.7))
    m = np.zeros((h, w), np.float32)
    for (c, wd, s) in ((0.35, 0.025, 1.0), (0.55, 0.012, 0.6), (0.72, 0.010, 0.45)):
        m = np.maximum(m, s * np.exp(-((v - c - wav) / wd) ** 2))
    below = _ss(0.36, 0.95, v + wav) * 0.35
    a = np.clip(m + below, 0, 1)
    a[:6, :] *= np.linspace(0, 1, 6, dtype=np.float32)[:, None]
    a[-6:, :] *= np.linspace(1, 0, 6, dtype=np.float32)[:, None]
    put("tide_marks", np.array([0.07, 0.085, 0.06], np.float32), a, m * 0.05)
    h, w = dims("digits")
    dig = _digits_alpha(w, h)
    r = np.random.default_rng(13)
    wear = _ss(0.25, 0.55, _fbm(h, w, 8, 40, r, 4))
    a = np.clip(dig * wear, 0, 1)
    put("digits", np.array([0.80, 0.80, 0.77], np.float32), a, a * 0.1)
    out = rgba[::-1].copy()
    out[:, :, :3] = srgb(out[:, :, :3])
    save_png("tmp", out, C.TEXTURES + "/cistern_decals.png")
    hh = hgt[::-1] * 0.002
    n = _normal(hh, 1.0 / 1024.0)
    save_png("tmp", np.dstack([n * 0.5 + 0.5, np.ones((S, S), np.float32)]), C.TEXTURES + "/cistern_decals_normal.png")
    atlas = {"files": {"albedo": "textures/cistern_decals.png", "normal": "textures/cistern_decals_normal.png"},
             "size_px": [S, S], "uv_origin": "top-left of the PNG (Godot UV convention)", "items": {}}
    for name, ((cx, cy, cw, ch), size, surf, note) in DECALS.items():
        atlas["items"][name] = {"rect_px": [cx * DECAL_CELL, cy * DECAL_CELL, cw * DECAL_CELL, ch * DECAL_CELL],
                                "uv_rect": [cx / 8.0, cy / 8.0, cw / 8.0, ch / 8.0], "size_m": list(size), "surface": surf, "note": note}
    with open(os.path.join(CACHE, "decals_atlas.json"), "w", encoding="utf-8") as fh:
        json.dump(atlas, fh, indent=2)
    return {"files": ["cistern_decals.png", "cistern_decals_normal.png"], "items": len(DECALS), "secs": round(time.time() - t, 1)}

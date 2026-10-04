"""Bake / review materials of the surge tank (LIVE Blender). Godot rebuilds the real materials from
textures (see README); these only have to give the Cycles bounce light the right colour and carry the
GRIME field that bake_tank.py multiplies into the light maps.

    ns = {"__name__": "tank_mats"}
    exec(open(".../source/materials_tank.py", encoding="utf-8").read(), ns)
    ns["setup_materials"]()

GRIME (multiplier, world coordinates converted to Godot space: x across, y up, z along), from the
reference photos of the tank:
  * walls and pillars: sediment stain, warm brown at the foot fading out by ~9 m (the lower third of
    every pillar is ochre-brown, the upper part pale grey), a darker wet band in the first 0.4 m, a few
    wavy tide lines (0.5 / 1.9 / 4.4 / 7.3 m), run-off streaks from the ceiling, per-pillar tone
  * ceiling: damp patches, darker toward the haunches, efflorescence runs along beam edges
  * floor: silt toward the side walls and the foot of the trench slopes (puddles, pillar rings and silt
    detail live in the Godot shader)
Heights are absolute (water rises from the trench floor), except the wet band at the foot, which follows the
local floor: the trench floor (y 0) or the shelves (y 5) outside the trench crest.
TK_BakeSwitch (shared node group) turns every material into an emission of its grime colour for the
GRIME bake.
"""
import bpy

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank/source/tank_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)
NB = C.NB


def bake_switch_group():
    g = bpy.data.node_groups.get("TK_BakeSwitch")
    if g is None:
        g = bpy.data.node_groups.new("TK_BakeSwitch", "ShaderNodeTree")
        g.interface.new_socket("Mode", in_out="OUTPUT", socket_type="NodeSocketFloat")
        out = g.nodes.new("NodeGroupOutput")
        val = g.nodes.new("ShaderNodeValue")
        val.name = "MODE"
        val.outputs[0].default_value = 0.0
        g.links.new(val.outputs[0], out.inputs[0])
    return g


def set_bake_mode(mode):
    """0 shaded, 1 emit the grime colour."""
    bake_switch_group().nodes["MODE"].outputs[0].default_value = float(mode)


def lin(nb, a, lo, hi):
    """Clamped linear ramp 0 at lo .. 1 at hi."""
    return nb.clamp01(nb.div(nb.sub(a, lo), hi - lo))


def grime_group():
    """Inputs: Kind (0 concrete, 1 floor, 2 steel). Output: Grime (RGB multiplier)."""
    name = "TK_Grime"
    g = bpy.data.node_groups.get(name)
    if g is not None:
        bpy.data.node_groups.remove(g)
    g = bpy.data.node_groups.new(name, "ShaderNodeTree")
    g.interface.new_socket("Kind", in_out="INPUT", socket_type="NodeSocketFloat")
    g.interface.new_socket("Grime", in_out="OUTPUT", socket_type="NodeSocketColor")
    nb = NB(g, clear=False)
    gin = nb.node("NodeGroupInput")
    gout = nb.node("NodeGroupOutput")
    kind = gin.outputs[0]
    geo = nb.node("ShaderNodeNewGeometry")
    bx, by, bz = nb.separate(geo.outputs["Position"])
    nx, ny, nz = nb.separate(geo.outputs["Normal"])
    # Godot space
    gx, gy, gz = bx, bz, nb.mul(by, -1.0)
    gny = nz
    pos_g = nb.combine(gx, gy, gz)
    up = nb.math("ABSOLUTE", gny)
    vertical = nb.sub(1.0, nb.smooth(up, 0.35, 0.8))           # 1 on walls and pillar shafts
    facing_down = nb.smooth(nb.mul(gny, -1.0), 0.5, 0.9)        # ceilings
    facing_up = nb.smooth(gny, 0.5, 0.9)                        # floor
    # large mottling and fine breakup
    big = nb.noise3(nb.combine(nb.mul(gx, 0.035), nb.mul(gy, 0.05), nb.mul(gz, 0.035)), detail=3.0, rough=0.55)
    mid = nb.noise3(nb.combine(nb.mul(gx, 0.21), nb.mul(gy, 0.18), nb.mul(gz, 0.21)), detail=4.0, rough=0.6)
    fine = nb.noise3(nb.combine(nb.mul(gx, 1.3), nb.mul(gy, 1.3), nb.mul(gz, 1.3)), detail=3.0, rough=0.6)
    # ---- walls / pillars: sediment stain fading with height (wobbly upper edge)
    wob = nb.mul(nb.sub(mid, 0.5), 2.6)
    stain_top = nb.add(8.5, nb.add(wob, nb.mul(nb.sub(big, 0.5), 3.0)))
    stain = nb.sub(1.0, nb.smooth(gy, 1.2, stain_top))          # 1 at the foot .. 0 above ~9 m
    stain = nb.mul(stain, nb.add(0.75, nb.mul(big, 0.5)))
    # trench crest along u (u = Z_PUMP - z): 27 at the pump end, 20 in the main stretch, 15 at the end wall
    u = nb.sub(C.Z_PUMP, gz)
    a, b, c = C.TRENCH_U
    crest = nb.sub(C.CREST_PUMP, nb.mul(lin(nb, u, a, b), C.CREST_PUMP - C.CREST_MAIN))
    crest = nb.sub(crest, nb.mul(lin(nb, u, c, C.END_U), C.CREST_MAIN - C.CREST_END))
    ax = nb.math("ABSOLUTE", gx)
    on_shelf = nb.smooth(nb.sub(ax, crest), -0.6, 0.2)
    local_y = nb.sub(gy, nb.mul(on_shelf, C.SHELF_Y))
    wetfoot = nb.sub(1.0, nb.smooth(local_y, 0.15, nb.add(0.45, nb.mul(fine, 0.2))))
    # tide lines: thin darker bands
    tides = None
    for h, w, s in ((0.55, 0.06, 0.16), (1.9, 0.08, 0.12), (4.4, 0.12, 0.08), (7.3, 0.16, 0.06)):
        hh = nb.add(h, nb.mul(nb.sub(mid, 0.5), 0.5))
        d = nb.math("ABSOLUTE", nb.sub(gy, hh))
        band = nb.mul(nb.sub(1.0, nb.smooth(d, w * 0.3, w)), s)
        tides = band if tides is None else nb.math("MAXIMUM", tides, band)
    # run-off streaks: noise stretched vertically, stronger high up
    streak_n = nb.noise3(nb.combine(nb.mul(nb.add(gx, gz), 1.7), nb.mul(gy, 0.08), nb.mul(gz, 0.05)), detail=2.0, rough=0.5)
    streaks = nb.mul(nb.smooth(streak_n, 0.56, 0.78), nb.add(0.25, nb.mul(nb.smooth(gy, 6.0, 17.0), 0.75)))
    # per-pillar / per-panel tone: a coarse cell noise on the floor plan
    cell_d, cell_c = nb.voronoi3(nb.combine(nb.mul(gx, 0.125), nb.mul(gz, 0.074), 0.0), scale=1.0, randomness=1.0)
    cell = nb.bw(cell_c)
    tone = nb.add(0.9, nb.mul(cell, 0.2))
    # colours (multipliers)
    brown = (0.52, 0.38, 0.22)
    wall_r = nb.mul(tone, nb.mix(1.0, brown[0], stain))
    wall_g = nb.mul(tone, nb.mix(1.0, brown[1], stain))
    wall_b = nb.mul(tone, nb.mix(1.0, brown[2], stain))
    dark = nb.add(nb.mul(wetfoot, 0.42), nb.add(nb.mul(tides, 1.0), nb.mul(streaks, 0.22)))
    dark = nb.math("MINIMUM", dark, 0.75)
    wall_k = nb.sub(1.0, dark)
    wall_r, wall_g, wall_b = nb.mul(wall_r, wall_k), nb.mul(wall_g, wall_k), nb.mul(wall_b, nb.mul(wall_k, 0.97))
    # ---- ceiling: damp patches, darker high up in the coffers
    damp = nb.smooth(nb.add(nb.mul(big, 0.7), nb.mul(mid, 0.5)), 0.55, 0.85)
    ceil_k = nb.sub(0.92, nb.mul(damp, 0.38))
    efflo = nb.mul(nb.smooth(fine, 0.72, 0.9), 0.25)
    ceil_r = nb.add(nb.mul(ceil_k, 0.95), efflo)
    ceil_g = nb.add(nb.mul(ceil_k, 0.92), efflo)
    ceil_b = nb.add(nb.mul(ceil_k, 0.86), efflo)
    # ---- floor: a little darker toward the walls (silt), mottled
    wall_dist = nb.sub(C.INNER_HALF, ax)
    silt = nb.sub(1.0, nb.smooth(wall_dist, 2.6, 9.0))
    toe_dist = nb.sub(nb.sub(crest, C.SLOPE_RUN), ax)
    in_trench = nb.sub(1.0, nb.smooth(gy, 1.5, 3.0))
    silt = nb.math("MAXIMUM", silt, nb.mul(nb.sub(1.0, nb.smooth(toe_dist, 0.8, 6.5)), in_trench))
    floor_k = nb.sub(1.0, nb.add(nb.mul(silt, 0.25), nb.mul(nb.sub(big, 0.5), 0.2)))
    floor_r, floor_g, floor_b = nb.mul(floor_k, 0.98), nb.mul(floor_k, 0.94), nb.mul(floor_k, 0.88)
    # ---- blend by orientation
    def pick(wv, cv, fv):
        v = nb.mix(wv, cv, facing_down)
        v = nb.mix(v, fv, facing_up)
        return v
    r = pick(wall_r, ceil_r, floor_r)
    gch = pick(wall_g, ceil_g, floor_g)
    b = pick(wall_b, ceil_b, floor_b)
    # steel (kind 2) only takes the stain at the foot, mildly
    is_steel = nb.smooth(kind, 1.5, 1.9)
    steel_k = nb.sub(1.0, nb.mul(stain, 0.25))
    r = nb.mix(r, steel_k, is_steel)
    gch = nb.mix(gch, steel_k, is_steel)
    b = nb.mix(b, nb.mul(steel_k, 0.95), is_steel)
    nb.link(nb.rgb(r, gch, b), gout.inputs[0])
    return g


BASE = {
    # name: (colour, roughness, metallic, kind)
    "TK_Concrete": ((0.32, 0.30, 0.27), 0.85, 0.0, 0.0),
    "TK_Pillar": ((0.33, 0.31, 0.28), 0.85, 0.0, 0.0),
    "TK_Floor": ((0.12, 0.105, 0.085), 0.4, 0.0, 1.0),
    "TK_Steel": ((0.16, 0.16, 0.16), 0.5, 0.4, 2.0),
    "TK_Paint": ((0.11, 0.24, 0.15), 0.55, 0.0, 2.0),
    "TK_Galv": ((0.56, 0.57, 0.58), 0.4, 0.9, 2.0),
    "TK_Grate": ((0.2, 0.2, 0.21), 0.6, 0.5, 2.0),
    "TK_Void": ((0.004, 0.004, 0.004), 1.0, 0.0, 2.0),
}
EMIT = {
    "TK_Lens": ((1.0, 0.97, 0.92), 40.0),
    "TK_Sky": ((0.82, 0.88, 1.0), 6.0),
}


def setup_materials():
    grime = grime_group()
    switch = bake_switch_group()
    done = []
    for name, (col, rough, metal, kind) in BASE.items():
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        nb = NB(m)
        out = nb.node("ShaderNodeOutputMaterial")
        gr = nb.node("ShaderNodeGroup")
        gr.node_tree = grime
        gr.inputs["Kind"].default_value = kind
        mix_col = nb.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
        mix_col.inputs[0].default_value = 1.0
        mix_col.inputs[6].default_value = col + (1.0,)
        nb.link(gr.outputs[0], mix_col.inputs[7])
        bsdf = nb.node("ShaderNodeBsdfPrincipled")
        nb.link(mix_col.outputs[2], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        emis = nb.node("ShaderNodeEmission")
        nb.link(gr.outputs[0], emis.inputs["Color"])
        emis.inputs["Strength"].default_value = 1.0
        sw = nb.node("ShaderNodeGroup")
        sw.node_tree = switch
        mix = nb.node("ShaderNodeMixShader")
        nb.link(sw.outputs[0], mix.inputs[0])
        nb.link(bsdf.outputs[0], mix.inputs[1])
        nb.link(emis.outputs[0], mix.inputs[2])
        nb.link(mix.outputs[0], out.inputs[0])
        tgt = nb.node("ShaderNodeTexImage")
        tgt.name = "BAKE_TARGET"
        tgt.label = "BAKE_TARGET"
        m.node_tree.nodes.active = tgt
        done.append(name)
    for name, (col, strength) in EMIT.items():
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        nb = NB(m)
        out = nb.node("ShaderNodeOutputMaterial")
        e = nb.node("ShaderNodeEmission")
        e.inputs["Color"].default_value = col + (1.0,)
        e.inputs["Strength"].default_value = strength
        # in the grime bake the lamps emit white 1 (no dirt on glass)
        e1 = nb.node("ShaderNodeEmission")
        e1.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        e1.inputs["Strength"].default_value = 1.0
        sw = nb.node("ShaderNodeGroup")
        sw.node_tree = switch
        mix = nb.node("ShaderNodeMixShader")
        nb.link(sw.outputs[0], mix.inputs[0])
        nb.link(e.outputs[0], mix.inputs[1])
        nb.link(e1.outputs[0], mix.inputs[2])
        nb.link(mix.outputs[0], out.inputs[0])
        tgt = nb.node("ShaderNodeTexImage")
        tgt.name = "BAKE_TARGET"
        tgt.label = "BAKE_TARGET"
        m.node_tree.nodes.active = tgt
        done.append(name)
    set_bake_mode(0)
    return {"materials": done}

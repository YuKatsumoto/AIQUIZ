"""水上機 C-130 の AO（環境光のさえぎり）を、ライブの Blender の Cycles で頂点色（色の属性 "AO"、角ごと）へ焼く。

Godot では fp_interior.gdshader が COLOR.r を AO として使う（環境光だけを暗くする。灯の光は消さない）。
外の材質は StandardMaterial3D に頂点色を弱く掛ける（fp_exterior の扱いは sudden_death_floatplane.gd）。
スロープと上のふたは閉じた形で焼く。ガラスと灯は焼かない（さえぎりにも入れない）。
"""
from __future__ import annotations

import time

import bpy

AO_ATTR = "AO"
NO_BAKE_PREFIX = ("Glass", "NavLight", "Beacon", "TailLight", "JumpLight", "MK_")


def flatten_big_polygons(me, attr, min_corners=7):
    """大きな多角形（前の壁・枠の面など）は角にしか頂点がないので、面の中の AO を角の平均にそろえる。"""
    data = attr.data
    for poly in me.polygons:
        if poly.loop_total < min_corners:
            continue
        idx = list(poly.loop_indices)
        m = sum(data[i].color[0] for i in idx) / len(idx)
        for i in idx:
            data[i].color = (m, m, m, 1.0)


def bake_ao(objs, distance=1.1, samples=96):
    sc = bpy.context.scene
    keep = {"engine": sc.render.engine, "samples": getattr(sc.cycles, "samples", 64), "device": getattr(sc.cycles, "device", "CPU")}
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    if sc.world is None:
        sc.world = bpy.data.worlds.new("FP_World")
    sc.world.light_settings.distance = distance
    sc.render.bake.target = "VERTEX_COLORS"
    sc.render.bake.use_selected_to_active = False
    sc.render.bake.margin = 0
    hidden = []
    for o in objs:
        if o.name.startswith(NO_BAKE_PREFIX) or o.name.startswith("Belt_"):
            if not o.hide_render:
                o.hide_render = True
                hidden.append(o)
    times = {}
    view_layer = bpy.context.view_layer
    for o in objs:
        if o.type != "MESH" or o.name.startswith(NO_BAKE_PREFIX):
            continue
        me = o.data
        attr = me.color_attributes.get(AO_ATTR) or me.color_attributes.new(AO_ATTR, "BYTE_COLOR", "CORNER")
        idx = list(me.color_attributes).index(attr)
        me.color_attributes.active_color_index = idx
        me.color_attributes.render_color_index = idx
        for other in view_layer.objects:
            other.select_set(False)
        o.select_set(True)
        view_layer.objects.active = o
        t0 = time.time()
        was_hidden = o.hide_render
        o.hide_render = False
        try:
            bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
        finally:
            o.hide_render = was_hidden
        flatten_big_polygons(me, attr)
        times[o.name] = round(time.time() - t0, 1)
    for o in hidden:
        o.hide_render = False
    # ベルトは灰色 1 のまま（AO なし）で色の属性だけ作る（書き出しの頂点の並びをそろえる）
    for o in objs:
        if o.type == "MESH" and o.name.startswith("Belt_"):
            me = o.data
            attr = me.color_attributes.get(AO_ATTR) or me.color_attributes.new(AO_ATTR, "BYTE_COLOR", "CORNER")
            attr.data.foreach_set("color", [1.0] * (4 * len(attr.data)))
            me.color_attributes.active_color_index = list(me.color_attributes).index(attr)
    sc.render.engine = keep["engine"]
    return times

"""サムネイル t8 のパネル（Blender のアドオン。3D ビューのサイドバー「Thumb」タブ）。

t8_thumbnail.blend の P1 のポーズを手で変えて、そのまま確認の絵・本番の絵まで作るためのボタン:
  ポーズを編集      ARM_P1 を選んでポーズモードに（骨を選んで R で回す。Alt+R で書き出しの姿＝全力疾走に戻る）
  ポーズを保存      いまの骨の姿を docs/pv/thumbnail/t8/blender_art.json の bone_pose に書き、.blend も保存する
  保存した姿に戻す  blender_art.json の bone_pose を当て直す
  確認の絵          1920×1080・24 サンプルで描き（画面は止まらない）、背景の絵とゲームの色で重ねて開く（blender/out/t8_prev_ui.png）
  本番を描く        1920×1080・384 サンプルで描き、背景・色・ロゴまで仕上げて開く（final/t8_blender.png・.jpg）
描画は render_layers.py の render_async（裏で描く。終わると .npy と done.txt）、合成はこの PC の Python で compose.py を動かす。
"""
bl_info = {
    "name": "AIQUIZ Thumbnail t8",
    "author": "AIQUIZ",
    "version": (1, 0, 0),
    "blender": (4, 2, 0),
    "location": "3D View > Sidebar > Thumb",
    "description": "t8 サムネイルのポーズ編集と描画",
    "category": "Render",
}

import os
import shutil
import subprocess

import bpy

def _root():
    """プロジェクト（project.godot のあるフォルダ）。開いている .blend から上へたどり、無ければ環境変数 AIQUIZ_ROOT、
    メインPC の C:\AIQUIZ\AIQUIZ-Godot・G:\AIQUIZ-Main\AIQUIZ-Godot、ノートPC の デスクトップ\AIQUIZ\AIQUIZ-Godot の順に探す"""
    p = bpy.data.filepath
    while p and os.path.dirname(p) != p:
        p = os.path.dirname(p)
        if os.path.isfile(os.path.join(p, "project.godot")):
            return p
    for c in (os.environ.get("AIQUIZ_ROOT", ""), r"C:\AIQUIZ\AIQUIZ-Godot", r"G:\AIQUIZ-Main\AIQUIZ-Godot",
              os.path.expanduser(r"~\Desktop\AIQUIZ\AIQUIZ-Godot")):
        if c and os.path.isfile(os.path.join(c, "project.godot")):
            return c
    raise RuntimeError("AIQUIZ-Godot が見つからない（環境変数 AIQUIZ_ROOT で指定できる）")


def _here():
    return os.path.join(_root(), "docs", "pv", "thumbnail", "blender")


def _ns():
    """build_scene.py と t8_art.py の関数（組み直しはしない）"""
    ns = bpy.app.driver_namespace.get("t8_ns")
    if ns is None or "save_pose" not in ns:
        ns = {}
        for name in ("build_scene.py", "t8_art.py"):
            exec(open(os.path.join(_here(), name), encoding="utf-8").read(), ns)
        bpy.app.driver_namespace["t8_ns"] = ns
    return ns


def _rl():
    rl = bpy.app.driver_namespace.get("t8_rl")
    if rl is None or "render_async" not in rl:
        rl = {}
        exec(open(os.path.join(_here(), "render_layers.py"), encoding="utf-8").read(), rl)
        bpy.app.driver_namespace["t8_rl"] = rl
    return rl


def _python():
    for name in ("python", "py"):
        p = shutil.which(name)
        if p:
            return p
    raise RuntimeError("この PC の Python が見つからない（合成に numpy と Pillow が要る）")


_STATE = {"busy": "", "msg": ""}


def _status(msg):
    _STATE["msg"] = msg
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == 'VIEW_3D':
                area.tag_redraw()


def _render_then_compose(tag, samples, args, open_path):
    """裏で描き、終わったら compose.py を別のプロセスで動かして、できた絵を開く（どれも Blender の画面を止めない）"""
    rl = _rl()
    info = rl["render_async"]("VL_t8", tag=tag, res=(1920, 1080), samples=samples)
    done, err = info["done"], info["done"].replace("_done.txt", "_error.txt")
    _STATE["busy"] = tag
    _status("描いています（%d サンプル）…" % samples)
    state = {"proc": None}

    def watch():
        if state["proc"] is None:
            if os.path.exists(err):
                _STATE["busy"] = ""
                _status("描画が止まりました：" + open(err, encoding="utf-8").read()[:120])
                return None
            if not os.path.exists(done):
                return 2.0
            _status("合成しています…")
            state["proc"] = subprocess.Popen([_python(), os.path.join(_here(), "compose.py"), "t8", tag] + args,
                                             cwd=_root(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            return 1.0
        if state["proc"].poll() is None:
            return 1.0
        out = state["proc"].stdout.read().decode("utf-8", "replace")
        _STATE["busy"] = ""
        if state["proc"].returncode != 0:
            _status("合成に失敗：" + out.strip().splitlines()[-1][:120] if out.strip() else "合成に失敗")
            return None
        path = os.path.join(_root(), open_path)
        _status("できました：" + open_path)
        if os.path.exists(path):
            os.startfile(path)
        return None

    bpy.app.timers.register(watch, first_interval=2.0)


class THUMB_OT_t8_edit_pose(bpy.types.Operator):
    bl_idname = "thumb.t8_edit_pose"
    bl_label = "ポーズを編集"
    bl_description = "ARM_P1 を選んでポーズモードにする（骨を選んで R で回す。Alt+R で書き出しの姿に戻る）"

    def execute(self, context):
        arm = bpy.data.objects.get("ARM_P1")
        if arm is None:
            self.report({'ERROR'}, "ARM_P1 がない（t8_art.py の setup() で骨を作る）")
            return {'CANCELLED'}
        if context.object is not None and context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        for o in context.view_layer.objects:
            o.select_set(False)
        context.view_layer.objects.active = arm
        arm.select_set(True)
        bpy.ops.object.mode_set(mode='POSE')
        _status("ポーズモード：骨をクリックして R（回す）。R X / R Y / R Z で軸を決められる")
        return {'FINISHED'}


class THUMB_OT_t8_save_pose(bpy.types.Operator):
    bl_idname = "thumb.t8_save_pose"
    bl_label = "ポーズを保存"
    bl_description = "いまの骨の姿を blender_art.json に書き、.blend も保存する"

    def execute(self, context):
        res = _ns()["save_pose"]()
        if context.object is not None and context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        bpy.ops.wm.save_mainfile()
        _status("保存しました（骨 %d 本）" % res["bones"])
        return {'FINISHED'}


class THUMB_OT_t8_load_pose(bpy.types.Operator):
    bl_idname = "thumb.t8_load_pose"
    bl_label = "保存した姿に戻す"
    bl_description = "blender_art.json の bone_pose を当て直す"

    def execute(self, context):
        ns = _ns()
        res = ns["apply_bone_pose"](ns["_art"]())
        _status("戻しました（骨 %d 本）" % res["applied"])
        return {'FINISHED'}


class THUMB_OT_t8_preview(bpy.types.Operator):
    bl_idname = "thumb.t8_preview"
    bl_label = "確認の絵"
    bl_description = "1920×1080・24 サンプルで描き、背景とゲームの色で重ねて開く"

    def execute(self, context):
        if _STATE["busy"]:
            self.report({'WARNING'}, "描画中です")
            return {'CANCELLED'}
        if context.object is not None and context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        _render_then_compose("prev_ui", 24, [], os.path.join("docs", "pv", "thumbnail", "blender", "out", "t8_prev_ui.png"))
        return {'FINISHED'}


class THUMB_OT_t8_final(bpy.types.Operator):
    bl_idname = "thumb.t8_final"
    bl_label = "本番を描く"
    bl_description = "1920×1080・384 サンプルで描き、背景・色・ロゴまで仕上げて開く（final/t8_blender）"

    def execute(self, context):
        if _STATE["busy"]:
            self.report({'WARNING'}, "描画中です")
            return {'CANCELLED'}
        if context.object is not None and context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        bpy.ops.wm.save_mainfile()
        _render_then_compose("final1080", 384, ["final"], os.path.join("docs", "pv", "thumbnail", "final", "t8_blender.jpg"))
        return {'FINISHED'}


class THUMB_PT_t8(bpy.types.Panel):
    bl_label = "サムネイル t8"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Thumb"

    def draw(self, context):
        col = self.layout.column(align=True)
        col.operator("thumb.t8_edit_pose", icon='ARMATURE_DATA')
        col.operator("thumb.t8_save_pose", icon='FILE_TICK')
        col.operator("thumb.t8_load_pose", icon='LOOP_BACK')
        col.separator()
        col.operator("thumb.t8_preview", icon='RENDER_STILL')
        col.operator("thumb.t8_final", icon='RENDER_RESULT')
        if _STATE["msg"]:
            box = self.layout.box()
            for line in (_STATE["msg"][i:i + 28] for i in range(0, len(_STATE["msg"]), 28)):
                box.label(text=line)


CLASSES = (THUMB_OT_t8_edit_pose, THUMB_OT_t8_save_pose, THUMB_OT_t8_load_pose, THUMB_OT_t8_preview, THUMB_OT_t8_final, THUMB_PT_t8)


def register():
    for c in CLASSES:
        bpy.utils.register_class(c)


def unregister():
    for c in reversed(CLASSES):
        bpy.utils.unregister_class(c)

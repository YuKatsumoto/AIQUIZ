"""サムネイル t8 のパネル（Blender のアドオン。3D ビューのサイドバー「Thumb」タブ）。

t8_thumbnail.blend の P1・P2 のポーズと場所を手で変えて、そのまま確認の絵・本番の絵まで作るためのボタン:
  対象（P1 / P2）  編集・保存・戻すボタンが働く人。P2 はゴーストライダー（乗り手 RIG_GhostRider とサメ GHOST_root）
  ポーズを編集      対象の骨を選んでポーズモードに（骨を選んで R で回す。Alt+R で元の姿に戻る）
  体ごと動かす      P1：ポーズモードで腰の骨（pelvis）だけを選ぶ（G で動かす・R で回す。全身が付いてくる）
                    P2：サメごと（GHOST_root）を選ぶ（G・R・S。乗り手もいっしょに）
  ポーズを保存      いまの骨の姿を docs/pv/thumbnail/t8/blender_art.json に書き、.blend も保存する
                    （P1 は bone_pose、P2 は ghost の乗り手の骨の姿 rider_pose とサメの位置 world）
  保存した姿に戻す  blender_art.json の保存した姿を当て直す
  確認の絵          1920×1080・24 サンプルで描き（画面は止まらない）、背景の絵とゲームの色で重ねて開く（blender/out/t8_prev_ui.png）
  本番を描く        1920×1080・384 サンプルで描き、背景・色・ロゴまで仕上げて開く（final/t8_blender.png・.jpg）
描画は render_layers.py の render_async（裏で描く。終わると .npy と done.txt）、合成はこの PC の Python で compose.py を動かす。
"""
bl_info = {
    "name": "AIQUIZ Thumbnail t8",
    "author": "AIQUIZ",
    "version": (1, 2, 3),
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
    r"""プロジェクト（project.godot のあるフォルダ）。開いている .blend から上へたどり、無ければ環境変数 AIQUIZ_ROOT、
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
    if ns is None or "save_pose" not in ns or "save_ghost" not in ns:
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
    # モーションブラーの動き（サメの突進・破片）は MOTION_FRAME（10）とその 1 フレーム前だけにキーがある。タイムラインがほかの
    # フレームにあると何も動かず、ぶれが消える（2026-11-01、93 フレーム目で描いて起きた）ので、描く前に必ず合わせる
    bpy.context.scene.frame_set(_ns().get("MOTION_FRAME", 10))
    info = rl["render_async"]("VL_t8", tag=tag, res=(1920, 1080), samples=samples)
    done, err = info["done"], info["done"].replace("_done.txt", "_error.txt")
    _STATE["busy"] = tag
    _status("描いています（%d サンプル）…" % samples)
    state = {"proc": None}

    def watch():
        if state["proc"] is None:
            if os.path.exists(err):
                _STATE["busy"] = ""
                _status("描画が止まりました：" + open(err, encoding="utf-8").read()[:240])
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


def _target(context):
    return getattr(context.scene, "thumb_t8_target", "P1")


def _target_arm(context):
    """P1 は ARM_P1、P2 はゴーストライダーの乗り手（RIG_GhostRider）"""
    if _target(context) == "P1":
        return bpy.data.objects.get("ARM_P1")
    return next((o for o in bpy.data.objects if o.type == 'ARMATURE' and o.name.startswith("RIG_GhostRider")), None)


def _enter_pose(context, arm):
    if context.object is not None and context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    for o in context.view_layer.objects:
        o.select_set(False)
    context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='POSE')


class THUMB_OT_t8_edit_pose(bpy.types.Operator):
    bl_idname = "thumb.t8_edit_pose"
    bl_label = "ポーズを編集"
    bl_description = "対象（P1 / P2）の骨を選んでポーズモードにする（骨を選んで R で回す。Alt+R で書き出しの姿に戻る）"

    def execute(self, context):
        arm = _target_arm(context)
        if arm is None:
            self.report({'ERROR'}, "%s の骨がない（t8_art.py の setup() で作る）" % _target(context))
            return {'CANCELLED'}
        _enter_pose(context, arm)
        _status("%s のポーズモード：骨をクリックして R（回す）。R X / R Y / R Z で軸を決められる" % _target(context))
        return {'FINISHED'}


class THUMB_OT_t8_move_body(bpy.types.Operator):
    bl_idname = "thumb.t8_move_body"
    bl_label = "体ごと動かす"
    bl_description = ("P1：腰の骨（pelvis）だけを選ぶ（G で動かす・R で回すと全身が付いてくる）。"
                      "P2：ゴーストライダーのサメごと（GHOST_root）を選ぶ（G・R・S で動かす・回す・大きさ）")

    def execute(self, context):
        if _target(context) == "P2":
            root = bpy.data.objects.get("GHOST_root")
            if root is None:
                self.report({'ERROR'}, "GHOST_root がない（t8_art.py の setup() で作る）")
                return {'CANCELLED'}
            if context.object is not None and context.object.mode != 'OBJECT':
                bpy.ops.object.mode_set(mode='OBJECT')
            for o in context.view_layer.objects:
                o.select_set(False)
            root.hide_select = False
            context.view_layer.objects.active = root
            root.select_set(True)
            _status("サメごと選びました：G で動かす、R で回す、S で大きさ（乗り手もいっしょに。乗り手の骨は「ポーズを編集」で）")
            return {'FINISHED'}
        arm = _target_arm(context)
        if arm is None:
            self.report({'ERROR'}, "ARM_P1 がない")
            return {'CANCELLED'}
        _enter_pose(context, arm)
        # 骨の選択はポーズの骨（PoseBone.select）で（Blender 5 で Bone.select・select_head・select_tail はなくなった）
        for pb in arm.pose.bones:
            pb.select = False
        arm.pose.bones["pelvis"].select = True
        arm.data.bones.active = arm.data.bones["pelvis"]
        _status("%s の腰を選びました：G で動かす（G X / G Y / G Z で軸）、R Z で向きを変える" % _target(context))
        return {'FINISHED'}


class THUMB_OT_t8_save_pose(bpy.types.Operator):
    bl_idname = "thumb.t8_save_pose"
    bl_label = "ポーズを保存"
    bl_description = "対象のいまの骨の姿（P2 は場所も）を blender_art.json に書き、.blend も保存する"

    def execute(self, context):
        ns = _ns()
        res = ns["save_pose"]() if _target(context) == "P1" else ns["save_ghost"]()
        if context.object is not None and context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        bpy.ops.wm.save_mainfile()
        _status("%s を保存しました（骨 %d 本）" % (_target(context), res["bones"]))
        return {'FINISHED'}


class THUMB_OT_t8_load_pose(bpy.types.Operator):
    bl_idname = "thumb.t8_load_pose"
    bl_label = "保存した姿に戻す"
    bl_description = "対象の、blender_art.json に保存した姿（P2 は場所も）を当て直す"

    def execute(self, context):
        ns = _ns()
        art = ns["_art"]()
        res = ns["apply_bone_pose"](art) if _target(context) == "P1" else ns["apply_ghost_pose"](art)
        _status("%s を戻しました（骨 %d 本）" % (_target(context), res["applied"]))
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
        self.layout.prop(context.scene, "thumb_t8_target", expand=True)
        col = self.layout.column(align=True)
        col.operator("thumb.t8_edit_pose", icon='ARMATURE_DATA')
        col.operator("thumb.t8_move_body", icon='ORIENTATION_GLOBAL')
        col.operator("thumb.t8_save_pose", icon='FILE_TICK')
        col.operator("thumb.t8_load_pose", icon='LOOP_BACK')
        col.separator()
        col.operator("thumb.t8_preview", icon='RENDER_STILL')
        col.operator("thumb.t8_final", icon='RENDER_RESULT')
        if _STATE["msg"]:
            box = self.layout.box()
            for line in (_STATE["msg"][i:i + 28] for i in range(0, len(_STATE["msg"]), 28)):
                box.label(text=line)


CLASSES = (THUMB_OT_t8_edit_pose, THUMB_OT_t8_move_body, THUMB_OT_t8_save_pose, THUMB_OT_t8_load_pose,
           THUMB_OT_t8_preview, THUMB_OT_t8_final, THUMB_PT_t8)


def register():
    bpy.types.Scene.thumb_t8_target = bpy.props.EnumProperty(
        name="対象", items=[("P1", "P1", "扉を突き破る P1（ARM_P1）"), ("P2", "P2", "ゴーストライダー（乗り手 RIG_GhostRider とサメ GHOST_root）")],
        default="P1")
    for c in CLASSES:
        bpy.utils.register_class(c)


def unregister():
    for c in reversed(CLASSES):
        bpy.utils.unregister_class(c)
    del bpy.types.Scene.thumb_t8_target
